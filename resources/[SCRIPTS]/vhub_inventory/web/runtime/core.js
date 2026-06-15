// runtime/core.js — engine: lifecycle de modulo + dispatcher de mensagens.
// createModule/mount/unmount (A-02, A-05). Dispatcher roteia SendNUIMessage -> bus.

(function () {
  const modules = {};   // name -> spec
  const live    = {};   // name -> bool (montado)

  // registra modulo e roda onInit
  vhub.createModule = function (name, spec) {
    modules[name] = spec;
    if (spec.onInit) { try { spec.onInit(); } catch (e) { console.error('[init]', name, e); } }
  };

  // monta (insere no DOM/ativa) e mostra — lazy load
  vhub.mount = function (name) {
    const m = modules[name];
    if (!m || live[name]) return;
    live[name] = true;
    if (m.onMount) m.onMount();
    if (m.onShow) m.onShow();
  };

  // esconde, destroi (cleanup A-07) e libera
  vhub.unmount = function (name) {
    const m = modules[name];
    if (!m || !live[name]) return;
    if (m.onHide) m.onHide();
    if (m.onDestroy) m.onDestroy();
    live[name] = false;
  };

  vhub.isMounted = function (name) { return live[name] === true; };

  // ============================================================
  // DISPATCHER — Lua SendNUIMessage({action=...}) -> vhub.emit('nui:action')
  // ============================================================
  window.addEventListener('message', (ev) => {
    const d = ev.data || {};
    if (!d.action) return;
    vhub.emit('nui:' + d.action, d);
  });

  // ============================================================
  // HANDSHAKE — anuncia pronto ao Lua e distribui config/catalogo
  // ============================================================
  window.addEventListener('DOMContentLoaded', () => {
    vhub.post('nui_ready', {}).then((cfg) => {
      vhub.config = cfg || {};
      vhub.emit('nui:config', vhub.config);
    });
  });
})();
