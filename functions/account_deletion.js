'use strict';
const {randomUUID,createHash}=require('node:crypto');
const {FieldValue,FieldPath,Timestamp}=require('firebase-admin/firestore');
const {HttpsError}=require('firebase-functions/v2/https');
const hash=value=>createHash('sha256').update(value).digest('hex');
const stamp=()=>FieldValue.serverTimestamp();
const validUid=uid=>typeof uid==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(uid);
const HOLD_MS=2*60*60*1000; // Expired ID tokens cannot recreate an erased account.
const LEASE_MS=9*60*1000;

async function enqueueDeletion(db,uid,{now=Date.now()}={}) {
  if(!validUid(uid)) throw new HttpsError('invalid-argument','Invalid account.');
  const ref=db.doc(`accountDeletions/${uid}`);
  await db.runTransaction(async tx=>{
    if((await tx.get(ref)).exists)return;
    tx.create(ref,{stage:0,status:'pending',requestedAt:Timestamp.fromMillis(now),nextAttemptAt:Timestamp.fromMillis(now),attempts:0});
    tx.set(db.doc(`accountRestrictions/${uid}`),{status:'deleting'});
  });
  return ref;
}
async function requestDeletion(db,request,{now=Date.now()}={}) {
  const uid=request.auth?.uid;
  if(!validUid(uid))throw new HttpsError('unauthenticated','Sign in to delete your account.');
  // The UID is ALWAYS taken from the verified token, never a request parameter.
  if(request.data?.confirm!=='DELETE'||request.data.expectedUid!==uid||Object.keys(request.data).some(k=>!['confirm','expectedUid'].includes(k)))throw new HttpsError('invalid-argument','Confirm account deletion for the signed-in account.');
  const time=request.auth.token?.auth_time;
  if(!Number.isFinite(time)||now/1000-time>300||time>now/1000+60)throw new HttpsError('failed-precondition','Verify your account again.',{reason:'requires-recent-login'});
  await enqueueDeletion(db,uid,{now});
  return {accepted:true};
}
const missingAuth=e=>e.code==='auth/user-not-found';
async function noUserError(action){try{return await action();}catch(e){if(!missingAuth(e))throw e;}}
async function clearQuery(db,query,check) {
  while(true){check();const page=await query.limit(100).get();if(page.empty)return;
    const batch=db.batch();for(const d of page.docs)batch.delete(d.ref);await batch.commit();}
}
async function scrubLikes(db,query,field,uid,check) {
  while(true){check();const page=await query.limit(100).get();if(page.empty)return;
    await Promise.all(page.docs.map(d=>db.runTransaction(async tx=>{const live=await tx.get(d.ref);if(live.exists)tx.update(d.ref,{[field]:FieldValue.arrayRemove(uid)});})));}
}
async function eraseReport(db,doc,check) {
  await eachQuery(db.collection('moderationActions').where('reportId','==',doc.id),d=>eraseAction(db,d),check);
  await db.doc(`moderationReviews/${doc.id}`).delete();await doc.ref.delete();
}
async function eraseAction(db,doc) {
  const data=doc.data();
  if(data.lockPath)await db.doc(`moderationLocks/${hash(data.lockPath)}`).delete();
  if(data.reportId)await db.doc(`moderationReviews/${data.reportId}`).delete();
  await doc.ref.delete();
}
async function eraseReports(db,query,check) {
  while(true){check();const page=await query.limit(50).get();if(page.empty)return;
    for(const doc of page.docs)await eraseReport(db,doc,check);}
}
async function eraseTarget(db,path,check) {
  // Also cleans reports, actions, locks and archived copies of this exact target.
  await eachQuery(db.collection('moderationActions').where('path','==',path),d=>eraseAction(db,d),check);
  await db.doc(`moderationContent/${hash(path)}`).delete();
  await db.doc(`moderationLocks/${hash(path)}`).delete();
}
async function erasePost(db,id,check) {
  const ref=db.doc(`posts/${id}`);
  await db.runTransaction(async tx=>{if((await tx.get(ref)).exists)tx.update(ref,{deleting:true});});
  await eraseReports(db,db.collection('reports').where('postId','==',id),check);
  await clearQuery(db,db.collectionGroup('notifications').where('postId','==',id),check);
  // Removed comments may exist only in the private moderation archive.
  for(const collection of ['moderationContent','moderationActions']){
    const query=db.collection(collection).where('path','>=',`${ref.path}/`).where('path','<',`${ref.path}0`);
    while(true){check();const page=await query.limit(50).get();if(page.empty)break;
      for(const doc of page.docs){const path=doc.data().path;if(path)await db.doc(`moderationLocks/${hash(path)}`).delete();if(collection==='moderationActions')await eraseAction(db,doc);else await doc.ref.delete();}}
  }
  await eraseTarget(db,ref.path,check);
  await db.recursiveDelete(ref);
  await db.doc(`moderationPosts/${id}`).delete();
}
async function eraseComment(db,doc,check) {
  const parts=doc.ref.path.split('/'),post=parts[1];
  await eraseReports(db,db.collection('reports').where('postId','==',post).where('commentId','==',doc.id),check);
  await clearQuery(db,db.collectionGroup('notifications').where('postId','==',post).where('commentId','==',doc.id),check);
  await eraseTarget(db,doc.ref.path,check);await db.recursiveDelete(doc.ref);
}
async function eachQuery(query,action,check) {
  while(true){check();const page=await query.limit(30).get();if(page.empty)return;for(const doc of page.docs){check();await action(doc);}}
}
async function eraseStorage(bucket,uid,check) {
  for(const prefix of [`posts/${uid}/`,`profile_pictures/${uid}/`]) {
    while(true){check();const [files]=await bucket.getFiles({prefix,maxResults:100,autoPaginate:false,versions:true});if(!files.length)break;
      for(const file of files){check();await file.delete({ignoreNotFound:true});}}
  }
  // Historical avatars used the exact UID as an object name.
  await bucket.file(`profile_pictures/${uid}`).delete({ignoreNotFound:true});
}
function stages(db,auth,bucket,uid,check) {
  const q=(collection,field)=>db.collection(collection).where(field,'==',uid);
  const g=(collection,field)=>db.collectionGroup(collection).where(field,'==',uid);
  return [
    async()=>{await noUserError(()=>auth.updateUser(uid,{disabled:true}));await noUserError(()=>auth.revokeRefreshTokens(uid));},
    async()=>eachQuery(q('posts','authorId'),d=>erasePost(db,d.id,check),check),
    async()=>eachQuery(db.collection('moderationContent').where('original.authorId','==',uid),async d=>{
      const path=d.data().path;
      if(/^posts\/[^/]+$/.test(path))await erasePost(db,path.split('/')[1],check);
      else if(/^posts\/[^/]+\/(comments|replies)\/[^/]+$/.test(path))await eraseComment(db,{id:path.split('/').at(-1),ref:db.doc(path)},check);
      await d.ref.delete();
    },check),
    async()=>eachQuery(g('comments','authorId'),async d=>{
      // Mark the parent before removing its thread so late replies are denied.
      await db.runTransaction(async tx=>{if((await tx.get(d.ref)).exists)tx.update(d.ref,{deleting:true});});
      await eachQuery(d.ref.parent.parent.collection('replies').where('parentId','==',d.id),r=>eraseComment(db,r,check),check);
      await eraseComment(db,d,check);
    },check),
    async()=>eachQuery(g('replies','authorId'),d=>eraseComment(db,d,check),check),
    async()=>eachQuery(g('replies','rootAuthorId'),d=>eraseComment(db,d,check),check),
    async()=>eachQuery(g('replies','replyToAuthorId'),d=>db.runTransaction(async tx=>{
      if((await tx.get(d.ref)).exists)tx.update(d.ref,{replyToAuthorId:FieldValue.delete(),replyToId:FieldValue.delete()});
    }),check),
    ...['posts','comments','replies'].map(c=>()=>scrubLikes(db,(c==='posts'?db.collection(c):db.collectionGroup(c)).where('likedBy','array-contains',uid),'likedBy',uid,check)),
    async()=>scrubLikes(db,db.collection('moderationContent').where('original.likedBy','array-contains',uid),'original.likedBy',uid,check),
    async()=>eachQuery(db.collection('moderationContent').where('original.replyToAuthorId','==',uid),d=>d.ref.update({'original.replyToAuthorId':FieldValue.delete(),'original.replyToId':FieldValue.delete()}),check),
    async()=>eachQuery(db.collection('moderationContent').where('original.rootAuthorId','==',uid),async d=>{const path=d.data().path;await eraseComment(db,{id:path.split('/').at(-1),ref:db.doc(path)},check);await d.ref.delete();},check),
    ...['senderId','recipientId'].map(f=>()=>clearQuery(db,q('dareInvites',f),check)),
    ...['reporterId','userId'].map(f=>()=>eraseReports(db,q('reports',f),check)),
    async()=>clearQuery(db,q('pushTokens','uid'),check),
    async()=>{await clearQuery(db,g('notifications','actorId'),check);await clearQuery(db,g('feedHistory','authorId'),check);},
    async()=>clearQuery(db,g('notifications','recipientId'),check),
    async()=>clearQuery(db,q('usernames','uid'),check),
    async()=>clearQuery(db,q('moderationPosts','ownerId'),check),
    ...['userId','staff'].map(f=>()=>eachQuery(q('moderationActions',f),d=>eraseAction(db,d),check)),
    async()=>clearQuery(db,q('moderationReviews','staff'),check),
    async()=>{await db.doc(`moderationStaff/${uid}`).delete();await db.doc(`moderationLocks/${hash('users/'+uid)}`).delete();},
    async()=>eachQuery(q('notificationCampaigns','cursor'),d=>d.ref.update({cursor:FieldValue.delete()}),check),
    // Legacy relationship docs store the other UID in their ID, not a field.
    // A checkpointed scan also finds broken pairs left by old app versions.
    ...['followers','following','blocked'].map(c=>async(job,save)=>{
      let cursor=job.cursor;
      while(true){check();let query=db.collectionGroup(c).orderBy(FieldPath.documentId()).limit(150);if(cursor)query=query.startAfter(db.doc(cursor));
        const page=await query.get();if(page.empty)return;
        const batch=db.batch();for(const d of page.docs)if(d.id===uid||d.ref.path.split('/')[1]===uid)batch.delete(d.ref);
        await batch.commit();cursor=page.docs.at(-1).ref.path;await save({cursor});}
    }),
    async()=>db.recursiveDelete(db.doc(`users/${uid}`)),
    async()=>db.doc('maintenance/uploadSweep').delete(),
    async()=>eraseStorage(bucket,uid,check),
    async()=>noUserError(()=>auth.deleteUser(uid)),
  ];
}
async function processDeletion(db,auth,bucket,uid,{now=()=>Date.now(),budgetMs=240000,afterStage=async()=>{}}={}) {
  if(!validUid(uid))throw new HttpsError('invalid-argument','Invalid account.');
  const ref=db.doc(`accountDeletions/${uid}`),lease=randomUUID(),start=now();
  const job=await db.runTransaction(async tx=>{
    const d=(await tx.get(ref)).data();if(!d||d.nextAttemptAt?.toMillis()>start||d.leaseUntil?.toMillis()>start)return null;
    tx.update(ref,{lease,leaseUntil:Timestamp.fromMillis(start+LEASE_MS),status:'processing',attempts:FieldValue.increment(1)});return d;
  });
  if(!job)return false;
  const check=()=>{if(now()-start>budgetMs)throw Object.assign(new Error('Yield cleanup'),{code:'cleanup-yield'});};
  const save=async values=>db.runTransaction(async tx=>{if((await tx.get(ref)).data()?.lease!==lease)throw Error('Deletion lease changed');tx.update(ref,values);});
  try {
    const steps=stages(db,auth,bucket,uid,check);
    // After the token/in-flight-upload grace period, sweep everything once more.
    if(job.status==='complete'){job.stage=0;job.cursor=null;job.finalSweep=true;await save({stage:0,cursor:FieldValue.delete(),finalSweep:true});}
    for(let stage=job.stage||0;stage<steps.length;stage++){
      check();await steps[stage](job,save);await afterStage(stage);
      job.cursor=null;await save({stage:stage+1,cursor:FieldValue.delete()});
    }
    if(job.finalSweep) {const batch=db.batch();batch.delete(ref);batch.delete(db.doc(`accountRestrictions/${uid}`));await batch.commit();return true;}
    await save({status:'complete',completedAt:stamp(),nextAttemptAt:Timestamp.fromMillis(now()+HOLD_MS),leaseUntil:Timestamp.fromMillis(0),lease:FieldValue.delete()});
    return true;
  }catch(error){
    await save({status:'retry',nextAttemptAt:Timestamp.fromMillis(now()+60000),leaseUntil:Timestamp.fromMillis(0),lease:FieldValue.delete(),lastError:error.code==='cleanup-yield'?'continuing':'retry-required'});
    throw error;
  }
}
async function recoverDeletions(db,auth,bucket,{now=()=>Date.now()}={}) {
  const page=await db.collection('accountDeletions').where('nextAttemptAt','<=',Timestamp.fromMillis(now())).orderBy('nextAttemptAt').limit(5).get();
  for(const doc of page.docs){try{await processDeletion(db,auth,bucket,doc.id,{now,budgetMs:60000});}catch(e){console.warn('Account cleanup scheduled for retry',{code:e.code||'cleanup-error'});}}
}
module.exports={requestDeletion,enqueueDeletion,processDeletion,recoverDeletions,eraseStorage,HOLD_MS};
