import {test} from 'node:test';
import assert from 'node:assert/strict';
import {validateSnapshot} from './analytics-view.js';
import {loadAnalytics} from './analytics-source.js';
const fresh = () => ({status:'ready',schemaVersion:1,rangeDays:7,generatedAt:'2026-10-05T12:00:00Z',startDate:'2026-09-29T00:00:00Z',endDate:'2026-10-06T00:00:00Z',metrics:{moodSelections:12,communityParticipants:3,communityMoments:5},moods:[{id:'creative',name:'Creative',selections:12},{id:'chill',name:'Chill',selections:0}],communityDares:[{id:'week1',title:'A little wonder',participants:2,moments:3},{id:'week2',title:'Something kind',participants:2,moments:2}]});
test('production adapter loads the selected range through the authenticated API',async()=>{
 const data=fresh();let route;assert.equal(await loadAnalytics({rangeDays:7,api:async r=>{route=r;return data;}}),data);assert.equal(route,'analytics?days=7');
 await assert.rejects(loadAnalytics({rangeDays:30,api:async()=>{throw Error('offline');}}));
});
test('version 2 requires tracking coverage and validated growth metrics',()=>{
 const d={...fresh(),schemaVersion:2,trackingStartedAt:'2026-10-05T00:00:00Z'};
 Object.assign(d.metrics,{signups:2,accountDeletions:1,currentProfiles:3,posts:5,creators:3,likes:8});
 assert.equal(validateSnapshot(d,7),d);d.metrics.signups=-1;assert.throws(()=>validateSnapshot(d,7));d.metrics.signups=2;delete d.trackingStartedAt;assert.throws(()=>validateSnapshot(d,7));
});
test('snapshot accepts unique participants across dares and zero-selection moods',()=>{
 const data=fresh();assert.equal(validateSnapshot(data,7),data);
 assert.equal(data.communityDares.reduce((n,r)=>n+r.participants,0),4);
 assert.equal(data.metrics.communityParticipants,3);
});
test('measured empty data is distinct from disconnected',()=>{
 const data={...fresh(),metrics:{moodSelections:0,communityParticipants:0,communityMoments:0},moods:[],communityDares:[]};
 assert.equal(validateSnapshot(data,7).status,'ready');
 assert.equal(validateSnapshot({status:'not-connected'},7).status,'not-connected');
});
test('rejects unsupported, incomplete, malformed and inconsistent snapshots',()=>{
 const mutations=[
  d=>d.schemaVersion=2,
  d=>d.rangeDays=30,
  d=>d.generatedAt='bad date',
  d=>d.startDate='2026-09-28T00:00:00Z',
  d=>d.metrics.moodSelections=-1,
  d=>d.metrics.communityParticipants=1.5,
  d=>d.metrics.communityParticipants=9,
  d=>d.metrics.communityParticipants=1,
  d=>d.metrics.communityMoments=9,
  d=>d.moods[0].selections=11,
  d=>d.moods[0].selections=Number.MAX_SAFE_INTEGER+1,
  d=>d.moods.push({...d.moods[0]}),
  d=>d.communityDares.push({...d.communityDares[0]}),
  d=>d.communityDares[0].participants=4,
  d=>d.communityDares[0].title='',
  d=>d.moods=null,
 ];
 for(const mutate of mutations){const data=fresh();mutate(data);assert.throws(()=>validateSnapshot(data,7));}
 assert.throws(()=>validateSnapshot(null,7));
});
