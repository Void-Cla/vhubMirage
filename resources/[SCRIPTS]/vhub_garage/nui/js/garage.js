(() => {
  const App = window.vhubApp;
  const list = document.getElementById('g-list');
  const detail = document.getElementById('g-detail');
  const categories = document.querySelectorAll('#view-garage .cat');
  const labels = { garage:'Na garagem', out:'Na rua', impound:'No patio', auction:'Em leilao',
    rental:'Alugado', sold:'Vendido' };
  let activeCategory = 'all';
  let selectedPlate = null;
  let snapshot = {};

  function action(text, classes, icon, name, vehicle) {
    const button = App.button(text, classes, icon);
    button.onclick = () => handleAction(name, vehicle);
    return button;
  }

  function renderList() {
    App.clear(list);
    const vehicles = (Array.isArray(snapshot.vehicles) ? snapshot.vehicles : [])
      .filter((vehicle) => activeCategory === 'all' || vehicle.vtype === activeCategory);
    if (!vehicles.length) return App.empty(list, 'warehouse', 'Nenhum veiculo nesta categoria.');
    for (const vehicle of vehicles) {
      const card = App.el('div', `card${selectedPlate === vehicle.plate ? ' selected' : ''}`);
      card.append(App.el('span', `status ${String(vehicle.status || '')}`, labels[vehicle.status] || vehicle.status || '—'));
      card.append(App.vehicleVisual(vehicle.vtype));
      card.append(App.el('h4', '', vehicle.nome || vehicle.model || 'Veiculo'));
      const meta = App.el('div', 'meta');
      meta.append(App.el('span', '', vehicle.plate || '—'), App.el('span', 'preco', vehicle.categoria || ''));
      card.append(meta);
      card.onclick = () => {
        selectedPlate = vehicle.plate;
        renderList();
        renderDetail(vehicle);
      };
      list.append(card);
    }
  }

  function renderDetail(vehicle) {
    App.clear(detail);
    const now = Math.floor(Date.now() / 1000);
    const ipvaOk = !vehicle.ipva_until || Number(vehicle.ipva_until) >= now;
    const rental = vehicle.status === 'rental' || vehicle.rented_until;
    const head = App.el('div', 'head');
    head.append(App.el('h2', '', vehicle.nome || vehicle.model || 'Veiculo'), App.el('div', 'preco', vehicle.plate || '—'));
    const tags = App.el('div', 'tag-list');
    tags.append(App.tag(vehicle.vtype || 'veiculo'), App.tag(vehicle.categoria || 'sem categoria'));
    if (vehicle.role) tags.append(App.tag(vehicle.role, true));
    for (const tag of Array.isArray(vehicle.tags) ? vehicle.tags : []) tags.append(App.tag(tag, true));
    if (rental) tags.append(App.tag('Aluguel', true));
    const stats = App.el('div', 'stats');
    stats.append(
      App.stat('Velocidade', vehicle.stats?.vel ?? 50),
      App.stat('Aceleracao', vehicle.stats?.acel ?? 50),
      App.stat('Freio', vehicle.stats?.freio ?? 50),
      App.stat('Direcao', vehicle.stats?.dir ?? 50),
    );
    const info = App.el('div');
    info.append(
      App.infoLine('Situacao', labels[vehicle.status] || vehicle.status || '—'),
      App.infoLine('IPVA', vehicle.ipva_until ? App.fmtDate(vehicle.ipva_until) : '—', ipvaOk ? 'ok-text' : 'danger-text'),
    );
    if (vehicle.rented_until) info.append(App.infoLine('Aluguel ate', App.fmtDate(vehicle.rented_until)));
    const actions = App.el('div', 'detail-actions');
    if (vehicle.status === 'garage' || vehicle.status === 'rental') {
      actions.append(action('Spawnar', 'primary', 'key', 'spawn', vehicle));
    } else if (vehicle.status === 'out') {
      actions.append(action('Estacionar', 'ok', 'square-parking', 'store', vehicle));
    } else {
      const disabled = App.button(labels[vehicle.status] || vehicle.status || 'Indisponivel');
      disabled.disabled = true;
      actions.append(disabled);
    }
    actions.append(action('Reparar', '', 'wrench', 'repair', vehicle));
    actions.append(action(ipvaOk ? 'Renovar IPVA' : 'Pagar IPVA', ipvaOk ? 'ghost' : 'warn', 'receipt', 'ipva', vehicle));
    if (!rental) actions.append(
      action('Clonar Chave', '', 'clone', 'clone', vehicle),
      action('Emprestar', '', 'handshake', 'lend', vehicle),
      action('Transferir / Vender', 'full', 'arrow-right-arrow-left', 'transfer', vehicle),
      action('Vender para a Loja', 'full danger', 'tag', 'sell', vehicle),
    );
    detail.append(head, App.vehicleVisual(vehicle.vtype, true), tags, stats, info, actions);
  }

  async function handleAction(name, vehicle) {
    if (name === 'spawn') return App.post('spawn', { plate: vehicle.plate });
    if (name === 'store') return App.post('store', { plate: vehicle.plate });
    if (name === 'repair') return App.post('repair', { plate: vehicle.plate });
    if (name === 'ipva') return App.post('ipvaPay', { plate: vehicle.plate });
    if (name === 'clone') {
      const result = await App.modal({ title:'Clonar Chave', text:`Pagar por outra chave de ${vehicle.plate}?` });
      if (result.ok) App.post('cloneKey', { plate: vehicle.plate });
    } else if (name === 'lend') {
      const result = await App.modal({ title:'Emprestar Chave', fields:[
        { label:'ID do jogador alvo', name:'target_src', type:'number', min:1 },
        { label:'Dias', name:'dias', type:'number', value:7, min:1 },
      ] });
      if (result.ok) App.post('lendKey', { plate:vehicle.plate, target_src:+result.fields.target_src, dias:+result.fields.dias });
    } else if (name === 'transfer') {
      const result = await App.modal({ title:'Transferir Veiculo', fields:[
        { label:'ID do comprador', name:'target_src', type:'number', min:1 },
        { label:'Valor (R$)', name:'valor', type:'number', value:0, min:0 },
      ] });
      if (result.ok) App.post('transfer', { plate:vehicle.plate, target_src:+result.fields.target_src, valor:+result.fields.valor });
    } else if (name === 'sell') {
      const result = await App.modal({ title:'Vender para a Loja', text:`Vender ${vehicle.plate} por aproximadamente 60%?` });
      if (result.ok) App.post('sellShop', { plate:vehicle.plate });
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
  document.getElementById('g-store').onclick = () => App.post('store', { plate:null });
  App.views.garage = { render(data) {
    snapshot = data || {};
    selectedPlate = null;
    renderList();
    App.empty(detail, 'car', 'Selecione um veiculo');
  } };
})();
