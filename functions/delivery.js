'use strict';
const {FieldValue, Timestamp} = require('firebase-admin/firestore');
const {category, notificationId, stillRelevant} = require('./events');
async function deliver(db, n) {
  const ref = db.doc(`users/${n.recipientId}/notifications/${notificationId(n)}`);
  await db.runTransaction(async tx => {
    const paths = [ref.path, n.source, `users/${n.actorId}`, `users/${n.recipientId}`,
      `users/${n.actorId}/blocked/${n.recipientId}`, `users/${n.recipientId}/blocked/${n.actorId}`,
      `users/${n.recipientId}/preferences/notifications`];
    if (n.postId) paths.push(`posts/${n.postId}`);
    if (n.parentId) paths.push(`posts/${n.postId}/comments/${n.parentId}`);
    paths.push(`accountDeletions/${n.actorId}`,`accountDeletions/${n.recipientId}`);
    const docs = await tx.getAll(...paths.map(p => db.doc(p)));
    const [existing, source, actor, recipient, blocked, blockedBy, prefs] = docs;
    if (docs.slice(-2).some(d=>d.exists) || existing.exists || !actor.exists || !recipient.exists || blocked.exists || blockedBy.exists || prefs.data()?.[category(n.kind)] === false) return;
    if (!stillRelevant(n, source.data(), n.postId ? docs[7].data() : null, n.parentId ? docs[8].data() : null)) return;
    // Store IDs, never private message text or a copied profile/photo.
    tx.create(ref, {...n, read:false, createdAt:FieldValue.serverTimestamp(), expiresAt:Timestamp.fromMillis(Date.now() + 30 * 86400000)});
  });
}
module.exports = {deliver};
