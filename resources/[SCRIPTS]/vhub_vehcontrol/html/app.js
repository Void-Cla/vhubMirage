// app.js — controle de veículo NUI (vhub_vehcontrol)
// vanilla JS, sem jQuery. Callbacks: exit · door · window · engine · light · lock · lights · seat · emergency
// Mensagens tratadas: ui · updateFuel · emergency


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
  attachHandlers();
  attachDrag();
});


// ============================================================
// MENSAGENS DO LUA (SendNUIMessage)
// ============================================================

window.addEventListener('message', function (event) {
  var d = event.data;
  if (!d || !d.type) return;

  switch (d.type) {
    case 'ui':
      if (d.status) { showPanel(); } else { hidePanel(); }
      break;
    case 'updateFuel':
      if (d.fuel !== undefined) updateFuel(Number(d.fuel));
      break;
    case 'emergency':
      setEmergency(d.emergencystatus === true);
      break;
  }
});


// ============================================================
// EXIBIÇÃO
// ============================================================

function showPanel() { _visible = true;  el.panel.classList.remove('hidden'); }
function hidePanel() { _visible = false; el.panel.classList.add('hidden'); }


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
