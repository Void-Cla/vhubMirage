// nui/js/app.js — vhub_money (Fleeca Camell)
// L-D8: NUI nao decide regra. Toda operacao e relay para o servidor via callback.

(() => {
  // ─── Estado ────────────────────────────────────────────────────────────────

  const state = {
    open: false,
    mode: 'atm',           // 'atm' | 'bank'
    station: null,
    wallet: 0,
    bank: 0,
    owner: false,
    txs: [],
    cfg: {
      brand_name: 'Fleeca Camell',
      brand_tag:  'Banco Digital',
      atm_max_w:  0, atm_max_d: 0, atm_cooldown: 30,
      bank_max_w: 0, bank_max_d: 0,
      transfer_min: 1, transfer_max: 1000000,
      fee_percent: 0, fee_fixed: 0,
    },
    activeTab: 'ops',
  };

  // ─── Util ──────────────────────────────────────────────────────────────────

  const $  = (sel) => document.querySelector(sel);
  const $$ = (sel) => document.querySelectorAll(sel);
  const el = (tag, attrs, ...children) => {
    const e = document.createElement(tag);
    if (attrs) for (const [k, v] of Object.entries(attrs)) {
      if (k === 'class') e.className = v;
      else if (k === 'html') e.innerHTML = v;
      else if (k.startsWith('on') && typeof v === 'function') e.addEventListener(k.slice(2), v);
      else if (k.startsWith('data-')) e.setAttribute(k, v);
      else if (k === 'colspan') e.setAttribute('colspan', v);
      else e[k] = v;
    }
    for (const c of children) {
      if (c == null) continue;
      e.appendChild(typeof c === 'string' ? document.createTextNode(c) : c);
    }
    return e;
  };

  const fmt = (n) => {
    const v = Math.max(0, Math.floor(Number(n) || 0));
    const s = v.toString();
    let out = '', c = 0;
    for (let i = s.length - 1; i >= 0; i--) {
      out = s[i] + out; c++;
      if (c % 3 === 0 && i > 0) out = '.' + out;
    }
    return 'R$ ' + out;
  };

  const fmtDate = (unix) => {
    if (!unix) return '—';
    const d = new Date(unix * 1000);
    return d.toLocaleString('pt-BR', {
      day: '2-digit', month: '2-digit', year: '2-digit',
      hour: '2-digit', minute: '2-digit',
    });
  };

  const fmtDateRel = (unix) => {
    if (!unix) return '—';
    const diff = Math.floor(Date.now() / 1000) - unix;
    if (diff < 60)    return `${diff}s atrás`;
    if (diff < 3600)  return `${Math.floor(diff / 60)}min atrás`;
    if (diff < 86400) return `${Math.floor(diff / 3600)}h atrás`;
    return fmtDate(unix);
  };

  const POST = (cb, data) =>
    fetch(`https://${typeof GetParentResourceName === 'function'
      ? GetParentResourceName() : 'vhub_money'}/${cb}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data || {}),
    }).then((r) => r.json().catch(() => ({}))).catch(() => ({}));

  function toast(message, kind = 'info') {
    const icon = kind === 'success' ? 'fa-circle-check'
              : kind === 'error'   ? 'fa-triangle-exclamation'
              :                      'fa-circle-info';
    const t = el('div', { class: `vh-toast ${kind}` },
      el('i', { class: 'fa-solid ' + icon }),
      el('span', null, message)
    );
    $('#toast-stack').appendChild(t);
    setTimeout(() => {
      t.classList.add('fade-out');
      setTimeout(() => t.remove(), 250);
    }, 3500);
  }

  // ─── Mapeamento de erros do servidor ───────────────────────────────────────

  function errMessage(raw) {
    const s = String(raw || '');
    if (s.startsWith('limite_excedido:')) {
      const cap = parseInt(s.split(':')[1], 10) || 0;
      return `Limite por operação excedido. Máximo: ${fmt(cap)}.`;
    }
    if (s.startsWith('cooldown:')) {
      const sec = parseInt(s.split(':')[1], 10) || 0;
      return `Aguarde ${sec}s para a próxima operação.`;
    }
    const map = {
      sem_sessao:            'Sessão não encontrada.',
      saldo_insuficiente:    'Saldo insuficiente.',
      saldo_insuficiente_offline: 'Saldo do destinatário insuficiente.',
      valor_invalido:        'Valor inválido.',
      valor_abaixo_do_minimo:'Valor abaixo do mínimo permitido.',
      valor_acima_do_maximo: 'Valor acima do máximo permitido.',
      identificador_invalido:'Destinatário inválido.',
      destino_invalido:      'Destinatário não encontrado.',
      telefone_nao_encontrado:'Telefone não cadastrado.',
      registro_nao_encontrado:'Registro civil não encontrado.',
      tipo_de_chave_desabilitado:'Esse tipo de chave foi desabilitado.',
      autotransferencia:     'Não é possível transferir para si mesmo.',
      destinatario_offline:  'Destinatário fora da cidade.',
      destino_offline:       'Destinatário fora da cidade.',
      conta_inexistente:     'Conta do destinatário não existe.',
      falha_credito_destino: 'Falha ao creditar o destinatário.',
      forbidden:             'Operação não permitida por este resource.',
    };
    return map[s] || `Falha: ${s || 'erro desconhecido'}.`;
  }

  // ─── Render: cabeçalho/saldos ──────────────────────────────────────────────

  function applyBalances() {
    $('#bal-wallet').textContent = fmt(state.wallet);
    $('#bal-bank').textContent   = fmt(state.bank);
    $('#bal-total').textContent  = fmt(state.wallet + state.bank);
    updateHints();
  }

  function applyHeader() {
    $('#hdr-mode-txt').textContent = state.mode === 'bank' ? 'Agência' : 'ATM';
    $('#brand-tag').textContent = state.cfg.brand_tag || 'Banco Digital';
    $('#ctx-info').textContent  = state.station
      ? '— ' + (state.station.label || (state.mode === 'bank' ? 'Agência' : 'Caixa Eletrônico'))
      : '';
    $('#ops-info-txt').innerHTML = state.mode === 'bank'
      ? '<strong>Agência:</strong> limites do balcão e sem cooldown.'
      : `<strong>ATM:</strong> saque máx. ${fmt(state.cfg.atm_max_w || 0)} · depósito máx. ${fmt(state.cfg.atm_max_d || 0)} · cooldown ${state.cfg.atm_cooldown}s.`;
  }

  function updateHints() {
    const wHint = $('#op-withdraw-hint');
    const dHint = $('#op-deposit-hint');
    if (wHint) wHint.textContent = `Disponível: ${fmt(state.bank)}`;
    if (dHint) dHint.textContent = `Disponível: ${fmt(state.wallet)}`;

    const feeHint = $('#tr-fee-hint');
    if (feeHint) {
      const cfg = state.cfg;
      if (state.owner || (cfg.fee_percent <= 0 && cfg.fee_fixed <= 0)) {
        feeHint.textContent = state.owner ? 'Você é o dono da cidade — sem taxas.' : 'Sem taxas.';
      } else {
        feeHint.textContent =
          `Taxa: ${cfg.fee_percent}% + ${fmt(cfg.fee_fixed)} sobre o valor enviado.`;
      }
    }
  }

  // ─── Render: extrato ───────────────────────────────────────────────────────

  const KIND_LABELS = {
    deposit:        ['Depósito',          'in'],
    atm_deposit:    ['Depósito (ATM)',    'in'],
    withdraw:       ['Saque',             'out'],
    atm_withdraw:   ['Saque (ATM)',       'out'],
    transfer_out:   ['Transferência enviada',  'out'],
    transfer_in:    ['Transferência recebida', 'in'],
    give:           ['Doação em mão',     'out'],
    payment:        ['Pagamento',         'out'],
    admin_set:      ['Ajuste admin',      'in'],
    admin_give:     ['Bonificação admin', 'in'],
    admin_take:     ['Penalidade admin',  'out'],
    death_loss:     ['Perda por morte',   'out'],
    initial:        ['Saldo inicial',     'in'],
  };

  function renderHistory() {
    const tbody = $('#tx-tbody');
    tbody.innerHTML = '';
    $('#tx-count').textContent = state.txs.length;

    if (!state.txs.length) {
      tbody.appendChild(el('tr', null,
        el('td', { class: 'vh-table-empty', colspan: 6 },
          'Nenhuma movimentação registrada ainda.')));
      return;
    }

    for (const t of state.txs) {
      const meta = KIND_LABELS[t.kind] || [t.kind || '?', 'in'];
      const flow = `${t.source_account || 'none'} → ${t.target_account || 'none'}`;
      tbody.appendChild(el('tr', null,
        el('td', { class: 'when', title: fmtDate(t.created_unix) }, fmtDateRel(t.created_unix)),
        el('td', { class: 'kind' }, meta[0]),
        el('td', { class: 'amount ' + meta[1] }, (meta[1] === 'out' ? '-' : '+') + fmt(t.amount)),
        el('td', { class: 'flow' }, flow),
        el('td', { class: 'balance' },
          `C ${fmt(t.balance_wallet)} · B ${fmt(t.balance_bank)}`),
        el('td', { class: 'reason', title: t.reason || '' }, t.reason || '—')
      ));
    }
  }

  // ─── Tabs ──────────────────────────────────────────────────────────────────

  function switchTab(name) {
    state.activeTab = name;
    $$('.vh-tab').forEach((t) => t.classList.toggle('active', t.dataset.tab === name));
    $$('.vh-tabpanel').forEach((p) => p.classList.toggle('active', p.dataset.tabpanel === name));
  }

  // ─── Operações ─────────────────────────────────────────────────────────────

  function readInput(id) {
    const raw = ($(id) && $(id).value) || '';
    const n = parseInt(raw, 10);
    return Number.isFinite(n) && n > 0 ? n : 0;
  }

  function clearInput(id) {
    const e = $(id); if (e) e.value = '';
  }

  function setInput(id, v) {
    const e = $(id); if (e) e.value = String(v);
  }

  function presetClick(ev) {
    const chip = ev.target.closest('.vh-chip');
    if (!chip) return;
    const wrap = chip.closest('.vh-op-presets');
    if (!wrap) return;
    const targetId = '#' + wrap.dataset.target;
    const v = chip.dataset.val;
    if (v === 'all') {
      const max = wrap.dataset.target === 'op-deposit-amount' ? state.wallet : state.bank;
      setInput(targetId, max);
    } else {
      setInput(targetId, v);
    }
  }

  function doDeposit() {
    const n = readInput('#op-deposit-amount');
    if (n <= 0) { toast('Informe um valor válido.', 'error'); return; }
    POST('deposit', { mode: state.mode, amount: n });
    clearInput('#op-deposit-amount');
  }

  function doWithdraw() {
    const n = readInput('#op-withdraw-amount');
    if (n <= 0) { toast('Informe um valor válido.', 'error'); return; }
    POST('withdraw', { mode: state.mode, amount: n });
    clearInput('#op-withdraw-amount');
  }

  function doTransfer() {
    const target = ($('#tr-target').value || '').trim();
    const amount = readInput('#tr-amount');
    const reason = ($('#tr-reason').value || '').trim();
    if (!target)     { toast('Informe o destinatário.', 'error'); return; }
    if (amount <= 0) { toast('Informe um valor válido.', 'error'); return; }
    if (state.mode !== 'bank') {
      toast('Transferências apenas em agências físicas.', 'error');
      return;
    }
    POST('transfer', { target, amount, reason });
    $('#tr-amount').value = '';
    $('#tr-reason').value = '';
  }

  // ─── Mensagens do server ───────────────────────────────────────────────────

  window.addEventListener('message', (e) => {
    const msg = e.data || {};
    switch (msg.action) {
      case 'open': {
        state.open    = true;
        const d = msg.data || {};
        state.mode    = d.mode || 'atm';
        state.station = d.station || null;
        state.wallet  = Number(d.wallet) || 0;
        state.bank    = Number(d.bank)   || 0;
        state.owner   = d.owner === true;
        state.txs     = Array.isArray(d.txs) ? d.txs : [];
        if (d.cfg) Object.assign(state.cfg, d.cfg);

        $('#vhub-bg').classList.remove('hidden');
        $('#panel').classList.remove('hidden');
        applyHeader();
        applyBalances();
        renderHistory();
        switchTab('ops');
        window.vhubSand && window.vhubSand.start();
        break;
      }
      case 'close': {
        state.open = false;
        $('#panel').classList.add('hidden');
        $('#vhub-bg').classList.add('hidden');
        window.vhubSand && window.vhubSand.stop();
        break;
      }
      case 'result': {
        const r = msg.data || {};
        if (r.ok) {
          toast('Operação concluída com sucesso.', 'success');
        } else {
          const errCode = (r.data && r.data.err) || 'falha';
          toast(errMessage(errCode), 'error');
        }
        break;
      }
      case 'refresh': {
        const d = msg.data || {};
        state.wallet = Number(d.wallet) || 0;
        state.bank   = Number(d.bank)   || 0;
        if (Array.isArray(d.txs)) state.txs = d.txs;
        applyBalances();
        renderHistory();
        break;
      }
    }
  });

  // ─── Bindings ──────────────────────────────────────────────────────────────

  document.addEventListener('click', (ev) => {
    const t = ev.target.closest('[data-action], [data-tab], .vh-chip');
    if (!t) return;
    if (t.dataset.tab) { switchTab(t.dataset.tab); return; }
    if (t.classList && t.classList.contains('vh-chip')) {
      presetClick(ev); return;
    }
    const action = t.dataset.action;
    if (action === 'close')    POST('close', {});
    if (action === 'deposit')  doDeposit();
    if (action === 'withdraw') doWithdraw();
    if (action === 'transfer') doTransfer();
  });

  document.addEventListener('keydown', (ev) => {
    if (!state.open) return;
    if (ev.key === 'Escape') POST('close', {});
    // Enter no input de valor confirma a operação na aba ativa
    if (ev.key === 'Enter') {
      if (state.activeTab === 'ops') {
        if (document.activeElement && document.activeElement.id === 'op-deposit-amount')  doDeposit();
        if (document.activeElement && document.activeElement.id === 'op-withdraw-amount') doWithdraw();
      } else if (state.activeTab === 'transfer') {
        if (document.activeElement && ['tr-target','tr-amount','tr-reason']
            .includes(document.activeElement.id)) doTransfer();
      }
    }
  });
})();
