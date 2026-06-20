-- tools/test_tier_rules.lua — teste OFFLINE do engine de skill (decisão #27).
-- Valida as funções PURAS de vhub_vehcontrol/shared/tier_rules.lua contra os
-- blocos `p1` REAIS de vhub_conce/shared/catalog.lua — ambos são módulos puros,
-- então o teste dá `dofile` neles (sem cópia: o que regredir no engine OU no
-- catálogo fica vermelho aqui, sem precisar de servidor).
--
-- Uso:  lua tools/test_tier_rules.lua        (rodar a partir da raiz do repo; requer Lua 5.4)
-- NOTA: ferramenta standalone de desenvolvimento — roda FORA do runtime vHub
--       (não há vHub.Logger aqui; saída via io.write — L-08). O teste RUNTIME
--       equivalente (export end-to-end in-server) é tests.test_vehicle_sheet_export
--       no vhub_testrunner.
--
-- Invariantes cobertas:
--   - base_alloc de TODO carro com p1 soma == BUDGET[tier_base]
--   - validateAlloc(defaultAlloc) == true (abrir a ficha e salvar sem editar funciona)
--   - freeRanges (limites do slider) ⊆ faixas que o servidor valida (slider nunca gera rejeição)
--   - redistribuição que zera os pontos num eixo (max-out) ainda valida
--   - score em [0,1000], build competitiva sobe o score, clampTier respeita tier_max
--   - buildSheet shape/nil-safety; validateAlloc rejeita malformado (soma/inteiro/negativo/anti-P2W)


-- ============================================================
-- LOADER (resolve os módulos puros relativo à raiz do repo OU ao script)
-- ============================================================

local function script_dir()
  local s = arg and arg[0] or ""
  return s:match("^(.*[/\\])") or "./"
end

-- dá dofile no primeiro caminho candidato que existir (retorno pode ser nil:
-- catalog.lua seta um global e não tem `return` — quem chama valida o que precisa)
local function load_first(rels)
  for _, rel in ipairs(rels) do
    local f = io.open(rel, "r")
    if f then f:close(); return dofile(rel), rel end
  end
  error("não encontrei o módulo nos caminhos: " .. table.concat(rels, " | "))
end

local TR = assert(load_first({
  "resources/[SCRIPTS]/vhub_vehcontrol/shared/tier_rules.lua",
  script_dir() .. "../resources/[SCRIPTS]/vhub_vehcontrol/shared/tier_rules.lua",
}), "tier_rules não retornou TR")

-- catalog.lua seta o global VHubConce.catalog (módulo de dados puro, sem return)
load_first({
  "resources/[SCRIPTS]/vhub_conce/shared/catalog.lua",
  script_dir() .. "../resources/[SCRIPTS]/vhub_conce/shared/catalog.lua",
})
local CATALOG = assert(VHubConce and VHubConce.catalog, "catalog não carregou")


-- ============================================================
-- MINI ASSERT
-- ============================================================

local function out(s) io.write(tostring(s) .. "\n") end
local pass, fail, fails = 0, 0, {}
local function ok(cond, msg)
  if cond then pass = pass + 1 else fail = fail + 1; fails[#fails+1] = msg end
end
local function eq(a, b, msg)
  ok(a == b, (msg or "eq") .. " (got=" .. tostring(a) .. " want=" .. tostring(b) .. ")")
end

local function sum(a) local s = 0; for _, ax in ipairs(TR.AXES) do s = s + (a[ax] or 0) end; return s end

-- carros REAIS do catálogo que têm bloco p1 (engine habilitado)
local P1_CARS = {}
for key, entry in pairs(CATALOG) do
  if type(entry) == "table" and type(entry.p1) == "table" and entry.p1.tier_base then
    P1_CARS[key] = entry.p1
  end
end

-- combos de peças p/ crescer o budget (idx => gtaLevel; turbo = booleano)
local COMBOS = {
  { name = "stock",        mods = {},                                   turbo = false },
  { name = "engine",       mods = { [11] = 2 },                         turbo = false },
  { name = "engine+turbo", mods = { [11] = 2 },                         turbo = true  },
  { name = "all-perf",     mods = { [11]=2,[12]=2,[13]=2,[15]=2,[16]=2 }, turbo = true },
  { name = "string-keys",  mods = { ["11"] = 2 },                       turbo = false }, -- msgpack manda chave string
}


-- ============================================================
-- 1. BUDGET e base_alloc (invariante do catálogo)
-- ============================================================

local n_cars = 0
for key, base in pairs(P1_CARS) do
  n_cars = n_cars + 1
  eq(TR.budgetOf(base, nil, nil), TR.BUDGET[base.tier_base], "budgetOf stock " .. key)
  if type(base.base_alloc) == "table" then
    eq(sum(base.base_alloc), TR.BUDGET[base.tier_base], "base_alloc sum == BUDGET[tier] " .. key)
  end
end
ok(n_cars > 0, "catálogo tem ao menos 1 carro com p1 (encontrei " .. n_cars .. ")")

do
  local pb = TR.partsBonus({ [11] = 2 }, true) -- motor(20)+turbo(15)=35
  eq(pb.total, 35, "partsBonus engine+turbo total")
  local fixedSum = 0; for _, ax in ipairs(TR.AXES) do fixedSum = fixedSum + pb.fixed[ax] end
  eq(pb.free + fixedSum, 35, "partsBonus fixed+free == total")
end


-- ============================================================
-- 2. CRÍTICO: validateAlloc(defaultAlloc) == true (abrir+salvar sem editar)
-- ============================================================

for key, base in pairs(P1_CARS) do
  for _, c in ipairs(COMBOS) do
    local budget = TR.budgetOf(base, c.mods, c.turbo)
    local da = TR.defaultAlloc(base, c.mods, c.turbo, budget)
    eq(sum(da), budget, ("defaultAlloc sum==budget %s/%s"):format(key, c.name))
    local v, why = TR.validateAlloc(da, budget)
    ok(v == true, ("validateAlloc(defaultAlloc) %s/%s -> %s"):format(key, c.name, tostring(why)))
  end
end


-- ============================================================
-- 3. freeRanges ⊆ faixas do validateAlloc + redistribuição max-out
-- ============================================================

for key, base in pairs(P1_CARS) do
  for _, c in ipairs(COMBOS) do
    local budget = TR.budgetOf(base, c.mods, c.turbo)
    local ranges = TR.freeRanges(base, c.mods, c.turbo, budget)
    for _, ax in ipairs(TR.AXES) do
      local r  = TR.ALLOC_RANGE[ax]
      local lo = math.floor(budget * r.min)
      local hi = math.ceil(budget * r.max)
      local fr = ranges[ax]
      ok(fr.min <= fr.max, ("freeRanges min<=max %s/%s/%s"):format(key, c.name, ax))
      ok(fr.min >= lo, ("freeRanges.min(%d)>=validateLo(%d) %s/%s/%s"):format(fr.min, lo, key, c.name, ax))
      ok(fr.max <= hi, ("freeRanges.max(%d)<=validateHi(%d) %s/%s/%s"):format(fr.max, hi, key, c.name, ax))
    end

    -- empurra potencia ao topo do slider e drena dos demais até o piso (igual ao JS)
    local draft = TR.defaultAlloc(base, c.mods, c.turbo, budget)
    local need  = ranges.potencia.max - draft.potencia
    draft.potencia = ranges.potencia.max
    for _, ax in ipairs(TR.AXES) do
      if ax ~= "potencia" and need > 0 then
        local take = math.min(draft[ax] - ranges[ax].min, need)
        draft[ax] = draft[ax] - take
        need = need - take
      end
    end
    if need == 0 then
      local v, why = TR.validateAlloc(draft, budget)
      ok(v == true, ("validateAlloc(max-out potencia) %s/%s -> %s"):format(key, c.name, tostring(why)))
    end
  end
end


-- ============================================================
-- 4. score / tier
-- ============================================================

do
  -- pega um carro determinístico do catálogo p/ asserts numéricos estáveis
  local base = P1_CARS.nissan370z or P1_CARS.m3e46
  if base then
    local budget = TR.budgetOf(base, nil, nil)
    local sBal = TR.scoreFromAlloc(TR.defaultAlloc(base, nil, nil, budget), budget)
    ok(sBal >= 0 and sBal <= 1000, "score em [0,1000]")

    local r = TR.freeRanges(base, nil, nil, budget)
    local comp = {
      potencia = r.potencia.max, grip = r.grip.max,
      frenagem = math.floor(budget * TR.ALLOC_RANGE.frenagem.min),
      aero     = math.floor(budget * TR.ALLOC_RANGE.aero.min),
      suspensao = math.floor(budget * TR.ALLOC_RANGE.suspensao.min),
    }
    comp.frenagem = comp.frenagem + (budget - sum(comp))
    if TR.validateAlloc(comp, budget) then
      ok(TR.scoreFromAlloc(comp, budget) > sBal, "build competitiva sobe o score")
    else
      ok(true, "build competitiva fora da faixa — informativo (não falha)")
    end
  end
  eq(TR.clampTier("S+", "S"), "S", "clampTier limita ao tier_max")
  eq(TR.clampTier("D", "S"), "D", "clampTier passa abaixo do teto")
end


-- ============================================================
-- 5. buildSheet
-- ============================================================

do
  local base = P1_CARS.f8t or select(2, next(P1_CARS))
  local sheet = TR.buildSheet(base, { [11] = 2 }, true, nil)
  ok(type(sheet) == "table", "buildSheet retorna tabela")
  for _, k in ipairs({ "tier","tier_base","tier_max","score","budget","used","alloc","affinity","ranges","free" }) do
    ok(sheet[k] ~= nil, "buildSheet tem chave " .. k)
  end
  eq(sheet.used, sheet.budget, "buildSheet default used==budget")
  ok(TR.buildSheet({}, nil, nil, nil) == nil, "buildSheet nil p/ base sem tier_base")
end


-- ============================================================
-- 6. validateAlloc rejeita malformado
-- ============================================================

do
  local base = P1_CARS.nissan370z or select(2, next(P1_CARS))
  local budget = TR.budgetOf(base, nil, nil)
  local good = TR.defaultAlloc(base, nil, nil, budget)
  ok(TR.validateAlloc(good, budget) == true, "sanity: alloc bom passa")

  local function clone(t) local o = {}; for k, v in pairs(t) do o[k] = v end; return o end

  local bad = clone(good); bad.potencia = bad.potencia + 1
  ok(select(1, TR.validateAlloc(bad, budget)) == false, "rejeita soma errada")

  local nonint = clone(good); nonint.grip = nonint.grip + 0.5; nonint.aero = nonint.aero - 0.5
  ok(select(1, TR.validateAlloc(nonint, budget)) == false, "rejeita eixo não-inteiro")

  local neg = clone(good); neg.aero = -10; neg.potencia = neg.potencia + 10
  ok(select(1, TR.validateAlloc(neg, budget)) == false, "rejeita eixo negativo")

  local allin = { potencia = budget, grip = 0, frenagem = 0, aero = 0, suspensao = 0 }
  ok(select(1, TR.validateAlloc(allin, budget)) == false, "rejeita all-in (anti-P2W)")
end


-- ============================================================
-- 7. handlingFromAlloc (F5 — alvos físicos derivados)
-- ============================================================

do
  local base   = P1_CARS.nissan370z or select(2, next(P1_CARS))
  local budget = TR.budgetOf(base, nil, nil)
  local bands  = {
    potencia = { field = 'fInitialDriveForce', min = 0.14, max = 0.46 },
    grip     = { field = 'fTractionCurveMax',  min = 1.55, max = 2.95 },
    aero     = { field = 'fInitialDragCoeff',  min = 6.0,  max = 18.0 },
  }
  local hnd = TR.handlingFromAlloc(TR.defaultAlloc(base, nil, nil, budget), budget, bands)
  ok(type(hnd) == 'table', 'handlingFromAlloc retorna tabela')
  ok(hnd.potencia >= 0.14 and hnd.potencia <= 0.46, 'hnd.potencia dentro da banda')
  ok(hnd.grip >= 1.55 and hnd.grip <= 2.95, 'hnd.grip dentro da banda')

  -- monotonicidade: + fração de potencia → maior driveForce
  local loP = TR.handlingFromAlloc({ potencia = math.floor(0.10 * budget) }, budget, bands)
  local hiP = TR.handlingFromAlloc({ potencia = math.floor(0.34 * budget) }, budget, bands)
  ok(hiP.potencia > loP.potencia, 'mais potencia -> maior driveForce (monotonico)')

  ok(TR.handlingFromAlloc(nil, budget, bands) == nil, 'handlingFromAlloc nil-safe (alloc nil)')
  ok(TR.handlingFromAlloc({}, budget, nil) == nil, 'handlingFromAlloc nil sem bandas')
end


-- ============================================================
-- 8. coerceAlloc (read-side: torna seguro ligar/desligar brute-test)
-- ============================================================

do
  local base   = P1_CARS.nissan370z or select(2, next(P1_CARS))
  local budget = TR.budgetOf(base, nil, nil)
  local extreme = { potencia = budget, grip = 0, frenagem = 0, aero = 0, suspensao = 0 }
  local co = TR.coerceAlloc(extreme, budget)
  eq(sum(co), budget, 'coerceAlloc: soma == budget')
  ok(TR.validateAlloc(co, budget) == true, 'coerceAlloc: vira alloc VALIDO em producao')

  local good = TR.defaultAlloc(base, nil, nil, budget)
  eq(sum(TR.coerceAlloc(good, budget)), budget, 'coerceAlloc idempotente (soma) em alloc valido')
end


-- ============================================================
-- 9. modo brute-test (Config.skillBruteTest) + sheet.hnd
-- ============================================================

do
  Config = {
    skillBruteTest    = true,
    skillApplyHandling = true,
    skillHandling     = { potencia = { field = 'fInitialDriveForce', min = 0.14, max = 0.46 } },
  }
  local base   = P1_CARS.nissan370z or select(2, next(P1_CARS))
  local budget = TR.budgetOf(base, nil, nil)

  local extreme = { potencia = budget, grip = 0, frenagem = 0, aero = 0, suspensao = 0 }
  ok(TR.validateAlloc(extreme, budget) == true, 'brute-test: build extrema VALIDA (0..100%)')
  eq(sum(TR.defaultAlloc(base, nil, nil, budget)), budget, 'brute-test: defaultAlloc soma==budget')

  -- brute libera o PISO: o slider pode zerar um eixo e empilhar no outro (budget inteiro)
  local fr = TR.freeRanges(base, nil, nil, budget)
  eq(fr.potencia.min, 0, 'brute-test: freeRanges.min libera o piso (=0)')
  eq(fr.potencia.max, budget, 'brute-test: freeRanges.max = budget inteiro')

  local sheet = TR.buildSheet(base, nil, nil, nil)
  ok(type(sheet) == 'table' and type(sheet.hnd) == 'table', 'buildSheet inclui hnd quando ligado')
  ok(type(sheet.hnd.potencia) == 'number', 'sheet.hnd.potencia e numero')

  Config = nil   -- restaura (demais asserts assumem producao)
end

-- com a fisica DESLIGADA, buildSheet nao deve trazer hnd
do
  local base  = P1_CARS.nissan370z or select(2, next(P1_CARS))
  local sheet = TR.buildSheet(base, nil, nil, nil)
  ok(sheet.hnd == nil, 'buildSheet SEM hnd quando skillApplyHandling desligado')
end


-- ============================================================
-- RELATÓRIO
-- ============================================================

out(("\n==== tier_rules: %d carros com p1 | %d asserts OK | %d falhas ===="):format(n_cars, pass, fail))
for _, m in ipairs(fails) do out("  FALHA: " .. m) end
os.exit(fail == 0 and 0 or 1)
