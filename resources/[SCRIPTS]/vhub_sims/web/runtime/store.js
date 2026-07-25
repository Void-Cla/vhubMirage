// store.js — slices observáveis com owner único

window.vhub = window.vhub || {};

(() => {
  const slices = new Map();

  vhub.store = (domain, initial = {}) => {
    if (slices.has(domain)) return slices.get(domain);

    let state = { ...initial };
    const subscribers = new Set();
    const api = {
      get: () => state,
      set: (update) => {
        const patch = typeof update === 'function' ? update(state) : update;
        state = { ...state, ...(patch || {}) };
        [...subscribers].forEach((callback) => callback(state));
        return state;
      },
      reset: (next = initial) => {
        state = { ...next };
        [...subscribers].forEach((callback) => callback(state));
      },
      subscribe: (callback) => {
        subscribers.add(callback);
        return () => subscribers.delete(callback);
      },
    };
    slices.set(domain, api);
    return api;
  };
})();

