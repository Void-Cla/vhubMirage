-- server/maintenance.lua  reparo na garagem + recep  o de report do cliente
-- KM/dano/fuel vivem no PRONTU RIO (vhub_vehicle_state, escritor  nico = conce).
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
    -- payload do cliente e hostil → whitelist de chaves + cap de tamanho
    local cust = U.sanitizeCustomization(payload.customization)
    if cust then
      SQL:updateCustomization(p, U.jenc(cust), payload.locked == true)
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

    -- sa de REAL persistida no prontu rio (a leitura antiga via export do CORE
    -- devolvia uma C PIA serializada, quase sempre nil  custo de reparo errado)
    local st
    pcall(function() st = exports.vhub_conce:getVehicleState(p) end)

    local eng  = (st and st.engine_health) or 1000
    local body = (st and st.body_health)   or 1000
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

    -- reparo TRUSTED no prontu rio (eleva health + limpa dano) e conserta a
    -- entidade VIVA no client (a vers o antiga mutava c pia = no-op real)
    pcall(function() exports.vhub_conce:repairVehicleState(p) end)
    TriggerClientEvent(E.DO_REPAIR, src, p)
    Core:log(p, 'repair', cid, { custo = custo, dmg_eng = dmg_eng, dmg_body = dmg_body })
    Core.notify(src, ('Ve culo reparado. R$ %d cobrados.'):format(custo))
  end)
end)
