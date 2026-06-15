// modules/container/container.js — baú dual-pane (mochila | baú) com transfer otimista.
// Otimista SO no lado de origem (remove de onde arrastou); o destino chega por delta
// do servidor (autoritativo). Em falha, o servidor reenvia o slot e reverte.

(function () {

  // ============================================================
  // ESTADO
  // ============================================================

  const inv  = vhub.store('inventory');   // mochila (compartilhada com o módulo backpack)
  const cont = vhub.store('container');    // baú aberto
  let root = null, bpGrid = null, cnGrid = null, toastEl = null, toastT = 0;
  const offs = [];

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
      const e = slots[i];
      if (e) vhub.util.fillSlot(cell, e);
      frag.appendChild(cell);
    }
    gridEl.innerHTML = ''; gridEl.appendChild(frag);
  }

  function setBar(barId, valId, w, m) {
    const bar = root.querySelector(barId), val = root.querySelector(valId);
    if (!bar || !val) return;
    const pct = m > 0 ? (w / m) * 100 : 0;
    val.textContent = `${vhub.util.fmtWeight(w)} / ${vhub.util.fmtWeight(m)} kg`;
    bar.style.width = Math.min(100, pct) + '%';
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
  // TRANSFER (otimista no lado de origem)
  // ============================================================

  function toast(msg, err) {
    if (!toastEl) return;
    toastEl.textContent = msg; toastEl.classList.toggle('err', !!err); toastEl.classList.add('show');
    clearTimeout(toastT); toastT = setTimeout(() => toastEl.classList.remove('show'), 2200);
  }

  function isStackable(id) { const d = vhub.util.itemDef(id); return !!(d && d.stack); }

  // remove `qty` de um slot (otimista no lado de origem)
  function removeQty(s, slot, qty) {
    const e = s[slot]; if (!e) return;
    if ((qty || e.amount) >= e.amount) delete s[slot]; else e.amount -= qty;
  }

  // rearranjo otimista dentro da mochila (mesma logica do modulo backpack)
  function localMoveBp(from, to, qty) {
    const s = bpSlots(); const a = s[from]; if (!a) return;
    qty = Math.min(qty || a.amount, a.amount);
    const b = s[to];
    if (!b) {
      if (qty >= a.amount) { s[to] = a; delete s[from]; }
      else { s[to] = { id: a.id, amount: qty, meta: isStackable(a.id) ? null : a.meta }; a.amount -= qty; }
    } else if (b.id === a.id && isStackable(a.id)) {
      b.amount += qty; if (qty >= a.amount) delete s[from]; else a.amount -= qty;
    } else if (qty >= a.amount) { s[from] = b; s[to] = a; }
  }

  // destino otimista chega por delta do servidor; aqui so mexemos na ORIGEM
  async function onTransfer(src, dst, entry) {
    if (dst.pane === 'hotbar') {                 // arrastar item da MOCHILA p/ a hotbar
      if (src.pane === 'bp') vhub.post('set_bind', { slot: dst.slot, id: entry.id });
      return;
    }
    if (src.pane === dst.pane) {
      if (src.pane === 'bp' && src.slot !== dst.slot) {       // rearranjo da mochila
        let qty = entry.amount;
        if (qty > 1) { qty = await vhub.interact.qtyModal(entry.amount); if (!qty) return; }
        localMoveBp(src.slot, dst.slot, qty); renderBackpack();
        vhub.post('move', { from: src.slot, to: dst.slot, qty: qty });
      }
      return;   // cn->cn: rearranjo interno do baú fica p/ depois
    }
    let qty = entry.amount;
    if (qty > 1) { qty = await vhub.interact.qtyModal(entry.amount); if (!qty) return; }
    if (src.pane === 'bp' && dst.pane === 'cn') {
      removeQty(bpSlots(), src.slot, qty); renderBackpack();
      vhub.post('store', { from: src.slot, to: dst.slot, qty: qty });
    } else if (src.pane === 'cn' && dst.pane === 'bp') {
      removeQty(cnSlots(), src.slot, qty); renderContainer();
      vhub.post('retrieve', { from: src.slot, to: dst.slot, qty: qty });
    }
  }


  // ============================================================
  // LIFECYCLE
  // ============================================================

  vhub.createModule('container', {

    onInit() {
      offs.push(vhub.listen('nui:container_open', (d) => {
        const data = d.data || {}, bp = data.backpack || {}, cn = data.container || {};
        setItems(inv, bp.items);  inv.set('max', bp.max || 0);     inv.set('size', bp.size || 30);
        setItems(cont, cn.items); cont.set('capacity', cn.capacity || 0); cont.set('size', cn.size || 50);
        cont.set('label', cn.label || 'Baú');
        vhub.mount('container');
        renderAll();
      }));
      offs.push(vhub.listen('nui:container_close', () => vhub.unmount('container')));

      // diffs do servidor (autoritativos)
      offs.push(vhub.listen('nui:container_delta', (d) => { applyItems(cont, (d.delta || {}).items); renderContainer(); }));
      offs.push(vhub.listen('nui:delta', (d) => {
        if (!d.delta || d.delta.scope !== 'backpack') return;
        applyItems(inv, d.delta.items); renderBackpack();
      }));
      offs.push(vhub.listen('nui:rollback', (d) => {
        const data = d.data || {}; if (data.scope && data.scope !== 'backpack') return;
        applyItems(inv, data.items); renderBackpack();
        toast(LANG[data.reason] || 'Operação negada', true);
      }));
      offs.push(vhub.listen('nui:notify', (d) => toast(d.msg || '', true)));
    },

    onMount() {
      root = document.getElementById('container-root');
      root.className = 'mod-container';
      root.innerHTML =
        '<div class="ct-shell">' +
          '<section class="ct-panel">' +
            '<div class="ct-head"><div class="ct-title">MOCHILA</div></div>' +
            '<div class="ct-grid" id="ct-bp"></div>' +
            '<div class="ct-foot"><div class="ct-wlabel"><span>Peso</span><span id="ct-bp-val"></span></div>' +
              '<div class="ct-track"><div class="ct-bar" id="ct-bp-bar"></div></div></div>' +
          '</section>' +
          '<section class="ct-panel">' +
            '<div class="ct-head"><div class="ct-title ct-cn-title">BAÚ</div><div class="ct-close">&times;</div></div>' +
            '<div class="ct-grid" id="ct-cn"></div>' +
            '<div class="ct-foot"><div class="ct-wlabel"><span>Capacidade</span><span id="ct-cn-val"></span></div>' +
              '<div class="ct-track"><div class="ct-bar" id="ct-cn-bar"></div></div></div>' +
          '</section>' +
        '</div>' +
        '<div class="ct-toast"></div>';
      root.classList.remove('hidden');

      bpGrid = root.querySelector('#ct-bp');
      cnGrid = root.querySelector('#ct-cn');
      toastEl = root.querySelector('.ct-toast');
      root.querySelector('.ct-cn-title').textContent = (cont.get('label') || 'Baú').toUpperCase();

      // arraste por MOUSE nas duas paineis (compartilhado)
      this._cleanupDrag = vhub.interact.enableDrag(root, {
        getEntry: (pane, slot) => (pane === 'cn' ? cnSlots() : bpSlots())[slot],
        onTransfer: onTransfer,
      });
      this._onClose = () => vhub.post('container_close');
      this._onKey   = (e) => { if (e.key === 'Escape') vhub.post('container_close'); };

      root.querySelector('.ct-close').addEventListener('click', this._onClose);
      window.addEventListener('keydown', this._onKey);
    },

    onDestroy() {
      if (this._cleanupDrag) this._cleanupDrag();
      window.removeEventListener('keydown', this._onKey);
      clearTimeout(toastT);
      if (root) { root.innerHTML = ''; root.classList.add('hidden'); }
      root = null; bpGrid = null; cnGrid = null; toastEl = null;
    },
  });
})();
