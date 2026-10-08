(() => {
  const App = window.vhubApp;
  const list = document.getElementById('a-list');
  const create = document.getElementById('a-new');
  let snapshot = {};
  let timer = null;

  function renderList() {
    App.clear(list);
    const auctions = Array.isArray(snapshot.auctions) ? snapshot.auctions : [];
    if (!auctions.length) return App.empty(list, 'gavel', 'Nenhum leilao ativo.');
    for (const auction of auctions) {
      const card = App.el('div', 'card auc-card');
      const left = App.el('div', 'left');
      left.append(App.vehicleVisual(auction.vtype), App.el('h4', '', auction.nome || auction.model || 'Veiculo'));
      const meta = App.el('div', 'meta');
      meta.append(App.el('span', '', `Placa: ${auction.plate || '—'}`), App.el('span', '', auction.vtype || '—'));
      left.append(meta, App.infoLine('Referencia', App.fmtMoney(auction.preco_ref)),
        App.infoLine('Lance minimo', App.fmtMoney(auction.min_bid)));
      if (auction.buyout) left.append(App.infoLine('Compra direta', App.fmtMoney(auction.buyout)));

      const current = Number(auction.current_bid || auction.min_bid) || 0;
      const increment = Math.max(1, Math.floor(current * (1 + (Number(snapshot.cfg?.increment) || 0.05))));
      const right = App.el('div', 'right');
      const countdown = App.el('div', 'timer', App.fmtDur(Number(auction.ends_at) - Math.floor(Date.now() / 1000)));
      countdown.dataset.ends = String(Number(auction.ends_at) || 0);
      const row = App.el('div', 'row');
      const input = App.el('input');
      input.type = 'number'; input.min = String(increment); input.value = String(increment);
      const bid = App.button('Dar Lance', 'primary', 'gavel');
      bid.onclick = () => App.post('auctionBid', { id:Number(auction.id), amount:Number(input.value) });
      row.append(input, bid);
      right.append(App.el('div', 'lance', App.fmtMoney(current)), countdown, row);
      card.append(left, right);
      list.append(card);
    }
    startTimer();
  }

  function startTimer() {
    clearInterval(timer);
    timer = setInterval(() => {
      const now = Math.floor(Date.now() / 1000);
      list.querySelectorAll('.timer').forEach((node) => {
        const remaining = Number(node.dataset.ends) - now;
        node.textContent = App.fmtDur(remaining);
        node.classList.toggle('danger-text', remaining <= 0);
      });
    }, 1000);
  }

  create.onclick = async () => {
    const result = await App.modal({ title:'Criar Leilao',
      text:`Taxa nao reembolsavel: ${App.fmtMoney(snapshot.cfg?.fee || 100)}.`,
      fields:[
        { label:'Placa do veiculo', name:'plate', maxLength:8 },
        { label:'Lance minimo (R$)', name:'min_bid', type:'number', min:1 },
        { label:'Compra direta (R$) — opcional', name:'buyout', type:'number', min:0 },
        { label:'Duracao (minutos)', name:'dur_min', type:'number', value:60, min:5, max:1440 },
      ], okText:'Criar Leilao' });
    if (result.ok) App.post('auctionNew', {
      plate:String(result.fields.plate || '').toUpperCase(), min_bid:+result.fields.min_bid,
      buyout:+result.fields.buyout || null, dur_min:+result.fields.dur_min,
    });
  };
  App.views.auction = { render(data) { snapshot = data || {}; renderList(); } };
})();
