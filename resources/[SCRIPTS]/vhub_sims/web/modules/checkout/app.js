// app.js — lifecycle do módulo Checkout

(() => {
  let root = null;
  let offs = [];

  vhub.createModule('checkout', {
    template: '../modules/checkout/index.html',

    onInit() {
      offs = [vhub.listen(vhubSims.events.RESULT, (result) => vhubSims.cart.result(result))];
    },

    onMount(element) {
      root = element;
      vhubSims.cart.mount(root);
    },

    onShow() {
      if (root) root.hidden = false;
    },

    onHide() {
      if (root) root.hidden = true;
    },

    onDestroy() {
      vhubSims.cart.destroy();
      offs.forEach((off) => off());
      offs = [];
      root = null;
    },
  });
})();
