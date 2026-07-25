-- server/buckets.lua — ownership único de routing buckets do jogador

VHubHSS_Buckets = {}
local Buckets = VHubHSS_Buckets

local Cfg = nil
local ResolveCharacter = nil

local _activity_by_src = {}
local _activity_by_bucket = {}
local _next_bucket = 0


-- ============================================================
-- HELPERS
-- ============================================================

local function set_player_bucket(src, bucket)
    if not GetPlayerName(src) or type(bucket) ~= 'number' or bucket % 1 ~= 0
        or bucket < 0 or bucket > 65535 then return false end
    if GetPlayerRoutingBucket(src) ~= bucket then SetPlayerRoutingBucket(src, bucket) end
    Player(src).state:set('vhub_routing_bucket', bucket, true)
    return true
end

local function allocate_bucket()
    local first = Cfg.PED.activity_bucket_first
    local last = Cfg.PED.activity_bucket_last
    local span = last - first + 1
    if _next_bucket < first or _next_bucket > last then _next_bucket = first end

    for _ = 1, span do
        local bucket = _next_bucket
        _next_bucket = bucket >= last and first or bucket + 1
        if not _activity_by_bucket[bucket] then
            SetRoutingBucketPopulationEnabled(bucket, false)
            SetRoutingBucketEntityLockdownMode(bucket, 'strict')
            return bucket
        end
    end
    return nil
end

local function restore_vehicle(activity)
    local entity = activity and activity.vehicle
    if entity
        and DoesEntityExist(entity)
        and GetEntityType(entity) == 2
        and NetworkGetEntityOwner(entity) == activity.src then
        SetEntityRoutingBucket(entity, Cfg.PED.world_bucket)
        return true
    end
    return entity == nil
end


-- ============================================================
-- API
-- ============================================================

-- Inicializa buckets fixos e injetores sem depender de SQL/inventário.
function Buckets.init(cfg, resolve_character, _logger)
    Cfg = cfg
    ResolveCharacter = resolve_character
    _next_bucket = Cfg.PED.activity_bucket_first
    SetRoutingBucketPopulationEnabled(Cfg.PED.entry_bucket, false)
    SetRoutingBucketEntityLockdownMode(Cfg.PED.entry_bucket, 'strict')
end

-- Move jogador online para o bucket de entrada.
function Buckets.enter(src)
    return set_player_bucket(tonumber(src), Cfg.PED.entry_bucket)
end

-- Move jogador online para o mundo canônico.
function Buckets.world(src)
    return set_player_bucket(tonumber(src), Cfg.PED.world_bucket)
end

-- Aloca bucket exclusivo para uma atividade server-side.
function Buckets.begin_activity(src)
    src = tonumber(src)
    if not src or not ResolveCharacter(src) then return nil end
    if GetPlayerRoutingBucket(src) ~= Cfg.PED.world_bucket or _activity_by_src[src] then return nil end
    local bucket = allocate_bucket()
    if not bucket then return nil end
    local activity = { bucket = bucket, vehicle = nil, src = src }
    _activity_by_src[src] = activity
    _activity_by_bucket[bucket] = src
    set_player_bucket(src, bucket)
    return bucket
end

-- Anexa veículo pertencente ao jogador ao bucket exclusivo atual.
function Buckets.attach_vehicle(src, entity)
    src, entity = tonumber(src), tonumber(entity)
    local activity = src and _activity_by_src[src] or nil
    if not activity or not entity or entity <= 0 then return false end
    if not ResolveCharacter(src) or GetPlayerRoutingBucket(src) ~= activity.bucket then return false end
    if not DoesEntityExist(entity) or GetEntityType(entity) ~= 2 then return false end
    if NetworkGetEntityOwner(entity) ~= src then return false end
    if activity.vehicle and activity.vehicle ~= entity then restore_vehicle(activity) end
    activity.vehicle = entity
    SetEntityRoutingBucket(entity, activity.bucket)
    return true
end

-- Encerra atividade idempotentemente e restaura entidade/jogador ao mundo.
function Buckets.end_activity(src, restore_world)
    src = tonumber(src)
    local activity = src and _activity_by_src[src] or nil
    if not activity then return false end
    restore_vehicle(activity)
    _activity_by_src[src] = nil
    _activity_by_bucket[activity.bucket] = nil
    if restore_world ~= false then Buckets.world(src) end
    return true
end

-- Limpa bucket da sessão desconectada sem escrever em player inexistente.
function Buckets.drop(src)
    return Buckets.end_activity(src, false)
end

-- Restaura todas as atividades antes de parar o resource.
function Buckets.shutdown()
    local sources = {}
    for src in pairs(_activity_by_src) do sources[#sources + 1] = src end
    for _, src in ipairs(sources) do Buckets.end_activity(src, true) end
end
