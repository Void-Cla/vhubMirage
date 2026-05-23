-- server/state.lua — State manager (VRAM-first, TX, batch SQL)
-- Responsabilidade: única fonte de verdade em memória; SQL é backup.

local S = {}; S.__index = S; vHub.State = S

S._mem        = {}    -- VRAM { [etype][eid][key] = value }
S._snap       = {}    -- snapshots de TX para rollback
S._batch      = {}    -- ops SQL pendentes
S._batchN     = 0
S._flushing   = false -- guard contra re-entrância de flush
S._validators = {}
S._driver     = nil
S._ready      = false
S._cprepare   = {}    -- fila de prepares antes do driver
S._cquery     = {}    -- fila de queries antes do driver
S._prepared   = {}    -- queries registradas

local BATCH_MAX = 800   -- força flush ao atingir este volume
local BATCH_INT = 3000  -- flush automático a cada 3s

-- Auto-flush periódico em thread dedicada
Citizen.CreateThread(function()
  while true do Citizen.Wait(BATCH_INT); S:_flush() end
end)

-- ── Driver ────────────────────────────────────────────────────────────

function S:setDriver(drv)
  self._driver = drv

  if not drv:init(vHub.cfg.db) then
    vHub.Logger:error("state", "Conexão com DB falhou")
    return false
  end

  -- Aplica prepares que chegaram antes do driver
  for _, p in ipairs(self._cprepare) do drv:prepare(table.unpack(p)) end

  -- Dispara queries que chegaram antes do driver
  for _, q in ipairs(self._cquery) do
    Citizen.CreateThread(function()
      local r = drv:query(table.unpack(q[1]))
      if q[2] then q[2](r) end
    end)
  end

  self._cprepare = nil
  self._cquery   = nil
  self._ready    = true

  -- Seed do alocador de user_id — corre em thread separada após driver pronto
  Citizen.CreateThread(function()
    local ok, r = pcall(function()
      return Citizen.Await(S:query("vh/max_userid"))
    end)
    local max = (ok and r and #r > 0 and r[1]) and tonumber(r[1].maxid) or 0
    vHub._next_user_id = max + 1
    vHub.Logger:info("state", "Alocador user_id iniciado em " .. vHub._next_user_id)
  end)

  -- Seed do alocador de char_id
  Citizen.CreateThread(function()
    local ok, r = pcall(function()
      return Citizen.Await(S:query("vh/max_charid"))
    end)
    local max = (ok and r and #r > 0 and r[1]) and tonumber(r[1].maxid) or 0
    vHub._next_char_id = max + 1
    vHub.Logger:info("state", "Alocador char_id iniciado em " .. vHub._next_char_id)
  end)

  vHub.Logger:info("state", "DB conectado: " .. tostring(drv.name))
  return true
end

-- ── Prepare / Query ───────────────────────────────────────────────────

function S:prepare(name, sql)
  self._prepared[name] = true
  if self._ready then
    self._driver:prepare(name, sql)
  else
    table.insert(self._cprepare, { name, sql })
  end
end

-- Retorna promise — chamador DEVE estar em Citizen.CreateThread
function S:query(name, params, mode)
  mode = mode or "query"
  assert(self._prepared[name],
    "[vHub][State] Query não preparada: " .. tostring(name))
  local p = promise.new()
  if self._ready then
    Citizen.CreateThread(function()
      p:resolve(self._driver:query(name, params or {}, mode))
    end)
  else
    table.insert(self._cquery,
      { { name, params or {}, mode }, function(r) p:resolve(r) end })
  end
  return p
end

function S:scalar(n, p) return self:query(n, p, "scalar")  end
function S:exec(n, p)   return self:query(n, p, "execute") end

-- ── VRAM get / set ─────────────────────────────────────────────────────

function S:get(et, eid, key)
  local t = self._mem[et]; if not t then return nil end
  local e = t[eid];        if not e then return nil end
  if key ~= nil then return e[key] end
  return e
end

function S:set(et, eid, key, val, tx)
  if not self._mem[et]      then self._mem[et] = {} end
  if not self._mem[et][eid] then self._mem[et][eid] = {} end
  if tx then
    if not self._snap[tx] then self._snap[tx] = {} end
    local sk = et.."\0"..tostring(eid).."\0"..key
    if self._snap[tx][sk] == nil then
      self._snap[tx][sk] = { et=et, eid=eid, key=key,
        prev = self._mem[et][eid][key] }
    end
  end
  self._mem[et][eid][key] = val
end

-- Limpa a VRAM de uma chave — força reload do banco na próxima leitura
-- ESSENCIAL: usado após gravar para evitar que a VRAM fique "presa"
--   com o valor antigo enquanto o banco tem o novo
function S:invalidate(et, eid, key)
  local t = self._mem[et]; if not t then return end
  local e = t[eid];        if not e then return end
  e[key] = nil
end

-- ── Transações ────────────────────────────────────────────────────────

local _txc = 0

function S:begin()
  _txc = _txc + 1
  self._snap[_txc] = {}
  return _txc
end

function S:commit(tx, sql_ops)
  local snap = self._snap[tx] or {}
  for _, v in ipairs(self._validators) do
    local ok, err = v(tx, snap, self._mem)
    if not ok then
      self:rollback(tx)
      return false, err or "validation_failed"
    end
  end
  if sql_ops then
    for _, op in ipairs(sql_ops) do self:_queue(op) end
  end
  self._snap[tx] = nil
  return true
end

function S:rollback(tx)
  local snap = self._snap[tx]; if not snap then return end
  for _, s in pairs(snap) do
    if self._mem[s.et] and self._mem[s.et][s.eid] then
      self._mem[s.et][s.eid][s.key] = s.prev
    end
  end
  self._snap[tx] = nil
  vHub.Logger:warn("state", "ROLLBACK tx=" .. tostring(tx))
end

function S:addValidator(fn)
  table.insert(self._validators, fn)
end

-- ── Batch SQL ─────────────────────────────────────────────────────────

function S:_queue(op)
  self._batchN = self._batchN + 1
  self._batch[self._batchN] = op
  if self._batchN >= BATCH_MAX then self:_flush() end
end

function S:_flush()
  if self._batchN == 0 or not self._ready or self._flushing then return end
  self._flushing = true
  local ops, n = self._batch, self._batchN
  self._batch, self._batchN = {}, 0
  Citizen.CreateThread(function()
    -- Driver:batch retorna (bool, lista_de_falhas):
    --   true,  {}          → tudo OK
    --   false, {op, op, …} → falha parcial: re-enfileira só as ops que falharam
    -- pcall captura exceções inesperadas (crash no driver, etc.)
    local pcall_ok, batch_ok, batch_falhas = pcall(self._driver.batch, self._driver, ops, n)
    if not pcall_ok then
      -- Exceção no driver: re-enfileira tudo (seguro de última instância)
      local pend, pendN = self._batch, self._batchN
      local fila = {}
      for i = 1, n     do fila[i]   = ops[i]  end
      for i = 1, pendN do fila[n+i] = pend[i] end
      self._batch, self._batchN = fila, n + pendN
      self._flushing = false
      vHub.Logger:warn("state", ("batch reenfileirado total=%d (excecao driver)"):format(n))
      return
    end
    if not batch_ok and type(batch_falhas) == "table" then
      -- Falha parcial: re-enfileira APENAS as ops que o driver reportou como falhas.
      -- Ops de outros jogadores que tiveram sucesso NÃO são re-enfileiradas.
      local nf = #batch_falhas
      local pend, pendN = self._batch, self._batchN
      local fila = {}
      for i = 1, nf    do fila[i]    = batch_falhas[i] end
      for i = 1, pendN do fila[nf+i] = pend[i] end
      self._batch, self._batchN = fila, nf + pendN
      self._flushing = false
      vHub.Logger:warn("state",
        ("batch parcial: %d/%d op(s) reenfileirada(s)"):format(nf, n))
      return
    end
    self._flushing = false
    if self._batchN > 0 then self:_flush() end
  end)
end

-- ── Serialização segura ────────────────────────────────────────────────
-- REGRA CRÍTICA: sempre serializa uma CÓPIA rasa da tabela para evitar
--   referências circulares e acúmulo de dados ao reler do banco.

local function _pack(val)
  if val == nil then return "" end
  -- Cópia rasa para tabelas: evita que a referência viva em VRAM
  --   seja serializada com subitems que já foram atualizados
  if type(val) == "table" then
    local copia = {}
    for k, v in pairs(val) do
      -- Não serializa subitems que sejam tabelas complexas aninhadas com
      -- chaves que começam com "_" (metadados internos)
      if type(k) == "string" and k:sub(1,1) == "_" then
        -- ignora campos internos como _dirty, _loaded etc
      else
        copia[k] = v
      end
    end
    return msgpack.pack(copia)
  end
  return msgpack.pack(val)
end

local function _unpack(raw)
  if type(raw) == "table" then
    -- BLOB retornado como array de bytes pelo oxmysql → converte para string
    local chars = {}
    for _, b in ipairs(raw) do chars[#chars+1] = string.char(b) end
    raw = table.concat(chars)
  end
  if type(raw) ~= "string" or raw == "" then return nil end
  local ok, val = pcall(msgpack.unpack, raw)
  if not ok then
    vHub.Logger:warn("state", "Falha ao desserializar msgpack — dado corrompido?")
    return nil
  end
  return val
end

-- ── API de dados (VRAM → DB fallback) ─────────────────────────────────
-- CORREÇÃO DO BUG DE DATATABLE CRESCENDO:
--   Antes: _set gravava na VRAM E no batch. Na próxima leitura,
--     a VRAM já tinha o valor (sem ir ao banco), mas o valor na VRAM
--     era a referência viva de user.data — que crescia a cada autosave
--     porque msgpack.pack serializa o estado atual da referência.
--   Agora: _set invalida a VRAM após enfileirar o batch.
--     A próxima leitura vai ao banco e recebe o valor limpo serializado.
--     Exceção: dados voláteis (ban.active, etc.) ficam na VRAM normalmente.

local function _get(et, eid, key, sql, idf)
  -- Tenta VRAM primeiro
  local v = S:get(et, eid, key)
  if v ~= nil then return v end

  -- Não está na VRAM — vai ao banco
  local ok, r = pcall(function()
    return Citizen.Await(S:scalar(sql, { [idf]=eid, key=key }))
  end)
  if not ok then return nil end

  local val = _unpack(r)
  -- Armazena na VRAM para próximas leituras na mesma sessão
  S:set(et, eid, key, val)
  return val
end

local function _set(et, eid, key, val, sql, idf, tx)
  -- Atualiza VRAM com o valor atual
  S:set(et, eid, key, val, tx)
  -- Enfileira escrita no banco com cópia serializada
  local packed = _pack(val)
  -- Guarda de tamanho: BLOB > 60 KB envenena toda a SQL transaction do batch.
  -- 61440 = 60 KB (4 KB abaixo do limite de 64 KB do tipo BLOB).
  if type(packed) == "string" and #packed > 61440 then
    vHub.Logger:error("state",
      ("BLOB overflow — op descartada et=%s eid=%s key=%s size=%d"):format(
        et, tostring(eid), tostring(key), #packed))
    return
  end
  S:_queue({ sql, { [idf]=eid, key=key, value=packed } })
  -- IMPORTANTE: invalida a VRAM logo após para que a próxima leitura
  --   vá ao banco e receba o dado limpo (evita acúmulo de referências)
  -- Exceção: não invalida se for uma chave "quente" (ban, whitelist)
  --   que precisa de acesso rápido sem round-trip
  if key ~= "ban.active" and key ~= "whitelist" and key ~= "permissions" then
    S:invalidate(et, eid, key)
  end
end

-- API pública — todas exigem Citizen.CreateThread no chamador
function vHub.getUData(uid, k)        vHub.assertThread(); return _get("ud",uid,k,"vh/get_ud","user_id") end
function vHub.setUData(uid, k, v, tx)                       _set("ud",uid,k,v,"vh/set_ud","user_id",tx)  end
function vHub.getCData(cid, k)        vHub.assertThread(); return _get("cd",cid,k,"vh/get_cd","char_id") end
function vHub.setCData(cid, k, v, tx)                       _set("cd",cid,k,v,"vh/set_cd","char_id",tx)  end
function vHub.getVData(pl, k)         vHub.assertThread(); return _get("vd",pl,k,"vh/get_vd","plate")    end
function vHub.setVData(pl, k, v, tx)                        _set("vd",pl,k,v,"vh/set_vd","plate",tx)     end
function vHub.getGData(k)             vHub.assertThread(); return _get("gd","__g",k,"vh/get_gd","dkey")  end
function vHub.setGData(k, v, tx)                            _set("gd","__g",k,v,"vh/set_gd","dkey",tx)   end
