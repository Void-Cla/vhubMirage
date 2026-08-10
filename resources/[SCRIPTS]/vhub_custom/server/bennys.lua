-- server/bennys.lua — estética validada, cobrada e persistida pelo servidor
---@diagnostic disable: undefined-global

local Core = VHubCustom.Core
local CFG  = VHubCustom.cfg
local U    = VHubCustom.U
local E    = VHubCustom.E

local function rgb(value)
  if type(value) ~= 'table' then return nil end
  local r, g, b = U.integer(value[1], 0, 255), U.integer(value[2], 0, 255), U.integer(value[3], 0, 255)
  return r and g and b and { r, g, b } or nil
end

local function pair(value, lo, hi)
  if type(value) ~= 'table' then return nil end
  local a, b = U.integer(value[1], lo, hi), U.integer(value[2], lo, hi)
  return a and b and { a, b } or nil
end

local function neonFlags(value)
  if type(value) ~= 'table' then return nil end
  for i = 1, 4 do if type(value[i]) ~= 'boolean' then return nil end end
  return { [0] = value[1], [1] = value[2], [2] = value[3], [3] = value[4] }
end

local function buildPatch(payload)
  if type(payload) ~= 'table' then return nil end
  local patch = {}
  if payload.colours ~= nil then patch.colours = pair(payload.colours, 0, 222) end
  if payload.extra_colours ~= nil then patch.extra_colours = pair(payload.extra_colours, 0, 222) end
  -- custom RGB: tabela {r,g,b} aplica; `false` explícito LIMPA (volta ao índice de paleta)
  if payload.custom_primary ~= nil then
    patch.custom_primary = (payload.custom_primary == false) and false or rgb(payload.custom_primary)
  end
  if payload.custom_secondary ~= nil then
    patch.custom_secondary = (payload.custom_secondary == false) and false or rgb(payload.custom_secondary)
  end
  if payload.tyre_smoke_color ~= nil then patch.tyre_smoke_color = rgb(payload.tyre_smoke_color) end
  if payload.neon_colour ~= nil then patch.neon_colour = rgb(payload.neon_colour) end
  if payload.neons ~= nil then patch.neons = neonFlags(payload.neons) end

  if type(payload.smoke) == 'boolean' then patch.smoke = payload.smoke end
  if type(payload.xenon) == 'boolean' then patch.xenon = payload.xenon end
  if payload.xenon_color ~= nil then patch.xenon_color = U.integer(payload.xenon_color, -1, 12) end
  if payload.window_tint ~= nil then patch.window_tint = U.integer(payload.window_tint, 0, 6) end
  if payload.interior_color  ~= nil then patch.interior_color  = U.integer(payload.interior_color, 0, 160) end
  if payload.dashboard_color ~= nil then patch.dashboard_color = U.integer(payload.dashboard_color, 0, 160) end
  if payload.livery ~= nil then patch.livery = U.integer(payload.livery, -1, 255) end
  if payload.plate_index ~= nil then patch.plate_index = U.integer(payload.plate_index, 0, 5) end
  if payload.wheel_type ~= nil then patch.wheel_type = U.integer(payload.wheel_type, 0, 12) end

  if type(payload.mods) == 'table' then
    local mods = U.sanitizeMods(payload.mods, CFG.cosmetic_mods, 255)
    if mods then
      for index in pairs(CFG.performance_mods) do mods[index] = nil end
      if next(mods) then patch.mods = mods end
    end
  end

  -- extras do modelo (acessórios visíveis — toggle por índice)
  if type(payload.extras) == 'table' then
    local extras, max = {}, CFG.extras_max or 14
    for k, v in pairs(payload.extras) do
      local idx = tonumber(k)
      if idx and idx >= 0 and idx < max and type(v) == 'boolean' then
        extras[tostring(idx)] = v
      end
    end
    if next(extras) then patch.extras = extras end
  end

  -- fogo no escapamento {enabled, r, g, b, scale}
  if type(payload.exhaust_fx) == 'table' then
    local fx = payload.exhaust_fx
    if type(fx.enabled) == 'boolean' then
      if fx.enabled then
        local r = U.integer(fx.r, 0, 255)
        local g = U.integer(fx.g, 0, 255)
        local b = U.integer(fx.b, 0, 255)
        -- rejeita scale não-finito (NaN/Inf passam em type=='number' e escapam o clamp)
        local sc = (type(fx.scale) == 'number' and fx.scale == fx.scale and math.abs(fx.scale) ~= math.huge)
          and math.max(0.5, math.min(3.0, fx.scale)) or 1.0
        if r and g and b then
          patch.exhaust_fx = { enabled=true, r=r, g=g, b=b, scale=sc }
        end
      else
        patch.exhaust_fx = { enabled=false }
      end
    end
  end

  -- stance (rebaixamento visual): { r, tf, tr, sz, wd } — cada eixo é um notch inteiro dentro
  -- da banda declarada em CFG.stance. Ausente/ inválido = 0 (stock). Todos os 5 eixos entram
  -- no patch (zeros inclusos) p/ permitir voltar ao stock; custo 0 se nada mudou (alreadyApplied).
  if type(payload.stance) == 'table' then
    local out = {}
    for _, spec in ipairs(CFG.stance or {}) do
      out[spec.key] = U.integer(payload.stance[spec.key], spec.min, spec.max) or 0
    end
    patch.stance = out
  end

  -- blindagem de vidro RP (tier 0-3)
  if payload.glass_armor ~= nil then
    local max_tier = #(CFG.glass_armor_tiers or {}) - 1
    local tier = U.integer(payload.glass_armor, 0, max_tier >= 0 and max_tier or 3)
    if tier ~= nil then patch.glass_armor = tier end
  end

  return next(patch) and patch or nil
end

local function costOf(patch)
  local price, total = CFG.prices, 0
  if patch.colours then total = total + price.cor_primaria + price.cor_secundaria end
  if patch.custom_primary then total = total + price.cor_custom end
  if patch.custom_secondary then total = total + price.cor_custom end
  if patch.extra_colours then total = total + price.cor_perolado + price.cor_roda end
  if patch.neons then total = total + price.neon end
  if patch.neon_colour then total = total + price.neon_cor end
  if patch.smoke ~= nil then total = total + price.fumaca end
  if patch.tyre_smoke_color then total = total + price.fumaca_cor end
  if patch.xenon ~= nil then total = total + price.xenon end
  if patch.window_tint ~= nil then total = total + price.tint end
  if patch.interior_color  ~= nil then total = total + (price.interior_color or 500) end
  if patch.dashboard_color ~= nil then total = total + (price.dashboard_color or 500) end
  if patch.livery ~= nil then total = total + price.livery end
  if patch.plate_index ~= nil then total = total + price.plate_index end
  if patch.wheel_type ~= nil then total = total + price.wheel_type end
  if patch.mods then for _ in pairs(patch.mods) do total = total + price.mod_cosmetic end end
  if patch.extras then
    for _ in pairs(patch.extras) do total = total + (price.extras_toggle or 300) end
  end
  if patch.exhaust_fx and patch.exhaust_fx.enabled then
    total = total + (price.exhaust_fx or 800)
  end
  if patch.stance ~= nil then total = total + (price.stance or 800) end
  if patch.glass_armor ~= nil then
    local tbl = price.glass_armor
    total = total + (type(tbl) == 'table' and (tbl[patch.glass_armor] or 0) or 0)
  end
  return total
end

local function beforeOf(state, patch)
  local current = state and type(state.customization) == 'table' and state.customization or {}
  local before = {}
  for key in pairs(patch) do
    if key == 'mods' then
      local mods = type(current.mods) == 'table' and current.mods or {}
      before.mods = {}
      for index in pairs(patch.mods) do before.mods[index] = mods[index] or mods[tostring(index)] end
    else
      before[key] = current[key]
    end
  end
  return before
end

local function sameValue(current, expected, depth)
  if type(expected) ~= 'table' then
    if type(expected) == 'number' then return tonumber(current) == expected end
    return current == expected
  end
  if type(current) ~= 'table' or depth >= 3 then return false end
  for key, value in pairs(expected) do
    local actual = current[key]
    if actual == nil then actual = current[tostring(key)] end
    if not sameValue(actual, value, depth + 1) then return false end
  end
  return true
end

RegisterNetEvent(E.BENNYS_APPLY)
AddEventHandler(E.BENNYS_APPLY, function(leaseId, requestId, payload)
  local src = source
  if not Core.rateOK(src, 'bennys_apply') then
    Core.notify(src, 'Aguarde antes de aplicar outro item.', 'error')
    TriggerClientEvent(E.BENNYS_CONFIRM, src, nil, false, nil, nil); return
  end

  local context, lock, why = Core.beginMutation(src, 'bennys', leaseId)
  if not context then
    Core.notify(src, why == 'busy' and 'Veículo em outra operação.' or 'Sessão inválida.', 'error')
    TriggerClientEvent(E.BENNYS_CONFIRM, src, nil, false, nil, nil); return
  end
  local function finish(ok, patch)
    Core.releaseLock(src, context.plate, lock)
    TriggerClientEvent(E.BENNYS_CONFIRM, src, context.plate, ok == true, patch, context.net_id)
  end

  local patch = buildPatch(payload)
  if not patch then Core.notify(src, 'Seleção cosmética inválida.', 'error'); return finish(false) end
  local state = Core.getVehicleState(context.plate)
  if not state then Core.notify(src, 'Prontuário indisponível.', 'error'); return finish(false) end
  local current = type(state.customization) == 'table' and state.customization or {}
  local alreadyApplied = sameValue(current, patch, 0)
  local before, cost = beforeOf(state, patch), alreadyApplied and 0 or costOf(patch)
  local after = { customization = patch }

  local paid, operationId, paymentErr, replayed, charged, operation =
    Core.commitPayment(context, 'cosmetic', requestId, cost, patch,
      { customization = before }, after)
  if not paid then
    local msg = paymentErr == 'insufficient' and ('Saldo insuficiente. Custo: R$ %d.'):format(cost)
      or 'Falha ao processar pagamento.'
    Core.notify(src, msg, 'error'); return finish(false)
  end

  if replayed then
    Core.notify(src, 'Operação já concluída.', 'info')
    return finish(true)
  end
  cost = tonumber(operation and operation.amount) or cost
  if alreadyApplied then
    Core.completeOperation(operationId)
    Core.auditVehicle(context, 'cosmetic', operationId, before, patch, 'recovered_applied')
    Core.notify(src, 'Configuração já aplicada.', 'info')
    return finish(true)
  end

  if not Core.lockValid(context, lock) or not Core.refreshOperation(operationId) then
    local compensated, compensation = Core.compensatePayment(operationId, replayed, charged)
    Core.auditVehicle(context, 'cosmetic', operationId, before, patch, 'lease_lost_' .. compensation)
    Core.notify(src, compensated and 'Sessão encerrada. Valor estornado.'
      or 'Falha crítica. Operação em reconciliação.', 'error')
    return finish(false)
  end

  if not Core.saveVehicleState(context.plate, { customization = patch }, 'cosmetic') then
    local compensated, compensation = Core.compensatePayment(operationId, replayed, charged)
    Core.auditVehicle(context, 'cosmetic', operationId, before, patch, 'save_failed_' .. compensation)
    Core.notify(src, compensated and 'Falha ao salvar. Valor estornado.'
      or 'Falha crítica. Operação em reconciliação.', 'error')
    return finish(false)
  end

  Core.completeOperation(operationId)
  Core.auditVehicle(context, 'cosmetic', operationId, before, patch, replayed and 'replayed' or 'committed')
  Core.log(context.plate, 'bennys_apply', context.char_id,
    { cost = cost, operation_id = operationId, replayed = replayed == true })

  -- stance/escapamento mudaram → reidrata os State Bags da entidade a partir da placa
  -- (server/visual.lua). Espelha p/ TODOS os clientes que veem o carro (não só o motorista).
  if patch.stance ~= nil or patch.exhaust_fx ~= nil then
    pcall(function() exports.vhub_custom:refreshVisualBag(context.net_id) end)
  end

  Core.notify(src, ('Estética aplicada! R$ %d cobrados.'):format(cost), 'success')
  finish(true, patch)
end)
