---@diagnostic disable: undefined-global, lowercase-global

-- client/totem.lua — TOTEM unico e verdadeiro (nativo 3D, sempre ativo).
--
-- Fiel ao design Forza: linha FINA e LONGA de areia dourada com glow forte,
-- ALTA de longe (999m = mais alta) e encolhe ate sumir ao chegar perto (0m).
-- Na base, rasteirinha de poeira de areia marcando o diametro do CP + baforadas
-- subindo. No topo, contador de distancia (km/m) + label do CP.
--
-- Renderizado SEMPRE via DrawMarker/DrawText (independente de NUI) — garante
-- que aparece de forma confiavel, sem depender do CEF. UM totem, sem duplicacao.


VHubRachaTotem = {}

local T   = VHubRachaTotem
local Cfg = VHubRachaCfg

local _target    = nil
local _t0        = GetGameTimer()
local _particles = {}


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


-- Altura: mais alta a SCALE_DIST (999m) e encolhe linearmente ate MIN no 0m.
local function height_for(dist_m)
  local cfg   = Cfg.TOTEM or {}
  local t     = clamp(dist_m / (cfg.SCALE_DIST or 999.0), 0.0, 1.0)
  local min_h = cfg.MIN_HEIGHT or 8.0
  local max_h = cfg.MAX_HEIGHT or 150.0
  return min_h + ((max_h - min_h) * t)
end


-- Cor do corpo por tipo de CP (areia dourada por padrao).
local function color_for(target)
  local cfg = Cfg.TOTEM or {}
  if type(target) ~= 'table' then return cfg.COLOR_DEFAULT or { r = 232, g = 198, b = 130 } end
  if target.is_finish           then return cfg.COLOR_FINISH     or { r = 120, g = 230, b = 140 } end
  if target.kind == 'speedtrap' then return cfg.COLOR_SPEEDTRAP  or { r = 38,  g = 220, b = 80  } end
  if target.kind == 'drift'     then return cfg.COLOR_DRIFT_ZONE or { r = 190, g = 120, b = 255 } end
  return cfg.COLOR_DEFAULT or { r = 232, g = 198, b = 130 }
end


local function core_color()
  return (Cfg.TOTEM or {}).COLOR_CORE or { r = 255, g = 244, b = 210 }
end


local function valid_target(target)
  if type(target) ~= 'table' then return false end
  return type(target.x) == 'number' and type(target.y) == 'number' and type(target.z) == 'number'
end


local function dist_label_of(dist_m)
  if dist_m >= 1000.0 then return ('%.2f KM'):format(dist_m / 1000.0) end
  return ('%d M'):format(math.floor(dist_m))
end


-- Inicializa baforadas de poeira dentro do raio do portal da base.
local function init_particles()
  local cfg  = Cfg.TOTEM or {}
  local n    = cfg.DUST_COUNT or 10
  local pw   = cfg.BASE_RADIUS or 11.0
  for i = 1, n do
    _particles[i] = {
      offset_z = math.random() * 4.0,
      angle    = math.random() * math.pi * 2.0,
      speed    = 0.30 + (math.random() * 0.80),
      radius   = math.random() * (pw * 0.8),
      size     = 0.8 + (math.random() * 1.4),
    }
  end
  for i = n + 1, #_particles do _particles[i] = nil end
end


-- ============================================================
-- API PUBLICA
-- ============================================================

-- Define o CP alvo (nil = limpa). Apenas estado — o render e por thread.
function T.set_target(target)
  if not valid_target(target) then _target = nil; return end
  _target = target
  _t0     = GetGameTimer()
  init_particles()
end


function T.clear() _target = nil end


function T.current() return _target end


-- ============================================================
-- RENDER — contador no topo + coluna + base de poeira
-- ============================================================

-- Contador de distancia (km/m) + label do CP, projetados no topo da coluna.
local function draw_top_label(target, height, dist_m)
  local top_z = target.z + height + 2.0
  local on_screen, sx, sy = GetScreenCoordFromWorldCoord(target.x, target.y, top_z)
  if not on_screen then return end

  -- Distancia (grande, dourado)
  SetTextFont(4)
  SetTextScale(0.0, 0.55)
  SetTextColour(255, 226, 155, 250)
  SetTextOutline()
  SetTextDropShadow()
  SetTextCentre(true)
  SetTextEntry('STRING')
  AddTextComponentString(dist_label_of(dist_m))
  DrawText(sx, sy - 0.04)

  -- Label do CP (menor, areia)
  SetTextFont(4)
  SetTextScale(0.0, 0.32)
  SetTextColour(232, 214, 170, 230)
  SetTextOutline()
  SetTextCentre(true)
  SetTextEntry('STRING')
  AddTextComponentString(tostring(target.label or 'CHECKPOINT'))
  DrawText(sx, sy)
end


-- Desenha o totem completo (chamado a cada frame quando ha alvo no alcance).
local function draw_totem(target, dist_m, t_ms)
  if not valid_target(target) then return end

  local cfg    = Cfg.TOTEM or {}
  local body   = color_for(target)
  local core   = core_color()
  local height = height_for(dist_m)
  local cx, cy, cz = target.x, target.y, target.z

  local phase  = (t_ms / 1000.0) * (cfg.PULSE_FREQ_HZ or 0.7) * math.pi * 2.0
  local glow_p = 0.90 + (math.sin(phase) * 0.10)

  local base_r = cfg.BASE_RADIUS   or 11.0
  local core_w = cfg.COLUMN_CORE_W or 0.45
  local glow_w = cfg.COLUMN_GLOW_W or 1.3


  -- 1) Rasteirinha de poeira de areia marcando o DIAMETRO do CP
  DrawMarker(1, cx, cy, cz - 0.96, 0,0,0, 0,0,0,
    base_r * 2.0, base_r * 2.0, 0.10,
    body.r, body.g, body.b, 80, false, false, 2, false, nil, nil, false)


  -- 2) Coluna fina e longa: halo de glow + nucleo solido (quase branco no topo)
  local col_z = cz + (height * 0.5)
  DrawMarker(1, cx, cy, col_z, 0,0,0, 0,0,0,
    glow_w, glow_w, height,
    body.r, body.g, body.b, math.floor(170 * glow_p),
    false, false, 2, false, nil, nil, false)
  DrawMarker(1, cx, cy, col_z, 0,0,0, 0,0,0,
    core_w, core_w, height,
    core.r, core.g, core.b, math.floor(255 * glow_p),
    false, false, 2, false, nil, nil, false)


  -- 3) Baforadas de poeira subindo da base (crescem e dissipam)
  local n = cfg.DUST_COUNT or 10
  for i = 1, n do
    local p = _particles[i]
    if p then
      p.offset_z = (p.offset_z + (4.0 * p.speed * 0.012)) % 4.0
      p.angle    = p.angle + (0.004 * p.speed)
      local px   = cx + (math.cos(p.angle) * p.radius)
      local py   = cy + (math.sin(p.angle) * p.radius)
      local pz   = cz - 0.6 + p.offset_z
      local fade = math.floor(70 * (1.0 - (p.offset_z / 4.0)))
      if fade > 0 then
        local s = p.size * (1.0 + (p.offset_z / 4.0) * 0.7)
        DrawMarker(28, px, py, pz, 0,0,0, 0,0,0,
          s, s, s, 210, 170, 120, fade,
          false, false, 2, false, nil, nil, false)
      end
    end
  end


  -- 4) Contador de distancia + label no topo
  draw_top_label(target, height, dist_m)
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
        draw_totem(target, dist, GetGameTimer() - _t0)
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
