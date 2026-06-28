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

// ============================================================
// CONFIG ESTÁTICA (rótulos; disponibilidade vem do servidor/cliente)
// ============================================================

const CATS = [
  { id: 'pintura', label: 'Pintura', icon: '🎨', focus: 'geral'   },
  { id: 'neon',    label: 'Neon',    icon: '💡', focus: 'lateral' },
  { id: 'rodas',   label: 'Rodas',   icon: '🛞', focus: 'roda'    },
  { id: 'kits',    label: 'Carroceria', icon: '🔧', focus: 'lateral' },
  { id: 'visual',  label: 'Detalhes', icon: '✨', focus: 'geral'  },
];

const TINT_OPTIONS = [
  { v: 0, label: 'Nenhum' }, { v: 1, label: 'Preto' }, { v: 2, label: 'Escuro' },
  { v: 3, label: 'Leve' }, { v: 4, label: 'Padrão' }, { v: 5, label: 'Limusine' }, { v: 6, label: 'Verde' },
];

const WHEEL_TYPES = [
  { v: 0, label: 'Sport' }, { v: 1, label: 'Muscle' }, { v: 2, label: 'Lowrider' },
  { v: 3, label: 'SUV' }, { v: 4, label: 'Offroad' }, { v: 5, label: 'Tuner' },
  { v: 6, label: 'Moto' }, { v: 7, label: 'High-end' },
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
let _orbitRAF  = null;
let _orbitAcc  = { dx: 0, dy: 0 };


// ============================================================
// HELPERS
// ============================================================

function post(name, body) {
  return fetch('https://vhub_custom/' + name, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(body || {}),
  }).catch(() => {});
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
      post('bennys:focus', { part: c.focus });
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


// ---- PINTURA ----
function renderPintura(root) {
  const b1 = block(root, 'Cor primária', 'Gradiente RGB contínuo · ' + fmtMoney(priceFor('cor_custom')));
  mountPicker(b1, _pending.custom_primary || _cur.custom_primary || [200, 32, 32], rgb => {
    _pending.custom_primary = rgb; pushPreview();
  });

  const b2 = block(root, 'Cor secundária', 'Gradiente RGB contínuo · ' + fmtMoney(priceFor('cor_custom')));
  mountPicker(b2, _pending.custom_secondary || _cur.custom_secondary || [24, 24, 26], rgb => {
    _pending.custom_secondary = rgb; pushPreview();
  });
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
    post('bennys:rescanWheels', { wheel_type: v }).then(r => r && r.json && r.json()).then(d => {
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
      post('bennys:focus', { kitIdx: t.idx });   // foca a câmera na peça alterada
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
  else if (_cat === 'kits')  renderKits(root);
  else if (_cat === 'visual') renderVisual(root);
}


// ============================================================
// CUSTO + PREVIEW + RODAPÉ
// ============================================================

// espelha calcCost do server/bennys.lua (verdade do custo é server-side; isto é só exibição)
function calcTotal() {
  if (!_data) return 0;
  const p = _pending; let t = 0;
  if (p.custom_primary)   t += priceFor('cor_custom');
  if (p.custom_secondary) t += priceFor('cor_custom');
  if (p.neons)            t += priceFor('neon');
  if (p.neon_colour)      t += priceFor('neon_cor');
  if (p.smoke)            t += priceFor('fumaca');
  if (p.tyre_smoke_color) t += priceFor('fumaca_cor');
  if (p.xenon)            t += priceFor('xenon');
  if (p.window_tint   !== undefined) t += priceFor('tint');
  if (p.livery        !== undefined) t += priceFor('livery');
  if (p.wheel_type    !== undefined) t += priceFor('wheel_type');
  if (p.plate_index   !== undefined) t += priceFor('plate_index');
  if (p.mods) for (const _ in p.mods) t += priceFor('mod_cosmetic');
  return t;
}

function renderFooter() {
  const total = calcTotal();
  document.getElementById('bn-total-cost').textContent = fmtMoney(total);
  document.getElementById('bn-btn-apply').disabled = (total === 0);
}

function pushPreview() {
  post('bennys:preview', _pending);   // preview efêmero no carro vivo
  renderFooter();
}


// ============================================================
// CÂMERA — arrasto no palco orbita; scroll dá zoom (throttle via RAF)
// ============================================================

function flushOrbit() {
  _orbitRAF = null;
  if (_orbitAcc.dx === 0 && _orbitAcc.dy === 0) return;
  post('bennys:orbit', { dx: _orbitAcc.dx, dy: _orbitAcc.dy });
  _orbitAcc.dx = 0; _orbitAcc.dy = 0;
}

function bindStage() {
  const stage = document.getElementById('bn-stage');
  stage.addEventListener('mousedown', (e) => { _drag = { x: e.clientX, y: e.clientY }; });
  window.addEventListener('mousemove', (e) => {
    if (!_drag) return;
    _orbitAcc.dx += (e.clientX - _drag.x);
    _orbitAcc.dy += (e.clientY - _drag.y);
    _drag.x = e.clientX; _drag.y = e.clientY;
    if (!_orbitRAF) _orbitRAF = requestAnimationFrame(flushOrbit);
  });
  window.addEventListener('mouseup', () => { _drag = null; });
  stage.addEventListener('wheel', (e) => { post('bennys:zoom', { delta: e.deltaY < 0 ? 1 : -1 }); }, { passive: true });
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
  // cleanup A-07: cancela RAF, zera arrasto, desanexa listeners dos pickers
  if (_orbitRAF) { cancelAnimationFrame(_orbitRAF); _orbitRAF = null; }
  _orbitAcc = { dx: 0, dy: 0 }; _drag = null;
  detachPickers();
  document.getElementById('bennys-overlay').classList.add('hidden');
  _data = null; _pending = {}; _cur = {};
}

function cancelar() {
  closeNUI();
  post('bennys:fechar', {});
}

function aplicar() {
  if (!_data || calcTotal() === 0) return;
  document.getElementById('bn-btn-apply').disabled  = true;
  document.getElementById('bn-btn-cancel').disabled = true;
  post('bennys:aplicar', { plate: _data.plate, payload: _pending });
  // a NUI fecha ao receber action='fecharBennys' (BENNYS_CONFIRM → SendNUIMessage)
}


// ============================================================
// BUS DE MENSAGENS + BIND ÚNICO
// ============================================================

window.addEventListener('message', (ev) => {
  const msg = ev.data || {};
  if (msg.action === 'openBennys')   openBennys(msg.data);
  if (msg.action === 'fecharBennys') closeNUI();
});

document.getElementById('bn-btn-cancel').addEventListener('click', cancelar);
document.getElementById('bn-btn-apply').addEventListener('click', aplicar);

// ESC fecha (cancelado) — nunca há fechamento automático por inatividade
window.addEventListener('keydown', (e) => {
  if (e.key === 'Escape' && _data) cancelar();
});

bindStage();

})();
