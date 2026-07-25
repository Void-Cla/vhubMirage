// router.js — rota modal exclusiva com unmount real

window.vhub = window.vhub || {};

(() => {
  let current = null;

  vhub.router = {
    navigate: async (name) => {
      if (current === name) return;
      if (current) vhub.unmount(current);
      current = name;
      await vhub.mount(name, '#route-layer');
    },
    close: () => {
      if (current) vhub.unmount(current);
      current = null;
    },
    current: () => current,
  };
})();

