// native.js — ponte NUI única; módulos acessam somente via services

window.vhub = window.vhub || {};

(() => {
  const resource = typeof GetParentResourceName === 'function'
    ? GetParentResourceName()
    : 'vhub_sims';

  async function post(endpoint, payload = {}) {
    try {
      const response = await fetch(`https://${resource}/${endpoint}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(payload),
      });
      return await response.json();
    } catch (_error) {
      return { ok: false, err: 'bridge_unavailable' };
    }
  }

  vhub.native = Object.freeze({ post });
})();

