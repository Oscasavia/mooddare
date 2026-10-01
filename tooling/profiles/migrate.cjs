// Read-only by default. Never logs profile contents or authentication credentials.
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { execFileSync } = require('node:child_process');
const allowed = new Set(['id','name','username','username_lower','username_normalized','photoUrl','bio','createdAt','updatedAt','coverColor']);
const colors = ['lavender','midnight','rose','sage','ocean','sunset'];
const validName = value => typeof value === 'string' && /^[a-zA-Z0-9_]{3,20}$/.test(value) && /[a-zA-Z]/.test(value) && /^[a-zA-Z0-9].*[a-zA-Z0-9]$/.test(value) && !value.includes('__');
function planMigration({users, usernames}) {
  const claims = new Map(usernames.map(d => [d.name.split('/').pop(), d]));
  const seen = new Set(), owners = new Set(users.map(d => d.name.split('/').pop()));
  const writes = [];
  for (const doc of users) {
    const f = doc.fields || {}, uid = doc.name.split('/').pop();
    if (!doc.updateTime || f.id?.stringValue !== uid || !f.createdAt?.timestampValue) throw Error('Profile identity or creation metadata needs manual review.');
    if (Object.keys(f).some(k => !allowed.has(k) && k !== 'email')) throw Error('Unexpected profile fields need private review.');
    for (const [key,max] of [['name',50],['bio',160]]) {
      if (f[key] && !('nullValue' in f[key]) && (typeof f[key].stringValue !== 'string' || [...f[key].stringValue].length > max)) throw Error('Profile text needs manual review.');
    }
    if (f.photoUrl && !('nullValue' in f.photoUrl) && (typeof f.photoUrl.stringValue !== 'string' || !/^https:\/\//.test(f.photoUrl.stringValue) || f.photoUrl.stringValue.length > 2048)) throw Error('Profile photo URL needs manual review.');
    if (f.coverColor && !colors.includes(f.coverColor.stringValue)) throw Error('Unknown profile cover needs review.');
    const username = f.username?.stringValue;
    if (f.username && !('nullValue' in f.username)) {
      if (!validName(username)) throw Error('Legacy username needs review; no automatic rename.');
      const lower = username.toLowerCase();
      if (seen.has(lower)) throw Error('Conflicting usernames need review; no reservations changed.');
      seen.add(lower);
      if (f.username_lower?.stringValue !== lower || claims.get(lower)?.fields?.uid?.stringValue !== uid) throw Error('Username reservation mismatch needs review.');
    } else if (f.username_lower || f.username_normalized) throw Error('Unclaimed username metadata needs review.');
    if (f.email) {
      // Mask deletes only the legacy public email, preserving every other field.
      writes.push({update:{name:doc.name,fields:{}},updateMask:{fieldPaths:['email']},currentDocument:{updateTime:doc.updateTime}});
    }
  }
  for (const claim of usernames) {
    const name = claim.name.split('/').pop(), f = claim.fields || {};
    const profile = users.find(d => d.name.split('/').pop() === f.uid?.stringValue);
    if (Object.keys(f).length !== 1 || !owners.has(f.uid?.stringValue) || profile?.fields?.username_lower?.stringValue !== name) throw Error('Orphaned or inconsistent username reservation needs review.');
  }
  return {writes, summary:{profiles:users.length, reservations:usernames.length, publicEmailsToRemove:writes.length}};
}
async function main() {
  const cli = path.join(execFileSync('npm',['root','-g'],{encoding:'utf8'}).trim(),'firebase-tools','lib');
  const {requireAuth} = require(path.join(cli,'requireAuth'));
  const {getGlobalDefaultAccount} = require(path.join(cli,'auth'));
  const {Client} = require(path.join(cli,'apiv2'));
  await requireAuth({project:'mooddare',nonInteractive:true,...getGlobalDefaultAccount()});
  const api = new Client({urlPrefix:'https://firestore.googleapis.com',apiVersion:'v1'});
  const base = 'projects/mooddare/databases/(default)/documents';
  async function read() {
    const result = {};
    for (const collection of ['users','usernames']) {
      result[collection] = [];
      let pageToken;
      do {
        const response = (await api.get(`${base}/${collection}`,{queryParams:{pageSize:100,...(pageToken ? {pageToken} : {})}})).body;
        result[collection].push(...response.documents || []);
        pageToken = response.nextPageToken;
      } while (pageToken);
    }
    return result;
  }
  const snapshot = await read(), plan = planMigration(snapshot);
  const apply = process.argv.includes('--apply');
  console.log(JSON.stringify({dryRun:!apply,...plan.summary}));
  if (!apply || !plan.writes.length) return;
  if (plan.writes.length > 400) throw Error('Migration exceeds reviewed atomic batch size.');
  const backup = path.join(os.tmpdir(),`mooddare-profiles-backup-${Date.now()}.json`);
  fs.writeFileSync(backup,JSON.stringify(snapshot),{mode:0o600,flag:'wx'});
  await api.post(`${base}:commit`,{writes:plan.writes});
  if (planMigration(await read()).writes.length) throw Error('Verification failed; keep the backup for review.');
  console.log(`Verified public-email removal. Private backup: ${backup}`);
}
module.exports = {planMigration};
if (require.main === module) main().catch(() => {console.error('Profile migration stopped. Review privately; no credentials or profile contents are logged.');process.exitCode = 1;});
