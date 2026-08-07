-- server/visual.lua — reidratação do estado VISUAL e de CAPABILITY persistidos (placa → State Bag).
--
-- Escritor canônico dos bags de entidade `vhub_custom:stance`, `vhub_custom:exhaust`,
-- `vhub_custom:drift` (Registro de Ownership). Responsabilidade separada da compra
-- (server/bennys.lua, server/drift.lua): aqui é só COPIAR o que já está na placa
-- para a entidade viva, disparado por eventos de spawn/entrada.
--
-- ZERO-TRUST (L-01): o cliente envia SOMENTE o netId. A placa REAL é derivada da entidade no
-- servidor (GetVehicleNumberPlateText) — nunca do payload. Leitura da verdade via export do
-- conce (L-14). Não decide nada; espelha a verdade da placa.
---@diagnostic disable: undefined-global

local Core = VHubCustom.Core
local U    = VHubCustom.U
local E    = VHubCustom.E
local BAG  = VHubCustom.BAG

local TRUSTED_BAG_CALLERS = { vhub_garage = true, vhub_custom = true }


-- clamp de stance: garante que valores antigos/extremos do DB não excedam os bounds da config.
-- Isso auto-corrige entradas persistidas antes do ajuste de bounds (evita clip carroceria/chão).
local function clampStance(stance)
  if type(stance) ~= 'table' then return false end
  local specs = (VHubCustom.cfg and VHubCustom.cfg.stance) or {}
  if not next(specs) then return stance end
  local out = {}
  for _, spec in ipairs(specs) do
    local v = math.floor(tonumber(stance[spec.key]) or 0)
    out[spec.key] = math.max(spec.min, math.min(spec.max, v))
  end
  return out
end


-- lê o estado visual da placa e espelha nos bags da entidade (replicado a todos os clientes)
local function hydrate(ent)
  if not ent or ent == 0 or not DoesEntityExist(ent) or GetEntityType(ent) ~= 2 then return false end
  local plate = U.normalizePlate(GetVehicleNumberPlateText(ent))
  if not plate then return false end

  local st   = Core.getVehicleState(plate)
  local cust = (st and type(st.customization) == 'table') and st.customization or {}

  -- clamp stance antes de setar o bag: valores do DB de sessões anteriores (bounds antigos)
  -- são sanitizados aqui, impedindo que extremos criem colisão de chassi → motor a 0.
  local stance     = clampStance(cust.stance)
  local exhaust    = (type(cust.exhaust_fx) == 'table') and cust.exhaust_fx or false
  local drift_cap  = cust.drift_capable == true
  Entity(ent).state:set(BAG.STANCE,  stance,    true)
  Entity(ent).state:set(BAG.EXHAUST, exhaust,   true)
  Entity(ent).state:set(BAG.DRIFT,   drift_cap, true)
  return true
end


-- cliente pede reidratação passando SÓ o netId. O evento é aberto e read-only (só espelha a
-- verdade da placa), mas amplificável → defesas: (1) rate-limit por player; (2) o solicitante
-- precisa estar PERTO do veículo (anti-abuso de terceiro pedindo refresh de netId arbitrário).
RegisterNetEvent(E.REQUEST_VISUAL, function(netId)
  local src = source
  if not Core.rateOK(src, 'request_visual') then return end
  local nid = tonumber(netId); if not nid or nid <= 0 then return end
  local ent = NetworkGetEntityFromNetworkId(nid)
  if not ent or ent == 0 or not DoesEntityExist(ent) then return end
  local ped = GetPlayerPed(src); if not ped or ped == 0 then return end
  local pc, vc = GetEntityCoords(ped), GetEntityCoords(ent)
  local dx, dy, dz = pc.x - vc.x, pc.y - vc.y, pc.z - vc.z
  if (dx * dx + dy * dy + dz * dz) > 2500.0 then return end   -- >50 m: pedido não plausível
  hydrate(ent)
end)


-- export gated default-deny ESTRITO (caller nil também é bloqueado): garage/bennys após persistir.
exports('refreshVisualBag', function(netId)
  local caller = GetInvokingResource()
  if not caller or not TRUSTED_BAG_CALLERS[caller] then return false end
  local nid = tonumber(netId); if not nid or nid <= 0 then return false end
  return hydrate(NetworkGetEntityFromNetworkId(nid))
end)
