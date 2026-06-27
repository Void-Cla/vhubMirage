-- client/mec.lua — L2 HAL: animação de reparo, execução de reboque (reposicionamento)
-- Animação: veh@repair / fixing_a_player (vanilla confirmado, com timeout de carregamento)
-- Reboque: solicita ao servidor, recebe autorização, controla entidade e confirma posição final.
---@diagnostic disable: undefined-global

local E = VHubCustom.E


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

local function stopRepairAnim()
  ClearPedTasks(PlayerPedId())
end


-- ============================================================
-- ABRIR MENU MEC
-- ============================================================

-- abre seleção de reparo para o veículo ativo na zona
function VHubCustom.openMec()
  local veh = VHubCustom.activeVeh
  if not DoesEntityExist(veh) or veh == 0 then return end
  if VHubCustom.inMenu then return end

  local plate = GetVehicleNumberPlateText(veh):upper():gsub('%s+', ' '):match('^%s*(.-)%s*$')
  local model = GetEntityModel(veh)
  local dispName = string.lower(GetDisplayNameFromVehicleModel(model) or '')
  local catEntry = (VHubCustom.catalog or {})[dispName] or {}

  VHubCustom.inMenu = true

  SendNUIMessage({
    action = 'openMec',
    data   = {
      plate = plate,
      nome  = catEntry.nome or GetDisplayNameFromVehicleModel(model) or plate,
    },
  })

  SetNuiFocus(true, true)
end

function VHubCustom.closeMec()
  VHubCustom.inMenu = false
  SetNuiFocus(false, false)
end


-- ============================================================
-- NUI CALLBACKS
-- ============================================================

-- NUI → fecha sem ação (botão Cancelar/✕ ou timeout de 20s)
RegisterNUICallback('mec:fechar', function(_, cb)
  VHubCustom.closeMec()
  cb('ok')
end)

-- NUI → solicita reparo parcial do componente selecionado
RegisterNUICallback('mec:repair', function(data, cb)
  local plate       = type(data.plate)       == 'string' and data.plate       or ''
  local repair_type = type(data.repair_type) == 'string' and data.repair_type or ''

  if plate == '' or repair_type == '' then
    cb({ ok = false })
    return
  end

  TriggerServerEvent(E.MEC_REPAIR, plate, repair_type)
  cb({ ok = true })
end)

-- NUI → solicita reboque do veículo ativo (servidor resolve netId→entidade→placa)
RegisterNUICallback('mec:tow', function(_, cb)
  local veh = VHubCustom.activeVeh
  if not DoesEntityExist(veh) or veh == 0 then
    cb({ ok = false })
    return
  end

  local plate = GetVehicleNumberPlateText(veh):upper():gsub('%s+', ' '):match('^%s*(.-)%s*$')
  local netId = NetworkGetNetworkIdFromEntity(veh)
  TriggerServerEvent(E.MEC_TOW_REQ, plate, netId)
  cb({ ok = true })
end)


-- ============================================================
-- REPARO: RESPOSTA DO SERVIDOR
-- ============================================================

RegisterNetEvent(E.MEC_CONFIRM)
AddEventHandler(E.MEC_CONFIRM, function(plate, ok, repair_type)
  if ok then
    Citizen.CreateThread(function()
      playRepairAnim()
      Citizen.Wait(3000)
      stopRepairAnim()
      -- aplica visualmente no veículo vivo
      local veh = VHubCustom.activeVeh
      if not veh or not DoesEntityExist(veh) then return end
      if repair_type == 'tyre' then
        for i = 0, 5 do SetVehicleTyreFixed(veh, i) end
      elseif repair_type == 'engine' then
        SetVehicleEngineHealth(veh, 1000.0)
      elseif repair_type == 'body' then
        SetVehicleBodyHealth(veh, 1000.0)
      end
    end)
  end
  VHubCustom.closeMec()
  SendNUIMessage({ action = 'fecharMec' })
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
    NetworkRequestControlOfEntity(ent)
    local t = GetGameTimer()
    while not NetworkHasControlOfEntity(ent) do
      if GetGameTimer() - t > 5000 then
        TriggerServerEvent('vhub_custom:server:mecTowDone', plate, net_id, nil)
        return
      end
      Citizen.Wait(100)
    end

    -- reposiciona próximo do jogador (estrada mais próxima)
    local pPos = GetEntityCoords(PlayerPedId())
    local groundZ = 0.0
    local _, gz = GetGroundZFor_3dCoord(pPos.x + 5.0, pPos.y, pPos.z, groundZ, false)
    local newZ = gz > 0 and gz or pPos.z

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
