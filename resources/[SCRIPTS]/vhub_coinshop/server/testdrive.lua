-- server/testdrive.lua — bucket de test-drive DELEGADO ao dono (decisão #35:
-- vhub_player_state = escritor ÚNICO de routing bucket; export setActivityBucket
-- gated range {1=mundo, 2=atividade}). Trade-off aceito: bucket 2 é COMPARTILHADO
-- entre test-drivers (o range do dono não expõe bucket por-src). Se o export negar
-- (trust/auth), degrada gracioso: test-drive segue no mundo, sem isolamento.

VHubCoin = VHubCoin or {}
local TestDrive = {}
VHubCoin.TestDrive = TestDrive


-- jogadores em test-drive: [src] = { x, y, z } (coord de ORIGEM salva SERVER-SIDE).
-- A coord de retorno NÃO vem do client (evita teleport arbitrário + 2ª fonte L-04) —
-- o server captura a posição real via getPosition do owner no setBucket.
TestDrive._origin = {}

-- delega a mudança de bucket ao dono (pcall na fronteira externa — R7)
local function setBucketVia(src, n)
    local ok, res = pcall(function()
        return exports.vhub_player_state:setActivityBucket(src, n)
    end)
    return ok and res == true
end


-- teleporta o ped via owner (L-16 — vhub_player_state é o escritor único do spawn)
local function teleportVia(src, x, y, z, h)
    pcall(function()
        exports.vhub_player_state:teleport(src, x, y, z, h or 0.0)
    end)
end


-- captura a posição de origem do ped pelo owner (server-authoritative; nil se indisponível)
local function captureOrigin(src)
    local ok, x, y, z = pcall(function()
        return exports.vhub_player_state:getPosition(src)
    end)
    if ok and tonumber(x) and not (x == 0 and y == 0 and z == 0) then
        return { x = x, y = y, z = z }
    end
    return nil
end


-- salva origem SERVER-SIDE + move p/ dimensão de atividade (2) + teleporta ao local de test-drive
function TestDrive.setBucket(src)
    if not src then return end
    if TestDrive._origin[src] then return end -- idempotente

    -- origem capturada ANTES do teleport de ida (fonte confiável p/ o retorno)
    TestDrive._origin[src] = captureOrigin(src) or false

    if not setBucketVia(src, 2) then
        VHubCoin.Core.log('setActivityBucket negado p/ src=' .. tostring(src) .. ' — test-drive sem isolamento')
    end
    -- teleport de IDA pelo owner (loc é vec4 LOCAL da config; achatado nos args do export)
    local loc = VHubCoin.cfg.testDriveLocation
    teleportVia(src, loc.x, loc.y, loc.z, loc.w)
end


-- retorna src ao mundo (bucket 1) + teleporta de volta à ORIGEM salva server-side
-- (o payload do client é IGNORADO — coord de retorno é verdade do server, anti-exploit)
function TestDrive.resetBucket(src)
    if not src then return end
    local origin = TestDrive._origin[src]
    if origin == nil then return end   -- não estava em test-drive
    TestDrive._origin[src] = nil

    setBucketVia(src, 1)
    if origin then   -- origin=false quando a captura falhou (não teleporta às cegas)
        teleportVia(src, origin.x, origin.y, origin.z, 0.0)
    end
end


-- chamado em playerDropped — garante que o jogador não fique preso no bucket
function TestDrive.onPlayerDropped(src)
    if TestDrive._origin[src] ~= nil then
        setBucketVia(src, 1)
        TestDrive._origin[src] = nil
    end
end


-- chamado em onResourceStop — libera TODOS os buckets (não vaza estado)
function TestDrive.resetAll()
    for src in pairs(TestDrive._origin) do
        setBucketVia(src, 1)
    end
    TestDrive._origin = {}
end


-- ============================================================
-- EVENTOS CLIENT→SERVER (intenção; servidor decide)
-- ============================================================

RegisterNetEvent(VHubCoin.S.SET_BUCKET, function()
    local src = source
    TestDrive.setBucket(src)
end)

-- payload IGNORADO de propósito: a coord de retorno é verdade server-side (_origin)
RegisterNetEvent(VHubCoin.S.RESET_BUCKET, function()
    local src = source
    TestDrive.resetBucket(src)
end)
