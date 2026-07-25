// services/index.js — única borda NUI do Wizard

window.vhubSims = window.vhubSims || {};

vhubSims.wizardService = Object.freeze({
  submit: (identity) => vhub.native.post('wizard', identity),
});

