// ════════════════════════════════════════════════════════════════════════════
// nui/js/sand.js — particulas de areia (vHub theme, v3)
// API preservada: window.vhubSand.{start, stop, boost}
//
// v3: motion blur sutil, mistura de pontos + faisquinhas + streaks horizontais
//     em modo boost para sensacao de velocidade (NFS / Forza vibes).
// ════════════════════════════════════════════════════════════════════════════
(() => {
  const canvas = document.getElementById('vhub-sand');
  if (!canvas) return;
  const ctx = canvas.getContext('2d');

  let W = 0, H = 0;
  const grains = [];
  const N_IDLE  = 60;
  const N_BOOST = 180;
  let target = N_IDLE;
  let boostMode = false;
  let running = false;
  let raf = null;
  let lastT = 0;

  function resize() {
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    W = canvas.clientWidth || window.innerWidth;
    H = canvas.clientHeight || window.innerHeight;
    canvas.width  = Math.floor(W * dpr);
    canvas.height = Math.floor(H * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  }
  window.addEventListener('resize', resize);

  function spawn(g, edge) {
    if (boostMode) {
      // streaks horizontais (faisquinhas) para sensacao de velocidade
      g.x = edge ? -10 - Math.random() * 50 : Math.random() * W;
      g.y = Math.random() * H;
      g.r = 0.6 + Math.random() * 1.8;
      g.vx = 4 + Math.random() * 11;          // velocidade horizontal forte
      g.vy = (Math.random() - 0.5) * 0.5;
      g.a = 0.16 + Math.random() * 0.32;
      g.len = 12 + Math.random() * 28;        // tamanho do rastro
      g.streak = true;
      // 20% chance de ser uma "faisca dourada" (brilho mais intenso)
      g.spark = Math.random() < 0.20;
    } else {
      g.x = Math.random() * W;
      g.y = edge ? -2 : Math.random() * H;
      g.r = 0.5 + Math.random() * 1.6;
      g.vy = 0.05 + Math.random() * 0.22;
      g.vx = (Math.random() - 0.5) * 0.20;
      g.a = 0.10 + Math.random() * 0.32;
      g.len = 0;
      g.streak = false;
      g.spark = false;
    }
  }

  function ensurePool() {
    while (grains.length < target) {
      const g = {}; spawn(g, false); grains.push(g);
    }
    if (grains.length > target) grains.length = target;
  }

  function tick(t) {
    if (!running) return;
    if (!lastT) lastT = t;
    const dt = Math.min(60, t - lastT) / 16.6667; // normalizado a 60fps
    lastT = t;

    ctx.clearRect(0, 0, W, H);

    for (let i = 0; i < grains.length; i++) {
      const g = grains[i];
      g.x += g.vx * dt;
      g.y += g.vy * dt;

      const off = boostMode
        ? (g.x > W + 40 || g.y > H + 6 || g.y < -6)
        : (g.y > H + 4 || g.x < -4 || g.x > W + 4);
      if (off) { spawn(g, true); continue; }

      if (g.streak) {
        // streak horizontal com gradiente
        const tailX = g.x - g.len;
        const grad = ctx.createLinearGradient(tailX, g.y, g.x, g.y);
        grad.addColorStop(0, 'rgba(243,181,58,0)');
        if (g.spark) {
          grad.addColorStop(0.5, `rgba(255,213,115,${g.a * 0.6})`);
          grad.addColorStop(1,   `rgba(255,235,180,${Math.min(1, g.a * 2.0)})`);
        } else {
          grad.addColorStop(1, `rgba(255,213,115,${g.a})`);
        }
        ctx.strokeStyle = grad;
        ctx.lineWidth = g.r;
        ctx.lineCap = 'round';
        ctx.beginPath();
        ctx.moveTo(tailX, g.y);
        ctx.lineTo(g.x, g.y);
        ctx.stroke();

        if (g.spark) {
          // ponta com glow
          ctx.fillStyle = `rgba(255,243,200,${g.a * 1.4})`;
          ctx.beginPath();
          ctx.arc(g.x, g.y, g.r * 1.4, 0, Math.PI * 2);
          ctx.fill();
        }
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
      lastT = 0;
      resize();
      ensurePool();
      raf = requestAnimationFrame(tick);
    },
    stop() {
      running = false;
      if (raf) cancelAnimationFrame(raf);
      raf = null;
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
