// nui/js/sand.js — particulas de areia (vHub theme)
// Densidade fixa, pausada quando NUI fechada (resmon obrigatorio < 0.10ms idle)
(() => {
  const canvas = document.getElementById('vhub-sand');
  if (!canvas) return;
  const ctx = canvas.getContext('2d');
  let W = 0, H = 0;
  const grains = [];
  const N = 40;
  let running = false;
  let raf = null;

  function resize() {
    W = canvas.width  = canvas.clientWidth;
    H = canvas.height = canvas.clientHeight;
  }
  window.addEventListener('resize', resize);

  function spawn(g) {
    g.x = Math.random() * W;
    g.y = Math.random() * H;
    g.r = 0.5 + Math.random() * 1.5;
    g.vy = 0.05 + Math.random() * 0.15;
    g.vx = (Math.random() - 0.5) * 0.12;
    g.a = 0.10 + Math.random() * 0.25;
  }
  for (let i = 0; i < N; i++) { const g = {}; spawn(g); grains.push(g); }

  function tick() {
    if (!running) return;
    ctx.clearRect(0, 0, W, H);
    for (const g of grains) {
      g.x += g.vx; g.y += g.vy;
      if (g.y > H + 2 || g.x < -2 || g.x > W + 2) spawn(g);
      ctx.beginPath();
      ctx.fillStyle = `rgba(243,181,58,${g.a})`;
      ctx.arc(g.x, g.y, g.r, 0, Math.PI * 2);
      ctx.fill();
    }
    raf = requestAnimationFrame(tick);
  }

  window.vhubSand = {
    start() { if (running) return; running = true; resize(); tick(); },
    stop()  { running = false; if (raf) cancelAnimationFrame(raf); ctx && ctx.clearRect(0, 0, W, H); },
  };
})();
