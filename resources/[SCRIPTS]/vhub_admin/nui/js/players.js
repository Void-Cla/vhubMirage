// nui/js/players.js  lista de jogadores + detalhe (RG)
(() => {
  const App = window.vhubAdmin;
  const $list   = document.getElementById('players-list');
  const $detail = document.getElementById('player-detail');
  const $search = document.getElementById('p-search');

  let all = [];
  let selected = null;

  function applyFilter() {
    const q = ($search.value || '').toLowerCase();
    return all.filter(p =>
      !q ||
      String(p.src).includes(q) ||
      String(p.uid).includes(q) ||
      (p.name || '').toLowerCase().includes(q));
  }

  function render() {
    $list.innerHTML = '';
    applyFilter().forEach(p => {
      const el = document.createElement('div');
      el.className = 'pcard' + (selected === p.src ? ' selected' : '');
      el.innerHTML = `
        <h4>[${p.src}] ${p.name}</h4>
        <div class="sub">uid ${p.uid}   char ${p.char}   ping ${p.ping}ms</div>
        <div class="tags">${(p.groups || []).slice(0,4).map(g => `<span class="tag">${g}</span>`).join('')}</div>`;
      el.onclick = () => { selected = p.src; render(); App.post('reqRG', { target: p.src }); };
      $list.appendChild(el);
    });
    document.getElementById('s-online').textContent = all.length;
  }

  $search.addEventListener('input', render);
  document.getElementById('p-refresh').onclick = () => App.post('reqPlayers');

  App.renderPlayers = (rows) => {
    all = Array.isArray(rows) ? rows : [];
    if (!all.some(p => p.src === selected)) selected = null;
    render();
  };

  App.renderRG = (info) => {
    if (!info) { $detail.classList.add('empty'); return; }
    $detail.classList.remove('empty');
    const id = info.identity || {};
    $detail.innerHTML = `
      <h2>${info.name}</h2>
      <div class="row"><span class="k">ID</span><span>${info.src}</span></div>
      <div class="row"><span class="k">uid</span><span>${info.uid}</span></div>
      <div class="row"><span class="k">char</span><span>${info.char_id}</span></div>
      <div class="row"><span class="k">Identidade</span><span>${(id.name||'?')+' '+(id.firstname||'')}</span></div>
      <div class="row"><span class="k">Registro</span><span>${id.registration || '?'}</span></div>
      <div class="row"><span class="k">Telefone</span><span>${id.phone || '?'}</span></div>
      <div class="row"><span class="k">Idade</span><span>${id.age || '?'}</span></div>
      <div class="row"><span class="k">Carteira</span><span>${App.fmtMoney(info.wallet)}</span></div>
      <div class="row"><span class="k">Banco</span><span>${App.fmtMoney(info.bank)}</span></div>
      <div class="row"><span class="k">Grupos</span><span>${(info.groups||[]).join(', ') || '-'}</span></div>
      <div class="row"><span class="k">Ve culos</span><span>${(info.vehicles||[]).map(v=>v.plate).join(', ') || '-'}</span></div>
      ${info.jail_until ? `<div class="row"><span class="k">Jail at </span><span style="color:var(--danger)">${App.fmtDate(info.jail_until)}</span></div>` : ''}
      ${info.mute_until ? `<div class="row"><span class="k">Mute at </span><span style="color:var(--warn)">${App.fmtDate(info.mute_until)}</span></div>` : ''}
      <div class="row"><span class="k">Ping</span><span>${info.ping}ms</span></div>
      <div class="actions">
        <button class="btn primary" data-a="tp">Ir at </button>
        <button class="btn" data-a="tptome">Trazer</button>
        <button class="btn" data-a="spec">Espectar</button>
        <button class="btn" data-a="heal">Curar</button>
        <button class="btn" data-a="revive">Reviver</button>
        <button class="btn" data-a="freeze">Congelar</button>
        <button class="btn warn" data-a="warn">Avisar</button>
        <button class="btn warn" data-a="jail">Prender</button>
        <button class="btn warn" data-a="mute">Silenciar</button>
        <button class="btn danger" data-a="kick">Expulsar</button>
        <button class="btn danger" data-a="ban">Banir</button>
        <button class="btn danger" data-a="kill">Matar</button>
      </div>`;

    $detail.querySelectorAll('[data-a]').forEach(b => b.onclick = () => quickAct(b.dataset.a, info));
  };

  async function quickAct(a, info) {
    const t = info.src;
    if (a === 'warn' || a === 'kick' || a === 'ban') {
      const r = await App.modal({
        title: a.toUpperCase() + ' [' + t + ']',
        html: `<label>Motivo</label><input data-field="reason" maxlength="180">`,
      });
      if (r.ok) App.post('act', { action: a, fields: { target: t, message: r.fields.reason, reason: r.fields.reason } });
      return;
    }
    if (a === 'jail' || a === 'mute') {
      const r = await App.modal({
        title: a.toUpperCase() + ' [' + t + ']',
        html: `<label>Minutos</label><input type="number" data-field="minutes" value="10" min="5" max="4320">
               <label>Motivo</label><input data-field="reason" maxlength="180">`,
      });
      if (r.ok) App.post('act', { action: a, fields: { target: t, minutes: r.fields.minutes, reason: r.fields.reason } });
      return;
    }
    App.post('act', { action: a, fields: { target: t } });
  }
})();
