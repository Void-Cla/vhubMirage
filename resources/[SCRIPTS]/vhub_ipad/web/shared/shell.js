// web/shared/shell.js — controlador do shell do iPad.
//
// WRITER ÚNICO do slice store('ipad') (A-04). Módulos LEEM o slice e EMITEM
// intenções pelo bus; o shell aplica, persiste (vhub.post) e re-emite o evento
// de mudança. Sem segunda fonte de verdade dentro da NUI.


(() => {
  'use strict';


  // ============================================================
  // STATE
  // ============================================================

  const ui = vhub.store('ipad');   // { catalog, version, installed[], prefs{}, wallpapers[] }

  let clockTimer    = null;
  let currentModule = null;
  let history       = [];


  // ============================================================
  // CLOCK
  // ============================================================

  function startClock() {
    if (clockTimer) return;
    const el = document.getElementById('ipad-clock');
    const tick = () => { if (el) el.textContent = vhub.clock(); };
    tick();
    clockTimer = setInterval(tick, 30000);
  }

  function stopClock() {
    if (clockTimer) { clearInterval(clockTimer); clockTimer = null; }
  }


  // ============================================================
  // PREFERÊNCIAS (zoom + wallpaper)
  // ============================================================

  function applyZoom(zoom) {
    const c = document.getElementById('ipad-container');
    if (c && typeof zoom === 'number') {
      c.style.width = Math.max(30, Math.min(100, zoom)) + 'vw';
    }
  }

  function applyWallpaper() {
    const st = ui.get();
    const wp = document.getElementById('ipad-wallpaper');
    if (wp) wp.style.backgroundImage = vhub.wallpaperStyle(st.prefs, st.wallpapers);
  }

  function applyPrefs() {
    const st = ui.get();
    applyZoom(st.prefs && st.prefs.zoom);
    applyWallpaper();
  }


  // ============================================================
  // NAVEGAÇÃO (sem router — orquestrada pelo shell)
  // ============================================================

  // entry (URLs) do app no catálogo; 'home' usa o padrão local do loader
  function entryFor(id) {
    if (id === 'home') return undefined;
    const st = ui.get();
    return st.catalog && st.catalog[id] && st.catalog[id].entry;
  }

  async function navigateTo(id) {
    if (id === currentModule) return;
    if (currentModule) { vhub.hide(currentModule); history.push(currentModule); }
    currentModule = id;
    vhub.app.setActive(id);                 // roteia o relay para o app ativo
    await vhub.show(id, entryFor(id));
  }

  function goHome() {
    history = [];
    if (currentModule && currentModule !== 'home') vhub.hide(currentModule);
    currentModule = 'home';
    vhub.app.setActive('home');
    vhub.show('home');
  }

  function goBack() {
    if (history.length === 0) return goHome();
    const prev = history.pop();
    if (currentModule) vhub.hide(currentModule);
    currentModule = prev;
    vhub.app.setActive(prev);
    vhub.show(prev, entryFor(prev));
  }


  // ============================================================
  // OPEN / CLOSE
  // ============================================================

  function openIpad(data) {
    data = data || {};
    ui.set({
      catalog:    data.apps        || {},
      version:    data.catalog_version,
      installed:  data.installed   || [],
      prefs:      data.prefs       || {},
      wallpapers: data.wallpapers  || [],
    });
    if (typeof data.cdn === 'string') vhub.cdn = data.cdn;
    if (data.cdn_ver != null) vhub.cdnVer = data.cdn_ver;   // cache-bust por boot

    applyPrefs();
    document.body.classList.add('visible');
    startClock();

    currentModule = null;
    history = [];
    goHome();

    vhub.bus.emit('ipad:opened', {});
  }

  function closeIpad() {
    stopClock();
    // pausa timers/RAF do módulo aberto (onHide) — zero custo com NUI fechada
    if (currentModule) vhub.hide(currentModule);
    document.body.classList.remove('visible');
    vhub.post('close', {});
  }


  // ============================================================
  // ESTADO per-char atualizado (pós-mutação no servidor)
  // ============================================================

  function onState(data) {
    if (!data || !data.installed) return;
    ui.set({ installed: data.installed });
    vhub.bus.emit('ipad:installed_changed', { installed: data.installed });
  }


  // ============================================================
  // INTENÇÕES DOS MÓDULOS (bus) — o shell é o writer
  // ============================================================

  // home pediu para abrir um app
  vhub.bus.listen('ipad:open_app', (d) => { if (d && d.id) navigateTo(d.id); });

  // settings pediu para mudar uma preferência (aplica otimista + persiste)
  vhub.bus.listen('ipad:set_pref', (p) => {
    if (!p || typeof p !== 'object') return;
    const prefs = Object.assign({}, ui.get().prefs, p);
    ui.set({ prefs });
    if ('zoom' in p) applyZoom(p.zoom);
    if ('wallpaper_id' in p || 'wallpaper_custom' in p) applyWallpaper();
    vhub.post('setPref', p);
  });

  // loja pediu para instalar um app (otimista + persiste; STATE reconcilia)
  vhub.bus.listen('ipad:install_app', (d) => {
    if (!d || !d.id) return;
    const inst = ui.get().installed || [];
    if (!inst.includes(d.id)) ui.set({ installed: inst.concat([d.id]) });
    vhub.bus.emit('ipad:installed_changed', { installed: ui.get().installed });
    vhub.post('install', { id: d.id });
  });

  // loja pediu para remover um app
  vhub.bus.listen('ipad:uninstall_app', (d) => {
    if (!d || !d.id) return;
    const inst = (ui.get().installed || []).filter((x) => x !== d.id);
    ui.set({ installed: inst });
    vhub.bus.emit('ipad:installed_changed', { installed: inst });
    // se estava vendo o app removido, volta para a home
    if (currentModule === d.id) goHome();
    vhub.post('uninstall', { id: d.id });
  });


  // ============================================================
  // EVENTOS NUI (do Lua) + navbar + teclado
  // ============================================================

  vhub.bus.listen('nui:open',  openIpad);
  vhub.bus.listen('nui:close', closeIpad);
  vhub.bus.listen('nui:state', onState);

  document.addEventListener('DOMContentLoaded', () => {
    const nav = document.getElementById('ipad-navbar');
    if (nav) nav.addEventListener('click', (e) => {
      const b = e.target.closest('[data-nav]'); if (!b) return;
      const a = b.dataset.nav;
      if (a === 'back') goBack();
      else if (a === 'home') goHome();
      else if (a === 'close') closeIpad();
    });
  });

  document.addEventListener('keydown', (e) => { if (e.key === 'Escape') closeIpad(); });


  // ============================================================
  // HANDSHAKE
  // ============================================================

  vhub.post('nui_ready', {});

  window._ipad = { goHome, navigateTo, openIpad, closeIpad };

})();
