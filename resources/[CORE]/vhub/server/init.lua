-- server/init.lua — Complementa vHub (não sobrescreve o que os shared criaram)
-- REGRA CRÍTICA: os shared_scripts já criaram vHub com Logger, Utils, E.
--   Este arquivo é carregado via load() pelo base.lua com _ENV = _G.
--   rawget(_G, "vHub") retorna o vHub dos shared — NUNCA criar um novo.

-- Pega o vHub existente dos shared_scripts
local vHub = rawget(_G, "vHub")
if type(vHub) ~= "table" then
  -- Segurança: se por algum motivo não existir, cria vazio
  vHub = {}
  rawset(_G, "vHub", vHub)
  print("[vHub][BOOT][AVISO] vHub não encontrado nos shared — criado vazio")
end

-- ── OOP helper ──────────────────────────────────────────────────────────

local function class(parent)
  local C = {}; C.__index = C
  if parent then setmetatable(C, { __index = parent }) end
  C.new = function(...)
    local o = setmetatable({}, C)
    if o.init then o:init(...) end
    return o
  end
  C.is = function(o) return getmetatable(o) == C end
  return C
end
vHub.class = class

-- ── assertThread ────────────────────────────────────────────────────────

local function assertThread()
  if Citizen and type(Citizen.GetCurrentThread) == "function" then
    assert(Citizen.GetCurrentThread() ~= nil,
      "[vHub] Esta função exige Citizen.CreateThread")
  end
end
vHub.assertThread = assertThread

-- ── Loader de módulos server/ ────────────────────────────────────────────
-- Carrega cada módulo dentro do mesmo _ENV global para que todos
-- acessem o mesmo vHub sem precisar de require().

local RESOURCE = GetCurrentResourceName()

local function loadmod(path)
  local code = LoadResourceFile(RESOURCE, path)
  if not code or code == "" then
    error(("[vHub][BOOT] módulo ausente: %s"):format(path), 2)
  end
  -- _ENV aqui é _G — módulos enxergam o mesmo vHub global
  local fn, err = load(code, ("@%s/%s"):format(RESOURCE, path), "t", _ENV)
  if not fn then
    error(("[vHub][BOOT] erro de compilação em %s:\n%s"):format(path, err), 2)
  end
  local ok, res = pcall(fn)
  if not ok then
    error(("[vHub][BOOT] erro ao executar %s:\n%s"):format(path, res), 2)
  end
  return res
end

-- Ordem obrigatória — cada módulo depende do anterior
loadmod("server/kernel.lua")   -- event bus, rate limit, perms, exports
loadmod("server/state.lua")    -- VRAM, TX, batch SQL, get/set*Data
loadmod("server/sql.lua")      -- S:prepare() de todas as queries
loadmod("server/notify.lua")   -- webhooks Discord com retry
loadmod("server/auth.lua")     -- identidade, sessão, personagem, ban
loadmod("server/vehicle.lua")  -- entidade de veículo, State Bags
loadmod("server/security.lua") -- payload, ACE, invoker whitelist
loadmod("server/boot.lua")     -- net events, autosave, lifecycle
loadmod("server/exports.lua")
-- spawn é responsabilidade de vhub_player_state (resource externo) — sem duplicação no core

-- ── Export: registerStateDriver ──────────────────────────────────────────
-- Permite que vhub_oxmysql externo registre um driver alternativo.
-- Só aceita se o driver interno ainda não está pronto.

exports("registerStateDriver", function(drv)
  if type(drv) ~= "table" then return false end
  if type(drv.init) ~= "function" then return false end
  if type(drv.prepare) ~= "function" then return false end
  if type(drv.query) ~= "function" then return false end
  if type(drv.batch) ~= "function" then return false end
  if vHub.State and vHub.State._ready then
    return false  -- driver interno já ativo — ignora silenciosamente
  end
  if vHub.State then
    vHub.State:setDriver(drv)
    return true
  end
  return false
end)

-- Export: acesso ao namespace vHub (para debug e vhub_oxmysql)
exports("getVHub", function() return vHub end)

return vHub
