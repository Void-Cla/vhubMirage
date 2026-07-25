// settings.js — componente lazy das preferências locais do WOW

(function () {
  'use strict';

  var state = vhub.store('wow');
  var refs = {};
  var offs = [];
  var handlers = {};
  var generation = 0;

  function render(payload) {
    if (payload && typeof payload.streamer_mode === 'boolean') {
      state.streamer_mode = payload.streamer_mode;
    }
    if (!refs.toggle) return;
    refs.toggle.checked = state.streamer_mode === true;
    refs.toggle.setAttribute('aria-checked', refs.toggle.checked ? 'true' : 'false');
    refs.status.textContent = refs.toggle.checked
      ? 'Áudio do WOW silenciado neste cliente.'
      : 'Áudio do WOW liberado neste cliente.';
  }

  vhub.createModule('wow-settings', {
    rootId: 'wow-settings-root',
    templateId: 'wow-settings-template',

    onInit: function () {
      offs.push(vhub.listen('nui:wow:settings:state', render));
      offs.push(vhub.listen('nui:wow:settings:close', function () {
        vhub.unmount('wow-settings');
      }));
    },

    onMount: function (root) {
      generation += 1;
      refs.toggle = root.querySelector('#wow-streamer-mode');
      refs.close = root.querySelector('.wow-settings__close');
      refs.status = root.querySelector('.wow-settings__status');

      handlers.change = function () {
        var requested = refs.toggle.checked;
        var requestGeneration = generation;
        refs.toggle.disabled = true;
        vhub.native.wow.setStreamerMode(requested).then(function (response) {
          if (requestGeneration !== generation || !refs.toggle) return;
          refs.toggle.disabled = false;
          render(response && response.ok === true && response.data
            ? response.data : { streamer_mode: !requested });
        }).catch(function () {
          if (requestGeneration !== generation || !refs.toggle) return;
          refs.toggle.disabled = false;
          render({ streamer_mode: !requested });
        });
      };
      handlers.close = function () { vhub.native.wow.closeSettings(); };
      handlers.keydown = function (event) {
        if (event.key === 'Escape') vhub.native.wow.closeSettings();
      };

      refs.toggle.addEventListener('change', handlers.change);
      refs.close.addEventListener('click', handlers.close);
      document.addEventListener('keydown', handlers.keydown);
      render(state);
    },

    onShow: function () {
      if (refs.toggle) refs.toggle.focus();
    },

    onHide: function () {},

    onDestroy: function () {
      generation += 1;
      if (refs.toggle) refs.toggle.removeEventListener('change', handlers.change);
      if (refs.close) refs.close.removeEventListener('click', handlers.close);
      document.removeEventListener('keydown', handlers.keydown);
      while (offs.length) offs.pop()();
      refs = {};
      handlers = {};
    },
  });

  vhub.listen('nui:wow:settings:open', function (payload) {
    state.streamer_mode = payload.streamer_mode === true;
    vhub.mount('wow-settings');
    render(payload);
  });
})();
