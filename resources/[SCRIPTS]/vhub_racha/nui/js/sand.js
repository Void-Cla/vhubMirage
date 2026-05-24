// nui/js/sand.js — particulas de areia (vHub theme, v2)
// v2: modo "boost" durante a corrida — particulas voam horizontalmente
//     dando sensacao de velocidade (Need for Speed / Forza vibes).
(() => {
  const canvas = document.getElementById('vhub-sand');
  if (!canvas) return;
  const ctx = canvas.getContext('2d');
  let W = 0, H = 0;
  const grains = [];
  const N_IDLE = 50;
  const N_BOOST = 140;
  let target = N_IDLE;
  let boostMode = false;
  let running = false;
  let raf = null;

  function resize() {
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    W = canvas.clientWidth;
    H = canvas.clientHeight;
    canvas.width  = Math.floor(W * dpr);
    canvas.height = Math.floor(H * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  }
  window.addEventListener('resize', resize);

  function spawn(g, fromSide) {
    if (boostMode) {
      // streaks horizontais para sensacao de velocidade
      g.x = fromSide ? -10 : Math.random() * W;
      g.y = Math.random() * H;
      g.r = 0.6 + Math.random() * 1.6;
      g.vx = 3 + Math.random() * 9;            // velocidade horizontal forte
      g.vy = (Math.random() - 0.5) * 0.4;
      g.a = 0.14 + Math.random() * 0.30;
      g.len = 8 + Math.random() * 22;          // tamanho do "rastro"
      g.streak = true;
    } else {
      g.x = Math.random() * W;
      g.y = fromSide ? -2 : Math.random() * H;
      g.r = 0.5 + Math.random() * 1.5;
      g.vy = 0.05 + Math.random() * 0.20;
      g.vx = (Math.random() - 0.5) * 0.18;
      g.a = 0.10 + Math.random() * 0.28;
      g.len = 0;
      g.streak = false;
    }
  }

  function ensurePool() {
    while (grains.length < target) {
      const g = {}; spawn(g, false); grains.push(g);
    }
    if (grains.length > target) grains.length = target;
  }

  function tick() {
    if (!running) return;
    ctx.clearRect(0, 0, W, H);
    for (const g of grains) {
      g.x += g.vx; g.y += g.vy;
      const off = boostMode
        ? (g.x > W + 30 || g.y > H + 4 || g.y < -4)
        : (g.y > H + 2 || g.x < -2 || g.x > W + 2);
      if (off) spawn(g, true);

      if (g.streak) {
        const grad = ctx.createLinearGradient(g.x - g.len, g.y, g.x, g.y);
        grad.addColorStop(0, 'rgba(243,181,58,0)');
        grad.addColorStop(1, `rgba(255,213,115,${g.a})`);
        ctx.strokeStyle = grad;
        ctx.lineWidth = g.r;
        ctx.lineCap = 'round';
        ctx.beginPath();
        ctx.moveTo(g.x - g.len, g.y);
        ctx.lineTo(g.x, g.y);
        ctx.stroke();
      } else {
        ctx.beginPath();
        ctx.fillStyle = `rgba(243,181,58,${g.a})`;
        ctx.arc(g.x, g.y, g.r, 0, Math.PI * 2);
        ctx.fill();
      }
    }
    raf = requestAnimationFrame(tick);
  }

  window.vhubSand = {
    start() {
      if (running) return;
      running = true;
      resize();
      ensurePool();
      tick();
    },
    stop() {
      running = false;
      if (raf) cancelAnimationFrame(raf);
      ctx && ctx.clearRect(0, 0, W, H);
    },
    boost(on) {
      const was = boostMode;
      boostMode = !!on;
      target = boostMode ? N_BOOST : N_IDLE;
      // Reconfigura particulas existentes para o novo modo
      if (was !== boostMode) {
        for (const g of grains) spawn(g, false);
      }
      ensurePool();
      if (boostMode && !running) this.start();
    },
  };
})();
