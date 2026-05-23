// nui/js/dealership.js — view "Concessionária" (tema vHub)
(() => {
  const App = window.vhubApp;
  const $list   = document.getElementById('d-list');
  const $detail = document.getElementById('d-detail');
  const $cats   = document.querySelectorAll('#view-dealer .cat');
  const $name   = document.getElementById('d-conc-name');

  let activeCat = 'all';
  let snapshot  = null;
  let selectedModel = null;

  function iconFor(t) {
    return { car:'car', bike:'motorcycle', plane:'plane', heli:'helicopter',
             boat:'ship', truck:'truck', trailer:'truck-moving' }[t] || 'car';
  }

  function renderList() {
    $list.innerHTML = '';
    const items = (snapshot?.catalog || [])
      .filter(v => activeCat === 'all' || v.tipo === activeCat);
    if (!items.length) {
      $list.innerHTML = `<div style="grid-column:1/-1; padding:60px 0; text-align:center; color:var(--vh-text-dim2);">
        <i class="fa-solid fa-store-slash" style="font-size:48px; display:block; margin-bottom:8px; color:rgba(243,181,58,0.25);"></i>
        Catálogo vazio.
      </div>`;
      return;
    }
    items.forEach((v) => {
      const c = document.createElement('div');
      c.className = 'card' + (selectedModel === v.model ? ' selected' : '');
      c.innerHTML = `
        <div class="thumb">
          <i class="fa-solid fa-${iconFor(v.tipo)}"></i>
          <img onerror="this.style.display='none'" src="${App.imgFor(v.model) || ''}" alt="">
        </div>
        <h4>${v.nome}</h4>
        <div class="meta">
          <span>${v.tipo} / ${v.categoria}</span>
          <span class="preco">${App.fmtMoney(v.preco)}</span>
        </div>
        ${v.estoque >= 0 ? `<div style="font-size:11px; color:var(--vh-text-dim2);">Estoque: ${v.estoque}</div>` : ''}`;
      c.onclick = () => { selectedModel = v.model; renderList(); renderDetail(v); };
      $list.appendChild(c);
    });
  }

  function statBar(label, val) {
    return `<div class="stat"><span class="label">${label}</span>
      <span class="bar"><span style="width:${val}%"></span></span>
      <span class="v">${val}</span></div>`;
  }

  function renderDetail(v) {
    const cfg = snapshot.cfg || {};
    $detail.innerHTML = `
      <div class="head">
        <h2>${v.nome}</h2>
        <div class="preco">${App.fmtMoney(v.preco)}</div>
      </div>
      <div class="img">
        <img onerror="this.replaceWith(Object.assign(document.createElement('i'),{className:'fa-solid fa-${iconFor(v.tipo)}'}))"
             style="width:100%; height:100%; object-fit:contain;" src="${App.imgFor(v.model) || ''}" alt="">
      </div>
      <div class="tag-list">
        <span class="tag">${v.tipo}</span>
        <span class="tag">${v.categoria}</span>
        ${(v.tags || []).map(t => `<span class="tag warn">${t}</span>`).join('')}
      </div>
      <div class="stats">
        ${statBar('Velocidade',    v.stats?.vel   || 50)}
        ${statBar('Aceleração',    v.stats?.acel  || 50)}
        ${statBar('Freio',         v.stats?.freio || 50)}
        ${statBar('Dirigibilidade',v.stats?.dir   || 50)}
      </div>
      <div class="detail-actions">
        <button class="btn primary full" data-act="buy"><i class="fa-solid fa-credit-card"></i> Comprar ${App.fmtMoney(v.preco)}</button>
        <button class="btn full" data-act="buy-custom"><i class="fa-solid fa-pen"></i> Comprar com placa personalizada +${App.fmtMoney(cfg.taxa_placa || 200)}</button>
        <button class="btn" data-act="test"><i class="fa-solid fa-flag-checkered"></i> Test Drive</button>
        <button class="btn warn" data-act="rent"><i class="fa-solid fa-key"></i> Alugar</button>
      </div>`;

    $detail.querySelectorAll('[data-act]').forEach((btn) => {
      btn.onclick = () => handleAct(btn.dataset.act, v);
    });
  }

  async function handleAct(act, v) {
    const conc = snapshot.conc;
    if (act === 'buy') {
      const r = await App.modal({
        title: 'Confirmar Compra',
        text: `Comprar ${v.nome} por ${App.fmtMoney(v.preco)}?`,
        okText: 'Comprar',
      });
      if (r.ok) App.post('buy', { model: v.model, conc_id: conc.id });
    } else if (act === 'buy-custom') {
      const r = await App.modal({
        title: 'Comprar com Placa Personalizada',
        html: `<p>Placa (2 a 8 caracteres, A-Z/0-9). Custo adicional: ${App.fmtMoney(snapshot.cfg?.taxa_placa || 200)}.</p>
               <label>Placa</label><input data-field="plate" maxlength="8" placeholder="EX 1234">`,
        okText: 'Comprar',
      });
      if (r.ok && r.fields.plate) App.post('buy', { model: v.model, conc_id: conc.id, plate: r.fields.plate.toUpperCase() });
    } else if (act === 'test') {
      App.post('testDrive', { model: v.model, conc_id: conc.id });
    } else if (act === 'rent') {
      const r = await App.modal({
        title: 'Alugar Veículo',
        html: `<label>Horas (1 a 168)</label><input data-field="horas" type="number" value="24" min="1" max="168">`,
        okText: 'Alugar',
      });
      if (r.ok) App.post('rent', { model: v.model, conc_id: conc.id, horas: +r.fields.horas });
    }
  }

  $cats.forEach((b) => {
    b.onclick = () => {
      $cats.forEach(x => x.classList.remove('active'));
      b.classList.add('active');
      activeCat = b.dataset.cat;
      renderList();
    };
  });

  App.views.dealer = {
    render(data) {
      snapshot = data || {};
      $name.textContent = snapshot.conc?.label ? `— ${snapshot.conc.label}` : '';
      selectedModel = null;
      renderList();
      $detail.innerHTML = `<div class="empty"><i class="fa-solid fa-tag"></i><br />Selecione um modelo</div>`;
    },
  };
})();
