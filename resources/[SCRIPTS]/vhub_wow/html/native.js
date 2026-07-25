// native.js — bridge único da NUI para o client Lua do WOW

(function () {
  'use strict';

  function post(endpoint, payload) {
    return fetch('https://' + GetParentResourceName() + '/' + endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload || {}),
    }).then(function (response) { return response.json(); });
  }

  vhub.native = vhub.native || {};
  vhub.native.wow = {
    setStreamerMode: function (active) {
      return post('settingsSetStreamer', { active: active === true });
    },
    closeSettings: function () {
      return post('settingsClose', {});
    },
    audioLifecycle: function (name, status) {
      return post('audioLifecycle', { name: name, status: status }).catch(function () {});
    },
  };
})();
