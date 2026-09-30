const {test} = require('node:test');
const assert = require('node:assert/strict');
const {planPolicy, role, member} = require('./check-access.cjs');
test('adds only required service binding, preserves etag and conditional roles', () => {
 const input = {version:3, etag:'version', bindings:[{role:'roles/viewer',members:['user:owner@example.com']},{role,members:['serviceAccount:other'],condition:{expression:'true',title:'existing'}}]};
 const before = structuredClone(input), plan = planPolicy(input);
 assert.equal(plan.changed,true);
 assert.deepEqual(plan.policy,{...input,bindings:[...input.bindings,{role,members:[member]}]});
 assert.deepEqual(input,before);
});
test('existing unconditional binding is extended and subsequent runs are no-ops', () => {
 const plan = planPolicy({etag:'version',bindings:[{role,members:['serviceAccount:other']}]});
 assert.deepEqual(plan.policy.bindings[0].members,['serviceAccount:other',member]);
 assert.equal(planPolicy(plan.policy).changed,false);
});
test('missing concurrency version prevents mutation', () => assert.throws(() => planPolicy({bindings:[]})));
