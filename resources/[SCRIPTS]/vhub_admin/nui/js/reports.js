// reports.js — denúncias com filtro por status (subtabs do topbar)
// Anti-XSS: mensagem de denúncia é dado de USUÁRIO → textContent sempre.
(() => {
  const App = window.vhubAdmin;
  const $list = document.getElementById('reports-list');

  let all = [];

  const ST_LABEL = { open: 'Aberta', claimed: 'Em atendimento', closed: 'Fechada' };
  const ST_COLOR = {
    open:    'var(--vh-ok)',
    claimed: 'var(--vh-amber)',
    closed:  'var(--vh-text-dim2)',
  };

  function render() {
    const sub = (App.state.section === 'reports' && App.state.sub) || 'open';
    $list.textContent = '';

    const rows = all.filter(r => sub === 'all' || r.status === sub);
    if (!rows.length) {
      $list.appendChild(App.el('div', 'empty-row', 'Nenhuma denúncia aqui.'));
    }

    rows.forEach(r => {
      const item = App.el('div', 'item');

      const left = App.el('div');
      const head = App.el('div');
      head.appendChild(App.el('strong', null, `#${r.id}`));
      head.appendChild(App.el('span', 'meta', ` personagem ${r.reporter_id} · `));
      const st = App.el('span', null, ST_LABEL[r.status] || r.status);
      st.style.color = ST_COLOR[r.status] || 'var(--vh-text-dim)';
      head.appendChild(st);
      left.appendChild(head);
      left.appendChild(App.el('div', 'meta', r.message || ''));
      left.appendChild(App.el('div', 'meta',
        App.fmtDate(r.created_at) + (r.claimed_by ? ` · atendida por ${r.claimed_by}` : '')));
      item.appendChild(left);

      const right = App.el('div', 'right');
      if (r.status === 'open') {
        const b = App.el('button', 'btn primary', 'Atender');
        b.onclick = () => {
          App.post('act', { action: 'reportClaim', fields: { id: r.id } });
          setTimeout(() => App.post('reqReports'), 500);
        };
        right.appendChild(b);
      }
      if (r.status !== 'closed') {
        const b = App.el('button', 'btn danger', 'Fechar');
        b.onclick = async () => {
          const res = await App.modal({
            title: `Fechar denúncia #${r.id}`,
            fields: [ { k: 'notes', label: 'Notas (opcional)', type: 'textarea', max: 220 } ],
          });
          if (!res.ok) return;
          App.post('act', { action: 'reportClose', fields: { id: r.id, notes: res.fields.notes } });
          setTimeout(() => App.post('reqReports'), 500);
        };
        right.appendChild(b);
      }
      item.appendChild(right);
      $list.appendChild(item);
    });
  }

  App.renderReports = (rows) => {
    all = Array.isArray(rows) ? rows : [];
    // badge do aside sempre reflete abertas
    const open = all.filter(r => r.status !== 'closed').length;
    const badge = document.getElementById('r-badge');
    if (badge) {
      badge.textContent = open;
      badge.classList.toggle('hidden', open === 0);
    }
    if (App.state.section === 'reports') render();
  };

  App.sectionHooks.reports = () => render();
})();
