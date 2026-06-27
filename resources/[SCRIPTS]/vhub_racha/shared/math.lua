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


-- ============================================================
-- ELO / PDL — funcoes PURAS (sem estado, sem natives, sem SQL)
-- O dominio de escrita (snapshot + persistencia) vive em server/ranked.lua.
-- ============================================================

-- Probabilidade esperada de A vencer B dado o fator de escala C (curva logistica).
--   E_A = 1 / (1 + 10^((R_B - R_A) / C))
-- C grande achata a curva para a escala de milhares (CS2-like).
function M.expected_score(rating_a, rating_b, c)
  local C = (tonumber(c) or 400)
  if C <= 0 then C = 400 end
  return 1.0 / (1.0 + 10.0 ^ ((rating_b - rating_a) / C))
end

-- Resolve a divisao (Bronze..Lendario) + tier (I..III) de um PDL.
-- `divisions` = lista CRESCENTE por `min` ({ key, label, min }). Retorna:
--   { key, label, tier (1..3), index, floor, next_min }
-- tier 1 = base da faixa, 3 = topo (proximo da promocao). next_min = nil no teto.
function M.division_of(pdl, divisions)
  if type(divisions) ~= 'table' or #divisions == 0 then
    return { key = 'none', label = '—', tier = 1, index = 0, floor = 0 }
  end

  local p   = tonumber(pdl) or 0
  local idx = 1
  for i = 1, #divisions do
    if p >= (tonumber(divisions[i].min) or 0) then idx = i else break end
  end

  local cur      = divisions[idx]
  local floor    = tonumber(cur.min) or 0
  local nxt      = divisions[idx + 1]
  local next_min = nxt and (tonumber(nxt.min) or 0) or nil

  -- tier 1..3 pela posicao dentro da faixa (band = floor..next_min)
  local tier = 3
  if next_min and next_min > floor then
    local frac = (p - floor) / (next_min - floor)
    tier = M.clamp(math.floor(frac * 3) + 1, 1, 3)
  end

  return {
    key = cur.key, label = cur.label, tier = tier,
    index = idx, floor = floor, next_min = next_min,
  }
end
