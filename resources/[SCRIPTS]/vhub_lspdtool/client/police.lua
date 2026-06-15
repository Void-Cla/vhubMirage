-- police.lua — experiência do policial no cliente (camada L2/HAL)
-- Recebe alertas de BOLO → notificação nativa (thefeed) + blip temporário + som, e a
-- notificação simples (NOTIFY) do servidor. O radar NATIVO vive em `client/radar.lua`.
-- Não decide verdade crítica: o servidor já validou que este player é policial.

local cfg = VHubLspd.cfg
local E   = VHubLspd.E


-- ============================================================
-- NOTIFICAÇÃO NATIVA (thefeed)
-- ============================================================

-- exibe uma mensagem simples no feed do GTA
local function thefeed(msg)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(tostring(msg or ''))
    EndTextCommandThefeedPostTicker(false, true)
end

RegisterNetEvent(E.NOTIFY, function(msg) thefeed(msg) end)


-- ============================================================
-- ALERTA DE BOLO (blip temporário + som)
-- ============================================================

local _blips = {}  -- handles de blip ativos (UI efêmera; não é estado crítico)


-- remove os blips mais antigos que excederem o teto configurado
local function enforceBlipCap()
    while #_blips > cfg.alert.maxBlips do
        local h = table.remove(_blips, 1)
        if DoesBlipExist(h) then RemoveBlip(h) end
    end
end


-- cria um blip temporário nas coords do BOLO e agenda sua remoção
local function spawnAlertBlip(coords)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, cfg.alert.blipSprite)
    SetBlipColour(blip, cfg.alert.blipColour)
    SetBlipScale(blip, cfg.alert.blipScale + 0.0)
    SetBlipFlashes(blip, true)
    SetBlipAsShortRange(blip, false)

    _blips[#_blips + 1] = blip
    enforceBlipCap()

    Citizen.SetTimeout(cfg.alert.blipDurationMs, function()
        if DoesBlipExist(blip) then RemoveBlip(blip) end
        for i, h in ipairs(_blips) do
            if h == blip then table.remove(_blips, i); break end
        end
    end)
end


-- recebe o alerta direcionado do servidor (já validado como policial em serviço)
RegisterNetEvent(E.BOLO_ALERT, function(data)
    if type(data) ~= 'table' or type(data.coords) ~= 'table' then return end

    thefeed(cfg.alert.buildMessage({
        plate  = data.plate,
        reason = data.reason,
        level  = data.level,
        kind   = data.kind,
    }))

    PlaySoundFrontend(-1, cfg.alert.sound.name, cfg.alert.sound.set, true)

    spawnAlertBlip(data.coords)
end)


-- ============================================================
-- ALERTA DE PROCURADO (pessoa) — dispatch dirigido às unidades
-- ============================================================

-- recebe o alerta de novo mandado (só policiais recebem este evento)
RegisterNetEvent(E.WANTED_ALERT, function(data)
    if type(data) ~= 'table' then return end
    thefeed(('~r~PROCURADO~s~ — ~y~%s~s~ (%s): %s'):format(
        tostring(data.name ~= '' and data.name or ('char ' .. tostring(data.char_id))),
        tostring(VHubLspd.cfg.wanted.levels[data.level] or 'Procurado'),
        tostring(data.reason or 'sinalizado')))
    PlaySoundFrontend(-1, cfg.alert.sound.name, cfg.alert.sound.set, true)
end)


-- ============================================================
-- CLEANUP
-- ============================================================

-- remove blips órfãos ao parar o resource
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, h in ipairs(_blips) do
        if DoesBlipExist(h) then RemoveBlip(h) end
    end
    _blips = {}
end)
