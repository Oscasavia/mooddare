const {test}=require('node:test');
const assert=require('node:assert/strict');
const {buildWrites}=require('./publish.cjs');
const catalog=require('../../content/dares.json');
const documents=()=>Object.entries(catalog.moods).filter(([name])=>!['Christmas','New Year'].includes(name)).map(([name,entry])=>({name:`projects/demo/databases/(default)/documents/dares/${name}`,updateTime:'2026-09-29T12:00:00Z',fields:{moodName:{stringValue:name},pack:{stringValue:entry.pack},isLocked:{booleanValue:entry.pack!=='basic'},dareList:{arrayValue:{values:[{stringValue:'Old prompt'}]}}}}));
test('publishing updates only prompt arrays and requires the version read',()=>{
 const docs=documents(),before=structuredClone(docs),plan=buildWrites(docs,catalog);
 assert.equal(plan.writes.length,27);
 plan.writes.forEach((write,i)=>{
  assert.equal(write.update.name,docs[i].name);
  assert.deepEqual(Object.keys(write.update.fields),['dareList']);
  assert.deepEqual(write.updateMask.fieldPaths,['dareList']);
  assert.deepEqual(write.currentDocument,{updateTime:docs[i].updateTime});
  const mood=docs[i].fields.moodName.stringValue;
  assert.deepEqual(write.update.fields.dareList.arrayValue.values.map(v=>v.stringValue),catalog.moods[mood].dares);
 });
 assert.deepEqual(docs,before);
 assert.equal(plan.summary.filter(m=>m.locked).length,15);
});
test('unchanged catalog produces no writes',()=>{
 const docs=documents();
 for(const doc of docs)doc.fields.dareList.arrayValue.values=catalog.moods[doc.fields.moodName.stringValue].dares.map(stringValue=>({stringValue}));
 assert.deepEqual(buildWrites(docs,catalog).writes,[]);
});
test('membership, pack and concurrency changes require review',()=>{
 for(const change of [docs=>docs.pop(),docs=>docs.push(docs[0]),docs=>delete docs[0].updateTime,docs=>docs[0].fields.pack.stringValue='epic',docs=>docs[0].fields.moodName.stringValue='Unknown']){
  const docs=documents();change(docs);assert.throws(()=>buildWrites(docs,catalog));
 }
});
