'use strict';
const {createHash} = require('node:crypto');
const kinds = ['follow', 'postLike', 'comment', 'reply', 'commentLike', 'replyLike', 'dare'];
const category = kind => ({follow:'follows', postLike:'likes', commentLike:'likes', replyLike:'likes', comment:'comments', reply:'comments', dare:'dares'})[kind];
// Stable across retries and repeated unlike/re-like or follow/unfollow actions.
const notificationId = n => createHash('sha256').update(JSON.stringify([n.kind, n.source, n.actorId, n.recipientId])).digest('hex');
function eventsFor(path, before, after, post) {
  if (!after || after.deleting) return [];
  const p = path.split('/');
  const events = [];
  const add = (kind, actorId, recipientId, extra = {}) => {
    if (actorId && recipientId && actorId !== recipientId) events.push({kind, actorId, recipientId, source:path, ...extra});
  };
  const newLikes = () => [...new Set(after.likedBy || [])].filter(uid => !(before?.likedBy || []).includes(uid));
  if (p[0] === 'users' && p[2] === 'followers' && !before) add('follow', p[3], p[1]);
  if (p[0] === 'dareInvites' && !before) add('dare', after.senderId, after.recipientId, {inviteId:p[1]});
  if (p[0] === 'posts' && p.length === 2) {
    for (const uid of newLikes()) add('postLike', uid, after.authorId, {postId:p[1]});
  }
  if (p[0] === 'posts' && p.length === 4 && post && !post.deleting) {
    const reply = p[2] === 'replies';
    const extra = {postId:p[1], commentId:p[3], ...(reply ? {parentId:after.parentId} : {})};
    if (!before) {
      if (reply) {
        // Notify the person being addressed and root author once each.
        for (const uid of new Set([after.replyToAuthorId, after.rootAuthorId])) add('reply', after.authorId, uid, extra);
      } else add('comment', after.authorId, post.authorId, extra);
    }
    for (const uid of newLikes()) add(reply ? 'replyLike' : 'commentLike', uid, after.authorId, extra);
  }
  return events;
}
function stillRelevant(n, current, post, root) {
  if (!current || current.deleting) return false;
  if (n.postId && (!post || post.deleting)) return false;
  if (n.parentId && (!root || root.deleting)) return false;
  if (n.kind.endsWith('Like')) return (current.likedBy || []).includes(n.actorId) && current.authorId === n.recipientId;
  if (n.kind === 'dare') return current.senderId === n.actorId && current.recipientId === n.recipientId;
  if (n.kind === 'comment') return current.authorId === n.actorId && post.authorId === n.recipientId;
  if (n.kind === 'reply') return current.authorId === n.actorId && [current.replyToAuthorId, current.rootAuthorId].includes(n.recipientId);
  return n.kind === 'follow';
}
module.exports = {kinds, category, notificationId, eventsFor, stillRelevant};
