-- utils.lua — helpers puros (sem efeitos colaterais, sem I/O)

VHubNpcAI       = VHubNpcAI or {}
VHubNpcAI.utils = {}
local U         = VHubNpcAI.utils


-- ============================================================
-- NORMALIZAÇÃO DE TEXTO (para matching de intenção)
-- ============================================================

-- mapa de substituição de acentos (UTF-8 multibyte → ASCII)
local _accent = {
    ['á']='a',['à']='a',['â']='a',['ã']='a',['ä']='a',
    ['é']='e',['è']='e',['ê']='e',['ë']='e',
    ['í']='i',['ì']='i',['î']='i',['ï']='i',
    ['ó']='o',['ò']='o',['ô']='o',['õ']='o',['ö']='o',
    ['ú']='u',['ù']='u',['û']='u',['ü']='u',
    ['ç']='c',['ñ']='n',
    ['Á']='a',['À']='a',['Â']='a',['Ã']='a',
    ['É']='e',['Ê']='e',['Í']='i',['Ó']='o',
    ['Ô']='o',['Õ']='o',['Ú']='u',['Ç']='c',
}

-- normaliza texto: minúsculo, sem acento, sem pontuação, sem espaço duplo
function U.normalize(text)
    if type(text) ~= 'string' then return '' end
    local s = text:lower()
    -- substitui caracteres acentuados (pattern multibyte)
    s = s:gsub('[%z\1-\127\194-\244][\128-\191]*', function(c)
        return _accent[c] or c
    end)
    s = s:gsub('[^%w%s]', ' ')
    s = s:gsub('%s+', ' ')
    s = s:match('^%s*(.-)%s*$')
    return s
end

-- tokeniza texto normalizado em lista de palavras
function U.tokenize(text)
    local tokens = {}
    for w in U.normalize(text):gmatch('%S+') do
        tokens[#tokens+1] = w
    end
    return tokens
end


-- ============================================================
-- SLUG SEGURO (nomes de arquivo, L-15 path traversal)
-- ============================================================

-- gera slug seguro: whitelist [a-z0-9_], sem / nem .., teto 48 chars
function U.safeSlug(str)
    if type(str) ~= 'string' then return 'unknown' end
    local s = U.normalize(str)
    s = s:gsub('[^a-z0-9]', '_')
    s = s:gsub('_+', '_')
    s = s:match('^_*(.-)_*$') or 'unknown'
    s = s:sub(1, 48)
    return (#s > 0) and s or 'unknown'
end


-- ============================================================
-- GEOMETRIA (primitivos, sem vec3 — L-19)
-- ============================================================

-- distância 3D entre dois pontos (primitivos, não vec3)
function U.dist3(x1, y1, z1, x2, y2, z2)
    local dx, dy, dz = x2-x1, y2-y1, z2-z1
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

-- normaliza ângulo para [-180, 180]
function U.normalizeAngle(deg)
    deg = deg % 360
    if deg > 180 then deg = deg - 360 end
    return deg
end

-- calcula ângulo horizontal (graus) de p1 para p2 (para panning L-R)
function U.bearingDeg(x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    return math.deg(math.atan(dx, dy)) % 360
end


-- ============================================================
-- VALIDAÇÃO DE SHAPE DE PAYLOAD (segurança L-01)
-- ============================================================

-- verifica que tabela tem chaves do shape esperado com tipos corretos
function U.checkShape(t, shape)
    if type(t) ~= 'table' then return false end
    for k, typ in pairs(shape) do
        if type(t[k]) ~= typ then return false end
    end
    return true
end
