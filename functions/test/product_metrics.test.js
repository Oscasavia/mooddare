'use strict';
const {test,beforeEach,after}=require('node:test'),assert=require('node:assert/strict');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore,Timestamp}=require('firebase-admin/firestore');
const m=require('../product_metrics');
const app=process.env.FIRESTORE_EMULATOR_HOST?initializeApp({projectId:'demo-mooddare-product'},'product-tests'):null,db=app?getFirestore(app):null;
const run=(name,fn)=>test(name,{skip:!db},fn),DAY=86400000,now=Date.parse('2026-10-05T12:00:00Z'),ts=Timestamp.fromMillis;
const event=(name='app_active',extra={})=>({id:require('node:crypto').randomUUID(),name,at:now,...extra});
const req=e=>({auth:{uid:'alice',token:{firebase:{sign_in_provider:'password'}}},data:{environment:'production',platform:'android',version:'1.0_3',session:'session-0000000001',expectedUid:'alice',events:[e]}});
beforeEach(async()=>{if(!db)return;for(const c of ['analyticsConfig','productDaily','productCohorts','analyticsPresence','analyticsVisits','analyticsTraffic','websiteDaily','analyticsPublications','analyticsReceipts','moderationStaff','analyticsExclusions','users','posts','accountRestrictions','accountDeletions'])await db.recursiveDelete(db.collection(c));await db.doc('analyticsConfig/current').set({productStartedAt:ts(now-90*DAY),trafficSalt:'test',webVideoIds:['launch-2026-10']});await db.doc('users/alice').set({});});
after(async()=>{if(app)await deleteApp(app);});
run('concurrent share retries increment post counter and analytics exactly once',async()=>{
 await db.doc('posts/post').set({authorId:'bob'});const e=event('share_completed',{postId:'post'});
 await Promise.all([m.appEvents(db,req(e),now),m.appEvents(db,req(e),now)]);
 assert.equal((await db.doc('posts/post').get()).data().shareCount,1);
 const r=await m.report(db,7,'production',now);assert.equal(r.app.events.share_completed,1);assert.equal(r.active.daily,1);
 await m.appEvents(db,req(event('share_opened',{postId:'post'})),now);
 assert.equal((await db.doc('posts/post').get()).data().shareCount,1);
});
run('account switch, blocked posts, deleted and banned accounts reject shares',async()=>{
 const r=req(event());r.data.expectedUid='bob';await assert.rejects(m.appEvents(db,r,now),/Account changed/);
 await db.doc('posts/post').set({authorId:'bob'});await db.doc('users/bob/blocked/alice').set({});
 await m.appEvents(db,req(event('share_completed',{postId:'post'})),now);assert.equal((await db.doc('posts/post').get()).data().shareCount,undefined);
 await db.doc('accountRestrictions/alice').set({status:'banned'});await m.appEvents(db,req(event()),now);assert.equal((await m.report(db,7,'production',now)).active.daily,0);
 await db.doc('accountRestrictions/alice').delete();await db.doc('accountDeletions/alice').set({});await m.appEvents(db,req(event()),now);assert.equal((await m.report(db,7,'production',now)).active.daily,0);
});
run('staff and development activity stay out of production; first steps deduplicate',async()=>{
 await db.doc('moderationStaff/alice').set({enabled:true});
 await m.appEvents(db,req(event('signup_completed')),now);await m.appEvents(db,req(event('signup_completed')),now);
 assert.equal((await m.report(db,30,'production',now)).active.daily,0);
 const r=await m.report(db,30,'development',now);assert.equal(r.app.firstSteps.signup_completed,1);assert.equal(r.app.events.signup_completed,2);
});
run('unique actives survive account erasure without exposing account IDs',async()=>{
 await m.appEvents(db,req(event()),now);await m.appEvents(db,req(event()),now+1000);
 await db.recursiveDelete(db.doc('users/alice'));
 const r=await m.report(db,7,'production',now);assert.equal(r.active.monthly,1);assert.equal(r.active.daily,1);assert.equal(JSON.stringify(r).includes('alice'),false);
 const p=await db.collection('analyticsPresence').get();assert.deepEqual(Object.keys(p.docs[0].data()).sort(),['days','environment','expiresAt']);
});
run('retention counts fully observed D1/D7/D30 cohorts and excludes immature days',async()=>{
 await db.doc('productCohorts/production_2026-09-04').set({size:10,d30:3});
 await db.doc('productCohorts/production_2026-10-04').set({size:20,d1:4});
 await db.doc('productCohorts/production_2026-10-03').set({size:5,d1:2});
 const r=await m.report(db,7,'production',now);
 assert.deepEqual(r.retention.find(x=>x.day===30),{day:30,eligible:10,returned:3});
 assert.deepEqual(r.retention.find(x=>x.day===1),{day:1,eligible:5,returned:2});
});
run('server publications remain counted after deletion and restore; retries stay idempotent',async()=>{
 const input={id:'one',name:'moment_published',uid:'alice',at:now,postId:'post'};
 await m.serverEvent(db,input,now);await m.serverEvent(db,{...input,id:'restore'},now+100*DAY);
 assert.equal((await m.report(db,7,'production',now)).app.events.moment_published,1);
});
run('public sessions deduplicate retry IDs and video milestones independently per version',async()=>{
 const cfg=(await db.doc('analyticsConfig/current').get()).data();const e=event('video_start',{page:'/',videoId:'launch'});
 await m.recordPublic(db,'production',e,cfg,now,'session');await m.recordPublic(db,'production',e,cfg,now,'session');
 await m.recordPublic(db,'production',event('video_start',{page:'/',videoId:'launch'}),cfg,now,'session');
 await m.recordPublic(db,'production',event('video_start',{page:'/',videoId:'next'}),cfg,now,'session');
 const w=(await m.report(db,7,'production',now)).website;assert.equal(w.sessions,1);assert.equal(w.videos.launch.video_start,1);assert.equal(w.videos.next.video_start,1);
});
run('website endpoint rejects foreign origins and never aggregates raw URLs or unregistered videos',async()=>{
 const response=()=>({code:200,set(){},status(n){this.code=n;return this;},end(){}});
 let res=response();await m.webEvents(db,{method:'POST',get:()=> 'https://evil.example'},res);assert.equal(res.code,403);
 const at=Date.now(),base={method:'POST',get:()=> 'https://mooddare.web.app',ip:'127.0.0.1'};
 res=response();await m.webEvents(db,{...base,body:{session:'test-session',events:[event('page_view',{at,page:'/private?email=x'}),event('video_start',{at,page:'/',videoId:'not-registered'}),event('page_view',{at,page:'/'})]}},res);assert.equal(res.code,204);
 const w=(await m.report(db,7,'production',at)).website;assert.equal(w.events.page_view,1);assert.equal(w.events.video_start,undefined);assert.equal(JSON.stringify(w).includes('email'),false);
});
run('invalid events and pre-collection events are acknowledged without counting',async()=>{
 const e=event('app_active',{at:now-8*DAY});assert.deepEqual(await m.appEvents(db,req(e),now),{acked:[e.id]});
 assert.equal((await m.report(db,7,'production',now)).active.daily,0);
});
run('anonymous app retries retain receipts beyond queue lifetime and use original event date',async()=>{
 const cfg=(await db.doc('analyticsConfig/current').get()).data(),e=event('signup_started',{at:now-DAY});
 await m.recordPublic(db,'production',e,cfg,now,'offline-session','app');
 const visits=await db.collection('analyticsVisits').get();assert.equal(visits.docs[0].data().expiresAt.toMillis(),now+9*DAY);
 assert.equal((await db.doc('productDaily/production_2026-10-04').get()).data().events.signup_started,1);
 await m.recordPublic(db,'production',e,cfg,now+3*DAY,'offline-session','app');
 assert.equal((await db.doc('productDaily/production_2026-10-04').get()).data().events.signup_started,1);
});
