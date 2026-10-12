(() => {
  const panel = document.getElementById('installDialog');
  const trigger = document.getElementById('installTrigger');
  const command = document.getElementById('installCommand');
  const status = document.getElementById('copyStatus');
  const reduced = () => matchMedia('(prefers-reduced-motion: reduce)').matches;
  let notice, timer, slide, copyVersion = 0;
  function selectPrompt() {
    const selection=window.getSelection(), range=document.createRange();
    range.selectNodeContents(command);selection.removeAllRanges();selection.addRange(range);
  }
  function confirmCopy(message) {
    notice?.cancel();clearTimeout(timer);
    status.textContent=message;status.style.opacity='1';
    if(!reduced()) notice=status.animate([
      {opacity:0,transform:'translateY(4px)',offset:0},
      {opacity:1,transform:'translateY(0)',offset:.12},
      {opacity:1,transform:'translateY(0)',offset:.78},
      {opacity:0,transform:'translateY(-3px)',offset:1}
    ],{duration:2200,fill:'forwards',easing:'ease-out'});
    timer=setTimeout(()=>{status.style.opacity='0';status.textContent='';},2200);
  }
  async function copyPrompt() {
    const version=++copyVersion;
    try { await navigator.clipboard.writeText(command.textContent);if(version===copyVersion)confirmCopy('✓ Copied to clipboard'); }
    catch { if(version!==copyVersion)return;selectPrompt();status.textContent='Press ⌘C / Ctrl+C to copy.';status.style.opacity='1'; }
  }
  function close() {
    ++copyVersion;clearTimeout(timer);notice?.cancel();status.style.opacity='0';status.textContent='';
    slide?.cancel();trigger.setAttribute('aria-expanded','false');
    if(reduced()){panel.hidden=true;return;}
    slide=panel.animate([{height:panel.offsetHeight+'px',opacity:1},{height:'0px',opacity:0}],{duration:180,easing:'ease-in'});
    slide.onfinish=()=>{panel.hidden=true;};
  }
  trigger.addEventListener('click',()=>{
    if(trigger.getAttribute('aria-expanded')==='true'){close();return;}
    slide?.cancel();panel.hidden=false;trigger.setAttribute('aria-expanded','true');
    if(!reduced())slide=panel.animate([{height:'0px',opacity:0,transform:'translateY(-5px)'},{height:panel.offsetHeight+'px',opacity:1,transform:'translateY(0)'}],{duration:260,easing:'cubic-bezier(.2,.8,.2,1)'});
    copyPrompt();
  });
  command.addEventListener('click',()=>{selectPrompt();copyPrompt();});
  command.addEventListener('keydown',e=>{
    if(e.key==='Enter'||e.key===' '){e.preventDefault();selectPrompt();copyPrompt();}
    if(e.key==='Escape'){close();trigger.focus();}
  });
})();
