-- server/state.lua — VRAM autoritativa e persistência atômica do HSS

VHubHSS_State = {}
local State = VHubHSS_State

local SQL = nil
local Cfg = nil
local Logger = nil

local _entries = {}
local _src_map = {}
local _char_src = {}
local _generation = {}
local _queue = {}
local _queue_head = 1
local _worker_running = false
local _worker_busy = false
local _worker_scheduled = false
local _shutting_down = false
local _save_window_at = 0
local _save_window_count = 0
local _customization_locks = {}
local _customization_sequence = 0

local MAX_RETRIES = 5
local MAX_OUTBOX_BYTES = 60000
local MAX_SNAPSHOT_BYTES = 50000
local MAX_SAVES_PER_WINDOW = 400
local SAVE_WINDOW_MS = 3000

local DEFAULTS = {
    food = 1.0,
    water = 1.0,
    energy = 1.0,
    stress = 0.0,
    adrenaline = 0.0,
    blood = 1.0,
    bleeding = 0,
    pain = 0.0,
    body_temp = 37.0,
    consciousness = 'awake',
    diseases = {},
    injuries = {},
}


-- ============================================================
-- SANITIZAÇÃO / SERIALIZAÇÃO
-- ============================================================

local function finite(value)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge then return nil end
    return number
end

local function clamp(value, min_value, max_value)
    return math.max(min_value, math.min(max_value, value))
end

local function copy_table(value)
    local out = {}
    if type(value) ~= 'table' then return out end
    for key, item in pairs(value) do
        out[key] = type(item) == 'table' and copy_table(item) or item
    end
    return out
end

local function decode_table(raw)
    if type(raw) == 'table' then return copy_table(raw) end
    local ok, value = pcall(json.decode, raw or '{}')
    return ok and type(value) == 'table' and value or {}
end

local function stable_encode(value)
    local kind = type(value)
    if kind == 'nil' then return 'null' end
    if kind == 'boolean' then return value and 'true' or 'false' end
    if kind == 'number' then return ('%.17g'):format(value) end
    if kind == 'string' then return json.encode(value) end
    if kind ~= 'table' then return 'null' end

    local count, max_index, array = 0, 0, true
    for key in pairs(value) do
        count = count + 1
        if type(key) ~= 'number' or key < 1 or key % 1 ~= 0 then
            array = false
        elseif key > max_index then
            max_index = key
        end
    end
    array = array and max_index == count and count > 0
    if array then
        local items = {}
        for index = 1, count do items[index] = stable_encode(value[index]) end
        return '[' .. table.concat(items, ',') .. ']'
    end

    local keys = {}
    for key in pairs(value) do
        if type(key) == 'string' then keys[#keys + 1] = key end
    end
    table.sort(keys)
    local items = {}
    for index, key in ipairs(keys) do
        items[index] = json.encode(key) .. ':' .. stable_encode(value[key])
    end
    return '{' .. table.concat(items, ',') .. '}'
end

local function checksum(value)
    local hash = 2166136261
    for index = 1, #value do
        hash = (hash ~ value:byte(index)) & 0xffffffff
        hash = (hash * 16777619) & 0xffffffff
    end
    return ('%08x'):format(hash)
end

local function sanitize_position(value)
    if type(value) ~= 'table' then return nil end
    local x, y, z = finite(value.x), finite(value.y), finite(value.z)
    if not x or not y or not z then return nil end
    if math.abs(x) >= 8000 or math.abs(y) >= 8000 or z <= -200 or z >= 2000 then return nil end
    return { x = x, y = y, z = z }
end

local function sanitize_customization(value)
    return VHubHSS.Appearance.sanitize(value)
end

local function build_state(row, legacy_vitals)
    local st = copy_table(DEFAULTS)
    if row then
        st.food = clamp(finite(row.food) or st.food, 0.0, 1.0)
        st.water = clamp(finite(row.water) or st.water, 0.0, 1.0)
        st.energy = clamp(finite(row.energy) or st.energy, 0.0, 1.0)
        st.stress = clamp(finite(row.stress) or st.stress, 0.0, 1.0)
        st.blood = clamp(finite(row.blood) or st.blood, 0.0, 1.0)
        st.bleeding = math.floor(clamp(finite(row.bleeding) or st.bleeding, 0, 4))
        st.pain = clamp(finite(row.pain) or st.pain, 0.0, 1.0)
        st.body_temp = clamp(finite(row.body_temp) or st.body_temp, 34.0, 43.0)
        st.consciousness = row.consciousness == 'unconscious' and 'unconscious' or 'awake'
        st.diseases = decode_table(row.diseases)
        st.injuries = decode_table(row.injuries)
    elseif type(legacy_vitals) == 'table' then
        st.water = clamp(finite(legacy_vitals.agua) or st.water, 0.0, 1.0)
        st.food = clamp(finite(legacy_vitals.comida) or st.food, 0.0, 1.0)
    end
    return st
end

local function build_profile(raw, legacy_state)
    raw = type(raw) == 'table' and raw or {}
    legacy_state = type(legacy_state) == 'table' and legacy_state or {}
    local position = sanitize_position(raw.position) or sanitize_position(legacy_state.position)
    local heading = finite(raw.heading) or finite(legacy_state.heading) or 0.0
    local health = finite(raw.health) or finite(legacy_state.health) or Cfg.PED.default_health
    local armour = finite(raw.armour) or finite(legacy_state.armour) or Cfg.PED.default_armour
    return {
        position = position,
        heading = heading % 360.0,
        health = math.floor(clamp(health, 0, 200)),
        armour = math.floor(clamp(armour, 0, 100)),
        customization = sanitize_customization(raw.customization or legacy_state.customization),
    }
end

local function persistent_state(st)
    return {
        food = st.food,
        water = st.water,
        energy = st.energy,
        stress = st.stress,
        blood = st.blood,
        bleeding = st.bleeding,
        pain = st.pain,
        body_temp = st.body_temp,
        consciousness = st.consciousness,
        diseases = copy_table(st.diseases),
        injuries = copy_table(st.injuries),
    }
end

local function make_bundle(entry, revision)
    local bundle = {
        state = persistent_state(entry.state),
        profile = copy_table(entry.profile),
        revision = revision or entry.version,
        customization_revision = math.max(0, tonumber(entry.customization_revision) or 0),
    }
    bundle.snapshot_json = stable_encode({
        customization_revision = bundle.customization_revision,
        profile = bundle.profile,
        revision = bundle.revision,
        state = bundle.state,
    })
    if #bundle.snapshot_json > MAX_SNAPSHOT_BYTES then return nil, 'snapshot_too_large' end
    return bundle
end


-- ============================================================
-- OUTBOX / FILA SERIAL
-- ============================================================

local function outbox_key(char_id) return 'hss_outbox:' .. tostring(char_id) end

local function write_outbox(char_id, bundle)
    local payload = {
        customization_revision = bundle.customization_revision,
        revision = bundle.revision,
        snapshot_json = bundle.snapshot_json,
    }
    local encoded = json.encode({
        payload = payload,
        checksum = checksum(('%d:%d'):format(
            payload.revision,
            payload.customization_revision
        ) .. ':' .. payload.snapshot_json),
    })
    if #encoded > MAX_OUTBOX_BYTES then return false, 'outbox_too_large' end
    local ok, err = pcall(SetResourceKvp, outbox_key(char_id), encoded)
    return ok, ok and nil or tostring(err)
end

local function read_outbox(char_id)
    local ok, raw = pcall(GetResourceKvpString, outbox_key(char_id))
    if not ok then return nil, 'kvp_read' end
    if not raw then return nil end
    local ok, envelope = pcall(json.decode, raw)
    local payload = ok and type(envelope) == 'table' and envelope.payload or nil
    if type(payload) ~= 'table' or type(envelope.checksum) ~= 'string' then return nil, 'invalid' end
    local revision = tonumber(payload.revision)
    local has_customization_revision = payload.customization_revision ~= nil
    local customization_revision = tonumber(payload.customization_revision) or 0
    if not revision or revision < 1 or customization_revision < 0
        or type(payload.snapshot_json) ~= 'string' then
        return nil, 'revision'
    end
    revision, customization_revision = math.floor(revision), math.floor(customization_revision)
    local checksum_input = has_customization_revision
        and (('%d:%d'):format(revision, customization_revision) .. ':' .. payload.snapshot_json)
        or (('%d'):format(revision) .. ':' .. payload.snapshot_json)
    if checksum(checksum_input) ~= envelope.checksum then
        return nil, 'checksum'
    end
    local decoded_ok, snapshot = pcall(json.decode, payload.snapshot_json)
    if not decoded_ok or type(snapshot) ~= 'table' then return nil, 'snapshot' end
    return {
        state = build_state(snapshot.state),
        profile = build_profile(snapshot.profile),
        revision = revision,
        customization_revision = customization_revision,
        legacy_format = not has_customization_revision,
        snapshot_json = payload.snapshot_json,
    }
end

local function delete_outbox(char_id) pcall(DeleteResourceKvp, outbox_key(char_id)) end

local function log_error(message, meta)
    if Logger then Logger('error', message, meta) end
end

local schedule_worker

local function enqueue(char_id, entry)
    if not entry or entry.queued or entry.in_flight or not entry.dirty then return end
    entry.queued = true
    _queue[#_queue + 1] = { char_id = char_id, entry = entry }
    if schedule_worker then schedule_worker(0) end
end

local function collect(char_id, entry)
    if entry.dropping and not entry.dirty and not entry.queued and not entry.in_flight then
        if _entries[char_id] == entry then _entries[char_id] = nil end
    end
end

local function rate_wait()
    local now = GetGameTimer()
    if now - _save_window_at >= SAVE_WINDOW_MS then
        _save_window_at = now
        _save_window_count = 0
    end
    if _save_window_count < MAX_SAVES_PER_WINDOW then return 0 end
    return math.max(1, SAVE_WINDOW_MS - (now - _save_window_at))
end

local function process_queue_item(item)
    local char_id, entry = item.char_id, item.entry
    entry.queued = false
    if _entries[char_id] ~= entry or not entry.dirty or entry.in_flight then return end

    local bundle, bundle_error = make_bundle(entry)
    if not bundle then
        log_error('Snapshot HSS excedeu o limite canônico.', {
            char_id = char_id,
            error = bundle_error,
        })
        return
    end
    entry.in_flight = true
    _worker_busy = true
    _save_window_count = _save_window_count + 1
    local started = pcall(SQL.save, char_id, bundle, function(success, result)
        _worker_busy = false
        if _entries[char_id] ~= entry then
            schedule_worker(0)
            return
        end
        entry.in_flight = false

        if success then
            entry.retries = 0
            if not _shutting_down then delete_outbox(char_id) end
            if entry.version == bundle.revision then entry.dirty = false end
            if entry.dirty then enqueue(char_id, entry) else collect(char_id, entry) end
            schedule_worker(0)
            return
        end

        entry.retries = entry.retries + 1
        if entry.retries <= MAX_RETRIES then
            local delay = math.min(4000, 250 * (2 ^ (entry.retries - 1)))
            SetTimeout(delay, function()
                if _entries[char_id] == entry then enqueue(char_id, entry) end
            end)
            schedule_worker(0)
            return
        end

        local terminal_bundle, bundle_error = make_bundle(entry)
        local stored, outbox_error = false, bundle_error
        if terminal_bundle then stored, outbox_error = write_outbox(char_id, terminal_bundle) end
        log_error('Falha terminal ao persistir estado.', {
            char_id = char_id,
            error = tostring(result),
            outbox = stored,
            outbox_error = outbox_error,
        })
        entry.retries = 0
        if entry.dropping and stored then
            entry.dirty = false
            collect(char_id, entry)
        end
        schedule_worker(0)
    end)
    if not started then
        _worker_busy = false
        entry.in_flight = false
        entry.retries = entry.retries + 1
        if entry.retries <= MAX_RETRIES then
            SetTimeout(math.min(4000, 250 * (2 ^ (entry.retries - 1))), function()
                if _entries[char_id] == entry then enqueue(char_id, entry) end
            end)
        else
            local terminal_bundle = make_bundle(entry)
            local stored = terminal_bundle and write_outbox(char_id, terminal_bundle) or false
            entry.retries = 0
            if entry.dropping and stored then
                entry.dirty = false
                collect(char_id, entry)
            end
        end
        schedule_worker(0)
    end
end

local function pump_worker()
    if not _worker_running or _worker_busy then return end
    local wait_ms = rate_wait()
    if wait_ms > 0 then
        schedule_worker(wait_ms)
        return
    end

    while _worker_running and not _worker_busy do
        local item = _queue[_queue_head]
        if not item then
            _queue = {}
            _queue_head = 1
            return
        end
        _queue[_queue_head] = nil
        _queue_head = _queue_head + 1
        process_queue_item(item)
    end
end

schedule_worker = function(delay_ms)
    if not _worker_running or _worker_busy or _worker_scheduled then return end
    _worker_scheduled = true
    SetTimeout(math.max(0, tonumber(delay_ms) or 0), function()
        _worker_scheduled = false
        pump_worker()
    end)
end

local function start_worker()
    if _worker_running then return end
    _worker_running = true
    schedule_worker(0)
end


-- ============================================================
-- LIFECYCLE
-- ============================================================

-- Injeta dependências autoritativas e inicia o escritor SQL único.
function State.init(sql_module, cfg, logger)
    SQL = sql_module
    Cfg = cfg
    Logger = logger
    start_worker()
end

local function session_valid(src, char_id, generation)
    return _generation[src] == generation
        and _src_map[src] == char_id
        and GetPlayerName(src) ~= nil
end

local function install_entry(
    src,
    char_id,
    state,
    profile,
    revision,
    customization_revision,
    dirty,
    on_loaded
)
    local entry = {
        state = state,
        profile = profile,
        src = src,
        version = math.max(0, tonumber(revision) or 0),
        customization_revision = math.max(0, tonumber(customization_revision) or 0),
        dirty = dirty == true,
        queued = false,
        in_flight = false,
        retries = 0,
        dropping = false,
    }
    _entries[char_id] = entry
    if entry.dirty then enqueue(char_id, entry) end
    if on_loaded then pcall(on_loaded, entry.state, nil) end
end

-- Registra sessão por char_id canônico, sem conservar referência viva do CORE.
function State.register(src, char_id, legacy, on_loaded)
    src, char_id = tonumber(src), tonumber(char_id)
    if not src or not char_id or src < 1 or char_id < 1 then return false end
    if _char_src[char_id] and _char_src[char_id] ~= src then return false end

    local generation = (_generation[src] or 0) + 1
    _generation[src] = generation
    _src_map[src] = char_id
    _char_src[char_id] = src

    local retained = _entries[char_id]
    if retained then
        retained.src = src
        retained.dropping = false
        if on_loaded then pcall(on_loaded, retained.state, nil) end
        return true
    end

    local function fail(reason)
        if not session_valid(src, char_id, generation) then return end
        _src_map[src] = nil
        if _char_src[char_id] == src then _char_src[char_id] = nil end
        if on_loaded then pcall(on_loaded, nil, reason) end
    end

    local function install_canonical_row(row, legacy_state, expected_snapshot, delete_after)
        local row_revision = tonumber(row.revision) or 0
        local customization_revision = tonumber(row.customization_revision) or 0
        local row_state = build_state(row)
        local row_profile = build_profile(decode_table(row.ped_state), legacy_state)
        local missing_integrity = row.ped_state == nil
            or type(row.digest) ~= 'string'
            or #row.digest ~= 64
        if missing_integrity then
            install_entry(
                src,
                char_id,
                row_state,
                row_profile,
                row_revision + 1,
                customization_revision,
                true,
                on_loaded
            )
            return
        end
        local bundle = make_bundle({
            state = row_state,
            profile = row_profile,
            version = row_revision,
            customization_revision = customization_revision,
        }, row_revision)
        if not bundle then fail('snapshot_too_large'); return end
        if expected_snapshot and bundle.snapshot_json ~= expected_snapshot then
            log_error('Colunas HSS divergiram do digest canônico.', { char_id = char_id })
            fail('digest_mismatch')
            return
        end
        SQL.matches(char_id, bundle.snapshot_json, function(match_ok, matches)
            if not session_valid(src, char_id, generation) then return end
            if not match_ok then
                -- falha de SQL real: bloqueia (condição de parada correta)
                log_error('Digest SQL HSS inválido; carga bloqueada.', { char_id = char_id })
                fail('digest_mismatch')
                return
            end
            if matches ~= true then
                -- digest divergiu (mudança de formato ou migração incompleta):
                -- colunas são a fonte de verdade real — reinstala dirty para re-salvar o digest correto
                log_error(
                    'Digest HSS divergiu do snapshot — reinstalando de colunas (auto-heal).',
                    { char_id = char_id }
                )
                install_entry(
                    src,
                    char_id,
                    row_state,
                    row_profile,
                    row_revision + 1,
                    customization_revision,
                    true,
                    on_loaded
                )
                return
            end
            if delete_after then delete_outbox(char_id) end
            install_entry(
                src,
                char_id,
                row_state,
                row_profile,
                row_revision,
                customization_revision,
                false,
                on_loaded
            )
        end)
    end

    SQL.load(char_id, function(load_ok, row)
        if not session_valid(src, char_id, generation) then return end
        if not load_ok then fail('load_failed'); return end

        local legacy_vitals = type(legacy) == 'table' and legacy.vitals or nil
        local legacy_state = type(legacy) == 'table' and legacy.state or nil
        local outbox, outbox_error = read_outbox(char_id)
        if outbox_error then
            log_error('Outbox HSS inválida; carga bloqueada.', { char_id = char_id, error = outbox_error })
            fail('outbox_invalid')
            return
        end

        if not row and outbox then
            install_entry(
                src,
                char_id,
                outbox.state,
                outbox.profile,
                outbox.revision,
                outbox.customization_revision,
                true,
                on_loaded
            )
            return
        end

        if not row then
            local candidate = {
                state = build_state(nil, legacy_vitals),
                profile = build_profile(nil, legacy_state),
                version = 1,
                customization_revision = 0,
            }
            local bundle = make_bundle(candidate, 1)
            if not bundle then fail('snapshot_too_large'); return end
            SQL.insert_if_absent(char_id, bundle, function(insert_ok, canonical)
                if not session_valid(src, char_id, generation) then return end
                if not insert_ok or not canonical then fail('insert_failed'); return end
                install_canonical_row(canonical, legacy_state)
            end)
            return
        end

        local row_revision = tonumber(row.revision) or 0
        if outbox and outbox.revision > row_revision then
            install_entry(
                src,
                char_id,
                outbox.state,
                outbox.profile,
                outbox.revision,
                outbox.customization_revision,
                true,
                on_loaded
            )
            return
        end
        if outbox and outbox.revision == row_revision then
            local missing_integrity = row.ped_state == nil
                or type(row.digest) ~= 'string'
                or #row.digest ~= 64
            if missing_integrity then
                install_entry(
                    src,
                    char_id,
                    outbox.state,
                    outbox.profile,
                    outbox.revision + 1,
                    outbox.customization_revision,
                    true,
                    on_loaded
                )
                return
            end
            install_canonical_row(
                row,
                legacy_state,
                outbox.legacy_format and nil or outbox.snapshot_json,
                true
            )
            return
        end
        install_canonical_row(row, legacy_state, nil, outbox ~= nil)
    end)
    return true
end

-- Desanexa sessão e agenda persistência do último snapshot.
function State.unregister(src)
    src = tonumber(src)
    local char_id = src and _src_map[src]
    if not char_id then return nil end
    _generation[src] = (_generation[src] or 0) + 1
    _src_map[src] = nil
    if _char_src[char_id] == src then _char_src[char_id] = nil end

    local entry = _entries[char_id]
    _customization_locks[char_id] = nil
    if entry then
        entry.src = nil
        entry.dropping = true
        if entry.dirty then enqueue(char_id, entry) else collect(char_id, entry) end
    end
    return char_id
end


-- ============================================================
-- READS
-- ============================================================

-- Retorna referência interna exclusivamente para módulos HSS.
function State.get(char_id)
    local entry = _entries[tonumber(char_id)]
    return entry and entry.state or nil
end

-- Retorna cópia profunda da fisiologia.
function State.snapshot(char_id)
    local st = State.get(char_id)
    if not st then return nil end
    local out = persistent_state(st)
    out.adrenaline = st.adrenaline
    out.trauma = tonumber(st.injuries.trauma) or 0.0
    return out
end

-- Retorna cópia profunda do estado persistente do ped.
function State.profile_snapshot(char_id)
    local entry = _entries[tonumber(char_id)]
    return entry and copy_table(entry.profile) or nil
end

-- Retorna aparência e revisão exclusivas em cópias profundas.
function State.customization_snapshot(char_id)
    local entry = _entries[tonumber(char_id)]
    if not entry then return nil end
    return {
        customization = copy_table(entry.profile.customization),
        revision = entry.customization_revision,
    }
end

-- Reconcilia ACK persistido após timeout/replay sem regredir revisão mais nova.
function State.reconcile_customization(char_id, customization, revision, persisted_version)
    char_id, revision = tonumber(char_id), tonumber(revision)
    local entry = char_id and _entries[char_id] or nil
    if not entry or not revision or revision < entry.customization_revision
        or _customization_locks[char_id] then
        return false
    end
    if revision == entry.customization_revision then return true end

    entry.profile.customization = sanitize_customization(customization)
    entry.customization_revision = revision
    persisted_version = math.max(0, tonumber(persisted_version) or 0)
    delete_outbox(char_id)
    if entry.dirty then
        entry.version = math.max(entry.version, persisted_version) + 1
        enqueue(char_id, entry)
    else
        entry.version = math.max(entry.version, persisted_version)
    end
    return true
end

-- Retorna o personagem associado à origem.
function State.get_char_id(src) return _src_map[tonumber(src)] end

-- Retorna a origem online associada ao personagem.
function State.get_src(char_id) return _char_src[tonumber(char_id)] end

-- Informa se o personagem está carregado.
function State.is_loaded(char_id) return _entries[tonumber(char_id)] ~= nil end


-- ============================================================
-- MUTATIONS
-- ============================================================

local function mark_dirty(entry)
    entry.version = entry.version + 1
    entry.dirty = true
end

-- Aplica delta validado a campo fisiológico escalar.
function State.mutate(char_id, field, delta)
    local entry = _entries[tonumber(char_id)]
    if not entry then return nil, false end
    local current = entry.state[field]
    local next_value
    if field == 'consciousness' then
        next_value = delta == 'unconscious' and 'unconscious' or 'awake'
    elseif type(current) == 'number' then
        next_value = current + (tonumber(delta) or 0)
        local limit = Cfg.LIMITS[field]
        if limit then next_value = clamp(next_value, limit.min, limit.max) end
        if field == 'bleeding' then next_value = math.floor(next_value) end
    else
        return current, false
    end
    if next_value == current then return current, false end
    entry.state[field] = next_value
    mark_dirty(entry)
    return next_value, true
end

-- Marca alteração direta feita pelo engine fisiológico.
function State.touch(char_id)
    local entry = _entries[tonumber(char_id)]
    if entry then mark_dirty(entry) end
end

-- Aplica delta no trauma persistido.
function State.mutate_trauma(char_id, delta)
    local entry = _entries[tonumber(char_id)]
    if not entry then return nil, false end
    local current = tonumber(entry.state.injuries.trauma) or 0.0
    local limit = Cfg.LIMITS.trauma
    local next_value = clamp(current + (tonumber(delta) or 0), limit.min, limit.max)
    if math.abs(next_value - current) < 0.000001 then return current, false end
    entry.state.injuries.trauma = next_value
    mark_dirty(entry)
    return next_value, true
end

-- Remove todas as lesões persistidas.
function State.clear_injuries(char_id)
    local entry = _entries[tonumber(char_id)]
    if not entry or next(entry.state.injuries) == nil then return false end
    entry.state.injuries = {}
    mark_dirty(entry)
    return true
end

-- Atualiza posição server-side validada.
function State.set_position(char_id, position, heading)
    local entry = _entries[tonumber(char_id)]
    local clean = sanitize_position(position)
    if not entry or not clean then return false end
    local next_heading = (finite(heading) or entry.profile.heading or 0.0) % 360.0
    local current = entry.profile.position
    if current
        and math.abs(current.x - clean.x) < 0.05
        and math.abs(current.y - clean.y) < 0.05
        and math.abs(current.z - clean.z) < 0.05
        and math.abs((entry.profile.heading or 0.0) - next_heading) < 1.0 then
        return true
    end
    entry.profile.position = clean
    entry.profile.heading = next_heading
    mark_dirty(entry)
    return true
end

-- Atualiza vida server-side validada.
function State.set_health(char_id, health)
    local entry, value = _entries[tonumber(char_id)], finite(health)
    if not entry or not value then return false end
    value = math.floor(clamp(value, 0, 200))
    if entry.profile.health == value then return true end
    entry.profile.health = value
    mark_dirty(entry)
    return true
end

-- Atualiza colete server-side validado.
function State.set_armour(char_id, armour)
    local entry, value = _entries[tonumber(char_id)], finite(armour)
    if not entry or not value then return false end
    value = math.floor(clamp(value, 0, 100))
    if entry.profile.armour == value then return true end
    entry.profile.armour = value
    mark_dirty(entry)
    return true
end

-- Atualiza customização sanitizada por contrato confiável.
function State.set_customization(char_id, customization)
    char_id = tonumber(char_id)
    local entry = _entries[char_id]
    if not entry or type(customization) ~= 'table' or _customization_locks[char_id] then return false end
    entry.profile.customization = sanitize_customization(customization)
    entry.customization_revision = entry.customization_revision + 1
    mark_dirty(entry)
    return true
end

-- Reserva CAS de aparência e materializa bundle completo para persistência atômica.
function State.prepare_customization(char_id, customization, expected_revision)
    char_id, expected_revision = tonumber(char_id), tonumber(expected_revision)
    local entry = char_id and _entries[char_id] or nil
    if not entry or not expected_revision or expected_revision % 1 ~= 0 then return nil, 'conflict' end
    if _customization_locks[char_id] or entry.in_flight
        or entry.customization_revision ~= expected_revision then
        return nil, 'conflict'
    end

    _customization_sequence = _customization_sequence + 1
    local profile = copy_table(entry.profile)
    profile.customization = sanitize_customization(customization)
    local prepared = {
        token = _customization_sequence,
        char_id = char_id,
        before = copy_table(entry.profile.customization),
        after = copy_table(profile.customization),
        before_revision = expected_revision,
        after_revision = expected_revision + 1,
        base_version = entry.version,
    }
    prepared.bundle = make_bundle({
        state = entry.state,
        profile = profile,
        version = entry.version + 1,
        customization_revision = prepared.after_revision,
    }, entry.version + 1)
    if not prepared.bundle then return nil, 'storage' end
    _customization_locks[char_id] = prepared.token
    entry.in_flight = true
    return prepared
end

-- Confirma CAS persistido e reconcilia mutações fisiológicas concorrentes.
function State.confirm_customization(prepared)
    if type(prepared) ~= 'table' then return false end
    local char_id = tonumber(prepared.char_id)
    local entry = char_id and _entries[char_id] or nil
    if not entry or _customization_locks[char_id] ~= prepared.token then return false end

    _customization_locks[char_id] = nil
    entry.in_flight = false
    entry.profile.customization = copy_table(prepared.after)
    entry.customization_revision = prepared.after_revision
    delete_outbox(char_id)
    if entry.version == prepared.base_version then
        entry.version = prepared.bundle.revision
        entry.dirty = false
    else
        entry.version = math.max(entry.version, prepared.bundle.revision) + 1
        entry.dirty = true
        enqueue(char_id, entry)
    end
    return true
end

-- Libera CAS falho sem alterar a aparência atual.
function State.abort_customization(prepared)
    if type(prepared) ~= 'table' then return false end
    local char_id = tonumber(prepared.char_id)
    if not char_id or _customization_locks[char_id] ~= prepared.token then return false end
    _customization_locks[char_id] = nil
    local entry = _entries[char_id]
    if entry then
        entry.in_flight = false
        if entry.dirty then enqueue(char_id, entry) end
    end
    return true
end

-- Limpa estado efêmero de morte e define respawn seguro.
function State.reset_after_death(char_id)
    local entry = _entries[tonumber(char_id)]
    if not entry then return false end
    entry.profile.position = nil
    entry.profile.heading = 0.0
    entry.profile.health = Cfg.PED.default_health
    entry.profile.armour = Cfg.PED.default_armour
    mark_dirty(entry)
    return true
end


-- ============================================================
-- FLUSH / SHUTDOWN
-- ============================================================

-- Agenda persistência do estado associado à origem.
function State.flush_src(src)
    local char_id = _src_map[tonumber(src)]
    if char_id then enqueue(char_id, _entries[char_id]) end
end

-- Agenda todos os snapshots sujos no escritor serial.
function State.flush_all()
    for char_id, entry in pairs(_entries) do enqueue(char_id, entry) end
end

-- Materializa cada estado sujo; KVP falho exige ACK SQL síncrono.
function State.flush_emergency()
    for char_id, entry in pairs(_entries) do
        if entry.dirty then
            local bundle, bundle_error = make_bundle(entry)
            local stored, outbox_error = false, bundle_error
            if bundle then stored, outbox_error = write_outbox(char_id, bundle) end
            if not stored and bundle then
                local saved, sql_error = SQL.save_sync(char_id, bundle)
                if saved then
                    entry.dirty = false
                    delete_outbox(char_id)
                else
                    log_error('Flush terminal HSS sem ACK.', {
                        char_id = char_id,
                        outbox_error = outbox_error,
                        sql_error = sql_error,
                    })
                end
            elseif not stored then
                log_error('Snapshot terminal HSS inválido.', {
                    char_id = char_id,
                    error = outbox_error,
                })
            end
        end
    end
end

-- Encerra o worker após materializar todo estado sujo no outbox local.
function State.shutdown()
    _shutting_down = true
    State.flush_emergency()
    _worker_running = false
    _worker_scheduled = false
end

-- Exercita retry, ACK SQL, reload/digest e outbox somente sob test mode.
function State.run_persistence_test(src)
    if GetConvar('vhub_test_mode', '0') ~= '1' then return nil end
    src = tonumber(src)
    local char_id = src and _src_map[src] or nil
    local entry = char_id and _entries[char_id] or nil
    if not entry or entry.dirty or entry.in_flight then return false end

    local original_stress = entry.state.stress
    local delta = original_stress < 0.999 and 0.001 or -0.001
    local original_save = SQL.save
    local injected = false
    SQL.save = function(test_char_id, bundle, cb)
        if test_char_id == char_id and not injected then
            injected = true
            SQL.save = original_save
            cb(false, 'test_retry')
            return
        end
        return original_save(test_char_id, bundle, cb)
    end

    State.mutate(char_id, 'stress', delta)
    State.flush_src(src)
    local deadline = GetGameTimer() + 12000
    while entry.dirty and GetGameTimer() < deadline do Citizen.Wait(25) end
    SQL.save = original_save
    local roundtrip = not entry.dirty and injected
    local bundle = roundtrip and make_bundle(entry) or nil
    if bundle then
        local stored = write_outbox(char_id, bundle)
        local recovered = stored and read_outbox(char_id) or nil
        delete_outbox(char_id)
        roundtrip = recovered ~= nil
            and recovered.revision == bundle.revision
            and recovered.snapshot_json == bundle.snapshot_json
    else
        roundtrip = false
    end

    if roundtrip then
        local expected_stress = entry.state.stress
        State.unregister(src)
        local reload_promise = promise.new()
        local accepted = State.register(src, char_id, nil, function(st, load_error)
            reload_promise:resolve({ state = st, error = load_error })
        end)
        local reloaded = accepted and Citizen.Await(reload_promise) or nil
        roundtrip = reloaded ~= nil
            and type(reloaded.state) == 'table'
            and math.abs((reloaded.state.stress or -1) - expected_stress) < 0.0000001
            and _entries[char_id] ~= nil
        if not roundtrip and not _entries[char_id] then
            entry.src = src
            entry.dropping = false
            _entries[char_id] = entry
            _src_map[src] = char_id
            _char_src[char_id] = src
        end
    end

    entry = _entries[char_id]
    if not entry then return false end
    State.mutate(char_id, 'stress', original_stress - entry.state.stress)
    State.flush_src(src)
    deadline = GetGameTimer() + 12000
    while entry.dirty and GetGameTimer() < deadline do Citizen.Wait(25) end
    return roundtrip and not entry.dirty
end
