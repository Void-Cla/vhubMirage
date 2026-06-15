// runtime/bus.js — event bus central (emit / listen / off).
// Inter-modulo passa SEMPRE por aqui (A-03). Sem acesso direto entre modulos.

window.vhub = window.vhub || {};

(function () {
  const handlers = {};

  // inscreve handler; retorna funcao off()
  vhub.listen = function (evt, fn) {
    (handlers[evt] = handlers[evt] || []).push(fn);
    return function off() {
      handlers[evt] = (handlers[evt] || []).filter((h) => h !== fn);
    };
  };

  // publica evento (erros isolados — um handler quebrado nao derruba os outros)
  vhub.emit = function (evt, payload) {
    (handlers[evt] || []).forEach((fn) => {
      try { fn(payload); } catch (e) { console.error('[vhub bus]', evt, e); }
    });
  };
})();
