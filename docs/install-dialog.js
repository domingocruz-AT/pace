(() => {
  const dialog = document.getElementById('installDialog');
  const command = document.getElementById('installCommand');
  const status = document.getElementById('copyStatus');
  document.getElementById('installTrigger').addEventListener('click', () => {
    dialog.showModal();
    copyPrompt();
  });
  dialog.querySelector('.dialog-close').addEventListener('click', () => dialog.close());
  dialog.addEventListener('click', e => {
    if(e.target !== dialog) return;
    const r = dialog.getBoundingClientRect();
    if(e.clientX < r.left || e.clientX > r.right || e.clientY < r.top || e.clientY > r.bottom) dialog.close();
  });
  async function copyPrompt() {
    status.textContent = 'Copying…';
    try { await navigator.clipboard.writeText(command.value); status.textContent = '✓ Copied to clipboard'; }
    catch { command.focus(); command.select(); status.textContent = 'Select and copy with ⌘C / Ctrl+C.'; }
  }
  document.getElementById('copyInstall').addEventListener('click', copyPrompt);
})();
