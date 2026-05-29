// web/runtime/core.js — engine NUI do vhub_racha (L3).
//
// Mini-framework sem dependencias. Registra modulos com lifecycle padronizado
// e gerencia montagem/desmontagem com fetch lazy de HTML+CSS.
//
// API publica (expose `window.vhub`):
//   vhub.createModule(name, spec)   registra modulo, chama spec.onInit imediato
//   vhub.mount(name)                garante carregado + chama onMount
//   vhub.show(name)                 mount + display + chama onShow
//   vhub.hide(name)                 hide + chama onHide
//   vhub.unmount(name)              chama onDestroy + remove DOM + descarta
//   vhub.bus / vhub.store / vhub.post / vhub.sand   re-export
//
// LIFECYCLE de um spec (A-02):
//   onInit(ctx)     primeira vez que `createModule` e chamado
//   onMount(el)     DOM injetado; recebe o wrapper element
//   onShow()        modulo visivel; iniciar animacoes leves
//   onHide()        modulo invisivel; PAUSAR animacoes
//   onDestroy()     cleanup OBRIGATORIO: cancelAnimationFrame, clearInterval,
//                   removeEventListener, observers, bus.off
//
// LAZY LOAD:
//   primeira chamada a mount(name) faz fetch dos arquivos:
//     web/modules/<name>/<name>.html  → inserido em #vhub-app
//     web/modules/<name>/<name>.css   → link rel=stylesheet no head
//   subsequentes chamadas a mount eh noop.


(() => {
    'use strict';


    // ============================================================
    // STATE
    // ============================================================

    const _modules = {};       // { [name]: spec + { _el, _loaded, _mounted } }
    let   _appEl   = null;     // container #vhub-app


    // ============================================================
    // BOOT — espera DOM pronto
    // ============================================================

    function ready(fn) {
        if (document.readyState !== 'loading') fn();
        else document.addEventListener('DOMContentLoaded', fn);
    }


    ready(() => {
        _appEl = document.getElementById('vhub-app');
        if (!_appEl) {
            console.error('[vhub.core] #vhub-app nao encontrado no DOM');
        }
    });


    // ============================================================
    // FETCH LAZY de HTML + CSS do modulo
    // ============================================================

    // Carrega HTML fragment e injeta link de CSS uma unica vez por modulo.
    // O wrapper gerado tem id="mod-<name>" e className="mod-<name>".
    async function _loadFiles(name) {
        const mod = _modules[name];
        if (!mod || mod._loaded) return;

        // CSS (link uma vez — browser deduplica via href)
        const link = document.createElement('link');
        link.rel  = 'stylesheet';
        link.href = `modules/${name}/${name}.css`;
        document.head.appendChild(link);

        // HTML fragment
        const r    = await fetch(`modules/${name}/${name}.html`);
        const html = await r.text();

        const wrapper = document.createElement('div');
        wrapper.id        = `mod-${name}`;
        wrapper.className = `mod-${name} hidden`;
        wrapper.innerHTML = html;

        if (!_appEl) _appEl = document.getElementById('vhub-app');
        _appEl.appendChild(wrapper);

        mod._el     = wrapper;
        mod._loaded = true;
    }


    // ============================================================
    // API — createModule
    // ============================================================

    // Registra um modulo. spec deve ter ao menos um dos hooks de lifecycle.
    // onInit roda IMEDIATO (sem DOM ainda — registrar listeners do bus aqui).
    function createModule(name, spec) {
        if (typeof name !== 'string' || name === '') {
            throw new Error('[vhub.core] createModule precisa de nome');
        }
        if (_modules[name]) {
            console.warn(`[vhub.core] modulo '${name}' ja registrado — sobrescrevendo`);
        }

        const wrap = Object.assign({}, spec || {}, {
            _el: null, _loaded: false, _mounted: false,
        });
        _modules[name] = wrap;

        if (typeof wrap.onInit === 'function') {
            try { wrap.onInit(); }
            catch (err) { console.error(`[vhub.core] onInit '${name}' erro:`, err); }
        }
    }


    // ============================================================
    // API — mount / show / hide / unmount
    // ============================================================

    // Garante DOM carregado e chama onMount. Idempotente.
    async function mount(name) {
        const mod = _modules[name];
        if (!mod) {
            console.warn(`[vhub.core] mount: modulo '${name}' inexistente`);
            return;
        }
        if (mod._mounted) return;

        await _loadFiles(name);
        mod._mounted = true;

        if (typeof mod.onMount === 'function') {
            try { mod.onMount(mod._el); }
            catch (err) { console.error(`[vhub.core] onMount '${name}' erro:`, err); }
        }
    }


    // Garante montado, remove .hidden, chama onShow.
    async function show(name) {
        await mount(name);
        const mod = _modules[name];
        if (!mod || !mod._el) return;

        mod._el.classList.remove('hidden');
        if (typeof mod.onShow === 'function') {
            try { mod.onShow(); }
            catch (err) { console.error(`[vhub.core] onShow '${name}' erro:`, err); }
        }
    }


    // Adiciona .hidden, chama onHide. Modulo continua montado em memoria.
    function hide(name) {
        const mod = _modules[name];
        if (!mod || !mod._el) return;

        mod._el.classList.add('hidden');
        if (typeof mod.onHide === 'function') {
            try { mod.onHide(); }
            catch (err) { console.error(`[vhub.core] onHide '${name}' erro:`, err); }
        }
    }


    // Cleanup completo (A-05 + A-07): chama onDestroy, remove DOM, libera refs.
    function unmount(name) {
        const mod = _modules[name];
        if (!mod) return;

        if (typeof mod.onDestroy === 'function') {
            try { mod.onDestroy(); }
            catch (err) { console.error(`[vhub.core] onDestroy '${name}' erro:`, err); }
        }

        if (mod._el) {
            mod._el.remove();
            mod._el = null;
        }
        mod._loaded  = false;
        mod._mounted = false;
    }


    // ============================================================
    // EXPORT — window.vhub agrega todas as APIs do runtime
    // ============================================================

    window.vhub = {
        createModule, mount, show, hide, unmount,
        bus:    window._vhubBus,
        store:  window._vhubStore,
        post:   window._vhubBridge.post,
        sand:   window._vhubSand,
    };


    // ============================================================
    // DISPATCHER UNICO — SendNUIMessage do Lua chega aqui
    // ============================================================
    //
    // O Lua usa dois shapes: `{ action, data }` (legado) e `{ type, payload/bag }`
    // (novo). Despachamos ambos via bus com prefixo 'nui:' para os modulos
    // escutarem apenas o que lhes interessa.

    window.addEventListener('message', (event) => {
        const msg = event.data;
        if (!msg || typeof msg !== 'object') return;

        // Shape legado: { action, data }
        if (msg.action) {
            window._vhubBus.emit('nui:' + msg.action, msg.data);
        }

        // Shape tipado: { type, <body> } — body pode vir em payload/bag/data/target
        if (msg.type) {
            const body = msg.payload !== undefined ? msg.payload
                       : msg.bag     !== undefined ? msg.bag
                       : msg.data    !== undefined ? msg.data
                       : msg.target  !== undefined ? msg.target
                       : msg;
            window._vhubBus.emit('nui:' + msg.type, body);
        }
    });

})();
