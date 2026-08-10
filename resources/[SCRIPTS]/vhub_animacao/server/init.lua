-- server/init.lua — comandos de emote com validações server-side
---@diagnostic disable: undefined-global

local E       = VHubAnimacao.E
local Catalog = VHubAnimacao.Cfg.CATALOG
local Adv     = VHubAnimacao.Cfg.ADVANTAGE


-- ============================================================
-- HELPERS
-- ============================================================

local function notify(src, kind, msg)
    pcall(function()
        TriggerClientEvent('vHub:notify', src, kind, msg)
    end)
end

-- Retorna bloqueios do HSS via export gated; falha silenciosa (soft-dep).
local function get_hss_blocks(src)
    local ok, result = pcall(function()
        return exports.vhub_hss:getAnimBlocks(src)
    end)
    if ok and type(result) == 'table' then return result end
    return { handcuffed = false, unconscious = false, weapon_drawn = false }
end


-- ============================================================
-- COMANDOS
-- ============================================================

-- Reproduz ou cancela emote; src=0 bloqueado (console).
RegisterCommand('e', function(src, args)
    if not src or src == 0 then return end
    local nome = args and args[1]

    if not nome or nome == '' then
        TriggerClientEvent(E.STOP_EMOTE, src)
        return
    end

    local entry = Catalog[nome]
    if not entry then
        notify(src, 'error', 'Emote desconhecido: /' .. tostring(nome))
        return
    end

    local ped = GetPlayerPed(src)
    if DoesEntityExist(ped) then
        local in_vehicle = IsPedInAnyVehicle(ped, false)
        if entry.carros and not in_vehicle then
            notify(src, 'error', 'Este emote só pode ser usado dentro de um veículo.')
            return
        end
        if not entry.carros and in_vehicle then
            notify(src, 'error', 'Saia do veículo para usar este emote.')
            return
        end
    end

    local blocks = get_hss_blocks(src)

    if blocks.handcuffed or blocks.unconscious then
        notify(src, 'error', 'Você não pode usar animações agora.')
        return
    end

    if blocks.weapon_drawn and Adv[nome] then
        notify(src, 'error', 'Guarde a arma antes de usar este emote.')
        return
    end

    TriggerClientEvent(E.PLAY_EMOTE, src, nome)
end, false)

-- Cancela emote atual do player.
RegisterCommand('cancelar', function(src)
    if not src or src == 0 then return end
    TriggerClientEvent(E.STOP_EMOTE, src)
end, false)


-- ============================================================
-- SENTAR — force-stand quando HSS bloqueia (algemado, desmaiado)
-- ============================================================

-- Força o cliente a levantar quando o estado HSS impede sentar.
-- Chamado pelo próprio HSS via export ou internamente ao detectar bloqueio.
exports('sitForceStand', function(src)
    if not src or src == 0 then return end
    TriggerClientEvent(E.SIT_FORCE_STAND, src)
end)
