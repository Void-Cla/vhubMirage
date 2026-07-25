-- server/monitor.lua — amostragem física server-side compartilhada do HSS

VHubHSS_Monitor = {}
local Monitor = VHubHSS_Monitor

local Cfg = nil
local ResolveCharacter = nil
local Observer = nil
local Logger = nil

local _slots = {}
local _by_src = {}
local _snapshots = {}
local _running = false
local _generation = 0
local _last_error_at = 0


-- ============================================================
-- AMOSTRAGEM
-- ============================================================

local function sample(src, char_id)
    if ResolveCharacter(src) ~= char_id then return nil end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    local coords = GetEntityCoords(ped)
    local vehicle = GetVehiclePedIsIn(ped, false)
    local mover = vehicle and vehicle ~= 0 and vehicle or ped
    return {
        at = GetGameTimer(),
        x = coords.x,
        y = coords.y,
        z = coords.z,
        heading = GetEntityHeading(ped),
        health = math.max(0, tonumber(GetEntityHealth(ped)) or 0),
        armour = math.max(0, tonumber(GetPedArmour(ped)) or 0),
        model = GetEntityModel(ped),
        vehicle = vehicle or 0,
        in_vehicle = vehicle ~= nil and vehicle ~= 0,
        speed = math.max(0.0, tonumber(GetEntitySpeed(mover)) or 0.0),
    }
end

local function tick_slot(slot)
    local src, char_id = slot.src, slot.char_id
    if not GetPlayerName(src) or ResolveCharacter(src) ~= char_id then
        Monitor.remove(src)
        return
    end
    local snapshot = sample(src, char_id)
    if not snapshot then return end
    _snapshots[char_id] = snapshot
    if Observer then Observer(src, char_id, snapshot) end
end


-- ============================================================
-- API
-- ============================================================

-- Injeta dependências e inicia monitor permanente em 1 Hz por jogador.
function Monitor.init(cfg, resolve_character, observer, logger)
    Cfg = cfg
    ResolveCharacter = resolve_character
    Observer = observer
    Logger = logger
    Monitor.start()
end

-- Registra ou troca a sessão monitorada idempotentemente.
function Monitor.add(src, char_id)
    src, char_id = tonumber(src), tonumber(char_id)
    if not src or not char_id then return false end
    local slot = _by_src[src]
    if slot then
        if slot.char_id ~= char_id then _snapshots[slot.char_id] = nil end
        slot.char_id = char_id
        return true
    end
    slot = { src = src, char_id = char_id }
    _by_src[src] = slot
    _slots[#_slots + 1] = slot
    return true
end

-- Remove sessão e snapshot físico associado.
function Monitor.remove(src)
    src = tonumber(src)
    local slot = src and _by_src[src] or nil
    if not slot then return false end
    _by_src[src] = nil
    _snapshots[slot.char_id] = nil
    for index, current in ipairs(_slots) do
        if current == slot then
            table.remove(_slots, index)
            break
        end
    end
    return true
end

-- Retorna snapshot compartilhado somente para módulos internos.
function Monitor.get(char_id) return _snapshots[tonumber(char_id)] end

-- Inicia scheduler em lotes de 16 com uma amostra por jogador/segundo.
function Monitor.start()
    if _running then return end
    _running = true
    _generation = _generation + 1
    local generation = _generation
    Citizen.CreateThread(function()
        while _running and generation == _generation do
            local period = math.max(250, math.floor(1000 / math.max(1, Cfg.PED.monitor_hz)))
            if #_slots == 0 then
                Citizen.Wait(period)
            else
                local cycle_at = GetGameTimer()
                local batch = {}
                for index, slot in ipairs(_slots) do batch[index] = slot end
                for index, slot in ipairs(batch) do
                    if _by_src[slot.src] == slot then
                        local ok, err = pcall(tick_slot, slot)
                        local now = GetGameTimer()
                        if not ok and Logger and (now - _last_error_at) >= 5000 then
                            _last_error_at = now
                            Logger('error', 'Falha isolada no monitor físico.', {
                                src = slot.src,
                                error = tostring(err),
                            })
                        end
                    end
                    if index % 16 == 0 then Citizen.Wait(0) end
                end
                Citizen.Wait(math.max(1, period - (GetGameTimer() - cycle_at)))
            end
        end
    end)
end

-- Encerra scheduler sem loop órfão.
function Monitor.stop()
    _running = false
    _generation = _generation + 1
    _slots = {}
    _by_src = {}
    _snapshots = {}
end
