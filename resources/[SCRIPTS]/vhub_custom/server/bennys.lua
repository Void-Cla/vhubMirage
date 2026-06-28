-- server/bennys.lua — domínio estético: cor, neon, roda, kit visual (source='cosmetic')
-- Regra-mestre: servidor valida MOD_SPLIT, cobra e persiste. Cliente só previsualiza.
---@diagnostic disable: undefined-global

local Core = VHubCustom.Core
local CFG  = VHubCustom.cfg
local U    = VHubCustom.U
local E    = VHubCustom.E


-- ============================================================
-- HELPERS INTERNOS
-- ============================================================

-- calcula custo de cosmético por tipo de campo recebido no payload
local function calcCost(payload)
  local prices = CFG.prices
  local total  = 0

  if payload.colours     then total = total + prices.cor_primaria + prices.cor_secundaria end
  if payload.custom_primary   then total = total + prices.cor_custom end
  if payload.custom_secondary then total = total + prices.cor_custom end
  if payload.extra_colours then
    total = total + prices.cor_perolado + prices.cor_roda
  end
  if payload.neons       then total = total + prices.neon end
  if payload.neon_colour then total = total + prices.neon_cor end
  if payload.smoke       then total = total + prices.fumaca end
  if payload.tyre_smoke_color then total = total + prices.fumaca_cor end
  if payload.xenon       then total = total + prices.xenon end
  if payload.window_tint then total = total + prices.tint end
  if payload.livery      then total = total + prices.livery end
  if payload.plate_index then total = total + prices.plate_index end
  if payload.wheel_type  then total = total + prices.wheel_type end
  if payload.mods then
    for _ in pairs(payload.mods) do total = total + prices.mod_cosmetic end
  end

  return total
end

-- monta patch de customization só com chaves cosméticas válidas
-- rejeita qualquer mod com índice em performance_mods (MOD_SPLIT server-side)
local function buildCosmeticPatch(payload)
  local perf = CFG.performance_mods
  local cos  = CFG.cosmetic_mods
  local patch = {}

  -- cores
  if type(payload.colours) == 'table' then
    patch.colours = {
      tonumber(payload.colours[1]) or 0,
      tonumber(payload.colours[2]) or 0,
    }
  end
  if type(payload.extra_colours) == 'table' then
    patch.extra_colours = {
      tonumber(payload.extra_colours[1]) or 0,
      tonumber(payload.extra_colours[2]) or 0,
    }
  end
  -- pintura RGB exata (custom paint) — clampa 0..255 cada canal
  local function rgb255(t)
    return {
      U.clamp(tonumber(t[1]), 0, 255) or 255,
      U.clamp(tonumber(t[2]), 0, 255) or 255,
      U.clamp(tonumber(t[3]), 0, 255) or 255,
    }
  end
  if type(payload.custom_primary)   == 'table' then patch.custom_primary   = rgb255(payload.custom_primary)   end
  if type(payload.custom_secondary) == 'table' then patch.custom_secondary = rgb255(payload.custom_secondary) end
  if type(payload.tyre_smoke_color) == 'table' then patch.tyre_smoke_color = rgb255(payload.tyre_smoke_color) end
  if payload.xenon_color ~= nil then
    patch.xenon_color = U.clamp(tonumber(payload.xenon_color), 0, 12) or 0
  end
  -- neon flags — payload chega 1-indexado [esq,dir,frente,trás]; persistimos 0-indexado
  -- ([0..3]) para casar com o round-trip do garage (collect/applyCustomization usa 0-index),
  -- senão o neon some ao guardar/spawnar pela garagem (des-sync).
  if type(payload.neons) == 'table' then
    patch.neons = {
      [0] = payload.neons[1] == true, [1] = payload.neons[2] == true,
      [2] = payload.neons[3] == true, [3] = payload.neons[4] == true,
    }
  end
  -- neon colour {r,g,b}
  if type(payload.neon_colour) == 'table' then
    patch.neon_colour = {
      U.clamp(tonumber(payload.neon_colour[1]), 0, 255) or 255,
      U.clamp(tonumber(payload.neon_colour[2]), 0, 255) or 255,
      U.clamp(tonumber(payload.neon_colour[3]), 0, 255) or 255,
    }
  end
  -- toggles visuais (turbo NÃO entra aqui — é chave EXCLUSIVA da oficina, performance)
  if payload.smoke   ~= nil then patch.smoke   = payload.smoke   == true end
  if payload.xenon   ~= nil then patch.xenon   = payload.xenon   == true end

  if payload.window_tint ~= nil then
    patch.window_tint = U.clamp(tonumber(payload.window_tint), 0, 6) or 0
  end
  if payload.livery ~= nil then
    patch.livery = U.clamp(tonumber(payload.livery), -1, 30) or -1
  end
  if payload.plate_index ~= nil then
    patch.plate_index = U.clamp(tonumber(payload.plate_index), 0, 4) or 0
  end
  if payload.wheel_type ~= nil then
    patch.wheel_type = U.clamp(tonumber(payload.wheel_type), 0, 7) or 0
  end

  -- mods: filtra pela whitelist cosmética e rejeita performance
  -- maxLvl=60: kits cosméticos do GTA têm muitas opções (não cabe no cap 5 de performance)
  if type(payload.mods) == 'table' then
    local clean = U.sanitizeMods(payload.mods, cos, 60)
    if clean then
      -- defesa dupla: rejeita qualquer índice performance que escapou do sanitize
      for idx in pairs(perf) do clean[idx] = nil end
      if next(clean) then patch.mods = clean end
    end
  end

  return next(patch) ~= nil and patch or nil
end


-- ============================================================
-- HANDLER PRINCIPAL
-- ============================================================

RegisterNetEvent(E.BENNYS_APPLY)
AddEventHandler(E.BENNYS_APPLY, function(plate, payload)
  local src = source
  Citizen.CreateThread(function()
    -- 1. rate
    if not Core.rateOK(src, 'bennys_apply') then
      Core.notify(src, 'Aguarde antes de aplicar outro item.', 'error'); return
    end

    -- 2. sessão
    local cid = Core.getCharId(src)
    if not cid then return end

    -- 3. placa
    local p = U.normalizePlate(plate)
    if not p or not U.validPayload(payload) then return end

    -- 4. autorização (canOperate ANTES de qualquer leitura de estado)
    if not Core.canOperate(src, p) then
      Core.notify(src, 'Sem autorização para este veículo.', 'error'); return
    end

    -- 5. monta patch cosmético + rejeita performance
    local custPatch = buildCosmeticPatch(payload)
    if not custPatch then
      Core.notify(src, 'Nenhum item cosmético válido selecionado.', 'error'); return
    end

    -- 6. custo server-side
    local custo = calcCost(payload)
    if custo > 0 and not Core.pay(src, custo) then
      Core.notify(src, ('Saldo insuficiente. Custo: R$ %d.'):format(custo), 'error')
      TriggerClientEvent(E.BENNYS_CONFIRM, src, p, false)
      return
    end

    -- 7. persiste (source='cosmetic' — guard no vstate garante que só customization é escrito)
    local ok = Core.saveVehicleState(p, { customization = custPatch }, 'cosmetic')
    if not ok then
      Core.notify(src, 'Erro ao salvar. Tente novamente.', 'error')
      TriggerClientEvent(E.BENNYS_CONFIRM, src, p, false)
      return
    end

    -- 8. confirma no cliente (aplica definitivo no veículo vivo)
    Core.log(p, 'bennys_apply', cid, { custo = custo })
    TriggerClientEvent(E.BENNYS_CONFIRM, src, p, true, custPatch)
    Core.notify(src, ('Estética aplicada! R$ %d cobrados.'):format(custo), 'success')
  end)
end)
