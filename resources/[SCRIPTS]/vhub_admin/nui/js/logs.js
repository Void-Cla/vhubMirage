// nui/js/logs.js  auditoria
(() => {
  const App = window.vhubAdmin;
  const $list   = document.getElementById('logs-list');
  const $search = document.getElementById('l-search');
  let all = [];

  function render() {
    const q = ($search.value || '').toLowerCase();
    $list.innerHTML = '';
    all.filter(r => !q || (r.action || '').toLowerCase().includes(q) ||
                       String(r.actor_id || '').includes(q) ||
                       String(r.target_id || '').includes(q))
       .forEach(r => {
      const el = document.createElement('div');
      el.className = 'item';
      el.innerHTML = `
        <div>
          <strong>${r.action}</strong>
          <span style="color:var(--text-dim)">por ${r.actor_name || 'console'} (uid ${r.actor_id || '-'})</span>
          ${r.target_id ? `   alvo uid ${r.target_id}` : ''}
          <div class="meta">${r.payload || ''}</div>
        </div>
        <div class="right meta">${App.fmtDate(r.created_at)}</div>`;
      $list.appendChild(el);
    });
  }

  $search.addEventListener('input', render);
  document.getElementById('l-refresh').onclick = () => App.post('reqLogs', { limit: 200 });

  App.renderLogs = (rows) => { all = Array.isArray(rows) ? rows : []; render(); };
})();
