/* ============================================================
   vhub_coinshop — nui/js/app.js
   Lifecycle A-02: onInit / onShow / onHide / onDestroy
   A-07: cleanup obrigatório (RAF/interval/listener/observer)
   A-08: idle 0ms com NUI fechada — countdown só roda quando visível
   A-10: sem CDN, sem fetch externo, todos os ícones SVG inline
   ============================================================ */

(function () {
    'use strict';

    // ============================================================
    // SLICE DE ESTADO (A-04 — dono único: este módulo)
    // ============================================================

    const state = {
        shopItems: [],
        customCategories: [],
        deals: [],
        playerCoins: 0,
        playerName: 'Jogador',
        playerAvatar: '',
        isAdmin: false,
        currentPage: 'home',
        redeemMode: 'self',
        selectedItem: null,
        selectedDeal: null,
        dealResetHour: 0,
        settings: {},
        locale: {},
        logo: '',
        // admin state
        adminPlayers: [],
        dealSelectedItems: [],
        editingItemId: null,
        editingCategoryId: null,
    };

    // handles para cleanup (A-07)
    let _countdownInterval = null;
    let _messageHandler = null;
    let _keydownHandler = null;
    let _clickHandler = null;
    let _toastTimeout = null;
    let _isVisible = false;
    let _destroyed = false;

    // ============================================================
    // ÍCONES SVG INLINE (sem CDN — A-10)
    // ============================================================

    const ICONS = {
        coin: "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none'><circle cx='12' cy='12' r='10' fill='%23f3b53a'/><circle cx='12' cy='12' r='8' fill='none' stroke='%23a89572' stroke-width='1'/><text x='12' y='16.5' text-anchor='middle' font-family='Arial,sans-serif' font-weight='bold' font-size='12' fill='%230c0a06'>$</text></svg>",
        home: "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23d9c19a' stroke-width='1.6' stroke-linecap='round' stroke-linejoin='round'><path d='M3 10.5L12 3l9 7.5V20a1 1 0 01-1 1h-4v-5a1 1 0 00-1-1h-2a1 1 0 00-1 1v5H5a1 1 0 01-1-1v-9.5z'/></svg>",
        car: "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23d9c19a' stroke-width='1.6' stroke-linecap='round' stroke-linejoin='round'><path d='M5 17h14M5 17a2 2 0 01-2-2v-3l2-4h10l2 4v3a2 2 0 01-2 2M5 17a1.5 1.5 0 100-3 1.5 1.5 0 000 3zm14 0a1.5 1.5 0 100-3 1.5 1.5 0 000 3z'/><path d='M5 10h14'/></svg>",
        box: "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23d9c19a' stroke-width='1.6' stroke-linecap='round' stroke-linejoin='round'><path d='M21 8l-9-5-9 5v8l9 5 9-5V8z'/><path d='M3 8l9 5 9-5M12 13v8'/></svg>",
        weapon: "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23d9c19a' stroke-width='1.6' stroke-linecap='round' stroke-linejoin='round'><circle cx='12' cy='12' r='8'/><path d='M12 2v4M12 18v4M2 12h4M18 12h4'/><circle cx='12' cy='12' r='2'/></svg>",
        tools: "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23d9c19a' stroke-width='1.6' stroke-linecap='round' stroke-linejoin='round'><path d='M14.7 6.3a1 1 0 000 1.4l1.6 1.6a1 1 0 001.4 0l3-3A6 6 0 0112.7 15L5.4 21.3a2 2 0 01-2.8-2.8L9 11.3A6 6 0 0114.7 6.3z'/></svg>",
        tutorial: "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23d9c19a' stroke-width='1.6' stroke-linecap='round' stroke-linejoin='round'><rect x='3' y='3' width='18' height='18' rx='2'/><path d='M7 8h10M7 12h10M7 16h6'/></svg>",
        redeem: "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23d9c19a' stroke-width='1.6' stroke-linecap='round' stroke-linejoin='round'><path d='M2 9V6a1 1 0 011-1h18a1 1 0 011 1v3a2 2 0 100 4v3a1 1 0 01-1 1H3a1 1 0 01-1-1v-3a2 2 0 100-4z'/><path d='M9 12l2 2 4-4'/></svg>",
        admin: "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23d9c19a' stroke-width='1.6' stroke-linecap='round' stroke-linejoin='round'><path d='M12 2l8 4v6c0 5-3.5 9-8 10-4.5-1-8-5-8-10V6l8-4z'/></svg>",
        close: "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round'><path d='M18 6L6 18M6 6l12 12'/></svg>",
        search: "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23a89572' stroke-width='1.6' stroke-linecap='round' stroke-linejoin='round'><circle cx='11' cy='11' r='7'/><path d='M21 21l-4.35-4.35'/></svg>",
        fire: "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='%23ff9a1f'><path d='M12 23c-4.97 0-8-3.03-8-7 0-2.22.98-4.47 2.5-6.2.46-.52 1.23-.33 1.39.34.22.94.63 1.7 1.22 2.25C9.68 8.9 11.05 5.36 10.7 2.57a.83.83 0 011.4-.53c2.44 2.3 4.65 6.16 4.65 9.96 1.2-.84 1.67-2.36 1.75-3.62a.84.84 0 011.44-.5C21.23 9.17 22 11.55 22 14c0 5.52-4.48 9-10 9z'/></svg>",
        gift: "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23d9c19a' stroke-width='1.6' stroke-linecap='round' stroke-linejoin='round'><rect x='3' y='10' width='18' height='11' rx='1'/><path d='M12 6a3 3 0 00-3-3c-1.66 0-3 1.34-3 3 0 2 3 3 3 3h6s3-1 3-3c0-1.66-1.34-3-3-3a3 3 0 00-3 3zM12 6v15'/><rect x='1' y='8' width='22' height='4' rx='1'/></svg>",
        placeholder: "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 200 200'><rect width='200' height='200' fill='%231a1610'/><text x='100' y='105' text-anchor='middle' font-family='Arial,sans-serif' font-size='14' fill='%235a4a30'>Sem Imagem</text></svg>",
    };

    // mapeamento de ícones por tipo de categoria (default)
    const CATEGORY_ICONS = {
        vehicles: ICONS.car,
        items: ICONS.box,
        weapons: ICONS.weapon,
        tools: ICONS.tools,
    };

    // ============================================================
    // HELPERS
    // ============================================================

    function L(key) { return state.locale[key] || key; }

    function esc(s) {
        if (s == null) return '';
        return String(s).replace(/[&<>"']/g, function (c) {
            return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
        });
    }

    // POST para o resource FiveM (callback NUI)
    function nuiPost(action, data) {
        return fetch('https://vhub_coinshop/' + action, {
            method: 'POST',
            body: JSON.stringify(data || {}),
        }).then(function (r) { return r.json(); }).catch(function (err) {
            return { ok: false, err: 'network_error' };
        });
    }

    // lib.callback wrapper (cliente aguarda resposta) — via NUI post → cliente lua
    function nuiCallback(action, data) {
        return nuiPost(action, data);
    }

    function $(id) { return document.getElementById(id); }
    function $$(sel) { return document.querySelectorAll(sel); }

    function formatNumber(n) {
        return (parseInt(n, 10) || 0).toLocaleString('pt-BR');
    }


    // ============================================================
    // LIFECYCLE — A-02
    // ============================================================

    function onInit() {
        // listener de mensagens do cliente Lua (SendNUIMessage)
        _messageHandler = function (event) {
            const data = event.data;
            if (!data || !data.type) return;
            handleMessage(data);
        };
        window.addEventListener('message', _messageHandler);

        // ESC fecha overlays/modais ou a loja
        _keydownHandler = function (e) {
            if (e.key !== 'Escape') return;
            if (handleEscape()) return; // overlay/modal fechou
            nuiPost('close');
        };
        document.addEventListener('keydown', _keydownHandler);

        // clique global: fecha custom-select ao clicar fora
        _clickHandler = function (e) {
            if (!e.target.closest('.custom-select')) {
                $$('.custom-select-options.open').forEach(function (el) {
                    el.classList.remove('open');
                    el.closest('.custom-select').querySelector('.custom-select-trigger').classList.remove('open');
                });
            }
        };
        document.addEventListener('click', _clickHandler);

        // delegação de cliques para botões com data-action
        document.body.addEventListener('click', function (e) {
            const btn = e.target.closest('[data-action]');
            if (!btn) return;
            handleAction(btn.dataset.action, btn.dataset, btn);
        });

        // aplica ícones SVG aos placeholders [data-svg]
        applySvgIcons();

        // aplica locale aos elementos com data-i18n
        applyLocale();

        // bind dos botões de ação específicos (que têm lógica própria)
        bindActionButtons();
    }

    function onShow() {
        _isVisible = true;
        $('app').classList.remove('hidden');
        applyLocale();
        renderNav();
        buildCategoryPages();
        updateCoinDisplays();
        applyTheme(state.settings);
        renderAllPages();
        showPage('home');
        startCountdown();
        updateCategoryDropdown();
        // admin button visibilidade
        const adminBtn = $('admin-btn');
        if (state.isAdmin) adminBtn.classList.remove('hidden');
        else adminBtn.classList.add('hidden');
        // logo + avatar + nome
        if (state.logo) $('shop-logo').src = state.logo;
        $('player-name').textContent = state.playerName;
        if (state.playerAvatar) $('player-avatar').src = state.playerAvatar;
        // ícone da moeda no header
        $('coin-icon-header').src = (state.settings.coinIcon || ICONS.coin);
    }

    function onHide() {
        _isVisible = false;
        $('app').classList.add('hidden');
        // fecha todos os overlays/modais
        ['payment', 'redeem', 'admin', 'deal-purchase'].forEach(function (name) {
            const el = $(name + '-overlay');
            if (el) el.classList.add('hidden');
        });
        ['create-modal', 'category-modal', 'deal-modal',
         'give-coins-modal', 'delete-confirm-modal', 'set-coins-modal', 'clear-all-modal'
        ].forEach(function (id) { const el = $(id); if (el) el.classList.add('hidden'); });
        stopCountdown();
    }

    function onDestroy() {
        _destroyed = true;
        if (_messageHandler) window.removeEventListener('message', _messageHandler);
        if (_keydownHandler) document.removeEventListener('keydown', _keydownHandler);
        if (_clickHandler) document.removeEventListener('click', _clickHandler);
        stopCountdown();
        if (_toastTimeout) { clearTimeout(_toastTimeout); _toastTimeout = null; }
    }


    // ============================================================
    // MESSAGE ROUTER — server→NUI
    // ============================================================

    function handleMessage(data) {
        switch (data.type) {
            case 'open':
                state.shopItems = data.items || [];
                state.customCategories = data.categories || [];
                state.deals = data.deals || [];
                state.playerCoins = data.coins || 0;
                state.playerName = data.playerName || 'Jogador';
                state.playerAvatar = data.playerAvatar || '';
                state.isAdmin = !!data.isAdmin;
                state.dealResetHour = data.dealResetHour || 0;
                state.settings = data.settings || {};
                state.locale = data.locale || {};
                onShow();
                break;
            case 'close':
                onHide();
                break;
            case 'coinsChanged':
                state.playerCoins = data.coins || 0;
                updateCoinDisplays();
                break;
            case 'refreshItems':
                state.shopItems = data.items || [];
                renderAllPages();
                renderCreatorPackages();
                break;
            case 'refreshCategories':
                state.customCategories = data.categories || [];
                renderNav();
                buildCategoryPages();
                renderAllPages();
                renderCreatorPackages();
                renderCreatorCategories();
                updateCategoryDropdown();
                break;
            case 'refreshDeals':
                state.deals = data.deals || [];
                renderTrendingBanner();
                renderCreatorDeals();
                break;
            case 'notify':
                showToast(data.message, data.kind);
                break;
        }
    }


    // ============================================================
    // SVG ICONS — aplica aos placeholders [data-svg]
    // ============================================================

    function applySvgIcons() {
        $$('[data-svg]').forEach(function (el) {
            const name = el.dataset.svg;
            if (ICONS[name]) {
                el.style.backgroundImage = 'url("' + ICONS[name] + '")';
                el.style.backgroundRepeat = 'no-repeat';
                el.style.backgroundPosition = 'center';
                el.style.backgroundSize = 'contain';
            }
        });
    }


    // ============================================================
    // LOCALE — aplica data-i18n aos elementos
    // ============================================================

    function applyLocale() {
        $$('[data-i18n]').forEach(function (el) {
            el.textContent = L(el.dataset.i18n);
        });
        $$('[data-i18n-placeholder]').forEach(function (el) {
            el.placeholder = L(el.dataset.i18nPlaceholder);
        });
    }


    // ============================================================
    // THEME — aplica settings de UI (paleta dinâmica)
    // ============================================================

    function applyTheme(settings) {
        const root = document.documentElement;
        const s = settings || {};
        if (s.accentColor) root.style.setProperty('--accent', s.accentColor);
        if (s.bgColor) root.style.setProperty('--bg', s.bgColor);
        if (s.textColor) root.style.setProperty('--text', s.textColor);
        if (s.errorColor) root.style.setProperty('--error', s.errorColor);
        if (s.cardBorderColor) root.style.setProperty('--card-border', s.cardBorderColor);
        if (s.bgOpacity) document.documentElement.style.setProperty('--bg-overlay', s.bgOpacity);
        if (s.bgBlur) document.documentElement.style.setProperty('--bg-blur', s.bgBlur + 'px');
        if (s.cardBgOpacity) document.documentElement.style.setProperty('--card-bg-opacity', s.cardBgOpacity);
        if (s.cardBorderRadius) document.documentElement.style.setProperty('--radius-md', s.cardBorderRadius + 'px');
        if (s.bgImage) document.documentElement.style.setProperty('--bg-image', "url('" + s.bgImage + "')");
        if (s.coinIcon) {
            const coinEls = $$('.coin-icon');
            coinEls.forEach(function (el) { el.src = s.coinIcon; });
        }
    }


    // ============================================================
    // COIN DISPLAYS — atualiza todos os displays de saldo
    // ============================================================

    function updateCoinDisplays() {
        const formatted = formatNumber(state.playerCoins);
        $('player-coins-nav').textContent = formatted;
        $('payment-coins').textContent = formatted;
        $('redeem-coins').textContent = formatted;
        const dealCoins = $('deal-purchase-coins');
        if (dealCoins) dealCoins.textContent = formatted;
    }


    // ============================================================
    // NAV — renderiza botões de navegação (home + categorias)
    // ============================================================

    function renderNav() {
        const container = $('nav-container');
        const items = [
            { id: 'home', label: L('ui_home'), icon: ICONS.home },
            { id: 'tutorial', label: L('ui_tutorial'), icon: ICONS.tutorial },
        ];
        // categorias canônicas (vehicles/items/weapons/tools) + custom
        const cats = state.customCategories || [];
        cats.forEach(function (cat) {
            const icon = cat.icon || CATEGORY_ICONS[cat.id] || CATEGORY_ICONS[cat.type] || ICONS.box;
            items.push({ id: 'cat_' + cat.id, label: cat.name, icon: icon });
        });
        container.innerHTML = items.map(function (item) {
            return '<button class="nav-btn" data-page="' + item.id + '" onclick="window.__coinshop.showPage(\'' + item.id + '\')">' +
                '<span class="btn-icon" style="background-image:url(\'' + item.icon + '\')"></span>' +
                '<span>' + esc(item.label) + '</span>' +
                '</button>';
        }).join('');
    }


    // ============================================================
    // PAGES — cria páginas dinâmicas para cada categoria custom
    // ============================================================

    function buildCategoryPages() {
        // remove páginas dinâmicas antigas
        $$('.dynamic-category-page').forEach(function (el) { el.remove(); });
        const pagesContainer = $('pages-container');
        (state.customCategories || []).forEach(function (cat) {
            const pageId = 'cat_' + cat.id;
            if ($(pageId + '-page')) return;
            const page = document.createElement('section');
            page.id = pageId + '-page';
            page.className = 'page dynamic-category-page hidden';
            page.innerHTML =
                '<div class="page-head">' +
                  '<div>' +
                    '<h2 class="page-title">' + esc(L('ui_browse').replace('%s', cat.name)) + '</h2>' +
                    '<p class="page-sub">' + esc(L('ui_explore').replace('%s', cat.name.toLowerCase())) + '</p>' +
                  '</div>' +
                  '<div class="search-box">' +
                    '<span class="btn-icon" style="background-image:url(\'' + ICONS.search + '\')"></span>' +
                    '<input type="text" oninput="window.__coinshop.filterItems(\'' + pageId + '\')" id="' + pageId + '-search" placeholder="' + esc(L('ui_search').replace('%s', cat.name.toLowerCase())) + '" class="search-input" />' +
                  '</div>' +
                '</div>' +
                '<div id="' + pageId + '-grid" class="grid"></div>';
            pagesContainer.appendChild(page);
        });
    }

    function showPage(pageId) {
        state.currentPage = pageId;
        $$('.page').forEach(function (p) { p.classList.add('hidden'); });
        const target = $(pageId + '-page') || $(pageId + '-page');
        const page = document.getElementById(pageId + '-page');
        if (page) page.classList.remove('hidden');
        $$('.nav-btn').forEach(function (b) {
            b.classList.toggle('active', b.dataset.page === pageId);
        });
        // renderiza a grade se for home ou categoria
        if (pageId === 'home') renderHomeGrid();
        else if (pageId.indexOf('cat_') === 0) renderCategoryGrid(pageId);
    }

    function renderAllPages() {
        renderHomeGrid();
        (state.customCategories || []).forEach(function (cat) {
            renderCategoryGrid('cat_' + cat.id);
        });
    }

    function renderHomeGrid() {
        const grid = $('home-grid');
        if (!grid) return;
        const items = state.shopItems.slice(0, 24); // home mostra topo
        grid.innerHTML = items.map(function (i) { return createItemCard(i); }).join('');
    }

    function renderCategoryGrid(pageId) {
        const grid = $(pageId + '-grid');
        if (!grid) return;
        const catId = pageId.replace('cat_', '');
        const items = state.shopItems.filter(function (i) {
            return i.category === catId || i.customCategory === catId;
        });
        grid.innerHTML = items.map(function (i) { return createItemCard(i); }).join('');
    }

    function filterItems(pageId) {
        const input = $(pageId + '-search');
        if (!input) return;
        const q = input.value.toLowerCase().trim();
        const grid = $(pageId + '-grid') || $('home-grid');
        if (!grid) return;
        let items;
        if (pageId === 'home') items = state.shopItems.slice(0, 24);
        else {
            const catId = pageId.replace('cat_', '');
            items = state.shopItems.filter(function (i) {
                return i.category === catId || i.customCategory === catId;
            });
        }
        if (q) {
            items = items.filter(function (i) {
                return (i.name && i.name.toLowerCase().indexOf(q) >= 0) ||
                       (i.description && i.description.toLowerCase().indexOf(q) >= 0) ||
                       (i.tags && i.tags.some(function (t) { return t.toLowerCase().indexOf(q) >= 0; }));
            });
        }
        grid.innerHTML = items.map(function (i) { return createItemCard(i); }).join('');
    }


    // ============================================================
    // ITEM CARD
    // ============================================================

    function createItemCard(item) {
        const firstImage = (item.images && item.images.length > 0) ? item.images[0] : ICONS.placeholder;
        const trendingBadge = item.trending
            ? '<span class="item-card-trending">' + esc(L('ui_trending')) + '</span>'
            : '';
        return '<div class="item-card" onclick="window.__coinshop.openPayment(\'' + esc(item.id) + '\')">' +
            '<img class="item-card-img" src="' + esc(firstImage) + '" onerror="this.src=\'' + ICONS.placeholder + '\'" />' +
            '<div class="item-card-name">' + esc(item.name) + '</div>' +
            '<div class="item-card-desc">' + esc(item.description || '') + '</div>' +
            '<div class="item-card-footer">' +
                '<div class="item-card-price">' +
                    '<img class="coin-icon" src="' + (state.settings.coinIcon || ICONS.coin) + '" />' +
                    formatNumber(item.price) +
                '</div>' +
                trendingBadge +
            '</div>' +
        '</div>';
    }


    // ============================================================
    // OVERLAYS — payment / redeem / admin / deal-purchase
    // ============================================================

    function showOverlay(name) {
        const el = $(name + '-overlay');
        if (el) el.classList.remove('hidden');
    }

    function hideOverlay(name) {
        const el = $(name + '-overlay');
        if (el) el.classList.add('hidden');
    }

    function openPayment(itemId) {
        const item = state.shopItems.find(function (i) { return i.id === itemId; });
        if (!item) return;
        state.selectedItem = item;
        $('payment-image').src = (item.images && item.images[0]) || ICONS.placeholder;
        $('payment-item-name').textContent = item.name;
        $('payment-item-price').innerHTML = '<img class="coin-icon" src="' + (state.settings.coinIcon || ICONS.coin) + '" /> ' + formatNumber(item.price);
        // botão de test-drive só aparece para veículos
        const tdBtn = $('test-drive-btn');
        if (item.category === 'vehicle') tdBtn.classList.remove('hidden');
        else tdBtn.classList.add('hidden');
        showOverlay('payment');
    }

    function openDealPurchase(dealId) {
        const deal = state.deals.find(function (d) { return d.id === dealId; });
        if (!deal) return;
        state.selectedDeal = deal;
        $('deal-purchase-name').textContent = deal.name;
        $('deal-purchase-price').innerHTML = '<img class="coin-icon" src="' + (state.settings.coinIcon || ICONS.coin) + '" /> ' + formatNumber(deal.price);
        $('deal-purchase-items').innerHTML = deal.items.map(function (i) {
            return '<div class="data-row"><span>' + esc(i.name) + '</span><span>' + formatNumber(i.price) + '</span></div>';
        }).join('');
        showOverlay('deal-purchase');
    }


    // ============================================================
    // ESC — fecha overlay/modal em ordem (A-07 cleanup implícito)
    // ============================================================

    function handleEscape() {
        const modalOrder = ['deal-modal', 'category-modal', 'create-modal', 'give-coins-modal', 'set-coins-modal', 'delete-confirm-modal', 'clear-all-modal'];
        for (let i = 0; i < modalOrder.length; i++) {
            const el = $(modalOrder[i]);
            if (el && !el.classList.contains('hidden')) {
                el.classList.add('hidden');
                return true;
            }
        }
        const overlays = ['payment', 'admin', 'redeem', 'deal-purchase'];
        for (let i = 0; i < overlays.length; i++) {
            const el = $(overlays[i] + '-overlay');
            if (el && !el.classList.contains('hidden')) {
                hideOverlay(overlays[i]);
                return true;
            }
        }
        return false;
    }


    // ============================================================
    // ACTIONS — delegação de cliques por data-action
    // ============================================================

    function handleAction(action, ds, btn) {
        switch (action) {
            case 'closeShop': nuiPost('close'); break;
            case 'showOverlay': showOverlay(ds.overlay); break;
            case 'hideOverlay': hideOverlay(ds.overlay); break;
            case 'showCreateItem': showCreateModal(null); break;
            case 'showCreateCategory': showCategoryModal(null); break;
            case 'showCreateDeal': showDealModal(); break;
            case 'showClearAll': $('clear-all-modal').classList.remove('hidden'); break;
            case 'hideClearAll': $('clear-all-modal').classList.add('hidden'); break;
            case 'hideCreateModal': $('create-modal').classList.add('hidden'); break;
            case 'hideCategoryModal': $('category-modal').classList.add('hidden'); break;
            case 'hideDealModal': $('deal-modal').classList.add('hidden'); break;
            case 'hideGiveCoinsModal': $('give-coins-modal').classList.add('hidden'); break;
            case 'hideSetCoinsModal': $('set-coins-modal').classList.add('hidden'); break;
            case 'hideDeleteConfirm': $('delete-confirm-modal').classList.add('hidden'); break;
            case 'refreshPlayers': loadOnlinePlayers(); break;
            case 'saveSettings': saveSettings(); break;
            case 'resetSettings': resetSettings(); break;
        }
    }

    // bind dos botões com lógica própria (não-genéricos)
    function bindActionButtons() {
        $('confirm-purchase-btn').addEventListener('click', confirmPurchase);
        $('test-drive-btn').addEventListener('click', confirmTestDrive);
        $('confirm-redeem-btn').addEventListener('click', confirmRedeem);
        $('confirm-deal-btn').addEventListener('click', confirmDealPurchase);
        $('confirm-give-btn').addEventListener('click', confirmGiveCoins);
        $('confirm-set-btn').addEventListener('click', confirmSetCoins);
        $('confirm-delete-btn').addEventListener('click', confirmDelete);
        $('confirm-clear-btn').addEventListener('click', confirmClearAll);
        $('save-item-btn').addEventListener('click', saveItem);
        $('save-category-btn').addEventListener('click', saveCategory);
        $('save-deal-btn').addEventListener('click', saveDeal);

        // tabs admin
        $$('.admin-tab-btn').forEach(function (btn) {
            btn.addEventListener('click', function () {
                $$('.admin-tab-btn').forEach(function (b) { b.classList.remove('active'); });
                btn.classList.add('active');
                $$('.admin-tab').forEach(function (t) { t.classList.add('hidden'); });
                $(btn.dataset.tab + '-tab').classList.remove('hidden');
                // carrega dados da tab
                if (btn.dataset.tab === 'admin-center') loadAdminCenter();
                if (btn.dataset.tab === 'creator-center') loadCreatorCenter();
                if (btn.dataset.tab === 'player-management') loadOnlinePlayers();
            });
        });

        // redeem mode toggle
        $('redeem-self-btn').addEventListener('click', function () { setRedeemMode('self'); });
        $('redeem-gift-btn').addEventListener('click', function () { setRedeemMode('gift'); });

        // mudança de tipo no create-modal mostra campos condicionais
        $('create-category').addEventListener('change', function () {
            const v = this.value;
            $('create-vehicle-fields').classList.toggle('hidden', v !== 'vehicle');
            $('create-item-fields').classList.toggle('hidden', v !== 'item' && v !== 'tool');
            $('create-weapon-fields').classList.toggle('hidden', v !== 'weapon');
        });
    }


    // ============================================================
    // PURCHASE / REDEEM / TEST-DRIVE
    // ============================================================

    function confirmPurchase() {
        if (!state.selectedItem) return;
        nuiCallback('purchaseItem', { itemId: state.selectedItem.id }).then(function (res) {
            if (res && res.ok) {
                showToast(res.data && res.data.message || L('purchase_successful'), 'success');
                hideOverlay('payment');
            } else {
                showToast(res && res.err || 'Erro', 'error');
            }
        });
    }

    function confirmTestDrive() {
        if (!state.selectedItem) return;
        nuiCallback('testDrive', { itemId: state.selectedItem.id }).then(function (res) {
            if (res && res.ok) {
                showToast(res.data && res.data.message || L('test_drive_started_msg'), 'success');
                hideOverlay('payment');
                onHide(); // fecha a loja — test-drive toma over
            } else {
                showToast(res && res.err || 'Erro', 'error');
            }
        });
    }

    function setRedeemMode(mode) {
        state.redeemMode = mode;
        $('redeem-self-btn').classList.toggle('active', mode === 'self');
        $('redeem-gift-btn').classList.toggle('active', mode === 'gift');
        $('player-id-field').classList.toggle('hidden', mode !== 'gift');
    }

    function confirmRedeem() {
        const key = $('redeem-key-input').value.trim();
        if (!key) { showToast(L('invalid_order_number'), 'error'); return; }
        const payload = { redeemKey: key };
        if (state.redeemMode === 'gift') {
            const tid = $('redeem-player-id').value.trim();
            if (!tid) { showToast(L('target_not_found'), 'error'); return; }
            payload.targetId = tid;
        }
        nuiCallback('redeemCode', payload).then(function (res) {
            if (res && res.ok) {
                showToast(res.data && res.data.message || L('successfully_redeemed', 0), 'success');
                $('redeem-key-input').value = '';
                $('redeem-player-id').value = '';
                hideOverlay('redeem');
            } else {
                showToast(res && res.err || 'Erro', 'error');
            }
        });
    }

    function confirmDealPurchase() {
        if (!state.selectedDeal) return;
        nuiCallback('purchaseDeal', { dealId: state.selectedDeal.id }).then(function (res) {
            if (res && res.ok) {
                showToast(res.data && res.data.message || L('deal_purchased'), 'success');
                hideOverlay('deal-purchase');
            } else {
                showToast(res && res.err || 'Erro', 'error');
            }
        });
    }


    // ============================================================
    // ADMIN — CENTER (stats + transações + top-selling)
    // ============================================================

    function loadAdminCenter() {
        nuiCallback('getAdminStats').then(function (res) {
            if (!res || !res.ok || !res.data) return;
            const d = res.data;
            $('stat-total-packages').textContent = formatNumber(d.totalPackages || 0);
            $('stat-total-sales').textContent = formatNumber(d.totalSales || 0);
            $('stat-coins-24h').textContent = formatNumber(d.coinsSpent24h || 0);
            $('stat-active-players').textContent = formatNumber(d.activePlayers || 0);
        });
        nuiCallback('getRecentTransactions').then(function (res) {
            if (!res || !res.ok || !res.data) return;
            $('recent-transactions').innerHTML = res.data.map(function (t) {
                return '<div class="data-row"><span>' + esc(t.itemName) + '</span><span>' + formatNumber(t.price) + '</span></div>';
            }).join('') || '<div class="data-row"><span>—</span></div>';
        });
        nuiCallback('getTopSelling').then(function (res) {
            if (!res || !res.ok || !res.data) return;
            $('top-selling').innerHTML = res.data.map(function (t) {
                return '<div class="data-row"><span>' + esc(t.name) + '</span><span>' + formatNumber(t.sales) + '</span></div>';
            }).join('') || '<div class="data-row"><span>—</span></div>';
        });
    }


    // ============================================================
    // ADMIN — CREATOR CENTER (CRUD)
    // ============================================================

    function loadCreatorCenter() {
        renderCreatorPackages();
        renderCreatorCategories();
        renderCreatorDeals();
    }

    function renderCreatorPackages() {
        const list = $('creator-packages');
        if (!list) return;
        list.innerHTML = state.shopItems.map(function (i) {
            return '<div class="data-row">' +
                '<span>' + esc(i.name) + ' <small>(' + esc(i.category) + ')</small></span>' +
                '<div class="data-row-actions">' +
                    '<button class="btn btn-ghost" onclick="window.__coinshop.editItem(\'' + esc(i.id) + '\')">' + L('ui_edit') + '</button>' +
                    '<button class="btn btn-danger" onclick="window.__coinshop.deleteItem(\'' + esc(i.id) + '\')">' + L('ui_delete') + '</button>' +
                '</div>' +
            '</div>';
        }).join('') || '<div class="data-row"><span>—</span></div>';
    }

    function renderCreatorCategories() {
        const list = $('creator-categories');
        if (!list) return;
        list.innerHTML = (state.customCategories || []).map(function (c) {
            return '<div class="data-row">' +
                '<span>' + esc(c.name) + '</span>' +
                '<div class="data-row-actions">' +
                    '<button class="btn btn-ghost" onclick="window.__coinshop.editCategory(\'' + esc(c.id) + '\')">' + L('ui_edit') + '</button>' +
                    '<button class="btn btn-danger" onclick="window.__coinshop.deleteCategory(\'' + esc(c.id) + '\')">' + L('ui_delete') + '</button>' +
                '</div>' +
            '</div>';
        }).join('') || '<div class="data-row"><span>—</span></div>';
    }

    function renderCreatorDeals() {
        const list = $('creator-deals');
        if (!list) return;
        list.innerHTML = (state.deals || []).map(function (d) {
            return '<div class="data-row">' +
                '<span>' + esc(d.name) + ' <small>(' + d.remainingSeconds + 's)</small></span>' +
                '<div class="data-row-actions">' +
                    '<button class="btn btn-danger" onclick="window.__coinshop.deleteDeal(\'' + esc(d.id) + '\')">' + L('ui_delete') + '</button>' +
                '</div>' +
            '</div>';
        }).join('') || '<div class="data-row"><span>—</span></div>';
    }

    // ---- CREATE/EDIT ITEM ----

    function showCreateModal(itemId) {
        state.editingItemId = itemId || null;
        $('create-modal-title').textContent = itemId ? L('ui_edit_package_title') : L('ui_create_package_title');
        const item = itemId ? state.shopItems.find(function (i) { return i.id === itemId; }) : null;
        $('create-id').value = item ? item.id : '';
        $('create-name').value = item ? item.name : '';
        $('create-description').value = item ? item.description : '';
        $('create-price').value = item ? item.price : '';
        $('create-category').value = item ? item.category : 'item';
        $('create-spawnName').value = item ? (item.spawnName || '') : '';
        $('create-itemName').value = item ? (item.itemName || '') : '';
        $('create-itemCount').value = item ? (item.itemCount || 1) : 1;
        $('create-weaponName').value = item ? (item.weaponName || '') : '';
        $('create-tags').value = item && item.tags ? item.tags.join(', ') : '';
        $('create-images').value = item && item.images ? item.images.join(', ') : '';
        $('create-trending').checked = !!(item && item.trending);
        // dispara change para mostrar campos condicionais
        $('create-category').dispatchEvent(new Event('change'));
        updateCategoryDropdown();
        $('create-modal').classList.remove('hidden');
    }

    function saveItem() {
        const data = {
            id: state.editingItemId || $('create-id').value.trim() || undefined,
            name: $('create-name').value.trim(),
            description: $('create-description').value.trim(),
            price: parseInt($('create-price').value, 10) || 0,
            category: $('create-category').value,
            spawnName: $('create-spawnName').value.trim(),
            itemName: $('create-itemName').value.trim(),
            itemCount: parseInt($('create-itemCount').value, 10) || 1,
            weaponName: $('create-weaponName').value.trim(),
            tags: $('create-tags').value.split(',').map(function (t) { return t.trim(); }).filter(Boolean),
            images: $('create-images').value.split(',').map(function (t) { return t.trim(); }).filter(Boolean),
            trending: $('create-trending').checked,
            customCategory: $('create-custom-category').value,
        };
        if (!data.name) { showToast(L('item_name_required'), 'error'); return; }
        const action = state.editingItemId ? 'adminEditItem' : 'adminCreateItem';
        nuiCallback(action, data).then(function (res) {
            if (res && res.ok) {
                showToast(res.data && res.data.message || 'OK', 'success');
                $('create-modal').classList.add('hidden');
                // refresh items
                state.shopItems = res.data && res.data.items ? res.data.items : state.shopItems;
                renderCreatorPackages();
                renderAllPages();
            } else {
                showToast(res && res.err || 'Erro', 'error');
            }
        });
    }

    function editItem(id) { showCreateModal(id); }

    function deleteItem(id) {
        $('delete-message').textContent = L('ui_delete_msg').replace('%s', id);
        $('confirm-delete-btn').dataset.targetId = id;
        $('confirm-delete-btn').dataset.deleteKind = 'item';
        $('delete-confirm-modal').classList.remove('hidden');
    }

    function confirmDelete() {
        const btn = $('confirm-delete-btn');
        const id = btn.dataset.targetId;
        const kind = btn.dataset.deleteKind;
        let action;
        if (kind === 'item') action = 'adminDeleteItem';
        else if (kind === 'category') action = 'adminDeleteCategory';
        else if (kind === 'deal') action = 'adminDeleteDeal';
        else return;
        nuiCallback(action, { id: id }).then(function (res) {
            if (res && res.ok) {
                showToast(res.data && res.data.message || 'OK', 'success');
                $('delete-confirm-modal').classList.add('hidden');
                loadCreatorCenter();
            } else {
                showToast(res && res.err || 'Erro', 'error');
            }
        });
    }

    // ---- CATEGORIES ----

    function showCategoryModal(catId) {
        state.editingCategoryId = catId || null;
        const cat = catId ? (state.customCategories || []).find(function (c) { return c.id === catId; }) : null;
        $('category-id').value = cat ? cat.id : '';
        $('category-name').value = cat ? cat.name : '';
        $('category-icon').value = cat ? (cat.icon || '') : '';
        $('category-modal').classList.remove('hidden');
    }

    function saveCategory() {
        const data = {
            id: state.editingCategoryId || $('category-id').value.trim() || undefined,
            name: $('category-name').value.trim(),
            icon: $('category-icon').value.trim(),
        };
        if (!data.name) { showToast(L('category_name_required'), 'error'); return; }
        const action = state.editingCategoryId ? 'adminEditCategory' : 'adminCreateCategory';
        nuiCallback(action, data).then(function (res) {
            if (res && res.ok) {
                showToast(res.data && res.data.message || 'OK', 'success');
                $('category-modal').classList.add('hidden');
                loadCreatorCenter();
            } else {
                showToast(res && res.err || 'Erro', 'error');
            }
        });
    }

    function editCategory(id) { showCategoryModal(id); }

    function deleteCategory(id) {
        $('delete-message').textContent = L('ui_delete_msg').replace('%s', id);
        $('confirm-delete-btn').dataset.targetId = id;
        $('confirm-delete-btn').dataset.deleteKind = 'category';
        $('delete-confirm-modal').classList.remove('hidden');
    }

    // ---- DEALS ----

    function showDealModal() {
        // renderiza o picker de itens
        const picker = $('deal-items-picker');
        picker.innerHTML = state.shopItems.map(function (i) {
            return '<div class="deal-picker-item" data-item-id="' + esc(i.id) + '" onclick="window.__coinshop.toggleDealItem(\'' + esc(i.id) + '\')">' +
                '<img src="' + esc((i.images && i.images[0]) || ICONS.placeholder) + '" />' +
                '<span class="name">' + esc(i.name) + '</span>' +
            '</div>';
        }).join('');
        state.dealSelectedItems = [];
        $('deal-modal').classList.remove('hidden');
    }

    function toggleDealItem(itemId) {
        const idx = state.dealSelectedItems.indexOf(itemId);
        if (idx >= 0) {
            state.dealSelectedItems.splice(idx, 1);
            document.querySelector('.deal-picker-item[data-item-id="' + itemId + '"]').classList.remove('selected');
        } else {
            if (state.dealSelectedItems.length >= 10) {
                showToast(L('deal_items_limit'), 'error');
                return;
            }
            state.dealSelectedItems.push(itemId);
            document.querySelector('.deal-picker-item[data-item-id="' + itemId + '"]').classList.add('selected');
        }
    }

    function saveDeal() {
        const data = {
            name: $('deal-name').value.trim(),
            description: $('deal-description').value.trim(),
            price: parseInt($('deal-price').value, 10) || 0,
            expiresIn: parseInt($('deal-expires').value, 10) || 0,
            image: $('deal-image').value.trim(),
            items: state.dealSelectedItems,
        };
        if (!data.name) { showToast(L('deal_name_required'), 'error'); return; }
        if (!data.expiresIn || data.expiresIn <= 0) { showToast(L('valid_expiry_required'), 'error'); return; }
        if (data.items.length === 0) { showToast(L('deal_items_limit'), 'error'); return; }
        nuiCallback('adminCreateDeal', data).then(function (res) {
            if (res && res.ok) {
                showToast(res.data && res.data.message || 'OK', 'success');
                $('deal-modal').classList.add('hidden');
                loadCreatorCenter();
            } else {
                showToast(res && res.err || 'Erro', 'error');
            }
        });
    }

    function deleteDeal(id) {
        $('delete-message').textContent = L('ui_delete_msg').replace('%s', id);
        $('confirm-delete-btn').dataset.targetId = id;
        $('confirm-delete-btn').dataset.deleteKind = 'deal';
        $('delete-confirm-modal').classList.remove('hidden');
    }

    function confirmClearAll() {
        nuiCallback('adminClearAll').then(function (res) {
            if (res && res.ok) {
                showToast(res.data && res.data.message || 'OK', 'success');
                $('clear-all-modal').classList.add('hidden');
                loadCreatorCenter();
            } else {
                showToast(res && res.err || 'Erro', 'error');
            }
        });
    }


    // ============================================================
    // ADMIN — PLAYER MANAGEMENT
    // ============================================================

    function loadOnlinePlayers() {
        nuiCallback('getOnlinePlayers').then(function (res) {
            if (!res || !res.ok || !Array.isArray(res.data)) return;
            state.adminPlayers = res.data;
            renderPlayersList(state.adminPlayers);
        });
        // histórico de compras
        nuiCallback('getPurchaseHistory').then(function (res) {
            if (!res || !res.ok || !Array.isArray(res.data)) return;
            $('activity-logs').innerHTML = res.data.map(function (t) {
                return '<div class="data-row"><span>' + esc(t.itemName) + ' • Char ' + t.charId + '</span><span>' + formatNumber(t.price) + '</span></div>';
            }).join('') || '<div class="data-row"><span>—</span></div>';
        });
    }

    function renderPlayersList(list) {
        const el = $('admin-players-list');
        if (!el) return;
        el.innerHTML = list.map(function (p) {
            return '<div class="admin-table-row">' +
                '<div>' + p.id + '</div>' +
                '<div>' + esc(p.name) + '</div>' +
                '<div>' + formatNumber(p.coins) + '</div>' +
                '<div class="data-row-actions">' +
                    '<button class="btn btn-ghost" onclick="window.__coinshop.showGiveCoinsModal(' + p.id + ')">' + L('ui_give_coins') + '</button>' +
                    '<button class="btn btn-ghost" onclick="window.__coinshop.showSetCoinsModal(' + p.id + ')">' + L('ui_set_coins') + '</button>' +
                '</div>' +
            '</div>';
        }).join('') || '<div class="admin-table-row"><div colspan="4">—</div></div>';
    }

    function filterPlayers() {
        const q = ($('admin-player-search').value || '').toLowerCase().trim();
        if (!q) { renderPlayersList(state.adminPlayers); return; }
        const filtered = state.adminPlayers.filter(function (p) {
            return String(p.id).indexOf(q) >= 0 || (p.name && p.name.toLowerCase().indexOf(q) >= 0);
        });
        renderPlayersList(filtered);
    }

    function showGiveCoinsModal(playerId) {
        $('give-target-id').value = playerId;
        $('give-amount').value = '';
        $('give-coins-modal').classList.remove('hidden');
    }

    function showSetCoinsModal(playerId) {
        $('set-target-id').value = playerId;
        $('set-amount').value = '';
        $('set-coins-modal').classList.remove('hidden');
    }

    function confirmGiveCoins() {
        const data = {
            targetId: parseInt($('give-target-id').value, 10),
            amount: parseInt($('give-amount').value, 10) || 0,
        };
        if (!data.targetId || data.amount <= 0) { showToast(L('invalid_target_amount'), 'error'); return; }
        nuiCallback('adminGiveCoins', data).then(function (res) {
            if (res && res.ok) {
                showToast(res.data && res.data.message || 'OK', 'success');
                $('give-coins-modal').classList.add('hidden');
                loadOnlinePlayers();
            } else {
                showToast(res && res.err || 'Erro', 'error');
            }
        });
    }

    function confirmSetCoins() {
        const data = {
            targetId: parseInt($('set-target-id').value, 10),
            amount: parseInt($('set-amount').value, 10) || 0,
        };
        if (!data.targetId || data.amount < 0) { showToast(L('invalid_target_amount'), 'error'); return; }
        nuiCallback('adminSetCoins', data).then(function (res) {
            if (res && res.ok) {
                showToast(res.data && res.data.message || 'OK', 'success');
                $('set-coins-modal').classList.add('hidden');
                loadOnlinePlayers();
            } else {
                showToast(res && res.err || 'Erro', 'error');
            }
        });
    }


    // ============================================================
    // ADMIN — CUSTOMIZE UI
    // ============================================================

    function saveSettings() {
        const data = {
            accentColor: $('theme-accentColor').value,
            bgColor: $('theme-bgColor').value,
            textColor: $('theme-textColor').value,
            errorColor: $('theme-errorColor').value,
            cardBorderColor: $('theme-cardBorderColor').value,
            bgImage: $('theme-bgImage').value,
            bgOpacity: $('theme-bgOpacity').value,
            bgBlur: $('theme-bgBlur').value,
            cardBgOpacity: $('theme-cardBgOpacity').value,
            cardBorderRadius: $('theme-cardBorderRadius').value,
            coinIcon: $('theme-coinIcon').value,
        };
        nuiCallback('adminSaveSettings', data).then(function (res) {
            if (res && res.ok) {
                showToast(res.data && res.data.message || L('settings_saved'), 'success');
                // merge local + reaplica
                Object.assign(state.settings, data);
                applyTheme(state.settings);
            } else {
                showToast(res && res.err || 'Erro', 'error');
            }
        });
    }

    function resetSettings() {
        nuiCallback('adminResetSettings').then(function (res) {
            if (res && res.ok) {
                showToast(res.data && res.data.message || L('settings_reset'), 'success');
                // recarrega defaults via init data
                state.settings = {
                    accentColor: '#f3b53a', bgColor: '#0c0a06', textColor: '#d9c19a',
                    errorColor: '#e8513f', cardBorderColor: 'rgba(243,181,58,0.18)',
                    bgImage: '', bgOpacity: '0.50', bgBlur: '3',
                    cardBgOpacity: '0.06', cardBorderRadius: '10',
                    coinIcon: ICONS.coin,
                };
                applyTheme(state.settings);
                populateThemeInputs();
            } else {
                showToast(res && res.err || 'Erro', 'error');
            }
        });
    }

    function populateThemeInputs() {
        const s = state.settings || {};
        $('theme-accentColor').value = s.accentColor || '';
        $('theme-bgColor').value = s.bgColor || '';
        $('theme-textColor').value = s.textColor || '';
        $('theme-errorColor').value = s.errorColor || '';
        $('theme-cardBorderColor').value = s.cardBorderColor || '';
        $('theme-bgImage').value = s.bgImage || '';
        $('theme-bgOpacity').value = s.bgOpacity || '';
        $('theme-bgBlur').value = s.bgBlur || '';
        $('theme-cardBgOpacity').value = s.cardBgOpacity || '';
        $('theme-cardBorderRadius').value = s.cardBorderRadius || '';
        $('theme-coinIcon').value = s.coinIcon || '';
    }


    // ============================================================
    // CUSTOM SELECT (categoria no create-modal)
    // ============================================================

    function toggleCustomSelect(selectId) {
        const wrapper = $(selectId);
        if (!wrapper) return;
        const trigger = wrapper.querySelector('.custom-select-trigger');
        const options = wrapper.querySelector('.custom-select-options');
        const isOpen = options.classList.contains('open');
        $$('.custom-select-options.open').forEach(function (el) {
            el.classList.remove('open');
            el.closest('.custom-select').querySelector('.custom-select-trigger').classList.remove('open');
        });
        if (!isOpen) {
            options.classList.add('open');
            trigger.classList.add('open');
        }
    }

    function selectCustomOption(selectId, value, label) {
        const wrapper = $(selectId);
        if (!wrapper) return;
        const hiddenInput = wrapper.previousElementSibling;
        if (hiddenInput && hiddenInput.tagName === 'INPUT') hiddenInput.value = value;
        wrapper.querySelector('.cs-label').textContent = label;
        wrapper.querySelectorAll('.custom-select-option').forEach(function (opt) {
            opt.classList.toggle('selected', opt.dataset.value === value);
        });
        wrapper.querySelector('.custom-select-options').classList.remove('open');
        wrapper.querySelector('.custom-select-trigger').classList.remove('open');
    }

    function updateCategoryDropdown() {
        const wrapper = $('create-custom-category-select');
        if (!wrapper) return;
        const optionsContainer = wrapper.querySelector('.custom-select-options');
        if (!optionsContainer) return;
        const currentVal = $('create-custom-category').value || 'none';
        let html = '<div class="custom-select-option' + (currentVal === 'none' ? ' selected' : '') + '" data-value="none" onclick="window.__coinshop.selectCustomOption(\'create-custom-category-select\', \'none\', \'' + L('ui_none_default') + '\')">' + L('ui_none_default') + '</div>';
        (state.customCategories || []).forEach(function (cat) {
            const escapedName = cat.name.replace(/'/g, "\\'");
            html += '<div class="custom-select-option' + (currentVal === cat.id ? ' selected' : '') + '" data-value="' + esc(cat.id) + '" onclick="window.__coinshop.selectCustomOption(\'create-custom-category-select\', \'' + esc(cat.id) + '\', \'' + escapedName + '\')">' + esc(cat.name) + '</div>';
        });
        optionsContainer.innerHTML = html;
    }


    // ============================================================
    // COUNTDOWN — ofertas ativas (A-08: só roda quando visível)
    // ============================================================

    function startCountdown() {
        stopCountdown();
        if (!_isVisible) return;
        _countdownInterval = setInterval(tickCountdown, 1000);
        tickCountdown(); // tick imediato
    }

    function stopCountdown() {
        if (_countdownInterval) {
            clearInterval(_countdownInterval);
            _countdownInterval = null;
        }
    }

    function tickCountdown() {
        if (!_isVisible) { stopCountdown(); return; }
        const pad = function (n) { return String(n).padStart(2, '0'); };
        let earliest = Infinity;
        $$('.deal-timer').forEach(function (el) {
            let remaining = parseInt(el.dataset.remaining, 10);
            if (remaining > 0) {
                remaining--;
                el.dataset.remaining = remaining;
                const h = Math.floor(remaining / 3600);
                const m = Math.floor((remaining % 3600) / 60);
                const s = remaining % 60;
                el.textContent = pad(h) + 'H ' + pad(m) + 'M ' + pad(s) + 'S';
                if (remaining < earliest) earliest = remaining;
            } else {
                el.textContent = L('ui_expired');
            }
        });
        const headerTimer = $('deal-timer');
        if (headerTimer) {
            if (earliest === Infinity || isNaN(earliest)) {
                headerTimer.textContent = '00H 00M 00S';
            } else {
                const h = Math.floor(earliest / 3600);
                const m = Math.floor((earliest % 3600) / 60);
                const s = earliest % 60;
                headerTimer.textContent = pad(h) + 'H ' + pad(m) + 'M ' + pad(s) + 'S';
            }
        }
    }

    function renderTrendingBanner() {
        const banner = $('trending-deal-banner');
        if (!banner) return;
        if (!state.deals || state.deals.length === 0) {
            banner.classList.add('hidden');
            return;
        }
        const deal = state.deals[0];
        banner.classList.remove('hidden');
        $('trending-deal-name').textContent = deal.name + ' — ' + formatNumber(deal.price) + ' moedas';
        const timer = $('deal-timer');
        if (timer) timer.dataset.remaining = deal.remainingSeconds || 0;
    }


    // ============================================================
    // TOAST
    // ============================================================

    function showToast(message, kind) {
        const t = $('toast');
        if (!t) return;
        t.textContent = message;
        t.className = 'toast' + (kind ? ' ' + kind : '');
        t.classList.remove('hidden');
        if (_toastTimeout) clearTimeout(_toastTimeout);
        _toastTimeout = setTimeout(function () {
            t.classList.add('hidden');
        }, 4000);
    }


    // ============================================================
    // PUBLIC API — expõe no window para onclick handlers
    // ============================================================

    window.__coinshop = {
        showPage: showPage,
        filterItems: filterItems,
        filterPlayers: filterPlayers,
        openPayment: openPayment,
        openDealPurchase: openDealPurchase,
        showCreateModal: showCreateModal,
        showCategoryModal: showCategoryModal,
        showDealModal: showDealModal,
        editItem: editItem,
        deleteItem: deleteItem,
        editCategory: editCategory,
        deleteCategory: deleteCategory,
        deleteDeal: deleteDeal,
        showGiveCoinsModal: showGiveCoinsModal,
        showSetCoinsModal: showSetCoinsModal,
        toggleDealItem: toggleDealItem,
        toggleCustomSelect: toggleCustomSelect,
        selectCustomOption: selectCustomOption,
        L: L,
    };

    // ============================================================
    // BOOT — onInit
    // ============================================================

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', onInit);
    } else {
        onInit();
    }

    // cleanup ao descarregar a página (não esperado no CEF, mas defensivo)
    window.addEventListener('beforeunload', onDestroy);

})();
