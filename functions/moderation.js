'use strict';
const {createHash,randomUUID}=require('node:crypto');
const {FieldValue,Timestamp}=require('firebase-admin/firestore');
const stamp=()=>FieldValue.serverTimestamp();
const key=path=>createHash('sha256').update(path).digest('hex');
function fail(message,status=400){throw Object.assign(new Error(message),{status});}
function id(value){if(typeof value!=='string'||!value.length||value.length>128||value.includes('/'))fail('Invalid identifier.');return value;}
function target(report){
  if(report.userId)return `users/${id(report.userId)}`;
  const path=`posts/${id(report.postId)}`;
  return report.commentId?`${path}/${report.isReply?'replies':'comments'}/${id(report.commentId)}`:path;
}
function blocked(data,now=Date.now()){return data?.status==='banned'||(data?.status==='suspended'&&data.until?.toMillis()>now);}
async function authorize(db,auth,bearer,write=false){
  if(!bearer?.startsWith('Bearer '))fail('Sign in to continue.',401);
  let token;try{token=await auth.verifyIdToken(bearer.slice(7),true);}catch{fail('Please sign in again.',401);}
  if(!token.email_verified || token.firebase?.sign_in_provider!=='google.com')fail('Use your approved Google account.',403);
  if((await db.doc(`moderationStaff/${token.uid}`).get()).data()?.enabled!==true)fail('This account does not have moderation access.',403);
  if(write&&Date.now()/1000-token.auth_time>3600)fail('Please sign in again before making changes.',401);
  return token.uid;
}
function serialize(value){return JSON.parse(JSON.stringify(value,(_,v)=>v));}
async function list(db,collection,cursor){
  let q=db.collection(collection).orderBy('createdAt','desc').limit(40);
  if(cursor){const last=await db.doc(`${collection}/${id(cursor)}`).get();if(!last.exists)fail('Refresh the queue to continue.',409);q=q.startAfter(last);}
  const docs=await q.get();
  const items=await Promise.all(docs.docs.map(async d=>{
    const data={id:d.id,...serialize(d.data())};
    if(collection==='reports'){
      const review=await db.doc(`moderationReviews/${d.id}`).get();
      data.review=serialize(review.data()||{});
      if(!review.exists || d.data().createdAt?.toMillis()>review.data().updatedAt?.toMillis())data.review.status='pending';
    }
    return data;
  }));
  return {items,cursor:docs.size===40?docs.docs.at(-1).id:null};
}
async function detail(db,reportId){
  const report=await db.doc(`reports/${id(reportId)}`).get();
  if(!report.exists)fail('Report no longer available.',404);
  const path=target(report.data());
  const [live,archive,review]=await Promise.all([db.doc(path).get(),db.doc(`moderationContent/${key(path)}`).get(),db.doc(`moderationReviews/${report.id}`).get()]);
  const data=archive.data()?.removed?archive.data().original:live.data();
  const uid=path.startsWith('users/')?path.split('/')[1]:data?.authorId;
  const profile=uid?await db.doc(`users/${uid}`).get():null;
  const restriction=uid?await db.doc(`accountRestrictions/${uid}`).get():null;
  return {report:{id:report.id,...serialize(report.data())},path,content:data?serialize(data):null,
    removed:archive.data()?.removed===true,review:serialize(review.data()||{}),
    author:profile?.exists?{id:uid,username:profile.data().username||'',name:profile.data().name||''}:null,
    restriction:serialize(restriction?.data()||{})};
}
async function requestAction(db,staff,input){
  const {action,reportId,reason,operationId}=input;
  id(operationId);id(reportId);
  if(!['remove','restore','dismiss','suspend','ban','reinstate'].includes(action))fail('Invalid action.');
  if(typeof reason!=='string'||reason.trim().length<5||reason.length>500)fail('Give a reason of 5–500 characters.');
  const op=db.doc(`moderationActions/${operationId}`);
  return db.runTransaction(async tx=>{
    const previous=await tx.get(op);
    if(previous.exists){const old=previous.data();if(old.staff!==staff||old.reportId!==reportId||old.action!==action||old.reason!==reason.trim())fail('Operation ID already used.',409);return operationId;}
    const report=await tx.get(db.doc(`reports/${reportId}`));if(!report.exists)fail('Report no longer available.',404);
    const path=target(report.data());
    const content=await tx.get(db.doc(path));
    const archive=await tx.get(db.doc(`moderationContent/${key(path)}`));
    const original=archive.data()?.removed?archive.data().original:content.data();
    const userId=report.data().userId||original?.authorId;
    if(['suspend','ban','reinstate'].includes(action)){
      if(!userId)fail('Account not found.',404);
      const protectedAccount=await tx.get(db.doc(`moderationStaff/${userId}`));
      if(userId===staff||protectedAccount.data()?.enabled)fail('Staff accounts cannot be restricted here.',403);
    }
    if(['remove','restore'].includes(action)&&path.startsWith('users/'))fail('Use an account action for this report.');
    if(action==='remove'&&!content.exists&&!archive.data()?.removed)fail('Content already deleted.',404);
    if(action==='restore'&&(!archive.data()?.removed||!original))fail('No removed content to restore.',409);
    if(action==='restore'&&!path.startsWith('users/')){
      const author=await tx.get(db.doc(`users/${original.authorId}`));if(!author.exists)fail('The author has deleted their account.',409);
      if(path.split('/').length>2){const parent=await tx.get(db.doc(path.split('/').slice(0,2).join('/')));if(!parent.exists)fail('Restore the parent post first.',409);}
    }
    const lockPath=['suspend','ban','reinstate'].includes(action)?`users/${userId}`:path;
    const lock=db.doc(`moderationLocks/${key(lockPath)}`),held=await tx.get(lock);
    if(held.exists)fail('An action is still processing. Retry it from History.',409);
    tx.set(lock,{operationId});
    tx.create(op,{staff,reportId,action,reason:reason.trim(),path,userId:userId||null,lockPath,status:'pending',createdAt:stamp(),until:action==='suspend'?Timestamp.fromMillis(Date.now()+7*86400000):null});
    return operationId;
  });
}
function mediaPath(data,path){
  const parts=path.split('/');
  const expected=`posts/${data.authorId}/${parts[1]}.${data.mediaType==='video'?'mp4':'jpg'}`;
  // Never trust a report or stored URL to address an unrelated storage object.
  if(data.mediaPath&&data.mediaPath!==expected)fail('Legacy media path needs manual review.',409);
  return expected;
}
async function processAction(db,auth,bucket,operationId){
  const ref=db.doc(`moderationActions/${id(operationId)}`),lease=randomUUID();
  const claimed=await db.runTransaction(async tx=>{
    const doc=await tx.get(ref),d=doc.data();if(!d||d.status==='done'||(d.leaseUntil?.toMillis()>Date.now()))return null;
    tx.update(ref,{lease,leaseUntil:Timestamp.fromMillis(Date.now()+180000),status:'processing'});return d;
  });
  if(!claimed)return;
  const d=claimed,archive=db.doc(`moderationContent/${key(d.path)}`),live=db.doc(d.path);
  try{
    if(['remove','restore'].includes(d.action)){
      if(d.action==='remove')await db.runTransaction(async tx=>{
        const [a,c]=await tx.getAll(archive,live);if(a.data()?.removed)return;
        if(!c.exists)fail('Content no longer exists.',409);
        tx.set(archive,{original:c.data(),path:d.path,removed:true,updatedAt:stamp()});
        if(d.path.split('/').length===2){tx.set(db.doc(`moderationPosts/${live.id}`),{removed:true});tx.delete(live);}
        else tx.update(live,{text:'This comment was removed by MoodDare.',moderationRemoved:true,likedBy:[]});
      });
      const a=(await archive.get()).data();
      if(!a?.original)fail('Archived content unavailable.',409);
      if(d.action !== 'restore' || a.removed) {
      let restored={...a.original};
      if(d.path.split('/').length===2){
        const file=bucket.file(mediaPath(a.original,d.path));
        if(d.action==='remove'){
          try{await file.setMetadata({metadata:{firebaseStorageDownloadTokens:null},cacheControl:'private, no-store'});}catch(e){if(e.code!==404)throw e;}
        }else{
          const token=randomUUID();
          await file.setMetadata({metadata:{firebaseStorageDownloadTokens:token},cacheControl:'private, no-store'});
          restored.mediaUrl=`https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(file.name)}?alt=media&token=${token}`;
        }
      }
      if(d.action==='restore')await db.runTransaction(async tx=>{
        const [a,owner,c]=await tx.getAll(archive,db.doc(`users/${restored.authorId}`),live);
        if(!a.data()?.removed)return;
        if(!owner.exists)fail('The author has deleted their account.',409);
        if(d.path.split('/').length>2){const parent=await tx.get(db.doc(d.path.split('/').slice(0,2).join('/')));if(!parent.exists||!c.exists)fail('Content or parent was deleted; restoration cancelled.',409);}
        tx.set(live,restored);tx.update(archive,{removed:false,updatedAt:stamp()});
        if(d.path.split('/').length===2)tx.delete(db.doc(`moderationPosts/${live.id}`));
      });
      }
    } else if(['suspend','ban','reinstate'].includes(d.action)){
      await db.doc(`accountRestrictions/${d.userId}`).set({status:d.action==='ban'?'banned':d.action==='suspend'?'suspended':'active',until:d.until,reason:d.reason,updatedAt:stamp()});
      // Firestore/Storage restrictions take effect even for existing ID tokens.
      if(d.action!=='reinstate')await auth.revokeRefreshTokens(d.userId);
    }
    await db.runTransaction(async tx=>{
      const current=await tx.get(ref);if(current.data()?.lease!==lease)fail('Action lease changed.',409);
      tx.update(ref,{status:'done',completedAt:stamp(),leaseUntil:Timestamp.fromMillis(0),error:FieldValue.delete()});
      tx.set(db.doc(`moderationReviews/${d.reportId}`),{status:'resolved',action:d.action,reason:d.reason,staff:d.staff,updatedAt:stamp()});
      tx.delete(db.doc(`moderationLocks/${key(d.lockPath)}`));
    });
  }catch(e){await ref.update({status:'retry',error:'Action incomplete. Retry after checking the content.',leaseUntil:Timestamp.fromMillis(0)});throw e;}
}
async function media(db,bucket,reportId){
  const view=await detail(db,reportId);if(!view.content||view.path.split('/').length!==2||!view.path.startsWith('posts/'))fail('No media available.',404);
  const file=bucket.file(mediaPath(view.content,view.path));
  const [meta]=await file.getMetadata();if(Number(meta.size)>30*1024*1024)fail('Media exceeds the review limit.',413);
  return {file,type:view.content.mediaType==='video'?'video/mp4':'image/jpeg'};
}
module.exports={authorize,list,detail,target,blocked,key,requestAction,processAction,media};
