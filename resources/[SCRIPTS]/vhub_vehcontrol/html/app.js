// app.js — controle de veículo NUI (vhub_vehcontrol)
// vanilla JS, sem jQuery. Callbacks: exit · door · window · engine · light · lock · lights · seat ·
// emergency · recalibrate
// Mensagens tratadas: ui · updateFuel · emergency · sheet · recalDone


// ============================================================
// REFS DOM (cacheadas no DOMContentLoaded)
// ============================================================

var el = {};
var _visible = false;

document.addEventListener('DOMContentLoaded', function () {
  el.panel        = document.getElementById('vc-panel');
  el.btnClose     = document.getElementById('btn-close');
  el.btnEmergency = document.getElementById('btn-emergency');
  el.btnEngine    = document.getElementById('btn-engine');
  el.btnLock      = document.getElementById('btn-lock');
  el.btnLights    = document.getElementById('btn-lights');
  el.btnLight     = document.getElementById('btn-light');
  el.fuelBar      = document.getElementById('fuel-bar');
  el.fuelPct      = document.getElementById('fuel-pct');
  // ficha
  el.fichaEmpty   = document.getElementById('ficha-empty');
  el.fichaBody    = document.getElementById('ficha-body');
  el.fichaTier    = document.getElementById('ficha-tier');
  el.fichaScore   = document.getElementById('ficha-score');
  el.fichaTierB   = document.getElementById('ficha-tierbase');
  el.fichaTierM   = document.getElementById('ficha-tiermax');
  el.fichaUsed     = document.getElementById('ficha-used');
  el.fichaBudget   = document.getElementById('ficha-budget');
  el.fichaBudgetRow = document.querySelector('.vc-ficha-budget');
  el.fichaBudgetLbl = document.getElementById('ficha-budget-label');
  el.fichaAlloc    = document.getElementById('ficha-alloc');
  el.fichaAffin    = document.getElementById('ficha-affinity');
  el.fichaAffinWrap = document.getElementById('ficha-affinity-wrap');
  el.btnFichaEdit  = document.getElementById('btn-ficha-edit');
  el.fichaEditFtr  = document.getElementById('ficha-editftr');
  el.btnFichaSave  = document.getElementById('btn-ficha-save');
  el.btnFichaCancel = document.getElementById('btn-ficha-cancel');
  // nitro (decisão #30)
  el.nitroWrap     = document.getElementById('ficha-nitro-wrap');
  el.nitroNoKit    = document.getElementById('nitro-nokit');
  el.nitroBody     = document.getElementById('nitro-body');
  el.nitroToggle   = document.getElementById('nitro-toggle');
  el.nitroToggleLbl = document.getElementById('nitro-toggle-lbl');
  el.nitroQty      = document.getElementById('nitro-qty');
  el.nitroLevel    = document.getElementById('nitro-level');
  el.nitroLevelVal = document.getElementById('nitro-level-val');
  el.nitroCharge   = document.getElementById('nitro-charge');
  attachHandlers();
  attachTabs();
  attachDrag();
  attachFichaEdit();
  attachNitro();
});


// ============================================================
// MENSAGENS DO LUA (SendNUIMessage)
// ============================================================

window.addEventListener('message', function (event) {
  var d = event.data;
  if (!d || !d.type) return;

  switch (d.type) {
    case 'ui':
      if (d.status) { showPanel(d.editTab === true); } else { hidePanel(); }
      break;
    case 'updateFuel':
      if (d.fuel !== undefined) updateFuel(Number(d.fuel));
      break;
    case 'emergency':
      setEmergency(d.emergencystatus === true);
      break;
    case 'sheet':
      onSheet(d.data || null, false);
      break;
    case 'recalDone':
      onRecalDone(d.ok === true, d.data || null);
      break;
    case 'nitroDone':
      onNitroDone(d.ok === true, d.nitro || null);
      break;
  }
});


// ============================================================
// EXIBIÇÃO
// ============================================================

// editTab=true (uso da caixa de ferramentas): abre direto na aba Ficha já em modo edição
function showPanel(editTab) {
  _visible = true;
  el.panel.classList.remove('hidden');
  switchTab(editTab ? 'ficha' : 'controls');
  if (editTab) pendingAutoEdit = true; // sheet ainda não chegou — entra em edição quando chegar
}
function hidePanel() { _visible = false; el.panel.classList.add('hidden'); exitEditMode(false); }


// ============================================================
// COMBUSTÍVEL (única info do painel)
// ============================================================

function updateFuel(fuel) {
  var pct = Math.max(0, Math.min(100, fuel));
  el.fuelBar.style.transform = 'scaleX(' + (pct / 100).toFixed(3) + ')';
  el.fuelPct.textContent = pct.toFixed(0) + '%';
}


// ============================================================
// EMERGÊNCIA (pisca-alerta — toggle visual)
// ============================================================

function setEmergency(on) {
  if (on) { el.btnEmergency.classList.add('is-on'); }
  else    { el.btnEmergency.classList.remove('is-on'); }
}


// ============================================================
// ABAS (Controles | Ficha)
// ============================================================

function attachTabs() {
  document.querySelectorAll('.vc-tab').forEach(function (tab) {
    tab.addEventListener('click', function () { switchTab(tab.dataset.tab); });
  });
}

function switchTab(name) {
  document.querySelectorAll('.vc-tab').forEach(function (t) {
    t.classList.toggle('is-active', t.dataset.tab === name);
  });
  document.querySelectorAll('[data-tab-body]').forEach(function (b) {
    b.classList.toggle('hidden', b.dataset.tabBody !== name);
  });
}


// ============================================================
// FICHA DO VEÍCULO (render read-only + modo edição com sliders)
// ============================================================

// rótulos PT-BR dos 5 eixos e das 5 afinidades (ordem fixa)
var ALLOC_LABELS = { potencia:'Potência', grip:'Aderência', frenagem:'Freio', aero:'Aero', suspensao:'Suspensão' };
var AFFIN_LABELS = { reta:'Reta', curva:'Curva', montanha:'Montanha', drift:'Drift', cidade:'Cidade' };

var lastSheet     = null;   // última ficha real recebida do servidor (fonte única — L-04)
var editing       = false;  // true = modo edição ativo (sliders)
var draftAlloc    = null;   // alloc em edição (não persistido até "Salvar")
var pendingAutoEdit = false; // true = entra em edição assim que a próxima sheet chegar (via item)

// monta uma barra ESTÁTICA rotulada (valor 0..max) — usada em afinidade (sempre read-only)
function barRow(label, value, max, suffix) {
  var pct = max > 0 ? Math.max(0, Math.min(100, (value / max) * 100)) : 0;
  var row = document.createElement('div');
  row.className = 'vc-bar-row';
  row.innerHTML =
    '<span class="vc-bar-label">' + label + '</span>' +
    '<span class="vc-bar-track"><span class="vc-bar-fill" style="width:' + pct.toFixed(1) + '%"></span></span>' +
    '<span class="vc-bar-val">' + (suffix || String(value)) + '</span>';
  return row;
}

// monta uma barra de DISTRIBUIÇÃO — read-only (track+fill) ou slider (modo edição)
function allocRow(ax, value, max) {
  var row = document.createElement('div');
  row.className = 'vc-bar-row';
  var valId = 'ficha-val-' + ax;

  if (!editing) {
    var pct = max > 0 ? Math.max(0, Math.min(100, (value / max) * 100)) : 0;
    row.innerHTML =
      '<span class="vc-bar-label">' + ALLOC_LABELS[ax] + '</span>' +
      '<span class="vc-bar-track"><span class="vc-bar-fill" style="width:' + pct.toFixed(1) + '%"></span></span>' +
      '<span class="vc-bar-val">' + value + '</span>';
    return row;
  }

  var r = (lastSheet.ranges && lastSheet.ranges[ax]) || { min: value, max: value };
  row.className += ' is-slider';
  row.innerHTML =
    '<span class="vc-bar-label">' + ALLOC_LABELS[ax] + '</span>' +
    '<input class="vc-bar-slider" type="range" data-ax="' + ax + '" ' +
      'min="' + r.min + '" max="' + r.max + '" step="1" value="' + value + '">' +
    '<span class="vc-bar-val" id="' + valId + '">' + value + '</span>';
  return row;
}

// recebe sheet do servidor (REQ_SHEET inicial OU refresh pós-recalibração)
function onSheet(s, fromRecal) {
  lastSheet = s;
  if (!fromRecal) editing = false; // sheet "fria" (abrir painel) nunca entra editando sem o item
  draftAlloc = null;
  renderFicha();
  if (pendingAutoEdit && s && s.tier) {
    pendingAutoEdit = false;
    enterEditMode();
  }
}

// renderiza a ficha completa (cabeçalho + barras) no modo atual (editing flag)
function renderFicha() {
  var s = lastSheet;
  if (!s || !s.tier) {
    el.fichaEmpty.classList.remove('hidden');
    el.fichaBody.classList.add('hidden');
    return;
  }
  el.fichaEmpty.classList.add('hidden');
  el.fichaBody.classList.remove('hidden');

  el.fichaTier.textContent   = s.tier;
  el.fichaTier.dataset.tier  = s.tier;            // estilo por cor do tier (CSS)
  el.fichaTierB.textContent  = s.tier_base || '—';
  el.fichaTierM.textContent  = s.tier_max  || '—';
  el.fichaBudget.textContent = s.budget || 0;

  var alloc = editing ? draftAlloc : (s.alloc || {});
  var used  = editing ? sumAlloc(draftAlloc) : (s.used || 0);
  el.fichaUsed.textContent  = used;
  el.fichaScore.textContent = editing ? used : s.score;

  el.btnFichaEdit.classList.toggle('is-active', editing);
  el.btnFichaEdit.textContent = editing ? 'Editando…' : 'Calibrar';
  el.fichaEditFtr.classList.toggle('hidden', !editing);
  el.fichaAffinWrap.classList.toggle('hidden', editing);
  el.fichaBudgetLbl.textContent = editing ? 'Pontos livres' : 'Pontos';
  el.fichaBudgetRow.classList.toggle('is-editing', editing);

  // barras de distribuição (escala = budget, p/ comparar eixos no mesmo teto)
  el.fichaAlloc.innerHTML = '';
  ['potencia','grip','frenagem','aero','suspensao'].forEach(function (ax) {
    el.fichaAlloc.appendChild(allocRow(ax, Number(alloc[ax] || 0), s.budget || 1));
  });
  if (editing) bindSliders();

  // barras de afinidade (0..1 → %) — somem em modo edição (não fazem sentido em draft)
  if (!editing) {
    el.fichaAffin.innerHTML = '';
    var aff = s.affinity || {};
    ['reta','curva','montanha','drift','cidade'].forEach(function (k) {
      var v = Number(aff[k] || 0);
      el.fichaAffin.appendChild(barRow(AFFIN_LABELS[k], v, 1, Math.round(v * 100) + '%'));
    });
  }

  // nitro: some em modo edição (calibração de pontos), aparece em modo leitura
  el.nitroWrap.classList.toggle('hidden', editing);
  if (!editing) renderNitro();
}

function sumAlloc(a) {
  var t = 0;
  for (var ax in a) t += Number(a[ax] || 0);
  return t;
}

// ============================================================
// MODO EDIÇÃO — redistribuição local (draft) com soma fixa = budget
// ============================================================

function attachFichaEdit() {
  el.btnFichaEdit.addEventListener('click', function () {
    if (editing) { exitEditMode(true); } else { enterEditMode(); }
  });
  el.btnFichaCancel.addEventListener('click', function () { exitEditMode(true); });
  el.btnFichaSave.addEventListener('click', function () {
    if (!draftAlloc) return;
    el.btnFichaSave.disabled = true;
    post('recalibrate', { alloc: draftAlloc });
  });
}

function enterEditMode() {
  if (!lastSheet || !lastSheet.tier) return;
  editing = true;
  draftAlloc = {};
  ['potencia','grip','frenagem','aero','suspensao'].forEach(function (ax) {
    draftAlloc[ax] = Number((lastSheet.alloc || {})[ax] || 0);
  });
  renderFicha();
}

function exitEditMode(reRender) {
  editing = false;
  draftAlloc = null;
  el.btnFichaSave.disabled = false;
  if (reRender) renderFicha();
}

// liga o drag dos sliders: ao mover um eixo, o delta é retirado/devolvido aos
// DEMAIS eixos (ordem fixa TR.AXES) respeitando o min/max de cada um — soma
// permanece SEMPRE == budget (mesma invariante que o servidor valida no final)
function bindSliders() {
  var inputs = el.fichaAlloc.querySelectorAll('.vc-bar-slider');
  inputs.forEach(function (input) {
    input.addEventListener('input', function () { onSliderDrag(input); });
  });
}

function onSliderDrag(input) {
  var ax = input.dataset.ax;
  var ranges = lastSheet.ranges || {};
  var target = Math.round(Number(input.value));
  var current = draftAlloc[ax];
  var delta = target - current; // >0 = eixo pediu pontos; <0 = eixo devolveu pontos

  if (delta > 0) {
    var need = delta;
    var axes = Object.keys(draftAlloc).filter(function (a) { return a !== ax; });
    for (var i = 0; i < axes.length && need > 0; i++) {
      var other = axes[i];
      var r = ranges[other] || { min: 0, max: draftAlloc[other] };
      var room = Math.max(0, draftAlloc[other] - r.min);
      var take = Math.min(room, need);
      draftAlloc[other] -= take;
      need -= take;
    }
    draftAlloc[ax] = target - need; // se não houve doadores suficientes, sobe só o possível
  } else if (delta < 0) {
    var give = -delta;
    var r2 = ranges[ax] || { min: 0, max: target };
    draftAlloc[ax] = Math.max(r2.min, target);
    // devolve o excedente ao eixo de MAIOR folga até o teto, em ordem fixa
    var axes2 = Object.keys(draftAlloc).filter(function (a) { return a !== ax; });
    for (var j = 0; j < axes2.length && give > 0; j++) {
      var other2 = axes2[j];
      var r3 = ranges[other2] || { min: 0, max: draftAlloc[other2] };
      var room2 = Math.max(0, r3.max - draftAlloc[other2]);
      var put = Math.min(room2, give);
      draftAlloc[other2] += put;
      give -= put;
    }
  }

  renderFicha();
}

// resultado da recalibração — sucesso: sai de edição e mostra ficha nova; erro: permanece editando
function onRecalDone(ok, sheet) {
  el.btnFichaSave.disabled = false;
  if (ok && sheet) {
    editing = false;
    draftAlloc = null;
    onSheet(sheet, true);
  }
}


// ============================================================
// NITRO (decisão #30) — estado da placa (sheet.nitro); escrita delegada ao servidor
// ============================================================

// liga os controles UMA vez (toggle / slider de nível / abastecer)
function attachNitro() {
  el.nitroToggle.addEventListener('click', function () {
    var n = lastSheet && lastSheet.nitro;
    if (!n || !n.kit) return;
    el.nitroToggle.disabled = true;
    post('nitroToggle', { on: !n.enabled });   // servidor responde com nitroDone (re-render)
  });

  // ajusta o rótulo ao arrastar; só envia ao SOLTAR (change) p/ não floodar o servidor
  el.nitroLevel.addEventListener('input', function () {
    el.nitroLevelVal.textContent = 'Nível ' + el.nitroLevel.value;
  });
  el.nitroLevel.addEventListener('change', function () {
    var n = lastSheet && lastSheet.nitro;
    if (!n || !n.kit) return;
    post('nitroLevel', { level: Number(el.nitroLevel.value) });
  });

  el.nitroCharge.addEventListener('click', function () {
    var n = lastSheet && lastSheet.nitro;
    if (!n || !n.kit) return;
    el.nitroCharge.disabled = true;
    post('nitroCharge', {});
  });
}

// desenha a seção nitro a partir de lastSheet.nitro (sem kit = instrução; com kit = controles)
function renderNitro() {
  var n = lastSheet && lastSheet.nitro;
  var hasKit = !!(n && n.kit);

  el.nitroNoKit.classList.toggle('hidden', hasKit);
  el.nitroBody.classList.toggle('hidden', !hasKit);
  if (!hasKit) return;

  var on  = n.enabled === true;
  var lvl = Math.max(1, Math.min(10, Number(n.level || 1)));
  var qty = Math.max(0, Math.min(100, Number(n.qty || 0)));

  el.nitroToggle.classList.toggle('is-on', on);
  el.nitroToggleLbl.textContent = on ? 'Ligado' : 'Desligado';
  el.nitroQty.textContent = qty;

  el.nitroLevel.value = lvl;
  el.nitroLevelVal.textContent = 'Nível ' + lvl;

  el.nitroToggle.disabled = false;
  el.nitroCharge.disabled = (qty >= 100);
}

// resultado de uma operação de nitro — usa o estado fresco do servidor (fonte única).
// renderNitro reaplica o estado final dos botões (toggle habilitado, charge conforme carga).
function onNitroDone(ok, nitro) {
  if (lastSheet && nitro) lastSheet.nitro = nitro;
  renderNitro();
}


// ============================================================
// NUI CALLBACK — post para o Lua
// ============================================================

var RES = null;
function res() {
  if (!RES) RES = 'https://' + GetParentResourceName() + '/';
  return RES;
}

function post(endpoint, payload) {
  fetch(res() + endpoint, {
    method:  'POST',
    headers: { 'Content-Type': 'application/json' },
    body:    JSON.stringify(payload || {}),
  }).catch(function () {});
}


// ============================================================
// HANDLERS DE CLIQUE
// ============================================================

function attachHandlers() {
  el.btnClose.addEventListener('click',     function () { post('exit', {}); });
  el.btnEmergency.addEventListener('click', function () { post('emergency', {}); });
  el.btnEngine.addEventListener('click',    function () { post('engine', {}); });
  el.btnLock.addEventListener('click',      function () { post('lock', {}); });
  el.btnLights.addEventListener('click',    function () { post('lights', {}); });
  el.btnLight.addEventListener('click',     function () { post('light', {}); });

  document.querySelector('[data-action="seat"]').addEventListener('click', function () {
    post('seat', {});
  });

  document.querySelectorAll('[data-action="door"]').forEach(function (btn) {
    btn.addEventListener('click', function () { post('door', { door: btn.dataset.door }); });
  });

  document.querySelectorAll('[data-action="window"]').forEach(function (btn) {
    btn.addEventListener('click', function () { post('window', { window: btn.dataset.window }); });
  });

  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape') post('exit', {});
  });
}


// ============================================================
// ARRASTAR PAINEL (pega no header, clampa no viewport)
// ============================================================

function attachDrag() {
  var handle = el.panel.querySelector('[data-drag-handle]');
  if (!handle) return;

  var dragging = false;
  var startX = 0, startY = 0;
  var origX = 0, origY = 0;
  var moved = false;

  handle.addEventListener('mousedown', function (e) {
    // ignora clique no botao fechar
    if (e.target.closest('#btn-close')) return;
    if (e.button !== 0) return;

    var rect = el.panel.getBoundingClientRect();
    // fixa posicao atual (remove o transform translateY central) para arrasto absoluto
    el.panel.style.left = rect.left + 'px';
    el.panel.style.top  = rect.top  + 'px';
    el.panel.style.right = 'auto';
    el.panel.style.bottom = 'auto';
    el.panel.style.transform = 'none';

    origX = rect.left;
    origY = rect.top;
    startX = e.clientX;
    startY = e.clientY;
    dragging = true;
    moved = false;
    el.panel.classList.add('is-dragging');
    e.preventDefault();
  });

  document.addEventListener('mousemove', function (e) {
    if (!dragging) return;
    var dx = e.clientX - startX;
    var dy = e.clientY - startY;
    if (Math.abs(dx) + Math.abs(dy) > 2) moved = true;

    var w = el.panel.offsetWidth;
    var h = el.panel.offsetHeight;
    var maxX = window.innerWidth  - w - 4;
    var maxY = window.innerHeight - h - 4;

    var nx = Math.max(4, Math.min(maxX, origX + dx));
    var ny = Math.max(4, Math.min(maxY, origY + dy));
    el.panel.style.left = nx + 'px';
    el.panel.style.top  = ny + 'px';
  });

  document.addEventListener('mouseup', function () {
    if (!dragging) return;
    dragging = false;
    el.panel.classList.remove('is-dragging');
  });
}
