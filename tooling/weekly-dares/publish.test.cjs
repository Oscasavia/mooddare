const {test} = require('node:test');
const assert = require('node:assert/strict');
const {buildSchedule, fieldsFor} = require('./publish.cjs');
test('52 contiguous Monday UTC weeks, bounded prompts, unique IDs, stable overlapping schedules', () => {
  const weeks = buildSchedule(new Date('2026-09-23T16:00:00Z'));
  assert.equal(weeks.length,52); assert.equal(new Set(weeks.map(w=>w.id)).size,52);
  assert.equal(weeks[0].id,'2026-09-21'); assert.equal(weeks[0].title,'A little joy');
  weeks.forEach((week,index) => {
    assert.equal(new Date(week.startsAt).getUTCDay(),1);
    assert.equal(Date.parse(week.endsAt)-Date.parse(week.startsAt),7*86400000);
    assert.ok(week.dareText.length > 0 && week.dareText.length <= 500);
    if(index) assert.equal(week.startsAt,weeks[index-1].endsAt);
    assert.equal(fieldsFor(week).startsAt.timestampValue,week.startsAt);
    assert.equal(fieldsFor(week).dareText.stringValue,week.dareText);
    assert.equal(fieldsFor(week).id,undefined);
  });
  assert.deepEqual(buildSchedule(new Date('2026-09-28T00:00:00Z'),1)[0],weeks[1]);
});
test('invalid ranges rejected and year/time-zone boundaries are deterministic', () => {
  assert.throws(()=>buildSchedule(new Date('invalid')));
  for(const weeks of [0,-1,105,1.5]) assert.throws(()=>buildSchedule(new Date(),weeks));
  assert.equal(buildSchedule(new Date('2026-09-27T20:00:00-05:00'),1)[0].id,'2026-09-28');
  assert.equal(buildSchedule(new Date('2027-01-01'),1)[0].id,'2026-12-28');
});
