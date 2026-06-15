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


    // ---- carga / troca de HUD ----
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

    // aplica a personalização (fundo/cor) DIRETO no documento do iframe (same-origin) — funciona para
    // QUALQUER HUD, inclusive os bespoke que não usam velo-core, via CSS vars --velo-bg / --velo-accent.
    function applyConfigToFrame() {
        if (!lastConfig) return;
        try {
            const doc = frame.contentDocument;
            if (!doc) return;
            const data = lastConfig.data || lastConfig;
            const root = doc.documentElement.style;
            if (typeof data.bg === 'string') root.setProperty('--velo-bg', data.bg ? 'url("' + data.bg + '")' : 'none');
            if (typeof data.accent === 'string' && data.accent) root.setProperty('--velo-accent', data.accent);
        } catch (_) {}
    }


    // ---- galeria ----
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
            const tag  = document.createElement('span'); tag.className = 'tag'; tag.textContent = h.id;
            item.appendChild(name); item.appendChild(tag);
            list.appendChild(item);
        });
    }

    function openGallery(d) {
        if (d.huds) huds = d.huds;
        if (d.category) category = d.category;
        buildGallery(category);
        inpBg.value = (typeof d.bg === 'string') ? d.bg : '';
        if (typeof d.accent === 'string' && d.accent) inpAcc.value = d.accent;
        gallery.classList.add('active');
    }

    function closeGallery() {
        gallery.classList.remove('active');
        post('velo:closeConfig');
    }


    // ---- mensagens do Lua ----
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

    // ---- interação da galeria ----
    gallery.addEventListener('click', function (e) {
        if (e.target.closest('[data-act="close"]')) { closeGallery(); return; }

        // personalização: aplicar (fundo + cor) ou limpar o fundo
        if (e.target.closest('[data-act="apply"]')) {
            post('velo:saveConfig', { category: category, bg: inpBg.value, accent: inpAcc.value });
            return;
        }
        if (e.target.closest('[data-act="clearbg"]')) {
            inpBg.value = '';
            post('velo:saveConfig', { category: category, bg: '', accent: inpAcc.value });
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
