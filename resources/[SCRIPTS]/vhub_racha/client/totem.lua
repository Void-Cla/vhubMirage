-- client/totem.lua - totem 3D de checkpoint + projeção NUI cinematográfica.
-- DrawMarker no mundo (sempre ativo) + thread NUI que envia coords de tela.
-- Lei L-02: NUI recebe projeção calculada aqui; não decide posição 3D.

VHubRachaTotem = {}

local T   = VHubRachaTotem
local Cfg = VHubRachaCfg

local USE_NUI = Cfg and Cfg.HUD and Cfg.HUD.USE_NUI

local _target    = nil
local _t0        = GetGameTimer()
local _particles = {}

-- ── Helpers ────────────────────────────────────────────────────────────────

local function clamp(v, mn, mx)
  v = tonumber(v) or mn
  if v < mn then return mn end
  if v > mx then return mx end
  return v
end

local function smoothstep(t)
  t = clamp(t, 0.0, 1.0)
  return t * t * (3.0 - (2.0 * t))
end

local function render_range()
  return (Cfg.TOTEM and Cfg.TOTEM.RENDER_RANGE) or 999.0
end

local function shape_for(dist_m)
  local cfg = Cfg.TOTEM or {}
  local range = render_range()
  local t = smoothstep(clamp(dist_m / range, 0.0, 1.0))
  local min_h = cfg.MIN_HEIGHT or 5.0
  local max_h = cfg.MAX_HEIGHT or cfg.HEIGHT or 110.0
  local min_w = cfg.WIDTH_MIN or 0.45
  local max_w = cfg.WIDTH_MAX or 2.80
  return min_h + ((max_h - min_h) * t), min_w + ((max_w - min_w) * t)
end

local function lod_for(dist_m)
  local cfg = Cfg.TOTEM or {}
  if dist_m <= (cfg.LOD_NEAR or 120.0) then return 'near' end
  if dist_m <= (cfg.LOD_MID  or 420.0) then return 'mid'  end
  return 'far'
end

local function color_for(target)
  local cfg = Cfg.TOTEM or {}
  if type(target) ~= 'table' then return cfg.COLOR_DEFAULT or { r = 243, g = 181, b = 58 } end
  if target.is_finish            then return cfg.COLOR_FINISH    or { r = 100, g = 220, b = 120 } end
  if target.kind == 'speedtrap'  then return cfg.COLOR_SPEEDTRAP or { r = 38,  g = 220, b = 80  } end
  if target.kind == 'drift'      then return cfg.COLOR_DRIFT_ZONE or { r = 168, g = 50,  b = 240 } end
  return cfg.COLOR_DEFAULT or { r = 243, g = 181, b = 58 }
end

local function valid_target(target)
  if type(target) ~= 'table' then return false end
  return type(target.x) == 'number' and type(target.y) == 'number' and type(target.z) == 'number'
end

local function init_particles()
  local cfg = Cfg.TOTEM or {}
  local n     = cfg.PARTICLES  or 14
  local max_h = cfg.MAX_HEIGHT or cfg.HEIGHT or 110.0
  local max_r = cfg.WIDTH_MAX  or 2.80
  for i = 1, n do
    _particles[i] = {
      offset_z = math.random() * max_h,
      angle    = math.random() * math.pi * 2.0,
      speed    = 0.25 + (math.random() * 0.75),
      radius   = 0.65 + (math.random() * max_r),
      size     = (cfg.PARTICLE_SIZE or 0.20) * (0.70 + math.random() * 0.70),
    }
  end
  for i = n + 1, #_particles do _particles[i] = nil end
end

-- ── API pública ────────────────────────────────────────────────────────────

function T.set_target(target)
  if not valid_target(target) then
    _target = nil
    if USE_NUI then SendNUIMessage({ type = 'vhub_racha.totem.clear' }) end
    return
  end
  _target = target
  _t0     = GetGameTimer()
  init_particles()
  if USE_NUI then
    SendNUIMessage({ type = 'vhub_racha.totem.set', target = target })
  end
end

function T.clear()
  _target = nil
  if USE_NUI then
    SendNUIMessage({ type = 'vhub_racha.totem.project', payload = { visible = false } })
    SendNUIMessage({ type = 'vhub_racha.totem.clear' })
  end
end

function T.current() return _target end

-- ── DrawMarker world-space (sempre ativo independente de NUI) ──────────────

local function draw_distance_label(target, height, dist_m, lod)
  -- Rótulo de distância visível em TODOS os LODs (near, mid e far)
  local scale = (lod == 'near') and 0.52 or (lod == 'mid') and 0.44 or 0.36
  local label = (dist_m >= 1000.0)
      and ('%.1f KM'):format(dist_m / 1000.0)
      or  ('%d M'):format(math.floor(dist_m))
  local on_screen, sx, sy = GetScreenCoordFromWorldCoord(target.x, target.y, target.z + height + 1.2)
  if not on_screen then return end
  SetTextFont(4)
  SetTextScale(0.0, scale)
  SetTextColour(255, 232, 168, 245)
  SetTextOutline()
  SetTextCentre(true)
  SetTextEntry('STRING')
  AddTextComponentString(label)
  DrawText(sx, sy - 0.02)
end

local function draw_totem(target, dist_m, t_ms)
  if not valid_target(target) then return end
  local cfg    = Cfg.TOTEM or {}
  local color  = color_for(target)
  local lod    = lod_for(dist_m)
  local height, width = shape_for(dist_m)
  local cx, cy, cz = target.x, target.y, target.z

  local phase  = (t_ms / 1000.0) * (cfg.PULSE_FREQ_HZ or 0.6) * math.pi * 2.0
  local pulse  = math.sin(phase) * (cfg.PULSE_AMPLITUDE or 0.18)
  local range_t = clamp(dist_m / render_range(), 0.0, 1.0)
  local alpha  = math.floor(145 - (range_t * 70))
  local base_radius = 4.0 + (width * 2.2)

  -- Base: disco fino no solo
  DrawMarker(1,
    cx, cy, cz - 0.95,
    0,0,0, 0,0,0,
    base_radius, base_radius, 0.12,
    color.r, color.g, color.b, 48,
    false, false, 2, false, nil, nil, false)

  -- Esfera base
  DrawMarker(28,
    cx, cy, cz + 0.35 + pulse,
    0,0,0, 0,0,0,
    width * 1.8, width * 1.8, width * 1.8,
    color.r, color.g, color.b, 95,
    false, false, 2, false, nil, nil, false)

  -- Coluna segmentada (cresce com a distância)
  local segments = (lod == 'near') and 6 or (lod == 'mid') and 4 or 2
  for i = 1, segments do
    local frac   = (i - 0.5) / segments
    local seg_h  = height / segments
    local fade   = 1.0 - (frac * 0.58)
    local seg_alpha = math.floor(alpha * fade)
    local seg_w  = width * (1.0 - (frac * 0.18)) * (1.0 + (pulse * 0.08))
    DrawMarker(1,
      cx, cy, cz + (height * frac) + pulse,
      0,0,0, 0,0,0,
      seg_w, seg_w, seg_h,
      color.r, color.g, color.b, seg_alpha,
      false, false, 2, false, nil, nil, false)
  end

  -- Coroa do alvo (topo)
  DrawMarker(28,
    cx, cy, cz + height + pulse,
    0,0,0, 0,0,0,
    width * 1.45, width * 1.45, width * 1.45,
    color.r, color.g, color.b, math.min(190, alpha + 35),
    false, false, 2, false, nil, nil, false)

  -- Partículas (near/mid) + label de distância em TODOS os LODs
  if lod ~= 'far' then
    local n = (lod == 'near') and (cfg.PARTICLES or 14) or math.ceil((cfg.PARTICLES or 14) * 0.55)
    local drift_z = cfg.PARTICLE_DRIFT_Y or 0.5
    for i = 1, n do
      local p = _particles[i]
      if p then
        p.offset_z = (p.offset_z + (drift_z * p.speed * 0.016)) % math.max(height, 1.0)
        p.angle    = p.angle + (0.006 * p.speed)
        local radius = math.min(p.radius, width * 2.4)
        local px = cx + (math.cos(p.angle) * radius)
        local py = cy + (math.sin(p.angle) * radius)
        local pz = cz + p.offset_z + pulse
        DrawMarker(28,
          px, py, pz,
          0,0,0, 0,0,0,
          p.size, p.size, p.size,
          color.r, color.g, color.b, 165,
          false, false, 2, false, nil, nil, false)
      end
    end
  end

  -- Label de distância sempre visível (independente de LOD)
  draw_distance_label(target, height, dist_m, lod)
end

-- ── Thread de render DrawMarker ────────────────────────────────────────────

CreateThread(function()
  while true do
    local target = _target
    if not target then
      Wait(400)
    else
      local ped = PlayerPedId()
      local pos = GetEntityCoords(ped)
      local dx  = pos.x - target.x
      local dy  = pos.y - target.y
      local dz  = pos.z - target.z
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

-- ── Thread NUI: projeta coordenadas de tela → CSS overlay ─────────────────
-- FIX PRINCIPAL: roda independente do estado da corrida (warmup + racing).
-- Envia vhub_racha.totem.project a 20Hz quando há target.

if USE_NUI then
  CreateThread(function()
    while true do
      local target = _target
      if not target then
        -- Sem alvo: garante que o overlay suma
        Wait(150)
      else
        Wait(50)   -- 20Hz
        local ped  = PlayerPedId()
        local pos  = GetEntityCoords(ped)
        local dx   = pos.x - target.x
        local dy   = pos.y - target.y
        local dz   = pos.z - target.z
        local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
        local range = render_range()

        -- Projeta o TOPO da coluna (onde fica a coroa) para coordenadas de tela
        local height, _ = shape_for(dist)
        local proj_z = target.z + height + 1.8

        local on_screen, sx, sy = GetScreenCoordFromWorldCoord(target.x, target.y, proj_z)

        -- Rótulo de distância
        local dist_label
        if dist >= 1000.0 then
          dist_label = ('%.1f KM'):format(dist / 1000.0)
        else
          dist_label = ('%d M'):format(math.floor(dist))
        end

        SendNUIMessage({
          type    = 'vhub_racha.totem.project',
          payload = {
            visible    = (on_screen == true) and (dist <= range),
            x          = sx or 0.0,
            y          = sy or 0.0,
            dist       = dist,
            dist_label = dist_label,
            cp_label   = target.label or 'CP',
            is_finish  = target.is_finish == true,
            kind       = target.kind or 'sprint',
            height_px  = height,
          }
        })
      end
    end
  end)
end

-- ── Cleanup ────────────────────────────────────────────────────────────────

AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  _target = nil
end)
