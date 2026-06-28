-- server/init.lua — lifecycle + GATE de entrada + net handlers.
-- O core auto-spawna; o único ponto de interceptação é o vhub_player_state:
-- chooseSpawn (a junta do hold/999). Aqui o gate decide: não-autenticado → abre
-- login (ped já em hold); autenticado → manda o cliente abrir o selector direto.

VHubLogin = VHubLogin or {}

local CFG = VHubLogin.Config
local F   = VHubLogin.Fluxo

local _ready = false


-- ============================================================
-- LIFECYCLE
-- ============================================================

AddEventHandler("onResourceStart", function(res)
  if res ~= GetCurrentResourceName() then return end

  -- schema idempotente
  local schema = LoadResourceFile(res, "sql/login_accounts.sql")
  if schema and #schema > 0 then
    exports.oxmysql:query(schema, {}, function() end)
  end

  -- espera o core ficar pronto (mesmo padrão do player_state)
  Citizen.CreateThread(function()
    local tries = 0
    while tries < 50 do
      local ok, vh = pcall(function() return exports.vhub:getVHub() end)
      if ok and type(vh) == "table" and vh.Auth then
        _ready = true
        print("[vhub_login] Pronto (gate de entrada). enabled=" .. tostring(CFG.enabled))
        return
      end
      Citizen.Wait(200); tries = tries + 1
    end
    print("[vhub_login][ERRO] core vHub indisponível após 10s")
  end)
end)


-- ============================================================
-- GATE — intercepta o pedido de spawn do player_state
-- ============================================================

AddEventHandler("vhub_player_state:chooseSpawn", function(src)
  if not CFG.enabled then return end                 -- gate desligado → inerte (selector abre)
  if not _ready then
    -- gate LIGADO mas core indisponível: FAIL-CLOSED. Um gate de credencial NUNCA
    -- pode deixar entrar sem login; melhor recusar e pedir reconexão.
    DropPlayer(tostring(src), "Servidor inicializando — reconecte em instantes.")
    return
  end
  Citizen.CreateThread(function()
    if F.isAuth(src) then
      TriggerClientEvent("vhub_login:proceedSpawn", src)   -- já logado → selector direto
      return
    end
    if F.iniciar(src) then
      F.armarDeadline(src)
      TriggerClientEvent("vhub_login:open", src)           -- abre NUI de login
    end
  end)
end)

-- O selector (Opção A) consulta isto para ceder a abertura ao gate SÓ quando ele
-- está realmente ativo. enabled=false ou core não pronto → selector abre normal
-- (estado intermediário seguro: ninguém fica preso sem login).
-- Liga = enabled (desacoplado de _ready): o selector cede sempre que o gate está
-- ligado; se o core cair, o handler acima faz fail-closed (DropPlayer), nunca
-- deixa o selector spawnar um não-autenticado.
exports("isGateActive", function() return CFG.enabled == true end)


-- ============================================================
-- ANTI BRUTE-FORCE (por src)
-- ============================================================

local _rl = {}
local function rateOK(src)
  local now = GetGameTimer()
  local e = _rl[src]
  if not e or (now - e.win) > CFG.rate.window then
    _rl[src] = { win = now, hits = 1 }
    return true
  end
  e.hits = e.hits + 1
  return e.hits <= CFG.rate.max
end


-- ============================================================
-- NET HANDLERS (cliente → servidor)
-- ============================================================

RegisterNetEvent("vhub_login:tryLogin")
AddEventHandler("vhub_login:tryLogin", function(username, password)
  local src = source
  if not rateOK(src) then return TriggerClientEvent("vhub_login:authFail", src, "rate_limit") end
  Citizen.CreateThread(function()
    local ok, err = F.autenticar(src, tostring(username or ""), tostring(password or ""))
    if ok then
      TriggerClientEvent("vhub_login:authOK", src, F.personagens(src) or {})
    else
      TriggerClientEvent("vhub_login:authFail", src, err)
    end
  end)
end)

RegisterNetEvent("vhub_login:tryRegister")
AddEventHandler("vhub_login:tryRegister", function(username, password)
  local src = source
  if not rateOK(src) then return TriggerClientEvent("vhub_login:authFail", src, "rate_limit") end
  Citizen.CreateThread(function()
    local ok, err = F.registrar(src, tostring(username or ""), tostring(password or ""))
    if ok then
      TriggerClientEvent("vhub_login:authOK", src, F.personagens(src) or {})
    else
      TriggerClientEvent("vhub_login:authFail", src, err)
    end
  end)
end)

RegisterNetEvent("vhub_login:pickChar")
AddEventHandler("vhub_login:pickChar", function(cid)
  local src = source
  Citizen.CreateThread(function()
    local ok, err = F.selecionar(src, tonumber(cid))
    if ok then
      TriggerClientEvent("vhub_login:charOK", src)   -- cliente fecha NUI e chama o selector
    else
      TriggerClientEvent("vhub_login:charFail", src, err)
    end
  end)
end)

-- PONTE para o futuro criador de personagem (não implementa criação — A SER ligado).
RegisterNetEvent("vhub_login:requestCreate")
AddEventHandler("vhub_login:requestCreate", function()
  local src = source
  -- TODO(ponte): quando o resource criador existir, delegar via export gated:
  --   exports.<vhub_charcreator>:abrir(src) e, ao concluir, voltar ao charselect.
  TriggerClientEvent("vhub_login:createUnavailable", src)
end)


-- ============================================================
-- HIGIENE
-- ============================================================

AddEventHandler("playerDropped", function()
  local src = source
  F.limpar(src)
  _rl[src] = nil
end)
