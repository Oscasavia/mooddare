// Uses the owner's existing Firebase CLI login; never logs credentials or user data.
// node tooling/analytics/manage.cjs [--enable]
const fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const backendRequire=require('node:module').createRequire(path.resolve(__dirname,'../../functions/package.json'));
const {Firestore,Timestamp}=backendRequire('@google-cloud/firestore');
const {GoogleAuth,OAuth2Client}=backendRequire('google-auth-library');
const tokens=JSON.parse(fs.readFileSync(path.join(os.homedir(),'.config/configstore/firebase-tools.json'),'utf8')).tokens;
const client=new OAuth2Client();client.setCredentials({access_token:tokens.access_token});
const db=new Firestore({projectId:'mooddare',auth:new GoogleAuth({authClient:client})});
(async()=>{
 if(process.argv.includes('--enable'))await db.runTransaction(async tx=>{const ref=db.doc('analyticsConfig/current');if(!(await tx.get(ref)).exists)tx.create(ref,{startedAt:Timestamp.now()});});
 if(process.argv.includes('--enable-product'))await db.runTransaction(async tx=>{const ref=db.doc('analyticsConfig/current'),old=(await tx.get(ref)).data()||{};tx.set(ref,{productStartedAt:old.productStartedAt||Timestamp.now(),trafficSalt:old.trafficSalt||require('node:crypto').randomBytes(32).toString('hex'),webVideoIds:[...new Set([...(old.webVideoIds||[]),'launch-2026-10'])]},{merge:true});});
 for(const group of ['analyticsReceipts','analyticsState'])await db.collectionGroup(group).where('expiresAt','<=',Timestamp.now()).limit(1).get();
 const snapshot=await require('../../functions/analytics').snapshot(db,30,Date.now(),process.argv.includes('--development')?'development':'production');
 console.log(JSON.stringify({status:snapshot.status,productStartedAt:snapshot.product?.startedAt,active:snapshot.product?.active,events:snapshot.product?.app.events,websiteEvents:snapshot.product?.website.events,trackingStartedAt:snapshot.trackingStartedAt,metrics:snapshot.metrics,moodRows:snapshot.moods?.length,communityDareRows:snapshot.communityDares?.length},null,2));
})().catch(e=>{console.error('Analytics operation failed:',e.code||e.name);process.exitCode=1;});
