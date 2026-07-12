-- client/mec.lua — L2 HAL: animação de reparo, execução de reboque (reposicionamento)
-- Animação: veh@repair / fixing_a_player (vanilla confirmado, com timeout de carregamento)
-- Reboque: solicita ao servidor, recebe autorização, controla entidade e confirma posição final.
---@diagnostic disable: undefined-global

local E   = VHubCustom.E
local CFG = VHubCustom.cfg


-- ============================================================
-- ANIMAÇÃO DE REPARO (vanilla confirmado)
-- ============================================================

local ANIM_DICT = 'veh@repair'
local ANIM_NAME = 'fixing_a_player'

-- carrega o dict de animação com timeout (L-06: sem loop infinito)
local function loadAnimDict(dict)
  RequestAnimDict(dict)
  local t = GetGameTimer()
  while not HasAnimDictLoaded(dict) do
    if GetGameTimer() - t > 3000 then return false end
    Citizen.Wait(100)
  end
  return true
end

-- executa animação de mecânico no ped local
local function playRepairAnim()
  if not loadAnimDict(ANIM_DICT) then return end
  TaskPlayAnim(PlayerPedId(), ANIM_DICT, ANIM_NAME, 8.0, -8.0, -1, 49, 0, false, false, false)
  RemoveAnimDict(ANIM_DICT)
end

-- para a animação de mecânico no ped local
local function stopRepairAnim()
  ClearPedTasks(PlayerPedId())
end

-- aguarda controle de rede da entidade com timeout (ms); retorna true se obteve
local function awaitControl(ent, timeout)
  if NetworkHasControlOfEntity(ent) then return true end
  NetworkRequestControlOfEntity(ent)
  local t = GetGameTimer()
  while not NetworkHasControlOfEntity(ent) do
    if GetGameTimer() - t > timeout then return false end
    Citizen.Wait(50)
  end
  return true
end


-- ============================================================
-- ABRIR MENU MEC
-- ============================================================

-- abre seleção de reparo para o veículo ativo na zona
function VHubCustom.openMec()
  local veh = VHubCustom.activeVeh
  if not DoesEntityExist(veh) or veh == 0 then return end
  if VHubCustom.inMenu then return end

  local model    = GetEntityModel(veh)
  local dispName = string.lower(GetDisplayNameFromVehicleModel(model) or '')
  local catEntry = (VHubCustom.catalog or {})[dispName] or {}
  local prices   = CFG.prices

  VHubCustom.inMenu = true

  SendNUIMessage({
    action = 'openMec',
    data   = {
      plate         = GetVehicleNumberPlateText(veh):upper():gsub('%s+', ' '):match('^%s*(.-)%s*$'),
      nome          = catEntry.nome or GetDisplayNameFromVehicleModel(model) or '—',
      -- preços de exibição (verdade autoritativa continua server-side)
      prices        = {
        tyre   = prices.pneu,
        engine = prices.motor_parcial,
        body   = prices.lataria_parcial,
      },
      -- health atual para exibição de estado (servidor valida de novo)
      engine_health = math.floor(GetVehicleEngineHealth(veh)),
      body_health   = math.floor(GetVehicleBodyHealth(veh)),
    },
  })

  SetNuiFocus(true, true)
end

-- fecha o menu de mecânica e libera foco da NUI
function VHubCustom.closeMec()
  VHubCustom.inMenu = false
  SetNuiFocus(false, false)
end


-- ============================================================
-- NUI CALLBACKS
-- ============================================================

-- NUI → fecha sem ação (botão Cancelar/✕)
RegisterNUICallback('mec:fechar', function(_, cb)
  VHubCustom.closeMec()
  cb('ok')
end)

-- NUI → solicita reparo parcial do componente selecionado
RegisterNUICallback('mec:repair', function(data, cb)
  local plate       = type(data.plate)       == 'string' and data.plate       or ''
  local repair_type = type(data.repair_type) == 'string' and data.repair_type or ''

  if plate == '' or repair_type == '' then cb({ ok = false }); return end

  TriggerServerEvent(E.MEC_REPAIR, plate, repair_type)
  cb({ ok = true })
end)

-- NUI → solicita reboque do veículo ativo (servidor resolve netId→entidade→placa)
RegisterNUICallback('mec:tow', function(_, cb)
  local veh = VHubCustom.activeVeh
  if not DoesEntityExist(veh) or veh == 0 then cb({ ok = false }); return end

  local plate = GetVehicleNumberPlateText(veh):upper():gsub('%s+', ' '):match('^%s*(.-)%s*$')
  local netId = NetworkGetNetworkIdFromEntity(veh)
  TriggerServerEvent(E.MEC_TOW_REQ, plate, netId)
  cb({ ok = true })
end)


-- ============================================================
-- REPARO: RESPOSTA DO SERVIDOR
-- ============================================================

-- replay-guard: impede dupla animação se o servidor disparar MEC_CONFIRM 2x
local _repairActive = false

RegisterNetEvent(E.MEC_CONFIRM)
AddEventHandler(E.MEC_CONFIRM, function(_, ok, repair_type)
  -- captura veh ANTES de qualquer Wait (evita race condition com activeVeh)
  local veh = VHubCustom.activeVeh

  -- fecha menu imediatamente (sem esperar a animação)
  VHubCustom.closeMec()
  SendNUIMessage({ action = 'fecharMec' })

  if not ok then return end
  if not veh or not DoesEntityExist(veh) then return end
  if _repairActive then return end

  _repairActive = true
  Citizen.CreateThread(function()
    playRepairAnim()
    Citizen.Wait(3000)
    stopRepairAnim()

    -- revalida entidade após animação
    if not DoesEntityExist(veh) then _repairActive = false; return end

    if repair_type == 'tyre' then
      -- SetVehicleTyreFixed propaga sem controle exclusivo (CVehicleTyreStateSync)
      for i = 0, 5 do SetVehicleTyreFixed(veh, i) end

    elseif repair_type == 'engine' then
      -- engine health usa CVehicleDamageSync: exige ser network owner para o sync persistir
      if awaitControl(veh, 3000) then
        SetVehicleEngineHealth(veh, 1000.0)
      end

    elseif repair_type == 'body' then
      -- body health: mesmo contrato de owner que engine
      if awaitControl(veh, 3000) then
        SetVehicleBodyHealth(veh, 1000.0)
      end
    end

    _repairActive = false
  end)
end)


-- ============================================================
-- REBOQUE: EXECUÇÃO CLIENT-SIDE
-- ============================================================

RegisterNetEvent(E.MEC_TOW_DO)
AddEventHandler(E.MEC_TOW_DO, function(plate, net_id)
  Citizen.CreateThread(function()
    local nid = tonumber(net_id)
    if not nid then return end

    local ent = NetworkGetEntityFromNetId(nid)
    if not ent or ent == 0 then
      TriggerServerEvent('vhub_custom:server:mecTowDone', plate, net_id, nil)
      return
    end

    -- pede controle da entidade com timeout (L-06: sem loop infinito)
    if not awaitControl(ent, 5000) then
      TriggerServerEvent('vhub_custom:server:mecTowDone', plate, net_id, nil)
      return
    end

    -- reposiciona próximo do jogador (estrada mais próxima)
    local pPos   = GetEntityCoords(PlayerPedId())
    local groundZ = 0.0
    local _, gz  = GetGroundZFor_3dCoord(pPos.x + 5.0, pPos.y, pPos.z, groundZ, false)
    local newZ   = gz > 0 and gz or pPos.z

    SetEntityCoords(ent, pPos.x + 5.0, pPos.y, newZ + 0.5, false, false, false, false)
    SetEntityHeading(ent, GetEntityHeading(PlayerPedId()))

    Citizen.Wait(200)  -- estabiliza física

    -- confirma posição ao servidor para persistência
    local finalPos = GetEntityCoords(ent)
    local finalH   = GetEntityHeading(ent)
    TriggerServerEvent('vhub_custom:server:mecTowDone', plate, net_id, {
      x = finalPos.x, y = finalPos.y, z = finalPos.z, h = finalH,
    })
  end)
end)
