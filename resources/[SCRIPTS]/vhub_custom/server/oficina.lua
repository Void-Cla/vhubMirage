-- server/oficina.lua — tuning de performance (stages 11/12/13/15/16/18, source='tune')
-- Cap de stage: por classe GTA (estático). Score/tier real vêm de vhub_vehcontrol (decisão #27) —
-- esta oficina NUNCA calcula score por conta própria, só compra stages e consulta a ficha.
-- INVARIANTE: todo caminho de retorno com src em menu dispara OFICINA_CONFIRM para fechar a NUI.
---@diagnostic disable: undefined-global

local Core = VHubCustom.Core
local CFG  = VHubCustom.cfg
local U    = VHubCustom.U
local E    = VHubCustom.E

-- índices de mods de performance e seus nomes PT-BR (para mensagens)
local PERF_NAMES = {
  [11] = 'Motor',      [12] = 'Freios',
  [13] = 'Câmbio',    [15] = 'Suspensão',
  [16] = 'Blindagem', [18] = 'Turbo',
}

-- custo por mod de performance (mapeia índice → chave de CFG.prices)
local PERF_PRICE_KEY = {
  [11] = 'engine_stage', [12] = 'brakes_stage',
  [13] = 'transmission_stage', [15] = 'suspension_stage',
  [16] = 'armor_stage',  [18] = 'turbo',
}


-- ============================================================
-- HELPERS
-- ============================================================

-- retorna o cap de stage para a classe do veículo (estático, sem carskill)
local function getStageCapStatic(veh_class)
  return CFG.stage_cap_by_class[veh_class] or CFG.stage_cap_default
end

-- calcula custo de um único mod de performance
local function calcModCost(mod_idx, level)
  local key = PERF_PRICE_KEY[mod_idx]
  if not key then return 0 end
  if mod_idx == 18 then
    return level >= 1 and CFG.prices.turbo or 0
  end
  local tbl = CFG.prices[key]
  if type(tbl) == 'table' then
    return tbl[level] or 0
  end
  return 0
end

-- ficha derivada real (tier/score/budget/alloc) — fonte única é vhub_vehcontrol (decisão #27)
local function vehSheet(plate)
  local ok, sheet = pcall(function() return exports.vhub_vehcontrol:getVehicleSheet(plate) end)
  return ok and sheet or nil
end


-- ============================================================
-- PRÉ-CHECAGEM DE ACESSO (antes de abrir o NUI)
-- Valida sessão + canOperate sem cobrar nem salvar nada.
-- Responde OFICINA_AUTH_OK(plate, ok, msg) ao cliente.
-- ============================================================

RegisterNetEvent(E.OFICINA_AUTH)
AddEventHandler(E.OFICINA_AUTH, function(plate)
  local src = source
  local cid = Core.getCharId(src)
  if not cid then
    TriggerClientEvent(E.OFICINA_AUTH_OK, src, plate, false, 'Personagem não carregado.')
    return
  end
  local p = U.normalizePlate(plate)
  if not p then
    TriggerClientEvent(E.OFICINA_AUTH_OK, src, plate, false, 'Placa inválida.')
    return
  end
  local ok = Core.canOperate(src, p)
  if not ok then
    TriggerClientEvent(E.OFICINA_AUTH_OK, src, plate, false,
      'Veículo não registrado no sistema ou sem chave no inventário.')
    return
  end
  -- ficha real (tier/score/budget/ranges) viaja JUNTO com a autorização: evita 2º
  -- round-trip e garante que a NUI nunca exiba número que o servidor não calculou (L-04)
  TriggerClientEvent(E.OFICINA_AUTH_OK, src, p, true, nil, vehSheet(p))
end)


-- ============================================================
-- PRÉVIA DE CALIBRAÇÃO (não persiste — só leitura via vhub_vehcontrol)
-- ============================================================

-- cliente arrasta slider → pede ficha hipotética com o alloc em rascunho;
-- mesma autorização de OFICINA_AUTH, zero escrita (decisão #27, export getVehicleSheetPreview)
RegisterNetEvent(E.OFICINA_PREVIEW)
AddEventHandler(E.OFICINA_PREVIEW, function(plate, draftAlloc)
  local src = source
  local p = U.normalizePlate(plate)
  if not p or type(draftAlloc) ~= 'table' or not Core.canOperate(src, p) then return end

  local ok, sheet = pcall(function()
    return exports.vhub_vehcontrol:getVehicleSheetPreview(p, draftAlloc)
  end)
  TriggerClientEvent(E.OFICINA_PREVIEW_OK, src, ok and sheet or nil)
end)


-- ============================================================
-- KIT NITRO (decisão #29) — a oficina COBRA; o vhub_nitro ESCREVE o estado na placa
-- (Doutrina da Placa: customization.nitro só é escrito por vhub_nitro via conce)
-- ============================================================

local NITRO_KIT_PRICE = 5000   -- preço do kit (a oficina é a vendedora; o estado mora no vhub_nitro)

RegisterNetEvent(E.OFICINA_NITRO_KIT)
AddEventHandler(E.OFICINA_NITRO_KIT, function(plate)
  local src = source
  local function reply(ok, msg) TriggerClientEvent(E.OFICINA_NITRO_KIT_OK, src, ok == true, msg or '') end

  if not Core.rateOK(src, 'oficina_nitro') then return reply(false, 'Aguarde um instante.') end
  local cid = Core.getCharId(src); if not cid then return reply(false, 'Personagem não carregado.') end
  local p = U.normalizePlate(plate); if not p then return reply(false, 'Placa inválida.') end
  if not Core.canOperate(src, p) then return reply(false, 'Sem autorização para este veículo.') end

  -- já tem kit? (lê a fonte única vhub_nitro) → não cobra
  local cur
  pcall(function() cur = exports.vhub_nitro:getNitro(p) end)
  if type(cur) == 'table' and cur.kit then return reply(false, 'Este veículo já tem kit de nitro.') end

  if not Core.pay(src, NITRO_KIT_PRICE) then
    return reply(false, ('Saldo insuficiente. Custo: R$ %d.'):format(NITRO_KIT_PRICE))
  end

  -- vhub_nitro é o ÚNICO escritor de customization.nitro (escreve via conce); a oficina só CHAMA
  local ok = false
  pcall(function() ok = exports.vhub_nitro:installKit(src, p) == true end)
  if not ok then
    pcall(function() exports.vhub_money:giveBank(src, NITRO_KIT_PRICE, 'estorno_kit_nitro') end)
    return reply(false, 'Falha ao instalar o kit. Valor estornado.')
  end

  Core.log(p, 'nitro_kit', cid, { price = NITRO_KIT_PRICE })
  reply(true, ('Kit de nitro instalado! R$ %d cobrados.'):format(NITRO_KIT_PRICE))
end)


-- ============================================================
-- HANDLER PRINCIPAL
-- ============================================================

RegisterNetEvent(E.OFICINA_TUNE)
AddEventHandler(E.OFICINA_TUNE, function(plate, proposed_mods, veh_class)
  local src = source

  -- helper: fecha NUI em qualquer saída antecipada (previne UI presa)
  local function bail(msg, lvl)
    if msg then Core.notify(src, msg, lvl or 'error') end
    TriggerClientEvent(E.OFICINA_CONFIRM, src, plate, false, nil)
  end

  Citizen.CreateThread(function()
    Core.dbg(src, '1/9 OFICINA_TUNE recebido')

    -- 1. rate
    if not Core.rateOK(src, 'oficina_tune') then
      bail('Aguarde antes de aplicar outro tuning.'); return
    end

    -- 2. sessão
    local cid = Core.getCharId(src)
    if not cid then
      VHubCustom.log('[oficina] bail: sem sessão para src=' .. tostring(src))
      bail('Personagem não carregado.'); return
    end
    Core.dbg(src, '2/9 sessão OK cid=' .. tostring(cid))

    -- 3. placa
    local p = U.normalizePlate(plate)
    if not p then
      VHubCustom.log('[oficina] bail: placa inválida raw=' .. tostring(plate))
      bail('Placa inválida.'); return
    end
    if type(proposed_mods) ~= 'table' then
      bail('Dados inválidos.'); return
    end
    Core.dbg(src, '3/9 placa=' .. p)

    -- 4. autorização (ANTES de qualquer leitura de estado)
    if not Core.canOperate(src, p) then
      VHubCustom.log('[oficina] bail: canOperate false | placa=' .. p .. ' cid=' .. tostring(cid))
      bail('Sem autorização para este veículo.'); return
    end
    Core.dbg(src, '4/9 canOperate OK')

    -- 5. classe GTA: usa o valor enviado pelo cliente mas clampa ao range válido
    local cls = U.clamp(tonumber(veh_class), 0, 20) or 0
    local cap  = getStageCapStatic(cls)

    if cap == 0 then
      bail('Este tipo de veículo não aceita tuning de performance.'); return
    end
    Core.dbg(src, '5/9 classe=' .. cls .. ' cap=' .. cap)

    -- 6. sanitiza mods: aceita APENAS índices performance dentro do cap
    local clean = U.sanitizeMods(proposed_mods, CFG.performance_mods)
    if not clean or not next(clean) then
      bail('Nenhum mod de performance válido informado.'); return
    end
    do
      local parts = {}
      for idx, lvl in pairs(clean) do parts[#parts+1] = (PERF_NAMES[idx] or idx) .. '=' .. lvl end
      Core.dbg(src, '6/9 mods: ' .. table.concat(parts, ', '))
    end

    -- valida nível de cada mod contra o cap
    local invalid = {}
    for idx, lvl in pairs(clean) do
      if lvl > cap then
        invalid[#invalid+1] = PERF_NAMES[idx]
        clean[idx] = cap   -- clampa silenciosamente ao cap
      end
    end
    if #invalid > 0 then
      Core.notify(src,
        ('Stage máximo para este veículo: %d. Ajustado: %s.'):format(cap, table.concat(invalid, ', ')),
        'warning')
    end

    -- 7. lê estado atual do prontuário para calcular delta de custo
    -- (cobramos apenas pelo UPGRADE — downgrade ou sem mudança é gratuito)
    -- CONVENÇÃO: o prontuário guarda mods em GTA-level (stock=-1) e turbo no campo
    -- booleano `turbo` (dono = garagem). Aqui convertemos para "stage" (stock=0) só
    -- para comparar com o `clean` do menu, que é stage.
    local st       = Core.getVehicleState(p)
    local cur_cust = (st and type(st.customization) == 'table') and st.customization or {}
    local cur_mods = (type(cur_cust.mods) == 'table') and cur_cust.mods or {}
    local cur_turbo = cur_cust.turbo == true

    -- nível atual em STAGE para o índice (turbo deriva do booleano; resto = GTA-level+1)
    local function curStage(idx)
      if idx == 18 then return cur_turbo and 1 or 0 end
      local gta = tonumber(cur_mods[idx]) or tonumber(cur_mods[tostring(idx)]) or -1
      return gta + 1
    end

    Core.dbg(src, '7/8 estado lido (st=' .. tostring(st ~= nil) .. ')')

    local custo = 0
    for idx, lvl in pairs(clean) do
      if lvl > curStage(idx) then
        custo = custo + calcModCost(idx, lvl)
      end
    end
    Core.dbg(src, '7/8 custo calculado: R$ ' .. custo)

    if custo > 0 and not Core.pay(src, custo) then
      Core.dbg(src, '7/8 PAGAMENTO FALHOU (tryFullPayment=false) — saldo?')
      bail(('Saldo insuficiente. Custo: R$ %d.'):format(custo)); return
    end
    Core.dbg(src, '7/8 pagamento OK (R$ ' .. custo .. ')')

    -- 8. converte STAGE → convenção da garagem ANTES de persistir:
    --    mods em GTA-level (stage-1; stock vira -1) e turbo no campo booleano `turbo`.
    --    Índice 18 NUNCA vai em `mods` (é toggle, dirigido pelo campo `turbo`).
    local gta_mods = {}
    for idx, stage in pairs(clean) do
      if idx ~= 18 then gta_mods[idx] = stage - 1 end
    end
    local patch_cust = { mods = gta_mods }
    if clean[18] ~= nil then patch_cust.turbo = clean[18] >= 1 end

    -- persiste (source='tune' — guard no vstate restringe a customization; merge por chave)
    local ok = Core.saveVehicleState(p, { customization = patch_cust }, 'tune')
    if not ok then
      Core.dbg(src, '8/8 saveVehicleState=FALSE — placa fora de vhub_vehicles? (carro de rua/test-drive não persiste)')
      bail('Erro ao salvar tuning. Tente novamente.'); return
    end
    Core.dbg(src, '8/8 saveVehicleState OK — PERSISTIU!')

    Core.log(p, 'oficina_tune', cid, { custo = custo, cls = cls, cap = cap })
    TriggerClientEvent(E.OFICINA_CONFIRM, src, p, true, clean)
    Core.notify(src, ('Tuning aplicado! R$ %d cobrados.'):format(custo), 'success')
  end)
end)
