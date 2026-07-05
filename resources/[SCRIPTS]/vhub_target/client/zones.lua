-- client/zones.lua — engine própria de zonas do targeting (box/sphere/poly)
-- Substitui lib.zones do ox_lib. Zonas aqui são de INTERAÇÃO POR MIRA (UX client),
-- distintas das zonas de negócio dos domínios (ex.: vhub_custom/client/zones.lua).
--
-- Budget (L-18): getNearby() roda SOMENTE com targeting ativo (olho aberto), no tick
-- do loop principal (50/100 ms = 10–20 Hz), custo O(n) linear sobre as zonas
-- registradas. Custo com olho fechado: ZERO (nenhuma thread própria).
-- Cap defensivo: cfg.maxZones (warn one-shot acima; nunca trava).
-- Cfx Lua (LuaGLM): usa table.wipe/vector — não é Lua 5.4 puro.
---@diagnostic disable: undefined-global, lowercase-global, undefined-field

VHubTarget = VHubTarget or {}

local zones   = {}    -- id → zone
local nextId  = 0
local total   = 0
local warned  = false

local Z = {}
VHubTarget.zones = Z
VHubTarget.Zones = zones   -- exposto p/ api.lua (zoneExists / removeZone / cleanup por resource)


-- ============================================================
-- CONTAINS por tipo (funções puras, sem alocação no hot path)
-- ============================================================

-- esfera: distância ao centro
local function sphereContains(self, pos)
  return #(pos - self.coords) <= self.radius
end

-- caixa: rotaciona o ponto para o espaço local (heading) + teste AABB
local function boxContains(self, pos)
  local d = pos - self.coords
  if d.z < -self.halfZ or d.z > self.halfZ then return false end

  local lx =  d.x * self.cos + d.y * self.sin
  local ly = -d.x * self.sin + d.y * self.cos
  return lx >= -self.halfX and lx <= self.halfX and ly >= -self.halfY and ly <= self.halfY
end

-- polígono: ray-casting 2D + faixa de altura
local function polyContains(self, pos)
  if pos.z < self.minZ or pos.z > self.maxZ then return false end

  local pts, inside, j = self.points, false, #self.points
  for i = 1, #pts do
    local pi, pj = pts[i], pts[j]
    if (pi.y > pos.y) ~= (pj.y > pos.y)
      and pos.x < (pj.x - pi.x) * (pos.y - pi.y) / (pj.y - pi.y) + pi.x then
      inside = not inside
    end
    j = i
  end
  return inside
end


-- ============================================================
-- REGISTRO (add/remove)
-- ============================================================

-- remove a zona do registro (método de instância)
local function zoneRemove(self)
  if zones[self.id] then
    zones[self.id] = nil
    total = total - 1
  end
end

-- registra uma zona montada; devolve a própria zona (com id)
local function register(zone)
  nextId = nextId + 1
  total = total + 1
  zone.id = nextId
  zone.remove = zoneRemove
  zones[nextId] = zone

  -- cap defensivo (advisory): flag consultável; sem print (R10) — resmon/debug expõem
  if not warned and total > VHubTarget.cfg.maxZones then
    warned = true
    VHubTarget.zonesOverCap = total
  end

  return zone
end

-- cria zona esférica { coords, radius, options, resource, name?, drawSprite?, distance? }
function Z.addSphere(data)
  data.contains = sphereContains
  data.radius = data.radius or 2.0
  return register(data)
end

-- cria zona caixa { coords, size(vec3), rotation(graus), ... }
function Z.addBox(data)
  local size = data.size or vec3(2.0, 2.0, 2.0)
  local rad  = math.rad(data.rotation or 0)
  data.halfX, data.halfY, data.halfZ = size.x / 2, size.y / 2, size.z / 2
  data.cos, data.sin = math.cos(rad), math.sin(rad)
  data.contains = boxContains
  return register(data)
end

-- cria zona polígono { points = {vec3,...}, thickness, ... } (coords = centróide p/ sprite)
function Z.addPoly(data)
  local pts = data.points
  local cx, cy, minZ, maxZ = 0, 0, math.huge, -math.huge

  for i = 1, #pts do
    local p = pts[i]
    cx, cy = cx + p.x, cy + p.y
    if p.z < minZ then minZ = p.z end
    if p.z > maxZ then maxZ = p.z end
  end

  local thick = (data.thickness or 4.0) / 2
  data.minZ = minZ - thick
  data.maxZ = maxZ + thick
  data.coords = data.coords or vec3(cx / #pts, cy / #pts, (minZ + maxZ) / 2)
  data.contains = polyContains
  return register(data)
end


-- ============================================================
-- CONSULTA — usada pelo loop de targeting (main.lua)
-- ============================================================

local drawSpriteCap = 0
local colour = vector(155, 155, 155, 175)
local hover  = vector(243, 181, 58, 255)   -- dourado vHub no hover
local currentZones, previousZones, drawZones = {}, {}, {}
local prevSet = {}   -- set reutilizável p/ diff O(n) (sem alocação por tick)
local drawN = 0
local width = 0.02
local height = width * GetAspectRatio(false)

-- retorna zonas que contêm o ponto + flag "mudou desde a última consulta"
function Z.getNearby(coords)
  local n = 0
  drawN = 0
  drawSpriteCap = VHubTarget.cfg.drawSprite
  previousZones, currentZones = currentZones, table.wipe(previousZones)

  for _, zone in pairs(zones) do
    local contains = zone:contains(coords)

    if contains then
      n = n + 1
      currentZones[n] = zone
    end

    if drawSpriteCap > 0 and drawN < drawSpriteCap and zone.drawSprite ~= false
      and (contains or #(coords - zone.coords) < (zone.distance or 7)) then
      drawN = drawN + 1
      drawZones[drawN] = zone
      zone.colour = contains and hover or nil
    end
  end

  local previousN = #previousZones
  if n ~= previousN then return currentZones, true end

  -- diff O(n): indexa o conjunto anterior num set e checa presença (era O(n²) aninhado)
  table.wipe(prevSet)
  for j = 1, previousN do prevSet[previousZones[j]] = true end
  for i = 1, n do
    if not prevSet[currentZones[i]] then return currentZones, true end
  end

  return currentZones, false
end

-- desenha os sprites das zonas próximas (chamado pela thread de input do main)
function Z.drawSprites(dict, texture)
  if drawN == 0 then return end

  for i = 1, drawN do
    local zone = drawZones[i]
    local c = zone.colour or colour
    SetDrawOrigin(zone.coords.x, zone.coords.y, zone.coords.z)
    DrawSprite(dict, texture, 0, 0, width, height, 0, c.r, c.g, c.b, c.a)
  end

  ClearDrawOrigin()
end
