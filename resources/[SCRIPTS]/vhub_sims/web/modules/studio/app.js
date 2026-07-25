// app.js — lifecycle do módulo Studio

(() => {
  let root = null;
  let offs = [];
  let keyHandler = null;

  vhub.createModule('studio', {
    template: '../modules/studio/index.html',

    onInit() {
      offs = [
        vhub.listen(vhubSims.events.RESULT, (result) => vhubSims.editor.result(result)),
        vhub.listen(vhubSims.events.OUTFITS, () => vhubSims.editor.outfits()),
      ];
      keyHandler = (event) => {
        if (event.key === 'Escape') vhubSims.studioService.cancel();
      };
      document.addEventListener('keydown', keyHandler);
    },

    onMount(element) {
      root = element;
      vhubSims.editor.mount(root);
    },

    onShow() {
      if (root) root.hidden = false;
    },

    onHide() {
      if (root) root.hidden = true;
    },

    onDestroy() {
      vhubSims.editor.destroy();
      vhubSims.studioService.destroy();
      offs.forEach((off) => off());
      offs = [];
      if (keyHandler) document.removeEventListener('keydown', keyHandler);
      keyHandler = null;
      root = null;
    },
  });
})();
