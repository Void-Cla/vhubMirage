-- driver.lua — vhub_oxmysql
-- Adapter entre vHub.State e o oxmysql upstream.
-- Pool de workers, batch transacional, retry, circuit breaker.
-- O vHub já tem driver interno no bootstrap.lua — este driver é OPCIONAL
-- e só se registra se o export registerStateDriver existir no vhub.

-- ── Constantes ──────────────────────────────────────────────────────────

local RETRY_MAX     = 4      -- retentativas por operação
local RETRY_BASE_MS = 80     -- base de backoff exponencial em ms
local CB_WINDOW_MS  = 10000  -- janela do circuit breaker em ms
local CB_THRESHOLD  = 20     -- falhas para abrir o breaker
local CB_OPEN_MS    = 15000  -- tempo de pausa quando aberto em ms
local POOL_SIZE     = 12     -- workers paralelos
local QUERY_TIMEOUT = 8000   -- timeout por query em ms
local QUEUE_MAX     = 4000   -- capacidade máxima da fila

-- ── Estado interno ───────────────────────────────────────────────────────

local _api     = nil   -- referência ao exports.oxmysql
local _queries = {}    -- { [name] = sql_string }

local _queue     = {}; local _queue_n = 0
local _queue_in  = 0;  local _queue_out = 0
local _workers_busy = 0

local _cb = { state="closed", failures=0, window_end=0, open_until=0 }

local _m = {
  queries_ok=0, queries_fail=0, queries_timeout=0,
  retries=0, batches_ok=0, batches_fail=0,
  queue_peak=0, cb_trips=0,
}

-- ── Circuit breaker ──────────────────────────────────────────────────────

local function _cb_fail()
  local now = GetGameTimer()
  if now > _cb.window_end then
    _cb.failures = 0; _cb.window_end = now + CB_WINDOW_MS
  end
  _cb.failures = _cb.failures + 1
  if _cb.failures >= CB_THRESHOLD and _cb.state == "closed" then
    _cb.state = "open"; _cb.open_until = now + CB_OPEN_MS
    _m.cb_trips = _m.cb_trips + 1
    print("[vhub_oxmysql][ERRO] Circuit breaker ABERTO — banco instável por " ..
          (CB_OPEN_MS/1000) .. "s")
  end
end

local function _cb_ok()
  if _cb.state == "half_open" then
    _cb.state = "closed"; _cb.failures = 0
    print("[vhub_oxmysql] Circuit breaker FECHADO — banco estabilizado")
  end
end

local function _cb_allow()
  if _cb.state == "closed" then return true end
  local now = GetGameTimer()
  if _cb.state == "open" then
    if now >= _cb.open_until then _cb.state = "half_open"; return true end
    return false
  end
  return true  -- half_open: deixa passar para teste
end

-- ── Fila ─────────────────────────────────────────────────────────────────

local function _enqueue(op)
  if _queue_n >= QUEUE_MAX then
    print("[vhub_oxmysql][AVISO] Fila saturada — operação rejeitada")
    if op.resolve then op.resolve(nil) end
    return false
  end
  _queue_in = _queue_in + 1
  _queue[_queue_in] = op
  _queue_n = _queue_n + 1
  if _queue_n > _m.queue_peak then _m.queue_peak = _queue_n end
  return true
end

local function _dequeue()
  if _queue_n == 0 then return nil end
  _queue_out = _queue_out + 1
  local op = _queue[_queue_out]
  _queue[_queue_out] = nil
  _queue_n = _queue_n - 1
  return op
end

-- ── Execução de query ─────────────────────────────────────────────────────

local function _exec_op(op)
  local sql    = _queries[op.name]
  local params = op.params or {}
  local mode   = op.mode   or "query"

  if not _cb_allow() then
    _m.queries_fail = _m.queries_fail + 1
    if op.resolve then op.resolve(nil) end
    return false
  end

  local result = nil
  local ok     = false

  for attempt = 1, RETRY_MAX do
    if attempt > 1 then
      Citizen.Wait(RETRY_BASE_MS * (2 ^ (attempt - 2)))
      _m.retries = _m.retries + 1
    end

    local p = promise.new()
    local replied = false

    SetTimeout(QUERY_TIMEOUT, function()
      if not replied then
        replied = true; _m.queries_timeout = _m.queries_timeout + 1; p:resolve(nil)
      end
    end)

    if mode == "execute" then
      _api:update(sql, params, function(r)
        if not replied then replied = true; p:resolve(r or 0) end
      end)
    elseif mode == "scalar" then
      _api:scalar(sql, params, function(r)
        if not replied then replied = true; p:resolve(r) end
      end)
    else
      _api:query(sql, params, function(rows)
        if not replied then
          replied = true
          -- Converte BLOB (array de bytes) para string
          if type(rows) == "table" then
            for _, row in ipairs(rows) do
              for k, v in pairs(row) do
                if type(v) == "table" then
                  local chars = {}
                  for _, b in ipairs(v) do chars[#chars+1] = string.char(b) end
                  row[k] = table.concat(chars)
                end
              end
            end
          end
          p:resolve(rows)
        end
      end)
    end

    result = Citizen.Await(p)

    if result ~= nil or mode == "execute" then
      ok = true; _cb_ok(); _m.queries_ok = _m.queries_ok + 1; break
    else
      _cb_fail()
    end
  end

  if not ok then
    _m.queries_fail = _m.queries_fail + 1
    print(("[vhub_oxmysql][ERRO] Query '%s' falhou após %d tentativas"):format(
      op.name, RETRY_MAX))
  end

  if op.resolve then op.resolve(result) end
  return ok
end

-- ── Worker loop ───────────────────────────────────────────────────────────

local function _worker_loop()
  while true do
    local op = _dequeue()
    if op then
      _workers_busy = _workers_busy + 1
      _exec_op(op)
      _workers_busy = _workers_busy - 1
    else
      Citizen.Wait(0)
    end
  end
end

-- ── Driver público ────────────────────────────────────────────────────────

local Driver = {}; Driver.__index = Driver; Driver.name = "oxmysql_ext"

function Driver:init(cfg)
  if GetResourceState("oxmysql") ~= "started" then
    print("[vhub_oxmysql][ERRO] oxmysql não está iniciado")
    return false
  end
  _api = exports["oxmysql"]
  if not _api then
    print("[vhub_oxmysql][ERRO] exports oxmysql indisponíveis")
    return false
  end
  -- Pool de workers
  for i = 1, POOL_SIZE do Citizen.CreateThread(_worker_loop) end
  -- Log periódico de métricas
  Citizen.CreateThread(function()
    while true do
      Citizen.Wait(60000)
      print(("[vhub_oxmysql][MÉTRICAS] ok=%d fail=%d timeout=%d retry=%d " ..
             "batch_ok=%d batch_fail=%d fila=%d/%d workers=%d/%d cb=%s"):format(
        _m.queries_ok, _m.queries_fail, _m.queries_timeout, _m.retries,
        _m.batches_ok, _m.batches_fail, _queue_n, QUEUE_MAX,
        _workers_busy, POOL_SIZE, _cb.state))
    end
  end)
  print(("[vhub_oxmysql] Iniciado — pool=%d retry=%d timeout=%dms"):format(
    POOL_SIZE, RETRY_MAX, QUERY_TIMEOUT))
  return true
end

function Driver:prepare(name, sql)
  if type(name)~="string" or type(sql)~="string" then return end
  _queries[name] = sql
end

function Driver:query(name, params, mode)
  if not _queries[name] then
    print("[vhub_oxmysql][ERRO] Query não registrada: " .. tostring(name))
    return mode == "scalar" and nil or {}
  end
  local p = promise.new()
  local ok = _enqueue({
    name=name, params=params or {}, mode=mode or "query",
    resolve=function(r) p:resolve(r) end,
  })
  if not ok then return mode == "scalar" and nil or {} end
  return Citizen.Await(p)
end

function Driver:batch(ops, n)
  if not n or n == 0 then return true end
  if not _cb_allow() then
    _m.batches_fail = _m.batches_fail + 1
    return false
  end

  local tx = {}
  for i = 1, n do
    local op  = ops[i]
    local sql = op and _queries[op[1]]
    if sql then tx[#tx+1] = { sql, op[2] or {} } end
  end
  if #tx == 0 then return true end

  for attempt = 1, RETRY_MAX do
    if attempt > 1 then
      Citizen.Wait(RETRY_BASE_MS * (2 ^ (attempt-2)))
      _m.retries = _m.retries + 1
    end

    local p = promise.new(); local replied = false
    local tms = math.max(QUERY_TIMEOUT, #tx * 30)
    SetTimeout(tms, function()
      if not replied then replied=true; p:resolve(false) end
    end)
    _api:transaction(tx, nil, function(ok)
      if not replied then replied=true; p:resolve(ok==true) end
    end)

    if Citizen.Await(p) then
      _cb_ok(); _m.batches_ok = _m.batches_ok + 1; return true
    end
    _cb_fail()
  end

  _m.batches_fail = _m.batches_fail + 1
  print(("[vhub_oxmysql][ERRO] Batch falhou após %d tentativas (%d ops)"):format(
    RETRY_MAX, #tx))
  return false
end

-- ── Registro no vHub via export registerStateDriver ──────────────────────
-- Tenta registrar com limite de tentativas para não fazer loop infinito.
-- O vHub agora expõe o export registerStateDriver no server/init.lua.

local MAX_TRIES   = 30    -- máximo de tentativas (30 × 2s = 60s de espera)
local RETRY_DELAY = 2000  -- ms entre tentativas

AddEventHandler("onResourceStart", function(res)
  if res ~= "vhub" and res ~= GetCurrentResourceName() then return end
  if GetResourceState("vhub") ~= "started" then return end

  Citizen.CreateThread(function()
    local tries = 0
    while tries < MAX_TRIES do
      tries = tries + 1
      Citizen.Wait(RETRY_DELAY)

      -- Tenta registrar via export dedicado (evita acessar State diretamente)
      local ok, result = pcall(function()
        return exports["vhub"]:registerStateDriver(Driver)
      end)

      if ok and result == true then
        -- Driver registrado — inicializa e para o loop
        local ok2 = Driver:init({})
        if ok2 then
          print("[vhub_oxmysql] Driver externo registrado no vHub.State com sucesso.")
        else
          print("[vhub_oxmysql][AVISO] Driver registrado mas init() falhou — DB não conectado.")
        end
        return  -- sai do loop

      elseif ok and result == false then
        -- Export existe mas State já tem driver ativo — não sobrescreve
        print("[vhub_oxmysql] vHub já tem driver ativo — driver externo não necessário.")
        return

      else
        -- Export não existe ainda — tenta de novo
        if tries == 1 then
          print("[vhub_oxmysql] Aguardando export registerStateDriver no vhub...")
        end
      end
    end

    -- Esgotou tentativas sem sucesso
    print("[vhub_oxmysql][AVISO] vhub não expõe registerStateDriver após " ..
          (MAX_TRIES * RETRY_DELAY / 1000) .. "s — driver externo desativado.")
    print("[vhub_oxmysql] O vhub usa o driver interno do bootstrap.lua — isso é normal.")
  end)
end)

-- Export de diagnóstico
AddEventHandler("__cfx_export_" .. GetCurrentResourceName() .. "_getDriverMetrics",
  function(cb)
    cb({
      pool_size    = POOL_SIZE,
      workers_busy = _workers_busy,
      queue_length = _queue_n,
      queue_peak   = _m.queue_peak,
      queries_ok   = _m.queries_ok,
      queries_fail = _m.queries_fail,
      timeouts     = _m.queries_timeout,
      retries      = _m.retries,
      batches_ok   = _m.batches_ok,
      batches_fail = _m.batches_fail,
      cb_state     = _cb.state,
      cb_trips     = _m.cb_trips,
    })
  end)

print("[vhub_oxmysql] Driver carregado — aguardando vHub iniciar.")
