// app.js — lifecycle do módulo Wizard

(() => {
  let root = null;
  let offs = [];

  vhub.createModule('wizard', {
    template: '../modules/wizard/index.html',

    onInit() {
      offs = [
        vhub.listen(vhubSims.events.RESULT, (result) => vhubSims.wizardForm.result(result)),
        vhub.listen(vhubSims.events.WIZARD_ACCEPTED, () => vhub.router.close()),
      ];
    },

    onMount(element) {
      root = element;
      vhubSims.wizardForm.mount(root);
    },

    onShow() {
      if (root) root.hidden = false;
    },

    onHide() {
      if (root) root.hidden = true;
    },

    onDestroy() {
      vhubSims.wizardForm.destroy();
      offs.forEach((off) => off());
      offs = [];
      root = null;
    },
  });
})();
