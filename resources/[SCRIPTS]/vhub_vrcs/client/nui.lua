---@diagnostic disable: undefined-global, lowercase-global

-- client/nui.lua — comando /replays + ponte com o servidor (lista + download) +
--                  roteamento dos controles para o Player.

VRCS = VRCS or {}

local Cfg   = VRCS.Cfg
local Cache = VRCS.Cache
local P     = VRCS.Player

local open         = false
local pending_play = nil   -- rid aguardando download p/ tocar


-- ============================================================
-- ABRE / FECHA
-- ============================================================

local function open_list()
    SetNuiFocus(true, true)
    SendNUIMessage({ type = 'open', view = 'list', replays = {} })   -- lista chega do servidor
    TriggerServerEvent('vhub_vrcs:list')
    open = true
end

local function close_all()
    P.stop()
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'close' })
    open = false
    pending_play = nil
end

RegisterCommand((Cfg.VIEWER and Cfg.VIEWER.COMMAND) or 'replays', function()
    if open then close_all() else open_list() end
end, false)


-- ============================================================
-- RESPOSTAS DO SERVIDOR
-- ============================================================

-- lista de replays disponiveis (DB)
RegisterNetEvent('vhub_vrcs:list:result')
AddEventHandler('vhub_vrcs:list:result', function(rows)
    if not open then return end
    SendNUIMessage({ type = 'open', view = 'list', replays = rows or {} })
end)

-- .vhr baixado (string bruta) → cacheia e, se houver play pendente, toca
RegisterNetEvent('vhub_vrcs:fetch:result')
AddEventHandler('vhub_vrcs:fetch:result', function(rid, data)
    if type(data) ~= 'string' then
        if pending_play == rid then pending_play = nil end
        return
    end
    Cache.save_raw(rid, data)
    if pending_play == rid then
        pending_play = nil
        local replay = Cache.get(rid)
        if replay and P.start(replay) then
            SendNUIMessage({ type = 'view', view = 'player' })
        end
    end
end)


-- ============================================================
-- CALLBACKS DA NUI
-- ============================================================

-- play: usa o cache local; se nao tiver, baixa do servidor (download sob demanda)
RegisterNUICallback('play', function(data, cb)
    local rid = data and data.raceId
    if type(rid) ~= 'string' then cb({ ok = false }); return end

    local replay = Cache.get(rid)
    if replay then
        if P.start(replay) then SendNUIMessage({ type = 'view', view = 'player' }) end
    else
        pending_play = rid
        TriggerServerEvent('vhub_vrcs:fetch', rid)
    end
    cb({ ok = true })
end)

-- controles de reproducao
RegisterNUICallback('control', function(data, cb)
    local a = data and data.action
    if     a == 'toggle' then P.toggle()
    elseif a == 'play'   then P.play()
    elseif a == 'pause'  then P.pause()
    elseif a == 'seek'   then P.seek(data.value)
    elseif a == 'speed'  then P.set_speed(data.value)
    elseif a == 'focus'  then P.focus(data.delta)
    elseif a == 'cam'    then P.cam_cycle()
    elseif a == 'back'   then
        P.stop()
        SendNUIMessage({ type = 'view', view = 'list' })
        TriggerServerEvent('vhub_vrcs:list')
    end
    cb({ ok = true })
end)

-- fecha o painel
RegisterNUICallback('close', function(_, cb)
    close_all()
    cb({ ok = true })
end)
