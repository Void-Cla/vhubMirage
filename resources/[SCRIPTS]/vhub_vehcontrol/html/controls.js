// controls.js — aside ESQUERDA (controles do veículo + combustível)
// Callbacks Lua: door · window · engine · light · lock · lights · seat · emergency
// Mensagens consumidas: updateFuel · emergency


vhub.ready(function (el) {
  attachHandlers();
});


// ============================================================
// COMBUSTÍVEL — única info "ao vivo" do aside
// ============================================================

function updateFuel(fuel) {
  var pct = Math.max(0, Math.min(100, fuel));
  vhub.el.fuelBar.style.transform = 'scaleX(' + (pct / 100).toFixed(3) + ')';
  vhub.el.fuelPct.textContent = pct.toFixed(0) + '%';
}


// ============================================================
// EMERGÊNCIA (pisca-alerta — toggle visual)
// ============================================================

function setEmergency(on) {
  if (on) { vhub.el.btnEmergency.classList.add('is-on'); }
  else    { vhub.el.btnEmergency.classList.remove('is-on'); }
}


// ============================================================
// HANDLERS DE CLIQUE
// ============================================================

function attachHandlers() {
  var el = vhub.el;

  el.btnEmergency.addEventListener('click', function () { post('emergency', {}); });
  el.btnEngine.addEventListener('click',    function () { post('engine', {}); });
  el.btnLock.addEventListener('click',      function () { post('lock', {}); });
  el.btnLights.addEventListener('click',    function () { post('lights', {}); });
  el.btnLight.addEventListener('click',     function () { post('light', {}); });

  var seatBtn = document.querySelector('[data-action="seat"]');
  if (seatBtn) seatBtn.addEventListener('click', function () { post('seat', {}); });

  document.querySelectorAll('[data-action="door"]').forEach(function (btn) {
    btn.addEventListener('click', function () { post('door', { door: btn.dataset.door }); });
  });

  document.querySelectorAll('[data-action="window"]').forEach(function (btn) {
    btn.addEventListener('click', function () { post('window', { window: btn.dataset.window }); });
  });
}
