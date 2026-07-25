// controls.js — controles do veículo e combustível

(function () {
  'use strict';

  var state = vhub.store('vehicle');
  var busOffs = [];
  var domOffs = [];


  // ============================================================
  // RENDER
  // ============================================================

  function renderFuel() {
    var fuel = Math.max(0, Math.min(100, Number(state.fuel || 0)));
    vhub.el.fuelBar.style.transform = 'scaleX(' + (fuel / 100).toFixed(3) + ')';
    vhub.el.fuelPct.textContent = fuel.toFixed(0) + '%';
  }

  function renderEmergency() {
    vhub.el.btnEmergency.classList.toggle('is-on', state.emergency === true);
  }


  // ============================================================
  // LIFECYCLE
  // ============================================================

  vhub.createModule('controls', {
    root: '.vc-aside-controls',
    onInit: function () {
      busOffs.push(vhub.listen('vehicle:fuel', function (payload) {
        if (payload.fuel === undefined) return;
        state.fuel = Number(payload.fuel);
        renderFuel();
      }));
      busOffs.push(vhub.listen('vehicle:emergency', function (payload) {
        state.emergency = payload.emergency_status === true;
        renderEmergency();
      }));
    },
    onMount: function () {
      var el = vhub.el;
      domOffs.push(vhub.bind(el.btnEmergency, 'click', vhub.native.vehicle.emergency));
      domOffs.push(vhub.bind(el.btnEngine, 'click', vhub.native.vehicle.engine));
      domOffs.push(vhub.bind(el.btnLock, 'click', vhub.native.vehicle.lock));
      domOffs.push(vhub.bind(el.btnLights, 'click', vhub.native.vehicle.lights));
      domOffs.push(vhub.bind(el.btnLight, 'click', vhub.native.vehicle.light));

      var seat = document.querySelector('[data-action="seat"]');
      domOffs.push(vhub.bind(seat, 'click', vhub.native.vehicle.seat));
      document.querySelectorAll('[data-action="door"]').forEach(function (button) {
        domOffs.push(vhub.bind(button, 'click', function () {
          vhub.native.vehicle.door(button.dataset.door);
        }));
      });
      document.querySelectorAll('[data-action="window"]').forEach(function (button) {
        domOffs.push(vhub.bind(button, 'click', function () {
          vhub.native.vehicle.window(button.dataset.window);
        }));
      });
    },
    onShow: function () {
      if (state.fuel !== undefined) renderFuel();
      renderEmergency();
    },
    onHide: function () {},
    onDestroy: function () {
      while (domOffs.length) domOffs.pop()();
      while (busOffs.length) busOffs.pop()();
    },
  });
})();
