// Verify the service role needed by storage.rules' Firestore moderation checks.
// Read-only by default; --apply adds exactly the missing Firebase service role.
const path = require('node:path');
const {execFileSync} = require('node:child_process');
const role = 'roles/firebaserules.firestoreServiceAgent';
const member = 'serviceAccount:service-1010705723283@gcp-sa-firebasestorage.iam.gserviceaccount.com';
function planPolicy(policy) {
  const next = structuredClone(policy);
  const binding = (next.bindings || []).find(b => b.role === role && !b.condition);
  if (binding?.members.includes(member)) return {changed: false, policy: next};
  if (!next.etag) throw Error('Refusing an IAM change without a concurrency version.');
  if (binding) binding.members.push(member);
  else (next.bindings ||= []).push({role, members: [member]});
  return {changed: true, policy: next};
}
async function main() {
  const cli = path.join(execFileSync('npm', ['root', '-g'], {encoding: 'utf8'}).trim(), 'firebase-tools', 'lib');
  const {requireAuth} = require(path.join(cli, 'requireAuth'));
  const {getGlobalDefaultAccount} = require(path.join(cli, 'auth'));
  const {Client} = require(path.join(cli, 'apiv2'));
  await requireAuth({project: 'mooddare', nonInteractive: true, ...getGlobalDefaultAccount()});
  const api = new Client({urlPrefix: 'https://cloudresourcemanager.googleapis.com', apiVersion: 'v1'});
  const read = async () => (await api.post('projects/mooddare:getIamPolicy', {options: {requestedPolicyVersion: 3}})).body;
  const plan = planPolicy(await read());
  if (!plan.changed) return console.log('Storage cross-service permission is configured.');
  console.log(`Missing role: ${role} for ${member}`);
  if (!process.argv.includes('--apply')) {
    process.exitCode = 1;
    return;
  }
  await api.post('projects/mooddare:setIamPolicy', {policy: plan.policy});
  if (planPolicy(await read()).changed) throw Error('Permission verification failed.');
  console.log('Added and verified the Firebase Storage cross-service role. Existing bindings preserved.');
}
module.exports = {planPolicy, role, member};
if (require.main === module) main().catch(error => {console.error(error.message); process.exitCode = 1;});
