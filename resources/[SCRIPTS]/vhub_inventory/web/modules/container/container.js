// modules/container/container.js — baú dual-pane (mochila | baú) com transfer autoritativa.
// A UI só solicita; origem e destino mudam por delta do servidor. Verdade = servidor.

(function () {

  // ============================================================
  // ESTADO
  // ============================================================

  const inv  = vhub.store('inventory');
  const cont = vhub.store('container');
  let root = null, bpGrid = null, cnGrid = null, toastEl = null, sandEl = null, toastT = 0;
  const offs      = [];
  const pendingBp = new Map();   // slot → timeoutId (mochila)
  const pendingCn = new Map();   // slot → timeoutId (baú)

  const LANG = {
    mov_negado: 'Movimento negado', ocupado: 'Baú em uso, tente de novo',
    cheio: 'Baú cheio', bloqueado: 'Item não permitido no baú',
    peso: 'Mochila cheia', qty: 'Quantidade inválida', vazio: 'Item não encontrado',
  };

  function bpSlots() { return inv.get('slots')  || inv.set('slots', {}).get('slots'); }
  function cnSlots() { return cont.get('slots') || cont.set('slots', {}).get('slots'); }

  function weightOf(s) {
    let w = 0;
    for (const k in s) { const d = vhub.util.itemDef(s[k].id); if (d) w += (d.peso || 0) * (s[k].amount || 0); }
    return w;
  }


  // ============================================================
  // WIRE -> ESTADO
  // ============================================================

  function setItems(store, items) {
    const s = {};
    (items || []).forEach((it) => { s[it.slot] = { id: it.id, amount: it.amount, meta: it.meta }; });
    store.set('slots', s);
  }
  function applyItems(store, items) {
    const s = store.get('slots') || {};
    (items || []).forEach((it) => {
      if (it.clear) delete s[it.slot]; else s[it.slot] = { id: it.id, amount: it.amount, meta: it.meta };
    });
    store.set('slots', s);
  }


  // ============================================================
  // RENDER
  // ============================================================

  function renderGrid(gridEl, slots, size, pane) {
    if (!gridEl) return;
    const frag = document.createDocumentFragment();
    for (let i = 1; i <= size; i++) {
      const cell = vhub.util.el('div', 'slot');
      cell.dataset.slot = i; cell.dataset.pane = pane;
      cell.setAttribute('tabindex', '0');
      cell.setAttribute('role', 'gridcell');
      const e = slots[i];
      if (e) {
        vhub.util.fillSlot(cell, e);
        cell.setAttribute('aria-label', (vhub.util.itemDef(e.id) || {}).nome || e.id);
      } else {
        cell.setAttribute('aria-label', 'Slot vazio ' + i);
      }
      frag.appendChild(cell);
    }
    gridEl.innerHTML = ''; gridEl.appendChild(frag);
  }

  function setBar(barId, valId, w, m) {
    const bar = root.querySelector(barId), val = root.querySelector(valId);
    if (!bar || !val) return;
    const pct = m > 0 ? (w / m) * 100 : 0;
    val.textContent = `${vhub.util.fmtWeight(w)} / ${vhub.util.fmtWeight(m)} kg`;
    bar.style.transform = 'scaleX(' + Math.min(1, pct / 100) + ')';
    bar.style.background = vhub.util.weightColor(pct);
  }

  function renderBackpack() {
    renderGrid(bpGrid, bpSlots(), inv.get('size') || 30, 'bp');
    if (root) setBar('#ct-bp-bar', '#ct-bp-val', weightOf(bpSlots()), inv.get('max') || 0);
  }
  function renderContainer() {
    renderGrid(cnGrid, cnSlots(), cont.get('size') || 50, 'cn');
    if (root) setBar('#ct-cn-bar', '#ct-cn-val', weightOf(cnSlots()), cont.get('capacity') || 0);
  }
  function renderAll() { renderBackpack(); renderContainer(); }


  // ============================================================
  // PENDING OVERLAY
  // ============================================================

  function setPending(map, grid, slot) {
    if (!grid) return;
    const cell = grid.querySelector(`.slot[data-slot="${slot}"]`);
    if (cell) cell.classList.add('slot--pending');
    clearTimeout(map.get(slot));
    map.set(slot, setTimeout(() => clearPending(map, grid, slot), 5000));
  }
  function clearPending(map, grid, slot) {
    clearTimeout(map.get(slot)); map.delete(slot);
    if (!grid) return;
    const cell = grid.querySelector(`.slot[data-slot="${slot}"]`);
    if (cell) cell.classList.remove('slot--pending');
  }


  // ============================================================
  // TRANSFER
  // ============================================================

  function toast(msg, err) {
    if (!toastEl) return;
    toastEl.textContent = msg; toastEl.classList.toggle('err', !!err); toastEl.classList.add('show');
    clearTimeout(toastT); toastT = setTimeout(() => toastEl.classList.remove('show'), 2200);
  }

  async function onTransfer(src, dst, entry) {
    if (dst.pane === 'hotbar') {
      if (src.pane === 'bp') vhub.post('set_bind', { slot: dst.slot, id: entry.id });
      return;
    }
    if (src.pane === dst.pane) {
      if (src.pane === 'bp' && src.slot !== dst.slot) {
        let qty = entry.amount;
        if (qty > 1) { qty = await vhub.interact.qtyModal(entry.amount); if (!qty) return; }
        setPending(pendingBp, bpGrid, src.slot);
        vhub.post('move', { from: src.slot, to: dst.slot, qty: qty });
      }
      return;
    }
    let qty = entry.amount;
    if (qty > 1) { qty = await vhub.interact.qtyModal(entry.amount); if (!qty) return; }
    if (src.pane === 'bp' && dst.pane === 'cn') {
      setPending(pendingBp, bpGrid, src.slot);
      vhub.post('store', { from: src.slot, to: dst.slot, qty: qty });
    } else if (src.pane === 'cn' && dst.pane === 'bp') {
      setPending(pendingCn, cnGrid, src.slot);
      vhub.post('retrieve', { from: src.slot, to: dst.slot, qty: qty });
    }
  }


  // ============================================================
  // LIFECYCLE
  // ============================================================

  vhub.createModule('container', {

    onInit() {
      // guard: offs ja populado = listeners registrados; nao registrar duplo entre mounts
      if (offs.length > 0) return;

      offs.push(vhub.listen('nui:container_open', (d) => {
        const data = d.data || {}, bp = data.backpack || {}, cn = data.container || {};
        setItems(inv, bp.items);  inv.set('max', bp.max || 0);     inv.set('size', bp.size || 30);
        setItems(cont, cn.items); cont.set('capacity', cn.capacity || 0); cont.set('size', cn.size || 50);
        cont.set('label', cn.label || 'Baú'); cont.set('kind', cn.kind || 'static');
        vhub.mount('container');
        renderAll();
      }));
      offs.push(vhub.listen('nui:container_close', () => vhub.unmount('container')));

      offs.push(vhub.listen('nui:container_delta', (d) => {
        ((d.delta || {}).items || []).forEach((it) => clearPending(pendingCn, cnGrid, it.slot));
        applyItems(cont, (d.delta || {}).items);
        renderContainer();
      }));
      offs.push(vhub.listen('nui:delta', (d) => {
        if (!d.delta || d.delta.scope !== 'backpack') return;
        (d.delta.items || []).forEach((it) => clearPending(pendingBp, bpGrid, it.slot));
        applyItems(inv, d.delta.items); renderBackpack();
      }));
      offs.push(vhub.listen('nui:rollback', (d) => {
        const data = d.data || {}; if (data.scope && data.scope !== 'backpack') return;
        (data.items || []).forEach((it) => clearPending(pendingBp, bpGrid, it.slot));
        applyItems(inv, data.items); renderBackpack();
        toast(LANG[data.reason] || 'Operação negada', true);
      }));

      offs.push(vhub.listen('nui:notify', (d) => toast(d.msg || '', false)));
    },

    onMount() {
      root = document.getElementById('container-root');
      root.className = 'mod-container';

      const kind  = cont.get('kind') || 'static';
      const cnIco = kind === 'trunk'
        ? '<path d="M3 13l2-6a2 2 0 0 1 2-1.4h10A2 2 0 0 1 21 7l2 6M5 13h14v4a1 1 0 0 1-1 1h-1a2 2 0 0 1-4 0H9a2 2 0 0 1-4 0H5a1 1 0 0 1-1-1z"/>'
        : '<rect x="4" y="8" width="16" height="12" rx="2"/><path d="M4 12h16M9 8V6a3 3 0 0 1 6 0v2"/>';

      root.innerHTML =
        '<canvas class="vh-sand" aria-hidden="true"></canvas>' +
        '<div class="ct-shell">' +
          '<section class="ct-panel">' +
            '<div class="ct-head">' +
              '<svg class="ct-ico" viewBox="0 0 24 24"><rect x="4" y="9" width="16" height="12" rx="2"/><path d="M9 9V7a3 3 0 0 1 6 0v2"/></svg>' +
              '<div class="ct-title">MOCHILA</div>' +
            '</div>' +
            '<div class="ct-grid" id="ct-bp" role="grid" aria-label="Grade de itens da mochila"></div>' +
            '<div class="ct-foot"><div class="ct-wlabel"><span>Peso</span><span id="ct-bp-val"></span></div>' +
              '<div class="ct-track"><div class="ct-bar" id="ct-bp-bar"></div></div></div>' +
          '</section>' +
          '<section class="ct-panel ct-panel--dst">' +
            '<div class="ct-head">' +
              '<svg class="ct-ico" viewBox="0 0 24 24">' + cnIco + '</svg>' +
              '<div class="ct-title ct-cn-title">BAÚ</div>' +
              '<div class="ct-close" tabindex="0" role="button" aria-label="Fechar baú">&#x2715;</div>' +
            '</div>' +
            '<div class="ct-grid" id="ct-cn" role="grid" aria-label="Grade de itens do baú"></div>' +
            '<div class="ct-foot"><div class="ct-wlabel"><span>Capacidade</span><span id="ct-cn-val"></span></div>' +
              '<div class="ct-track"><div class="ct-bar" id="ct-cn-bar"></div></div></div>' +
          '</section>' +
          '<div class="ct-insp"></div>' +
        '</div>' +
        '<div class="ct-toast" role="status" aria-live="polite"></div>';
      root.classList.remove('hidden');

      sandEl  = root.querySelector('.vh-sand');
      bpGrid  = root.querySelector('#ct-bp');
      cnGrid  = root.querySelector('#ct-cn');
      toastEl = root.querySelector('.ct-toast');
      root.querySelector('.ct-cn-title').textContent = (cont.get('label') || 'Baú').toUpperCase();

      if (vhub.sand && sandEl) vhub.sand.start(sandEl);
      this._inspectOff = vhub.inspect.init(root.querySelector('.ct-insp'));

      this._onBpClick = (e) => {
        const c = e.target.closest('.slot');
        if (!c || !c.dataset.filled) { vhub.inspect.hide(); return; }
        const entry = bpSlots()[+c.dataset.slot];
        if (entry) vhub.inspect.show(entry);
      };
      this._onCnClick = (e) => {
        const c = e.target.closest('.slot');
        if (!c || !c.dataset.filled) { vhub.inspect.hide(); return; }
        const entry = cnSlots()[+c.dataset.slot];
        if (entry) vhub.inspect.show(entry);
      };

      this._cleanupDrag = vhub.interact.enableDrag(root, {
        getEntry: (pane, slot) => (pane === 'cn' ? cnSlots() : bpSlots())[slot],
        onTransfer: onTransfer,
      });
      this._onClose = () => vhub.post('container_close');
      this._onKey   = (e) => { if (e.key === 'Escape') vhub.post('container_close'); };

      bpGrid.addEventListener('click', this._onBpClick);
      cnGrid.addEventListener('click', this._onCnClick);
      root.querySelector('.ct-close').addEventListener('click', this._onClose);
      window.addEventListener('keydown', this._onKey);
    },

    onShow() { if (root) root.classList.remove('hidden'); },

    onHide() { if (vhub.inspect) vhub.inspect.hide(); },

    onDestroy() {
      if (vhub.sand) vhub.sand.stop();
      if (this._cleanupDrag) this._cleanupDrag();
      if (bpGrid) bpGrid.removeEventListener('click', this._onBpClick);
      if (cnGrid) cnGrid.removeEventListener('click', this._onCnClick);
      window.removeEventListener('keydown', this._onKey);
      clearTimeout(toastT);
      pendingBp.forEach((t) => clearTimeout(t)); pendingBp.clear();
      pendingCn.forEach((t) => clearTimeout(t)); pendingCn.clear();
      if (this._inspectOff) { this._inspectOff(); this._inspectOff = null; }
      if (root) { root.innerHTML = ''; root.classList.add('hidden'); }
      // offs NAO sao drenados: governam o ciclo mount/unmount deste modulo lazy.
      root = null; bpGrid = null; cnGrid = null; toastEl = null; sandEl = null;
    },
  });
})();
