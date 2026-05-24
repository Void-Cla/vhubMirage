-- shared/math.lua — helpers de vetor/distancia/angulo. Sem natives.

VHubRachaMath = {}
local M = VHubRachaMath

function M.dist2_xyz(ax, ay, az, bx, by, bz)
  local dx, dy, dz = ax - bx, ay - by, az - bz
  return dx * dx + dy * dy + dz * dz
end

function M.dist2(a, b)
  local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
  return dx * dx + dy * dy + dz * dz
end

function M.dist(a, b) return math.sqrt(M.dist2(a, b)) end

function M.dist2_xy(ax, ay, bx, by)
  local dx, dy = ax - bx, ay - by
  return dx * dx + dy * dy
end

function M.dist_xy(ax, ay, bx, by)
  return math.sqrt(M.dist2_xy(ax, ay, bx, by))
end

function M.clamp(n, min, max)
  if n < min then return min end
  if n > max then return max end
  return n
end

function M.lerp(a, b, t) return a + (b - a) * t end

function M.ms_to_kmh(ms) return (tonumber(ms) or 0) * 3.6 end

-- Polygon: point-in-polygon (ray casting). poly = { {x, y}, {x, y}, ... }
function M.point_in_poly(px, py, poly)
  if type(poly) ~= 'table' or #poly < 3 then return false end
  local inside = false
  local j = #poly
  for i = 1, #poly do
    local xi, yi = poly[i][1], poly[i][2]
    local xj, yj = poly[j][1], poly[j][2]
    if ((yi > py) ~= (yj > py))
       and (px < (xj - xi) * (py - yi) / (yj - yi + 1e-9) + xi) then
      inside = not inside
    end
    j = i
  end
  return inside
end

-- Circulo (mais barato pra ready-zone simples)
function M.point_in_circle(px, py, cx, cy, radius)
  local dx, dy = px - cx, py - cy
  return (dx * dx + dy * dy) <= (radius * radius)
end

-- Forward vector do heading (GTA: heading 0 = norte = +y)
function M.heading_to_forward(heading_deg)
  local rad = math.rad(tonumber(heading_deg) or 0)
  return -math.sin(rad), math.cos(rad)
end

-- Distancia 2D entre dois CPs (para HUD "Proximo CP: 1.24 KM")
function M.cp_distance_m(from_x, from_y, cp)
  return M.dist_xy(from_x, from_y, cp.x, cp.y)
end
