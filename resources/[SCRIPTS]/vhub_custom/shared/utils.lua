-- shared/utils.lua — helpers puros do vhub_custom
---@diagnostic disable: undefined-global, lowercase-global

VHubCustom   = VHubCustom or {}
VHubCustom.U = {}

local U = VHubCustom.U


-- ============================================================
-- NORMALIZAÇÃO
-- ============================================================

-- normaliza placa (upper + colapso de espaços internos + trim de bordas)
-- compatível com conce U.normalizePlate (mesmo algoritmo — evita divergência de chave)
function U.normalizePlate(plate)
  if type(plate) ~= 'string' then return nil end
  local p = plate:upper():gsub('%s+', ' '):match('^%s*(.-)%s*$')
  if not p or #p < 2 or #p > 8 then return nil end
  return p
end

-- número finito no intervalo [lo, hi], ou nil
function U.clamp(v, lo, hi)
  if type(v) ~= 'number' or v ~= v or math.abs(v) == math.huge then return nil end
  return math.max(lo, math.min(hi, v))
end


-- ============================================================
-- VALIDAÇÃO DE PAYLOAD
-- ============================================================

-- retorna true se o payload é tabela não-vazia com tamanho plausível
function U.validPayload(p)
  return type(p) == 'table' and next(p) ~= nil
end

-- sanitiza tabela de mods {[idx]=level} → só indices integer 0..49, levels 0..5
-- filtra via whitelist opcional (set de índices)
function U.sanitizeMods(raw, whitelist)
  if type(raw) ~= 'table' then return nil end
  local out, n = {}, 0
  for k, v in pairs(raw) do
    local idx = tonumber(k)
    local lvl = tonumber(v)
    if idx and lvl and idx == math.floor(idx) and idx >= 0 and idx <= 49
       and lvl == math.floor(lvl) and lvl >= -1 and lvl <= 5 then
      if not whitelist or whitelist[idx] then
        out[idx] = lvl
        n = n + 1
        if n > 50 then return nil end  -- payload acima do plausível = hostil
      end
    end
  end
  return next(out) ~= nil and out or nil
end
