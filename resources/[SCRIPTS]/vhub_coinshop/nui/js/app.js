/* ============================================================
   vhub_coinshop — nui/js/app.js (PAINEL ADMIN /coinshop, decisão #59)
   Lifecycle A-02: onInit / onShow / onHide / onDestroy
   A-07: cleanup obrigatório (listener/timeout; ZERO interval/RAF)
   A-08: idle 0ms com NUI fechada — sem timers; countdown de oferta é
         texto ESTÁTICO calculado no render
   A-10: sem CDN, sem fetch externo, ícones SVG inline
   Anti-XSS: DOM construído com el()/textContent — NUNCA innerHTML
   com dado vindo do servidor (a versão antiga usava e quebrava com
   aspas em nomes; classe de bug eliminada).
   ============================================================ */

(function () {
    'use strict';

    // ============================================================
    // STATE — slice único do painel (A-04)
    // ============================================================

    var state = {
        items: [],
        categories: [],
        deals: [],
        players: [],
        history: [],
        codes: [],
        settings: {},
        pix: { enabled: false, packages: [] },
        playerName: '—',
        coins: 0,
        view: 'dash',
        dataAt: 0,              // base do countdown estático das ofertas
        // edição em curso
        editingItemId: null,
        editingCatId: null,
        editingDealId: null,
        dealSelected: [],
        coinsMode: 'give',      // give | set
        coinsTarget: null,      // { id, name }
        confirm: null,          // { kind: 'item'|'cat'|'deal'|'code'|'clearAll', id }
        codesLoaded: false,
    };

    // handles para cleanup (A-07)
    var _messageHandler = null;
    var _keydownHandler = null;
    var _clickHandler = null;
    var _toastTimeout = null;

    var VIEW_TITLE = {
        dash: 'Dashboard', catalog: 'Catálogo', cats: 'Categorias',
        deals: 'Ofertas & Combos', players: 'Jogadores', codes: 'Códigos',
        pix: 'Pix', import: 'Importar Itens', theme: 'Aparência',
    };

    var CAT_LABEL = { vehicle: 'Veículo', item: 'Item', weapon: 'Arma', tool: 'Ferramenta' };


    // ============================================================
    // HELPERS
    // ============================================================

    function $(sel) { return document.querySelector(sel); }
    function ref(name) { return document.querySelector('[data-el="' + name + '"]'); }

    // cria elemento + atrs + filhos; texto vira textNode (anti-XSS)
    function el(tag, attrs, children) {
        var node = document.createElement(tag);
        if (attrs) {
            for (var k in attrs) {
                if (k === 'class') node.className = attrs[k];
                else node.setAttribute(k, attrs[k]);
            }
        }
        if (children != null) {
            var arr = Array.isArray(children) ? children : [children];
            for (var i = 0; i < arr.length; i++) {
                var c = arr[i];
                if (c == null) continue;
                node.appendChild(typeof c === 'string' ? document.createTextNode(c) : c);
            }
        }
        return node;
    }

    function fmt(n) { return (parseInt(n, 10) || 0).toLocaleString('pt-BR'); }

    function fmtBRL(n) {
        return (Number(n) || 0).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
    }

    // tempo restante legível (estático no render — sem timer, A-08)
    function remainTxt(totalSec) {
        var s = Math.max(0, Math.floor(totalSec));
        if (s === 0) return 'expirada';
        var h = Math.floor(s / 3600);
        var m = Math.floor((s % 3600) / 60);
        return h > 0 ? 'expira em ' + h + 'h ' + m + 'm' : 'expira em ' + m + 'm';
    }

    // POST para o resource (callback NUI); sempre resolve {ok, data?, err?}
    function nuiPost(action, data) {
        return fetch('https://vhub_coinshop/' + action, {
            method: 'POST',
            body: JSON.stringify(data || {}),
        }).then(function (r) { return r.json(); }).catch(function () {
            return { ok: false, err: 'network_error' };
        });
    }

    function toast(message, kind) {
        var t = ref('toast');
        if (!t) return;
        t.textContent = message;
        t.className = 'csa-toast' + (kind ? ' ' + kind : '');
        if (_toastTimeout) clearTimeout(_toastTimeout);
        _toastTimeout = setTimeout(function () { t.classList.add('hidden'); _toastTimeout = null; }, 4000);
    }

    // aplica listas frescas devolvidas pelo server pós-CRUD (mata o stale — #59)
    function absorbLists(d) {
        if (!d) return;
        if (Array.isArray(d.items)) state.items = d.items;
        if (Array.isArray(d.categories)) state.categories = d.categories;
        if (Array.isArray(d.deals)) { state.deals = d.deals; state.dataAt = Date.now(); }
        if (Array.isArray(d.codes)) state.codes = d.codes;
    }


    // ============================================================
    // NAVEGAÇÃO ENTRE VIEWS
    // ============================================================

    function showView(view) {
        state.view = view;
        var title = ref('viewTitle');
        if (title) title.textContent = VIEW_TITLE[view] || view;

        document.querySelectorAll('.csa-nav-btn').forEach(function (b) {
            b.classList.toggle('active', b.getAttribute('data-view') === view);
        });
        document.querySelectorAll('[data-view-panel]').forEach(function (p) {
            p.hidden = p.getAttribute('data-view-panel') !== view;
        });

        if (view === 'dash') loadDashboard();
        if (view === 'catalog') renderCatalog();
        if (view === 'cats') renderCats();
        if (view === 'deals') renderDeals();
        if (view === 'players') loadPlayers();
        if (view === 'codes') loadCodes();
        if (view === 'pix') renderPix();
        if (view === 'import') initImport();
        if (view === 'theme') populateTheme();
    }


    // ============================================================
    // DASHBOARD
    // ============================================================

    function loadDashboard() {
        nuiPost('getAdminStats').then(function (res) {
            if (!res || !res.ok || !res.data) return;
            var d = res.data;
            ref('statPackages').textContent = fmt(d.totalPackages);
            ref('statSales').textContent = fmt(d.totalSales);
            ref('statCoins24h').textContent = fmt(d.coinsSpent24h);
            ref('statPlayers').textContent = fmt(d.activePlayers);
        });
        nuiPost('getRecentTransactions').then(function (res) {
            if (!res || !res.ok || !Array.isArray(res.data)) return;
            renderSimpleRows(ref('recentTx'), res.data, function (t) {
                return [el('span', { class: 'grow' }, String(t.itemName || t.itemId || '—')),
                        el('span', { class: 'num' }, fmt(t.price))];
            }, 'Nenhuma transação ainda.');
        });
        nuiPost('getTopSelling').then(function (res) {
            if (!res || !res.ok || !Array.isArray(res.data)) return;
            renderSimpleRows(ref('topSelling'), res.data, function (t) {
                return [el('span', { class: 'grow' }, String(t.name || '—')),
                        el('span', { class: 'num' }, fmt(t.sales) + 'x')];
            }, 'Nenhuma venda ainda.');
        });
    }

    function renderSimpleRows(container, list, rowFn, emptyMsg) {
        if (!container) return;
        if (!list.length) {
            container.replaceChildren(el('div', { class: 'csa-empty' }, emptyMsg));
            return;
        }
        container.replaceChildren.apply(container, list.map(function (item) {
            return el('div', { class: 'csa-row' }, rowFn(item));
        }));
    }


    // ============================================================
    // CATÁLOGO — lista + CRUD de itens
    // ============================================================

    function renderCatalog() {
        var listEl = ref('catalogList');
        if (!listEl) return;
        var q = (ref('catalogSearch').value || '').trim().toLowerCase();
        var list = state.items;
        if (q) {
            list = list.filter(function (i) {
                return (i.name || '').toLowerCase().indexOf(q) >= 0 ||
                       (i.category || '').toLowerCase().indexOf(q) >= 0 ||
                       (Array.isArray(i.tags) && i.tags.some(function (t) { return String(t).toLowerCase().indexOf(q) >= 0; }));
            });
        }
        if (!list.length) {
            listEl.replaceChildren(el('div', { class: 'csa-empty' }, 'Nenhum item no catálogo.'));
            return;
        }
        listEl.replaceChildren.apply(listEl, list.map(function (i) {
            return el('div', { class: 'csa-row' }, [
                el('span', { class: 'csa-badge' + (i.trending ? ' gold' : '') }, CAT_LABEL[i.category] || 'Item'),
                el('span', { class: 'grow' }, [
                    String(i.name || '—') + ' ',
                    el('small', {}, '(' + String(i.id) + ')'),
                ]),
                el('span', { class: 'num' }, fmt(i.price) + ' moedas'),
                el('button', { class: 'csa-btn mini', 'data-act': 'editItem', 'data-id': i.id }, 'Editar'),
                el('button', { class: 'csa-btn mini danger ghost', 'data-act': 'delItem', 'data-id': i.id }, 'Excluir'),
            ]);
        }));
    }

    function itemModalField(name) { return $('[data-modal="item"] [data-f="' + name + '"]'); }

    function applyCategoryConditionals() {
        var cat = itemModalField('category').value;
        document.querySelectorAll('[data-modal="item"] [data-cond]').forEach(function (f) {
            f.hidden = f.getAttribute('data-cond').split(' ').indexOf(cat) < 0;
        });
    }

    function openItemModal(itemId) {
        state.editingItemId = itemId || null;
        var item = itemId ? state.items.find(function (i) { return i.id === itemId; }) : null;
        ref('itemModalTitle').textContent = item ? 'Editar item' : 'Novo item';

        itemModalField('id').value = item ? item.id : '';
        itemModalField('id').disabled = !!item;
        itemModalField('name').value = item ? (item.name || '') : '';
        itemModalField('description').value = item ? (item.description || '') : '';
        itemModalField('price').value = item ? (item.price || 0) : '';
        itemModalField('category').value = item ? (item.category || 'item') : 'item';
        itemModalField('spawnName').value = item ? (item.spawnName || '') : '';
        itemModalField('itemName').value = item ? (item.itemName || '') : '';
        itemModalField('itemCount').value = item ? (item.itemCount || 1) : 1;
        itemModalField('weaponName').value = item ? (item.weaponName || '') : '';
        itemModalField('tags').value = item && Array.isArray(item.tags) ? item.tags.join(', ') : '';
        itemModalField('images').value = item && Array.isArray(item.images) ? item.images.join(', ') : '';
        itemModalField('trending').checked = !!(item && item.trending);

        // categorias custom no select
        var sel = itemModalField('customCategory');
        sel.replaceChildren(el('option', { value: '' }, 'Nenhuma'));
        state.categories.forEach(function (c) {
            if (c.type) return; // padrão não é custom
            var opt = el('option', { value: c.id }, String(c.name));
            sel.appendChild(opt);
        });
        sel.value = (item && item.customCategory) || '';

        applyCategoryConditionals();
        updateItemImgPreview();
        openModal('item');
    }

    // atualiza preview das imagens do modal de item (sem innerHTML — anti-XSS via src)
    function updateItemImgPreview() {
        var preview = ref('itemImgPreview');
        if (!preview) return;
        var raw = itemModalField('images').value || '';
        var urls = raw.split(',').map(function (u) { return u.trim(); }).filter(Boolean);
        if (!urls.length) { preview.hidden = true; preview.replaceChildren(); return; }
        preview.replaceChildren.apply(preview, urls.map(function (u) {
            var img = document.createElement('img');
            img.alt = '';
            img.src = u;
            img.onerror = function () { img.style.opacity = '0.3'; };
            return img;
        }));
        preview.hidden = false;
    }

    function saveItem() {
        var data = {
            id: state.editingItemId || itemModalField('id').value.trim() || undefined,
            name: itemModalField('name').value.trim(),
            description: itemModalField('description').value.trim(),
            price: parseInt(itemModalField('price').value, 10) || 0,
            category: itemModalField('category').value,
            spawnName: itemModalField('spawnName').value.trim(),
            itemName: itemModalField('itemName').value.trim(),
            itemCount: parseInt(itemModalField('itemCount').value, 10) || 1,
            weaponName: itemModalField('weaponName').value.trim(),
            tags: itemModalField('tags').value.split(',').map(function (t) { return t.trim(); }).filter(Boolean),
            images: itemModalField('images').value.split(',').map(function (t) { return t.trim(); }).filter(Boolean),
            trending: itemModalField('trending').checked,
            customCategory: itemModalField('customCategory').value || '',
        };
        if (!data.name) { toast('Nome do item é obrigatório', 'error'); return; }

        nuiPost(state.editingItemId ? 'adminEditItem' : 'adminCreateItem', data).then(function (res) {
            if (res && res.ok) {
                absorbLists(res.data);
                toast((res.data && res.data.message) || 'Item salvo', 'success');
                closeModals();
                renderCatalog();
            } else {
                toast((res && res.err) || 'Erro ao salvar', 'error');
            }
        });
    }


    // ============================================================
    // CATEGORIAS
    // ============================================================

    function renderCats() {
        var listEl = ref('catsList');
        if (!listEl) return;
        if (!state.categories.length) {
            listEl.replaceChildren(el('div', { class: 'csa-empty' }, 'Nenhuma categoria.'));
            return;
        }
        listEl.replaceChildren.apply(listEl, state.categories.map(function (c) {
            var row = [
                el('span', { class: 'csa-badge' + (c.type ? '' : ' gold') }, c.type ? 'Padrão' : 'Custom'),
                el('span', { class: 'grow' }, String(c.name || c.id)),
            ];
            if (!c.type) { // só custom edita/apaga
                row.push(el('button', { class: 'csa-btn mini', 'data-act': 'editCat', 'data-id': c.id }, 'Editar'));
                row.push(el('button', { class: 'csa-btn mini danger ghost', 'data-act': 'delCat', 'data-id': c.id }, 'Excluir'));
            }
            return el('div', { class: 'csa-row' }, row);
        }));
    }

    function catField(name) { return $('[data-modal="cat"] [data-f="' + name + '"]'); }

    function openCatModal(catId) {
        state.editingCatId = catId || null;
        var cat = catId ? state.categories.find(function (c) { return c.id === catId; }) : null;
        ref('catModalTitle').textContent = cat ? 'Editar categoria' : 'Nova categoria';
        catField('catName').value = cat ? (cat.name || '') : '';
        catField('catIcon').value = cat ? (cat.icon || '') : '';
        openModal('cat');
    }

    function saveCat() {
        var data = {
            id: state.editingCatId || undefined,
            name: catField('catName').value.trim(),
            icon: catField('catIcon').value.trim(),
        };
        if (!data.name) { toast('Nome da categoria é obrigatório', 'error'); return; }
        nuiPost(state.editingCatId ? 'adminEditCategory' : 'adminCreateCategory', data).then(function (res) {
            if (res && res.ok) {
                absorbLists(res.data);
                toast((res.data && res.data.message) || 'Categoria salva', 'success');
                closeModals();
                renderCats();
            } else {
                toast((res && res.err) || 'Erro ao salvar', 'error');
            }
        });
    }


    // ============================================================
    // OFERTAS & COMBOS
    // ============================================================

    function renderDeals() {
        var listEl = ref('dealsList');
        if (!listEl) return;
        if (!state.deals.length) {
            listEl.replaceChildren(el('div', { class: 'csa-empty' }, 'Nenhuma oferta ativa.'));
            return;
        }
        var elapsed = Math.floor((Date.now() - state.dataAt) / 1000);
        listEl.replaceChildren.apply(listEl, state.deals.map(function (d) {
            return el('div', { class: 'csa-row' }, [
                el('span', { class: 'csa-badge gold' }, 'Combo'),
                el('span', { class: 'grow' }, [
                    String(d.name || '—') + ' ',
                    el('small', {}, (d.items || []).length + ' item(ns) · ' + remainTxt((d.remainingSeconds || 0) - elapsed)),
                ]),
                el('span', { class: 'num' }, fmt(d.price) + ' moedas'),
                el('button', { class: 'csa-btn mini', 'data-act': 'editDeal', 'data-id': d.id }, 'Editar'),
                el('button', { class: 'csa-btn mini danger ghost', 'data-act': 'delDeal', 'data-id': d.id }, 'Excluir'),
            ]);
        }));
    }

    function dealField(name) { return $('[data-modal="deal"] [data-f="' + name + '"]'); }

    function renderDealPicker() {
        var picker = ref('dealPicker');
        var countEl = ref('dealPickerCount');
        if (countEl) countEl.textContent = String(state.dealSelected.length);

        var q = (ref('dealPickerSearch') ? ref('dealPickerSearch').value || '' : '').trim().toLowerCase();
        var list = state.items;
        if (q) list = list.filter(function (i) { return (i.name || '').toLowerCase().indexOf(q) >= 0; });

        if (!list.length) {
            picker.replaceChildren(el('div', { class: 'csa-picker-empty' },
                state.items.length ? 'Nenhum item corresponde à busca.' : 'Catálogo vazio — adicione itens primeiro.'));
            return;
        }

        picker.replaceChildren.apply(picker, list.map(function (i) {
            var sel = state.dealSelected.indexOf(i.id) >= 0;
            return el('button', {
                type: 'button',
                class: 'csa-pick' + (sel ? ' selected' : ''),
                'data-pick': i.id,
                title: i.name || i.id,
            }, [
                el('span', {}, CAT_LABEL[i.category] ? CAT_LABEL[i.category][0] : '◆'),
                String(i.name || i.id),
            ]);
        }));
    }

    function openDealModal(dealId) {
        state.editingDealId = dealId || null;
        var deal = dealId ? state.deals.find(function (d) { return d.id === dealId; }) : null;
        ref('dealModalTitle').textContent = deal ? 'Editar oferta' : 'Nova oferta';
        dealField('dealName').value = deal ? (deal.name || '') : '';
        dealField('dealDesc').value = deal ? (deal.description || '') : '';
        dealField('dealPrice').value = deal ? (deal.price || 0) : '';
        dealField('dealHours').value = '';
        dealField('dealImage').value = deal ? (deal.image || '') : '';
        state.dealSelected = deal ? (deal.items || []).map(function (i) { return i.id; }) : [];
        var search = ref('dealPickerSearch');
        if (search) search.value = '';
        renderDealPicker();
        openModal('deal');
    }

    function saveDeal() {
        var hours = parseInt(dealField('dealHours').value, 10) || 0;
        var data = {
            id: state.editingDealId || undefined,
            name: dealField('dealName').value.trim(),
            description: dealField('dealDesc').value.trim(),
            price: parseInt(dealField('dealPrice').value, 10) || 0,
            image: dealField('dealImage').value.trim(),
            items: state.dealSelected.slice(),
        };
        if (hours > 0) data.expiresIn = hours * 3600;
        if (!data.name) { toast('Nome da oferta é obrigatório', 'error'); return; }
        if (!state.editingDealId && !data.expiresIn) { toast('Informe o prazo de expiração em horas', 'error'); return; }
        if (!data.items.length || data.items.length > 10) { toast('Selecione 1 a 10 itens', 'error'); return; }

        nuiPost(state.editingDealId ? 'adminEditDeal' : 'adminCreateDeal', data).then(function (res) {
            if (res && res.ok) {
                absorbLists(res.data);
                toast((res.data && res.data.message) || 'Oferta salva', 'success');
                closeModals();
                renderDeals();
            } else {
                toast((res && res.err) || 'Erro ao salvar', 'error');
            }
        });
    }


    // ============================================================
    // JOGADORES — lista online + give/set + histórico
    // ============================================================

    function loadPlayers() {
        nuiPost('getOnlinePlayers').then(function (res) {
            if (!res || !res.ok || !Array.isArray(res.data)) return;
            state.players = res.data;
            renderPlayers();
        });
        nuiPost('getPurchaseHistory').then(function (res) {
            if (!res || !res.ok || !Array.isArray(res.data)) return;
            state.history = res.data;
            renderSimpleRows(ref('historyList'), state.history, function (t) {
                return [el('span', { class: 'grow' }, String(t.itemName || '—') + ' · char ' + String(t.charId)),
                        el('span', { class: 'num' }, fmt(t.price))];
            }, 'Nenhuma compra registrada.');
        });
    }

    function renderPlayers() {
        var listEl = ref('playersList');
        if (!listEl) return;
        var q = (ref('playerSearch').value || '').trim().toLowerCase();
        var list = state.players;
        if (q) {
            list = list.filter(function (p) {
                return String(p.id).indexOf(q) >= 0 || (p.name || '').toLowerCase().indexOf(q) >= 0;
            });
        }
        if (!list.length) {
            listEl.replaceChildren(el('div', { class: 'csa-empty' }, 'Nenhum jogador online.'));
            return;
        }
        listEl.replaceChildren.apply(listEl, list.map(function (p) {
            return el('div', { class: 'csa-row player' }, [
                el('span', {}, String(p.id)),
                el('span', { class: 'grow' }, String(p.name || '—')),
                el('span', { class: 'num' }, fmt(p.coins)),
                el('span', { class: 'csa-row-actions' }, [
                    el('button', { class: 'csa-btn mini', 'data-act': 'giveCoins', 'data-id': p.id }, 'Dar'),
                    el('button', { class: 'csa-btn mini', 'data-act': 'setCoins', 'data-id': p.id }, 'Definir'),
                ]),
            ]);
        }));
    }

    function openCoinsModal(mode, playerId) {
        var p = state.players.find(function (x) { return x.id === playerId; });
        state.coinsMode = mode;
        state.coinsTarget = { id: playerId, name: p ? p.name : ('ID ' + playerId) };
        ref('coinsModalTitle').textContent = mode === 'give' ? 'Dar moedas' : 'Definir moedas';
        ref('coinsModalTarget').textContent =
            'Jogador ' + state.coinsTarget.name + ' (ID ' + playerId + ')' +
            (p ? ' — saldo atual: ' + fmt(p.coins) : '');
        $('[data-modal="coins"] [data-f="coinsAmount"]').value = '';
        openModal('coins');
    }

    function confirmCoins() {
        if (!state.coinsTarget) return;
        var amount = parseInt($('[data-modal="coins"] [data-f="coinsAmount"]').value, 10);
        if (isNaN(amount) || amount < 0 || (state.coinsMode === 'give' && amount <= 0)) {
            toast('Quantidade inválida', 'error'); return;
        }
        var action = state.coinsMode === 'give' ? 'adminGiveCoins' : 'adminSetCoins';
        nuiPost(action, { targetId: state.coinsTarget.id, amount: amount }).then(function (res) {
            if (res && res.ok) {
                toast((res.data && res.data.message) || 'Feito', 'success');
                closeModals();
                loadPlayers();
            } else {
                toast((res && res.err) || 'Erro', 'error');
            }
        });
    }


    // ============================================================
    // CÓDIGOS DE RESGATE
    // ============================================================

    function loadCodes() {
        nuiPost('adminListCodes').then(function (res) {
            if (!res || !res.ok || !res.data) return;
            state.codes = res.data.codes || [];
            renderCodes();
        });
    }

    function renderCodes() {
        var listEl = ref('codesList');
        if (!listEl) return;
        if (!state.codes.length) {
            listEl.replaceChildren(el('div', { class: 'csa-empty' }, 'Nenhum código criado ainda.'));
            return;
        }
        listEl.replaceChildren.apply(listEl, state.codes.map(function (c) {
            var pending = c.status === 'pending';
            var row = [
                el('span', { class: 'csa-badge ' + (pending ? 'green' : 'red') }, pending ? 'Pendente' : 'Resgatado'),
                el('span', { class: 'grow mono' }, String(c.key)),
                el('span', { class: 'num' }, fmt(c.coins) + ' moedas'),
            ];
            if (pending) {
                row.push(el('button', { class: 'csa-btn mini danger ghost', 'data-act': 'delCode', 'data-id': c.key }, 'Apagar'));
            }
            return el('div', { class: 'csa-row' }, row);
        }));
    }

    function createCode(ev) {
        ev.preventDefault();
        var coins = parseInt(ref('codeCoins').value, 10);
        if (isNaN(coins) || coins <= 0) { toast('Quantidade inválida', 'error'); return; }
        nuiPost('adminCreateCode', { coins: coins }).then(function (res) {
            if (res && res.ok && res.data) {
                state.codes = res.data.codes || state.codes;
                ref('keyOut').value = res.data.key || '';
                ref('keyBox').hidden = !res.data.key;
                ref('codeCoins').value = '';
                renderCodes();
                toast('Código gerado — copie agora', 'success');
            } else {
                toast((res && res.err) || 'Erro ao gerar código', 'error');
            }
        });
    }

    function copyKey() {
        var input = ref('keyOut');
        if (!input || !input.value) return;
        input.select();
        input.setSelectionRange(0, 99999);
        try { document.execCommand('copy'); toast('Copiado!', 'success'); }
        catch (e) { toast('Selecione e copie com Ctrl+C', 'error'); }
    }


    // ============================================================
    // IMPORTAR — bulk import do inventário + catálogo de veículos
    // ============================================================

    var CAT_LABEL_IMP = { vehicle: 'Veículo', item: 'Item', weapon: 'Arma', tool: 'Ferramenta' };

    function getImportSources() {
        return {
            inventory: !!document.querySelector('[data-imp="inventory"]') &&
                       document.querySelector('[data-imp="inventory"]').checked,
            conce:     !!document.querySelector('[data-imp="conce"]') &&
                       document.querySelector('[data-imp="conce"]').checked,
        };
    }

    function renderImportList(list, badge) {
        var listEl = ref('importList');
        var resultCard = ref('importResult');
        var badgeEl = ref('importBadge');
        if (!listEl || !resultCard) return;
        resultCard.hidden = false;
        if (badgeEl) badgeEl.textContent = String(list.length);
        if (badge != null && badgeEl) badgeEl.textContent = String(badge);
        if (!list.length) {
            listEl.replaceChildren(el('div', { class: 'csa-empty' }, 'Nenhum item encontrado nas fontes selecionadas.'));
            return;
        }
        listEl.replaceChildren.apply(listEl, list.map(function (item) {
            var exists = item.exists === true;
            return el('div', { class: 'csa-row imp' }, [
                el('span', { class: 'mono' }, String(item.id || '—')),
                el('span', { class: 'grow' }, String(item.name || '—')),
                el('span', { class: 'csa-badge' }, CAT_LABEL_IMP[item.category] || 'Item'),
                el('span', {}, item.source === 'conce' ? 'Concessionária' : 'Inventário'),
                el('span', { class: 'csa-badge ' + (exists ? 'red' : 'green') }, exists ? 'Já existe' : 'Novo'),
            ]);
        }));
    }

    function initImport() {
        var resultCard = ref('importResult');
        if (resultCard) resultCard.hidden = true;
    }

    function runImportPreview() {
        var src = getImportSources();
        if (!src.inventory && !src.conce) { toast('Selecione pelo menos uma fonte', 'error'); return; }
        nuiPost('adminImportPreview', { sources: src }).then(function (res) {
            if (!res || !res.ok) { toast((res && res.err) || 'Erro ao pré-visualizar', 'error'); return; }
            var d = res.data || {};
            renderImportList(d.preview || [], d.total);
            toast('Pré-visualização: ' + (d.total || 0) + ' item(ns) encontrado(s)', 'success');
        });
    }

    function runImportExecute() {
        var src = getImportSources();
        if (!src.inventory && !src.conce) { toast('Selecione pelo menos uma fonte', 'error'); return; }
        nuiPost('adminImportRun', { sources: src }).then(function (res) {
            if (!res || !res.ok) { toast((res && res.err) || 'Erro ao importar', 'error'); return; }
            var d = res.data || {};
            absorbLists({ items: d.items });
            toast((d.message) || (d.inserted + ' importado(s)'), 'success');
            // recarrega pré-visualização para refletir status "Já existe"
            runImportPreview();
        });
    }


    // ============================================================
    // PIX — read-only (slot reservado #59)
    // ============================================================

    function renderPix() {
        var status = ref('pixStatus');
        if (status) {
            status.textContent = state.pix.enabled
                ? 'Pix HABILITADO — cobranças reais serão geradas no app do jogador.'
                : 'Pix DESABILITADO — o app do jogador mostra os pacotes com aviso "em breve".';
        }
        var listEl = ref('pixList');
        if (!listEl) return;
        var packs = Array.isArray(state.pix.packages) ? state.pix.packages : [];
        if (!packs.length) {
            listEl.replaceChildren(el('div', { class: 'csa-empty' }, 'Nenhum pacote configurado.'));
            return;
        }
        listEl.replaceChildren.apply(listEl, packs.map(function (p) {
            return el('div', { class: 'csa-row' }, [
                el('span', { class: 'csa-badge gold' }, 'Pacote'),
                el('span', { class: 'grow' }, [
                    String(p.name || p.id) + ' ',
                    el('small', {}, fmt(p.coins) + ' moedas' + (Number(p.bonus) > 0 ? ' +' + fmt(p.bonus) + ' bônus' : '')),
                ]),
                el('span', { class: 'num' }, fmtBRL(p.priceBRL)),
            ]);
        }));
    }


    // ============================================================
    // APARÊNCIA — settings da UI (persistidos em GData pelo server)
    // ============================================================

    var THEME_KEYS = ['accentColor', 'bgColor', 'textColor', 'errorColor', 'cardBorderColor',
                      'bgImage', 'bgOpacity', 'bgBlur', 'cardBgOpacity', 'cardBorderRadius', 'coinIcon'];

    // chaves de cor que têm swatch [type=color] — somente hex puro #RRGGBB é suportado pelo input
    var THEME_COLOR_KEYS = ['accentColor', 'bgColor', 'textColor', 'errorColor', 'cardBorderColor'];

    // converte qualquer valor de cor para #rrggbb (melhor esforço; retorna null se não for hex)
    function toSwatchHex(val) {
        if (!val) return null;
        var m = val.match(/^#?([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/);
        if (!m) return null;
        var h = m[1];
        if (h.length === 3) h = h[0]+h[0]+h[1]+h[1]+h[2]+h[2];
        return '#' + h;
    }

    function populateTheme() {
        THEME_KEYS.forEach(function (k) {
            var input = $('[data-set="' + k + '"]');
            var val = state.settings[k] || '';
            if (input) input.value = val;
            // sincroniza swatch se existir
            var swatch = $('[data-swatch="' + k + '"]');
            if (swatch) {
                var hex = toSwatchHex(val);
                if (hex) swatch.value = hex;
            }
        });
    }

    function collectTheme() {
        var out = {};
        THEME_KEYS.forEach(function (k) {
            var input = $('[data-set="' + k + '"]');
            if (input) out[k] = input.value;
        });
        return out;
    }

    function applyTheme(s) {
        var root = document.documentElement;
        if (s.accentColor) root.style.setProperty('--accent', s.accentColor);
        if (s.bgColor) root.style.setProperty('--bg', s.bgColor);
        if (s.textColor) root.style.setProperty('--text', s.textColor);
        if (s.errorColor) root.style.setProperty('--error', s.errorColor);
        if (s.cardBorderColor) root.style.setProperty('--card-border', s.cardBorderColor);
        if (s.cardBorderRadius) root.style.setProperty('--radius-md', s.cardBorderRadius + 'px');
    }

    function saveTheme() {
        var data = collectTheme();
        nuiPost('adminSaveSettings', data).then(function (res) {
            if (res && res.ok) {
                Object.assign(state.settings, data);
                applyTheme(state.settings);
                toast((res.data && res.data.message) || 'Configurações salvas', 'success');
            } else {
                toast((res && res.err) || 'Erro', 'error');
            }
        });
    }

    function resetTheme() {
        nuiPost('adminResetSettings').then(function (res) {
            if (res && res.ok) {
                toast((res.data && res.data.message) || 'Restaurado', 'success');
                // defaults canônicos reaplicados no próximo open; limpa overrides locais
                THEME_KEYS.forEach(function (k) { delete state.settings[k]; });
                populateTheme();
                document.documentElement.removeAttribute('style');
            } else {
                toast((res && res.err) || 'Erro', 'error');
            }
        });
    }


    // ============================================================
    // MODAIS + CONFIRMAÇÃO
    // ============================================================

    function openModal(name) {
        var m = $('[data-modal="' + name + '"]');
        if (m) m.classList.remove('hidden');
    }

    function closeModals() {
        document.querySelectorAll('.csa-overlay').forEach(function (m) { m.classList.add('hidden'); });
    }

    function anyModalOpen() {
        var open = false;
        document.querySelectorAll('.csa-overlay').forEach(function (m) {
            if (!m.classList.contains('hidden')) open = true;
        });
        return open;
    }

    function askConfirm(kind, id, msg) {
        state.confirm = { kind: kind, id: id };
        ref('confirmMsg').textContent = msg;
        openModal('confirm');
    }

    function confirmYes() {
        var c = state.confirm;
        if (!c) return;
        state.confirm = null;

        var map = {
            item:     { action: 'adminDeleteItem',     payload: { itemId: c.id },     after: renderCatalog },
            cat:      { action: 'adminDeleteCategory', payload: { categoryId: c.id }, after: function () { renderCats(); renderCatalog(); } },
            deal:     { action: 'adminDeleteDeal',     payload: { dealId: c.id },     after: renderDeals },
            code:     { action: 'adminDeleteCode',     payload: { key: c.id },        after: renderCodes },
            clearAll: { action: 'adminClearAll',       payload: {},                   after: function () { renderCatalog(); renderCats(); renderDeals(); } },
        };
        var task = map[c.kind];
        if (!task) return;

        nuiPost(task.action, task.payload).then(function (res) {
            if (res && res.ok) {
                absorbLists(res.data);
                if (res.data && Array.isArray(res.data.codes)) state.codes = res.data.codes;
                toast((res.data && res.data.message) || 'Feito', 'success');
                closeModals();
                task.after();
            } else {
                toast((res && res.err) || 'Erro', 'error');
            }
        });
    }


    // ============================================================
    // AÇÕES — delegação global de cliques
    // ============================================================

    function onClick(ev) {
        var navBtn = ev.target.closest('[data-view]');
        if (navBtn) { showView(navBtn.getAttribute('data-view')); return; }

        var pick = ev.target.closest('[data-pick]');
        if (pick) {
            var pid = pick.getAttribute('data-pick');
            var idx = state.dealSelected.indexOf(pid);
            if (idx >= 0) state.dealSelected.splice(idx, 1);
            else if (state.dealSelected.length < 10) state.dealSelected.push(pid);
            else { toast('Máximo de 10 itens por combo', 'error'); return; }
            pick.classList.toggle('selected', state.dealSelected.indexOf(pid) >= 0);
            var countEl = ref('dealPickerCount');
            if (countEl) countEl.textContent = String(state.dealSelected.length);
            return;
        }

        var act = ev.target.closest('[data-act]');
        if (act) {
            var id = act.getAttribute('data-id');
            switch (act.getAttribute('data-act')) {
                case 'editItem': openItemModal(id); break;
                case 'delItem':  askConfirm('item', id, 'Excluir o item "' + id + '" do catálogo?'); break;
                case 'editCat':  openCatModal(id); break;
                case 'delCat':   askConfirm('cat', id, 'Excluir a categoria "' + id + '"? Itens vinculados perdem a aba.'); break;
                case 'editDeal': openDealModal(id); break;
                case 'delDeal':  askConfirm('deal', id, 'Excluir a oferta "' + id + '"?'); break;
                case 'delCode':  askConfirm('code', id, 'Apagar o código pendente ' + id + '?'); break;
                case 'giveCoins': openCoinsModal('give', parseInt(id, 10)); break;
                case 'setCoins':  openCoinsModal('set', parseInt(id, 10)); break;
            }
            return;
        }

        var action = ev.target.closest('[data-action]');
        if (!action) return;
        switch (action.getAttribute('data-action')) {
            case 'close':          nuiPost('close'); break;
            case 'newItem':        openItemModal(null); break;
            case 'newCat':         openCatModal(null); break;
            case 'newDeal':        openDealModal(null); break;
            case 'clearAll':       askConfirm('clearAll', null, 'Limpar TODOS os itens, categorias e ofertas? O histórico de compras é preservado.'); break;
            case 'refreshPlayers': loadPlayers(); break;
            case 'modalClose':     closeModals(); break;
            case 'confirmYes':     confirmYes(); break;
            case 'saveItem':       saveItem(); break;
            case 'saveCat':        saveCat(); break;
            case 'saveDeal':       saveDeal(); break;
            case 'confirmCoins':   confirmCoins(); break;
            case 'copyKey':        copyKey(); break;
            case 'importPreview':  runImportPreview(); break;
            case 'importRun':      runImportExecute(); break;
            case 'saveTheme':      saveTheme(); break;
            case 'resetTheme':     resetTheme(); break;
        }
    }


    // ============================================================
    // LIFECYCLE — A-02
    // ============================================================

    function onOpen(data) {
        state.items = data.items || [];
        state.categories = data.categories || [];
        state.deals = data.deals || [];
        state.settings = data.settings || {};
        state.pix = (data.pix && typeof data.pix === 'object') ? data.pix : { enabled: false, packages: [] };
        state.playerName = data.playerName || '—';
        state.coins = data.coins || 0;
        state.dataAt = Date.now();
        state.codesLoaded = false;

        ref('meName').textContent = state.playerName;
        ref('meCoins').textContent = fmt(state.coins);
        applyTheme(state.settings);

        $('#app').classList.remove('hidden');
        showView('dash');
    }

    function onClose() {
        $('#app').classList.add('hidden');
        closeModals();
        if (_toastTimeout) { clearTimeout(_toastTimeout); _toastTimeout = null; }
        var t = ref('toast');
        if (t) t.classList.add('hidden');
    }

    function handleMessage(event) {
        var data = event.data;
        if (!data || !data.type) return;
        switch (data.type) {
            case 'open':  onOpen(data); break;
            case 'close': onClose(); break;
            case 'coinsChanged':
                state.coins = data.coins || 0;
                ref('meCoins').textContent = fmt(state.coins);
                break;
        }
    }

    function onInit() {
        _messageHandler = handleMessage;
        window.addEventListener('message', _messageHandler);

        _keydownHandler = function (e) {
            if (e.key !== 'Escape') return;
            if (anyModalOpen()) { closeModals(); return; }
            nuiPost('close');
        };
        document.addEventListener('keydown', _keydownHandler);

        _clickHandler = onClick;
        document.body.addEventListener('click', _clickHandler);

        // buscas + campos condicionais + form de código
        ref('catalogSearch').addEventListener('input', renderCatalog);
        ref('playerSearch').addEventListener('input', renderPlayers);
        ref('codeForm').addEventListener('submit', createCode);
        itemModalField('category').addEventListener('change', applyCategoryConditionals);

        // deal picker — filtro de busca
        var dps = ref('dealPickerSearch');
        if (dps) dps.addEventListener('input', renderDealPicker);

        // swatches de cor: swatch → hex input (tempo real)
        THEME_COLOR_KEYS.forEach(function (k) {
            var swatch = $('[data-swatch="' + k + '"]');
            var hex = $('[data-set="' + k + '"]');
            if (swatch && hex) {
                swatch.addEventListener('input', function () { hex.value = swatch.value; });
                hex.addEventListener('input', function () {
                    var h = toSwatchHex(hex.value);
                    if (h) swatch.value = h;
                });
            }
        });

        // preview de imagem no modal de item (atualiza ao digitar)
        var imgField = itemModalField('images');
        if (imgField) imgField.addEventListener('input', updateItemImgPreview);
    }

    function onDestroy() {
        if (_messageHandler) window.removeEventListener('message', _messageHandler);
        if (_keydownHandler) document.removeEventListener('keydown', _keydownHandler);
        if (_clickHandler) document.body.removeEventListener('click', _clickHandler);
        if (_toastTimeout) { clearTimeout(_toastTimeout); _toastTimeout = null; }
    }


    // ============================================================
    // BOOT
    // ============================================================

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', onInit);
    } else {
        onInit();
    }

    // cleanup ao descarregar a página (não esperado no CEF, mas defensivo)
    window.addEventListener('beforeunload', onDestroy);

})();
