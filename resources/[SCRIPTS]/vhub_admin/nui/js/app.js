// nui/js/app.js  bootstrap + router + modal + toast
(() => {
  const App = (window.vhubAdmin = { res: 'vhub_admin', state: {} });

  App.post = async (cb, data = {}) => {
    try {
      const r = await fetch(`https://${App.res}/${cb}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
      });
      return await r.json().catch(() => ({}));
    } catch (e) { return {}; }
  };

  // toast
  const $toast = document.getElementById('toast');
  let toastT = null;
  App.toast = (msg, type = 'info', ttl = 3500) => {
    $toast.textContent = msg; $toast.classList.remove('hidden');
    $toast.style.borderColor = type === 'err' ? 'rgba(255,91,110,0.7)' :
      type === 'ok' ? 'rgba(107,214,107,0.7)' : 'rgba(76,200,255,0.6)';
    if (toastT) clearTimeout(toastT);
    toastT = setTimeout(() => $toast.classList.add('hidden'), ttl);
  };

  // announce banner
  const $announce = document.getElementById('announce');
  App.announce = (text) => {
    $announce.querySelector('div').textContent = text;
    $announce.classList.remove('hidden');
    setTimeout(() => $announce.classList.add('hidden'), 9000);
  };

  // modal universal
  const $mbg = document.getElementById('modal-bg');
  const $mt  = document.getElementById('modal-title');
  const $mb  = document.getElementById('modal-body');
  const $mok = document.getElementById('modal-ok');
  const $mc  = document.getElementById('modal-cancel');
  App.modal = (opts) => new Promise((resolve) => {
    $mt.textContent = opts.title || 'Confirmar';
    $mb.innerHTML = opts.html || `<p>${opts.text || ''}</p>`;
    $mok.textContent = opts.okText || 'Confirmar';
    $mc.textContent  = opts.cancelText || 'Cancelar';
    const close = (val) => { $mbg.classList.add('hidden'); $mok.onclick=null; $mc.onclick=null; resolve(val); };
    $mok.onclick = () => {
      const fields = {};
      $mb.querySelectorAll('[data-field]').forEach((el) => {
        fields[el.dataset.field] = el.type === 'checkbox' ? el.checked : el.value;
      });
      close({ ok: true, fields });
    };
    $mc.onclick = () => close({ ok: false });
    $mbg.classList.remove('hidden');
  });

  // view router
  App.switchView = (id) => {
    document.querySelectorAll('.view').forEach(v => v.classList.add('hidden'));
    document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
    document.getElementById('view-' + id)?.classList.remove('hidden');
    document.querySelector(`.tab[data-view="${id}"]`)?.classList.add('active');
    App.state.view = id;
    // refresh dinamicas
    if (id === 'players') App.post('reqPlayers');
    if (id === 'reports') App.post('reqReports');
    if (id === 'logs')    App.post('reqLogs', { limit: 100 });
  };

  document.querySelectorAll('.tab').forEach(t => t.onclick = () => App.switchView(t.dataset.view));
  document.querySelectorAll('[data-close]').forEach(el => el.onclick = () => App.post('close'));
  document.addEventListener('keydown', e => { if (e.key === 'Escape') App.post('close'); });

  // refresh global
  document.getElementById('btn-refresh').onclick = () => App.switchView(App.state.view || 'dashboard');

  // quick actions (dashboard)
  document.querySelectorAll('[data-quick]').forEach(b => b.onclick = async () => {
    const k = b.dataset.quick;
    if (k === 'announce') {
      const r = await App.modal({
        title: 'An ncio global',
        html: `<label>Mensagem (at  220 caracteres)</label><textarea data-field="message" maxlength="220"></textarea>`,
        okText: 'Anunciar',
      });
      if (r.ok) App.post('act', { action: 'announce', fields: r.fields });
      return;
    }
    App.post('act', { action: k, fields: {} });
  });

  // flag toggles (header)
  document.querySelectorAll('.flag').forEach(f => f.onclick = () => {
    App.post('act', { action: f.dataset.act, fields: {} });
  });

  // listener postMessage
  window.addEventListener('message', (ev) => {
    const m = ev.data || {};
    switch (m.action) {
      case 'open':
        document.getElementById('bg').classList.remove('hidden');
        document.getElementById('panel').classList.remove('hidden');
        App.state.actions = m.data?.actions || {};
        App.state.flags   = m.data?.flags   || {};
        App.renderActions?.();
        App.switchView(m.data?.view || 'dashboard');
        App.syncFlags();
        break;
      case 'close':
        document.getElementById('panel').classList.add('hidden');
        document.getElementById('bg').classList.add('hidden');
        document.getElementById('modal-bg').classList.add('hidden');
        break;
      case 'playerList':  App.renderPlayers?.(m.data); break;
      case 'rgInfo':      App.renderRG?.(m.data); break;
      case 'reportList':  App.renderReports?.(m.data); break;
      case 'logList':     App.renderLogs?.(m.data); break;
      case 'toast':       App.toast(m.data?.text, m.data?.kind); break;
      case 'announce':    App.announce(m.data?.text || ''); break;
      case 'stateSync':   Object.assign(App.state.flags || {}, m.data || {}); App.syncFlags(); break;
      case 'specHud':
        const hud = document.getElementById('spec-hud');
        if (m.data?.on) { document.getElementById('spec-id').textContent = m.data.target; hud.classList.remove('hidden'); }
        else hud.classList.add('hidden');
        break;
    }
  });

  App.syncFlags = () => {
    const f = App.state.flags || {};
    document.getElementById('f-noclip').classList.toggle('on', !!f.noclip);
    document.getElementById('f-god').classList.toggle('on', !!f.god);
    document.getElementById('f-invis').classList.toggle('on', !!f.invis);
  };

  App.fmtMoney = (n) => 'R$ ' + (n || 0).toLocaleString('pt-BR');
  App.fmtDate  = (ts) => ts ? new Date(ts * 1000).toLocaleString('pt-BR', { day:'2-digit', month:'2-digit', hour:'2-digit', minute:'2-digit' }) : ' ';
})();
