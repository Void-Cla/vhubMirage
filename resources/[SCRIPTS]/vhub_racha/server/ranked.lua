---@diagnostic disable: undefined-global, lowercase-global

-- server/ranked.lua — ranqueado PDL (escritor UNICO de vh_race_ranked).
--
-- Rating GLOBAL por personagem (cross-kind, estilo CS2/Premier). A verdade do
-- skill mora aqui; vh_race_stats segue como historico por modalidade (sem 2a
-- fonte — dominios distintos). L-04 / L-07 / L-13.
--
-- Matematica:
--   • expected_score / division_of = PURAS em shared/math.lua.
--   • Elo FFA pairwise: cada piloto e comparado a TODOS os outros; o delta e
--     normalizado por (n-1) → o swing de UMA corrida fica limitado a ~K,
--     independente do tamanho do grid. Brabo que ganha de novato sobe pouco;
--     se toma a zebra (cai pro fim), perde muito. Calibracao usa K maior nas
--     primeiras partidas para convergir rapido.
--
-- Atomicidade: snapshot-read de TODOS os ratings ANTES de calcular qualquer
-- delta (independente de ordem) e UM unico INSERT...ON DUPLICATE (atomico no
-- MySQL) com valores absolutos. Chamado SO de dentro de H.finalize, ja gateado
-- por mode=='rankeada'; aqui ainda exige >=2 char_ids distintos (anti-farm).


VHubRachaRanked = {}
local Ranked = VHubRachaRanked
local Cfg    = VHubRachaCfg
local SQL    = VHubRachaSQL
local Mth    = VHubRachaMath

Ranked._running = false   -- guard do cron de decay (L-06)


-- ============================================================
-- HELPERS
-- ============================================================

-- atalho local do bloco de config (sempre presente — default no config.lua)
local function rcfg() return Cfg.RANKED or {} end


-- ============================================================
-- QUERIES (read-only) + divisao
-- ============================================================

-- Resolve a divisao (Bronze..Lendario) + tier de um PDL. Regra no SERVIDOR (A-01).
function Ranked.division(pdl)
  return Mth.division_of(pdl, rcfg().DIVISIONS or {})
end


-- Linha PDL de um personagem; default provisorio (nunca correu ranqueada).
function Ranked.get(char_id)
  local cid = tonumber(char_id) or 0
  local row = (cid > 0) and SQL.ranked_one(cid) or nil
  local c   = rcfg()
  local start = c.PDL_START or 1000

  if not row then
    return {
      char_id = cid, pdl = start, peak_pdl = start,
      matches = 0, wins = 0, last_match_at = 0, provisional = true,
    }
  end

  row.char_id       = tonumber(row.char_id) or cid
  row.pdl           = tonumber(row.pdl) or start
  row.peak_pdl      = tonumber(row.peak_pdl) or row.pdl
  row.matches       = tonumber(row.matches) or 0
  row.wins          = tonumber(row.wins) or 0
  row.last_match_at = tonumber(row.last_match_at) or 0
  row.provisional   = row.matches < (c.CALIBRATION_MATCHES or 10)
  return row
end


-- true se o personagem ja correu ao menos 1 ranqueada (linha com matches > 0).
-- Usado para fechar enumeracao de char_id no perfil de TERCEIRO (so quem competiu).
function Ranked.has_played(char_id)
  local row = SQL.ranked_one(tonumber(char_id) or 0)
  return row ~= nil and (tonumber(row.matches) or 0) > 0
end


-- Leaderboard PDL (cross-kind) enriquecido com a divisao. Nick = caller resolve.
function Ranked.top(limit)
  local rows = SQL.ranked_top(limit)
  for _, r in ipairs(rows) do
    r.pdl      = tonumber(r.pdl) or 0
    r.peak_pdl = tonumber(r.peak_pdl) or r.pdl
    r.matches  = tonumber(r.matches) or 0
    r.wins     = tonumber(r.wins) or 0
    r.division = Ranked.division(r.pdl)
  end
  return rows
end


-- ============================================================
-- APPLY RACE — Elo FFA pairwise (MUTATION atomica, escritor unico)
-- ============================================================

-- `participants` = { { char_id, placement (1=melhor) }, ... }. Retorna mapa
-- char_id → { delta, old_pdl, new_pdl, division }. Vazio se ranqueado desligado
-- ou < 2 personagens distintos (anti-farm). Idempotencia da corrida e garantida
-- pelo guard de estado do RT.finish (finalize roda 1x por instancia).
function Ranked.apply_race(participants)
  local c = rcfg()
  if not c.ENABLED then return {} end
  if type(participants) ~= 'table' then return {} end

  -- Dedupe por char_id (>0) preservando placement
  local seen, list = {}, {}
  for _, p in ipairs(participants) do
    local cid = tonumber(p.char_id) or 0
    local plc = tonumber(p.placement) or 0
    if cid > 0 and plc > 0 and not seen[cid] then
      seen[cid] = true
      list[#list + 1] = { char_id = cid, placement = plc }
    end
  end

  local n = #list
  if n < 2 then return {} end   -- sem adversario real → sem PDL

  -- Snapshot dos ratings ATUAIS (antes de qualquer escrita → independe de ordem)
  local ids = {}
  for i, p in ipairs(list) do ids[i] = p.char_id end

  local snap = {}
  for _, r in ipairs(SQL.ranked_many(ids)) do snap[tonumber(r.char_id)] = r end

  local C     = c.C_FACTOR or 4000
  local start = c.PDL_START or 1000
  local minp  = c.MIN_PDL or 100
  local calK  = c.K_CALIBRATION or 1500
  local stdK  = c.K_FACTOR or 500
  local calM  = c.CALIBRATION_MATCHES or 10

  for _, p in ipairs(list) do
    local s    = snap[p.char_id]
    p.old_pdl  = s and (tonumber(s.pdl) or start) or start
    p.matches  = s and (tonumber(s.matches) or 0) or 0
    p.wins_old = s and (tonumber(s.wins) or 0) or 0
    p.peak_old = s and (tonumber(s.peak_pdl) or p.old_pdl) or p.old_pdl
  end

  -- Elo FFA: expected = Σ E(i,j); actual = Σ score(coloc_i vs coloc_j)
  local now = os.time()
  local out, batch = {}, {}

  for i = 1, n do
    local pi = list[i]
    local expected, actual = 0.0, 0.0

    for j = 1, n do
      if j ~= i then
        local pj = list[j]
        expected = expected + Mth.expected_score(pi.old_pdl, pj.old_pdl, C)
        if     pi.placement < pj.placement then actual = actual + 1.0
        elseif pi.placement == pj.placement then actual = actual + 0.5 end
      end
    end

    local K       = (pi.matches < calM) and calK or stdK
    local delta   = math.floor(K * (actual - expected) / (n - 1) + 0.5)
    local new_pdl = math.max(minp, pi.old_pdl + delta)
    local won     = (pi.placement == 1) and 1 or 0
    local new_peak = math.max(pi.peak_old, new_pdl)

    batch[#batch + 1] = {
      char_id = pi.char_id, pdl = new_pdl, peak_pdl = new_peak,
      matches = pi.matches + 1, wins = pi.wins_old + won, last_match_at = now,
    }
    out[pi.char_id] = {
      delta    = new_pdl - pi.old_pdl,   -- delta REAL pos-clamp (honesto no piso)
      old_pdl  = pi.old_pdl,
      new_pdl  = new_pdl,
      division = Ranked.division(new_pdl),
    }
  end

  -- Persiste tudo num unico statement atomico
  SQL.upsert_ranked_batch(batch)
  return out
end


-- ============================================================
-- DECAY — sweep diario (limpa o topo de quem sumiu)
-- ============================================================

-- 1 UPDATE set-based: elite inativa perde PER_DAY ate o piso ABOVE_PDL.
function Ranked.decay_sweep()
  local d = rcfg().DECAY
  if not (d and d.ENABLED) then return end
  local cutoff = os.time() - (d.INACTIVE_DAYS or 14) * 86400
  SQL.ranked_decay(d.ABOVE_PDL or 2200, d.PER_DAY or 25, d.ABOVE_PDL or 2200, cutoff)
end


-- Agenda o sweep via SetTimeout-chain reschedulavel (sem while-true; L-06).
-- Cadencia por DIA-CALENDARIO real (os.date) — robusto a servidores que reiniciam
-- antes de 24h (GetGameTimer zeraria e o sweep nunca rodaria). Cancela quando o
-- resource para (_running=false). Residual: restart muito frequente pode varrer
-- mais de 1x/dia (so afeta elite inativa 14d+, -PER_DAY por varredura; aceito).
function Ranked.start_decay_cron()
  local c = rcfg()
  local d = c.DECAY
  if not (c.ENABLED and d and d.ENABLED) then return end
  if Ranked._running then return end

  Ranked._running = true
  local interval  = d.INTERVAL_MS or 3600000
  local last_day  = nil

  local function tick()
    if not Ranked._running then return end
    local day = os.date('%Y-%m-%d')   -- dia-calendario real
    if day ~= last_day then
      last_day = day
      pcall(Ranked.decay_sweep)
    end
    SetTimeout(interval, tick)
  end

  SetTimeout(interval, tick)
end


-- Para o cron no stop do resource (L-06 — saida explicita).
AddEventHandler('onResourceStop', function(res)
  if res == GetCurrentResourceName() then Ranked._running = false end
end)
