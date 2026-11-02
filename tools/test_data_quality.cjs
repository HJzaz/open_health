const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('dashboard/web/app.js','utf8');
const esc = source.split('\n').find(l=>l.startsWith('const esc ='));
const renderer=source.slice(source.indexOf('function dataQualityHtml('),source.indexOf('function renderDevice('));
const ctx=vm.createContext({});vm.runInContext(esc+'\n'+renderer,ctx);
assert.equal(ctx.dataQualityHtml(null),'');
const q={generated_at:100000,scope:'Saved data <only>',untrusted_clock_packets:3,
 battery:{points_per_day:null,net_drop_points:null,span_hours:1,samples:2,message:'Need more history',method:'No polling',end_at:null},
 coverage:{recorded_nights:1,complete_staging_nights:0,candidate_overlap_bins:0,message:'Bins are not minutes',next_step:'Needs review',signals:[{title:'HRV',bins:4,outside_sleep_bins:2}]}};
let html=ctx.dataQualityHtml(q);
assert(html.includes('Collecting baseline'));assert(!html.includes('NaN'));
assert(html.includes('4 bins with data'));assert(html.includes('2 outside recorded sleep'));
assert(html.includes('Saved data &lt;only&gt;'));
q.battery.points_per_day=12;q.battery.net_drop_points=18;q.battery.span_hours=36;
html=ctx.dataQualityHtml(q);assert(html.includes('12.0 percentage points / day'));
const uri=html.match(/href="(data:application\/json[^\"]+)"/)[1];
assert.deepEqual(JSON.parse(decodeURIComponent(uri.split(',')[1])),q);
console.log('Data quality renderer and diagnostic export checks passed');
