-- shared/vehicle.lua — wrapper de natives de veiculo com pcall + log 1-shot.
-- Resolve "native faltando": tudo retorna default seguro, sem crashar o resource.

VHubRachaVeh = {}
local V = VHubRachaVeh
local _MISSING = {}

local function _warn(name)
  if _MISSING[name] then return end
  _MISSING[name] = true
  VHubRachaLog.warn('native indisponivel: %s — default seguro aplicado.', name)
end

local function _call(name, fn, default, ...)
  if type(fn) ~= 'function' then _warn(name); return default end
  local ok, r = pcall(fn, ...)
  if not ok then _warn(name); return default end
  return r
end

function V.is_alive(veh)
  if not veh or veh == 0 then return false end
  return _call('DoesEntityExist', _G.DoesEntityExist, false, veh) == true
end

function V.class(veh)
  if not V.is_alive(veh) then return -1 end
  return _call('GetVehicleClass', _G.GetVehicleClass, -1, veh)
end

function V.coords(veh)
  if not V.is_alive(veh) then return 0.0, 0.0, 0.0 end
  local r = _call('GetEntityCoords', _G.GetEntityCoords, nil, veh)
  if not r then return 0.0, 0.0, 0.0 end
  return r.x or 0.0, r.y or 0.0, r.z or 0.0
end

function V.heading(veh)
  if not V.is_alive(veh) then return 0.0 end
  return _call('GetEntityHeading', _G.GetEntityHeading, 0.0, veh) or 0.0
end

function V.velocity(veh)
  if not V.is_alive(veh) then return 0.0, 0.0, 0.0 end
  local r = _call('GetEntityVelocity', _G.GetEntityVelocity, nil, veh)
  if not r then return 0.0, 0.0, 0.0 end
  return r.x or 0.0, r.y or 0.0, r.z or 0.0
end

function V.speed_kmh(veh)
  if not V.is_alive(veh) then return 0.0 end
  local ms = _call('GetEntitySpeed', _G.GetEntitySpeed, 0.0, veh)
  return (ms or 0.0) * 3.6
end

function V.is_in_air(veh)
  if not V.is_alive(veh) then return false end
  return _call('IsEntityInAir', _G.IsEntityInAir, false, veh)
end

-- Velocidade local (forward/lateral) para drift scoring.
function V.local_velocity(veh)
  if not V.is_alive(veh) then return 0.0, 0.0, 0.0 end
  local vx, vy, _ = V.velocity(veh)
  local h = V.heading(veh)
  local rad = math.rad(h)
  local fx, fy = -math.sin(rad), math.cos(rad)
  local fwd = (vx * fx + vy * fy)
  local lat = (vx * fy - vy * fx)
  return fwd * 3.6, lat * 3.6, h
end

-- Veh atual do ped, sempre dentro de pcall (algumas builds nao tem inclusive arg)
function V.ped_vehicle(ped)
  if not ped or ped == 0 then return 0 end
  if type(_G.GetVehiclePedIsIn) ~= 'function' then return 0 end
  local ok, veh = pcall(_G.GetVehiclePedIsIn, ped, false)
  return ok and (veh or 0) or 0
end

-- Esta como motorista (seat -1)?
function V.is_driver(ped)
  local veh = V.ped_vehicle(ped)
  if veh == 0 then return false, 0 end
  if type(_G.GetPedInVehicleSeat) ~= 'function' then return false, veh end
  local ok, seat_ped = pcall(_G.GetPedInVehicleSeat, veh, -1)
  return ok and seat_ped == ped, veh
end

-- Buzina (input control). Use no editor para "salvar slot" sem digitar comando.
function V.is_horn_pressed(ped)
  if type(_G.IsControlJustPressed) ~= 'function' then return false end
  local ok, pressed = pcall(_G.IsControlJustPressed, 0, 86)   -- 86 = horn
  return ok and pressed
end
