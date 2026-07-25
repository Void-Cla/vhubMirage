// services/index.js — única borda NUI do Checkout

window.vhubSims = window.vhubSims || {};

vhubSims.checkoutService = Object.freeze({
  confirm: () => vhub.native.post('checkout', {
    session_id: vhubSims.store.get().sessionId,
    patch: vhubSims.store.get().patch || {},
  }),
});
