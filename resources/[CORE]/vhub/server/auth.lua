-- server/auth.lua — Autenticação, sessões e personagens
-- BUGS CORRIGIDOS nesta versão:
--   1. datatable não acumula mais: user.data é uma tabela plana separada do VRAM
--   2. _resolveUID não cria duplicatas: INSERT IGNORE + espera alocador
--   3. selectCharacter: tonumber() em ambos os lados
--   4. connect tem guard de sessão dupla por source

local Auth = {}; Auth.__index = Auth; vHub.Auth = Auth

Auth._sessions = {}   -- { [source] = User }
Auth._byUID    = {}   -- { [user_id] = User }

-- ── Classe User ────────────────────────────────────────────────────────

local User = vHub.class()

function User:init(src, uid)
  self.source   = src
  self.id       = uid
  self.name     = GetPlayerName(src) or "desconhecido"
  self.endpoint = GetPlayerEP(src)   or "0.0.0.0"
  self.char_id  = nil
  self.spawns   = 0
  -- user.data é uma tabela plana de persistência do jogador
  -- NUNCA deve conter referências para outras tabelas vivas (evita acúmulo)
  self.data     = {}
end

-- ── Acesso a sessões ────────────────────────────────────────────────────

function Auth:getUID(src)  local s = self._sessions[src]; return s and s.id end
function Auth:getUser(src) return self._sessions[src] end
function Auth:byUID(uid)   return self._byUID[uid] end

-- ── Resolução de identifiers ─────────────────────────────────────────────
-- Prioridade: license > license2 > steam > discord > fivem > demais (sem ip:)

function Auth:_ids(src)
  local raw  = GetPlayerIdentifiers(src) or {}
  local ids  = {}
  local seen = {}

  local function add(id)
    if type(id) ~= "string" or id == "" then return end
    if id:find("^ip:") then return end
    if seen[id] then return end
    seen[id] = true
    ids[#ids+1] = id
  end

  for _, prefix in ipairs({"license:","license2:","steam:","discord:","fivem:"}) do
    for _, id in ipairs(raw) do
      if type(id)=="string" and id:sub(1,#prefix)==prefix then add(id) end
    end
  end
  for _, id in ipairs(raw) do add(id) end
  return ids
end

-- ── _resolveUID — DEVE estar em Citizen.CreateThread ─────────────────────

function Auth:_resolveUID(src)
  vHub.assertThread()
  local ids = self:_ids(src)
  if #ids == 0 then
    vHub.Logger:warn("auth",("src=%d sem identifiers válidos"):format(src))
    return nil
  end

  local uid = nil

  -- Fase 1: verifica TODOS os identifiers em UM round-trip (SELECT … IN (…))
  local q_name = vHub.SQL.uidByIdsIn(#ids)
  local ok, r = pcall(function()
    return Citizen.Await(vHub.State:query(q_name, ids))
  end)
  if ok and type(r) == "table" then
    -- Indexa rows por identifier para preservar a ordem de resolução por `ids`
    --   (mantém semântica original: primeiro id encontrado define uid; warn em divergência)
    local by_id = {}
    for _, row in ipairs(r) do
      by_id[tostring(row.identifier)] = tonumber(row.user_id)
    end
    for _, id in ipairs(ids) do
      local found = by_id[tostring(id)]
      if found then
        if uid and uid ~= found then
          vHub.Logger:warn("auth",
            ("src=%d conflito de UIDs (%d vs %d) — usando %d"):format(
              src, uid, found, uid))
        else
          uid = found
        end
      end
    end
  end

  -- Fase 2: usuário existente — vincula novos identifiers se necessário
  if uid then
    for _, id in ipairs(ids) do
      pcall(function()
        Citizen.Await(vHub.State:exec("vh/add_id", {user_id=uid, identifier=id}))
      end)
    end
    vHub.Logger:debug("auth",
      ("src=%d → uid=%d (existente)"):format(src, uid))
    return uid
  end

  -- Fase 3: usuário novo — aguarda alocador estar pronto
  local waited = 0
  while not vHub._next_user_id and waited < 5000 do
    Citizen.Wait(100); waited = waited + 100
  end
  if not vHub._next_user_id then
    vHub.Logger:error("auth",
      ("src=%d alocador user_id não inicializado após 5s"):format(src))
    return nil
  end

  -- Reserva o id (Lua é single-thread — sem race aqui)
  local uid_new = vHub._next_user_id
  vHub._next_user_id = vHub._next_user_id + 1

  -- INSERT IGNORE: não lança erro se o id já existir por algum motivo
  local ok_ins = pcall(function()
    Citizen.Await(vHub.State:exec("vh/create_user_with_id", {id=uid_new}))
  end)

  if not ok_ins then
    -- Fallback: AUTO_INCREMENT + last_insert_id em query separada
    vHub.Logger:warn("auth",
      ("src=%d INSERT id=%d falhou — usando AUTO_INCREMENT"):format(src, uid_new))
    local ok_fb = pcall(function()
      Citizen.Await(vHub.State:exec("vh/create_user", {}))
    end)
    if not ok_fb then
      vHub.Logger:error("auth", ("src=%d falha total ao criar usuário"):format(src))
      return nil
    end
    local ok_li, r_li = pcall(function()
      return Citizen.Await(vHub.State:query("vh/last_insert_id", {}))
    end)
    if not ok_li or not r_li or #r_li == 0 then
      vHub.Logger:error("auth", ("src=%d não recuperou id do fallback"):format(src))
      return nil
    end
    uid_new = tonumber(r_li[1].id)
    if uid_new and uid_new >= vHub._next_user_id then
      vHub._next_user_id = uid_new + 1
    end
  end

  uid = tonumber(uid_new)
  if not uid then return nil end

  -- Vincula todos os identifiers ao novo usuário
  for _, id in ipairs(ids) do
    pcall(function()
      Citizen.Await(vHub.State:exec("vh/add_id", {user_id=uid, identifier=id}))
    end)
  end

  vHub.Logger:info("auth",
    ("src=%d → uid=%d criado com %d identifier(s)"):format(src, uid, #ids))
  return uid
end

-- ── Connect — DEVE estar em Citizen.CreateThread ──────────────────────────
-- Ponto único de autenticação — chamado apenas do handler de vHub:ready

function Auth:connect(src)
  vHub.assertThread()
  vHub.Logger:debug("auth", ("connect tentativa src=%s"):format(tostring(src)))

  -- Guard: já tem sessão para este source
  if self._sessions[src] then
    vHub.Logger:debug("auth", ("connect sessão já existe src=%s uid=%s"):format(
      tostring(src), tostring(self._sessions[src] and self._sessions[src].id)))
    return self._sessions[src]
  end

  local uid = self:_resolveUID(src)
  if not uid then
    vHub.Logger:warn("auth", ("connect sem uid src=%s"):format(tostring(src)))
    return nil
  end

  -- Ban check (VRAM first)
  if vHub.getUData(uid, "ban.active") then
    local raw    = vHub.getUData(uid, "ban.reason")
    local reason = (type(raw) == "string" and raw ~= "") and raw
                   or (vHub.cfg.lang or {}).banned
                   or "Você foi banido."
    DropPlayer(src, tostring(reason))
    vHub.Notify:send("security",
      ("⚠️ Banido tentou entrar | ID:`%d` | %s"):format(uid, reason))
    return nil
  end

  -- Whitelist check
  if vHub.cfg.whitelist_enabled and not vHub.getUData(uid, "whitelist") then
    local msg = ((vHub.cfg.lang or {}).not_whitelisted or "Sem whitelist. ID: ") .. uid
    DropPlayer(src, msg)
    return nil
  end

  -- Derruba sessão duplicada do mesmo uid em outro source
  local prev = self._byUID[uid]
  if prev and prev.source ~= src then
    local msg = (vHub.cfg.lang or {}).duplicate_login or
      "Sessão encerrada: você entrou em outro lugar."
    vHub.Logger:info("auth",
      ("uid=%d já em src=%d — encerrando sessão anterior"):format(uid, prev.source))
    self:disconnect(prev.source, msg)
  end

  local user = User.new(src, uid)
  self._sessions[src] = user
  self._byUID[uid]    = user
  vHub.Logger:debug("auth", ("connect ok src=%s uid=%s"):format(tostring(src), tostring(uid)))

  -- Carrega datatable — cópia profunda via vHub.Utils.dataCopy
  --   (evita que user.data seja a mesma referência da VRAM)
  local dt_raw = vHub.getUData(uid, "datatable")
  if type(dt_raw) == "table" then
    for k, v in pairs(vHub.Utils.dataCopy(dt_raw)) do user.data[k] = v end
  end

  -- Atualiza datas de login sem criar referência circular
  user.data.last_login    = user.data.current_login
  user.data.current_login = os.date("%H:%M:%S %d/%m/%Y")

  -- Restaura permissões
  local perms = vHub.getUData(uid, "permissions")
  if type(perms) == "table" then
    for p in pairs(perms) do vHub.Kernel:grantPerm(uid, p) end
  end

  vHub.Notify:send("join",
    ("✅ **%s** | ID:`%d` | IP:`%s`"):format(user.name, uid, user.endpoint))
  TriggerEvent("vHub:playerJoin", user)
  return user
end

-- ── Disconnect ─────────────────────────────────────────────────────────────

function Auth:disconnect(src, reason)
  local user = self._sessions[src]; if not user then return end

  TriggerEvent("vHub:playerLeave", user, reason)

  -- Persiste datatable — cópia plana via vHub.Utils.dataCopy
  --   (evita acúmulo: grava cópia, não a referência viva)
  vHub.setUData(user.id, "datatable", vHub.Utils.dataCopy(user.data))
  vHub.State:_flush()

  vHub.Kernel:clearPerms(user.id)
  self._sessions[src]  = nil
  self._byUID[user.id] = nil

  vHub.Notify:send("leave",
    ("🚪 **%s** | ID:`%d` | %s"):format(
      user.name, user.id, tostring(reason or "disconnect")))
end

-- ── Personagens ────────────────────────────────────────────────────────────

function Auth:getCharacters(uid)
  vHub.assertThread()
  local ok, r = pcall(function()
    return Citizen.Await(vHub.State:query("vh/get_chars", {user_id=uid}))
  end)
  return (ok and r) and r or {}
end

local function validRequestId(request_id)
  return type(request_id) == "string"
    and #request_id >= 8
    and #request_id <= 64
    and request_id:match("^[%w%._:%-]+$") ~= nil
end

local function reserveCharacterId()
  local waited = 0
  while not vHub._next_char_id and waited < 5000 do
    Citizen.Wait(100)
    waited = waited + 100
  end
  if not vHub._next_char_id then return nil end

  local char_id = vHub._next_char_id
  vHub._next_char_id = char_id + 1
  return char_id
end

local function queryRows(name, params)
  local ok, rows = pcall(function()
    return Citizen.Await(vHub.State:query(name, params))
  end)
  if not ok or type(rows) ~= "table" then return nil end
  return rows
end

-- Retorna IDs canônicos do usuário online, limitados a três.
function Auth:getCharacterIds(src)
  vHub.assertThread()
  src = tonumber(src)
  local user = src and self:getUser(src) or nil
  if not user then return { ok = false, err = "offline" } end

  local rows = queryRows("vh/get_char_ids", { user_id = user.id })
  if not rows then return { ok = false, err = "storage" } end

  local items = {}
  for _, row in ipairs(rows) do
    local char_id = tonumber(row.id)
    if char_id then items[#items + 1] = char_id end
  end
  return { ok = true, items = items }
end

-- Cria personagem idempotente sob lock persistido e limite de três.
function Auth:createCharacterRequest(src, request_id)
  vHub.assertThread()
  src = tonumber(src)
  local user = src and self:getUser(src) or nil
  if not user then return { ok = false, err = "offline" } end
  if not validRequestId(request_id) then
    return { ok = false, err = "invalid_request" }
  end

  local params = { user_id = user.id, request_id = request_id }
  local previous = queryRows("vh/get_character_request", params)
  if not previous then return { ok = false, err = "storage" } end
  if previous[1] and tonumber(previous[1].char_id) then
    return { ok = true, char_id = tonumber(previous[1].char_id), replayed = true }
  end

  local char_id = reserveCharacterId()
  if not char_id then return { ok = false, err = "storage" } end

  local committed = vHub.SQL.createCharacterAtomic(user.id, char_id, request_id)
  local persisted = queryRows("vh/get_character_request", params)
  local stored_id = persisted and persisted[1] and tonumber(persisted[1].char_id) or nil
  if stored_id then
    local replayed = stored_id ~= char_id
    if not replayed then
      vHub.audit("vhub_login", "createCharacter", tostring(stored_id), tostring(src), nil, {
        user_id = user.id,
        request_id = request_id,
      })
    end
    return { ok = true, char_id = stored_id, replayed = replayed }
  end

  local countRows = queryRows("vh/count_chars", { user_id = user.id })
  local count = countRows and countRows[1] and tonumber(countRows[1].total) or nil
  if count and count >= 3 then return { ok = false, err = "limit" } end
  if not committed then return { ok = false, err = "storage" } end
  return { ok = false, err = "storage" }
end

-- Apaga personagem meio-criado/abandonado sob contrato do gate de login (ADR #76).
-- Idempotente por efeito (char_id monotônico + WHERE user_id no prepared). Recusa o char
-- ATIVO da sessão (ped/veículos keyed ao char). Toda deleção audita (R12).
function Auth:deleteCharacterRequest(src, char_id)
  vHub.assertThread()
  src = tonumber(src)
  char_id = tonumber(char_id)
  local user = src and self:getUser(src) or nil
  if not user then return { ok = false, err = "offline" } end
  if not char_id or char_id < 1 then return { ok = false, err = "invalid_request" } end

  -- Nunca apagar o personagem ativo da sessão online (estado vivo na VRAM).
  if char_id == tonumber(user.char_id) then return { ok = false, err = "in_use" } end

  -- Ownership em profundidade (além do WHERE user_id do prepared): char precisa ser do uid.
  -- Ausência = já apagado ou nunca foi dono → no-op idempotente (nada a fazer, sucesso).
  local rows = queryRows("vh/get_char_ids", { user_id = user.id })
  if not rows then return { ok = false, err = "storage" } end
  local owned = false
  for _, row in ipairs(rows) do
    if tonumber(row.id) == char_id then owned = true; break end
  end
  if not owned then return { ok = true, deleted = false, replayed = true } end

  local ok = pcall(function()
    Citizen.Await(vHub.State:exec("vh/delete_char", { id = char_id, user_id = user.id }))
  end)
  if not ok then return { ok = false, err = "storage" } end

  vHub.audit("vhub_login", "deleteCharacter", tostring(char_id), tostring(src),
    { user_id = user.id }, { deleted = true })
  return { ok = true, deleted = true }
end

-- Retorna a marca persistida de conclusão do criador do personagem atual.
function Auth:getSimsCreation(src)
  vHub.assertThread()
  src = tonumber(src)
  local user = src and self:getUser(src) or nil
  if not user then return { ok = false, err = "offline" } end
  local char_id = tonumber(user.char_id)
  if not char_id then return { ok = false, err = "no_character" } end

  local rows = queryRows("vh/get_sims_creation", { char_id = char_id })
  if not rows then return { ok = false, err = "storage" } end
  if not rows[1] then return { ok = true, created = false } end
  return { ok = true, created = true, apv = tonumber(rows[1].apv) }
end

-- persiste conclusão do criador; tolera replay de request anterior se apv bate.
function Auth:commitSimsCreation(src, request_id, apv)
  vHub.assertThread()
  src = tonumber(src)
  local user = src and self:getUser(src) or nil
  if not user then return { ok = false, err = "offline" } end
  local char_id = tonumber(user.char_id)
  if not char_id then return { ok = false, err = "no_character" } end

  apv = tonumber(apv)
  if not validRequestId(request_id) or not apv or apv ~= math.floor(apv)
    or apv < 1 or apv > 255 then
    return { ok = false, err = "invalid_request" }
  end

  local current = queryRows("vh/get_sims_creation", { char_id = char_id })
  if not current then return { ok = false, err = "storage" } end
  if current[1] then
    -- Personagem já completou criação. Se apv bate → replayed ok, independente do request_id
    -- (o mesmo personagem pode ter sido criado em outra sessão/request anterior).
    -- Conflict real: apv diferente = tentativa de sobrescrever com dados distintos.
    if tonumber(current[1].apv) == apv then
      return { ok = true, created = true, replayed = true }
    end
    return { ok = false, err = "conflict" }
  end

  local inserted, affected = pcall(function()
    return Citizen.Await(vHub.State:exec("vh/commit_sims_creation", {
      char_id = char_id,
      request_id = request_id,
      apv = apv,
    }))
  end)

  local persisted = queryRows("vh/get_sims_creation", { char_id = char_id })
  if persisted and persisted[1] then
    -- Aceita se o apv gravado bate (pode ser de request diferente por race benigna)
    if tonumber(persisted[1].apv) ~= apv then
      return { ok = false, err = "conflict" }
    end
    local replayed = tonumber(affected) == 0
    if not replayed then
      vHub.audit("vhub_sims", "commitSimsCreation", tostring(char_id), tostring(src), nil, {
        request_id = request_id,
        apv = apv,
      })
    end
    return { ok = true, created = true, replayed = replayed }
  end

  local requestRows = queryRows("vh/get_sims_creation_by_request", { request_id = request_id })
  if requestRows and requestRows[1] then return { ok = false, err = "conflict" } end
  if not inserted then return { ok = false, err = "storage" } end
  return { ok = false, err = "storage" }
end

function Auth:createCharacter(uid)
  vHub.assertThread()

  -- Aguarda alocador de char_id
  local waited = 0
  while not vHub._next_char_id and waited < 5000 do
    Citizen.Wait(100); waited = waited + 100
  end

  if vHub._next_char_id then
    local cid = vHub._next_char_id
    vHub._next_char_id = vHub._next_char_id + 1
    local ok = pcall(function()
      Citizen.Await(vHub.State:exec("vh/create_char_with_id",
        {id=cid, user_id=uid}))
    end)
    if ok then return cid end
  end

  -- Fallback AUTO_INCREMENT
  local ok = pcall(function()
    Citizen.Await(vHub.State:exec("vh/create_char", {user_id=uid}))
  end)
  if not ok then return nil end

  local ok2, r = pcall(function()
    return Citizen.Await(vHub.State:query("vh/last_insert_id", {}))
  end)
  if ok2 and r and #r > 0 then
    local cid = tonumber(r[1].id)
    if cid and vHub._next_char_id and cid >= vHub._next_char_id then
      vHub._next_char_id = cid + 1
    end
    return cid
  end
  return nil
end

-- CORREÇÃO: tonumber() em ambos os lados antes de comparar
function Auth:selectCharacter(user, cid)
  vHub.assertThread()
  local cid_n = tonumber(cid)
  if not cid_n then return false end

  local chars = self:getCharacters(user.id)
  for _, c in ipairs(chars) do
    if tonumber(c.id) == cid_n then
      user.char_id             = cid_n
      user.data.last_character = cid_n
      TriggerEvent("vHub:characterLoad", user)
      vHub.Kernel:emit(user.source, "vHub:charSelected", cid_n)
      return true
    end
  end
  return false
end

-- ── Ban / Unban ─────────────────────────────────────────────────────────────

function Auth:ban(uid, reason, by)
  local tx = vHub.State:begin()
  local reason_str = type(reason) == "string" and reason or tostring(reason or "banido")
  local by_str     = type(by)     == "string" and by     or tostring(by     or "admin")
  vHub.setUData(uid, "ban.active", true,       tx)
  vHub.setUData(uid, "ban.reason", reason_str, tx)
  vHub.setUData(uid, "ban.by",     by_str,     tx)
  vHub.State:commit(tx)

  local user = self._byUID[uid]
  if user then
    DropPlayer(user.source, reason or "Banido.")
  end
  vHub.Notify:send("ban",
    ("🔨 Banido: ID`%d` | %s | por %s"):format(uid, tostring(reason), tostring(by)))
end

function Auth:unban(uid)
  local tx = vHub.State:begin()
  vHub.setUData(uid, "ban.active", nil, tx)
  vHub.setUData(uid, "ban.reason", nil, tx)
  vHub.setUData(uid, "ban.by",     nil, tx)
  vHub.State:commit(tx)
end
