// players.js — lista de jogadores + ficha (RG) com transações
// Anti-XSS: nome de jogador e identidade são dados de USUÁRIO → textContent sempre.
(() => {
  const App = window.vhubAdmin;
  const $list   = document.getElementById('players-list');
  const $detail = document.getElementById('player-detail');

  let all = [];
  let selected = null;
  let query = '';

  // ============================================================
  // LISTA
  // ============================================================

  function applyFilter() {
    const q = query.toLowerCase();
    return all.filter(p =>
      !q ||
      String(p.src).includes(q) ||
      String(p.uid).includes(q) ||
      (p.name || '').toLowerCase().includes(q));
  }

  function render() {
    $list.textContent = '';
    applyFilter().forEach(p => {
      const card = App.el('div', 'pcard' + (selected === p.src ? ' selected' : ''));
      card.appendChild(App.el('h4', null, `[${p.src}] ${p.name}`));
      card.appendChild(App.el('div', 'sub', `uid ${p.uid} · char ${p.char} · ping ${p.ping}ms`));
      const tags = App.el('div', 'tags');
      (p.groups || []).slice(0, 4).forEach(g => tags.appendChild(App.el('span', 'tag', g)));
      card.appendChild(tags);
      card.onclick = () => { selected = p.src; render(); App.post('reqRG', { target: p.src }); };
      $list.appendChild(card);
    });
    if (!$list.children.length) {
      $list.appendChild(App.el('div', 'empty-row', 'Nenhum jogador encontrado.'));
    }
  }

  App.renderPlayers = (rows) => {
    all = Array.isArray(rows) ? rows : [];
    App.state.players = all;   // alimenta o seletor de alvo dos modais
    if (!all.some(p => p.src === selected)) selected = null;
    if (App.state.section === 'players') render();
  };

  App.sectionHooks.players = () => { query = ''; render(); };
  App.searchHooks.players  = (q) => { query = q; render(); };

  // ============================================================
  // FICHA (RG)
  // ============================================================

  // linha rótulo→valor da ficha
  function row(k, v, color) {
    const r = App.el('div', 'row');
    r.appendChild(App.el('span', 'k', k));
    const val = App.el('span', 'val', v);
    if (color) val.style.color = color;
    r.appendChild(val);
    return r;
  }

  App.renderRG = (info) => {
    if (!info) { $detail.classList.add('empty'); return; }
    $detail.classList.remove('empty');
    $detail.textContent = '';

    const id = info.identity || {};
    const fullName = [id.firstname, id.lastname].filter(Boolean).join(' ') || '?';
    $detail.appendChild(App.el('h2', null, info.name));
    $detail.appendChild(row('ID', String(info.src)));
    $detail.appendChild(row('uid', String(info.uid)));
    $detail.appendChild(row('char', String(info.char_id)));
    $detail.appendChild(row('Identidade', fullName));
    $detail.appendChild(row('Registro', id.registration || '?'));
    if (id.age) $detail.appendChild(row('Idade', String(id.age)));
    if (id.phone) $detail.appendChild(row('Telefone', id.phone));
    if (info.coords) {
      const c = info.coords;
      $detail.appendChild(row('Coords', `${c.x.toFixed(1)}, ${c.y.toFixed(1)}, ${c.z.toFixed(1)}`));
    }
    // economia: carteira + banco lado a lado em pills
    const ecoRow = App.el('div', 'eco-row');
    const mkPill = (label, val) => {
      const p = App.el('div', 'eco-pill');
      p.appendChild(App.el('div', 'ep-label', label));
      p.appendChild(App.el('div', 'ep-val', App.fmtMoney(val)));
      return p;
    };
    ecoRow.appendChild(mkPill('Carteira', info.wallet));
    ecoRow.appendChild(mkPill('Banco', info.bank));
    $detail.appendChild(ecoRow);

    const groupStr = (info.groups || []).map(g =>
      typeof g === 'object' ? `${g.id} (${g.level})` : String(g)
    ).join(', ') || '—';
    $detail.appendChild(row('Grupos', groupStr));
    $detail.appendChild(row('Veículos', (info.vehicles || []).map(v => v.plate).join(', ') || '—'));
    if (info.jail_until) $detail.appendChild(row('Preso até', App.fmtDate(info.jail_until), 'var(--vh-danger)'));
    if (info.mute_until) $detail.appendChild(row('Silenciado', App.fmtDate(info.mute_until), 'var(--vh-amber)'));
    $detail.appendChild(row('Ping', `${info.ping}ms`));

    // últimas movimentações financeiras (max 5, compacto)
    const txs = (info.transactions || []).slice(0, 5);
    if (txs.length) {
      const block = App.el('div', 'tx-block');
      block.appendChild(App.el('div', 'tx-block-title', 'Movimentações recentes'));
      txs.forEach(tx => {
        const r = App.el('div', 'txrow');
        const desc = App.el('span', 'tx-desc');
        desc.textContent = tx.kind + (tx.reason ? ' · ' + tx.reason : '');
        r.appendChild(desc);
        const amt = App.el('span', 'amt ' + (tx.amount >= 0 ? 'pos' : 'neg'));
        amt.textContent = App.fmtMoney(Math.abs(tx.amount));
        r.appendChild(amt);
        block.appendChild(r);
      });
      $detail.appendChild(block);
    }

    // ações rápidas sobre o alvo
    const actions = App.el('div', 'actions');
    const mk = (label, cls, fn) => {
      const b = App.el('button', 'btn ' + cls, label);
      b.onclick = fn;
      actions.appendChild(b);
    };
    const t = info.src;
    const simple = (a) => () => App.post('act', { action: a, fields: { target: t } });

    mk('Ir até', 'primary', simple('tp'));
    mk('Trazer', '', simple('tptome'));
    mk('Espectar', '', simple('spec'));
    mk('Curar', '', simple('heal'));
    mk('Reviver', '', simple('revive'));
    mk('Congelar', '', simple('freeze'));
    mk('Avisar', 'warn', () => withReason('warn', t, 'Avisar'));
    mk('Prender', 'warn', () => withMinutes('jail', t, 'Prender', 4320));
    mk('Silenciar', 'warn', () => withMinutes('mute', t, 'Silenciar', 1440));
    mk('Expulsar', 'danger', () => withReason('kick', t, 'Expulsar'));
    mk('Banir', 'danger', () => withReason('ban', t, 'Banir'));
    mk('Matar', 'danger', simple('kill'));
    mk('Skin', '', async () => {
      const r = await App.modal({
        title: `Skin — jogador ${t}`,
        fields: [ { k: 'model', label: 'PedHash / Model', type: 'text', maxlen: 64 } ],
        okText: 'Aplicar',
      });
      if (!r.ok) return;
      App.post('act', { action: 'skin', fields: { target: t, model: r.fields.model } });
    });
    $detail.appendChild(actions);
  };

  // modal de motivo (warn/kick/ban)
  async function withReason(action, t, label) {
    const r = await App.modal({
      title: `${label} — jogador ${t}`,
      fields: [ { k: 'reason', label: 'Motivo', type: 'text', maxlen: 180 } ],
      okText: 'Confirmar ação',
    });
    if (!r.ok) return;
    App.post('act', { action, fields: { target: t, reason: r.fields.reason, message: r.fields.reason } });
  }

  // modal de minutos + motivo (jail/mute)
  async function withMinutes(action, t, label, max) {
    const r = await App.modal({
      title: `${label} — jogador ${t}`,
      fields: [
        { k: 'minutes', label: `Minutos (5–${max})`, type: 'number', min: 5, max, value: 10 },
        { k: 'reason',  label: 'Motivo', type: 'text', maxlen: 180 },
      ],
      okText: 'Confirmar ação',
    });
    if (!r.ok) return;
    App.post('act', { action, fields: { target: t, minutes: r.fields.minutes, reason: r.fields.reason } });
  }
})();
