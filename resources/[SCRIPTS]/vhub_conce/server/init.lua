-- server/init.lua — bootstrap e lifecycle do vhub_conce
-- Ordem (fxmanifest): shared/{config,events,utils} → server/{sql,core,exports,init}
-- FASE 1: conce é escritor único de vhub_vehicles/_keys/_stock + espelho vh_vehicles;
-- garage consome via proxy. Schema (DDL) ainda mora no garage até a FASE 6.
---@diagnostic disable: undefined-global

local SQL  = VHubConce.SQL
local Core = VHubConce.Core

VHubConce._running = true   -- guard de threads/cron (desligado em onResourceStop, L-06)


-- ============================================================
-- LIFECYCLE
-- ============================================================

-- sobe o resource: DDL do prontuário + espelho vh_vehicles + backfill de chave 'owner'
AddEventHandler('onResourceStart', function(res)
  if res ~= GetCurrentResourceName() then return end
  Citizen.CreateThread(function()
    -- prontuário (vhub_vehicle_state): tabela própria, SEM FK — pode nascer aqui
    -- mesmo em DB nova. Backfill/reconcile ficam com o garage (pós-DDL de vhub_vehicles).
    pcall(function() VHubConce.VState:ensureSchema() end)
    -- idempotente; em DB nova as tabelas do garage podem ainda não existir (pcall).
    pcall(function() SQL:backfillMirror() end)       -- FASE 1: âncora física
    pcall(function() SQL:backfillOwnerKeys() end)    -- FASE 3a: todo dono tem linha 'owner'
  end)
end)

-- desliga threads de fundo de forma limpa
AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  VHubConce._running = false
end)


-- ============================================================
-- CRON 24h — varredura fria de posse temporária (L-06: guard _running + lote)
-- ============================================================

Citizen.CreateThread(function()
  while VHubConce._running do
    Citizen.Wait(VHubConce.cfg.cron_interval_ms)   -- varredura horária
    if not VHubConce._running then break end
    pcall(function() Core:returnExpiredHoldings() end)
  end
end)


-- ============================================================
-- SESSÕES (referência viva do user — base de getCharId/canOperate)
-- ============================================================

AddEventHandler('vHub:characterLoad', function(user)
  Core:setSession(user.source, user)
end)

AddEventHandler('vHub:playerSpawn', function(user)
  Core:setSession(user.source, user)
end)

AddEventHandler('playerDropped', function()
  Core:dropSession(source)
end)
