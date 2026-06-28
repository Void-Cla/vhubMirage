-- server/dominio/fluxo.lua — máquina de estados da sessão de entrada.
-- Orquestra: login → seleção de char (verdade DELEGADA ao core) → handoff p/ o
-- selector. NÃO toca ped, bucket nem coordenada (donos: player_state/selector).

VHubLogin = VHubLogin or {}

local F = {}; VHubLogin.Fluxo = F
local CFG = VHubLogin.Config

-- [src] = { step="login"|"charselect"|"spawning", uid, account, deadline_ms }
F.sessions = {}

-- Trava por USERNAME (anti brute-force com rotação de src; o rate por-src vive no
-- init.lua). [username_lower] = { n, until_ms }
local _userFails = {}
local function userBlocked(u)
  local e = _userFails[u]
  return e ~= nil and e.until_ms ~= nil and GetGameTimer() < e.until_ms
end
local function userFail(u)
  local e = _userFails[u] or { n = 0 }
  e.n = e.n + 1
  if e.n >= (CFG.lockout.fails or 5) then
    e.until_ms = GetGameTimer() + (CFG.lockout.ms or 60000)
    e.n = 0
  end
  _userFails[u] = e
end
local function userOK(u) _userFails[u] = nil end


-- ============================================================
-- PONTES PARA O CORE (sem reimplementar nada)
-- ============================================================

local function uidOf(src)
  local ok, uid = pcall(function() return exports.vhub:getUID(src) end)
  return ok and uid or nil
end

local function userOf(src)
  local ok, u = pcall(function() return exports.vhub:getUser(src) end)
  return ok and u or nil
end

local function core()
  local ok, vh = pcall(function() return exports.vhub:getVHub() end)
  return (ok and type(vh) == "table") and vh or nil
end


-- ============================================================
-- ESTADO
-- ============================================================

function F.get(src) return F.sessions[src] end

-- autenticado nesta sessão? (passou da etapa de login)
function F.isAuth(src)
  local s = F.sessions[src]
  return s ~= nil and s.step ~= "login"
end

function F.limpar(src) F.sessions[src] = nil end

-- abre o gate (chamado pelo chooseSpawn). retorna true se abriu login agora.
function F.iniciar(src)
  if F.isAuth(src) then return false end
  local uid = uidOf(src)
  if not uid then return false end
  F.sessions[src] = {
    step     = "login",
    uid      = uid,
    deadline = GetGameTimer() + (CFG.auth_deadline * 1000),
  }
  return true
end

-- DropPlayer se estourar o prazo sem concluir (preempta o fallback do player_state
-- que spawnaria um não-autenticado). Sem polling eterno: sai ao concluir/cair.
function F.armarDeadline(src)
  Citizen.CreateThread(function()
    while true do
      Citizen.Wait(1000)
      local s = F.sessions[src]
      if not s or s.step == "spawning" then return end
      if GetGameTimer() >= s.deadline then
        F.sessions[src] = nil
        DropPlayer(tostring(src), "Tempo de login esgotado.")
        return
      end
    end
  end)
end


-- ============================================================
-- TRANSIÇÕES
-- ============================================================

-- login de conta existente
function F.autenticar(src, username, password)
  local s = F.sessions[src]
  if not s or s.step ~= "login" then return false, "estado_invalido" end
  local ukey = (type(username) == "string") and username:lower() or ""
  if userBlocked(ukey) then return false, "bloqueado_temporario" end
  local acc, err = VHubLogin.Contas.autenticar(s.uid, username, password)
  if not acc then userFail(ukey); return false, err end
  userOK(ukey)
  s.account = acc
  s.step    = "charselect"
  return true
end

-- registro de conta nova → auto-login
function F.registrar(src, username, password)
  local s = F.sessions[src]
  if not s or s.step ~= "login" then return false, "estado_invalido" end
  local ok, err = VHubLogin.Contas.registrar(s.uid, username, password)
  if not ok then return false, err end
  local acc = VHubLogin.Contas.autenticar(s.uid, username, password)
  if not acc then return false, "falha_pos_registro" end
  s.account = acc
  s.step    = "charselect"
  return true
end

-- lista personagens do uid (verdade do core; não reimplementa multichar)
function F.personagens(src)
  local s = F.sessions[src]
  if not s or s.step ~= "charselect" then return nil end
  local vh = core(); if not vh then return nil end
  return vh.Auth:getCharacters(s.uid)
end

-- seleciona char: o CORE valida ownership e grava (Auth:selectCharacter).
function F.selecionar(src, cid)
  local s = F.sessions[src]
  if not s or s.step ~= "charselect" then return false, "estado_invalido" end
  local vh = core(); if not vh then return false, "core_indisponivel" end
  local user = userOf(src); if not user then return false, "sem_user" end
  if not vh.Auth:selectCharacter(user, cid) then return false, "char_invalido" end
  s.step = "spawning"
  return true
end

return F
