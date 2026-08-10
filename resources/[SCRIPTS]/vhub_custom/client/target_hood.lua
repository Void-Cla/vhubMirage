-- client/target_hood.lua — interação IMERSIVA do capô via vhub_target (ADR #82 F2.2)
--
-- Substitui o gatilho de proximidade+[E] da oficina por uma interação de OLHO no próprio carro:
-- o jogador mira o veículo perto da oficina → abre o capô (UX) → escolhe abrir a oficina ou
-- inspecionar o motor. É L2/L3 puro (affordance): NÃO decide verdade. A abertura real passa pelo
-- gate físico server-side EXISTENTE (SERVICE_AUTH → Core.validateVehicle) e a inspeção idem
-- (ENGINE_BAY_INSPECT gated). Skill de referência: interacao_target_migration (#57).
--
-- SOFT-DEP: vhub_target pode não estar de pé. Todo registro é pcall — sem ele, o fluxo antigo por
-- proximidade continua valendo (client/zones.lua mantém a thread fria). Zero acoplamento de boot.
---@diagnostic disable: undefined-global, lowercase-global

local CFG = VHubCustom.cfg
local E   = VHubCustom.E

local HOOD_DOOR = 4   -- índice GTA da porta do capô (Config.doorIndex.hood no vehcontrol)


-- ============================================================
-- ESTADO (capô aberto por ESTA interação — p/ fechar no fim)
-- ============================================================

local _openedHood = 0   -- handle do veículo cujo capô abrimos (0 = nenhum)


-- ============================================================
-- HELPERS
-- ============================================================

-- zona de oficina cujo CENTRO está dentro do raio de detecção do player (ou nil).
-- É conveniência CLIENT: o server revalida a distância real à zona em validateVehicle.
local function nearOficinaZone()
  local pPos = GetEntityCoords(PlayerPedId())
  for _, z in ipairs(CFG.zones) do
    if z.domain == 'oficina' then
      local zv = z._vec or vec3(z.x, z.y, z.z)
      if #(pPos - zv) < (z.raio_check or 40.0) then return z end
    end
  end
  return nil
end

-- pode interagir com o capô deste veículo? (tudo conveniência client — verdade é server-side)
local function canInteractHood(entity)
  if VHubCustom.inMenu or VHubCustom.opening then return false end
  local ped = PlayerPedId()
  if IsPedInAnyVehicle(ped, false) then return false end        -- a pé
  if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
  if GetVehicleClass(entity) == 8 then return false end          -- moto não tem capô útil aqui
  if GetEntitySpeed(entity) > 1.5 then return false end          -- carro parado
  return nearOficinaZone() ~= nil
end

-- abre o capô como affordance visual (efêmero, revertível; NÃO é verdade crítica — gate seguranca)
local function openHood(entity)
  if not entity or entity == 0 or not DoesEntityExist(entity) then return end
  SetVehicleDoorOpen(entity, HOOD_DOOR, false, false)
  _openedHood = entity
end

-- fecha o capô que ESTA interação abriu (idempotente; no-op se nada aberto/entidade sumiu)
local function closeHood()
  local e = _openedHood
  _openedHood = 0
  if e ~= 0 and DoesEntityExist(e) then
    SetVehicleDoorShut(e, HOOD_DOOR, false)
  end
end
VHubCustom.closeEngineHood = closeHood   -- oficina.lua fecha ao sair do menu


-- ============================================================
-- AÇÕES (onSelect — client dispara intenção; server dispõe)
-- ============================================================

-- abre a OFICINA reusando o gate físico existente (SERVICE_AUTH). Abre o capô junto (imersão).
local function actOpenOficina(entity)
  local zone = nearOficinaZone()
  if not zone then return VHubCustom.notify('Aproxime-se da oficina.', 'warning') end
  openHood(entity)
  VHubCustom.requestService(zone, entity)   -- server revalida tudo; abre o menu no OK
end

-- INSPECIONA o motor: pede o resumo read-only gated (ENGINE_BAY_INSPECT). Abre o capô p/ imersão.
local function actInspect(entity)
  local zone = nearOficinaZone()
  if not zone or not DoesEntityExist(entity) or not NetworkGetEntityIsNetworked(entity) then
    return VHubCustom.notify('Aproxime-se da oficina.', 'warning')
  end
  local netId = NetworkGetNetworkIdFromEntity(entity)
  local plate = (GetVehicleNumberPlateText(entity) or ''):upper():gsub('%s+', ' '):match('^%s*(.-)%s*$')
  if not netId or netId == 0 or not plate or plate == '' then return end
  openHood(entity)
  TriggerServerEvent(E.ENGINE_BAY_INSPECT, zone.id, plate, netId)
end


-- ============================================================
-- RESPOSTA DA INSPEÇÃO (read-only — feed nativo; NUI rica vem na F2.3)
-- ============================================================

RegisterNetEvent(E.ENGINE_BAY_INSPECT_OK)
AddEventHandler(E.ENGINE_BAY_INSPECT_OK, function(ok, summary)
  if not ok or type(summary) ~= 'table' then
    return VHubCustom.notify('Não foi possível inspecionar este motor.', 'error')
  end
  local n = type(summary.parts) == 'table' and #summary.parts or 0
  local pct = math.floor((tonumber(summary.power_boost) or 0.0) * 100 + 0.5)
  VHubCustom.notify(('%s — %d peça(s) de engenharia | +%d%% potência')
    :format(summary.name or 'Veículo', n, pct), 'info')
end)


-- ============================================================
-- REGISTRO NO vhub_target (soft-dep — pcall; sem ele, fluxo antigo segue)
-- ============================================================

CreateThread(function()
  local ok = pcall(function()
    exports.vhub_target:addGlobalVehicle({
      {
        name        = 'vhub_custom:hood_oficina',
        label       = 'Abrir Oficina',
        icon        = 'screwdriver-wrench',
        distance    = 2.0,
        canInteract = canInteractHood,
        onSelect    = function(data) actOpenOficina(data and data.entity or data) end,
      },
      {
        name        = 'vhub_custom:hood_inspect',
        label       = 'Inspecionar Motor',
        icon        = 'car',
        distance    = 2.0,
        canInteract = canInteractHood,
        onSelect    = function(data) actInspect(data and data.entity or data) end,
      },
    })
  end)
  if not ok then
    VHubCustom.log('[F2.2] vhub_target indisponível — interação de capô inativa (fluxo por proximidade segue)')
  end
end)


-- ============================================================
-- CLEANUP
-- ============================================================

AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  closeHood()
end)
