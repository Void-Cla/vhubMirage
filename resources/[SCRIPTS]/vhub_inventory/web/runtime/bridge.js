// runtime/bridge.js — unico ponto de IPC NUI -> Lua (A-06).
// Modulos nunca fazem fetch espalhado; chamam vhub.post(callback, data).

(function () {
  const RES = (typeof GetParentResourceName === 'function')
    ? GetParentResourceName() : 'vhub_inventory';

  // POST para um RegisterNUICallback do Lua; erro sempre volta tipado.
  vhub.post = function (cb, data) {
    return fetch(`https://${RES}/${cb}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data || {}),
    })
      .then((r) => r.json().catch(() => ({ ok: false, err: 'invalid_json' })))
      .catch(() => ({ ok: false, err: 'fetch_failed' }));
  };
})();
