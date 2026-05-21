-- vhub_inventory/client.lua
-- [TAB] abre/fecha mochila. Seta+Enter navega, Enter usa item, Esc fecha.
-- Servidor é autoridade — cliente só solicita uso via net event.

local _inventario = {}
local _bau_aberto = nil
local _inv_aberto = false

-- ── Recebe inventário do servidor ─────────────────────────────────────────────

RegisterNetEvent("vhub_inventory:update")
AddEventHandler("vhub_inventory:update", function(inv)
  _inventario = type(inv) == "table" and inv or {}
  TriggerEvent("vhub_inventory:local_update", _inventario)
end)

RegisterNetEvent("vhub_inventory:notify")
AddEventHandler("vhub_inventory:notify", function(msg)
  BeginTextCommandThefeedPost("STRING")
  AddTextComponentSubstringPlayerName(msg)
  EndTextCommandThefeedPostTicker(false, true)
end)

-- Baú
RegisterNetEvent("vhub_inventory:open_chest")
AddEventHandler("vhub_inventory:open_chest", function(bau_id, conteudo, peso_max)
  _bau_aberto = { id = bau_id, conteudo = conteudo, peso_max = peso_max }
  TriggerEvent("vhub_inventory:chest_opened", _bau_aberto)
end)

RegisterNetEvent("vhub_inventory:chest_sync")
AddEventHandler("vhub_inventory:chest_sync", function(bau_id, conteudo)
  if _bau_aberto and _bau_aberto.id == bau_id then
    _bau_aberto.conteudo = conteudo
    TriggerEvent("vhub_inventory:chest_updated", _bau_aberto)
  end
end)

-- ── Nomes de display (fallback sem def do servidor) ──────────────────────────

local function nomeItem(fullid)
  local base = fullid:match("^([^|]+)")
  local arg  = fullid:match("|(.+)$")
  local nomes = {
    repairkit    = "Kit de Reparo",    water_bottle = "Garrafa d'Água",
    sandwich     = "Sanduíche",         bandage      = "Bandagem",
    medkit       = "Kit Médico",        handcuffs    = "Algemas",
    lockpick     = "Gazua",             phone        = "Celular",
    radio        = "Rádio",             id_card      = "Carteira de ID",
    veh_key      = "Chave",
  }
  local nome = nomes[base] or base
  return arg and (nome .. " [" .. arg .. "]") or nome
end

-- ── Construção da lista de itens ──────────────────────────────────────────────

local function buildLista()
  local lista = {}
  for fid, amt in pairs(_inventario) do
    if amt and amt > 0 then
      lista[#lista + 1] = { fid = fid, amt = amt, label = nomeItem(fid) .. "  x" .. amt }
    end
  end
  table.sort(lista, function(a, b) return a.label < b.label end)
  return lista
end

-- ── UI nativa (mochila) ───────────────────────────────────────────────────────

local _lista = {}
local _sel   = 1

Citizen.CreateThread(function()
  while true do
    if not _inv_aberto then Citizen.Wait(200); goto __i end
    Citizen.Wait(0)

    local n   = #_lista
    local sel = _sel

    if n == 0 then
      -- Inventário vazio
      DrawRect(0.845, 0.5, 0.295, 0.18, 8, 8, 12, 210)
      DrawRect(0.845, 0.423, 0.295, 0.076, 22, 60, 155, 240)
      SetTextFont(1); SetTextScale(0, 0.44); SetTextColour(255, 210, 55, 255); SetTextOutline()
      SetTextEntry("STRING"); AddTextComponentString("Mochila"); DrawText(0.708, 0.396)
      SetTextFont(0); SetTextScale(0, 0.37); SetTextColour(180, 180, 180, 255)
      SetTextEntry("STRING"); AddTextComponentString("(vazia)"); DrawText(0.720, 0.472)
      if IsControlJustReleased(0, 37) or IsControlJustReleased(0, 200) or IsControlJustReleased(0, 177) then
        _inv_aberto = false
      end
      goto __i
    end

    local h   = math.min(n * 0.057 + 0.11, 0.88)
    local top = 0.5 - h * 0.5

    DrawRect(0.845, 0.5, 0.295, h, 8, 8, 12, 210)
    DrawRect(0.845, top + 0.038, 0.295, 0.076, 22, 60, 155, 240)
    SetTextFont(1); SetTextScale(0, 0.44); SetTextColour(255, 210, 55, 255); SetTextOutline()
    SetTextEntry("STRING"); AddTextComponentString("Mochila  [TAB]"); DrawText(0.708, top + 0.010)

    for i = 1, n do
      local y = top + 0.086 + (i - 1) * 0.057
      if i == sel then
        DrawRect(0.845, y + 0.026, 0.291, 0.052, 255, 205, 50, 55)
        SetTextColour(255, 235, 80, 255)
      else
        SetTextColour(218, 218, 218, 255)
      end
      SetTextFont(0); SetTextScale(0, 0.37); SetTextEntry("STRING")
      AddTextComponentString(_lista[i].label); DrawText(0.709, y)
    end

    -- Dica de uso na base
    SetTextFont(0); SetTextScale(0, 0.30); SetTextColour(150, 150, 150, 200)
    SetTextEntry("STRING"); AddTextComponentString("Enter = Usar   Esc = Fechar")
    DrawText(0.709, top + h - 0.04)

    -- Controles
    if IsControlJustReleased(0, 172) then
      _sel = sel > 1 and sel - 1 or n
    elseif IsControlJustReleased(0, 173) then
      _sel = sel < n and sel + 1 or 1
    elseif IsControlJustReleased(0, 201) or IsControlJustReleased(0, 176) then
      local item = _lista[sel]
      if item then
        TriggerServerEvent("vhub_inventory:use", item.fid)
      end
    elseif IsControlJustReleased(0, 37) or IsControlJustReleased(0, 200) or IsControlJustReleased(0, 177) then
      _inv_aberto = false
    end

    ::__i::
  end
end)

-- TAB (37) para abrir/fechar mochila
Citizen.CreateThread(function()
  while true do
    Citizen.Wait(0)
    if IsControlJustReleased(0, 37) and not _inv_aberto then
      _lista      = buildLista()
      _sel        = 1
      _inv_aberto = true
    end
  end
end)

-- Atualiza lista quando inventário mudar com a UI aberta
AddEventHandler("vhub_inventory:local_update", function()
  if _inv_aberto then
    _lista = buildLista()
    if _sel > #_lista then _sel = math.max(1, #_lista) end
  end
end)

-- ── Getters para scripts externos ─────────────────────────────────────────────

function vHub_getInventario()       return _inventario          end
function vHub_getBauAberto()        return _bau_aberto          end
function vHub_hasItem(fid, amount)  return (_inventario[fid] or 0) >= (amount or 1) end
function vHub_getItemAmount(fid)    return _inventario[fid] or 0 end
