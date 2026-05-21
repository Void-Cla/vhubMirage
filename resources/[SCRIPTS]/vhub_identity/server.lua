-- vhub_identity/server.lua
-- Responsabilidade: identidade do personagem (nome, sobrenome, idade, registro, telefone).
-- Autoridade: servidor — cliente jamais altera dados de identidade.
-- Dependências: vhub (Auth, characterLoad, playerSpawn), oxmysql (persistência própria).
-- Persistência: tabela dedicada vh_identity via oxmysql direto.
-- NOTA ARQUITETURAL: usa oxmysql sem passar pelo vhub.State porque o
--   FiveM serializa tabelas em exports cross-resource — chamadas como
--   S:prepare() de fora do vhub não persistem no _prepared real.

local _vHub   = nil
local _pronto = false

-- ── Configuração ──────────────────────────────────────────────────────────────

local CFG = {
  custo_nova_identidade = 0,
  formato_telefone      = "DDD-DDDD",

  primeiros_nomes = {
    "Carlos","João","Pedro","Lucas","Matheus","Rafael","Gabriel","Felipe","André",
    "Bruno","Diego","Eduardo","Fernando","Gustavo","Henrique","Igor","Jorge",
    "Leandro","Marcos","Nelson","Otávio","Paulo","Ricardo","Sérgio","Thiago",
    "Ana","Beatriz","Camila","Daniela","Eduarda","Fernanda","Gabriela","Helena",
    "Isabela","Juliana","Larissa","Mariana","Natália","Patrícia","Roberta","Sandra",
  },
  ultimos_nomes = {
    "Silva","Santos","Oliveira","Souza","Rodrigues","Ferreira","Alves","Pereira",
    "Lima","Gomes","Costa","Ribeiro","Martins","Carvalho","Almeida","Lopes",
    "Sousa","Fernandes","Vieira","Barbosa","Rocha","Dias","Nascimento","Andrade",
    "Moreira","Nunes","Marques","Machado","Mendes","Freitas","Cardoso","Ramos",
  },
}

-- ── Helpers SQL (oxmysql direto, callback → promise) ─────────────────────────

-- Executa SELECT múltiplas linhas; retorna {} em caso de falha
local function _query(sql, params)
  local p = promise.new()
  exports.oxmysql:query(sql, params or {}, function(r) p:resolve(r or {}) end)
  return Citizen.Await(p)
end

-- Executa INSERT/UPDATE/DELETE; retorna affectedRows (number) ou 0
local function _execute(sql, params)
  local p = promise.new()
  exports.oxmysql:execute(sql, params or {}, function(r) p:resolve(r or 0) end)
  return Citizen.Await(p)
end

-- ── Helpers de geração ───────────────────────────────────────────────────────

local function gerarString(formato)
  local s = ""
  for i = 1, #formato do
    local c = formato:sub(i, i)
    if     c == "D" then s = s .. tostring(math.random(0, 9))
    elseif c == "L" then s = s .. string.char(65 + math.random(0, 25))
    else                 s = s .. c
    end
  end
  return s
end

local function gerarRegistroUnico()
  for _ = 1, 20 do
    local reg = gerarString("DDDDLL")
    local r   = _query("SELECT char_id FROM vh_identity WHERE registration = ? LIMIT 1", { reg })
    if #r == 0 then return reg end
  end
  return gerarString("DDD") .. tostring(os.time() % 1000)
end

local function gerarTelefoneUnico()
  for _ = 1, 20 do
    local tel = gerarString(CFG.formato_telefone)
    local r   = _query("SELECT char_id FROM vh_identity WHERE phone = ? LIMIT 1", { tel })
    if #r == 0 then return tel end
  end
  return gerarString("DDD") .. "-" .. tostring(os.time() % 10000)
end

local function nomeAleatorio()
  return
    CFG.primeiros_nomes[math.random(#CFG.primeiros_nomes)],
    CFG.ultimos_nomes[math.random(#CFG.ultimos_nomes)]
end

-- Sanitiza string: só letras (incluindo acentuadas), espaços e hífens
local function sanitizaNome(s)
  if type(s) ~= "string" then return "" end
  return s:match("^%s*(.-)%s*$"):gsub("[^%a%sÀ-ÿ%-]", ""):sub(1, 50)
end

-- ── Persistência ─────────────────────────────────────────────────────────────

local function upsertIdentity(char_id, ident)
  _execute(
    "INSERT INTO vh_identity(char_id, firstname, lastname, age, registration, phone) " ..
    "VALUES(?, ?, ?, ?, ?, ?) " ..
    "ON DUPLICATE KEY UPDATE firstname=VALUES(firstname), lastname=VALUES(lastname), " ..
    "age=VALUES(age), registration=VALUES(registration), phone=VALUES(phone)",
    { char_id, ident.firstname, ident.lastname, ident.age, ident.registration, ident.phone })
end

local function getIdentity(char_id)
  local r = _query(
    "SELECT firstname, lastname, age, registration, phone " ..
    "FROM vh_identity WHERE char_id = ? LIMIT 1",
    { char_id })
  return r[1]
end

-- ── Inicialização ────────────────────────────────────────────────────────────

AddEventHandler("onResourceStart", function(res)
  if res ~= GetCurrentResourceName() then return end

  Citizen.CreateThread(function()
    -- Aguarda vHub disponível (precisamos do Auth e do Logger)
    local tentativas = 0
    while tentativas < 50 do
      local ok, vh = pcall(function() return exports.vhub:getVHub() end)
      if ok and type(vh) == "table" and vh.Auth then
        _vHub = vh
        break
      end
      Citizen.Wait(200)
      tentativas = tentativas + 1
    end

    if not _vHub then
      print("[vhub_identity][ERRO] vHub não disponível após 10s")
      return
    end

    -- Aplica schema via oxmysql direto (resource carrega o .sql)
    local schema = LoadResourceFile(GetCurrentResourceName(), "sql/schema.sql")
    if type(schema) ~= "string" or schema == "" then
      print("[vhub_identity][ERRO] sql/schema.sql não encontrado")
      return
    end
    _execute(schema, {})

    _pronto = true
    print("[vhub_identity] Pronto — schema aplicado.")
  end)
end)

-- ── Carregamento de identidade ───────────────────────────────────────────────

AddEventHandler("vHub:characterLoad", function(user)
  if not user or not user.char_id then return end
  if not _pronto then
    print(("[vhub_identity] AVISO: characterLoad antes de _pronto (uid=%d)"):format(
      user.id or 0))
    return
  end

  Citizen.CreateThread(function()
    local row = getIdentity(user.char_id)
    local identity

    if row then
      identity = {
        firstname    = row.firstname,
        lastname     = row.lastname,
        age          = tonumber(row.age),
        registration = row.registration,
        phone        = row.phone,
      }
    else
      -- Primeiro acesso: gera identidade aleatória e persiste imediatamente
      local fn, ln = nomeAleatorio()
      identity = {
        firstname    = fn,
        lastname     = ln,
        age          = math.random(18, 45),
        registration = gerarRegistroUnico(),
        phone        = gerarTelefoneUnico(),
      }
      upsertIdentity(user.char_id, identity)
    end

    user.identity = identity
    TriggerClientEvent("vhub_identity:load", user.source, identity)

    if _vHub and _vHub.Logger then
      _vHub.Logger:debug("identity",
        ("uid=%d char=%d identidade carregada: %s %s"):format(
          user.id, user.char_id, identity.firstname, identity.lastname))
    end
  end)
end)

-- Reenvia identidade ao spawnar (cliente pode ter perdido o evento anterior)
AddEventHandler("vHub:playerSpawn", function(user, _)
  if not user or not user.identity then return end
  TriggerClientEvent("vhub_identity:load", user.source, user.identity)
end)

-- ── Net events ───────────────────────────────────────────────────────────────

-- Solicita própria identidade (cliente recém-conectado)
RegisterNetEvent("vhub_identity:get")
AddEventHandler("vhub_identity:get", function()
  local src  = source
  if not _vHub then return end
  local user = _vHub.Auth:getUser(src)
  if not user or not user.identity then return end
  TriggerClientEvent("vhub_identity:load", src, user.identity)
end)

-- Atualiza nome/sobrenome/idade via prefeitura
RegisterNetEvent("vhub_identity:update")
AddEventHandler("vhub_identity:update", function(dados)
  local src = source
  if type(dados) ~= "table" or not _pronto or not _vHub then return end

  local user = _vHub.Auth:getUser(src)
  if not user or not user.char_id or not user.identity then return end

  local fn  = sanitizaNome(dados.firstname or "")
  local ln  = sanitizaNome(dados.lastname  or "")
  local age = tonumber(dados.age) or 0

  if #fn < 2 or #ln < 2 then
    TriggerClientEvent("vhub_identity:error", src, "nome_invalido")
    return
  end
  if age < 16 or age > 120 then
    TriggerClientEvent("vhub_identity:error", src, "idade_invalida")
    return
  end

  if CFG.custo_nova_identidade > 0 then
    local pagou = pcall(function()
      assert(exports.vhub_money:tryPayment(src, CFG.custo_nova_identidade))
    end)
    if not pagou then
      TriggerClientEvent("vhub_identity:error", src, "sem_dinheiro")
      return
    end
  end

  user.identity.firstname = fn
  user.identity.lastname  = ln
  user.identity.age       = age

  Citizen.CreateThread(function()
    upsertIdentity(user.char_id, user.identity)
  end)

  TriggerClientEvent("vhub_identity:load", src, user.identity)
end)

-- ── Exports ──────────────────────────────────────────────────────────────────

-- Retorna identidade de um jogador online por source
exports("getIdentity", function(src)
  if not _vHub then return nil end
  local user = _vHub.Auth:getUser(src)
  return user and user.identity or nil
end)

-- Retorna nome completo formatado de um jogador
exports("getFullName", function(src)
  if not _vHub then return "Desconhecido" end
  local user = _vHub.Auth:getUser(src)
  if not user or not user.identity then return "Desconhecido" end
  return user.identity.firstname .. " " .. user.identity.lastname
end)

-- Busca char_id pelo número de registro (para polícia verificar veículos)
exports("getCharByRegistration", function(registration)
  if not _pronto or type(registration) ~= "string" then return nil end
  local r = _query(
    "SELECT char_id FROM vh_identity WHERE registration = ? LIMIT 1",
    { registration })
  return r[1] and tonumber(r[1].char_id) or nil
end)

-- Busca char_id por número de telefone
exports("getCharByPhone", function(phone)
  if not _pronto or type(phone) ~= "string" then return nil end
  local r = _query(
    "SELECT char_id FROM vh_identity WHERE phone = ? LIMIT 1",
    { phone })
  return r[1] and tonumber(r[1].char_id) or nil
end)
