// web/runtime/bus.js — event bus central do vhub_ipad (L3).
//
// Comunicacao inter-modulo SEMPRE passa por aqui. Modulo A nao acessa DOM
// ou estado de modulo B; A emite, B escuta. Convencao de nome: '<modulo>:<verbo>'.
//
// API:
//   bus.emit(name, payload)        publica evento, sem retorno
//   bus.listen(name, fn) -> off    registra handler, retorna funcao de unsubscribe
//   bus.off(name, fn)              remove handler especifico
//
// REGRA OBRIGATORIA (A-07): modulos devem GUARDAR a referencia do off()
// retornado por listen() e chamar no onDestroy. Sem isso, handler vaza
// quando o modulo eh desmontado.


(() => {
    'use strict';


    // ============================================================
    // STATE (private — apenas o bus toca)
    // ============================================================

    const _listeners = {};   // { [name:string]: Set<fn> }


    // ============================================================
    // API
    // ============================================================

    // Publica um evento. Nao espera retorno dos handlers (fire-and-forget).
    function emit(name, payload) {
        const set = _listeners[name];
        if (!set || set.size === 0) return;

        for (const fn of set) {
            try {
                fn(payload);
            } catch (err) {
                console.error(`[vhub.bus] erro em handler de '${name}':`, err);
            }
        }
    }


    // Registra handler para um evento. Retorna `off()` para cancelar.
    function listen(name, fn) {
        if (typeof fn !== 'function') return () => {};

        if (!_listeners[name]) _listeners[name] = new Set();
        _listeners[name].add(fn);

        return () => off(name, fn);
    }


    // Remove handler especifico de um evento.
    function off(name, fn) {
        const set = _listeners[name];
        if (!set) return;

        set.delete(fn);
        if (set.size === 0) delete _listeners[name];
    }


    // ============================================================
    // EXPORT
    // ============================================================

    window._vhubBus = { emit, listen, off };

})();
