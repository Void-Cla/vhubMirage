-- server/skill.lua — engine de skill: redistribuição de pontos (server-authoritative)
--
-- ÚNICO ponto de escrita do alloc (customization.handling). As DUAS portas — caixa de
-- ferramentas (perto do veículo) e mecânico (oficina) — caem AQUI. Zero lógica duplicada,
-- zero competição: a oficina NÃO escreve alloc, ela CHAMA esta função (decisão #27).
--
-- Fluxo: valida payload → canOperate → resolve budget → validateAlloc (invariante) →
--        cobra a porta (item OU dinheiro) → persiste via conce → devolve ficha nova.
---@diagnostic disable: undefined-global, lowercase-global

local TR = VHubVeh.TR
local E  = VHubVeh.E


-- ============================================================
-- CONFIG (custos das portas)
-- ============================================================

local TOOLBOX_ITEM   = 'caixadeferramentas'   -- consumido na porta "caixa de ferramentas"
local OFICINA_PRICE  = 2500                    -- cobrado na porta "mecânico/oficina"
local RATE_WINDOW_MS = 5000                    -- anti-spam por jogador


-- ============================================================
-- HELPERS (sessão / rate / cobrança — reuso dos exports existentes)
-- ============================================================

local _rate = {}   -- [src] = lastMs

-- true se dentro do limite de tempo (anti-spam de recalibração)
local function rateOK(src)
  local now = GetGameTimer()
  if _rate[src] and (now - _rate[src]) < RATE_WINDOW_MS then return false end
  _rate[src] = now
  return true
end

-- autoridade: chave-item + dono via conce (prova o PLAYER, não só o resource)
local function canOperate(src, plate)
  local ok = false
  pcall(function() ok = exports.vhub_conce:canOperate(src, plate) == true end)
  return ok
end

-- cobra dinheiro (carteira→banco); true se ok
local function payMoney(src, amount)
  if amount <= 0 then return true end
  local ok = false
  pcall(function() ok = exports.vhub_money:tryFullPayment(src, amount) == true end)
  return ok
end

-- consome 1 unidade do item; true se tinha e removeu
local function consumeItem(src, id)
  local has = false
  pcall(function() has = exports.vhub_inventory:hasItem(src, id, 1) == true end)
  if not has then return false end
  local ok = false
  pcall(function() ok = exports.vhub_inventory:takeItem(src, id, 1) == true end)
  return ok
end

-- ============================================================
-- HANDLER ÚNICO DE RECALIBRAÇÃO (as 2 portas caem aqui)
-- ============================================================

-- alloc: { potencia, grip, frenagem, aero, suspensao } (escolha do jogador)
-- origin: 'toolbox' (consome item) | 'oficina' (cobra dinheiro)
RegisterNetEvent(E.RECALIBRATE)
AddEventHandler(E.RECALIBRATE, function(plate, alloc, origin)
  local src = source

  -- responde sempre (fecha/atualiza a UI) — msg/kind viajam no MESMO evento (sem
  -- canal de notify paralelo: o client decide como exibir, RECAL_DONE é a única verdade)
  local function reply(ok, msg, kind)
    TriggerClientEvent(E.RECAL_DONE, src, ok == true, tostring(msg or ''),
      kind or (ok and 'success' or 'error'), ok and VHubVeh.sheetOf(plate) or nil)
  end

  Citizen.CreateThread(function()
    -- 1. rate + shape
    if not rateOK(src) then return reply(false, 'Aguarde um instante.') end
    if type(alloc) ~= 'table' then return reply(false, 'Dados inválidos.') end

    local p = plate and tostring(plate):upper():gsub('%s+', ' '):match('^%s*(.-)%s*$') or ''
    if p == '' then return reply(false, 'Placa inválida.') end

    -- 2. autorização (prova o player dono/chave)
    if not canOperate(src, p) then return reply(false, 'Sem autorização para este veículo.') end

    -- 3. resolve identidade + budget (carro sem p1 não tem skill)
    local base = VHubVeh.p1Byplate(p)
    if not base then return reply(false, 'Este veículo não suporta calibração.') end

    local st
    pcall(function() st = exports.vhub_conce:getVehicleState(p) end)
    local cust   = (st and type(st.customization) == 'table') and st.customization or {}
    local budget = TR.budgetOf(base, cust.mods, cust.turbo)
    if not budget then return reply(false, 'Falha ao calcular o limite de pontos.') end

    -- 4. valida invariante (Σ == budget, cada eixo dentro da faixa anti-P2W)
    local valid, why = TR.validateAlloc(alloc, budget)
    if not valid then return reply(false, 'Distribuição inválida (' .. tostring(why) .. ').') end

    -- 5. cobra a porta (item OU dinheiro), conforme a origem
    if origin == 'oficina' then
      if not payMoney(src, OFICINA_PRICE) then
        return reply(false, ('Saldo insuficiente. Custo: R$ %d.'):format(OFICINA_PRICE))
      end
    else
      if not consumeItem(src, TOOLBOX_ITEM) then
        return reply(false, 'Você precisa de uma Caixa de Ferramentas.')
      end
    end

    -- 6. persiste o alloc (escritor único = conce; source='handling')
    local saved = false
    pcall(function()
      saved = exports.vhub_conce:saveVehicleState(p, { customization = { handling = alloc } }, 'handling') == true
    end)
    if not saved then return reply(false, 'Erro ao salvar a calibração.') end

    reply(true, 'Veículo recalibrado!')
  end)
end)
