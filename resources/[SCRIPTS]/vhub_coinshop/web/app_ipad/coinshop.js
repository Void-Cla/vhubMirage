// coinshop.js — app CoinShop do iPad v2.4.1
// Anti-XSS: ZERO innerHTML com dado do servidor. Todo texto via textContent/createTextNode.
// A-09: sem backdrop-filter. A-10: sem CDN externo, sem fetch externo.
// Estrutura: canal relay → recebe `data` → renderiza → usuário clica → relay envia ação.
// Padrão iPad: IIFE isolado + vhub.createModule('coinshop', spec) — nunca window.CoinShopApp.

(() => {
'use strict';


// ============================================================
// CANAL DE COMUNICAÇÃO COM O BROKER DO IPAD
// ============================================================
// `ch` fornecido pelo runtime do iPad — escopo isolado desta IIFE.
const ch = vhub.app.channel('coinshop');


// ============================================================
// ESTADO LOCAL
// ============================================================

let _data     = null;   // snapshot recebido do server (data)
let _busy     = false;  // trava de ação em voo
let _view     = null;   // aba ativa ('grid', 'deals', 'redeem', 'pix', 'adm-dash', …)
let _search   = '';     // filtro de busca atual
let _category = 'all';  // categoria local; catálogo continua autoritativo no servidor
let _sort     = 'featured';
let _modal    = null;   // item aberto no modal jogador
let _admModal = null;   // contexto do modal admin (tipo + callback de ok)
let _root     = null;

const _channelOffs = [];
const _pickerOffs  = new Set();

// caches lazy de pickers admin (key → { ts, rows })
const _pickerCache = {};
const PICKER_TTL   = 60_000;  // 60 s

// SVG icons por tab id (inline, A-10 — sem arquivo externo)
const ICONS = {
    grid: `<svg viewBox="0 0 20 20" class="cs-nav-ico" aria-hidden="true">
        <rect x="2" y="2" width="6" height="6" rx="1.2" fill="currentColor"/>
        <rect x="12" y="2" width="6" height="6" rx="1.2" fill="currentColor"/>
        <rect x="2" y="12" width="6" height="6" rx="1.2" fill="currentColor"/>
        <rect x="12" y="12" width="6" height="6" rx="1.2" fill="currentColor"/>
    </svg>`,
    deals: `<svg viewBox="0 0 20 20" class="cs-nav-ico" aria-hidden="true">
        <path d="M3 10.5L10 3l7 7.5-7 6.5-7-6.5z" fill="none" stroke="currentColor"
              stroke-width="1.6" stroke-linejoin="round"/>
        <circle cx="10" cy="10.2" r="2.2" fill="currentColor"/>
    </svg>`,
    redeem: `<svg viewBox="0 0 20 20" class="cs-nav-ico" aria-hidden="true">
        <rect x="2" y="5" width="16" height="10" rx="2" fill="none"
              stroke="currentColor" stroke-width="1.6"/>
        <path d="M6 10h8M12 7.5l2.5 2.5-2.5 2.5" stroke="currentColor"
              stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
    </svg>`,
    pix: `<svg viewBox="0 0 20 20" class="cs-nav-ico" aria-hidden="true">
        <circle cx="10" cy="10" r="8" fill="none" stroke="currentColor" stroke-width="1.6"/>
        <path d="M7 10h6M10 7v6" stroke="currentColor" stroke-width="1.8"
              stroke-linecap="round"/>
    </svg>`,
    vehicle: `<svg viewBox="0 0 20 20" class="cs-nav-ico" aria-hidden="true">
        <path d="M3 12.5 5.3 8h9.4l2.3 4.5v3H3v-3Z" fill="none" stroke="currentColor"
              stroke-width="1.5" stroke-linejoin="round"/>
        <circle cx="6" cy="15.5" r="1.4" fill="currentColor"/><circle cx="14" cy="15.5" r="1.4" fill="currentColor"/>
    </svg>`,
    item: `<svg viewBox="0 0 20 20" class="cs-nav-ico" aria-hidden="true">
        <path d="m3 6 7-3 7 3v8l-7 3-7-3V6Z" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"/>
        <path d="m3 6 7 3 7-3M10 9v8" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"/>
    </svg>`,
    weapon: `<svg viewBox="0 0 20 20" class="cs-nav-ico" aria-hidden="true">
        <circle cx="10" cy="10" r="6.5" fill="none" stroke="currentColor" stroke-width="1.5"/>
        <circle cx="10" cy="10" r="2" fill="currentColor"/><path d="M10 1.5v3M10 15.5v3M1.5 10h3M15.5 10h3" stroke="currentColor" stroke-width="1.5"/>
    </svg>`,
    tool: `<svg viewBox="0 0 20 20" class="cs-nav-ico" aria-hidden="true">
        <path d="m12.8 4.1 3.1 3.1-7.8 7.8a2.2 2.2 0 0 1-3.1-3.1l7.8-7.8Z" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"/>
        <path d="m12.6 3.2 1.1-1.1 3.2 3.2-1.1 1.1" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
    </svg>`,
    'adm-dash': `<svg viewBox="0 0 20 20" class="cs-nav-ico" aria-hidden="true">
        <rect x="2" y="10" width="4" height="8" rx="1" fill="currentColor"/>
        <rect x="8" y="6" width="4" height="12" rx="1" fill="currentColor"/>
        <rect x="14" y="2" width="4" height="16" rx="1" fill="currentColor"/>
    </svg>`,
    'adm-catalog': `<svg viewBox="0 0 20 20" class="cs-nav-ico" aria-hidden="true">
        <rect x="3" y="3" width="14" height="14" rx="2" fill="none"
              stroke="currentColor" stroke-width="1.6"/>
        <path d="M6 7h8M6 10h8M6 13h5" stroke="currentColor"
              stroke-width="1.4" stroke-linecap="round"/>
    </svg>`,
    'adm-cats': `<svg viewBox="0 0 20 20" class="cs-nav-ico" aria-hidden="true">
        <path d="M3 5h14M3 10h9M3 15h11" stroke="currentColor"
              stroke-width="1.6" stroke-linecap="round"/>
    </svg>`,
    'adm-deals': `<svg viewBox="0 0 20 20" class="cs-nav-ico" aria-hidden="true">
        <path d="M3 3l14 14M17 3l-5 9-9 5" stroke="currentColor"
              stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>
    </svg>`,
    'adm-players': `<svg viewBox="0 0 20 20" class="cs-nav-ico" aria-hidden="true">
        <circle cx="8" cy="7" r="3" fill="none" stroke="currentColor" stroke-width="1.6"/>
        <path d="M2 17c0-3.3 2.7-6 6-6s6 2.7 6 6" fill="none"
              stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/>
        <path d="M15 8v6M12 11h6" stroke="currentColor"
              stroke-width="1.5" stroke-linecap="round"/>
    </svg>`,
    'adm-codes': `<svg viewBox="0 0 20 20" class="cs-nav-ico" aria-hidden="true">
        <rect x="3" y="5" width="14" height="10" rx="2" fill="none"
              stroke="currentColor" stroke-width="1.6"/>
        <path d="M6.5 10l2 2 4-4" stroke="currentColor"
              stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
    </svg>`,
    'adm-theme': `<svg viewBox="0 0 20 20" class="cs-nav-ico" aria-hidden="true">
        <circle cx="10" cy="10" r="3" fill="currentColor"/>
        <path d="M10 2v2M10 16v2M2 10h2M16 10h2
                 M4.2 4.2l1.4 1.4M14.4 14.4l1.4 1.4
                 M14.4 5.6l-1.4 1.4M5.6 14.4l-1.4 1.4"
              stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
    </svg>`,
    'adm-import': `<svg viewBox="0 0 20 20" class="cs-nav-ico" aria-hidden="true">
        <path d="M10 3v10M6 9l4 4 4-4" stroke="currentColor"
              stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>
        <path d="M3 15h14" stroke="currentColor"
              stroke-width="1.6" stroke-linecap="round"/>
    </svg>`,
};

// mapeamento tab → painel HTML (data-el)
const VIEW_EL = {
    grid:          'grid',
    deals:         'deals',
    redeem:        'redeem',
    pix:           'pix',
    'adm-dash':    'admDash',
    'adm-catalog': 'admCatalog',
    'adm-cats':    'admCats',
    'adm-deals':   'admDeals',
    'adm-players': 'admPlayers',
    'adm-codes':   'admCodes',
    'adm-theme':   'admTheme',
    'adm-import':  'admImport',
};

const VIEW_TITLE = {
    grid:          'Destaques',
    deals:         'Ofertas',
    redeem:        'Resgatar Código',
    pix:           'Comprar Coins',
    'adm-dash':    'Dashboard',
    'adm-catalog': 'Catálogo',
    'adm-cats':    'Categorias',
    'adm-deals':   'Ofertas Admin',
    'adm-players': 'Jogadores',
    'adm-codes':   'Cupons MG7',
    'adm-theme':   'Aparência',
    'adm-import':  'Importar',
};

const CATEGORY_META = {
    vehicle: { icon: 'vehicle', description: 'Garagens e carros' },
    item:    { icon: 'item',    description: 'Itens e consumíveis' },
    weapon:  { icon: 'weapon',  description: 'Armas e munição' },
    tool:    { icon: 'tool',    description: 'Ferramentas úteis' },
};


// ============================================================
// UTIL — CONSTRUTORES DE DOM (zero innerHTML com dado externo)
// ============================================================

function el(tag, attrs, ...children) {
    const node = document.createElement(tag);
    if (attrs) {
        for (const [k, v] of Object.entries(attrs)) {
            if (k === 'class')         node.className = v;
            else if (k === 'dataset')  Object.assign(node.dataset, v);
            else if (k === 'style')    Object.assign(node.style, v);
            else                       node.setAttribute(k, v);
        }
    }
    for (const child of children) {
        if (child == null) continue;
        node.appendChild(typeof child === 'string'
            ? document.createTextNode(child)
            : child);
    }
    return node;
}

function iconIdFor(category) {
    const type = String(category || '').toLowerCase();
    return CATEGORY_META[type]?.icon || 'grid';
}

function iconNode(iconId, className) {
    const wrap = document.createElement('span');
    wrap.innerHTML = ICONS[iconId] || ICONS.grid;
    const icon = wrap.firstElementChild;
    if (icon && className) icon.classList.add(className);
    return icon || document.createElement('span');
}

function setIcon(target, iconId) {
    if (!target) return;
    target.replaceChildren(iconNode(iconId));
}

function categoryMeta(category) {
    return CATEGORY_META[String(category?.type || category || '').toLowerCase()] || {
        icon: 'grid', description: 'Seleção especial',
    };
}

function fmtCoins(n) { return Number(n || 0).toLocaleString('pt-BR'); }

function spinner() { return el('div', { class: 'cs-spinner' }); }

function emptyMsg(msg) {
    const p = el('p', { class: 'cs-empty' });
    p.textContent = msg || 'Nenhum item encontrado.';
    return p;
}


// ============================================================
// REFS
// ============================================================

let refs = {};

function cacheRefs() {
    const q = (sel) => document.querySelector(`.mod-coinshop [data-el="${sel}"]`);
    refs = {
        player:          q('player'),
        coins:           q('coins'),
        nav:             q('nav'),
        topnav:          q('topnav'),
        viewContext:     q('viewContext'),
        viewTitle:       q('viewTitle'),
        search:          q('search'),
        status:          q('status'),
        grid:            q('grid'),
        homePix:         q('homePix'),
        deals:           q('deals'),
        redeem:          q('redeem'),
        redeemKey:       q('redeemKey'),
        giftToggle:      q('giftToggle'),
        giftId:          q('giftId'),
        pix:             q('pix'),
        pixPacks:        q('pixPacks'),
        pixCheckout:     q('pixCheckout'),
        pixSummary:      q('pixSummary'),
        pixSumCoins:     q('pixSumCoins'),
        pixSumPrice:     q('pixSumPrice'),
        pixQrImg:        q('pixQrImg'),
        pixQrFallback:   q('pixQrFallback'),
        pixQrTxt:        q('pixQrTxt'),
        pixDone:         q('pixDone'),
        pixDoneTxt:      q('pixDoneTxt'),
        pixStatus:       q('pixStatus'),
        pixDot:          q('pixDot'),
        pixStatusTxt:    q('pixStatusTxt'),
        pixExpire:       q('pixExpire'),
        pixMsg:          q('pixMsg'),
        pixCopyRow:      q('pixCopyRow'),
        pixCopy:         q('pixCopy'),
        admCouponNew:    q('admCouponNew'),
        admCouponKey:    q('admCouponKey'),
        admCouponSub:    q('admCouponSub'),
        admDash:         q('admDash'),
        admCatalog:      q('admCatalog'),
        admCats:         q('admCats'),
        admDeals:        q('admDeals'),
        admPlayers:      q('admPlayers'),
        admCodes:        q('admCodes'),
        admTheme:        q('admTheme'),
        admThemeForm:    q('admThemeForm'),
        admImport:       q('admImport'),
        admImportJson:   q('admImportJson'),
        admItemList:     q('admItemList'),
        admCatList:      q('admCatList'),
        admDealList:     q('admDealList'),
        admPlayerList:   q('admPlayerList'),
        admCodeList:     q('admCodeList'),
        admImportResult: q('admImportResult'),
        admRecentTx:     q('admRecentTx'),
        statItems:       q('statItems'),
        statSales:       q('statSales'),
        statCoins24h:    q('statCoins24h'),
        statOnline:      q('statOnline'),
        overlay:         q('overlay'),
        mIcon:           q('mIcon'),
        mName:           q('mName'),
        mDesc:           q('mDesc'),
        mPrice:          q('mPrice'),
        mBuy:            q('mBuy'),
        admOverlay:      q('admOverlay'),
        admModalTitle:   q('admModalTitle'),
        admModalBody:    q('admModalBody'),
        admModalOk:      q('admModalOk'),
    };
}


// ============================================================
// BUSY
// ============================================================

function setBusy(on) {
    _busy = on;
    if (refs.mBuy)       refs.mBuy.disabled       = on;
    if (refs.admModalOk) refs.admModalOk.disabled  = on;
}


// ============================================================
// NAV — sidebar com ícones SVG
// ============================================================

// rail minimalista: só ícones circulares com tooltip; categorias viraram chips na topbar
function buildNav() {
    if (!refs.nav || !_data) return;
    refs.nav.replaceChildren();

    const isAdm = !!_data.isAdmin;

    refs.nav.appendChild(navBtn('grid',   'Início — catálogo e coins'));
    refs.nav.appendChild(navBtn('deals',  'Ofertas especiais'));
    refs.nav.appendChild(navBtn('redeem', 'Resgatar cupom'));
    if (_data.pix?.enabled === true) {
        refs.nav.appendChild(navBtn('pix', 'Comprar coins (Pix)'));
    }

    if (isAdm) {
        refs.nav.appendChild(el('div', { class: 'cs-nav-sep' }));
        refs.nav.appendChild(navBtn('adm-dash',    'Admin — Dashboard'));
        refs.nav.appendChild(navBtn('adm-catalog', 'Admin — Catálogo'));
        refs.nav.appendChild(navBtn('adm-cats',    'Admin — Categorias'));
        refs.nav.appendChild(navBtn('adm-deals',   'Admin — Ofertas'));
        refs.nav.appendChild(navBtn('adm-players', 'Admin — Jogadores'));
        refs.nav.appendChild(navBtn('adm-codes',   'Admin — Cupons MG7'));
        refs.nav.appendChild(navBtn('adm-theme',   'Admin — Aparência'));
        refs.nav.appendChild(navBtn('adm-import',  'Admin — Importar'));
    }
}

function navBtn(id, tooltip) {
    const btn = el('button', {
        type: 'button', class: 'cs-nav-btn', title: tooltip,
        dataset: { action: 'view', view: id },
    });
    btn.appendChild(iconNode(id));
    return btn;
}

function updateNavActive() {
    document.querySelectorAll('.mod-coinshop .cs-nav-btn').forEach(btn => {
        const viewActive = btn.dataset.view === _view;
        const catActive = btn.dataset.categoryId && btn.dataset.categoryId === _category;
        btn.classList.toggle('active', viewActive || catActive);
    });
    if (refs.viewTitle && VIEW_TITLE[_view]) {
        refs.viewTitle.textContent = VIEW_TITLE[_view];
    }
    if (refs.viewContext) {
        const category = selectedCategory();
        refs.viewContext.textContent = _view === 'grid' && category
            ? (category.name || 'Categoria')
            : (_view === 'grid' ? 'Catálogo' : 'CoinShop');
    }
    buildTopNav();
}

function selectedCategory() {
    if (!_data || _category === 'all') return null;
    return (_data.categories || []).find(category => String(category.id || '') === _category) || null;
}

function buildTopNav() {
    if (!refs.topnav) return;
    refs.topnav.replaceChildren();
    refs.topnav.hidden = _view !== 'grid';
    if (_view !== 'grid') return;

    // categorias (saíram do rail — aqui como chips)
    const categories = Array.isArray(_data?.categories) ? _data.categories : [];
    if (categories.length) {
        const all = el('button', {
            type: 'button', class: 'cs-top-chip',
            dataset: { action: 'category', categoryId: '' },
        });
        all.textContent = 'Tudo';
        all.classList.toggle('active', _category === 'all');
        refs.topnav.appendChild(all);

        categories.forEach(category => {
            const chip = el('button', {
                type: 'button', class: 'cs-top-chip',
                dataset: { action: 'category', categoryId: String(category.id || '') },
            });
            chip.textContent = category.name || category.id || '?';
            chip.classList.toggle('active', String(category.id || '') === _category);
            refs.topnav.appendChild(chip);
        });

        refs.topnav.appendChild(el('span', { class: 'cs-chip-sep' }));
    }

    const filters = [
        ['featured', 'Destaques'],
        ['price', 'Menor preço'],
        ['available', 'No saldo'],
    ];
    filters.forEach(([id, label]) => {
        const btn = el('button', {
            type: 'button', class: 'cs-top-chip',
            dataset: { action: 'sort', sort: id },
        });
        btn.textContent = label;
        btn.classList.toggle('active', _sort === id);
        refs.topnav.appendChild(btn);
    });
}


// ============================================================
// NAVEGAÇÃO
// ============================================================

function navigate(view) {
    if (!VIEW_EL[view]) return;
    _view = view;
    updateNavActive();

    Object.values(VIEW_EL).forEach(elKey => {
        const panel = refs[elKey];
        if (panel) panel.hidden = true;
    });

    const panel = refs[VIEW_EL[view]];
    if (panel) panel.hidden = false;

    // faixa "Comprar Coins" mora na página principal, junto do catálogo
    if (refs.homePix) {
        const showHome = view === 'grid' && _data?.pix?.enabled === true;
        refs.homePix.hidden = !showHome;
        if (showHome) renderHomePix();
    }

    const hasSearch = view === 'grid' || view === 'adm-catalog';
    if (refs.search?.parentElement) refs.search.parentElement.hidden = !hasSearch;

    if (view === 'grid')          renderGrid();
    if (view === 'deals')         renderDeals();
    if (view === 'pix')           renderPixPacks();
    if (view === 'adm-dash')      loadAdmDash();
    if (view === 'adm-catalog')   renderAdmCatalog();
    if (view === 'adm-cats')      renderAdmCats();
    if (view === 'adm-deals')     renderAdmDeals();
    if (view === 'adm-players')   loadAdmPlayers();
    if (view === 'adm-codes')     loadAdmCodes();
    if (view === 'adm-theme')     fillThemeForm();
}


// ============================================================
// GRADE DE ITENS
// ============================================================

function renderGrid() {
    if (!refs.grid || !_data) return;
    refs.grid.replaceChildren();

    const q = _search.toLowerCase();
    const category = selectedCategory();
    let items = (_data.items || []).filter(item => {
        const matchesCategory = !category || (category.type
            ? item.category === category.type
            : item.customCategory === category.id);
        if (!matchesCategory) return false;
        if (!q) return true;
        return (item.name || '').toLowerCase().includes(q)
            || (item.description || '').toLowerCase().includes(q)
            || (item.category || '').toLowerCase().includes(q);
    });

    if (_sort === 'available') {
        items = items.filter(item => Number(item.price || 0) <= Number(_data.coins || 0));
    }
    items = items.slice().sort((a, b) => {
        if (_sort === 'price') return Number(a.price || 0) - Number(b.price || 0);
        if (_sort === 'featured') return Number(b.trending === true) - Number(a.trending === true)
            || String(a.name || a.id).localeCompare(String(b.name || b.id), 'pt-BR');
        return String(a.name || a.id).localeCompare(String(b.name || b.id), 'pt-BR');
    });

    if (!items.length) { refs.grid.appendChild(emptyMsg('Nenhum item encontrado.')); return; }
    items.forEach(item => refs.grid.appendChild(cardItem(item)));
}

function cardItem(item) {
    const wrap = el('button', {
        type: 'button', class: 'cs-card', dataset: { action: 'open-item', itemId: item.id },
    });
    const head = el('div', { class: 'cs-card-head' });
    head.appendChild(iconNode(iconIdFor(item.category), 'cs-card-icon'));

    const body = el('div', { class: 'cs-card-copy' });
    const name = el('div', { class: 'cs-card-name' });
    name.textContent = item.name || item.id;
    const desc = el('p', { class: 'cs-card-desc' });
    desc.textContent = item.description || categoryMeta(item.category).description;
    body.append(name, desc);
    head.appendChild(body);

    const foot = el('div', { class: 'cs-card-foot' });
    const cat = el('span', { class: 'cs-card-cat' });
    cat.textContent = item.category || 'item';
    const price = el('strong', { class: 'cs-card-price' });
    price.textContent = fmtCoins(item.price);
    foot.append(cat, price);
    wrap.append(head, foot);
    return wrap;
}


// ============================================================
// MODAL DE COMPRA (jogador)
// ============================================================

function openItemModal(item) {
    _modal = item;
    setIcon(refs.mIcon, iconIdFor(item.category));

    refs.mName.textContent  = item.name || item.id;
    refs.mDesc.textContent  = item.description || '';
    refs.mPrice.textContent = fmtCoins(item.price) + ' moedas';
    refs.mBuy.disabled = false;
    refs.overlay.hidden = false;
}

function closeModal() {
    refs.overlay.hidden = true;
    _modal = null;
    setBusy(false);
}

function openDealModal(deal) {
    _modal = { ...deal, _isDeal: true };
    setIcon(refs.mIcon, 'deals');
    refs.mName.textContent  = deal.name || deal.id;
    refs.mDesc.textContent  = deal.description || '';
    refs.mPrice.textContent = fmtCoins(deal.price) + ' moedas';
    refs.mBuy.disabled = false;
    refs.overlay.hidden = false;
}


// ============================================================
// DEALS
// ============================================================

function renderDeals() {
    if (!refs.deals || !_data) return;
    refs.deals.innerHTML = '';
    const deals = _data.deals || [];
    if (!deals.length) { refs.deals.appendChild(emptyMsg('Nenhuma oferta disponível.')); return; }
    deals.forEach(deal => refs.deals.appendChild(cardDeal(deal)));
}

function cardDeal(deal) {
    const wrap = el('button', {
        type: 'button', class: 'cs-deal', dataset: { action: 'open-deal', dealId: deal.id },
    });
    const icon = iconNode('deals', 'cs-deal-icon');
    const body = el('div', { class: 'cs-deal-info' });
    const name = el('h3');
    name.textContent = deal.name || deal.id;
    const desc = el('p');
    desc.textContent = deal.description || '';
    const side = el('div', { class: 'cs-deal-side' });
    const priceRow = el('strong');
    priceRow.textContent = fmtCoins(deal.price) + ' moedas';
    if (deal.originalPrice && deal.originalPrice > deal.price) {
        const orig = el('span', { class: 'cs-deal-original' });
        orig.textContent = fmtCoins(deal.originalPrice);
        priceRow.appendChild(orig);
    }

    body.appendChild(name);
    body.appendChild(desc);
    side.appendChild(priceRow);
    wrap.append(icon, body, side);
    return wrap;
}


// ============================================================
// PIX
// ============================================================

let _selectedPack = null;
let _pixTimer     = null;   // countdown 1 Hz — sempre limpo (A-07)
let _pixExpiresAt = 0;      // unix seconds

// para o countdown do checkout (A-07 — nunca deixar interval órfão)
function stopPixTimer() {
    if (_pixTimer) { clearInterval(_pixTimer); _pixTimer = null; }
}

// faixa compacta de pacotes na página principal (clique → checkout na aba Pix)
function renderHomePix() {
    if (!refs.homePix || !_data) return;
    refs.homePix.replaceChildren();

    const packs = Array.isArray(_data.pix?.packages) ? _data.pix.packages : [];
    if (!packs.length) { refs.homePix.hidden = true; return; }

    const lbl = el('span', { class: 'cs-home-pix-lbl' });
    lbl.textContent = 'Comprar coins';
    refs.homePix.appendChild(lbl);

    packs.forEach(pack => {
        const pill = el('button', {
            type: 'button',
            class: 'cs-home-pack' + (pack.popular ? ' popular' : ''),
            title: (pack.name || pack.id) + ' — pagamento via Pix',
            dataset: { action: 'home-pix', packageId: pack.id },
        });
        const coins = el('strong');
        coins.textContent = fmtCoins(pack.coins);
        const unit = el('span', { class: 'cs-home-pack-unit' });
        unit.textContent = Number(pack.coins) === 1 ? 'coin' : 'coins';
        const price = el('span', { class: 'cs-home-pack-price' });
        price.textContent = 'R$ ' + Number(pack.priceBRL || 0).toFixed(2).replace('.', ',');
        pill.append(coins, unit, price);
        refs.homePix.appendChild(pill);
    });
}

// estado visual da linha de status (dot pulsante / ok / erro)
function setPixStatus(text, kind) {
    if (!refs.pixStatus) return;
    refs.pixStatus.hidden = false;
    refs.pixStatusTxt.textContent = text;
    refs.pixDot.classList.remove('ok', 'err');
    if (kind) refs.pixDot.classList.add(kind);
}

function renderPixPacks() {
    if (!refs.pixPacks || !_data) return;
    refs.pixPacks.innerHTML = '';
    refs.pixCheckout.hidden = true;
    _selectedPack = null;
    stopPixTimer();

    const packs = Array.isArray(_data.pix?.packages) ? _data.pix.packages : [];
    if (!packs.length) { refs.pixPacks.appendChild(emptyMsg('Nenhum pacote configurado.')); return; }

    packs.forEach(pack => {
        const card = el('button', {
            type: 'button', class: 'cs-pack tier' + Number(pack.tier || 1)
                + (pack.popular ? ' popular' : ''),
            dataset: { action: 'pix-create', packageId: pack.id },
        });
        const badges = el('div', { class: 'cs-pack-badges' });
        const tier = el('span', { class: 'cs-pack-tier t' + Number(pack.tier || 1) });
        tier.textContent = 'R$1 = 1';
        badges.appendChild(tier);
        if (pack.popular) {
            const badge = el('span', { class: 'cs-pack-popular' });
            badge.textContent = 'Popular';
            badges.appendChild(badge);
        }

        const name = el('div', { class: 'cs-pack-name' });
        name.textContent = pack.name || pack.id;

        const coins = el('div', { class: 'cs-pack-coins' });
        coins.textContent = fmtCoins(pack.coins) + (Number(pack.coins) === 1 ? ' moeda' : ' moedas');

        const price = el('div', { class: 'cs-pack-price' });
        price.textContent = 'R$ ' + Number(pack.priceBRL || 0).toFixed(2).replace('.', ',');
        card.append(badges, name, coins, price);
        refs.pixPacks.appendChild(card);
    });
}

function createPix(packageId) {
    const packs = Array.isArray(_data?.pix?.packages) ? _data.pix.packages : [];
    const pack = packs.find(entry => entry.id === packageId);
    if (!pack || _busy) return;

    document.querySelectorAll('.mod-coinshop .cs-pack').forEach(card => {
        card.classList.toggle('selected', card.dataset.packageId === packageId);
    });
    _selectedPack = pack;
    stopPixTimer();

    refs.pixCheckout.hidden = false;
    refs.pixQrFallback.hidden = false;
    refs.pixQrImg.hidden = true;
    if (refs.pixDone)    refs.pixDone.hidden    = true;
    if (refs.pixStatus)  refs.pixStatus.hidden  = true;
    if (refs.pixExpire)  refs.pixExpire.hidden  = true;
    if (refs.pixMsg)     refs.pixMsg.hidden     = true;
    if (refs.pixCopyRow) refs.pixCopyRow.hidden = true;
    if (refs.pixQrTxt)   refs.pixQrTxt.textContent = 'Gerando cobrança Pix…';

    if (refs.pixSummary) {
        refs.pixSummary.hidden = false;
        refs.pixSumCoins.textContent = fmtCoins(pack.coins)
            + (Number(pack.coins) === 1 ? ' moeda' : ' moedas');
        refs.pixSumPrice.textContent = 'R$ ' + Number(pack.priceBRL || 0).toFixed(2).replace('.', ',');
    }

    ch.send('pix_create', { packageId });
}

function handlePixResult(pix) {
    refs.pixCheckout.hidden = false;
    if (!pix.ok) {
        refs.pixQrFallback.hidden = false;
        refs.pixQrImg.hidden = true;
        if (refs.pixQrTxt) refs.pixQrTxt.textContent = pix.message || 'Pix indisponível.';
        setPixStatus(pix.message || 'Pix indisponível no momento.', 'err');
        return;
    }

    const qr = typeof pix.qrcode_base64 === 'string' && pix.qrcode_base64.length <= 400000
        && /^[A-Za-z0-9+/=]+$/.test(pix.qrcode_base64) ? pix.qrcode_base64 : '';
    if (qr) {
        refs.pixQrImg.src = 'data:image/png;base64,' + qr;
        refs.pixQrImg.hidden = false;
        refs.pixQrFallback.hidden = true;
    }

    if (pix.copiaECola && refs.pixCopy) {
        refs.pixCopy.value = pix.copiaECola;
        refs.pixCopyRow.hidden = false;
    }

    setPixStatus('Aguardando pagamento…', null);

    // countdown vivo (mm:ss) até a expiração da cobrança
    _pixExpiresAt = Number(pix.expiresAt) || 0;
    if (_pixExpiresAt > 0 && refs.pixExpire) {
        refs.pixExpire.hidden = false;
        stopPixTimer();
        _pixTimer = setInterval(tickPixCountdown, 1000);
        tickPixCountdown();
    }
}

function tickPixCountdown() {
    const left = Math.max(0, _pixExpiresAt - Math.floor(Date.now() / 1000));
    const mm = String(Math.floor(left / 60)).padStart(2, '0');
    const ss = String(left % 60).padStart(2, '0');
    if (refs.pixExpire) {
        refs.pixExpire.textContent = 'Expira em ' + mm + ':' + ss;
        refs.pixExpire.classList.toggle('urgent', left > 0 && left < 120);
    }
    if (left === 0) {
        stopPixTimer();
        setPixStatus('Cobrança expirada — escolha o pacote novamente.', 'err');
        if (refs.pixCopyRow) refs.pixCopyRow.hidden = true;
    }
}

// push do servidor após entrega confirmada (handler 'coins' do vhub_df)
function handlePixPaid(d) {
    stopPixTimer();
    if (refs.coins && d.newBalance != null) refs.coins.textContent = fmtCoins(d.newBalance);
    if (_data && d.newBalance != null) _data.coins = d.newBalance;

    if (_view !== 'pix' || refs.pixCheckout?.hidden) {
        showStatus('✓ Pix aprovado! +' + fmtCoins(d.coins) + ' moedas.', 5000);
        return;
    }
    if (refs.pixDone) {
        refs.pixDone.hidden = false;
        refs.pixDoneTxt.textContent = '+' + fmtCoins(d.coins) + ' moedas creditadas!';
    }
    setPixStatus('Pagamento confirmado!', 'ok');
    if (refs.pixExpire)  refs.pixExpire.hidden  = true;
    if (refs.pixCopyRow) refs.pixCopyRow.hidden = true;
}


// ============================================================
// ADMIN — dashboard
// ============================================================

function loadAdmDash() {
    if (!refs.admDash) return;
    if (refs.statItems)    refs.statItems.textContent    = '…';
    if (refs.statSales)    refs.statSales.textContent    = '…';
    if (refs.statCoins24h) refs.statCoins24h.textContent = '…';
    if (refs.statOnline)   refs.statOnline.textContent   = '…';
    if (refs.admRecentTx)  { refs.admRecentTx.innerHTML = ''; refs.admRecentTx.appendChild(spinner()); }
    ch.send('admin_stats', {});
    ch.send('admin_recent_tx', {});
}

function handleAdmStats(d) {
    if (!d.ok || !d.data) return;
    const s = d.data;
    if (refs.statItems)    refs.statItems.textContent    = s.totalItems ?? '—';
    if (refs.statSales)    refs.statSales.textContent    = s.totalSales ?? '—';
    if (refs.statCoins24h) refs.statCoins24h.textContent = fmtCoins(s.coins24h);
    if (refs.statOnline)   refs.statOnline.textContent   = s.online     ?? '—';
}

function handleAdmRecentTx(d) {
    if (!refs.admRecentTx) return;
    refs.admRecentTx.innerHTML = '';
    if (!d.ok || !d.data || !d.data.length) {
        refs.admRecentTx.appendChild(emptyMsg('Nenhuma transação recente.'));
        return;
    }
    d.data.forEach(tx => {
        const row  = el('div', { class: 'cs-adm-row' });
        const info = el('div', { class: 'cs-adm-row-info' });
        const name = el('div', { class: 'cs-adm-row-name' });
        name.textContent = tx.itemName || tx.item_id || '—';
        const sub = el('div', { class: 'cs-adm-row-sub' });
        sub.textContent = (tx.playerName || tx.char_id || '?') + ' · ' + fmtCoins(tx.price) + ' moedas';
        info.appendChild(name); info.appendChild(sub); row.appendChild(info);
        refs.admRecentTx.appendChild(row);
    });
}


// ============================================================
// ADMIN — catálogo
// ============================================================

function renderAdmCatalog() {
    if (!refs.admItemList || !_data) return;
    refs.admItemList.innerHTML = '';
    const q = _search.toLowerCase();
    const items = (_data.items || []).filter(i =>
        !q || (i.name || '').toLowerCase().includes(q) || (i.id || '').toLowerCase().includes(q)
    );
    if (!items.length) { refs.admItemList.appendChild(emptyMsg('Catálogo vazio.')); return; }
    items.forEach(item => refs.admItemList.appendChild(admItemRow(item)));
}

function admItemRow(item) {
    const row  = el('div', { class: 'cs-adm-row' });
    const info = el('div', { class: 'cs-adm-row-info' });
    const name = el('div', { class: 'cs-adm-row-name' });
    name.textContent = item.name || item.id;
    const sub = el('div', { class: 'cs-adm-row-sub' });
    sub.textContent = (item.category || '—') + ' · ' + fmtCoins(item.price) + ' moedas';
    info.appendChild(name); info.appendChild(sub); row.appendChild(info);

    const acts = el('div', { class: 'cs-adm-row-actions' });

    const btnEdit = el('button', { type: 'button', class: 'cs-btn ghost' });
    btnEdit.textContent = 'Editar';
    btnEdit.addEventListener('click', () => openAdmItemModal('edit', item));

    const btnDel = el('button', { type: 'button', class: 'cs-btn danger' });
    btnDel.textContent = 'Remover';
    btnDel.addEventListener('click', () => confirmAdmAction(
        'Remover "' + (item.name || item.id) + '"?',
        () => ch.send('admin_delete_item', { itemId: item.id })
    ));

    acts.appendChild(btnEdit);
    acts.appendChild(btnDel);
    row.appendChild(acts);
    return row;
}

function openAdmItemModal(mode, item) {
    const isEdit = mode === 'edit';
    if (refs.admModalBody) refs.admModalBody.innerHTML = '';

    const cats = (_data && _data.categories) ? _data.categories.map(c => c.id || c.name) : [];
    const formEls = {};

    const baseFields = [
        { key: 'id',          label: 'ID único',         hidden: isEdit, value: item?.id       || '',  placeholder: 'meu_carro' },
        { key: 'name',        label: 'Nome',                             value: item?.name     || '',  placeholder: 'Meu Carro' },
        { key: 'price',       label: 'Preço (moedas)',    type: 'number', value: item?.price  ?? 0 },
        { key: 'category',    label: 'Categoria',         type: 'select', value: item?.category || '',  options: cats },
        { key: 'description', label: 'Descrição',                         value: item?.description || '', placeholder: 'Descrição opcional' },
    ];

    baseFields.forEach(f => {
        if (f.hidden) return;
        const w = el('div', { class: 'cs-adm-field' });
        const lbl = el('span'); lbl.textContent = f.label; w.appendChild(lbl);

        let input;
        if (f.type === 'select') {
            input = el('select', { class: 'cs-select' });
            (f.options || []).forEach(opt => {
                const o = document.createElement('option');
                o.value = opt; o.textContent = opt;
                if (opt === f.value) o.selected = true;
                input.appendChild(o);
            });
        } else if (f.type === 'number') {
            input = el('input', { type: 'number', class: 'cs-input', min: '0' });
            input.value = f.value;
        } else {
            input = el('input', { type: 'text', class: 'cs-input', placeholder: f.placeholder || '' });
            input.value = f.value;
        }
        w.appendChild(input);
        formEls[f.key] = input;
        refs.admModalBody.appendChild(w);
    });

    // campos condicionais por categoria — injetados quando categoria muda
    function injectCatFields(cat) {
        refs.admModalBody.querySelectorAll('[data-cat-field]').forEach(n => n.remove());

        const extra = [];
        if (cat === 'vehicle') {
            extra.push({ key: 'spawnName',  label: 'Modelo (spawn_name)', picker: 'conce_vehicles',    vKey: 'spawnName', dKey: 'name'  });
        } else if (cat === 'weapon') {
            extra.push({ key: 'weaponName', label: 'Arma (weapon_name)',  picker: 'inventory_items',   vKey: 'name',      dKey: 'label', filter: 'weapon' });
        } else if (cat === 'item' || cat === 'consumable') {
            extra.push({ key: 'itemName',   label: 'Item (item_name)',    picker: 'inventory_items',   vKey: 'name',      dKey: 'label' });
        }

        extra.forEach(f => {
            const w = el('div', { class: 'cs-adm-field' });
            w.setAttribute('data-cat-field', '1');
            const lbl = el('span'); lbl.textContent = f.label; w.appendChild(lbl);

            const sel = el('select', { class: 'cs-select' });
            const loadOpt = document.createElement('option');
            loadOpt.textContent = 'Carregando…'; sel.appendChild(loadOpt);
            w.appendChild(sel);
            formEls[f.key] = sel;
            refs.admModalBody.appendChild(w);

            fetchPickerData(f.picker, f.filter).then(rows => {
                sel.innerHTML = '';
                const blank = document.createElement('option'); blank.value = ''; blank.textContent = '— Selecionar —'; sel.appendChild(blank);
                rows.forEach(row => {
                    const o = document.createElement('option');
                    o.value = row[f.vKey] || '';
                    o.textContent = row[f.dKey] || row[f.vKey] || '';
                    if (o.value === (item?.[f.key] || '')) o.selected = true;
                    sel.appendChild(o);
                });
            });
        });
    }

    if (formEls.category) {
        injectCatFields(formEls.category.value);
        formEls.category.addEventListener('change', () => injectCatFields(formEls.category.value));
    }

    openAdmModal(isEdit ? 'Editar Item' : 'Novo Item', () => {
        const payload = {};
        if (isEdit) payload.itemId = item?.id;
        for (const [k, node] of Object.entries(formEls)) payload[k] = node.value;
        if (!isEdit && !payload.id) payload.id = payload.spawnName || payload.itemName || payload.weaponName || '';
        ch.send(isEdit ? 'admin_edit_item' : 'admin_create_item', payload);
    });
}


// ============================================================
// PICKER LAZY (cache 60 s)
// ============================================================

function fetchPickerData(pickerKey, filterType) {
    const cached = _pickerCache[pickerKey];
    if (cached && Date.now() - cached.ts < PICKER_TTL) {
        return Promise.resolve(filterRows(cached.rows, filterType));
    }

    return new Promise(resolve => {
        const action = pickerKey === 'conce_vehicles'
            ? 'admin_list_conce_vehicles'
            : 'admin_list_inventory_items';

        const off = ch.on(action, d => {
            off();
            _pickerOffs.delete(off);
            const rows = (d && d.data) ? d.data : [];
            _pickerCache[pickerKey] = { ts: Date.now(), rows };
            resolve(filterRows(rows, filterType));
        });
        if (typeof off === 'function') _pickerOffs.add(off);

        ch.send(action, {});
    });
}

function filterRows(rows, filterType) {
    if (!filterType) return rows;
    return rows.filter(r => (r.type || r.category || '').toLowerCase().includes(filterType));
}


// ============================================================
// ADMIN — categorias
// ============================================================

function renderAdmCats() {
    if (!refs.admCatList || !_data) return;
    refs.admCatList.innerHTML = '';
    const cats = _data.categories || [];
    if (!cats.length) { refs.admCatList.appendChild(emptyMsg('Nenhuma categoria.')); return; }
    cats.forEach(cat => {
        const row  = el('div', { class: 'cs-adm-row' });
        const info = el('div', { class: 'cs-adm-row-info' });
        const name = el('div', { class: 'cs-adm-row-name' }); name.textContent = cat.name || cat.id;
        info.appendChild(name); row.appendChild(info);

        const acts = el('div', { class: 'cs-adm-row-actions' });
        const btnEdit = el('button', { type: 'button', class: 'cs-btn ghost' });
        btnEdit.textContent = 'Editar';
        btnEdit.addEventListener('click', () => openAdmCatModal('edit', cat));
        const btnDel = el('button', { type: 'button', class: 'cs-btn danger' });
        btnDel.textContent = 'Remover';
        btnDel.addEventListener('click', () => confirmAdmAction(
            'Remover categoria "' + (cat.name || cat.id) + '"?',
            () => ch.send('admin_delete_cat', { catId: cat.id })
        ));
        acts.appendChild(btnEdit); acts.appendChild(btnDel); row.appendChild(acts);
        refs.admCatList.appendChild(row);
    });
}

function openAdmCatModal(mode, cat) {
    if (refs.admModalBody) refs.admModalBody.innerHTML = '';
    const formEls = {};
    [
        { key: 'id',    label: 'ID',    hidden: mode === 'edit', value: cat?.id    || '' },
        { key: 'name',  label: 'Nome',                           value: cat?.name  || '' },
        { key: 'order', label: 'Ordem', type: 'number',          value: cat?.order ?? 0 },
    ].forEach(f => {
        if (f.hidden) return;
        const w = el('div', { class: 'cs-adm-field' });
        const lbl = el('span'); lbl.textContent = f.label; w.appendChild(lbl);
        const inp = el('input', { type: f.type || 'text', class: 'cs-input' });
        inp.value = f.value;
        w.appendChild(inp); formEls[f.key] = inp; refs.admModalBody.appendChild(w);
    });
    openAdmModal(mode === 'edit' ? 'Editar Categoria' : 'Nova Categoria', () => {
        const payload = {}; if (mode === 'edit') payload.catId = cat?.id;
        for (const [k, n] of Object.entries(formEls)) payload[k] = n.value;
        ch.send(mode === 'edit' ? 'admin_edit_cat' : 'admin_create_cat', payload);
    });
}


// ============================================================
// ADMIN — deals
// ============================================================

function renderAdmDeals() {
    if (!refs.admDealList || !_data) return;
    refs.admDealList.innerHTML = '';
    const deals = _data.deals || [];
    if (!deals.length) { refs.admDealList.appendChild(emptyMsg('Nenhuma oferta.')); return; }
    deals.forEach(deal => {
        const row  = el('div', { class: 'cs-adm-row' });
        const info = el('div', { class: 'cs-adm-row-info' });
        const name = el('div', { class: 'cs-adm-row-name' }); name.textContent = deal.name || deal.id;
        const sub  = el('div', { class: 'cs-adm-row-sub' });  sub.textContent = fmtCoins(deal.price) + ' moedas';
        info.appendChild(name); info.appendChild(sub); row.appendChild(info);
        const acts = el('div', { class: 'cs-adm-row-actions' });
        const btnDel = el('button', { type: 'button', class: 'cs-btn danger' });
        btnDel.textContent = 'Remover';
        btnDel.addEventListener('click', () => confirmAdmAction(
            'Remover oferta "' + (deal.name || deal.id) + '"?',
            () => ch.send('admin_delete_deal', { dealId: deal.id })
        ));
        acts.appendChild(btnDel); row.appendChild(acts);
        refs.admDealList.appendChild(row);
    });
}


// ============================================================
// ADMIN — jogadores
// ============================================================

function loadAdmPlayers() {
    if (!refs.admPlayerList) return;
    refs.admPlayerList.innerHTML = '';
    refs.admPlayerList.appendChild(spinner());
    ch.send('admin_online_players', {});
}

function handleAdmPlayers(d) {
    if (!refs.admPlayerList) return;
    refs.admPlayerList.innerHTML = '';
    if (!d.ok || !d.data || !d.data.length) {
        refs.admPlayerList.appendChild(emptyMsg('Nenhum jogador online.'));
        return;
    }
    d.data.forEach(p => {
        const row  = el('div', { class: 'cs-adm-row' });
        const info = el('div', { class: 'cs-adm-row-info' });
        const name = el('div', { class: 'cs-adm-row-name' }); name.textContent = p.name || ('ID ' + p.src);
        const sub  = el('div', { class: 'cs-adm-row-sub' });  sub.textContent = fmtCoins(p.coins) + ' moedas · ID ' + p.src;
        info.appendChild(name); info.appendChild(sub); row.appendChild(info);

        const acts = el('div', { class: 'cs-adm-row-actions' });
        const btnGive = el('button', { type: 'button', class: 'cs-btn sand' });
        btnGive.textContent = '+ Moedas';
        btnGive.addEventListener('click', () => openCoinModal('give', p));
        const btnSet = el('button', { type: 'button', class: 'cs-btn ghost' });
        btnSet.textContent = 'Definir';
        btnSet.addEventListener('click', () => openCoinModal('set', p));
        acts.appendChild(btnGive); acts.appendChild(btnSet); row.appendChild(acts);
        refs.admPlayerList.appendChild(row);
    });
}

function openCoinModal(mode, player) {
    if (refs.admModalBody) refs.admModalBody.innerHTML = '';
    const w = el('div', { class: 'cs-adm-field' });
    const lbl = el('span'); lbl.textContent = 'Quantidade'; w.appendChild(lbl);
    const inp = el('input', { type: 'number', class: 'cs-input', min: '0', placeholder: '0' });
    w.appendChild(inp); refs.admModalBody.appendChild(w);
    openAdmModal((mode === 'give' ? 'Dar Moedas' : 'Definir Moedas') + ' — ' + (player.name || 'ID ' + player.src), () => {
        const amount = parseInt(inp.value, 10);
        if (!amount && mode === 'give') return;
        ch.send(mode === 'give' ? 'admin_give_coins' : 'admin_set_coins', { targetId: player.src, amount });
    });
}


// ============================================================
// ADMIN — cupons MG7 (chave nasce no servidor; admin só informa moedas)
// ============================================================

let _lastCoupon = null;   // última chave gerada (para o botão copiar da vitrine)

// copia texto com fallback execCommand (clipboard API pode falhar no CEF)
function copyText(text) {
    if (!text) return false;
    let ok = false;
    const tmp = document.createElement('textarea');
    tmp.value = text;
    tmp.style.position = 'fixed';
    tmp.style.opacity = '0';
    document.body.appendChild(tmp);
    tmp.select();
    try { ok = document.execCommand('copy'); } catch (_) { /* CEF antigo */ }
    document.body.removeChild(tmp);
    if (!ok && navigator.clipboard) {
        navigator.clipboard.writeText(text).catch(() => {});
        ok = true;
    }
    return ok;
}

// exibe a vitrine do cupom recém-gerado (chave em claro; some ao reabrir a aba)
function showGeneratedCoupon(key, coins) {
    _lastCoupon = key;
    if (!refs.admCouponNew) return;
    refs.admCouponNew.hidden = false;
    refs.admCouponKey.textContent = key;
    refs.admCouponSub.textContent = fmtCoins(coins) + (Number(coins) === 1 ? ' moeda' : ' moedas');
}

function loadAdmCodes(keepCoupon) {
    if (!refs.admCodeList) return;
    if (!keepCoupon && refs.admCouponNew) refs.admCouponNew.hidden = true;
    refs.admCodeList.innerHTML = '';
    refs.admCodeList.appendChild(spinner());
    ch.send('admin_list_codes', {});
}

function handleAdmCodes(d) {
    if (!refs.admCodeList) return;
    refs.admCodeList.innerHTML = '';
    if (!d.ok || !d.data || !d.data.length) {
        refs.admCodeList.appendChild(emptyMsg('Nenhum cupom gerado ainda.')); return;
    }
    d.data.forEach(code => {
        const row  = el('div', { class: 'cs-adm-row' });
        const info = el('div', { class: 'cs-adm-row-info' });
        const name = el('div', { class: 'cs-adm-row-name cs-coupon-key' });
        name.textContent = code.key || '—';

        const sub = el('div', { class: 'cs-adm-row-sub' });
        sub.textContent = fmtCoins(code.coins) + ' moedas';
        const badge = el('span', {
            class: 'cs-badge ' + (code.status === 'pending' ? 'pending' : 'redeemed'),
        });
        badge.textContent = code.status === 'pending' ? 'Disponível' : 'Resgatado';
        sub.appendChild(document.createTextNode(' · '));
        sub.appendChild(badge);

        info.appendChild(name); info.appendChild(sub); row.appendChild(info);

        const acts = el('div', { class: 'cs-adm-row-actions' });
        if (code.status === 'pending') {
            const btnCopy = el('button', { type: 'button', class: 'cs-btn sand sm' });
            btnCopy.textContent = 'Copiar';
            btnCopy.addEventListener('click', () => {
                if (copyText(code.key)) showStatus('Cupom copiado!', 2000);
            });
            const btnDel = el('button', { type: 'button', class: 'cs-btn danger sm' });
            btnDel.textContent = 'Remover';
            btnDel.addEventListener('click', () => confirmAdmAction(
                'Remover o cupom ' + code.key + '?',
                () => ch.send('admin_delete_code', { key: code.key })
            ));
            acts.appendChild(btnCopy);
            acts.appendChild(btnDel);
        }
        row.appendChild(acts);
        refs.admCodeList.appendChild(row);
    });
}


// ============================================================
// ADMIN — tema
// ============================================================

function fillThemeForm() {
    if (!refs.admThemeForm || !_data) return;
    const s = _data.settings || {};
    if (refs.admThemeForm.accentColor) refs.admThemeForm.accentColor.value = s.accentColor || '';
    if (refs.admThemeForm.bgColor)     refs.admThemeForm.bgColor.value     = s.bgColor     || '';
    if (refs.admThemeForm.coinIcon)    refs.admThemeForm.coinIcon.value     = s.coinIcon    || '';
}


// ============================================================
// ADMIN — importar
// ============================================================

function handleAdmImportResult(d, target) {
    if (!target) return;
    target.innerHTML = '';
    const msg = el('p', { class: 'cs-sub' });
    msg.textContent = d.ok
        ? ('Importados: ' + (d.data?.count || 0) + ' itens.')
        : ('Erro: ' + (d.err || 'falha desconhecida'));
    target.appendChild(msg);
}


// ============================================================
// MODAL ADMIN GENÉRICO
// ============================================================

function openAdmModal(title, onOk) {
    if (refs.admModalTitle) refs.admModalTitle.textContent = title;
    _admModal = { onOk };
    if (refs.admOverlay) refs.admOverlay.hidden = false;
    setBusy(false);
}

function closeAdmModal() {
    if (refs.admOverlay) refs.admOverlay.hidden = true;
    _admModal = null;
    setBusy(false);
}

function confirmAdmAction(label, action) {
    if (refs.admModalBody) refs.admModalBody.innerHTML = '';
    const p = el('p', { class: 'cs-sub' }); p.textContent = label;
    refs.admModalBody.appendChild(p);
    openAdmModal('Confirmar', () => action());
}


// ============================================================
// STATUS
// ============================================================

let _statusTimer = null;
function showStatus(msg, ms) {
    if (!refs.status) return;
    clearTimeout(_statusTimer);
    refs.status.textContent = msg;
    refs.status.hidden = false;
    _statusTimer = setTimeout(() => { if (refs.status) refs.status.hidden = true; }, ms || 3000);
}


// ============================================================
// EVENTOS DO CANAL (server → UI) — registrados em onInit()
// ============================================================

// pickers lazy — sem stub permanente; fetchPickerData registra/cancela one-shot por demanda
// todos os ch.on permanentes vivem em onInit() abaixo

function listenChannel(event, handler) {
    const off = ch.on(event, handler);
    if (typeof off === 'function') _channelOffs.push(off);
    return off;
}


// ============================================================
// DELEGAÇÃO DE CLIQUES (data-action)
// ============================================================

function onClick(e) {
    const btn = e.target.closest('[data-action]');
    if (!btn) return;
    const action = btn.dataset.action;

    switch (action) {
        case 'view':
            _category = 'all';
            navigate(btn.dataset.view);
            break;

        case 'category':
            _category = btn.dataset.categoryId || 'all';
            navigate('grid');
            break;

        case 'sort':
            _sort = btn.dataset.sort || 'featured';
            renderGrid();
            buildTopNav();
            break;

        case 'open-item': {
            const item = (_data?.items || []).find(entry => entry.id === btn.dataset.itemId);
            if (item) openItemModal(item);
            break;
        }

        case 'open-deal': {
            const deal = (_data?.deals || []).find(entry => entry.id === btn.dataset.dealId);
            if (deal) openDealModal(deal);
            break;
        }

        case 'pix-create': createPix(btn.dataset.packageId); break;

        // pacote clicado na página principal → abre a aba Pix já com o checkout
        case 'home-pix':
            navigate('pix');
            createPix(btn.dataset.packageId);
            break;

        case 'modal-close': closeModal(); break;
        case 'modal-buy':
            if (_busy || !_modal) break;
            setBusy(true);
            ch.send(_modal._isDeal ? 'buy_deal' : 'buy_item',
                _modal._isDeal ? { dealId: _modal.id } : { itemId: _modal.id });
            break;

        case 'adm-modal-close': closeAdmModal(); break;
        case 'adm-modal-ok':
            if (_busy || !_admModal?.onOk) break;
            setBusy(true);
            _admModal.onOk();
            break;

        case 'adm-item-new':   openAdmItemModal('new', null); break;
        case 'adm-cat-new':    openAdmCatModal('new', null);  break;

        case 'adm-deal-new': {
            if (refs.admModalBody) refs.admModalBody.innerHTML = '';
            const dealFields = {};
            [
                { key: 'id',          label: 'ID único',   placeholder: 'deal_especial' },
                { key: 'name',        label: 'Nome',        placeholder: 'Oferta Especial' },
                { key: 'price',       label: 'Preço',       type: 'number' },
                { key: 'description', label: 'Descrição' },
            ].forEach(f => {
                const w = el('div', { class: 'cs-adm-field' });
                const lbl = el('span'); lbl.textContent = f.label; w.appendChild(lbl);
                const inp = el('input', { type: f.type || 'text', class: 'cs-input', placeholder: f.placeholder || '' });
                w.appendChild(inp); dealFields[f.key] = inp; refs.admModalBody.appendChild(w);
            });
            openAdmModal('Nova Oferta', () => {
                const payload = {};
                for (const [k, n] of Object.entries(dealFields)) payload[k] = n.value;
                ch.send('admin_create_deal', payload);
            });
            break;
        }

        case 'adm-code-new': {
            if (refs.admModalBody) refs.admModalBody.innerHTML = '';
            const w = el('div', { class: 'cs-adm-field' });
            const lbl = el('span'); lbl.textContent = 'Valor do cupom (moedas)'; w.appendChild(lbl);
            const inp = el('input', {
                type: 'number', class: 'cs-input', min: '1', placeholder: 'ex: 100',
            });
            w.appendChild(inp);
            const hint = el('p', { class: 'cs-sub' });
            hint.textContent = 'O código MG7 é gerado automaticamente pelo servidor.';
            refs.admModalBody.appendChild(w);
            refs.admModalBody.appendChild(hint);
            openAdmModal('Gerar Cupom MG7', () => {
                const coins = parseInt(inp.value, 10);
                if (!coins || coins <= 0) { setBusy(false); return; }
                ch.send('admin_create_code', { coins });
            });
            break;
        }

        case 'adm-coupon-copy':
            if (_lastCoupon && copyText(_lastCoupon)) showStatus('Cupom copiado!', 2000);
            break;

        case 'adm-players-refresh': loadAdmPlayers(); break;
        case 'adm-codes-refresh':   loadAdmCodes();   break;

        case 'adm-clear-all':
            confirmAdmAction('Isso apagará TODO o catálogo (itens, categorias, ofertas). Confirmar?',
                () => ch.send('admin_clear_all', {}));
            break;

        case 'adm-theme-reset': ch.send('admin_reset_settings', {}); break;

        case 'adm-import-preview':
            if (refs.admImportJson) ch.send('admin_import_preview', { json: refs.admImportJson.value });
            break;

        case 'adm-import-run':
            if (refs.admImportJson) ch.send('admin_import_run', { json: refs.admImportJson.value });
            break;

        case 'pix-copy':
            if (refs.pixCopy && copyText(refs.pixCopy.value)) {
                showStatus('Pix copia-e-cola copiado!', 2000);
            }
            break;
    }
}


// ============================================================
// BUSCA
// ============================================================

function onSearch(e) {
    _search = (e.target.value || '').trim();
    if (_view === 'grid')         renderGrid();
    if (_view === 'adm-catalog')  renderAdmCatalog();
}


// ============================================================
// REDEEM
// ============================================================

function onRedeemSubmit(e) {
    e.preventDefault();
    if (_busy) return;
    const key = refs.redeemKey?.value?.trim();
    if (!key) return showStatus('Informe o código ou número do pedido.', 3000);
    const giftId = refs.giftToggle?.checked ? (refs.giftId?.value?.trim() || null) : null;
    setBusy(true);
    ch.send('redeem', { redeemKey: key, targetId: giftId });
}

function onGiftToggle() {
    if (refs.giftId) refs.giftId.hidden = !refs.giftToggle?.checked;
}


// ============================================================
// TEMA ADMIN — submit
// ============================================================

function onThemeSubmit(e) {
    e.preventDefault();
    if (!refs.admThemeForm) return;
    ch.send('admin_save_settings', {
        accentColor: refs.admThemeForm.accentColor?.value || '',
        bgColor:     refs.admThemeForm.bgColor?.value     || '',
        coinIcon:    refs.admThemeForm.coinIcon?.value     || '',
    });
}


// ============================================================
// LIFECYCLE — contrato do iPad (vhub.createModule)
// ============================================================

vhub.createModule('coinshop', {

    onInit() {
        listenChannel('data', d => {
            _data = d;
            if (_category !== 'all' && !(d.categories || []).some(category =>
                String(category.id || '') === _category)) {
                _category = 'all';
            }
            if (refs.player) refs.player.textContent = d.playerName || d.charName || '—';
            if (refs.coins)  refs.coins.textContent  = fmtCoins(d.coins);
            buildNav();
            navigate(_view || 'grid');
        });

        listenChannel('coins', d => {
            if (refs.coins) refs.coins.textContent = fmtCoins(d.coins);
            if (_data) _data.coins = d.coins;
        });

        listenChannel('result', d => {
            setBusy(false);
            const ok = d.ok === true;
            showStatus((ok ? '✓ ' : '✗ ') + (d.message || (ok ? 'OK' : 'Erro')), 4000);
            if (ok) {
                closeModal();
                closeAdmModal();
            }
        });

        listenChannel('pix',                  handlePixResult);
        listenChannel('pix_paid',             handlePixPaid);
        listenChannel('admin_create_code', d => {
            setBusy(false);
            if (d.ok && d.key) {
                closeAdmModal();
                showGeneratedCoupon(d.key, d.coins);
                loadAdmCodes(true);
                showStatus('✓ Cupom gerado!', 3000);
            } else {
                showStatus('✗ Falha ao gerar cupom: ' + (d.err || 'erro'), 4000);
            }
        });
        listenChannel('admin_delete_code', d => {
            if (d.ok) loadAdmCodes(true);
            else showStatus('✗ ' + (d.err || 'Falha ao remover cupom.'), 3500);
        });
        listenChannel('admin_stats',          handleAdmStats);
        listenChannel('admin_recent_tx',      handleAdmRecentTx);
        listenChannel('admin_online_players', handleAdmPlayers);
        listenChannel('admin_list_codes',     handleAdmCodes);
        listenChannel('admin_give_coins',     d => { if (d.ok) loadAdmPlayers(); });
        listenChannel('admin_set_coins',      d => { if (d.ok) loadAdmPlayers(); });
        listenChannel('admin_import_preview', d => handleAdmImportResult(d, refs.admImportResult));
        listenChannel('admin_import_run',     d => { handleAdmImportResult(d, refs.admImportResult); if (d.ok) ch.send('open', {}); });
        listenChannel('admin_create_item',    d => { if (d.ok) { closeAdmModal(); ch.send('open', {}); } });
        listenChannel('admin_edit_item',      d => { if (d.ok) { closeAdmModal(); ch.send('open', {}); } });
        listenChannel('admin_delete_item',    d => { if (d.ok) ch.send('open', {}); });
        listenChannel('admin_create_cat',     d => { if (d.ok) { closeAdmModal(); ch.send('open', {}); } });
        listenChannel('admin_edit_cat',       d => { if (d.ok) { closeAdmModal(); ch.send('open', {}); } });
        listenChannel('admin_delete_cat',     d => { if (d.ok) ch.send('open', {}); });
        listenChannel('admin_create_deal',    d => { if (d.ok) { closeAdmModal(); ch.send('open', {}); } });
        listenChannel('admin_delete_deal',    d => { if (d.ok) ch.send('open', {}); });
        listenChannel('admin_clear_all',      d => { if (d.ok) ch.send('open', {}); });
        listenChannel('admin_save_settings',  d => { if (d.ok) ch.send('open', {}); });
        listenChannel('admin_reset_settings', d => { if (d.ok) ch.send('open', {}); });
        listenChannel('denied',               () => showStatus('Acesso negado.', 3000));
    },

    onMount(el) {
        _root = el;
        cacheRefs();

        el.addEventListener('click', onClick);
        if (refs.search)       refs.search.addEventListener('input', onSearch);
        if (refs.giftToggle)   refs.giftToggle.addEventListener('change', onGiftToggle);
        if (refs.redeem)       refs.redeem.addEventListener('submit', onRedeemSubmit);
        if (refs.admThemeForm) refs.admThemeForm.addEventListener('submit', onThemeSubmit);
    },

    onShow() {
        ch.send('open', {});
    },
    onHide()  {
        stopPixTimer();   // não deixa countdown rodando com o app oculto (A-07)
    },

    onDestroy() {
        clearTimeout(_statusTimer);
        stopPixTimer();
        _channelOffs.splice(0).forEach(off => off());
        _pickerOffs.forEach(off => off());
        _pickerOffs.clear();

        if (_root) _root.removeEventListener('click', onClick);
        if (refs.search)       refs.search.removeEventListener('input', onSearch);
        if (refs.giftToggle)   refs.giftToggle.removeEventListener('change', onGiftToggle);
        if (refs.redeem)       refs.redeem.removeEventListener('submit', onRedeemSubmit);
        if (refs.admThemeForm) refs.admThemeForm.removeEventListener('submit', onThemeSubmit);

        _root = null;
        refs = {};
    },

});

})();
