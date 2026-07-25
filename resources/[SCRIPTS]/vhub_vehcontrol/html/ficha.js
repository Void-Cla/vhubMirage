// ficha.js — ficha, remap e nitro do veículo

(function () {
  'use strict';

  var ALLOC_LABELS = {
    potencia: 'Potência', grip: 'Aderência', frenagem: 'Freio',
    aero: 'Aero', suspensao: 'Suspensão',
  };
  var AFFIN_LABELS = {
    reta: 'Reta', curva: 'Curva', montanha: 'Montanha',
    drift: 'Drift', cidade: 'Cidade',
  };
  var state = vhub.store('sheet');
  var busOffs = [];
  var domOffs = [];

  state.sheet = state.sheet || null;
  state.editing = false;
  state.draftAlloc = null;
  state.autoEdit = false;


  // ============================================================
  // HELPERS DE RENDER
  // ============================================================

  function barRow(label, value, max, suffix) {
    var pct = max > 0 ? Math.max(0, Math.min(100, (value / max) * 100)) : 0;
    var row = document.createElement('div');
    row.className = 'vc-bar-row';
    row.innerHTML =
      '<span class="vc-bar-label">' + label + '</span>' +
      '<span class="vc-bar-track"><span class="vc-bar-fill" style="width:' +
        pct.toFixed(1) + '%"></span></span>' +
      '<span class="vc-bar-val">' + (suffix || String(value)) + '</span>';
    return row;
  }

  function allocRow(axis, value, max) {
    var row = document.createElement('div');
    row.className = 'vc-bar-row';

    if (!state.editing) {
      var pct = max > 0 ? Math.max(0, Math.min(100, (value / max) * 100)) : 0;
      row.innerHTML =
        '<span class="vc-bar-label">' + ALLOC_LABELS[axis] + '</span>' +
        '<span class="vc-bar-track"><span class="vc-bar-fill" style="width:' +
          pct.toFixed(1) + '%"></span></span>' +
        '<span class="vc-bar-val">' + value + '</span>';
      return row;
    }

    var range = (state.sheet.ranges && state.sheet.ranges[axis]) || { min: value, max: value };
    row.className += ' is-slider';
    row.innerHTML =
      '<span class="vc-bar-label">' + ALLOC_LABELS[axis] + '</span>' +
      '<input class="vc-bar-slider" type="range" data-ax="' + axis + '" min="' +
        range.min + '" max="' + range.max + '" step="1" value="' + value + '">' +
      '<span class="vc-bar-val" id="ficha-val-' + axis + '">' + value + '</span>';
    return row;
  }

  function sumAlloc(alloc) {
    var total = 0;
    for (var axis in alloc) total += Number(alloc[axis] || 0);
    return total;
  }


  // ============================================================
  // FICHA
  // ============================================================

  function receiveSheet(sheet, fromRecalibration) {
    state.sheet = sheet;
    if (!fromRecalibration) state.editing = false;
    state.draftAlloc = null;
    renderFicha();
    if (state.autoEdit && sheet && sheet.tier) {
      state.autoEdit = false;
      enterEditMode();
    }
  }

  function renderFicha() {
    var el = vhub.el;
    var sheet = state.sheet;
    if (!sheet || !sheet.tier) {
      el.fichaEmpty.classList.remove('hidden');
      el.fichaBody.classList.add('hidden');
      return;
    }

    el.fichaEmpty.classList.add('hidden');
    el.fichaBody.classList.remove('hidden');
    el.fichaTier.textContent = sheet.tier;
    el.fichaTier.dataset.tier = sheet.tier;
    el.fichaTierB.textContent = sheet.tier_base || '—';
    el.fichaTierM.textContent = sheet.tier_max || '—';
    el.fichaBudget.textContent = sheet.budget || 0;

    var alloc = state.editing ? state.draftAlloc : (sheet.alloc || {});
    var used = state.editing ? sumAlloc(state.draftAlloc) : (sheet.used || 0);
    el.fichaUsed.textContent = used;
    el.fichaScore.textContent = state.editing ? used : sheet.score;
    el.btnFichaEdit.classList.toggle('is-active', state.editing);
    el.btnFichaEdit.textContent = state.editing ? 'Editando…' : 'Calibrar';
    el.fichaEditFtr.classList.toggle('hidden', !state.editing);
    el.fichaAffinWrap.classList.toggle('hidden', state.editing);
    el.fichaBudgetLbl.textContent = state.editing ? 'Pontos livres' : 'Pontos';
    el.fichaBudgetRow.classList.toggle('is-editing', state.editing);

    el.fichaAlloc.replaceChildren();
    ['potencia', 'grip', 'frenagem', 'aero', 'suspensao'].forEach(function (axis) {
      el.fichaAlloc.appendChild(allocRow(axis, Number(alloc[axis] || 0), sheet.budget || 1));
    });

    if (!state.editing) {
      el.fichaAffin.replaceChildren();
      var affinity = sheet.affinity || {};
      ['reta', 'curva', 'montanha', 'drift', 'cidade'].forEach(function (key) {
        var value = Number(affinity[key] || 0);
        el.fichaAffin.appendChild(
          barRow(AFFIN_LABELS[key], value, 1, Math.round(value * 100) + '%')
        );
      });
    }

    el.nitroWrap.classList.toggle('hidden', state.editing);
    if (!state.editing) renderNitro();
  }

  function enterEditMode() {
    if (!state.sheet || !state.sheet.tier) return;
    state.editing = true;
    state.draftAlloc = {};
    ['potencia', 'grip', 'frenagem', 'aero', 'suspensao'].forEach(function (axis) {
      state.draftAlloc[axis] = Number((state.sheet.alloc || {})[axis] || 0);
    });
    renderFicha();
  }

  function exitEditMode(reRender) {
    state.editing = false;
    state.draftAlloc = null;
    if (vhub.el.btnFichaSave) vhub.el.btnFichaSave.disabled = false;
    if (reRender) renderFicha();
  }

  // Mantém a soma do draft igual ao budget; o servidor revalida a mutação.
  function onSliderDrag(input) {
    var axis = input.dataset.ax;
    var ranges = state.sheet.ranges || {};
    var target = Math.round(Number(input.value));
    var current = state.draftAlloc[axis];
    var delta = target - current;

    if (delta > 0) {
      var need = delta;
      var axes = Object.keys(state.draftAlloc).filter(function (other) { return other !== axis; });
      for (var index = 0; index < axes.length && need > 0; index++) {
        var other = axes[index];
        var range = ranges[other] || { min: 0, max: state.draftAlloc[other] };
        var take = Math.min(Math.max(0, state.draftAlloc[other] - range.min), need);
        state.draftAlloc[other] -= take;
        need -= take;
      }
      state.draftAlloc[axis] = target - need;
    } else if (delta < 0) {
      var give = -delta;
      var currentRange = ranges[axis] || { min: 0, max: target };
      state.draftAlloc[axis] = Math.max(currentRange.min, target);
      var otherAxes = Object.keys(state.draftAlloc).filter(function (other) {
        return other !== axis;
      });
      for (var next = 0; next < otherAxes.length && give > 0; next++) {
        var otherAxis = otherAxes[next];
        var otherRange = ranges[otherAxis] || { min: 0, max: state.draftAlloc[otherAxis] };
        var put = Math.min(Math.max(0, otherRange.max - state.draftAlloc[otherAxis]), give);
        state.draftAlloc[otherAxis] += put;
        give -= put;
      }
    }

    renderFicha();
  }


  // ============================================================
  // NITRO
  // ============================================================

  function renderNitro() {
    var el = vhub.el;
    var nitro = state.sheet && state.sheet.nitro;
    var hasKit = !!(nitro && nitro.kit);
    el.nitroNoKit.classList.toggle('hidden', hasKit);
    el.nitroBody.classList.toggle('hidden', !hasKit);
    if (!hasKit) return;

    var enabled = nitro.enabled === true;
    var level = Math.max(1, Math.min(10, Number(nitro.level || 1)));
    var quantity = Math.max(0, Math.min(100, Number(nitro.qty || 0)));
    el.nitroToggle.classList.toggle('is-on', enabled);
    el.nitroToggleLbl.textContent = enabled ? 'Ligado' : 'Desligado';
    el.nitroQty.textContent = quantity;
    el.nitroLevel.value = level;
    el.nitroLevelVal.textContent = 'Nível ' + level;
    el.nitroToggle.disabled = false;
    el.nitroCharge.disabled = quantity >= 100;
  }


  // ============================================================
  // LIFECYCLE
  // ============================================================

  vhub.createModule('ficha', {
    root: '.vc-aside-ficha',
    onInit: function () {
      busOffs.push(vhub.listen('ui:status', function (payload) {
        state.autoEdit = payload.status && payload.editTab === true;
        if (state.autoEdit && state.sheet && state.sheet.tier) enterEditMode();
      }));
      busOffs.push(vhub.listen('sheet:update', function (payload) {
        receiveSheet(payload.sheet || null, false);
      }));
      busOffs.push(vhub.listen('sheet:recalDone', function (payload) {
        vhub.el.btnFichaSave.disabled = false;
        if (payload.ok === true && payload.sheet) receiveSheet(payload.sheet, true);
      }));
      busOffs.push(vhub.listen('sheet:nitroDone', function (payload) {
        if (state.sheet && payload.nitro) state.sheet.nitro = payload.nitro;
        renderNitro();
      }));
    },
    onMount: function () {
      var el = vhub.el;
      domOffs.push(vhub.bind(el.btnFichaEdit, 'click', function () {
        if (state.editing) exitEditMode(true); else enterEditMode();
      }));
      domOffs.push(vhub.bind(el.btnFichaCancel, 'click', function () { exitEditMode(true); }));
      domOffs.push(vhub.bind(el.btnFichaSave, 'click', function () {
        if (!state.draftAlloc) return;
        el.btnFichaSave.disabled = true;
        vhub.native.sheet.recalibrate(state.draftAlloc);
      }));
      domOffs.push(vhub.bind(el.fichaAlloc, 'input', function (event) {
        if (event.target.matches('.vc-bar-slider')) onSliderDrag(event.target);
      }));
      domOffs.push(vhub.bind(el.nitroToggle, 'click', function () {
        var nitro = state.sheet && state.sheet.nitro;
        if (!nitro || !nitro.kit) return;
        el.nitroToggle.disabled = true;
        vhub.native.nitro.toggle(!nitro.enabled);
      }));
      domOffs.push(vhub.bind(el.nitroLevel, 'input', function () {
        el.nitroLevelVal.textContent = 'Nível ' + el.nitroLevel.value;
      }));
      domOffs.push(vhub.bind(el.nitroLevel, 'change', function () {
        var nitro = state.sheet && state.sheet.nitro;
        if (nitro && nitro.kit) vhub.native.nitro.level(Number(el.nitroLevel.value));
      }));
      domOffs.push(vhub.bind(el.nitroCharge, 'click', function () {
        var nitro = state.sheet && state.sheet.nitro;
        if (!nitro || !nitro.kit) return;
        el.nitroCharge.disabled = true;
        vhub.native.nitro.charge();
      }));
    },
    onShow: function () {
      var ui = vhub.store('ui');
      state.autoEdit = ui.editTab === true;
      renderFicha();
      if (state.autoEdit && state.sheet && state.sheet.tier) enterEditMode();
    },
    onHide: function () { exitEditMode(false); },
    onDestroy: function () {
      while (domOffs.length) domOffs.pop()();
      while (busOffs.length) busOffs.pop()();
      state.autoEdit = false;
      if (vhub.el.btnFichaSave) vhub.el.btnFichaSave.disabled = false;
    },
  });
})();
