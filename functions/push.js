'use strict';
const {activeWeek} = require('./weekly');
const {category} = require('./events');
const pushBodies = {
  follow:'Someone started following you.', postLike:'Someone liked your moment.',
  comment:'There’s a new comment on your moment.', reply:'Someone replied to your comment.',
  commentLike:'Someone liked your comment.', replyLike:'Someone liked your reply.',
  dare:'A friend sent you a dare.',
  weekly:'A new community dare is here. Join this week!',
};
async function sendPush(db, messaging, event) {
  const n = event.data.data();
  const {uid, id} = event.params;
  // Claim once before sending. The durable inbox is authoritative; push is
  // best-effort so an ambiguous FCM acknowledgement never duplicates alerts.
  const claimed = await db.runTransaction(async tx => {
    const weekly=n.kind==='weekly';
    if(weekly && !/^\d{4}-\d{2}-\d{2}$/.test(n.weeklyDareId || '')) return false;
    const refs=[event.data.ref, db.doc(`users/${uid}`), db.doc(`users/${uid}/preferences/notifications`)];
    if(weekly) refs.push(db.doc(`weeklyDares/${n.weeklyDareId}`));
    else refs.push(db.doc(`users/${uid}/blocked/${n.actorId}`),db.doc(`users/${n.actorId}/blocked/${uid}`),db.doc(`users/${n.actorId}`));
    const docs = await tx.getAll(...refs);
    if (!docs[0].exists || docs[0].data().pushAttempted || !docs[1].exists || docs[2].data()?.push === false || docs[2].data()?.[category(n.kind)] === false || !pushBodies[n.kind]) return false;
    if(weekly) {
      if(!activeWeek(n.weeklyDareId,docs[3].data(),Date.now())) return false;
    } else if(!docs[5].exists || docs[3].exists || docs[4].exists) return false;
    tx.update(event.data.ref, {pushAttempted:true});
    return true;
  });
  if (!claimed) return;
  const tokens = await db.collection('pushTokens').where('uid','==',uid).limit(20).get();
  if (tokens.empty) return;
  const result = await messaging.sendEachForMulticast({
    tokens:tokens.docs.map(d => d.id),
    notification:{title:'MoodDare', body:pushBodies[n.kind]},
    data:{notificationId:id, recipientId:uid},
    android:{priority:'high', ttl:3600000, notification:{channelId:'mooddare_activity', icon:'ic_notification', color:'#BBA0FF', tag:id}},
    apns:{headers:{'apns-collapse-id':id}, payload:{aps:{sound:'default'}}},
  });
  for (let i=0; i<result.responses.length; i++) {
    if (['messaging/registration-token-not-registered','messaging/invalid-registration-token'].includes(result.responses[i].error?.code)) await tokens.docs[i].ref.delete();
  }
}
module.exports = {sendPush};
