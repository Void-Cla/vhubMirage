// nui/js/app.js  bootstrap, postMessage router, modal/toast util
(() => {
  const App = (window.vhubApp = {
    resName: 'vhub_garage',
    state: { view: null, conc: null, garagem: null, payload: null },
    views: {},
  });

  // ---------- POST helper ---------------------------------------------------
  App.post = async (callback, data = {}) => {
    try {
      const resp = await fetch(`https://${App.resName}/${callback}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
      });
      return await resp.json().catch(() => ({}));
    } catch (e) { return {}; }
  };

  // ---------- Toast ---------------------------------------------------------
  const $toast = document.getElementById('vhub-toast');
  let toastT = null;
  App.toast = (msg, type = 'info', ttl = 3500) => {
    $toast.textContent = msg;
    $toast.classList.remove('hidden');
    if (type === 'err')  $toast.style.borderColor = 'rgba(255,91,110,0.6)';
    else if (type === 'ok') $toast.style.borderColor = 'rgba(107,214,107,0.6)';
    else $toast.style.borderColor = 'rgba(76,200,255,0.6)';
    if (toastT) clearTimeout(toastT);
    toastT = setTimeout(() => $toast.classList.add('hidden'), ttl);
  };

  // ---------- Modal universal ----------------------------------------------
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
    const close = (val) => {
      $mbg.classList.add('hidden');
      $mok.onclick = null; $mc.onclick = null;
      resolve(val);
    };
    $mok.onclick = () => {
      const fields = {};
      $mb.querySelectorAll('[data-field]').forEach((el) => {
        fields[el.dataset.field] = el.value;
      });
      close({ ok: true, fields });
    };
    $mc.onclick = () => close({ ok: false });
    $mbg.classList.remove('hidden');
  });

  // ---------- View router ---------------------------------------------------
  App.show = (id) => {
    document.querySelectorAll('.vhub-view').forEach((v) => v.classList.add('hidden'));
    document.getElementById('vhub-bg').classList.remove('hidden');
    if (id) document.getElementById(id).classList.remove('hidden');
  };
  App.hideAll = () => {
    document.querySelectorAll('.vhub-view').forEach((v) => v.classList.add('hidden'));
    document.getElementById('vhub-bg').classList.add('hidden');
    $mbg.classList.add('hidden');
  };

  // ---------- ESC + close buttons + tecla "B" ------------------------------
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') App.post('close');
  });
  document.addEventListener('click', (e) => {
    const t = e.target.closest('[data-close]');
    if (t) App.post('close');
  });

  // ---------- Mensagens vindas do client.lua --------------------------------
  window.addEventListener('message', (ev) => {
    const m = ev.data || {};
    switch (m.action) {
      case 'openGarage':
        App.state.view = 'garage'; App.state.payload = m.data;
        App.views.garage?.render(m.data); App.show('view-garage'); break;
      case 'openDealership':
        App.state.view = 'dealer'; App.state.payload = m.data;
        App.views.dealer?.render(m.data); App.show('view-dealer'); break;
      case 'openAuction':
        App.state.view = 'auction'; App.state.payload = m.data;
        App.views.auction?.render(m.data); App.show('view-auction'); break;
      case 'openImpound':
        App.state.view = 'impound'; App.state.payload = m.data;
        App.views.impound?.render(m.data); App.show('view-impound'); break;
      case 'refresh':
        // qual view est  ativa? recarrega ela
        if (App.state.view && App.views[App.state.view]?.render) {
          App.views[App.state.view].render(m.data || App.state.payload);
        }
        break;
      case 'notify':
        App.toast(m.data?.text || '', m.data?.kind || 'info', m.data?.ttl);
        break;
      case 'close':
        App.hideAll();
        break;
    }
  });

  // ---------- Imagem do ve culo (FiveM docs fallback) ----------------------
  App.imgFor = (model) => {
    if (!model) return null;
    return `https://docs.fivem.net/vehicles/${model}.webp`;
  };

  // ---------- Format helpers ------------------------------------------------
  App.fmtMoney = (n) => 'R$ ' + (n || 0).toLocaleString('pt-BR');
  App.fmtDate  = (ts) => ts ? new Date(ts * 1000).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', year: '2-digit', hour: '2-digit', minute: '2-digit' }) : ' ';
  App.fmtDur   = (s) => {
    s = Math.max(0, Math.floor(s));
    if (s >= 86400) return `${Math.floor(s/86400)}d ${Math.floor((s%86400)/3600)}h`;
    if (s >= 3600)  return `${Math.floor(s/3600)}h ${Math.floor((s%3600)/60)}m`;
    if (s >= 60)    return `${Math.floor(s/60)}m ${s%60}s`;
    return `${s}s`;
  };
})();
