// nui/js/garage.js  view "Garagem"
(() => {
  const App = window.vhubApp;
  const $list   = document.getElementById('g-list');
  const $detail = document.getElementById('g-detail');
  const $cats   = document.querySelectorAll('#view-garage .cat');

  let activeCat = 'all';
  let selectedPlate = null;
  let snapshot = null;     // payload do servidor
  let garagem_id = null;   // contexto da garagem atual (resolvido por proximidade)

  // status   classe CSS
  const statusClass = (s) => s in { garage:1, out:1, impound:1, auction:1, rental:1 } ? s : 'garage';

  function renderList() {
    $list.innerHTML = '';
    const vlist = (snapshot?.vehicles || [])
      .filter(v => activeCat === 'all' || v.vtype === activeCat);
    if (!vlist.length) {
      $list.innerHTML = `<div class="empty" style="grid-column:1/-1; color: var(--text-dim2); text-align:center; padding:60px 0;">
        <i class="fa-solid fa-warehouse" style="font-size:48px; display:block; margin-bottom:8px;"></i>
        Nenhum ve culo nesta categoria.
      </div>`;
      return;
    }
    vlist.forEach((v) => {
      const c = document.createElement('div');
      c.className = 'card' + (selectedPlate === v.plate ? ' selected' : '');
      c.innerHTML = `
        <span class="status ${statusClass(v.status)}">${v.status}</span>
        <div class="thumb">
          <i class="fa-solid fa-${iconFor(v.vtype)}"></i>
          <img onerror="this.style.display='none'" src="${App.imgFor(v.model) || ''}" alt="">
        </div>
        <h4>${v.nome || v.model}</h4>
        <div class="meta">
          <span>${v.plate}</span>
          <span class="preco">${v.categoria || ''}</span>
        </div>`;
      c.onclick = () => { selectedPlate = v.plate; renderList(); renderDetail(v); };
      $list.appendChild(c);
    });
  }

  function iconFor(t) {
    return { car:'car', bike:'motorcycle', plane:'plane', heli:'helicopter',
             boat:'ship', truck:'truck', trailer:'truck-moving' }[t] || 'car';
  }

  function renderDetail(v) {
    const ipva_ok = !v.ipva_until || v.ipva_until >= Math.floor(Date.now()/1000);
    const ipva_dt = v.ipva_until ? App.fmtDate(v.ipva_until) : ' ';
    const role    = v.role ? `<span class="tag warn">${v.role}</span>` : '';

    $detail.innerHTML = `
      <div class="head">
        <h2>${v.nome || v.model}</h2>
        <div class="preco">${v.plate}</div>
      </div>
      <div class="img">
        <img onerror="this.replaceWith(Object.assign(document.createElement('i'), {className:'fa-solid fa-${iconFor(v.vtype)}'}))"
             style="width:100%; height:100%; object-fit:contain;" src="${App.imgFor(v.model) || ''}" alt="">
      </div>
      <div class="tag-list">
        <span class="tag">${v.vtype}</span>
        <span class="tag">${v.categoria || ''}</span>
        ${role}
        ${(v.tags || []).map(t => `<span class="tag warn">${t}</span>`).join('')}
      </div>
      <div class="stats">
        ${statBar('Vel.', v.stats?.vel || 50)}
        ${statBar('Acel.', v.stats?.acel || 50)}
        ${statBar('Freio', v.stats?.freio || 50)}
        ${statBar('Dir.',  v.stats?.dir  || 50)}
      </div>
      <div>
        <div class="info-line"><span class="k">Status</span><span class="v">${v.status}</span></div>
        <div class="info-line"><span class="k">IPVA</span><span class="v" style="color:${ipva_ok?'var(--ok)':'var(--danger)'}">${ipva_dt}</span></div>
        ${v.rented_until ? `<div class="info-line"><span class="k">Aluguel at </span><span class="v">${App.fmtDate(v.rented_until)}</span></div>` : ''}
      </div>
      <div class="detail-actions">
        ${v.status === 'garage' ? `<button class="btn primary" data-act="spawn"><i class="fa-solid fa-key"></i> Spawnar</button>` :
          v.status === 'out'    ? `<button class="btn ok"      data-act="store"><i class="fa-solid fa-square-parking"></i> Estacionar</button>` :
                                  `<button class="btn" disabled>${v.status}</button>`}
        <button class="btn" data-act="repair"><i class="fa-solid fa-wrench"></i> Reparar</button>
        ${!ipva_ok ? `<button class="btn warn" data-act="ipva"><i class="fa-solid fa-receipt"></i> Pagar IPVA</button>`
                  : `<button class="btn ghost" data-act="ipva"><i class="fa-solid fa-receipt"></i> Renovar IPVA</button>`}
        <button class="btn" data-act="clone"><i class="fa-solid fa-clone"></i> Clonar Chave</button>
        <button class="btn" data-act="lend"><i class="fa-solid fa-handshake"></i> Emprestar</button>
        <button class="btn full" data-act="transfer"><i class="fa-solid fa-arrow-right-arrow-left"></i> Transferir / Vender P2P</button>
        <button class="btn full danger" data-act="sell"><i class="fa-solid fa-tag"></i> Vender   Loja</button>
      </div>`;

    $detail.querySelectorAll('[data-act]').forEach((btn) => {
      btn.onclick = () => handleAct(btn.dataset.act, v);
    });
  }

  function statBar(label, val) {
    return `<div class="stat"><span class="label">${label}</span>
      <span class="bar"><span style="width:${val}%"></span></span>
      <span class="v">${val}</span></div>`;
  }

  async function handleAct(act, v) {
    if (act === 'spawn') {
      App.post('spawn', { plate: v.plate, garagem_id });
    } else if (act === 'store') {
      App.post('store', { plate: v.plate, garagem_id });
    } else if (act === 'repair') {
      App.post('repair', { plate: v.plate });
    } else if (act === 'ipva') {
      App.post('ipvaPay', { plate: v.plate });
    } else if (act === 'clone') {
      const r = await App.modal({ title: 'Clonar Chave', text: `Pagar para receber outra c pia da chave do ve culo ${v.plate}?` });
      if (r.ok) App.post('cloneKey', { plate: v.plate });
    } else if (act === 'lend') {
      const r = await App.modal({
        title: 'Emprestar Chave',
        html: `<label>ID do jogador alvo</label><input data-field="target_src" type="number">
               <label>Dias</label><input data-field="dias" type="number" value="7">`,
      });
      if (r.ok) App.post('lendKey', { plate: v.plate, target_src: +r.fields.target_src, dias: +r.fields.dias });
    } else if (act === 'transfer') {
      const r = await App.modal({
        title: 'Transferir Ve culo',
        html: `<label>ID do comprador</label><input data-field="target_src" type="number">
               <label>Valor (R$)</label><input data-field="valor" type="number" value="0">`,
      });
      if (r.ok) App.post('transfer', { plate: v.plate, target_src: +r.fields.target_src, valor: +r.fields.valor });
    } else if (act === 'sell') {
      const r = await App.modal({ title: 'Vender para a Loja', text: `Vender ${v.plate}   loja por ~60% do valor de compra?` });
      if (r.ok) App.post('sellShop', { plate: v.plate });
    }
  }

  // ---------- Categorias ----------------------------------------------------
  $cats.forEach((b) => {
    b.onclick = () => {
      $cats.forEach(x => x.classList.remove('active')); b.classList.add('active');
      activeCat = b.dataset.cat; renderList();
    };
  });

  // ---------- Estacionar (rodap ) ------------------------------------------
  document.getElementById('g-store').onclick = () => {
    // pega o ve culo mais pr ximo via callback (cliente Lua resolve)
    App.post('store', { plate: null, garagem_id });
  };

  // ---------- Exposi  o -----------------------------------------------------
  App.views.garage = {
    render(data) {
      snapshot = data || {};
      garagem_id = data?.garagem_id || (window.__vhubLastGarage = window.__vhubLastGarage || null);
      // se servidor mandou no payload  ok; sen o resolvemos via tag escondida na pr xima itera  o
      selectedPlate = null;
      renderList();
      $detail.innerHTML = `<div class="empty"><i class="fa-solid fa-car"></i><br />Selecione um ve culo</div>`;
    },
  };
})();
