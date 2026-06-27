---@diagnostic disable: undefined-global

-- server/main.lua — autoridade do controle de veiculo (vHub, server-authoritative).
--
-- PRINCIPIO: o servidor NAO toca a entidade do veiculo. Nativas de veiculo sao
-- instaveis/ausentes server-side (ex: NetworkGetEntityFromNetworkId nil). Entao o
-- servidor apenas AUTORIZA (chave do inventario / dono no garage), mantem o ESTADO
-- autoritativo (trava/motor — fonte unica p/ evitar desync) e BROADCASTA; o CLIENTE
-- aplica o native localmente. Portas/janelas/luzes/banco/camera sao locais (cosmeticos).

local E = 'vhub_vehcontrol:'

local _lock   = {}   -- [plate] = 1 (destravado) | 2 (travado)
local _engine = {}   -- [plate] = bool (ligado)

-- normaliza placa p/ comparacao (GTA devolve padding de espacos; espelha o CORE)
local function normPlate(p)
  local s = tostring(p or ''):upper():gsub('%s+', ' ')
  return s:match('^%s*(.-)%s*$') or ''
end


-- ============================================================
-- AUTORIZACAO
-- ============================================================

-- jogador pode controlar trava/motor/radio deste veiculo?
local function hasAccess(src, plate)
  if not Config.requireKey then return true end
  if type(plate) ~= 'string' or plate == '' then return false end

  -- 1) chave fisica no inventario (vhub_inventory)
  local ok, hasKey = pcall(function() return exports.vhub_inventory:hasVehicleKey(src, plate) end)
  if ok and hasKey then return true end

  -- 2) dono do veiculo no garage (vhub_garage)
  local oku, user = pcall(function() return exports.vhub:getUser(src) end)
  if oku and user and user.char_id then
    local okv, veh = pcall(function() return exports.vhub_garage:getVehicle(plate) end)
    if okv and veh and tonumber(veh.char_id) == user.char_id then return true end
  end

  return false
end

-- exposto p/ outros arquivos server do resource (ex: sound.lua) — mesma checagem, fonte única (L-04/L-09)
VHubVeh = VHubVeh or {}
VHubVeh.hasVehicleAccess = hasAccess


-- ============================================================
-- TRAVA / MOTOR — servidor mantem o estado e manda TODOS aplicarem
-- ============================================================

-- ANTI-SPOOF: o servidor manda a PLACA junto do netId. O cliente só aplica se a
-- placa do veiculo do netId bater (plateOf e confiavel client-side). Assim, mesmo
-- que o cliente forje um netId de outro carro, o broadcast e descartado nos clientes.

RegisterNetEvent(E .. 'requestLock')
AddEventHandler(E .. 'requestLock', function(netId, plate)
  local src = source
  if type(plate) ~= 'string' or not hasAccess(src, plate) then return end   -- silencioso (L-01)
  local newState = (_lock[plate] == 2) and 1 or 2                            -- alterna travado/destravado
  _lock[plate] = newState
  TriggerClientEvent(E .. 'applyLock', -1, tonumber(netId), plate, newState)
  TriggerClientEvent(E .. 'lockNotify', src, newState)                       -- so o requester ve a msg
end)

RegisterNetEvent(E .. 'requestEngine')
AddEventHandler(E .. 'requestEngine', function(netId, plate)
  local src = source
  if type(plate) ~= 'string' or not hasAccess(src, plate) then return end
  local newState = not (_engine[plate] or false)
  _engine[plate] = newState
  TriggerClientEvent(E .. 'applyEngine', -1, tonumber(netId), plate, newState)
end)


-- ============================================================
-- PRONTUÁRIO — telemetria física validada → escritor único (vhub_conce)
-- ============================================================
-- A cadeia física do CORE (vEnter→onEnter→vh_vehicle_data) foi DESCONECTADA no
-- sprint PRONTUÁRIO (supera a decisão #21). Fluxo novo: client (motorista) coleta
-- natives → stateSync → validação FAIL-CLOSED aqui → exports.vhub_conce:
-- saveVehicleState (única escrita). Exceção CONSCIENTE ao residual #22d: netId
-- que não resolve = DROP, pois este evento ESCREVE estado (o vEnter só ancorava).

local SYNC_MIN_MS  = 14000   -- gate temporal: telemetria legítima é 15s (L-18)
local FINAL_MIN_MS = 2000    -- snapshot final (sair do banco) tem gate próprio
local _syncAt, _finalAt, _reqAt = {}, {}, {}

-- valida netId→entidade→placa→motorista (FAIL-CLOSED, OneSync Infinity)
local function resolveDriven(src, netId, plate)
  netId = tonumber(netId)
  if not (netId and netId > 0 and netId == math.floor(netId)) then return nil end
  local p = normPlate(plate); if p == '' then return nil end
  local ent = NetworkGetEntityFromNetworkId(netId)
  if not ent or ent == 0 then return nil end
  if normPlate(GetVehicleNumberPlateText(ent) or '') ~= p then return nil end
  if GetPedInVehicleSeat(ent, -1) ~= GetPlayerPed(src) then return nil end
  return p
end

-- número finito clampado, ou nil (rejeita NaN/±inf ANTES do clamp)
local function finiteNum(v, lo, hi)
  if type(v) ~= 'number' or v ~= v or math.abs(v) == math.huge then return nil end
  if lo and v < lo then v = lo end
  if hi and v > hi then v = hi end
  return v
end

RegisterNetEvent(E .. 'stateSync')
AddEventHandler(E .. 'stateSync', function(netId, plate, snap)
  local src = source
  if type(snap) ~= 'table' then return end

  -- gate temporal por src: periódico ≥14s; final (sair do banco) ≥2s (dedup leave×tick)
  local now = GetGameTimer()
  if snap.final == true then
    if now - (_finalAt[src] or -FINAL_MIN_MS) < FINAL_MIN_MS then return end
    _finalAt[src] = now
  else
    if now - (_syncAt[src] or -SYNC_MIN_MS) < SYNC_MIN_MS then return end
    _syncAt[src] = now
  end

  local p = resolveDriven(src, netId, plate)
  if not p then return end   -- silencioso (L-01)

  -- odômetro: delta negativo/NaN = payload hostil → dropa o snapshot INTEIRO
  local odo = snap.odo_delta_km
  if odo ~= nil and (type(odo) ~= 'number' or odo ~= odo or odo < 0 or odo == math.huge) then
    return
  end

  local patch = {
    fuel          = finiteNum(snap.fuel, 0.0, 100.0),
    engine_health = finiteNum(snap.engine_health, -4000.0, 1000.0),
    body_health   = finiteNum(snap.body_health, 0.0, 1000.0),
    odometer_add  = odo and math.min(odo, 2.0) or nil,
    damage        = (type(snap.damage) == 'table') and snap.damage or nil,
  }

  -- escrita imediata no escritor único (re-sanitiza/clampa lá — defesa em
  -- profundidade); fail-closed para placa sem registro ou status ~= 'out'
  Citizen.CreateThread(function()
    pcall(function() exports.vhub_conce:saveVehicleState(p, patch, 'telemetry') end)
  end)
end)

-- entrada como motorista: devolve o estado salvo p/ o client aplicar nos natives
-- (substitui o vHub:vehicleStateLoad do CORE)
RegisterNetEvent(E .. 'requestState')
AddEventHandler(E .. 'requestState', function(netId, plate)
  local src = source
  local now = GetGameTimer()
  if now - (_reqAt[src] or -2000) < 2000 then return end
  _reqAt[src] = now
  local p = resolveDriven(src, netId, plate)
  if not p then return end
  Citizen.CreateThread(function()
    local ok, st = pcall(function() return exports.vhub_conce:getVehicleState(p) end)
    if ok and type(st) == 'table' then
      TriggerClientEvent(E .. 'applyState', src, p, {
        fuel          = st.fuel,
        engine_health = st.engine_health,
        body_health   = st.body_health,
        odometer_km   = st.odometer_km,
        damage        = st.damage,
      })
    end
  end)
end)


-- ============================================================
-- GC de estado (placa nao precisa de estado eterno em memoria)
-- ============================================================

-- limpeza leve: ao parar o resource, descarta o estado em memoria.
-- NADA pendente a flushar: todo snapshot aceito vira UPSERT IMEDIATO no conce
-- (sem buffer server-side) — garantia mais forte que flush-em-stop.
AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  _lock, _engine, _syncAt, _finalAt, _reqAt = {}, {}, {}, {}, {}
end)

-- evita crescimento dos mapas de rate-limit quando o jogador sai
AddEventHandler('playerDropped', function()
  _syncAt[source], _finalAt[source], _reqAt[source] = nil, nil, nil
end)
