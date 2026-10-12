// One persistent surface, with crisp content revealed after its expansion.
(() => {
  const reduce = matchMedia('(prefers-reduced-motion: reduce)');
  const widget = document.querySelector('.widget');
  const replay = document.querySelector('.replay');
  const cursor = document.createElement('div');
  cursor.setAttribute('aria-hidden','true');
  cursor.style.cssText='position:fixed;left:0;top:0;z-index:10;pointer-events:none;opacity:0;width:24px;height:28px;filter:drop-shadow(0 2px 3px #0008)';
  cursor.innerHTML='<svg viewBox="0 0 24 28" fill="white" stroke="#20242b" stroke-width="1.5"><path d="M3 2v21l5-5 4 8 4-2-4-8h8Z"/></svg>';
  document.body.append(cursor);
  let active = [];
  function cancel() { active.forEach(a => a.cancel()); active = []; }
  function animate(el, frames, options) {
    const a = el.animate(frames, options); active.push(a); return a;
  }
  function morph() {
    cancel();
    if (reduce.matches) return;
    const rect = widget.getBoundingClientRect();
    const {width, height} = rect;
    const x = (width - 48) / 2, y = (height - 48) / 2;
    const dockX = document.documentElement.clientWidth - 14 - (rect.left + width/2);
    const tab = `inset(${(height-68)/2}px ${(width-28)/2}px round 14px 0 0 14px)`;
    const ball = `inset(${y}px ${x}px round 24px)`;
    const frames = [
      {clipPath:tab,offset:0}, {clipPath:tab,offset:.28},
      {clipPath:ball,offset:.39}, {clipPath:ball,offset:.69}
    ];
    // The same surface detaches, travels, pauses, then opens with a damped spring.
    for (let i = 0; i <= 60; i++) {
      const t = i/60, z=.8, w=11, wd=w*Math.sqrt(1-z*z);
      const response=1-Math.exp(-z*w*t)*(Math.cos(wd*t)+z/Math.sqrt(1-z*z)*Math.sin(wd*t));
      const p=i===60?1:Math.min(1,Math.max(0,response));
      frames.push({clipPath:`inset(${y*(1-p)}px ${x*(1-p)}px round ${24-2*p}px)`,offset:.70+t*.30});
    }
    animate(widget,frames,{duration:3600,fill:'backwards',easing:'linear'});
    animate(widget,[
      {transform:`translate(${dockX}px,0)`,offset:0},
      {transform:`translate(${dockX}px,0)`,offset:.28,easing:'cubic-bezier(.35,0,.2,1)'},
      {transform:`translate(${dockX*.48}px,-20px)`,offset:.43,easing:'cubic-bezier(.2,.7,.2,1)'},
      {transform:'translate(0,0)',offset:.59},
      {transform:'translate(0,0)',offset:1}
    ],{duration:3600,fill:'backwards'});
    const cx=rect.left+width/2,cy=rect.top+height/2;
    const at=(dx,dy)=>`translate(${cx+dx}px,${cy+dy}px)`;
    animate(cursor,[
      {opacity:0,transform:at(dockX-95,75),offset:0},
      {opacity:0,transform:at(dockX-95,75),offset:.12},
      {opacity:1,transform:at(dockX-4,0),offset:.25},
      {opacity:1,transform:at(dockX-4,0)+' scale(.85)',offset:.28,easing:'cubic-bezier(.35,0,.2,1)'},
      {opacity:1,transform:at(dockX*.48-4,-20)+' scale(.85)',offset:.43,easing:'cubic-bezier(.2,.7,.2,1)'},
      {opacity:1,transform:at(-4,0)+' scale(.85)',offset:.59},
      {opacity:1,transform:at(-4,0),offset:.63},
      {opacity:0,transform:at(45,45),offset:.70},
      {opacity:0,transform:at(45,45),offset:1}
    ],{duration:3600,fill:'backwards'});
    [...widget.children].forEach((el,i) => animate(el,
      [{opacity:0,transform:'translateY(9px)'},{opacity:1,transform:'translateY(0)'}],
      {duration:360,delay:2820+i*65,fill:'backwards',easing:'cubic-bezier(.2,.7,.2,1)'}));
  }
  if (!reduce.matches) {
    document.querySelectorAll('nav,.hero>div:first-child>*').forEach((el,i) =>
      el.animate([{opacity:0,transform:'translateY(14px)'},{opacity:1,transform:'translateY(0)'}],
        {duration:600,delay:i*65,fill:'backwards',easing:'cubic-bezier(.2,.7,.2,1)'}));
    morph();
  }
  replay.setAttribute('aria-label','Replay edge tab drag and expansion');
  replay.addEventListener('click',morph);
  window.addEventListener('resize',cancel);
  window.addEventListener('scroll',cancel,{passive:true});
  reduce.addEventListener('change', () => {
    if(reduce.matches) { cancel(); document.getAnimations().forEach(a=>a.finish()); }
  });
})();
