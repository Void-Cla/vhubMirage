'use strict';

// IIFE: isola estado/funções deste domínio do escopo global window,
// compartilhado com oficina.js/bennys.js no mesmo documento (1 ui_page por resource).
(function () {

// ============================================================
// CONFIG DE OPÇÕES DE REPARO (type → ícone/label/desc fixos)
// ============================================================

const REPAIR_OPTIONS = [
  { type: 'tyre',   icon: '🛞', name: 'Pneus',   desc: 'Repara todos os pneus furados',        healthKey: null },
  { type: 'engine', icon: '⚙️', name: 'Motor',   desc: 'Restaura a saúde do motor',             healthKey: 'engine_health' },
  { type: 'body',   icon: '🔧', name: 'Lataria', desc: 'Restaura a saúde da carroceria',         healthKey: 'body_health' },
];


// ============================================================
// STATE
// ============================================================

let _data = null;   // payload recebido de openMec (plate, nome, prices, engine_health, body_health)
let _busy = false;  // trava UI durante round-trip (evita duplo clique)


// ============================================================
// HELPERS
// ============================================================

function setBusy(v) {
  _busy = v;
  document.querySelectorAll('.mc-opt').forEach((el) => el.classList.toggle('mc-opt-disabled', v));
  document.getElementById('mc-btn-tow').disabled = v;
}

function fmtMoney(v) {
  return 'R$ ' + Number(v || 0).toLocaleString('pt-BR');
}

// retorna percentual de saúde (0..100) dado valor 0..1000
function healthPct(val) {
  return Math.max(0, Math.min(100, Math.round((val / 1000) * 100)));
}

// retorna classe de cor pela porcentagem de saúde
function healthClass(pct) {
  if (pct >= 80) return 'mc-health-ok';
  if (pct >= 40) return 'mc-health-mid';
  return 'mc-health-low';
}


// ============================================================
// RENDER
// ============================================================

function renderOptions() {
  const root    = document.getElementById('mc-options');
  const prices  = (_data && _data.prices)  || {};
  const engHp   = (_data && _data.engine_health != null) ? _data.engine_health : null;
  const bodyHp  = (_data && _data.body_health   != null) ? _data.body_health   : null;
  root.innerHTML = '';

  for (const opt of REPAIR_OPTIONS) {
    const row = document.createElement('div');
    row.className = 'mc-opt' + (_busy ? ' mc-opt-disabled' : '');

    const icon = document.createElement('span');
    icon.className = 'mc-opt-icon'; icon.textContent = opt.icon;

    const info = document.createElement('div');
    info.className = 'mc-opt-info';

    const name = document.createElement('div');
    name.className = 'mc-opt-name'; name.textContent = opt.name;

    const desc = document.createElement('div');
    desc.className = 'mc-opt-desc'; desc.textContent = opt.desc;

    // barra de saúde para motor e lataria
    if (opt.healthKey) {
      const rawVal = opt.healthKey === 'engine_health' ? engHp : bodyHp;
      if (rawVal != null) {
        const pct  = healthPct(rawVal);
        const cls  = healthClass(pct);
        const bar  = document.createElement('div');
        bar.className = 'mc-health-bar';
        const fill = document.createElement('div');
        fill.className = 'mc-health-fill ' + cls;
        fill.style.width = pct + '%';
        bar.appendChild(fill);

        const label = document.createElement('span');
        label.className = 'mc-health-label';
        label.textContent = pct + '%';

        const wrap = document.createElement('div');
        wrap.className = 'mc-health-wrap';
        wrap.appendChild(bar); wrap.appendChild(label);
        info.appendChild(name); info.appendChild(desc); info.appendChild(wrap);
      } else {
        info.appendChild(name); info.appendChild(desc);
      }
    } else {
      info.appendChild(name); info.appendChild(desc);
    }

    // preço real (vem do servidor via payload)
    const price = document.createElement('span');
    price.className = 'mc-opt-price';
    const priceVal = prices[opt.type];
    if (priceVal != null) {
      price.textContent = opt.type === 'tyre'
        ? fmtMoney(priceVal) + '/pneu'
        : fmtMoney(priceVal) + '/100hp';
    } else {
      price.textContent = '—';
    }

    row.appendChild(icon); row.appendChild(info); row.appendChild(price);
    row.addEventListener('click', () => requestRepair(opt.type));
    root.appendChild(row);
  }
}


// ============================================================
// AÇÕES
// ============================================================

function requestRepair(repairType) {
  if (!_data || _busy) return;
  setBusy(true);
  fetch('https://vhub_custom/mec:repair', {
    method: 'POST',
    body:   JSON.stringify({ plate: _data.plate, repair_type: repairType }),
  });
  // libera UI quando mecConfirm chegar (ou após timeout de segurança)
  setTimeout(() => { if (_data) setBusy(false); }, 6000);
}

function requestTow() {
  if (!_data || _busy) return;
  setBusy(true);
  fetch('https://vhub_custom/mec:tow', { method: 'POST', body: '{}' });
  setTimeout(() => { if (_data) setBusy(false); }, 6000);
}

function fecharMec() {
  closeNUI();
  fetch('https://vhub_custom/mec:fechar', { method: 'POST', body: '{}' });
}


// ============================================================
// OPEN / CLOSE
// ============================================================

function openMec(data) {
  _data = data;
  _busy = false;

  document.getElementById('mc-veh-sub').textContent =
    (data.nome || '—') + '  ·  ' + (data.plate || '—');

  renderOptions();
  document.getElementById('mc-btn-tow').classList.remove('hidden');
  document.getElementById('mec-overlay').classList.remove('hidden');
}

function closeNUI() {
  document.getElementById('mec-overlay').classList.add('hidden');
  _data = null;
  _busy = false;
}


// ============================================================
// LUA MESSAGE BUS
// ============================================================

window.addEventListener('message', function (ev) {
  const msg = ev.data || {};
  if (msg.action === 'openMec')   openMec(msg.data);
  if (msg.action === 'fecharMec') closeNUI();
});

document.getElementById('mc-btn-close').addEventListener('click', fecharMec);
document.getElementById('mc-btn-tow').addEventListener('click',   requestTow);

})();
