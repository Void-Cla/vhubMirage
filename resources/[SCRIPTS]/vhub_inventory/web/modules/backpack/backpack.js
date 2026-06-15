// modules/backpack/backpack.js — mochila (grid + drag-drop + UI otimista).
// Slice: store('inventory'). Verdade e do servidor; aqui so renderizamos e
// disparamos INTENCAO. Servidor confirma por delta ou corrige por rollback.

(function () {

  // ============================================================
  // ESTADO
  // ============================================================

  const inv    = vhub.store('inventory');
  const player = vhub.store('player');
  let root = null, gridEl = null, toastEl = null, toastT = 0;
  let filterText = '', filterCat = 'all';
  const offs = [];

  const LANG = {
    mov_negado: 'Movimento negado',
    weight:     'Peso excedido',
    full:       'Inventário cheio',
    qty:        'Quantidade inválida',
    erro:       'Operação negada',
  };

  // slots vivem como mapa { [slot]=entry }; itens da NUI sao indexados por slot
  function slots() { return inv.get('slots') || inv.set('slots', {}).get('slots'); }
  function size()  { return inv.get('size') || (vhub.config && vhub.config.size) || 30; }
  function maxW()  { return inv.get('max')  || (vhub.config && vhub.config.max)  || 0; }

  function isStackable(id) {
    const d = vhub.util.itemDef(id);
    return !!(d && d.stack);
  }

  function weightOf(s) {
    let w = 0;
    for (const k in s) {
      const d = vhub.util.itemDef(s[k].id);
      if (d) w += (d.peso || 0) * (s[k].amount || 0);
    }
    return w;
  }


  // ============================================================
  // WIRE -> ESTADO (lista de itens vinda do Lua)
  // ============================================================

  // substitui todos os slots a partir de uma lista { slot,id,amount,meta }
  function setFromItems(items) {
    const s = {};
    (items || []).forEach((it) => { s[it.slot] = { id: it.id, amount: it.amount, meta: it.meta }; });
    inv.set('slots', s);
  }

  // aplica um diff (lista com {slot,...} ou {slot,clear})
  function applyItems(items) {
    const s = slots();
    (items || []).forEach((it) => {
      if (it.clear) delete s[it.slot];
      else s[it.slot] = { id: it.id, amount: it.amount, meta: it.meta };
    });
  }


  // ============================================================
  // RENDER
  // ============================================================

  function renderPanel() {
    if (!root) return;
    const nameEl = root.querySelector('.bp-pname');
    if (!nameEl) return;
    nameEl.textContent = player.get('name') || 'Cidadão';
    const id = player.get('id');
    root.querySelector('.bp-pid').textContent   = (id != null) ? id : '--';
    root.querySelector('.bp-pphone').textContent = player.get('phone') || '--';
  }

  function renderWeight() {
    if (!root) return;
    const valEl = root.querySelector('.bp-weight-val');
    const bar   = root.querySelector('.bp-weight-bar');
    if (!valEl || !bar) return;
    const w = weightOf(slots()), m = maxW();
    const pctRaw = m > 0 ? (w / m) * 100 : 0;
    valEl.textContent = `${vhub.util.fmtWeight(w)} / ${vhub.util.fmtWeight(m)} kg`;
    bar.style.width = Math.min(100, pctRaw) + '%';
    bar.style.background = vhub.util.weightColor(pctRaw);   // gradiente por ocupacao
  }

  function renderGrid() {
    if (!gridEl) return;
    const s = slots(), n = size();
    const frag = document.createDocumentFragment();
    for (let i = 1; i <= n; i++) {
      const cell = vhub.util.el('div', 'slot');
      cell.dataset.slot = i;
      const e = s[i];
      if (e) vhub.util.fillSlot(cell, e);   // render compartilhado (DRY)
      frag.appendChild(cell);
    }
    gridEl.innerHTML = '';
    gridEl.appendChild(frag);
    renderChips(); applyFilter();           // busca + categorias
  }

  // ---- busca / categorias (esmaece o que nao casa; mantem as posicoes) ----
  function itemMatches(entry) {
    if (!entry) return true;
    const def = vhub.util.itemDef(entry.id) || {};
    if (filterCat !== 'all' && (def.categoria || 'outros') !== filterCat) return false;
    if (filterText) return ((def.nome || entry.id) + '').toLowerCase().includes(filterText);
    return true;
  }
  function applyFilter() {
    if (!gridEl) return;
    const s = slots();
    gridEl.querySelectorAll('.slot').forEach((cell) => {
      const entry = s[+cell.dataset.slot];
      cell.classList.toggle('dim', !!entry && !itemMatches(entry));
    });
  }
  function renderChips() {
    if (!root) return;
    const wrap = root.querySelector('.bp-cats'); if (!wrap) return;
    const cats = new Set(), s = slots();
    for (const k in s) { const d = vhub.util.itemDef(s[k].id); cats.add((d && d.categoria) || 'outros'); }
    const list = ['all'].concat(Array.from(cats).sort());
    wrap.innerHTML = '';
    list.forEach((c) => {
      const chip = vhub.util.el('div', 'bp-chip' + (c === filterCat ? ' active' : ''));
      chip.textContent = c === 'all' ? 'Todos' : c;
      chip.dataset.cat = c;
      wrap.appendChild(chip);
    });
  }

  function renderAll() { renderPanel(); renderWeight(); renderGrid(); }


  // ============================================================
  // INTERACAO (otimista) + TOAST
  // ============================================================

  function toast(msg, isErr) {
    if (!toastEl) return;
    toastEl.textContent = msg;
    toastEl.classList.toggle('err', !!isErr);
    toastEl.classList.add('show');
    clearTimeout(toastT);
    toastT = setTimeout(() => toastEl.classList.remove('show'), 2200);
  }

  // movimento otimista local, ciente de quantidade (servidor confirma/corrige depois)
  function localMove(from, to, qty) {
    const s = slots();
    const a = s[from]; if (!a) return;
    qty = Math.min(qty || a.amount, a.amount);
    const b = s[to];
    if (!b) {
      if (qty >= a.amount) { s[to] = a; delete s[from]; }
      else { s[to] = { id: a.id, amount: qty, meta: isStackable(a.id) ? null : a.meta }; a.amount -= qty; }
    } else if (b.id === a.id && isStackable(a.id)) {
      b.amount += qty; if (qty >= a.amount) delete s[from]; else a.amount -= qty;
    } else if (qty >= a.amount) {
      s[from] = b; s[to] = a;     // swap so move o stack inteiro
    }
  }


  // ============================================================
  // LIFECYCLE
  // ============================================================

  vhub.createModule('backpack', {

    onInit() {
      // abrir/fechar comandados pelo servidor/bridge
      offs.push(vhub.listen('nui:open', (d) => {
        const snap = d.snap || {};
        setFromItems(snap.items);
        inv.set('max', snap.max || 0);
        inv.set('size', snap.size || 30);
        vhub.mount('backpack');
        renderAll();
      }));
      offs.push(vhub.listen('nui:close', () => vhub.unmount('backpack')));

      // confirmacao incremental do servidor
      offs.push(vhub.listen('nui:delta', (d) => {
        if (!d.delta || d.delta.scope !== 'backpack') return;
        applyItems(d.delta.items);
        renderGrid(); renderWeight();
      }));

      // rollback: estado autoritativo dos slots tocados
      offs.push(vhub.listen('nui:rollback', (d) => {
        const data = d.data || {};
        if (data.scope && data.scope !== 'backpack') return;
        applyItems(data.items);
        renderGrid(); renderWeight();
        toast(LANG[data.reason] || LANG.erro, true);
      }));

      offs.push(vhub.listen('nui:notify', (d) => toast(d.msg || '', false)));
    },

    onMount() {
      filterText = ''; filterCat = 'all';          // estado de filtro limpo a cada abertura
      root = document.getElementById('backpack-root');
      root.className = 'mod-backpack';
      root.innerHTML =
        '<div class="bp-shell">' +
          '<aside class="bp-side">' +
            '<div class="bp-pname"></div>' +
            '<div class="bp-pmeta">' +
              '<span>ID: <b class="bp-pid"></b></span>' +
              '<span>Telefone: <b class="bp-pphone"></b></span>' +
            '</div>' +
            '<div class="bp-weight-wrap">' +
              '<div class="bp-weight-label"><span>Peso</span><span class="bp-weight-val"></span></div>' +
              '<div class="bp-weight-track"><div class="bp-weight-bar"></div></div>' +
            '</div>' +
          '</aside>' +
          '<section class="bp-main">' +
            '<div class="bp-head"><div class="bp-title">MOCHILA</div><div class="bp-close">&times;</div></div>' +
            '<div class="bp-tools">' +
              '<input class="bp-search" type="text" placeholder="Buscar item..." />' +
              '<div class="bp-cats"></div>' +
            '</div>' +
            '<div class="bp-grid"></div>' +
          '</section>' +
        '</div>' +
        '<div class="bp-toast"></div>';
      root.classList.remove('hidden');

      gridEl  = root.querySelector('.bp-grid');
      toastEl = root.querySelector('.bp-toast');

      // arraste por MOUSE (compartilhado); guarda cleanup p/ onDestroy
      this._cleanupDrag = vhub.interact.enableDrag(gridEl, {
        getEntry: (pane, slot) => slots()[slot],
        onTransfer: async (src, dst, entry) => {
          if (dst.pane === 'hotbar') {                 // arrastar p/ a hotbar = vincular atalho
            vhub.post('set_bind', { slot: dst.slot, id: entry.id });
            return;
          }
          if (src.slot === dst.slot) return;
          let qty = entry.amount;
          if (qty > 1) { qty = await vhub.interact.qtyModal(entry.amount); if (!qty) return; }
          localMove(src.slot, dst.slot, qty);          // UI instantanea
          renderGrid(); renderWeight();
          vhub.post('move', { from: src.slot, to: dst.slot, qty: qty });
        },
      });

      // duplo-clique usa o item
      this._onDblClick = (e) => {
        const c = e.target.closest('.slot'); if (!c || !c.dataset.filled) return;
        const slot = +c.dataset.slot, entry = slots()[slot];
        if (entry) vhub.post('use', { slot: slot, id: entry.id });
      };

      // right-click: menu de contexto (Usar / Dividir)
      this._onCtx = (e) => {
        const c = e.target.closest('.slot'); if (!c || !c.dataset.filled) return;
        e.preventDefault();
        const slot = +c.dataset.slot, entry = slots()[slot]; if (!entry) return;
        vhub.interact.contextMenu(e.clientX, e.clientY, [
          { label: 'Usar', onClick: () => vhub.post('use', { slot: slot, id: entry.id }) },
          { label: 'Dividir', disabled: entry.amount <= 1, onClick: async () => {
              const qty = await vhub.interact.qtyModal(entry.amount - 1); if (!qty) return;
              const s = slots(); let empty = null;
              for (let i = 1; i <= size(); i++) { if (!s[i]) { empty = i; break; } }
              if (!empty) return;
              localMove(slot, empty, qty); renderGrid(); renderWeight();
              vhub.post('move', { from: slot, to: empty, qty: qty });
            } },
        ]);
      };

      this._onSearch = (e) => { filterText = (e.target.value || '').toLowerCase().trim(); applyFilter(); };
      this._onCats   = (e) => {
        const chip = e.target.closest('.bp-chip'); if (!chip) return;
        filterCat = chip.dataset.cat; renderChips(); applyFilter();
      };
      this._onClose = () => vhub.post('close');
      this._onKey   = (e) => { if (e.key === 'Escape') vhub.post('close'); };

      gridEl.addEventListener('dblclick', this._onDblClick);
      gridEl.addEventListener('contextmenu', this._onCtx);
      root.querySelector('.bp-search').addEventListener('input', this._onSearch);
      root.querySelector('.bp-cats').addEventListener('click', this._onCats);
      root.querySelector('.bp-close').addEventListener('click', this._onClose);
      window.addEventListener('keydown', this._onKey);
    },

    onShow() { if (root) root.classList.remove('hidden'); },

    onDestroy() {
      // cleanup obrigatorio (A-07)
      if (this._cleanupDrag) this._cleanupDrag();
      if (gridEl) {
        gridEl.removeEventListener('dblclick', this._onDblClick);
        gridEl.removeEventListener('contextmenu', this._onCtx);
      }
      window.removeEventListener('keydown', this._onKey);
      clearTimeout(toastT);
      if (root) { root.innerHTML = ''; root.classList.add('hidden'); }
      root = null; gridEl = null; toastEl = null;   // root=null evita render em DOM morto
    },
  });

  // listeners de bus do modulo persistem entre mounts (registrados no onInit);
  // sao liberados so se o modulo for descartado do runtime (nao ocorre aqui).
})();
