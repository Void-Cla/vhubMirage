local bitlib = bit or bit32
if not bitlib then
    -- Fallback para ambientes sem bit/bit32 (Lua 5.3+ com operadores bitwise)
    local mask = 0xFFFFFFFF
    local function toU32(x) return x & mask end
    bitlib = {}
    function bitlib.band(a, b, ...)
        local res = toU32(a) & toU32(b)
        if select('#', ...) > 0 then
            return bitlib.band(res, ...)
        end
        return res
    end
    function bitlib.bor(a, b, ...)
        local res = toU32(a) | toU32(b)
        if select('#', ...) > 0 then
            return bitlib.bor(res, ...)
        end
        return res
    end
    function bitlib.bxor(a, b, ...)
        local res = toU32(a) ~ toU32(b)
        if select('#', ...) > 0 then
            return bitlib.bxor(res, ...)
        end
        return res
    end
    function bitlib.bnot(a)
        return toU32(~toU32(a))
    end
    function bitlib.rshift(a, n)
        return toU32(toU32(a) >> n)
    end
    function bitlib.lshift(a, n)
        return toU32(toU32(a) << n)
    end
    function bitlib.ror(a, n)
        n = n % 32
        return toU32((toU32(a) >> n) | (toU32(a) << (32 - n)))
    end
end

local band = bitlib.band
local bor = bitlib.bor
local bxor = bitlib.bxor
local bnot = bitlib.bnot
local rshift = bitlib.rshift
local lshift = bitlib.lshift
local rrotate = bitlib.ror or function(x, n)
    return bor(rshift(x, n), lshift(x, 32 - n))
end

local Utils = {}

local function tohex(num)
    return string.format('%08x', num)
end

-- SHA256 simples em Lua (baseado em algoritmo padrao)
function Utils.sha256(msg)
    msg = msg or ''
    local K = {
        0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
        0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
        0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
        0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
        0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
        0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
        0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
        0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
    }

    local bytes = { string.byte(msg, 1, #msg) }
    local bitlen = #bytes * 8

    -- append '1' bit
    bytes[#bytes + 1] = 0x80

    -- pad with zeros
    while ((#bytes + 8) % 64) ~= 0 do
        bytes[#bytes + 1] = 0x00
    end

    -- append length (64-bit big-endian)
    for i = 7, 0, -1 do
        bytes[#bytes + 1] = band(rshift(bitlen, i * 8), 0xff)
    end

    local h0 = 0x6a09e667
    local h1 = 0xbb67ae85
    local h2 = 0x3c6ef372
    local h3 = 0xa54ff53a
    local h4 = 0x510e527f
    local h5 = 0x9b05688c
    local h6 = 0x1f83d9ab
    local h7 = 0x5be0cd19

    local w = {}
    for i = 1, #bytes, 64 do
        for j = 0, 15 do
            local idx = i + (j * 4)
            w[j] = bor(lshift(bytes[idx], 24), lshift(bytes[idx + 1], 16), lshift(bytes[idx + 2], 8), bytes[idx + 3])
        end
        for j = 16, 63 do
            local s0 = bxor(rrotate(w[j - 15], 7), rrotate(w[j - 15], 18), rshift(w[j - 15], 3))
            local s1 = bxor(rrotate(w[j - 2], 17), rrotate(w[j - 2], 19), rshift(w[j - 2], 10))
            w[j] = (w[j - 16] + s0 + w[j - 7] + s1) % 0x100000000
        end

        local a, b, c, d, e, f, g, h = h0, h1, h2, h3, h4, h5, h6, h7

        for j = 0, 63 do
            local S1 = bxor(rrotate(e, 6), rrotate(e, 11), rrotate(e, 25))
            local ch = bxor(band(e, f), band(bnot(e), g))
            local temp1 = (h + S1 + ch + K[j + 1] + w[j]) % 0x100000000
            local S0 = bxor(rrotate(a, 2), rrotate(a, 13), rrotate(a, 22))
            local maj = bxor(band(a, b), band(a, c), band(b, c))
            local temp2 = (S0 + maj) % 0x100000000

            h = g
            g = f
            f = e
            e = (d + temp1) % 0x100000000
            d = c
            c = b
            b = a
            a = (temp1 + temp2) % 0x100000000
        end

        h0 = (h0 + a) % 0x100000000
        h1 = (h1 + b) % 0x100000000
        h2 = (h2 + c) % 0x100000000
        h3 = (h3 + d) % 0x100000000
        h4 = (h4 + e) % 0x100000000
        h5 = (h5 + f) % 0x100000000
        h6 = (h6 + g) % 0x100000000
        h7 = (h7 + h) % 0x100000000
    end

    return tohex(h0) .. tohex(h1) .. tohex(h2) .. tohex(h3) .. tohex(h4) .. tohex(h5) .. tohex(h6) .. tohex(h7)
end

function Utils.gerarUUID()
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return string.gsub(template, '[xy]', function(c)
        local v = (c == 'x') and math.random(0, 15) or math.random(8, 11)
        return string.format('%x', v)
    end)
end

function Utils.randomHex(len)
    local out = {}
    for i = 1, len do
        out[#out + 1] = string.format('%x', math.random(0, 15))
    end
    return table.concat(out)
end

function Utils.gerarSerialKey(userId, nomeItem)
    local timestamp = os.time()
    local random = Utils.randomHex(6)
    local base = string.format('VOID_%s_%d_%d_%s', string.upper(nomeItem), userId, timestamp, random)
    local checksum = string.sub(Utils.sha256(base), 1, 6)
    return base .. '_' .. checksum
end

function Utils.validarSerialKey(serialkey)
    if not serialkey or #serialkey < 20 then return false end
    local partes = {}
    for parte in string.gmatch(serialkey, '([^_]+)') do
        partes[#partes + 1] = parte
    end
    if #partes < 5 then return false end
    local base = table.concat(partes, '_', 1, #partes - 1)
    local checksum_esperado = partes[#partes]
    local checksum_calculado = string.sub(Utils.sha256(base), 1, 6)
    return checksum_esperado == checksum_calculado
end

function Utils.calcularChecksum(userId, nomeItem, serialkey)
    local base = string.format('%s|%s|%s', tostring(userId), tostring(nomeItem), tostring(serialkey))
    return string.sub(Utils.sha256(base), 1, 6)
end

function Utils.safeNumber(value, fallback)
    local n = tonumber(value)
    if n == nil then return fallback or 0 end
    return n
end

function Utils.safeString(value, fallback)
    if value == nil then return fallback or '' end
    return tostring(value)
end

function Utils.clamp(value, min, max)
    if value < min then return min end
    if value > max then return max end
    return value
end

function Utils.jsonDecode(value)
    if not value or value == '' then return nil end
    local ok, result = pcall(json.decode, value)
    if ok then return result end
    return nil
end

function Utils.jsonEncode(value)
    local ok, result = pcall(json.encode, value)
    if ok then return result end
    return '[]'
end

function Utils.tableSize(t)
    local count = 0
    for _ in pairs(t or {}) do
        count = count + 1
    end
    return count
end

return Utils
