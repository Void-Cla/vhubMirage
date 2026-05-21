-- vhub_money/client.lua
-- HUD de saldo + ATMs interativos ([E] depositar/sacar).
-- Servidor valida tudo — cliente só envia pedidos.

local _carteira = 0
local _banco    = 0
local _mostrar  = false

-- ── HUD e notificações ────────────────────────────────────────────────────────

RegisterNetEvent("vhub_money:hud")
AddEventHandler("vhub_money:hud", function(dados)
  if type(dados) == "table" then
    _carteira = tonumber(dados.carteira) or 0
    _banco    = tonumber(dados.banco)    or 0
  elseif type(dados) == "number" then
    _carteira = dados
  end
  _mostrar = true
  TriggerEvent("vhub_money:local_update", _carteira, _banco)
end)

RegisterNetEvent("vhub_money:update_hud")
AddEventHandler("vhub_money:update_hud", function(carteira, banco)
  _carteira = tonumber(carteira) or 0
  _banco    = tonumber(banco)    or 0
  _mostrar  = true
  TriggerEvent("vhub_money:local_update", _carteira, _banco)
end)

RegisterNetEvent("vhub_money:notify")
AddEventHandler("vhub_money:notify", function(msg)
  BeginTextCommandThefeedPost("STRING")
  AddTextComponentSubstringPlayerName(tostring(msg))
  EndTextCommandThefeedPostTicker(false, true)
end)

-- ── ATMs (localizações reais GTA V) ──────────────────────────────────────────

local ATMS = {
  { label = "ATM — Fleeca Downtown",    x = -1213.74, y = -330.41,  z = 37.78  },
  { label = "ATM — Fleeca Little Seoul",x = -1393.37, y = -590.83,  z = 30.33  },
  { label = "ATM — Fleeca Morningwood", x = -350.65,  y = -48.36,   z = 49.04  },
  { label = "ATM — Fleeca Strawberry",  x = -527.49,  y = -696.53,  z = 28.36  },
  { label = "ATM — Blaine County Bank", x = 314.02,   y = -279.95,  z = 54.17  },
  { label = "ATM — Sandy Shores",        x = 1401.11,  y = 3877.95,  z = 32.38  },
  { label = "ATM — Paleto Bay",         x = -113.01,  y = 6471.07,  z = 31.87  },
}
local ATM_RAIO = 3.5

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function fmtMoney(n)
  local s, res, c = tostring(math.floor(n or 0)), "", 0
  for i = #s, 1, -1 do
    res = s:sub(i, i) .. res; c = c + 1
    if c % 3 == 0 and i > 1 then res = "." .. res end
  end
  return "R$ " .. res
end

local function notify(msg)
  BeginTextCommandThefeedPost("STRING")
  AddTextComponentSubstringPlayerName(msg)
  EndTextCommandThefeedPostTicker(false, true)
end

local function pedirNumero(titulo, cb)
  Citizen.CreateThread(function()
    DisplayOnscreenKeyboard(1, "FMMC_KEY_TIP1", titulo, "", "", "", "", 10)
    while UpdateOnscreenKeyboard() == 0 do Citizen.Wait(0) end
    local r = GetOnscreenKeyboardResult()
    local n = tonumber(r)
    if n and n > 0 then cb(math.floor(n))
    else notify("Valor inválido.") end
  end)
end

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
    ::__m::
  end
end)

-- ── ATM: menu de operações ────────────────────────────────────────────────────

local function abrirATM(atm)
  abrirMenu("Banco  — " .. atm.label, {
    { label = "Carteira:  " .. fmtMoney(_carteira), action = function() end },
    { label = "Banco:     " .. fmtMoney(_banco),    action = function() end },
    { label = "Depositar na conta", action = function()
        fecharMenu()
        pedirNumero("Quanto depositar?", function(val)
          TriggerServerEvent("vhub_money:deposit", val)
        end)
    end},
    { label = "Sacar da conta", action = function()
        fecharMenu()
        pedirNumero("Quanto sacar?", function(val)
          TriggerServerEvent("vhub_money:withdraw", val)
        end)
    end},
    { label = "× Fechar", action = fecharMenu },
  }, fecharMenu)
end

-- ── Blips dos ATMs ────────────────────────────────────────────────────────────

Citizen.CreateThread(function()
  for _, atm in ipairs(ATMS) do
    local blip = AddBlipForCoord(atm.x, atm.y, atm.z)
    SetBlipSprite(blip, 108)       -- ícone de dinheiro/banco
    SetBlipColour(blip, 2)         -- verde
    SetBlipScale(blip, 0.65)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentSubstringPlayerName(atm.label)
    EndTextCommandSetBlipName(blip)
  end
end)

-- ── Detecção de proximidade ao ATM ───────────────────────────────────────────

local _em_atm = nil

Citizen.CreateThread(function()
  while true do
    Citizen.Wait(600)
    local coords  = GetEntityCoords(PlayerPedId())
    local novo    = nil
    for i, atm in ipairs(ATMS) do
      if #(coords - vector3(atm.x, atm.y, atm.z)) <= ATM_RAIO then
        novo = i; break
      end
    end
    if novo ~= _em_atm then _em_atm = novo end
  end
end)

-- Frame loop: marker + hint + [E] quando perto de ATM
Citizen.CreateThread(function()
  while true do
    Citizen.Wait(0)
    if not _em_atm then Citizen.Wait(500); goto __f end
    local atm = ATMS[_em_atm]
    DrawMarker(27,
      atm.x, atm.y, atm.z,
      0,0,0, 0,0,0, 0.4,0.4,0.4,
      50,205,50,180, false,false,2,false,nil,nil,false)
    SetTextScale(0.35, 0.35); SetTextFont(4); SetTextProportional(true)
    SetTextColour(255, 255, 255, 215); SetTextOutline()
    SetTextEntry("STRING")
    AddTextComponentString("[E] " .. atm.label)
    DrawText(0.5, 0.92)
    if IsControlJustReleased(0, 38) and not _menu then
      abrirATM(atm)
    end
    ::__f::
  end
end)

-- ── Getters ───────────────────────────────────────────────────────────────────

function vHub_getCarteira() return _carteira end
function vHub_getBanco()    return _banco    end
function vHub_mostraMoney() return _mostrar  end
