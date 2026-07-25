// eventbus.js — barramento central com cleanup explícito

window.vhub = window.vhub || {};

(() => {
  const listeners = new Map();

  vhub.listen = (event, callback) => {
    if (!listeners.has(event)) listeners.set(event, new Set());
    listeners.get(event).add(callback);
    return () => {
      const bucket = listeners.get(event);
      if (!bucket) return;
      bucket.delete(callback);
      if (bucket.size === 0) listeners.delete(event);
    };
  };

  vhub.emit = (event, payload) => {
    const bucket = listeners.get(event);
    if (!bucket) return;
    [...bucket].forEach((callback) => callback(payload));
  };
})();

