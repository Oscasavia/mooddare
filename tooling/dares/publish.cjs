// Dry-run first; updates only dareList on existing moods, with optimistic locks.
const fs=require('node:fs'),path=require('node:path'),os=require('node:os');
const {execFileSync}=require('node:child_process');
const root=path.resolve(__dirname,'../..');
function buildWrites(documents,catalog){
  const writes=[],summary=[],seen=new Set();
  for(const doc of documents){
    const name=doc.fields?.moodName?.stringValue,entry=catalog.moods[name];
    if(!entry)throw Error(`Unreviewed live mood: ${name}`);
    if(seen.has(name))throw Error(`Duplicate live mood: ${name}`);seen.add(name);
    if(doc.fields.pack?.stringValue!==entry.pack)throw Error(`Pack changed for ${name}; review before publishing.`);
    if(!doc.updateTime)throw Error('Missing concurrency version.');
    const old=(doc.fields.dareList?.arrayValue?.values||[]).map(v=>v.stringValue);
    summary.push({mood:name,before:old.length,after:entry.dares.length,locked:doc.fields.isLocked?.booleanValue===true});
    if(JSON.stringify(old)===JSON.stringify(entry.dares))continue;
    writes.push({update:{name:doc.name,fields:{dareList:{arrayValue:{values:entry.dares.map(stringValue=>({stringValue}))}}}},updateMask:{fieldPaths:['dareList']},currentDocument:{updateTime:doc.updateTime}});
  }
  if(seen.size!==Object.keys(catalog.moods).length-2||seen.has('Christmas')||seen.has('New Year'))throw Error('Live catalog membership changed; review before publishing.');
  return {writes,summary};
}
async function main(){
  execFileSync('python3',[path.join(__dirname,'catalog.py')],{stdio:'inherit'});
  const catalog=JSON.parse(fs.readFileSync(path.join(root,'content/dares.json')));
  const cli=path.join(execFileSync('npm',['root','-g'],{encoding:'utf8'}).trim(),'firebase-tools','lib');
  const {requireAuth}=require(path.join(cli,'requireAuth')),{getGlobalDefaultAccount}=require(path.join(cli,'auth')),{Client}=require(path.join(cli,'apiv2'));
  await requireAuth({project:'mooddare',nonInteractive:true,...getGlobalDefaultAccount()});
  const api=new Client({urlPrefix:'https://firestore.googleapis.com',apiVersion:'v1'});
  const base='projects/mooddare/databases/(default)/documents';
  const response=(await api.get(`${base}/dares`,{queryParams:{pageSize:100}})).body;
  if(response.nextPageToken)throw Error('Catalog exceeds the reviewed page; stop and review.');
  const {writes,summary}=buildWrites(response.documents||[],catalog);
  console.log(JSON.stringify({dryRun:!process.argv.includes('--apply'),changed:writes.length,moods:summary},null,2));
  if(process.argv.includes('--apply')&&writes.length){
    const backup=path.join(os.tmpdir(),`mooddare-dares-backup-${Date.now()}.json`);
    fs.writeFileSync(backup,JSON.stringify(response,null,2));
    await api.post(`${base}:commit`,{writes});
    console.log(`Published ${writes.length} reviewed mood lists. Previous version: ${backup}`);
    const verified=(await api.get(`${base}/dares`,{queryParams:{pageSize:100}})).body;
    if(buildWrites(verified.documents,catalog).writes.length)throw Error('Post-publish verification differed.');
    console.log('Verified all live lists; mood IDs, metadata and locks preserved.');
  }
}
module.exports={buildWrites};
if(require.main===module)main().catch(e=>{console.error(e.message);process.exitCode=1;});
