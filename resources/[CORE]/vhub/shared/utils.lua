-- shared/utils.lua — Utilitários puros (sem side-effects, sem dependências)
-- Depende de: shared/config.lua (garante que vHub existe)

vHub = vHub or {}

local M = {}

-- Formata número com separador de milhar (1234567 → "1.234.567")
function M.formatNumber(n)
  return tostring(math.floor(n)):reverse()
    :gsub("(%d%d%d)", "%1."):reverse():gsub("^%.", "")
end

-- Formata segundos em string legível (3661 → "1h 01m 01s")
function M.formatTime(s)
  s = math.floor(s)
  local d = math.floor(s/86400); s = s - d*86400
  local h = math.floor(s/3600);  s = s - h*3600
  local m = math.floor(s/60);    s = s - m*60
  if d > 0 then return ("%dd %02dh %02dm"):format(d,h,m)
  elseif h > 0 then return ("%dh %02dm %02ds"):format(h,m,s)
  elseif m > 0 then return ("%dm %02ds"):format(m,s)
  else return ("%ds"):format(s) end
end

-- Limita v ao intervalo [a, b]
function M.clamp(v, a, b) return math.max(a, math.min(b, v)) end

-- Contagem de chaves de uma tabela
function M.tableSize(t)
  local n = 0
  for _ in pairs(t or {}) do n = n + 1 end
  return n
end

-- Normaliza placa: uppercase, trim, valida charset GTA
-- Retorna string normalizada ou nil se inválida
function M.normalizePlate(p)
  if type(p) ~= "string" then return nil end
  local plate = p:upper():match("^%s*(.-)%s*$")
  if not plate or plate == "" or #plate > 10 then return nil end
  if not plate:match("^[A-Z0-9][A-Z0-9 ]*$") then return nil end
  return plate
end

-- Cópia rasa de tabela
function M.shallowCopy(t)
  local c = {}
  for k, v in pairs(t or {}) do c[k] = v end
  return c
end

-- Cópia profunda de tabela (1 nível de profundidade — suficiente para user.data)
function M.dataCopy(t)
  if type(t) ~= "table" then return t end
  local c = {}
  for k, v in pairs(t) do
    if type(v) == "table" then
      local sub = {}
      for sk, sv in pairs(v) do sub[sk] = sv end
      c[k] = sub
    else
      c[k] = v
    end
  end
  return c
end

vHub.Utils = M
