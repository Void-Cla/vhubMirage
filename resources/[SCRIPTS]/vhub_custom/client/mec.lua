-- client/mec.lua — L2 HAL: animação de reparo e interface da mecânica
-- Animação: veh@repair / fixing_a_player (vanilla confirmado, com timeout de carregamento)
-- Reboque: o cliente declara intenção; movimento e posição pertencem ao servidor.
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
    if not DoesEntityExist(ent) then return false end
    NetworkRequestControlOfEntity(ent)
    Citizen.Wait(50)
  end
  return true
end

local JANELAS = { 'window_lf', 'window_rf', 'window_lr', 'window_rr',
  'window_lm', 'window_rm', 'windscreen', 'windscreen_r' }

local function danoAtual(veh)
  local dano = { doors = {}, windows = {}, tyres = {}, tyres_rim = {} }
  for i = 0, 5 do if IsVehicleDoorDamaged(veh, i) then dano.doors[#dano.doors + 1] = i end end
  for i = 0, 7 do
    if GetEntityBoneIndexByName(veh, JANELAS[i + 1]) ~= -1 and not IsVehicleWindowIntact(veh, i) then
      dano.windows[#dano.windows + 1] = i
    end
  end
  for _, i in ipairs(VHubCustom.U.pneus) do
    if IsVehicleTyreBurst(veh, i, true) then dano.tyres_rim[#dano.tyres_rim + 1] = i
    elseif IsVehicleTyreBurst(veh, i, false) then dano.tyres[#dano.tyres + 1] = i end
  end
  return dano
end

RegisterNetEvent(E.MEC_PHYSICAL)
AddEventHandler(E.MEC_PHYSICAL, function(token, netId, plate, componente)
  if source ~= 65535 or type(token) ~= 'string' then return end
  local veh = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
  local lock = token:match('^(.-):')
  local function valido()
    return veh and veh ~= 0 and DoesEntityExist(veh)
      and VHubCustom.U.normalizePlate(GetVehicleNumberPlateText(veh)) == plate
      and Entity(veh).state[VHubCustom.BAG.REPAIR] == lock
  end
  Citizen.CreateThread(function()
    local prazo = GetGameTimer() + 1000
    while not valido() and GetGameTimer() < prazo do
      Citizen.Wait(50)
      veh = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    end
    if not valido() or not awaitControl(veh, 2500) or not valido() then
      TriggerServerEvent(E.MEC_PHYSICAL_OK, token, false); return
    end
    if componente == 'inspect' then
      TriggerServerEvent(E.MEC_PHYSICAL_OK, token, true, { damage = danoAtual(veh) }); return
    end
    -- Sem Wait entre validação e mutação. Um reparo não concede outros componentes.
    if componente == 'tyre' then
      for _, i in ipairs(VHubCustom.U.pneus) do SetVehicleTyreFixed(veh, i) end
    elseif componente == 'engine' then
      SetVehicleEngineHealth(veh, 1000.0)
      SetVehicleUndriveable(veh, false)
    elseif componente == 'body' then
      local motor, tanque, combustivel = GetVehicleEngineHealth(veh), GetVehiclePetrolTankHealth(veh), GetVehicleFuelLevel(veh)
      local ligado, dirigivel = GetIsVehicleEngineRunning(veh), IsVehicleDriveable(veh, false)
      local sujeira, dano = GetVehicleDirtLevel(veh), danoAtual(veh)
      -- SET_VEHICLE_FIXED exige motor funcional; restaura-o imediatamente, sem upgrade gratuito.
      SetVehicleEngineHealth(veh, 1000.0)
      SetVehicleFixed(veh)
      SetVehicleDeformationFixed(veh)
      SetVehicleBodyHealth(veh, 1000.0)
      SetVehicleEngineHealth(veh, motor + 0.0)
      SetVehiclePetrolTankHealth(veh, tanque + 0.0)
      SetVehicleFuelLevel(veh, combustivel + 0.0)
      SetVehicleDirtLevel(veh, sujeira + 0.0)
      SetVehicleUndriveable(veh, not dirigivel)
      SetVehicleEngineOn(veh, ligado, true, true)
      for _, i in ipairs(dano.tyres) do SetVehicleTyreBurst(veh, i, false, 1000.0) end
      for _, i in ipairs(dano.tyres_rim) do SetVehicleTyreBurst(veh, i, true, 1000.0) end
    else TriggerServerEvent(E.MEC_PHYSICAL_OK, token, false); return end
    local dano = danoAtual(veh)
    local sucesso = componente == 'tyre' and VHubCustom.U.contarPneus(dano) == 0
      or componente == 'engine' and GetVehicleEngineHealth(veh) >= 999.0
      or componente == 'body' and GetVehicleBodyHealth(veh) >= 999.0 and #dano.doors == 0 and #dano.windows == 0
    TriggerServerEvent(E.MEC_PHYSICAL_OK, token, sucesso)
  end)
end)


-- ============================================================
-- ABRIR MENU MEC
-- ============================================================

-- abre seleção de reparo para o veículo ativo na zona
function VHubCustom.openMec(auth)
  local veh = VHubCustom.activeVeh
  if not DoesEntityExist(veh) or veh == 0 then return end
  if VHubCustom.inMenu then return end
  if type(auth) ~= 'table' or not VHubCustom.service or VHubCustom.service.domain ~= 'mec' then return end

  local model    = GetEntityModel(veh)
  local prices   = CFG.prices
  local atual = { engine_health = GetVehicleEngineHealth(veh), body_health = GetVehicleBodyHealth(veh), damage = danoAtual(veh) }
  local estimativas = {}
  for _, componente in ipairs({ 'tyre', 'engine', 'body' }) do
    local _, preco = VHubCustom.U.reparo(atual, componente, prices)
    estimativas[componente] = preco
  end

  VHubCustom.inMenu = true

  SendNUIMessage({
    action = 'openMec',
    data   = {
      plate         = auth.plate,
      nome          = auth.name or GetDisplayNameFromVehicleModel(model) or '—',
      -- preços de exibição (verdade autoritativa continua server-side)
      prices        = {
        tyre   = prices.pneu,
        engine = prices.motor_parcial,
        body   = prices.lataria_parcial,
      },
      estimates = estimativas,
      materiais = auth.materiais,
      damaged_tyres = VHubCustom.U.contarPneus(atual.damage),
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
  VHubCustom.endService('mec')
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
  if type(data) ~= 'table' then cb({ ok = false }); return end
  local plate       = type(data.plate)       == 'string' and data.plate       or ''
  local repair_type = type(data.repair_type) == 'string' and data.repair_type or ''

  if plate == '' or repair_type == '' then cb({ ok = false }); return end

  local service = VHubCustom.service
  if not service or service.domain ~= 'mec' then cb({ ok = false }); return end
  TriggerServerEvent(E.MEC_REPAIR, service.lease_id, VHubCustom.nextRequestId(), repair_type)
  cb({ ok = true })
end)

-- NUI → solicita reboque do veículo ativo (servidor resolve netId→entidade→placa)
RegisterNUICallback('mec:tow', function(_, cb)
  local veh = VHubCustom.activeVeh
  if not DoesEntityExist(veh) or veh == 0 then cb({ ok = false }); return end

  local service = VHubCustom.service
  if not service or service.domain ~= 'mec' then cb({ ok = false }); return end
  TriggerServerEvent(E.MEC_TOW_REQ, service.lease_id, VHubCustom.nextRequestId())
  cb({ ok = true })
end)


-- ============================================================
-- REPARO: RESPOSTA DO SERVIDOR
-- ============================================================

-- replay-guard: impede dupla animação se o servidor disparar MEC_CONFIRM 2x
local _repairActive = false

RegisterNetEvent(E.MEC_CONFIRM)
AddEventHandler(E.MEC_CONFIRM, function(plate, ok, repair_type, netId, leaseId)
  local servico = VHubCustom.service
  if not servico or servico.domain ~= 'mec' or leaseId ~= servico.lease_id
      or (plate and plate ~= servico.plate) or (netId and tonumber(netId) ~= tonumber(servico.net_id)) then return end
  -- captura veh ANTES de qualquer Wait (evita race condition com activeVeh)
  local veh = VHubCustom.activeVeh

  -- fecha menu imediatamente (sem esperar a animação)
  VHubCustom.closeMec()
  SendNUIMessage({ action = 'fecharMec' })

  if not ok or repair_type == nil then return end
  if repair_type == 'tow' then return end
  if not veh or not DoesEntityExist(veh) or NetworkGetNetworkIdFromEntity(veh) ~= tonumber(netId) then return end
  if _repairActive then return end

  _repairActive = true
  Citizen.CreateThread(function()
    playRepairAnim()
    Citizen.Wait(3000)
    stopRepairAnim()

    -- revalida entidade após animação
    if not DoesEntityExist(veh) then _repairActive = false; return end

    -- A física já foi aplicada e confirmada pelo owner; animação é somente apresentação.
    _repairActive = false
  end)
end)
