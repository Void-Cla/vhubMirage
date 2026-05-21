-- vhub_dealership/client.lua
-- Menu nativo (sem NUI) — seta + Enter navega, Esc fecha.
-- [E] na zona abre catálogo; test drive via menu.

local _concessionarias = {}
local _catalogo        = {}
local _pronto          = false
local _em_conc         = nil
local _test_drive_veh  = nil

-- ── Mini menu nativo ──────────────────────────────────────────────────────────

local _menu = nil

local function fecharMenu() _menu = nil end

local function abrirMenu(titulo, itens, voltar)
  _menu = { t = titulo, i = itens, s = 1, v = voltar }
end

Citizen.CreateThread(function()
  while true do
    if not _menu then Citizen.Wait(200); goto __m end
    Citizen.Wait(0)
    local m   = _menu
    local its = m.i
    local n   = #its
    local sel = m.s
    local h   = math.min(n * 0.057 + 0.11, 0.88)
    local top = 0.5 - h * 0.5
    -- Fundo do painel
    DrawRect(0.845, 0.5, 0.295, h, 8, 8, 12, 210)
    -- Cabeçalho
    DrawRect(0.845, top + 0.038, 0.295, 0.076, 22, 60, 155, 240)
    -- Título
    SetTextFont(1); SetTextScale(0, 0.44); SetTextColour(255, 210, 55, 255); SetTextOutline()
    SetTextEntry("STRING"); AddTextComponentString(m.t); DrawText(0.708, top + 0.010)
    -- Itens
    for i = 1, n do
      local y = top + 0.086 + (i - 1) * 0.057
      if i == sel then
        DrawRect(0.845, y + 0.026, 0.291, 0.052, 255, 205, 50, 55)
        SetTextColour(255, 235, 80, 255)
      else
        SetTextColour(218, 218, 218, 255)
      end
      SetTextFont(0); SetTextScale(0, 0.37); SetTextEntry("STRING")
      AddTextComponentString(its[i].label); DrawText(0.709, y)
    end
    -- Controles
    if IsControlJustReleased(0, 172) then
      m.s = sel > 1 and sel - 1 or n
    elseif IsControlJustReleased(0, 173) then
      m.s = sel < n and sel + 1 or 1
    elseif IsControlJustReleased(0, 201) or IsControlJustReleased(0, 176) then
      if its[sel] and its[sel].action then its[sel].action() end
    elseif IsControlJustReleased(0, 200) or IsControlJustReleased(0, 177) then
      if m.v then m.v() else fecharMenu() end
    end
    ::__m::
  end
end)

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function fmtMoney(n)
  local s, res, c = tostring(math.floor(n or 0)), "", 0
  for i = #s, 1, -1 do
    res = s:sub(i, i) .. res; c = c + 1
    if c % 3 == 0 and i > 1 then res = "." .. res end
  end
  return "R$ " .. res
end

local function pedirTexto(titulo, maxLen, cb)
  Citizen.CreateThread(function()
    DisplayOnscreenKeyboard(1, "FMMC_KEY_TIP1", titulo, "", "", "", "", maxLen)
    while UpdateOnscreenKeyboard() == 0 do Citizen.Wait(0) end
    local r = GetOnscreenKeyboardResult()
    cb((r and r ~= "") and r or nil)
  end)
end

local function notify(msg)
  BeginTextCommandThefeedPost("STRING")
  AddTextComponentSubstringPlayerName(msg)
  EndTextCommandThefeedPostTicker(false, true)
end

-- ── Lógica de compra ──────────────────────────────────────────────────────────

local function abrirModelo(modelo, cfg, voltar)
  abrirMenu(cfg.nome, {
    { label = "Comprar  " .. fmtMoney(cfg.preco), action = function()
        fecharMenu()
        TriggerServerEvent("vhub_dealership:buy", modelo, "")
    end},
    { label = "Placa custom  +" .. fmtMoney(200), action = function()
        fecharMenu()
        pedirTexto("Digite a placa (max 8)", 8, function(placa)
          if placa then
            TriggerServerEvent("vhub_dealership:buy", modelo, placa)
          else
            notify("Placa cancelada.")
          end
        end)
    end},
    { label = "Test Drive", action = function()
        fecharMenu()
        TriggerServerEvent("vhub_dealership:test_drive", modelo, _em_conc)
    end},
    { label = "Vender meu veículo...", action = function()
        fecharMenu()
        pedirTexto("Digite a placa do veículo", 8, function(placa)
          if placa then
            TriggerServerEvent("vhub_dealership:sell", placa)
          end
        end)
    end},
    { label = "← Voltar", action = voltar },
  }, voltar)
end

local function abrirCategoria(cat)
  local itens = {}
  for modelo, cfg in pairs(_catalogo) do
    if cfg.cat == cat then
      local m2, cfg2 = modelo, cfg
      itens[#itens + 1] = {
        label  = ("%-16s %s"):format(cfg.nome, fmtMoney(cfg.preco)),
        action = function()
          abrirModelo(m2, cfg2, function() abrirCategoria(cat) end)
        end
      }
    end
  end
  table.sort(itens, function(a, b) return a.label < b.label end)
  itens[#itens + 1] = { label = "← Voltar", action = function()
    TriggerEvent("vhub_dealership:abrir_menu", _em_conc)
  end}
  abrirMenu(cat, itens, function()
    TriggerEvent("vhub_dealership:abrir_menu", _em_conc)
  end)
end

-- Handler principal — agrupa por categoria
AddEventHandler("vhub_dealership:abrir_menu", function()
  if not _pronto then notify("Concessionária não disponível."); return end
  local cats, seen = {}, {}
  for _, cfg in pairs(_catalogo) do
    if not seen[cfg.cat] then seen[cfg.cat] = true; cats[#cats + 1] = cfg.cat end
  end
  table.sort(cats)
  local itens = {}
  for _, cat in ipairs(cats) do
    local count, c2 = 0, cat
    for _, c in pairs(_catalogo) do if c.cat == cat then count = count + 1 end end
    itens[#itens + 1] = {
      label  = ("%s  (%d modelos)"):format(cat, count),
      action = function() abrirCategoria(c2) end
    }
  end
  itens[#itens + 1] = { label = "× Fechar", action = fecharMenu }
  abrirMenu("Concessionária", itens, fecharMenu)
end)

-- ── Setup recebido do servidor ────────────────────────────────────────────────

RegisterNetEvent("vhub_dealership:setup")
AddEventHandler("vhub_dealership:setup", function(concessionarias, catalogo)
  _concessionarias = type(concessionarias) == "table" and concessionarias or {}
  _catalogo        = type(catalogo)        == "table" and catalogo        or {}
  _pronto          = true
  -- Blips (cria uma única vez)
  if not _blips_criados then
    _blips_criados = true
    for i, c in ipairs(_concessionarias) do
      local blip = AddBlipForCoord(c.x, c.y, c.z)
      SetBlipSprite(blip, 326); SetBlipColour(blip, 3); SetBlipScale(blip, 0.75)
      SetBlipAsShortRange(blip, true)
      BeginTextCommandSetBlipName("STRING")
      AddTextComponentSubstringPlayerName(c.label or ("Concessionária #" .. i))
      EndTextCommandSetBlipName(blip)
    end
  end
end)

-- ── Notificações e eventos do servidor ───────────────────────────────────────

RegisterNetEvent("vhub_dealership:notify")
AddEventHandler("vhub_dealership:notify", function(msg) notify(msg) end)

RegisterNetEvent("vhub_dealership:compra_ok")
AddEventHandler("vhub_dealership:compra_ok", function(dados)
  if type(dados) ~= "table" then return end
  if _test_drive_veh and IsEntityAVehicle(_test_drive_veh) then
    TaskLeaveVehicle(PlayerPedId(), _test_drive_veh, 4160)
    Citizen.Wait(500)
    SetEntityAsMissionEntity(_test_drive_veh, false, true)
    SetVehicleAsNoLongerNeeded(Citizen.PointerValueIntInitialized(_test_drive_veh))
    _test_drive_veh = nil
  end
  TriggerEvent("vhub_dealership:veiculo_comprado", dados)
end)

RegisterNetEvent("vhub_dealership:do_test_drive")
AddEventHandler("vhub_dealership:do_test_drive", function(modelo, pos)
  Citizen.CreateThread(function()
    if _test_drive_veh and IsEntityAVehicle(_test_drive_veh) then
      TaskLeaveVehicle(PlayerPedId(), _test_drive_veh, 4160)
      Citizen.Wait(500)
      SetEntityAsMissionEntity(_test_drive_veh, false, true)
      SetVehicleAsNoLongerNeeded(Citizen.PointerValueIntInitialized(_test_drive_veh))
    end
    local mhash = GetHashKey(modelo)
    RequestModel(mhash)
    local w = 0
    while not HasModelLoaded(mhash) and w < 5000 do Citizen.Wait(100); w = w + 100 end
    if not HasModelLoaded(mhash) then notify("Modelo indisponível."); return end
    local veh = CreateVehicle(mhash, pos.x, pos.y, pos.z + 0.5, pos.heading or 0.0, true, false)
    SetModelAsNoLongerNeeded(mhash)
    SetVehicleOnGroundProperly(veh)
    SetEntityAsMissionEntity(veh, true, true)
    SetVehicleHasBeenOwnedByPlayer(veh, true)
    SetPedIntoVehicle(PlayerPedId(), veh, -1)
    _test_drive_veh = veh
    notify("Test drive iniciado! 5 minutos.")
    SetTimeout(300000, function()
      if _test_drive_veh == veh and IsEntityAVehicle(veh) then
        local ped = PlayerPedId()
        if GetVehiclePedIsIn(ped, false) == veh then
          TaskLeaveVehicle(ped, veh, 4160); Citizen.Wait(1000)
        end
        SetEntityAsMissionEntity(veh, false, true)
        SetVehicleAsNoLongerNeeded(Citizen.PointerValueIntInitialized(veh))
        _test_drive_veh = nil; notify("Test drive encerrado.")
      end
    end)
  end)
end)

-- ── Detecção de zona ─────────────────────────────────────────────────────────

Citizen.CreateThread(function()
  while true do
    Citizen.Wait(_pronto and 500 or 1000)
    if not _pronto then goto __z end
    local coords = GetEntityCoords(PlayerPedId())
    local nova   = nil
    for i, c in ipairs(_concessionarias) do
      if #(coords - vector3(c.x, c.y, c.z)) <= (c.raio or 10.0) then
        nova = i; break
      end
    end
    if nova ~= _em_conc then
      _em_conc = nova
      if nova then TriggerEvent("vhub_dealership:entrou_zona", nova, _concessionarias[nova])
      else TriggerEvent("vhub_dealership:saiu_zona") end
    end
    ::__z::
  end
end)

-- Frame loop: marker + hint + [E] apenas na zona
Citizen.CreateThread(function()
  while true do
    Citizen.Wait(0)
    if not _em_conc then Citizen.Wait(500); goto __f end
    local c = _concessionarias[_em_conc]
    DrawMarker(1, c.x, c.y, c.z - 1.0, 0,0,0, 0,0,0, 5.0,5.0,1.0,
      255,180,50,80, false,true,2,false,nil,nil,false)
    SetTextScale(0.35, 0.35); SetTextFont(4); SetTextProportional(true)
    SetTextColour(255, 255, 255, 215); SetTextOutline()
    SetTextEntry("STRING"); AddTextComponentString("[E] " .. (c.label or "Concessionária"))
    DrawText(0.5, 0.92)
    if IsControlJustReleased(0, 38) and not _menu then
      TriggerEvent("vhub_dealership:abrir_menu")
    end
    ::__f::
  end
end)

RegisterCommand("concessionaria", function()
  if _em_conc then TriggerEvent("vhub_dealership:abrir_menu")
  else notify("Você não está em uma concessionária.") end
end, false)

-- ── Getters ───────────────────────────────────────────────────────────────────

function vHub_getCatalogo()        return _catalogo        end
function vHub_getConcessionarias() return _concessionarias end
function vHub_getConcAtual()       return _em_conc         end
function vHub_getTestDriveVeh()    return _test_drive_veh  end
