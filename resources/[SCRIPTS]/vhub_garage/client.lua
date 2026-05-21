-- vhub_garage/client.lua
-- Responsabilidade: spawnar/despeitar veículos, gerenciar ownership via decorator,
--   reportar estado periodicamente ao servidor.
-- Regra: nunca decide sozinho — apenas executa ordens do servidor.

local _veiculos      = {}     -- plate → entity
local _hash_map      = {}     -- hash → plate
local _garagens      = {}     -- configuração das garagens
local _pronto        = false
local _blips_criados = false
local _lista_veiculos = {}    -- plate → { na_garagem, fuel, model } (do servidor)

-- Decorator para marcar veículo como propriedade do jogador
-- (DecorRegister deve ser chamado antes de qualquer uso)
CreateThread(function()
  DecorRegister("vhub.plate", 7)  -- 7 = string decorator
end)

-- ── Recebe configuração das garagens ─────────────────────────────────────────

RegisterNetEvent("vhub_garage:setup")
AddEventHandler("vhub_garage:setup", function(garagens)
  _garagens = type(garagens) == "table" and garagens or {}
  _pronto   = true
  -- Cria blips apenas uma vez (evita duplicados em respawn/resource restart)
  if not _blips_criados then
    _blips_criados = true
    for i, g in ipairs(_garagens) do
      local blip = AddBlipForCoord(g.x, g.y, g.z)
      SetBlipSprite(blip, 357); SetBlipColour(blip, 5); SetBlipScale(blip, 0.75)
      SetBlipAsShortRange(blip, true)
      BeginTextCommandSetBlipName("STRING")
      AddTextComponentSubstringPlayerName(g.label or ("Garagem #" .. i))
      EndTextCommandSetBlipName(blip)
    end
  end
end)

-- ── Recebe lista de veículos ──────────────────────────────────────────────────

RegisterNetEvent("vhub_garage:vehicle_list")
AddEventHandler("vhub_garage:vehicle_list", function(lista)
  _lista_veiculos = type(lista) == "table" and lista or {}
  TriggerEvent("vhub_garage:local_vehicle_list", _lista_veiculos)
end)

-- ── Spawn ordenado pelo servidor ──────────────────────────────────────────────

RegisterNetEvent("vhub_garage:do_spawn")
AddEventHandler("vhub_garage:do_spawn", function(plate, state, pos)
  Citizen.CreateThread(function()
    _spawnVeiculo(plate, state, pos, true)  -- true = colocar player dentro
  end)
end)

-- Spawnar veículos que estavam fora (reconexão)
RegisterNetEvent("vhub_garage:spawn_out")
AddEventHandler("vhub_garage:spawn_out", function(veiculos)
  Citizen.CreateThread(function()
    if type(veiculos) ~= "table" then return end
    for plate, data in pairs(veiculos) do
      if not _veiculos[plate] then
        _spawnVeiculo(plate, data, data.position, false)
      end
    end
  end)
end)

-- ── Despawn ordenado pelo servidor ────────────────────────────────────────────

RegisterNetEvent("vhub_garage:do_despawn")
AddEventHandler("vhub_garage:do_despawn", function(plate)
  _despawnVeiculo(plate)
end)

-- ── Notificação ───────────────────────────────────────────────────────────────

RegisterNetEvent("vhub_garage:notify")
AddEventHandler("vhub_garage:notify", function(msg)
  BeginTextCommandThefeedPost("STRING")
  AddTextComponentSubstringPlayerName(msg)
  EndTextCommandThefeedPostTicker(false, true)
end)

-- ── Funções de spawn/despawn ──────────────────────────────────────────────────

function _spawnVeiculo(plate, state, pos, entrar)
  -- Remove versão anterior se existir
  _despawnVeiculo(plate)

  -- Carrega o modelo
  -- Plate diz qual modelo usar se não vier no state — usa plate para inferir
  -- mas a garagem deve passar o modelo no state.customization.model
  local model_name = (state and state.customization and state.customization.model)
                  or "adder"  -- fallback genérico; concessionária garante o model correto
  local mhash = GetHashKey(model_name)

  RequestModel(mhash)
  local w = 0
  while not HasModelLoaded(mhash) and w < 5000 do
    Citizen.Wait(100); w = w + 100
  end
  if not HasModelLoaded(mhash) then
    print("[vhub_garage] Modelo não carregou: " .. model_name)
    return
  end

  local x = (pos and pos.x) or 0.0
  local y = (pos and pos.y) or 0.0
  local z = (pos and pos.z) or 0.0
  local h = (pos and pos.heading) or 0.0

  local veh = CreateVehicle(mhash, x, y, z + 0.5, h, true, false)
  SetModelAsNoLongerNeeded(mhash)

  if not IsEntityAVehicle(veh) then
    print("[vhub_garage] Falha ao criar veículo: " .. plate)
    return
  end

  -- Placa exata
  SetVehicleNumberPlateText(veh, plate)

  -- Aplica rotação se existir (veículo respawnando no mesmo lugar)
  if pos and pos.rotation then
    SetEntityQuaternion(veh, pos.rotation[1], pos.rotation[2],
                             pos.rotation[3], pos.rotation[4])
  end

  -- Coloca no chão
  SetVehicleOnGroundProperly(veh)

  -- Mission entity (não desaparece)
  SetEntityAsMissionEntity(veh, true, true)
  SetVehicleHasBeenOwnedByPlayer(veh, true)

  -- Decorator de ownership (identificação server-side e cliente)
  if DecorExistOn then
    DecorSetString(veh, "vhub.plate", plate)
  end

  -- Aplica customização e condição
  if state then
    _aplicarEstadoVeiculo(veh, state)
  end

  -- Entra no veículo se solicitado
  if entrar then
    SetPedIntoVehicle(PlayerPedId(), veh, -1)
  end

  -- Registra localmente
  _veiculos[plate] = veh
  _hash_map[GetEntityModel(veh)] = plate

  TriggerEvent("vhub_garage:veículo_spawnado", plate, veh)
end

function _despawnVeiculo(plate)
  local veh = _veiculos[plate]
  if not veh or not IsEntityAVehicle(veh) then
    _veiculos[plate] = nil
    return
  end

  -- Ejecta player se estiver dentro
  local ped = PlayerPedId()
  if GetVehiclePedIsIn(ped, false) == veh then
    TaskLeaveVehicle(ped, veh, 4160)
    Citizen.Wait(500)
  end

  SetVehicleHasBeenOwnedByPlayer(veh, false)
  SetEntityAsMissionEntity(veh, false, true)
  SetVehicleAsNoLongerNeeded(Citizen.PointerValueIntInitialized(veh))
  Citizen.InvokeNative(0xEA386986E786A54F, Citizen.PointerValueIntInitialized(veh))
  _veiculos[plate] = nil

  TriggerEvent("vhub_garage:veículo_despawnado", plate)
end

-- ── Aplicar estado visual/físico do veículo ───────────────────────────────────

function _aplicarEstadoVeiculo(veh, state)
  SetVehicleModKit(veh, 0)

  local c = state.customization
  if type(c) == "table" then
    if c.colours then SetVehicleColours(veh, table.unpack(c.colours)) end
    if c.extra_colours then SetVehicleExtraColours(veh, table.unpack(c.extra_colours)) end
    if c.plate_index   then SetVehicleNumberPlateTextIndex(veh, c.plate_index) end
    if c.wheel_type    then SetVehicleWheelType(veh, c.wheel_type)             end
    if c.window_tint   then SetVehicleWindowTint(veh, c.window_tint)           end
    if c.livery        then SetVehicleLivery(veh, c.livery)                    end
    if c.mods then
      for i, mod in pairs(c.mods) do SetVehicleMod(veh, i, mod, false) end
    end
    if c.turbo_enabled  ~= nil then ToggleVehicleMod(veh, 18, c.turbo_enabled) end
    if c.smoke_enabled  ~= nil then ToggleVehicleMod(veh, 20, c.smoke_enabled) end
    if c.xenon_enabled  ~= nil then ToggleVehicleMod(veh, 22, c.xenon_enabled) end
    if type(c.neons) == "table" then
      for i = 0, 3 do SetVehicleNeonLightEnabled(veh, i, c.neons[i] == true) end
    end
    if c.neon_colour then SetVehicleNeonLightsColour(veh, table.unpack(c.neon_colour)) end
  end

  local cond = state.condition
  if type(cond) == "table" then
    if cond.health       then SetEntityHealth(veh, cond.health)                        end
    if cond.engine_health then SetVehicleEngineHealth(veh, cond.engine_health)         end
    if cond.petrol_tank_health then
      SetVehiclePetrolTankHealth(veh, cond.petrol_tank_health)
    end
    if cond.dirt_level   then SetVehicleDirtLevel(veh, cond.dirt_level)                end
  end

  if state.fuel then
    -- Fuel via State Bag do vHub core (não nativo GTA)
    Entity(veh).state:set('vhub:fuel', state.fuel, true)
  end

  if state.locked then
    SetVehicleDoorsLocked(veh, 2)
    SetVehicleDoorsLockedForAllPlayers(veh, true)
  else
    SetVehicleDoorsLockedForAllPlayers(veh, false)
    SetVehicleDoorsLocked(veh, 1)
    SetVehicleDoorsLockedForPlayer(veh, PlayerId(), false)
  end
end

-- ── Coletor de estado do veículo ─────────────────────────────────────────────

local function coletarEstadoVeiculo(veh, plate)
  local state = {
    customization = {},
    condition     = {},
    fuel          = Entity(veh).state['vhub:fuel'] or 100.0,
    locked        = GetVehicleDoorLockStatus(veh) >= 2,
    position = (function()
      local c = GetEntityCoords(veh, true)
      return { x = c.x, y = c.y, z = c.z }
    end)(),
    rotation = (function()
      local a, b, c, d = GetEntityQuaternion(veh)
      return { a, b, c, d }
    end)(),
  }

  -- Customização
  local c = state.customization
  c.colours         = { GetVehicleColours(veh) }
  c.extra_colours   = { GetVehicleExtraColours(veh) }
  c.plate_index     = GetVehicleNumberPlateTextIndex(veh)
  c.wheel_type      = GetVehicleWheelType(veh)
  c.window_tint     = GetVehicleWindowTint(veh)
  c.livery          = GetVehicleLivery(veh)
  c.turbo_enabled   = IsToggleModOn(veh, 18)
  c.smoke_enabled   = IsToggleModOn(veh, 20)
  c.xenon_enabled   = IsToggleModOn(veh, 22)
  c.mods            = {}
  for i = 0, 49 do c.mods[i] = GetVehicleMod(veh, i) end
  c.neons           = {}
  for i = 0, 3 do c.neons[i] = IsVehicleNeonLightEnabled(veh, i) end
  c.neon_colour     = { GetVehicleNeonLightsColour(veh) }

  -- Condição
  local cond = state.condition
  cond.health             = GetEntityHealth(veh)
  cond.engine_health      = GetVehicleEngineHealth(veh)
  cond.petrol_tank_health = GetVehiclePetrolTankHealth(veh)
  cond.dirt_level         = GetVehicleDirtLevel(veh)

  return state
end

-- ── Report periódico ──────────────────────────────────────────────────────────

Citizen.CreateThread(function()
  while true do
    Citizen.Wait(30000)
    if not _pronto then goto continue end
    for plate, veh in pairs(_veiculos) do
      if IsEntityAVehicle(veh) then
        local state = coletarEstadoVeiculo(veh, plate)
        TriggerServerEvent("vhub_garage:update_state", plate, state)
      else
        _veiculos[plate] = nil  -- limpa referência inválida
      end
    end
    ::continue::
  end
end)

-- ── Tentativa de re-ownership periódica ──────────────────────────────────────
-- Recupera veículos que perderam o decorator por OOS (OneSync out-of-scope)

Citizen.CreateThread(function()
  while true do
    Citizen.Wait(15000)
    if not _pronto or not DecorExistOn then goto continue end
    local it, veh = FindFirstVehicle()
    if it then
      local found = true
      while found do
        if DoesEntityExist(veh) and DecorExistOn(veh, "vhub.plate") then
          local plate = DecorGetString(veh, "vhub.plate")
          if plate and plate ~= "" and not _veiculos[plate] then
            _veiculos[plate] = veh
          end
        end
        found, veh = FindNextVehicle(it)
      end
      EndFindVehicle(it)
    end
    ::continue::
  end
end)

-- ── Detecção de zona + DrawText3D + [E] interação ────────────────────────────

local _em_garagem = nil

Citizen.CreateThread(function()
  while true do
    local sleep = _pronto and 500 or 1000
    Citizen.Wait(sleep)
    if not _pronto then goto continue end

    local ped    = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local nova_garagem = nil

    for i, g in ipairs(_garagens) do
      if #(coords - vector3(g.x, g.y, g.z)) <= (g.raio or 8.0) then
        nova_garagem = i; break
      end
    end

    if nova_garagem ~= _em_garagem then
      _em_garagem = nova_garagem
      if nova_garagem then
        TriggerEvent("vhub_garage:entrou_zona", nova_garagem, _garagens[nova_garagem])
        TriggerServerEvent("vhub_garage:get_vehicles")
      else
        TriggerEvent("vhub_garage:saiu_zona")
      end
    end

    ::continue::
  end
end)

-- Frame loop ativo apenas quando na zona: desenha marker, hint e trata [E]
Citizen.CreateThread(function()
  while true do
    Citizen.Wait(0)
    if not _em_garagem then
      Citizen.Wait(500); goto continue
    end
    local g   = _garagens[_em_garagem]
    local ped = PlayerPedId()

    -- Marker cilíndrico no chão
    DrawMarker(1,
      g.x, g.y, g.z - 1.0,
      0.0, 0.0, 0.0,
      0.0, 0.0, 0.0,
      4.0, 4.0, 1.0,
      100, 200, 255, 80,
      false, true, 2, false, nil, nil, false)

    -- DrawText3D: label + dica de tecla
    local c3 = GetEntityCoords(ped)
    if #(c3 - vector3(g.x, g.y, g.z)) <= (g.raio or 8.0) then
      SetTextScale(0.35, 0.35)
      SetTextFont(4)
      SetTextProportional(true)
      SetTextColour(255, 255, 255, 215)
      SetTextOutline()
      SetTextEntry("STRING")
      AddTextComponentString(("[E] %s"):format(g.label or "Garagem"))
      DrawText(0.5, 0.92)
    end

    -- [E] = tecla 38 (INPUT_PICKUP)
    if IsControlJustReleased(0, 38) then
      TriggerEvent("vhub_garage:abrir_menu", _em_garagem, _garagens[_em_garagem])
    end

    ::continue::
  end
end)

-- ── Interação: guardar veículo próximo ────────────────────────────────────────
-- Chamado por script de UI quando jogador confirma guardar

RegisterNetEvent("vhub_garage:client_store")
AddEventHandler("vhub_garage:client_store", function()
  -- Acha o veículo próprio mais próximo
  local ped    = PlayerPedId()
  local coords = GetEntityCoords(ped)
  local min_dist, found_plate, found_veh = 999, nil, nil

  for plate, veh in pairs(_veiculos) do
    if IsEntityAVehicle(veh) then
      local c = GetEntityCoords(veh, true)
      local d = #(coords - vector3(c.x, c.y, c.z))
      if d < min_dist then
        min_dist    = d
        found_plate = plate
        found_veh   = veh
      end
    end
  end

  if not found_plate or min_dist > 15 then
    BeginTextCommandThefeedPost("STRING")
    AddTextComponentSubstringPlayerName("Nenhum veículo próprio próximo (raio 15m).")
    EndTextCommandThefeedPostTicker(false, true)
    return
  end

  local state = coletarEstadoVeiculo(found_veh, found_plate)
  TriggerServerEvent("vhub_garage:store", found_plate, state)
end)

-- ── Mini menu + handler abrir_menu ───────────────────────────────────────────

local _menu = nil
local function fecharMenu() _menu = nil end
local function abrirMenu(titulo, itens, voltar)
  _menu = { t = titulo, i = itens, s = 1, v = voltar }
end

Citizen.CreateThread(function()
  while true do
    if not _menu then Citizen.Wait(200); goto __mg end
    Citizen.Wait(0)
    local m, its, n, sel = _menu, _menu.i, #_menu.i, _menu.s
    local h   = math.min(n * 0.057 + 0.11, 0.88)
    local top = 0.5 - h * 0.5
    DrawRect(0.845, 0.5, 0.295, h, 8, 8, 12, 210)
    DrawRect(0.845, top + 0.038, 0.295, 0.076, 22, 60, 155, 240)
    SetTextFont(1); SetTextScale(0, 0.44); SetTextColour(255, 210, 55, 255); SetTextOutline()
    SetTextEntry("STRING"); AddTextComponentString(m.t); DrawText(0.708, top + 0.010)
    for i = 1, n do
      local y = top + 0.086 + (i - 1) * 0.057
      if i == sel then
        DrawRect(0.845, y + 0.026, 0.291, 0.052, 255, 205, 50, 55)
        SetTextColour(255, 235, 80, 255)
      else SetTextColour(218, 218, 218, 255) end
      SetTextFont(0); SetTextScale(0, 0.37); SetTextEntry("STRING")
      AddTextComponentString(its[i].label); DrawText(0.709, y)
    end
    if IsControlJustReleased(0, 172) then m.s = sel > 1 and sel - 1 or n
    elseif IsControlJustReleased(0, 173) then m.s = sel < n and sel + 1 or 1
    elseif IsControlJustReleased(0, 201) or IsControlJustReleased(0, 176) then
      if its[sel] and its[sel].action then its[sel].action() end
    elseif IsControlJustReleased(0, 200) or IsControlJustReleased(0, 177) then
      if m.v then m.v() else fecharMenu() end
    end
    ::__mg::
  end
end)

local function abrirOpcoes(plate, info, garagem_idx)
  local status = info.na_garagem and "Na garagem" or "Fora"
  local fuel   = info.fuel and ("Comb: %.0f%%"):format(info.fuel) or ""
  local modelo = info.model or plate
  abrirMenu(plate .. " — " .. modelo, {
    { label = "Status: " .. status .. "  " .. fuel, action = function() end },
    { label = info.na_garagem and "▶ Spawnar veículo" or "▶ Guardar veículo", action = function()
        fecharMenu()
        if info.na_garagem then
          TriggerServerEvent("vhub_garage:spawn", plate, garagem_idx)
        else
          -- Guarda o veículo mais próximo com essa placa
          local veh = _veiculos[plate]
          if veh and IsEntityAVehicle(veh) then
            local state = coletarEstadoVeiculo(veh, plate)
            TriggerServerEvent("vhub_garage:store", plate, state)
          else
            BeginTextCommandThefeedPost("STRING")
            AddTextComponentSubstringPlayerName("Veículo não encontrado perto de você.")
            EndTextCommandThefeedPostTicker(false, true)
          end
        end
    end},
    { label = "← Voltar", action = function()
        TriggerEvent("vhub_garage:abrir_menu", garagem_idx)
    end},
  }, function() TriggerEvent("vhub_garage:abrir_menu", garagem_idx) end)
end

AddEventHandler("vhub_garage:abrir_menu", function(garagem_idx)
  local itens = {}
  for plate, info in pairs(_lista_veiculos) do
    local p2, i2 = plate, info
    local status = info.na_garagem and "[G]" or "[F]"
    itens[#itens + 1] = {
      label  = status .. " " .. plate .. "  " .. (info.model or ""),
      action = function() abrirOpcoes(p2, i2, garagem_idx) end
    }
  end
  if #itens == 0 then
    BeginTextCommandThefeedPost("STRING")
    AddTextComponentSubstringPlayerName("Nenhum veículo. Compre na concessionária.")
    EndTextCommandThefeedPostTicker(false, true)
    return
  end
  table.sort(itens, function(a, b) return a.label < b.label end)
  itens[#itens + 1] = { label = "× Fechar", action = fecharMenu }
  abrirMenu("Garagem", itens, fecharMenu)
end)

-- ── Getters para scripts externos ─────────────────────────────────────────────

function vHub_getVeiculosAtivos()  return _veiculos end
function vHub_getGaragemAtual()    return _em_garagem end

function vHub_getVeiculoProximo(raio)
  raio = raio or 15
  local ped    = PlayerPedId()
  local coords = GetEntityCoords(ped)
  local min_dist, found_plate = raio + 1, nil
  for plate, veh in pairs(_veiculos) do
    if IsEntityAVehicle(veh) then
      local c = GetEntityCoords(veh, true)
      local d = #(coords - vector3(c.x, c.y, c.z))
      if d < min_dist then min_dist = d; found_plate = plate end
    end
  end
  return found_plate, _veiculos[found_plate]
end
