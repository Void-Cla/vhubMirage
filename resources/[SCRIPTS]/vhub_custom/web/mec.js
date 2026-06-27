'use strict';

// IIFE: isola estado/funções deste domínio do escopo global window,
// compartilhado com oficina.js/bennys.js no mesmo documento (1 ui_page por resource).
(function () {

// ============================================================
// CONFIG DE OPÇÕES DE REPARO (type → ícone/label/desc fixos)
// ============================================================

const REPAIR_OPTIONS = [
  { type: 'tyre',   icon: '🛞', name: 'Pneus',   desc: 'Repara todos os pneus furados' },
  { type: 'engine', icon: '⚙️', name: 'Motor',   desc: 'Restaura a saúde do motor' },
  { type: 'body',   icon: '🔧', name: 'Lataria', desc: 'Restaura a saúde da carroceria' },
];


// ============================================================
// STATE
// ============================================================

let _data        = null;   // payload recebido de openMec (plate, nome, categoria)
let _busy         = false;  // trava UI durante round-trip (evita duplo clique)
let _closeTimeout = null;


// ============================================================
// HELPERS
// ============================================================

function setBusy(v) {
  _busy = v;
  document.querySelectorAll('.mc-opt').forEach((el) => el.classList.toggle('mc-opt-disabled', v));
  document.getElementById('mc-btn-tow').disabled = v;
}


// ============================================================
// RENDER
// ============================================================

function renderOptions() {
  const root = document.getElementById('mc-options');
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
    info.appendChild(name); info.appendChild(desc);

    const price = document.createElement('span');
    price.className = 'mc-opt-price'; price.textContent = '$';

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

  clearTimeout(_closeTimeout);
  _closeTimeout = setTimeout(() => { if (_data) fecharMec(); }, 20000);
}

function closeNUI() {
  clearTimeout(_closeTimeout);
  _closeTimeout = null;
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
