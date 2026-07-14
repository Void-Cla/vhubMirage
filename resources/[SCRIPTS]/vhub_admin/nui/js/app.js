// app.js — núcleo da NUI: aside popover, router, builders seguros, modal tipado
// A-09: sem backdrop-filter (aside/popover = fundo opaco sem blur do mundo)
// A-10: zero CDN — sistema de fontes, SVG inline
// Anti-XSS: dado de servidor SEMPRE via textContent. innerHTML apenas p/ SVG literal (ICONS).
(() => {
  const App = (window.vhubAdmin = { res: 'vhub_admin', state: {} });

  App.post = async (cb, data = {}) => {
    try {
      const r = await fetch(`https://${App.res}/${cb}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
      });
      return await r.json().catch(() => ({}));
    } catch (e) { return {}; }
  };


  // ============================================================
  // BUILDERS SEGUROS (anti-XSS)
  // ============================================================

  // cria elemento com classe e texto via textContent — nunca innerHTML de dado externo
  App.el = (tag, cls, text) => {
    const n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text !== undefined && text !== null) n.textContent = text;
    return n;
  };


  // ============================================================
  // ÍCONES SVG (literais controlados — único caso de innerHTML permitido)
  // ============================================================

  const S = (p) => `<svg viewBox="0 0 24 24" aria-hidden="true">${p}</svg>`;

  const ICONS = {
    gauge:   S('<path d="M12 15l4-6"/><path d="M4 17a9 9 0 1 1 16 0"/><circle cx="12" cy="16" r="1.2"/>'),
    users:   S('<circle cx="9" cy="8" r="3.2"/><path d="M3.5 19c.6-3 2.8-4.6 5.5-4.6s4.9 1.6 5.5 4.6"/><circle cx="17" cy="9" r="2.4"/><path d="M15.8 14.7c2.3.2 4 1.6 4.6 4"/>'),
    bolt:    S('<path d="M13 3L5 13.5h5L10.5 21 19 10.5h-5.5z"/>'),
    flag:    S('<path d="M5 21V4"/><path d="M5 5h13l-2.5 3.5L18 12H5"/>'),
    scroll:  S('<path d="M6 4h12v16H6z"/><path d="M9 8h6M9 12h6M9 16h4"/>'),
    shield:  S('<path d="M12 3l7 3v5c0 4.5-2.9 8-7 10-4.1-2-7-5.5-7-10V6z"/>'),
    eyeoff:  S('<path d="M4 4l16 16"/><path d="M10 10a2.5 2.5 0 0 0 3.5 3.5"/><path d="M7 7C4.8 8.3 3.3 10.2 2.5 12c1.6 3.6 5.2 6 9.5 6 1.6 0 3.1-.3 4.4-.9M12 6c4.3 0 7.9 2.4 9.5 6-.5 1.1-1.2 2.2-2.1 3.1"/>'),
    feather: S('<path d="M19 5c-4 0-11 2-13 10l-2 6"/><path d="M6 15c4 1 9 0 12-4 1.5-2 1.6-4.5 1-6-1.5-.6-4-.5-6 1"/><path d="M9 12h5"/>'),
    close:   S('<path d="M6 6l12 12M18 6L6 18"/>'),
    sync:    S('<path d="M20 11a8 8 0 0 0-14.9-3M4 13a8 8 0 0 0 14.9 3"/><path d="M20 4v4h-4M4 20v-4h4"/>'),
    coins:   S('<ellipse cx="12" cy="6.5" rx="7" ry="3"/><path d="M5 6.5V12c0 1.7 3.1 3 7 3s7-1.3 7-3V6.5"/><path d="M5 12v5.5c0 1.7 3.1 3 7 3s7-1.3 7-3V12"/>'),
    clock:   S('<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/>'),
    heart:   S('<path d="M12 20s-7-4.6-9-9c-1.2-2.7.5-6 3.7-6 1.9 0 3.4 1.1 4.3 2.6h2C13.9 6.1 15.4 5 17.3 5c3.2 0 4.9 3.3 3.7 6-2 4.4-9 9-9 9z"/>'),
    marker:  S('<path d="M12 21s-6.5-5.8-6.5-10.5a6.5 6.5 0 0 1 13 0C18.5 15.2 12 21 12 21z"/><circle cx="12" cy="10.5" r="2.3"/>'),
    horn:    S('<path d="M4 10v4h3l6 4V6l-6 4z"/><path d="M17 9a4.5 4.5 0 0 1 0 6"/>'),
    back:    S('<path d="M9 14L4 9l5-5"/><path d="M4 9h10a6 6 0 0 1 0 12h-3"/>'),
  };

  // retorna nó SVG pelo nome
  App.icon = (name) => {
    const w = document.createElement('span');
    w.style.cssText = 'display:contents';
    w.innerHTML = ICONS[name] || '';
    return w.firstChild || document.createTextNode('');
  };


  // ============================================================
  // TOAST
  // ============================================================

  const $toast = document.getElementById('toast');
  let _toastT = null;
  App.toast = (msg, type = 'info', ttl = 3500) => {
    $toast.textContent = msg;
    $toast.style.borderColor =
      type === 'err' ? 'rgba(232,81,63,0.7)' :
      type === 'ok'  ? 'rgba(107,191,107,0.7)' :
                       'rgba(243,181,58,0.7)';
    $toast.classList.remove('hidden');
    clearTimeout(_toastT);
    _toastT = setTimeout(() => $toast.classList.add('hidden'), ttl);
  };

  const $ann = document.getElementById('announce');
  let _annT = null;
  App.announce = (text) => {
    $ann.querySelector('div').textContent = text;
    $ann.classList.remove('hidden');
    clearTimeout(_annT);
    _annT = setTimeout(() => $ann.classList.add('hidden'), 9000);
  };


  // ============================================================
  // MODAL TIPADO — campos: text|number|textarea|select|color
  // ============================================================

  const $mbg = document.getElementById('modal-bg');
  const $mt  = document.getElementById('modal-title');
  const $mb  = document.getElementById('modal-body');
  const $mok = document.getElementById('modal-ok');
  const $mc  = document.getElementById('modal-cancel');

  function buildField(f) {
    const wrap = document.createDocumentFragment();
    wrap.appendChild(App.el('label', null, f.label || f.k));

    let input;
    if (f.type === 'select' || f.type === 'player') {
      const opts = f.options || [];
      if (!opts.length) {
        input = App.el('input'); input.type = 'text';
        input.placeholder = f.placeholder || '';
      } else {
        input = App.el('select');
        if (f.blank !== false) {
          const o = App.el('option', null, '— selecionar —'); o.value = '';
          input.appendChild(o);
        }
        opts.forEach(op => {
          const o = App.el('option', null, op.label);
          o.value = op.value;
          if (String(op.value) === String(f.value ?? '')) o.selected = true;
          input.appendChild(o);
        });
        if (f.custom) {
          const o = App.el('option', null, '✎ digitar manualmente…');
          o.value = '__custom'; input.appendChild(o);
        }
      }
    } else if (f.type === 'checkbox') {
      input = App.el('input');
      input.type = 'checkbox';
      input.checked = f.value === true;
    } else if (f.type === 'textarea') {
      input = App.el('textarea');
      input.maxLength = f.max || 500;
      input.placeholder = f.placeholder || '';
    } else if (f.type === 'color') {
      input = App.el('input');
      input.type = 'color';
      input.value = f.value || '#f3b53a';
    } else {
      input = App.el('input');
      input.type = f.type === 'number' ? 'number' : 'text';
      if (f.min  !== undefined) input.min  = f.min;
      if (f.max  !== undefined) input.max  = f.max;
      if (f.maxlen) input.maxLength = f.maxlen;
      if (f.value !== undefined) input.value = f.value;
      input.placeholder = f.placeholder || '';
    }
    input.dataset.field = f.k;
    wrap.appendChild(input);

    if (f.custom && input.tagName === 'SELECT') {
      const free = App.el('input');
      free.type = 'text'; free.placeholder = f.placeholder || 'valor personalizado';
      free.dataset.customFor = f.k; free.classList.add('hidden');
      free.style.marginTop = '5px';
      input.addEventListener('change', () =>
        free.classList.toggle('hidden', input.value !== '__custom'));
      wrap.appendChild(free);
    }
    return wrap;
  }

  // abre modal; opts = { title, text, fields:[spec], okText, cancelText }
  App.modal = (opts) => new Promise((resolve) => {
    $mt.textContent = opts.title || 'Confirmar';
    $mb.textContent = '';
    if (opts.text) $mb.appendChild(App.el('p', null, opts.text));
    (opts.fields || []).forEach(f => $mb.appendChild(buildField(f)));
    $mok.textContent = opts.okText  || 'Confirmar';
    $mc.textContent  = opts.cancelText || 'Cancelar';

    const close = (val) => {
      $mbg.classList.add('hidden');
      $mok.onclick = null; $mc.onclick = null;
      resolve(val);
    };
    $mok.onclick = () => {
      const fields = {};
      $mb.querySelectorAll('[data-field]').forEach((el) => {
        let v = el.type === 'checkbox' ? el.checked : el.value;
        if (v === '__custom') {
          const free = $mb.querySelector(`[data-custom-for="${el.dataset.field}"]`);
          v = free ? free.value : '';
        }
        fields[el.dataset.field] = v;
      });
      close({ ok: true, fields });
    };
    $mc.onclick = () => close({ ok: false });
    $mbg.classList.remove('hidden');
  });


  // ============================================================
  // ROUTER — aside (seções) + popover (subcategorias + conteúdo)
  // ============================================================

  const SECTIONS = [
    { id: 'dashboard', label: 'Painel',    icon: 'gauge',
      subs: [{ id: 'geral', label: 'Geral' }, { id: 'economia', label: 'Economia' }] },
    { id: 'players',   label: 'Jogadores', icon: 'users',
      search: 'Buscar nome, ID, UID' },
    { id: 'actions',   label: 'Ações',     icon: 'bolt',
      subs: [
        { id: 'moderation', label: 'Mod' },
        { id: 'teleport',   label: 'TP' },
        { id: 'player',     label: 'Jogador' },
        { id: 'vehicle',    label: 'Veículo' },
        { id: 'world',      label: 'Mundo' },
        { id: 'economy',    label: 'Economia' },
        { id: 'inventory',  label: 'Inv' },
        { id: 'groups',     label: 'Grupos' },
      ],
      search: 'Filtrar ações' },
    { id: 'fleet',     label: 'Frota',     icon: 'feather',
      search: 'Buscar placa, modelo, dono' },
    { id: 'reports',   label: 'Denúncias', icon: 'flag',
      subs: [
        { id: 'open',    label: 'Abertas' },
        { id: 'claimed', label: 'Em atend.' },
        { id: 'closed',  label: 'Fechadas' },
        { id: 'all',     label: 'Todas' },
      ] },
    { id: 'logs', label: 'Histórico', icon: 'scroll',
      search: 'Filtrar logs' },
  ];

  const VIEW_OF = (sec, sub) => {
    if (sec === 'dashboard') return sub === 'economia' ? 'view-dash-economia' : 'view-dash-geral';
    if (sec === 'actions')   return 'view-actions';
    return 'view-' + sec;
  };

  const $aside   = document.getElementById('aside');
  const $anav    = document.getElementById('aside-nav');
  const $popover = document.getElementById('popover');
  const $title   = document.getElementById('pop-title');
  const $subtabs = document.getElementById('subtabs');
  const $search  = document.getElementById('tb-search');

  App.searchHooks  = {};
  App.sectionHooks = {};
  App.renderSection = (sec, sub) => App.sectionHooks[sec]?.(sub);

  let _activeSec = null;

  // constrói botões do aside (uma vez)
  function buildAside() {
    $anav.textContent = '';
    SECTIONS.forEach(s => {
      const b = App.el('button', 'abtn');
      b.dataset.sec = s.id;
      b.dataset.label = s.label;
      b.appendChild(App.icon(s.icon));
      if (s.id === 'reports') {
        const badge = App.el('span', 'badge hidden', '0');
        badge.id = 'r-badge'; b.appendChild(badge);
      }
      b.onclick = () => {
        if (_activeSec === s.id && !$popover.classList.contains('hidden')) {
          // segundo clique fecha o popover
          $popover.classList.add('hidden');
          b.classList.remove('active');
          _activeSec = null;
        } else {
          App.go(s.id);
        }
      };
      $anav.appendChild(b);
    });
  }

  // fecha popover ao clicar fora (no jogo)
  document.addEventListener('mousedown', (e) => {
    if (!$popover.contains(e.target) && !$aside.contains(e.target)) {
      $popover.classList.add('hidden');
      $anav.querySelectorAll('.abtn').forEach(b => b.classList.remove('active'));
      _activeSec = null;
    }
  });

  function refreshSection(sec) {
    if (sec === 'dashboard') App.post('reqDash');
    if (sec === 'players')   App.post('reqPlayers');
    if (sec === 'actions')   { App.post('reqPlayers'); App.post('reqPickers'); }
    if (sec === 'fleet')     App.post('reqFleet');
    if (sec === 'reports')   App.post('reqReports');
    if (sec === 'logs')      App.post('reqLogs', { limit: 200 });
  }

  // navega para seção (abre popover) + subcategoria opcional
  App.go = (secId, subId) => {
    const sec = SECTIONS.find(s => s.id === secId) || SECTIONS[0];
    const sub = sec.subs
      ? (subId || App.state.subOf?.[secId] || sec.subs[0].id)
      : null;

    App.state.section = sec.id;
    App.state.sub = sub;
    App.state.subOf = App.state.subOf || {};
    if (sub) App.state.subOf[sec.id] = sub;
    _activeSec = sec.id;

    // aside: ativa botão correto
    $anav.querySelectorAll('.abtn').forEach(b =>
      b.classList.toggle('active', b.dataset.sec === sec.id));

    // topbar: título + subcategorias
    $title.textContent = sec.label;
    $subtabs.textContent = '';
    (sec.subs || []).forEach(st => {
      const b = App.el('button', 'subtab' + (st.id === sub ? ' active' : ''), st.label);
      b.onclick = () => App.go(sec.id, st.id);
      $subtabs.appendChild(b);
    });

    // busca contextual
    if (sec.search) {
      $search.placeholder = sec.search;
      $search.classList.remove('hidden');
    } else {
      $search.classList.add('hidden');
    }
    $search.value = '';

    // troca de view
    document.querySelectorAll('.view').forEach(v => v.classList.add('hidden'));
    document.getElementById(VIEW_OF(sec.id, sub))?.classList.remove('hidden');

    // abre o popover
    $popover.classList.remove('hidden');

    refreshSection(sec.id);
    App.renderSection?.(sec.id, sub);
  };

  $search.addEventListener('input', () =>
    App.searchHooks[App.state.section]?.($search.value || ''));

  const $refresh = document.getElementById('btn-refresh');
  $refresh.appendChild(App.icon('sync'));
  $refresh.onclick = () =>
    App.state.section && App.go(App.state.section, App.state.sub);

  const $close = document.getElementById('btn-close');
  $close.appendChild(App.icon('close'));
  $close.onclick = () => {
    $popover.classList.add('hidden');
    $anav.querySelectorAll('.abtn').forEach(b => b.classList.remove('active'));
    _activeSec = null;
  };

  document.addEventListener('keydown', e => {
    if (e.key === 'Escape') {
      if (!$mbg.classList.contains('hidden')) {
        $mbg.classList.add('hidden');
      } else if (!$popover.classList.contains('hidden')) {
        $popover.classList.add('hidden');
        $anav.querySelectorAll('.abtn').forEach(b => b.classList.remove('active'));
        _activeSec = null;
      } else {
        App.post('close');
      }
    }
  });


  // ============================================================
  // FLAGS RÁPIDAS (god / invis / noclip)
  // ============================================================

  const $fgod    = document.getElementById('f-god');
  const $finvis  = document.getElementById('f-invis');
  const $fnoclip = document.getElementById('f-noclip');

  $fgod.appendChild(App.icon('shield'));
  $finvis.appendChild(App.icon('eyeoff'));
  $fnoclip.appendChild(App.icon('feather'));

  $fgod.onclick    = () => App.post('act', { action: 'god',   fields: {} });
  $finvis.onclick  = () => App.post('act', { action: 'invis', fields: {} });
  $fnoclip.onclick = () => App.post('noclip');

  App.syncFlags = () => {
    const f = App.state.flags || {};
    $fnoclip.classList.toggle('on', !!f.noclip);
    $fgod.classList.toggle('on', !!f.god);
    $finvis.classList.toggle('on', !!f.invis);
  };


  // ============================================================
  // LISTENER postMessage (Lua → NUI)
  // ============================================================

  window.addEventListener('message', (ev) => {
    const m = ev.data || {};
    switch (m.action) {
      case 'open':
        $aside.classList.remove('hidden');
        const selectors = m.data?.selectors || {};
        App.state.actions  = m.data?.actions  || {};
        App.state.zones    = selectors.zones || [];
        App.state.weathers = selectors.weather || [];
        App.state.routes   = selectors.routes || [];
        App.state.minutes  = selectors.minutes || [];
        App.state.statuses = selectors.vehicleStatuses || [];
        App.state.flags    = m.data?.flags    || {};
        App.state.pickers  = {
          items: App.state.pickers?.items || [],
          vehicles: App.state.pickers?.vehicles || [],
          groups: selectors.groups || [],
        };
        // vai direto p/ a seção pedida (ou dashboard) e abre popover
        App.go(m.data?.view || 'dashboard');
        App.syncFlags();
        break;

      case 'close':
        $aside.classList.add('hidden');
        $popover.classList.add('hidden');
        $mbg.classList.add('hidden');
        _activeSec = null;
        break;

      case 'playerList':  App.renderPlayers?.(m.data); break;
      case 'profile':     App.renderRG?.(m.data);      break;
      case 'reportList':  App.renderReports?.(m.data); break;
      case 'logList':     App.renderLogs?.(m.data);    break;
      case 'dashboard':   App.renderDash?.(m.data);    break;
      case 'fleetList':   App.renderFleet?.(m.data);   break;
      case 'fleetDetail': App.renderFleetDetail?.(m.data); break;

      case 'pickerData':
        App.state.pickers = m.data || { items: [], groups: [], vehicles: [] };
        break;

      case 'toast':    App.toast(m.data?.text, m.data?.kind); break;
      case 'announce': App.announce(m.data?.text || '');       break;

      case 'stateSync':
        Object.assign(App.state.flags = App.state.flags || {}, m.data || {});
        App.syncFlags();
        break;

      case 'specHud': {
        const hud = document.getElementById('spec-hud');
        if (m.data?.on) {
          document.getElementById('spec-id').textContent = m.data.target;
          hud.classList.remove('hidden');
        } else hud.classList.add('hidden');
        break;
      }
    }
  });


  // ============================================================
  // FORMATADORES
  // ============================================================

  App.fmtMoney = (n) => 'R$ ' + (Number(n) || 0).toLocaleString('pt-BR');
  App.fmtDate  = (ts) => ts ? new Date(ts * 1000).toLocaleString('pt-BR',
    { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' }) : '—';
  App.fmtDur   = (ms) => {
    const s = Math.floor((Number(ms) || 0) / 1000);
    const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600),
          mn = Math.floor((s % 3600) / 60);
    if (d > 0) return `${d}d ${h}h`;
    if (h > 0) return `${h}h ${mn}m`;
    return `${mn}m`;
  };

  buildAside();
})();
