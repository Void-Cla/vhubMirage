---@diagnostic disable: undefined-global, lowercase-global

-- client.lua — nitro (vHub HAL, decisão #30).
--
-- Lê o estado do nitro DA PLACA (servidor é a autoridade), aplica o boost SÓ no carro
-- que o player DIRIGE (seat -1) ao segurar SHIFT DIREITO, drena local e PERSISTE o qty
-- ao soltar/sair (nunca por tick). O NÍVEL (1..10) escala potência×consumo (NitroCfg.LEVELS).
-- Recarga e liga/desliga são feitos na FICHA do veículo (vhub_vehcontrol) — sem proximidade.
-- Mantido: fogo no escapamento. Removidos: efeito "maconha", rastro de lanterna, uso por item.

local f = function(n) return n + 0.00001 end

local _plate    = nil      -- placa do carro dirigido (nil = não sou motorista)
local _kit      = false    -- kit instalado? (do servidor)
local _enabled  = false    -- nitro ligado na ficha? (do servidor)
local _level    = 1        -- nível 1..10 (do servidor)
local _qty      = 0        -- carga 0..100 (piso autoritativo do servidor; float durante o uso)
local _holding  = false    -- segurando o shift direito
local _boosting = false    -- thread de boost ativa
local _running  = true


-- ============================================================
-- HELPERS
-- ============================================================

local function notify(msg)
  if not msg or msg == '' then return end
  BeginTextCommandThefeedPost('STRING')
  AddTextComponentSubstringPlayerName(msg)
  EndTextCommandThefeedPostTicker(false, true)
end

-- placa normalizada (espelha o servidor)
local function plateOf(v)
  if not v or v == 0 then return nil end
  local p = GetVehicleNumberPlateText(v); if not p then return nil end
  p = p:upper():gsub('%s+', ' '):match('^%s*(.-)%s*$')
  return (p and #p >= 1) and p or nil
end

-- modelo na blacklist?
local function blacklisted(veh)
  local m = GetEntityModel(veh)
  for name in pairs(NitroCfg.blacklist or {}) do
    if GetHashKey(name) == m then return true end
  end
  return false
end

-- parâmetros físicos do nível atual (powerMult, consumeMult) — fonte: NitroCfg.LEVELS
local function levelParams()
  local lv = math.max(1, math.min(10, math.floor(tonumber(_level) or 1)))
  return (NitroCfg.LEVELS and NitroCfg.LEVELS[lv]) or { powerMult = 1.0, consumeMult = 1.0 }
end

-- fogo no escapamento (mantido) — ptfx backfire nos bones de escape do carro
local _ptfxReady = false
local function ensurePtfx()
  if _ptfxReady then return true end
  RequestNamedPtfxAsset('core')
  local t = 0
  while not HasNamedPtfxAssetLoaded('core') and t < 50 do Wait(0); t = t + 1 end
  _ptfxReady = HasNamedPtfxAssetLoaded('core')
  return _ptfxReady
end

local function exhaustFire(veh)
  if not NitroCfg.exhaustFire or not ensurePtfx() then return end
  for _, bone in ipairs({ 'exhaust', 'exhaust_2', 'exhaust_3', 'exhaust_4' }) do
    local idx = GetEntityBoneIndexByName(veh, bone)
    if idx ~= -1 then
      UseParticleFxAssetNextCall('core')
      StartNetworkedParticleFxNonLoopedOnEntityBone(
        'veh_backfire', veh, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, idx,
        f(NitroCfg.fireSize or 2.0), false, false, false)
    end
  end
end

-- aplica/limpa o boost no veículo (precisa reaplicar por frame enquanto ativo).
-- O ganho é o boost BASE × powerMult do nível (nível 10 = dobro).
local function setBoost(veh, on, powerMult)
  if on then
    SetVehicleCheatPowerIncrease(veh, f((NitroCfg.torqueBoost or 5.0) * (powerMult or 1.0)))
    ModifyVehicleTopSpeed(veh, f((NitroCfg.topSpeedBoost or 10.0) * (powerMult or 1.0)))
  else
    SetVehicleCheatPowerIncrease(veh, 0.0)
    ModifyVehicleTopSpeed(veh, 0.0)
  end
end


-- ============================================================
-- BOOST (segurar shift direito) — drena local, persiste ao soltar
-- ============================================================

local function startBoost()
  -- gate: kit + ligado na ficha + tem carga
  if _boosting or not (_kit and _enabled and _qty > 0) then return end
  local ped = PlayerPedId()
  local veh = GetVehiclePedIsIn(ped, false)
  if veh == 0 or GetPedInVehicleSeat(veh, -1) ~= ped or blacklisted(veh) then return end

  _boosting = true
  local boosted      = veh      -- entidade que RECEBE e LIMPA o boost (sempre a mesma)
  local boostedPlate = _plate   -- placa da entidade boostada (drena na MESMA — netId+placa coerentes)
  local lp           = levelParams()
  CreateThread(function()
    -- taxa = base (100/durationSec) × consumeMult do nível: nível alto gasta MUITO mais
    local ratePerSec = (100.0 / (NitroCfg.durationSec or 10)) * (lp.consumeMult or 1.0)
    local last, fireTick = GetGameTimer(), 0

    while _running and _holding and _qty > 0 do
      local p = PlayerPedId()
      local v = GetVehiclePedIsIn(p, false)
      -- sai se trocou de carro / saiu / não é mais o motorista da entidade boostada
      if v == 0 or v ~= boosted or GetPedInVehicleSeat(v, -1) ~= p then break end

      setBoost(boosted, true, lp.powerMult)

      local now = GetGameTimer()
      _qty = math.max(0, _qty - ratePerSec * (now - last) / 1000.0)
      last = now

      fireTick = fireTick + 1
      if fireTick % 5 == 0 then exhaustFire(boosted) end
      Wait(50)
    end

    -- LIMPA SEMPRE a entidade boostada (não a atual) — sem leak de cheat power no carro antigo
    if boosted ~= 0 and DoesEntityExist(boosted) then setBoost(boosted, false) end
    _boosting = false

    -- persiste o gasto na MESMA entidade/placa boostada (no fim do uso; monotônico no servidor)
    if boostedPlate and boosted ~= 0 and DoesEntityExist(boosted) then
      TriggerServerEvent('vhub_nitro:drain', VehToNet(boosted), boostedPlate, math.floor(_qty))
    end
  end)
end

RegisterCommand('+nitro', function() _holding = true; startBoost() end, false)
RegisterCommand('-nitro', function() _holding = false end, false)
RegisterKeyMapping('+nitro', 'Veículo: ativar nitro', 'keyboard', 'RSHIFT')


-- ============================================================
-- ESTADO (do servidor) — verdade da placa
-- ============================================================

RegisterNetEvent('vhub_nitro:state')
AddEventHandler('vhub_nitro:state', function(plate, n)
  if plate ~= _plate or type(n) ~= 'table' then return end
  _kit     = n.kit == true
  _enabled = n.enabled == true
  _level   = math.max(1, math.min(10, math.floor(tonumber(n.level) or 1)))
  _qty     = math.max(0, math.min(100, tonumber(n.qty) or 0))
end)

-- aviso do servidor (ex.: usou a garrafa pela mochila → recarga é pela ficha)
RegisterNetEvent('vhub_nitro:notify')
AddEventHandler('vhub_nitro:notify', function(msg) notify(msg) end)


-- ============================================================
-- DETECÇÃO DE MOTORISTA (1 Hz) — pede o estado da placa ao entrar
-- ============================================================

CreateThread(function()
  while _running do
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
      local v = GetVehiclePedIsIn(ped, false)
      if GetPedInVehicleSeat(v, -1) == ped then
        local pl = plateOf(v)
        if pl and pl ~= _plate then
          _plate, _kit, _enabled, _level, _qty = pl, false, false, 1, 0
          TriggerServerEvent('vhub_nitro:request', pl)
        end
      elseif _plate then
        _plate, _kit, _enabled, _level, _qty = nil, false, false, 1, 0   -- virei passageiro
      end
    elseif _plate then
      _plate, _kit, _enabled, _level, _qty = nil, false, false, 1, 0     -- saí do veículo
    end
    Wait(1000)
  end
end)


-- ============================================================
-- CLEANUP
-- ============================================================

AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  _running, _holding = false, false
  local v = GetVehiclePedIsIn(PlayerPedId(), false)
  if v ~= 0 then setBoost(v, false) end
end)
