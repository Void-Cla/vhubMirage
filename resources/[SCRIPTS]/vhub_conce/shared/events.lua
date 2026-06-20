-- shared/events.lua — fonte única de nomes de eventos do vhub_conce
-- Toda string de evento de rede vive aqui (sem literais espalhados).
---@diagnostic disable: undefined-global, lowercase-global

VHubConce     = VHubConce or {}
VHubConce.E   = {
  -- ciclo de vida / setup (cliente pede config da concessionária — FASE 2)
  SETUP        = 'vhub_conce:setup',
  NOTIFY       = 'vhub_conce:notify',

  -- concessionária (FASE 2)
  REQ_CATALOG  = 'vhub_conce:reqCatalog',
  OPEN_UI      = 'vhub_conce:openUI',
  ACT_BUY      = 'vhub_conce:buy',
  ACT_TESTDRIVE= 'vhub_conce:testDrive',

  -- PRONTUÁRIO: emitido pelo VState após save bem-sucedido (escritor único → broadcast confiável)
  -- Shape (primitivo L-19, sem vec): { plate=string, source=string, changed={customization=bool, health=bool, fuel=bool} }
  -- Emissão: TriggerEvent local (server→server); implementação no VState na F2 (carskill/p1skill).
  -- Consumers registram via: AddEventHandler(VHubConce.E.VEHICLE_COMMITTED, function(ev) ... end)
  VEHICLE_COMMITTED = 'vHub:vehicleCommitted',
}
