import {test} from 'node:test';
import assert from 'node:assert/strict';
import {VideoProgress} from '../video-progress.js';
test('video coverage merges overlapping playback and never counts skipped sections',()=>{
 const p=new VideoProgress();p.add(0,10);p.add(5,15);assert.equal(p.watched,15);p.add(90,100);assert.equal(p.watched,25);p.add(0,10);assert.equal(p.watched,25);p.add(15,90);assert.equal(p.watched,100);p.add(10,5);assert.equal(p.watched,100);
});
