// web/app_ipad/coinshop.js — app CoinShop do iPad (superfície do JOGADOR, #58/#59).
//
// Roda DENTRO da NUI única do iPad, carregado REMOTO de cfx-nui-vhub_coinshop.
// A navbar do iPad (◀ ⌂ ×) fecha — o app NÃO tem botão de fechar nem ESC.
//
// COMUNICAÇÃO = RELAY do iPad (vhub.app.channel('coinshop')):
//   • ch.send(action, data) → ipadRelay(src, action, data) no server do coinshop
//   • ch.on(action, fn)      → push appPush(src, 'coinshop', action, data)
//
// O JS só ENVIA intenção e RENDERIZA push (A-01): preço/saldo/entrega são
// validados no SERVER. SEM setInterval/RAF/polling: render só em push.
// SEM innerHTML com dado do servidor (textContent/el → anti-XSS).
// #59: navegação em ASIDE; view "Comprar Coins" (Pix, contrato estável do stub);
//      render-from-store no mount (rate-limit do open nunca deixa o app vazio).


(() => {
    'use strict';


    // ============================================================
    // HELPERS LOCAIS — autocontidos (o iPad não expõe window.vhubUtils)
    // ============================================================

    // cria elemento + atrs + filhos; texto vira textNode (anti-XSS)
    function el(tag, attrs, children) {
        const node = document.createElement(tag);

        if (attrs && typeof attrs === 'object') {
            for (const k in attrs) {
                if (k === 'class')      node.className = attrs[k];
                else if (k === 'style') Object.assign(node.style, attrs[k]);
                else                    node.setAttribute(k, attrs[k]);
            }
        }

        if (children) {
            const arr = Array.isArray(children) ? children : [children];
            for (const c of arr) {
                if (c == null) continue;
                node.appendChild(typeof c === 'string' ? document.createTextNode(c) : c);
            }
        }

        return node;
    }

    // formata moedas com separador PT-BR
    function fmt(n) {
        return (Number(n) || 0).toLocaleString('pt-BR');
    }

    // formata preço BRL (pacotes Pix)
    function fmtBRL(n) {
        return (Number(n) || 0).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
    }

    // só aceita URL de imagem segura (http/https, data:image, cfx-nui) — nunca executável
    function safeImg(url) {
        if (typeof url !== 'string') return null;
        const u = url.trim();
        if (/^https?:\/\//i.test(u) || /^data:image\//i.test(u) || /^nui:\/\//i.test(u)) return u;
        return null;
    }

    // tempo restante legível a partir de segundos (estático no render — sem timer, A-08)
    function remainTxt(totalSec) {
        const s = Math.max(0, Math.floor(totalSec));
        const h = Math.floor(s / 3600);
        const m = Math.floor((s % 3600) / 60);
        return h > 0 ? `expira em ${h}h ${m}m` : `expira em ${m}m`;
    }

    const CAT_LABEL = { vehicle: 'Veículo', item: 'Item', weapon: 'Arma', tool: 'Ferramenta' };

    const VIEW_TITLE = {
        home:   'Destaques',
        deals:  'Ofertas',
        redeem: 'Resgatar código',
        pix:    'Comprar Coins',
    };


    // ============================================================
    // STATE — relay channel + slice isolado (A-04)
    // ============================================================

    const ch    = vhub.app.channel('coinshop');
    const store = vhub.store('coinshop');

    // leitura defensiva do slice (nunca destruturar undefined)
    function S() { return store.get() || {}; }

    let root = null;      // module root (.mod-coinshop)
    let refs = {};        // map data-el → node
    let chOffs = [];      // off() do relay acumulados (A-07)

    let clickHandler  = null;   // delegação de clique (removida no destroy)
    let searchHandler = null;
    let giftHandler   = null;
    let submitHandler = null;
    let statusTimer   = null;   // timeout do status — limpo em onHide/onDestroy (A-07)

    let modalItem = null;       // item aberto no modal de confirmação
    let dataAt    = 0;          // timestamp do último push 'data' (base do countdown estático)
    let pixBusy   = false;      // trava anti duplo-clique do pacote Pix


    // ============================================================
    // HELPERS DOM
    // ============================================================

    function grabRefs() {
        refs = {};
        root.querySelectorAll('[data-el]').forEach((n) => { refs[n.getAttribute('data-el')] = n; });
    }

    // status inline (ok/err); some sozinho após 5s
    function setStatus(msg, isOk) {
        const s = refs.status;
        if (!s) return;
        s.textContent = msg;
        s.className = 'cs-status ' + (isOk ? 'ok' : 'err');
        s.hidden = false;
        if (statusTimer) clearTimeout(statusTimer);
        statusTimer = setTimeout(() => { s.hidden = true; statusTimer = null; }, 5000);
    }

    function setBusy(busy) {
        if (refs.mBuy)  refs.mBuy.disabled  = busy;
        if (refs.mTest) refs.mTest.disabled = busy;
    }


    // ============================================================
    // RENDER — navegação do aside
    // ============================================================

    function navEntries() {
        const { categories = [], pix = {} } = S();
        const entries = [{ id: 'home', label: 'Destaques' }];
        for (const c of categories) entries.push({ id: c.id, label: c.name });
        entries.push({ id: 'deals',  label: 'Ofertas' });
        entries.push({ id: 'redeem', label: 'Resgatar' });
        if (Array.isArray(pix.packages) && pix.packages.length > 0) {
            entries.push({ id: 'pix', label: 'Comprar Coins' });
        }
        return entries;
    }

    function buildNav() {
        if (!refs.nav) return;
        refs.nav.replaceChildren(...navEntries().map((t) => el('button', {
            type: 'button', class: 'cs-nav-btn', 'data-tab': t.id,
        }, [el('span', { class: 'cs-nav-dot' }), t.label])));
        markActiveTab();
    }

    function markActiveTab() {
        if (!refs.nav) return;
        const active = S().tab || 'home';
        refs.nav.querySelectorAll('.cs-nav-btn').forEach((b) => {
            b.classList.toggle('active', b.getAttribute('data-tab') === active);
        });
    }

    function switchTab(tab) {
        if (!refs.toolbar) return;   // push antes do mount (protocolo anômalo) → no-op seguro
        store.set({ tab });
        markActiveTab();

        const isCatalog = tab !== 'deals' && tab !== 'redeem' && tab !== 'pix';
        if (refs.viewTitle) {
            const entry = navEntries().find((t) => t.id === tab);
            refs.viewTitle.textContent = VIEW_TITLE[tab] || (entry && entry.label) || 'Catálogo';
        }
        refs.search.hidden  = !isCatalog;
        refs.grid.hidden    = !isCatalog;
        refs.deals.hidden   = tab !== 'deals';
        refs.redeem.hidden  = tab !== 'redeem';
        if (refs.pix) refs.pix.hidden = tab !== 'pix';

        if (isCatalog)      renderGrid();
        if (tab === 'deals') renderDeals();
        if (tab === 'pix')   renderPix();
    }


    // ============================================================
    // RENDER — grade de itens
    // ============================================================

    function itemsForTab() {
        const { items = [], categories = [], tab = 'home' } = S();
        if (tab === 'home') {
            // trending primeiro, resto na ordem do catálogo
            return [...items].sort((a, b) => (b.trending === true) - (a.trending === true));
        }
        const cat = categories.find((c) => c.id === tab);
        if (!cat) return [];
        if (cat.type) return items.filter((i) => i.category === cat.type);
        return items.filter((i) => i.customCategory === cat.id);
    }

    function renderGrid() {
        const q = (refs.search.value || '').trim().toLowerCase();
        let list = itemsForTab();
        if (q) list = list.filter((i) => (i.name || '').toLowerCase().includes(q));

        if (!list.length) {
            refs.grid.replaceChildren(el('div', { class: 'cs-empty' }, 'Nenhum item por aqui.'));
            return;
        }

        refs.grid.replaceChildren(...list.map((item) => {
            const media = el('div', { class: 'cs-card-media' });
            const url = safeImg(Array.isArray(item.images) ? item.images[0] : null);
            if (url) {
                const img = el('img', { alt: '' });
                img.src = url;
                img.onerror = () => { img.remove(); media.appendChild(el('span', { class: 'cs-card-fallback' }, '◆')); };
                media.appendChild(img);
            } else {
                media.appendChild(el('span', { class: 'cs-card-fallback' }, '◆'));
            }
            media.appendChild(el('span', {
                class: 'cs-card-badge' + (item.trending ? ' hot' : ''),
            }, item.trending ? 'Destaque' : (CAT_LABEL[item.category] || 'Item')));

            return el('div', { class: 'cs-card', 'data-item': item.id }, [
                media,
                el('div', { class: 'cs-card-name' }, item.name || '—'),
                el('div', { class: 'cs-card-price' }, [
                    el('strong', {}, fmt(item.price) + ' moedas'),
                    el('span', {}, 'ver'),
                ]),
            ]);
        }));
    }


    // ============================================================
    // RENDER — ofertas
    // ============================================================

    function renderDeals() {
        const { deals = [] } = S();
        if (!deals.length) {
            refs.deals.replaceChildren(el('div', { class: 'cs-empty' }, 'Nenhuma oferta ativa no momento.'));
            return;
        }

        const elapsed = Math.floor((Date.now() - dataAt) / 1000);
        refs.deals.replaceChildren(...deals.map((d) => el('div', { class: 'cs-deal' }, [
            el('div', { class: 'cs-deal-info' }, [
                el('h3', {}, d.name || '—'),
                el('p', {}, d.description || ''),
                el('p', { class: 'cs-deal-meta' },
                    `${(d.items || []).length} item(ns) · ${remainTxt((d.remainingSeconds || 0) - elapsed)}`),
            ]),
            el('div', { class: 'cs-deal-side' }, [
                el('strong', {}, fmt(d.price) + ' moedas'),
                el('button', { type: 'button', class: 'cs-btn primary', 'data-deal': d.id }, 'Comprar'),
            ]),
        ])));
    }


    // ============================================================
    // RENDER — Comprar Coins (Pix, #60)
    // ============================================================

    const TIER_LABEL = { 1: 'Bronze', 2: 'Prata', 3: 'Ouro', 4: 'Diamante' };

    function renderPix() {
        if (!refs.pixPacks) return;
        const { pix = {} } = S();
        const packs = Array.isArray(pix.packages) ? pix.packages : [];

        if (!packs.length) {
            refs.pixPacks.replaceChildren(el('div', { class: 'cs-empty' }, 'Nenhum pacote disponível.'));
            return;
        }

        const selected = S().pixSelected;
        refs.pixPacks.replaceChildren(...packs.map((p) => {
            const tier = Number(p.tier) || 0;
            const tierLabel = TIER_LABEL[tier] || null;
            const isPopular = p.popular === true;

            const badges = el('div', { class: 'cs-pack-badges' }, [
                tierLabel ? el('span', { class: 'cs-pack-tier t' + tier }, tierLabel) : null,
                isPopular ? el('span', { class: 'cs-pack-popular' }, '★ Popular') : null,
            ]);

            return el('button', {
                type: 'button',
                class: 'cs-pack' + (selected === p.id ? ' selected' : '') + (isPopular ? ' popular' : '') + ' tier' + tier,
                'data-pack': p.id,
            }, [
                badges,
                el('span', { class: 'cs-pack-name' }, p.name || 'Pacote'),
                el('span', { class: 'cs-pack-coins' }, fmt(p.coins + (Number(p.bonus) || 0)) + ' moedas'),
                (Number(p.bonus) > 0)
                    ? el('span', { class: 'cs-pack-bonus' }, fmt(p.coins) + ' + ' + fmt(p.bonus) + ' bônus')
                    : null,
                el('span', { class: 'cs-pack-price' }, fmtBRL(p.priceBRL)),
            ]);
        }));
    }

    // resultado da cobrança Pix — contrato ESTÁVEL (#60)
    function onPix(res) {
        res = res || {};
        pixBusy = false;
        if (!refs.pixCheckout) return;
        refs.pixCheckout.hidden = false;

        if (res.ok === true) {
            const qr = typeof res.qrcode_base64 === 'string' && res.qrcode_base64
                ? 'data:image/png;base64,' + res.qrcode_base64 : null;
            refs.pixQrImg.hidden      = !qr;
            refs.pixQrFallback.hidden = !!qr;
            if (qr) refs.pixQrImg.src = qr;
            refs.pixMsg.textContent = 'Escaneie o QR Code ou use o copia-e-cola abaixo.';
            refs.pixMsg.hidden = false;

            // expiração — expiresAt é unix timestamp (segundos)
            const expiresAt = Number(res.expiresAt) || 0;
            if (expiresAt > 0 && refs.pixExpire) {
                const secLeft = expiresAt - Math.floor(Date.now() / 1000);
                refs.pixExpire.textContent = remainTxt(secLeft);
                refs.pixExpire.hidden = false;
            }

            const copy = typeof res.copiaECola === 'string' ? res.copiaECola : '';
            if (refs.pixCopyRow) refs.pixCopyRow.hidden = !copy;
            if (copy && refs.pixCopy) refs.pixCopy.value = copy;
        } else {
            refs.pixQrImg.hidden      = true;
            refs.pixQrFallback.hidden = false;
            if (refs.pixQrTxt) {
                refs.pixQrTxt.textContent = res.code === 'pix_disabled'
                    ? 'Em breve: o QR Code Pix aparecerá aqui'
                    : 'O QR Code Pix aparecerá aqui';
            }
            refs.pixMsg.textContent = res.message || 'Pix indisponível no momento.';
            refs.pixMsg.hidden = false;
            if (refs.pixExpire) refs.pixExpire.hidden = true;
            if (refs.pixCopyRow) refs.pixCopyRow.hidden = true;
        }
    }


    // ============================================================
    // MODAL — confirmação de compra / test-drive
    // ============================================================

    function openModal(item) {
        modalItem = item;
        refs.mName.textContent  = item.name || '—';
        refs.mDesc.textContent  = item.description || '';
        refs.mPrice.textContent = fmt(item.price) + ' moedas';
        refs.mTest.hidden = item.category !== 'vehicle';

        const url = safeImg(Array.isArray(item.images) ? item.images[0] : null);
        refs.mImg.hidden      = !url;
        refs.mFallback.hidden = !!url;
        if (url) refs.mImg.src = url;

        setBusy(false);
        refs.overlay.hidden = false;
    }

    function closeModal() {
        modalItem = null;
        refs.overlay.hidden = true;
    }


    // ============================================================
    // PUSH HANDLERS — registrados no onInit (A-07)
    // ============================================================

    // snapshot completo da loja (abertura / refresh)
    function onData(data) {
        data = data || {};
        dataAt = Date.now();
        store.set({
            items:      Array.isArray(data.items) ? data.items : [],
            categories: Array.isArray(data.categories) ? data.categories : [],
            deals:      Array.isArray(data.deals) ? data.deals : [],
            coins:      Number(data.coins) || 0,
            pix:        (data.pix && typeof data.pix === 'object') ? data.pix : { enabled: false, packages: [] },
            playerName: data.playerName || '—',
        });

        renderFromStore();
    }

    // re-renderiza tudo a partir do slice (usado no push 'data' E no mount — #59)
    function renderFromStore() {
        if (!root || !refs.nav) return;
        const s = S();
        if (refs.player) refs.player.textContent = s.playerName || '—';
        if (refs.coins)  refs.coins.textContent  = fmt(s.coins);
        buildNav();
        switchTab(s.tab || 'home');
    }

    // resultado de ação (open / buy_item / buy_deal / redeem / testdrive)
    function onResult(res) {
        res = res || {};
        setBusy(false);
        setStatus(res.message || (res.ok ? 'Feito!' : 'Falhou.'), res.ok === true);
        if (res.ok && (res.action === 'buy_item' || res.action === 'buy_deal')) closeModal();
        if (res.action === 'buy_deal' && !refs.deals.hidden) renderDeals();   // reabilita o botão
        if (res.ok && res.action === 'redeem' && refs.redeemKey) refs.redeemKey.value = '';
    }

    // saldo atualizado (compra/resgate/admin — ponto único server-side, #59)
    function onCoins(data) {
        const coins = Number(data && data.coins) || 0;
        store.set({ coins });
        if (refs.coins) refs.coins.textContent = fmt(coins);
    }

    // sem personagem carregado — o server recusou
    function onDenied() {
        setStatus('Personagem não carregado — entre na cidade primeiro.', false);
    }


    // ============================================================
    // INTERAÇÃO — delegação de clique + formulário de resgate
    // ============================================================

    function onClick(ev) {
        const tabBtn = ev.target.closest('[data-tab]');
        if (tabBtn) { switchTab(tabBtn.getAttribute('data-tab')); return; }

        const card = ev.target.closest('[data-item]');
        if (card) {
            const { items = [] } = S();
            const item = items.find((i) => i.id === card.getAttribute('data-item'));
            if (item) openModal(item);
            return;
        }

        const dealBtn = ev.target.closest('[data-deal]');
        if (dealBtn) {
            dealBtn.disabled = true;
            ch.send('buy_deal', { dealId: dealBtn.getAttribute('data-deal') });
            return;
        }

        const packBtn = ev.target.closest('[data-pack]');
        if (packBtn && !pixBusy) {
            pixBusy = true;
            store.set({ pixSelected: packBtn.getAttribute('data-pack') });
            renderPix();
            ch.send('pix_create', { packageId: packBtn.getAttribute('data-pack') });
            return;
        }

        const action = ev.target.closest('[data-action]');
        if (!action) return;
        switch (action.getAttribute('data-action')) {
            case 'modal-close': closeModal(); break;
            case 'modal-buy':
                if (modalItem) { setBusy(true); ch.send('buy_item', { itemId: modalItem.id }); }
                break;
            case 'modal-test':
                if (modalItem) { setBusy(true); ch.send('testdrive', { itemId: modalItem.id }); }
                break;
            case 'pix-copy': {
                const inp = refs.pixCopy;
                if (!inp || !inp.value) break;
                try { navigator.clipboard.writeText(inp.value); } catch (_) {
                    inp.select();
                    document.execCommand('copy');
                }
                const btn = refs.pixCopyBtn;
                if (btn) { btn.textContent = 'Copiado!'; setTimeout(() => { btn.textContent = 'Copiar'; }, 2000); }
                break;
            }
        }
    }

    function onRedeemSubmit(ev) {
        ev.preventDefault();
        const redeemKey = (refs.redeemKey.value || '').trim();
        if (!redeemKey) { setStatus('Informe o número do pedido.', false); return; }
        const gift = refs.giftToggle.checked ? (refs.giftId.value || '').trim() : '';
        ch.send('redeem', { redeemKey, targetId: gift });
    }


    // ============================================================
    // LIFECYCLE (A-02)
    // ============================================================

    vhub.createModule('coinshop', {

        onInit() {
            chOffs.push(ch.on('data',   onData));
            chOffs.push(ch.on('result', onResult));
            chOffs.push(ch.on('coins',  onCoins));
            chOffs.push(ch.on('pix',    onPix));
            chOffs.push(ch.on('denied', onDenied));
        },

        onMount(el0) {
            root = el0;
            grabRefs();

            clickHandler = onClick;
            root.addEventListener('click', clickHandler);

            searchHandler = () => renderGrid();
            refs.search.addEventListener('input', searchHandler);

            giftHandler = () => { refs.giftId.hidden = !refs.giftToggle.checked; };
            refs.giftToggle.addEventListener('change', giftHandler);

            submitHandler = onRedeemSubmit;
            refs.redeem.addEventListener('submit', submitHandler);

            // se o slice já tem dados (reabertura dentro do rate do server), renderiza
            // na hora — o push 'data' atualiza depois se vier (#59)
            if (Array.isArray(S().items) && S().items.length) renderFromStore();
        },

        onShow() {
            // renderiza imediatamente se já há dados (evita nav vazia durante o round-trip)
            if (Array.isArray(S().items)) renderFromStore();
            ch.send('open');   // pede snapshot atualizado ao server
        },

        onHide() {
            if (statusTimer) { clearTimeout(statusTimer); statusTimer = null; }
        },

        onDestroy() {
            for (const off of chOffs) { try { off(); } catch (_) {} }
            chOffs = [];
            if (statusTimer) { clearTimeout(statusTimer); statusTimer = null; }
            if (root && clickHandler) root.removeEventListener('click', clickHandler);
            if (refs.search && searchHandler)     refs.search.removeEventListener('input', searchHandler);
            if (refs.giftToggle && giftHandler)   refs.giftToggle.removeEventListener('change', giftHandler);
            if (refs.redeem && submitHandler)     refs.redeem.removeEventListener('submit', submitHandler);
            clickHandler = searchHandler = giftHandler = submitHandler = null;
            modalItem = null;
            pixBusy = false;
            refs = {};
            root = null;
        },

    });
})();
