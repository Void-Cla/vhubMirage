// Bootstrap NUI. Nenhum dado de dominio entra em HTML interpretado.
(() => {
  const App = (window.vhubApp = {
    resName: 'vhub_garage',
    state: { view: null, payload: null },
    views: {},
  });

  App.post = async (callback, data = {}) => {
    try {
      const response = await fetch(`https://${App.resName}/${callback}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
      });
      return await response.json().catch(() => ({}));
    } catch (_) { return {}; }
  };

  App.el = (tag, className, text) => {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined && text !== null) node.textContent = String(text);
    return node;
  };
  App.clear = (node) => node.replaceChildren();
  App.icon = (name) => App.el('i', `fa-solid fa-${name}`);
  App.button = (text, classes = '', icon = null) => {
    const button = App.el('button', `btn ${classes}`.trim());
    button.type = 'button';
    if (icon) button.append(App.icon(icon));
    button.append(document.createTextNode(text));
    return button;
  };
  App.empty = (container, icon, text) => {
    const empty = App.el('div', 'empty-state');
    empty.append(App.icon(icon), App.el('span', '', text));
    container.replaceChildren(empty);
  };
  App.vehicleVisual = (type, large = false) => {
    const names = { car:'car', bike:'motorcycle', plane:'plane', heli:'helicopter',
      boat:'ship', truck:'truck', trailer:'truck-moving' };
    const box = App.el('div', large ? 'img' : 'thumb');
    box.append(App.icon(names[type] || 'car'));
    return box;
  };
  App.tag = (text, warn = false) => App.el('span', `tag${warn ? ' warn' : ''}`, text);
  App.infoLine = (key, value, valueClass = '') => {
    const line = App.el('div', 'info-line');
    line.append(App.el('span', 'k', key), App.el('span', `v ${valueClass}`.trim(), value));
    return line;
  };
  App.stat = (label, raw) => {
    const value = Math.min(100, Math.max(0, Number(raw) || 0));
    const stat = App.el('div', 'stat');
    const bar = App.el('span', 'bar');
    const fill = App.el('span');
    fill.style.width = `${value}%`;
    bar.append(fill);
    stat.append(App.el('span', 'label', label), bar, App.el('span', 'v', value));
    return stat;
  };
  App.field = (label, name, options = {}) => {
    const wrap = App.el('div');
    const caption = App.el('label', '', label);
    const input = App.el(options.multiline ? 'textarea' : 'input');
    input.dataset.field = name;
    if (!options.multiline) input.type = options.type || 'text';
    for (const key of ['value', 'placeholder', 'min', 'max', 'maxLength']) {
      if (options[key] !== undefined) input[key] = options[key];
    }
    wrap.append(caption, input);
    return wrap;
  };

  const toast = document.getElementById('vhub-toast');
  let toastTimer = null;
  App.toast = (message, type = 'info', ttl = 3500) => {
    toast.textContent = String(message || '');
    toast.classList.remove('hidden');
    toast.style.borderColor = type === 'err' ? 'rgba(232,81,63,0.7)'
      : type === 'ok' ? 'rgba(107,191,107,0.7)' : 'rgba(243,181,58,0.7)';
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => toast.classList.add('hidden'), Number(ttl) || 3500);
  };

  const modalBg = document.getElementById('modal-bg');
  const modalTitle = document.getElementById('modal-title');
  const modalBody = document.getElementById('modal-body');
  const modalOk = document.getElementById('modal-ok');
  const modalCancel = document.getElementById('modal-cancel');
  App.modal = (options = {}) => new Promise((resolve) => {
    modalTitle.textContent = String(options.title || 'Confirmar');
    modalBody.replaceChildren();
    if (options.text) modalBody.append(App.el('p', '', options.text));
    for (const field of options.fields || []) {
      modalBody.append(App.field(field.label, field.name, field));
    }
    modalOk.textContent = String(options.okText || 'Confirmar');
    modalCancel.textContent = String(options.cancelText || 'Cancelar');
    const close = (value) => {
      modalBg.classList.add('hidden');
      modalOk.onclick = null;
      modalCancel.onclick = null;
      resolve(value);
    };
    modalOk.onclick = () => {
      const fields = {};
      modalBody.querySelectorAll('[data-field]').forEach((field) => {
        fields[field.dataset.field] = field.value;
      });
      close({ ok: true, fields });
    };
    modalCancel.onclick = () => close({ ok: false, fields: {} });
    modalBg.classList.remove('hidden');
  });

  App.show = (id) => {
    document.querySelectorAll('.vhub-view').forEach((view) => view.classList.add('hidden'));
    document.getElementById('vhub-bg').classList.remove('hidden');
    window.vhubSand?.start();
    if (id) document.getElementById(id)?.classList.remove('hidden');
  };
  App.hideAll = () => {
    document.querySelectorAll('.vhub-view').forEach((view) => view.classList.add('hidden'));
    document.getElementById('vhub-bg').classList.add('hidden');
    modalBg.classList.add('hidden');
    window.vhubSand?.stop();
  };

  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') App.post('close');
  });
  document.addEventListener('click', (event) => {
    if (event.target.closest('[data-close]')) App.post('close');
  });

  window.addEventListener('message', (event) => {
    const message = event.data || {};
    const routes = {
      openGarage: ['garage', 'view-garage'],
      openDealership: ['dealer', 'view-dealer'],
      openAuction: ['auction', 'view-auction'],
      openImpound: ['impound', 'view-impound'],
    };
    if (routes[message.action]) {
      const [view, element] = routes[message.action];
      App.state.view = view;
      App.state.payload = message.data || {};
      App.views[view]?.render(App.state.payload);
      App.show(element);
    } else if (message.action === 'refresh' && App.state.view) {
      App.state.payload = message.data || App.state.payload;
      App.views[App.state.view]?.render(App.state.payload);
    } else if (message.action === 'notify') {
      App.toast(message.data?.text, message.data?.kind, message.data?.ttl);
    } else if (message.action === 'close') {
      App.hideAll();
    }
  });

  App.fmtMoney = (value) => `R$ ${Math.max(0, Number(value) || 0).toLocaleString('pt-BR')}`;
  App.fmtDate = (timestamp) => timestamp ? new Date(Number(timestamp) * 1000).toLocaleString('pt-BR',
    { day:'2-digit', month:'2-digit', year:'2-digit', hour:'2-digit', minute:'2-digit' }) : '—';
  App.fmtDur = (raw) => {
    const seconds = Math.max(0, Math.floor(Number(raw) || 0));
    if (seconds >= 86400) return `${Math.floor(seconds / 86400)}d ${Math.floor((seconds % 86400) / 3600)}h`;
    if (seconds >= 3600) return `${Math.floor(seconds / 3600)}h ${Math.floor((seconds % 3600) / 60)}m`;
    if (seconds >= 60) return `${Math.floor(seconds / 60)}m ${seconds % 60}s`;
    return `${seconds}s`;
  };
})();
