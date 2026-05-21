-- server/ipva.lua  imposto peri dico (IPVA)
-- Bloqueia spawn de ve culo com IPVA vencido (verifica  o em garage.lua).
-- Pagamento estende `ipva_paid_until` por `cfg.ipva_dias` dias.
---@diagnostic disable: undefined-global

local SQL  = VHubGarage.SQL
local Core = VHubGarage.Core
local U    = VHubGarage.U
local CFG  = VHubGarage.cfg
local E    = VHubGarage.E

RegisterNetEvent(E.ACT_IPVA_PAY)
AddEventHandler(E.ACT_IPVA_PAY, function(plate)
  local src = source
  local cid = Core:getCharId(src); if not cid then return end
  local p   = U.normalizePlate(plate); if not p then return end
  Citizen.CreateThread(function()
    local v = SQL:getVehicle(p); if not v then return end
    if v.char_id ~= cid then
      Core.notify(src, 'Voc  n o   o dono.'); return
    end
    local entry = VHubGarage.catalog[v.model] or {}
    local valor = math.max(50, math.floor((entry.preco or 0) * CFG.ipva_porcentagem))
    if not Core.pay(src, valor) then
      Core.notify(src, ('Saldo insuficiente. IPVA: R$ %d.'):format(valor))
      return
    end
    local base = math.max(os.time(), tonumber(v.ipva_paid_until) or 0)
    local until_ts = base + CFG.ipva_dias * 86400
    SQL:updateIpva(p, until_ts)
    Core:log(p, 'ipva_paid', cid, { valor = valor, until_ts = until_ts })
    Core.notify(src, ('IPVA pago. V lido at  %s.')
      :format(os.date('%d/%m/%Y', until_ts)))
  end)
end)
