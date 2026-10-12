// One persistent surface, with crisp content revealed after its expansion.
(() => {
  const reduce = matchMedia('(prefers-reduced-motion: reduce)');
  const widget = document.querySelector('.widget');
  const replay = document.querySelector('.replay');
  let active = [];
  function cancel() { active.forEach(a => a.cancel()); active = []; }
  function animate(el, frames, options) {
    const a = el.animate(frames, options); active.push(a); return a;
  }
  function morph() {
    cancel();
    if (reduce.matches) return;
    const {width, height} = widget.getBoundingClientRect();
    const x = (width - 48) / 2, y = (height - 48) / 2;
    const frames = [];
    // Analytic damped spring; higher damping keeps the large morph calm.
    for (let i = 0; i <= 60; i++) {
      const t = i / 60;
      const z = .8, w = 11, wd = w * Math.sqrt(1-z*z);
      const response = 1 - Math.exp(-z*w*t) * (Math.cos(wd*t) + z/Math.sqrt(1-z*z)*Math.sin(wd*t));
      const p = i === 60 ? 1 : Math.min(1, Math.max(0, response));
      frames.push({clipPath:`inset(${y*(1-p)}px ${x*(1-p)}px round ${24-2*p}px)`,offset:t});
    }
    animate(widget, frames, {duration:900, delay:180, fill:'backwards',easing:'linear'});
    [...widget.children].forEach((el,i) => animate(el,
      [{opacity:0,transform:'translateY(9px)'},{opacity:1,transform:'translateY(0)'}],
      {duration:360,delay:480+i*65,fill:'backwards',easing:'cubic-bezier(.2,.7,.2,1)'}));
  }
  if (!reduce.matches) {
    document.querySelectorAll('nav,.hero>div:first-child>*').forEach((el,i) =>
      el.animate([{opacity:0,transform:'translateY(14px)'},{opacity:1,transform:'translateY(0)'}],
        {duration:600,delay:i*65,fill:'backwards',easing:'cubic-bezier(.2,.7,.2,1)'}));
    morph();
  }
  replay.addEventListener('click',morph);
  reduce.addEventListener('change', () => {
    if(reduce.matches) { cancel(); document.getAnimations().forEach(a=>a.finish()); }
  });
})();
