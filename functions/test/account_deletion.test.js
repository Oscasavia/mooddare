'use strict';
const {test,beforeEach,after}=require('node:test');
const assert=require('node:assert/strict');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore,Timestamp}=require('firebase-admin/firestore');
const {getAuth}=require('firebase-admin/auth');
const {createHash}=require('node:crypto');
const d=require('../account_deletion');
const enabled=!!process.env.FIRESTORE_EMULATOR_HOST&&!!process.env.FIREBASE_AUTH_EMULATOR_HOST;
const app=enabled?initializeApp({projectId:'demo-mooddare-deletion'},'deletion-tests'):null;
const db=app?getFirestore(app):null,auth=app?getAuth(app):null;
const run=(name,fn)=>test(name,{skip:!enabled},fn);
const hash=v=>createHash('sha256').update(v).digest('hex');
let clock,objects,failStorage;
const bucket={file:name=>({name,delete:async()=>{if(failStorage)throw Error('storage unavailable');objects.delete(name);}}),getFiles:async({prefix,maxResults})=>[[...objects].filter(n=>n.startsWith(prefix)).slice(0,maxResults).map(n=>bucket.file(n))]};
const request=(uid='erase')=>({auth:{uid,token:{auth_time:clock/1000}},data:{confirm:'DELETE',expectedUid:uid}});
const erase=(options={})=>d.processDeletion(db,auth,bucket,'erase',{now:()=>clock,...options});
const put=(path,value)=>db.doc(path).set(value);
const exists=async path=>(await db.doc(path).get()).exists;
const data=async path=>(await db.doc(path).get()).data();
beforeEach(async()=>{
 if(!db)return;clock=Date.now();objects=new Set();failStorage=false;
 for(const c of await db.listCollections())await db.recursiveDelete(c);
 for(const u of (await auth.listUsers()).users)await auth.deleteUser(u.uid);
 for(const uid of ['erase','keep']){await auth.createUser({uid,email:uid+'@example.test'});await put('users/'+uid,{username:uid});}
});
after(async()=>{if(app)await deleteApp(app);});
run('only recent authenticated intent for the same account creates an idempotent durable job',async()=>{
 await assert.rejects(d.requestDeletion(db,{data:{confirm:'DELETE'}},{now:clock}),{code:'unauthenticated'});
 await assert.rejects(d.requestDeletion(db,{...request(),data:{confirm:'DELETE',expectedUid:'keep'}},{now:clock}),{code:'invalid-argument'});
 await assert.rejects(d.requestDeletion(db,{...request(),auth:{uid:'erase',token:{auth_time:clock/1000-301}}},{now:clock}),{code:'failed-precondition'});
 await assert.rejects(d.requestDeletion(db,{...request(),data:{...request().data,uid:'keep'}},{now:clock}),{code:'invalid-argument'});
 assert.deepEqual(await d.requestDeletion(db,request(),{now:clock}),{accepted:true});
 await d.requestDeletion(db,request(),{now:clock});assert.equal((await db.collection('accountDeletions').get()).size,1);
 assert.equal((await auth.getUser('keep')).disabled,false);
});
run('erases Auth, all account media, orphaned descendants and cross-account references while preserving another account',async()=>{
 const values={
  'users/erase/preferences/private':{secret:true},'users/erase/savedDares/saved':{dare:'saved'},'users/erase/arbitrary/child/nested/grandchild':{private:true},
  'usernames/erase':{uid:'erase'},'usernames/old':{uid:'erase'},'usernames/keep':{uid:'keep'},
  'posts/own':{authorId:'erase',likedBy:['keep']},'posts/own/comments/their':{authorId:'keep',text:'on deleted post'},
  'posts/own/replies/their':{authorId:'keep',rootAuthorId:'keep',parentId:'their'},
  'posts/keep':{authorId:'keep',likedBy:['erase','keep'],mediaUrl:'untouched'},
  'posts/keep/comments/mine':{authorId:'erase',text:'erase me'},
  'posts/keep/replies/rootchild':{authorId:'keep',parentId:'mine',rootAuthorId:'erase'},
  'posts/keep/comments/keep':{authorId:'keep',text:'keep me',likedBy:['erase','keep']},
  'posts/keep/replies/mine':{authorId:'erase',parentId:'keep',rootAuthorId:'keep'},
  'posts/keep/replies/keep':{authorId:'keep',parentId:'keep',rootAuthorId:'keep',replyToAuthorId:'erase',replyToId:'mine',text:'their words',likedBy:['erase','keep']},
  'posts/missing/comments/orphan':{authorId:'erase'},'posts/missing/replies/orphan':{authorId:'erase'},
  'users/erase/following/keep':{},'users/keep/followers/erase':{},'users/keep/following/erase':{},'users/keep/blocked/erase':{},
  'users/third/following/erase':{},'users/keep/following/someone':{},
  'dareInvites/sent':{senderId:'erase',recipientId:'keep'},'dareInvites/received':{senderId:'keep',recipientId:'erase'},'dareInvites/keep':{senderId:'keep',recipientId:'other'},
  'pushTokens/mine':{uid:'erase'},'pushTokens/keep':{uid:'keep'},
  'users/keep/notifications/actor':{actorId:'erase',recipientId:'keep'},'users/keep/notifications/post':{actorId:'other',recipientId:'keep',postId:'own'},
  'users/keep/notifications/comment':{actorId:'other',recipientId:'keep',postId:'keep',commentId:'mine'},'users/keep/notifications/keep':{actorId:'other',recipientId:'keep'},
  'reports/reporter':{reporterId:'erase',postId:'keep'},'reports/person':{reporterId:'keep',userId:'erase'},'reports/post':{reporterId:'keep',postId:'own'},
  'reports/comment':{reporterId:'keep',postId:'keep',commentId:'mine'},'reports/keep':{reporterId:'keep',postId:'keep'},
  'accountRestrictions/erase':{status:'banned'},'moderationStaff/erase':{enabled:true},
  'notificationCampaigns/week':{cursor:'erase',status:'working'},
  ['moderationContent/'+hash('posts/archived')]:{path:'posts/archived',original:{authorId:'erase'},removed:true},
  'posts/archived/comments/other':{authorId:'keep'},'moderationPosts/archived':{removed:true},
  ['moderationContent/'+hash('posts/keep/comments/keep')]:{path:'posts/keep/comments/keep',original:{authorId:'keep',text:'preserve',likedBy:['erase','keep']}},
  ['moderationContent/'+hash('posts/keep/replies/keep')]:{path:'posts/keep/replies/keep',original:{authorId:'keep',rootAuthorId:'keep',replyToAuthorId:'erase',replyToId:'mine'}},
  'moderationActions/a':{staff:'staff',userId:'erase',reportId:'person',path:'users/erase',lockPath:'users/erase'},
  ['moderationLocks/'+hash('users/erase')]:{operationId:'a'},'moderationReviews/person':{staff:'staff'},
 };
 await Promise.all(Object.entries(values).map(([p,v])=>put(p,v)));
 for(const name of ['posts/erase/own.jpg','posts/erase/unposted.mp4','posts/erase/nested/old.jpg','profile_pictures/erase/old.jpg','profile_pictures/erase','posts/keep/keep.jpg','posts/erase-other/keep.jpg'])objects.add(name);
 await put('users/erase/feedHistory/own',{authorId:'keep'});
 await put('users/keep/feedHistory/deleted-author',{authorId:'erase'});
 await put('users/keep/feedHistory/keep',{authorId:'keep'});
 await d.requestDeletion(db,request(),{now:clock});await erase();
 assert.equal(await exists('users/erase/feedHistory/own'),false);
 assert.equal(await exists('users/keep/feedHistory/deleted-author'),false);
 assert.equal(await exists('users/keep/feedHistory/keep'),true);
 await assert.rejects(auth.getUser('erase'),{code:'auth/user-not-found'});
 assert.equal((await auth.getUser('keep')).disabled,false);
 assert.deepEqual([...objects].sort(),['posts/erase-other/keep.jpg','posts/keep/keep.jpg']);
 assert.deepEqual((await data('posts/keep')).likedBy,['keep']);
 assert.deepEqual((await data('posts/keep/comments/keep')).likedBy,['keep']);
 const reply=await data('posts/keep/replies/keep');assert.equal(reply.text,'their words');assert.equal(reply.replyToAuthorId,undefined);assert.deepEqual(reply.likedBy,['keep']);
 for(const p of ['posts/own','posts/own/comments/their','posts/archived/comments/other','posts/keep/comments/mine','posts/keep/replies/rootchild','posts/keep/replies/mine','posts/missing/comments/orphan','users/erase','users/erase/arbitrary/child/nested/grandchild','users/third/following/erase','users/keep/blocked/erase','reports/person','reports/post','reports/comment','reports/reporter','moderationActions/a','moderationReviews/person'])assert.equal(await exists(p),false,p);
 for(const p of ['users/keep','posts/keep','reports/keep','usernames/keep','pushTokens/keep','dareInvites/keep','users/keep/notifications/keep','users/keep/following/someone'])assert.equal(await exists(p),true,p);
 assert.equal((await data('accountDeletions/erase')).status,'complete');
 // Finish the stale-token/upload grace period, then ensure no structured UID
 // remains anywhere (including document IDs and private moderation copies).
 clock+=d.HOLD_MS+1;await erase();
 const scan=async collection=>{for(const doc of await collection.listDocuments()){
   assert.ok(!doc.path.split('/').includes('erase'),doc.path);
   const snapshot=await doc.get();if(snapshot.exists)assert.ok(!JSON.stringify(snapshot.data()).includes('"erase"'),doc.path);
   for(const child of await doc.listCollections())await scan(child);
 }};
 for(const collection of await db.listCollections())await scan(collection);
});
run('Storage failure keeps an Auth tombstone disabled and retries without harming surviving content',async()=>{
 objects.add('posts/erase/unposted.mp4');await d.enqueueDeletion(db,'erase',{now:clock});failStorage=true;
 await assert.rejects(erase(),/storage unavailable/);assert.equal((await auth.getUser('erase')).disabled,true);
 assert.equal((await data('accountDeletions/erase')).status,'retry');
 assert.equal(await erase(),false);clock+=60001;failStorage=false;await erase();
 await assert.rejects(auth.getUser('erase'),{code:'auth/user-not-found'});assert.equal(objects.size,0);
});
run('every checkpoint can resume after an interrupted acknowledgement',async()=>{
 await d.enqueueDeletion(db,'erase',{now:clock});const interrupted=new Set();
 for(let attempt=0;attempt<50;attempt++){
  try{await erase({afterStage:async stage=>{if(!interrupted.has(stage)){interrupted.add(stage);throw Error('lost acknowledgement');}}});break;}
  catch(error){assert.match(error.message,/lost acknowledgement/);clock+=60001;}
 }
 assert.ok(interrupted.size>25);assert.equal((await data('accountDeletions/erase')).status,'complete');
 await assert.rejects(auth.getUser('erase'),{code:'auth/user-not-found'});
});
run('concurrent workers use one lease; final sweep removes late uploads and survives its own failure',async()=>{
 await d.enqueueDeletion(db,'erase',{now:clock});let unblock;const blocked=new Promise(r=>unblock=r);let started;const ready=new Promise(r=>started=r);
 const first=erase({afterStage:async stage=>{if(stage===0){started();await blocked;}}});await ready;
 assert.equal(await erase(),false);unblock();await first;
 objects.add('posts/erase/late.mp4');clock+=d.HOLD_MS+1;failStorage=true;await assert.rejects(erase());
 clock+=60001;failStorage=false;await erase();assert.equal(objects.size,0);assert.equal(await exists('accountDeletions/erase'),false);
});
run('expired worker lease and budget yield recover; missing Auth accounts are safe',async()=>{
 await auth.deleteUser('erase');await d.enqueueDeletion(db,'erase',{now:clock});
 await db.doc('accountDeletions/erase').update({lease:'dead',leaseUntil:Timestamp.fromMillis(clock+100)});
 assert.equal(await erase(),false);clock+=101;
 await assert.rejects(erase({budgetMs:-1}),{code:'cleanup-yield'});clock+=60001;
 await d.recoverDeletions(db,auth,bucket,{now:()=>clock});assert.equal((await data('accountDeletions/erase')).status,'complete');
});
run('real Storage emulator erases nested media and preserves another owner',async()=>{
 const {getStorage}=require('firebase-admin/storage');const realBucket=getStorage(app).bucket('demo-mooddare-deletion.appspot.com');
 for(const name of ['posts/erase/photo.jpg','posts/erase/nested/video.mp4','profile_pictures/erase/avatar.jpg','profile_pictures/erase','posts/keep/photo.jpg'])await realBucket.file(name).save(Buffer.from('test media'));
 await d.enqueueDeletion(db,'erase',{now:clock});await d.processDeletion(db,auth,realBucket,'erase',{now:()=>clock});
 assert.deepEqual((await realBucket.getFiles())[0].map(f=>f.name),['posts/keep/photo.jpg']);
 await realBucket.file('posts/keep/photo.jpg').delete();
});
run('late notification delivery and moderation actions cannot recreate erased data',async()=>{
 const {deliver}=require('../delivery');const {sendPush}=require('../push');const m=require('../moderation');
 await put('users/keep/followers/erase',{});
 const n={kind:'follow',actorId:'erase',recipientId:'keep',source:'users/keep/followers/erase'};
 await deliver(db,n);const notification=(await db.collection('users/keep/notifications').get()).docs[0];assert.ok(notification);
 await put('posts/victim',{authorId:'erase'});await put('reports/reported',{postId:'victim'});
 await m.requestAction(db,'staff',{action:'ban',operationId:'ban',reportId:'reported',reason:'Reviewed test report'});
 await d.enqueueDeletion(db,'erase',{now:clock});
 await assert.rejects(m.processAction(db,{revokeRefreshTokens:async()=>{}},bucket,'ban'),/deletion/);
 await sendPush(db,{sendEachForMulticast:()=>assert.fail('must not push')},{data:notification,params:{uid:'keep',id:notification.id}});
 await notification.ref.delete();await deliver(db,n);assert.equal((await db.collection('users/keep/notifications').get()).size,0);
});
run('abandoned upload reclamation preserves published/archived/recent media and assigns a stable retry ID',async()=>{
 const {reclaimUpload,GRACE_MS}=require('../abandoned_uploads');let removed=0;
 const file=id=>({name:`posts/keep/${id}.jpg`,getMetadata:async()=>[{generation:'7',timeCreated:new Date(clock-GRACE_MS-1).toISOString()}],delete:async options=>{assert.equal(options.ifGenerationMatch,'7');removed++;}});
 await put('posts/published',{authorId:'keep'});await put('moderationContent/'+hash('posts/archived'),{path:'posts/archived',original:{authorId:'keep'}});
 assert.equal(await reclaimUpload(db,auth,file('published'),{now:clock}),false);
 assert.equal(await reclaimUpload(db,auth,file('archived'),{now:clock}),false);
 assert.equal(await reclaimUpload(db,auth,file('recent'),{now:clock-GRACE_MS}),false);
 assert.equal(await reclaimUpload(db,auth,file('abandoned'),{now:clock}),true);
 const marker=await data('moderationPosts/abandoned');assert.equal(marker.ownerId,'keep');assert.ok(marker.replacementPostId);
 await reclaimUpload(db,auth,file('abandoned'),{now:clock});assert.equal((await data('moderationPosts/abandoned')).replacementPostId,marker.replacementPostId);assert.equal(removed,2);
 // Lost file-delete acknowledgement must leave the old post ID fenced.
 await assert.rejects(reclaimUpload(db,auth,{...file('failure'),delete:async()=>{throw Error('offline');}},{now:clock}));assert.equal(await exists('moderationPosts/failure'),true);
 await auth.deleteUser('keep');await reclaimUpload(db,auth,file('missing-account'),{now:clock});assert.equal(await exists('accountDeletions/keep'),true);
});
