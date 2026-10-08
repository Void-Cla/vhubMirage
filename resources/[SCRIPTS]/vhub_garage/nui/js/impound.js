(() => {
  const App = window.vhubApp;
  const list = document.getElementById('p-list');
  let snapshot = {};

  function renderList() {
    App.clear(list);
    const items = Array.isArray(snapshot.items) ? snapshot.items : [];
    if (!items.length) return App.empty(list, 'triangle-exclamation', 'Nenhum veiculo no patio.');
    for (const item of items) {
      const card = App.el('div', 'card auc-card');
      const left = App.el('div', 'left');
      left.append(App.vehicleVisual(item.vtype), App.el('h4', '', item.model || 'Veiculo'));
      const meta = App.el('div', 'meta');
      meta.append(App.el('span', '', `Placa: ${item.plate || '—'}`), App.el('span', '', item.vtype || '—'));
      left.append(meta, App.infoLine('Motivo', item.reason || '—'),
        App.infoLine('Apreendido em', App.fmtDate(item.impounded_at)));
      const right = App.el('div', 'right');
      const release = App.button('Liberar', 'primary', 'money-bill-wave');
      release.onclick = async () => {
        const result = await App.modal({ title:'Liberar Veiculo', text:`Pagar para liberar ${item.plate || 'o veiculo'}?`, okText:'Pagar e liberar' });
        if (result.ok) App.post('impoundPay', { plate:item.plate });
      };
      right.append(App.el('div', 'lance danger-text', App.fmtMoney(item.fee)), release);
      card.append(left, right);
      list.append(card);
    }
  }
  App.views.impound = { render(data) { snapshot = data || {}; renderList(); } };
})();
