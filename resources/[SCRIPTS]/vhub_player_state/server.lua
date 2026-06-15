-- vhub_player_state/server.lua
-- SPAWN OWNER (decisão Void-Zero/It.1): este módulo é o ÚNICO emissor de
--   apply/release/teleport ao ped. Nenhum outro resource chama SetEntityCoords
--   ou SetPlayerModel no fluxo de spawn — o selector apenas ELEGE coordenada
--   e devolve via export spawnAt().
-- Contratos públicos:
--   evento server  vhub_player_state:chooseSpawn (src)        → provedores de UI escutam
--   export         spawnAt(src, pos|nil) -> bool              → provedores devolvem coordenada
--   export         getPosition / teleport / give* / set*      → inalterados
-- Integração: user.data.state persiste via datatable do vHub.

local _vHub   = nil
local _pronto = false
local function vHub() return _vHub end

-- ── Configuração ──────────────────────────────────────────────────────────────

local CFG = {
  spawn_pos        = { x = -538.70, y = -214.91, z = 37.65, heading = 0.0 },
  spawn_radius     = 3.0,
  modelo_padrao    = "mp_m_freemode_01",
  saude_padrao     = 900,
  armadura_padrao  = 900,
  update_interval  = 15,     -- segundos entre reports do cliente
  mp_models        = { "mp_m_freemode_01", "mp_f_freemode_01" },

  -- Eleição de coordenada (selector) — ROLLBACK: usar_selector=false restaura
  --   o fluxo direto antigo em 1 boolean, sem tocar mais nada.
  usar_selector    = true,
  selector_modo    = "session",  -- "session" = só no 1º spawn da sessão | "always"
  selector_timeout = 60,         -- s sem escolha → spawn automático na pos salva/padrão
}

-- ── Inicialização ─────────────────────────────────────────────────────────────

AddEventHandler("onResourceStart", function(res)
  if res ~= GetCurrentResourceName() then return end
  Citizen.CreateThread(function()
    local tentativas = 0
    while tentativas < 50 do
      local ok, vh = pcall(function() return exports.vhub:getVHub() end)
      if ok and type(vh) == "table" and vh.Auth then
        _vHub = vh; _pronto = true
        print("[vhub_player_state] Pronto (spawn owner).")
        return
      end
      Citizen.Wait(200); tentativas = tentativas + 1
    end
    print("[vhub_player_state][ERRO] vHub não disponível após 10s")
  end)
end)

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function getState(user)
  if not user.data.state then user.data.state = {} end
  return user.data.state
end

-- Valida e normaliza uma coordenada (mesmos bounds do report do cliente)
local function posValida(p)
  if type(p) ~= "table" then return nil end
  local x, y, z = tonumber(p.x), tonumber(p.y), tonumber(p.z)
  if not (x and y and z) then return nil end
  if math.abs(x) >= 8000 or math.abs(y) >= 8000 or z <= -200 or z >= 2000 then return nil end
  return { x = x, y = y, z = z, heading = tonumber(p.heading) or tonumber(p.h) or 0.0 }
end

-- Posição efetiva: salva > padrão com dispersão
local function posEfetiva(state)
  local pos = posValida(state.position)
  if pos then
    pos.heading = tonumber(state.heading) or pos.heading
    return pos
  end
  local r = CFG.spawn_radius
  return {
    x       = CFG.spawn_pos.x + (math.random() * r * 2 - r),
    y       = CFG.spawn_pos.y + (math.random() * r * 2 - r),
    z       = CFG.spawn_pos.z,
    heading = CFG.spawn_pos.heading,
  }
end

-- ── Controle de pipeline por sessão ───────────────────────────────────────────

local _spawn_seen = {}  -- [src] = user.spawns do último apply (replay-guard)
local _pending    = {}  -- [src] = token do hold aguardando spawnAt (anti-double-release)

local function liberar(src, pos, first_spawn)
  _pending[src] = nil
  TriggerClientEvent("vhub_player_state:release", src, pos, first_spawn == true)
end

-- ── Eventos vHub ─────────────────────────────────────────────────────────────

AddEventHandler("vHub:characterLoad", function(user)
  if not user then return end
  if not user.data.state then user.data.state = {} end
end)

-- ÚNICO responsável pelo spawn — envia vhub_player_state:apply ao cliente
AddEventHandler("vHub:playerSpawn", function(user, first_spawn)
  if not user or not _pronto then return end
  local src   = user.source
  local state = getState(user)

  -- REPLAY-GUARD: o CORE re-dispara vHub:playerSpawn para TODAS as sessões em
  --   onResourceStart de qualquer resource (boot.lua) para repopular caches.
  --   user.spawns só incrementa no fluxo vHub:ready real; replay chega com o
  --   mesmo contador → no-op aqui (corrige re-teleporte/re-armas globais).
  local spawns = tonumber(user.spawns) or 0
  if _spawn_seen[src] == spawns then return end
  _spawn_seen[src] = spawns

  local pos = posEfetiva(state)

  -- Eleição de coordenada via selector?
  local selecionar = CFG.usar_selector
    and GetResourceState("vhub_spawselector") == "started"
    and (CFG.selector_modo == "always" or spawns <= 1)

  TriggerClientEvent("vhub_player_state:apply", src, {
    pos             = pos,
    hold            = selecionar,   -- true = ped fica congelado/invisível até release
    health          = state.health   or CFG.saude_padrao,
    armour          = state.armour   or CFG.armadura_padrao,
    weapons         = state.weapons  or {},
    customization   = state.customization or { model = CFG.modelo_padrao },
    first_spawn     = first_spawn == true,
    mp_models       = CFG.mp_models,
    update_interval = CFG.update_interval,
  })

  if selecionar then
    local token = spawns
    _pending[src] = token
    -- Provedores de UI (vhub_spawselector) escutam e abrem a eleição
    TriggerEvent("vhub_player_state:chooseSpawn", src)
    -- Timeout: AFK na tela não deixa ped eterno congelado/invisível
    SetTimeout(CFG.selector_timeout * 1000, function()
      if _pending[src] == token then liberar(src, nil, first_spawn) end
    end)
  end

  vHub().Logger:info("player_state",
    ("uid=%d src=%d → spawn pos=(%.1f,%.1f,%.1f) first=%s selector=%s"):format(
      user.id, src, pos.x, pos.y, pos.z, tostring(first_spawn), tostring(selecionar)))
end)

-- Limpa estado na morte
AddEventHandler("vHub:playerDeath", function(user)
  if not user then return end
  local state = getState(user)
  state.position = nil   -- spawn no local padrão
  state.heading  = nil
  state.weapons  = nil   -- perde armas
  state.health   = nil
  state.armour   = nil
end)

AddEventHandler("playerDropped", function()
  local src = source
  _spawn_seen[src] = nil
  _pending[src]    = nil
end)

-- ── Net event: report do cliente ─────────────────────────────────────────────

RegisterNetEvent("vhub_player_state:update")
AddEventHandler("vhub_player_state:update", function(dados)
  local src  = source
  if not _pronto or type(dados) ~= "table" then return end
  if _pending[src] then return end   -- em hold: ignora reports (pos ainda não eleita)
  local user = vHub().Auth:getUser(src)
  if not user then return end
  local state = getState(user)

  -- Valida posição (limites do mapa GTA V)
  local pos = posValida(dados.position)
  if pos then
    state.position = { x = pos.x, y = pos.y, z = pos.z }
    state.heading  = tonumber(dados.heading) or 0.0
  end

  -- Valida saúde (100–200 no GTA V)
  if dados.health then
    local h = tonumber(dados.health)
    if h and h >= 0 and h <= 200 then state.health = h end
  end

  -- Valida armadura (0–100)
  if dados.armour then
    local a = tonumber(dados.armour)
    if a and a >= 0 and a <= 100 then state.armour = a end
  end

  -- Salva armas e customização (tabelas — validação adicional no cliente)
  if type(dados.weapons)       == "table" then state.weapons       = dados.weapons       end
  if type(dados.customization) == "table" then state.customization = dados.customization end
end)

-- ── Exports ───────────────────────────────────────────────────────────────────

-- CONTRATO DE ELEIÇÃO: provedores (selector) devolvem a coordenada escolhida.
--   pos = {x,y,z,heading?} valida server-side | nil = usar salva/padrão.
--   Retorna false se não havia hold pendente para o src (anti-spoof/duplo-clique).
exports("spawnAt", function(src, pos)
  src = tonumber(src)
  if not src or not _pending[src] then return false end
  local user = _pronto and _vHub.Auth:getUser(src)

  -- Com user: a pos eleita vira a verdade persistida (evita corrida com update).
  -- Sem user (edge de timing): NÃO retornar false silencioso — isso limparia o
  --   _pending e o selector cairia no fallback teleport (que não desfaz o hold),
  --   prendendo o ped em tela preta. Então SEMPRE liberamos quando há hold
  --   pendente — o release garante a saída do hold. (IT.1 runtime fix)
  local destino
  if user then
    destino = posValida(pos) or posEfetiva(getState(user))
    local state = getState(user)
    state.position = { x = destino.x, y = destino.y, z = destino.z }
    state.heading  = destino.heading
  else
    destino = posValida(pos) or {
      x = CFG.spawn_pos.x, y = CFG.spawn_pos.y, z = CFG.spawn_pos.z,
      heading = CFG.spawn_pos.heading,
    }
  end

  local first = user ~= nil and (tonumber(user.spawns) or 0) <= 1
  liberar(src, destino, first)
  return true
end)

-- Há hold pendente para este src? (provedores checam antes de abrir UI)
exports("isPendingSpawn", function(src) return _pending[tonumber(src)] ~= nil end)

-- Dá armas (chamado por vhub_groups no onjoin da polícia, etc.)
exports("giveWeapons", function(src, weapons, clear_before)
  TriggerClientEvent("vhub_player_state:give_weapons", src, weapons, clear_before == true)
end)

exports("setArmour", function(src, amount)
  TriggerClientEvent("vhub_player_state:set_armour", src, tonumber(amount) or 0)
end)

exports("setHealth", function(src, amount)
  TriggerClientEvent("vhub_player_state:set_health", src, tonumber(amount) or 200)
end)

exports("setCustomization", function(src, custom)
  TriggerClientEvent("vhub_player_state:set_customization", src, custom)
end)

exports("teleport", function(src, x, y, z, heading)
  TriggerClientEvent("vhub_player_state:teleport", src, x, y, z, heading)
end)

exports("getPosition", function(src)
  if not _pronto then return 0, 0, 0 end
  local user = _vHub.Auth:getUser(src)
  if not user then return 0, 0, 0 end
  local pos = getState(user).position
  if not pos then return 0, 0, 0 end
  return pos.x, pos.y, pos.z
end)
