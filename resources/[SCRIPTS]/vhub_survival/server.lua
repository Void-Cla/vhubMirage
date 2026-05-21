-- vhub_survival/server.lua
-- Responsabilidade: fome, sede e dano por inanição — autoridade server-side.
-- Persistência: user.data.vitals via datatable do vHub.
-- Dependências: vhub (characterLoad, playerSpawn, playerDeath), vhub_player_state (setHealth).

local _vHub   = nil
local _pronto = false
local function vHub() return _vHub end

local CFG = {
  agua_por_minuto    = 0.025,   -- decaimento por minuto (0-1)
  comida_por_minuto  = 0.0125,
  dano_por_tick      = 10,      -- HP perdido por tick quando vital = 0
  tick_dano_ms       = 30000,   -- intervalo do tick de dano em ms (30s)
  exibir_vitais      = true,
  -- Consumo por ação (reduz o vital indicado)
  consumo = {
    correr   = { agua = 0.01 },
    nadar    = { agua = 0.015, comida = 0.005 },
    lutar    = { agua = 0.008 },
  },
}

AddEventHandler("onResourceStart", function(res)
  if res ~= GetCurrentResourceName() then return end
  Citizen.CreateThread(function()
    local tries = 0
    while tries < 50 do
      local ok, vh = pcall(function() return exports.vhub:getVHub() end)
      if ok and type(vh) == "table" and vh.Auth then
        _vHub = vh; _pronto = true
        print("[vhub_survival] Pronto.")
        return
      end
      Citizen.Wait(200); tries = tries + 1
    end
    print("[vhub_survival][ERRO] vHub não disponível após 10s")
  end)
end)

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function getVitais(user)
  if not user.data.vitals then user.data.vitals = {} end
  return user.data.vitals
end

local function setVital(user, nome, valor)
  local vitais = getVitais(user)
  valor = math.max(0.0, math.min(1.0, tonumber(valor) or 0))
  vitais[nome] = valor
  TriggerClientEvent("vhub_survival:vital_update", user.source, nome, valor)
end

local function aplicarDano(user)
  -- Reduz HP via net event direto ao cliente (não depende de getPosition)
  local hp_atual = (user.data.state and user.data.state.health) or 200
  local hp_novo  = math.max(100, hp_atual - CFG.dano_por_tick)
  -- Atualiza cache local para próximos cálculos
  if user.data.state then user.data.state.health = hp_novo end
  TriggerClientEvent("vhub_player_state:set_health", user.source, hp_novo)
end

-- ── Exports ───────────────────────────────────────────────────────────────────

exports("getVital", function(src, nome)
  if not _pronto then return 0 end
  local user = _vHub.Auth:getUser(src)
  if not user then return 0 end
  return getVitais(user)[nome] or 0
end)

exports("setVital", function(src, nome, valor)
  if not _pronto then return end
  local user = _vHub.Auth:getUser(src)
  if not user then return end
  setVital(user, nome, valor)
end)

exports("varyVital", function(src, nome, delta)
  if not _pronto then return end
  local user = _vHub.Auth:getUser(src)
  if not user then return end
  local vitais = getVitais(user)
  setVital(user, nome, (vitais[nome] or 0) + (tonumber(delta) or 0))
end)

-- ── Eventos vHub ─────────────────────────────────────────────────────────────

AddEventHandler("vHub:characterLoad", function(user)
  if not user then return end
  local vitais = getVitais(user)
  if vitais.agua   == nil then vitais.agua   = 1.0  end
  if vitais.comida == nil then vitais.comida = 0.75 end
end)

AddEventHandler("vHub:playerSpawn", function(user, first_spawn)
  if not user then return end
  TriggerClientEvent("vhub_survival:init", user.source, {
    agua   = getVitais(user).agua,
    comida = getVitais(user).comida,
    exibir = CFG.exibir_vitais,
  })
end)

AddEventHandler("vHub:playerDeath", function(user)
  if not user then return end
  -- Restaura vitais na morte
  local vitais = getVitais(user)
  vitais.agua   = 1.0
  vitais.comida = 0.75
end)

-- ── Decaimento periódico ──────────────────────────────────────────────────────

Citizen.CreateThread(function()
  while true do
    Citizen.Wait(60000)  -- 1 minuto
    if not _pronto then goto continue end
    for _, user in pairs(vHub().Auth._sessions) do
      if user then
        local vitais = getVitais(user)
        setVital(user, "agua",   (vitais.agua   or 1) - CFG.agua_por_minuto)
        setVital(user, "comida", (vitais.comida or 1) - CFG.comida_por_minuto)
      end
    end
    ::continue::
  end
end)

-- Dano periódico quando vitais críticos
Citizen.CreateThread(function()
  while true do
    Citizen.Wait(CFG.tick_dano_ms)
    if not _pronto then goto continue end
    for _, user in pairs(vHub().Auth._sessions) do
      if user then
        local vitais = getVitais(user)
        if (vitais.agua or 1) <= 0 or (vitais.comida or 1) <= 0 then
          aplicarDano(user)
        end
      end
    end
    ::continue::
  end
end)

-- ── Net event: consumo por ação ───────────────────────────────────────────────

RegisterNetEvent("vhub_survival:consume")
AddEventHandler("vhub_survival:consume", function(acao)
  local src  = source
  if not _pronto then return end
  local user = vHub().Auth:getUser(src)
  if not user then return end

  local consumo = CFG.consumo[acao]
  if not consumo then return end

  local vitais = getVitais(user)
  for nome, delta in pairs(consumo) do
    setVital(user, nome, (vitais[nome] or 1) - delta)
  end
end)
