// ficha.js — aside DIREITA (Ficha / Remap + Nitro)
// Callbacks Lua: recalibrate · nitroToggle · nitroLevel · nitroCharge
// Mensagens consumidas: sheet · recalDone · nitroDone


// ============================================================
// ESTADO — única fonte: lastSheet (vem do servidor via 'sheet')
// ============================================================

var ALLOC_LABELS = { potencia:'Potência', grip:'Aderência', frenagem:'Freio', aero:'Aero', suspensao:'Suspensão' };
var AFFIN_LABELS = { reta:'Reta', curva:'Curva', montanha:'Montanha', drift:'Drift', cidade:'Cidade' };

var lastSheet  = null;
var editing    = false;
var draftAlloc = null;


vhub.ready(function (el) {
  attachFichaEdit();
  attachNitro();

  // Se a flag de auto-edição já tiver sido marcada pelo core (showPanel(editTab=true)
  // antes do init), entramos em edição assim que a próxima sheet chegar.
  // A flag vive em vhub._pendingAutoEdit para sobreviver entre módulos.
});


// ============================================================
// HELPERS DE LINHA (barra estática + linha de slider)
// ============================================================

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


// ============================================================
// RECEBE SHEET (REQ_SHEET inicial OU refresh pós-recalibração)
// ============================================================

function onSheet(s, fromRecal) {
  lastSheet = s;
  if (!fromRecal) editing = false;
  draftAlloc = null;
  renderFicha();
  if (vhub._pendingAutoEdit && s && s.tier) {
    vhub._pendingAutoEdit = false;
    enterEditMode();
  }
}


// ============================================================
// RENDER FICHA — alimenta cabeçalho, distribuição, afinidade, nitro
// ============================================================

function renderFicha() {
  var el = vhub.el;
  var s = lastSheet;
  if (!s || !s.tier) {
    el.fichaEmpty.classList.remove('hidden');
    el.fichaBody.classList.add('hidden');
    return;
  }
  el.fichaEmpty.classList.add('hidden');
  el.fichaBody.classList.remove('hidden');

  el.fichaTier.textContent   = s.tier;
  el.fichaTier.dataset.tier  = s.tier;
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

  // distribuição (escala = budget)
  el.fichaAlloc.innerHTML = '';
  ['potencia','grip','frenagem','aero','suspensao'].forEach(function (ax) {
    el.fichaAlloc.appendChild(allocRow(ax, Number(alloc[ax] || 0), s.budget || 1));
  });
  if (editing) bindSliders();

  // afinidade (oculta em edição)
  if (!editing) {
    el.fichaAffin.innerHTML = '';
    var aff = s.affinity || {};
    ['reta','curva','montanha','drift','cidade'].forEach(function (k) {
      var v = Number(aff[k] || 0);
      el.fichaAffin.appendChild(barRow(AFFIN_LABELS[k], v, 1, Math.round(v * 100) + '%'));
    });
  }

  // nitro (oculto em edição)
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
  var el = vhub.el;

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
  if (vhub.el.btnFichaSave) vhub.el.btnFichaSave.disabled = false;
  if (reRender) renderFicha();
}

function bindSliders() {
  var inputs = vhub.el.fichaAlloc.querySelectorAll('.vc-bar-slider');
  inputs.forEach(function (input) {
    input.addEventListener('input', function () { onSliderDrag(input); });
  });
}

// Soma SEMPRE == budget (mesma invariante validada no servidor)
function onSliderDrag(input) {
  var ax = input.dataset.ax;
  var ranges = lastSheet.ranges || {};
  var target = Math.round(Number(input.value));
  var current = draftAlloc[ax];
  var delta = target - current;

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
    draftAlloc[ax] = target - need;
  } else if (delta < 0) {
    var give = -delta;
    var r2 = ranges[ax] || { min: 0, max: target };
    draftAlloc[ax] = Math.max(r2.min, target);
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

function onRecalDone(ok, sheet) {
  if (vhub.el.btnFichaSave) vhub.el.btnFichaSave.disabled = false;
  if (ok && sheet) {
    editing = false;
    draftAlloc = null;
    onSheet(sheet, true);
  }
}


// ============================================================
// NITRO (decisão #30) — escrita delegada ao servidor; estado vem da placa
// ============================================================

function attachNitro() {
  var el = vhub.el;

  el.nitroToggle.addEventListener('click', function () {
    var n = lastSheet && lastSheet.nitro;
    if (!n || !n.kit) return;
    el.nitroToggle.disabled = true;
    post('nitroToggle', { on: !n.enabled });
  });

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

function renderNitro() {
  var el = vhub.el;
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

function onNitroDone(ok, nitro) {
  if (lastSheet && nitro) lastSheet.nitro = nitro;
  renderNitro();
}
