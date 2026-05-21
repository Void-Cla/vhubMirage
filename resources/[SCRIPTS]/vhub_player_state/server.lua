-- vhub_player_state/server.lua
-- Responsabilidade: spawn autoritativo e persistência de estado do jogador
--   (posição, saúde, armadura, armas, customização de ped).
-- DONO DO SPAWN: este módulo é o único que envia vhub_player_state:apply ao cliente.
--   O vhub core NÃO tem mais server/modules/spawn.lua — esta é a fonte única.
-- Integração: user.data.state persiste via datatable do vHub.

local _vHub   = nil
local _pronto = false
local function vHub() return _vHub end

-- ── Configuração ──────────────────────────────────────────────────────────────

local CFG = {
  spawn_pos       = { x = -538.70, y = -214.91, z = 37.65, heading = 0.0 },
  spawn_radius    = 3.0,
  modelo_padrao   = "mp_m_freemode_01",
  saude_padrao    = 200,
  armadura_padrao = 0,
  update_interval = 15,      -- segundos entre reports do cliente
  mp_models       = { "mp_m_freemode_01", "mp_f_freemode_01" },
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
        print("[vhub_player_state] Pronto.")
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

-- ── Eventos vHub ─────────────────────────────────────────────────────────────

AddEventHandler("vHub:characterLoad", function(user)
  if not user then return end
  if not user.data.state then user.data.state = {} end
end)

-- ÚNICO responsável pelo spawn — envia vhub_player_state:apply ao cliente
AddEventHandler("vHub:playerSpawn", function(user, first_spawn)
  if not user or not _pronto then return end
  local state = getState(user)
  local src   = user.source

  -- Posição: salva > padrão com dispersão
  local pos = state.position
  if not pos then
    local r = CFG.spawn_radius
    pos = {
      x       = CFG.spawn_pos.x + (math.random() * r * 2 - r),
      y       = CFG.spawn_pos.y + (math.random() * r * 2 - r),
      z       = CFG.spawn_pos.z,
      heading = CFG.spawn_pos.heading,
    }
  end

  TriggerClientEvent("vhub_player_state:apply", src, {
    pos             = pos,
    health          = state.health   or CFG.saude_padrao,
    armour          = state.armour   or CFG.armadura_padrao,
    weapons         = state.weapons  or {},
    customization   = state.customization or { model = CFG.modelo_padrao },
    first_spawn     = first_spawn == true,
    mp_models       = CFG.mp_models,
    update_interval = CFG.update_interval,
  })

  vHub().Logger:info("player_state",
    ("uid=%d src=%d → spawn pos=(%.1f,%.1f,%.1f) first=%s"):format(
      user.id, src, pos.x, pos.y, pos.z, tostring(first_spawn)))
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

-- ── Net event: report do cliente ─────────────────────────────────────────────

RegisterNetEvent("vhub_player_state:update")
AddEventHandler("vhub_player_state:update", function(dados)
  local src  = source
  if not _pronto or type(dados) ~= "table" then return end
  local user = vHub().Auth:getUser(src)
  if not user then return end
  local state = getState(user)

  -- Valida posição (limites do mapa GTA V)
  if type(dados.position) == "table" then
    local x = tonumber(dados.position.x)
    local y = tonumber(dados.position.y)
    local z = tonumber(dados.position.z)
    if x and y and z
       and math.abs(x) < 8000 and math.abs(y) < 8000
       and z > -200 and z < 2000 then
      state.position = { x = x, y = y, z = z }
      state.heading  = tonumber(dados.heading) or 0.0
    end
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

  -- Salva armas e customização (tabelas — confiamos estruturalmente, validação adicional no cliente)
  if type(dados.weapons)       == "table" then state.weapons       = dados.weapons       end
  if type(dados.customization) == "table" then state.customization = dados.customization end
end)

-- ── Exports ───────────────────────────────────────────────────────────────────

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
