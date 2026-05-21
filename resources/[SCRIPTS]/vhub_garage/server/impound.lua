-- server/impound.lua  p tio (apreens o de ve culos + libera  o)
-- Acesso de apreens o: somente quem tem `CFG.perms.impound_admin`.
-- Ve culo apreendido fica status='impound'; chave fica com o dono mas spawn   bloqueado.
---@diagnostic disable: undefined-global

local SQL  = VHubGarage.SQL
local Core = VHubGarage.Core
local U    = VHubGarage.U
local CFG  = VHubGarage.cfg
local E    = VHubGarage.E

-- ----------------------------------------------------------------------------
-- LIST: REQ_IMPOUND
-- ----------------------------------------------------------------------------
RegisterNetEvent(E.REQ_IMPOUND)
AddEventHandler(E.REQ_IMPOUND, function()
  local src = source
  local cid = Core:getCharId(src); if not cid then return end
  Citizen.CreateThread(function()
    -- jogador comum: s  seus ve culos no p tio
    -- admin: lista completa
    local rows
    if Core.hasPerm(src, CFG.perms.impound_admin) then
      rows = SQL:impoundList() or {}
    else
      local mine = SQL:listByStatus('impound') or {}
      rows = {}
      for _, v in ipairs(mine) do
        if v.char_id == cid then
          local imp = SQL:impoundGetActive(v.plate)
          if imp then rows[#rows+1] = {
            plate = v.plate, model = v.model, vtype = v.vtype,
            reason = imp.reason, fee = imp.fee,
            impounded_at = imp.impounded_at,
          } end
        end
      end
    end
    TriggerClientEvent(E.OPEN_UI, src, {
      view = VHubGarage.UI.OPEN_IMPOUND,
      payload = {
        items = rows,
        admin = Core.hasPerm(src, CFG.perms.impound_admin),
        cfg = { taxa_base = CFG.patio_taxa, taxa_porc = CFG.patio_taxa_porcent },
      },
    })
  end)
end)

-- ----------------------------------------------------------------------------
-- PUT (admin/police): coloca ve culo no p tio
-- ----------------------------------------------------------------------------
RegisterNetEvent(E.ACT_IMPOUND_PUT)
AddEventHandler(E.ACT_IMPOUND_PUT, function(plate, reason, fee_extra)
  local src = source
  if not Core.hasPerm(src, CFG.perms.impound_admin) then
    Core.notify(src, 'Sem autoriza  o.'); return
  end
  local p = U.normalizePlate(plate); if not p then return end
  Citizen.CreateThread(function()
    local v = SQL:getVehicle(p); if not v then
      Core.notify(src, 'Ve culo n o registrado.'); return
    end
    if v.status == 'impound' then
      Core.notify(src, 'Ve culo j  est  no p tio.'); return
    end
    local entry = VHubGarage.catalog[v.model] or {}
    local preco = entry.preco or 0
    local fee   = CFG.patio_taxa + math.floor(preco * CFG.patio_taxa_porcent)
    if fee_extra and tonumber(fee_extra) and tonumber(fee_extra) > 0 then
      fee = fee + math.floor(tonumber(fee_extra))
    end
    SQL:updateStatus(p, 'impound')
    SQL:impoundPut(p, reason or 'apreendido', fee, Core:getCharId(src))
    Core:log(p, 'impound_put', Core:getCharId(src), { reason = reason, fee = fee })
    -- despawna se est  out
    TriggerClientEvent(E.DO_DESPAWN, -1, p)
    Core.notify(src, ('%s enviado ao p tio (R$ %d).'):format(p, fee))
  end)
end)

-- ----------------------------------------------------------------------------
-- PAY (jogador paga libera  o)
-- ----------------------------------------------------------------------------
RegisterNetEvent(E.ACT_IMPOUND_PAY)
AddEventHandler(E.ACT_IMPOUND_PAY, function(plate)
  local src = source
  local cid = Core:getCharId(src); if not cid then return end
  local p   = U.normalizePlate(plate); if not p then return end
  Citizen.CreateThread(function()
    local v = SQL:getVehicle(p); if not v then return end
    if v.char_id ~= cid then
      Core.notify(src, 'Voc  n o   o dono.'); return
    end
    if v.status ~= 'impound' then
      Core.notify(src, 'Ve culo n o est  apreendido.'); return
    end
    local imp = SQL:impoundGetActive(p)
    if not imp then return end
    if not Core.pay(src, imp.fee) then
      Core.notify(src, ('Saldo insuficiente. Taxa: R$ %d.'):format(imp.fee))
      return
    end
    SQL:impoundRelease(imp.id, cid)
    SQL:updateStatus(p, 'garage')
    Core:log(p, 'impound_release', cid, { id = imp.id, fee = imp.fee })
    Core.notify(src, ('Ve culo %s liberado.'):format(p))
    TriggerClientEvent(E.RESCUE_DONE, src, p)
  end)
end)

-- ----------------------------------------------------------------------------
-- Export: outros resources (police, eventos) podem apreender via export
-- ----------------------------------------------------------------------------
exports('impoundVehicle', function(plate, reason, fee_extra)
  local p = U.normalizePlate(plate); if not p then return false end
  Citizen.CreateThread(function()
    local v = SQL:getVehicle(p); if not v then return end
    if v.status == 'impound' then return end
    local entry = VHubGarage.catalog[v.model] or {}
    local fee   = CFG.patio_taxa + math.floor((entry.preco or 0) * CFG.patio_taxa_porcent)
    if fee_extra and tonumber(fee_extra) then
      fee = fee + math.floor(tonumber(fee_extra))
    end
    SQL:updateStatus(p, 'impound')
    SQL:impoundPut(p, reason or 'apreendido', fee, nil)
    Core:log(p, 'impound_put_api', nil, { reason = reason, fee = fee })
    TriggerClientEvent(E.DO_DESPAWN, -1, p)
  end)
  return true
end)
