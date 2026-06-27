---@diagnostic disable: undefined-global, lowercase-global

-- client/player.lua — engine de playback do .vhr in-game (L2 HAL).
--
-- Reproduz a corrida com carros-fantasma (entidades LOCAIS, nao em rede),
-- interpolando entre as amostras de 20Hz, com camera de perseguicao no piloto
-- em foco. Controles vem da NUI. Cleanup garantido no stop/onResourceStop (A-07).

VRCS = VRCS or {}

local Cfg = VRCS.Cfg
local Log = VRCS.Log

local P = {}; VRCS.Player = P

local V = {
    active   = false,
    replay   = nil,
    ghosts   = {},          -- { veh, frames, cursor, charId, label }
    focus    = 1,
    playing  = false,
    speed    = 1.0,
    playhead = 0.0,         -- segundos
    dur      = 0.0,
    cam      = nil,
    cam_mode = 'chase',
    origin   = nil,
    origin_h = 0.0,
    thread   = false,
    last_push = 0,
}

local function vcfg() return Cfg.VIEWER or {} end

local CAM_MODES = { 'chase', 'orbit', 'side', 'front', 'drone' }


-- ============================================================
-- HELPERS
-- ============================================================

-- carrega o modelo do veiculo (por hash) com timeout; fallback se invalido
local function load_model(hash)
    hash = tonumber(hash) or 0
    if hash == 0 or not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then
        hash = GetHashKey('adder')
    end
    RequestModel(hash)
    local tries = 0
    while not HasModelLoaded(hash) and tries < 100 do Wait(10); tries = tries + 1 end
    return HasModelLoaded(hash) and hash or nil
end


-- aplica a customizacao persistida da placa ao carro-fantasma (mesma semantica do
-- applyCustomization do vhub_garage) — preserva cor/mods/rodas/neon/placa no replay.
local function apply_custom(veh, c, plate)
    if plate and plate ~= '' then SetVehicleNumberPlateText(veh, plate) end
    if type(c) ~= 'table' then return end
    SetVehicleModKit(veh, 0)
    if c.colours       then SetVehicleColours(veh, table.unpack(c.colours)) end
    if c.extra_colours then SetVehicleExtraColours(veh, table.unpack(c.extra_colours)) end
    if c.plate_index   then SetVehicleNumberPlateTextIndex(veh, c.plate_index) end
    if c.wheel_type    then SetVehicleWheelType(veh, c.wheel_type) end
    if c.window_tint   then SetVehicleWindowTint(veh, c.window_tint) end
    if c.livery        then SetVehicleLivery(veh, c.livery) end
    if type(c.mods) == 'table' then
        for i, m in pairs(c.mods) do SetVehicleMod(veh, tonumber(i), m, false) end
    end
    if c.turbo ~= nil then ToggleVehicleMod(veh, 18, c.turbo) end
    if c.smoke ~= nil then ToggleVehicleMod(veh, 20, c.smoke) end
    if c.xenon ~= nil then ToggleVehicleMod(veh, 22, c.xenon) end
    if type(c.neons) == 'table' then
        for i = 0, 3 do
            local on = c.neons[i]
            if on == nil then on = c.neons[tostring(i)] end
            SetVehicleNeonLightEnabled(veh, i, on == true)
        end
    end
    if c.neon_colour then SetVehicleNeonLightsColour(veh, table.unpack(c.neon_colour)) end
end


-- aplica a aparencia (look) ao motorista-fantasma: roupa + props (tolera chave
-- numerica virando string apos JSON)
local function apply_look(ped, look)
    if type(look) ~= 'table' then return end
    for i = 0, 11 do
        local c = look.components and (look.components[i] or look.components[tostring(i)])
        if c then SetPedComponentVariation(ped, i, c[1] or 0, c[2] or 0, c[3] or 0) end
    end
    for i = 0, 7 do
        local p = look.props and (look.props[i] or look.props[tostring(i)])
        if p then
            if (p[1] or -1) < 0 then ClearPedProp(ped, i)
            else SetPedPropIndex(ped, i, p[1], p[2] or 0, true) end
        end
    end
end


-- cria o motorista no banco do carro (look completo, ou fallback pelo pedModel)
local function spawn_driver(veh, look, fallback_model)
    if not vcfg().DRIVER then return nil end

    local model = (type(look) == 'table' and tonumber(look.model)) or tonumber(fallback_model) or 0
    if model == 0 or not IsModelInCdimage(model) then model = GetHashKey('mp_m_freemode_01') end

    RequestModel(model)
    local tries = 0
    while not HasModelLoaded(model) and tries < 100 do Wait(10); tries = tries + 1 end
    if not HasModelLoaded(model) then return nil end

    local ped = CreatePedInsideVehicle(veh, 4, model, -1, false, false)
    SetModelAsNoLongerNeeded(model)
    if not ped or ped == 0 then return nil end

    apply_look(ped, look)
    SetBlockingOfNonTemporaryEvents(ped, true)   -- nao tenta dirigir / reagir
    SetPedCanRagdoll(ped, false)
    SetEntityInvincible(ped, true)
    SetPedCanBeDraggedOut(ped, false)
    return ped
end


-- primeira posicao conhecida (ancora da cena)
local function first_anchor(replay)
    for _, p in ipairs(replay.players or {}) do
        local f = p.frames and p.frames[1]
        if f then return f end
    end
    return { x = 0.0, y = 0.0, z = 70.0 }
end


-- duracao = maior t entre todos os frames (ou replay.duration)
local function compute_dur(replay)
    local d = tonumber(replay.duration) or 0
    for _, p in ipairs(replay.players or {}) do
        local f = p.frames
        if f and #f > 0 then
            local lt = f[#f].t
            if lt > d then d = lt end
        end
    end
    return math.max(d, 0.1)
end


local function lerp(a, b, t) return a + (b - a) * t end

-- menor angulo com sinal de a para b
local function adelta(a, b) return ((b - a + 180) % 360) - 180 end

-- interpolacao angular pelo caminho mais curto
local function lerp_angle(a, b, t) return a + adelta(a, b) * t end

-- Catmull-Rom cubico (4 pontos de controle) — usado so para posicao (x/y/z),
-- reduz o "quicado" da interpolacao linear em curva/salto a 20Hz.
local function catmull_rom(p0, p1, p2, p3, t)
    local t2 = t * t
    local t3 = t2 * t
    return 0.5 * (
        (2 * p1) +
        (-p0 + p2) * t +
        (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
        (-p0 + 3 * p1 - 3 * p2 + p3) * t3
    )
end


-- amostra (a, b, alpha, idx) de um ghost no tempo tp — idx = indice de "a" em g.frames
local function sample(g, tp)
    local f = g.frames
    local n = #f
    if n == 0 then return nil end
    if tp <= f[1].t then return f[1], f[1], 0, 1 end
    if tp >= f[n].t then return f[n], f[n], 0, n end
    if tp < f[g.cursor].t then g.cursor = 1 end                 -- seek p/ tras
    while g.cursor < n and f[g.cursor + 1].t <= tp do g.cursor = g.cursor + 1 end
    local a = f[g.cursor]
    local b = f[math.min(g.cursor + 1, n)]
    local span  = b.t - a.t
    local alpha = (span > 0) and ((tp - a.t) / span) or 0
    return a, b, alpha, g.cursor
end


-- posicao com Catmull-Rom quando ha vizinhos dos 2 lados; cai para lerp nas pontas
local function sample_pos(g, a, b, alpha, idx)
    local f = g.frames
    local n = #f
    local p_prev = f[math.max(idx - 1, 1)]
    local p_next = f[math.min(idx + 2, n)]
    if idx <= 1 or idx >= n - 1 then
        return lerp(a.x, b.x, alpha), lerp(a.y, b.y, alpha), lerp(a.z, b.z, alpha)
    end
    return catmull_rom(p_prev.x, a.x, b.x, p_next.x, alpha),
           catmull_rom(p_prev.y, a.y, b.y, p_next.y, alpha),
           catmull_rom(p_prev.z, a.z, b.z, p_next.z, alpha)
end


-- ============================================================
-- UPDATE (por frame)
-- ============================================================

-- bits de bf/lf gravados em client/recorder.lua (input_bits/light_bits)
local LF_LOW, LF_HIGH, LF_IND_L, LF_IND_R = 1, 2, 4, 8

-- volante REAL gravado (st); fallback = deriva da guinada entre os 2 frames
local function steer_angle(a, b, al)
    local ast, bst = a.st, b.st
    if ast ~= nil or bst ~= nil then return lerp(ast or 0, bst or 0, al) end
    local dt  = (b.t or 0) - (a.t or 0)
    local yaw = (dt > 0.001) and (adelta(a.rz or 0, b.rz or 0) / dt) or 0
    return yaw * (vcfg().STEER_GAIN or 0.6)
end

-- RPM gravado (audio do motor); fallback = deriva da velocidade do chassi
local function rpm_value(a, b, al, spd)
    local arpm, brpm = a.rpm, b.rpm
    if arpm ~= nil or brpm ~= nil then return lerp(arpm or 0, brpm or 0, al) end
    return 0.2 + math.min(1.0, spd / (vcfg().RPM_MAX_KMH or 200)) * 0.8
end

-- velocidade do chassi (s, v1+v2) interpolada entre os 2 frames
local function chassis_speed(a, b, al)
    local as, bs = a.s, b.s
    return lerp(as or 0, bs or 0, al)
end

-- Catmull-Rom em ANGULO: desembrulha cada ponto p/ ser continuo com o vizinho
-- (evita o salto no cruzamento 359°→0°) antes de interpolar
local function cr_angle(a0, a1, a2, a3, t)
    a0 = a1 + adelta(a1, a0)
    a2 = a1 + adelta(a1, a2)
    a3 = a2 + adelta(a2, a3)
    return catmull_rom(a0, a1, a2, a3, t)
end


-- rotacao com Catmull-Rom no interior (suaviza a guinada em curva — tira o
-- "tique" do lerp a 20Hz); cai para lerp_angle nas pontas da sequencia
local function sample_rot(g, a, b, al, idx)
    local f = g.frames
    local n = #f
    if idx <= 1 or idx >= n - 1 then
        return lerp_angle(a.rx or 0, b.rx or 0, al),
               lerp_angle(a.ry or 0, b.ry or 0, al),
               lerp_angle(a.rz or 0, b.rz or 0, al)
    end
    local pp, pn = f[idx - 1], f[idx + 2]
    return cr_angle(pp.rx or 0, a.rx or 0, b.rx or 0, pn.rx or 0, al),
           cr_angle(pp.ry or 0, a.ry or 0, b.ry or 0, pn.ry or 0, al),
           cr_angle(pp.rz or 0, a.rz or 0, b.rz or 0, pn.rz or 0, al)
end


-- erro de posicao (m²) acima do qual reposiciona por TELEPORTE (seek / 1o frame
-- / lag spike) em vez de velocidade — evita "voar" atravessando o mapa num tick.
local RESYNC_DIST2 = 25.0   -- (5 m)^2


-- POSICAO POR VELOCIDADE: a cada frame damos ao carro a velocidade EXATA p/
-- chegar no alvo (velocidade = (alvo - atual)/dt). O corpo ANDA de verdade sobre
-- o solo (colisao com o MUNDO ligada) — e e isso que faz o MOTOR girar as rodas
-- sozinho, sem native manual (nao existe native que role a roda no carro parado).
-- Com timestamps em ms a velocidade fica suave e o carro para no alvo (sem
-- deriva). Seek / 1o frame / lag caem p/ teleporte.
local function update_transform(g, a, b, al, idx, dt)
    local x, y, z    = sample_pos(g, a, b, al, idx)
    local rx, ry, rz = sample_rot(g, a, b, al, idx)
    SetEntityRotation(g.veh, rx + 0.0, ry + 0.0, rz + 0.0, 2, true)

    local cur = GetEntityCoords(g.veh)
    local ex, ey, ez = x - cur.x, y - cur.y, z - cur.z

    if dt and dt > 0.0001 and (ex * ex + ey * ey + ez * ez) <= RESYNC_DIST2 then
        SetEntityVelocity(g.veh, ex / dt, ey / dt, ez / dt)
    else
        SetEntityCoordsNoOffset(g.veh, x + 0.0, y + 0.0, z + 0.0, false, false, false)
        SetEntityVelocity(g.veh, 0.0, 0.0, 0.0)
    end
end


-- RPM/esterco/volante/luzes — TODO frame. As RODAS giram sozinhas (o carro anda
-- de verdade sobre o solo, ver update_transform) — sem native manual de roda.
local function update_detail(g, a, b, al)
    local spd = chassis_speed(a, b, al)

    SetVehicleSteeringAngle(g.veh, math.max(-45, math.min(45, steer_angle(a, b, al))) + 0.0)
    SetVehicleCurrentRpm(g.veh, rpm_value(a, b, al, spd))

    if a.hb == 1 then SetVehicleBrakeLights(g.veh, true) end   -- luz de freio

    -- luzes/indicadores (v2, bitmask lf) — best-effort, cosmetico
    local lf = a.lf
    if lf then
        SetVehicleLights(g.veh, (lf & LF_LOW) ~= 0 and 0 or 2)
        SetVehicleFullbeam(g.veh, (lf & LF_HIGH) ~= 0)
        SetVehicleIndicatorLights(g.veh, 0, (lf & LF_IND_L) ~= 0)
        SetVehicleIndicatorLights(g.veh, 1, (lf & LF_IND_R) ~= 0)
    end
end


local function update_ghosts(dt)
    for _, g in ipairs(V.ghosts) do
        if g.veh and DoesEntityExist(g.veh) then
            local a, b, al, idx = sample(g, V.playhead)
            if a then
                update_transform(g, a, b, al, idx, dt)
                update_detail(g, a, b, al)
            end
        end
    end
end


local function update_cam()
    local g = V.ghosts[V.focus]
    if not (V.cam and g and g.veh and DoesEntityExist(g.veh)) then return end

    local pos = GetEntityCoords(g.veh)
    local h   = GetEntityHeading(g.veh)
    local rad = math.rad(h)
    local fx, fy = -math.sin(rad), math.cos(rad)   -- frente do carro
    local rxv, ryv = math.cos(rad), math.sin(rad)  -- lateral do carro
    local dist   = vcfg().CAM_DISTANCE or 6.5
    local height = vcfg().CAM_HEIGHT or 2.8

    local cx, cy, cz
    local mode = V.cam_mode
    if mode == 'orbit' then
        local a = (GetGameTimer() / 1000.0) * 0.7   -- giro suave, independente de fps
        cx, cy, cz = pos.x + math.cos(a) * dist * 1.25, pos.y + math.sin(a) * dist * 1.25, pos.z + height * 0.7
    elseif mode == 'side' then
        cx, cy, cz = pos.x + rxv * dist, pos.y + ryv * dist, pos.z + 1.5
    elseif mode == 'front' then
        cx, cy, cz = pos.x + fx * dist, pos.y + fy * dist, pos.z + 1.5
    elseif mode == 'drone' then
        cx, cy, cz = pos.x - fx * 2.0, pos.y - fy * 2.0, pos.z + dist * 2.4
    else -- chase (padrao)
        cx, cy, cz = pos.x - fx * dist, pos.y - fy * dist, pos.z + height
    end

    -- suavizacao: a camera DESLIZA ate o alvo (glide), em vez de travar a cada frame
    local k = vcfg().CAM_SMOOTH or 0.18
    if not V.cam_pos then V.cam_pos = { x = cx, y = cy, z = cz } end
    V.cam_pos.x = V.cam_pos.x + (cx - V.cam_pos.x) * k
    V.cam_pos.y = V.cam_pos.y + (cy - V.cam_pos.y) * k
    V.cam_pos.z = V.cam_pos.z + (cz - V.cam_pos.z) * k

    SetCamCoord(V.cam, V.cam_pos.x, V.cam_pos.y, V.cam_pos.z)
    PointCamAtCoord(V.cam, pos.x, pos.y, pos.z + 0.5)
end


-- envia o estado de reproducao para a NUI (throttle ~10/s, salvo force)
local function push_tick(force)
    local now = GetGameTimer()
    if not force and (now - V.last_push) < 100 then return end
    V.last_push = now
    SendNUIMessage({
        type       = 'tick',
        t          = V.playhead,
        dur        = V.dur,
        playing    = V.playing,
        speed      = V.speed,
        focus      = V.focus,
        focusLabel = (V.ghosts[V.focus] and V.ghosts[V.focus].label) or '—',
        camMode    = V.cam_mode,
    })
end


-- ============================================================
-- CENA — prepara/restaura o ped do jogador
-- ============================================================

local function setup_scene(anchor)
    local ped = PlayerPedId()
    V.origin   = GetEntityCoords(ped)
    V.origin_h = GetEntityHeading(ped)
    SetEntityCoordsNoOffset(ped, anchor.x + 0.0, anchor.y + 0.0, anchor.z + 0.0, false, false, false)
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)
    SetEntityInvincible(ped, true)
    SetEntityCollision(ped, false, false)
end


local function teardown_scene()
    local ped = PlayerPedId()
    SetEntityVisible(ped, true, false)
    SetEntityInvincible(ped, false)
    FreezeEntityPosition(ped, false)
    SetEntityCollision(ped, true, true)
    if V.origin then
        SetEntityCoordsNoOffset(ped, V.origin.x, V.origin.y, V.origin.z, false, false, false)
        SetEntityHeading(ped, V.origin_h or 0.0)
    end
    V.origin = nil
end


-- ============================================================
-- LIFECYCLE
-- ============================================================

-- inicia o playback de um replay (tabela ja decodificada do cache)
function P.start(replay)
    if V.active then P.stop() end
    if type(replay) ~= 'table' or type(replay.players) ~= 'table' then return false end

    if VRCS.Schema and replay.schema ~= VRCS.Schema.VERSION then
        Log.warn(('replay incompativel: schema %s (esperado %s)'):format(
            tostring(replay.schema), VRCS.Schema.VERSION))
        SendNUIMessage({ type = 'error', reason = 'replay_incompativel' })
        return false
    end

    V.replay   = replay
    V.dur      = compute_dur(replay)
    V.playhead = 0.0
    V.playing  = true
    V.speed    = vcfg().DEFAULT_SPEED or 1.0
    V.focus    = 1
    V.cam_mode = 'chase'
    V.cam_pos  = nil
    V.ghosts   = {}

    local anchor = first_anchor(replay)
    setup_scene(anchor)

    V.cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA',
        anchor.x, anchor.y, anchor.z + 5.0, 0.0, 0.0, 0.0, 55.0, false, 0)
    SetCamActive(V.cam, true)
    RenderScriptCams(true, false, 0, true, true)

    local alpha = vcfg().GHOST_ALPHA or 255
    for i, pl in ipairs(replay.players) do
        local f0 = pl.frames and pl.frames[1]
        if f0 then
            local model = load_model(pl.vehicle)
            if model then
                local veh = CreateVehicle(model, f0.x + 0.0, f0.y + 0.0, f0.z + 0.0,
                    f0.rz or 0.0, false, false)
                -- O ghost ANDA de verdade (update_transform usa velocidade) p/ o
                -- motor girar as rodas — precisa de colisao com o MUNDO (contato de
                -- solo). A colisao ENTRE ghosts e desligada depois (loop abaixo).
                SetEntityCollision(veh, true, true)
                SetEntityInvincible(veh, true)
                SetVehicleEngineOn(veh, true, true, false)
                SetVehicleRadioEnabled(veh, false)
                SetVehicleLights(veh, 2)
                apply_custom(veh, pl.customization, pl.plate)   -- aparencia da placa
                if alpha < 255 then SetEntityAlpha(veh, alpha, false) end
                SetModelAsNoLongerNeeded(model)

                local ped = spawn_driver(veh, pl.ped, pl.pedModel)   -- motorista no volante

                V.ghosts[#V.ghosts + 1] = {
                    veh    = veh,
                    ped    = ped,
                    frames = pl.frames,
                    cursor = 1,
                    wheels = GetVehicleNumberOfWheels(veh),
                    charId = pl.charId,
                    label  = ('#%s • char %s'):format(tostring(pl.placement or i), tostring(pl.charId or '?')),
                }
            end
        end
    end

    if #V.ghosts == 0 then P.stop(); return false end

    -- ghosts colidem com o MUNDO (roda gira no solo) mas NUNCA entre si
    for i = 1, #V.ghosts do
        for j = i + 1, #V.ghosts do
            SetEntityNoCollisionEntity(V.ghosts[i].veh, V.ghosts[j].veh, false)
            SetEntityNoCollisionEntity(V.ghosts[j].veh, V.ghosts[i].veh, false)
        end
    end

    V.active = true
    P._run()
    push_tick(true)
    SendNUIMessage({ type = 'view', view = 'player' })
    Log.info(('playback iniciado: %s (%d carros, %.0fs)'):format(replay.raceId, #V.ghosts, V.dur))
    return true
end


-- thread de reproducao (sai quando V.active = false — L-06)
function P._run()
    if V.thread then return end
    V.thread = true
    Citizen.CreateThread(function()
        local last = GetGameTimer()
        while V.active do
            local now = GetGameTimer()
            local dt  = (now - last) / 1000.0
            last = now

            if V.playing then
                V.playhead = V.playhead + dt * V.speed
                if V.playhead >= V.dur then
                    V.playhead = V.dur
                    V.playing  = false
                    push_tick(true)
                end
            end

            update_ghosts(dt)
            update_cam()
            push_tick(false)
            Wait(0)
        end
        V.thread = false
    end)
end


-- encerra o playback e restaura a cena (cleanup obrigatorio — A-07)
function P.stop()
    if not V.active and not V.cam then return end
    V.active = false

    for _, g in ipairs(V.ghosts) do
        if g.ped and DoesEntityExist(g.ped) then DeleteEntity(g.ped) end
        if g.veh and DoesEntityExist(g.veh) then DeleteEntity(g.veh) end
    end
    V.ghosts = {}

    if V.cam then
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(V.cam, false)
        V.cam = nil
    end

    teardown_scene()
    V.replay = nil
end


-- ============================================================
-- CONTROLES (chamados pela NUI)
-- ============================================================

function P.play()
    if V.playhead >= V.dur then V.playhead = 0.0 end
    V.playing = true
    push_tick(true)
end

function P.pause()
    V.playing = false
    push_tick(true)
end

function P.toggle()
    if V.playing then P.pause() else P.play() end
end

function P.seek(frac)
    frac = tonumber(frac) or 0
    V.playhead = math.max(0.0, math.min(1.0, frac)) * V.dur
    push_tick(true)
end

function P.set_speed(v)
    V.speed = tonumber(v) or 1.0
    push_tick(true)
end

function P.focus(delta)
    local n = #V.ghosts
    if n == 0 then return end
    V.focus = ((V.focus - 1 + (tonumber(delta) or 1)) % n) + 1
    V.cam_pos = nil   -- snap a camera ao novo alvo (sem glide pela cidade)
    push_tick(true)
end

-- cicla o tipo de camera (chase → orbit → side → front → drone)
function P.cam_cycle()
    local i = 1
    for k, m in ipairs(CAM_MODES) do if m == V.cam_mode then i = k; break end end
    V.cam_mode = CAM_MODES[(i % #CAM_MODES) + 1]
    V.cam_pos  = nil
    push_tick(true)
end

function P.is_active() return V.active end


AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    P.stop()
end)
