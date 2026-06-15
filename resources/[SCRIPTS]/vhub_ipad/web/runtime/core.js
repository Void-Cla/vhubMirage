// web/runtime/core.js — engine NUI do vhub_ipad (L3).
//
// FORK OWNED/DIVERGENTE do runtime do vhub_racha — NÃO ressincronizar.
// Divergências (decisão da plataforma de apps):
//   1. _loadFiles aceita `entry` com URLs resolvidas (local OU cfx-nui-<resource>).
//   2. mount injeta o <script> de apps de TERCEIRO e aguarda script.onload
//      (createModule roda síncrono no corpo do script → sem polling, A-02/L-06).
//   3. unmount remove o <link> CSS (fix de leak: re-mount não duplica mais).
//
// API publica (window.vhub):
//   vhub.createModule(name, spec)        registra modulo, chama spec.onInit imediato
//   vhub.mount(name, entry)              garante carregado + onMount
//   vhub.show(name, entry)               mount + display + onShow
//   vhub.hide(name)                      hide + onHide
//   vhub.unmount(name)                   onDestroy + remove DOM + libera <link>
//   vhub.bus / vhub.store / vhub.post / vhub.sand   re-export
//
// LIFECYCLE (A-02): onInit / onMount(el) / onShow / onHide / onDestroy.
// LAZY LOAD (A-05): mount(name) so carrega HTML/CSS (e JS remoto) na 1a vez.


(() => {
    'use strict';


    // ============================================================
    // STATE
    // ============================================================

    const _modules = {};       // { [name]: spec + { _el, _loaded, _mounted, _cssLink } }
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
        if (!_appEl) console.error('[vhub.core] #vhub-app nao encontrado no DOM');
    });


    // ============================================================
    // RESOLUCAO DE URLs (local padrao | entry do manifest)
    // ============================================================

    // Resolve as URLs de html/css/js do modulo. Sem entry → padrao local.
    function _resolve(name, entry) {
        return {
            html: (entry && entry.html) || `modules/${name}/${name}.html`,
            css:  (entry && entry.css)  || `modules/${name}/${name}.css`,
            js:   (entry && entry.js)   || `modules/${name}/${name}.js`,
        };
    }


    // ============================================================
    // FETCH LAZY de HTML + CSS
    // ============================================================

    // Carrega HTML fragment + injeta <link> CSS UMA vez (com ref p/ remover no unmount).
    async function _loadFiles(name, urls) {
        const mod = _modules[name];
        if (!mod || mod._loaded) return;

        // CSS uma vez por modulo (guarda ref — fix de leak de <link> em re-mount)
        if (!mod._cssLink && !document.querySelector(`link[data-mod="${name}"]`)) {
            const link = document.createElement('link');
            link.rel = 'stylesheet';
            link.href = urls.css;
            link.dataset.mod = name;
            document.head.appendChild(link);
            mod._cssLink = link;
        }

        const r    = await fetch(urls.html);
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
    // REGISTRO DE APP REMOTO (injeta <script>, aguarda onload)
    // ============================================================

    // Garante que createModule(name) ja rodou. Builtins/local: ja registrados via
    // <script> no index.html → resolve na hora. Remoto: injeta o <script> do entry.
    function _ensureRegistered(name, urls) {
        return new Promise((resolve) => {
            if (_modules[name]) return resolve(true);

            if (!urls.js) {
                console.warn(`[vhub.core] modulo '${name}' nao registrado e sem entry.js`);
                return resolve(false);
            }

            const s = document.createElement('script');
            s.src = urls.js;
            s.dataset.app = name;
            s.onload = () => {
                if (!_modules[name]) {
                    console.error(`[vhub.core] app '${name}' carregou mas nao chamou createModule('${name}')`);
                    return resolve(false);
                }
                if (typeof _modules[name].onDestroy !== 'function') {
                    console.warn(`[vhub.core] app '${name}' sem onDestroy — A-07 risco de leak`);
                }
                resolve(true);
            };
            s.onerror = () => {
                console.error(`[vhub.core] falha ao carregar JS de '${name}'`);
                resolve(false);
            };
            document.head.appendChild(s);
        });
    }


    // ============================================================
    // API — createModule
    // ============================================================

    // Registra um modulo. onInit roda IMEDIATO (sem DOM — registrar bus aqui).
    function createModule(name, spec) {
        if (typeof name !== 'string' || name === '') {
            throw new Error('[vhub.core] createModule precisa de nome');
        }
        if (_modules[name]) {
            console.warn(`[vhub.core] modulo '${name}' ja registrado — sobrescrevendo`);
        }

        const wrap = Object.assign({}, spec || {}, {
            _el: null, _loaded: false, _mounted: false, _cssLink: null,
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

    // Garante registrado (injeta JS remoto se preciso) + DOM carregado + onMount.
    async function mount(name, entry) {
        const urls = _resolve(name, entry);

        let mod = _modules[name];
        if (!mod) {
            const ok = await _ensureRegistered(name, urls);
            if (!ok) return;
            mod = _modules[name];
        }
        if (mod._mounted) return;

        await _loadFiles(name, urls);
        mod._mounted = true;

        if (typeof mod.onMount === 'function') {
            try { mod.onMount(mod._el); }
            catch (err) { console.error(`[vhub.core] onMount '${name}' erro:`, err); }
        }
    }


    // Garante montado, remove .hidden, chama onShow.
    async function show(name, entry) {
        await mount(name, entry);
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


    // Cleanup (A-05 + A-07): onDestroy, remove DOM + <link>, mantem spec (cache).
    function unmount(name) {
        const mod = _modules[name];
        if (!mod) return;

        if (typeof mod.onDestroy === 'function') {
            try { mod.onDestroy(); }
            catch (err) { console.error(`[vhub.core] onDestroy '${name}' erro:`, err); }
        }

        if (mod._el)      { mod._el.remove(); mod._el = null; }
        if (mod._cssLink) { mod._cssLink.remove(); mod._cssLink = null; }
        mod._loaded  = false;
        mod._mounted = false;
    }


    // ============================================================
    // APP RELAY CHANNEL — app embutido ↔ server do resource dono
    // ============================================================
    //
    // O app usa vhub.app.send/on; o broker (server do iPad) roteia. O shell
    // define o app ATIVO ao navegar (setActive), garantindo que o send saiba
    // para qual app rotear e o push chegue só ao app correto.

    const _appChannels = {};   // { app: { [action]: Set<fn> } } — handlers ESCOPADOS por app
    let   _activeApp   = null;

    // canal de um app: send(action,data) → broker; on(action,fn) → push do server
    function _channelFor(app) {
        if (!_appChannels[app]) _appChannels[app] = {};
        const handlers = _appChannels[app];
        return {
            send(action, data) {
                if (typeof action !== 'string') return;
                window._vhubBridge.post('appRelay', { app, action, data });
            },
            // retorna off() — A-07 (o app desfaz no onDestroy)
            on(action, fn) {
                if (typeof action !== 'string' || typeof fn !== 'function') return () => {};
                if (!handlers[action]) handlers[action] = new Set();
                handlers[action].add(fn);
                return () => { const s = handlers[action]; if (s) s.delete(fn); };
            },
        };
    }

    const appChannel = {
        setActive(name) { _activeApp = name || null; },
        channel: _channelFor,
        // conveniência: roteia pelo app ativo (compat)
        send(action, data) { if (_activeApp) _channelFor(_activeApp).send(action, data); },
    };

    // push do server → handlers DO APP correto (roteado por p.app; sem vazar entre apps)
    window._vhubBus.listen('nui:appPush', (p) => {
        if (!p || typeof p.app !== 'string' || typeof p.action !== 'string') return;
        const handlers = _appChannels[p.app];
        const s = handlers && handlers[p.action];
        if (!s) return;
        for (const fn of s) {
            try { fn(p.data); } catch (e) { console.error('[vhub.app] handler', p.app, p.action, e); }
        }
    });


    // ============================================================
    // EXPORT — window.vhub agrega o runtime
    // ============================================================

    window.vhub = {
        createModule, mount, show, hide, unmount,
        bus:    window._vhubBus,
        store:  window._vhubStore,
        post:   window._vhubBridge.post,
        sand:   window._vhubSand,
        app:    appChannel,
    };


    // ============================================================
    // DISPATCHER UNICO — SendNUIMessage do Lua chega aqui
    // ============================================================
    //
    // Shape { action, data } → emite 'nui:' + action com o data.

    window.addEventListener('message', (event) => {
        const msg = event.data;
        if (!msg || typeof msg !== 'object') return;

        if (msg.action) {
            window._vhubBus.emit('nui:' + msg.action, msg.data);
        }
        if (msg.type) {
            const body = msg.payload !== undefined ? msg.payload
                       : msg.data    !== undefined ? msg.data
                       : msg;
            window._vhubBus.emit('nui:' + msg.type, body);
        }
    });

})();
