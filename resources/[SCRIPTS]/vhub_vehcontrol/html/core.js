// core.js — núcleo do NUI (vhub_vehcontrol)
// Cacheia refs globais, gerencia visibilidade do painel, despacha mensagens
// do Lua para os módulos (controls/ficha/sound), provê post() e drag genérico.
//
// Compatibilidade: mantém o objeto global `el`, as funções `showPanel`,
// `hidePanel`, `switchTab`, `post`, `attachDrag` e os callbacks que o Lua
// dispara (ui · updateFuel · emergency · sheet · recalDone · nitroDone).


// ============================================================
// NAMESPACE vhub + fila de init (módulos registram seus handlers
// e rodam APÓS o el ter sido cacheado).
// ============================================================

window.vhub = window.vhub || {};
vhub.el = {};
vhub._inits = [];
vhub.ready = function (fn) { vhub._inits.push(fn); };

// Mantém `el` global por compatibilidade com código legado.
var el = vhub.el;
var _visible = false;


// ============================================================
// CACHE DE REFS DOM — uma única passagem no DOMContentLoaded
// ============================================================

document.addEventListener('DOMContentLoaded', function () {
  // wrapper global
  el.panel        = document.getElementById('vc-panel');
  el.btnClose     = document.getElementById('btn-close');

  // controles
  el.btnEmergency = document.getElementById('btn-emergency');
  el.btnEngine    = document.getElementById('btn-engine');
  el.btnLock      = document.getElementById('btn-lock');
  el.btnLights    = document.getElementById('btn-lights');
  el.btnLight     = document.getElementById('btn-light');
  el.fuelBar      = document.getElementById('fuel-bar');
  el.fuelPct      = document.getElementById('fuel-pct');

  // ficha
  el.fichaEmpty     = document.getElementById('ficha-empty');
  el.fichaBody      = document.getElementById('ficha-body');
  el.fichaTier      = document.getElementById('ficha-tier');
  el.fichaScore     = document.getElementById('ficha-score');
  el.fichaTierB     = document.getElementById('ficha-tierbase');
  el.fichaTierM     = document.getElementById('ficha-tiermax');
  el.fichaUsed      = document.getElementById('ficha-used');
  el.fichaBudget    = document.getElementById('ficha-budget');
  el.fichaBudgetRow = document.querySelector('.vc-ficha-budget');
  el.fichaBudgetLbl = document.getElementById('ficha-budget-label');
  el.fichaAlloc     = document.getElementById('ficha-alloc');
  el.fichaAffin     = document.getElementById('ficha-affinity');
  el.fichaAffinWrap = document.getElementById('ficha-affinity-wrap');
  el.btnFichaEdit   = document.getElementById('btn-ficha-edit');
  el.fichaEditFtr   = document.getElementById('ficha-editftr');
  el.btnFichaSave   = document.getElementById('btn-ficha-save');
  el.btnFichaCancel = document.getElementById('btn-ficha-cancel');

  // nitro
  el.nitroWrap      = document.getElementById('ficha-nitro-wrap');
  el.nitroNoKit     = document.getElementById('nitro-nokit');
  el.nitroBody      = document.getElementById('nitro-body');
  el.nitroToggle    = document.getElementById('nitro-toggle');
  el.nitroToggleLbl = document.getElementById('nitro-toggle-lbl');
  el.nitroQty       = document.getElementById('nitro-qty');
  el.nitroLevel     = document.getElementById('nitro-level');
  el.nitroLevelVal  = document.getElementById('nitro-level-val');
  el.nitroCharge    = document.getElementById('nitro-charge');

  // som (Buscar=Jamendo / Rádio / URL — tudo via post() → vhub_wow)
  el.soundTitle       = document.getElementById('sound-title');
  el.soundArtist      = document.getElementById('sound-artist');
  el.soundSource      = document.getElementById('sound-source');
  el.soundViz         = document.getElementById('sound-viz');
  el.soundPlay        = document.getElementById('sound-play');
  el.soundPrev        = document.getElementById('sound-prev');
  el.soundNext        = document.getElementById('sound-next');
  el.soundVolume      = document.getElementById('sound-volume');
  el.soundVolumeVal   = document.getElementById('sound-volume-val');
  el.soundUrlRow      = document.getElementById('sound-url-row');
  el.soundUrlInput    = document.getElementById('sound-url-input');
  el.soundSearchRow   = document.getElementById('sound-search-row');
  el.soundSearchInput = document.getElementById('sound-search-input');
  el.soundResults     = document.getElementById('sound-results');

  // Roda inits dos módulos (controls.js, ficha.js, sound.js)
  vhub._inits.forEach(function (fn) {
    try { fn(el); } catch (e) { console.error('[vhub] init falhou:', e); }
  });

  // Tabs legadas (no-op se ocultas) + tecla ESC + drag de cada aside
  attachTabs();
  attachDrag();

  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape') post('exit', {});
  });

  // Fechar global (preserva #btn-close — agora vive no aside Som)
  if (el.btnClose) {
    el.btnClose.addEventListener('click', function () { post('exit', {}); });
  }
});


// ============================================================
// MENSAGENS DO LUA (SendNUIMessage) — despacha p/ módulos
// ============================================================

window.addEventListener('message', function (event) {
  var d = event.data;
  if (!d || !d.type) return;

  switch (d.type) {
    case 'ui':
      if (d.status) { showPanel(d.editTab === true); } else { hidePanel(); }
      break;
    case 'updateFuel':
      if (d.fuel !== undefined && typeof updateFuel === 'function') {
        updateFuel(Number(d.fuel));
      }
      break;
    case 'emergency':
      if (typeof setEmergency === 'function') setEmergency(d.emergencystatus === true);
      break;
    case 'sheet':
      if (typeof onSheet === 'function') onSheet(d.data || null, false);
      break;
    case 'recalDone':
      if (typeof onRecalDone === 'function') onRecalDone(d.ok === true, d.data || null);
      break;
    case 'nitroDone':
      if (typeof onNitroDone === 'function') onNitroDone(d.ok === true, d.nitro || null);
      break;
    case 'soundRejected':
      if (typeof onSoundRejected === 'function') onSoundRejected();
      break;
    case 'soundResults':
      if (typeof onSoundResults === 'function') onSoundResults(d.items || []);
      break;
    case 'soundNow':
      if (typeof onSoundNow === 'function') onSoundNow(d.title || '', d.artist || '');
      break;
  }
});


// ============================================================
// EXIBIÇÃO — toggla o wrapper #vc-panel (mostra os 3 asides juntos)
// editTab=true (via caixa de ferramentas): força aba ficha em edição
// ============================================================

function showPanel(editTab) {
  _visible = true;
  el.panel.classList.remove('hidden');
  switchTab(editTab ? 'ficha' : 'controls');
  if (editTab) vhub._pendingAutoEdit = true;
}

function hidePanel() {
  _visible = false;
  el.panel.classList.add('hidden');
  if (typeof exitEditMode === 'function') exitEditMode(false);
}


// ============================================================
// ABAS (Controles | Ficha) — mantidas para compat. No layout
// aside as duas seções aparecem juntas; switchTab continua válida
// (oculta/mostra sem afetar nada visível além das tabs ocultas).
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
  // No layout aside, os dois bodies devem ficar sempre visíveis. Não tocamos
  // em [data-tab-body] aqui (toggling antigo escondia o aside inteiro). A
  // assinatura da função permanece para o Lua / código legado.
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
// ARRASTAR — agora genérico: cada [data-drag-root] é independente.
// Pega no [data-drag-handle] interno, clampa no viewport, libera ao soltar.
// ============================================================

function attachDrag() {
  document.querySelectorAll('[data-drag-root]').forEach(function (root) {
    var handle = root.querySelector('[data-drag-handle]');
    if (!handle) return;
    _wireDrag(root, handle);
  });
}

function _wireDrag(root, handle) {
  var dragging = false;
  var startX = 0, startY = 0;
  var origX = 0, origY = 0;

  handle.addEventListener('mousedown', function (e) {
    if (e.target.closest('#btn-close')) return;
    if (e.target.closest('button')) return;  // não arrasta ao clicar em botão do header
    if (e.button !== 0) return;

    var rect = root.getBoundingClientRect();
    // fixa posição atual em px e remove qualquer transform de centralização
    root.style.left      = rect.left + 'px';
    root.style.top       = rect.top  + 'px';
    root.style.right     = 'auto';
    root.style.bottom    = 'auto';
    root.style.transform = 'none';

    origX  = rect.left;
    origY  = rect.top;
    startX = e.clientX;
    startY = e.clientY;
    dragging = true;
    root.classList.add('is-dragging');
    e.preventDefault();
  });

  document.addEventListener('mousemove', function (e) {
    if (!dragging) return;
    var dx = e.clientX - startX;
    var dy = e.clientY - startY;

    var w = root.offsetWidth;
    var h = root.offsetHeight;
    var maxX = window.innerWidth  - w - 4;
    var maxY = window.innerHeight - h - 4;

    var nx = Math.max(4, Math.min(maxX, origX + dx));
    var ny = Math.max(4, Math.min(maxY, origY + dy));
    root.style.left = nx + 'px';
    root.style.top  = ny + 'px';
  });

  document.addEventListener('mouseup', function () {
    if (!dragging) return;
    dragging = false;
    root.classList.remove('is-dragging');
  });
}
