---@diagnostic disable: undefined-global, lowercase-global

-- client/main.lua — vhub_velo: telemetria + seleção de HUD (camada L2/HAL).
-- PURO CONSUMIDOR: lê bags (vh_fuel/vh_odo/vhub_seatbelt) + natives efêmeros e envia ao HUD.
-- NUNCA escreve bag nem setVData (sem 2ª fonte de verdade, L-04). Preferência de HUD = KVP client-side.

local ATIVO_MS    = 80
local INATIVO_MS  = 350
local MS_PARA_KMH = 3.6

local visible   = false   -- HUD visível
local category  = nil     -- categoria atual (carro/moto/aero)
local running   = true    -- saída determinística da thread (L-06)

local last = { speed=-1, rpm=-1, gear='', fuel=-1, odo=-1, tl=nil, tr=nil, sb=nil, lk=nil, hd=-1 }

local odo_km    = 0.0     -- odômetro de EXIBIÇÃO (km); integra local, base do CORE, nunca persiste
local odo_plate = nil


-- ============================================================
-- HELPERS DE HUD (KVP — preferência por jogador, por categoria)
-- ============================================================

-- caminho do HUD pela categoria+id (fallback p/ o primeiro da categoria)
local function getHudPath(cat, id)
    local huds = Config.Huds[cat]
    if not huds then return nil end
    for _, h in ipairs(huds) do if h.id == id then return h.path end end
    return huds[1] and huds[1].path
end

-- id do HUD escolhido pelo jogador (KVP) ou o padrão da categoria
local function getUserHud(cat)
    local v = GetResourceKvpString('vhub_velo:' .. cat)
    if v and v ~= '' then return v end
    return Config.DefaultHuds[cat]
end

-- personalização salva por jogador (KVP): URL de fundo + cor de destaque, por categoria
local function getUserConfig(cat)
    local raw = GetResourceKvpString('vhub_velo:config:' .. cat)
    if raw and raw ~= '' then
        local ok, parsed = pcall(function() return json.decode(raw) end)
        if ok and type(parsed) == 'table' then return parsed end
    end
    -- fallback legado
    local bg = GetResourceKvpString('vhub_velo:bg:' .. cat) or ''
    local accent = GetResourceKvpString('vhub_velo:accent:' .. cat) or ''
    return { bgFuel = bg, bgSpeed = bg, bgRpm = bg, accent = accent }
end

-- valida a URL de fundo (entrada hostil): exige http(s):// + extensão de imagem.
-- '' = limpar o fundo; nil = inválida (ignora). Só carrega imagem client-side do próprio jogador.
local function sanitizeBgUrl(url)
    if type(url) ~= 'string' then return nil end
    url = url:gsub('^%s+', ''):gsub('%s+$', '')
    if url == '' then return '' end
    if #url > 512 or not url:match('^https?://') then return nil end
    -- defesa em profundidade: sem caracteres que quebrem a string CSS de url("...") (espaço/aspas/()<>\)
    if url:find('[%s"\'()<>\\]') then return nil end
    local path = (url:match('^[^?#]+') or ''):lower()
    if path:match('%.png$') or path:match('%.jpe?g$') or path:match('%.webp$') or path:match('%.gif$') then
        return url
    end
    return nil
end

-- valida a cor de destaque (#rgb ou #rrggbb); nil = inválida
local function sanitizeAccent(c)
    if type(c) ~= 'string' then return nil end
    c = c:gsub('^%s+', ''):gsub('%s+$', '')
    if c:match('^#%x%x%x%x%x%x$') or c:match('^#%x%x%x$') then return c end
    return nil
end

-- envia a personalização salva (fundo + cor) ao HUD ativo
local function pushConfig(cat)
    local cfg = getUserConfig(cat) or {}
    SendNUIMessage({ type = 'velocimetro:config', data = cfg })
end


-- ============================================================
-- LEITURA DE TELEMETRIA (natives + bags — confiável client-side)
-- ============================================================

local function limitar(v, a, b) v = tonumber(v) or a; if v < a then return a elseif v > b then return b end return v end
local function arredondar(v) return math.floor((tonumber(v) or 0) + 0.5) end

-- direção local separa ré de neutro quando a marcha nativa retorna zero
local function eixo_veiculo(veh)
    if type(GetEntitySpeedVector) ~= 'function' then return 0.0 end
    local vec = GetEntitySpeedVector(veh, true)
    if type(vec) == 'vector3' or type(vec) == 'table' then return tonumber(vec.y or vec[2]) or 0.0 end
    return 0.0
end

-- marcha visual: número real, N ou R
local function ler_marcha(veh)
    local g = tonumber(GetVehicleCurrentGear(veh)) or 0
    if g > 0 then return ('%d'):format(limitar(arredondar(g), 1, 9)) end
    return eixo_veiculo(veh) < -0.35 and 'R' or 'N'
end

-- pisca esq/dir (leitura crua do nativo; a correção de lado é feita na NUI)
local function ler_indicadores(veh)
    if type(GetVehicleIndicatorLights) ~= 'function' then return false, false end
    local e = GetVehicleIndicatorLights(veh) or 0
    local right = (e % 2) >= 1
    local left  = (math.floor(e / 2) % 2) >= 1
    return left, right
end

-- cinto: o vehcontrol é o DONO (tecla G → vhub_seatbelt); aqui só LEMOS (sem 2ª fonte)
local function ler_cinto()
    local ok, v = pcall(function() return LocalPlayer.state.vhub_seatbelt end)
    return ok and v == true
end

-- trava da porta (2/3/4/7 = trancado)
local function ler_trancado(veh)
    if type(GetVehicleDoorLockStatus) ~= 'function' then return false end
    local s = GetVehicleDoorLockStatus(veh) or 0
    return s == 2 or s == 3 or s == 4 or s == 7
end

-- combustível: LEITURA do bag vh_fuel (CORE escreve); fallback ao native. NUNCA escreve.
local function ler_fuel(veh)
    local ok, bag = pcall(function() return Entity(veh).state.vh_fuel end)
    if ok and type(bag) == 'number' and bag >= 0 then return bag end
    if type(GetVehicleFuelLevel) ~= 'function' then return 0.0 end
    return tonumber(GetVehicleFuelLevel(veh)) or 0.0
end

-- odômetro autoritativo (km) do bag vh_odo; nil quando o veículo não tem registro vHub
local function ler_odo_bag(veh)
    local ok, v = pcall(function() return Entity(veh).state.vh_odo end)
    if ok and type(v) == 'number' and v >= 0 then return v end
    return nil
end

-- heading arredondado a 2° (aero muda todo frame; threshold evita spam de update parado)
local function ler_heading(veh)
    return math.floor((GetEntityHeading(veh) or 0.0) / 2 + 0.5) * 2
end

-- placa limpa do veículo (ou nil)
local function placa_de(veh)
    local p = GetVehicleNumberPlateText(veh)
    return p and (p:upper():gsub('^%s+', ''):gsub('%s+$', '')) or nil
end


-- ============================================================
-- ODÔMETRO — base autoritativa do PRONTUÁRIO + integração local
-- ============================================================

-- base do PRONTUÁRIO: evento LOCAL do vehcontrol ao aplicar o estado salvo
AddEventHandler('vhub_vehcontrol:stateApplied', function(plate, state)
    if type(state) == 'table' and type(state.odometer_km) == 'number' then
        odo_plate, odo_km = plate, state.odometer_km
    end
end)

-- compat: base antiga do CORE (cadeia inerte pós-PRONTUÁRIO; mantido sem custo)
RegisterNetEvent('vHub:vehicleStateLoad')
AddEventHandler('vHub:vehicleStateLoad', function(plate, state)
    if type(state) == 'table' and type(state.odometer) == 'number' then
        odo_plate, odo_km = plate, state.odometer
    end
end)


-- ============================================================
-- ENVIO AO HUD (dedup — sem spam de 80ms)
-- ============================================================

local function enviar(ativo, sp, rpm, gear, tl, tr, sb, lk, fuel, odo, hd)
    sp   = limitar(arredondar(sp), 0, 999)
    rpm  = limitar(arredondar(rpm), 0, 100)
    fuel = limitar(arredondar(fuel), 0, 100)
    gear = ativo and tostring(gear or 'N') or 'N'
    tl = ativo and tl == true; tr = ativo and tr == true
    sb = ativo and sb == true; lk = lk == true
    local odo_cmp = odo and math.floor(odo) or -1

    if last.speed == sp and last.rpm == rpm and last.gear == gear and last.fuel == fuel
       and last.odo == odo_cmp and last.tl == tl and last.tr == tr and last.sb == sb
       and last.lk == lk and last.hd == hd then return end

    last.speed, last.rpm, last.gear, last.fuel, last.odo = sp, rpm, gear, fuel, odo_cmp
    last.tl, last.tr, last.sb, last.lk, last.hd = tl, tr, sb, lk, hd

    SendNUIMessage({ type = 'velocimetro:update', data = {
        visible = ativo, active = ativo, speed_kmh = sp, rpm_percent = rpm, gear_label = gear,
        fuel_percent = fuel, odometer_km = odo, turn_left = tl, turn_right = tr,
        seatbelt = sb, locked = lk, heading = hd,
    } })
end


-- ============================================================
-- VISIBILIDADE / CARGA DE HUD
-- ============================================================

-- carrega o HUD da categoria (preferência KVP ou padrão) e popula a galeria
local function loadCategory(cat)
    category = cat
    local id   = getUserHud(cat)
    local path = getHudPath(cat, id)
    SendNUIMessage({ type = 'velocimetro:loadHud', path = path, category = cat, hudId = id, huds = Config.Huds })
    pushConfig(cat)   -- aplica a personalização salva no HUD recém-carregado (host re-aplica no onload)
end

-- mostra/esconde o HUD (idempotente)
local function setVisible(v)
    if v == visible then return end
    visible = v
    SendNUIMessage({ type = 'velocimetro:toggle', visible = v })
    if not v then
        last.speed = -1   -- força o 1º update ao reentrar
        -- desativa o HUD: o velo-core para o RAF do odômetro (idle ~0 com o veículo desligado)
        SendNUIMessage({ type = 'velocimetro:update', data = { visible = false, active = false } })
    end
end


-- ============================================================
-- LOOP PRINCIPAL (adaptativo, L-06)
-- ============================================================

CreateThread(function()
    local lastT = GetGameTimer()
    while running do
        local agora = GetGameTimer()
        local dt = (agora - lastT) / 1000.0
        lastT = agora

        local ped = PlayerPedId()
        local veh = (ped ~= 0 and IsPedInAnyVehicle(ped, false)) and GetVehiclePedIsIn(ped, false) or 0
        local driver = veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped

        if driver then
            -- categoria → carrega o HUD quando muda de tipo de veículo
            local cat = Config.VehicleCategories[GetVehicleClass(veh)] or 'carro'
            if cat ~= category then loadCategory(cat) end
            setVisible(true)

            local sp   = (GetEntitySpeed(veh) or 0.0) * MS_PARA_KMH
            local rpm  = (GetVehicleCurrentRpm(veh) or 0.0) * 100.0
            local gear = ler_marcha(veh)
            local tl, tr = ler_indicadores(veh)
            local sb   = ler_cinto()
            local lk   = ler_trancado(veh)
            local fuel = ler_fuel(veh)
            local hd   = ler_heading(veh)

            -- odômetro de EXIBIÇÃO: integra local SEMPRE; bag/vehicleStateLoad = PISO, nunca override/persiste
            local plate   = placa_de(veh)
            local odo_bag = ler_odo_bag(veh)
            if plate then
                if plate ~= odo_plate then odo_plate, odo_km = plate, tonumber(odo_bag) or 0 end
                odo_km = odo_km + math.max(0, sp) * dt / 3600.0
                if odo_bag and odo_bag > odo_km then odo_km = odo_bag end
            end

            enviar(true, sp, rpm, gear, tl, tr, sb, lk, fuel, plate and odo_km or nil, hd)
            Wait(ATIVO_MS)
        else
            setVisible(false)
            category = nil
            Wait(INATIVO_MS)
        end
    end
end)


-- ============================================================
-- /velo — GALERIA DE HUD (foco só ao abrir) + KVP
-- ============================================================

-- abre a galeria p/ trocar de HUD + personalizar (só dentro do veículo)
RegisterCommand('velo', function()
    if not visible or not category then return end
    SetNuiFocus(true, true)
    SendNUIMessage({ type = 'velocimetro:openConfig', category = category, huds = Config.Huds, data = getUserConfig(category) })
end, false)

-- fecha a galeria e devolve o foco
RegisterNUICallback('velo:closeConfig', function(_, cb)
    SetNuiFocus(false, false)
    cb('ok')
end)

-- salva a preferência de HUD (KVP) e recarrega o HUD na hora
RegisterNUICallback('velo:saveHud', function(data, cb)
    if type(data) == 'table' and type(data.category) == 'string' and type(data.hudId) == 'string' then
        SetResourceKvp('vhub_velo:' .. data.category, data.hudId)
        local path = getHudPath(data.category, data.hudId)
        if path then
            SendNUIMessage({ type = 'velocimetro:loadHud', path = path,
                             category = data.category, hudId = data.hudId, huds = Config.Huds })
            pushConfig(data.category)   -- reaplica fundo/cor no HUD trocado
        end
    end
    cb('ok')
end)

-- salva a personalização (fundo por link + cor de destaque) por categoria (KVP) e aplica ao vivo.
-- Entrada hostil: a URL é sanitizada (http(s)+imagem); cor exige hex. Inválido = ignorado.
RegisterNUICallback('velo:saveConfig', function(data, cb)
    if type(data) == 'table' and type(data.category) == 'string' and Config.Huds[data.category] then
        local cat = data.category
        local cfg = {}
        local bgFuel = sanitizeBgUrl(data.bgFuel or data.urlImagemFuel or data.bg)
        local bgSpeed = sanitizeBgUrl(data.bgSpeed or data.urlImagemVelocidade or data.bg)
        local bgRpm = sanitizeBgUrl(data.bgRpm or data.urlImagemRpm)
        local accent = sanitizeAccent(data.accent or data.corPonteiroVelocidade or data.corPonteiroFuel or data.corPonteiroRpm)
        if bgFuel ~= nil then cfg.bgFuel = bgFuel end
        if bgSpeed ~= nil then cfg.bgSpeed = bgSpeed end
        if bgRpm ~= nil then cfg.bgRpm = bgRpm end
        if accent then cfg.accent = accent end
        -- grava JSON KVP
        pcall(function() SetResourceKvp('vhub_velo:config:' .. cat, json.encode(cfg)) end)
        -- compatibilidade com chaves legadas
        if cfg.bgSpeed and cfg.bgSpeed ~= '' then SetResourceKvp('vhub_velo:bg:' .. cat, cfg.bgSpeed) end
        if cfg.accent and cfg.accent ~= '' then SetResourceKvp('vhub_velo:accent:' .. cat, cfg.accent) end
        pushConfig(cat)
    end
    cb('ok')
end)

-- foco remoto (HUD pede que o host ajuste SetNuiFocus)
RegisterNUICallback('focar', function(data, cb)
    if type(data) == 'table' and data.focar ~= nil then
        SetNuiFocus(data.focar == true, data.focar == true)
    end
    cb('ok')
end)


-- ============================================================
-- CLEANUP (L-06 / foco)
-- ============================================================

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    running = false
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'velocimetro:toggle', visible = false })
end)
