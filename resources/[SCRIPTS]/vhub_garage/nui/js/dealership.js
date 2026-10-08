(() => {
  const App = window.vhubApp;
  const list = document.getElementById('d-list');
  const detail = document.getElementById('d-detail');
  const categories = document.querySelectorAll('#view-dealer .cat');
  const name = document.getElementById('d-conc-name');
  let activeCategory = 'all';
  let selectedModel = null;
  let snapshot = {};

  function renderList() {
    App.clear(list);
    const items = (Array.isArray(snapshot.catalog) ? snapshot.catalog : [])
      .filter((vehicle) => activeCategory === 'all' || vehicle.tipo === activeCategory);
    if (!items.length) return App.empty(list, 'store-slash', 'Catalogo vazio.');
    for (const vehicle of items) {
      const card = App.el('div', `card${selectedModel === vehicle.model ? ' selected' : ''}`);
      card.append(App.vehicleVisual(vehicle.tipo), App.el('h4', '', vehicle.nome || vehicle.model || 'Veiculo'));
      const meta = App.el('div', 'meta');
      meta.append(App.el('span', '', `${vehicle.tipo || '—'} / ${vehicle.categoria || '—'}`),
        App.el('span', 'preco', App.fmtMoney(vehicle.preco)));
      card.append(meta);
      if (Number(vehicle.estoque) >= 0) card.append(App.el('div', 'stock', `Estoque: ${Number(vehicle.estoque)}`));
      card.onclick = () => { selectedModel = vehicle.model; renderList(); renderDetail(vehicle); };
      list.append(card);
    }
  }

  function renderDetail(vehicle) {
    App.clear(detail);
    const config = snapshot.cfg || {};
    const head = App.el('div', 'head');
    head.append(App.el('h2', '', vehicle.nome || vehicle.model || 'Veiculo'),
      App.el('div', 'preco', App.fmtMoney(vehicle.preco)));
    const tags = App.el('div', 'tag-list');
    tags.append(App.tag(vehicle.tipo || 'veiculo'), App.tag(vehicle.categoria || 'sem categoria'));
    for (const tag of Array.isArray(vehicle.tags) ? vehicle.tags : []) tags.append(App.tag(tag, true));
    const stats = App.el('div', 'stats');
    stats.append(App.stat('Velocidade', vehicle.stats?.vel ?? 50), App.stat('Aceleracao', vehicle.stats?.acel ?? 50),
      App.stat('Freio', vehicle.stats?.freio ?? 50), App.stat('Direcao', vehicle.stats?.dir ?? 50));
    const actions = App.el('div', 'detail-actions');
    const buy = App.button(`Comprar ${App.fmtMoney(vehicle.preco)}`, 'primary full', 'credit-card');
    const custom = App.button(`Placa personalizada +${App.fmtMoney(config.taxa_placa || 200)}`, 'full', 'pen');
    const test = App.button('Test Drive', '', 'flag-checkered');
    const rent = App.button('Alugar', 'warn', 'key');
    buy.onclick = () => handle('buy', vehicle);
    custom.onclick = () => handle('buy-custom', vehicle);
    test.onclick = () => handle('test', vehicle);
    rent.onclick = () => handle('rent', vehicle);
    actions.append(buy, custom, test, rent);
    detail.append(head, App.vehicleVisual(vehicle.tipo, true), tags, stats, actions);
  }

  async function handle(action, vehicle) {
    const dealership = snapshot.conc || {};
    if (action === 'buy') {
      const result = await App.modal({ title:'Confirmar Compra', text:`Comprar ${vehicle.nome || vehicle.model} por ${App.fmtMoney(vehicle.preco)}?`, okText:'Comprar' });
      if (result.ok) App.post('buy', { model:vehicle.model, conc_id:dealership.id });
    } else if (action === 'buy-custom') {
      const result = await App.modal({ title:'Comprar com Placa Personalizada',
        text:`Use 2 a 8 caracteres A-Z/0-9. Adicional: ${App.fmtMoney(snapshot.cfg?.taxa_placa || 200)}.`,
        fields:[{ label:'Placa', name:'plate', maxLength:8, placeholder:'EX 1234' }], okText:'Comprar' });
      const plate = String(result.fields?.plate || '').toUpperCase();
      if (result.ok && plate) App.post('buy', { model:vehicle.model, conc_id:dealership.id, plate });
    } else if (action === 'test') {
      App.post('testDrive', { model:vehicle.model, conc_id:dealership.id });
    } else if (action === 'rent') {
      const result = await App.modal({ title:'Alugar Veiculo', fields:[
        { label:'Horas (1 a 168)', name:'horas', type:'number', value:24, min:1, max:168 },
      ], okText:'Alugar' });
      if (result.ok) App.post('rent', { model:vehicle.model, conc_id:dealership.id, horas:+result.fields.horas });
    }
  }

  categories.forEach((button) => {
    button.onclick = () => {
      categories.forEach((item) => item.classList.remove('active'));
      button.classList.add('active');
      activeCategory = button.dataset.cat;
      renderList();
    };
  });
  App.views.dealer = { render(data) {
    snapshot = data || {};
    name.textContent = snapshot.conc?.label ? `— ${snapshot.conc.label}` : '';
    selectedModel = null;
    renderList();
    App.empty(detail, 'tag', 'Selecione um modelo');
  } };
})();
