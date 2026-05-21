// nui/js/auction.js  view "Leil es"
(() => {
  const App = window.vhubApp;
  const $list = document.getElementById('a-list');
  const $new  = document.getElementById('a-new');

  let snapshot = null;
  let timerId  = null;

  function renderList() {
    $list.innerHTML = '';
    const items = snapshot?.auctions || [];
    if (!items.length) {
      $list.innerHTML = `<div style="grid-column:1/-1; padding:60px 0; text-align:center; color:var(--text-dim2);">
        <i class="fa-solid fa-gavel" style="font-size:48px; display:block; margin-bottom:8px;"></i>
        Nenhum leil o ativo no momento.
      </div>`;
      return;
    }
    items.forEach((a) => {
      const c = document.createElement('div');
      c.className = 'card auc-card';
      const lance = a.current_bid || a.min_bid;
      const incr  = Math.floor(lance * (1 + (snapshot.cfg?.increment || 0.05)));
      c.innerHTML = `
        <div class="left">
          <div class="thumb" style="aspect-ratio:21/9;">
            <i class="fa-solid fa-car"></i>
            <img onerror="this.style.display='none'" src="${App.imgFor(a.model) || ''}">
          </div>
          <h4 style="margin-top:8px;">${a.nome || a.model}</h4>
          <div class="meta">
            <span>Placa: ${a.plate}</span>
            <span>${a.vtype}</span>
          </div>
          <div class="info-line"><span class="k">Refer ncia</span><span class="v">${App.fmtMoney(a.preco_ref)}</span></div>
          <div class="info-line"><span class="k">Lance m nimo</span><span class="v">${App.fmtMoney(a.min_bid)}</span></div>
          ${a.buyout ? `<div class="info-line"><span class="k">Compra direta</span><span class="v">${App.fmtMoney(a.buyout)}</span></div>` : ''}
        </div>
        <div class="right">
          <div class="lance">${App.fmtMoney(lance)}</div>
          <div class="timer" data-ends="${a.ends_at}">${App.fmtDur(a.ends_at - Math.floor(Date.now()/1000))}</div>
          <div class="row">
            <input type="number" min="${incr}" value="${incr}" data-bid="${a.id}">
            <button class="btn primary" data-act="bid" data-id="${a.id}"><i class="fa-solid fa-gavel"></i> Lance</button>
          </div>
        </div>`;
      $list.appendChild(c);
    });
    $list.querySelectorAll('[data-act="bid"]').forEach((btn) => {
      btn.onclick = () => {
        const id = +btn.dataset.id;
        const input = $list.querySelector(`input[data-bid="${id}"]`);
        const amount = +input.value;
        App.post('auctionBid', { id, amount });
      };
    });
    startTimer();
  }

  function startTimer() {
    if (timerId) clearInterval(timerId);
    timerId = setInterval(() => {
      const now = Math.floor(Date.now()/1000);
      $list.querySelectorAll('.timer').forEach((t) => {
        const ends = +t.dataset.ends;
        t.textContent = App.fmtDur(ends - now);
        if (ends - now <= 0) t.style.color = 'var(--danger)';
      });
    }, 1000);
  }

  $new.onclick = async () => {
    const r = await App.modal({
      title: 'Criar Leil o',
      html: `<label>Placa do seu ve culo</label><input data-field="plate" maxlength="8">
             <label>Lance m nimo (R$)</label><input data-field="min_bid" type="number" min="1">
             <label>Compra direta (R$)  opcional</label><input data-field="buyout" type="number" min="0">
             <label>Dura  o (minutos)</label><input data-field="dur_min" type="number" value="60" min="5" max="1440">
             <p>Taxa de listagem n o-reembols vel: ${App.fmtMoney(snapshot?.cfg?.fee || 100)}</p>`,
    });
    if (r.ok) {
      App.post('auctionNew', {
        plate: (r.fields.plate || '').toUpperCase(),
        min_bid: +r.fields.min_bid,
        buyout:  +(r.fields.buyout || 0) || null,
        dur_min: +r.fields.dur_min,
      });
    }
  };

  App.views.auction = {
    render(data) { snapshot = data || {}; renderList(); },
  };
})();
