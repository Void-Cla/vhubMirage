// nui/js/impound.js — view "Pátio" (tema vHub)
(() => {
  const App = window.vhubApp;
  const $list = document.getElementById('p-list');

  let snapshot = null;

  function iconFor(t) {
    return { car:'car', bike:'motorcycle', plane:'plane', heli:'helicopter',
             boat:'ship', truck:'truck', trailer:'truck-moving' }[t] || 'car';
  }

  function renderList() {
    $list.innerHTML = '';
    const items = snapshot?.items || [];
    if (!items.length) {
      $list.innerHTML = `<div style="grid-column:1/-1; padding:60px 0; text-align:center; color:var(--vh-text-dim2);">
        <i class="fa-solid fa-triangle-exclamation" style="font-size:48px; display:block; margin-bottom:8px; color:rgba(243,181,58,0.25);"></i>
        Nenhum veículo no pátio.
      </div>`;
      return;
    }
    items.forEach((it) => {
      const c = document.createElement('div');
      c.className = 'card auc-card';
      c.innerHTML = `
        <div class="left">
          <div class="thumb" style="aspect-ratio:21/9;">
            <i class="fa-solid fa-${iconFor(it.vtype)}"></i>
            <img onerror="this.style.display='none'" src="${App.imgFor(it.model) || ''}">
          </div>
          <h4 style="margin-top:8px;">${it.model}</h4>
          <div class="meta">
            <span>Placa: ${it.plate}</span>
            <span>${it.vtype}</span>
          </div>
          <div class="info-line"><span class="k">Motivo</span><span class="v">${it.reason}</span></div>
          <div class="info-line"><span class="k">Apreendido em</span><span class="v">${App.fmtDate(it.impounded_at)}</span></div>
        </div>
        <div class="right">
          <div class="lance" style="color:var(--vh-danger)">${App.fmtMoney(it.fee)}</div>
          <button class="btn primary" data-pay="${it.plate}"><i class="fa-solid fa-money-bill-wave"></i> Liberar</button>
        </div>`;
      $list.appendChild(c);
    });
    $list.querySelectorAll('[data-pay]').forEach((btn) => {
      btn.onclick = async () => {
        const r = await App.modal({
          title: 'Liberar Veículo',
          text: `Pagar para liberar o veículo ${btn.dataset.pay}?`,
          okText: 'Pagar e liberar',
        });
        if (r.ok) App.post('impoundPay', { plate: btn.dataset.pay });
      };
    });
  }

  App.views.impound = {
    render(data) { snapshot = data || {}; renderList(); },
  };
})();
