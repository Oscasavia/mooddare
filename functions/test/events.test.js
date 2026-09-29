const {test} = require('node:test');
const assert = require('node:assert/strict');
const {eventsFor,notificationId,stillRelevant,category,kinds} = require('../events');
const post={authorId:'owner',likedBy:[],expiresAt:{toMillis:()=>Date.now()+100000}};
test('follows exclude self and existing follow updates',()=>{
  assert.equal(eventsFor('users/a/followers/b',null,{}).length,1);
  assert.deepEqual(eventsFor('users/a/followers/a',null,{}),[]);
  assert.deepEqual(eventsFor('users/a/followers/b',{},{}),[]);
});
test('likes only notify added actors, not removals, duplicates, edits or own likes',()=>{
  assert.deepEqual(eventsFor('posts/p',post,{...post,likedBy:['owner','b','b']}).map(n=>n.actorId),['b']);
  assert.deepEqual(eventsFor('posts/p',{...post,likedBy:['b']},post),[]);
  assert.deepEqual(eventsFor('posts/p',post,{...post,deleting:true,likedBy:['b']}),[]);
});
test('comments notify owner once; edits do not notify, likes notify commenter',()=>{
  const c={authorId:'c',text:'Hi'};
  assert.equal(eventsFor('posts/p/comments/c',null,c,post)[0].recipientId,'owner');
  assert.deepEqual(eventsFor('posts/p/comments/c',c,{...c,text:'Edited'},post),[]);
  assert.equal(eventsFor('posts/p/comments/c',c,{...c,likedBy:['b']},post)[0].kind,'commentLike');
});
test('reply targets and root get unique alerts, excluding actor; post owner not spammed',()=>{
  const r={authorId:'b',rootAuthorId:'a',replyToAuthorId:'c',parentId:'root'};
  assert.deepEqual(eventsFor('posts/p/replies/r',null,r,post).map(n=>n.recipientId),['c','a']);
  assert.equal(eventsFor('posts/p/replies/r',null,{...r,replyToAuthorId:'a'},post).length,1);
  assert.deepEqual(eventsFor('posts/p/replies/r',null,{...r,rootAuthorId:'b',replyToAuthorId:'b'},post),[]);
  assert.equal(eventsFor('posts/p/replies/r',r,{...r,likedBy:['a']},post)[0].kind,'replyLike');
});
test('dare opening/deletion does not generate new notifications',()=>{
  const invite={senderId:'a',recipientId:'b'};
  assert.equal(eventsFor('dareInvites/d',null,invite)[0].kind,'dare');
  assert.deepEqual(eventsFor('dareInvites/d',invite,{...invite,opened:true}),[]);
  assert.deepEqual(eventsFor('dareInvites/d',invite,null),[]);
});
test('stable IDs suppress replay and re-like spam while distinguishing recipients and sources',()=>{
  const n={kind:'reply',source:'posts/p/replies/r',actorId:'a',recipientId:'b'};
  assert.equal(notificationId(n),notificationId({...n}));
  assert.notEqual(notificationId(n),notificationId({...n,recipientId:'c'}));
  assert.notEqual(notificationId(n),notificationId({...n,source:'posts/p/replies/other'}));
});
test('delayed events reject removed likes, deleted posts, removed or deleting roots',()=>{
  const n={kind:'replyLike',actorId:'b',recipientId:'a',postId:'p',parentId:'root'};
  assert.equal(stillRelevant(n,{authorId:'a',likedBy:['b']},post,{}),true);
  assert.equal(stillRelevant(n,{authorId:'a',likedBy:[]},post,{}),false);
  assert.equal(stillRelevant(n,{authorId:'a',likedBy:['b']},{...post,deleting:true},{}),false);
  assert.equal(stillRelevant(n,{authorId:'a',likedBy:['b']},post,{deleting:true}),false);
  assert.equal(stillRelevant(n,{authorId:'a',likedBy:['b']},post,null),false);
});
test('each supported kind has a preference category',()=>{for(const kind of kinds) assert.ok(category(kind));});
