// runtime.js — lifecycle, store e event bus mínimos do WOW

(function () {
  'use strict';

  var modules = Object.create(null);
  var stores = Object.create(null);
  var listeners = Object.create(null);

  window.vhub = window.vhub || {};

  vhub.store = function (name) {
    if (!stores[name]) stores[name] = {};
    return stores[name];
  };

  vhub.listen = function (name, handler) {
    if (!listeners[name]) listeners[name] = [];
    listeners[name].push(handler);
    return function () {
      var list = listeners[name] || [];
      var index = list.indexOf(handler);
      if (index >= 0) list.splice(index, 1);
    };
  };

  vhub.emit = function (name, payload) {
    (listeners[name] || []).slice().forEach(function (handler) {
      try { handler(payload); } catch (error) {}
    });
  };

  vhub.createModule = function (name, spec) {
    if (!name || modules[name]) throw new Error('Módulo inválido ou duplicado: ' + name);
    modules[name] = { spec: spec, mounted: false };
  };

  vhub.mount = function (name) {
    var module = modules[name];
    if (!module || module.mounted) return false;
    var spec = module.spec;
    var root = document.getElementById(spec.rootId);
    var template = document.getElementById(spec.templateId);
    if (!root || !template) return false;
    if (spec.onInit) spec.onInit();
    root.appendChild(template.content.cloneNode(true));
    module.mounted = true;
    if (spec.onMount) spec.onMount(root);
    if (spec.onShow) spec.onShow();
    return true;
  };

  vhub.unmount = function (name) {
    var module = modules[name];
    if (!module || !module.mounted) return false;
    var spec = module.spec;
    if (spec.onHide) spec.onHide();
    if (spec.onDestroy) spec.onDestroy();
    var root = document.getElementById(spec.rootId);
    if (root) root.replaceChildren();
    module.mounted = false;
    return true;
  };

  window.addEventListener('message', function (event) {
    var message = event.data || {};
    if (typeof message.type !== 'string') return;
    vhub.emit('nui:' + message.type, message.data || {});
  });
})();

