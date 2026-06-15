// modules/hud/hud.js — Player Info HUD (sempre visivel). Le store('player').

(function () {
  let root = null;
  const offs = [];
  const player = vhub.store('player');

  // ============================================================
  // RENDER
  // ============================================================

  function render() {
    if (!root) return;
    const id = player.get('id');
    root.querySelector('.hud-name').textContent  = player.get('name') || '';
    root.querySelector('.hud-id').textContent    = (id !== undefined && id !== null) ? ('ID ' + id) : '';
    const ph = player.get('phone');
    root.querySelector('.hud-phone').textContent = ph ? ('☎ ' + ph) : '';
  }

  // ============================================================
  // LIFECYCLE
  // ============================================================

  vhub.createModule('hud', {

    onInit() {
      // ouve o delta de HUD vindo do Lua (State Bag -> bridge -> bus)
      offs.push(vhub.listen('nui:hud', (d) => {
        const h = d.hud || {};
        if ('id' in h)    player.set('id', h.id);
        if ('phone' in h) player.set('phone', h.phone);
        if ('name' in h)  player.set('name', h.name);
        render();
      }));
    },

    onMount() {
      root = document.getElementById('hud-root');
      root.className = 'mod-hud';
      root.innerHTML =
        '<div class="hud-name"></div>' +
        '<div class="hud-line"><span class="hud-id"></span><span class="hud-phone"></span></div>';
      root.classList.remove('hidden');
      render();
    },

    onDestroy() {
      offs.forEach((o) => o());
      offs.length = 0;
      if (root) { root.innerHTML = ''; root.classList.add('hidden'); }
    },
  });
})();
