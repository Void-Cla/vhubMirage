// app.js — DISPATCHER mínimo da NUI do lspdtool.
// Roteia cada mensagem (Lua → CEF) pelo PREFIXO do type ('radar:' | 'helicam:' | 'mdt:') para o
// módulo registrado. SEM store/bus/router/native-bridge (decisão do arquiteto: modular SEM engine).
// Cada módulo (web/modules/<n>/<n>.js) chama LSPD.register('<n>', { onMessage, onDestroy }).

(function () {
    'use strict';

    const LSPD = {
        _mods: {},

        // registra um módulo de overlay pelo seu prefixo (ex.: 'radar')
        register(name, spec) {
            this._mods[name] = spec;
        },

        // entrega a mensagem ao módulo dono do prefixo (ex.: 'radar:update' → módulo 'radar')
        _route(m) {
            const type = m && m.type;
            if (typeof type !== 'string') return;
            const mod = this._mods[type.split(':')[0]];
            if (mod && mod.onMessage) mod.onMessage(type, m);
        },

        // A-07: chama o cleanup de cada módulo (RAF/interval/listener próprios)
        _destroyAll() {
            for (const k in this._mods) {
                const mod = this._mods[k];
                if (mod && mod.onDestroy) mod.onDestroy();
            }
        },
    };

    window.LSPD = LSPD;

    // UM único listener central de mensagens; removido no unload (A-07)
    function onMessage(e) { LSPD._route(e.data || {}); }

    window.addEventListener('message', onMessage);
    window.addEventListener('unload', function () {
        window.removeEventListener('message', onMessage);
        LSPD._destroyAll();
    });
})();
