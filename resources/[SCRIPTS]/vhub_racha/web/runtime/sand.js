// web/runtime/sand.js — particulas de areia (L3 — canonico vHub L-D2).
//
// CANONICO: N=40 particulas (limite L-D2). A variante boost de race com
// N=60..180 vive em web/modules/panel/sand-race.js como override LOCAL
// do resource racha — NAO subir aqui pois quebra a regra shared.
//
// API:
//   vhub.sand.start()     inicia RAF (idempotente)
//   vhub.sand.stop()      cancela RAF + limpa canvas
//
// REGRA A-07: stop() OBRIGATORIO ao esconder/desmontar painel. Sem stop,
// resmon idle > 0 mesmo com NUI fechada.
//
// CORRECAO (vhub_guardiao_performance achado #1): cancelar RAF antes de
// re-start para evitar handle fantasma se stop()+start() colidirem no
// mesmo frame.


(() => {
    'use strict';


    // ============================================================
    // CONST
    // ============================================================

    const N        = 40;                            // limite canonico L-D2
    const COLOR    = 'rgba(243, 181, 58, ';         // dourado vHub (alpha por particula)
    const MIN_SIZE = 0.5;
    const MAX_SIZE = 2.0;
    const MIN_VY   = 0.05;
    const MAX_VY   = 0.20;


    // ============================================================
    // STATE
    // ============================================================

    let canvas  = null;
    let ctx     = null;
    let W       = 0;
    let H       = 0;
    const grains = [];
    let running = false;
    let raf     = null;


    // ============================================================
    // SETUP
    // ============================================================

    function resize() {
        if (!canvas) return;
        W = canvas.width  = canvas.clientWidth;
        H = canvas.height = canvas.clientHeight;
    }


    function spawn(g) {
        g.x  = Math.random() * W;
        g.y  = Math.random() * H;
        g.r  = MIN_SIZE + Math.random() * (MAX_SIZE - MIN_SIZE);
        g.vy = MIN_VY  + Math.random() * (MAX_VY  - MIN_VY);
        g.vx = (Math.random() - 0.5) * 0.12;
        g.a  = 0.10 + Math.random() * 0.25;
    }


    function ensurePool() {
        while (grains.length < N) {
            const g = {};
            spawn(g);
            grains.push(g);
        }
    }


    // ============================================================
    // TICK
    // ============================================================

    function tick() {
        if (!running) return;

        ctx.clearRect(0, 0, W, H);

        for (const g of grains) {
            g.x += g.vx;
            g.y += g.vy;
            if (g.y > H + 2 || g.x < -2 || g.x > W + 2) spawn(g);

            ctx.beginPath();
            ctx.fillStyle = COLOR + g.a + ')';
            ctx.arc(g.x, g.y, g.r, 0, Math.PI * 2);
            ctx.fill();
        }

        raf = requestAnimationFrame(tick);
    }


    // ============================================================
    // API
    // ============================================================

    function start() {
        if (running) return;

        canvas = canvas || document.getElementById('vhub-sand');
        if (!canvas) return;

        ctx = ctx || canvas.getContext('2d');

        // Cancela RAF fantasma (correcao guardiao_performance #1)
        if (raf) { cancelAnimationFrame(raf); raf = null; }

        running = true;
        resize();
        ensurePool();
        tick();
    }


    function stop() {
        running = false;

        if (raf) { cancelAnimationFrame(raf); raf = null; }
        if (ctx && W && H) ctx.clearRect(0, 0, W, H);
    }


    // Resize automatico (custo zero quando NUI fechada — listener passivo)
    window.addEventListener('resize', () => { if (running) resize(); });


    window._vhubSand = { start, stop };

})();
