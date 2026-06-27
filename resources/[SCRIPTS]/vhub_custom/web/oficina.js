'use strict';

// IIFE: isola todo o estado/funções deste domínio do escopo global window,
// compartilhado com bennys.js/mec.js no mesmo documento (1 ui_page por resource).
(function () {

// ============================================================
// CONFIG DE COMPONENTES (visual + estimativas de boost)
// Os boost são estimativas para preview — não afetam a lógica server-side.
// ============================================================

const COMPONENT_DEFS = [
  {
    idx: 11, label: 'MOTOR',
    stages: [
      { stage: 0, name: 'Original',         desc: 'Motor de fábrica, sem modificações.',                        boost: {} },
      { stage: 1, name: 'EMS Upgrade Nv.1', desc: 'Filtro de ar esportivo e ajuste de injeção eletrônica.',    boost: { vel: 2, acel: 4 } },
      { stage: 2, name: 'EMS Upgrade Nv.2', desc: 'Cabeçotes polidos, velas de alta performance e intercooler.',boost: { vel: 5, acel: 7 } },
      { stage: 3, name: 'EMS Upgrade Nv.3', desc: 'Motor de corrida completo. Máximo de desempenho possível.', boost: { vel: 8, acel: 11 } },
    ],
  },
  {
    idx: 12, label: 'FREIOS',
    stages: [
      { stage: 0, name: 'Original',           desc: 'Sistema de série.',                                         boost: {} },
      { stage: 1, name: 'Street Brakes',      desc: 'Pastilhas performance e fluido DOT 5.',                    boost: { freio: 3 } },
      { stage: 2, name: 'Sport Brakes',       desc: 'Discos ventilados e pinças monobloco esportivas.',         boost: { freio: 6 } },
      { stage: 3, name: 'Race Brakes',        desc: 'Sistema de frenagem de competição com pinças 6 pistões.',  boost: { freio: 9 } },
    ],
  },
  {
    idx: 13, label: 'CÂMBIO',
    stages: [
      { stage: 0, name: 'Original',           desc: 'Câmbio de fábrica.',                                       boost: {} },
      { stage: 1, name: 'Street Transmission',desc: 'Óleo sintético e ajuste fino das relações.',               boost: { acel: 2, vel: 1 } },
      { stage: 2, name: 'Sport Transmission', desc: 'Relações recalibradas para troca mais rápida.',            boost: { acel: 4, vel: 2 } },
      { stage: 3, name: 'Race Transmission',  desc: 'Câmbio sequencial de corrida com paddle shift.',           boost: { acel: 6, vel: 3 } },
    ],
  },
  {
    idx: 15, label: 'SUSPENSÃO',
    stages: [
      { stage: 0, name: 'Original',            desc: 'Suspensão de série.',                                      boost: {} },
      { stage: 1, name: 'Lowering Kit',        desc: 'Rebaixamento moderado e molas esportivas.',                boost: { dir: 2 } },
      { stage: 2, name: 'Street Suspension',   desc: 'Amortecedores coilover reguláveis.',                       boost: { dir: 4 } },
      { stage: 3, name: 'Competition Setup',   desc: 'Suspensão de competição com geometria otimizada.',         boost: { dir: 6 } },
    ],
  },
  {
    idx: 16, label: 'BLINDAGEM',
    stages: [
      { stage: 0, name: 'Sem Proteção',     desc: 'Sem blindagem adicional.',                                 boost: {} },
      { stage: 1, name: 'Blindagem Leve',   desc: 'Proteção leve nas portas. Não afeta aceleração.',         boost: {} },
      { stage: 2, name: 'Blindagem Parcial',desc: 'Proteção no painel e portas. Pequena redução de velocidade.', boost: {} },
      { stage: 3, name: 'Blindagem Total',  desc: 'Blindagem completa. Resistência máxima a projéteis.',      boost: {} },
    ],
  },
  {
    idx: 18, label: 'TURBO', isTurbo: true,
    stages: [
      { stage: 0, name: 'Motor Aspirado',    desc: 'Sem compressor. Motor natural aspirado.',                 boost: {} },
      { stage: 1, name: 'Turbo Kit',         desc: 'Compressor turbo instalado. Ganho expressivo de torque.', boost: { vel: 4, acel: 5 } },
    ],
  },
];

// rótulos PT-BR dos 5 eixos reais (vhub_vehcontrol — fonte única, decisão #27)
const AXIS_DEFS = [
  { key: 'potencia',  label: 'POTÊNCIA'   },
  { key: 'grip',      label: 'ADERÊNCIA'  },
  { key: 'frenagem',  label: 'FRENAGEM'   },
  { key: 'aero',      label: 'AERO'       },
  { key: 'suspensao', label: 'SUSPENSÃO'  },
];

const TIER_CLS = { D: 't-D', C: 't-C', B: 't-B', A: 't-A', S: 't-S', 'S+': 't-Sp' };

const PRICE_KEYS = {
  11: 'engine_stage', 12: 'brakes_stage',
  13: 'transmission_stage', 15: 'suspension_stage',
  16: 'armor_stage',  18: 'turbo',
};

const STAGE_BADGE_CLS = ['sc-badge-default', 'sc-badge-1', 'sc-badge-2', 'sc-badge-3'];


// ============================================================
// STATE
// ============================================================

let _data         = null;   // payload do Lua (inclui _data.sheet — ficha REAL do vhub_vehcontrol)
let _selected     = {};     // { "modIdx": stage } seleções pendentes (compra de stage)
let _activeComp   = 0;      // índice em COMPONENT_DEFS do componente visível
let _closeTimeout = null;   // failsafe de fechamento
let _calibrating  = false;  // true = modo redistribuição ativo (sliders no lugar das barras)
let _draftAlloc   = null;   // alloc em edição durante calibração (não persistido até salvar)
let _previewSheet = null;   // ficha hipotética do draftAlloc (vem do servidor — getVehicleSheetPreview)
let _previewTimer = null;   // debounce do pedido de prévia ao arrastar slider
let _previewPending = false; // true entre o fetch e a resposta (distingue "carregando" de "erro")


// ============================================================
// HELPERS
// ============================================================

function fmtMoney(v) {
  return 'R$ ' + Number(v).toLocaleString('pt-BR');
}

function calcTotalCost() {
  if (!_data) return 0;
  let total = 0;
  const prices  = _data.prices || {};
  const current = _data.stages || {};
  for (const def of COMPONENT_DEFS) {
    const key      = String(def.idx);
    const curStage = Number(current[key] ?? 0);
    const selStage = Number(_selected[key] ?? curStage);
    if (selStage <= curStage) continue;
    if (def.isTurbo) {
      if (selStage >= 1 && curStage < 1) total += Number(prices.turbo ?? 0);
    } else {
      const tbl = prices[PRICE_KEYS[def.idx]] || {};
      total += Number(tbl[selStage] ?? 0);
    }
  }
  return total;
}

function effectiveStage(defIdx) {
  const key = String(defIdx);
  const cur = Number((_data.stages || {})[key] ?? 0);
  return Number(_selected[key] ?? cur);
}


// ============================================================
// RENDER — NAV
// ============================================================

function renderNav() {
  const nav = document.getElementById('comp-nav');
  nav.innerHTML = '';
  const cap     = Number(_data.stage_cap ?? 0);
  const current = _data.stages || {};

  COMPONENT_DEFS.forEach((def, i) => {
    const key      = String(def.idx);
    const curStage = Number(current[key] ?? 0);
    const selStage = Number(_selected[key] ?? curStage);
    const maxStage = def.isTurbo ? 1 : Math.min(cap, 3);

    const item = document.createElement('div');
    item.className = 'nav-item' + (i === _activeComp ? ' active' : '');
    item.addEventListener('click', () => setActiveComp(i));

    const lbl = document.createElement('span');
    lbl.className   = 'nav-label';
    lbl.textContent = def.label;

    const dots = document.createElement('div');
    dots.className = 'nav-stage-dots';

    for (let s = 1; s <= maxStage; s++) {
      const dot     = document.createElement('div');
      dot.className = 'nav-dot'
        + (s <= selStage  ? ' current' : '')
        + (s <= curStage && s !== selStage ? ' filled' : '');
      dots.appendChild(dot);
    }

    item.appendChild(lbl);
    if (maxStage > 0) item.appendChild(dots);
    nav.appendChild(item);
  });
}


// ============================================================
// RENDER — DETAIL (stage cards)
// ============================================================

function renderDetail() {
  const section = document.getElementById('comp-detail');
  section.innerHTML = '';

  const def     = COMPONENT_DEFS[_activeComp];
  const key     = String(def.idx);
  const cap     = Number(_data.stage_cap ?? 0);
  const curStage = Number((_data.stages || {})[key] ?? 0);
  const selStage = effectiveStage(def.idx);
  const prices  = _data.prices || {};
  const maxStage = def.isTurbo ? 1 : Math.min(cap, 3);

  const title = document.createElement('div');
  title.className   = 'comp-section-title';
  title.textContent = def.label + ' — selecione o nível';
  section.appendChild(title);

  for (const stageDef of def.stages) {
    const s   = stageDef.stage;
    const isInstalled = s === curStage && s > 0;
    const isSelected  = s === selStage;
    const isCapped    = s > maxStage && s > 0;

    const card = document.createElement('div');
    card.className = 'stage-card'
      + (isSelected  ? ' selected'    : '')
      + (isInstalled && !isSelected ? ' installed' : '')
      + (isCapped    ? ' disabled-cap' : '');

    if (!isCapped) card.addEventListener('click', () => selectStage(def.idx, s));

    // header
    const hdr = document.createElement('div');
    hdr.className = 'sc-header';

    const badge = document.createElement('span');
    badge.className   = 'sc-badge ' + (STAGE_BADGE_CLS[s] || 'sc-badge-default');
    badge.textContent = s === 0 ? 'PADRÃO' : 'STG ' + s;
    hdr.appendChild(badge);

    const name = document.createElement('span');
    name.className   = 'sc-name';
    name.textContent = stageDef.name;
    hdr.appendChild(name);

    if (isInstalled) {
      const tag = document.createElement('span');
      tag.className   = 'sc-installed-tag';
      tag.textContent = 'INSTALADO';
      hdr.appendChild(tag);
    } else if (s > 0 && !isCapped) {
      let price = null;
      if (def.isTurbo) {
        price = prices.turbo;
      } else {
        const tbl = prices[PRICE_KEYS[def.idx]] || {};
        price = tbl[s];
      }
      if (price != null) {
        const pr = document.createElement('span');
        pr.className   = 'sc-price';
        pr.textContent = fmtMoney(price);
        hdr.appendChild(pr);
      }
    } else if (isCapped) {
      const pr = document.createElement('span');
      pr.className   = 'sc-price';
      pr.style.color = 'var(--text-3)';
      pr.textContent = 'CAP atingido';
      hdr.appendChild(pr);
    }

    card.appendChild(hdr);

    // descrição
    const desc = document.createElement('div');
    desc.className   = 'sc-desc';
    desc.textContent = stageDef.desc;
    card.appendChild(desc);

    // boost pills
    if (s > 0 && Object.keys(stageDef.boost || {}).length > 0) {
      const boosts = document.createElement('div');
      boosts.className = 'sc-boosts';
      for (const [stat, delta] of Object.entries(stageDef.boost)) {
        const pill = document.createElement('span');
        pill.className   = 'boost-pill';
        pill.textContent = '+' + delta + ' ' + stat.toUpperCase();
        boosts.appendChild(pill);
      }
      card.appendChild(boosts);
    } else if (s > 0) {
      const boosts = document.createElement('div');
      boosts.className = 'sc-boosts';
      const pill = document.createElement('span');
      pill.className   = 'boost-pill neutral';
      pill.textContent = 'sem boost de desempenho';
      boosts.appendChild(pill);
      card.appendChild(boosts);
    }

    section.appendChild(card);
  }
}


// ============================================================
// RENDER — FICHA REAL (tier/score/alloc do vhub_vehcontrol)
// ============================================================

// soma os valores de um alloc { eixo: pontos }
function sumAlloc(a) {
  let t = 0;
  for (const ax of AXIS_DEFS) t += Number((a || {})[ax.key] || 0);
  return t;
}

// devolve o alloc ativo: rascunho em calibração ou o persistido da ficha
function activeAlloc() {
  const sheet = (_data && _data.sheet) || {};
  return _calibrating ? (_draftAlloc || {}) : (sheet.alloc || {});
}

function renderStats() {
  const sheet = (_data && _data.sheet) || null;

  const badgeEl = document.getElementById('tier-badge');
  const tier    = (sheet && sheet.tier) || 'D';
  badgeEl.textContent = tier;
  badgeEl.className   = 'tier-badge ' + (TIER_CLS[tier] || 't-D');

  const score = sheet ? Number(sheet.score || 0) : 0;
  document.getElementById('score-base').textContent = score;
  document.getElementById('sm-cur-base').style.left  = Math.min(100, score / 10) + '%';

  const budget = sheet ? Number(sheet.budget || 0) : 0;
  const alloc  = activeAlloc();

  // stat rows — 5 eixos reais, barra estática ou slider conforme o modo
  const rowsEl = document.getElementById('stat-rows');
  rowsEl.innerHTML = '';
  for (const ax of AXIS_DEFS) {
    const ranges = (sheet && sheet.ranges && sheet.ranges[ax.key]) || { min: 0, max: budget };
    const value  = Number(alloc[ax.key] || 0);
    const pct    = budget > 0 ? Math.min(100, (value / budget) * 100) : 0;

    const row = document.createElement('div');
    row.className = 'stat-row';

    const hdr = document.createElement('div');
    hdr.className = 'sr-header';

    const lbl = document.createElement('span');
    lbl.className   = 'sr-label';
    lbl.textContent = ax.label;
    hdr.appendChild(lbl);

    const nums = document.createElement('span');
    nums.className   = 'sr-nums';
    nums.textContent = value + ' pts';
    hdr.appendChild(nums);

    row.appendChild(hdr);

    if (_calibrating) {
      const slider = document.createElement('input');
      slider.type      = 'range';
      slider.className = 'sr-slider';
      slider.min       = ranges.min;
      slider.max       = ranges.max;
      slider.step      = 1;
      slider.value     = value;
      slider.dataset.ax = ax.key;
      slider.addEventListener('input', () => onSliderDrag(slider));
      row.appendChild(slider);
    } else {
      const barWrap = document.createElement('div');
      barWrap.className = 'sr-bar-wrap';

      const barPrev = document.createElement('div');
      barPrev.className   = 'sr-bar-prev';
      barPrev.style.width = pct + '%';

      barWrap.appendChild(barPrev);
      row.appendChild(barWrap);
    }

    rowsEl.appendChild(row);
  }

  renderCalibFooter(sheet, budget, alloc);
}

// redistribui pontos entre eixos ao arrastar um slider, mantendo soma == budget
// (mesmo algoritmo do vhub_vehcontrol/html/app.js — cópia independente por design,
// sem componente compartilhado entre resources)
function onSliderDrag(input) {
  if (!_draftAlloc) return;
  const sheet  = (_data && _data.sheet) || {};
  const ranges = sheet.ranges || {};
  const ax     = input.dataset.ax;
  const prev   = Number(_draftAlloc[ax] || 0);
  let next     = Number(input.value);
  const r      = ranges[ax] || { min: 0, max: next };
  next = Math.max(r.min, Math.min(r.max, next));

  let delta = next - prev;
  if (delta === 0) return;

  const others = AXIS_DEFS.map(a => a.key).filter(k => k !== ax);

  if (delta > 0) {
    // toma pontos das outras (respeitando o piso .min de cada uma)
    for (const ok of others) {
      if (delta <= 0) break;
      const or_  = ranges[ok] || { min: 0, max: 0 };
      const ov   = Number(_draftAlloc[ok] || 0);
      const take = Math.min(delta, Math.max(0, ov - or_.min));
      if (take > 0) { _draftAlloc[ok] = ov - take; delta -= take; }
    }
    next -= delta; // se não havia sobra suficiente, devolve o que não coube
  } else {
    // devolve o excedente às outras (respeitando o teto .max de cada uma)
    let surplus = -delta;
    for (const ok of others) {
      if (surplus <= 0) break;
      const or_   = ranges[ok] || { min: 0, max: 0 };
      const ov    = Number(_draftAlloc[ok] || 0);
      const give  = Math.min(surplus, Math.max(0, or_.max - ov));
      if (give > 0) { _draftAlloc[ok] = ov + give; surplus -= give; }
    }
  }

  _draftAlloc[ax] = next;
  requestPreview();
  renderStats();
}

// pede ao servidor a ficha hipotética do draftAlloc atual (debounced — não persiste nada)
function requestPreview() {
  clearTimeout(_previewTimer);
  _previewPending = true;
  _previewTimer = setTimeout(() => {
    if (!_calibrating || !_draftAlloc || !_data) return;
    fetch('https://vhub_custom/oficina:previewCalibrar', {
      method: 'POST',
      body:   JSON.stringify({ plate: _data.plate, alloc: _draftAlloc }),
    });
  }, 120);
}

function onPreviewCalibrarResultado(sheet) {
  _previewSheet   = sheet;
  _previewPending = false;
  if (_calibrating) renderCalibFooter((_data && _data.sheet) || null, Number((_data && _data.sheet && _data.sheet.budget) || 0), activeAlloc());
}

function renderCalibFooter(sheet, budget, alloc) {
  const btn = document.getElementById('btn-calibrar');
  btn.classList.toggle('active', _calibrating);
  btn.textContent = _calibrating ? 'Cancelar' : 'Calibrar';

  document.getElementById('calib-ftr').classList.toggle('hidden', !_calibrating);

  const compareEl = document.getElementById('score-compare');
  const hintEl     = document.getElementById('tier-hint');

  if (!_calibrating) {
    compareEl.classList.add('hidden');
    hintEl.classList.add('hidden');
    return;
  }

  const used = sumAlloc(alloc);
  const ok   = used === budget;
  document.getElementById('btn-calib-save').disabled = !ok;

  if (ok && _previewSheet) {
    compareEl.classList.remove('hidden');
    hintEl.classList.add('hidden');

    document.getElementById('sc-base-num').textContent = sheet ? Number(sheet.score || 0) : 0;
    const baseTier = (sheet && sheet.tier) || 'D';
    const sbEl = document.getElementById('sc-base-tier');
    sbEl.textContent = baseTier;
    sbEl.className   = 'sc-tier ' + (TIER_CLS[baseTier] || 't-D');

    document.getElementById('sc-prev-num').textContent = Number(_previewSheet.score || 0);
    const prevTier = _previewSheet.tier || 'D';
    const spEl = document.getElementById('sc-prev-tier');
    spEl.textContent = prevTier;
    spEl.className   = 'sc-tier ' + (TIER_CLS[prevTier] || 't-D');
  } else {
    compareEl.classList.add('hidden');
    hintEl.classList.remove('hidden');
    if (!ok) {
      hintEl.textContent = `Distribuição inválida (${used} / ${budget}) — ajuste os eixos`;
      hintEl.className   = 'tier-hint neg';
    } else if (_previewPending) {
      hintEl.textContent = 'Calculando prévia...';
      hintEl.className   = 'tier-hint';
    } else {
      hintEl.textContent = 'Prévia indisponível — tente ajustar novamente.';
      hintEl.className   = 'tier-hint neg';
    }
  }
}


// ============================================================
// RENDER — FOOTER
// ============================================================

function renderFooter() {
  const total = calcTotalCost();
  const cap   = Number(_data.stage_cap ?? 0);
  document.getElementById('total-cost').textContent  = fmtMoney(total);
  document.getElementById('btn-apply').disabled      = (total === 0);
  document.getElementById('cap-info').textContent    =
    cap === 0 ? '⚠ Tuning indisponível para esta classe' : `Cap: Stage ${cap}  ·  Classe GTA ${_data.classe_gta ?? '?'}`;
}


// ============================================================
// INTERACTION
// ============================================================

function setActiveComp(idx) {
  _activeComp = idx;
  renderNav();
  renderDetail();
}

function selectStage(modIdx, stage) {
  const key      = String(modIdx);
  const curStage = Number((_data.stages || {})[key] ?? 0);
  if (stage === curStage) {
    delete _selected[key];
  } else {
    _selected[key] = stage;
  }
  renderNav();
  renderDetail();
  renderStats();
  renderFooter();
}


// ============================================================
// OPEN / CLOSE
// ============================================================

function openOficina(data) {
  _data           = data;
  _selected       = {};
  _activeComp     = 0;
  _calibrating    = false;
  _draftAlloc     = null;
  _previewSheet   = null;
  _previewPending = false;

  document.getElementById('veh-nome').textContent = data.nome || '—';
  document.getElementById('veh-sub').textContent  =
    (data.categoria || '—') + '  ·  ' + (data.plate || '—');

  renderNav();
  renderDetail();
  renderStats();
  renderFooter();

  document.getElementById('overlay').classList.remove('hidden');
  document.getElementById('btn-cancel').disabled = false;
  document.getElementById('btn-apply').disabled  = (calcTotalCost() === 0);

  // failsafe: se o servidor não responder em 20s, fecha e notifica Lua (libera NuiFocus)
  clearTimeout(_closeTimeout);
  _closeTimeout = setTimeout(() => {
    if (_data) cancelarOficina();
  }, 20000);
}

function closeNUI() {
  clearTimeout(_closeTimeout);
  clearTimeout(_previewTimer);
  _closeTimeout = null;
  document.getElementById('overlay').classList.add('hidden');
  _data           = null;
  _selected       = {};
  _calibrating    = false;
  _draftAlloc     = null;
  _previewSheet   = null;
  _previewPending = false;
}

function cancelarOficina() {
  closeNUI();
  fetch('https://vhub_custom/oficina:fechar', { method: 'POST', body: '{}' });
}

// ============================================================
// CALIBRAÇÃO — redistribuição de pontos livres (decisão #27)
// ============================================================

function entrarCalibragem() {
  const sheet = (_data && _data.sheet) || null;
  if (!sheet || !sheet.tier) return;
  _calibrating = true;
  _draftAlloc  = {};
  for (const ax of AXIS_DEFS) _draftAlloc[ax.key] = Number((sheet.alloc || {})[ax.key] || 0);
  _previewSheet   = sheet; // ponto de partida = ficha real (alloc atual == draft atual)
  _previewPending = false;
  renderStats();
}

function cancelarCalibragem() {
  clearTimeout(_previewTimer);
  _calibrating    = false;
  _draftAlloc     = null;
  _previewSheet   = null;
  _previewPending = false;
  renderStats();
}

function salvarCalibragem() {
  if (!_draftAlloc || !_data) return;
  document.getElementById('btn-calib-save').disabled = true;
  fetch('https://vhub_custom/oficina:recalibrar', {
    method: 'POST',
    body:   JSON.stringify({ plate: _data.plate, alloc: _draftAlloc }),
  });
}

function onRecalibrarResultado(ok, sheet) {
  document.getElementById('btn-calib-save').disabled = false;
  if (ok && sheet && _data) {
    _data.sheet     = sheet;
    _calibrating    = false;
    _draftAlloc     = null;
    _previewSheet   = null;
    _previewPending = false;
  }
  renderStats();
}

function aplicarTuning() {
  if (!_data || calcTotalCost() === 0) return;

  const mods = {};
  const current = _data.stages || {};
  for (const def of COMPONENT_DEFS) {
    const key      = String(def.idx);
    const curStage = Number(current[key] ?? 0);
    mods[key]      = Number(_selected[key] ?? curStage);
  }

  document.getElementById('btn-apply').disabled  = true;
  document.getElementById('btn-cancel').disabled = true;

  fetch('https://vhub_custom/oficina:aplicarTuning', {
    method: 'POST',
    body:   JSON.stringify({ plate: _data.plate, mods }),
  });
  // NUI fecha ao receber action='fecharOficina' do Lua (OFICINA_CONFIRM → SendNUIMessage)
}


// ============================================================
// LUA MESSAGE BUS
// ============================================================

window.addEventListener('message', function (ev) {
  const msg = ev.data || {};
  if (msg.action === 'openOficina')             openOficina(msg.data);
  if (msg.action === 'fecharOficina')           closeNUI();
  if (msg.action === 'recalibrarResultado')     onRecalibrarResultado(msg.ok === true, msg.data || null);
  if (msg.action === 'previewCalibrarResultado') onPreviewCalibrarResultado(msg.data || null);
  if (msg.action === 'nitroKitResultado')       { var bn = document.getElementById('btn-nitro-kit'); if (bn) bn.disabled = false; }
});

document.getElementById('btn-close').addEventListener('click',  cancelarOficina);
document.getElementById('btn-cancel').addEventListener('click', cancelarOficina);
document.getElementById('btn-apply').addEventListener('click',  aplicarTuning);

// kit nitro: instala via oficina (cobra); estado real escrito por vhub_nitro (decisão #29)
var _btnNitro = document.getElementById('btn-nitro-kit');
if (_btnNitro) _btnNitro.addEventListener('click', function () {
  if (!_data || !_data.plate) return;
  _btnNitro.disabled = true;
  fetch('https://vhub_custom/oficina:instalarKitNitro', {
    method:  'POST',
    headers: { 'Content-Type': 'application/json' },
    body:    JSON.stringify({ plate: _data.plate }),
  }).catch(function () { _btnNitro.disabled = false; });
});

document.getElementById('btn-calibrar').addEventListener('click', function () {
  if (_calibrating) cancelarCalibragem(); else entrarCalibragem();
});
document.getElementById('btn-calib-cancel').addEventListener('click', cancelarCalibragem);
document.getElementById('btn-calib-save').addEventListener('click',   salvarCalibragem);

})();
