// modules/backpack/backpack.js — player hub: topbar identidade + sidebar de navegação + tabs.
// Slice: store('inventory') e store('player'). Verdade vem do servidor; aqui só renderizamos
// e disparamos INTENÇÃO. Servidor confirma por delta ou corrige por rollback.

(function () {

  // ============================================================
  // ESTADO
  // ============================================================

  const inv    = vhub.store('inventory');
  const player = vhub.store('player');

  let root = null, gridEl = null, toastEl = null, toastT = 0;
  let sidebarEl = null, lojaBtnEl = null;
  let filterText = '', filterCat = 'all', activeTab = 'bag';

  const offs          = [];
  const pendingTimers = new Map();

  const LANG = {
    mov_negado: 'Movimento negado',
    weight:     'Peso excedido',
    full:       'Inventário cheio',
    qty:        'Quantidade inválida',
    erro:       'Operação negada',
  };

  function slots() { return inv.get('slots') || inv.set('slots', {}).get('slots'); }
  function size()  { return inv.get('size') || (vhub.config && vhub.config.size) || 30; }
  function maxW()  { return inv.get('max')  || (vhub.config && vhub.config.max)  || 0; }

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

  function setFromItems(items) {
    const s = {};
    (items || []).forEach((it) => { s[it.slot] = { id: it.id, amount: it.amount, meta: it.meta }; });
    inv.set('slots', s);
  }

  function applyItems(items) {
    const s = slots();
    (items || []).forEach((it) => {
      if (it.clear) delete s[it.slot];
      else s[it.slot] = { id: it.id, amount: it.amount, meta: it.meta };
    });
  }


  // ============================================================
  // TABS
  // ============================================================

  function switchTab(tab) {
    activeTab = tab;
    if (!root) return;
    root.querySelectorAll('.bp-nav').forEach((b) => {
      b.classList.toggle('bp-nav--active', b.dataset.tab === tab);
    });
    root.querySelectorAll('.bp-tab').forEach((p) => {
      p.classList.toggle('bp-tab--hidden', p.dataset.pane !== tab);
    });
  }


  // ============================================================
  // RENDER
  // ============================================================

  function renderTopbar() {
    if (!root) return;
    const name = player.get('name') || 'Cidadão';
    const id   = player.get('id');
    const ph   = player.get('phone');
    root.querySelector('.bp-avatar').textContent = name.charAt(0).toUpperCase();
    root.querySelector('.bp-pname').textContent  = name;
    root.querySelector('.bp-pid').textContent    = (id != null) ? id : '--';
    root.querySelector('.bp-pphone').textContent = ph || '--';
  }

  function renderWeight() {
    if (!root) return;
    const valEl = root.querySelector('.bp-weight-val');
    const bar   = root.querySelector('.bp-weight-bar');
    if (!valEl || !bar) return;
    const w = weightOf(slots()), m = maxW();
    const pctRaw = m > 0 ? (w / m) * 100 : 0;
    valEl.textContent    = `${vhub.util.fmtWeight(w)} / ${vhub.util.fmtWeight(m)} kg`;
    bar.style.transform  = 'scaleX(' + Math.min(1, pctRaw / 100) + ')';
    bar.style.background = vhub.util.weightColor(pctRaw);
  }

  function renderGrid() {
    if (!gridEl) return;
    const s = slots(), n = size();
    const frag = document.createDocumentFragment();
    for (let i = 1; i <= n; i++) {
      const cell = vhub.util.el('div', 'slot');
      cell.dataset.slot = i;
      cell.setAttribute('tabindex', '0');
      cell.setAttribute('role', 'gridcell');
      const e = s[i];
      if (e) {
        vhub.util.fillSlot(cell, e);
        cell.setAttribute('aria-label', (vhub.util.itemDef(e.id) || {}).nome || e.id);
      } else {
        cell.setAttribute('aria-label', 'Slot vazio ' + i);
      }
      frag.appendChild(cell);
    }
    gridEl.innerHTML = '';
    gridEl.appendChild(frag);
    renderChips(); applyFilter();
  }

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

  function renderAll() { renderTopbar(); renderWeight(); renderGrid(); }


  // ============================================================
  // PENDING OVERLAY (otimismo visual antes do ACK do servidor)
  // ============================================================

  function setPending(slot) {
    if (!gridEl) return;
    const cell = gridEl.querySelector(`.slot[data-slot="${slot}"]`);
    if (cell) cell.classList.add('slot--pending');
    clearTimeout(pendingTimers.get(slot));
    pendingTimers.set(slot, setTimeout(() => clearPending(slot), 5000));
  }

  function clearPending(slot) {
    clearTimeout(pendingTimers.get(slot));
    pendingTimers.delete(slot);
    if (!gridEl) return;
    const cell = gridEl.querySelector(`.slot[data-slot="${slot}"]`);
    if (cell) cell.classList.remove('slot--pending');
  }


  // ============================================================
  // TOAST
  // ============================================================

  function toast(msg, isErr) {
    if (!toastEl) return;
    toastEl.textContent = msg;
    toastEl.classList.toggle('err', !!isErr);
    toastEl.classList.add('show');
    clearTimeout(toastT);
    toastT = setTimeout(() => toastEl.classList.remove('show'), 2200);
  }


  // ============================================================
  // LIFECYCLE
  // ============================================================

  vhub.createModule('backpack', {

    onInit() {
      // guard: offs já populado = listeners já registrados (não duplicar entre mounts)
      if (offs.length > 0) return;

      offs.push(vhub.listen('nui:open', (d) => {
        const snap = d.snap || {};
        setFromItems(snap.items);
        inv.set('max', snap.max || 0);
        inv.set('size', snap.size || 30);
        vhub.mount('backpack');
        renderAll();
      }));
      offs.push(vhub.listen('nui:close', () => vhub.unmount('backpack')));

      offs.push(vhub.listen('nui:delta', (d) => {
        if (!d.delta || d.delta.scope !== 'backpack') return;
        (d.delta.items || []).forEach((it) => clearPending(it.slot));
        applyItems(d.delta.items);
        renderGrid(); renderWeight();
      }));

      offs.push(vhub.listen('nui:rollback', (d) => {
        const data = d.data || {};
        if (data.scope && data.scope !== 'backpack') return;
        (data.items || []).forEach((it) => clearPending(it.slot));
        applyItems(data.items);
        renderGrid(); renderWeight();
        toast(LANG[data.reason] || LANG.erro, true);
      }));

      offs.push(vhub.listen('nui:notify', (d) => toast(d.msg || '', false)));
    },

    onMount() {
      filterText = ''; filterCat = 'all'; activeTab = 'bag';
      root = document.getElementById('backpack-root');
      root.className = 'mod-backpack';
      root.innerHTML = `
        <div class="bp-shell">

          <div class="bp-topbar">
            <div class="bp-avatar"></div>
            <div class="bp-idbk">
              <span class="bp-pname"></span>
              <span class="bp-pmeta">#<b class="bp-pid"></b> &middot; <b class="bp-pphone"></b></span>
            </div>
            <div class="bp-close" tabindex="0" role="button" aria-label="Fechar mochila">&#x2715;</div>
          </div>

          <div class="bp-layout">

            <nav class="bp-sidebar" role="navigation" aria-label="Seções">
              <button class="bp-nav bp-nav--active" data-tab="bag" type="button">
                <svg viewBox="0 0 24 24"><rect x="4" y="9" width="16" height="12" rx="2"/><path d="M9 9V7a3 3 0 0 1 6 0v2"/><line x1="9" y1="13" x2="15" y2="13"/></svg>
                <span>MOCHILA</span>
              </button>
              <button class="bp-nav" data-tab="loja" type="button">
                <svg viewBox="0 0 24 24"><path d="M3 3h2l.4 2M7 13h10l4-8H5.4M7 13 5.4 5M7 13l-2 5M17 13l1.5 5M9 21a1 1 0 1 0 2 0 1 1 0 0 0-2 0M18 21a1 1 0 1 0 2 0 1 1 0 0 0-2 0"/></svg>
                <span>LOJA</span>
              </button>
              <button class="bp-nav" data-tab="skin" type="button">
                <svg viewBox="0 0 24 24"><circle cx="12" cy="8" r="4"/><path d="M4 20c0-4 3.6-7 8-7s8 3 8 7"/></svg>
                <span>SKIN</span>
              </button>
            </nav>

            <div class="bp-content">

              <div class="bp-tab" data-pane="bag">
                <div class="bp-tools">
                  <input class="bp-search" type="text" placeholder="Buscar item..." />
                  <div class="bp-cats" role="group" aria-label="Categorias"></div>
                </div>
                <div class="bp-body">
                  <div class="bp-grid" role="grid" aria-label="Grade de itens da mochila"></div>
                  <div class="bp-insp"></div>
                </div>
                <div class="bp-footer">
                  <div class="bp-weight-wrap">
                    <div class="bp-weight-label">
                      <span>Peso</span>
                      <span class="bp-weight-val"></span>
                    </div>
                    <div class="bp-weight-track"><div class="bp-weight-bar"></div></div>
                  </div>
                </div>
              </div>

              <div class="bp-tab bp-tab--hidden" data-pane="loja">
                <div class="bp-promo-card">
                  <div class="bp-promo-icon">
                    <svg viewBox="0 0 24 24"><path d="M6 2L3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4z"/><line x1="3" y1="6" x2="21" y2="6"/><path d="M16 10a4 4 0 0 1-8 0"/></svg>
                  </div>
                  <div class="bp-promo-title">Loja de Moedas</div>
                  <div class="bp-promo-sub">Adquira moedas e desbloqueie itens exclusivos do servidor</div>
                  <button class="bp-promo-btn" type="button">Abrir no iPad</button>
                </div>
              </div>

              <div class="bp-tab bp-tab--hidden" data-pane="skin">
                <div class="bp-soon-card">
                  <div class="bp-soon-icon">
                    <svg viewBox="0 0 24 24"><circle cx="12" cy="8" r="4"/><path d="M4 20c0-4 3.6-7 8-7s8 3 8 7"/><line x1="12" y1="14" x2="12" y2="22"/><path d="M9 17l3-3 3 3"/></svg>
                  </div>
                  <div class="bp-soon-title">Customização</div>
                  <div class="bp-soon-sub">Skins de armas e personagens — em breve</div>
                </div>
              </div>

            </div>
          </div>
        </div>
        <div class="bp-toast" role="status" aria-live="polite"></div>
      `;
      root.classList.remove('hidden');

      gridEl    = root.querySelector('.bp-grid');
      toastEl   = root.querySelector('.bp-toast');
      sidebarEl = root.querySelector('.bp-sidebar');
      lojaBtnEl = root.querySelector('.bp-promo-btn');

      this._inspectOff = vhub.inspect.init(root.querySelector('.bp-insp'));

      // atualiza topbar quando dados de identidade chegam enquanto a mochila está aberta
      this._hudOff = vhub.listen('nui:hud', () => renderTopbar());

      this._onClick = (e) => {
        const c = e.target.closest('.slot');
        if (!c || !c.dataset.filled) { vhub.inspect.hide(); return; }
        const entry = slots()[+c.dataset.slot];
        if (entry) vhub.inspect.show(entry);
      };

      this._cleanupDrag = vhub.interact.enableDrag(gridEl, {
        getEntry: (pane, slot) => slots()[slot],
        onTransfer: async (src, dst, entry) => {
          if (dst.pane === 'hotbar') {
            vhub.post('set_bind', { slot: dst.slot, id: entry.id });
            return;
          }
          if (src.slot === dst.slot) return;
          let qty = entry.amount;
          if (qty > 1) { qty = await vhub.interact.qtyModal(entry.amount); if (!qty) return; }
          setPending(src.slot); setPending(dst.slot);
          vhub.post('move', { from: src.slot, to: dst.slot, qty: qty });
        },
      });

      this._onDblClick = (e) => {
        const c = e.target.closest('.slot'); if (!c || !c.dataset.filled) return;
        const slot = +c.dataset.slot, entry = slots()[slot];
        if (entry) { setPending(slot); vhub.post('use', { slot: slot, id: entry.id }); }
      };

      this._onCtx = (e) => {
        const c = e.target.closest('.slot'); if (!c || !c.dataset.filled) return;
        e.preventDefault();
        const slot = +c.dataset.slot, entry = slots()[slot]; if (!entry) return;
        vhub.interact.contextMenu(e.clientX, e.clientY, [
          { label: 'Usar', onClick: () => { setPending(slot); vhub.post('use', { slot: slot, id: entry.id }); } },
          { label: 'Dividir', disabled: entry.amount <= 1, onClick: async () => {
              const qty = await vhub.interact.qtyModal(entry.amount - 1); if (!qty) return;
              const s = slots(); let empty = null;
              for (let i = 1; i <= size(); i++) { if (!s[i]) { empty = i; break; } }
              if (!empty) return;
              setPending(slot); setPending(empty);
              vhub.post('move', { from: slot, to: empty, qty: qty });
            } },
        ]);
      };

      this._onSearch   = (e) => { filterText = (e.target.value || '').toLowerCase().trim(); applyFilter(); };
      this._onCats     = (e) => {
        const chip = e.target.closest('.bp-chip'); if (!chip) return;
        filterCat = chip.dataset.cat; renderChips(); applyFilter();
      };
      this._onClose    = () => vhub.post('close');
      this._onNavClick = (e) => {
        const btn = e.target.closest('.bp-nav');
        if (btn && btn.dataset.tab) switchTab(btn.dataset.tab);
      };
      this._onLojaBtn  = () => vhub.post('open_loja');
      this._onKey      = (e) => {
        if (e.key === 'Escape') { vhub.post('close'); return; }
        if (activeTab !== 'bag' || !gridEl) return;
        const focused = document.activeElement;
        if (!focused || !gridEl.contains(focused)) return;
        const all = Array.from(gridEl.querySelectorAll('.slot'));
        const idx = all.indexOf(focused);
        if (idx === -1) return;
        const cols = 6;
        let next = -1;
        if (e.key === 'ArrowRight') next = idx + 1;
        else if (e.key === 'ArrowLeft') next = idx - 1;
        else if (e.key === 'ArrowDown') next = idx + cols;
        else if (e.key === 'ArrowUp') next = idx - cols;
        else if (e.key === 'Enter' && focused.dataset.filled) {
          const entry = slots()[+focused.dataset.slot];
          if (entry) vhub.inspect.show(entry);
          return;
        }
        if (next >= 0 && next < all.length) { e.preventDefault(); all[next].focus(); }
      };

      gridEl.addEventListener('click', this._onClick);
      gridEl.addEventListener('dblclick', this._onDblClick);
      gridEl.addEventListener('contextmenu', this._onCtx);
      root.querySelector('.bp-search').addEventListener('input', this._onSearch);
      root.querySelector('.bp-cats').addEventListener('click', this._onCats);
      root.querySelector('.bp-close').addEventListener('click', this._onClose);
      sidebarEl.addEventListener('click', this._onNavClick);
      lojaBtnEl.addEventListener('click', this._onLojaBtn);
      window.addEventListener('keydown', this._onKey);

      renderTopbar();
    },

    onShow() { if (root) root.classList.remove('hidden'); },

    onHide() { if (vhub.inspect) vhub.inspect.hide(); },

    onDestroy() {
      if (this._cleanupDrag) this._cleanupDrag();
      if (gridEl) {
        gridEl.removeEventListener('click', this._onClick);
        gridEl.removeEventListener('dblclick', this._onDblClick);
        gridEl.removeEventListener('contextmenu', this._onCtx);
      }
      if (sidebarEl) { sidebarEl.removeEventListener('click', this._onNavClick); sidebarEl = null; }
      if (lojaBtnEl) { lojaBtnEl.removeEventListener('click', this._onLojaBtn); lojaBtnEl = null; }
      if (this._hudOff) { this._hudOff(); this._hudOff = null; }
      window.removeEventListener('keydown', this._onKey);
      clearTimeout(toastT);
      pendingTimers.forEach((t) => clearTimeout(t));
      pendingTimers.clear();
      if (this._inspectOff) { this._inspectOff(); this._inspectOff = null; }
      if (root) { root.innerHTML = ''; root.classList.add('hidden'); }
      root = null; gridEl = null; toastEl = null;
    },
  });

  // offs são permanentes neste módulo (lazy): governam o próprio ciclo de mount/unmount.
  // São liberados apenas se o runtime descartar o módulo (não ocorre em prod).
})();
