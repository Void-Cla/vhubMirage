// modules/hotbar/hotbar.js — barra de atalhos (1-5). Sempre visivel.
// Vincular: arraste um item da mochila para um slot da barra. Limpar: right-click.
// Usar: tecla configurada (bridge.lua) -> servidor resolve o item e usa.

(function () {
  let root = null;
  const offs = [];
  let binds = {};                       // { [slot]=id }
  const inv = vhub.store('inventory');   // contagem best-effort (atualiza por delta)

  function size() { return (vhub.config && vhub.config.hotbar) || 5; }

  function countOf(id) {
    let n = 0; const s = inv.get('slots') || {};
    for (const k in s) { if (s[k].id === id) n += (s[k].amount || 0); }
    return n;
  }


  // ============================================================
  // RENDER
  // ============================================================

  function render() {
    if (!root) return;
    root.innerHTML = '';
    for (let i = 1; i <= size(); i++) {
      const cell = vhub.util.el('div', 'slot hb-cell');
      cell.dataset.pane = 'hotbar'; cell.dataset.slot = i;       // alvo do drag (pane=hotbar)

      const key = vhub.util.el('div', 'hb-key'); key.textContent = i; cell.appendChild(key);

      const id = binds[i];
      if (id) {
        cell.dataset.filled = '1';
        const def = vhub.util.itemDef(id);
        const ic = vhub.util.el('div', 'ic');
        ic.style.backgroundImage = `url(${vhub.util.itemIcon(id)})`;
        const probe = new Image();                                // fallback se o CDN falhar
        probe.onerror = () => {
          ic.style.backgroundImage = 'none';
          const ini = vhub.util.el('div', 'ini');
          ini.textContent = ((def && def.nome) ? def.nome : id).charAt(0).toUpperCase();
          cell.appendChild(ini);
        };
        probe.src = vhub.util.itemIcon(id);
        cell.appendChild(ic);

        const cnt = countOf(id);
        if (cnt > 0) { const q = vhub.util.el('div', 'qt'); q.textContent = 'x' + cnt; cell.appendChild(q); }
        cell.title = (def && def.nome) || id;
      }
      root.appendChild(cell);
    }
  }


  // ============================================================
  // LIFECYCLE
  // ============================================================

  vhub.createModule('hotbar', {

    onInit() {
      offs.push(vhub.listen('nui:hotbar', (d) => {
        binds = {};
        (d.binds || []).forEach((b) => { binds[b.slot] = b.id; });
        render();
      }));
      // atualiza contagem quando a mochila muda (delta autoritativo)
      offs.push(vhub.listen('nui:delta', (d) => { if (d.delta && d.delta.scope === 'backpack') render(); }));
      offs.push(vhub.listen('nui:open', render));
    },

    onMount() {
      root = document.getElementById('hotbar-root');
      root.className = 'mod-hotbar';
      root.classList.remove('hidden');

      // right-click em um slot da barra: limpar o atalho
      this._onCtx = (e) => {
        const c = e.target.closest('.slot'); if (!c) return;
        e.preventDefault();
        const slot = +c.dataset.slot;
        if (binds[slot]) vhub.post('set_bind', { slot: slot, id: null });
      };
      root.addEventListener('contextmenu', this._onCtx);
      render();
    },

    onDestroy() {
      offs.forEach((o) => o()); offs.length = 0;
      if (root) { root.removeEventListener('contextmenu', this._onCtx); root.innerHTML = ''; root.classList.add('hidden'); }
      root = null;
    },
  });
})();
