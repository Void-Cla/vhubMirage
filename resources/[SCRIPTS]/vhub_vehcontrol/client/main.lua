---@diagnostic disable: undefined-global, lowercase-global

-- client/main.lua — controle de veiculo (HAL). Dirige a NUI existente (html/ intacto).
--
-- O CLIENTE executa os natives (tem a entidade): portas, janelas, luzes, banco, cinto.
-- Trava e motor passam pelo SERVIDOR (autoridade por chave) e voltam por broadcast.

local E = 'vhub_vehcontrol:'


-- ============================================================
-- ESTADO
-- ============================================================

local open     = false
local veh      = 0
local plate    = nil
local winDown  = {}        -- [doorIndex] = bool (janela abaixada)
local intLight = false
local extLight = false
local sigL, sigR = false, false   -- estado do pisca (esq/dir; ambos ligados = alerta)
local seatbelt = false     -- cinto de segurança (keyboard 'g')
local _running  = true     -- saida deterministica das threads (L-06)


-- ============================================================
-- HELPERS
-- ============================================================

local function setFocus(b)
  SetNuiFocus(b, b)
  SetNuiFocusKeepInput(b)
end

-- placa limpa de um veiculo (ou nil) — normaliza leading+trailing+case
-- GetVehicleNumberPlateText retorna 8 chars com padding bilateral; espelha normalizePlate do servidor
local function plateOf(v)
  if not v or v == 0 then return nil end
  local p = GetVehicleNumberPlateText(v)
  if not p then return nil end
  p = p:upper():gsub('%s+', ' '):match('^%s*(.-)%s*$')
  return (p and #p >= 1) and p or nil
end

-- veiculo que o jogador pode controlar: o que esta dentro, senao o mais proximo a pe
local function controlledVehicle()
  local ped = PlayerPedId()
  if IsPedInAnyVehicle(ped, false) then return GetVehiclePedIsIn(ped, false) end
  local p = GetEntityCoords(ped)
  local v = GetClosestVehicle(p.x, p.y, p.z, Config.distance or 5.0, 0, 71)
  return (v and v ~= 0) and v or 0
end

-- ============================================================
-- ABRIR / FECHAR
-- ============================================================

local function closePanel()
  if not open then return end
  open = false
  setFocus(false)
  SendNUIMessage({ type = 'ui', status = false })
end

local function openPanel()
  if open or IsNuiFocused() then return end
  local v = controlledVehicle()
  if v == 0 then return end
  veh, plate = v, plateOf(v)
  winDown = {}
  open = true
  setFocus(true)
  SendNUIMessage({ type = 'ui', status = true, windows = Config.viewWindows == true })
  SendNUIMessage({ type = 'emergency', emergencystatus = (sigL and sigR) })
end

-- comando de chat (sempre disponivel)
if Config.command and Config.command ~= '' then
  RegisterCommand(Config.command, function()
    if open then closePanel() else openPanel() end
  end, false)
end


-- ============================================================
-- ACOES RAPIDAS (trava, pisca, janela) — helpers compartilhados
-- ============================================================

-- pede trava/destrava ao servidor (autoridade por chave). v = veiculo alvo
local function requestLock(v)
  if not v or v == 0 then return end
  local pl = plateOf(v)
  if pl then TriggerServerEvent(E .. 'requestLock', VehToNet(v), pl) end
end

-- aplica o pisca atual ao veiculo + reflete o alerta na NUI (se aberta)
local function applySignals()
  local v = controlledVehicle()
  if v == 0 then return end
  SetVehicleIndicatorLights(v, Config.indicator.left, sigL)
  SetVehicleIndicatorLights(v, Config.indicator.right, sigR)
  if open then SendNUIMessage({ type = 'emergency', emergencystatus = (sigL and sigR) }) end
end

-- liga/desliga o pisca-alerta (os dois lados juntos)
local function toggleHazard()
  local haz = not (sigL and sigR)
  sigL, sigR = haz, haz
  applySignals()
end

-- seta esq/dir: pisca individual; as duas quase juntas (<=220ms) = pisca-alerta
local _lastArrow = { L = 0, R = 0 }
local function arrowSignal(side)
  if controlledVehicle() == 0 then return end
  local now    = GetGameTimer()
  local other  = (side == 'L') and 'R' or 'L'
  if now - _lastArrow[other] <= 220 then
    toggleHazard()
  else
    if side == 'L' then sigL = not sigL else sigR = not sigR end
    applySignals()
  end
  _lastArrow[side] = now
end

-- sobe/abaixa a janela do assento do jogador
local function windowAction(up)
  local ped = PlayerPedId()
  if not IsPedInAnyVehicle(ped, false) then return end
  local v   = GetVehiclePedIsIn(ped, false)
  local idx = 0
  for s = -1, GetVehicleModelNumberOfSeats(GetEntityModel(v)) - 2 do
    if GetPedInVehicleSeat(v, s) == ped then
      idx = ({ [-1] = 0, [0] = 1, [1] = 2, [2] = 3 })[s] or 0
      break
    end
  end
  if up then RollUpWindow(v, idx) else RollDownWindow(v, idx) end
end


-- ============================================================
-- TECLAS
-- ============================================================

-- 'L': TOQUE = trança/destranca | SEGURAR = abre o painel
local _lHeld, _lUsed = false, false
RegisterCommand('+vhubvc_lock', function()
  if open or IsNuiFocused() then return end
  _lHeld, _lUsed = true, false
  SetTimeout(Config.holdToOpenMs or 1000, function()
    if _lHeld and not _lUsed and not open then _lUsed = true; openPanel() end
  end)
end, false)
RegisterCommand('-vhubvc_lock', function()
  local was = _lHeld; _lHeld = false
  if was and not _lUsed then requestLock(controlledVehicle()) end   -- toque = trava
end, false)
RegisterKeyMapping('+vhubvc_lock', 'Veiculo: trancar (toque) / abrir painel (segurar)', 'keyboard', Config.keys.lock or 'L')

-- setas: pisca (esq/dir/alerta) e janela (cima/baixo) — disparam no toque
RegisterCommand('vhubvc_sigL', function() arrowSignal('L') end, false)
RegisterKeyMapping('vhubvc_sigL', 'Veiculo: pisca esquerdo', 'keyboard', Config.keys.signalLeft or 'LEFT')

RegisterCommand('vhubvc_sigR', function() arrowSignal('R') end, false)
RegisterKeyMapping('vhubvc_sigR', 'Veiculo: pisca direito', 'keyboard', Config.keys.signalRight or 'RIGHT')

RegisterCommand('vhubvc_winUp', function() windowAction(true) end, false)
RegisterKeyMapping('vhubvc_winUp', 'Veiculo: subir janela', 'keyboard', Config.keys.windowUp or 'UP')

RegisterCommand('vhubvc_winDn', function() windowAction(false) end, false)
RegisterKeyMapping('vhubvc_winDn', 'Veiculo: descer janela', 'keyboard', Config.keys.windowDown or 'DOWN')

-- notificacao de trava (o servidor avisa quem acionou)
RegisterNetEvent(E .. 'lockNotify')
AddEventHandler(E .. 'lockNotify', function(state)
  if Config.notify then Config.notify(state == 2 and 'Veículo trancado' or 'Veículo destrancado') end
end)


-- ============================================================
-- CINTO DE SEGURANCA (keyboard 'g')
-- ============================================================

-- Define o cinto e publica o estado para HUDs (ex: velocimetro) via statebag local.
-- Este resource e a fonte unica de verdade do cinto (L-04). false = desafivelado.
local function setSeatbelt(state)
  seatbelt = state and true or false
  LocalPlayer.state:set('vhub_seatbelt', seatbelt, false)
end

-- estado inicial: sempre desafivelado
setSeatbelt(false)

-- alterna cinto + notificacao
RegisterCommand('vhubvc_seatbelt', function()
  if controlledVehicle() == 0 then return end
  setSeatbelt(not seatbelt)
  if Config.notify then Config.notify(seatbelt and 'Cinto afivelado' or 'Cinto desafivelado') end
end, false)
RegisterKeyMapping('vhubvc_seatbelt', 'Veiculo: cinto de seguranca', 'keyboard', 'G')

-- ============================================================
-- PRONTUÁRIO (sprint que supera a #21) — telemetria física do motorista
-- ============================================================
-- O motorista é o ÚNICO escritor da entidade (L-16): drena fuel localmente
-- (física efêmera, L-02), acumula odômetro e envia snapshot COMPLETO ao servidor
-- (15s dirigindo + final ao sair do banco). O servidor valida fail-closed e
-- persiste via escritor único do conce. Ao entrar, pede o estado salvo
-- (requestState) e aplica nos natives (substitui o vHub:vehicleStateLoad do CORE).

local FUEL_DECOR   = 'FUEL_LEVEL'   -- decor do vhub_legacyfuel (a bomba lê daqui)
local SNAP_MS      = 15000          -- cadência do snapshot periódico (L-18)
local vc_veh       = 0              -- veiculo atual rastreado
local vc_plate     = nil            -- placa que estou dirigindo (nil = nao sou motorista)
local vc_applied   = false          -- estado salvo ja foi aplicado nesta placa
local vc_lastReq   = 0
local vc_reqTries  = 0
local vc_odoAcc    = 0.0            -- km acumulados desde o ultimo snapshot
local vc_lastSnap  = 0
local vc_lastDecor = -10.0

-- multiplicador de drenagem por classe GTA (espelha o legacyfuel; default 0.4)
local CLASS_DRAIN = { [13]=0.0, [14]=0.0, [15]=0.0, [16]=0.0, [17]=0.3, [18]=0.3, [21]=0.0 }

-- bones de janela por indice (IsVehicleWindowIntact retorna false p/ janela
-- INEXISTENTE no modelo — bone-check obrigatorio antes de persistir/aplicar)
local WINDOW_BONES = {
  [0]='window_lf', [1]='window_rf', [2]='window_lr', [3]='window_rr',
  [4]='window_lm', [5]='window_rm', [6]='windscreen', [7]='windscreen_r',
}

-- coleta o dano estrutural persistivel do veiculo (portas/janelas/pneus)
local function collectDamage(v)
  local d = { doors = {}, windows = {}, tyres = {}, tyres_rim = {} }
  for i = 0, 5 do
    if IsVehicleDoorDamaged(v, i) then d.doors[#d.doors+1] = i end
  end
  for i = 0, 7 do
    local bone = WINDOW_BONES[i]
    if bone and GetEntityBoneIndexByName(v, bone) ~= -1 and not IsVehicleWindowIntact(v, i) then
      d.windows[#d.windows+1] = i
    end
  end
  if GetVehicleTyresCanBurst(v) then
    for i = 0, 7 do
      if IsVehicleTyreBurst(v, i, true) then d.tyres_rim[#d.tyres_rim+1] = i
      elseif IsVehicleTyreBurst(v, i, false) then d.tyres[#d.tyres+1] = i end
    end
  end
  return d
end

-- garante controle de rede da entidade antes de mutar dano (anti-revert do sync)
local function ensureControl(v)
  if NetworkHasControlOfEntity(v) then return true end
  NetworkRequestControlOfEntity(v)
  local t = 0
  while not NetworkHasControlOfEntity(v) and t < 20 do Wait(0); t = t + 1 end
  return NetworkHasControlOfEntity(v)
end

-- snapshot completo do estado fisico atual (telemetria manda SEMPRE full-field)
local function buildSnapshot(v, final)
  local snap = {
    fuel          = GetVehicleFuelLevel(v),
    engine_health = GetVehicleEngineHealth(v),
    body_health   = GetVehicleBodyHealth(v),
    odo_delta_km  = vc_odoAcc,
    damage        = collectDamage(v),
    final         = final == true or nil,
  }
  vc_odoAcc = 0.0
  return snap
end

-- envia snapshot ao servidor (validado la; escrita unica no conce)
local function sendSnapshot(v, pl, final)
  TriggerServerEvent(E .. 'stateSync', VehToNet(v), pl, buildSnapshot(v, final))
  vc_lastSnap = GetGameTimer()
end

-- aplica o estado salvo na entidade local (fuel local; dano atras de controle de rede)
RegisterNetEvent(E .. 'applyState')
AddEventHandler(E .. 'applyState', function(pl, st)
  if type(st) ~= 'table' then return end
  local ped = PlayerPedId()
  local v = GetVehiclePedIsIn(ped, false)   -- sempre fresh (race: trocou de carro)
  if not v or v == 0 or plateOf(v) ~= pl then return end
  vc_applied = true

  -- CRITICO: '+ 0.0' força subtipo FLOAT (Lua 5.4). Numeros inteiros vindos do
  -- msgpack (100, 1000) passados a native de param float são BIT-REINTERPRETADOS
  -- (1000 → 1.4e-42) — fuel/motor viravam ~0 e o snapshot persistia o lixo.
  if type(st.fuel) == 'number' then
    SetVehicleFuelLevel(v, st.fuel + 0.0)
    if DecorIsRegisteredAsType(FUEL_DECOR, 1) then DecorSetFloat(v, FUEL_DECOR, st.fuel + 0.0) end
    vc_lastDecor = st.fuel
  end

  CreateThread(function()
    if not ensureControl(v) then return end
    if type(st.engine_health) == 'number' then SetVehicleEngineHealth(v, st.engine_health + 0.0) end
    if type(st.body_health)   == 'number' then SetVehicleBodyHealth(v, st.body_health + 0.0) end
    local d = st.damage
    if type(d) == 'table' then
      for _, i in ipairs(d.doors or {})   do SetVehicleDoorBroken(v, i, true) end
      for _, i in ipairs(d.windows or {}) do
        local bone = WINDOW_BONES[i]
        if bone and GetEntityBoneIndexByName(v, bone) ~= -1 then SmashVehicleWindow(v, i) end
      end
      if GetVehicleTyresCanBurst(v) then
        for _, i in ipairs(d.tyres or {})     do SetVehicleTyreBurst(v, i, false, 1000.0) end
        for _, i in ipairs(d.tyres_rim or {}) do SetVehicleTyreBurst(v, i, true, 1000.0) end
      end
    end
  end)

  -- evento LOCAL p/ HUDs (vhub_velo semeia o odometro daqui)
  TriggerEvent('vhub_vehcontrol:stateApplied', pl, st)
end)

-- detecta crash (eject sem cinto), reseta o cinto ao entrar e gerencia o ciclo
-- requestState/snapshot-final do prontuario quando motorista
CreateThread(function()
  local lastVel = 0

  -- saiu do banco do motorista: snapshot FINAL imediato (estado mais importante)
  local function finishDriving()
    if vc_plate then
      local v = vc_veh
      if v ~= 0 and DoesEntityExist(v) then sendSnapshot(v, vc_plate, true) end
      vc_plate, vc_applied = nil, false
    end
  end

  while _running do
    Wait(100)
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
      local v = GetVehiclePedIsIn(ped, false)

      -- entrou num veiculo diferente: reseta cinto e fecha o ciclo anterior
      if v ~= vc_veh then
        finishDriving()
        vc_veh = v
        setSeatbelt(false)
      end

      if GetPedInVehicleSeat(v, -1) == ped then
        local pl = plateOf(v)
        if pl then
          if vc_plate ~= pl then
            vc_plate, vc_applied, vc_lastReq, vc_reqTries = pl, false, 0, 0
            vc_odoAcc, vc_lastSnap = 0.0, GetGameTimer()
          end
          -- pede o estado salvo ate o applyState chegar (3 tentativas / 2.5s)
          if not vc_applied and vc_reqTries < 3 then
            local now = GetGameTimer()
            if now - vc_lastReq > 2500 then
              vc_lastReq, vc_reqTries = now, vc_reqTries + 1
              TriggerServerEvent(E .. 'requestState', VehToNet(v), pl)
            end
          end
          -- snapshot periodico (15s dirigindo)
          if GetGameTimer() - vc_lastSnap >= SNAP_MS then sendSnapshot(v, pl, false) end
        end
      elseif vc_plate then
        finishDriving()   -- trocou p/ assento de passageiro
      end

      -- crash detectado: velocidade caiu > 15 m/s em 100ms (impacto forte)
      local vel = GetEntitySpeed(v)
      if (lastVel - vel) > 15 and lastVel > 10 and not seatbelt then
        TaskLeaveVehicle(ped, v, 0)
        ApplyDamageToPed(ped, 10, false)  -- toma dano extra por ser ejetado
      end
      lastVel = vel
    else
      finishDriving()
      lastVel = 0
      vc_veh = 0
    end
  end
end)

-- drenagem de combustivel por rpm + odometro (1s motorista; 2s fora — L-06/L-18).
-- Fonte unica do consumo: o native local da entidade; o snapshot persiste.
CreateThread(function()
  while _running do
    local ped = PlayerPedId()
    local v = (ped ~= 0 and IsPedInAnyVehicle(ped, false)) and GetVehiclePedIsIn(ped, false) or 0
    if v ~= 0 and GetPedInVehicleSeat(v, -1) == ped then
      -- odometro: integra velocidade (km) — clamp server-side cobre o resto
      vc_odoAcc = vc_odoAcc + (GetEntitySpeed(v) or 0.0) * 3.6 / 3600.0

      if GetIsVehicleEngineRunning(v) then
        local rpm   = GetVehicleCurrentRpm(v) or 0.0
        local mult  = CLASS_DRAIN[GetVehicleClass(v)] or 0.4
        local fuel  = GetVehicleFuelLevel(v)
        local nf    = math.max(0.0, fuel - rpm * mult / 10.0)
        SetVehicleFuelLevel(v, nf)
        -- decor p/ a bomba do legacyfuel; delta-gate 0.5 evita churn de sync
        if DecorIsRegisteredAsType(FUEL_DECOR, 1) and math.abs(nf - vc_lastDecor) >= 0.5 then
          DecorSetFloat(v, FUEL_DECOR, nf)
          vc_lastDecor = nf
        end
      end
      Wait(1000)
    else
      Wait(2000)
    end
  end
end)


-- ============================================================
-- INTEGRACAO COM INVENTARIO (veh_key)
-- ============================================================

-- Quando a chave é usada do inventário, abre o painel
RegisterNetEvent(E .. 'open_from_key')
AddEventHandler(E .. 'open_from_key', function(pl)
  if pl and pl ~= '' then
    plate = pl
    openPanel()
  end
end)


-- ============================================================
-- DASHBOARD (loop so quando aberto)
-- ============================================================

CreateThread(function()
  while _running do
    if open and veh ~= 0 and DoesEntityExist(veh) then
      Wait(500)

      -- fecha se o player saiu do alcance do veiculo
      local ped = PlayerPedId()
      if not IsPedInAnyVehicle(ped, false)
         and #(GetEntityCoords(ped) - GetEntityCoords(veh)) > ((Config.distance or 5.0) + 3.0) then
        closePanel()
      else
        -- painel compacto: so combustivel. MESMA fonte do velocimetro (State Bag vh_fuel
        -- do CORE) p/ os dois HUDs nunca divergirem; fallback ao native sem registro vHub.
        local okf, fbag = pcall(function() return Entity(veh).state.vh_fuel end)
        local fuelv = (okf and type(fbag) == 'number' and fbag >= 0) and fbag or GetVehicleFuelLevel(veh)
        SendNUIMessage({ type = 'updateFuel', fuel = math.floor(fuelv) })
      end
    else
      if open then closePanel() end
      Wait(800)
    end
  end
end)


-- ============================================================
-- NUI CALLBACKS — controles
-- ============================================================

RegisterNUICallback('exit', function(_, cb) closePanel(); cb('ok') end)

-- portas (lf/rf/lr/rr/hood/trunk) — toggle local
RegisterNUICallback('door', function(d, cb)
  local idx = Config.doorIndex[d and d.door]
  if veh ~= 0 and idx then
    if GetVehicleDoorAngleRatio(veh, idx) > 0.0 then
      SetVehicleDoorShut(veh, idx, false)
    else
      SetVehicleDoorOpen(veh, idx, false, false)
    end
  end
  cb('ok')
end)

-- janelas — toggle local (estado proprio por nao haver native confiavel de leitura)
RegisterNUICallback('window', function(d, cb)
  local idx = Config.windowIndex[d and d.window]
  if veh ~= 0 and idx then
    winDown[idx] = not winDown[idx]
    if winDown[idx] then RollDownWindow(veh, idx) else RollUpWindow(veh, idx) end
  end
  cb('ok')
end)

-- luz interna — local
RegisterNUICallback('light', function(_, cb)
  if veh ~= 0 then intLight = not intLight; SetVehicleInteriorlight(veh, intLight) end
  cb('ok')
end)

-- farois — local (2 = faróis forçados; 0 = devolve o controle automatico ao jogo)
RegisterNUICallback('lights', function(_, cb)
  if veh ~= 0 then extLight = not extLight; SetVehicleLights(veh, extLight and 2 or 0) end
  cb('ok')
end)

-- banco — vai p/ o proximo assento livre
RegisterNUICallback('seat', function(_, cb)
  if veh ~= 0 then
    local ped = PlayerPedId()
    local seats = GetVehicleModelNumberOfSeats(GetEntityModel(veh))
    local cur = -2
    for s = -1, seats - 2 do if GetPedInVehicleSeat(veh, s) == ped then cur = s; break end end
    local placed = false
    for s = cur + 1, seats - 2 do
      if IsVehicleSeatFree(veh, s) then SetPedIntoVehicle(ped, veh, s); placed = true; break end
    end
    if not placed then
      for s = -1, cur - 1 do
        if IsVehicleSeatFree(veh, s) then SetPedIntoVehicle(ped, veh, s); break end
      end
    end
  end
  cb('ok')
end)

-- emergencia — pisca-alerta (mesma logica da tecla seta-esq+dir)
RegisterNUICallback('emergency', function(_, cb)
  toggleHazard()
  cb('ok')
end)


-- ============================================================
-- TRAVA / MOTOR — intencao p/ o servidor (autoridade por chave)
-- ============================================================

RegisterNUICallback('lock', function(_, cb)
  requestLock(veh)
  cb('ok')
end)

RegisterNUICallback('engine', function(_, cb)
  if veh ~= 0 and plate then TriggerServerEvent(E .. 'requestEngine', VehToNet(veh), plate) end
  cb('ok')
end)

-- aplica o estado autoritativo (broadcast). So aplica se a placa do veiculo do
-- netId bater com a autorizada — fecha spoof de netId (plateOf e confiavel no client).
RegisterNetEvent(E .. 'applyLock')
AddEventHandler(E .. 'applyLock', function(netId, pl, state)
  local v = NetToVeh(netId)
  if v and v ~= 0 and DoesEntityExist(v) and plateOf(v) == pl then
    SetVehicleDoorsLocked(v, state)
    if state == 2 then PlayVehicleDoorCloseSound(v, 1) else PlayVehicleDoorOpenSound(v, 0) end
  end
end)

RegisterNetEvent(E .. 'applyEngine')
AddEventHandler(E .. 'applyEngine', function(netId, pl, on)
  local v = NetToVeh(netId)
  if v and v ~= 0 and DoesEntityExist(v) and plateOf(v) == pl then
    SetVehicleEngineOn(v, on, false, true)
  end
end)


-- ============================================================
-- CLEANUP
-- ============================================================

AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  _running = false                       -- encerra as threads (L-06)
  if open then setFocus(false) end
end)
