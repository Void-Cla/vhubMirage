'use strict';

(function () {
  const modules = new Map();
  const actions = new Map();
  const resourceName = typeof GetParentResourceName === 'function'
    ? GetParentResourceName()
    : 'vhub_custom';

  if (!/^[A-Za-z0-9_-]{1,64}$/.test(resourceName)) throw new Error('resource inválido');

  function request(endpoint, payload, timeoutMs) {
    if (typeof endpoint !== 'string' || !/^[a-z]+:[A-Za-z]+$/.test(endpoint)) {
      return Promise.reject(new Error('endpoint inválido'));
    }
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), Number(timeoutMs) || 5000);
    return fetch('https://' + resourceName + '/' + endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(payload || {}),
      signal: controller.signal,
    }).then((response) => {
      if (!response.ok) throw new Error('NUI HTTP ' + response.status);
      return response.text();
    }).then((body) => {
      if (!body) return null;
      try { return JSON.parse(body); } catch (_) { return body; }
    }).finally(() => clearTimeout(timer));
  }

  function createModule(name, hooks) {
    if (typeof name !== 'string' || modules.has(name) || !hooks) throw new Error('módulo inválido');
    const state = { mounted: false, visible: false, destroyed: false };
    const api = {
      show(data) {
        if (state.destroyed) return;
        if (!state.mounted) { if (hooks.onMount) hooks.onMount(api); state.mounted = true; }
        state.visible = true;
        if (hooks.onShow) hooks.onShow(data, api);
      },
      hide() {
        if (state.destroyed || !state.visible) return;
        state.visible = false;
        if (hooks.onHide) hooks.onHide(api);
      },
      destroy() {
        if (state.destroyed) return;
        api.hide();
        state.destroyed = true;
        if (hooks.onDestroy) hooks.onDestroy(api);
        modules.delete(name);
        for (const [action, route] of actions) if (route.api === api) actions.delete(action);
      },
      isVisible() { return state.visible; },
    };
    modules.set(name, api);
    for (const [action, handler] of Object.entries(hooks.actions || {})) {
      if (actions.has(action) || typeof handler !== 'function') throw new Error('ação duplicada: ' + action);
      actions.set(action, { api, handler });
    }
    if (hooks.onInit) hooks.onInit(api);
    return api;
  }

  window.addEventListener('message', (event) => {
    const message = event.data;
    if (!message || typeof message.action !== 'string') return;
    const route = actions.get(message.action);
    if (route) route.handler(message, route.api);
  });

  window.addEventListener('beforeunload', () => {
    for (const module of Array.from(modules.values())) module.destroy();
  }, { once: true });

  window.vhub = Object.freeze({ request, createModule });
})();
