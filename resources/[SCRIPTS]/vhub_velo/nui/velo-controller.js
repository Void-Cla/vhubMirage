// velo-controller.js — host/dispatcher da NUI do vhub_velo (IIFE, sem poluir o escopo global).
// Roteia as mensagens do Lua: troca o HUD (iframe), repassa telemetria ao iframe, e gerencia a
// galeria /velo. O HUD em si roda ISOLADO no iframe (único canal = postMessage). A preferência
// é salva por callback (Lua → KVP). fetch só em ação do usuário (A-06).

(function () {
    'use strict';

    const host    = document.getElementById('hud-host');
    const frame   = document.getElementById('hud-frame');
    const gallery = document.getElementById('velo-gallery');
    const list    = document.getElementById('vg-list');
    const inpBg   = document.getElementById('vg-bg');
    const inpAcc  = document.getElementById('vg-accent');
    const inpZoom = document.getElementById('vg-zoom');
    const lblZoom = document.getElementById('vg-zoom-val');

    const RES = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'vhub_velo';

    let huds = {}, category = null, currentId = null;
    let lastConfig = null, lastUpdate = null;   // re-aplicados quando o iframe (re)carrega

    function post(cb, data) {
        fetch('https://' + RES + '/' + cb, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data || {}),
        }).catch(function () {});
    }

    function getZoom() {
        const v = parseFloat(inpZoom ? inpZoom.value : '1.0');
        return Number.isFinite(v) ? v : 1.0;
    }


    // ============================================================
    // CARGA / TROCA DE HUD
    // ============================================================

    function loadHud(d) {
        if (d.huds) huds = d.huds;
        if (d.category) category = d.category;
        if (d.hudId) currentId = d.hudId;
        if (d.path) {
            // ao (re)carregar o HUD, reaplica config + último estado quando o iframe terminar de carregar
            frame.onload = function () {
                if (lastConfig) { forward(lastConfig); applyConfigToFrame(); }
                if (lastUpdate) forward(lastUpdate);
            };
            frame.src = d.path;
            host.classList.remove('hidden');
        }
    }

    // repassa uma mensagem ao HUD dentro do iframe
    function forward(m) {
        try { if (frame.contentWindow) frame.contentWindow.postMessage(m, '*'); } catch (_) {}
    }

    // aplica fundo/cor/zoom DIRETO no documento do iframe via CSS vars — funciona para qualquer HUD,
    // inclusive os bespoke sem velo-core, cobrindo troca de HUD sem aguardar postMessage de volta.
    function applyConfigToFrame() {
        if (!lastConfig) return;
        try {
            const doc = frame.contentDocument;
            if (!doc) return;
            const c    = lastConfig.data || lastConfig;
            const root = doc.documentElement.style;
            function setBg(prop, url) {
                if (typeof url === 'string')
                    root.setProperty(prop, url ? 'url("' + url + '")' : 'none');
            }
            const bg = c.bgSpeed || c.bg;
            setBg('--velo-bg-speed', bg);
            setBg('--velo-bg-fuel',  c.bgFuel || bg);
            setBg('--velo-bg-rpm',   c.bgRpm  || bg);
            setBg('--velo-bg',       c.bg);
            if (typeof c.accent === 'string' && c.accent) root.setProperty('--velo-accent', c.accent);
            if (typeof c.zoom   === 'number')             root.setProperty('--velo-zoom',   String(c.zoom));
        } catch (_) {}
    }


    // ============================================================
    // GALERIA
    // ============================================================

    function buildGallery(cat) {
        list.textContent = '';
        const arr = huds[cat] || [];
        if (!arr.length) {
            const e = document.createElement('div');
            e.className = 'vg-empty'; e.textContent = 'Nenhum HUD nesta categoria.';
            list.appendChild(e); return;
        }
        arr.forEach(function (h) {
            const item = document.createElement('div');
            item.className = 'vg-item' + (h.id === currentId ? ' is-active' : '');
            item.dataset.id = h.id;
            const name = document.createElement('span'); name.className = 'name'; name.textContent = h.name;
            const tag  = document.createElement('span'); tag.className = 'tag';  tag.textContent  = h.id;
            item.appendChild(name); item.appendChild(tag);
            list.appendChild(item);
        });
    }

    function openGallery(d) {
        if (d.huds) huds = d.huds;
        if (d.category) category = d.category;
        buildGallery(category);
        // Lua envia d.data.bgSpeed (chave nova) ou d.bg (chave legada) — ambos suportados
        const cfg = d.data || {};
        const bgVal = cfg.bgSpeed || cfg.bg || d.bg || '';
        inpBg.value = (typeof bgVal === 'string') ? bgVal : '';
        if (typeof cfg.accent === 'string' && cfg.accent) inpAcc.value = cfg.accent;
        if (inpZoom) {
            const z = typeof cfg.zoom === 'number' ? cfg.zoom : 1.0;
            inpZoom.value = String(z);
            if (lblZoom) lblZoom.textContent = z.toFixed(2) + '×';
        }
        gallery.classList.add('active');
    }

    function closeGallery() {
        gallery.classList.remove('active');
        post('velo:closeConfig');
    }


    // ============================================================
    // MENSAGENS DO LUA
    // ============================================================

    window.addEventListener('message', function (e) {
        const d = e.data; if (!d || !d.type) return;
        switch (d.type) {
            case 'velocimetro:loadHud':    loadHud(d); break;
            case 'velocimetro:toggle':     host.classList.toggle('hidden', !d.visible); break;
            case 'velocimetro:update':     lastUpdate = d; forward(d); break;
            case 'velocimetro:config':     lastConfig = d; applyConfigToFrame(); forward(d); break;
            case 'velocimetro:openConfig': openGallery(d); break;
        }
    });


    // ============================================================
    // INTERAÇÃO DA GALERIA
    // ============================================================

    // atualiza o rótulo do zoom em tempo real conforme o slider é arrastado
    if (inpZoom && lblZoom) {
        inpZoom.addEventListener('input', function () {
            lblZoom.textContent = parseFloat(inpZoom.value).toFixed(2) + '×';
        });
    }

    gallery.addEventListener('click', function (e) {
        if (e.target.closest('[data-act="close"]')) { closeGallery(); return; }

        if (e.target.closest('[data-act="apply"]')) {
            const bg = inpBg.value;
            post('velo:saveConfig', { category: category, bg: bg, bgSpeed: bg, bgFuel: bg, bgRpm: bg, accent: inpAcc.value, zoom: getZoom() });
            return;
        }
        if (e.target.closest('[data-act="clearbg"]')) {
            inpBg.value = '';
            post('velo:saveConfig', { category: category, bg: '', bgSpeed: '', bgFuel: '', bgRpm: '', accent: inpAcc.value, zoom: getZoom() });
            return;
        }

        const item = e.target.closest('.vg-item');
        if (item && item.dataset.id && category) {
            currentId = item.dataset.id;
            buildGallery(category);
            post('velo:saveHud', { category: category, hudId: item.dataset.id });
        }
    });

    document.addEventListener('keydown', function (e) {
        if (e.key === 'Escape' && gallery.classList.contains('active')) closeGallery();
    });
})();
