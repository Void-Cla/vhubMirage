// radar.js — overlay do radar terrestre (FASE A). Registrado no dispatcher (app.js).
// Passivo: só reflete o estado vindo do Lua. Sem regra de negócio (A-01), sem fetch (A-06).

(function () {
    'use strict';

    const root   = document.getElementById('radar');
    const lockEl = document.getElementById('radar-lock');
    const patrol = document.querySelector('#radar-patrol .mod-radar__unit-val');
    const unitEl = document.querySelector('#radar-patrol .mod-radar__unit-lbl');

    // referências fixas de cada câmera (sem re-query no hot path)
    function pick(name) {
        const el = document.querySelector('.mod-radar__cam[data-cam="' + name + '"]');
        return {
            box:   el,
            speed: el.querySelector('.mod-radar__speed'),
            val:   el.querySelector('.mod-radar__speed-val'),
            plate: el.querySelector('.mod-radar__plate'),
        };
    }

    const cam = { front: pick('front'), rear: pick('rear') };

    // pinta uma câmera com o alvo (ou estado vazio quando não há veículo)
    function paintCam(c, t) {
        if (t && typeof t.speed === 'number') {
            c.val.textContent     = t.speed;
            c.speed.dataset.empty = 'false';
            c.plate.textContent   = (t.plate && t.plate.length) ? t.plate : '------';
        } else {
            c.val.textContent     = '--';
            c.speed.dataset.empty = 'true';
            c.plate.textContent   = '------';
        }
    }

    function onMessage(type, m) {
        switch (type) {
            case 'radar:open':
                root.classList.add('is-open');
                root.setAttribute('aria-hidden', 'false');
                break;

            case 'radar:close':
                root.classList.remove('is-open');
                root.setAttribute('aria-hidden', 'true');
                break;

            case 'radar:update':
                patrol.textContent = (typeof m.patrol === 'number') ? m.patrol : 0;
                if (m.unit) unitEl.textContent = m.unit;
                paintCam(cam.front, m.front);
                paintCam(cam.rear,  m.rear);
                lockEl.hidden = !m.locked;
                cam.front.box.classList.toggle('is-locked', !!m.locked);
                cam.rear.box.classList.toggle('is-locked', !!m.locked);
                break;
        }
    }

    // sem RAF/interval próprios → onDestroy vazio (o listener central é removido no app.js)
    window.LSPD.register('radar', { onMessage: onMessage, onDestroy: function () {} });
})();
