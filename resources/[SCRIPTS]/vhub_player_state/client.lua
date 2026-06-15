-- vhub_player_state/client.lua
-- Responsabilidade: aplicar spawn e estado recebido do servidor; reportar estado periodicamente.
-- ÚNICO ESCRITOR DO PED (Void-Zero/It.1): nenhum outro resource chama
--   SetPlayerModel/SetEntityCoords no fluxo de spawn. O selector elege coordenada
--   no servidor; este arquivo recebe apply (com hold opcional) e release.
-- Regra: NUNCA modifica dados sem autorização do servidor.

local _state_ready     = false
local _update_interval = 15
local _mp_models       = {}   -- hash → true para modelos freemode
local _hold            = false
local _first_spawn     = false

-- Fluxo: spawnmanager/fallback do CORE deixa o player ativo e envia vHub:ready;
-- o servidor responde com vhub_player_state:apply (model+custom+pos). Com
-- hold=true o ped fica congelado/invisível até vhub_player_state:release
-- entregar a coordenada eleita (selector) ou o timeout server-side liberar.

-- ── Primitivas de movimento (uso interno exclusivo) ───────────────────────────

local function moverPed(ped, x, y, z, heading)
  FreezeEntityPosition(ped, true)
  SetEntityCoords(ped, x, y, z, false, false, false, false)
  if heading then SetEntityHeading(ped, heading) end
  RequestCollisionAtCoord(x, y, z)
  local wc = 0
  while not HasCollisionLoadedAroundEntity(ped) and wc < 3000 do
    Citizen.Wait(100); wc = wc + 100
  end
end

local function finalizarSpawn(ped, first_spawn)
  FreezeEntityPosition(ped, false)
  SetEntityVisible(ped, true, false)
  SetEntityInvincible(ped, false)
  DoScreenFadeIn(500)
  _state_ready = true

  TriggerEvent("vhub_player_state:spawned", first_spawn)

  if first_spawn then
    BeginTextCommandThefeedPost("STRING")
    AddTextComponentSubstringPlayerName("Bem-vindo ao servidor!")
    EndTextCommandThefeedPostTicker(false, true)
  end
end

-- ── Aplicação do estado no spawn ─────────────────────────────────────────────

RegisterNetEvent("vhub_player_state:apply")
AddEventHandler("vhub_player_state:apply", function(dados)
  if type(dados) ~= "table" then return end

  _update_interval = tonumber(dados.update_interval) or 15

  -- Monta mapa de MP models (suportam customização completa)
  if type(dados.mp_models) == "table" then
    _mp_models = {}
    for _, m in ipairs(dados.mp_models) do
      _mp_models[GetHashKey(m)] = true
    end
  end

  Citizen.CreateThread(function()
    _state_ready = false
    _hold        = dados.hold == true
    _first_spawn = dados.first_spawn == true

    -- 1. Aguarda player ativo no mundo
    local tries = 0
    while not NetworkIsPlayerActive(PlayerId()) and tries < 100 do
      Citizen.Wait(100); tries = tries + 1
    end
    if not NetworkIsPlayerActive(PlayerId()) then
      print("[vhub_player_state] Player não ficou ativo — spawn abortado")
      return
    end

    -- 2. Fade out durante transição
    DoScreenFadeOut(200)
    Citizen.Wait(300)

    local ped = PlayerPedId()

    -- 3. Modelo de ped
    local custom     = type(dados.customization) == "table" and dados.customization or {}
    local model_name = custom.model or dados.model or "mp_m_freemode_01"
    local model_hash = GetHashKey(model_name)

    if GetEntityModel(ped) ~= model_hash then
      RequestModel(model_hash)
      local w = 0
      while not HasModelLoaded(model_hash) and w < 5000 do
        Citizen.Wait(100); w = w + 100
      end
      if HasModelLoaded(model_hash) then
        SetPlayerModel(PlayerId(), model_hash)
        SetModelAsNoLongerNeeded(model_hash)
        Citizen.Wait(0)
        ped = PlayerPedId()   -- ped muda após SetPlayerModel
      end
    end

    -- 4. Customização de ped (partes, props, overlays)
    _aplicarCustomizacao(ped, custom)

    -- 5. Posição (provável/final). Em hold permanece congelado nela.
    local pos = dados.pos
    if type(pos) == "table" and pos.x and pos.y and pos.z then
      moverPed(ped, pos.x, pos.y, pos.z, pos.heading)
    end

    -- 6. Saúde e armadura
    SetEntityHealth(ped,
      math.max(100, math.min(200, tonumber(dados.health) or 200)))
    SetPedArmour(ped,
      math.max(0, math.min(100, tonumber(dados.armour) or 0)))

    -- 7. Armas
    if type(dados.weapons) == "table" then
      _aplicarArmas(dados.weapons, true)
    end

    -- 8. Finaliza OU segura para eleição de coordenada (selector)
    if _hold then
      SetEntityVisible(ped, false, false)
      SetEntityInvincible(ped, true)
      -- ped fica congelado (moverPed) e invisível; release fecha o ciclo
    else
      finalizarSpawn(ped, _first_spawn)
    end
  end)
end)

-- Coordenada eleita (ou timeout): teleporta se veio pos e libera o ped.
RegisterNetEvent("vhub_player_state:release")
AddEventHandler("vhub_player_state:release", function(pos, first_spawn)
  Citizen.CreateThread(function()
    local ped = PlayerPedId()
    _hold = false
    if type(pos) == "table" and pos.x and pos.y and pos.z then
      moverPed(ped, pos.x, pos.y, pos.z, pos.heading)
    end
    finalizarSpawn(ped, first_spawn == true or _first_spawn)
  end)
end)

-- ── Customização de ped ───────────────────────────────────────────────────────

function _aplicarCustomizacao(ped, custom)
  if type(custom) ~= "table" then return end
  local is_mp = _mp_models[GetEntityModel(ped)]

  if is_mp then
    local face = (custom["drawable:0"] and custom["drawable:0"][1]) or 0
    SetPedHeadBlendData(ped, face, face, 0, face, face, 0, 0.5, 0.5, 0.0, false)
  end

  for k, v in pairs(custom) do
    if type(k) == "string" and type(v) == "table" then
      local parts = {}
      for part in k:gmatch("[^:]+") do parts[#parts+1] = part end
      local idx = tonumber(parts[2])

      if parts[1] == "prop" and idx then
        if (v[1] or 0) < 0 then
          ClearPedProp(ped, idx)
        else
          SetPedPropIndex(ped, idx, v[1] or 0, v[2] or 0, true)
        end
      elseif parts[1] == "drawable" and idx then
        SetPedComponentVariation(ped, idx, v[1] or 0, v[2] or 0, v[3] or 2)
      elseif parts[1] == "overlay" and idx and is_mp then
        local ctype = (idx==1 or idx==2 or idx==10) and 1
                   or (idx==5 or idx==8)             and 2 or 0
        SetPedHeadOverlay(ped, idx, v[1] or 0, v[4] or 1.0)
        SetPedHeadOverlayColor(ped, idx, ctype, v[2] or 0, v[3] or 0)
      end
    end

    if k == "hair_color" and is_mp and type(v) == "table" then
      SetPedHairColor(ped, v[1] or 0, v[2] or 0)
    end
  end
end

-- ── Aplicar armas ─────────────────────────────────────────────────────────────

function _aplicarArmas(weapons, clear_before)
  local ped = PlayerPedId()
  if clear_before then RemoveAllPedWeapons(ped, true) end
  for nome, dados in pairs(weapons) do
    GiveWeaponToPed(ped, GetHashKey(nome),
      (type(dados) == "table" and dados.ammo) or 0, false)
  end
end

-- ── Coleta de estado para report ─────────────────────────────────────────────

local WEAPON_LIST = {
  "WEAPON_KNIFE","WEAPON_STUNGUN","WEAPON_FLASHLIGHT","WEAPON_NIGHTSTICK",
  "WEAPON_HAMMER","WEAPON_BAT","WEAPON_CROWBAR",
  "WEAPON_PISTOL","WEAPON_COMBATPISTOL","WEAPON_APPISTOL","WEAPON_PISTOL50",
  "WEAPON_MICROSMG","WEAPON_SMG","WEAPON_ASSAULTSMG",
  "WEAPON_ASSAULTRIFLE","WEAPON_CARBINERIFLE","WEAPON_ADVANCEDRIFLE",
  "WEAPON_MG","WEAPON_COMBATMG",
  "WEAPON_PUMPSHOTGUN","WEAPON_SAWNOFFSHOTGUN","WEAPON_ASSAULTSHOTGUN",
  "WEAPON_SNIPERRIFLE","WEAPON_HEAVYSNIPER",
  "WEAPON_GRENADELAUNCHER","WEAPON_RPG","WEAPON_MINIGUN",
  "WEAPON_GRENADE","WEAPON_STICKYBOMB","WEAPON_SMOKEGRENADE",
  "WEAPON_MOLOTOV","WEAPON_PETROLCAN","WEAPON_FIREEXTINGUISHER",
}

local function coletarArmas()
  local ped     = PlayerPedId()
  local weapons = {}
  local seen    = {}  -- evita duplicar ammo por tipo compartilhado
  for _, nome in ipairs(WEAPON_LIST) do
    local hash = GetHashKey(nome)
    if HasPedGotWeapon(ped, hash, false) then
      local ammo_type = Citizen.InvokeNative(0x7FEAD38B326B9F74, ped, hash)
      weapons[nome] = {
        ammo = (not seen[ammo_type]) and GetAmmoInPedWeapon(ped, hash) or 0
      }
      seen[ammo_type] = true
    end
  end
  return weapons
end

local function coletarCustomizacao()
  local ped    = PlayerPedId()
  local custom = { modelhash = GetEntityModel(ped) }
  for i = 0, 20 do
    custom["drawable:"..i] = {
      GetPedDrawableVariation(ped, i),
      GetPedTextureVariation(ped, i),
      GetPedPaletteVariation(ped, i),
    }
  end
  for i = 0, 10 do
    custom["prop:"..i] = {
      GetPedPropIndex(ped, i),
      math.max(GetPedPropTextureIndex(ped, i), 0),
    }
  end
  custom.hair_color = { GetPedHairColor(ped), GetPedHairHighlightColor(ped) }
  return custom
end

-- ── Report periódico ao servidor ─────────────────────────────────────────────

Citizen.CreateThread(function()
  while true do
    Citizen.Wait(_update_interval * 1000)
    if not _state_ready then goto continue end

    local ped = PlayerPedId()
    if not ped or ped == 0 or IsEntityDead(ped) then goto continue end

    local coords = GetEntityCoords(ped)
    TriggerServerEvent("vhub_player_state:update", {
      position      = { x = coords.x, y = coords.y, z = coords.z },
      heading       = GetEntityHeading(ped),
      health        = GetEntityHealth(ped),
      armour        = GetPedArmour(ped),
      weapons       = coletarArmas(),
      customization = coletarCustomizacao(),
    })

    ::continue::
  end
end)

-- Desativa regeneração automática de saúde (conflita com sistema de sobrevivência)
Citizen.CreateThread(function()
  while true do
    Citizen.Wait(1000)
    SetPlayerHealthRechargeMultiplier(PlayerId(), 0)
  end
end)

-- ── Net events do servidor ────────────────────────────────────────────────────

RegisterNetEvent("vhub_player_state:give_weapons")
AddEventHandler("vhub_player_state:give_weapons", function(weapons, clear_before)
  if type(weapons) == "table" then _aplicarArmas(weapons, clear_before) end
end)

RegisterNetEvent("vhub_player_state:set_armour")
AddEventHandler("vhub_player_state:set_armour", function(amount)
  SetPedArmour(PlayerPedId(), math.max(0, math.min(100, tonumber(amount) or 0)))
end)

RegisterNetEvent("vhub_player_state:set_health")
AddEventHandler("vhub_player_state:set_health", function(amount)
  SetEntityHealth(PlayerPedId(),
    math.max(100, math.min(200, math.floor(tonumber(amount) or 200))))
end)

RegisterNetEvent("vhub_player_state:set_customization")
AddEventHandler("vhub_player_state:set_customization", function(custom)
  Citizen.CreateThread(function()
    _aplicarCustomizacao(PlayerPedId(), custom)
  end)
end)

RegisterNetEvent("vhub_player_state:teleport")
AddEventHandler("vhub_player_state:teleport", function(x, y, z, heading)
  Citizen.CreateThread(function()
    local ped = PlayerPedId()
    moverPed(ped, x, y, z, heading)
    if _hold then
      -- veio do fallback do selector com o ped ainda em hold: finaliza para
      -- nunca deixar a tela preta / ped invisível. (IT.1 runtime fix)
      finalizarSpawn(ped, _first_spawn)
    else
      Citizen.Wait(500)
      FreezeEntityPosition(ped, false)
    end
  end)
end)
