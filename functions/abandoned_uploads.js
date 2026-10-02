'use strict';
const {randomUUID,createHash}=require('node:crypto');
const {FieldValue}=require('firebase-admin/firestore');
const {enqueueDeletion}=require('./account_deletion');
const hash=value=>createHash('sha256').update(value).digest('hex');
const GRACE_MS=7*86400000;
// A transaction fences old post IDs before removing media. A retry uses the
// stable replacement ID in this marker, so late commits cannot publish a broken
// URL and repeated client retries cannot create duplicate moments.
async function reclaimUpload(db,auth,file,{now=Date.now()}={}) {
  const match=/^posts\/([A-Za-z0-9_-]{1,128})\/([A-Za-z0-9_-]{1,128})\.(jpg|mp4)$/.exec(file.name);
  if(!match)return false;
  const [,uid,id]=match;
  const [metadata]=await file.getMetadata().catch(e=>{if(e.code===404)return [{}];throw e;});
  const uploaded=Date.parse(metadata.timeCreated||'');
  if(!Number.isFinite(uploaded)||now-uploaded<GRACE_MS)return false;
  try{await auth.getUser(uid);}catch(error){if(error.code!=='auth/user-not-found')throw error;await enqueueDeletion(db,uid,{now});return false;}
  const allowed=await db.runTransaction(async tx=>{
    const marker=db.doc(`moderationPosts/${id}`);
    const [post,archive,old,deleting]=await tx.getAll(db.doc(`posts/${id}`),db.doc(`moderationContent/${hash('posts/'+id)}`),marker,db.doc(`accountDeletions/${uid}`));
    if(post.exists||archive.exists||deleting.exists)return false;
    if(old.exists)return old.data().reason==='abandoned-upload'&&old.data().ownerId===uid;
    tx.create(marker,{removed:true,reason:'abandoned-upload',ownerId:uid,replacementPostId:randomUUID(),createdAt:FieldValue.serverTimestamp()});
    return true;
  });
  if(!allowed)return false;
  // Delete only the inspected generation. This also protects a newer object if
  // an upload was already in flight before the rules fence was installed.
  await file.delete({ignoreNotFound:true,ifGenerationMatch:metadata.generation});
  return true;
}
async function sweepUploads(db,auth,bucket,{now=Date.now()}={}) {
  const ref=db.doc('maintenance/uploadSweep');
  const cursor=(await ref.get()).data()?.pageToken;
  const [files,next]=await bucket.getFiles({prefix:'posts/',versions:true,maxResults:200,autoPaginate:false,...(cursor?{pageToken:cursor}:{})});
  for(const file of files)await reclaimUpload(db,auth,file,{now});
  if(next?.pageToken)await ref.set({pageToken:next.pageToken});else await ref.delete();
}
module.exports={reclaimUpload,sweepUploads,GRACE_MS};
