-- client/vehicles.lua  spawn/despawn de ve culos + estado visual
-- Mant m mapa local plate   entity, registra decorator e cuida do surface (ground/water/air).
---@diagnostic disable: undefined-global

local E = VHubGarage.E
local state = VHubGarage.state

state.veiculos = state.veiculos or {}

-- forward declarations (permitem que `spawnVehicle` chame fun  es definidas
-- mais abaixo no arquivo; Lua resolve a vari vel local em runtime)
local despawnLocal, scanAndDeleteByPlate

-- NOTA: n o usamos `DecorSetString` (foi removido do FiveM). A placa GTA
-- nativa (`SetVehicleNumberPlateText` / `GetVehicleNumberPlateText`)   o
-- identificador  nico do ve culo  ela j  replica por sync padr o.

-- ----------------------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------------------
local function loadModel(name)
  local hash = type(name) == 'number' and name or GetHashKey(name)
  if not IsModelInCdimage(hash) then return nil end
  RequestModel(hash)
  local t = 0
  while not HasModelLoaded(hash) and t < 5000 do Citizen.Wait(50); t = t + 50 end
  return HasModelLoaded(hash) and hash or nil
end

local function placeOnSurface(veh, surface)
  if surface == 'water' then
    SetEntityCoordsNoOffset(veh, GetEntityCoords(veh), false, false, false)
  elseif surface == 'pad' or surface == 'runway' then
    -- aeronaves: deixa na altura recebida do servidor
  else
    SetVehicleOnGroundProperly(veh)
  end
end

local function applyCustomization(veh, c)
  if type(c) ~= 'table' then return end
  SetVehicleModKit(veh, 0)
  if c.colours        then SetVehicleColours(veh, table.unpack(c.colours)) end
  if c.extra_colours  then SetVehicleExtraColours(veh, table.unpack(c.extra_colours)) end
  if c.plate_index    then SetVehicleNumberPlateTextIndex(veh, c.plate_index) end
  if c.wheel_type     then SetVehicleWheelType(veh, c.wheel_type) end
  if c.window_tint    then SetVehicleWindowTint(veh, c.window_tint) end
  if c.livery         then SetVehicleLivery(veh, c.livery) end
  if type(c.mods) == 'table' then
    for i, m in pairs(c.mods) do SetVehicleMod(veh, tonumber(i), m, false) end
  end
  if c.turbo  ~= nil then ToggleVehicleMod(veh, 18, c.turbo) end
  if c.smoke  ~= nil then ToggleVehicleMod(veh, 20, c.smoke) end
  if c.xenon  ~= nil then ToggleVehicleMod(veh, 22, c.xenon) end
  if type(c.neons) == 'table' then
    -- chaves numericas viram string apos round-trip JSON ("0".."3") — tolerar ambas
    for i = 0, 3 do
      local on = c.neons[i]
      if on == nil then on = c.neons[tostring(i)] end
      SetVehicleNeonLightEnabled(veh, i, on == true)
    end
  end
  if c.neon_colour then SetVehicleNeonLightsColour(veh, table.unpack(c.neon_colour)) end
end

local function collectCustomization(veh)
  local c = {
    colours       = { GetVehicleColours(veh) },
    extra_colours = { GetVehicleExtraColours(veh) },
    plate_index   = GetVehicleNumberPlateTextIndex(veh),
    wheel_type    = GetVehicleWheelType(veh),
    window_tint   = GetVehicleWindowTint(veh),
    livery        = GetVehicleLivery(veh),
    turbo         = IsToggleModOn(veh, 18),
    smoke         = IsToggleModOn(veh, 20),
    xenon         = IsToggleModOn(veh, 22),
    mods          = {},
    neons         = {},
    neon_colour   = { GetVehicleNeonLightsColour(veh) },
    model         = GetEntityModel(veh),
  }
  for i = 0, 49 do c.mods[i] = GetVehicleMod(veh, i) end
  for i = 0, 3  do c.neons[i] = IsVehicleNeonLightEnabled(veh, i) end
  return c
end

-- bones de janela por  ndice (janela inexistente no modelo reporta "quebrada"
-- no native  bone-check obrigat rio antes de aplicar)
local WINDOW_BONES = {
  [0]='window_lf', [1]='window_rf', [2]='window_lr', [3]='window_rr',
  [4]='window_lm', [5]='window_rm', [6]='windscreen', [7]='windscreen_r',
}

-- aplica o estado f sico do PRONTU RIO (fuel/health/dano) na entidade rec m-criada
-- (criador da entidade = dono de rede neste momento, sem gate de controle)
local function applyPhysicalState(veh, st)
  if type(st) ~= 'table' then return end
  -- CRITICO: '+ 0.0' força subtipo FLOAT (Lua 5.4) — inteiro do msgpack passado
  -- a native float é bit-reinterpretado (1000 → 1.4e-42 = motor/fuel zerados)
  if type(st.fuel)          == 'number' then SetVehicleFuelLevel(veh, st.fuel + 0.0) end
  if type(st.engine_health) == 'number' then SetVehicleEngineHealth(veh, st.engine_health + 0.0) end
  if type(st.body_health)   == 'number' then SetVehicleBodyHealth(veh, st.body_health + 0.0) end
  local d = st.damage
  if type(d) ~= 'table' then return end
  for _, i in ipairs(d.doors or {}) do SetVehicleDoorBroken(veh, i, true) end
  for _, i in ipairs(d.windows or {}) do
    local bone = WINDOW_BONES[i]
    if bone and GetEntityBoneIndexByName(veh, bone) ~= -1 then SmashVehicleWindow(veh, i) end
  end
  if GetVehicleTyresCanBurst(veh) then
    for _, i in ipairs(d.tyres or {})     do SetVehicleTyreBurst(veh, i, false, 1000.0) end
    for _, i in ipairs(d.tyres_rim or {}) do SetVehicleTyreBurst(veh, i, true, 1000.0) end
  end
end

-- ----------------------------------------------------------------------------
-- SPAWN  apaga duplicata local + scan global antes de criar
-- ----------------------------------------------------------------------------
local function spawnVehicle(snap, pos, entrar)
  -- defesa: apaga qualquer inst ncia anterior dessa placa
  if state.veiculos[snap.plate] then despawnLocal(snap.plate) end
  scanAndDeleteByPlate(snap.plate)

  local hash = loadModel(snap.model)
  if not hash then return false end
  local x, y, z = pos.x, pos.y, pos.z + 0.5
  local h = pos.h or 0.0
  local veh = CreateVehicle(hash, x, y, z, h, true, false)
  SetModelAsNoLongerNeeded(hash)
  if not DoesEntityExist(veh) then return false end
  SetVehicleNumberPlateText(veh, snap.plate)
  placeOnSurface(veh, snap.surface)
  SetEntityAsMissionEntity(veh, true, true)
  SetVehicleHasBeenOwnedByPlayer(veh, true)
  applyCustomization(veh, snap.customization)
  applyPhysicalState(veh, snap.state)   -- PRONTU RIO: fuel/health/dano (p s-customization)
  if snap.locked then
    SetVehicleDoorsLocked(veh, 2)
    SetVehicleDoorsLockedForAllPlayers(veh, true)
  end
  if entrar then SetPedIntoVehicle(PlayerPedId(), veh, -1) end
  state.veiculos[snap.plate] = veh
  return true, veh
end

RegisterNetEvent(E.DO_SPAWN)
AddEventHandler(E.DO_SPAWN, function(snap, pos)
  Citizen.CreateThread(function() spawnVehicle(snap, pos, true) end)
end)

RegisterNetEvent(E.SPAWN_OUT)
AddEventHandler(E.SPAWN_OUT, function(list)
  if type(list) ~= 'table' then return end
  Citizen.CreateThread(function()
    for _, snap in ipairs(list) do
      spawnVehicle(snap, snap.position or { x = 0, y = 0, z = 0, h = 0 }, false)
    end
  end)
end)

-- ----------------------------------------------------------------------------
-- DESPAWN  apaga DE VERDADE (warp out + NetworkRequestControl + DeleteVehicle)
-- + scan do pool de ve culos para apagar qualquer duplicata com mesma placa
-- ----------------------------------------------------------------------------

-- iterador local de ve culos no mundo
local function enumerateVehicles()
  return coroutine.wrap(function()
    local it, veh = FindFirstVehicle()
    if not it or not veh or veh == 0 then
      if it then EndFindVehicle(it) end
      return
    end
    coroutine.yield(veh)
    while true do
      local has
      has, veh = FindNextVehicle(it)
      if not has or not veh or veh == 0 then break end
      coroutine.yield(veh)
    end
    EndFindVehicle(it)
  end)
end

-- tenta deletar o entity (assume controle de rede + DeleteEntity + fallback)
local function tryDeleteEntity(veh)
  if not veh or veh == 0 or not DoesEntityExist(veh) then return false end
  NetworkRequestControlOfEntity(veh)
  local t = 0
  while not NetworkHasControlOfEntity(veh) and t < 1000 do
    Citizen.Wait(50); t = t + 50
  end
  SetEntityAsMissionEntity(veh, true, true)
  DeleteEntity(veh)
  if DoesEntityExist(veh) then SetVehicleAsNoLongerNeeded(veh) end
  return not DoesEntityExist(veh)
end

-- normaliza placa para compara  o (sem espa os, upper)
local function normPlate(p)
  if type(p) ~= 'string' then return '' end
  return p:upper():gsub('%s+', '')
end

-- procura QUALQUER ve culo no mundo com placa == plate e apaga
-- Usa SOMENTE placa nativa do GTA (DecorSetString foi removido do FiveM).
scanAndDeleteByPlate = function(plate)
  if not plate or plate == '' then return 0 end
  local target = normPlate(plate)
  local removed = 0
  for veh in enumerateVehicles() do
    if DoesEntityExist(veh) then
      local raw = GetVehicleNumberPlateText(veh)
      if raw and normPlate(raw) == target then
        if tryDeleteEntity(veh) then removed = removed + 1 end
      end
    end
  end
  return removed
end

despawnLocal = function(plate)
  local veh = state.veiculos[plate]
  if veh and DoesEntityExist(veh) then
    local ped = PlayerPedId()
    if GetVehiclePedIsIn(ped, false) == veh then
      TaskLeaveVehicle(ped, veh, 16)  -- flag 16 = warp out (sem anima  o)
      Citizen.Wait(150)
    end
    tryDeleteEntity(veh)
  end
  state.veiculos[plate] = nil
  -- defesa: apaga qualquer outra inst ncia com a mesma placa
  scanAndDeleteByPlate(plate)
end

-- encontra entidade local pela placa (fallback p/ handle stale apos migracao/cull)
local function findByPlate(plate)
  local target = normPlate(plate)
  if target == '' then return nil end
  for veh in enumerateVehicles() do
    if DoesEntityExist(veh) then
      local raw = GetVehicleNumberPlateText(veh)
      if raw and normPlate(raw) == target then return veh end
    end
  end
end

RegisterNetEvent(E.DO_DESPAWN)
AddEventHandler(E.DO_DESPAWN, function(plate)
  despawnLocal(plate)
end)

-- ----------------------------------------------------------------------------
-- Test drive (cliente cria, removido ao fim ou ao se afastar)
-- ----------------------------------------------------------------------------
local _td = nil
local function endTestDrive(msg)
  if _td and DoesEntityExist(_td.veh) then
    if GetVehiclePedIsIn(PlayerPedId(), false) == _td.veh then
      TaskLeaveVehicle(PlayerPedId(), _td.veh, 4160); Citizen.Wait(500)
    end
    SetEntityAsMissionEntity(_td.veh, false, true)
    SetVehicleAsNoLongerNeeded(_td.veh)
  end
  _td = nil
  if msg then
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandThefeedPostTicker(false, true)
  end
end

RegisterNetEvent(E.DO_TESTDRIVE)
AddEventHandler(E.DO_TESTDRIVE, function(data)
  Citizen.CreateThread(function()
    endTestDrive(nil)
    local hash = loadModel(data.model); if not hash then return end
    local sp = data.spawn or { x = 0, y = 0, z = 0, h = 0 }
    local veh = CreateVehicle(hash, sp.x, sp.y, sp.z + 0.5, sp.h or 0.0, true, false)
    SetModelAsNoLongerNeeded(hash)
    if not DoesEntityExist(veh) then return end
    SetVehicleOnGroundProperly(veh)
    SetEntityAsMissionEntity(veh, true, true)
    SetPedIntoVehicle(PlayerPedId(), veh, -1)
    _td = { veh = veh, expires = GetGameTimer() + data.seg * 1000, raio = data.raio, origin = vector3(sp.x, sp.y, sp.z) }
    -- watchdog
    Citizen.CreateThread(function()
      while _td and _td.veh == veh do
        Citizen.Wait(1000)
        if GetGameTimer() > _td.expires then endTestDrive('Test drive encerrado.'); break end
        local d = #(GetEntityCoords(PlayerPedId()) - _td.origin)
        if d > _td.raio then endTestDrive('Voc  se afastou demais. Test drive cancelado.'); break end
      end
    end)
  end)
end)

-- ----------------------------------------------------------------------------
-- Coleta de estado (para `store` no servidor)
-- Event handlers em FXServer N O retornam valores; chamamos via callback param.
-- Uso: TriggerEvent('vhub_garage:collectClientState', plate, function(s) ... end)
-- ----------------------------------------------------------------------------
AddEventHandler('vhub_garage:collectClientState', function(plate, cb)
  if type(cb) ~= 'function' then return end
  local veh = state.veiculos[plate]
  if not veh or not DoesEntityExist(veh) then
    -- handle pode ficar stale (migracao de ownership/cull): re-resolve pela placa
    -- para nao guardar SILENCIOSAMENTE sem customization (mods sumiam no restart)
    veh = findByPlate(plate)
    if veh then state.veiculos[plate] = veh end
  end
  if not veh or not DoesEntityExist(veh) then cb(nil); return end
  local c = GetEntityCoords(veh, true)
  -- dano estrutural persist vel (espelha a coleta do vehcontrol; bone-check de janela)
  local dmg = { doors = {}, windows = {}, tyres = {}, tyres_rim = {} }
  for i = 0, 5 do if IsVehicleDoorDamaged(veh, i) then dmg.doors[#dmg.doors+1] = i end end
  for i = 0, 7 do
    local bone = WINDOW_BONES[i]
    if bone and GetEntityBoneIndexByName(veh, bone) ~= -1 and not IsVehicleWindowIntact(veh, i) then
      dmg.windows[#dmg.windows+1] = i
    end
  end
  if GetVehicleTyresCanBurst(veh) then
    for i = 0, 7 do
      if IsVehicleTyreBurst(veh, i, true) then dmg.tyres_rim[#dmg.tyres_rim+1] = i
      elseif IsVehicleTyreBurst(veh, i, false) then dmg.tyres[#dmg.tyres+1] = i end
    end
  end
  cb({
    customization = collectCustomization(veh),
    locked        = GetVehicleDoorLockStatus(veh) >= 2,
    position      = { x = c.x, y = c.y, z = c.z, h = GetEntityHeading(veh) },
    fuel          = GetVehicleFuelLevel(veh),
    engine_health = GetVehicleEngineHealth(veh),
    body_health   = GetVehicleBodyHealth(veh),
    damage        = dmg,
  })
end)

-- ----------------------------------------------------------------------------
-- Reparo pago: conserta a entidade VIVA (o servidor j  elevou o prontu rio)
-- ----------------------------------------------------------------------------
RegisterNetEvent(E.DO_REPAIR)
AddEventHandler(E.DO_REPAIR, function(plate)
  Citizen.CreateThread(function()
    local veh = state.veiculos[plate] or findByPlate(plate)
    if not veh or not DoesEntityExist(veh) then return end
    NetworkRequestControlOfEntity(veh)
    local t = 0
    while not NetworkHasControlOfEntity(veh) and t < 20 do Citizen.Wait(0); t = t + 1 end
    if not NetworkHasControlOfEntity(veh) then return end
    SetVehicleFixed(veh)
    SetVehicleEngineHealth(veh, 1000.0)
    SetVehicleBodyHealth(veh, 1000.0)
    SetVehicleDirtLevel(veh, 0.0)
  end)
end)

-- ----------------------------------------------------------------------------
-- Reporte peri dico ao servidor (n o-cr tico: posi  o + customization)
-- ----------------------------------------------------------------------------
Citizen.CreateThread(function()
  local cfg = VHubGarage.cfg
  while true do
    Citizen.Wait((cfg.report_intervalo_s or 30) * 1000)
    for plate, veh in pairs(state.veiculos) do
      if DoesEntityExist(veh) and IsEntityAVehicle(veh) then
        local c = GetEntityCoords(veh, true)
        TriggerServerEvent(E.REPORT_STATE, plate, {
          position = { x = c.x, y = c.y, z = c.z, h = GetEntityHeading(veh) },
          locked   = GetVehicleDoorLockStatus(veh) >= 2,
        })
      else
        state.veiculos[plate] = nil
      end
    end
  end
end)

-- ----------------------------------------------------------------------------
-- Helpers expostos a outros m dulos do client
-- ----------------------------------------------------------------------------
function VHubGarage.veiculoMaisProximo(raio)
  raio = raio or 18.0
  local ped = PlayerPedId()
  local origin = GetEntityCoords(ped)
  local best, best_d = nil, raio
  for plate, veh in pairs(state.veiculos) do
    if DoesEntityExist(veh) then
      local d = #(origin - GetEntityCoords(veh))
      if d < best_d then best, best_d = plate, d end
    end
  end
  return best
end
