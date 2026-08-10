'use strict';

// ============================================================
// bennys.js — runtime da NUI estética (Bennys)
// IIFE: isola estado/funções deste domínio (mesmo document de oficina.js/mec.js).
//
// Princípios:
//   * SEM timeout de inatividade (removido) — fecha só por ação explícita do jogador.
//   * Anti-fantasma: renderiza só o que data.avail diz que o carro possui.
//   * Cor: pickers HSV contínuos (RGB real) p/ primária, secundária, fumaça e neon.
//   * Preview a cada mudança (efêmero, custo zero) → o servidor valida/cobra no APLICAR.
//   * Câmera orbital: arrasto no palco central → bennys:orbit; scroll → bennys:zoom.
//   * Cleanup (A-07): RAF e estado de arrasto zerados ao fechar; listeners únicos.
// ============================================================

(function () {

let _module = null;

// ============================================================
// CONFIG ESTÁTICA (rótulos; disponibilidade vem do servidor/cliente)
// ============================================================

const CATS = [
  { id: 'pintura', label: 'Pintura', icon: '🎨', focus: 'geral'   },
  { id: 'neon',    label: 'Neon',    icon: '💡', focus: 'lateral' },
  { id: 'rodas',   label: 'Rodas',   icon: '🛞', focus: 'roda'    },
  { id: 'stance',  label: 'Stance',  icon: '📐', focus: 'roda'    },
  { id: 'kits',    label: 'Carroceria', icon: '🔧', focus: 'lateral' },
  { id: 'extras',  label: 'Acessórios', icon: '🧩', focus: 'geral' },
  { id: 'visual',  label: 'Detalhes', icon: '✨', focus: 'geral'  },
];

// Tabela de referência GTA V (índice de cor → hex aproximado) — só p/ tingir o swatch.
// A cor REAL aparece no veículo 3D (preview autoritativo); o swatch é indicativo.
const GTA_PAINT_HEX = {
  0:'#0d1116',1:'#1c1d21',2:'#33373d',3:'#45494e',4:'#999da0',5:'#c2c4c6',6:'#979a97',
  7:'#637380',8:'#63625c',9:'#3c3f47',10:'#444e54',11:'#1d2129',12:'#13181f',13:'#2f2f30',
  14:'#7f8ea3',27:'#c00e1a',28:'#da1918',29:'#b6111b',30:'#a94744',31:'#6f1818',32:'#a72421',
  33:'#791d1d',34:'#8e1421',35:'#ff6600',36:'#bf6d3b',38:'#f78616',39:'#c2944f',40:'#f3c98c',
  41:'#e59f00',42:'#cf1f21',49:'#132428',50:'#12383c',51:'#31423f',52:'#155c2d',53:'#1b8a1e',
  54:'#3aa53a',55:'#c8e600',61:'#132430',62:'#122e4f',63:'#1938a0',64:'#0f4c7a',65:'#5c88c2',
  66:'#2f6fb3',67:'#4271b3',68:'#6cb2e0',69:'#0e316d',70:'#2354a1',71:'#5d76a6',72:'#2b3f6a',
  73:'#5a5d84',74:'#4a5468',82:'#221c1c',83:'#2a2a2a',84:'#0a0a0a',88:'#fbe212',89:'#f9a825',
  90:'#f7b825',91:'#c1c1c1',92:'#7a888f',94:'#514f4d',95:'#463f3a',96:'#31261f',97:'#2b2b2b',
  98:'#302b25',100:'#4c4a44',101:'#645d55',102:'#5a5651',103:'#6b6b63',104:'#7c7461',
  105:'#3a3936',106:'#605f5b',107:'#a5a08f',111:'#3d4a58',112:'#576675',117:'#b8bcc4',
  118:'#5a5e63',119:'#8c9296',120:'#eceff1',128:'#2f2f2f',131:'#ffffff',135:'#e6e0d4',
  136:'#efd7a0',137:'#d5b06b',138:'#c99b3d',141:'#3a6ea5',142:'#7ba0c7',143:'#a3312e',
  145:'#3a5a7a',147:'#141414',148:'#630b0b',149:'#5c1a1a',150:'#7a1414',151:'#213b2a',
  152:'#4a5f2a',153:'#6b7a3a',154:'#8a9a4a',155:'#25322a',158:'#9aa0a6',159:'#4a4e52',
};

function paintHex(idx) { return GTA_PAINT_HEX[idx] || '#5a5f66'; }

const TINT_OPTIONS = [
  { v: 0, label: 'Nenhum' }, { v: 1, label: 'Preto' }, { v: 2, label: 'Escuro' },
  { v: 3, label: 'Leve' }, { v: 4, label: 'Padrão' }, { v: 5, label: 'Limusine' }, { v: 6, label: 'Verde' },
];

const WHEEL_TYPES = [
  { v: 0, label: 'Sport' }, { v: 1, label: 'Muscle' }, { v: 2, label: 'Lowrider' },
  { v: 3, label: 'SUV' }, { v: 4, label: 'Offroad' }, { v: 5, label: 'Tuner' },
  { v: 6, label: 'Moto' }, { v: 7, label: 'High-end' },
  { v: 8, label: 'Benny\'s Original' }, { v: 9, label: 'Benny\'s Bespoke' },
  { v: 10, label: 'Open Wheel' }, { v: 11, label: 'Street' }, { v: 12, label: 'Track' },
];

// 13 cores nativas de xenon (índice → swatch aproximado p/ a faixa de cor)
const XENON_COLORS = [
  { v: 0, hex: '#ffffff' }, { v: 1, hex: '#3a6fff' }, { v: 2, hex: '#4fb6ff' },
  { v: 3, hex: '#39e0ff' }, { v: 4, hex: '#23d18b' }, { v: 5, hex: '#b6ff3a' },
  { v: 6, hex: '#ffd23a' }, { v: 7, hex: '#ff8c2a' }, { v: 8, hex: '#ff3a3a' },
  { v: 9, hex: '#ff3aa0' }, { v: 10, hex: '#c23aff' }, { v: 11, hex: '#7a3aff' },
  { v: 12, hex: '#ffe9b0' },
];


// ============================================================
// STATE
// ============================================================

let _data    = null;     // payload de openBennys (plate, nome, prices, avail, kit_types, current)
let _cur     = {};        // estado atual REAL do veículo (reflexo inicial, anti-fantasma)
let _pending = {};        // patch a aplicar (mesmo shape que server/bennys.lua espera)
let _cat     = 'pintura';
let _neon    = [false, false, false, false];   // [esq, dir, frente, trás]
let _wheelCount = 0;       // nº de opções de roda do tipo atual (re-scan ao trocar tipo)

// orbit/zoom (câmera via arrasto no palco)
let _drag      = null;     // {x,y} enquanto arrasta o palco
let _orbitTimer = null;
let _orbitAcc  = { dx: 0, dy: 0 };
let _zoomTimer = null;
let _zoomAcc   = 0;

let _previewTimer = null;  // coalesce de preview — máximo 10 Hz

// referências para cleanup de listeners do palco (A-07)
let _stageDownRef = null;
let _stageMoveRef = null;
let _stageUpRef   = null;
let _stageWheelRef = null;


// ============================================================
// HELPERS
// ============================================================

function post(name, body) {
  return window.vhub.request(name, body);
}

function fmtMoney(v) { return 'R$ ' + Number(v || 0).toLocaleString('pt-BR'); }
function priceFor(key) { return Number((_data && _data.prices && _data.prices[key]) || 0); }
function clamp255(n) { return Math.max(0, Math.min(255, Math.round(n))); }
function el(tag, cls, txt) { const e = document.createElement(tag); if (cls) e.className = cls; if (txt != null) e.textContent = txt; return e; }


// ============================================================
// CONVERSÃO HSV ↔ RGB (picker contínuo)
// ============================================================

function hsvToRgb(h, s, v) {
  h = (h % 360 + 360) % 360;
  const c = v * s, x = c * (1 - Math.abs(((h / 60) % 2) - 1)), m = v - c;
  let r = 0, g = 0, b = 0;
  if (h < 60)       { r = c; g = x; }
  else if (h < 120) { r = x; g = c; }
  else if (h < 180) { g = c; b = x; }
  else if (h < 240) { g = x; b = c; }
  else if (h < 300) { r = x; b = c; }
  else              { r = c; b = x; }
  return [clamp255((r + m) * 255), clamp255((g + m) * 255), clamp255((b + m) * 255)];
}

function rgbToHsv(r, g, b) {
  r /= 255; g /= 255; b /= 255;
  const max = Math.max(r, g, b), min = Math.min(r, g, b), d = max - min;
  let h = 0;
  if (d !== 0) {
    if (max === r)      h = ((g - b) / d) % 6;
    else if (max === g) h = (b - r) / d + 2;
    else                h = (r - g) / d + 4;
    h *= 60; if (h < 0) h += 360;
  }
  const s = max === 0 ? 0 : d / max;
  return [h, s, max];
}

function rgbToHex(rgb) {
  return '#' + rgb.map(n => clamp255(n).toString(16).padStart(2, '0')).join('');
}


// ============================================================
// COLOR PICKER — gradiente contínuo (SV square + hue slider)
// retorna { el } e dispara onChange([r,g,b]) ao arrastar
// ============================================================

function createColorPicker(initRGB, onChange) {
  const rgb0 = (Array.isArray(initRGB) && initRGB.length === 3) ? initRGB.slice() : [255, 255, 255];
  let [h, s, v] = rgbToHsv(rgb0[0], rgb0[1], rgb0[2]);

  const wrap   = el('div', 'cp');
  const sv     = el('div', 'cp-sv');
  const svThumb= el('div', 'cp-sv-thumb');
  const hue    = el('div', 'cp-hue');
  const hueThumb = el('div', 'cp-hue-thumb');
  const foot   = el('div', 'cp-foot');
  const swatch = el('div', 'cp-swatch');
  const hex    = el('div', 'cp-hex');

  sv.appendChild(svThumb); hue.appendChild(hueThumb);
  foot.appendChild(swatch); foot.appendChild(hex);
  wrap.appendChild(sv); wrap.appendChild(hue); wrap.appendChild(foot);

  function paint(emit) {
    const rgb = hsvToRgb(h, s, v);
    sv.style.backgroundColor = 'hsl(' + Math.round(h) + ', 100%, 50%)';
    svThumb.style.left = (s * 100) + '%';
    svThumb.style.top  = ((1 - v) * 100) + '%';
    hueThumb.style.left = (h / 360 * 100) + '%';
    swatch.style.background = rgbToHex(rgb);
    hex.textContent = rgbToHex(rgb);
    if (emit && typeof onChange === 'function') onChange(rgb);
  }

  function svFromEvent(ev) {
    const r = sv.getBoundingClientRect();
    s = Math.max(0, Math.min(1, (ev.clientX - r.left) / r.width));
    v = Math.max(0, Math.min(1, 1 - (ev.clientY - r.top) / r.height));
    paint(true);
  }
  function hueFromEvent(ev) {
    const r = hue.getBoundingClientRect();
    h = Math.max(0, Math.min(360, ((ev.clientX - r.left) / r.width) * 360));
    paint(true);
  }

  // drag local do picker (independente do arrasto do palco)
  let mode = null;
  sv.addEventListener('mousedown', e => { mode = 'sv'; svFromEvent(e); e.preventDefault(); });
  hue.addEventListener('mousedown', e => { mode = 'hue'; hueFromEvent(e); e.preventDefault(); });
  function onMove(e) { if (mode === 'sv') svFromEvent(e); else if (mode === 'hue') hueFromEvent(e); }
  function onUp() { mode = null; }
  wrap._detach = function () { window.removeEventListener('mousemove', onMove); window.removeEventListener('mouseup', onUp); };
  window.addEventListener('mousemove', onMove);
  window.addEventListener('mouseup', onUp);

  paint(false);
  return wrap;
}

// registry p/ desanexar listeners dos pickers vivos (cleanup A-07)
let _pickers = [];
function mountPicker(root, initRGB, onChange) {
  const p = createColorPicker(initRGB, onChange);
  _pickers.push(p);
  root.appendChild(p);
}
function detachPickers() {
  for (const p of _pickers) { if (p._detach) p._detach(); }
  _pickers = [];
}


// ============================================================
// RENDER — categorias (aside esquerdo)
// ============================================================

function renderCats() {
  const nav = document.getElementById('bn-cats');
  nav.innerHTML = '';
  for (const c of CATS) {
    const item = el('div', 'bn-cat' + (c.id === _cat ? ' active' : ''));
    item.appendChild(el('span', 'bn-cat-ico', c.icon));
    item.appendChild(el('span', 'bn-cat-label', c.label));
    item.addEventListener('click', () => {
      _cat = c.id;
      renderCats();
      renderControls();
      post('bennys:focus', { part: c.focus }).catch(() => {});
    });
    nav.appendChild(item);
  }
}


// ============================================================
// RENDER — controles (aside direito) por categoria
// ============================================================

function block(root, title, sub) {
  const b = el('div', 'bn-block');
  b.appendChild(el('div', 'bn-block-title', title));
  if (sub) b.appendChild(el('div', 'bn-block-sub', sub));
  root.appendChild(b);
  return b;
}

function switchRow(root, label, priceTxt, isOn, onToggle) {
  const row = el('div', 'bn-row');
  row.appendChild(el('span', 'bn-row-label', label));
  if (priceTxt) row.appendChild(el('span', 'bn-row-price', priceTxt));
  const sw = el('div', 'bn-switch' + (isOn ? ' on' : ''));
  sw.addEventListener('click', () => { const next = !sw.classList.contains('on'); sw.classList.toggle('on', next); onToggle(next); });
  row.appendChild(sw);
  root.appendChild(row);
  return sw;
}

function chips(root, options, selected, onPick) {
  const wrap = el('div', 'bn-chips');
  for (const opt of options) {
    const chip = el('div', 'bn-chip' + (opt.v === selected ? ' selected' : ''));
    if (opt.hex) {
      const dot = el('span');
      dot.style.cssText = 'display:inline-block;width:12px;height:12px;border-radius:50%;'
        + 'background:' + opt.hex + ';margin-right:6px;vertical-align:middle;border:1px solid rgba(0,0,0,.45)';
      chip.appendChild(dot);
    }
    chip.appendChild(document.createTextNode(opt.label != null && opt.label !== '' ? opt.label : ('#' + opt.v)));
    chip.addEventListener('click', () => { onPick(opt.v); });
    wrap.appendChild(chip);
  }
  root.appendChild(wrap);
  return wrap;
}

// stepper p/ kits/rodas com muitas opções (-1 = nenhum/stock)
function stepper(root, count, current, onChange) {
  const box = el('div', 'bn-step');
  const dec = el('div', 'bn-step-btn', '‹');
  const val = el('div', 'bn-step-val');
  const inc = el('div', 'bn-step-btn', '›');
  let cur = (typeof current === 'number') ? current : -1;

  function label() { val.textContent = cur < 0 ? 'Nenhum' : ('Opção ' + (cur + 1) + ' / ' + count); }
  dec.addEventListener('click', () => { cur = cur <= -1 ? count - 1 : cur - 1; label(); onChange(cur); });
  inc.addEventListener('click', () => { cur = cur >= count - 1 ? -1 : cur + 1; label(); onChange(cur); });

  label();
  box.appendChild(dec); box.appendChild(val); box.appendChild(inc);
  root.appendChild(box);
}

// stepper numérico contínuo (min..max, sem "nenhum") p/ perolado/cor de aro
function rangeStepper(root, min, max, current, onChange) {
  const box = el('div', 'bn-step');
  const dec = el('div', 'bn-step-btn', '‹');
  const val = el('div', 'bn-step-val');
  const inc = el('div', 'bn-step-btn', '›');
  let cur = (typeof current === 'number') ? Math.max(min, Math.min(max, current)) : min;

  function label() {
    val.textContent = 'Índice ' + cur;
    val.style.borderLeft = '10px solid ' + paintHex(cur);
  }
  dec.addEventListener('click', () => { cur = cur <= min ? max : cur - 1; label(); onChange(cur); });
  inc.addEventListener('click', () => { cur = cur >= max ? min : cur + 1; label(); onChange(cur); });

  label();
  box.appendChild(dec); box.appendChild(val); box.appendChild(inc);
  root.appendChild(box);
}

// stepper de NOTCH para stance: valor inteiro com sinal (−/+), sem wrap e sem swatch de tinta
function notchStepper(root, min, max, current, onChange) {
  const box = el('div', 'bn-step');
  const dec = el('div', 'bn-step-btn', '‹');
  const val = el('div', 'bn-step-val');
  const inc = el('div', 'bn-step-btn', '›');
  let cur = (typeof current === 'number') ? Math.max(min, Math.min(max, Math.round(current))) : 0;
  function label() { val.textContent = (cur > 0 ? '+' : '') + cur; }
  dec.addEventListener('click', () => { if (cur > min) { cur--; label(); onChange(cur); } });
  inc.addEventListener('click', () => { if (cur < max) { cur++; label(); onChange(cur); } });
  label();
  box.appendChild(dec); box.appendChild(val); box.appendChild(inc);
  root.appendChild(box);
}

// grade de swatches de tinta por índice GTA — clique aplica no slot indicado
function swatchGrid(root, indices, selected, onPick) {
  const grid = el('div', 'bn-swatches');
  for (const idx of indices) {
    const sw = el('div', 'bn-swatch' + (idx === selected ? ' selected' : ''));
    sw.style.background = paintHex(idx);
    sw.title = 'Índice ' + idx;
    sw.addEventListener('click', () => onPick(idx));
    grid.appendChild(sw);
  }
  root.appendChild(grid);
  return grid;
}


// ---- PINTURA ----

// devolve o par [primária, secundária] atual (pendente > real > preto)
function curColourPair() {
  const src = _pending.colours || _cur.colours || [0, 0];
  return [Number(src[0] || src['1'] || 0), Number(src[1] || src['2'] || 0)];
}

// aplica um índice de paleta ao slot (0=primária, 1=secundária) e limpa o custom do slot
// `false` explícito no custom = servidor LIMPA o RGB salvo (senão o custom antigo
// sobreporia a paleta no respawn — persistência é merge por chave)
function setPaletteColour(slot, idx) {
  const pair = curColourPair();
  pair[slot] = idx;
  _pending.colours = pair;
  if (slot === 0) _pending.custom_primary = false;
  else            _pending.custom_secondary = false;
  pushPreview();
  renderControls();
}

const PALETTE_GROUPS = [
  { key: 'metalico', label: 'Metálico' },
  { key: 'fosco',    label: 'Fosco'    },
  { key: 'cromado',  label: 'Cromado'  },
  { key: 'metal',    label: 'Metal'    },
];

function renderPintura(root) {
  const palettes = (_data && _data.paint_palettes) || {};
  const pair = curColourPair();

  // paletas de acabamento (metálico/fosco/cromado/metal) — aplicadas ao slot primário
  const usingCustomPrim = Array.isArray(_pending.custom_primary);
  for (const g of PALETTE_GROUPS) {
    const list = palettes[g.key];
    if (!Array.isArray(list) || list.length === 0) continue;
    const bg = block(root, 'Primária — ' + g.label, fmtMoney(priceFor('cor_primaria') + priceFor('cor_secundaria')));
    swatchGrid(bg, list, usingCustomPrim ? -1 : pair[0], (idx) => setPaletteColour(0, idx));
  }

  // paleta secundária (reaproveita metálico + fosco num único bloco compacto)
  const secList = (palettes.metalico || []).concat(palettes.fosco || []);
  if (secList.length > 0) {
    const usingCustomSec = Array.isArray(_pending.custom_secondary);
    const bs = block(root, 'Cor secundária (paleta)', 'Índice de fábrica');
    swatchGrid(bs, secList, usingCustomSec ? -1 : pair[1], (idx) => setPaletteColour(1, idx));
  }

  // pintura RGB exata (custom) — sobrepõe a paleta no slot correspondente
  const b1 = block(root, 'Primária personalizada', 'RGB exato · ' + fmtMoney(priceFor('cor_custom')));
  mountPicker(b1, _pending.custom_primary || _cur.custom_primary || [200, 32, 32], rgb => {
    _pending.custom_primary = rgb; pushPreview();
  });

  const b2 = block(root, 'Secundária personalizada', 'RGB exato · ' + fmtMoney(priceFor('cor_custom')));
  mountPicker(b2, _pending.custom_secondary || _cur.custom_secondary || [24, 24, 26], rgb => {
    _pending.custom_secondary = rgb; pushPreview();
  });

  // perolado + cor de aro (par extra_colours) — índices GTA
  const be = block(root, 'Perolado', 'Reflexo perolado · ' + fmtMoney(priceFor('cor_perolado')));
  const curPearl = (_pending.extra_colours && _pending.extra_colours[0] != null)
                 ? _pending.extra_colours[0]
                 : (_cur.extra_colours && _cur.extra_colours[0] != null ? _cur.extra_colours[0] : 0);
  rangeStepper(be, 0, 160, curPearl, (v) => setExtraColour(0, v));

  const bwc = block(root, 'Cor do aro', 'Tinta da roda · ' + fmtMoney(priceFor('cor_roda')));
  const curWheelCol = (_pending.extra_colours && _pending.extra_colours[1] != null)
                    ? _pending.extra_colours[1]
                    : (_cur.extra_colours && _cur.extra_colours[1] != null ? _cur.extra_colours[1] : 0);
  rangeStepper(bwc, 0, 160, curWheelCol, (v) => setExtraColour(1, v));
}

// aplica índice ao par extra_colours (0=perolado, 1=cor de aro)
function setExtraColour(slot, idx) {
  const src = _pending.extra_colours || _cur.extra_colours || [0, 0];
  const pair = [Number(src[0] || src['1'] || 0), Number(src[1] || src['2'] || 0)];
  pair[slot] = idx;
  _pending.extra_colours = pair;
  pushPreview();
}

// ---- NEON ----
function renderNeon(root) {
  const b = block(root, 'Luzes neon', 'Ligue cada ponto (esq/dir/frente/trás)');
  const labels = ['Esquerdo', 'Direito', 'Frente', 'Trás'];
  for (let i = 0; i < 4; i++) {
    switchRow(b, labels[i], i === 0 ? fmtMoney(priceFor('neon')) : '', _neon[i], (on) => {
      _neon[i] = on;
      _pending.neons = _neon.slice();   // array [esq,dir,frente,trás] — índice 0 NUNCA pulado
      pushPreview();
    });
  }

  const bc = block(root, 'Cor do neon', 'Gradiente RGB contínuo · ' + fmtMoney(priceFor('neon_cor')));
  mountPicker(bc, _pending.neon_colour || _cur.neon_colour || [0, 120, 255], rgb => {
    _pending.neon_colour = rgb; pushPreview();
  });
}

// ---- RODAS ----
function renderRodas(root) {
  const bt = block(root, 'Tipo de roda', fmtMoney(priceFor('wheel_type')));
  const curType = (_pending.wheel_type != null) ? _pending.wheel_type : _cur.wheel_type;
  chips(bt, WHEEL_TYPES, curType, (v) => {
    _pending.wheel_type = v;
    // re-enumera as rodas do novo tipo (a lista 23 muda com o tipo) — anti-fantasma
    post('bennys:rescanWheels', { wheel_type: v }).then(d => {
      _wheelCount = (d && d.count) || 0;
      pushPreview();
      renderControls();
    }).catch(() => { pushPreview(); renderControls(); });
  });

  if (_wheelCount > 0) {
    const bw = block(root, 'Modelo da roda', _wheelCount + ' opções disponíveis');
    const curWheel = (_pending.mods && _pending.mods['23'] != null) ? _pending.mods['23']
                   : (_cur.mods && _cur.mods['23'] != null ? _cur.mods['23'] : -1);
    stepper(bw, _wheelCount, curWheel, (lvl) => { setMod(23, lvl); });
  } else {
    block(root, 'Modelo da roda', '').appendChild(el('div', 'bn-empty', 'Sem modelos para este tipo de roda.'));
  }
}

// ---- STANCE (rebaixamento visual: altura, bitola, tamanho/largura de roda) ----

// stance atual = salvo (_cur.stance) sobreposto pelo pendente (_pending.stance)
function curStance() {
  return Object.assign({}, _cur.stance || {}, _pending.stance || {});
}

// aplica um notch a um eixo, mantendo TODOS os eixos no pendente (preview de um não zera os outros)
function setStance(key, v) {
  const s = curStance();
  s[key] = v;
  _pending.stance = s;
  pushPreview();
}

function renderStance(root) {
  const specs = (_data && _data.stance) || [];
  if (specs.length === 0) {
    root.appendChild(el('div', 'bn-empty', 'Stance indisponível para este veículo.'));
    return;
  }
  const cur = curStance();
  for (let i = 0; i < specs.length; i++) {
    const spec = specs[i];
    const sub = (i === 0) ? ('Rebaixamento real · ' + fmtMoney(priceFor('stance')))
              : (spec.key === 'sz' || spec.key === 'wd') ? 'Exige roda esportiva' : '';
    const b = block(root, spec.label, sub);
    notchStepper(b, spec.min, spec.max, (cur[spec.key] != null ? cur[spec.key] : 0), (v) => setStance(spec.key, v));
  }
}

// ---- KITS DE CARROCERIA (anti-fantasma via avail.kits) ----
function renderKits(root) {
  const avail = (_data && _data.avail && _data.avail.kits) || {};
  const types = (_data && _data.kit_types) || [];
  let any = false;

  for (const t of types) {
    const count = avail[String(t.idx)];
    if (!count || count <= 0) continue;       // FANTASMA: o carro não tem esse kit → não renderiza
    if (t.idx === 23) continue;                // rodas têm aba própria
    any = true;
    const b = block(root, t.name, count + ' opções');
    const cur = (_pending.mods && _pending.mods[String(t.idx)] != null) ? _pending.mods[String(t.idx)]
              : (_cur.mods && _cur.mods[String(t.idx)] != null ? _cur.mods[String(t.idx)] : -1);
    stepper(b, count, cur, (lvl) => {
      setMod(t.idx, lvl);
      post('bennys:focus', { kitIdx: t.idx }).catch(() => {});   // foca a câmera na peça alterada
    });
  }

  if (!any) root.appendChild(el('div', 'bn-empty', 'Este veículo não possui kits de carroceria personalizáveis.'));
}

// ---- DETALHES (tint, livery, xenon, fumaça, placa) ----
function renderVisual(root) {
  // vidro fumê
  const bt = block(root, 'Vidro fumê', fmtMoney(priceFor('tint')));
  chips(bt, TINT_OPTIONS, (_pending.window_tint != null ? _pending.window_tint : _cur.window_tint),
        (v) => { _pending.window_tint = v; pushPreview(); });

  // livery (só se o veículo tiver)
  const liveryCount = (_data && _data.avail && _data.avail.liveryCount) || -1;
  if (liveryCount > 0) {
    const bl = block(root, 'Adesivo (livery)', liveryCount + ' opções · ' + fmtMoney(priceFor('livery')));
    const curL = (_pending.livery != null) ? _pending.livery : _cur.livery;
    stepper(bl, liveryCount, (curL != null ? curL : -1), (lvl) => { _pending.livery = lvl; pushPreview(); });
  }

  // xenon: toggle + faixa de cor (13 índices nativos)
  const bx = block(root, 'Faróis xenon', fmtMoney(priceFor('xenon')));
  switchRow(bx, 'Ativar xenon', '', (_pending.xenon != null ? _pending.xenon : _cur.xenon),
            (on) => { _pending.xenon = on; pushPreview(); });
  chips(bx, XENON_COLORS.map(c => ({ v: c.v, label: '', hex: c.hex })),
        (_pending.xenon_color != null ? _pending.xenon_color : _cur.xenon_color),
        (v) => { _pending.xenon_color = v; _pending.xenon = true; pushPreview(); renderControls(); });

  // fumaça de pneu: toggle + cor RGB
  const bs = block(root, 'Fumaça de pneu', fmtMoney(priceFor('fumaca')));
  switchRow(bs, 'Ativar fumaça', '', (_pending.smoke != null ? _pending.smoke : _cur.smoke),
            (on) => { _pending.smoke = on; pushPreview(); });
  const bsc = block(root, 'Cor da fumaça', 'Gradiente RGB contínuo · ' + fmtMoney(priceFor('fumaca_cor')));
  mountPicker(bsc, _pending.tyre_smoke_color || _cur.tyre_smoke_color || [255, 40, 40], rgb => {
    _pending.tyre_smoke_color = rgb; _pending.smoke = true; pushPreview();
  });

  // índice de placa
  const bp = block(root, 'Estilo da placa', fmtMoney(priceFor('plate_index')));
  chips(bp, [0, 1, 2, 3, 4].map(v => ({ v: v, label: 'Tipo ' + v })),
        (_pending.plate_index != null ? _pending.plate_index : _cur.plate_index),
        (v) => { _pending.plate_index = v; pushPreview(); });

  // cor do interior + painel (índice GTA 0..160) — swatch indicativo via rangeStepper
  const bic = block(root, 'Cor do interior', 'Índice GTA · ' + fmtMoney(priceFor('interior_color')));
  const curInt = (_pending.interior_color != null) ? _pending.interior_color
               : (_cur.interior_color != null ? _cur.interior_color : 0);
  rangeStepper(bic, 0, 160, curInt, (v) => { _pending.interior_color = v; pushPreview(); });

  const bdc = block(root, 'Cor do painel', 'Índice GTA · ' + fmtMoney(priceFor('dashboard_color')));
  const curDash = (_pending.dashboard_color != null) ? _pending.dashboard_color
                : (_cur.dashboard_color != null ? _cur.dashboard_color : 0);
  rangeStepper(bdc, 0, 160, curDash, (v) => { _pending.dashboard_color = v; pushPreview(); });

  // blindagem de vidro (RP — sem efeito visual; preço escalonado por tier)
  const tiers = (_data && _data.glass_armor_tiers) || [];
  if (tiers.length > 0) {
    const bga = block(root, 'Blindagem de vidro', 'Proteção dos vidros (RP)');
    const curGa = (_pending.glass_armor != null) ? _pending.glass_armor
                : (_cur.glass_armor != null ? _cur.glass_armor : 0);
    chips(bga, tiers.map(t => ({ v: t.id, label: t.label + (t.price > 0 ? ' · ' + fmtMoney(t.price) : '') })),
          curGa, (v) => { _pending.glass_armor = v; renderControls(); renderFooter(); });
  }

  // fogo no escapamento (PTFX): toggle + cor + densidade
  const fx = _pending.exhaust_fx || _cur.exhaust_fx || { enabled: false };
  const bfx = block(root, 'Fogo no escapamento', fmtMoney(priceFor('exhaust_fx')));
  switchRow(bfx, 'Ativar chamas', '', fx.enabled === true, (on) => {
    _pending.exhaust_fx = _pending.exhaust_fx || Object.assign({}, fx);
    _pending.exhaust_fx.enabled = on;
    if (on && _pending.exhaust_fx.r == null) {
      _pending.exhaust_fx.r = 255; _pending.exhaust_fx.g = 90; _pending.exhaust_fx.b = 0;
      _pending.exhaust_fx.scale = 1.0;
    }
    pushPreview(); renderControls();
  });

  if ((_pending.exhaust_fx || fx).enabled) {
    const cur = _pending.exhaust_fx || fx;
    const bfc = block(root, 'Cor das chamas', 'Gradiente RGB contínuo');
    mountPicker(bfc, [cur.r != null ? cur.r : 255, cur.g != null ? cur.g : 90, cur.b != null ? cur.b : 0], rgb => {
      _pending.exhaust_fx = _pending.exhaust_fx || { enabled: true };
      _pending.exhaust_fx.enabled = true;
      _pending.exhaust_fx.r = rgb[0]; _pending.exhaust_fx.g = rgb[1]; _pending.exhaust_fx.b = rgb[2];
      pushPreview();
    });
    const bfs = block(root, 'Densidade das chamas', 'Escala do efeito');
    const curScale = cur.scale != null ? cur.scale : 1.0;
    chips(bfs, [{ v: 0.6, label: 'Sutil' }, { v: 1.0, label: 'Normal' }, { v: 1.8, label: 'Forte' }, { v: 3.0, label: 'Brutal' }],
          curScale, (v) => {
      _pending.exhaust_fx = _pending.exhaust_fx || { enabled: true };
      _pending.exhaust_fx.enabled = true; _pending.exhaust_fx.scale = v;
      pushPreview(); renderControls();
    });
  }
}

// ---- ACESSÓRIOS (extras do modelo — anti-fantasma via avail.extras) ----
function renderExtras(root) {
  const avail = (_data && _data.avail && _data.avail.extras) || {};
  const idxs = Object.keys(avail).map(Number).sort((a, b) => a - b);
  if (idxs.length === 0) {
    root.appendChild(el('div', 'bn-empty', 'Este veículo não possui acessórios extras.'));
    return;
  }
  const b = block(root, 'Acessórios do modelo', 'Ligue/desligue peças do pacote · ' + fmtMoney(priceFor('extras_toggle')) + ' cada');
  for (const idx of idxs) {
    const key = String(idx);
    const on = (_pending.extras && _pending.extras[key] != null) ? _pending.extras[key]
             : (_cur.extras && _cur.extras[key] === true);
    switchRow(b, 'Extra ' + idx, '', on === true, (val) => {
      _pending.extras = _pending.extras || {};
      _pending.extras[key] = val;
      pushPreview();
    });
  }
}

function setMod(idx, lvl) {
  _pending.mods = _pending.mods || {};
  if (lvl < 0) delete _pending.mods[String(idx)];
  else _pending.mods[String(idx)] = lvl;
  if (Object.keys(_pending.mods).length === 0) delete _pending.mods;
  pushPreview();
}

function renderControls() {
  const root = document.getElementById('bn-controls');
  detachPickers();
  root.innerHTML = '';
  document.getElementById('bn-cat-title').lastChild.textContent = ' ' +
    (CATS.find(c => c.id === _cat) || {}).label.toUpperCase();

  if (_cat === 'pintura') renderPintura(root);
  else if (_cat === 'neon')  renderNeon(root);
  else if (_cat === 'rodas') renderRodas(root);
  else if (_cat === 'stance') renderStance(root);
  else if (_cat === 'kits')  renderKits(root);
  else if (_cat === 'extras') renderExtras(root);
  else if (_cat === 'visual') renderVisual(root);
}


// ============================================================
// CUSTO + PREVIEW + RODAPÉ
// ============================================================

// espelha calcCost do server/bennys.lua (verdade do custo é server-side; isto é só exibição)
function calcTotal() {
  if (!_data) return 0;
  const p = _pending; let t = 0;
  if (p.colours)          t += priceFor('cor_primaria') + priceFor('cor_secundaria');
  if (p.extra_colours)    t += priceFor('cor_perolado') + priceFor('cor_roda');
  if (p.custom_primary)   t += priceFor('cor_custom');
  if (p.custom_secondary) t += priceFor('cor_custom');
  if (p.neons)            t += priceFor('neon');
  if (p.neon_colour)      t += priceFor('neon_cor');
  if (p.smoke)            t += priceFor('fumaca');
  if (p.tyre_smoke_color) t += priceFor('fumaca_cor');
  if (p.xenon)            t += priceFor('xenon');
  if (p.window_tint   !== undefined) t += priceFor('tint');
  if (p.interior_color  !== undefined) t += priceFor('interior_color');
  if (p.dashboard_color !== undefined) t += priceFor('dashboard_color');
  if (p.livery        !== undefined) t += priceFor('livery');
  if (p.wheel_type    !== undefined) t += priceFor('wheel_type');
  if (p.plate_index   !== undefined) t += priceFor('plate_index');
  if (p.mods) for (const _ in p.mods) t += priceFor('mod_cosmetic');
  if (p.extras) for (const _ in p.extras) t += priceFor('extras_toggle');
  if (p.exhaust_fx && p.exhaust_fx.enabled) t += priceFor('exhaust_fx');
  if (p.stance) t += priceFor('stance');
  if (p.glass_armor !== undefined) {
    const tiers = (_data && _data.glass_armor_tiers) || [];
    const entry = tiers.find(x => x.id === p.glass_armor);
    if (entry) t += Number(entry.price || 0);
  }
  return t;
}

function renderFooter() {
  const total = calcTotal();
  document.getElementById('bn-total-cost').textContent = fmtMoney(total);
  document.getElementById('bn-btn-apply').disabled = (total === 0);
}

function flushPreview() {
  _previewTimer = null;
  if (_data) post('bennys:preview', _pending).catch(() => {});
  renderFooter();
}

// coalesce chamadas durante drag do picker (A-08 — máximo 10 Hz)
function pushPreview() {
  if (!_previewTimer) _previewTimer = setTimeout(flushPreview, 100);
}


// ============================================================
// CÂMERA — arrasto no palco orbita; scroll dá zoom (throttle via RAF)
// ============================================================

function flushOrbit() {
  _orbitTimer = null;
  if (_orbitAcc.dx === 0 && _orbitAcc.dy === 0) return;
  post('bennys:orbit', { dx: _orbitAcc.dx, dy: _orbitAcc.dy }).catch(() => {});
  _orbitAcc.dx = 0; _orbitAcc.dy = 0;
}

function flushZoom() {
  _zoomTimer = null;
  if (_zoomAcc === 0) return;
  post('bennys:zoom', { delta: Math.max(-3, Math.min(3, _zoomAcc)) }).catch(() => {});
  _zoomAcc = 0;
}

function bindStage() {
  if (_stageMoveRef) return;
  const stage = document.getElementById('bn-stage');
  _stageDownRef = (e) => { if (_data) _drag = { x: e.clientX, y: e.clientY }; };
  stage.addEventListener('mousedown', _stageDownRef);

  _stageMoveRef = (e) => {
    if (!_drag) return;
    _orbitAcc.dx += (e.clientX - _drag.x);
    _orbitAcc.dy += (e.clientY - _drag.y);
    _drag.x = e.clientX; _drag.y = e.clientY;
    if (!_orbitTimer) _orbitTimer = setTimeout(flushOrbit, 33);
  };
  _stageUpRef = () => { _drag = null; };
  _stageWheelRef = (e) => {
    if (!_data) return;
    _zoomAcc += e.deltaY < 0 ? 1 : -1;
    if (!_zoomTimer) _zoomTimer = setTimeout(flushZoom, 33);
  };

  window.addEventListener('mousemove', _stageMoveRef);
  window.addEventListener('mouseup',   _stageUpRef);
  stage.addEventListener('wheel', _stageWheelRef, { passive: true });
}

function unbindStage() {
  const stage = document.getElementById('bn-stage');
  if (_stageDownRef) { stage.removeEventListener('mousedown', _stageDownRef); _stageDownRef = null; }
  if (_stageMoveRef) { window.removeEventListener('mousemove', _stageMoveRef); _stageMoveRef = null; }
  if (_stageUpRef) { window.removeEventListener('mouseup', _stageUpRef); _stageUpRef = null; }
  if (_stageWheelRef) { stage.removeEventListener('wheel', _stageWheelRef); _stageWheelRef = null; }
}


// ============================================================
// OPEN / CLOSE (sem timeout)
// ============================================================

function openBennys(data) {
  _data    = data || {};
  _cur     = _data.current || {};
  _pending = {};
  _cat     = 'pintura';
  _wheelCount = (_data.avail && _data.avail.wheelMods) || 0;

  // estado de neon inicial reflete a realidade ([esq,dir,frente,trás])
  const cn = _cur.neons || [false, false, false, false];
  _neon = [cn[0] === true, cn[1] === true, cn[2] === true, cn[3] === true];

  document.getElementById('bn-veh-nome').textContent = _data.nome || '—';
  document.getElementById('bn-veh-sub').textContent  = (_data.categoria || '—') + '  ·  ' + (_data.plate || '—');

  renderCats();
  renderControls();
  renderFooter();

  document.getElementById('bennys-overlay').classList.remove('hidden');
}

function closeNUI() {
  if (_orbitTimer) { clearTimeout(_orbitTimer); _orbitTimer = null; }
  if (_previewTimer) { clearTimeout(_previewTimer); _previewTimer = null; }
  if (_zoomTimer) { clearTimeout(_zoomTimer); _zoomTimer = null; }
  _orbitAcc = { dx: 0, dy: 0 }; _zoomAcc = 0; _drag = null;
  unbindStage();
  detachPickers();
  document.getElementById('bennys-overlay').classList.add('hidden');
  _data = null; _pending = {}; _cur = {};
}

function cancelar() {
  _module.hide();
  post('bennys:fechar', {}).catch(() => {});
}

function aplicar() {
  if (!_data || calcTotal() === 0) return;
  document.getElementById('bn-btn-apply').disabled  = true;
  document.getElementById('bn-btn-cancel').disabled = true;
  post('bennys:aplicar', { plate: _data.plate, payload: _pending }).catch(() => {
    document.getElementById('bn-btn-apply').disabled = false;
    document.getElementById('bn-btn-cancel').disabled = false;
  });
  // a NUI fecha ao receber action='fecharBennys' (BENNYS_CONFIRM → SendNUIMessage)
}


// ============================================================
// BUS DE MENSAGENS + BIND ÚNICO
// ============================================================

function onKeydown(e) {
  if (e.key === 'Escape' && _data) cancelar();
}

_module = window.vhub.createModule('bennys', {
  actions: {
    openBennys: (message, api) => api.show(message.data),
    fecharBennys: (_message, api) => api.hide(),
  },
  onInit() {
    document.getElementById('bn-btn-cancel').addEventListener('click', cancelar);
    document.getElementById('bn-btn-apply').addEventListener('click', aplicar);
    window.addEventListener('keydown', onKeydown);
  },
  onMount() {},
  onShow(data) { openBennys(data); bindStage(); },
  onHide() { closeNUI(); },
  onDestroy() {
    document.getElementById('bn-btn-cancel').removeEventListener('click', cancelar);
    document.getElementById('bn-btn-apply').removeEventListener('click', aplicar);
    window.removeEventListener('keydown', onKeydown);
    closeNUI();
  },
});

})();
