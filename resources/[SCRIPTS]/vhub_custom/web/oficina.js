'use strict';

// oficina.js — NUI da OFICINA — bancada de engenharia AAA (ADR #82 F2.3 redesign).
//
// Layout: diagrama SVG central com 9 slots clicáveis → gaveta horizontal de peças da família
// ativa → aside de telemetria/calibração (preservado). Drag & drop via Pointer Events (não
// HTML5 drag API — quirks de ghost no CEF). Server-authoritative: NUI dispara intenção,
// re-renderiza do estado fresco devolvido (applyFresh — sem 2ª fonte de verdade, A-04).
//
// Contratos preservados:
//   oficina:instalarParte → instalarParteResultado
//   oficina:removerParte  → removerParteResultado
//   oficina:recalibrar    → recalibrarResultado
//   oficina:previewCalibrar → previewCalibrarResultado
//   oficina:instalarKitNitro → nitroKitResultado
//   oficina:fechar
//
// IIFE: isola estado deste domínio (documento compartilhado com bennys/mec).
(function () {

let _module = null;


// ============================================================
// CONSTANTES
// ============================================================

// rótulos PT-BR dos 5 eixos reais (vhub_vehcontrol — fonte única, decisão #27)
const AXIS_DEFS = [
  { key: 'potencia',  label: 'POTÊNCIA'  },
  { key: 'grip',      label: 'ADERÊNCIA' },
  { key: 'frenagem',  label: 'FRENAGEM'  },
  { key: 'aero',      label: 'AERO'      },
  { key: 'suspensao', label: 'SUSPENSÃO' },
];

const AXIS_SHORT = {
  potencia: 'POT', grip: 'ADER', frenagem: 'FRE', aero: 'AERO', suspensao: 'SUSP',
};

const MAX_PILLS = 3;

// rótulos PT-BR das 9 famílias — mapeado pelo data-family do SVG
const FAM_LABELS = {
  engine:       'MOTOR',
  turbo:        'TURBO',
  ecu:          'ECU / MAPEAMENTO',
  transmission: 'CÂMBIO',
  brakes:       'FREIOS',
  suspension:   'SUSPENSÃO',
  aero:         'AERODINÂMICA',
  weight:       'REDUÇÃO DE PESO',
  handbrake:    'FREIO DE MÃO',
};


// ============================================================
// STATE
// ============================================================

let _data           = null;   // payload do Lua (parts_catalog + sheet + installed_parts)
let _activeFamId    = null;   // family_id (string) do slot SVG selecionado
let _installing     = false;  // trava anti-duplo-clique durante install em voo
let _calibrating    = false;  // modo redistribuição de pontos (sliders)
let _draftAlloc     = null;   // alloc em edição durante calibração
let _previewSheet   = null;   // ficha hipotética do draftAlloc (server)
let _previewTimer   = null;   // debounce do pedido de prévia
let _previewPending = false;

// drag & drop — estado isolado (nunca persiste entre gestos)
let _drag = { active: false, partId: null, ghostEl: null, origFamId: null, hitSlot: null };

// referências de handlers para removeEventListener posterior (runtime condição 2)
let _onTrayPointerDown = null;
let _onDocPointerMove  = null;
let _onDocPointerUp    = null;
let _onDocPointerCancel = null;


// ============================================================
// HELPERS
// ============================================================

function fmtMoney(v) {
  return 'R$ ' + Number(v || 0).toLocaleString('pt-BR');
}

function pct(v) {
  return '+' + Math.round((Number(v) || 0) * 100) + '%';
}

// famílias do catálogo com suas peças; filtra vazias
function familiesWithParts() {
  const cat = (_data && _data.parts_catalog) || null;
  if (!cat || !Array.isArray(cat.families) || !Array.isArray(cat.parts)) return [];
  const byFamily = {};
  for (const p of cat.parts) (byFamily[p.family] = byFamily[p.family] || []).push(p);
  return cat.families
    .map((f) => ({ ...f, parts: byFamily[f.id] || [] }))
    .filter((f) => f.parts.length > 0);
}

// partes de uma família pelo id
function partsOfFamily(famId) {
  const fams = familiesWithParts();
  const fam  = fams.find((f) => f.id === famId);
  return fam ? fam.parts : [];
}

// status HONESTO da peça (server-authoritative), { state, hint?, replaces? }
// state: ok | already_installed | conflict | requires_missing | missing_item
function partStatus(part) {
  const ps = (_data && _data.parts_status) || null;
  if (ps && ps[part.id]) return ps[part.id];
  const inst = (_data && _data.installed_parts) || {};
  return { state: inst[part.id] === true ? 'already_installed' : 'ok' };
}

function isInstalled(part) { return partStatus(part).state === 'already_installed'; }

function nameOfPart(id) {
  const cat = (_data && _data.parts_catalog) || null;
  if (!cat || !Array.isArray(cat.parts)) return id;
  const p = cat.parts.find((x) => x.id === id);
  return (p && p.name) || id;
}

// se alguma peça de uma família está instalada (ponto no slot SVG)
function famHasInstalled(famId) {
  const parts = partsOfFamily(famId);
  return parts.some((p) => isInstalled(p));
}


// ============================================================
// RENDER — DIAGRAMA SVG (slots por família)
// ============================================================

// aplica classes de estado aos <g class="slot"> do SVG
function renderDiagram() {
  const diagramEl = document.getElementById('oficina-diagram');
  if (!diagramEl) return;

  const slots = diagramEl.querySelectorAll('.slot[data-family]');
  slots.forEach((slot) => {
    const famId    = slot.dataset.family;
    const active   = famId === _activeFamId;
    const hasInst  = famHasInstalled(famId);
    const hasParts = partsOfFamily(famId).length > 0;

    // remove todas as classes de estado e reaplica (evita acúmulo)
    slot.classList.remove('active', 'installed', 'empty');
    if (!hasParts) slot.classList.add('empty');
    if (hasInst)  slot.classList.add('installed');
    if (active)   slot.classList.add('active');
  });
}

// label da família ativa no cabeçalho do diagrama
function renderDiagramLabel() {
  const el = document.getElementById('diagram-fam-label');
  if (!el) return;
  if (_activeFamId) {
    el.textContent = FAM_LABELS[_activeFamId] || _activeFamId.toUpperCase();
  } else {
    el.textContent = 'SELECIONE UM SISTEMA';
  }
}


// ============================================================
// RENDER — GAVETA DE PEÇAS (horizontal, família ativa)
// ============================================================

function renderTray() {
  const tray = document.getElementById('parts-tray');
  if (!tray) return;
  tray.innerHTML = '';

  if (!_activeFamId || !_data) {
    const msg = document.createElement('div');
    msg.className   = 'tray-empty';
    msg.textContent = 'Selecione um sistema no diagrama acima.';
    tray.appendChild(msg);
    return;
  }

  const parts = partsOfFamily(_activeFamId);
  if (parts.length === 0) {
    const msg = document.createElement('div');
    msg.className   = 'tray-empty';
    msg.textContent = 'Nenhuma peça disponível para este sistema.';
    tray.appendChild(msg);
    return;
  }

  for (const part of parts) {
    const st        = partStatus(part);
    const state     = st.state;
    const installed = state === 'already_installed';
    const blocked   = state === 'conflict' || state === 'requires_missing';
    const noItem    = state === 'missing_item';

    const card = document.createElement('div');
    card.className = 'tray-card'
      + (installed ? ' installed' : '')
      + (blocked   ? ' blocked'   : '')
      + (noItem    ? ' need-item' : '');
    card.dataset.partId  = part.id;
    card.dataset.famId   = part.family;
    card.draggable       = false; // drag via Pointer Events, não HTML5

    // badge de estado
    const badge = document.createElement('span');
    badge.className = 'tray-badge';
    if (installed)    { badge.classList.add('on');   badge.textContent = 'INSTALADA'; }
    else if (blocked) { badge.classList.add('warn'); badge.textContent = 'BLOQUEADA'; }
    else if (noItem)  { badge.classList.add('muted');badge.textContent = 'SEM ITEM';  }
    else              { badge.textContent = Number(part.price || 0) > 0 ? fmtMoney(part.price) : 'incluso'; }
    card.appendChild(badge);

    // nome da peça
    const nameEl = document.createElement('div');
    nameEl.className   = 'tray-name';
    nameEl.textContent = part.name;
    card.appendChild(nameEl);

    // deltas compactos (máx 3 pílulas)
    card.appendChild(deltaPills(part.deltas));

    // hint não-bloqueante (ADR #85)
    if (st.hint) {
      const h = document.createElement('div');
      h.className   = 'tray-hint';
      h.textContent = '⚠ ' + st.hint;
      card.appendChild(h);
    }

    // botões de ação
    const btnsRow = document.createElement('div');
    btnsRow.className = 'tray-btns';
    if (installed) {
      const btn = document.createElement('button');
      btn.className   = 'part-remove';
      btn.textContent = 'REMOVER';
      btn.disabled    = _installing;
      btn.addEventListener('click', (e) => { e.stopPropagation(); removePart(part.id, btn); });
      btnsRow.appendChild(btn);
    } else if (state === 'ok') {
      const btn = document.createElement('button');
      btn.className   = 'part-install';
      btn.textContent = 'INSTALAR';
      btn.disabled    = _installing;
      btn.addEventListener('click', (e) => { e.stopPropagation(); installPart(part.id, btn); });
      btnsRow.appendChild(btn);
    }
    if (btnsRow.children.length > 0) card.appendChild(btnsRow);

    tray.appendChild(card);
  }
}

// pílulas de trade-off (reutilizadas na gaveta)
function deltaPills(deltas) {
  const wrap = document.createElement('div');
  wrap.className = 'eng-deltas';
  const entries = Object.entries(deltas || {}).filter(([, n]) => Number(n) !== 0);

  if (entries.length === 0) {
    const pill = document.createElement('span');
    pill.className = 'eng-pill neutral';
    pill.textContent = 'sem efeito';
    wrap.appendChild(pill);
    return wrap;
  }

  entries.sort((a, b) => Number(b[1]) - Number(a[1]));
  const shown = entries.slice(0, MAX_PILLS);
  const rest  = entries.length - shown.length;

  for (const [ax, n] of shown) {
    const v = Number(n);
    const pill = document.createElement('span');
    pill.className = 'eng-pill ' + (v > 0 ? 'pos' : 'neg');
    pill.textContent = (v > 0 ? '+' : '') + v + ' ' + (AXIS_SHORT[ax] || ax.toUpperCase());
    wrap.appendChild(pill);
  }
  if (rest > 0) {
    const more = document.createElement('span');
    more.className = 'eng-pill neutral';
    more.textContent = '+' + rest;
    wrap.appendChild(more);
  }
  return wrap;
}

// badge de estado por peça (usado na gaveta)
function stateTag(state, part) {
  const tag = document.createElement('span');
  if (state === 'already_installed')     { tag.className = 'part-badge on';   tag.textContent = 'INSTALADA'; }
  else if (state === 'conflict')         { tag.className = 'part-badge warn'; tag.textContent = 'INCOMPATÍVEL'; }
  else if (state === 'requires_missing') { tag.className = 'part-badge warn'; tag.textContent = 'REQUER PEÇA'; }
  else if (state === 'missing_item')     { tag.className = 'part-badge muted';tag.textContent = 'SEM PEÇA'; }
  else { tag.className = 'part-price'; tag.textContent = Number(part.price || 0) > 0 ? fmtMoney(part.price) : 'incluso'; }
  return tag;
}

function blockReason(state) {
  if (state === 'missing_item')     return 'Você não possui esta peça no inventário.';
  if (state === 'conflict')         return 'Incompatível com uma peça já instalada.';
  if (state === 'requires_missing') return 'Requer outra peça instalada antes.';
  return '';
}


// ============================================================
// RENDER — EFEITO DERIVADO + FICHA/CALIBRAÇÃO (aside — preservado)
// ============================================================

function renderEngEffect() {
  const sheet = (_data && _data.sheet) || {};
  const eng   = (sheet && sheet.eng) || null;
  document.getElementById('ee-power').textContent = eng ? pct(eng.power_boost)   : '+0%';
  document.getElementById('ee-top').textContent   = eng ? pct(eng.top_speed_pct) : '+0%';

  const massEl = document.getElementById('ee-mass');
  if (massEl) {
    if (sheet && typeof sheet.mass === 'number') {
      const d = Number(sheet.mass_delta || 0);
      const sign = d > 0 ? ' (+' + d + ')' : d < 0 ? ' (' + d + ')' : '';
      massEl.textContent = Math.round(sheet.mass) + ' kg' + sign;
    } else {
      massEl.textContent = '—';
    }
  }
}

function sumAlloc(a) {
  let t = 0;
  for (const ax of AXIS_DEFS) t += Number((a || {})[ax.key] || 0);
  return t;
}

function activeAlloc() {
  const sheet = (_data && _data.sheet) || {};
  return _calibrating ? (_draftAlloc || {}) : (sheet.alloc || {});
}

function renderStats() {
  const sheet = (_data && _data.sheet) || null;

  const score = sheet ? Number(sheet.score || 0) : 0;
  document.getElementById('score-base').textContent = score;
  document.getElementById('sm-cur-base').style.left  = Math.min(100, score / 10) + '%';

  const budget = sheet ? Number(sheet.budget || 0) : 0;
  const alloc  = activeAlloc();

  const rowsEl = document.getElementById('stat-rows');
  rowsEl.innerHTML = '';
  for (const ax of AXIS_DEFS) {
    const ranges = (sheet && sheet.ranges && sheet.ranges[ax.key]) || { min: 0, max: budget };
    const value  = Number(alloc[ax.key] || 0);
    const p      = budget > 0 ? Math.min(100, (value / budget) * 100) : 0;

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
      slider.type       = 'range';
      slider.className  = 'sr-slider';
      slider.min        = ranges.min;
      slider.max        = ranges.max;
      slider.step       = 1;
      slider.value      = value;
      slider.dataset.ax = ax.key;
      slider.addEventListener('input', () => onSliderDrag(slider));
      row.appendChild(slider);
    } else {
      const barWrap = document.createElement('div');
      barWrap.className = 'sr-bar-wrap';
      const barPrev = document.createElement('div');
      barPrev.className   = 'sr-bar-prev';
      barPrev.style.width = p + '%';
      barWrap.appendChild(barPrev);
      row.appendChild(barWrap);
    }
    rowsEl.appendChild(row);
  }

  renderCalibFooter(sheet, budget, alloc);
}


// ============================================================
// CALIBRAÇÃO — redistribuição de pontos livres
// ============================================================

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

  const others = AXIS_DEFS.map((a) => a.key).filter((k) => k !== ax);

  if (delta > 0) {
    for (const ok of others) {
      if (delta <= 0) break;
      const or_  = ranges[ok] || { min: 0, max: 0 };
      const ov   = Number(_draftAlloc[ok] || 0);
      const take = Math.min(delta, Math.max(0, ov - or_.min));
      if (take > 0) { _draftAlloc[ok] = ov - take; delta -= take; }
    }
    next -= delta;
  } else {
    let surplus = -delta;
    for (const ok of others) {
      if (surplus <= 0) break;
      const or_  = ranges[ok] || { min: 0, max: 0 };
      const ov   = Number(_draftAlloc[ok] || 0);
      const give = Math.min(surplus, Math.max(0, or_.max - ov));
      if (give > 0) { _draftAlloc[ok] = ov + give; surplus -= give; }
    }
  }

  _draftAlloc[ax] = next;
  requestPreview();
  renderStats();
}

function requestPreview() {
  clearTimeout(_previewTimer);
  _previewPending = true;
  _previewTimer = setTimeout(() => {
    if (!_calibrating || !_draftAlloc || !_data) return;
    window.vhub.request('oficina:previewCalibrar', { plate: _data.plate, alloc: _draftAlloc })
      .catch(() => { _previewPending = false; });
  }, 120);
}

function onPreviewCalibrarResultado(sheet) {
  _previewSheet   = sheet;
  _previewPending = false;
  if (_calibrating) {
    const s = (_data && _data.sheet) || null;
    renderCalibFooter(s, Number((s && s.budget) || 0), activeAlloc());
  }
}

function renderCalibFooter(sheet, budget, alloc) {
  const btn = document.getElementById('btn-calibrar');
  btn.classList.toggle('active', _calibrating);
  btn.textContent = _calibrating ? 'Cancelar' : 'Calibrar';

  document.getElementById('calib-ftr').classList.toggle('hidden', !_calibrating);

  const compareEl = document.getElementById('score-compare');
  const hintEl    = document.getElementById('tier-hint');

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
    document.getElementById('sc-prev-num').textContent = Number(_previewSheet.score || 0);
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

function entrarCalibragem() {
  const sheet = (_data && _data.sheet) || null;
  if (!sheet || !sheet.tier) return;
  _calibrating = true;
  _draftAlloc  = {};
  for (const ax of AXIS_DEFS) _draftAlloc[ax.key] = Number((sheet.alloc || {})[ax.key] || 0);
  _previewSheet   = sheet;
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
  window.vhub.request('oficina:recalibrar', { plate: _data.plate, alloc: _draftAlloc })
    .catch(() => { if (_data) document.getElementById('btn-calib-save').disabled = false; });
}

function onRecalibrarResultado(ok, sheet) {
  document.getElementById('btn-calib-save').disabled = false;
  if (ok && sheet && _data) {
    _data.sheet     = sheet;
    _calibrating    = false;
    _draftAlloc     = null;
    _previewSheet   = null;
    _previewPending = false;
    renderEngEffect();
  }
  renderStats();
}

function toggleCalibragem() {
  if (_calibrating) cancelarCalibragem(); else entrarCalibragem();
}


// ============================================================
// INSTALAR / REMOVER PEÇA (server-authoritative)
// ============================================================

function setActiveFam(famId) {
  _activeFamId = famId || null;
  renderDiagram();
  renderDiagramLabel();
  renderTray();
}

function installPart(partId, btn) {
  if (_installing || !_data || !partId) return;
  _installing = true;
  if (btn) { btn.disabled = true; btn.textContent = '...'; }
  window.vhub.request('oficina:instalarParte', { part_id: partId })
    .catch(() => { _installing = false; renderTray(); });
}

function removePart(partId, btn) {
  if (_installing || !_data || !partId) return;
  _installing = true;
  if (btn) { btn.disabled = true; btn.textContent = '...'; }
  window.vhub.request('oficina:removerParte', { part_id: partId })
    .catch(() => { _installing = false; renderTray(); });
}

// aplica estado fresco AUTORITATIVO — nunca 2ª fonte de verdade (A-04, skill nui_fresh_state_rerender)
function applyFresh(data) {
  if (!data || !_data) return false;
  if (data.installed_parts) _data.installed_parts = data.installed_parts;
  if (data.parts_status)    _data.parts_status    = data.parts_status;
  if (data.sheet)           _data.sheet           = data.sheet;
  return true;
}

function onParteResultado(ok, data) {
  _installing = false;
  if (ok && applyFresh(data)) renderEngEffect();
  renderDiagram();
  renderTray();
  renderStats();
}


// ============================================================
// DRAG & DROP — Pointer Events (não HTML5 — quirks de ghost no CEF)
// Fluxo: pointerdown na gaveta → cria ghost → pointermove move ghost →
//        hit-test sobre slot SVG → pointerup confirma drop → installPart() (server)
// ============================================================

function createDragGhost(partName, x, y) {
  const ghost = document.createElement('div');
  ghost.className   = 'drag-ghost';
  ghost.textContent = partName;
  ghost.style.left  = x + 'px';
  ghost.style.top   = y + 'px';
  document.body.appendChild(ghost);
  return ghost;
}

function destroyDragGhost() {
  if (_drag.ghostEl) {
    _drag.ghostEl.remove();
    _drag.ghostEl = null;
  }
}

// cancela o drag em curso (pointercancel, ESC, onDestroy mid-drag)
function cancelDrag() {
  destroyDragGhost();
  // limpa highlight de slot que estava com drop-target
  if (_drag.hitSlot) {
    _drag.hitSlot.classList.remove('drop-target', 'drop-ok', 'drop-bad');
    _drag.hitSlot = null;
  }
  _drag.active    = false;
  _drag.partId    = null;
  _drag.origFamId = null;
}

// Delegação de pointerdown no container da gaveta — bind em onMount (handler nomeado)
function _buildTrayPointerDown() {
  return function onTrayPointerDown(event) {
    if (event.button !== 0) return;  // só botão primário
    const card = event.target.closest('.tray-card[data-part-id]');
    if (!card) return;

    const partId  = card.dataset.partId;
    const famId   = card.dataset.famId;

    // só peças no estado "ok" são arrastáveis
    const part = ((_data && _data.parts_catalog && _data.parts_catalog.parts) || []).find((p) => p.id === partId);
    if (!part) return;
    const st = partStatus(part);
    if (st.state !== 'ok') return;

    _drag.active    = true;
    _drag.partId    = partId;
    _drag.origFamId = famId;
    _drag.hitSlot   = null;
    _drag.ghostEl   = createDragGhost(part.name, event.clientX + 12, event.clientY + 12);

    // captura o pointer para receber eventos mesmo fora do elemento
    event.currentTarget.setPointerCapture(event.pointerId);
    event.preventDefault();
  };
}

function _buildDocPointerMove() {
  return function onDocPointerMove(event) {
    if (!_drag.active) return;

    // guard: se o botão primário foi solto fora da janela CEF, o pointerup pode não ter chegado
    if (!(event.buttons & 1)) { cancelDrag(); return; }

    // move ghost
    if (_drag.ghostEl) {
      _drag.ghostEl.style.left = (event.clientX + 12) + 'px';
      _drag.ghostEl.style.top  = (event.clientY + 12) + 'px';
    }

    // hit-test sobre o SVG — elementFromPoint pode retornar filho interno do <g>
    _drag.ghostEl && (_drag.ghostEl.style.display = 'none');
    const el   = document.elementFromPoint(event.clientX, event.clientY);
    _drag.ghostEl && (_drag.ghostEl.style.display = '');

    const slot = el && el.closest('.slot[data-family]');

    // limpa highlight anterior
    if (_drag.hitSlot && _drag.hitSlot !== slot) {
      _drag.hitSlot.classList.remove('drop-target', 'drop-ok', 'drop-bad');
    }

    if (slot) {
      const targetFam = slot.dataset.family;
      const validDrop = targetFam === _drag.origFamId;
      slot.classList.add('drop-target');
      slot.classList.toggle('drop-ok',  validDrop);
      slot.classList.toggle('drop-bad', !validDrop);
      _drag.hitSlot = slot;
    } else {
      _drag.hitSlot = null;
    }
  };
}

function _buildDocPointerUp() {
  return function onDocPointerUp() {
    if (!_drag.active) return;

    // captura antes de cancelDrag resetar o estado
    const partId  = _drag.partId;
    const hitSlot = _drag.hitSlot;

    // cleanup obrigatório (A-07): ghost, highlight, _drag reset
    cancelDrag();

    // avalia se o drop caiu num slot compatível com a peça arrastada
    if (hitSlot && partId) {
      const part = ((_data && _data.parts_catalog && _data.parts_catalog.parts) || []).find((p) => p.id === partId);
      const validFam = part && hitSlot.dataset.family === part.family;
      if (validFam && !_installing) {
        installPart(partId, null);
      }
    }
  };
}

function _buildDocPointerCancel() {
  return function onDocPointerCancel() {
    if (_drag.active) cancelDrag();
  };
}


// ============================================================
// SLOT SVG — clique direto (sem drag)
// ============================================================

function onSlotClick(event) {
  // ignora durante drag ou logo após soltar
  if (_drag.active) return;
  const slot = event.target.closest('.slot[data-family]');
  if (!slot) return;
  const famId = slot.dataset.family;
  if (famId === _activeFamId) {
    // clique no slot já ativo: desseleciona
    setActiveFam(null);
  } else {
    setActiveFam(famId);
  }
}


// ============================================================
// FOOTER / CAP
// ============================================================

function renderCapInfo() {
  const cat = (_data && _data.categoria) || 'categoria desconhecida';
  document.getElementById('cap-info').textContent =
    'Classe base: ' + cat + '  ·  peças acima do ideal recebem aviso, mas podem ser instaladas';
}


// ============================================================
// OPEN / CLOSE
// ============================================================

function openOficina(data) {
  _data           = data;
  _activeFamId    = null;
  _installing     = false;
  _calibrating    = false;
  _draftAlloc     = null;
  _previewSheet   = null;
  _previewPending = false;
  cancelDrag();

  document.getElementById('veh-nome').textContent = data.nome || '—';
  document.getElementById('veh-sub').textContent  =
    (data.categoria || '—') + '  ·  ' + (data.plate || '—');

  renderDiagram();
  renderDiagramLabel();
  renderTray();
  renderEngEffect();
  renderStats();
  renderCapInfo();

  document.getElementById('overlay').classList.remove('hidden');
  document.getElementById('btn-cancel').disabled = false;
}

function closeNUI() {
  clearTimeout(_previewTimer);
  _previewTimer = null;
  cancelDrag();  // cleanup ghost mid-drag (A-07)
  document.getElementById('overlay').classList.add('hidden');
  _data           = null;
  _activeFamId    = null;
  _installing     = false;
  _calibrating    = false;
  _draftAlloc     = null;
  _previewSheet   = null;
  _previewPending = false;
}

function cancelarOficina() {
  _module.hide();
  window.vhub.request('oficina:fechar', {}).catch(() => {});
}


// ============================================================
// NITRO (contrato preservado)
// ============================================================

const _btnNitro = document.getElementById('btn-nitro-kit');

function instalarNitro() {
  if (!_data || !_data.plate) return;
  _btnNitro.disabled = true;
  window.vhub.request('oficina:instalarKitNitro', { plate: _data.plate })
    .catch(() => { if (_data) _btnNitro.disabled = false; });
}


// ============================================================
// LUA MESSAGE BUS + LIFECYCLE
// ============================================================

function onKeydown(event) {
  if (event.key === 'Escape' && _data) cancelarOficina();
}

_module = window.vhub.createModule('oficina', {
  actions: {
    openOficina:             (message, api) => api.show(message.data),
    fecharOficina:           (_message, api) => api.hide(),
    instalarParteResultado:  (message) => onParteResultado(message.ok === true, message.data || null),
    removerParteResultado:   (message) => onParteResultado(message.ok === true, message.data || null),
    recalibrarResultado:     (message) => onRecalibrarResultado(message.ok === true, message.data || null),
    previewCalibrarResultado:(message) => onPreviewCalibrarResultado(message.data || null),
    nitroKitResultado:       () => { if (_btnNitro) _btnNitro.disabled = false; },
  },

  onInit() {
    // botões estáticos — DOM garantido antes de onInit pelo runtime
    document.getElementById('btn-close').addEventListener('click', cancelarOficina);
    document.getElementById('btn-cancel').addEventListener('click', cancelarOficina);
    if (_btnNitro) _btnNitro.addEventListener('click', instalarNitro);
    document.getElementById('btn-calibrar').addEventListener('click', toggleCalibragem);
    document.getElementById('btn-calib-cancel').addEventListener('click', cancelarCalibragem);
    document.getElementById('btn-calib-save').addEventListener('click', salvarCalibragem);
    window.addEventListener('keydown', onKeydown);

    // clique nos slots SVG (delegado ao diagrama, não a cada <g>)
    const diagramEl = document.getElementById('oficina-diagram');
    if (diagramEl) diagramEl.addEventListener('click', onSlotClick);
  },

  onMount() {
    // drag & drop via Pointer Events — handlers nomeados para removeEventListener (runtime condição 2)
    // bind em onMount pois o container da gaveta precisa do DOM montado
    const tray = document.getElementById('parts-tray');
    if (!tray) return;

    _onTrayPointerDown  = _buildTrayPointerDown();
    _onDocPointerMove   = _buildDocPointerMove();
    _onDocPointerUp     = _buildDocPointerUp();
    _onDocPointerCancel = _buildDocPointerCancel();

    tray.addEventListener('pointerdown', _onTrayPointerDown);
    document.addEventListener('pointermove',   _onDocPointerMove);
    document.addEventListener('pointerup',     _onDocPointerUp);
    document.addEventListener('pointercancel', _onDocPointerCancel);
  },

  onShow(data) { openOficina(data); },
  onHide()     { closeNUI(); },

  onDestroy() {
    // remove listeners estáticos de onInit
    document.getElementById('btn-close').removeEventListener('click', cancelarOficina);
    document.getElementById('btn-cancel').removeEventListener('click', cancelarOficina);
    if (_btnNitro) _btnNitro.removeEventListener('click', instalarNitro);
    document.getElementById('btn-calibrar').removeEventListener('click', toggleCalibragem);
    document.getElementById('btn-calib-cancel').removeEventListener('click', cancelarCalibragem);
    document.getElementById('btn-calib-save').removeEventListener('click', salvarCalibragem);
    window.removeEventListener('keydown', onKeydown);

    const diagramEl = document.getElementById('oficina-diagram');
    if (diagramEl) diagramEl.removeEventListener('click', onSlotClick);

    // remove handlers de drag (A-07 obrigatório — cleanup completo)
    const tray = document.getElementById('parts-tray');
    if (tray && _onTrayPointerDown) tray.removeEventListener('pointerdown', _onTrayPointerDown);
    if (_onDocPointerMove)   document.removeEventListener('pointermove',   _onDocPointerMove);
    if (_onDocPointerUp)     document.removeEventListener('pointerup',     _onDocPointerUp);
    if (_onDocPointerCancel) document.removeEventListener('pointercancel', _onDocPointerCancel);

    // ghost mid-drag — nunca vazar elemento fixed no DOM (A-07, runtime condição 1)
    cancelDrag();

    closeNUI();
  },
});

})();
