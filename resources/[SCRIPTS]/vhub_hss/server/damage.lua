-- server/damage.lua — dano validado pela réplica server-side compartilhada

VHubHSS_Damage = {}
local Damage = VHubHSS_Damage

local State = nil
local Cfg = nil
local _health = {}


-- ============================================================
-- HELPERS
-- ============================================================

local function apply_damage(src, char_id, delta)
    local damage = Cfg.DAMAGE
    local before = State.snapshot(char_id)
    State.mutate(char_id, 'pain', delta * damage.pain_per_health)
    State.mutate(char_id, 'stress', delta * damage.stress_per_health)
    State.mutate(char_id, 'adrenaline', delta * damage.adrenaline_per_health)
    State.mutate_trauma(char_id, delta * damage.trauma_per_health)

    if delta >= damage.bleed_level_2 then
        State.mutate(char_id, 'bleeding', 2)
    elseif delta >= damage.bleed_level_1 then
        State.mutate(char_id, 'bleeding', 1)
    end

    TriggerEvent(VHubHSS.E.STATE_CHANGED, char_id, {
        reason = 'damage',
        source = src,
        health_delta = delta,
        before = before,
        after = State.snapshot(char_id),
        at = os.time(),
    })
end


-- ============================================================
-- API
-- ============================================================

-- Injeta estado e configuração do domínio.
function Damage.init(state_module, cfg)
    State = state_module
    Cfg = cfg
end

-- Limpa baseline para a próxima réplica canônica da sessão.
function Damage.register(src, char_id)
    src, char_id = tonumber(src), tonumber(char_id)
    if src and char_id then _health[src] = { char_id = char_id, value = nil } end
end

-- Consome queda de vida observada pelo monitor; curas apenas renovam baseline.
function Damage.observe(src, char_id, health)
    src, char_id, health = tonumber(src), tonumber(char_id), tonumber(health)
    if not src or not char_id or not health or not State.is_loaded(char_id) then return end
    local baseline = _health[src]
    if not baseline or baseline.char_id ~= char_id or baseline.value == nil then
        _health[src] = { char_id = char_id, value = health }
        return
    end

    local delta = baseline.value - health
    baseline.value = health
    if delta <= 0 then return end
    apply_damage(src, char_id, math.min(delta, Cfg.DAMAGE.max_health_delta))
end

-- Limpa baseline da sessão encerrada.
function Damage.unregister(src)
    _health[tonumber(src)] = nil
end
