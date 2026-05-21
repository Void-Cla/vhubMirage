-- server/maintenance.lua  reparo na garagem + recep  o de report do cliente
-- KM/dano/fuel s o gerenciados pelo CORE do vHub (vHub.Vehicle).
-- Aqui recebemos delta de customization/posi  o (n o-cr ticos) e oferecemos reparo pago.
---@diagnostic disable: undefined-global

local SQL  = VHubGarage.SQL
local Core = VHubGarage.Core
local U    = VHubGarage.U
local CFG  = VHubGarage.cfg
local E    = VHubGarage.E

-- ----------------------------------------------------------------------------
-- REPORT do cliente (apenas dados N O cr ticos: posi  o, customization, locked)
-- Cr ticos (fuel/odometer/health) fluem pelo CORE.
-- ----------------------------------------------------------------------------
RegisterNetEvent(E.REPORT_STATE)
AddEventHandler(E.REPORT_STATE, function(plate, payload)
  local src = source
  local cid = Core:getCharId(src); if not cid then return end
  local p   = U.normalizePlate(plate); if not p then return end
  if type(payload) ~= 'table' then return end
  Citizen.CreateThread(function()
    local v = SQL:getVehicle(p); if not v then return end
    -- s  driver autoriza  o (proxy: tem chave-item)
    if not Core.hasKeyItem(src, p) then return end

    if type(payload.position) == 'table' and U.validCoords(payload.position) then
      SQL:updatePosition(p, U.jenc({
        x = payload.position.x, y = payload.position.y, z = payload.position.z,
        h = tonumber(payload.position.h) or 0.0,
      }))
    end
    if type(payload.customization) == 'table' then
      SQL:updateCustomization(p, U.jenc(payload.customization), payload.locked == true)
    end
  end)
end)

-- ----------------------------------------------------------------------------
-- REPAIR (reparo na garagem)
-- O custo   calculado a partir do `state` no core: engine_health + body_health.
-- ----------------------------------------------------------------------------
RegisterNetEvent(E.ACT_REPAIR)
AddEventHandler(E.ACT_REPAIR, function(plate)
  local src = source
  local cid = Core:getCharId(src); if not cid then return end
  local p   = U.normalizePlate(plate); if not p then return end
  Citizen.CreateThread(function()
    local v = SQL:getVehicle(p); if not v then return end
    if not Core:authorized(src, p) then
      Core.notify(src, 'Sem autoriza  o.'); return
    end

    -- state do core (pode estar nil em VRAM); usa export getVehicle do core
    local core_vd
    local ok, vd = pcall(function() return exports.vhub:getVehicle(p) end)
    if ok then core_vd = vd end

    local eng  = (core_vd and core_vd.state and core_vd.state.engine_health) or 1000
    local body = (core_vd and core_vd.state and core_vd.state.body_health)   or 1000
    local dmg_eng  = math.max(0, 1000 - eng)
    local dmg_body = math.max(0, 1000 - body)
    local entry = VHubGarage.catalog[v.model] or {}
    local preco = entry.preco or 0
    local custo = math.floor(preco * (dmg_eng * CFG.reparo_taxa_engine
                                   + dmg_body * CFG.reparo_taxa_body))
    if custo <= 0 then
      Core.notify(src, 'Ve culo sem danos a reparar.'); return
    end
    if not Core.pay(src, custo) then
      Core.notify(src, ('Saldo insuficiente. Reparo: R$ %d.'):format(custo)); return
    end

    -- restaura health no core (state bag) via export se houver
    if core_vd and core_vd.state then
      core_vd.state.engine_health = 1000.0
      core_vd.state.body_health   = 1000.0
      core_vd.dirty = true
      pcall(function() core_vd:_syncBags() end)
    end
    Core:log(p, 'repair', cid, { custo = custo, dmg_eng = dmg_eng, dmg_body = dmg_body })
    Core.notify(src, ('Ve culo reparado. R$ %d cobrados.'):format(custo))
  end)
end)
