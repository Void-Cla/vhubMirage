-- events.lua — fonte única dos nomes de evento do SIMS

VHubSims = VHubSims or {}

VHubSims.E = {
  SRV_OPEN_REQUEST = 'vhub_sims:server:openRequest',
  SRV_CHECKOUT = 'vhub_sims:server:checkout',
  SRV_WIZARD_SUBMIT = 'vhub_sims:server:wizardSubmit',
  SRV_CANCEL = 'vhub_sims:server:cancel',
  SRV_OUTFIT_LIST = 'vhub_sims:server:outfitList',
  SRV_OUTFIT_SAVE = 'vhub_sims:server:outfitSave',
  SRV_OUTFIT_RENAME = 'vhub_sims:server:outfitRename',
  SRV_OUTFIT_DELETE = 'vhub_sims:server:outfitDelete',
  SRV_OUTFIT_APPLY = 'vhub_sims:server:outfitApply',
  CLI_STUDIO_OPEN = 'vhub_sims:client:studioOpen',
  CLI_STUDIO_CLOSE = 'vhub_sims:client:studioClose',
  CLI_CHECKOUT_RESULT = 'vhub_sims:client:checkoutResult',
  CLI_OUTFITS = 'vhub_sims:client:outfits',
  CREATION_DONE = 'vhub_sims:creationDone',
  CREATION_CANCELLED = 'vhub_sims:creationCancelled',
  NOTIFY = 'vHub:notify',
}
