'use strict';
const {initializeApp} = require('firebase-admin/app');
const {getFirestore, Timestamp} = require('firebase-admin/firestore');
const {onDocumentWritten, onDocumentDeleted} = require('firebase-functions/v2/firestore');
const {setGlobalOptions} = require('firebase-functions/v2');
const {eventsFor} = require('./events');
const {deliver} = require('./delivery');
initializeApp();
setGlobalOptions({region:'us-central1', maxInstances:3, memory:'256MiB'});
const db = getFirestore();
async function handle(event) {
  const after = event.data?.after;
  if (!after?.exists) return;
  const before = event.data.before.exists ? event.data.before.data() : null;
  const path = after.ref.path;
  const parts = path.split('/');
  const post = parts[0] === 'posts' && parts.length === 4 ? (await db.doc(`posts/${parts[1]}`).get()).data() : null;
  for (const n of eventsFor(path, before, after.data(), post)) await deliver(db, n);
}
exports.notifyFollow = onDocumentWritten({document:'users/{uid}/followers/{actor}', retry:true}, handle);
exports.notifyPostLike = onDocumentWritten({document:'posts/{post}', retry:true}, handle);
exports.notifyComment = onDocumentWritten({document:'posts/{post}/comments/{comment}', retry:true}, handle);
exports.notifyReply = onDocumentWritten({document:'posts/{post}/replies/{reply}', retry:true}, handle);
exports.notifyDare = onDocumentWritten({document:'dareInvites/{invite}', retry:true}, handle);
async function clear(query) {
  while (true) {
    const page = await query.limit(200).get();
    if (page.empty) return;
    const batch = db.batch();
    for (const doc of page.docs) batch.delete(doc.ref);
    await batch.commit();
  }
}
exports.clearBlockedNotifications = onDocumentWritten('users/{uid}/blocked/{other}', async event => {
  if (!event.data?.after.exists) return;
  const {uid, other} = event.params;
  for (const [owner, actor] of [[uid,other], [other,uid]]) await clear(db.collection(`users/${owner}/notifications`).where('actorId','==',actor));
});
exports.clearDeletedUserNotifications = onDocumentDeleted('users/{uid}', async event => {
  const {uid} = event.params;
  await clear(db.collection(`users/${uid}/notifications`));
  await clear(db.collection(`users/${uid}/preferences`));
  await clear(db.collection('pushTokens').where('uid','==',uid));
  await clear(db.collectionGroup('notifications').where('actorId','==',uid));
});
const {onDocumentCreated} = require('firebase-functions/v2/firestore');
const {getMessaging} = require('firebase-admin/messaging');
const {onSchedule} = require('firebase-functions/v2/scheduler');
const {sendPush} = require('./push');
exports.pushNotification = onDocumentCreated('users/{uid}/notifications/{id}', event => sendPush(db, getMessaging(), event));
exports.expireNotifications = onSchedule('every day 03:00', async () => {
  await clear(db.collectionGroup('notifications').where('expiresAt','<=',Timestamp.now()));
  await clear(db.collectionGroup('feedHistory').where('expiresAt','<=',Timestamp.now()));
  await clear(db.collection('pushTokens').where('updatedAt','<=',Timestamp.fromMillis(Date.now()-60*86400000)));
});
const {announceWeek} = require('./weekly');
// Same Monday/UTC boundary as the app. Subsequent ticks resume bounded fan-out
// or a late-published schedule; completed campaigns perform no recipient reads.
exports.notifyWeeklyDare = onSchedule({schedule:'*/5 * * * 1', timeZone:'Etc/UTC', timeoutSeconds:300, maxInstances:1}, () => announceWeek(db));

const {onRequest}=require('firebase-functions/v2/https');
const {getAuth}=require('firebase-admin/auth');
const {getStorage}=require('firebase-admin/storage');
const {handler}=require('./moderation_http');
exports.moderationApi=onRequest({timeoutSeconds:120,memory:'512MiB',cors:['https://mooddare.web.app','https://mooddare.firebaseapp.com']},handler(db,getAuth(),getStorage().bucket('mooddare.firebasestorage.app')));

// Deletion requests are accepted durably before the app signs out. A scheduler
// recovers failed invocations and performs the final expired-token sweep.
const deletion=require('./account_deletion');
const {onCall}=require('firebase-functions/v2/https');
const deletionBucket=()=>getStorage().bucket('mooddare.firebasestorage.app');
exports.requestAccountDeletion=onCall({timeoutSeconds:30},request=>deletion.requestDeletion(db,request));
exports.eraseAccount=onDocumentCreated({document:'accountDeletions/{uid}',retry:true,timeoutSeconds:540,memory:'512MiB',maxInstances:1},event=>deletion.processDeletion(db,getAuth(),deletionBucket(),event.params.uid));
exports.recoverAccountDeletions=onSchedule({schedule:'every 10 minutes',timeoutSeconds:540,memory:'512MiB',maxInstances:1},()=>deletion.recoverDeletions(db,getAuth(),deletionBucket()));
// Covers account removals through older apps or an administrator as well.
exports.eraseDeletedAuthAccount=require('firebase-functions/v1').region('us-central1').runWith({failurePolicy:true}).auth.user().onDelete(user=>deletion.enqueueDeletion(db,user.uid));
const {sweepUploads}=require('./abandoned_uploads');
exports.cleanupAbandonedUploads=onSchedule({schedule:'every 60 minutes',timeoutSeconds:540,memory:'256MiB',maxInstances:1},()=>sweepUploads(db,getAuth(),deletionBucket()));
