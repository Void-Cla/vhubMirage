-- server/rental.lua  aluguel de ve culos da concession ria
-- Aluguel cria um registro vhub_vehicles status='rental' + chave kind='rental'.
-- Ao expirar, o ve culo   automaticamente removido (e a chave revogada).
---@diagnostic disable: undefined-global

local SQL  = VHubGarage.SQL
local Core = VHubGarage.Core
local U    = VHubGarage.U
local CFG  = VHubGarage.cfg
local E    = VHubGarage.E

-- decisao #25: concessionaria resolvida pelo resolver unico do Core (config no
-- vhub_conce, lida do cache do PULL) — sem copia local de getConc.

RegisterNetEvent(E.ACT_RENT)
AddEventHandler(E.ACT_RENT, function(model, conc_id, horas)
  local src = source
  local cid = Core:getCharId(src); if not cid then return end
  local entry = VHubGarage.catalog[model]; if not entry then return end
  local conc  = Core:resolveConc(conc_id); if not conc then return end
  horas = tonumber(horas) or CFG.aluguel_periodo_h
  if horas < 1 then horas = 1 elseif horas > 168 then horas = 168 end

  -- valida tipo
  local ok = false
  for _, t in ipairs(conc.tipos) do if t == entry.tipo then ok = true; break end end
  if not ok then return end

  Citizen.CreateThread(function()
    local total = math.floor(entry.preco * CFG.fator_aluguel * (horas / CFG.aluguel_periodo_h))
    if not Core.pay(src, total) then
      Core.notify(src, ('Saldo insuficiente. Aluguel: R$ %d.'):format(total))
      return
    end

    local plate = Core:newPlate(nil)
    if not Core.giveKeyItem(src, plate) then
      Core.refund(src, total)
      Core.notify(src, 'Invent rio cheio. Aluguel cancelado.')
      return
    end

    local now = os.time()
    local rented_until = now + horas * 3600
    -- Aluguel: status normal 'garage' (igual aos demais). O que marca
    -- como aluguel   o campo `rented_until` (consultado pelo cron de expira  o).
    -- Isso permite spawnar/guardar normalmente; chave   kind='rental'.
    SQL:createVehicle({
      plate = plate, model = model, vtype = entry.tipo,
      category = entry.categoria, char_id = cid,
      status = 'garage',
      customization = U.jenc({ model = model }),
      locked = false,
      purchase_price = 0, purchase_at = now,
      rented_until = rented_until,
      last_seen_at = now,
    })
    SQL:grantKey(plate, cid, 'rental', cid, rented_until)
    Core:log(plate, 'rent_new', cid, { model = model, horas = horas, total = total })
    Core.notify(src, ('Aluguel ativo at  %s. Chave no invent rio.')
      :format(os.date('%H:%M %d/%m', rented_until)))
  end)
end)

-- ----------------------------------------------------------------------------
-- CRON: aluguel expirando (1x por minuto)
-- Identifica  o por `rented_until` (n o por status, que pode ser garage/out).
-- ----------------------------------------------------------------------------
Citizen.CreateThread(function()
  while true do
    Citizen.Wait(60 * 1000)
    local now = os.time()
    local rows = SQL.query([[
      SELECT plate, char_id FROM vhub_vehicles
       WHERE rented_until IS NOT NULL AND rented_until <= ?
    ]], { now }) or {}
    for _, r in ipairs(rows) do
      -- tira chave-item se dono online + despawna em todos os clientes
      for src, u in pairs(Core.sessions) do
        if u.char_id == r.char_id then Core.takeKeyItem(src, r.plate); break end
      end
      TriggerClientEvent(E.DO_DESPAWN, -1, r.plate)
      SQL:revokeKey(r.plate, r.char_id, 'rental')
      -- prontu rio morre junto no deleteVehicle  nada a persistir antes
      SQL:deleteVehicle(r.plate)
      Core:log(r.plate, 'rent_expired', r.char_id, {})
    end
  end
end)
