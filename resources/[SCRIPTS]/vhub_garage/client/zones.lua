-- client/zones.lua — detecção de zona + blips + marker + [E]
-- Blips de garagem/pátio criados do cfg local (sem dep. de SETUP).
-- Blip de ferinha criado após SETUP, com handle tracking idempotente.
-- Blips de concessionária são criados pelo próprio vhub_conce (ownership correto).
---@diagnostic disable: undefined-global

local E     = VHubGarage.E
local state = VHubGarage.state
local CFG   = VHubGarage.cfg


-- ============================================================
-- UTILITÁRIO DE BLIP
-- ============================================================

-- cria blip e retorna o handle
local function makeBlip(x, y, z, sprite, color, scale, label)
  local b = AddBlipForCoord(x, y, z)
  SetBlipSprite(b, sprite)
  SetBlipColour(b, color)
  SetBlipScale(b, scale)
  SetBlipAsShortRange(b, false)
  BeginTextCommandSetBlipName('STRING')
  AddTextComponentSubstringPlayerName(label)
  EndTextCommandSetBlipName(b)
  return b
end


-- ============================================================
-- BLIPS ESTÁTICOS — garagens e pátio (cfg local, sem SETUP)
-- ============================================================

Citizen.CreateThread(function()
  Citizen.Wait(0)

  for _, g in ipairs(CFG.garagens or {}) do
    makeBlip(
      g.coord.x, g.coord.y, g.coord.z,
      g.blip and g.blip.sprite or 357,
      g.blip and g.blip.color  or 5,
      g.blip and g.blip.scale  or 0.75,
      g.label or 'Garagem'
    )
  end

  local p = CFG.patio_local
  if p then
    makeBlip(
      p.coord.x, p.coord.y, p.coord.z,
      p.blip and p.blip.sprite or 67,
      p.blip and p.blip.color  or 1,
      p.blip and p.blip.scale  or 0.85,
      p.label or 'Pátio'
    )
  end
end)


-- ============================================================
-- BLIP DINÂMICO — ferinha (chega via SETUP)
-- ============================================================

local _dynBlips = {}

-- recria blip dinâmico a cada SETUP (idempotente) — apenas ferinha
local function spawnDynamicBlips()
  for _, b in ipairs(_dynBlips) do
    if DoesBlipExist(b) then RemoveBlip(b) end
  end
  _dynBlips = {}

  if state.leilao then
    local l = state.leilao
    _dynBlips[#_dynBlips + 1] = makeBlip(
      l.x, l.y, l.z,
      l.blip and l.blip.sprite or 431,
      l.blip and l.blip.color  or 46,
      l.blip and l.blip.scale  or 0.85,
      l.label or 'Casa de Leilões'
    )
  end
end

AddEventHandler('vhub_garage:setupReady', spawnDynamicBlips)


-- ============================================================
-- RESOLUÇÃO DE ZONAS (fallback p/ cfg quando SETUP ainda pendente)
-- ============================================================

-- retorna lista de garagens; fallback para cfg se state ainda vazio
local function getGaragens()
  if state.garagens and #state.garagens > 0 then return state.garagens end
  local out = {}
  for _, g in ipairs(CFG.garagens or {}) do
    out[#out + 1] = {
      id = g.id, label = g.label, h = g.h, raio = g.raio,
      tipos = g.tipos, blip = g.blip,
      x = g.coord.x, y = g.coord.y, z = g.coord.z,
    }
  end
  return out
end

-- retorna pátio; fallback para cfg se state ainda vazio
local function getPatio()
  if state.patio then return state.patio end
  local p = CFG.patio_local
  if not p then return nil end
  return { id = p.id, label = p.label, raio = p.raio,
           x = p.coord.x, y = p.coord.y, z = p.coord.z }
end

local function findZone(coords)
  for _, g in ipairs(getGaragens()) do
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
  local pt = getPatio()
  if pt then
    if #(coords - vector3(pt.x, pt.y, pt.z)) <= (pt.raio or 8.0) then
      return { kind = 'impound', id = pt.id, data = pt }
    end
  end
end


-- ============================================================
-- DETECÇÃO DE ZONA (500ms; garagens disponíveis sem SETUP)
-- ============================================================

Citizen.CreateThread(function()
  while true do
    Citizen.Wait(500)
    if not state.nui_aberta then
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


-- ============================================================
-- FRAME LOOP — marker + [E]
-- ============================================================

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
        if z.kind == 'garage'   then TriggerServerEvent(E.REQ_LIST)              end
        if z.kind == 'dealer'   then TriggerServerEvent(E.REQ_CATALOG, z.id)     end
        if z.kind == 'auction'  then TriggerServerEvent(E.REQ_AUCTIONS)          end
        if z.kind == 'impound'  then TriggerServerEvent(E.REQ_IMPOUND)           end
      end
    end
  end
end)
