-- server/sql.lua — todas as queries nomeadas do vHub
-- Depende de: server/state.lua (S = vHub.State já inicializado)
-- REGRA: nunca use LAST_INSERT_ID() sem transação explícita —
--   o alocador server-side (vHub._next_user_id / _next_char_id) evita a race.

local S = vHub.State

-- ── Usuários ──────────────────────────────────────────────────────────

-- Cria usuário com id explícito (alocador server-side — sem LAST_INSERT_ID)
-- INSERT IGNORE: se por alguma race o id já existir, não lança erro
S:prepare("vh/create_user_with_id",
  "INSERT IGNORE INTO vh_users(id, created_at) VALUES(@id, NOW())")

-- Fallback: criação sem id (banco gera AUTO_INCREMENT)
-- Usado APENAS se o alocador ainda não estiver pronto
S:prepare("vh/create_user",
  "INSERT INTO vh_users(created_at) VALUES(NOW())")

-- Busca o maior id para seed do alocador na inicialização
S:prepare("vh/max_userid",
  "SELECT COALESCE(MAX(id), 0) AS maxid FROM vh_users")

-- Pega o LAST_INSERT_ID após insert sem id explícito (query separada, mesma conexão)
S:prepare("vh/last_insert_id",
  "SELECT LAST_INSERT_ID() AS id")

-- Vincula um identifier (license:, steam:, etc.) a um user_id
-- INSERT IGNORE: se o identifier já existe, não lança erro
S:prepare("vh/add_id",
  "INSERT IGNORE INTO vh_user_ids(identifier, user_id) VALUES(@identifier, @user_id)")

-- Resolve identifier → user_id
S:prepare("vh/uid_by_id",
  "SELECT user_id FROM vh_user_ids WHERE identifier = @identifier")

-- Resolve N identifiers em 1 round-trip (lazy-prepared por N).
-- Uso: local name = vHub.SQL.uidByIdsIn(#ids); S:query(name, ids)
vHub.SQL = vHub.SQL or {}
function vHub.SQL.uidByIdsIn(n)
  local name = "vh/uid_by_ids_in_" .. tostring(n)
  if not S._prepared[name] then
    local qs = {}
    for i = 1, n do qs[i] = "?" end
    S:prepare(name,
      "SELECT identifier, user_id FROM vh_user_ids WHERE identifier IN ("..table.concat(qs,",")..")")
  end
  return name
end

-- ── Personagens ───────────────────────────────────────────────────────

-- Busca o maior char_id para seed do alocador
S:prepare("vh/max_charid",
  "SELECT COALESCE(MAX(id), 0) AS maxid FROM vh_characters")

-- Cria personagem com id explícito (alocador server-side)
S:prepare("vh/create_char_with_id",
  "INSERT IGNORE INTO vh_characters(id, user_id, created_at) VALUES(@id, @user_id, NOW())")

-- Fallback sem id explícito
S:prepare("vh/create_char",
  "INSERT INTO vh_characters(user_id, created_at) VALUES(@user_id, NOW())")

-- Lista personagens de um usuário por id
S:prepare("vh/get_chars",
  "SELECT id FROM vh_characters WHERE user_id = @user_id ORDER BY id")

-- Lista no máximo os três IDs públicos do usuário.
S:prepare("vh/get_char_ids",
  "SELECT id FROM vh_characters WHERE user_id = @user_id ORDER BY id LIMIT 3")

-- Recupera a criação idempotente de personagem pelo request_id.
S:prepare("vh/get_character_request",
  "SELECT char_id FROM vh_character_requests " ..
  "WHERE user_id = @user_id AND request_id = @request_id LIMIT 1")

-- Conta personagens para distinguir limite de falha de persistência.
S:prepare("vh/count_chars",
  "SELECT COUNT(*) AS total FROM vh_characters WHERE user_id = @user_id")

-- Deleta personagem (valida ownership)
S:prepare("vh/delete_char",
  "DELETE FROM vh_characters WHERE id = @id AND user_id = @user_id")

-- Lê a conclusão do criador pertencente ao personagem.
S:prepare("vh/get_sims_creation",
  "SELECT request_id, apv FROM vh_sims_creation WHERE char_id = @char_id LIMIT 1")

-- Detecta reutilização global de request_id por outro personagem.
S:prepare("vh/get_sims_creation_by_request",
  "SELECT char_id, apv FROM vh_sims_creation WHERE request_id = @request_id LIMIT 1")

-- Grava a conclusão uma única vez; o chamador relê antes do ACK.
S:prepare("vh/commit_sims_creation",
  "INSERT IGNORE INTO vh_sims_creation(char_id, request_id, apv, created_at) " ..
  "VALUES(@char_id, @request_id, @apv, NOW())")

local SQL_LOCK_USER =
  "SELECT id FROM vh_users WHERE id = @user_id FOR UPDATE"
local SQL_CREATE_CHAR_CAPPED =
  "INSERT INTO vh_characters(id, user_id, created_at) " ..
  "SELECT @char_id, @user_id, NOW() FROM DUAL " ..
  "WHERE (SELECT COUNT(*) FROM vh_characters WHERE user_id = @user_id) < 3 " ..
  "AND NOT EXISTS (SELECT 1 FROM vh_character_requests " ..
  "WHERE user_id = @user_id AND request_id = @request_id)"
local SQL_RECORD_CHAR_REQUEST =
  "INSERT IGNORE INTO vh_character_requests(user_id, request_id, char_id, created_at) " ..
  "SELECT @user_id, @request_id, @char_id, NOW() FROM vh_characters " ..
  "WHERE id = @char_id AND user_id = @user_id"

local function awaitTransaction(operations)
  local pending = promise.new()
  local resolved = false

  local function resolve(result)
    if resolved then return end
    resolved = true
    pending:resolve(result == true)
  end

  Citizen.SetTimeout(15000, function() resolve(false) end)
  local dispatched = pcall(function()
    exports.oxmysql:transaction(operations, nil, resolve)
  end)
  if not dispatched then resolve(false) end
  return Citizen.Await(pending)
end

-- Cria personagem e request na mesma transação após serializar pelo usuário.
function vHub.SQL.createCharacterAtomic(user_id, char_id, request_id)
  vHub.assertThread()
  local parameters = {
    user_id = user_id,
    char_id = char_id,
    request_id = request_id,
  }
  return awaitTransaction({
    { SQL_LOCK_USER, parameters },
    { SQL_CREATE_CHAR_CAPPED, parameters },
    { SQL_RECORD_CHAR_REQUEST, parameters },
  })
end

-- ── Dados KV (user / char / global) ──────────────────────────────────

-- dvalue é BLOB — msgpack binário (pós-freeze v1.0; antes era MEDIUMBLOB)
S:prepare("vh/set_ud",
  "REPLACE INTO vh_user_data(user_id, dkey, dvalue) VALUES(@user_id, @key, @value)")
S:prepare("vh/get_ud",
  "SELECT dvalue FROM vh_user_data WHERE user_id = @user_id AND dkey = @key")

S:prepare("vh/set_cd",
  "REPLACE INTO vh_char_data(char_id, dkey, dvalue) VALUES(@char_id, @key, @value)")
S:prepare("vh/get_cd",
  "SELECT dvalue FROM vh_char_data WHERE char_id = @char_id AND dkey = @key")

S:prepare("vh/set_gd",
  "REPLACE INTO vh_global_data(dkey, dvalue) VALUES(@dkey, @value)")
S:prepare("vh/get_gd",
  "SELECT dvalue FROM vh_global_data WHERE dkey = @dkey")

-- ── Veículos ──────────────────────────────────────────────────────────

S:prepare("vh/veh_create",
  "INSERT IGNORE INTO vh_vehicles(plate, key_uid) VALUES(@plate, @key_uid)")
S:prepare("vh/veh_set_key",
  "UPDATE vh_vehicles SET key_uid = @key_uid WHERE plate = @plate")
S:prepare("vh/veh_key",
  "SELECT key_uid FROM vh_vehicles WHERE plate = @plate")
S:prepare("vh/veh_by_key",
  "SELECT plate FROM vh_vehicles WHERE key_uid = @key_uid")
-- NOTA(hotfix 2026-06-04): estes dois usavam @dkey, mas o _set/_get compartilhado em
-- state.lua SEMPRE liga o parametro como `key` (igual a user/char data acima). Com @dkey
-- o bind ficava nulo → escrita falhava ("Column 'dkey' cannot be null") e leitura filtrava
-- dkey=NULL (nunca casava) → vh_vehicle_data ficou morto desde o freeze. Alinhado a @key.
S:prepare("vh/set_vd",
  "REPLACE INTO vh_vehicle_data(plate, dkey, dvalue) VALUES(@plate, @key, @value)")
S:prepare("vh/get_vd",
  "SELECT dvalue FROM vh_vehicle_data WHERE plate = @plate AND dkey = @key")

-- ── Audit unificado (ADR #42) ─────────────────────────────────────────

-- Append-only: nunca há UPDATE/DELETE preparado para vh_audit por construção
S:prepare("vh/audit_insert",
  "INSERT INTO vh_audit(actor, action, target, source, before_json, after_json) " ..
  "VALUES(@actor, @action, @target, @source, @before_json, @after_json)")
