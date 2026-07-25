-- server/customization.lua — contratos persistidos de aparência APV2

VHubHSS_Customization = {}
local Customization = VHubHSS_Customization

local SQL = nil
local State = nil


-- ============================================================
-- GUARDS / SERIALIZAÇÃO
-- ============================================================

local function stable_encode(value)
    local kind = type(value)
    if kind == 'nil' then return 'null' end
    if kind == 'boolean' then return value and 'true' or 'false' end
    if kind == 'number' then return ('%.17g'):format(value) end
    if kind == 'string' then return json.encode(value) end
    if kind ~= 'table' then return 'null' end

    local count, maximum, array = 0, 0, true
    for key in pairs(value) do
        count = count + 1
        if type(key) ~= 'number' or key < 1 or key % 1 ~= 0 then
            array = false
        elseif key > maximum then
            maximum = key
        end
    end
    array = array and count > 0 and maximum == count
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

local function decode_table(value)
    if type(value) == 'table' then return VHubHSS.Appearance.copy(value) end
    local ok, decoded = pcall(json.decode, value or '{}')
    return ok and type(decoded) == 'table' and decoded or nil
end

local function valid_identifier(value, minimum, maximum)
    return type(value) == 'string'
        and #value >= minimum
        and #value <= maximum
        and value:match('^[a-zA-Z0-9:_%-]+$') ~= nil
end

local function trusted(...)
    local caller = GetInvokingResource()
    for index = 1, select('#', ...) do
        if caller == select(index, ...) then return true end
    end
    return false
end

local function resolve_online(src)
    src = tonumber(src)
    if not src or src < 1 or not GetPlayerName(src) or not State then return nil end
    local char_id = State.get_char_id(src)
    return char_id and State.is_loaded(char_id) and char_id or nil
end

local function await_sql(start)
    local response = promise.new()
    local started = pcall(start, function(ok, result) response:resolve({ ok = ok, result = result }) end)
    if not started then return false, nil end
    local value = Citizen.Await(response)
    return value.ok == true, value.result
end

local function audit(char_id, reason, before, after)
    TriggerEvent(VHubHSS.E.STATE_CHANGED, char_id, {
        reason = reason,
        actor_resource = GetInvokingResource(),
        before = before,
        after = after,
        at = os.time(),
    })
end

local function operation_replay(row, char_id, src)
    if not row then return nil end
    if tonumber(row.char_id) ~= char_id or tonumber(row.digest_ok) ~= 1 then
        return { ok = false, err = 'conflict' }
    end
    if row.state ~= 'committed' then return { ok = false, err = 'conflict' } end
    local customization = decode_table(row.after_customization)
    if not customization then return { ok = false, err = 'storage' } end
    customization = VHubHSS.Appearance.sanitize(customization)
    local snapshot = State.customization_snapshot(char_id)
    local operation_revision = tonumber(row.after_revision) or 0
    if snapshot and snapshot.revision < operation_revision then
        if not State.reconcile_customization(
            char_id,
            customization,
            operation_revision,
            row.stored_version
        ) then
            return { ok = false, err = 'storage' }
        end
        TriggerClientEvent(VHubHSS.E.PED_SET_CUSTOMIZATION, src, customization)
    end
    return {
        ok = true,
        customization = customization,
        new_revision = operation_revision,
        rollback_token = row.rollback_token,
        replayed = true,
    }
end


-- ============================================================
-- CONTRATOS SERVER-SIDE
-- ============================================================

local function get_customization(src)
    if not trusted('vhub_sims', 'vhub_login') then return { ok = false, err = 'forbidden' } end
    src = tonumber(src)
    if not src or not GetPlayerName(src) then return { ok = false, err = 'offline' } end
    local char_id = resolve_online(src)
    if not char_id then
        local ok, core_char = pcall(function() return exports.vhub:getCharacterId(src) end)
        if not ok then return { ok = false, err = 'storage' } end
        if not tonumber(core_char) then return { ok = false, err = 'no_character' } end
        -- char já selecionado no CORE, mas o load físico do HSS ainda não concluiu (assíncrono)
        -- → transitório: o consumidor reespera. Nunca reportar como falha terminal.
        return { ok = false, err = 'not_ready' }
    end
    local snapshot = State.customization_snapshot(char_id)
    if not snapshot then return { ok = false, err = 'storage' } end
    local customization = snapshot.customization
    -- char novo: copy_table(nil)={} — sem campo apv; sintetizar padrão para o SIMS abrir
    if type(customization) ~= 'table' or not customization.apv then
        customization = VHubHSS.Appearance.sanitize({})
        if not customization then return { ok = false, err = 'storage' } end
    end
    return {
        ok = true,
        customization = customization,
        revision = snapshot.revision,
    }
end

local function get_character_summaries(src)
    if not trusted('vhub_login') then return { ok = false, err = 'forbidden' } end
    src = tonumber(src)
    if not src or not GetPlayerName(src) then return { ok = false, err = 'offline' } end
    local called, response = pcall(function() return exports.vhub:getCharacterIds(src) end)
    if not called or type(response) ~= 'table' or response.ok ~= true or type(response.items) ~= 'table' then
        local error_code = type(response) == 'table' and response.err or nil
        return { ok = false, err = error_code == 'offline' and 'offline' or 'storage' }
    end

    local ids = {}
    for index = 1, math.min(#response.items, 3) do
        local char_id = tonumber(response.items[index])
        if char_id and char_id > 0 then ids[#ids + 1] = math.floor(char_id) end
    end
    if #ids == 0 then return { ok = true, items = {} } end
    local ok, rows = await_sql(function(cb) SQL.load_customizations(ids, cb) end)
    if not ok or type(rows) ~= 'table' then return { ok = false, err = 'storage' } end

    local by_id = {}
    for _, row in ipairs(rows) do by_id[tonumber(row.char_id)] = row end
    local items = {}
    for _, char_id in ipairs(ids) do
        local row = by_id[char_id]
        local profile = row and decode_table(row.ped_state) or nil
        items[#items + 1] = {
            char_id = char_id,
            customization = VHubHSS.Appearance.sanitize(profile and profile.customization or nil),
            revision = row and math.max(0, tonumber(row.customization_revision) or 0) or 0,
        }
    end
    return { ok = true, items = items }
end

-- Normaliza patch APV2 para o editor autorizado sem expor mutação.
local function sanitize_customization_patch(patch)
    if not trusted('vhub_sims') then return { ok = false, err = 'forbidden' } end
    local encoded_ok, encoded = pcall(json.encode, patch)
    if not encoded_ok or type(encoded) ~= 'string' or #encoded > 8192 then
        return { ok = false, err = 'invalid_patch' }
    end
    local clean = VHubHSS.Appearance.sanitizePatch(patch)
    if not clean then return { ok = false, err = 'invalid_patch' } end
    return { ok = true, patch = clean }
end

local function commit_customization(src, patch, expected_revision, operation_id)
    if not trusted('vhub_sims') then return { ok = false, err = 'forbidden' } end
    src, expected_revision = tonumber(src), tonumber(expected_revision)
    if not src or not GetPlayerName(src) then return { ok = false, err = 'offline' } end
    if not expected_revision or expected_revision < 0 or expected_revision % 1 ~= 0
        or not valid_identifier(operation_id, 8, 96) then
        return { ok = false, err = 'invalid_patch' }
    end
    local clean = VHubHSS.Appearance.sanitizePatch(patch)
    if not clean then return { ok = false, err = 'invalid_patch' } end
    local char_id = resolve_online(src)
    if not char_id then return { ok = false, err = 'offline' } end
    local payload_json = stable_encode({ patch = clean, expected_revision = expected_revision })

    local read_ok, existing = await_sql(function(cb)
        SQL.get_customization_operation(operation_id, payload_json, cb)
    end)
    if not read_ok then return { ok = false, err = 'storage' } end
    local replay = operation_replay(existing, char_id, src)
    if replay then return replay end

    local snapshot = State.customization_snapshot(char_id)
    if not snapshot or snapshot.revision ~= expected_revision then
        return { ok = false, err = 'conflict' }
    end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return { ok = false, err = 'native' } end

    local after = VHubHSS.Appearance.merge(snapshot.customization, clean)
    local prepared, prepare_error = State.prepare_customization(char_id, after, expected_revision)
    if not prepared then return { ok = false, err = prepare_error or 'conflict' } end
    local rollback_token = 'rb:' .. operation_id
    local commit_ok, row = await_sql(function(cb)
        SQL.commit_customization(prepared, operation_id, payload_json, rollback_token, cb)
    end)
    if not commit_ok then
        State.abort_customization(prepared)
        return { ok = false, err = 'storage' }
    end
    if type(row) ~= 'table' then
        State.abort_customization(prepared)
        return { ok = false, err = 'conflict' }
    end
    if tonumber(row.digest_ok) ~= 1
        or tonumber(row.char_id) ~= char_id
        or row.state ~= 'committed'
        or tonumber(row.after_revision) ~= prepared.after_revision
        or tonumber(row.stored_revision) ~= prepared.after_revision then
        State.abort_customization(prepared)
        return { ok = false, err = 'conflict' }
    end
    if not State.confirm_customization(prepared) then
        return { ok = false, err = GetPlayerName(src) and 'storage' or 'offline' }
    end

    TriggerClientEvent(VHubHSS.E.PED_SET_CUSTOMIZATION, src, prepared.after)
    audit(char_id, 'commitCustomization', prepared.before, prepared.after)
    return {
        ok = true,
        customization = VHubHSS.Appearance.copy(prepared.after),
        new_revision = prepared.after_revision,
        rollback_token = rollback_token,
        replayed = false,
    }
end

local function rollback_customization(src, rollback_token)
    if not trusted('vhub_sims') then return { ok = false, err = 'forbidden' } end
    src = tonumber(src)
    if not src or not GetPlayerName(src) then return { ok = false, err = 'offline' } end
    if not valid_identifier(rollback_token, 11, 99) or rollback_token:sub(1, 3) ~= 'rb:' then
        return { ok = false, err = 'invalid_token' }
    end
    local char_id = resolve_online(src)
    if not char_id then return { ok = false, err = 'offline' } end

    local read_ok, operation = await_sql(function(cb)
        SQL.get_customization_rollback(rollback_token, cb)
    end)
    if not read_ok then return { ok = false, err = 'storage' } end
    if not operation or tonumber(operation.char_id) ~= char_id then
        return { ok = false, err = 'invalid_token' }
    end
    if operation.state == 'rolled_back' then
        local before = decode_table(operation.before_customization)
        local rollback_revision = tonumber(operation.rollback_revision) or 0
        local snapshot = State.customization_snapshot(char_id)
        if before and snapshot and snapshot.revision < rollback_revision then
            if not State.reconcile_customization(
                char_id,
                before,
                rollback_revision,
                operation.stored_version
            ) then
                return { ok = false, err = 'storage' }
            end
            TriggerClientEvent(VHubHSS.E.PED_SET_CUSTOMIZATION, src, before)
        end
        return {
            ok = true,
            new_revision = rollback_revision,
            replayed = true,
        }
    end
    if operation.state ~= 'committed' then return { ok = false, err = 'invalid_token' } end

    local before = decode_table(operation.before_customization)
    local expected_revision = tonumber(operation.after_revision)
    local snapshot = State.customization_snapshot(char_id)
    if not before or not expected_revision or not snapshot
        or snapshot.revision ~= expected_revision then
        return { ok = false, err = 'conflict' }
    end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return { ok = false, err = 'native' } end

    local prepared, prepare_error = State.prepare_customization(char_id, before, expected_revision)
    if not prepared then return { ok = false, err = prepare_error or 'conflict' } end
    local rollback_ok, row = await_sql(function(cb)
        SQL.rollback_customization(prepared, rollback_token, cb)
    end)
    if not rollback_ok or type(row) ~= 'table' then
        State.abort_customization(prepared)
        return { ok = false, err = 'storage' }
    end
    if row.state ~= 'rolled_back'
        or tonumber(row.rollback_revision) ~= prepared.after_revision
        or tonumber(row.stored_revision) ~= prepared.after_revision then
        State.abort_customization(prepared)
        return { ok = false, err = 'conflict' }
    end
    if not State.confirm_customization(prepared) then
        return { ok = false, err = GetPlayerName(src) and 'storage' or 'offline' }
    end

    TriggerClientEvent(VHubHSS.E.PED_SET_CUSTOMIZATION, src, prepared.after)
    audit(char_id, 'rollbackCustomization', snapshot.customization, prepared.after)
    return { ok = true, new_revision = prepared.after_revision, replayed = false }
end


-- ============================================================
-- EXPORTS / LIFECYCLE
-- ============================================================

exports('getCustomization', get_customization)
exports('getCharacterSummaries', get_character_summaries)
exports('sanitizeCustomizationPatch', sanitize_customization_patch)
exports('commitCustomization', commit_customization)
exports('rollbackCustomization', rollback_customization)

-- Injeta escritor SQL e VRAM após o schema ser validado.
function Customization.init(sql_module, state_module, _logger)
    SQL, State = sql_module, state_module
end
