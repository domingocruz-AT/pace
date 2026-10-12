(() => {
  const dialog = document.getElementById('installDialog');
  const command = document.getElementById('installCommand');
  const status = document.getElementById('copyStatus');
  document.getElementById('installTrigger').addEventListener('click', () => {
    status.textContent = '';
    dialog.showModal();
  });
  dialog.querySelector('.dialog-close').addEventListener('click', () => dialog.close());
  dialog.addEventListener('click', e => {
    if(e.target !== dialog) return;
    const r = dialog.getBoundingClientRect();
    if(e.clientX < r.left || e.clientX > r.right || e.clientY < r.top || e.clientY > r.bottom) dialog.close();
  });
  document.getElementById('copyInstall').addEventListener('click', async () => {
    try { await navigator.clipboard.writeText(command.value); status.textContent = 'Copied. Paste into your agent.'; }
    catch { command.focus(); command.select(); status.textContent = 'Press ⌘C to copy the selected instruction.'; }
  });
})();
