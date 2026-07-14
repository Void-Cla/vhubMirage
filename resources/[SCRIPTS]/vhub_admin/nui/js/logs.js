// logs.js — auditoria (filtro pela busca do topbar)
// Anti-XSS: actor_name/payload vêm do servidor mas carregam texto de usuário → textContent.
(() => {
  const App = window.vhubAdmin;
  const $list = document.getElementById('logs-list');

  let all = [];
  let query = '';

  function render() {
    const q = query.toLowerCase();
    $list.textContent = '';
    const rows = all.filter(r =>
      !q ||
      (r.action || '').toLowerCase().includes(q) ||
      String(r.actor_id || '').includes(q) ||
      String(r.target_id || '').includes(q));

    if (!rows.length) {
      $list.appendChild(App.el('div', 'empty-row', 'Nenhum registro.'));
    }

    rows.forEach(r => {
      const item = App.el('div', 'item');
      const left = App.el('div');
      const head = App.el('div');
      head.appendChild(App.el('strong', null, r.action || '?'));
      head.appendChild(App.el('span', 'meta',
        ` por ${r.actor_name || 'console'} (uid ${r.actor_id ?? '—'})` +
        (r.target_id ? ` · alvo uid ${r.target_id}` : '')));
      left.appendChild(head);
      if (r.payload) left.appendChild(App.el('div', 'meta', r.payload));
      item.appendChild(left);

      const right = App.el('div', 'right meta', App.fmtDate(r.created_at));
      item.appendChild(right);
      $list.appendChild(item);
    });
  }

  App.renderLogs = (rows) => {
    all = Array.isArray(rows) ? rows : [];
    if (App.state.section === 'logs') render();
  };

  App.sectionHooks.logs = () => { query = ''; render(); };
  App.searchHooks.logs  = (q) => { query = q; render(); };
})();
