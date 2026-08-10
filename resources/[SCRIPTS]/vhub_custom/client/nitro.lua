---@diagnostic disable: undefined-global, lowercase-global

-- client/nitro.lua — nitro HAL (FASE 2 ADR #81).
--
-- Absorveu vhub_nitro/client.lua. Lê o estado da PLACA (servidor autoridade), aplica boost
-- SÓ no carro dirigido (seat -1) ao segurar RSHIFT, drena local e persiste qty ao soltar/sair.
-- Recarga e liga/desliga são feitos na FICHA do vehcontrol. Fogo no escapamento mantido.

local NCfg = VHubCustom.NitroCfg
local f = function(n) return n + 0.00001 end

local _plate    = nil
local _kit      = false
local _enabled  = false
local _level    = 1
local _qty      = 0
local _holding  = false
local _boosting = false
local _running  = true
local _fireColor = nil


-- ============================================================
-- HELPERS
-- ============================================================

local function notify(msg)
  if not msg or msg == '' then return end
  BeginTextCommandThefeedPost('STRING')
  AddTextComponentSubstringPlayerName(msg)
  EndTextCommandThefeedPostTicker(false, true)
end

local function plateOf(v)
  if not v or v == 0 then return nil end
  local p = GetVehicleNumberPlateText(v); if not p then return nil end
  p = p:upper():gsub('%s+', ' '):match('^%s*(.-)%s*$')
  return (p and #p >= 1) and p or nil
end

local function blacklisted(veh)
  local m = GetEntityModel(veh)
  for name in pairs(NCfg.blacklist or {}) do
    if GetHashKey(name) == m then return true end
  end
  return false
end

local function levelParams()
  local lv = math.max(1, math.min(10, math.floor(tonumber(_level) or 1)))
  return (NCfg.LEVELS and NCfg.LEVELS[lv]) or { powerMult = 1.0, consumeMult = 1.0 }
end

local _hudLast = nil
local function hudSync()
  local qty = _kit and math.floor(_qty + 0.5) or 0
  local sig = qty * 4 + (_kit and 2 or 0) + (_enabled and 1 or 0)
  if sig == _hudLast then return end
  _hudLast = sig
  TriggerEvent('vhub_nitro:hud', { kit = _kit, enabled = _enabled, qty = qty })
end

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
  if not NCfg.exhaustFire or not ensurePtfx() then return end
  local c = _fireColor
  for _, bone in ipairs({ 'exhaust', 'exhaust_1', 'exhaust_2', 'exhaust_3', 'exhaust_4' }) do
    local idx = GetEntityBoneIndexByName(veh, bone)
    if idx ~= -1 then
      UseParticleFxAssetNextCall('core')
      if c then SetParticleFxNonLoopedColour(c.r / 255.0, c.g / 255.0, c.b / 255.0) end
      StartNetworkedParticleFxNonLoopedOnEntityBone(
        'veh_backfire', veh, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, idx,
        f(NCfg.fireSize or 2.0), false, false, false)
    end
  end
end

-- ADR #82 FASE 2: o nitro é overlay EFÊMERO sobre a BASE per-entidade da engenharia (Camada A).
-- Liga = seta o VALOR ABSOLUTO `base + boost` (a native é "set", não acumula → re-setar por tick
-- é idempotente). A base é lida UMA vez no início do boost (startBoost) e passada aqui — nunca
-- relida no loop (senão empilharia). Desliga = restaura a BASE via evento
-- 'vhub_vehcontrol:reapplyBase' (STRING literal — VHubVeh.E não cruza resource), NUNCA hardcode
-- 0.0. Com Config.applyPerEntity=false no vehcontrol, a base é 0.0 → comportamento idêntico ao
-- legado (zero regressão). Escritor único da BASE = vehcontrol (L-04).
local function setBoost(veh, on, powerMult, base)
  if on then
    SetVehicleCheatPowerIncrease(veh, f((base or 0.0) + (NCfg.torqueBoost or 5.0) * (powerMult or 1.0)))
    ModifyVehicleTopSpeed(veh, f((NCfg.topSpeedBoost or 10.0) * (powerMult or 1.0)))
  else
    TriggerEvent('vhub_vehcontrol:reapplyBase', veh)   -- restaura a base (0.0 se Camada A off)
  end
end


-- ============================================================
-- BOOST (segurar RSHIFT) — drena local, persiste ao soltar
-- ============================================================

local function startBoost()
  if _boosting or not (_kit and _enabled and _qty > 0) then return end
  local ped = PlayerPedId()
  local veh = GetVehiclePedIsIn(ped, false)
  if veh == 0 or GetPedInVehicleSeat(veh, -1) ~= ped or blacklisted(veh) then return end

  _boosting = true
  local boosted      = veh
  local boostedPlate = _plate
  local lp           = levelParams()
  -- base per-entidade da engenharia lida UMA vez (Camada A). O boost SOMA sobre ela sem empilhar.
  local baseCheat    = GetVehicleCheatPowerIncrease(boosted) or 0.0
  CreateThread(function()
    local ratePerSec = (100.0 / (NCfg.durationSec or 10)) * (lp.consumeMult or 1.0)
    local last, fireTick = GetGameTimer(), 0

    while _running and _holding and _qty > 0 do
      local p = PlayerPedId()
      local v = GetVehiclePedIsIn(p, false)
      if v == 0 or v ~= boosted or GetPedInVehicleSeat(v, -1) ~= p then break end

      setBoost(boosted, true, lp.powerMult, baseCheat)

      local now = GetGameTimer()
      _qty = math.max(0, _qty - ratePerSec * (now - last) / 1000.0)
      last = now
      hudSync()

      fireTick = fireTick + 1
      if fireTick % 3 == 0 then exhaustFire(boosted) end
      Wait(50)
    end

    if boosted ~= 0 and DoesEntityExist(boosted) then setBoost(boosted, false) end
    _boosting = false

    if boostedPlate and boosted ~= 0 and DoesEntityExist(boosted) then
      TriggerServerEvent('vhub_nitro:drain', VehToNet(boosted), boostedPlate, math.floor(_qty))
    end
  end)
end

RegisterCommand('+nitro', function() _holding = true; startBoost() end, false)
RegisterCommand('-nitro', function() _holding = false end, false)
RegisterKeyMapping('+nitro', 'Veículo: ativar nitro', 'keyboard', 'RSHIFT')


-- ============================================================
-- ESTADO (do servidor)
-- ============================================================

RegisterNetEvent('vhub_nitro:state')
AddEventHandler('vhub_nitro:state', function(plate, n)
  if plate ~= _plate or type(n) ~= 'table' then return end
  _kit     = n.kit == true
  _enabled = n.enabled == true
  _level   = math.max(1, math.min(10, math.floor(tonumber(n.level) or 1)))
  _qty     = math.max(0, math.min(100, tonumber(n.qty) or 0))
  _fireColor = (type(n.fire) == 'table' and tonumber(n.fire.r) and tonumber(n.fire.g)
    and tonumber(n.fire.b)) and { r = n.fire.r, g = n.fire.g, b = n.fire.b } or nil
  hudSync()
end)

RegisterNetEvent('vhub_nitro:notify')
AddEventHandler('vhub_nitro:notify', function(msg) notify(msg) end)


-- ============================================================
-- DETECÇÃO DE MOTORISTA (1 Hz)
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
          hudSync()
          TriggerServerEvent('vhub_nitro:request', pl)
        end
      elseif _plate then
        _plate, _kit, _enabled, _level, _qty = nil, false, false, 1, 0
        hudSync()
      end
    elseif _plate then
      _plate, _kit, _enabled, _level, _qty = nil, false, false, 1, 0
      hudSync()
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
