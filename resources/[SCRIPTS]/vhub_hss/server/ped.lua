-- server/ped.lua — owner autoritativo do estado físico e spawn do ped

VHubHSS_Ped = {}
local Ped = VHubHSS_Ped

local State = nil
local Buckets = nil
local Cfg = nil
local ResolveCharacter = nil
local Logger = nil

local _spawn_seen = {}
local _pending = {}
local _pending_generation = 0
local _observed = {}
local _ledger = {}
local _volatile = {}
local _rate = {}
local _movement_override = {}
local _active_char = {}
local _suspended = {}
local _dead = {}
local _revive_generation = {}
local _model_override = {}
local _customization_stages = {}
local _ended_stage_tokens = {}
local _stage_generation = 0
local _creation_hold = {}


-- ============================================================
-- GUARDS / NORMALIZAÇÃO
-- ============================================================

local function finite(value)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge then return nil end
    return number
end

local function clamp(value, min_value, max_value)
    return math.max(min_value, math.min(max_value, value))
end

local function valid_model_name(value)
    return type(value) == 'string' and #value >= 1 and #value <= 64
        and value:match('^[a-zA-Z0-9_]+$') ~= nil
end

local function valid_position(value)
    if type(value) ~= 'table' then return nil end
    local x, y, z = finite(value.x), finite(value.y), finite(value.z)
    if not x or not y or not z then return nil end
    if math.abs(x) >= 8000 or math.abs(y) >= 8000 or z <= -200 or z >= 2000 then return nil end
    return {
        x = x,
        y = y,
        z = z,
        heading = (finite(value.heading) or finite(value.h) or 0.0) % 360.0,
    }
end

local function clean_custom(value)
    return VHubHSS.Appearance.sanitize(value)
end

local function copy_table(value)
    local out = {}
    if type(value) ~= 'table' then return out end
    for key, item in pairs(value) do
        out[key] = type(item) == 'table' and copy_table(item) or item
    end
    return out
end

local function default_profile()
    return {
        position = nil,
        heading = 0.0,
        health = Cfg.PED.default_health,
        armour = Cfg.PED.default_armour,
        customization = { model = Cfg.PED.default_model },
    }
end

local function resolve_online(src)
    src = tonumber(src)
    if not ResolveCharacter or not src or src < 1 or not GetPlayerName(src) then return nil end
    return tonumber(ResolveCharacter(src))
end

local function profile_for(src, char_id)
    if State and State.is_loaded(char_id) then return State.profile_snapshot(char_id) end
    local profile = _volatile[char_id]
    if not profile then
        profile = default_profile()
        _volatile[char_id] = profile
    end
    return copy_table(profile)
end

local function set_volatile(char_id, field, value)
    local profile = _volatile[char_id] or default_profile()
    profile[field] = type(value) == 'table' and copy_table(value) or value
    _volatile[char_id] = profile
end

local function ped_invoker_ok()
    if not Cfg then return false end
    local caller = GetInvokingResource()
    return caller ~= nil and caller ~= '' and Cfg.PED_TRUSTED[caller] == true
end

local function creation_invoker_ok()
    return GetInvokingResource() == 'vhub_login'
end

local function activity_invoker_ok()
    if not Cfg then return false end
    local caller = GetInvokingResource()
    return caller ~= nil and caller ~= '' and Cfg.ACTIVITY_TRUSTED[caller] == true
end

local function customization_invoker_ok()
    if not Cfg then return false end
    local caller = GetInvokingResource()
    return caller ~= nil and caller ~= '' and Cfg.CUSTOMIZATION_TRUSTED[caller] == true
end

local function rate_ok(name, src)
    local caller = GetInvokingResource() or ''
    local key = caller .. ':' .. name .. ':' .. tostring(src)
    local now = GetGameTimer()
    local previous = _rate[key]
    local limit = Cfg.RATE_LIMIT_MS[name] or Cfg.RATE_LIMIT_MS.pedMutation
    if previous and now - previous < limit then return false end
    _rate[key] = now
    return true
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

local function report_physical_death(src)
    local ok, accepted = pcall(function() return exports.vhub:reportPhysicalDeath(src) end)
    return ok and accepted == true
end

local function report_physical_respawn(src)
    local ok, accepted = pcall(function() return exports.vhub:reportPhysicalRespawn(src) end)
    return ok and accepted == true
end

local function physical_health(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    return tonumber(GetEntityHealth(ped))
end

local function schedule_respawn_confirmation(src, char_id)
    local generation = (_revive_generation[src] or 0) + 1
    _revive_generation[src] = generation
    Citizen.CreateThread(function()
        for _ = 1, 30 do
            Citizen.Wait(100)
            if _revive_generation[src] ~= generation or resolve_online(src) ~= char_id then return end
            if report_physical_respawn(src) then return end
        end
        if Logger then Logger('warn', 'Respawn físico não confirmado em 3s.', { src = src, char_id = char_id }) end
    end)
end


-- ============================================================
-- SPAWN
-- ============================================================

local function effective_position(profile)
    local position = valid_position(profile and profile.position)
    if position then
        position.heading = finite(profile.heading) or position.heading
        return position
    end
    local spawn = Cfg.PED.spawn
    return {
        x = finite(spawn.x) or 0.0,
        y = finite(spawn.y) or 0.0,
        z = finite(spawn.z) or 70.0,
        heading = finite(spawn.w) or 0.0,
    }
end

local function seed_baseline(src, profile, position, authorize)
    position = valid_position(position) or effective_position(profile)
    local now = GetGameTimer()
    _observed[src] = {
        at = now,
        x = position.x,
        y = position.y,
        z = position.z,
        heading = position.heading,
        health = math.floor(clamp(finite(profile.health) or Cfg.PED.default_health, 0, 200)),
        armour = math.floor(clamp(finite(profile.armour) or Cfg.PED.default_armour, 0, 100)),
    }
    if authorize then
        _ledger[src] = {
            teleport_until = now + Cfg.PED.mutation_ledger_ms,
            position = position,
            health = _observed[src].health,
            health_until = now + Cfg.PED.mutation_ledger_ms,
            armour = _observed[src].armour,
            armour_until = now + Cfg.PED.mutation_ledger_ms,
        }
    end
end

local function creation_complete(src)
    local ok, result = pcall(function() return exports.vhub:getSimsCreation(src) end)
    return ok and type(result) == 'table' and result.ok == true and result.created == true
end

local function login_gate_step(src)
    if GetResourceState('vhub_login') ~= 'started' then return nil end
    local ok, step = pcall(function() return exports.vhub_login:getSessionStep(src) end)
    if not ok then return 'indisponivel' end
    if step == 'ready' then return nil end
    return type(step) == 'string' and step or nil
end

local function release_spawn(src, position, first_spawn)
    local char_id = resolve_online(src)
    if not char_id then return false end
    if first_spawn == true and not creation_complete(src) then
        if Logger then
            Logger('warn', 'Release de personagem incompleto bloqueado.', {
                src = src,
                char_id = char_id,
            })
        end
        return false
    end
    _pending[src] = nil
    _customization_stages[src] = nil
    _ended_stage_tokens[src] = nil
    -- Libera qualquer bucket exclusivo (criação) de volta ao pool e leva ao mundo.
    if not Buckets.end_activity(src, true) then Buckets.world(src) end
    local destination = valid_position(position)
    if destination then
        local profile = profile_for(src, char_id)
        seed_baseline(src, profile, destination, true)
    end
    _suspended[src] = nil
    _dead[src] = nil
    TriggerClientEvent(VHubHSS.E.PED_RELEASE, src, destination, first_spawn == true)
    return true
end

local function automatic_release(src, position, first_spawn, reason)
    local gate_step = login_gate_step(src)
    if gate_step then
        if Logger then
            Logger('error', 'Release automático bloqueado pelo gate.', {
                src = src,
                step = gate_step,
                reason = reason,
            })
        end
        DropPlayer(tostring(src), 'Fluxo de entrada indisponível. Reconecte.')
        return false
    end
    return release_spawn(src, position, first_spawn)
end

local function schedule_pending_timeout(src, pending)
    _pending_generation = _pending_generation + 1
    pending.token = _pending_generation
    local token = pending.token
    SetTimeout(Cfg.PED.selector_timeout_ms, function()
        local current = _pending[src]
        if current and current.token == token and not _customization_stages[src] then
            automatic_release(src, effective_position(profile_for(src, current.char_id)),
                current.first_spawn, 'pending_timeout')
        end
    end)
end

local function stage_position()
    local position = Cfg.PED.customization_stage
    return {
        x = finite(position.x) or 402.60,
        y = finite(position.y) or -997.20,
        z = finite(position.z) or -98.30,
        heading = finite(position.w) or 180.0,
    }
end

-- Posição de fallback (void subterrâneo) quando a cena do interior não carrega no cliente.
local function stage_void()
    local position = Cfg.PED.customization_void
    return {
        x = finite(position and position.x) or 402.60,
        y = finite(position and position.y) or -997.20,
        z = finite(position and position.z) or -98.30,
        heading = finite(position and position.w) or 180.0,
    }
end

local function valid_session_id(value)
    return type(value) == 'string'
        and #value >= 8
        and #value <= 96
        and value:match('^[a-zA-Z0-9:_%-]+$') ~= nil
end

local function owned_player_ped(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    local ok, owner = pcall(NetworkGetEntityOwner, ped)
    return ok and tonumber(owner) == src and ped or nil
end

local function move_owned_ped(src, ped, destination)
    if not ped or owned_player_ped(src) ~= ped then return false end
    -- O move é INTENÇÃO autoritativa do servidor; quem conclui o reposicionamento de fato é
    -- o cliente dono do ped (VHubHSS_MovePed no evento de estágio). Sob o gate de login o ped
    -- está congelado (FreezeEntityPosition client-side), então SetEntityCoords server-side não
    -- reloca e a leitura de volta permaneceria na origem — uma conferência estrita de distância
    -- aqui daria falso 'native' e travava a criação. Confirma posse (L-16) e emite a coordenada;
    -- a aterrissagem física é responsabilidade do cliente e conferida lá.
    local moved = pcall(function()
        SetEntityCoords(
            ped,
            destination.x,
            destination.y,
            destination.z,
            false,
            false,
            false,
            false
        )
        SetEntityHeading(ped, destination.heading)
    end)
    return moved and owned_player_ped(src) == ped
end

local function begin_pending_stage(src, session_id)
    if not customization_invoker_ok() then return { ok = false, err = 'forbidden' } end
    src = tonumber(src)
    if not src or not GetPlayerName(src) then return { ok = false, err = 'offline' } end
    if not valid_session_id(session_id) then return { ok = false, err = 'conflict' } end
    local char_id = resolve_online(src)
    if not char_id then return { ok = false, err = 'offline' } end
    local pending = _pending[src]
    -- Self-heal do hold físico: char selecionado, mas o pending não está (re)ancorado.
    -- Ocorre no gate de login em retry/reseleção, ou quando um release intermediário
    -- (releaseCreationHold após falha anterior) limpou o pending. O SIMS só chega aqui
    -- em handoff legítimo — invoker (CUSTOMIZATION_TRUSTED) e session_id já validados
    -- acima. Reancorar aqui elimina o not_pending terminal, que caía em "algo deu errado"
    -- na NUI (código não mapeado) e travava a criação.
    if not pending or pending.char_id ~= char_id then
        _pending_generation = _pending_generation + 1
        pending = {
            token = _pending_generation,
            char_id = char_id,
            first_spawn = not creation_complete(src),
        }
        _pending[src] = pending
    end
    _creation_hold[src] = nil

    local current = _customization_stages[src]
    if current then
        if current.char_id == char_id and current.session_id == session_id then
            return { ok = true, stage_token = current.stage_token }
        end
        -- estágio de personagem anterior do mesmo src = resíduo → limpar e prosseguir;
        -- mesmo char com sessão distinta = concorrência real → conflito.
        if current.char_id == char_id then return { ok = false, err = 'conflict' } end
        _customization_stages[src] = nil
    end
    -- load físico do char recém-selecionado ainda em voo (assíncrono) → transitório, NÃO conflito;
    -- o consumidor (SIMS) reespera. Conflito só para colisão real acima.
    if not State or not State.is_loaded(char_id) then return { ok = false, err = 'not_ready' } end
    if not Buckets.begin_creation(src) then
        if Logger then Logger('warn', 'beginPendingStage: Buckets.begin_creation falhou.', { src = src, char_id = char_id }) end
        return { ok = false, err = 'native' }
    end
    local ped = owned_player_ped(src)
    if not ped then
        if Logger then Logger('warn', 'beginPendingStage: ped ausente/não possuído pelo src.', { src = src, char_id = char_id }) end
        return { ok = false, err = 'native' }
    end

    _stage_generation = _stage_generation + 1
    local stage_token = ('stage:%d:%d:%d'):format(char_id, _stage_generation, GetGameTimer())
    local destination = stage_position()
    if not move_owned_ped(src, ped, destination) then
        if Logger then Logger('warn', 'beginPendingStage: move_owned_ped falhou (posse perdida).', { src = src, char_id = char_id }) end
        return { ok = false, err = 'native' }
    end

    _pending_generation = _pending_generation + 1
    pending.token = _pending_generation

    _ended_stage_tokens[src] = nil
    _customization_stages[src] = {
        char_id = char_id,
        session_id = session_id,
        stage_token = stage_token,
    }
    TriggerClientEvent(VHubHSS.E.CUSTOMIZATION_STAGE_BEGIN, src, {
        position = destination,
        ipl = Cfg.PED.customization_ipl,
        fallback = stage_void(),
        customization = profile_for(src, char_id).customization,
    })
    return { ok = true, stage_token = stage_token }
end

local function end_pending_stage(src, stage_token)
    if not customization_invoker_ok() then return { ok = false, err = 'forbidden' } end
    src = tonumber(src)
    if not src or not GetPlayerName(src) then return { ok = false, err = 'offline' } end
    if type(stage_token) ~= 'string' or #stage_token > 128 then
        return { ok = false, err = 'invalid_token' }
    end
    if _ended_stage_tokens[src] == stage_token then return { ok = true, replayed = true } end

    local char_id = resolve_online(src)
    local stage = _customization_stages[src]
    if not char_id then return { ok = false, err = 'offline' } end
    if not stage or stage.char_id ~= char_id or stage.stage_token ~= stage_token then
        return { ok = false, err = 'invalid_token' }
    end
    local pending = _pending[src]
    if not pending or pending.char_id ~= char_id then return { ok = false, err = 'conflict' } end
    local profile = profile_for(src, char_id)
    local destination = effective_position(profile)
    if not Buckets.begin_creation(src) then
        return { ok = false, err = 'native' }
    end
    local ped = owned_player_ped(src)
    if not move_owned_ped(src, ped, destination) then return { ok = false, err = 'native' } end

    _customization_stages[src] = nil
    _ended_stage_tokens[src] = stage_token
    schedule_pending_timeout(src, pending)
    TriggerClientEvent(VHubHSS.E.CUSTOMIZATION_STAGE_END, src, {
        position = destination,
        customization = profile.customization,
    })
    return { ok = true, replayed = false }
end

-- Aplica spawn idempotente a partir do evento institucional do CORE.
function Ped.handle_spawn(user, first_spawn)
    if type(user) ~= 'table' then return false end
    local src = tonumber(user.source)
    local char_id = src and resolve_online(src) or nil
    if not char_id or tonumber(user.char_id) ~= char_id then return false end

    local spawns = math.max(0, tonumber(user.spawns) or 0)
    local seen = _spawn_seen[src]
    if seen and seen.char_id == char_id and seen.spawns == spawns then return true end
    if _active_char[src] and _active_char[src] ~= char_id then
        _pending[src] = nil
        _observed[src] = nil
        _ledger[src] = nil
        if not Buckets.is_creation(src) then Buckets.end_activity(src, true) end
    end
    _active_char[src] = char_id
    _revive_generation[src] = (_revive_generation[src] or 0) + 1
    _model_override[src] = nil
    _suspended[src] = nil
    _dead[src] = nil
    _spawn_seen[src] = { char_id = char_id, spawns = spawns }

    local profile = profile_for(src, char_id)
    local position = effective_position(profile)
    local select_spawn = Cfg.PED.selector_enabled
        and GetResourceState('vhub_spawselector') == 'started'
        and (Cfg.PED.selector_mode == 'always' or spawns <= 1)
    -- hold explícito de criação (vhub_login chamou holdForCreation antes de selectCore).
    local creation_hold = _creation_hold[src] == true
    local gate_step = login_gate_step(src)
    local isolate = select_spawn or creation_hold or gate_step ~= nil

    if isolate then
        if not Buckets.begin_creation(src) then return false end
    else
        Buckets.world(src)
    end
    seed_baseline(src, profile, position, true)
    TriggerClientEvent(VHubHSS.E.PED_APPLY, src, {
        position = position,
        hold = select_spawn or creation_hold or gate_step ~= nil,
        health = profile.health,
        armour = profile.armour,
        customization = profile.customization,
        first_spawn = first_spawn == true,
    })

    if select_spawn or creation_hold then
        _pending_generation = _pending_generation + 1
        local token = _pending_generation
        _pending[src] = {
            token = token,
            char_id = char_id,
            first_spawn = first_spawn == true,
        }
        if select_spawn then
            TriggerEvent(VHubHSS.E.SPAWN_CHOOSE, src)
        end
        SetTimeout(Cfg.PED.selector_timeout_ms, function()
            local pending = _pending[src]
            if pending and pending.token == token then
                automatic_release(src, position, pending.first_spawn, 'selector_timeout')
            end
        end)
    end

    if Logger then
        Logger('info', 'Spawn aplicado.', {
            src = src,
            char_id = char_id,
            first_spawn = first_spawn == true,
            selector = select_spawn,
            creation_hold = creation_hold,
        })
    end
    return true
end


-- ============================================================
-- OBSERVAÇÃO FÍSICA
-- ============================================================

local function distance(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function rollback_position(src, previous)
    local ped = owned_player_ped(src)
    if ped then
        move_owned_ped(src, ped, {
            x = previous.x,
            y = previous.y,
            z = previous.z,
            heading = previous.heading or 0.0,
        })
    end
    TriggerClientEvent(
        VHubHSS.E.PED_TELEPORT,
        src,
        previous.x,
        previous.y,
        previous.z,
        previous.heading or 0.0
    )
end

local function rollback_health(src, value)
    local ped = GetPlayerPed(src)
    if ped and ped ~= 0 and DoesEntityExist(ped) then pcall(SetEntityHealth, ped, value) end
    TriggerClientEvent(VHubHSS.E.PED_SET_HEALTH, src, value)
end

local function rollback_armour(src, value)
    local ped = GetPlayerPed(src)
    if ped and ped ~= 0 and DoesEntityExist(ped) then pcall(SetPedArmour, ped, value) end
    TriggerClientEvent(VHubHSS.E.PED_SET_ARMOUR, src, value)
end

-- Consome snapshot server-side, persiste deltas válidos e reverte mutações ilegítimas.
function Ped.observe(src, char_id, sample)
    if resolve_online(src) ~= char_id
        or type(sample) ~= 'table'
        or _pending[src]
        or (_suspended[src] and not _dead[src]) then
        return
    end
    if _dead[src] then
        if sample.health > 0 then rollback_health(src, 0) end
        return
    end
    local profile = profile_for(src, char_id)
    if not _observed[src] then seed_baseline(src, profile, effective_position(profile), false) end
    local previous = _observed[src]
    local ledger = _ledger[src]
    local now = sample.at or GetGameTimer()
    if _movement_override[src] and _movement_override[src] < now then
        _movement_override[src] = nil
    end

    if sample.health <= 0 then
        report_physical_death(src)
        return
    end

    local model_override = _model_override[src]
    if model_override and not model_override.confirmed and model_override.expires_at < now then
        _model_override[src] = nil
        model_override = nil
    elseif model_override and tonumber(sample.model) == tonumber(model_override.hash) then
        model_override.confirmed = true
    end
    local model_name = profile.customization and profile.customization.model or Cfg.PED.default_model
    local expected_model = model_override and model_override.hash or joaat(model_name)
    if tonumber(sample.model) ~= tonumber(expected_model) and not model_override then
        pcall(SetPlayerModel, src, expected_model)
        TriggerClientEvent(VHubHSS.E.PED_SET_CUSTOMIZATION, src, profile.customization)
        return
    elseif tonumber(sample.model) ~= tonumber(expected_model) and model_override.confirmed then
        pcall(SetPlayerModel, src, expected_model)
        TriggerClientEvent(VHubHSS.E.PED_SET_MODEL, src, model_override.name)
        return
    end

    if previous then
        local dt = clamp((now - previous.at) / 1000.0, 0.05, 5.0)
        local speed_limit = sample.in_vehicle and Cfg.PED.max_vehicle_speed or Cfg.PED.max_foot_speed
        local dx, dy = sample.x - previous.x, sample.y - previous.y
        local horizontal = math.sqrt(dx * dx + dy * dy)
        local vertical = math.abs(sample.z - previous.z)
        local allowed_horizontal = speed_limit * dt + Cfg.PED.position_slack
        local allowed_vertical = Cfg.PED.max_vertical_speed * dt + Cfg.PED.position_slack
        local teleported = ledger and ledger.teleport_until and ledger.teleport_until >= now
            and ledger.position and distance(sample, ledger.position) <= Cfg.PED.teleport_tolerance
        local movement_allowed = (_movement_override[src] or 0) >= now
        local implausible = horizontal > allowed_horizontal or vertical > allowed_vertical
        if implausible and not teleported and not movement_allowed then
            rollback_position(src, previous)
            return
        end
    end

    local position = { x = sample.x, y = sample.y, z = sample.z }
    if State and State.is_loaded(char_id) then
        State.set_position(char_id, position, sample.heading)
    else
        set_volatile(char_id, 'position', position)
        set_volatile(char_id, 'heading', sample.heading)
    end

    local accepted_health = previous and previous.health or sample.health
    if not previous or sample.health <= previous.health
        or (ledger and ledger.health_until and ledger.health_until >= now and sample.health <= ledger.health) then
        accepted_health = math.floor(clamp(sample.health, 0, 200))
        if State and State.is_loaded(char_id) then
            State.set_health(char_id, accepted_health)
        else
            set_volatile(char_id, 'health', accepted_health)
        end
    else
        rollback_health(src, previous.health)
    end

    local accepted_armour = previous and previous.armour or sample.armour
    if not previous or sample.armour <= previous.armour
        or (ledger and ledger.armour_until and ledger.armour_until >= now and sample.armour <= ledger.armour) then
        accepted_armour = math.floor(clamp(sample.armour, 0, 100))
        if State and State.is_loaded(char_id) then
            State.set_armour(char_id, accepted_armour)
        else
            set_volatile(char_id, 'armour', accepted_armour)
        end
    else
        rollback_armour(src, previous.armour)
    end

    _observed[src] = {
        at = now,
        x = sample.x,
        y = sample.y,
        z = sample.z,
        heading = sample.heading,
        health = accepted_health,
        armour = accepted_armour,
    }
    if ledger and now > math.max(
        ledger.teleport_until or 0,
        ledger.health_until or 0,
        ledger.armour_until or 0
    ) then
        _ledger[src] = nil
    end
end


-- ============================================================
-- EXPORTS DE PED / BUCKET
-- ============================================================

local function export_spawn_at(src, position)
    if not ped_invoker_ok() then return false end
    src = tonumber(src)
    local pending = src and _pending[src] or nil
    local char_id = src and resolve_online(src) or nil
    if not pending or not Buckets.is_creation(src) or _customization_stages[src]
        or not char_id or pending.char_id ~= char_id then
        return false
    end
    if pending.first_spawn == true and not creation_complete(src) then return false end
    if State and not State.is_loaded(char_id) then
        local vpos = valid_position(position)
        pending.requested_position = vpos
        -- Escape/fechar sem escolha → position=nil → vpos=nil; flag para distinguir de
        -- "seletor ainda não respondeu" (ambos nil sem o flag → jogador presa no bucket 999).
        if vpos == nil then pending.escape_chosen = true end
        return true
    end
    local profile = profile_for(src, char_id)
    local destination = valid_position(position) or effective_position(profile)
    if State and State.is_loaded(char_id) then
        State.set_position(char_id, destination, destination.heading)
    else
        set_volatile(char_id, 'position', destination)
        set_volatile(char_id, 'heading', destination.heading)
    end
    return release_spawn(src, destination, pending.first_spawn)
end

local function export_give_weapons(src, weapons, clear_before)
    src = tonumber(src)
    if not ped_invoker_ok() or not src or not rate_ok('giveWeapons', src) then return false end
    if not resolve_online(src) or type(weapons) ~= 'table' then return false end
    local clean, count = {}, 0
    for name, spec in pairs(weapons) do
        if count >= 64 then break end
        if type(name) == 'string' and #name <= 64 and name:match('^WEAPON_[A-Z0-9_]+$') then
            clean[name] = { ammo = math.floor(clamp(finite(type(spec) == 'table' and spec.ammo) or 0, 0, 9999)) }
            count = count + 1
        end
    end
    if count == 0 and clear_before ~= true then return false end
    TriggerClientEvent(VHubHSS.E.PED_GIVE_WEAPONS, src, clean, clear_before == true)
    return true
end

local function export_set_health(src, amount)
    src = tonumber(src)
    if not ped_invoker_ok() or not src or not rate_ok('setHealth', src) then return false end
    local char_id, value = src and resolve_online(src), finite(amount)
    if not char_id or not value then return false end
    value = math.floor(clamp(value, 0, 200))
    if _dead[src] and value > 0 then return false end
    local before = profile_for(src, char_id)
    if State and State.is_loaded(char_id) then
        State.set_health(char_id, value)
    else
        set_volatile(char_id, 'health', value)
    end
    _ledger[src] = _ledger[src] or {}
    _ledger[src].health = value
    _ledger[src].health_until = GetGameTimer() + Cfg.PED.mutation_ledger_ms
    TriggerClientEvent(VHubHSS.E.PED_SET_HEALTH, src, value)
    audit(char_id, 'setHealth', before.health, value)
    return true
end

local function export_set_armour(src, amount)
    src = tonumber(src)
    if not ped_invoker_ok() or not src or not rate_ok('setArmour', src) then return false end
    local char_id, value = src and resolve_online(src), finite(amount)
    if not char_id or not value then return false end
    value = math.floor(clamp(value, 0, 100))
    local before = profile_for(src, char_id)
    if State and State.is_loaded(char_id) then
        State.set_armour(char_id, value)
    else
        set_volatile(char_id, 'armour', value)
    end
    _ledger[src] = _ledger[src] or {}
    _ledger[src].armour = value
    _ledger[src].armour_until = GetGameTimer() + Cfg.PED.mutation_ledger_ms
    TriggerClientEvent(VHubHSS.E.PED_SET_ARMOUR, src, value)
    audit(char_id, 'setArmour', before.armour, value)
    return true
end

local function export_revive(src)
    src = tonumber(src)
    if not ped_invoker_ok() or not src or not rate_ok('revive', src) then return false end
    local char_id = src and resolve_online(src)
    local health = char_id and physical_health(src) or nil
    if not char_id or not health or _pending[src] then return false end
    local before = profile_for(src, char_id)
    local was_dead = _dead[src] == true or health <= 0
    if was_dead and not report_physical_death(src) then return false end
    if State and State.is_loaded(char_id) then
        State.set_health(char_id, Cfg.PED.default_health)
        State.set_armour(char_id, 100)
    else
        set_volatile(char_id, 'health', Cfg.PED.default_health)
        set_volatile(char_id, 'armour', 100)
    end
    _ledger[src] = {
        health = Cfg.PED.default_health,
        health_until = GetGameTimer() + Cfg.PED.mutation_ledger_ms,
        armour = 100,
        armour_until = GetGameTimer() + Cfg.PED.mutation_ledger_ms,
    }
    if was_dead then
        TriggerClientEvent(VHubHSS.E.PED_REVIVE, src)
        schedule_respawn_confirmation(src, char_id)
    else
        TriggerClientEvent(VHubHSS.E.PED_SET_HEALTH, src, Cfg.PED.default_health)
        TriggerClientEvent(VHubHSS.E.PED_SET_ARMOUR, src, 100)
    end
    audit(char_id, 'revive', before, profile_for(src, char_id))
    return true
end

local function export_set_customization(src, customization)
    src = tonumber(src)
    if not ped_invoker_ok() or not src or not rate_ok('setCustomization', src) then return false end
    local char_id = src and resolve_online(src)
    if not char_id or type(customization) ~= 'table' then return false end
    _model_override[src] = nil
    local before = profile_for(src, char_id).customization
    local clean = clean_custom(customization)
    if State and State.is_loaded(char_id) then
        if not State.set_customization(char_id, clean) then return false end
    else
        set_volatile(char_id, 'customization', clean)
    end
    TriggerClientEvent(VHubHSS.E.PED_SET_CUSTOMIZATION, src, clean)
    audit(char_id, 'setCustomization', before, clean)
    return true
end

local function export_teleport(src, x, y, z, heading)
    src = tonumber(src)
    if not ped_invoker_ok() or not src or not rate_ok('teleport', src) then return false end
    local char_id = src and resolve_online(src)
    local destination = valid_position({ x = x, y = y, z = z, heading = heading })
    if not char_id or not destination then return false end
    local before = profile_for(src, char_id).position
    if State and State.is_loaded(char_id) then
        State.set_position(char_id, destination, destination.heading)
    else
        set_volatile(char_id, 'position', destination)
        set_volatile(char_id, 'heading', destination.heading)
    end
    _ledger[src] = _ledger[src] or {}
    _ledger[src].teleport_until = GetGameTimer() + Cfg.PED.mutation_ledger_ms
    _ledger[src].position = destination
    TriggerClientEvent(VHubHSS.E.PED_TELEPORT, src, x, y, z, destination.heading)
    audit(char_id, 'teleport', before, destination)
    return true
end

exports('holdForCreation', function(src)
    if not creation_invoker_ok() then return false end
    src = tonumber(src)
    if not src or not GetPlayerName(src) then return false end
    _creation_hold[src] = true
    return true
end)
-- Subinstancia exclusiva do gate autenticado. O bucket 999 permanece como entrada-base;
-- cada sessao ocupa temporariamente um bucket do pool privado 100..998.
exports('isolateEntrySession', function(src)
    if not creation_invoker_ok() then return nil end
    src = tonumber(src)
    if not src or not GetPlayerName(src) then return nil end
    return Buckets.begin_creation(src)
end)
exports('releaseEntrySession', function(src)
    if not creation_invoker_ok() then return false end
    src = tonumber(src)
    if not src or not GetPlayerName(src) then return false end
    return Buckets.begin_creation(src) ~= nil
end)
-- Libera o flag de criação, preservando pending e bucket privado até o selector concluir.
exports('releaseCreationHold', function(src)
    if not creation_invoker_ok() then return false end
    src = tonumber(src)
    if not src or not GetPlayerName(src) then return false end
    _creation_hold[src] = nil
    -- Limpa estágio que possa ter ficado preso em sessão anterior (evita 'conflict' na retentativa).
    _customization_stages[src] = nil
    _ended_stage_tokens[src] = nil
    local pending = _pending[src]
    if pending then
        -- Com o selector ATIVO, NÃO spawnar aqui: preserva _pending para o selector abrir
        -- (isPendingSpawn=true) e mover 999→1 via spawnAt no local ESCOLHIDO. Spawnar direto
        -- consumiria o pending e o selector nunca abriria (o player caía na posição salva).
        -- Sem selector, falha fechado: o gate mantém o jogador isolado e retorna erro.
        local selector_ready = Cfg.PED.selector_enabled
            and GetResourceState('vhub_spawselector') == 'started'
        if not selector_ready then return false end
    end
    return Buckets.begin_creation(src) ~= nil
end)
exports('spawnAt', export_spawn_at)
exports('beginPendingStage', begin_pending_stage)
exports('endPendingStage', end_pending_stage)
exports('isPendingSpawn', function(src)
    if not ped_invoker_ok() then return false end
    src = tonumber(src)
    return src ~= nil and _pending[src] ~= nil and Buckets.is_creation(src)
end)
exports('beginActivity', function(src)
    if not activity_invoker_ok() then return nil end
    return Buckets.begin_activity(src)
end)
exports('attachActivityVehicle', function(src, entity)
    if not activity_invoker_ok() then return false end
    return Buckets.attach_vehicle(src, entity)
end)
exports('endActivity', function(src)
    if not activity_invoker_ok() then return false end
    return Buckets.end_activity(src, true)
end)
exports('giveWeapons', export_give_weapons)
exports('setArmour', export_set_armour)
exports('setHealth', export_set_health)
exports('revive', export_revive)
exports('setPedModel', function(src, model)
    src = tonumber(src)
    if not ped_invoker_ok() or not src or not rate_ok('setPedModel', src)
        or not valid_model_name(model) then
        return false
    end
    model = model:lower()
    local char_id = resolve_online(src)
    if not char_id or _pending[src] or _dead[src] then return false end
    _model_override[src] = {
        name = model,
        hash = joaat(model),
        expires_at = GetGameTimer() + 5000,
        confirmed = false,
    }
    TriggerClientEvent(VHubHSS.E.PED_SET_MODEL, src, model)
    audit(char_id, 'setPedModel', nil, { model = model, transient = true })
    return true
end)
exports('kill', function(src)
    src = tonumber(src)
    if not ped_invoker_ok() or not src or not rate_ok('kill', src) then return false end
    local char_id = src and resolve_online(src)
    if not char_id then return false end
    if State and State.is_loaded(char_id) then State.set_health(char_id, 0) else set_volatile(char_id, 'health', 0) end
    TriggerClientEvent(VHubHSS.E.PED_KILL, src)
    audit(char_id, 'kill', nil, 0)
    return true
end)
exports('setCustomization', export_set_customization)
exports('teleport', export_teleport)
exports('getPosition', function(src)
    if not ped_invoker_ok() and GetInvokingResource() ~= 'vhub_sims' then return 0, 0, 0 end
    src = tonumber(src)
    local char_id = src and resolve_online(src)
    local profile = char_id and profile_for(src, char_id) or nil
    local position = profile and profile.position
    if not position then return 0, 0, 0 end
    return position.x, position.y, position.z
end)
exports('setMovementOverride', function(src, active)
    if GetInvokingResource() ~= 'vhub_admin' then return false end
    src = tonumber(src)
    if type(active) ~= 'boolean' or not src or not resolve_online(src) then return false end
    if active then
        _movement_override[src] = GetGameTimer() + 5000
    else
        _movement_override[src] = nil
        _observed[src] = nil
    end
    return true
end)
-- Autoriza uma transição geométrica validada pelo servidor da corrida.
exports('authorizePosition', function(src, position)
    if GetInvokingResource() ~= 'vhub_racha' then return false end
    src = tonumber(src)
    local destination = valid_position(position)
    if not src or not destination or not resolve_online(src) then return false end
    local now = GetGameTimer()
    _ledger[src] = _ledger[src] or {}
    _ledger[src].position = destination
    _ledger[src].teleport_until = now + Cfg.PED.mutation_ledger_ms
    return true
end)


-- ============================================================
-- LIFECYCLE
-- ============================================================

-- Injeta dependências mínimas; permanece operacional sem SQL/fisiologia.
function Ped.init(state_module, buckets_module, cfg, resolve_character, logger)
    State = state_module
    Buckets = buckets_module
    Cfg = cfg
    ResolveCharacter = resolve_character
    Logger = logger
end

-- Atualiza referência do estado após schema ficar disponível.
function Ped.set_state(state_module) State = state_module end

-- Invalida a geração física ao trocar o personagem canônico do slot.
function Ped.handle_character_load(user)
    if type(user) ~= 'table' then return false end
    local src, char_id = tonumber(user.source), tonumber(user.char_id)
    if not src or not char_id or ResolveCharacter(src) ~= char_id then return false end
    local previous_char = _active_char[src]
    if previous_char == char_id then
        -- Reancora o hold perdido no restart sem renovar um pending válido.
        if _creation_hold[src] ~= true then return true end
        local pending = _pending[src]
        if pending and pending.char_id == char_id then return true end
        if not Buckets.begin_creation(src) then return false end

        pending = {
            char_id = char_id,
            first_spawn = not creation_complete(src),
        }
        _pending[src] = pending
        _suspended[src] = true
        schedule_pending_timeout(src, pending)
        return true
    end

    _active_char[src] = char_id
    _revive_generation[src] = (_revive_generation[src] or 0) + 1
    _model_override[src] = nil
    _customization_stages[src] = nil
    _ended_stage_tokens[src] = nil
    _suspended[src] = true
    _dead[src] = nil
    _observed[src] = nil
    _ledger[src] = nil
    _movement_override[src] = nil
    if not Buckets.is_creation(src) then Buckets.end_activity(src, true) end

    -- Estabelece o hold físico SEMPRE que o player carrega um char ainda não spawnado:
    -- troca de personagem OU primeiro-char via gate de login. No primeiro-char o CORE já pôs
    -- o player no bucket 999 (boot.lua:198) SEM passar pelo handle_spawn, então o _pending do
    -- HSS ficaria vazio e o criador (beginPendingStage) devolveria not_pending. Aqui o owner
    -- complementa o hold que o CORE iniciou.
    local seen = _spawn_seen[src]
    local first_char_on_gate = previous_char == nil
        and (seen == nil or (tonumber(seen.spawns) or 0) == 0)
    if previous_char or first_char_on_gate then
        local pending = _pending[src]
        local first_spawn = not creation_complete(src)
        _pending_generation = _pending_generation + 1
        _pending[src] = {
            token = _pending_generation,
            char_id = char_id,
            first_spawn = first_spawn,
        }
        _spawn_seen[src] = {
            char_id = char_id,
            spawns = math.max(0, tonumber(user.spawns) or 0),
        }
        if not Buckets.begin_creation(src) then return false end
        -- No primeiro-char o CORE (boot.lua:203) já disparou chooseSpawn; não duplicar.
        if not pending and not first_char_on_gate then TriggerEvent(VHubHSS.E.SPAWN_CHOOSE, src) end
        local token = _pending_generation
        SetTimeout(Cfg.PED.selector_timeout_ms, function()
            local current = _pending[src]
            if current and current.token == token and current.char_id == ResolveCharacter(src) then
                automatic_release(src, effective_position(profile_for(src, current.char_id)),
                    current.first_spawn, 'character_load_timeout')
            end
        end)
    end
    return true
end

-- Reaplica o perfil carregado ou retoma monitoramento após restart do HSS.
function Ped.handle_profile_loaded(src, char_id)
    src, char_id = tonumber(src), tonumber(char_id)
    if not src or not char_id or ResolveCharacter(src) ~= char_id or _active_char[src] ~= char_id then
        return false
    end
    local profile = profile_for(src, char_id)
    local pending = _pending[src]
    if pending and pending.char_id == char_id then
        local position = valid_position(pending.requested_position) or effective_position(profile)
        -- "Ainda aguardando seletor" = requested_position nil E escape_chosen nil.
        -- Escape/fechar = escape_chosen=true → já tem posição (effective), spawnar imediato.
        local selector_pending = pending.requested_position == nil and not pending.escape_chosen
        TriggerClientEvent(VHubHSS.E.PED_APPLY, src, {
            position = position,
            hold = selector_pending,
            health = profile.health,
            armour = profile.armour,
            customization = profile.customization,
            first_spawn = pending.first_spawn == true,
        })
        if not selector_pending then
            if pending.first_spawn == true and not creation_complete(src) then return false end
            if State and State.is_loaded(char_id) then
                State.set_position(char_id, position, position.heading)
            end
            return release_spawn(src, position, pending.first_spawn)
        end
        local creation_hold = _creation_hold[src] == true
        if not creation_hold and GetResourceState('vhub_spawselector') ~= 'started' then
            automatic_release(src, position, pending.first_spawn, 'selector_unavailable')
        end
        return true
    end
    if _spawn_seen[src] and _spawn_seen[src].char_id == char_id then
        local snapshot = VHubHSS_Monitor and VHubHSS_Monitor.get(char_id) or nil
        local position = snapshot and valid_position(snapshot) or effective_position(profile)
        if snapshot then
            profile.health = snapshot.health
            profile.armour = snapshot.armour
        end
        seed_baseline(src, profile, position, false)
        _suspended[src] = nil
        return true
    end
    return false
end

-- Informa se a geração física ainda não pode ser monitorada.
function Ped.is_suspended(src)
    src = tonumber(src)
    return src == nil or _suspended[src] == true or _dead[src] == true
end

-- Semeia replay-guard no restart sem reaplicar estado físico ao jogador online.
function Ped.seed_spawn(src, char_id, spawns)
    src, char_id = tonumber(src), tonumber(char_id)
    if not src or not char_id or ResolveCharacter(src) ~= char_id then return false end
    _active_char[src] = char_id
    _suspended[src] = true
    _spawn_seen[src] = { char_id = char_id, spawns = math.max(0, tonumber(spawns) or 0) }
    return true
end

-- Invalida baselines físicos para que o próximo respawn crie nova geração.
function Ped.handle_death(src, char_id)
    src, char_id = tonumber(src), tonumber(char_id)
    if not src or ResolveCharacter(src) ~= char_id then return false end
    _pending[src] = nil
    _customization_stages[src] = nil
    _ended_stage_tokens[src] = nil
    _observed[src] = nil
    _ledger[src] = nil
    _movement_override[src] = nil
    _model_override[src] = nil
    _revive_generation[src] = (_revive_generation[src] or 0) + 1
    _suspended[src] = true
    _dead[src] = true
    Buckets.end_activity(src, true)
    Buckets.world(src)
    return true
end

-- Limpa caches efêmeros e atividade da origem.
function Ped.drop(src, known_char_id)
    src = tonumber(src)
    local char_id = tonumber(known_char_id) or (src and ResolveCharacter(src) or nil)
    _spawn_seen[src] = nil
    _pending[src] = nil
    _creation_hold[src] = nil
    _customization_stages[src] = nil
    _ended_stage_tokens[src] = nil
    _observed[src] = nil
    _ledger[src] = nil
    _movement_override[src] = nil
    _model_override[src] = nil
    _revive_generation[src] = nil
    _active_char[src] = nil
    _suspended[src] = nil
    _dead[src] = nil
    Buckets.drop(src)
    if char_id then _volatile[char_id] = nil end
    local suffix = ':' .. tostring(src)
    for key in pairs(_rate) do
        if key:sub(-#suffix) == suffix then _rate[key] = nil end
    end
end

-- Encerra holds de forma fail-safe; gate/char incompleto nunca são liberados no mundo.
function Ped.shutdown()
    for src, pending in pairs(_pending) do
        local stage = _customization_stages[src]
        if stage then
            local profile = profile_for(src, stage.char_id)
            local ped = owned_player_ped(src)
            if ped and profile then move_owned_ped(src, ped, effective_position(profile)) end
        end
        _pending[src] = nil
        _creation_hold[src] = nil
        _customization_stages[src] = nil
        _ended_stage_tokens[src] = nil
        if login_gate_step(src) or (pending.first_spawn == true and not creation_complete(src)) then
            DropPlayer(src, 'Serviço de personagem reiniciado. Reconecte.')
            Buckets.drop(src)
        else
            Buckets.world(src)
        end
    end
    Buckets.shutdown()
end
