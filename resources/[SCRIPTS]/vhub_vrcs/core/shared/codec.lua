---@diagnostic disable: undefined-global, lowercase-global

-- core/shared/codec.lua — (de)serializacao do .vhr. Puro, sem I/O.
--
-- .vhr v1 = JSON. NUNCA load/loadstring na leitura (sem code-exec; o arquivo e
-- tratado como dado nao-confiavel — vrcs.md secao 9.5).

VRCS = VRCS or {}

local C = {}; VRCS.Codec = C


-- ============================================================
-- CODEC
-- ============================================================

-- serializa um replay para string (.vhr)
function C.encode(replay)
    return json.encode(replay)
end

-- desserializa uma string .vhr para tabela. Falha = nil + erro (nunca crasha).
function C.decode(str)
    if type(str) ~= 'string' or str == '' then return nil, 'empty' end
    local ok, data = pcall(json.decode, str)
    if not ok or type(data) ~= 'table' then return nil, 'parse_failed' end
    return data
end
