// dashboard.js — Painel: visão geral + economia (dados do REQ_DASH)
(() => {
  const App = window.vhubAdmin;

  const $cards    = document.getElementById('dash-cards');
  const $quick    = document.getElementById('quick-actions');
  const $staff    = document.getElementById('staff-list');
  const $ecoCards = document.getElementById('eco-cards');
  const $ecoTop   = document.getElementById('eco-top');

  // ============================================================
  // CARDS
  // ============================================================

  // cria card de estatística (ícone + rótulo + valor)
  function card(icon, label, value) {
    const c = App.el('div', 'card stat');
    c.appendChild(App.icon(icon));
    const box = App.el('div');
    box.appendChild(App.el('div', 'k', label));
    box.appendChild(App.el('div', 'v', value));
    c.appendChild(box);
    return c;
  }

  App.renderDash = (d) => {
    if (!d) return;

    // visão geral
    $cards.textContent = '';
    $cards.appendChild(card('users',  'Jogadores online', `${d.online} / ${d.max_slots}`));
    $cards.appendChild(card('flag',   'Denúncias abertas', String(d.reports_open ?? 0)));
    $cards.appendChild(card('clock',  'Uptime do servidor', App.fmtDur(d.uptime_ms)));
    $cards.appendChild(card('shield', 'Equipe online', String((d.staff || []).length)));

    // badge de denúncias no aside
    const badge = document.getElementById('r-badge');
    if (badge) {
      const n = Number(d.reports_open) || 0;
      badge.textContent = n;
      badge.classList.toggle('hidden', n === 0);
    }

    // equipe
    $staff.textContent = '';
    const staff = d.staff || [];
    if (!staff.length) {
      $staff.appendChild(App.el('div', 'empty-row', 'Nenhum admin online.'));
    } else {
      staff.forEach(s => {
        const item = App.el('div', 'item');
        const left = App.el('div');
        left.appendChild(App.el('strong', null, s.name));
        left.appendChild(App.el('div', 'meta', `ID ${s.src}`));
        item.appendChild(left);
        $staff.appendChild(item);
      });
    }

    // economia (players online — verdade é o vhub_money)
    const eco = d.economy || {};
    $ecoCards.textContent = '';
    $ecoCards.appendChild(card('coins', 'Circulante (online)', App.fmtMoney(eco.total)));
    $ecoCards.appendChild(card('coins', 'Em carteira', App.fmtMoney(eco.wallet_total)));
    $ecoCards.appendChild(card('coins', 'Em banco', App.fmtMoney(eco.bank_total)));
    $ecoCards.appendChild(card('users', 'Jogadores contados', String(eco.counted ?? 0)));

    $ecoTop.textContent = '';
    const top = eco.top || [];
    if (!top.length) {
      $ecoTop.appendChild(App.el('div', 'empty-row', 'Sem jogadores online.'));
    } else {
      top.forEach((p, i) => {
        const item = App.el('div', 'item');
        const left = App.el('div');
        left.appendChild(App.el('strong', null, `${i + 1}º · ${p.name}`));
        left.appendChild(App.el('div', 'meta', `ID ${p.src}`));
        item.appendChild(left);
        const right = App.el('div', 'right');
        right.appendChild(App.el('span', null, App.fmtMoney(p.total)));
        item.appendChild(right);
        $ecoTop.appendChild(item);
      });
    }
  };

  // ============================================================
  // AÇÕES RÁPIDAS (visão geral)
  // ============================================================

  const QUICK = [
    { key: 'god',     icon: 'shield', label: 'Invencível' },
    { key: 'invis',   icon: 'eyeoff', label: 'Invisível' },
    { key: 'tpgo',    icon: 'marker', label: 'Ir ao marcador' },
    { key: 'tplast',  icon: 'back',   label: 'Voltar' },
    { key: 'healall', icon: 'heart',  label: 'Curar todos' },
    { key: 'announce',icon: 'horn',   label: 'Anunciar', warn: true },
  ];

  QUICK.forEach(q => {
    const b = App.el('button', 'btn' + (q.warn ? ' warn' : ''));
    b.appendChild(App.icon(q.icon));
    b.appendChild(document.createTextNode(q.label));
    b.onclick = async () => {
      if (q.key === 'announce') {
        const a = (App.state.actions || {}).announce || { desc: 'Anúncio global', fields: ['message'] };
        App.triggerAction('announce', a);
        return;
      }
      App.post('act', { action: q.key, fields: {} });
    };
    $quick.appendChild(b);
  });
})();
