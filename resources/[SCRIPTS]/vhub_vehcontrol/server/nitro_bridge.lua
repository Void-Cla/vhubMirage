---@diagnostic disable: undefined-global, lowercase-global

-- server/nitro_bridge.lua — PONTE de nitro: ficha → vhub_nitro (decisão #30)
--
-- O vehcontrol NÃO é dono do nitro. A ficha recebe a intenção do jogador (ligar/desligar,
-- nível, abastecer) e DELEGA ao escritor único `vhub_nitro` via seus exports TRUSTED. Toda
-- autoridade (canOperate), gate (kit) e clamp (1..10) vivem LÁ — aqui é só call + reply.
-- A placa vem do cliente; o export re-prova o player dono/chave, então é seguro (zero-trust).

local E = VHubVeh.E


-- ============================================================
-- HELPERS
-- ============================================================

-- normaliza a placa (espelha conce/vhub_nitro) — defensivo contra payload do cliente
local function normPlate(p)
  local s = tostring(p or ''):upper():gsub('%s+', ' ')
  return s:match('^%s*(.-)%s*$') or ''
end

-- devolve ao cliente: (ok, msg, nitro novo) — o client decide como exibir; refaz a ficha.
-- nitro novo vem do getNitro (fonte única) p/ a UI nunca recachear estado por conta própria.
local function reply(src, plate, ok, msg)
  local nitro
  pcall(function() nitro = exports.vhub_nitro:getNitro(plate) end)
  TriggerClientEvent(E.NITRO_DONE, src, ok == true, tostring(msg or ''),
    (type(nitro) == 'table') and nitro or nil)
end


-- ============================================================
-- HANDLERS (ficha → export do escritor único)
-- ============================================================

-- liga/desliga o nitro
RegisterNetEvent(E.NITRO_TOGGLE)
AddEventHandler(E.NITRO_TOGGLE, function(plate, on)
  local src = source
  local p = normPlate(plate); if p == '' then return reply(src, p, false, 'Placa inválida.') end
  local ok = false
  pcall(function() ok = exports.vhub_nitro:setEnabled(src, p, on == true) == true end)
  reply(src, p, ok, ok and (on and 'Nitro ligado.' or 'Nitro desligado.')
        or 'Não foi possível alterar o nitro (precisa do kit instalado).')
end)

-- ajusta o nível 1..10
RegisterNetEvent(E.NITRO_LEVEL)
AddEventHandler(E.NITRO_LEVEL, function(plate, level)
  local src = source
  local p = normPlate(plate); if p == '' then return reply(src, p, false, 'Placa inválida.') end
  local ok = false
  pcall(function() ok = exports.vhub_nitro:setLevel(src, p, level) == true end)
  reply(src, p, ok, ok and 'Nível do nitro ajustado.'
        or 'Não foi possível ajustar o nível (precisa do kit instalado).')
end)

-- abastece (consome 1 Garrafa de Nitro via o escritor único; estorno é tratado lá)
RegisterNetEvent(E.NITRO_CHARGE)
AddEventHandler(E.NITRO_CHARGE, function(plate)
  local src = source
  local p = normPlate(plate); if p == '' then return reply(src, p, false, 'Placa inválida.') end
  local ok = false
  pcall(function() ok = exports.vhub_nitro:chargeFromItem(src, p) == true end)
  reply(src, p, ok, ok and 'Nitro abastecido!'
        or 'Não foi possível abastecer (sem kit, já cheio, ou sem Garrafa de Nitro).')
end)
