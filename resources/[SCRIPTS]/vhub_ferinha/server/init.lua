-- server/init.lua — bootstrap e lifecycle do vhub_ferinha (leilão; FASE 4)
-- As tabelas vhub_auctions/_bids têm DDL no garage até a FASE 6 — ferinha só faz DML.
-- Marketplace P2P genérico (vhub_market_listings) é incremento futuro.
---@diagnostic disable: undefined-global

local Core = VHubFerinha.Core

VHubFerinha._running = true   -- guard de threads/cron (L-06)


-- ============================================================
-- LIFECYCLE
-- ============================================================

-- sobe o resource: reconcilia leilões órfãos (servidor reiniciou com leilão 'active' →
-- escrow em memória perdido). Estorna bidders (offline-safe) + devolve carros. Idempotente.
AddEventHandler('onResourceStart', function(res)
  if res ~= GetCurrentResourceName() then return end
  Citizen.CreateThread(function()
    pcall(function() VHubFerinha.reconcileOrphans() end)
  end)
end)

AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  VHubFerinha._running = false
end)


-- ============================================================
-- SESSÕES (escrow/entrega resolvem char_id↔src server-side)
-- ============================================================

AddEventHandler('vHub:characterLoad', function(user) Core:setSession(user.source, user) end)
AddEventHandler('vHub:playerSpawn',  function(user) Core:setSession(user.source, user) end)
AddEventHandler('playerDropped',     function() Core:dropSession(source) end)


-- ============================================================
-- CRON — encerra leilões vencidos (thread fria guardada, lote Wait(0))
-- ============================================================

Citizen.CreateThread(function()
  while VHubFerinha._running do
    Citizen.Wait(60 * 1000)
    if not VHubFerinha._running then break end
    pcall(function() VHubFerinha.finalizeExpired() end)
  end
end)
