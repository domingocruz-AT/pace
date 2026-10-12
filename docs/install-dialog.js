(() => {
  const panel = document.getElementById('installDialog');
  const trigger = document.getElementById('installTrigger');
  const command = document.getElementById('installCommand');
  const status = document.getElementById('copyStatus');
  function close() { panel.hidden=true; trigger.setAttribute('aria-expanded','false'); trigger.focus(); }
  async function copyPrompt() {
    status.textContent='Copying…';
    try { await navigator.clipboard.writeText(command.textContent); status.textContent='✓ Copied to clipboard'; }
    catch { const selection=window.getSelection(); const range=document.createRange();range.selectNodeContents(command);selection.removeAllRanges();selection.addRange(range);status.textContent='Press ⌘C / Ctrl+C to copy.'; }
  }
  trigger.addEventListener('click', () => {
    if(!panel.hidden) { close(); return; }
    panel.hidden=false;trigger.setAttribute('aria-expanded','true');
    if(!matchMedia('(prefers-reduced-motion: reduce)').matches) panel.animate(
      [{opacity:0,transform:'translateY(-10px)'},{opacity:1,transform:'translateY(0)'}],
      {duration:240,easing:'cubic-bezier(.2,.8,.2,1)'});
    copyPrompt();
  });
  panel.addEventListener('keydown',e=>{if(e.key==='Escape')close();});
})();
