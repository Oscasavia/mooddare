'use strict';
const {test,beforeEach,after}=require('node:test');
const assert=require('node:assert/strict');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore,Timestamp}=require('firebase-admin/firestore');
const a=require('../analytics');
const app=process.env.FIRESTORE_EMULATOR_HOST?initializeApp({projectId:'demo-mooddare-analytics'},'analytics-tests'):null;
const db=app?getFirestore(app):null;
const run=(name,fn)=>test(name,{skip:!db},fn);
const now=Date.parse('2026-10-05T12:00:00Z'),ts=t=>Timestamp.fromMillis(t);
const req=(id='selection-00000001',moodId='happy')=>({auth:{uid:'alice',token:{firebase:{sign_in_provider:'password'}}},data:{eventId:id,moodId}});
beforeEach(async()=>{if(!db)return;for(const c of ['analyticsConfig','analyticsDaily','analyticsReceipts','users','posts','weeklyDares','dares','accountDeletions','accountRestrictions'])await db.recursiveDelete(db.collection(c));await db.doc('analyticsConfig/current').set({startedAt:ts(now-86400000)});await db.doc('users/alice').set({});});
after(async()=>{if(app)await deleteApp(app);});
run('concurrent duplicates count once; rate limit and invalid payload cannot inflate moods',async()=>{
 await Promise.all([a.recordMood(db,req(),now),a.recordMood(db,req(),now)]);
 assert.equal((await a.snapshot(db,7,now)).metrics.moodSelections,1);
 await a.recordMood(db,req('selection-00000002'),now+1000);
 assert.equal((await a.snapshot(db,7,now)).metrics.moodSelections,1);
 await a.recordMood(db,req('selection-00000003','chill'),now+3000);
 const s=await a.snapshot(db,7,now+3000);assert.equal(s.metrics.moodSelections,2);assert.equal(s.moods.find(m=>m.id==='creative').selections,0);
 await assert.rejects(a.recordMood(db,{...req(),auth:null},now));await assert.rejects(a.recordMood(db,req('selection-00000004','unknown'),now));
 await assert.rejects(a.recordMood(db,{...req(),data:{...req().data,uid:'someone'}},now));
 await db.doc('accountDeletions/alice').set({status:'pending'});await assert.rejects(a.recordMood(db,req('selection-00000005'),now+5000));
});
run('lifecycle events are deduplicated and pre-collection events are ignored',async()=>{
 await Promise.all([a.recordLifecycle(db,'signups','one',new Date(now).toISOString()),a.recordLifecycle(db,'signups','one',new Date(now).toISOString())]);
 await a.recordLifecycle(db,'signups','old','2026-09-01T12:00:00Z');
 await a.recordLifecycle(db,'accountDeletions','two',new Date(now).toISOString());
 const s=await a.snapshot(db,7,now);assert.equal(s.schemaVersion,2);assert.equal(s.metrics.signups,1);assert.equal(s.metrics.accountDeletions,1);assert.equal(s.trackingStartedAt,new Date(now-86400000).toISOString());
});
run('existing content counts distinct creators and participants, zero dares, likes and removals accurately',async()=>{
 for(const id of ['week1','week2','week3'])await db.doc('weeklyDares/'+id).set({title:id,startsAt:ts(now-86400000),endsAt:ts(now+86400000)});
 for(const [id,author,week]of [['p1','alice','week1'],['p2','alice','week2'],['p3','bob','week1']])await db.doc('posts/'+id).set({authorId:author,weeklyDareId:week,createdAt:ts(now-1000),likedBy:['a','b']});
 await db.doc('posts/old').set({authorId:'c',createdAt:ts(now-40*86400000)});
 let s=await a.snapshot(db,7,now);assert.equal(s.metrics.posts,3);assert.equal(s.metrics.creators,2);assert.equal(s.metrics.communityParticipants,2);assert.equal(s.metrics.likes,6);assert.equal(s.communityDares.find(d=>d.id==='week3').moments,0);
 await db.doc('posts/p3').delete();s=await a.snapshot(db,7,now);assert.equal(s.metrics.communityParticipants,1);assert.equal(s.metrics.communityMoments,2);
 assert.equal(JSON.stringify(s).includes('alice'),false);
 await assert.rejects(a.snapshot(db,99,now));
});
run('account-linked receipts contain no mood and disappear on account deletion; anonymous aggregates remain',async()=>{
 await a.recordMood(db,req(),now);
 const receipts=await db.collection('users/alice/analyticsReceipts').get();assert.deepEqual(Object.keys(receipts.docs[0].data()),['expiresAt']);
 assert.equal(receipts.docs[0].data().expiresAt.toMillis(),now+32*86400000);
 await db.recursiveDelete(db.doc('users/alice'));assert.equal((await a.snapshot(db,7,now)).metrics.moodSelections,1);
 await assert.rejects(a.recordMood(db,req('selection-00000002'),now+3000));
});
run('unconfigured tracking remains disconnected; remote catalog does not include paid previews',async()=>{
 await db.doc('dares/paid').set({moodName:'Paid',pack:'epic',dareList:['x']});assert.equal((await a.catalog(db)).has('paid'),false);
 await db.doc('dares/real').set({moodName:'Real',pack:'basic',dareList:['x']});const c=await a.catalog(db);assert.equal(c.has('real'),true);assert.equal(c.has('happy'),false);
 await db.doc('analyticsConfig/current').delete();assert.deepEqual(await a.snapshot(db,7,now),{status:'not-connected'});
});
run('analytics HTTP route requires enabled staff and never returns member IDs',async()=>{
 const {handler}=require('../moderation_http');
 const auth={verifyIdToken:async()=>({uid:'staff',email_verified:true,firebase:{sign_in_provider:'google.com'}})};
 const api=handler(db,auth,{});
 async function call(token){const response={code:200,set(){},status(c){this.code=c;return this;},json(body){this.body=body;return this;},end(){}};await api({method:'GET',path:'/admin-api/analytics',query:{days:'7'},get:()=>token},response);return response;}
 assert.equal((await call(null)).code,401);
 assert.equal((await call('Bearer test')).code,403);
 await db.doc('moderationStaff/staff').set({enabled:true});
 const response=await call('Bearer test');assert.equal(response.code,200);assert.equal(response.body.status,'ready');assert.equal(JSON.stringify(response.body).includes('alice'),false);
 await db.doc('moderationStaff/staff').delete();
});
run('daily cap, anonymous identity and suspension reject further tracking',async()=>{
 await db.doc('users/alice/analyticsState/rate').set({day:'2026-10-05',count:500,lastAt:ts(now-3000)});
 assert.deepEqual(await a.recordMood(db,req(),now),{recorded:false});
 const r=req();r.auth.token.firebase.sign_in_provider='anonymous';await assert.rejects(a.recordMood(db,r,now));
 await db.doc('accountRestrictions/alice').set({status:'suspended',until:ts(now+10000)});await assert.rejects(a.recordMood(db,req(),now));
});
run('catalog matches app fallback, locked-name precedence, and seasonal deduplication',async()=>{
 await db.doc('dares/locked-creative').set({moodName:'Creative',isLocked:true,dareList:['x']});
 await db.doc('dares/holiday').set({moodName:'Christmas',season:'Christmas',dareList:['x']});
 let c=await a.catalog(db);assert.equal(c.has('creative'),false);assert.equal(c.has('happy'),true);assert.equal(c.has('season-christmas'),false);assert.equal(c.has('holiday'),true);
 await db.doc('dares/custom').set({moodName:'Custom',pack:'legacy-custom',dareList:['x']});
 c=await a.catalog(db);assert.equal(c.has('custom'),true);assert.equal(c.has('happy'),false);
});
