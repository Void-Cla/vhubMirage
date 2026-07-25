-- vhub_spawselector/client/main.lua — UI pura de eleição de coordenada
-- PAPEL (Void-Zero/It.1): NUNCA toca o ped. Sem SetEntityCoords, sem auto-open.
--   Abre quando o servidor manda (Open), traduz a escolha posicional da NUI para
--   o index CANÔNICO do Config e envia RequestSpawn. Quem move o ped é o
--   vhub_hss (release/teleport).

local _payload = nil   -- último payload do servidor; itens carregam .index canônico
local _aberto  = false

local function abrirUI(payload)
  _payload = payload
  _aberto  = true
  ClearTimecycleModifier()
  DoScreenFadeIn(0)
  SetNuiFocus(true, true)
  SendNUIMessage({
    action = "open",
    data   = payload.data,
    last   = payload.last,
  })
end

local function fecharUI()
  if not _aberto then return end
  _aberto = false
  _payload = nil
  SetNuiFocus(false, false)
  ClearTimecycleModifier()
  DoScreenFadeIn(0)
  SendNUIMessage({ action = "close" })
end

-- ── Servidor manda abrir (fluxo do Spawn Owner ou RequestOpen manual) ─────────

RegisterNetEvent(VHubSpawnSelector.E.OPEN)
AddEventHandler(VHubSpawnSelector.E.OPEN, function(payload)
  if type(payload) ~= "table" or type(payload.data) ~= "table" then return end
  abrirUI(payload)
end)

-- Export manual (admin/debug): pede ao servidor — validação e filtro são server-side
exports("Open", function()
  TriggerServerEvent(VHubSpawnSelector.E.REQUEST_OPEN)
end)

-- ── Callbacks da NUI ──────────────────────────────────────────────────────────

-- A NUI envia a POSIÇÃO do card (1-based, pós-filtro). Traduz para o index
-- canônico do Config antes de enviar — a renumeração da UI nunca chega ao server.
RegisterNUICallback("teleport", function(data, cb)
  local pos_ui = data and tonumber(data.index)
  local canon  = nil
  if pos_ui and _payload and _payload.data[pos_ui] then
    canon = _payload.data[pos_ui].index
  end
  TriggerServerEvent(VHubSpawnSelector.E.REQUEST_SPAWN, canon)  -- nil = fechar/pos salva
  fecharUI()
  cb({ ok = true })
end)

-- Higiene: parar o resource com a UI aberta não pode deixar foco/vignette herdados na tela.
AddEventHandler("onResourceStop", function(res)
  if res ~= GetCurrentResourceName() then return end
  if _aberto then
    SetNuiFocus(false, false)
    ClearTimecycleModifier()
    DoScreenFadeIn(0)
    SendNUIMessage({ action = "close" })
  end
  _aberto = false
  _payload = nil
end)
