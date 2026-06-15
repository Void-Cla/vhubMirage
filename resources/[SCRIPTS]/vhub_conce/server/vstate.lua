-- server/vstate.lua — PRONTUÁRIO físico do veículo (escritor ÚNICO, server-authoritative)
--
-- Substitui a cadeia física do CORE (vh_vehicle_data — inerte desde o sprint PRONTUÁRIO):
-- 1 linha por placa em `vhub_vehicle_state`, colunas explícitas LEGÍVEIS (sem blob binário),
-- JSON puro nas colunas compostas (customization/damage/damage_log).
--
-- DEFAULTS da tabela = ESTADO DE FÁBRICA (fuel 100, health 1000, odômetro 0): corretos
-- para veículo novo. Fontes de telemetria enviam snapshot COMPLETO — row-miss nunca
-- ressuscita default em veículo usado.
--
-- REGRAS DO ESCRITOR (gates arquiteto/persistência/segurança 2026-06-11):
-- - Placa SEMPRE normalizada (U.normalizePlate) em todo read/write (anti ghost-row #23)
-- - Âncora fail-closed: sem linha em vhub_vehicles, NADA é escrito
-- - source='telemetry': health MONOTÔNICO não-crescente (anti repair-hack) e rejeitado
--   quando status ~= 'out' (anti race store×telemetria — L-13)
-- - source='store'/'pump'/'seed'/'repair': caminhos trusted com regras próprias
-- - NaN/Inf rejeitados (finiteNum) ANTES de qualquer clamp
-- - Escrita é IMEDIATA (per-op oxmysql, sem buffer) — nada pendente em stop/drop
---@diagnostic disable: undefined-global

local M = {}; VHubConce = VHubConce or {}; VHubConce.VState = M

local U = VHubConce.U

-- helpers SQL do repositório do conce (promise → valor; exigem thread)
local function sq(...)  return VHubConce.SQL.query(...)   end
local function se(...)  return VHubConce.SQL.execute(...) end
local function ss(...)  return VHubConce.SQL.scalar(...)  end


-- ============================================================
-- VALIDAÇÃO (payload é hostil até prova em contrário)
-- ============================================================

-- número finito clampado, ou nil (rejeita não-número, NaN e ±inf ANTES do clamp)
local function finiteNum(v, lo, hi)
  if type(v) ~= 'number' or v ~= v or math.abs(v) == math.huge then return nil end
  if lo and v < lo then v = lo end
  if hi and v > hi then v = hi end
  return v
end

-- whitelist de chaves de customization (espelha o sanitize do garage — defesa em profundidade)
local CUST_KEYS = {
  colours = true, extra_colours = true, plate_index = true, wheel_type = true,
  window_tint = true, livery = true, turbo = true, smoke = true, xenon = true,
  mods = true, neons = true, neon_colour = true, model = true,
}

-- filtra customization (tabela) → JSON com cap de 8 KB, ou nil
local function sanitizeCustJson(c)
  if type(c) ~= 'table' then return nil end
  local out = {}
  for k, v in pairs(c) do
    if CUST_KEYS[k] then out[k] = v end
  end
  local j = U.jenc(out)
  if not j or #j > 8192 then return nil end
  return j
end

-- array de índices inteiros 0..maxIdx, dedup, cap de tamanho — ou nil se vazio
local function sanitizeIdxArray(t, maxIdx, cap)
  if type(t) ~= 'table' then return nil end
  local out, seen, n = {}, {}, 0
  for _, v in pairs(t) do
    if type(v) == 'number' and v == math.floor(v) and v >= 0 and v <= maxIdx and not seen[v] then
      seen[v] = true; n = n + 1; out[n] = v
      if n > cap then return nil end   -- payload acima do plausível = hostil, descarta
    end
  end
  return n > 0 and out or nil
end

-- estrutura de dano {doors, windows, tyres, tyres_rim} → JSON com cap de 2 KB, ou nil
-- '{}' explícito (tabela vazia) significa "sem danos" e LIMPA a coluna
local function sanitizeDamageJson(d)
  if type(d) ~= 'table' then return nil end
  local out = {
    doors     = sanitizeIdxArray(d.doors, 5, 6),
    windows   = sanitizeIdxArray(d.windows, 7, 8),
    tyres     = sanitizeIdxArray(d.tyres, 7, 8),
    tyres_rim = sanitizeIdxArray(d.tyres_rim, 7, 8),
  }
  local j = U.jenc(out)
  if not j or #j > 2048 then return nil end
  return j
end


-- ============================================================
-- CACHE VRAM (read-through; invalidação no write; evict no delete)
-- Dispensa GC enquanto o conce for o escritor único (gate performance).
-- ============================================================

local _cache = {}   -- [plate] = state decodificado

-- remove a placa do cache (chamado por deleteVehicle)
function M:evict(plate)
  local p = U.normalizePlate(plate)
  if p then _cache[p] = nil end
end

-- estado de fábrica (espelha os DEFAULTs da tabela)
local function factoryState()
  return {
    fuel = 100.0, engine_health = 1000.0, body_health = 1000.0,
    odometer_km = 0.0, customization = nil, damage = nil, damage_log = nil,
    updated_at = 0,
  }
end


-- ============================================================
-- LIFECYCLE (DDL própria — sem FK, sem dependência do schema do garage)
-- ============================================================

-- cria a tabela do prontuário (idempotente; roda no boot do conce).
-- COLLATE OBRIGATÓRIO igual ao das tabelas do garage (utf8mb4_unicode_ci):
-- sem ele o JOIN/subquery com vhub_vehicles falha ("Illegal mix of collations").
function M:ensureSchema()
  se([[
    CREATE TABLE IF NOT EXISTS vhub_vehicle_state (
      plate         VARCHAR(12)  NOT NULL PRIMARY KEY,
      fuel          FLOAT        NOT NULL DEFAULT 100,
      engine_health FLOAT        NOT NULL DEFAULT 1000,
      body_health   FLOAT        NOT NULL DEFAULT 1000,
      odometer_km   DOUBLE       NOT NULL DEFAULT 0,
      customization MEDIUMTEXT   NULL,
      damage        TEXT         NULL,
      damage_log    MEDIUMTEXT   NULL,
      updated_at    INT          NOT NULL DEFAULT 0
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  ]], {})
  -- migração: instalação criada antes do fix nasceu com a collation default
  -- (general_ci) — converte 1x; checagem barata evita rebuild a cada boot
  local coll = ss([[
    SELECT TABLE_COLLATION FROM information_schema.TABLES
     WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'vhub_vehicle_state'
  ]], {})
  if coll and coll ~= 'utf8mb4_unicode_ci' then
    se('ALTER TABLE vhub_vehicle_state CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci', {})
  end
  return true
end

-- backfill 1x da customization legada (vhub_vehicles.customization → prontuário).
-- Idempotente; disparado pelo GARAGE após o DDL de vhub_vehicles (ordem de boot).
function M:backfillCustomization()
  se([[
    INSERT IGNORE INTO vhub_vehicle_state (plate, customization, updated_at)
    SELECT plate, customization, UNIX_TIMESTAMP()
      FROM vhub_vehicles
     WHERE customization IS NOT NULL AND customization != ''
  ]], {})
  -- cobre linha de estado criada ANTES do backfill (ex.: bomba) com cosmético ainda nulo
  se([[
    UPDATE vhub_vehicle_state s
      JOIN vhub_vehicles v ON v.plate = s.plate
       SET s.customization = v.customization
     WHERE s.customization IS NULL
       AND v.customization IS NOT NULL AND v.customization != ''
  ]], {})
  _cache = {}
  return true
end

-- remove linhas órfãs (substituto da FK). NUNCA roda no boot do conce: o garage
-- dispara após o DDL. Guarda dupla: vhub_vehicles precisa existir E estar populada
-- (DB parcial/restore não pode virar wipe total — gate persistência).
function M:reconcileOrphans()
  local n = tonumber(ss('SELECT COUNT(*) FROM vhub_vehicles', {}) or 0) or 0
  if n == 0 then return false end
  se([[
    DELETE FROM vhub_vehicle_state
     WHERE plate NOT IN (SELECT plate FROM vhub_vehicles)
  ]], {})
  return true
end


-- ============================================================
-- QUERIES (read-only)
-- ============================================================

-- estado físico da placa: linha decodificada, ou estado de fábrica se a placa é
-- registrada mas nunca persistiu, ou nil se a placa NÃO existe no negócio
function M:get(plate)
  local p = U.normalizePlate(plate); if not p then return nil end
  if _cache[p] then return _cache[p] end

  local rows = sq('SELECT * FROM vhub_vehicle_state WHERE plate = ? LIMIT 1', { p })
  local st
  if rows and rows[1] then
    local r = rows[1]
    st = {
      fuel          = tonumber(r.fuel) or 100.0,
      engine_health = tonumber(r.engine_health) or 1000.0,
      body_health   = tonumber(r.body_health) or 1000.0,
      odometer_km   = tonumber(r.odometer_km) or 0.0,
      customization = U.jdec(r.customization),
      damage        = U.jdec(r.damage),
      damage_log    = U.jdec(r.damage_log),
      updated_at    = tonumber(r.updated_at) or 0,
    }
  else
    if ss('SELECT 1 FROM vhub_vehicles WHERE plate = ? LIMIT 1', { p }) == nil then return nil end
    st = factoryState()
  end
  _cache[p] = st
  return st
end

-- dossiê da placa (identidade + físico) — alimenta o metadata da chave-item e admin
function M:dossier(plate)
  local p = U.normalizePlate(plate); if not p then return nil end
  local v = VHubConce.SQL:getVehicle(p); if not v then return nil end
  local st = self:get(p) or factoryState()
  return {
    plate = p, model = v.model, vtype = v.vtype, status = v.status,
    fuel = st.fuel, engine_health = st.engine_health, body_health = st.body_health,
    odometer_km = st.odometer_km, damage = st.damage, updated_at = st.updated_at,
  }
end


-- ============================================================
-- MUTATIONS (escritor único — TODO write do físico passa AQUI)
-- ============================================================

-- aplica patch parcial validado/clampado/sanitizado (UPSERT). Campos ausentes são
-- preservados (linha existente) ou recebem default de fábrica (linha nova).
-- patch: { fuel, engine_health, body_health, odometer_add (DELTA km),
--          customization (tabela), damage (tabela; {} = limpa) }
-- source: 'telemetry' | 'store' | 'pump' | 'seed' | 'repair' | 'system'
function M:save(plate, patch, source)
  local p = U.normalizePlate(plate)
  if not p or type(patch) ~= 'table' then return false end
  source = source or 'system'

  -- âncora fail-closed + status (1 SELECT; dobra como plateExists)
  local status = ss('SELECT status FROM vhub_vehicles WHERE plate = ? LIMIT 1', { p })
  if status == nil then return false end
  if source == 'telemetry' and status ~= 'out' then return false end

  local cur = self:get(p)   -- estado persistido (cache-hit usual) p/ monotonia e damage_log

  local cols, vals, upds = {}, {}, {}
  local function setcol(c, v, updExpr)
    cols[#cols+1] = c; vals[#vals+1] = v
    upds[#upds+1] = updExpr or (c .. ' = VALUES(' .. c .. ')')
  end

  local fuel = finiteNum(patch.fuel, 0.0, 100.0)
  if fuel then setcol('fuel', fuel) end

  local eng = finiteNum(patch.engine_health, -4000.0, 1000.0)
  if eng then
    -- telemetria nunca ELEVA health (anti repair-hack); reparo usa source='repair'
    if source == 'telemetry' and cur then eng = math.min(eng, cur.engine_health or 1000.0) end
    setcol('engine_health', eng)
  end

  local body = finiteNum(patch.body_health, 0.0, 1000.0)
  if body then
    if source == 'telemetry' and cur then body = math.min(body, cur.body_health or 1000.0) end
    setcol('body_health', body)
  end

  -- odômetro é DELTA acumulativo (clamp por snapshot: 2 km ≈ 15 s @ 480 km/h)
  local odo = finiteNum(patch.odometer_add, 0.0, 2.0)
  if odo and odo > 0 then
    setcol('odometer_km', odo, 'odometer_km = odometer_km + VALUES(odometer_km)')
  end

  local custJson = sanitizeCustJson(patch.customization)
  if custJson then setcol('customization', custJson) end

  local dmgJson = sanitizeDamageJson(patch.damage)
  if dmgJson then setcol('damage', dmgJson) end

  -- histórico de dano: append interno em queda brusca de health (telemetria) ou reparo
  local log = (cur and type(cur.damage_log) == 'table') and cur.damage_log or {}
  local logChanged = false
  if source == 'telemetry' and cur and (eng or body) then
    local dEng  = eng  and ((cur.engine_health or 1000.0) - eng)  or 0
    local dBody = body and ((cur.body_health   or 1000.0) - body) or 0
    if dEng >= 150.0 or dBody >= 150.0 then
      log[#log+1] = { t = os.time(), eng = eng or cur.engine_health, body = body or cur.body_health,
                      d_eng = math.floor(dEng), d_body = math.floor(dBody) }
      logChanged = true
    end
  elseif source == 'repair' then
    log[#log+1] = { t = os.time(), repair = true }
    logChanged = true
  end
  if logChanged then
    while #log > 30 do table.remove(log, 1) end   -- cap FIFO ANTES do encode
    local lj = U.jenc(log)
    if lj and #lj <= 16384 then setcol('damage_log', lj) end
  end

  if #cols == 0 then return false end
  setcol('updated_at', os.time())

  local sql = ('INSERT INTO vhub_vehicle_state (plate, %s) VALUES (?%s) ON DUPLICATE KEY UPDATE %s')
    :format(table.concat(cols, ', '), (', ?'):rep(#cols), table.concat(upds, ', '))
  table.insert(vals, 1, p)

  local ok = se(sql, vals)
  _cache[p] = nil   -- invalidação no write (read-through repõe)
  return ok ~= nil
end

-- reparo TRUSTED (manutenção/admin): único caminho que ELEVA health e limpa dano
function M:repair(plate)
  return self:save(plate, {
    engine_health = 1000.0, body_health = 1000.0, damage = {},
  }, 'repair')
end

-- semeia a linha de fábrica na compra (customization inicial já em JSON, pode ser nil)
function M:seed(plate, custJson)
  local p = U.normalizePlate(plate); if not p then return false end
  local ok = se([[
    INSERT IGNORE INTO vhub_vehicle_state (plate, customization, updated_at)
    VALUES (?, ?, ?)
  ]], { p, custJson, os.time() })
  _cache[p] = nil
  return ok ~= nil
end

-- apaga o prontuário da placa (chamado por deleteVehicle — substitui o CASCADE da FK)
function M:delete(plate)
  local p = U.normalizePlate(plate); if not p then return false end
  se('DELETE FROM vhub_vehicle_state WHERE plate = ?', { p })
  _cache[p] = nil
  return true
end

return M
