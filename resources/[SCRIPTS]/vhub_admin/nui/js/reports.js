// nui/js/reports.js  tickets
(() => {
  const App = window.vhubAdmin;
  const $list = document.getElementById('reports-list');
  document.getElementById('r-refresh').onclick = () => App.post('reqReports');

  App.renderReports = (rows) => {
    rows = Array.isArray(rows) ? rows : [];
    $list.innerHTML = '';
    const open = rows.filter(r => r.status !== 'closed').length;
    document.getElementById('s-reports').textContent = open;
    const badge = document.getElementById('r-badge');
    if (open > 0) { badge.textContent = open; badge.classList.remove('hidden'); }
    else badge.classList.add('hidden');

    rows.forEach(r => {
      const el = document.createElement('div');
      el.className = 'item';
      el.innerHTML = `
        <div>
          <strong>#${r.id}</strong>   <span style="color:var(--text-dim)">char ${r.reporter_id}</span>
          <span style="color:${r.status==='open'?'var(--ok)':r.status==='claimed'?'var(--warn)':'var(--text-dim2)'}">  [${r.status}]</span>
          <div class="meta">${r.message}</div>
          <div class="meta">${App.fmtDate(r.created_at)} ${r.claimed_by ? '  reclamado por '+r.claimed_by : ''}</div>
        </div>
        <div class="right">
          ${r.status==='open' ? `<button class="btn primary" data-claim="${r.id}">Atender</button>` : ''}
          ${r.status!=='closed' ? `<button class="btn danger" data-close="${r.id}">Fechar</button>` : ''}
        </div>`;
      $list.appendChild(el);
    });

    $list.querySelectorAll('[data-claim]').forEach(b => b.onclick = (e) => {
      e.stopPropagation();
      App.post('act', { action: 'reportClaim', fields: { id: +b.dataset.claim } });
      setTimeout(() => App.post('reqReports'), 500);
    });
    $list.querySelectorAll('[data-close]').forEach(b => b.onclick = async (e) => {
      e.stopPropagation();
      const r = await App.modal({
        title: 'Fechar report #' + b.dataset.close,
        html: `<label>Notas (opcional)</label><textarea data-field="notes" maxlength="220"></textarea>`,
      });
      if (r.ok) {
        App.post('act', { action: 'reportClose', fields: { id: +b.dataset.close, notes: r.fields.notes } });
        setTimeout(() => App.post('reqReports'), 500);
      }
    });
  };
})();
