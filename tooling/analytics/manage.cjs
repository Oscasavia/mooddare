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
 for(const group of ['analyticsReceipts','analyticsState'])await db.collectionGroup(group).where('expiresAt','<=',Timestamp.now()).limit(1).get();
 const snapshot=await require('../../functions/analytics').snapshot(db,30);
 console.log(JSON.stringify({status:snapshot.status,trackingStartedAt:snapshot.trackingStartedAt,metrics:snapshot.metrics,moodRows:snapshot.moods?.length,communityDareRows:snapshot.communityDares?.length},null,2));
})().catch(e=>{console.error('Analytics operation failed:',e.code||e.name);process.exitCode=1;});
