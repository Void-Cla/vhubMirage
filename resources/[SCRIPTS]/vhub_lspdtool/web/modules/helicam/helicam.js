// helicam.js — overlay HUD da câmera de heli (FASE B). Registrado no dispatcher (app.js).
// Passivo: só reflete o estado vindo do Lua. Sem regra de negócio (A-01), sem fetch (A-06).

(function () {
    'use strict';

    const root = document.getElementById('helicam');

    // referências fixas (sem re-query no hot path)
    const el = {
        vision: document.querySelector('#helicam .js-vision'),
        zoom:   document.querySelector('#helicam .js-zoom'),
        alt:    document.querySelector('#helicam .js-alt'),
        hdg:    document.querySelector('#helicam .js-hdg'),
        target: document.querySelector('#helicam .mod-helicam__target'),
        tplate: document.querySelector('#helicam .js-tplate'),
        tspeed: document.querySelector('#helicam .js-tspeed'),
        tdist:  document.querySelector('#helicam .js-tdist'),
        spot:   document.querySelector('#helicam .mod-helicam__spot'),
    };

    function onMessage(type, m) {
        switch (type) {
            case 'helicam:open':
                root.classList.add('is-open');
                root.setAttribute('aria-hidden', 'false');
                break;

            case 'helicam:close':
                root.classList.remove('is-open', 'is-locked');
                root.setAttribute('aria-hidden', 'true');
                el.target.classList.remove('is-on');
                el.spot.classList.remove('is-on');
                break;

            case 'helicam:update':
                if (m.vision) el.vision.textContent = m.vision;
                if (typeof m.zoom === 'number')     el.zoom.textContent = m.zoom + '%';
                if (typeof m.altitude === 'number') el.alt.textContent  = m.altitude + ' m';
                if (typeof m.heading === 'number')  el.hdg.textContent  = m.heading + '°';

                root.classList.toggle('is-locked', !!m.locked);
                el.spot.classList.toggle('is-on', !!m.spotlight);

                if (m.target) {
                    el.target.classList.add('is-on');
                    el.tplate.textContent = (m.target.plate && m.target.plate.length) ? m.target.plate : '------';
                    el.tspeed.textContent = (typeof m.target.speed === 'number') ? m.target.speed : '--';
                    el.tdist.textContent  = (typeof m.target.dist === 'number')  ? m.target.dist  : '--';
                } else {
                    el.target.classList.remove('is-on');
                }
                break;
        }
    }

    // sem RAF/interval próprios → onDestroy vazio (listener central removido no app.js)
    window.LSPD.register('helicam', { onMessage: onMessage, onDestroy: function () {} });
})();
