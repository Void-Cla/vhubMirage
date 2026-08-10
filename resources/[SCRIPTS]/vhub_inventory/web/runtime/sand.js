// runtime/sand.js — partículas de areia dourada (assinatura Mirage).
// Motor único e barato: um só RAF, ativo APENAS enquanto um painel está aberto
// (start no onMount/onShow, stop no onHide/onDestroy). Pausa quando a aba some.
// Respeita prefers-reduced-motion (um quadro estático, sem loop). A-07/A-08/L-18.

(function () {

  const COUNT   = 54;                 // densidade baixa (idle = 0 quando parado)
  const reduced = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  let canvas = null, ctx = null, raf = 0, running = false;
  let W = 0, H = 0;
  let motes = [];


  // ============================================================
  // PARTÍCULAS
  // ============================================================

  const rnd = (a, b) => a + Math.random() * (b - a);

  // semeia uma mote de areia com posição/velocidade/brilho aleatórios
  function seed(fromBottom) {
    return {
      x:    rnd(0, W),
      y:    fromBottom ? rnd(H, H + 40) : rnd(0, H),
      r:    rnd(0.6, 2.3),
      vy:   rnd(-0.28, -0.05),        // sobe devagar (calor da areia)
      sway: rnd(0.15, 0.6),           // amplitude do bamboleio horizontal
      ph:   rnd(0, Math.PI * 2),      // fase (sway + cintilância)
      spd:  rnd(0.004, 0.014),        // velocidade do bamboleio
      a:    rnd(0.05, 0.34),          // brilho base
    };
  }

  function build() {
    motes = [];
    for (let i = 0; i < COUNT; i++) motes.push(seed(false));
  }


  // ============================================================
  // RENDER
  // ============================================================

  function size() {
    if (!canvas) return;
    W = canvas.width  = window.innerWidth;
    H = canvas.height = window.innerHeight;
  }

  function draw() {
    if (!ctx) return;
    ctx.clearRect(0, 0, W, H);
    for (let i = 0; i < motes.length; i++) {
      const m = motes[i];
      const tw = 0.6 + 0.4 * Math.sin(m.ph * 2.0);     // cintilância suave
      ctx.beginPath();
      ctx.arc(m.x + Math.sin(m.ph) * (m.sway * 8), m.y, m.r, 0, Math.PI * 2);
      ctx.fillStyle = 'rgba(248, 200, 105, ' + (m.a * tw).toFixed(3) + ')';
      ctx.fill();
    }
  }

  function step() {
    if (!running) return;
    for (let i = 0; i < motes.length; i++) {
      const m = motes[i];
      m.y  += m.vy;
      m.ph += m.spd;
      if (m.y < -6) { motes[i] = seed(true); }        // recicla pelo rodape
    }
    draw();
    raf = requestAnimationFrame(step);
  }


  // ============================================================
  // VISIBILIDADE (pausa quando a aba/janela some — não gasta em background)
  // ============================================================

  function onVis() {
    if (document.hidden) { if (raf) cancelAnimationFrame(raf); raf = 0; }
    else if (running && !reduced && !raf) { raf = requestAnimationFrame(step); }
  }


  // ============================================================
  // API
  // ============================================================

  vhub.sand = {

    // liga o campo de areia sobre o canvas fornecido pelo módulo dono (idempotente)
    start(cv) {
      if (!cv) return;
      if (raf) cancelAnimationFrame(raf); raf = 0;     // encerra loop anterior, se houver
      window.removeEventListener('resize', size);       // no-op se ainda não registrado
      document.removeEventListener('visibilitychange', onVis);
      canvas  = cv;
      ctx     = cv.getContext('2d');
      running = true;
      size();
      build();
      window.addEventListener('resize', size);
      document.addEventListener('visibilitychange', onVis);
      if (reduced) { draw(); return; }                // reduzido: 1 quadro, sem loop
      raf = requestAnimationFrame(step);
    },

    // desliga e limpa (cleanup obrigatório — A-07)
    stop() {
      running = false;
      if (raf) cancelAnimationFrame(raf);
      raf = 0;
      window.removeEventListener('resize', size);
      document.removeEventListener('visibilitychange', onVis);
      if (ctx && W && H) ctx.clearRect(0, 0, W, H);
      canvas = null; ctx = null; motes = [];
    },
  };
})();
