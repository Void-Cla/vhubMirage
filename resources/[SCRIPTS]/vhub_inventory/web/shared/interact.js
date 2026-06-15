// shared/interact.js — drag por MOUSE (confiavel no CEF) + modal de quantidade.
// HTML5 drag-and-drop e instavel no CEF do FiveM; aqui usamos mousedown/move/up.
// Compartilhado por mochila e baú (DRY). Distingue clique (sem mover) de arraste.

(function () {
  vhub.interact = {};

  const THRESHOLD = 4;   // px de movimento p/ iniciar arraste (clique nao arrasta)

  // slot sob o cursor (ignora o ghost por pointer-events:none)
  function slotUnder(x, y) {
    const el = document.elementFromPoint(x, y);
    return el ? el.closest('.slot') : null;
  }

  // cria o "fantasma" que segue o cursor
  function makeGhost(entry) {
    const g = document.createElement('div');
    g.className = 'vh-ghost';
    g.style.backgroundImage = `url(${vhub.util.itemIcon(entry.id)})`;
    document.body.appendChild(g);
    return g;
  }


  // ============================================================
  // DRAG por mouse — enableDrag(rootEl, opts) -> cleanup()
  //   opts.getEntry(pane, slot) -> entry|null
  //   opts.onTransfer(src, dst, qty)   (src/dst = { pane, slot })
  // ============================================================

  vhub.interact.enableDrag = function (rootEl, opts) {
    let pending = null, active = null, ghost = null;

    const moveGhost = (x, y) => { if (ghost) { ghost.style.left = x + 'px'; ghost.style.top = y + 'px'; } };
    const clearHot  = () => rootEl.querySelectorAll('.drop-hot').forEach((c) => c.classList.remove('drop-hot'));
    const highlight = (x, y) => { clearHot(); const c = slotUnder(x, y); if (c && rootEl.contains(c)) c.classList.add('drop-hot'); };

    function onDown(e) {
      if (e.button !== 0) return;
      const cell = e.target.closest('.slot');
      if (!cell || !cell.dataset.filled) return;
      const src = { pane: cell.dataset.pane || 'bp', slot: +cell.dataset.slot };
      const entry = opts.getEntry(src.pane, src.slot);
      if (!entry) return;
      pending = { src: src, entry: entry, x: e.clientX, y: e.clientY };
    }

    function onMove(e) {
      if (active) { moveGhost(e.clientX, e.clientY); highlight(e.clientX, e.clientY); return; }
      if (pending && (Math.abs(e.clientX - pending.x) + Math.abs(e.clientY - pending.y)) > THRESHOLD) {
        active = pending; pending = null;
        ghost = makeGhost(active.entry); moveGhost(e.clientX, e.clientY);
      }
    }

    function onUp(e) {
      pending = null;
      if (!active) return;
      const a = active; active = null;
      if (ghost) { ghost.remove(); ghost = null; }
      clearHot();

      const cell = slotUnder(e.clientX, e.clientY);
      if (!cell) return;
      const dst = { pane: cell.dataset.pane || 'bp', slot: +cell.dataset.slot };
      if (dst.pane === a.src.pane && dst.slot === a.src.slot) return;

      // o modulo decide a quantidade (qtyModal) conforme o destino (ex: hotbar pula o modal)
      opts.onTransfer(a.src, dst, a.entry);
    }

    rootEl.addEventListener('mousedown', onDown);
    window.addEventListener('mousemove', onMove);
    window.addEventListener('mouseup', onUp);

    return function cleanup() {
      rootEl.removeEventListener('mousedown', onDown);
      window.removeEventListener('mousemove', onMove);
      window.removeEventListener('mouseup', onUp);
      if (ghost) { ghost.remove(); }
      ghost = null; active = null; pending = null;
    };
  };


  // ============================================================
  // MODAL DE QUANTIDADE — qtyModal(max) -> Promise<number|null>
  // ============================================================

  vhub.interact.qtyModal = function (max) {
    return new Promise((resolve) => {
      const ov     = document.getElementById('qty-modal');
      const input  = ov.querySelector('.qm-input');
      const slider = ov.querySelector('.qm-slider');
      const maxEl  = ov.querySelector('.qm-max');
      const ok     = ov.querySelector('.qm-ok');
      const cancel = ov.querySelector('.qm-cancel');
      const allBtn = ov.querySelector('.qm-all');

      input.min = 1; input.max = max; input.value = max;
      slider.min = 1; slider.max = max; slider.value = max;
      maxEl.textContent = '/ ' + max;
      ov.classList.remove('hidden');
      input.focus(); input.select();

      const clamp = (v) => Math.max(1, Math.min(max, Math.floor(+v || 1)));
      const sync  = (v) => { const c = clamp(v); input.value = c; slider.value = c; };
      const onInput = () => sync(input.value);
      const onSlide = () => sync(slider.value);

      const cleanup = () => {
        ov.classList.add('hidden');
        input.removeEventListener('input', onInput);
        slider.removeEventListener('input', onSlide);
        ok.removeEventListener('click', onOk);
        cancel.removeEventListener('click', onCancel);
        allBtn.removeEventListener('click', onAll);
        input.removeEventListener('keydown', onKey);
      };
      const onOk     = () => { const v = clamp(input.value); cleanup(); resolve(v); };
      const onCancel = () => { cleanup(); resolve(null); };
      const onAll    = () => { cleanup(); resolve(max); };
      const onKey    = (e) => { if (e.key === 'Enter') onOk(); else if (e.key === 'Escape') { e.stopPropagation(); onCancel(); } };

      input.addEventListener('input', onInput);
      slider.addEventListener('input', onSlide);
      ok.addEventListener('click', onOk);
      cancel.addEventListener('click', onCancel);
      allBtn.addEventListener('click', onAll);
      input.addEventListener('keydown', onKey);
    });
  };


  // ============================================================
  // MENU DE CONTEXTO — contextMenu(x, y, options[{label, onClick, disabled}])
  // ============================================================

  vhub.interact.contextMenu = function (x, y, options) {
    const old = document.getElementById('vh-ctx');
    if (old) old.remove();

    const menu = document.createElement('div');
    menu.id = 'vh-ctx'; menu.className = 'vh-ctx';
    menu.style.left = x + 'px'; menu.style.top = y + 'px';

    const close = () => { menu.remove(); window.removeEventListener('mousedown', onOut, true); };
    const onOut = (e) => { if (!menu.contains(e.target)) close(); };

    options.forEach((opt) => {
      const it = document.createElement('div');
      it.className = 'vh-ctx-item' + (opt.disabled ? ' disabled' : '');
      it.textContent = opt.label;
      if (!opt.disabled) it.addEventListener('click', () => { close(); opt.onClick(); });
      menu.appendChild(it);
    });

    document.body.appendChild(menu);
    setTimeout(() => window.addEventListener('mousedown', onOut, true), 0);  // fecha ao clicar fora
  };
})();
