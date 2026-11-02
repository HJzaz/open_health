// Exercise the actual renderer's unavailable/learning/ready states and escaping.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('dashboard/web/app.js', 'utf8');
const esc = source.split('\n').find(line => line.startsWith('const esc ='));
const renderer = source.slice(source.indexOf('function overnightStressHtml('), source.indexOf('function renderPersonalInsights('));
const ctx = vm.createContext({});
vm.runInContext(esc + '\n' + renderer, ctx);
assert.equal(ctx.overnightStressHtml(null), '');
const base = {status:'learning',label:'Learning your baseline',date:'2026-10-15',baseline_nights:8,
  message:'8/14 prior nights',method:'Experimental <estimate>',rhr:null,hrv:null};
const learning = ctx.overnightStressHtml(base);
assert(learning.includes('<progress'));
assert(learning.includes('value="8"'));
assert(!learning.includes('baseline NaN'));
assert(learning.includes('&lt;estimate&gt;'));
const ready = ctx.overnightStressHtml({...base,status:'ready',level:'higher',label:'Higher strain pattern',baseline_nights:14,
  rhr:{value:64,baseline:60,unit:'bpm'},hrv:{value:30,baseline:40,unit:'ms'}});
assert(ready.includes('64.0 bpm · baseline 60.0 bpm'));
assert(ready.includes('30.0 ms · baseline 40.0 ms'));
assert(ready.includes('Compared with 14 earlier nights'));
assert(!ready.includes('<progress'));
const stale = ctx.overnightStressHtml({...base,status:'stale',label:'Sync a recent night'});
assert(!stale.includes('<progress'));
assert(stale.includes('not a live stress reading'));
console.log('Stress indicator renderer checks passed');
