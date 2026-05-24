-- client/totem.lua — TOTEM cinematografico de checkpoint.
-- Substitui blip/marker/seta vanilla GTA por uma coluna holografica gigante
-- com particulas de areia dourada. LOD dinamico por distancia.
--
-- API publica:
--   VHubRachaTotem.set_target(target)   target = { x, y, z, kind, is_finish, label, distance_km }
--   VHubRachaTotem.clear()              limpa overlay
--
-- Render: thread frame loop CONDICIONAL (so quando ha target ativo + perto).

VHubRachaTotem = {}
local T = VHubRachaTotem
local Cfg = VHubRachaCfg
local MA  = VHubRachaMath

local _target = nil   -- alvo atual (CP a atingir)
local _t0     = GetGameTimer()

function T.set_target(target)
  _target = target
  _t0 = GetGameTimer()
end

function T.clear() _target = nil end
function T.current() return _target end

-- Cor do totem conforme tipo de CP
local function color_for(target)
  local cfg = Cfg.TOTEM or {}
  if target.is_finish then return cfg.COLOR_FINISH or { r = 100, g = 220, b = 120 } end
  if target.kind == 'speedtrap' then return cfg.COLOR_SPEEDTRAP or { r = 38, g = 220, b = 80 } end
  if target.kind == 'drift'     then return cfg.COLOR_DRIFT_ZONE or { r = 168, g = 50, b = 240 } end
  return cfg.COLOR_DEFAULT or { r = 243, g = 181, b = 58 }
end

-- LOD: distancia define densidade de particulas/altura
local function lod_for(dist_m)
  local cfg = Cfg.TOTEM or {}
  if dist_m <= (cfg.LOD_NEAR or 80) then return 'near' end
  if dist_m <= (cfg.LOD_MID  or 180) then return 'mid' end
  return 'far'
end

-- Particles: array circular pre-alocado para performance
local _particles = {}
local function init_particles()
  local cfg = Cfg.TOTEM or {}
  for i = 1, (cfg.PARTICLES or 14) do
    _particles[i] = {
      offset_y = math.random() * (cfg.HEIGHT or 50),
      angle    = math.random() * math.pi * 2,
      speed    = 0.3 + math.random() * 0.6,
      radius   = 0.4 + math.random() * 0.6,
      size     = (cfg.PARTICLE_SIZE or 0.20) * (0.7 + math.random() * 0.6),
    }
  end
end
init_particles()

-- Render principal: chamado em loop CONDICIONAL (so quando target perto)
local function render_totem(target, dist_m, t_ms)
  if not target then return end
  local cfg = Cfg.TOTEM or {}
  local color = color_for(target)
  local lod = lod_for(dist_m)
  local cx, cy, cz = target.x, target.y, target.z

  -- Pulse vertical (oscilacao leve)
  local pulse_phase = (t_ms / 1000) * (cfg.PULSE_FREQ_HZ or 0.6) * math.pi * 2
  local pulse = math.sin(pulse_phase) * (cfg.PULSE_AMPLITUDE or 0.18)

  -- 1) BASE CIRCULAR no chao (sempre visivel, marca o ponto)
  DrawMarker(1,
    cx, cy, cz - 1.0,
    0, 0, 0, 0, 0, 0,
    14.0, 14.0, 0.6,
    color.r, color.g, color.b, 110,
    false, false, 2, false, nil, nil, false)

  -- 2) CILINDRO/COLUNA hologr fica vertical (DrawMarker 28 = sphere cilindrica;
  --    1 = box. Vamos usar markers empilhados para criar a "coluna").
  --    Em LOD 'far' mostramos so 1 marker grande; LOD 'mid' = 3; LOD 'near' = particulas completas.
  local height  = cfg.HEIGHT or 50.0
  local width   = (cfg.WIDTH or 1.4) * (1.0 + pulse * 0.1)

  -- Cor com alpha que decai com a altura (efeito "fade pro topo")
  local segments
  if lod == 'far' then segments = 1
  elseif lod == 'mid' then segments = 3
  else segments = 6 end

  for i = 1, segments do
    local frac = (i - 1) / segments
    local seg_h = height / segments
    local zc = cz + (height * frac) + (seg_h * 0.5) + pulse
    local alpha = math.floor(180 * (1.0 - frac * 0.8))   -- fade do chao pro topo
    DrawMarker(28,   -- sphere (transparente, com glow)
      cx, cy, zc,
      0, 0, 0, 0, 0, 0,
      width, width, seg_h,
      color.r, color.g, color.b, alpha,
      false, false, 2, false, nil, nil, false)
  end

  -- 3) PARTICULAS (so em LOD near/mid)
  if lod ~= 'far' then
    local n_part = (lod == 'near') and (cfg.PARTICLES or 14) or math.ceil((cfg.PARTICLES or 14) / 2)
    local drift_y = cfg.PARTICLE_DRIFT_Y or 0.5
    for i = 1, n_part do
      local p = _particles[i]
      if p then
        -- Particula sobe lentamente, faz loop quando passa do topo
        p.offset_y = (p.offset_y + drift_y * (1/60)) % height
        local px = cx + math.cos(p.angle) * p.radius
        local py = cy + math.sin(p.angle) * p.radius
        local pz = cz + p.offset_y + pulse
        DrawMarker(28,
          px, py, pz,
          0, 0, 0, 0, 0, 0,
          p.size, p.size, p.size,
          color.r, color.g, color.b, 180,
          false, false, 2, false, nil, nil, false)
      end
    end
  end

  -- 4) TEXTO 3D no topo (CP X / distancia) — so em LOD near/mid
  if lod ~= 'far' then
    -- Mostra apenas a distancia no topo do totem (sem 'CP' grande)
    local hgt = cfg.HEIGHT or 50.0
    local dist_label = (dist_m >= 1000) and ('%.2f KM'):format(dist_m / 1000)
                       or (('%d M'):format(math.floor(dist_m)))
    local on_screen, sx, sy = GetScreenCoordFromWorldCoord(cx, cy, cz + hgt + 1.0)
    if on_screen then
      SetTextFont(4); SetTextScale(0.0, 0.55)
      SetTextColour(217, 193, 154, 240); SetTextOutline()
      SetTextEntry('STRING'); AddTextComponentString(dist_label)
      SetTextCentre(true); DrawText(sx, sy - 0.02)
    end
  end
end

-- ── Loop de render condicional ─────────────────────────────────────────────

CreateThread(function()
  while true do
    if not _target then
      Wait(400)
    else
      local ped = PlayerPedId()
      local px, py, pz = table.unpack(GetEntityCoords(ped))
      local dx = px - _target.x
      local dy = py - _target.y
      local dz = pz - _target.z
      local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
      local render_range = (Cfg.TOTEM and Cfg.TOTEM.RENDER_RANGE) or 350.0

      if dist > render_range then
        Wait(500)
      else
        Wait(0)
        render_totem(_target, dist, GetGameTimer() - _t0)
      end
    end
  end
end)

AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  _target = nil
end)
