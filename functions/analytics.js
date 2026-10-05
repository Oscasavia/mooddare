'use strict';
// First-party aggregates only. No content, email, advertising ID or feed history.
const {createHash}=require('node:crypto');
const {Timestamp,FieldValue}=require('firebase-admin/firestore');
const {HttpsError}=require('firebase-functions/v2/https');
const DAY=86400000;
const hash=s=>createHash('sha256').update(s).digest('hex');
const day=t=>new Date(t).toISOString().slice(0,10);
const localMoods={creative:'Creative',happy:'Happy',chill:'Chill',curious:'Curious',silly:'Silly',energized:'Energized','season-christmas':'Christmas','season-new-year':'New Year'};
async function catalog(db){
 const result=new Map(),names=new Set();
 const rows=await db.collection('dares').limit(101).get();
 if(rows.size>100)throw Error('Mood catalog exceeds supported size');
 const text=(v,fallback)=>typeof v==='string'&&v.trim()?v.trim():fallback;
 function add(id,name,available,seasonal=false){
  if(result.has(id)||names.has(name.toLowerCase()))return;
  result.set(id,{name,available,seasonal});names.add(name.toLowerCase());
 }
 for(const doc of rows.docs){
  const d=doc.data(),locked=d.isLocked!=null&&d.isLocked!==false;
  const pack=text(d.pack,'basic').toLowerCase();
  const premium=d.tier!=null?!['basic','free'].includes(text(d.tier,'').toLowerCase()):locked||['gold','daring','premium','diamond','epic'].includes(pack);
  const hasDares=Array.isArray(d.dareList)&&d.dareList.some(v=>typeof v==='string'&&v.trim());
  if(premium||locked||hasDares)add(doc.id,text(d.moodName,'Unnamed mood'),!premium&&!locked&&hasDares,!!text(d.season,''));
 }
 // Match app precedence, local fallback, and name/ID deduplication.
 if(![...result.values()].some(m=>m.available&&!m.seasonal))
  for(const [id,name]of Object.entries(localMoods))if(!id.startsWith('season-'))add(id,name,true);
 for(const id of ['season-christmas','season-new-year'])add(id,localMoods[id],true,true);
 return new Map([...result].filter(([,m])=>m.available).map(([id,m])=>[id,m.name.slice(0,300)]));
}
async function recordMood(db,request,now=Date.now()){
 const uid=request.auth?.uid,d=request.data;
 if(!uid||request.auth.token?.firebase?.sign_in_provider==='anonymous')throw new HttpsError('unauthenticated','Sign in to continue.');
 if(!d||Object.keys(d).some(k=>!['eventId','moodId'].includes(k))||typeof d.eventId!=='string'||! /^[a-zA-Z0-9-]{16,80}$/.test(d.eventId)||typeof d.moodId!=='string'||d.moodId.length>100)throw new HttpsError('invalid-argument','Invalid selection.');
 const moods=await catalog(db);if(!moods.has(d.moodId))throw new HttpsError('invalid-argument','Mood unavailable.');
 const config=await db.doc('analyticsConfig/current').get();if(!config.exists)return {recorded:false};
 const root=db.doc(`users/${uid}`),receipt=root.collection('analyticsReceipts').doc(hash(d.eventId)),rate=root.collection('analyticsState').doc('rate');
 return db.runTransaction(async tx=>{
  const [user,restriction,deletion,prior,limit]=await Promise.all([tx.get(root),tx.get(db.doc(`accountRestrictions/${uid}`)),tx.get(db.doc(`accountDeletions/${uid}`)),tx.get(receipt),tx.get(rate)]);
  const r=restriction.data();
  if(!user.exists||deletion.exists||r?.status==='banned'||r?.status==='deleting'||(r?.status==='suspended'&&r.until?.toMillis()>now))throw new HttpsError('permission-denied','Account unavailable.');
  if(prior.exists)return {recorded:false};
  const v=limit.data()||{},today=day(now);
  if(now-(v.lastAt?.toMillis()||0)<2000||(v.day===today&&v.count>=500))return {recorded:false};
  tx.set(rate,{lastAt:Timestamp.fromMillis(now),day:today,count:v.day===today?(v.count||0)+1:1,expiresAt:Timestamp.fromMillis(now+32*DAY)});
  tx.create(receipt,{expiresAt:Timestamp.fromMillis(now+32*DAY)});
  tx.set(db.doc(`analyticsDaily/${today}`),{moods:{[hash(d.moodId)]:{id:d.moodId,name:moods.get(d.moodId),selections:FieldValue.increment(1)}}},{merge:true});
  return {recorded:true};
 });
}
async function recordLifecycle(db,kind,eventId,at){
 if(!['signups','accountDeletions'].includes(kind))throw Error('Invalid lifecycle event');
 const time=Date.parse(at);if(!Number.isFinite(time))throw Error('Missing event time');
 const config=await db.doc('analyticsConfig/current').get();
 if(!config.exists||time<config.data().startedAt.toMillis())return;
 const ref=db.doc(`analyticsReceipts/${hash(kind+':'+eventId)}`);
 await db.runTransaction(async tx=>{if((await tx.get(ref)).exists)return;
  tx.create(ref,{expiresAt:Timestamp.fromMillis(time+90*DAY)});
  tx.set(db.doc(`analyticsDaily/${day(time)}`),{[kind]:FieldValue.increment(1)},{merge:true});
 });
}
async function bounded(query){const rows=await query.limit(20001).get();if(rows.size>20000){const e=Error('Analytics needs a larger aggregation job before this period can be displayed.');e.status=503;throw e;}return rows.docs;}
async function snapshot(db,rangeDays,now=Date.now()){
 rangeDays=Number(rangeDays);if(![7,30].includes(rangeDays)){const e=Error('Choose 7 or 30 days.');e.status=400;throw e;}
 const config=await db.doc('analyticsConfig/current').get();if(!config.exists)return {status:'not-connected'};
 const end=Date.parse(day(now))+DAY,start=end-rangeDays*DAY;
 const [moodCatalog,daily,posts,users,weeks]=await Promise.all([
  catalog(db),db.collection('analyticsDaily').where('__name__','>=',day(start)).where('__name__','<',day(end)).get(),
  bounded(db.collection('posts').where('createdAt','>=',Timestamp.fromMillis(start)).where('createdAt','<',Timestamp.fromMillis(end)).select('authorId','weeklyDareId','mediaType','likedBy','deleting')),
  db.collection('users').count().get(),
  bounded(db.collection('weeklyDares').where('endsAt','>',Timestamp.fromMillis(start)).select('title','startsAt','endsAt'))
 ]);
 const metrics={moodSelections:0,communityParticipants:0,communityMoments:0,signups:0,accountDeletions:0,currentProfiles:users.data().count,posts:0,creators:0,likes:0};
 const moods=new Map([...moodCatalog].map(([id,name])=>[id,{id,name,selections:0}]));
 for(const doc of daily.docs){const d=doc.data();metrics.signups+=d.signups||0;metrics.accountDeletions+=d.accountDeletions||0;
  for(const m of Object.values(d.moods||{})){if(!moods.has(m.id))moods.set(m.id,{id:m.id,name:m.name,selections:0});moods.get(m.id).selections+=m.selections;metrics.moodSelections+=m.selections;}}
 const dares=new Map();for(const doc of weeks){const d=doc.data();if(d.startsAt?.toMillis()<end)dares.set(doc.id,{id:doc.id,title:String(d.title||doc.id).slice(0,300),people:new Set(),moments:0});}
 const creators=new Set(),participants=new Set();
 for(const doc of posts){const p=doc.data();if(p.deleting||typeof p.authorId!=='string')continue;
  metrics.posts++;creators.add(p.authorId);metrics.likes+=new Set(p.likedBy||[]).size;
  if(typeof p.weeklyDareId==='string'&&p.weeklyDareId){let d=dares.get(p.weeklyDareId);
   if(!d){d={id:p.weeklyDareId,title:`Community dare ${p.weeklyDareId}`,people:new Set(),moments:0};dares.set(d.id,d);}
   d.moments++;d.people.add(p.authorId);participants.add(p.authorId);metrics.communityMoments++;
  }
 }
 metrics.creators=creators.size;metrics.communityParticipants=participants.size;
 if(moods.size>500||dares.size>500)throw Error('Analytics catalog exceeds supported size');
 return {status:'ready',schemaVersion:2,rangeDays,generatedAt:new Date(now).toISOString(),startDate:new Date(start).toISOString(),endDate:new Date(end).toISOString(),trackingStartedAt:config.data().startedAt.toDate().toISOString(),metrics,moods:[...moods.values()],communityDares:[...dares.values()].sort((a,b)=>b.id.localeCompare(a.id)).map(({people,...d})=>({...d,participants:people.size}))};
}
module.exports={recordMood,recordLifecycle,snapshot,catalog};
