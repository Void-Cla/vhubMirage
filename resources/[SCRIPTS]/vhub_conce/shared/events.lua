-- shared/events.lua — fonte única de nomes de eventos do vhub_conce
-- Toda string de evento de rede vive aqui (sem literais espalhados).
---@diagnostic disable: undefined-global, lowercase-global

VHubConce     = VHubConce or {}
VHubConce.E   = {
  -- PRONTUÁRIO: emitido pelo VState após save bem-sucedido (escritor único → broadcast confiável)
  -- Shape (primitivo L-19, sem vec): { plate=string, source=string, changed={customization=bool, health=bool, fuel=bool} }
  -- Emissão: TriggerEvent local (server→server); implementação no VState na F2 (carskill/p1skill).
  -- Consumers registram via: AddEventHandler(VHubConce.E.VEHICLE_COMMITTED, function(ev) ... end)
  VEHICLE_COMMITTED = 'vHub:vehicleCommitted',
}
