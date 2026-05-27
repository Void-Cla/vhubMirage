const app = document.getElementById('app');
const modal = document.getElementById('modal');
const modalQty = document.getElementById('modal-qty');
const modalOk = document.getElementById('modal-ok');
const modalCancel = document.getElementById('modal-cancel');
const contextLabel = document.getElementById('context-label');
const closeBtn = document.getElementById('btn-close');

const views = {
  mochila: document.getElementById('view-mochila'),
  bau: document.getElementById('view-bau'),
  market: document.getElementById('view-market'),
  loja: document.getElementById('view-loja')
};

const state = {
  contexto: 'mochila',
  mochila: [],
  peso: 0,
  maxpeso: 0,
  identidade: null,
  foto: null,
  binds: {},
  selected: null,
  bau: null,
  market: null,
  lojas: []
};

function sendNui(event, data = {}) {
  return fetch(`https://${GetParentResourceName()}/${event}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data)
  }).then(async (res) => {
    try {
      return await res.json();
    } catch {
      return null;
    }
  }).catch(() => null);
}

function setContext(ctx) {
  state.contexto = ctx;
  Object.values(views).forEach((view) => view.classList.remove('active'));
  if (views[ctx]) views[ctx].classList.add('active');
  contextLabel.textContent = ctx.toUpperCase();
}

function formatMoney(value) {
  return (value || 0).toLocaleString('pt-BR');
}

function updateWeight(elText, elBar, peso, max) {
  const pesoNum = Number(peso) || 0;
  const maxNum = Number(max) || 0;
  const pct = maxNum > 0 ? Math.min(100, Math.round((pesoNum / maxNum) * 100)) : 0;
  elText.textContent = `${pesoNum.toFixed(1)} / ${maxNum.toFixed(1)}`;
  elBar.style.width = `${pct}%`;
}

function createItemCard(item, options = {}) {
  const card = document.createElement('div');
  card.className = 'item-card';
  card.dataset.item = item.key;

  const icon = document.createElement('div');
  icon.className = 'item-icon';
  let iconPath = 'images/item-default.svg';
  if (item.icon) {
    iconPath = item.icon.includes('.') ? `images/${item.icon}` : `images/${item.icon}.png`;
  }
  icon.style.backgroundImage = `url(${iconPath})`;
  if (!item.icon) {
    icon.textContent = item.name ? item.name.charAt(0) : '?';
  }

  const title = document.createElement('div');
  title.className = 'item-title';
  title.textContent = item.name || item.key;

  const meta = document.createElement('div');
  meta.className = 'item-meta';
  meta.innerHTML = `<span>x${item.amount}</span><span>${item.peso || 0}kg</span>`;

  card.append(icon, title, meta);

  if (options.onClick) {
    card.addEventListener('click', () => options.onClick(item, card));
  }

  return card;
}

function renderMochila() {
  const list = document.getElementById('mochila-list');
  list.innerHTML = '';
  state.mochila.forEach((item) => {
    const card = createItemCard(item, {
      onClick: (itemData, el) => {
        state.selected = itemData;
        document.querySelectorAll('#mochila-list .item-card').forEach((node) => node.classList.remove('selected'));
        el.classList.add('selected');
        document.getElementById('selected-item').textContent = itemData.name || itemData.key;
      }
    });
    list.appendChild(card);
  });

  updateWeight(
    document.getElementById('mochila-weight'),
    document.getElementById('mochila-weight-bar'),
    state.peso,
    state.maxpeso
  );

  renderPlayerInfo();
  renderBinds();
}

function renderPlayerInfo() {
  const ident = state.identidade || {};
  document.getElementById('player-name').textContent = `${ident.name || ''} ${ident.firstname || ''}`.trim() || 'Jogador';
  document.getElementById('player-id').textContent = `ID ${ident.user_id || 0}`;
  document.getElementById('player-job').textContent = ident.job || 'Sem cargo';
  document.getElementById('player-vip').textContent = ident.vip || 'Sem vip';
  document.getElementById('player-cash').textContent = formatMoney(ident.cash);
  document.getElementById('player-bank').textContent = formatMoney(ident.bank);
  document.getElementById('player-coin').textContent = formatMoney(ident.coin);

  const avatar = document.getElementById('player-avatar');
  if (state.foto) {
    avatar.style.backgroundImage = `url(${state.foto})`;
  }
}

function renderBinds() {
  const bindsEl = document.getElementById('binds');
  bindsEl.innerHTML = '';
  for (let i = 1; i <= 5; i++) {
    const slot = document.createElement('div');
    slot.className = 'bind-slot';
    const bind = state.binds?.[String(i)];
    if (bind) {
      slot.classList.add('active');
      slot.innerHTML = `<div>${bind.item}</div><div>${bind.type || 'usar'}</div>`;
    } else {
      slot.textContent = `Slot ${i}`;
    }
    slot.addEventListener('click', () => {
      if (!state.selected) return;
      const payload = { slot: i, item: state.selected.key, type: state.selected.type };
      state.binds[String(i)] = { item: state.selected.key, type: state.selected.type };
      sendNui('saveBind', payload);
      renderBinds();
    });
    bindsEl.appendChild(slot);
  }
}

function renderBau() {
  const bauList = document.getElementById('bau-list');
  const mochilaList = document.getElementById('bau-mochila-list');
  const bau = state.bau || {};

  document.getElementById('bau-title').textContent = bau.bauNome || 'Bau';
  updateWeight(
    document.getElementById('bau-weight'),
    document.getElementById('bau-weight-bar'),
    bau.pesoBau || 0,
    bau.maxPesoBau || 0
  );
  updateWeight(
    document.getElementById('bau-mochila-weight'),
    document.getElementById('bau-mochila-weight-bar'),
    bau.pesoMochila || 0,
    bau.maxPesoMochila || 0
  );

  bauList.innerHTML = '';
  (bau.inventarioBau || []).forEach((item) => {
    const card = createItemCard(item, {
      onClick: async (itemData) => {
        const qty = await openQtyModal(1);
        if (!qty) return;
        sendNui('takeItem', { item: itemData.key, amount: qty }).then(() => sendNui('requestBau')).then(refreshBau);
      }
    });
    bauList.appendChild(card);
  });

  mochilaList.innerHTML = '';
  (bau.inventario || []).forEach((item) => {
    const card = createItemCard(item, {
      onClick: async (itemData) => {
        const qty = await openQtyModal(1);
        if (!qty) return;
        sendNui('storeItem', { item: itemData.key, amount: qty }).then(() => sendNui('requestBau')).then(refreshBau);
      }
    });
    mochilaList.appendChild(card);
  });
}

function renderMarket() {
  const itemsEl = document.getElementById('market-items');
  const recentEl = document.getElementById('market-recent');
  const sellInv = document.getElementById('sell-inventory');

  const market = state.market || { items: [], recent: [], myItems: [] };
  itemsEl.innerHTML = '';
  recentEl.innerHTML = '';
  sellInv.innerHTML = '';

  market.items.forEach((item) => {
    const card = document.createElement('div');
    card.className = 'market-card';
    card.innerHTML = `
      <div class="item-title">${item.label || item.item_name}</div>
      <div class="item-meta">x${item.quantidade} - $${formatMoney(item.preco)}</div>
      <button data-id="${item.marketplace_id}">Comprar</button>
    `;
    card.querySelector('button').addEventListener('click', () => {
      sendNui('marketBuyItem', { marketplace_id: item.marketplace_id });
    });
    itemsEl.appendChild(card);
  });

  market.recent.forEach((item) => {
    const card = document.createElement('div');
    card.className = 'market-card';
    card.innerHTML = `
      <div class="item-title">${item.label || item.item_name}</div>
      <div class="item-meta">x${item.quantidade}</div>
    `;
    recentEl.appendChild(card);
  });

  market.myItems.forEach((item) => {
    const card = document.createElement('div');
    card.className = 'item-card';
    card.innerHTML = `
      <div class="item-title">${item.name || item.key}</div>
      <div class="item-meta">x${item.amount}</div>
    `;
    card.addEventListener('click', () => {
      state.market.selected = item;
      document.getElementById('sell-selected').textContent = item.name || item.key;
    });
    sellInv.appendChild(card);
  });
}

function renderLojas() {
  const lojasList = document.getElementById('lojas-list');
  lojasList.innerHTML = '';

  state.lojas.forEach((loja) => {
    const item = document.createElement('div');
    item.className = 'list-item';
    item.textContent = loja.nome;
    item.addEventListener('click', () => {
      document.querySelectorAll('.list-item').forEach((node) => node.classList.remove('active'));
      item.classList.add('active');
      sendNui('lojaDados', { loja_id: loja.loja_id }).then((dados) => {
        renderLojaDados(dados);
      });
    });
    lojasList.appendChild(item);
  });
}

function renderLojaDados(dados) {
  if (!dados || !dados.loja) return;
  document.getElementById('loja-nome').textContent = dados.loja.nome;
  document.getElementById('loja-saldo').textContent = formatMoney(dados.loja.saldo_caixa || 0);

  const itemsEl = document.getElementById('loja-items');
  itemsEl.innerHTML = '';
  (dados.itens || []).forEach((item) => {
    const card = document.createElement('div');
    card.className = 'item-card';
    card.innerHTML = `
      <div class="item-title">${item.item_name}</div>
      <div class="item-meta">$${formatMoney(item.preco_compra)} | Estoque ${item.estoque_atual}</div>
      <div class="action-buttons">
        <button data-action="buy">Comprar</button>
        <button data-action="sell">Vender</button>
      </div>
    `;
    card.querySelector('[data-action="buy"]').addEventListener('click', async () => {
      const qty = await openQtyModal(1);
      if (!qty) return;
      sendNui('comprarLoja', { loja_id: dados.loja.loja_id, item: item.item_name, amount: qty });
    });
    card.querySelector('[data-action="sell"]').addEventListener('click', async () => {
      const qty = await openQtyModal(1);
      if (!qty) return;
      sendNui('venderLoja', { loja_id: dados.loja.loja_id, item: item.item_name, amount: qty });
    });
    itemsEl.appendChild(card);
  });
}

function refreshBau(dados) {
  if (!dados) return;
  state.bau = dados;
  renderBau();
}

function openQtyModal(defaultValue) {
  modalQty.value = defaultValue || 1;
  modal.classList.remove('hidden');
  return new Promise((resolve) => {
    const cleanup = () => {
      modal.classList.add('hidden');
      modalOk.removeEventListener('click', onOk);
      modalCancel.removeEventListener('click', onCancel);
    };
    const onOk = () => {
      const value = parseInt(modalQty.value, 10);
      cleanup();
      resolve(Number.isNaN(value) ? 1 : value);
    };
    const onCancel = () => {
      cleanup();
      resolve(null);
    };
    modalOk.addEventListener('click', onOk);
    modalCancel.addEventListener('click', onCancel);
  });
}

closeBtn.addEventListener('click', () => sendNui('invClose'));

window.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') sendNui('invClose');
});

window.addEventListener('message', (event) => {
  const data = event.data;

  if (data.action === 'open') {
    app.classList.remove('hidden');
    setContext(data.contexto);

    if (data.contexto === 'mochila') {
      state.mochila = data.mochila || [];
      state.peso = data.peso || 0;
      state.maxpeso = data.maxpeso || 0;
      state.identidade = data.identidade || null;
      state.foto = data.foto || null;
      state.binds = data.binds || {};
      renderMochila();
    }

    if (data.contexto === 'bau') {
      state.bau = data.dados || {};
      renderBau();
    }

    if (data.contexto === 'market') {
      state.market = data.dados || {};
      renderMarket();
    }

    if (data.contexto === 'loja') {
      state.lojas = (data.dados && data.dados.lojas) || [];
      renderLojas();
    }
  }

  if (data.action === 'close') {
    app.classList.add('hidden');
    state.selected = null;
  }

  if (data.action === 'updateMochila') {
    state.mochila = data.mochila || [];
    state.peso = data.peso || 0;
    state.maxpeso = data.maxpeso || 0;
    renderMochila();
  }

  if (data.action === 'updateBau') {
    state.bau = data.dados || {};
    renderBau();
  }

  if (data.action === 'updateMarket') {
    state.market = data.dados || {};
    renderMarket();
  }

  if (data.action === 'updateLoja') {
    state.lojas = (data.dados && data.dados.lojas) || [];
    renderLojas();
  }
});

const actionButtons = document.querySelectorAll('.action-buttons button');
actionButtons.forEach((btn) => {
  btn.addEventListener('click', async () => {
    if (!state.selected) return;
    const qty = parseInt(document.getElementById('action-qty').value || '1', 10);
    const amount = Number.isNaN(qty) ? 1 : qty;
    if (amount <= 0) return;

    if (btn.dataset.action === 'use') {
      sendNui('useItem', { item: state.selected.key, amount, type: state.selected.type });
    }

    if (btn.dataset.action === 'drop') {
      sendNui('dropItem', { item: state.selected.key, amount });
    }

    if (btn.dataset.action === 'send') {
      sendNui('sendItem', { item: state.selected.key, amount });
    }

    if (btn.dataset.action === 'market') {
      setContext('market');
      sendNui('marketGetData').then((data) => {
        state.market = data || { items: [], recent: [], myItems: state.mochila };
        state.market.selected = state.selected;
        document.getElementById('sell-selected').textContent = state.selected.name || state.selected.key;
        renderMarket();
      });
    }
  });
});

const sellSubmit = document.getElementById('sell-submit');
sellSubmit.addEventListener('click', () => {
  const selected = state.market?.selected;
  if (!selected) return;
  const qty = parseInt(document.getElementById('sell-qty').value || '1', 10);
  const price = parseInt(document.getElementById('sell-price').value || '1', 10);
  if (Number.isNaN(qty) || Number.isNaN(price) || qty <= 0 || price <= 0) return;
  const desc = document.getElementById('sell-desc').value || '';
  sendNui('marketListItem', { item: selected.key, amount: qty, price, description: desc });
});

const marketSearch = document.getElementById('market-search');
marketSearch.addEventListener('input', () => {
  const term = marketSearch.value.toLowerCase();
  const filtered = (state.market?.items || []).filter((item) => {
    const name = (item.label || item.item_name || '').toLowerCase();
    return name.includes(term);
  });
  const itemsEl = document.getElementById('market-items');
  itemsEl.innerHTML = '';
  filtered.forEach((item) => {
    const card = document.createElement('div');
    card.className = 'market-card';
    card.innerHTML = `
      <div class="item-title">${item.label || item.item_name}</div>
      <div class="item-meta">x${item.quantidade} - $${formatMoney(item.preco)}</div>
      <button data-id="${item.marketplace_id}">Comprar</button>
    `;
    card.querySelector('button').addEventListener('click', () => {
      sendNui('marketBuyItem', { marketplace_id: item.marketplace_id });
    });
    itemsEl.appendChild(card);
  });
});
