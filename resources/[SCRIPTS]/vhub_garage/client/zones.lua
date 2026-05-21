-- client/zones.lua  detec  o de zona + blips + marker + [E]
-- Cria blips uma vez, varre zonas em 500ms, frame loop ativo apenas dentro de uma zona.
---@diagnostic disable: undefined-global

local E = VHubGarage.E
local state = VHubGarage.state

local _blips = false

local function spawnBlips()
  if _blips then return end; _blips = true
  for _, g in ipairs(state.garagens) do
    local b = AddBlipForCoord(g.x, g.y, g.z)
    SetBlipSprite(b, g.blip and g.blip.sprite or 357)
    SetBlipColour(b, g.blip and g.blip.color or 5)
    SetBlipScale(b,  g.blip and g.blip.scale or 0.75)
    SetBlipAsShortRange(b, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(g.label or 'Garagem')
    EndTextCommandSetBlipName(b)
  end
  for _, c in ipairs(state.concessionarias) do
    local b = AddBlipForCoord(c.x, c.y, c.z)
    SetBlipSprite(b, c.blip and c.blip.sprite or 326)
    SetBlipColour(b, c.blip and c.blip.color or 3)
    SetBlipScale(b,  c.blip and c.blip.scale or 0.85)
    SetBlipAsShortRange(b, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(c.label or 'Concession ria')
    EndTextCommandSetBlipName(b)
  end
  if state.leilao then
    local b = AddBlipForCoord(state.leilao.x, state.leilao.y, state.leilao.z)
    SetBlipSprite(b, state.leilao.blip and state.leilao.blip.sprite or 431)
    SetBlipColour(b, state.leilao.blip and state.leilao.blip.color or 46)
    SetBlipScale(b,  state.leilao.blip and state.leilao.blip.scale or 0.85)
    SetBlipAsShortRange(b, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(state.leilao.label or 'Casa de Leil es')
    EndTextCommandSetBlipName(b)
  end
  if state.patio then
    local b = AddBlipForCoord(state.patio.x, state.patio.y, state.patio.z)
    SetBlipSprite(b, state.patio.blip and state.patio.blip.sprite or 67)
    SetBlipColour(b, state.patio.blip and state.patio.blip.color or 1)
    SetBlipScale(b,  state.patio.blip and state.patio.blip.scale or 0.85)
    SetBlipAsShortRange(b, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(state.patio.label or 'P tio')
    EndTextCommandSetBlipName(b)
  end
end

AddEventHandler('vhub_garage:setupReady', spawnBlips)

-- ----------------------------------------------------------------------------
-- Detec  o de zona (low frequency)
-- ----------------------------------------------------------------------------
local function findZone(coords)
  for _, g in ipairs(state.garagens) do
    if #(coords - vector3(g.x, g.y, g.z)) <= (g.raio or 8.0) then
      return { kind = 'garage', id = g.id, data = g }
    end
  end
  for _, c in ipairs(state.concessionarias) do
    if #(coords - vector3(c.x, c.y, c.z)) <= (c.raio or 10.0) then
      return { kind = 'dealer', id = c.id, data = c }
    end
  end
  if state.leilao then
    local l = state.leilao
    if #(coords - vector3(l.x, l.y, l.z)) <= (l.raio or 6.0) then
      return { kind = 'auction', id = l.id, data = l }
    end
  end
  if state.patio then
    local p = state.patio
    if #(coords - vector3(p.x, p.y, p.z)) <= (p.raio or 8.0) then
      return { kind = 'impound', id = p.id, data = p }
    end
  end
end

Citizen.CreateThread(function()
  while true do
    Citizen.Wait(state.pronto and 500 or 1500)
    if state.pronto and not state.nui_aberta then
      local ped = PlayerPedId()
      local z = findZone(GetEntityCoords(ped))
      if (z and (not state.zona or z.id ~= state.zona.id))
         or (state.zona and not z) then
        state.zona = z
        TriggerEvent('vhub_garage:zonaTrocou', z)
      end
    end
  end
end)

-- ----------------------------------------------------------------------------
-- Frame loop ativo apenas dentro de uma zona (marker + [E])
-- ----------------------------------------------------------------------------
local function colorFor(kind)
  if kind == 'garage'  then return 100, 200, 255 end
  if kind == 'dealer'  then return 255, 180, 50  end
  if kind == 'auction' then return 180, 80, 220  end
  if kind == 'impound' then return 230, 60, 60   end
  return 255, 255, 255
end

Citizen.CreateThread(function()
  while true do
    Citizen.Wait(0)
    if not state.zona or state.nui_aberta then
      Citizen.Wait(500)
    else
      local z = state.zona; local d = z.data
      local r, g, b = colorFor(z.kind)
      DrawMarker(1,
        d.x, d.y, d.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        4.0, 4.0, 1.0, r, g, b, 80, false, true, 2, false, nil, nil, false)
      local pc = GetEntityCoords(PlayerPedId())
      if #(pc - vector3(d.x, d.y, d.z)) <= (d.raio or 8.0) then
        SetTextScale(0.35, 0.35); SetTextFont(4); SetTextProportional(true)
        SetTextColour(255, 255, 255, 215); SetTextOutline()
        SetTextEntry('STRING')
        AddTextComponentString(('[E] %s'):format(d.label or '?'))
        DrawText(0.5, 0.92)
      end
      if IsControlJustReleased(0, 38) then
        if z.kind == 'garage'   then TriggerServerEvent(E.REQ_LIST) end
        if z.kind == 'dealer'   then TriggerServerEvent(E.REQ_CATALOG, z.id) end
        if z.kind == 'auction'  then TriggerServerEvent(E.REQ_AUCTIONS) end
        if z.kind == 'impound'  then TriggerServerEvent(E.REQ_IMPOUND) end
      end
    end
  end
end)
