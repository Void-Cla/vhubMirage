// web/runtime/bridge.js — POST central para client/init.lua (L3).
//
// TODA chamada NUI→Lua passa por aqui. Modulos NUNCA chamam fetch() direto
// para o resource — sempre `vhub.post(action, data)`. Isso garante:
//   • tratamento de erro consistente
//   • timeout protegendo de fetch travado
//   • shape de resposta padronizado { ok, data?, err? }
//
// Nome do endpoint deve bater com RegisterNUICallback() do lado Lua.


(() => {
    'use strict';


    // ============================================================
    // CONST
    // ============================================================

    const BASE         = `https://${GetParentResourceName()}/`;
    const POST_TIMEOUT = 8000;   // 8s — fetch travado retorna { ok:false, err:'timeout' }


    // ============================================================
    // FETCH COM TIMEOUT
    // ============================================================

    // Wrap o fetch nativo com AbortController para nao travar a UI se o
    // callback Lua nunca responder.
    function fetchWithTimeout(url, options, ms) {
        const ctrl  = new AbortController();
        const timer = setTimeout(() => ctrl.abort(), ms);

        return fetch(url, Object.assign({}, options, { signal: ctrl.signal }))
            .finally(() => clearTimeout(timer));
    }


    // ============================================================
    // API — vhub.post(action, data) → Promise<{ok, data?, err?}>
    // ============================================================

    async function post(action, data) {
        if (typeof action !== 'string' || action === '') {
            return { ok: false, err: 'action_invalida' };
        }

        try {
            const r = await fetchWithTimeout(BASE + action, {
                method:  'POST',
                headers: { 'Content-Type': 'application/json' },
                body:    JSON.stringify(data || {}),
            }, POST_TIMEOUT);

            return await r.json();

        } catch (err) {
            if (err && err.name === 'AbortError') {
                console.warn(`[vhub.bridge] timeout em '${action}'`);
                return { ok: false, err: 'timeout' };
            }
            console.error(`[vhub.bridge] erro em '${action}':`, err);
            return { ok: false, err: 'network' };
        }
    }


    window._vhubBridge = { post };

})();
