'use strict';

// IIFE: isola estado/funções deste domínio do escopo global window,
// compartilhado com oficina.js/mec.js no mesmo documento (1 ui_page por resource).
(function () {

// ============================================================
// CONFIG DE CATEGORIAS (mapeia tab → payload key esperado pelo server/bennys.lua)
// ============================================================

const PRIMARY_COLOURS = [
  0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,
  25,26,27,28,29,30,31,37,38,39,40,41,42,49,50,64,66,69,70,72,73,
  74,75,83,88,111,112,113,114,123,126,127,128,134,135,136,141,
  142,143,144,145,146,147,148,150,151,152,153,154,155,156,
];

const NEON_INDEX = ['left', 'right', 'front', 'back'];

const TINT_OPTIONS = [
  { v: 0, label: 'Sem tint' }, { v: 1, label: 'Pure black' },
  { v: 2, label: 'Dark smoke' }, { v: 3, label: 'Light smoke' },
  { v: 4, label: 'Stock' }, { v: 5, label: 'Limo' }, { v: 6, label: 'Green' },
];

const WHEEL_TYPES = [
  { v: 0, label: 'Sport' }, { v: 1, label: 'Muscle' }, { v: 2, label: 'Lowrider' },
  { v: 3, label: 'SUV' }, { v: 4, label: 'Offroad' }, { v: 5, label: 'Tuner' },
  { v: 6, label: 'Bike' }, { v: 7, label: 'High-end' },
];

// kits cosméticos de lataria (índice GTA → nome PT-BR; preço vem do servidor em data.prices.mod_cosmetic)
const COSMETIC_KITS = [
  { idx: 0, name: 'Aerofólio' }, { idx: 1, name: 'Para-choque frontal' },
  { idx: 2, name: 'Para-choque traseiro' }, { idx: 3, name: 'Saias laterais' },
  { idx: 4, name: 'Escapamento' }, { idx: 5, name: 'Rollcage' },
  { idx: 6, name: 'Grade' }, { idx: 7, name: 'Capô' },
  { idx: 9, name: 'Paralamas' }, { idx: 10, name: 'Teto' },
];

const TABS = [
  { id: 'cor',    label: 'Pintura' },
  { id: 'neon',   label: 'Neon' },
  { id: 'visual', label: 'Visual' },
  { id: 'kits',   label: 'Kits' },
];


// ============================================================
// STATE
// ============================================================

let _data         = null;   // payload recebido de openBennys (plate, nome, categoria, prices)
let _activeTab     = 'cor';
let _pending       = {};    // patch acumulado a enviar ao servidor (mesmo shape do server/bennys.lua)
let _closeTimeout  = null;


// ============================================================
// HELPERS
// ============================================================

function fmtMoney(v) {
  return 'R$ ' + Number(v).toLocaleString('pt-BR');
}

function priceFor(key) {
  return Number((_data && _data.prices && _data.prices[key]) || 0);
}

// soma o custo de tudo que está pendente (mesma regra de calcCost do server/bennys.lua)
function calcTotal() {
  if (!_data) return 0;
  let total = 0;
  if (_pending.colours)       total += priceFor('cor_primaria') + priceFor('cor_secundaria');
  if (_pending.extra_colours) total += priceFor('cor_perolado') + priceFor('cor_roda');
  if (_pending.neons)         total += priceFor('neon');
  if (_pending.neon_colour)   total += priceFor('neon');
  if (_pending.smoke   !== undefined) total += priceFor('fumaca');
  if (_pending.xenon   !== undefined) total += priceFor('xenon');
  if (_pending.window_tint !== undefined) total += priceFor('tint');
  if (_pending.livery !== undefined) total += priceFor('livery');
  if (_pending.plate_index !== undefined) total += priceFor('plate_index');
  if (_pending.wheel_type  !== undefined) total += priceFor('wheel_type');
  if (_pending.mods) {
    for (const _ in _pending.mods) total += priceFor('mod_cosmetic');
  }
  return total;
}


// ============================================================
// RENDER — TABS
// ============================================================

function renderTabs() {
  const nav = document.getElementById('bn-tabs');
  nav.innerHTML = '';
  for (const t of TABS) {
    const btn = document.createElement('button');
    btn.className   = 'bn-tab' + (t.id === _activeTab ? ' active' : '');
    btn.textContent = t.label;
    btn.addEventListener('click', () => { _activeTab = t.id; renderTabs(); renderDetail(); });
    nav.appendChild(btn);
  }
}


// ============================================================
// RENDER — DETAIL (por categoria)
// ============================================================

function renderDetail() {
  const root = document.getElementById('bn-detail');
  root.innerHTML = '';

  if (_activeTab === 'cor')    renderCorTab(root);
  if (_activeTab === 'neon')   renderNeonTab(root);
  if (_activeTab === 'visual') renderVisualTab(root);
  if (_activeTab === 'kits')   renderKitsTab(root);
}

function sectionTitle(root, text) {
  const t = document.createElement('div');
  t.className   = 'bn-section-title';
  t.textContent = text;
  root.appendChild(t);
}

function colourSwatch(root, label, slot) {
  sectionTitle(root, label);
  const grid = document.createElement('div');
  grid.className = 'bn-swatch-grid';
  const cur = (_pending.colours || [])[slot];
  for (const c of PRIMARY_COLOURS) {
    const sw = document.createElement('div');
    sw.className = 'bn-swatch' + (cur === c ? ' selected' : '');
    sw.title      = 'Cor ' + c;
    sw.style.background = '#3a322a'; // GTA paint codes não mapeiam para RGB real sem tabela nativa
    sw.addEventListener('click', () => {
      const colours = _pending.colours || [null, null];
      colours[slot] = c;
      _pending.colours = colours;
      previewAndRender();
    });
    grid.appendChild(sw);
  }
  root.appendChild(grid);
}

function renderCorTab(root) {
  colourSwatch(root, 'COR PRIMÁRIA', 0);
  colourSwatch(root, 'COR SECUNDÁRIA', 1);

  sectionTitle(root, 'PEROLADO / ARO');
  const row = document.createElement('div');
  row.className = 'bn-toggle-row';
  const lbl = document.createElement('span');
  lbl.className = 'bn-toggle-label'; lbl.textContent = 'Aplicar perolado + cor de aro';
  const price = document.createElement('span');
  price.className = 'bn-toggle-price';
  price.textContent = fmtMoney(priceFor('cor_perolado') + priceFor('cor_roda'));
  const sw = document.createElement('div');
  sw.className = 'bn-switch' + (_pending.extra_colours ? ' on' : '');
  sw.addEventListener('click', () => {
    _pending.extra_colours = _pending.extra_colours ? null : [0, 0];
    if (!_pending.extra_colours) delete _pending.extra_colours;
    previewAndRender();
  });
  row.appendChild(lbl); row.appendChild(price); row.appendChild(sw);
  root.appendChild(row);
}

function toggleRow(root, label, priceKey, field, nativeValue) {
  const row = document.createElement('div');
  row.className = 'bn-toggle-row';
  const lbl = document.createElement('span');
  lbl.className = 'bn-toggle-label'; lbl.textContent = label;
  const price = document.createElement('span');
  price.className = 'bn-toggle-price'; price.textContent = fmtMoney(priceFor(priceKey));
  const sw = document.createElement('div');
  const isOn = _pending[field] === true;
  sw.className = 'bn-switch' + (isOn ? ' on' : '');
  sw.addEventListener('click', () => {
    if (_pending[field] === true) delete _pending[field];
    else _pending[field] = true;
    previewAndRender();
  });
  row.appendChild(lbl); row.appendChild(price); row.appendChild(sw);
  root.appendChild(row);
}

function renderNeonTab(root) {
  sectionTitle(root, 'LUZES NEON');
  const row = document.createElement('div');
  row.className = 'bn-toggle-row';
  const lbl = document.createElement('span');
  lbl.className = 'bn-toggle-label'; lbl.textContent = 'Ativar kit neon (4 pontos)';
  const price = document.createElement('span');
  price.className = 'bn-toggle-price'; price.textContent = fmtMoney(priceFor('neon'));
  const sw = document.createElement('div');
  const isOn = !!_pending.neons;
  sw.className = 'bn-switch' + (isOn ? ' on' : '');
  sw.addEventListener('click', () => {
    _pending.neons = isOn ? undefined : [true, true, true, true];
    if (_pending.neons === undefined) delete _pending.neons;
    previewAndRender();
  });
  row.appendChild(lbl); row.appendChild(price); row.appendChild(sw);
  root.appendChild(row);

  sectionTitle(root, 'COR DO NEON');
  const grid = document.createElement('div');
  grid.className = 'bn-option-strip';
  const colours = [[255,0,0],[0,255,0],[0,120,255],[255,0,200],[255,255,255],[255,180,0]];
  for (const c of colours) {
    const chip = document.createElement('div');
    const cur = _pending.neon_colour;
    const isSel = cur && cur[0] === c[0] && cur[1] === c[1] && cur[2] === c[2];
    chip.className = 'bn-opt-chip' + (isSel ? ' selected' : '');
    chip.style.borderLeftColor = 'rgb(' + c.join(',') + ')';
    chip.style.borderLeftWidth = '4px';
    chip.textContent = 'RGB ' + c.join(',');
    chip.addEventListener('click', () => { _pending.neon_colour = c; previewAndRender(); });
    grid.appendChild(chip);
  }
  root.appendChild(grid);
}

function selectStrip(root, label, options, field, priceKey) {
  const wrap = document.createElement('div');
  wrap.className = 'bn-select-row';
  const lbl = document.createElement('span');
  lbl.className = 'bn-select-label';
  lbl.textContent = label + ' · ' + fmtMoney(priceFor(priceKey));
  wrap.appendChild(lbl);

  const strip = document.createElement('div');
  strip.className = 'bn-option-strip';
  for (const opt of options) {
    const chip = document.createElement('div');
    chip.className = 'bn-opt-chip' + (_pending[field] === opt.v ? ' selected' : '');
    chip.textContent = opt.label;
    chip.addEventListener('click', () => { _pending[field] = opt.v; previewAndRender(); });
    strip.appendChild(chip);
  }
  wrap.appendChild(strip);
  root.appendChild(wrap);
}

function renderVisualTab(root) {
  sectionTitle(root, 'ACABAMENTOS');
  toggleRow(root, 'Fumaça nos pneus', 'fumaca', 'smoke');
  toggleRow(root, 'Faróis xenon', 'xenon', 'xenon');

  sectionTitle(root, 'PERSONALIZAÇÃO');
  selectStrip(root, 'Vidro fumê', TINT_OPTIONS, 'window_tint', 'tint');
  selectStrip(root, 'Tipo de roda', WHEEL_TYPES, 'wheel_type', 'wheel_type');
}

function renderKitsTab(root) {
  sectionTitle(root, 'KITS DE LATARIA (cosmético)');
  for (const kit of COSMETIC_KITS) {
    const card = document.createElement('div');
    const mods = _pending.mods || {};
    const isSel = mods[String(kit.idx)] !== undefined;
    card.className = 'bn-kit-card' + (isSel ? ' selected' : '');

    const name = document.createElement('span');
    name.className = 'bn-kit-name'; name.textContent = kit.name;
    const price = document.createElement('span');
    price.className = 'bn-kit-price'; price.textContent = fmtMoney(priceFor('mod_cosmetic'));

    card.appendChild(name); card.appendChild(price);
    card.addEventListener('click', () => {
      const m = _pending.mods || {};
      if (m[String(kit.idx)] !== undefined) delete m[String(kit.idx)];
      else m[String(kit.idx)] = 1;
      _pending.mods = Object.keys(m).length ? m : undefined;
      if (!_pending.mods) delete _pending.mods;
      previewAndRender();
    });
    root.appendChild(card);
  }
}


// ============================================================
// RENDER — FOOTER
// ============================================================

function renderFooter() {
  const total = calcTotal();
  document.getElementById('bn-total-cost').textContent = fmtMoney(total);
  document.getElementById('bn-btn-apply').disabled     = (total === 0);
}

function previewAndRender() {
  // preview efêmero imediato no veículo vivo (client Lua aplica via VHubCustom.previewCosmetic)
  fetch('https://vhub_custom/bennys:preview', {
    method: 'POST',
    body:   JSON.stringify(_pending),
  });
  renderDetail();
  renderFooter();
}


// ============================================================
// OPEN / CLOSE
// ============================================================

function openBennys(data) {
  _data        = data;
  _activeTab   = 'cor';
  _pending     = {};

  document.getElementById('bn-veh-nome').textContent = data.nome || '—';
  document.getElementById('bn-veh-sub').textContent  =
    (data.categoria || '—') + '  ·  ' + (data.plate || '—');

  renderTabs();
  renderDetail();
  renderFooter();

  document.getElementById('bennys-overlay').classList.remove('hidden');
  document.getElementById('bn-btn-cancel').disabled = false;

  clearTimeout(_closeTimeout);
  _closeTimeout = setTimeout(() => { if (_data) cancelarBennys(); }, 20000);
}

function closeNUI() {
  clearTimeout(_closeTimeout);
  _closeTimeout = null;
  document.getElementById('bennys-overlay').classList.add('hidden');
  _data    = null;
  _pending = {};
}

function cancelarBennys() {
  closeNUI();
  fetch('https://vhub_custom/bennys:fechar', { method: 'POST', body: '{}' });
}

function aplicarBennys() {
  if (!_data || calcTotal() === 0) return;
  document.getElementById('bn-btn-apply').disabled  = true;
  document.getElementById('bn-btn-cancel').disabled = true;

  fetch('https://vhub_custom/bennys:aplicar', {
    method: 'POST',
    body:   JSON.stringify({ plate: _data.plate, payload: _pending }),
  });
  // NUI fecha ao receber action='fecharBennys' do Lua (BENNYS_CONFIRM → SendNUIMessage)
}


// ============================================================
// LUA MESSAGE BUS
// ============================================================

window.addEventListener('message', function (ev) {
  const msg = ev.data || {};
  if (msg.action === 'openBennys')   openBennys(msg.data);
  if (msg.action === 'fecharBennys') closeNUI();
});

document.getElementById('bn-btn-close').addEventListener('click',  cancelarBennys);
document.getElementById('bn-btn-cancel').addEventListener('click', cancelarBennys);
document.getElementById('bn-btn-apply').addEventListener('click',  aplicarBennys);

})();
