// modules/hud/hud.js — Player Info HUD (sempre visivel). Le store('player').

(function () {
  let root = null;
  const offs = [];
  const player = vhub.store('player');

  // ============================================================
  // RENDER
  // ============================================================

  function render() {
    // hud-pill removida: ID não é exibido em jogo; render reservada para futuras adições visuais
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
        render();   // apenas ID; topbar da mochila ouve o mesmo bus e atualiza o perfil
      }));
    },

    onMount() {
      root = document.getElementById('hud-root');
      root.className = 'mod-hud';
      // hud-pill removida: ID do personagem não é exibido na tela durante o jogo
      render();
    },

    onShow() { if (root) root.classList.remove('hidden'); },

    onHide() { if (root) root.classList.add('hidden'); },

    onDestroy() {
      offs.forEach((o) => o());
      offs.length = 0;
      if (root) { root.innerHTML = ''; root.classList.add('hidden'); }
    },
  });
})();
