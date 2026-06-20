-- shared/checkpoints.lua — normalizador multi-formato + helpers de CP.
--
-- Aceita 5 formatos (resolve "config chato"). Em qualquer caso, normaliza
-- para o shape canonico `{ x, y, z, h }`:
--
--   1. { x = X, y = Y, z = Z [, h = H] }       ← canonico (record nomeado)
--   2. vec3(X, Y, Z)                            ← FiveM nativo (sem heading)
--   3. { X, Y, Z [, H] }                        ← array (nation_race style)
--   4. "x = N, y = N, z = N"                    ← string do comando /cds
--   5. { cds = vec3(X, Y, Z), h = H }           ← novo: cds + heading separado
--
-- Formato (5) e o estilo preferido para slots de grid: a coordenada vai em
-- `cds` (campo nomeado, igual ao nation_race) e o `h` (heading) fica fora.

VHubRachaCP = {}
local CP = VHubRachaCP


-- ============================================================
-- PARSING DE STRING (formato 4)
-- ============================================================

local function _parse_string(s)
  if type(s) ~= 'string' then return nil end
  local x, y, z = s:match('x%s*=%s*([%-%d%.]+)%s*,?%s*y%s*=%s*([%-%d%.]+)%s*,?%s*z%s*=%s*([%-%d%.]+)')
  if x and y and z then return tonumber(x), tonumber(y), tonumber(z) end
  local px, py, pz = s:match('([%-%d%.]+)[,%s]+([%-%d%.]+)[,%s]+([%-%d%.]+)')
  if px and py and pz then return tonumber(px), tonumber(py), tonumber(pz) end
  return nil
end


-- ============================================================
-- NORMALIZE — qualquer formato → { x, y, z, h }
-- ============================================================

function CP.normalize(raw, default_h)
  if raw == nil then return nil end

  -- Formato 4 — string crua
  if type(raw) == 'string' then
    local x, y, z = _parse_string(raw)
    if not x then return nil end
    return { x = x, y = y, z = z, h = tonumber(default_h) or 0.0 }
  end

  -- Formato 2 — vec3 nativo do FiveM
  if type(raw) == 'vector3' then
    return { x = raw.x, y = raw.y, z = raw.z, h = tonumber(default_h) or 0.0 }
  end

  if type(raw) ~= 'table' then return nil end

  -- Formato 5 — { cds = vec3(...), h = N } (estilo nation_race / preferido)
  if raw.cds ~= nil then
    local c = raw.cds
    if type(c) == 'vector3' then
      return {
        x = c.x, y = c.y, z = c.z,
        h = tonumber(raw.h or raw.heading or default_h) or 0.0,
      }
    end
    if type(c) == 'table' and c.x and c.y and c.z then
      return {
        x = tonumber(c.x) or 0.0,
        y = tonumber(c.y) or 0.0,
        z = tonumber(c.z) or 0.0,
        h = tonumber(raw.h or raw.heading or default_h) or 0.0,
      }
    end
  end

  -- Formato 1 — record { x, y, z, h }
  if raw.x ~= nil and raw.y ~= nil and raw.z ~= nil then
    return {
      x = tonumber(raw.x) or 0.0,
      y = tonumber(raw.y) or 0.0,
      z = tonumber(raw.z) or 0.0,
      h = tonumber(raw.h or raw.heading or default_h) or 0.0,
    }
  end

  -- Formato 3 — array { X, Y, Z [, H] }
  if raw[1] ~= nil and raw[2] ~= nil and raw[3] ~= nil then
    return {
      x = tonumber(raw[1]) or 0.0,
      y = tonumber(raw[2]) or 0.0,
      z = tonumber(raw[3]) or 0.0,
      h = tonumber(raw[4] or default_h) or 0.0,
    }
  end

  return nil
end

function CP.normalize_list(list, default_h)
  if type(list) ~= 'table' then return {} end
  local out = {}
  for i, raw in ipairs(list) do
    local n = CP.normalize(raw, default_h)
    if n then n.idx = i; out[#out + 1] = n end
  end
  return out
end

function CP.inside(px, py, pz, cp, radius)
  local r = tonumber(radius) or tonumber(cp.radius) or 11.0
  local dx, dy = px - cp.x, py - cp.y
  local dz = pz - cp.z
  if math.abs(dz) > 25.0 then return false end   -- margem Z ampliada (rampas/pontes)
  return (dx * dx + dy * dy) <= (r * r)
end

-- Comprimento total da rota em metros (para metadata do editor)
function CP.route_length(checkpoints)
  if type(checkpoints) ~= 'table' or #checkpoints < 2 then return 0 end
  local total = 0
  for i = 1, #checkpoints - 1 do
    local a, b = checkpoints[i], checkpoints[i + 1]
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    total = total + math.sqrt(dx * dx + dy * dy + dz * dz)
  end
  return math.floor(total)
end
