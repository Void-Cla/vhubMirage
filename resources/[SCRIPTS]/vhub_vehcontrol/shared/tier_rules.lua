-- shared/tier_rules.lua — regras PURAS do engine de skill (server + client, ZERO I/O)
--
-- Fonte da verdade do CÁLCULO derivado do veículo (decisão #27). Tudo aqui é função pura:
-- mesma implementação usada pelo servidor (autoridade) e pelo cliente (preview da UI).
-- NUNCA toca natives, SQL, exports ou State Bag. Recebe dados, devolve números.
--
-- MODELO DE PONTOS (híbrido, decisão do dono):
--   budget_total = base_alloc do tier (natural) + Σ bônus das peças instaladas
--   cada peça dá pontos: METADE fixa no eixo natural dela, METADE livre p/ o jogador realocar
--   nos eixos semânticos permitidos da peça. O jogador calibra o "livre"; o servidor valida.
---@diagnostic disable: undefined-global, lowercase-global

VHubVeh        = VHubVeh or {}
local TR       = {}
VHubVeh.TR     = TR


-- ============================================================
-- CONSTANTES (eixos, budget por tier, faixas anti-P2W)
-- ============================================================

-- os 5 eixos de skill (ordem canônica — usada em iteração determinística)
TR.AXES = { 'potencia', 'grip', 'frenagem', 'aero', 'suspensao' }

-- budget de pontos por tier (teto base; peças somam por cima)
TR.BUDGET = { D=500, C=600, B=700, A=800, S=900, ['S+']=1000 }

-- ordem determinística de tiers (não depender de pairs)
TR.TIER_ORDER = { 'D', 'C', 'B', 'A', 'S', 'S+' }

-- faixa de score por tier (score derivado → tier exibido)
TR.TIER_SCORE = {
  D  = { min=0,   max=199  }, C  = { min=200, max=399 },
  B  = { min=400, max=599  }, A  = { min=600, max=749 },
  S  = { min=750, max=899  }, ['S+'] = { min=900, max=1000 },
}

-- faixa de alocação por eixo (% do budget) — anti-P2W: nada all-in num eixo só
TR.ALLOC_RANGE = {
  potencia  = { min=0.10, max=0.35 }, grip      = { min=0.08, max=0.35 },
  frenagem  = { min=0.08, max=0.30 }, aero      = { min=0.08, max=0.30 },
  suspensao = { min=0.08, max=0.28 },
}

-- pontos por peça (índice GTA) + eixo fixo (piso) + eixos livres (realocáveis)
-- metade dos pontos vai ao eixo fixo; metade vira "livre" nos eixos permitidos
TR.PART_POINTS = {
  [11] = { pontos=20, fixo='potencia',  livres={ 'potencia', 'aero' } },        -- motor
  [18] = { pontos=15, fixo='potencia',  livres={ 'potencia', 'grip' } },        -- turbo (torque↔aceleração)
  [12] = { pontos=12, fixo='frenagem',  livres={ 'frenagem', 'suspensao' } },   -- freio
  [13] = { pontos=10, fixo='potencia',  livres={ 'potencia', 'frenagem' } },    -- câmbio
  [15] = { pontos=10, fixo='suspensao', livres={ 'suspensao', 'grip' } },       -- suspensão
  [16] = { pontos=8,  fixo='suspensao', livres={ 'suspensao', 'frenagem' } },   -- blindagem
}

-- pesos do score (impacto competitivo real — espelha carskill §5.3)
local SCORE_W = { potencia=0.35, grip=0.30, frenagem=0.15, aero=0.10, suspensao=0.10 }


-- ============================================================
-- HELPERS PUROS
-- ============================================================

-- clamp numérico simples (sem rejeitar NaN — entrada já validada no ponto de uso)
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- clamp 0..1
local function c01(v) return clamp(v, 0, 1) end

-- soma os valores de uma tabela de alloc (só os eixos canônicos)
local function sumAlloc(alloc)
  local s = 0
  for _, ax in ipairs(TR.AXES) do s = s + (tonumber(alloc[ax]) or 0) end
  return s
end

-- faixa efetiva (% do budget) de um eixo: produção = anti-P2W (ALLOC_RANGE);
-- modo brute-test (Config.skillBruteTest) = 0..100% p/ permitir builds extremas de
-- validação. Tudo que valida/clampa/desenha slider passa por aqui (fonte única da faixa).
function TR.range(ax)
  if Config and Config.skillBruteTest then return { min = 0.0, max = 1.0 } end
  return TR.ALLOC_RANGE[ax] or { min = 0.0, max = 1.0 }
end


-- ============================================================
-- BUDGET (teto de pontos = tier natural + bônus das peças)
-- ============================================================

-- bônus de pontos das peças instaladas (lê customization.mods já persistido)
-- mods: { [idx]=gtaLevel } onde gtaLevel -1=stock, 0/1/2=stages; turbo vem do booleano
-- retorna { total, fixed={eixo=pts}, free=pts } — fixed já alocado; free a distribuir
function TR.partsBonus(mods, turbo)
  local fixed, free, total = {}, 0, 0
  for _, ax in ipairs(TR.AXES) do fixed[ax] = 0 end

  -- peça com level >= 0 (stage instalado) conta; turbo é o booleano separado
  local function addPart(def)
    if not def then return end
    local half = math.floor(def.pontos / 2)
    fixed[def.fixo] = (fixed[def.fixo] or 0) + half
    free  = free  + (def.pontos - half)
    total = total + def.pontos
  end

  if type(mods) == 'table' then
    for idx, lvl in pairs(mods) do
      local i = tonumber(idx)
      local level = tonumber(lvl) or -1
      if i and i ~= 18 and level >= 0 then addPart(TR.PART_POINTS[i]) end
    end
  end
  if turbo == true then addPart(TR.PART_POINTS[18]) end

  return { total = total, fixed = fixed, free = free }
end

-- teto total de pontos do veículo: base do tier + total das peças
function TR.budgetOf(base, mods, turbo)
  if type(base) ~= 'table' or not base.tier_base then return nil end
  local tierBudget = TR.BUDGET[base.tier_base]
  if not tierBudget then return nil end
  return tierBudget + TR.partsBonus(mods, turbo).total
end


-- ============================================================
-- SCORE e TIER (derivados do alloc)
-- ============================================================

-- mapeia uma quantidade de PONTOS (budget) para o score-âncora 0..1000, via a
-- correspondência BUDGET[tier] ↔ meio da faixa TIER_SCORE[tier]. Pontos entre dois
-- tiers interpolam linearmente. É o "chão" do score: define em qual tier o carro nasce.
local function budgetToScore(points)
  -- pares (pontos do tier, meio da faixa de score do tier), em ordem crescente
  local prevP, prevS
  for _, t in ipairs(TR.TIER_ORDER) do
    local p = TR.BUDGET[t]
    local r = TR.TIER_SCORE[t]
    local mid = (r.min + r.max) / 2
    if points <= p then
      if not prevP then return mid end                 -- abaixo do menor tier
      local f = (points - prevP) / (p - prevP)         -- interpola entre tiers
      return prevS + f * (mid - prevS)
    end
    prevP, prevS = p, mid
  end
  return prevS or 0                                     -- acima do maior tier (S+)
end

-- score 0..1000 do alloc: ÂNCORA no budget (tier + peças) + DELTA de distribuição.
-- Uma build competitiva (pontos em potencia/grip, eixos de maior peso) sobe o score;
-- uma build equilibrada fica no meio da faixa; off-meta desce um pouco. Por isso a
-- redistribuição mexe no tier — sem deixar um eixo só estourar a faixa (validado à parte).
function TR.scoreFromAlloc(alloc, budget)
  if type(alloc) ~= 'table' or not budget or budget <= 0 then return 0 end

  local anchor = budgetToScore(budget)

  -- qualidade da distribuição: média ponderada dos eixos vs. distribuição uniforme.
  -- weighted = Σ (fração do eixo × peso competitivo); uniforme = média dos pesos (=0.20).
  -- delta = (weighted - uniforme) escalado p/ ±metade de uma faixa (~75 pts).
  local weighted = 0
  for ax, w in pairs(SCORE_W) do
    weighted = weighted + ((tonumber(alloc[ax]) or 0) / budget) * w
  end
  local uniform = 0.20                                  -- 1/5 eixos × Σpesos(=1.0)
  local delta   = (weighted - uniform) * 750            -- ganho/perda por foco competitivo

  return math.floor(clamp(anchor + delta, 0, 1000))
end

-- score → tier key (determinístico, sem depender de pairs)
function TR.calcTier(score)
  for _, t in ipairs(TR.TIER_ORDER) do
    local r = TR.TIER_SCORE[t]
    if score >= r.min and score <= r.max then return t end
  end
  return 'D'
end

-- índice de um tier na ordem (p/ clamp ao teto)
local function tierIndex(t)
  for i, k in ipairs(TR.TIER_ORDER) do if k == t then return i end end
  return 1
end

-- limita o tier calculado ao teto do catálogo (anti-salto: nunca acima de tier_max)
function TR.clampTier(tier, tierMax)
  if not tierMax then return tier end
  if tierIndex(tier) > tierIndex(tierMax) then return tierMax end
  return tier
end


-- ============================================================
-- ALLOC DEFAULT e VALIDAÇÃO (invariante server-side)
-- ============================================================

-- alloc inicial do veículo: base_alloc natural + a metade FIXA das peças + a metade
-- LIVRE distribuída em ordem (TR.AXES), respeitando o teto de cada eixo e VAZANDO o
-- resto para o próximo — postura neutra até o jogador calibrar, mas SEMPRE dentro da
-- faixa anti-P2W (nunca empilha tudo livre num eixo só e estoura o cap, decisão #27).
function TR.defaultAlloc(base, mods, turbo, budget)
  local out = {}
  local ba = (type(base) == 'table' and base.base_alloc) or {}
  local bonus = TR.partsBonus(mods, turbo)
  for _, ax in ipairs(TR.AXES) do
    out[ax] = (tonumber(ba[ax]) or 0) + (bonus.fixed[ax] or 0)
  end

  local rest = bonus.free or 0
  if rest > 0 then
    for _, ax in ipairs(TR.AXES) do
      if rest <= 0 then break end
      local r  = TR.range(ax)
      local hi = budget and math.ceil(budget * r.max) or math.huge
      local room = math.max(0, hi - out[ax])
      local take  = math.min(rest, room)
      out[ax] = out[ax] + take
      rest    = rest - take
    end
    if rest > 0 then out[TR.AXES[#TR.AXES]] = out[TR.AXES[#TR.AXES]] + rest end
  end
  return out
end

-- faixa editável (slider) por eixo: piso = fixo (peças+tier) que NUNCA pode descer;
-- teto = min(ALLOC_RANGE.max, fixo + todo o livre disponível). UI usa para clampar.
-- floors somam ao chão de TODOS os eixos; o jogador só redistribui a fatia LIVRE.
function TR.freeRanges(base, mods, turbo, budget)
  local bonus = TR.partsBonus(mods, turbo)
  local ba    = (type(base) == 'table' and base.base_alloc) or {}
  local brute = (Config and Config.skillBruteTest) == true
  local out   = {}
  for _, ax in ipairs(TR.AXES) do
    local r = TR.range(ax)
    if brute then
      -- TESTE: o budget INTEIRO é redistribuível (sem piso de base/peças) — permite
      -- zerar um eixo e empilhar noutro p/ validar a física com discrepância máxima.
      out[ax] = { min = math.floor(budget * r.min), max = math.ceil(budget * r.max) }
    else
      -- produção: piso = base do tier + metade FIXA das peças; só a fatia LIVRE move.
      local floor = (tonumber(ba[ax]) or 0) + (bonus.fixed[ax] or 0)
      local hi    = budget and math.ceil(budget * r.max) or (floor + bonus.free)
      out[ax] = { min = floor, max = math.max(floor, math.min(hi, floor + bonus.free)) }
    end
  end
  return out, bonus.free
end

-- valida o alloc proposto contra o budget e as faixas (invariante do engine)
-- retorna ok, motivo. Σalloc deve == budget; cada eixo dentro de ALLOC_RANGE.
function TR.validateAlloc(alloc, budget)
  if type(alloc) ~= 'table' or not budget or budget <= 0 then
    return false, 'budget_invalido'
  end

  -- shape: só os 5 eixos, todos números inteiros >= 0
  for _, ax in ipairs(TR.AXES) do
    local v = alloc[ax]
    if type(v) ~= 'number' or v ~= v or v < 0 or v ~= math.floor(v) then
      return false, 'eixo_invalido:' .. ax
    end
  end

  -- soma deve fechar exatamente com o budget (não cria nem some pontos)
  if sumAlloc(alloc) ~= budget then
    return false, 'soma_diferente_do_budget'
  end

  -- cada eixo dentro da faixa vigente (anti-P2W; ou 0..100% em brute-test)
  for _, ax in ipairs(TR.AXES) do
    local r = TR.range(ax)
    local lo, hi = math.floor(budget * r.min), math.ceil(budget * r.max)
    if alloc[ax] < lo or alloc[ax] > hi then
      return false, 'fora_da_faixa:' .. ax
    end
  end

  return true
end


-- ajusta um alloc p/ caber na faixa VIGENTE mantendo Σ==budget (read-side).
-- Torna seguro ligar/desligar o brute-test: um alloc extremo salvo em teste é puxado
-- de volta p/ a faixa de produção na LEITURA da ficha — nunca corrompe nem trava o veículo.
function TR.coerceAlloc(alloc, budget)
  if type(alloc) ~= 'table' or not budget or budget <= 0 then return alloc end

  local out = {}
  for _, ax in ipairs(TR.AXES) do
    local r = TR.range(ax)
    local lo, hi = math.floor(budget * r.min), math.ceil(budget * r.max)
    out[ax] = clamp(math.floor(tonumber(alloc[ax]) or 0), lo, hi)
  end

  -- corrige a soma p/ o budget distribuindo o residual DENTRO das faixas
  local diff = budget - sumAlloc(out)
  if diff ~= 0 then
    for _, ax in ipairs(TR.AXES) do
      if diff == 0 then break end
      local r = TR.range(ax)
      local lo, hi = math.floor(budget * r.min), math.ceil(budget * r.max)
      if diff > 0 then
        local take = math.min(hi - out[ax], diff); out[ax] = out[ax] + take; diff = diff - take
      else
        local give = math.min(out[ax] - lo, -diff); out[ax] = out[ax] - give; diff = diff + give
      end
    end
    if diff ~= 0 then out[TR.AXES[#TR.AXES]] = out[TR.AXES[#TR.AXES]] + diff end  -- residual raro
  end
  return out
end


-- ============================================================
-- AFINIDADE (por tipo de pista — cruza alloc + identidade do .meta)
-- ============================================================

-- afinidade 0..1 por contexto. Usa campos físicos do catalog.p1 quando existem;
-- degrada para neutro quando ausentes (carro sem bloco físico completo).
function TR.calcAffinity(alloc, base, budget)
  if not budget or budget <= 0 then return nil end
  local n = function(ax) return (tonumber(alloc[ax]) or 0) / budget end

  local driveBias = tonumber(base and base.drive_bias) or 0.0
  local suspRaise = tonumber(base and base.susp_raise) or 0.0
  local inertiaZ  = tonumber(base and base.inertia_z)  or 1.0

  local isRWD = driveBias < 0.2
  local isAWD = driveBias >= 0.2 and driveBias <= 0.8
  local heightBonus = math.max(0, suspRaise * 20)
  local agility = c01(1.30 - inertiaZ * 0.30)                       -- pesado gira devagar
  local launch  = c01((n('grip') / math.max(n('potencia'), 0.01)) * (isAWD and 1.0 or 0.85))

  return {
    reta     = c01(n('potencia')*0.50 + n('aero')*0.35 + launch*0.15),
    curva    = c01((n('grip')*0.50 + n('frenagem')*0.30
                    + (isAWD and 0.10 or isRWD and -0.05 or 0.05)) * (0.70 + agility*0.30)),
    montanha = c01(n('suspensao')*0.40 + n('frenagem')*0.30 + n('grip')*0.20 + heightBonus),
    drift    = c01((1 - n('grip')*0.6) + (isRWD and 0.25 or 0.05) + n('potencia')*0.15
                    + (agility-0.8)*0.10),
    cidade   = c01((n('frenagem')*0.45 + n('grip')*0.35 + n('suspensao')*0.20) * (0.80 + agility*0.20)),
  }
end


-- ============================================================
-- HANDLING DERIVADO (F5 — alvos físicos a partir do alloc)
-- ============================================================

-- alvos de handling (FLAT, primitivos L-19) derivados do alloc, ou nil se sem bandas.
-- Cada eixo: valor = lerp(banda.min, banda.max, t), t = posição NORMALIZADA do eixo na
-- sua faixa (mesma fração 0..1 que o slider/afinidade usam — não o valor absoluto, p/ o
-- brute-test não distorcer). bands = Config.skillHandling (ou injetado p/ teste puro).
-- O CLIENTE re-clampa antes de aplicar; isto aqui é só o cálculo (server-authoritative).
function TR.handlingFromAlloc(alloc, budget, bands)
  bands = bands or (Config and Config.skillHandling)
  if type(bands) ~= 'table' or type(alloc) ~= 'table' or not budget or budget <= 0 then
    return nil
  end

  local out = {}
  for ax, b in pairs(bands) do
    local r    = TR.range(ax)
    local span = r.max - r.min
    local frac = (tonumber(alloc[ax]) or 0) / budget
    local t    = (span > 0) and c01((frac - r.min) / span) or 0
    out[ax] = b.min + (b.max - b.min) * t          -- min>max OK (eixo inverso, ex.: aero)
  end
  return out
end


-- ============================================================
-- FICHA COMPLETA (composição on-read — a verdade derivada do veículo)
-- ============================================================

-- monta a ficha derivada completa a partir do catálogo (base) + estado persistido.
-- alloc: se o jogador já redistribuiu (customization.handling), usa-o; senão defaultAlloc.
-- inclui `ranges`/`free` (faixa editável por eixo) — a MESMA conta server usa pra validar,
-- exposta read-only pra UI desenhar sliders sem recalcular nada por conta própria (L-04).
-- retorna tabela FLAT de primitivos (pronta p/ cruzar fronteira L-19), ou nil se sem p1.
function TR.buildSheet(base, mods, turbo, savedAlloc)
  if type(base) ~= 'table' or not base.tier_base then return nil end
  local budget = TR.budgetOf(base, mods, turbo)
  if not budget then return nil end

  -- alloc salvo é COAGIDO p/ a faixa vigente (read-side): build extrema de brute-test
  -- nunca trava a ficha quando o teste é desligado; sem alloc salvo = default neutro.
  local alloc = (type(savedAlloc) == 'table' and sumAlloc(savedAlloc) > 0)
                and TR.coerceAlloc(savedAlloc, budget) or TR.defaultAlloc(base, mods, turbo, budget)

  local score          = TR.scoreFromAlloc(alloc, budget)
  local tier           = TR.clampTier(TR.calcTier(score), base.tier_max)
  local affinity       = TR.calcAffinity(alloc, base, budget)
  local ranges, free   = TR.freeRanges(base, mods, turbo, budget)

  -- alvos de física derivados (só quando ligado; nunca persistido — L-04). nil = sem override.
  local hnd = (Config and Config.skillApplyHandling) and TR.handlingFromAlloc(alloc, budget) or nil

  return {
    tier        = tier,
    tier_base   = base.tier_base,
    tier_max    = base.tier_max,
    archetype   = base.archetype,
    score       = score,
    budget      = budget,
    used        = sumAlloc(alloc),
    alloc       = alloc,
    affinity    = affinity,
    parts       = TR.partsBonus(mods, turbo),
    ranges      = ranges,
    free        = free,
    hnd         = hnd,
  }
end


return TR
