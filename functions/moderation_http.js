'use strict';
const m=require('./moderation');
function handler(db,auth,bucket){return async(req,res)=>{
  res.set('Cache-Control','private, no-store');res.set('X-Content-Type-Options','nosniff');
  try{
    const write=req.method==='POST';
    if(!['GET','POST'].includes(req.method))return res.status(405).end();
    const staff=await m.authorize(db,auth,req.get('Authorization'),write);
    const route=req.path.split('/').filter(Boolean).at(-1);
    if(!write){
      if(route==='session')return res.json({uid:staff});
      if(route==='reports')return res.json(await m.list(db,'reports',req.query.cursor));
      if(route==='analytics')return res.json(await require('./analytics').snapshot(db,req.query.days));
      if(route==='history')return res.json(await m.list(db,'moderationActions',req.query.cursor));
      if(route==='detail')return res.json(await m.detail(db,req.query.id));
      if(route==='media'){const {file,type}=await m.media(db,bucket,req.query.id);res.type(type);const stream=file.createReadStream();stream.on('error',()=>res.destroy());stream.pipe(res);return;}
    }else if(route==='action'){
      const op=await m.requestAction(db,staff,req.body);
      await m.processAction(db,auth,bucket,op);
      return res.json({operationId:op,status:(await db.doc(`moderationActions/${op}`).get()).data().status});
    }else if(route==='retry'){
      await m.processAction(db,auth,bucket,req.body.operationId);return res.json({ok:true});
    }
    res.status(404).json({error:'Not found.'});
  }catch(e){if(!e.status)console.error('Moderation operation failed',e.code||e.name);res.status(e.status||500).json({error:e.status?e.message:'The action could not finish. Check History and retry.'});}
};}
module.exports={handler};
