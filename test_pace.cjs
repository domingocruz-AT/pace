const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = fs.readFileSync('pace.js','utf8').split("document.querySelectorAll('[data-unit]').forEach(e=>e.onclick")[0];
const context = vm.createContext({Date, Intl, location:{search:''}, document:{body:{classList:{toggle(){}}}},window:{}});
vm.runInContext(source,context);
function evaluate(code){return vm.runInContext(code,context)}
function range(view,date){return JSON.parse(evaluate(`view=${JSON.stringify(view)};selected=new Date(${JSON.stringify(date+'T00:00:00Z')});JSON.stringify(bounds())`))}
assert.equal(range('month','2026-02-10').days,28);
assert.equal(range('month','2024-02-10').days,29);
assert.equal(range('week','2026-09-30').start.slice(0,10),'2026-09-28');
for(const count of [30,60,90]) assert.equal(range('l'+count,'2026-09-30').days,count);
const current = evaluate('key(utcDay(new Date()))');
assert.equal(range('month',current).end.slice(0,10),current);
assert.equal(range('day',current).days,1);
for(const count of [30,60,90]) {
 const trailing=range('l'+count,'2024-02-10');
 assert.equal(trailing.end.slice(0,10),current);
 assert.equal(trailing.days,count);
 assert.equal((new Date(trailing.end)-new Date(trailing.start))/86400000,count-1);
}
const aggregation=evaluate(`view='day';selected=new Date('2026-09-30T00:00:00Z');unit='tokens';history={rangeStart:'2026-09-30',rangeEnd:'2026-09-30',daily:[{tokens:{a:10,b:20,c:30,d:40}}]};const g=grouped();JSON.stringify({names:modelNames,values:values(history.daily[0],g.ordered)})`);
assert.deepEqual(JSON.parse(aggregation),{names:['d','c','Other models'],values:[40,30,30]});
assert.equal(evaluate(`esc('<script>"&')`),'&lt;script&gt;&quot;&amp;');
console.log('Passed: calendar months, leap year, Monday weeks, rolling windows, future-day exclusion, model grouping, escaping');
// Unchanged refreshes must preserve chart nodes and their hover state.
const elements=new Map();let chartWrites=0;
function element(id){if(!elements.has(id))elements.set(id,{style:{},classList:{toggle(){}},setAttribute(){},firstElementChild:{},_html:'',set innerHTML(v){this._html=v;if(id==='bars')chartWrites++},get innerHTML(){return this._html}});return elements.get(id)}
const rendering=vm.createContext({Date,Intl,document:{body:{classList:{toggle(){}}},getElementById:element,querySelector:element,querySelectorAll:()=>[]},window:{}});
vm.runInContext(source,rendering);
vm.runInContext(`view='day';selected=utcDay(new Date());history={state:'ok',rangeStart:key(selected),rangeEnd:key(selected),tokensAvailable:true,estimatedUSD:1,daily:[{date:key(selected),tokens:{model:10}}]};loading=false;render();`,rendering);
const initialWrites=chartWrites;
vm.runInContext('loading=true;render();loading=false;render();dailyLimit=100;render();',rendering);
assert.equal(chartWrites,initialWrites,'Refresh status and budget edits must not rebuild chart');
vm.runInContext('history.daily[0].tokens.model=20;render();',rendering);
assert.ok(chartWrites>initialWrites,'Changed usage must redraw chart');
console.log('Passed: chart reuse on refresh and budget edits; redraw on changed usage');
