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
  // Direct pointer tracking with a damped spring on release. No layout writes per frame.
  let drag=null, physics=0;
  widget.style.touchAction='none';widget.style.cursor='grab';
  widget.setAttribute('aria-label','Interactive Pace preview. Drag to move; release to expand.');
  function restore(){
    cancelAnimationFrame(physics);physics=0;drag=null;
    widget.style.transform='';widget.style.clipPath='';widget.style.cursor='grab';
    [...widget.children].forEach(el=>el.style.opacity='');
  }
  widget.addEventListener('pointerdown',e=>{
    if(e.button!==0)return;
    cancel();restore();
    const r=widget.getBoundingClientRect();
    drag={id:e.pointerId,x:e.clientX,y:e.clientY,px:e.clientX,py:e.clientY,dx:0,dy:0,vx:0,vy:0,t:performance.now(),w:r.width,h:r.height,cx:r.left+r.width/2,cy:r.top+r.height/2};
    widget.setPointerCapture(e.pointerId);widget.style.cursor='grabbing';
    [...widget.children].forEach(el=>el.style.opacity='0');
    widget.style.clipPath=`inset(${(r.height-56)/2}px ${(r.width-56)/2}px round 28px)`;
    if(!reducedMotion())animate(widget,[{clipPath:'inset(0px round 22px)'},{clipPath:widget.style.clipPath}],{duration:180,easing:'cubic-bezier(.2,.8,.2,1)'});
  });
  const reducedMotion=()=>reduce.matches;
  widget.addEventListener('pointermove',e=>{
    if(!drag||drag.id!==e.pointerId)return;
    const now=performance.now(),dt=Math.max(8,now-drag.t);
    drag.vx=.55*drag.vx+.45*(e.clientX-drag.px)/dt*1000;
    drag.vy=.55*drag.vy+.45*(e.clientY-drag.py)/dt*1000;
    drag.px=e.clientX;drag.py=e.clientY;drag.t=now;
    drag.dx=Math.max(38-drag.cx,Math.min(innerWidth-38-drag.cx,e.clientX-drag.x));
    drag.dy=Math.max(38-drag.cy,Math.min(innerHeight-38-drag.cy,e.clientY-drag.y));
    paintDrag(drag.dx,drag.dy,drag.vx,drag.vy);
  });
  function paintDrag(x,y,vx,vy){
    const speed=Math.hypot(vx,vy),stretch=reducedMotion()?0:Math.min(.48,speed/4200);
    const angle=Math.atan2(vy,vx)*180/Math.PI;
    widget.style.transform=`translate(${x}px,${y}px) rotate(${angle}deg) scale(${1+stretch},${1/(1+stretch)}) rotate(${-angle}deg)`;
  }
  function release(e){
    if(!drag||drag.id!==e.pointerId)return;
    const d=drag;drag=null;widget.style.cursor='grab';
    if(widget.hasPointerCapture(e.pointerId))widget.releasePointerCapture(e.pointerId);
    if(reducedMotion()){restore();return;}
    let x=d.dx,y=d.dy,vx=Math.max(-1600,Math.min(1600,d.vx)),vy=Math.max(-1600,Math.min(1600,d.vy)),last=performance.now(),start=last;
    function step(now){
      const dt=Math.min(.025,(now-last)/1000);last=now;
      vx+=(-180*x-20*vx)*dt;vy+=(-180*y-20*vy)*dt;x+=vx*dt;y+=vy*dt;
      x=Math.max(38-d.cx,Math.min(innerWidth-38-d.cx,x));y=Math.max(38-d.cy,Math.min(innerHeight-38-d.cy,y));
      paintDrag(x,y,vx,vy);
      if((Math.hypot(x,y)<.5&&Math.hypot(vx,vy)<8)||now-start>1600){
        restore();
        const r=widget.getBoundingClientRect();
        animate(widget,[{clipPath:`inset(${(r.height-56)/2}px ${(r.width-56)/2}px round 28px)`},{clipPath:'inset(0px round 22px)'}],{duration:450,easing:'cubic-bezier(.16,1,.3,1)'});
        [...widget.children].forEach((el,i)=>animate(el,[{opacity:0,transform:'translateY(7px)'},{opacity:1,transform:'translateY(0)'}],{duration:250,delay:170+i*35,fill:'backwards'}));
        return;
      }
      physics=requestAnimationFrame(step);
    }
    physics=requestAnimationFrame(step);
  }
  widget.addEventListener('pointerup',release);
  widget.addEventListener('pointercancel',()=>{cancel();restore();});
  widget.addEventListener('lostpointercapture',()=>{if(drag){cancel();restore();}});
  window.addEventListener('resize',restore);
  window.addEventListener('scroll',restore,{passive:true});
  reduce.addEventListener('change',()=>{if(reduce.matches)restore();});
  replay.addEventListener('click',restore);
  replay.setAttribute('aria-label','Replay edge tab drag and expansion');
  replay.addEventListener('click',morph);
  window.addEventListener('resize',cancel);
  window.addEventListener('scroll',cancel,{passive:true});
  reduce.addEventListener('change', () => {
    if(reduce.matches) { cancel(); document.getAnimations().forEach(a=>a.finish()); }
  });
})();
