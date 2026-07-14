// fleet.js — listagem e gestão de frota persistente
// Anti-XSS: placa, modelo e nome via textContent
(() => {
  const App = window.vhubAdmin;

  const $list    = document.getElementById('fleet-list');
  const $detail  = document.getElementById('fleet-detail');
  const $toolbar = document.getElementById('fleet-toolbar');

  let all = [];
  let selected = null;
  let query = '';


  // ============================================================
  // STATUS MAP
  // ============================================================

  const STATUS_COLOR = {
    out:      'var(--vh-ok)',
    garage:   'var(--vh-text-dim)',
    impound:  'var(--vh-danger)',
    auction:  'var(--vh-amber)',
    rental:   'var(--vh-gold)',
    sold:     'var(--vh-text-dim2)',
  };

  function statusLabel(s) {
    const m = { out: 'Fora', garage: 'Garagem', impound: 'Pátio',
                auction: 'Leilão', rental: 'Aluguel', sold: 'Vendido' };
    return m[s] || s;
  }


  // ============================================================
  // LISTA
  // ============================================================

  function applyFilter() {
    const q = query.toLowerCase();
    if (!q) return all;
    return all.filter(v =>
      (v.plate || '').toLowerCase().includes(q) ||
      (v.model || '').toLowerCase().includes(q) ||
      (v.owner_name || '').toLowerCase().includes(q));
  }

  function renderList() {
    $list.textContent = '';
    const rows = applyFilter();
    if (!rows.length) {
      $list.appendChild(App.el('div', 'empty-row', 'Nenhum veículo encontrado.'));
      return;
    }
    rows.forEach(v => {
      const row = App.el('div', 'item fleet-row' + (selected === v.plate ? ' sel' : ''));

      const left = App.el('div');
      const plate = App.el('span', 'fleet-plate', v.plate);
      left.appendChild(plate);
      const meta = App.el('div', 'fleet-meta',
        `${v.model || '?'} · ${v.owner_name || '?'}`);
      left.appendChild(meta);
      row.appendChild(left);

      const right = App.el('div', 'right');
      const st = App.el('span', null, statusLabel(v.status || 'garage'));
      st.style.color = STATUS_COLOR[v.status] || 'var(--vh-text-dim)';
      st.style.fontSize = '11px';
      right.appendChild(st);
      row.appendChild(right);

      row.onclick = () => {
        selected = v.plate;
        renderList();
        App.post('reqFleetDetail', { plate: v.plate });
      };
      $list.appendChild(row);
    });
  }

  App.renderFleet = (rows) => {
    all = Array.isArray(rows) ? rows : [];
    if (App.state.section === 'fleet') renderList();
  };

  App.sectionHooks.fleet = () => { query = ''; renderList(); };
  App.searchHooks.fleet  = (q) => { query = q; renderList(); };


  // ============================================================
  // DETALHE
  // ============================================================

  function row(k, v, color) {
    const r = App.el('div', 'row');
    r.appendChild(App.el('span', 'k', k));
    const val = App.el('span', 'val', v);
    if (color) val.style.color = color;
    r.appendChild(val);
    return r;
  }

  App.renderFleetDetail = (d) => {
    if (!d) { $detail.classList.add('empty'); return; }
    $detail.classList.remove('empty');
    $detail.textContent = '';

    $detail.appendChild(App.el('h2', null, d.plate));
    $detail.appendChild(row('Modelo', d.model || '?'));
    $detail.appendChild(row('Dono', d.owner_name || '?'));
    $detail.appendChild(row('Status', statusLabel(d.status), STATUS_COLOR[d.status]));
    if (d.ipva_due) $detail.appendChild(row('IPVA vence', App.fmtDate(d.ipva_due)));
    if (d.keys && d.keys.length) {
      $detail.appendChild(row('Chaves', d.keys.map(k => k.name || k.char_id).join(', ')));
    }

    // ações rápidas
    const acts = App.el('div', 'actions');
    const mk = (label, cls, fn) => {
      const b = App.el('button', 'btn ' + cls, label);
      b.onclick = fn;
      acts.appendChild(b);
    };
    const p = d.plate;
    mk('Despawnar', '', () => confirm('fleet', 'fleetDespawn', { plate: p }));
    mk('Liberar pátio', 'ok', () => confirm('fleet', 'fleetRelease', { plate: p }));
    mk('Renovar IPVA', '', () => confirmDays('fleetIpva', p));
    mk('Transferir', 'warn', () => confirmTransfer(p));
    mk('Excluir', 'danger', () => confirm('fleet', 'fleetDelete', { plate: p }));
    $detail.appendChild(acts);
  };

  async function confirm(section, action, fields) {
    const r = await App.modal({ title: PT_LABEL[action] || action,
      text: `Confirmar ação para placa ${fields.plate}?`, okText: 'Confirmar' });
    if (!r.ok) return;
    App.post('act', { action, fields });
  }

  async function confirmDays(action, plate) {
    const r = await App.modal({ title: 'Renovar IPVA',
      fields: [ { k: 'days', label: 'Dias', type: 'number', min: 1, max: 3650, value: 365 } ],
      okText: 'Renovar' });
    if (!r.ok) return;
    App.post('act', { action, fields: { plate, days: r.fields.days } });
  }

  async function confirmTransfer(plate) {
    const r = await App.modal({ title: 'Transferir posse',
      fields: [
        { k: 'target', label: 'Alvo (ID)', type: 'player',
          options: (App.state.players || []).map(p => ({ value: p.src, label: `[${p.src}] ${p.name}` })) },
      ],
      okText: 'Transferir' });
    if (!r.ok) return;
    App.post('act', { action: 'fleetTransfer', fields: { plate, target: r.fields.target } });
  }

  const PT_LABEL = {
    fleetDespawn: 'Recolher placa', fleetRelease: 'Liberar pátio',
    fleetDelete: 'Excluir veículo', fleetIpva: 'Renovar IPVA',
  };
})();
