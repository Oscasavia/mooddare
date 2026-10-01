const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const {planMigration} = require('./migrate.cjs');
const s = stringValue => ({stringValue});
function fixture() {return {users:[{name:'projects/demo/databases/(default)/documents/users/alice',updateTime:'2026-09-30T00:00:00Z',fields:{id:s('alice'),name:s('Alice'),username:s('Alice_1'),username_lower:s('alice_1'),email:s('private@example.invalid'),bio:s('Hello'),photoUrl:s('https://example.invalid/a.jpg'),createdAt:{timestampValue:'2026-01-01T00:00:00Z'}}}],usernames:[{name:'projects/demo/databases/(default)/documents/usernames/alice_1',fields:{uid:s('alice')}}]};}
test('migration removes only public email with an optimistic precondition and leaves input intact',()=>{
 const data=fixture(), before=structuredClone(data), {writes,summary}=planMigration(data);
 assert.deepEqual(data,before);assert.equal(writes.length,1);assert.deepEqual(writes[0].updateMask,{fieldPaths:['email']});assert.deepEqual(writes[0].update.fields,{});assert.equal(writes[0].currentDocument.updateTime,data.users[0].updateTime);assert.equal(summary.publicEmailsToRemove,1);
 delete data.users[0].fields.email;assert.equal(planMigration(data).writes.length,0);
});
test('conflicts, unknown fields and malformed profiles stop without renaming or deleting claims',()=>{
 const changes=[d=>d.users[0].fields.id=s('other'),d=>delete d.users[0].updateTime,d=>delete d.users[0].fields.createdAt,d=>d.users[0].fields.admin={booleanValue:true},d=>d.users[0].fields.username=s('___'),d=>d.users[0].fields.username_lower=s('wrong'),d=>d.usernames[0].fields.uid=s('other'),d=>d.usernames=[],d=>d.users.push(structuredClone(d.users[0])),d=>d.users[0].fields.name=s('x'.repeat(51)),d=>d.users[0].fields.bio=s('x'.repeat(161)),d=>d.users[0].fields.photoUrl=s('http://unsafe.invalid'),d=>d.users[0].fields.coverColor=s('unknown'),d=>d.usernames.push({name:'usernames/orphan',fields:{uid:s('missing')}})];
 for(const change of changes){const data=fixture();change(data);assert.throws(()=>planMigration(data));}
});
test('new profiles awaiting username selection remain valid and optional nulls are preserved',()=>{
 const data=fixture();data.usernames=[];for(const key of ['username','username_lower','email'])delete data.users[0].fields[key];data.users[0].fields.name={nullValue:null};data.users[0].fields.photoUrl={nullValue:null};assert.equal(planMigration(data).writes.length,0);
});
test('compatibility deployment cannot restore broad legacy access',()=>{
 const root=require('node:path').resolve(__dirname,'../..');
 assert.equal(JSON.parse(fs.readFileSync(root+'/firebase.compat.json')).firestore.rules,'firestore.rules');
 assert.equal(fs.readFileSync(root+'/firestore.compat.rules','utf8'),fs.readFileSync(root+'/firestore.rules','utf8'));
});
