// The native host supplies sanitized usage only. No credentials or network access here.
const $=id=>document.getElementById(id),dayMS=86400000;
const utcDay=d=>new Date(Date.UTC(d.getUTCFullYear(),d.getUTCMonth(),d.getUTCDate()));
const key=d=>d.toISOString().slice(0,10),shift=(d,n)=>new Date(+d+n*dayMS);
const dateFormatter=new Intl.DateTimeFormat('en-US',{month:'short',day:'numeric',timeZone:'UTC'});
const moneyFormatter=new Intl.NumberFormat('en-US',{style:'currency',currency:'USD'});
const numberFormatter=new Intl.NumberFormat('en-US',{notation:'compact',maximumFractionDigits:1});
const shortDate=d=>dateFormatter.format(d);
const money=n=>Number.isFinite(n)?moneyFormatter.format(n):'—';
const number=n=>Number.isFinite(n)?numberFormatter.format(n):'—';
const sum=values=>values.reduce((a,b)=>a+b,0);
const esc=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
let view='month',unit='tokens',selected=utcDay(new Date()),history=null,current=null,loading=true,dailyLimit=0,monthlyLimit=0,lastQuery='',modelNames=[],ready=false;
const compact=!window.paceDashboard;
document.body.classList.toggle('popout',compact);
function send(action,extra={}){window.webkit?.messageHandlers.pace.postMessage({action,...extra});}
function bounds(){
 const today=utcDay(new Date());let start=new Date(selected),end=new Date(selected);
 if(view==='month'){start=new Date(Date.UTC(selected.getUTCFullYear(),selected.getUTCMonth(),1));end=new Date(Math.min(+today,+new Date(Date.UTC(selected.getUTCFullYear(),selected.getUTCMonth()+1,0))));}
 else if(view==='week'){start=shift(selected,-(selected.getUTCDay()+6)%7);end=new Date(Math.min(+today,+shift(start,6)));}
 else if(view.startsWith('l')){end=today;start=shift(today,1-Number(view.slice(1)));}
 return {start,end,days:Math.round((end-start)/dayMS)+1};
}
function query(force=false){const b=bounds(),q=key(b.end)+'/'+b.days;if(q!==lastQuery||force){lastQuery=q;loading=true;render();send('range',{end:key(b.end),days:b.days,force});}}
window.receive=payload=>{
 current=payload.current;dailyLimit=payload.dailyLimit;monthlyLimit=payload.monthlyLimit;
 const b=bounds();if(payload.history?.rangeStart===key(b.start)&&payload.history?.rangeEnd===key(b.end)){history=payload.history;loading=payload.loading;}
 else {history=null;loading=true;}
 render();
};
function rows(){const b=bounds();return history?.rangeStart===key(b.start)&&history?.rangeEnd===key(b.end)?history.daily||[]:[];}
function grouped(){const totals={};for(const r of rows())for(const [name,value]of Object.entries(unit==='tokens'?r.tokens||{}:r.models||{}))totals[name]=(totals[name]||0)+value;
 const ordered=Object.keys(totals).sort((a,b)=>totals[b]-totals[a]);
 modelNames=compact&&ordered.length>3?[...ordered.slice(0,2),'Other models']:ordered;
 return {ordered,totals};
}
function values(row,ordered){const source=unit==='tokens'?row.tokens||{}:row.models||{};return modelNames.map(name=>name==='Other models'?sum(ordered.slice(2).map(k=>source[k]||0)):source[name]||0).map(n=>unit==='cost'?n*(history?.usdPerCredit||0):n);}
let lastChartKey='';
function render(){
 const b=bounds(),multi=view!=='day',data=rows(),hasData=history&&data.length>0,available=hasData&&(unit!=='tokens'||history.tokensAvailable)&&(unit!=='cost'||history.usdPerCredit!=null);
 const spend=hasData?history.estimatedUSD:null,limit=view==='month'?monthlyLimit:dailyLimit*b.days,pct=limit>0&&spend!=null?spend/limit*100:null;
 $('rangeName').textContent={day:'Day',week:'Week',month:'Month',l30:'Last 30 days',l60:'Last 60 days',l90:'Last 90 days'}[view];
 document.querySelectorAll('[data-range]').forEach(e=>e.setAttribute('aria-checked',e.dataset.range===view));
 document.querySelectorAll('[data-unit]').forEach(e=>e.classList.toggle('active',e.dataset.unit===unit));
 $('period').textContent=multi?shortDate(b.start)+' – '+shortDate(b.end):shortDate(b.end);$('period').title=key(b.start)+' to '+key(b.end)+' · UTC';
 $('prev').disabled=view.startsWith('l');$('next').disabled=view.startsWith('l')||+b.end>=+utcDay(new Date());
 $('budgetTitle').textContent=view==='month'?'Monthly budget':multi?'Range budget':'Daily budget';$('status').textContent=loading?'Updating…':view==='day'?'UTC day':b.days+' UTC days';
 $('limitLabel').textContent=view==='month'?'Monthly limit':'Daily limit';if(document.activeElement!==$('limit'))$('limit').value=view==='month'?monthlyLimit:dailyLimit;
 $('ring').style.background='conic-gradient('+(pct>100?'#dfad97':'#b3a2ee')+' '+Math.min(pct||0,100)*3.6+'deg,#ffffff12 0deg)';$('ring').firstElementChild.textContent=pct==null?'—':Math.round(pct)+'%';
 $('spend').textContent=money(spend);$('remaining').textContent=limit<=0?'Set a personal budget ↗':spend==null?'Waiting for usage':money(Math.abs(limit-spend))+(spend>limit?' over target':' remaining')+(multi&&view!=='month'?' · daily × '+b.days:'');
 $('remaining').title='Open the dashboard to edit your personal limits';$('remaining').onclick=()=>send('dashboard');
 $('paceLabel').textContent='Budget used';$('paceValue').textContent=pct==null?'Not set':Math.round(pct)+'%';$('progress').style.width=Math.min(pct||0,100)+'%';
 $('paceNote').textContent=multi&&view!=='month'?'Range target = your daily limit × '+b.days+' days.':'Set 0 to turn off this personal target.';
 $('chartTitle').textContent=multi?'Daily usage':'Usage by model';$('unitLabel').textContent=unit==='tokens'?'Tokens (input + cached + output)':'Estimated dollars';
 $('overview').textContent=compact?'Open dashboard ↗':'Refresh';$('overview').setAttribute('aria-label',compact?'Open dashboard':'Refresh usage');
 $('bars').classList.toggle('day',!multi);$('bars').classList.toggle('dense',data.length>30);
 const chartKey=JSON.stringify([view,unit,key(b.start),key(b.end),data,history?.tokensAvailable,history?.usdPerCredit,available?false:loading]);
 if(chartKey!==lastChartKey){
 lastChartKey=chartKey;
 const {ordered,totals}=grouped(),allValues=modelNames.map(n=>n==='Other models'?sum(ordered.slice(2).map(k=>totals[k])):totals[n]).map(v=>unit==='cost'?v*(history?.usdPerCredit||0):v),fmt=unit==='cost'?money:number;
 const colors=['#b6a5ed','#89bac6','#d4d6dd','#d6b594','#a3bc9a','#b59cc0'];
 document.querySelector('.legend').innerHTML=available?modelNames.map((n,i)=>'<span><i class="swatch" style="background:'+colors[i%colors.length]+'"></i>'+esc(n.replace(/^gpt-/,''))+'</span>').join(''):'';
 $('total').textContent=available?fmt(sum(allValues)):'—';$('caption').textContent=multi?b.days+' days · Work + Codex':'Work + Codex';$('breakdownPeriod').textContent='Selected range';
 $('bars').innerHTML='';$('models').innerHTML='';
 if(!available){$('max').textContent='';$('axis').textContent='';$('bars').innerHTML='<div class="empty">'+(loading?'Loading usage…':unit==='tokens'?'Token history unavailable. Try Est. cost.':'Usage unavailable. Refresh to retry.')+'</div>';}
 else {
 const max=Math.max(1,...(multi?data.map(r=>sum(values(r,ordered))):allValues))*1.1;$('max').textContent=fmt(max);
 if(multi){$('bars').innerHTML=data.map(row=>{const v=values(row,ordered);return '<button class="bar" data-date="'+esc(row.date)+'" title="'+esc(row.date+' · '+fmt(sum(v)))+'" aria-label="Open '+esc(row.date)+' usage">'+v.map((n,i)=>({n,i})).reverse().map(({n,i})=>n>0?'<span style="background:'+colors[i%colors.length]+';height:'+n/max*100+'%"></span>':'').join('')+'</button>'}).join('');$('axis').innerHTML=[...new Set([0,Math.floor((data.length-1)/2),data.length-1])].map(i=>'<span>'+shortDate(new Date(data[i].date+'T00:00:00Z'))+'</span>').join('');}
 else {$('bars').innerHTML=allValues.map((n,i)=>'<div class="bar" title="'+esc(modelNames[i]+' · '+fmt(n))+'"><span style="background:'+colors[i%colors.length]+';height:'+n/max*100+'%"></span></div>').join('');$('axis').innerHTML=modelNames.map(n=>'<span>'+esc(n.replace(/^gpt-/,''))+'</span>').join('');}
 $('models').innerHTML=modelNames.map((n,i)=>'<div class="model"><span title="'+esc(n==='Other models'?ordered.slice(2).join(', '):n)+'"><i class="swatch" style="background:'+colors[i%colors.length]+'"></i>'+esc(n)+'</span><strong>'+fmt(allValues[i])+'</strong><span class="tiny">'+(sum(allValues)>0?Math.round(allValues[i]/sum(allValues)*100):0)+'%</span><div class="model-track"><i style="background:'+colors[i%colors.length]+';width:'+(sum(allValues)>0?allValues[i]/sum(allValues)*100:0)+'%"></i></div></div>').join('');
 if(!modelNames.length)$('models').innerHTML='<div class="empty">No reported usage for this period.</div>';
 }
 }
 $('chartNote').textContent=multi?'Select a daily bar to inspect its model usage.':'Input, cached input, and output tokens are included.';
 const source=unit==='tokens'?history?.tokenDataAsOf:history?.dataAsOf;
 $('sourceStatus').textContent=loading?'Updating usage…':history?.state!=='ok'?(history?.message||current?.message||'Usage unavailable'):'Work + Codex · UTC · estimates may lag';
 $('sourceStatus').title='Source: '+(source||'not reported')+' · Checked: '+(history?.fetchedAt||'not yet');
}
document.querySelectorAll('[data-unit]').forEach(e=>e.onclick=()=>{unit=e.dataset.unit;render()});
function move(n){if(view.startsWith('l'))return;selected=view==='month'?new Date(Date.UTC(selected.getUTCFullYear(),selected.getUTCMonth()+n,1)):shift(selected,n*(view==='week'?7:view.startsWith('l')?Number(view.slice(1)):1));selected=new Date(Math.min(+selected,+utcDay(new Date())));query();}
$('prev').onclick=()=>move(-1);$('next').onclick=()=>move(1);$('overview').onclick=()=>compact?send('dashboard'):query(true);
$('limit').onchange=e=>{const v=Number(e.target.value);if(Number.isFinite(v)&&v>=0&&v<=1000000){if(view==='month')monthlyLimit=v;else dailyLimit=v;send('budget',{dailyLimit,monthlyLimit});}render()};
const trigger=$('rangeTrigger'),menu=$('rangeMenu');
function closeMenu(focus=false){menu.hidden=true;trigger.setAttribute('aria-expanded','false');if(focus)trigger.focus()}
function openMenu(){menu.hidden=false;trigger.setAttribute('aria-expanded','true');menu.querySelector('[aria-checked="true"]').focus()}
trigger.onclick=()=>menu.hidden?openMenu():closeMenu(true);
trigger.onkeydown=e=>{if(e.key==='ArrowDown'){e.preventDefault();openMenu()}};
document.querySelectorAll('[data-range]').forEach(e=>e.onclick=()=>{view=e.dataset.range;if(view.startsWith('l'))selected=utcDay(new Date());closeMenu(true);query();render()});
menu.onkeydown=e=>{const options=[...menu.querySelectorAll('[data-range]')],i=options.indexOf(document.activeElement);if(e.key==='Escape'){e.preventDefault();closeMenu(true)}else if(['ArrowDown','ArrowUp','Home','End'].includes(e.key)){e.preventDefault();options[e.key==='Home'?0:e.key==='End'?options.length-1:(i+(e.key==='ArrowDown'?1:-1)+options.length)%options.length].focus()}else if(e.key==='Tab')closeMenu()};
document.addEventListener('click',e=>{if(!e.target.closest('.range-picker'))closeMenu()});
$('bars').onclick=e=>{const bar=e.target.closest('[data-date]');if(!bar)return;selected=new Date(bar.dataset.date+'T00:00:00Z');view='day';query();};
// Roll a visible trailing range forward after UTC midnight. Unchanged queries do no work.
setInterval(()=>{if(view.startsWith('l'))query();},60000);
render();ready=true;send('ready');query();
