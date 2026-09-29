const {test,beforeEach,after} = require('node:test');
const assert=require('node:assert/strict');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore,Timestamp}=require('firebase-admin/firestore');
const {weekId,activeWeek,announceWeek}=require('../weekly');
const {sendPush}=require('../push');
const monday=Date.parse('2026-10-05T00:00:00Z');
const value=(start=monday)=>({title:'A little joy',dareText:'Share a happy moment.',moodId:'happy',moodName:'Happy',startsAt:Timestamp.fromMillis(start),endsAt:Timestamp.fromMillis(start+7*86400000)});
test('weekly boundaries match Monday UTC across timezones and year changes',()=>{
  assert.equal(weekId(Date.parse('2026-10-04T23:59:59Z')),'2026-09-28');
  assert.equal(weekId(monday),'2026-10-05');
  assert.equal(weekId(Date.parse('2026-10-04T19:00:00-05:00')),'2026-10-05');
  assert.equal(weekId(Date.parse('2027-01-01T00:00:00Z')),'2026-12-28');
  assert.equal(activeWeek('2026-10-05',value(),monday-1),false);
  assert.equal(activeWeek('2026-10-05',value(),monday),true);
  assert.equal(activeWeek('2026-10-05',value(),monday+7*86400000),false);
  assert.equal(activeWeek('2026-10-05',{...value(),dareText:''},monday),false);
  assert.equal(activeWeek('2026-10-05',{...value(),endsAt:Timestamp.fromMillis(monday+5)},monday),false);
});
const enabled=!!process.env.FIRESTORE_EMULATOR_HOST;
const app=enabled?initializeApp({projectId:'demo-mooddare-weekly'},'weekly-tests'):null;
const db=app?getFirestore(app):null;
beforeEach(async()=>{
  if(!db)return;
  for(const collection of ['users','weeklyDares','notificationCampaigns','pushTokens']) await db.recursiveDelete(db.collection(collection));
  await db.doc('weeklyDares/2026-10-05').set(value());
  for(const id of ['a','b','c','d','e'])await db.doc(`users/${id}`).set({createdAt:Timestamp.fromMillis(monday-1)});
});
after(async()=>{if(app)await deleteApp(app);});
const count=async()=> (await db.collectionGroup('notifications').get()).size;
test('no alerts before Monday, future publication, missing schedule, or midweek deploy',{skip:!enabled},async()=>{
  for(const now of [monday-1,monday+86400000,monday-7*86400000]) assert.equal(await announceWeek(db,{now:()=>now}),0);
  assert.equal(await count(),0);
  assert.equal((await db.collection('notificationCampaigns').get()).size,0);
});
test('bounded pages resume after interruption and concurrent retries never duplicate or reset read state',{skip:!enabled},async()=>{
  const options={now:()=>monday,pageSize:2,maxPages:1};
  await Promise.all([announceWeek(db,options),announceWeek(db,options)]);
  const first=await db.collectionGroup('notifications').get();
  assert.ok(first.size>=2 && first.size<=4);
  await first.docs[0].ref.update({read:true});
  for(let i=0;i<5;i++)await announceWeek(db,options);
  assert.equal(await count(),5);
  assert.equal((await first.docs[0].ref.get()).data().read,true);
  assert.equal((await db.doc('notificationCampaigns/2026-10-05').get()).data().complete,true);
  assert.equal(await announceWeek(db,options),0);
});
test('weekly opt-out skips both inbox and push; new accounts are not backfilled; others stay enabled',{skip:!enabled},async()=>{
  await db.doc('users/a/preferences/notifications').set({weeklyDares:false});
  await db.doc('users/b/preferences/notifications').set({dares:false,push:false});
  await db.doc('users/c').update({createdAt:Timestamp.fromMillis(monday+1)});
  assert.equal(await announceWeek(db,{now:()=>monday+5000}),3);
  assert.equal((await db.doc('users/a/notifications/weekly_2026-10-05').get()).exists,false);
  assert.equal((await db.doc('users/b/notifications/weekly_2026-10-05').get()).exists,true);
});
test('new week gets its own campaign; deleted or ended weekly dare suppresses pending push',{skip:!enabled},async()=>{
  await announceWeek(db,{now:()=>monday});
  await db.doc('weeklyDares/2026-10-12').set(value(monday+7*86400000));
  await announceWeek(db,{now:()=>monday+7*86400000});assert.equal(await count(),10);
  const doc=await db.doc('users/a/notifications/weekly_2026-10-05').get();
  await db.doc('weeklyDares/2026-10-05').delete();
  await sendPush(db,{sendEachForMulticast:()=>assert.fail('must not send')},{data:doc,params:{uid:'a',id:doc.id}});
  assert.equal((await doc.ref.get()).data().pushAttempted,undefined);
});
test('weekly push uses Mood-wink and owner-scoped inbox link without needing an actor profile',{skip:!enabled},async()=>{
  const current=Date.now(),start=Date.parse(weekId(current)+'T00:00:00Z'),id=weekId(current);
  await db.doc(`weeklyDares/${id}`).set(value(start));
  const ref=db.doc('users/a/notifications/weekly_test');
  await ref.set({kind:'weekly',weeklyDareId:id,read:false});
  await db.doc('pushTokens/device').set({uid:'a'});
  const calls=[];const messaging={sendEachForMulticast:async m=>{calls.push(m);return {responses:[{success:true}]};}};
  await sendPush(db,messaging,{data:await ref.get(),params:{uid:'a',id:ref.id}});
  assert.equal(calls.length,1);assert.match(calls[0].notification.body,/new community dare/);
  assert.equal(calls[0].android.notification.icon,'ic_notification');assert.equal(calls[0].data.notificationId,'weekly_test');
});
test('weekly opt-out or phone-alert opt-out suppresses an already queued push',{skip:!enabled},async()=>{
  for(const preference of ['weeklyDares','push']) {
    const id=weekId(Date.now());await db.doc(`weeklyDares/${id}`).set(value(Date.parse(id+'T00:00:00Z')));
    const ref=db.doc(`users/a/notifications/${preference}`);await ref.set({kind:'weekly',weeklyDareId:id});
    await db.doc('users/a/preferences/notifications').set({[preference]:false});
    await sendPush(db,{sendEachForMulticast:()=>assert.fail('disabled')},{data:await ref.get(),params:{uid:'a',id:ref.id}});
    assert.equal((await ref.get()).data().pushAttempted,undefined);
  }
});
