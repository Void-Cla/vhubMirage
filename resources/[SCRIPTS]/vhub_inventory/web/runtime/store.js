// runtime/store.js — slices de estado por dominio (A-04).
// Cada modulo dono de seu slice. Sem segunda fonte de verdade dentro da NUI.

(function () {
  const slices = {};

  vhub.store = function (domain) {
    if (!slices[domain]) {
      slices[domain] = {
        _d: {},
        get(k) { return this._d[k]; },
        set(k, v) { this._d[k] = v; return this; },
        all() { return this._d; },
        // patch raso: chaves com valor === false sao removidas (delta de slot)
        patch(obj) {
          for (const k in obj) {
            if (obj[k] === false) delete this._d[k];
            else this._d[k] = obj[k];
          }
          return this;
        },
      };
    }
    return slices[domain];
  };
})();
