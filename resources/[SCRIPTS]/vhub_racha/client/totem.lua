---@diagnostic disable: undefined-global, lowercase-global

-- client/totem.lua — TOTEM de checkpoint (nativo 3D, sempre ativo).
--
-- Design: UMA unica linha fina e longa, cor de areia de ouro neon, que nasce
-- NO CHAO (conectada a base, sem flutuar) e sobe. Mais alta a 999m, encolhe
-- ate sumir a 0m. Na base, uma nuvem de areia quase transparente (sombra
-- suave). No topo, o contador de distancia (%m). Sem esferas/bolas.
--
-- Renderizado SEMPRE via DrawMarker/DrawText — um totem, confiavel, sem NUI.


VHubRachaTotem = {}

local T   = VHubRachaTotem
local Cfg = VHubRachaCfg

local _target = nil


-- ============================================================
-- HELPERS
-- ============================================================

local function clamp(v, mn, mx)
  v = tonumber(v) or mn
  if v < mn then return mn end
  if v > mx then return mx end
  return v
end


local function render_range()
  return (Cfg.TOTEM and Cfg.TOTEM.RENDER_RANGE) or 999.0
end


-- Altura: mais alta a SCALE_DIST (999m), encolhe linear ate MIN no 0m.
local function height_for(dist_m)
  local cfg   = Cfg.TOTEM or {}
  local t     = clamp(dist_m / (cfg.SCALE_DIST or 999.0), 0.0, 1.0)
  local min_h = cfg.MIN_HEIGHT or 5.0
  local max_h = cfg.MAX_HEIGHT or 350.0
  return min_h + ((max_h - min_h) * t)
end


-- Cor da linha por tipo de CP (areia de ouro neon por padrao).
local function color_for(target)
  local cfg = Cfg.TOTEM or {}
  if type(target) ~= 'table' then return cfg.COLOR_DEFAULT or { r = 248, g = 200, b = 105 } end
  if target.is_finish           then return cfg.COLOR_FINISH     or { r = 120, g = 230, b = 140 } end
  if target.kind == 'speedtrap' then return cfg.COLOR_SPEEDTRAP  or { r = 38,  g = 220, b = 80  } end
  if target.kind == 'drift'     then return cfg.COLOR_DRIFT_ZONE or { r = 190, g = 120, b = 255 } end
  return cfg.COLOR_DEFAULT or { r = 248, g = 200, b = 105 }
end


local function valid_target(target)
  if type(target) ~= 'table' then return false end
  return type(target.x) == 'number' and type(target.y) == 'number' and type(target.z) == 'number'
end


local function dist_label_of(dist_m)
  if dist_m >= 1000.0 then return ('%.2f KM'):format(dist_m / 1000.0) end
  return ('%d M'):format(math.floor(dist_m))
end


-- ============================================================
-- API PUBLICA
-- ============================================================

function T.set_target(target)
  if not valid_target(target) then _target = nil; return end
  _target = target
end


function T.clear() _target = nil end


function T.current() return _target end


-- ============================================================
-- RENDER
-- ============================================================

-- Contador de distancia (%m) projetado acima do topo da linha.
local function draw_top_label(target, top_z, dist_m)
  local on_screen, sx, sy = GetScreenCoordFromWorldCoord(target.x, target.y, top_z + 1.5)
  if not on_screen then return end

  SetTextFont(4)
  SetTextScale(0.0, 0.50)
  SetTextColour(255, 226, 155, 250)
  SetTextOutline()
  SetTextDropShadow()
  SetTextCentre(true)
  SetTextEntry('STRING')
  AddTextComponentString(dist_label_of(dist_m))
  DrawText(sx, sy - 0.02)
end


-- Desenha o totem: nuvem de areia na base + linha unica solida + label.
local function draw_totem(target, dist_m)
  if not valid_target(target) then return end

  local cfg    = Cfg.TOTEM or {}
  local body   = color_for(target)
  local height = height_for(dist_m)
  local cx, cy, cz = target.x, target.y, target.z

  local gnd  = cfg.GROUND_OFFSET or 1.0
  local foot = cz - gnd            -- base no chao (conecta a linha ao solo)
  local w    = cfg.COLUMN_W   or 0.35
  local br   = cfg.BASE_RADIUS or 5.0


  -- 1) Nuvem de areia na base — sombra quase transparente (2 discos suaves)
  DrawMarker(1, cx, cy, foot + 0.03, 0,0,0, 0,0,0,
    br * 2.0, br * 2.0, 0.04,
    body.r, body.g, body.b, 20, false, false, 2, false, nil, nil, false)
  DrawMarker(1, cx, cy, foot + 0.02, 0,0,0, 0,0,0,
    br * 1.1, br * 1.1, 0.04,
    body.r, body.g, body.b, 14, false, false, 2, false, nil, nil, false)


  -- 2) Linha UNICA solida (neon areia-ouro), ANCORADA no chao e subindo.
  -- DrawMarker tipo 1 cresce a partir da posicao (base = foot), entao a
  -- coluna nasce no solo e sobe `height` — sem flutuar.
  DrawMarker(1, cx, cy, foot, 0,0,0, 0,0,0,
    w, w, height,
    body.r, body.g, body.b, 235, false, false, 2, false, nil, nil, false)


  -- 3) Distancia (%m) no topo
  draw_top_label(target, foot + height, dist_m)
end


-- ============================================================
-- THREAD — desenha enquanto ha alvo no alcance
-- ============================================================

CreateThread(function()
  while true do
    local target = _target
    if not target then
      Wait(400)
    else
      local pos  = GetEntityCoords(PlayerPedId())
      local dx   = pos.x - target.x
      local dy   = pos.y - target.y
      local dz   = pos.z - target.z
      local dist = math.sqrt(dx * dx + dy * dy + dz * dz)

      if dist > render_range() then
        Wait(500)
      else
        Wait(0)
        draw_totem(target, dist)
      end
    end
  end
end)


-- ============================================================
-- CLEANUP
-- ============================================================

AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  _target = nil
end)
