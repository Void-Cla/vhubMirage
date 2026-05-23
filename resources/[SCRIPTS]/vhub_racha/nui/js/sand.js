// nui/js/sand.js — partículas de areia (vHub theme oficial)
// Densidade fixa em 40 grãos. start() ao abrir NUI, stop() ao fechar.
// Resmon idle = 0 (cancelAnimationFrame quando stop).
(() => {
  const canvas = document.getElementById('vhub-sand');
  if (!canvas) return;
  const ctx = canvas.getContext('2d', { alpha: true });
  let W = 0, H = 0;
  const grains = [];
  const N = 40;
  let running = false;
  let raf = null;

  function resize() {
    W = canvas.width  = canvas.clientWidth  || window.innerWidth;
    H = canvas.height = canvas.clientHeight || window.innerHeight;
  }
  window.addEventListener('resize', resize);

  function spawn(g, atTop) {
    g.x  = Math.random() * W;
    g.y  = atTop ? -Math.random() * 30 : Math.random() * H;
    g.r  = 0.5 + Math.random() * 1.5;
    g.vy = 0.05 + Math.random() * 0.16;
    g.vx = (Math.random() - 0.5) * 0.12;
    g.a  = 0.10 + Math.random() * 0.28;
  }
  for (let i = 0; i < N; i++) { const g = {}; spawn(g, false); grains.push(g); }

  function tick() {
    if (!running) return;
    ctx.clearRect(0, 0, W, H);
    for (const g of grains) {
      g.x += g.vx; g.y += g.vy;
      if (g.y > H + 2 || g.x < -2 || g.x > W + 2) spawn(g, true);
      ctx.beginPath();
      ctx.fillStyle = `rgba(243,181,58,${g.a})`;
      ctx.arc(g.x, g.y, g.r, 0, Math.PI * 2);
      ctx.fill();
    }
    raf = requestAnimationFrame(tick);
  }

  window.vhubSand = {
    start() {
      if (running) return;
      running = true;
      resize();
      raf = requestAnimationFrame(tick);
    },
    stop() {
      running = false;
      if (raf) { cancelAnimationFrame(raf); raf = null; }
      if (ctx && W && H) ctx.clearRect(0, 0, W, H);
    },
  };
})();
