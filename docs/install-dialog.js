(() => {
  const panel = document.getElementById('installDialog');
  const trigger = document.getElementById('installTrigger');
  const command = document.getElementById('installCommand');
  const status = document.getElementById('copyStatus');
  function close() { panel.hidden=true; trigger.setAttribute('aria-expanded','false'); trigger.focus(); }
  async function copyPrompt() {
    status.textContent='Copying…';
    try { await navigator.clipboard.writeText(command.value); status.textContent='✓ Copied to clipboard'; }
    catch { command.focus(); command.select(); status.textContent='Select and copy with ⌘C / Ctrl+C.'; }
  }
  trigger.addEventListener('click', () => {
    if(!panel.hidden) { close(); return; }
    panel.hidden=false;trigger.setAttribute('aria-expanded','true');
    if(!matchMedia('(prefers-reduced-motion: reduce)').matches) panel.animate(
      [{opacity:0,transform:'translateY(-10px)'},{opacity:1,transform:'translateY(0)'}],
      {duration:240,easing:'cubic-bezier(.2,.8,.2,1)'});
    copyPrompt();
  });
  panel.querySelector('.dialog-close').addEventListener('click',close);
  panel.addEventListener('keydown',e=>{if(e.key==='Escape')close();});
  document.getElementById('copyInstall').addEventListener('click',copyPrompt);
})();
