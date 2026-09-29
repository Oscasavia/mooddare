const {test,beforeEach,after} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp,deleteApp} = require('firebase-admin/app');
const {getFirestore,Timestamp} = require('firebase-admin/firestore');
const {deliver} = require('../delivery');
const enabled=!!process.env.FIRESTORE_EMULATOR_HOST;
const app=enabled?initializeApp({projectId:'demo-mooddare-notifications'}):null;
const db=app?getFirestore(app):null;
const n={kind:'follow',actorId:'alice',recipientId:'bob',source:'users/bob/followers/alice'};
beforeEach(async()=>{
  if(!db)return;
  for(const uid of ['alice','bob'])await db.recursiveDelete(db.doc(`users/${uid}`));
  await db.doc('users/alice').set({username:'alice'});await db.doc('users/bob').set({username:'bob'});
  await db.doc(n.source).set({createdAt:Timestamp.now()});
});
after(async()=>{if(app)await deleteApp(app);});
test('transaction creates exactly one notification under concurrent retries',{skip:!enabled},async()=>{
  await Promise.all(Array.from({length:5},()=>deliver(db,n)));
  const result=await db.collection('users/bob/notifications').get();assert.equal(result.size,1);
  assert.equal(result.docs[0].data().read,false);assert.equal(result.docs[0].data().actorId,'alice');
  assert.equal(result.docs[0].data().text,undefined);
  await result.docs[0].ref.update({read:true});await deliver(db,n);
  assert.equal((await result.docs[0].ref.get()).data().read,true);
});
for(const blockedPath of ['users/alice/blocked/bob','users/bob/blocked/alice'])test(`suppresses blocked direction ${blockedPath}`,{skip:!enabled},async()=>{
  await db.doc(blockedPath).set({});await deliver(db,n);assert.equal((await db.collection('users/bob/notifications').get()).size,0);
});
test('deleted recipient, missing source and disabled categories suppress delivery',{skip:!enabled},async()=>{
  await db.doc('users/bob/preferences/notifications').set({follows:false});await deliver(db,n);
  assert.equal((await db.collection('users/bob/notifications').get()).size,0);
  await db.doc('users/bob/preferences/notifications').delete();await db.doc(n.source).delete();await deliver(db,n);
  assert.equal((await db.collection('users/bob/notifications').get()).size,0);
  await db.doc(n.source).set({});await db.doc('users/bob').delete();await deliver(db,n);
  assert.equal((await db.collection('users/bob/notifications').get()).size,0);
});
const {sendPush} = require('../push');
test('push uses branded channel/icon, targets recipient devices and claims retries once',{skip:!enabled},async()=>{
  await deliver(db,n);
  const doc=(await db.collection('users/bob/notifications').get()).docs[0];
  await db.doc('pushTokens/token1').set({uid:'bob'});await db.doc('pushTokens/token2').set({uid:'alice'});
  const calls=[];const messaging={sendEachForMulticast:async m=>{calls.push(m);return {responses:[{success:true}]};}};
  const event={data:doc,params:{uid:'bob',id:doc.id}};
  await Promise.all([sendPush(db,messaging,event),sendPush(db,messaging,event)]);
  assert.equal(calls.length,1);assert.deepEqual(calls[0].tokens,['token1']);
  assert.equal(calls[0].android.notification.icon,'ic_notification');
  assert.equal(calls[0].android.notification.channelId,'mooddare_activity');
  assert.equal(calls[0].data.recipientId,'bob');assert.equal(calls[0].data.notificationId,doc.id);
  assert.equal(calls[0].notification.title,'MoodDare');
  await db.doc('pushTokens/token1').delete();await db.doc('pushTokens/token2').delete();
});
test('push preferences suppress phone alerts while preserving the inbox',{skip:!enabled},async()=>{
  await deliver(db,n);await db.doc('users/bob/preferences/notifications').set({push:false});
  const doc=(await db.collection('users/bob/notifications').get()).docs[0];
  await sendPush(db,{sendEachForMulticast:()=>assert.fail('must not send')},{data:doc,params:{uid:'bob',id:doc.id}});
  assert.equal((await doc.ref.get()).exists,true);assert.equal((await doc.ref.get()).data().pushAttempted,undefined);
});
test('push removes invalid registrations and never targets a reassigned token',{skip:!enabled},async()=>{
  await deliver(db,n);const doc=(await db.collection('users/bob/notifications').get()).docs[0];
  await db.doc('pushTokens/stale').set({uid:'bob'});await db.doc('pushTokens/switched').set({uid:'alice'});
  const messaging={sendEachForMulticast:async m=>{assert.deepEqual(m.tokens,['stale']);return {responses:[{error:{code:'messaging/registration-token-not-registered'}}]};}};
  await sendPush(db,messaging,{data:doc,params:{uid:'bob',id:doc.id}});
  assert.equal((await db.doc('pushTokens/stale').get()).exists,false);
  await db.doc('pushTokens/switched').delete();
});
test('all social categories create recipient links from current source data',{skip:!enabled},async()=>{
  const {eventsFor}=require('../events');
  const post={authorId:'bob',likedBy:['alice'],expiresAt:Timestamp.fromMillis(Date.now()+86400000)};
  const comment={authorId:'alice',likedBy:['bob']};
  const root={authorId:'bob'};
  const reply={authorId:'alice',rootAuthorId:'bob',replyToAuthorId:'bob',parentId:'root',likedBy:['bob']};
  const invite={senderId:'alice',recipientId:'bob'};
  const sources=[['posts/p',post],['posts/p/comments/root',root],['posts/p/comments/c',comment],['posts/p/replies/r',reply],['dareInvites/invite',invite]];
  for(const [path,data] of sources)await db.doc(path).set(data);
  for(const [path,data] of sources)for(const event of eventsFor(path,null,data,post))await deliver(db,event);
  const results=[...(await db.collection('users/bob/notifications').get()).docs,...(await db.collection('users/alice/notifications').get()).docs].map(d=>d.data());
  for(const kind of ['postLike','comment','reply','commentLike','replyLike','dare'])assert.ok(results.some(n=>n.kind===kind),kind);
  assert.equal(results.filter(n=>n.kind==='reply').length,1);
  assert.equal(results.find(n=>n.kind==='reply').parentId,'root');
  await db.recursiveDelete(db.doc('posts/p'));await db.doc('dareInvites/invite').delete();
});
