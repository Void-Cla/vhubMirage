// sims.js — slice e eventos canônicos compartilhados pelos módulos SIMS

window.vhubSims = window.vhubSims || {};
vhubSims.store = vhub.store('sims');
vhubSims.events = Object.freeze({
  RESULT: 'sims:result',
  OUTFITS: 'sims:outfits',
  WIZARD_ACCEPTED: 'sims:wizardAccepted',
});
