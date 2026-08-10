-- shared/engineering.lua — DERIVADOR PURO da Camada A (peças → física per-entidade)
--
-- ADR #82 FASE 2 (F2.1). Função pura, ZERO I/O (sem native/SQL/export/State Bag) — mesmo
-- contrato de tier_rules.lua: recebe dados, devolve números. Server é autoridade; o client
-- (client/engineering.lua) só APLICA o que sai daqui via sheet.eng.
--
-- DOMÍNIOS ORTOGONAIS (L-04): as PEÇAS (vetor de deltas) são dado do vhub_custom; a TRADUÇÃO
-- peça→física (power_boost/top_speed_pct) é gramática do vhub_vehcontrol (dono da ficha e da
-- Camada A). Por isso o derivador mora AQUI e NÃO em tier_rules.lua (que é a gramática de
-- PONTOS/tier — vocabulário diferente; misturar inflaria o módulo).
--
-- ENTRADAS:
--   partsMap  = customization.parts persistido = { [part_id] = def } (mapa esparso, LEITURA-ONLY;
--               é referência VIVA do cache VRAM do conce — NUNCA mutar aqui)
--   deltasCat = catálogo de deltas por peça = { [part_id] = { deltas={eixo=n}, capabilities={} } }
--               (vem de exports.vhub_custom:getPartsDeltas — dono do dado = vhub_custom)
--   base      = catalog.p1 do modelo (identidade física; usada só p/ presença, não obrigatória)
--
-- SAÍDA: { power_boost = <0..CAP_POWER>, top_speed_pct = <0..CAP_TOP> } — FLAT, primitivos (L-19),
--         já clampado (o client re-clampa por defesa em profundidade; aqui entregamos pré-validado).
--
-- ⚠️ DERIVADO — NUNCA PERSISTIR. sheet.eng é recomposto on-read a cada ficha, igual a tier/score/
--    hnd/nitro. O dado bruto (as peças) é que persiste, no vhub_custom.
---@diagnostic disable: undefined-global, lowercase-global

VHubVeh = VHubVeh or {}
local ENG = {}
VHubVeh.Engineering = ENG


-- ============================================================
-- CONSTANTES DE TRADUÇÃO (peça-pontos → física da Camada A)
-- ============================================================
-- Os deltas do catálogo são pontos de DESIGN (−30..+30 por eixo, ver parts_catalog). Aqui os
-- convertemos em GRANDEZAS FÍSICAS das natives per-entidade:
--   potencia → SetVehicleCheatPowerIncrease (fração de boost de potência; 0.30 ≈ +30%)
--   aero     → ModifyVehicleTopSpeed (% de acréscimo ao teto; aero alto empurra topo)
-- Escalas conservadoras: soma bruta de deltas de potência é dividida por DIVISOR e teta em CAP.
-- Recalibrar o "feel" da Camada A = mexer SÓ nestes números (fonte única da tradução).

local AXIS_POWER   = 'potencia'   -- eixo que alimenta o boost de potência
local AXIS_TOP     = 'aero'       -- eixo que alimenta o teto de velocidade

local POWER_DIVISOR = 120.0       -- Σ deltas de potência ÷ isto = fração (ex.: +48 pts → 0.40)
local TOP_DIVISOR   = 240.0       -- Σ deltas de aero ÷ isto = fração de topo (aero rende menos)

local CAP_POWER = 0.60            -- teto de boost de potência (casa com clamp do client: 0..1, aqui menor)
local CAP_TOP   = 0.25            -- teto de acréscimo de velocidade (client clampa em 0.5; aqui menor)


-- ============================================================
-- HELPERS PUROS
-- ============================================================

-- clamp numérico simples (entrada já é número no ponto de uso)
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end


-- ============================================================
-- DERIVAÇÃO
-- ============================================================

-- true se o slot da peça está INSTALADO. O mapa esparso `parts` faz merge ADITIVO no conce
-- (MERGE_SPARSE nunca apaga chave): remover peça = gravar `parts[id]=false`. Por isso valor
-- FALSY = ausente (não basta a chave existir). Fonte única desta regra de leitura.
local function installed(v)
  return v ~= nil and v ~= false
end

-- soma os deltas de UM eixo sobre todas as peças INSTALADAS (read-only sobre partsMap).
-- Resolve cada part_id contra o catálogo de deltas — peça não catalogada é ignorada (whitelist).
-- Itera com pairs SEM tocar partsMap (é a referência viva do cache VRAM do conce).
local function sumAxis(partsMap, deltasCat, axis)
  local total = 0
  for id, v in pairs(partsMap) do
    if installed(v) then
      local def = deltasCat[id]
      local d   = def and def.deltas
      if type(d) == 'table' then
        total = total + (tonumber(d[axis]) or 0)
      end
    end
  end
  return total
end

-- deriva a base física per-entidade das peças instaladas.
-- Retorna SEMPRE uma tabela { power_boost, top_speed_pct } (0,0 quando não há peça/entrada).
-- Pura e determinística: mesmas entradas → mesma saída (idempotente por construção — R14).
function ENG.derive(partsMap, deltasCat, base)
  if type(partsMap) ~= 'table' or type(deltasCat) ~= 'table' then
    return { power_boost = 0.0, top_speed_pct = 0.0 }
  end

  local pPts = sumAxis(partsMap, deltasCat, AXIS_POWER)   -- pode ser negativo (peças com trade-off)
  local aPts = sumAxis(partsMap, deltasCat, AXIS_TOP)

  -- só ganho conta como boost (deltas negativos de potência NÃO viram "freio" na Camada A —
  -- isso seria física de handling, domínio da Camada B/ADR #83). Piso 0.
  local power = clamp(pPts / POWER_DIVISOR, 0.0, CAP_POWER)
  local top   = clamp(aPts / TOP_DIVISOR,   0.0, CAP_TOP)

  return { power_boost = power, top_speed_pct = top }
end

-- true se há QUALQUER peça INSTALADA (evita anexar sheet.eng vazio — economia de sync na ficha).
-- Conta só slots truthy: um carro com todas as peças removidas (parts = {[id]=false}) = sem peça.
function ENG.hasParts(partsMap)
  if type(partsMap) ~= 'table' then return false end
  for _, v in pairs(partsMap) do
    if installed(v) then return true end
  end
  return false
end

-- ADR #85 F2.5-B: soma o delta de PESO (kg) das peças INSTALADAS (read-only sobre partsMap).
-- Pura e determinística; peça não catalogada é ignorada (whitelist). O consumidor (sheetOf)
-- soma isto ao base_mass do catálogo → sheet.mass DERIVADO (efêmero, nunca persistido — L-04).
-- A APLICAÇÃO física da massa é model-wide (fMass) → permanece GATED na Camada B (ADR #83).
function ENG.massDelta(partsMap, deltasCat)
  if type(partsMap) ~= 'table' or type(deltasCat) ~= 'table' then return 0 end
  local total = 0
  for id, v in pairs(partsMap) do
    if installed(v) then
      local def = deltasCat[id]
      if def then total = total + (tonumber(def.mass) or 0) end
    end
  end
  return total
end


return ENG
