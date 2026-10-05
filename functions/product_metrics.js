'use strict';
const {createHash,randomUUID}=require('node:crypto');
const {Timestamp,FieldValue}=require('firebase-admin/firestore');
const {HttpsError}=require('firebase-functions/v2/https');
const DAY=86400000,hash=v=>createHash('sha256').update(v).digest('hex'),date=t=>new Date(t).toISOString().slice(0,10);
const APP=new Set(['app_active','signup_started','signup_completed','login_started','login_completed','auth_failed','profile_completed','mood_selected','dare_viewed','dare_shuffled','capture_started','upload_started','upload_succeeded','upload_failed','share_opened','share_completed','share_unconfirmed','app_error','community_opened','community_started']);
const PUBLIC=new Set(['signup_started','login_started','auth_failed']);
const WEB=new Set(['page_view','navigation_click','download_click','contact_click','mood_demo','screenshot_open','faq_open','video_start','video_25','video_50','video_75','video_complete','video_error']);
const PAGES=new Set(['/','/index.html','/privacy.html','/terms.html','/delete-data.html','/moment/']);
const label=v=>typeof v==='string'&&/^[a-zA-Z0-9_.:-]{1,80}$/.test(v);
const increment=()=>FieldValue.increment(1);
async function config(db){const d=(await db.doc('analyticsConfig/current').get()).data();return d?.productStartedAt?d:null;}
async function environment(db,uid,requested){
 if(!uid)return requested;
 const [staff,excluded]=await Promise.all([db.doc(`moderationStaff/${uid}`).get(),db.doc(`analyticsExclusions/${uid}`).get()]);
 return staff.data()?.enabled||excluded.data()?.enabled?'development':requested;
}
async function publicLimit(db,ip,cfg,now){
 const slot=Math.floor(now/900000),ref=db.doc(`analyticsTraffic/${hash(cfg.trafficSalt+':'+slot+':'+(ip||'unknown'))}`);
 return db.runTransaction(async tx=>{const n=(await tx.get(ref)).data()?.count||0;if(n>=600)throw new HttpsError('resource-exhausted','Try later.');tx.set(ref,{count:n+1,expiresAt:Timestamp.fromMillis(now+2*DAY)});});
}
function validate(e,now){
 return e&&typeof e==='object'&&Object.keys(e).every(k=>['id','name','at','moodId','postId','weekId','durationMs','error','page','target','videoId'].includes(k))&&label(e.id)&&e.id.length>=16&&label(e.name)&&Number.isSafeInteger(e.at)&&e.at>=now-7*DAY&&e.at<=now+300000&&
 ['moodId','postId','weekId','error','target','videoId'].every(k=>e[k]===undefined||label(e[k]))&&(e.durationMs===undefined||(Number.isSafeInteger(e.durationMs)&&e.durationMs>=0&&e.durationMs<=3600000));
}
async function recordMember(db,uid,env,version,platform,e,cfg,now){
 const root=db.doc(`users/${uid}`),receipt=root.collection('analyticsReceipts').doc(hash('v3:'+e.id)),stateRef=root.collection('productMetrics').doc(env);
 const observed=date(now),eventDay=date(Math.max(e.at,cfg.productStartedAt.toMillis())),daily=db.doc(`productDaily/${env}_${eventDay}`);
 const presenceId=randomUUID();
 return db.runTransaction(async tx=>{
  const refs=[root,receipt,stateRef,db.doc(`accountRestrictions/${uid}`),db.doc(`accountDeletions/${uid}`)];
  const [profile,seen,state,restriction,deletion]=await Promise.all(refs.map(r=>tx.get(r)));
  if(seen.exists)return;
  const r=restriction.data();if(!profile.exists||deletion.exists||r?.status==='banned'||r?.status==='deleting'||(r?.status==='suspended'&&r.until?.toMillis()>now))throw new HttpsError('permission-denied','Account unavailable.');
  let post;
  if(e.name.startsWith('share_')){
   if(!e.postId)throw new HttpsError('invalid-argument','Missing post.');
   post=await tx.get(db.doc(`posts/${e.postId}`));
   if(!post.exists||post.data().deleting)return;
   const author=post.data().authorId;
   const blocked=await Promise.all([tx.get(db.doc(`users/${uid}/blocked/${author}`)),tx.get(db.doc(`users/${author}/blocked/${uid}`))]);
   if(blocked.some(d=>d.exists))throw new HttpsError('permission-denied','Post unavailable.');
  }
  const old=state.data()||{},days=(old.days||[]).filter(d=>d>=date(now-35*DAY)),freshDay=!days.includes(eventDay),first=!state.exists;
  if(old.rateDay===observed&&old.rateCount>=2000)throw new HttpsError('resource-exhausted','Try later.');
  const firstDay=old.firstDay||observed,offset=Math.floor((Date.parse(eventDay)-Date.parse(firstDay))/DAY);
  const milestones={...(old.milestones||{})},stages={...(old.stages||{})};
  const total={events:{[e.name]:increment()}};
  if(['signup_completed','profile_completed','mood_selected','capture_started','upload_succeeded'].includes(e.name)&&!stages[e.name]){stages[e.name]=true;total.firstSteps={[e.name]:increment()};}
  if(e.name==='mood_selected'&&e.moodId)total.moods={[hash(e.moodId)]:{id:e.moodId,count:increment()}};
  if(e.weekId)total.community={[e.name]:increment()};
  if(e.name.endsWith('failed')||e.name==='app_error')total.errors={[hash(`${e.name}:${platform}:${version}:${e.error||'unknown'}`)]:{name:e.name,platform,version,code:e.error||'unknown',count:increment()}};
  if(e.durationMs!==undefined)total.timings={[e.name]:{count:increment(),totalMs:FieldValue.increment(e.durationMs),slow:FieldValue.increment(e.durationMs>=10000?1:0)}};
  const cohort={};if(first)cohort.size=increment();
  if([1,7,30].includes(offset)&&!milestones['d'+offset]){milestones['d'+offset]=true;cohort['d'+offset]=increment();}
  if(Object.keys(cohort).length)tx.set(db.doc(`productCohorts/${env}_${firstDay}`),cohort,{merge:true});
  if(freshDay){days.push(eventDay);total.activeUsers=increment();}
  tx.set(stateRef,{firstDay,days,milestones,stages,presenceId:old.presenceId||presenceId,rateDay:observed,rateCount:old.rateDay===observed?(old.rateCount||0)+1:1});
  // Random presence keys carry only activity dates, never an account identifier.
  // Deletion removes the account-to-key mapping; these expire independently.
  tx.set(db.doc(`analyticsPresence/${old.presenceId||presenceId}`),{environment:env,days,expiresAt:Timestamp.fromMillis(now+35*DAY)});
  tx.create(receipt,{expiresAt:Timestamp.fromMillis(now+32*DAY)});
  if(e.name==='share_completed')tx.update(post.ref,{shareCount:FieldValue.increment(1)});
  tx.set(daily,total,{merge:true});
 });
}
async function recordPublic(db,env,e,cfg,now,session,source='website'){
 const ref=db.doc(`analyticsVisits/${hash(source+':'+env+':'+session)}`),daily=db.doc(`${source==='website'?'websiteDaily':'productDaily'}/${env}_${date(e.at)}`);
 await db.runTransaction(async tx=>{
  const sessionDoc=await tx.get(ref),s=sessionDoc.data()||{},seen=s.seen||[];
  if(seen.includes(e.id))return;
  if(seen.length>=500)throw new HttpsError('resource-exhausted','Session limit reached.');
  const milestones=s.milestones||{},key=e.videoId+':'+e.name;
  const patch={events:{[e.name]:increment()}};
  if(source==='website'){
   if(!sessionDoc.exists)patch.sessions=increment();
   if(e.name==='page_view')patch.pages={[hash(e.page)]:{page:e.page,count:increment()}};
   if(e.target)patch.clicks={[hash(e.name+':'+e.target)]:{name:e.name,target:e.target,count:increment()}};
   if(e.videoId){
    // One milestone per video version per tab session, across reloads and replays.
    if(!milestones[key]){patch.videos={[e.videoId]:{[e.name]:increment()}};milestones[key]=true;}
   }
  }
  tx.set(ref,{seen:[...seen,e.id],milestones,expiresAt:Timestamp.fromMillis(now+(source==='app'?9:2)*DAY)});
  tx.set(daily,patch,{merge:true});
 });
}
async function appEvents(db,request,now=Date.now()){
 const cfg=await config(db);if(!cfg)return {acked:[]};
 const d=request.data;
 if(!d||!['production','development'].includes(d.environment)||!label(d.version)||!['android','ios','other'].includes(d.platform)||!label(d.session)||!Array.isArray(d.events)||d.events.length>20)throw new HttpsError('invalid-argument','Invalid events.');
 const uid=request.auth?.token?.firebase?.sign_in_provider==='anonymous'?null:request.auth?.uid;
 if(d.anonymous!==true&&d.expectedUid!==uid)throw new HttpsError('permission-denied','Account changed.');
 const env=await environment(db,uid,d.environment),acked=[];
 if(!uid||d.anonymous===true)await publicLimit(db,request.rawRequest?.ip,cfg,now);
 for(const e of d.events){
  if(!validate(e,now)||!APP.has(e.name)||e.at<cfg.productStartedAt.toMillis()){if(typeof e?.id==='string')acked.push(e.id);continue;}
  if(!uid||d.anonymous===true){if(PUBLIC.has(e.name))await recordPublic(db,env,e,cfg,now,d.session,'app');}
  else{
   if(e.name==='mood_selected'&&!(await require('./analytics').catalog(db)).has(e.moodId)){acked.push(e.id);continue;}
   try {await recordMember(db,uid,env,d.version,d.platform,e,cfg,now);} catch(error){if(error.code!=='permission-denied')throw error;} // Permanent account/post restrictions must not jam later events.
  }
  acked.push(e.id);
 }
 return {acked};
}
async function serverEvent(db,{id,name,uid,at,env='production',amount=1,postId},now=Date.now()){
 const cfg=await config(db);if(!cfg||at<cfg.productStartedAt.toMillis())return;
 env=await environment(db,uid,env);
 const receipt=db.doc(`${postId?'analyticsPublications':'analyticsReceipts'}/${hash(postId||id+':'+name)}`);
 await db.runTransaction(async tx=>{if((await tx.get(receipt)).exists)return;
  tx.create(receipt,postId?{recordedAt:Timestamp.fromMillis(now)}:{expiresAt:Timestamp.fromMillis(now+90*DAY)});
  tx.set(db.doc(`productDaily/${env}_${date(at)}`),{events:{[name]:FieldValue.increment(amount)}},{merge:true});
 });
}
async function postWritten(db,event){
 const before=event.data?.before,after=event.data?.after;if(!after?.exists)return;
 const p=after.data();
 if(!before?.exists){await serverEvent(db,{id:event.id,name:'moment_published',uid:p.authorId,at:p.createdAt?.toMillis()||Date.parse(event.time),env:p.analyticsEnvironment||'production',postId:after.id});return;}
 const added=(p.likedBy||[]).filter(uid=>!(before.data().likedBy||[]).includes(uid));
 for(const uid of added)await serverEvent(db,{id:event.id+':'+uid,name:'like_added',uid,at:Date.parse(event.time),env:p.analyticsEnvironment||'production'});
}
async function webEvents(db,req,res){
 res.set('Cache-Control','no-store');
 if(req.method!=='POST')return res.status(405).end();
 if(!['https://mooddare.web.app','https://mooddare.firebaseapp.com'].includes(req.get('origin')))return res.status(403).end();
 try{
  const cfg=await config(db);if(!cfg)return res.status(503).end();
  const d=req.body,now=Date.now();
  if(!d||!label(d.session)||!Array.isArray(d.events)||d.events.length>20||JSON.stringify(d).length>16000)return res.status(400).end();
  await publicLimit(db,req.ip,cfg,now);
  for(const e of d.events){
   if(!validate(e,now)||e.at<now-DAY||!WEB.has(e.name)||!PAGES.has(e.page))continue;
   if(e.videoId&&!(cfg.webVideoIds||[]).includes(e.videoId))continue;
   if(e.name.startsWith('video_')&&!e.videoId)continue;
   if(e.target&&!['how-it-works','inside','film','downloads','home','privacy','terms','delete-data','android','ios','support','creative','chill','curious','happy','discover','dare','moments','faq'].includes(e.target))continue;
   await recordPublic(db,'production',e,cfg,now,d.session);
  }
  res.status(204).end();
 }catch(e){res.status(e.code==='resource-exhausted'?429:503).end();}
}
async function report(db,rangeDays,env='production',now=Date.now()){
 if(!['production','development'].includes(env)){const e=Error('Invalid analytics environment.');e.status=400;throw e;}
 const cfg=await config(db);if(!cfg)return null;
 const end=Date.parse(date(now))+DAY,start=end-rangeDays*DAY;
 const read=async (c,from=start)=>(await db.collection(c).where('__name__','>=',env+'_'+date(from)).where('__name__','<',env+'_'+date(end)).get()).docs;
 const [app,web,cohorts,presences]=await Promise.all([read('productDaily'),read('websiteDaily'),read('productCohorts',start-31*DAY),db.collection('analyticsPresence').where('environment','==',env).limit(20001).get()]);
 if(presences.size>20000)throw Error('Activity aggregation capacity exceeded');
 const total={events:{},firstSteps:{},moods:{},errors:{},timings:{},community:{}},site={events:{},pages:{},clicks:{},videos:{},sessions:0};
 function merge(target,source){for(const [k,v]of Object.entries(source)){if(typeof v==='number')target[k]=(target[k]||0)+v;else if(v&&typeof v==='object')merge(target[k]||=( {}),v);else target[k]=v;}}
 for(const row of app)merge(total,row.data());for(const row of web)merge(site,row.data());
 const active={daily:0,weekly:0,monthly:0};for(const p of presences.docs){const days=p.data().days||[];for(const [key,n]of [['daily',1],['weekly',7],['monthly',30]])if(days.some(d=>d>=date(end-n*DAY)&&d<date(end)))active[key]++;}
 const retention=[1,7,30].map(n=>{let eligible=0,returned=0;for(const c of cohorts){const age=Math.floor((Date.parse(date(now))-Date.parse(c.id.slice(env.length+1)))/DAY);if(age>n&&age<=n+rangeDays){eligible+=c.data().size||0;returned+=c.data()['d'+n]||0;}}return {day:n,eligible,returned};});
 return {startedAt:cfg.productStartedAt.toDate().toISOString(),environment:env,active,retention,app:total,website:site,trend:app.map(d=>({day:d.id.slice(env.length+1),active:d.data().activeUsers||0,posts:d.data().events?.moment_published||0}))};
}
module.exports={environment,appEvents,webEvents,serverEvent,postWritten,report,validate,recordMember,recordPublic};
