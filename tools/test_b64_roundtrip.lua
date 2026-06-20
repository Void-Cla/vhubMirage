-- tools/test_b64_roundtrip.lua — teste OFFLINE da blindagem b64 do state.lua
-- Valida o par _b64encode/_b64decode (cópia fiel de server/state.lua, decisão A2
-- 2026-06-11) fora do FXServer: vetores RFC 4648, binário completo 0x00–0xFF,
-- tamanhos aleatórios (resto 0/1/2) e benchmark do caso típico e do cap raw.
--
-- Uso:  lua tools/test_b64_roundtrip.lua      (requer Lua 5.4 — bitwise)
-- NOTA: ferramenta standalone de desenvolvimento — roda FORA do runtime vHub
--       (não há vHub.Logger aqui; saída via io.write). O teste RUNTIME
--       equivalente é tests.test_blob_armor_roundtrip no vhub_testrunner.
--
-- ATENÇÃO: se _b64encode/_b64decode mudarem em server/state.lua, atualizar a
-- cópia abaixo — este arquivo trava o algoritmo, não o import.

local B64_PREFIX = "b64:"
local _b64enc, _b64dec = {}, {}
do
  local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  for i = 1, 64 do
    _b64enc[i - 1] = chars:sub(i, i)
    _b64dec[chars:byte(i)] = i - 1
  end
end

-- codifica string binária em base64 (cópia de server/state.lua)
local function _b64encode(s)
  local out, oi = {}, 0
  local n   = #s
  local rem = n % 3
  for i = 1, n - rem, 3 do
    local a, b, c = s:byte(i, i + 2)
    local v = (a << 16) | (b << 8) | c
    oi = oi + 1
    out[oi] = _b64enc[(v >> 18) & 63] .. _b64enc[(v >> 12) & 63]
           .. _b64enc[(v >> 6) & 63]  .. _b64enc[v & 63]
  end
  if rem == 1 then
    local v = s:byte(n) << 16
    oi = oi + 1
    out[oi] = _b64enc[(v >> 18) & 63] .. _b64enc[(v >> 12) & 63] .. "=="
  elseif rem == 2 then
    local a, b = s:byte(n - 1, n)
    local v = (a << 16) | (b << 8)
    oi = oi + 1
    out[oi] = _b64enc[(v >> 18) & 63] .. _b64enc[(v >> 12) & 63]
           .. _b64enc[(v >> 6) & 63] .. "="
  end
  return table.concat(out)
end

-- decodifica base64 em string binária (cópia de server/state.lua)
local function _b64decode(s)
  local out, oi = {}, 0
  local buf, bits = 0, 0
  for i = 1, #s do
    local d = _b64dec[s:byte(i)]
    if d then
      buf  = (buf << 6) | d
      bits = bits + 6
      if bits >= 8 then
        bits = bits - 8
        oi = oi + 1
        out[oi] = string.char((buf >> bits) & 255)
      end
    end
  end
  return table.concat(out)
end


-- ============================================================
-- TESTES
-- ============================================================

-- vetores conhecidos (RFC 4648 §10)
assert(_b64encode("")       == "",         "vazio")
assert(_b64encode("f")      == "Zg==",     "f")
assert(_b64encode("fo")     == "Zm8=",     "fo")
assert(_b64encode("foo")    == "Zm9v",     "foo")
assert(_b64encode("foob")   == "Zm9vYg==", "foob")
assert(_b64encode("fooba")  == "Zm9vYmE=", "fooba")
assert(_b64encode("foobar") == "Zm9vYmFy", "foobar")
for _, t in ipairs({"", "f", "fo", "foo", "foob", "fooba", "foobar"}) do
  assert(_b64decode(_b64encode(t)) == t, "round-trip " .. t)
end

-- binário completo 0x00–0xFF (o mangle latin1→UTF-8 era fatal exatamente aqui)
local bytes = {}
for b = 0, 255 do bytes[#bytes + 1] = string.char(b) end
local bin = table.concat(bytes)
assert(_b64decode(_b64encode(bin)) == bin, "round-trip binário 0x00-0xFF")

-- blobs pseudo-aleatórios de tamanhos variados (cobre resto 0/1/2)
math.randomseed(42)
for n = 1, 200 do
  local t = {}
  for i = 1, n do t[i] = string.char(math.random(0, 255)) end
  local s = table.concat(t)
  assert(_b64decode(_b64encode(s)) == s, "round-trip aleatório n=" .. n)
end

-- simulação do caminho completo _pack/_unpack com prefixo
local packed = B64_PREFIX .. _b64encode(bin)
assert(packed:sub(1, 4) == B64_PREFIX,            "prefixo presente")
assert(packed:find("[^\32-\126]") == nil,         "saída 100%% ASCII imprimível")
assert(_b64decode(packed:sub(5)) == bin,          "unpack com prefixo")

-- colisão de prefixo dentro do VALOR (o valor vira bytes do msgpack — a
-- blindagem é incondicional no _pack, então não há ambiguidade no read)
local colide = "b64:texto_legitimo"
assert(_b64decode(_b64encode(colide)) == colide,  "valor colidindo com prefixo")


-- ============================================================
-- BENCHMARK (orçamento L-18: caso típico 50B–3KB; cap raw ~45KB)
-- ============================================================

local function bench(sz)
  local t = {}
  for i = 1, sz do t[i] = string.char(math.random(0, 255)) end
  local s = table.concat(t)
  local t0 = os.clock()
  local e = _b64encode(s)
  local t1 = os.clock()
  local d = _b64decode(e)
  local t2 = os.clock()
  assert(d == s, "round-trip benchmark " .. sz)
  io.write(("blob %6d B: encode %7.3f ms | decode %7.3f ms\n"):format(
    sz, (t1 - t0) * 1000, (t2 - t1) * 1000))
end
bench(3 * 1024)    -- caso típico (vd.state / datatable)
bench(45 * 1024)   -- pior caso (cap raw sob o guard de 60 KB pós-encode)

io.write("TODOS OS TESTES PASSARAM\n")
