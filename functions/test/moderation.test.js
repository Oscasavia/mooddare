'use strict';
const {test,beforeEach,after}=require('node:test');
const assert=require('node:assert/strict');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore,Timestamp}=require('firebase-admin/firestore');
const m=require('../moderation');
const enabled=!!process.env.FIRESTORE_EMULATOR_HOST;
const app=enabled?initializeApp({projectId:'demo-mooddare-moderation'},'moderation-tests'):null;
const db=app?getFirestore(app):null;
const run=(name,fn)=>test(name,{skip:!enabled},fn);
const t=()=>Timestamp.now();
let metadata,calls,failMedia,failAuth;
const auth={revokeRefreshTokens:async uid=>{if(failAuth)throw Error('offline');calls.push(uid);}};
const bucket={name:'bucket',file:name=>({name,setMetadata:async value=>{if(failMedia)throw Error('offline');metadata=value;},getMetadata:async()=>[{size:12}]})};
const input=(action,operationId='op',reportId='report')=>({action,operationId,reportId,reason:'Reviewed the reported concern.'});
beforeEach(async()=>{
 if(!db)return;
 for(const c of ['users','posts','reports','moderationContent','moderationActions','moderationReviews','moderationLocks','moderationPosts','moderationStaff','accountRestrictions'])await db.recursiveDelete(db.collection(c));
 await db.doc('users/author').set({username:'author'});
 await db.doc('posts/post').set({authorId:'author',mediaType:'image',mediaPath:'posts/author/post.jpg',mediaUrl:'https://old',likedBy:['reader'],createdAt:t(),expiresAt:t()});
 await db.doc('reports/report').set({postId:'post',reason:'inappropriate',createdAt:t()});
 metadata=null;calls=[];failMedia=false;failAuth=false;
});
after(async()=>{if(app)await deleteApp(app);});
run('authorization requires verified Google identity and server-only staff membership',async()=>{
 const token={uid:'staff',email_verified:true,firebase:{sign_in_provider:'google.com'},auth_time:Date.now()/1000};
 const a={verifyIdToken:async(raw,revoked)=>{assert.equal(raw,'token');assert.equal(revoked,true);return token;}};
 await assert.rejects(m.authorize(db,a,null),/Sign in/);
 await assert.rejects(m.authorize(db,a,'Bearer token'),/does not have/);
 await db.doc('moderationStaff/staff').set({enabled:true});assert.equal(await m.authorize(db,a,'Bearer token',true),'staff');
 token.auth_time-=7200;await assert.rejects(m.authorize(db,a,'Bearer token',true),/sign in again/);
 token.auth_time=Date.now()/1000;token.email_verified=false;await assert.rejects(m.authorize(db,a,'Bearer token'),/approved Google/);
 token.email_verified=true;token.firebase.sign_in_provider='password';await assert.rejects(m.authorize(db,a,'Bearer token'),/approved Google/);
});
run('remove archives content, blocks recreation and revokes its token; restore rotates URL',async()=>{
 await m.requestAction(db,'staff',input('remove'));await m.processAction(db,auth,bucket,'op');
 assert.equal((await db.doc('posts/post').get()).exists,false);
 assert.equal((await db.doc('moderationPosts/post').get()).exists,true);
 assert.equal(metadata.metadata.firebaseStorageDownloadTokens,null);
 const view=await m.detail(db,'report');assert.equal(view.removed,true);assert.equal(view.content.authorId,'author');
 await m.requestAction(db,'staff',input('restore','restore'));await m.processAction(db,auth,bucket,'restore');
 const restored=(await db.doc('posts/post').get()).data();assert.ok(restored.mediaUrl.includes('token='));assert.notEqual(restored.mediaUrl,'https://old');assert.deepEqual(restored.likedBy,['reader']);
 assert.equal((await db.doc('moderationPosts/post').get()).exists,false);assert.equal((await m.detail(db,'report')).removed,false);
});
run('double submissions are idempotent; conflicting operations and reused IDs fail',async()=>{
 await Promise.all([m.requestAction(db,'staff',input('remove')),m.requestAction(db,'staff',input('remove'))]);
 await assert.rejects(m.requestAction(db,'staff',input('dismiss','other')),/still processing/);
 await assert.rejects(m.requestAction(db,'other',input('remove')),/already used/);
 await Promise.all([m.processAction(db,auth,bucket,'op'),m.processAction(db,auth,bucket,'op')]);
 assert.equal((await db.collection('moderationActions').get()).size,1);
 assert.equal((await db.doc('moderationActions/op').get()).data().status,'done');
});
run('interrupted media removal stays locked and can be resumed without losing archive',async()=>{
 await m.requestAction(db,'staff',input('remove'));failMedia=true;await assert.rejects(m.processAction(db,auth,bucket,'op'));
 assert.equal((await db.doc('moderationActions/op').get()).data().status,'retry');
 assert.equal((await m.detail(db,'report')).removed,true);
 failMedia=false;await m.processAction(db,auth,bucket,'op');assert.equal((await db.doc('moderationActions/op').get()).data().status,'done');
});
run('restore never resurrects a deleted account and rejects foreign media paths',async()=>{
 await m.requestAction(db,'staff',input('remove'));await m.processAction(db,auth,bucket,'op');await db.doc('users/author').delete();
 await assert.rejects(m.requestAction(db,'staff',input('restore','restore')),/deleted their account/);
 await db.doc('users/author').set({});await db.doc('posts/post').set({authorId:'author',mediaPath:'posts/other/private.jpg'});
 await db.doc(`moderationContent/${m.key('posts/post')}`).delete();
 await m.requestAction(db,'staff',input('remove','foreign'));await assert.rejects(m.processAction(db,auth,bucket,'foreign'),/manual review/);
});
run('comment and reply removals redact public text; restorations preserve thread metadata',async()=>{
 for(const [collection,isReply] of [['comments',false],['replies',true]]){
 const reportId=collection,operationId=collection;
 await db.doc(`posts/post/${collection}/c`).set({authorId:'author',text:'original',likedBy:['reader'],...(isReply?{parentId:'root',rootAuthorId:'author'}:{}),createdAt:t()});
 await db.doc(`reports/${reportId}`).set({postId:'post',commentId:'c',isReply,reason:'spam',createdAt:t()});
 await m.requestAction(db,'staff',input('remove',operationId,reportId));await m.processAction(db,auth,bucket,operationId);
 const redacted=(await db.doc(`posts/post/${collection}/c`).get()).data();assert.equal(redacted.moderationRemoved,true);assert.ok(!redacted.text.includes('original'));
 await m.requestAction(db,'staff',input('restore',operationId+'r',reportId));await m.processAction(db,auth,bucket,operationId+'r');
 assert.equal((await db.doc(`posts/post/${collection}/c`).get()).data().text,'original');
 }
});
run('deleted comments cannot be restored by an interrupted operation',async()=>{
 await db.doc('posts/post/comments/c').set({authorId:'author',text:'original'});await db.doc('reports/comment').set({postId:'post',commentId:'c',isReply:false});
 await m.requestAction(db,'staff',input('remove','rm','comment'));await m.processAction(db,auth,bucket,'rm');
 await m.requestAction(db,'staff',input('restore','rs','comment'));await db.doc('posts/post/comments/c').delete();
 await assert.rejects(m.processAction(db,auth,bucket,'rs'),/deleted/);
});
run('suspend, ban and reinstate write restrictions and revoke sessions with retry',async()=>{
 await m.requestAction(db,'staff',input('suspend'));failAuth=true;await assert.rejects(m.processAction(db,auth,bucket,'op'));
 assert.equal(m.blocked((await db.doc('accountRestrictions/author').get()).data()),true);
 failAuth=false;await m.processAction(db,auth,bucket,'op');assert.deepEqual(calls,['author']);
 await m.requestAction(db,'staff',input('ban','ban'));await m.processAction(db,auth,bucket,'ban');assert.equal(m.blocked((await db.doc('accountRestrictions/author').get()).data(),Date.now()+20*86400000),true);
 await m.requestAction(db,'staff',input('reinstate','rs'));await m.processAction(db,auth,bucket,'rs');assert.equal(m.blocked((await db.doc('accountRestrictions/author').get()).data()),false);
});
run('cannot restrict self or another staff member; reasons and target paths validated',async()=>{
 await assert.rejects(m.requestAction(db,'author',input('ban')),/Staff accounts/);
 await db.doc('moderationStaff/author').set({enabled:true});await assert.rejects(m.requestAction(db,'staff',input('ban')),/Staff accounts/);
 await assert.rejects(m.requestAction(db,'staff',{...input('remove'),reason:'x'}),/reason/);
 assert.throws(()=>m.target({postId:'../private'}),/identifier/);
 assert.equal(m.blocked({status:'suspended',until:Timestamp.fromMillis(0)}),false);
});
run('report resolution is separate from reporter data; repeat reports reopen review',async()=>{
 await m.requestAction(db,'staff',input('dismiss'));await m.processAction(db,auth,bucket,'op');
 assert.equal((await db.doc('reports/report').get()).data().reason,'inappropriate');
 assert.equal((await m.list(db,'reports')).items[0].review.status,'resolved');
 await db.doc('reports/report').update({createdAt:Timestamp.fromMillis(Date.now()+1000)});
 assert.equal((await m.list(db,'reports')).items[0].review.status,'pending');
});
run('restoration retry after its commit does not invalidate the restored media URL',async()=>{
 await m.requestAction(db,'staff',input('remove'));await m.processAction(db,auth,bucket,'op');
 await m.requestAction(db,'staff',input('restore','restore'));await m.processAction(db,auth,bucket,'restore');
 const url=(await db.doc('posts/post').get()).data().mediaUrl;const token=metadata.metadata.firebaseStorageDownloadTokens;
 // Simulate a lost final acknowledgement after the content transaction.
 await db.doc('moderationActions/restore').update({status:'retry'});
 await db.doc(`moderationLocks/${m.key('posts/post')}`).set({operationId:'restore'});
 await m.processAction(db,auth,bucket,'restore');
 assert.equal(metadata.metadata.firebaseStorageDownloadTokens,token);
 assert.equal((await db.doc('posts/post').get()).data().mediaUrl,url);
});
run('HTTP routes deny anonymous access and serve an authorized report queue',async()=>{
 const {handler}=require('../moderation_http');let output,status=200;
 const res={set(){return this;},status(code){status=code;return this;},json(value){output=value;return this;},end(){return this;}};
 const a={verifyIdToken:async()=>({uid:'staff',email_verified:true,firebase:{sign_in_provider:'google.com'},auth_time:Date.now()/1000})};
 const h=handler(db,a,bucket);await h({method:'GET',path:'/admin-api/reports',query:{},get:()=>null},res);assert.equal(status,401);
 await db.doc('moderationStaff/staff').set({enabled:true});status=200;
 await h({method:'GET',path:'/admin-api/reports',query:{},get:()=> 'Bearer token'},res);assert.equal(status,200);assert.equal(output.items.length,1);
 await h({method:'GET',path:'/admin-api/action',query:{},get:()=> 'Bearer token'},res);assert.equal(status,404);
});
run('restore uses current archive after account cleanup scrubs references during media work',async()=>{
 await m.requestAction(db,'staff',input('remove'));await m.processAction(db,auth,bucket,'op');
 await m.requestAction(db,'staff',input('restore','restore'));
 const raced={...bucket,file:name=>({...bucket.file(name),setMetadata:async value=>{
   metadata=value;await db.doc(`moderationContent/${m.key('posts/post')}`).update({'original.likedBy':[]});
 }})};
 await m.processAction(db,auth,raced,'restore');assert.deepEqual((await db.doc('posts/post').get()).data().likedBy,[]);
});
