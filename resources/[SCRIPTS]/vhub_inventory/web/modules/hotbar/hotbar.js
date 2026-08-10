// modules/hotbar/hotbar.js — barra de atalhos (1-5). Sempre visível.
// Vincular: arraste um item da mochila para um slot da barra. Limpar: right-click.
// Usar: tecla configurada (bridge.lua) -> servidor resolve o item e usa.

(function () {
  let root = null;
  const offs = [];
  let binds = {};                        // { [slot]=id }
  const inv = vhub.store('inventory');    // contagem best-effort (atualiza por delta)

  let _peekTimer   = null;
  let _backpackOpen = false;

  function showRoot()  { if (root) root.classList.remove('hidden'); }
  function hideRoot()  { if (root) root.classList.add('hidden'); }

  // mostra a hotbar por PEEK_MS e então esconde (cancela timer anterior)
  const PEEK_MS = 5000;
  function peekHotbar() {
    showRoot();
    if (_peekTimer) clearTimeout(_peekTimer);
    if (_backpackOpen) return;          // mochila aberta → não auto-esconde
    _peekTimer = setTimeout(function () { _peekTimer = null; hideRoot(); }, PEEK_MS);
  }

  function size() { return (vhub.config && vhub.config.hotbar) || 5; }

  // total do item id somando todos os slots da mochila
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
    const frag = document.createDocumentFragment();
    for (let i = 1; i <= size(); i++) {
      const cell = vhub.util.el('div', 'slot hb-cell');
      cell.dataset.pane = 'hotbar'; cell.dataset.slot = i;       // alvo do drag (pane=hotbar)

      const key = vhub.util.el('div', 'hb-key'); key.textContent = i; cell.appendChild(key);

      const id = binds[i];
      if (id) {
        cell.dataset.filled = '1';
        const def = vhub.util.itemDef(id) || {};
        cell.style.setProperty('--slot-accent', vhub.util.legalityColor(def.legalidade));

        const ic = vhub.util.el('div', 'ic');
        cell.appendChild(ic);
        vhub.util.applyIcon(ic, id);                                          // SVG local + PNG do repo se carregar

        const cnt = countOf(id);
        const q = vhub.util.el('div', 'qt' + (cnt === 0 ? ' hb-empty' : ''));
        q.textContent = cnt;
        cell.appendChild(q);
        cell.title = def.nome || id;
      }
      frag.appendChild(cell);
    }
    root.innerHTML = '';
    root.appendChild(frag);
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
      // peek via tecla 1-5 do Lua (action = hotbar_peek → nui:hotbar_peek)
      offs.push(vhub.listen('nui:hotbar_peek', () => peekHotbar()));
      // mochila abre → mostra hotbar; fecha → esconde
      offs.push(vhub.listen('nui:open', () => {
        _backpackOpen = true;
        if (_peekTimer) { clearTimeout(_peekTimer); _peekTimer = null; }
        showRoot();
        render();
      }));
      offs.push(vhub.listen('nui:close', () => {
        _backpackOpen = false;
        hideRoot();
      }));
    },

    onMount() {
      root = document.getElementById('hotbar-root');
      root.className = 'mod-hotbar';
      // inicia escondida: aparece apenas no peek (tecla 1-5) ou quando mochila abre

      // right-click num slot da barra: limpar o atalho
      this._onCtx = (e) => {
        const c = e.target.closest('.slot'); if (!c) return;
        e.preventDefault();
        const slot = +c.dataset.slot;
        if (binds[slot]) vhub.post('set_bind', { slot: slot, id: null });
      };
      root.addEventListener('contextmenu', this._onCtx);
      render();
    },

    onShow() { /* visibilidade controlada por peekHotbar / nui:open-close */ },

    onHide() { hideRoot(); },

    onDestroy() {
      offs.forEach((o) => o()); offs.length = 0;
      if (_peekTimer) { clearTimeout(_peekTimer); _peekTimer = null; }
      _backpackOpen = false;
      if (root) { root.removeEventListener('contextmenu', this._onCtx); root.innerHTML = ''; root.classList.add('hidden'); }
      root = null;
    },
  });
})();
