-- shared/utils.lua — utilitários puros sem side-effects

VHubDF = VHubDF or {}
VHubDF.U = {}
local U = VHubDF.U


-- retorna true se o valor é uma string não-vazia
function U.isStr(v) return type(v) == 'string' and v ~= '' end

-- clampeia um número entre min e max
function U.clamp(n, lo, hi) return math.max(lo, math.min(hi, n)) end

-- retorna true se n é número finito e >= lo e <= hi
function U.inRange(n, lo, hi)
    return type(n) == 'number' and n == n and n >= lo and n <= hi
end

-- garante que amount é BRL válido (inteiro ou .00 / .50 / .99)
-- aceita até 2 casas decimais; retorna número ou nil se inválido
function U.parseBRL(v)
    local n = tonumber(v)
    if not n then return nil end
    n = math.floor(n * 100 + 0.5) / 100    -- arredonda p/ 2 casas
    if not U.inRange(n, VHubDF.cfg.minAmountBRL, VHubDF.cfg.maxAmountBRL) then
        return nil
    end
    return n
end

-- sanitiza product_key: só ASCII printável, sem espaços, até 64 chars
function U.sanitizeKey(v)
    if type(v) ~= 'string' then return nil end
    v = v:sub(1, 64)
    if v:match('[^%w%-_%.:]') then return nil end
    if #v == 0 then return nil end
    return v
end

-- sanitiza product_desc: até 120 chars, sem controles
function U.sanitizeDesc(v)
    if type(v) ~= 'string' then return '' end
    v = v:gsub('[%c]', ' '):sub(1, 120)
    return v
end

-- sanitiza metadata: deve ser table; json.encode dela não pode exceder maxMetadataBytes
function U.sanitizeMetadata(v)
    if type(v) ~= 'table' then return nil end
    local ok, encoded = pcall(json.encode, v)
    if not ok then return nil end
    if #encoded > VHubDF.cfg.maxMetadataBytes then return nil end
    return encoded
end

-- formata timestamp unix em 'DD/MM/YYYY HH:MM:SS' (PT-BR)
function U.fmtDate(ts)
    return os.date('%d/%m/%Y %H:%M:%S', ts)
end
