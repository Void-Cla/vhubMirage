-- server/vehicle.lua — Gestão de veículos e sincronização
-- Responsabilidade: manter VRAM, State Bags e autoridade de entidades
local Veh = {}; Veh.__index = Veh; vHub.Vehicle = Veh

Veh._veh   = {}  -- { [plate]   = VehicleData }
Veh._byKey = {}  -- { [key_uid] = plate }
Veh._byNet = {}  -- { [netid]   = plate }

local function normalizePlate(p)
  if type(p) ~= "string" or #p < 1 or #p > 16 then return nil end
  if #p <= 10 and (p:match("^[A-Z0-9]+[A-Z0-9 ]*[A-Z0-9]$") or p:match("^[A-Z0-9]$")) then return p end
  local plate = p:upper():gsub("%s+", " "):match("^%s*(.-)%s*$")
  if plate == "" or #plate > 10 or not plate:match("^[A-Z0-9]+[A-Z0-9 ]*[A-Z0-9]$") then return nil end
  return plate
end

local VD = vHub.class()
function VD:init(plate, key_uid)
  self.plate     = plate
  self.key_uid   = key_uid   -- nil = server/auction owns it
  self.netid     = nil
  self.spawned   = false
  self.driver    = nil
  self.occupants = {}        -- { [source] = seat_index }
  self.dirty     = false
  self.state = {
    fuel=100.0, engine_health=1000.0, body_health=1000.0,
    damage={}, tuning={}, garage=nil,
    last_pos={x=0,y=0,z=0,h=0}, odometer=0.0, engine_on=false,
  }
  -- Cache do último valor replicado ao State Bag (gating por delta — F4.4).
  -- Default -math.huge garante que o primeiro write SEMPRE acontece.
  self._last_fuel_bag = -math.huge
  self._last_eng_bag  = -math.huge
  self._last_body_bag = -math.huge
  self._last_odo_bag  = -math.huge
end

-- Helper: escreve em State Bag apenas se delta >= threshold OU se valor cruzou
-- limite crítico (0 = vazio/destruído). Evita que cliente fique vendo "0.4L"
-- quando tanque na verdade já zerou, ou motor "morto" continuar exibindo HP.
local function bagSet(bag, key, value, vd, last_field, threshold)
  local last = vd[last_field]
  local cruzou_zero = (value == 0 and last ~= 0)
  if cruzou_zero or math.abs(value - last) >= threshold then
    bag:set(key, value, true)
    vd[last_field] = value
  end
end

-- Write state to FiveM State Bags — FiveM replicates to all clients
function VD:_syncBags()
  if not self.netid then return end
  local ent = NetworkGetEntityFromNetworkId(self.netid)
  if not ent or ent == 0 then return end
  local bag = Entity(ent).state; local s = self.state
  bagSet(bag, "vh_fuel", s.fuel,          self, "_last_fuel_bag", 0.5)
  bagSet(bag, "vh_eng",  s.engine_health, self, "_last_eng_bag",  5.0)
  bagSet(bag, "vh_body", s.body_health,   self, "_last_body_bag", 5.0)
  bagSet(bag, "vh_odo",  s.odometer,      self, "_last_odo_bag",  0.05)
  bag:set("vh_tune", s.tuning,    true)  -- tabela; mudança rara
  bag:set("vh_on",   s.engine_on, true)  -- bool; mudança rara
end

function Veh:_atualizarPosicao(vd)
  if not (vd and vd.netid) then return false end
  local ent = NetworkGetEntityFromNetworkId(vd.netid)
  if not ent or ent == 0 then return false end
  local c = GetEntityCoords(ent)
  vd.state.last_pos = {x=c.x,y=c.y,z=c.z,h=GetEntityHeading(ent)}
  return true
end

-- Register / load — MUST run inside Citizen.CreateThread (uses Await)
function Veh:register(plate, key_uid)
  vHub.assertThread()
  plate = normalizePlate(plate)
  if not plate then
    if vHub and vHub.Logger then vHub.Logger:warn("vehicle", "Placa inválida rejeitada: " .. tostring(plate)) end
    return nil
  end
  if self._veh[plate] then return self._veh[plate] end
  local vd = VD.new(plate, key_uid)
  local saved = vHub.getVData(plate, "state")
  if type(saved) == "table" then vd.state = saved end
  if not key_uid then
    local r = Citizen.Await(vHub.State:query("vh/veh_key", {plate=plate}))
    if r and #r > 0 then vd.key_uid = r[1].key_uid end
  end
  self._veh[plate] = vd
  if vd.key_uid then self._byKey[vd.key_uid] = plate end
  TriggerEvent("vHub:vehicleLoaded", vd)
  return vd
end

function Veh:unregister(plate)
  plate = normalizePlate(plate)
  if not plate then return end
  local vd = self._veh[plate]; if not vd then return end
  self:_save(vd)
  if vd.key_uid then self._byKey[vd.key_uid] = nil end
  if vd.netid   then self._byNet[vd.netid]   = nil end
  self._veh[plate] = nil
end

function Veh:transferKey(plate, new_key_uid)
  plate = normalizePlate(plate)
  if not plate then return false end
  local vd = self._veh[plate]
  if not vd then
    -- not in VRAM yet, register first (caller must be in thread)
    vd = self:register(plate, nil)
  end
  if not vd then return false end
  if vd.key_uid then self._byKey[vd.key_uid] = nil end
  vd.key_uid = new_key_uid; vd.dirty = true
  if new_key_uid then self._byKey[new_key_uid] = plate end
  vHub.State:_queue({"vh/veh_set_key", {plate=plate, key_uid=new_key_uid}})
  TriggerEvent("vHub:vehicleKeyTransferred", vd, new_key_uid)
  return true
end

function Veh:byKey(key_uid)
  vHub.assertThread()
  if key_uid == nil then return nil end
  if self._byKey[key_uid] then return self._byKey[key_uid] end
  local r = Citizen.Await(vHub.State:query("vh/veh_by_key", {key_uid=key_uid}))
  if r and #r > 0 then
    local plate = normalizePlate(r[1].plate)
    if plate then self._byKey[key_uid]=plate; return plate end
  end
end

function Veh:onSpawned(plate, netid)
  plate = normalizePlate(plate)
  if not plate then return end
  local vd = self._veh[plate] or self:register(plate, nil)
  if not vd then return end
  vd.netid=netid; vd.spawned=true
  self._byNet[netid] = plate
  vd:_syncBags()   -- saved state pushed to State Bags immediately
  TriggerEvent("vHub:vehicleSpawned", vd)
end

function Veh:onDespawned(plate)
  plate = normalizePlate(plate)
  if not plate then return end
  local vd = self._veh[plate]; if not vd then return end
  if vd.netid then
    if self:_atualizarPosicao(vd) then vd.dirty = true end
    self._byNet[vd.netid] = nil
  end
  vd.netid=nil; vd.spawned=false; vd.driver=nil; vd.occupants={}
  self:_save(vd)
  TriggerEvent("vHub:vehicleDespawned", vd)
end

function Veh:onEnter(src, plate, netid, seat)
  plate = normalizePlate(plate)
  if not plate then return end
  local vd = self._veh[plate]
  if not vd then
    self:onSpawned(plate, netid); vd = self._veh[plate]
  end
  if not vd then return end

  vd.occupants[src] = seat

  if seat == -1 then   -- DRIVER → becomes sole position authority
    vd.driver = src
    local ent = vd.netid and NetworkGetEntityFromNetworkId(vd.netid)
    if ent and ent ~= 0 then
      NetworkSetEntityOwner(ent, src)   -- GTA native: only driver writes pos
    end
    vHub.Kernel:emit(src, "vHub:vehicleStateLoad", plate, vd.state)
  else                 -- PASSENGER → passive, GTA delivers position
    vHub.Kernel:emit(src, "vHub:passengerMode", plate, true)
  end
  TriggerEvent("vHub:vehicleEnter", vd, src, seat)
end

function Veh:onLeave(src, plate, seat)
  plate = normalizePlate(plate)
  if not plate then return end
  local vd = self._veh[plate]; if not vd then return end
  vd.occupants[src] = nil

  if seat == -1 and vd.driver == src then
    vd.driver = nil
    local next_src = next(vd.occupants)
    if next_src and vd.netid then
      local ent = NetworkGetEntityFromNetworkId(vd.netid)
      if ent and ent ~= 0 then NetworkSetEntityOwner(ent, next_src) end
    end
  else
    vHub.Kernel:emit(src, "vHub:passengerMode", plate, false)
  end
  TriggerEvent("vHub:vehicleLeave", vd, src, seat)
end

function Veh:onStateUpdate(src, plate, upd)
  plate = normalizePlate(plate)
  if not plate or type(upd) ~= "table" then return end
  local vd = self._veh[plate]
  if not vd or vd.driver ~= src then return end   -- only driver authorized

  local s   = vd.state
  local ent = vd.netid and NetworkGetEntityFromNetworkId(vd.netid)
  local bag = (ent and ent ~= 0) and Entity(ent).state

  local rpm = tonumber(upd.rpm)
  if rpm and rpm > 0.05 then
    rpm = math.min(rpm, 1.0)
    s.fuel = math.max(0, s.fuel - rpm * (vHub.cfg.fuel_rate or 0.005))
    if bag then bagSet(bag, "vh_fuel", s.fuel, vd, "_last_fuel_bag", 0.5) end
    if s.fuel == 0 then TriggerEvent("vHub:vehicleFuelEmpty", vd, src) end
  end

  local engine_health = tonumber(upd.engine_health)
  if engine_health then
    s.engine_health = math.max(0, math.min(1000, engine_health))
    if bag then bagSet(bag, "vh_eng", s.engine_health, vd, "_last_eng_bag", 5.0) end
  end

  local body_health = tonumber(upd.body_health)
  if body_health then
    s.body_health = math.max(0, math.min(1000, body_health))
    if bag then bagSet(bag, "vh_body", s.body_health, vd, "_last_body_bag", 5.0) end
  end

  local odometer_delta = tonumber(upd.odometer_delta)
  if odometer_delta and odometer_delta > 0 then
    local hz = tonumber((vHub.cfg and vHub.cfg.veh_state_hz) or 4)
    local time_per_tick = 1 / math.max(1, hz)
    local max_speed_kmh = tonumber((vHub.cfg and vHub.cfg.max_speed_kmh) or 350)
    local max_delta = (rpm or 0) * max_speed_kmh * time_per_tick / 3600
    local applied = math.min(odometer_delta, math.max(0.0001, max_delta), 0.5)
    s.odometer = s.odometer + applied
    if bag then bagSet(bag, "vh_odo", s.odometer, vd, "_last_odo_bag", 0.05) end
  end

  if upd.engine_on ~= nil then
    s.engine_on = upd.engine_on == true
    if bag then bag:set("vh_on", s.engine_on, true) end
  end

  vd.dirty = true
end

function Veh:_save(vd)
  if not vd.dirty then return end
  self:_atualizarPosicao(vd)
  vHub.setVData(vd.plate, "state", vd.state); vd.dirty=false
end

function Veh:saveAll()
  for _, vd in pairs(self._veh) do self:_save(vd) end
end

-- GC periódico de _byNet: remove netids cuja entidade não existe mais (5 min)
Citizen.CreateThread(function()
  vHub.assertThread()
  while true do
    Citizen.Wait(300000)
    local checados, removidos = 0, 0
    for netid in pairs(Veh._byNet) do
      local ent = NetworkGetEntityFromNetworkId(netid)
      if not ent or ent == 0 then
        Veh._byNet[netid] = nil
        removidos = removidos + 1
      end
      checados = checados + 1
      if checados % 100 == 0 then Citizen.Wait(0) end
    end
    if removidos > 0 and vHub.Logger then
      vHub.Logger:info("vehicle",
        ("GC _byNet — %d removido(s) de %d checado(s)"):format(removidos, checados))
    end
  end
end)
