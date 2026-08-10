-- client/stance.lua — L2/HAL: rebaixamento visual REAL, per-entidade (NÃO model-wide).
--
-- Substitui o antigo stance via SetVehicleHandlingFloat(fSuspensionRaise), que era MODEL-WIDE
-- (afetava todas as instâncias do modelo, quase invisível e instável). Agora usa natives
-- per-entidade — SetVehicleSuspensionHeight / SetVehicleWheelSize / SetVehicleWheelWidth /
-- SetVehicleWheelXOffset — que dão altura VISÍVEL sem vazar entre veículos.
--
-- BASE STOCK: capturada da PRÓPRIA ENTIDADE, UMA vez por handle, ANTES da 1ª modificação
-- (guardada por modelo p/ tolerar reuso de handle). NÃO usa veículo temporário — o temp lia
-- offset de roda = 0 e o apply jogava as rodas pro CENTRO do carro (x=0), atravessando a
-- carroceria → física explodia → motor a 0 / fogo. Ler a base da entidade viva (que no 1º
-- toque está STOCK: spawn/entrada/oficina) resolve isso.
--
-- Sincronização: estado na PLACA (customization.stance = { r, tf, tr, sz, wd } em notches);
-- o servidor (server/visual.lua) espelha na entidade via State Bag `vhub_custom:stance`; este
-- módulo aplica em QUALQUER cliente (todos veem + sobrevive respawn). Alvo = base + notch*unit.
---@diagnostic disable: undefined-global

local CFG = VHubCustom.cfg
local BAG = VHubCustom.BAG

local ST = {}; VHubCustom.Stance = ST


-- ============================================================
-- BANDAS DE SEGURANÇA (clamp absoluto — nunca cravar a geometria)
-- ============================================================

-- hard-caps físicos: segurança absoluta independente da config. Valores conservadores
-- calibrados p/ evitar clip de carroceria/chão e tremor/bug de pneu.
local RIDE_MIN, RIDE_MAX   = -0.10, 0.08   -- ±10cm / 8cm (era -0.20/0.14 — muito largo)
local SIZE_MIN, SIZE_MAX   =  0.20, 1.50   -- roda custom: cap de tamanho reduzido
local WIDTH_MIN, WIDTH_MAX =  0.20, 1.50   -- roda custom: cap de largura reduzido
local XOFF_LIM             =  0.10         -- max ±10cm de bitola p/ fora (era 0.16 — exagerado)
local XOFF_BASE_SANE       =  0.30         -- base de roda >30cm = captura em estado transitório
                                           -- (réplica não estabilizada) → NÃO confia, pula o poke

local _base = {}   -- [entity] = { model, ride, size, width, xoff[0..3] } — base STOCK por handle

local function specs() return CFG.stance or {} end


-- ============================================================
-- BASE STOCK (lida da entidade VIVA, 1x por handle, antes de modificar)
-- ============================================================

-- captura (ou devolve) a base stock da entidade. Guardada por modelo: se o handle for reusado
-- por outro modelo, recaptura; mesmo modelo mantém (é a mesma referência de fábrica).
local function captureBase(veh)
  local model = GetEntityModel(veh)
  local b = _base[veh]
  if b and b.model == model then return b end
  b = { model = model, xoff = {} }
  b.ride  = GetVehicleSuspensionHeight(veh) or 0.0
  b.size  = GetVehicleWheelSize(veh) or 0.0
  b.width = GetVehicleWheelWidth(veh) or 0.0
  for i = 0, 3 do b.xoff[i] = GetVehicleWheelXOffset(veh, i) or 0.0 end
  _base[veh] = b
  return b
end


-- ============================================================
-- APLICAÇÃO (per-entidade, clampada)
-- ============================================================

-- notch validado do eixo (chave curta r/tf/tr/sz/wd) dentro da banda declarada
local function notch(stance, spec)
  local v = tonumber(stance and stance[spec.key]) or 0
  if v ~= math.floor(v) then v = math.floor(v) end
  if v < spec.min then v = spec.min elseif v > spec.max then v = spec.max end
  return v
end

-- aplica o objeto stance no veículo. `stance=nil/false` = volta ao stock (todos os notches 0).
function ST.apply(veh, stance)
  if not veh or veh == 0 or not DoesEntityExist(veh) then return end
  local b = captureBase(veh)   -- SEMPRE captura/lê a base ANTES de tocar em qualquer roda
  local byKey = {}; for _, s in ipairs(specs()) do byKey[s.key] = s end
  local st = type(stance) == 'table' and stance or {}
  local hasCustomWheel = GetVehicleMod(veh, 23) >= 0

  -- altura (SetVehicleSuspensionHeight é per-entidade — (−) abaixa, (+) levanta). Sempre seguro.
  if byKey.r then
    local target = b.ride + notch(st, byKey.r) * byKey.r.unit
    target = math.max(RIDE_MIN, math.min(RIDE_MAX, target))
    pcall(SetVehicleSuspensionHeight, veh, target + 0.0)
  end

  -- tamanho / largura da roda (só com roda custom — a stock não redimensiona; alvo = base+delta)
  if hasCustomWheel then
    if byKey.sz then
      local target = math.max(SIZE_MIN, math.min(SIZE_MAX, b.size + notch(st, byKey.sz) * byKey.sz.unit))
      pcall(SetVehicleWheelSize, veh, target + 0.0)
      for i = 0, 3 do
        pcall(SetVehicleWheelRimColliderSize, veh, i, (target / 2) + 0.0)
        pcall(SetVehicleWheelTireColliderSize, veh, i, (target / 2) + 0.0)
      end
    end
    if byKey.wd then
      local target = math.max(WIDTH_MIN, math.min(WIDTH_MAX, b.width + notch(st, byKey.wd) * byKey.wd.unit))
      pcall(SetVehicleWheelWidth, veh, target + 0.0)
    end
  end

  -- bitola (poke lateral, só p/ FORA): esquerda (par)=base−delta, direita (ímpar)=base+delta.
  -- delta >= 0 (banda min=0) → NUNCA puxa a roda p/ dentro do carro. base correta = sem centrar.
  -- GUARD DE PLAUSIBILIDADE: se a base capturada da roda for absurda (|xoff|>30cm), a entidade
  -- estava em estado transitório na captura (réplica ainda não estabilizou na entrada do carro).
  -- Aplicar delta sobre base-lixo foi o que jogava a roda pro centro/carroceria → física
  -- explodia → motor a 0/fogo. Base implausível = NÃO confia, pula aquela roda (stock preservado).
  local function poke(spec, wheels)
    if not spec then return end
    local delta = notch(st, spec) * spec.unit   -- notch >= 0 (banda min=0) → só p/ FORA
    if delta > XOFF_LIM then delta = XOFF_LIM end
    for _, i in ipairs(wheels) do
      local base = b.xoff[i] or 0.0
      if math.abs(base) <= XOFF_BASE_SANE then   -- base plausível: aplica o poke
        local target = base + ((i % 2 == 0) and -delta or delta)
        pcall(SetVehicleWheelXOffset, veh, i, target + 0.0)
      end
    end
  end
  poke(byKey.tf, { 0, 1 })
  poke(byKey.tr, { 2, 3 })

  if GetEntitySpeed(veh) < 1.0 then pcall(SetVehicleOnGroundProperly, veh) end
end

-- restaura o stock (usado no cancelar do preview)
function ST.restore(veh)
  ST.apply(veh, nil)
end


-- ============================================================
-- SYNC — State Bag na entidade (aplica p/ TODOS que veem o carro)
-- ============================================================

-- debounce por bag: um único thread por entidade por vez (evita threads concorrentes
-- disputando ST.apply → jitter). Lê o valor ATUAL do bag ao aplicar (não o capturado),
-- então mudanças rápidas convergem no último estado.
local _busy = {}

AddStateBagChangeHandler(BAG.STANCE, nil, function(bagName)
  if _busy[bagName] then return end
  _busy[bagName] = true
  CreateThread(function()
    local ent, tries = 0, 0
    repeat
      ent = GetEntityFromStateBagName(bagName)
      if ent and ent ~= 0 and DoesEntityExist(ent) then break end
      tries = tries + 1; Wait(120)
    until tries > 60
    if ent and ent ~= 0 and DoesEntityExist(ent) then
      local t = 0
      while not HasCollisionLoadedAroundEntity(ent) and t < 5000 do Wait(100); t = t + 100 end
      if DoesEntityExist(ent) then
        local cur = Entity(ent).state[BAG.STANCE]   -- valor ATUAL (não o capturado)
        ST.apply(ent, (type(cur) == 'table') and cur or nil)
      end
    end
    _busy[bagName] = nil
  end)
end)

-- limpa a base de handles que deixaram de existir (evita crescimento indefinido do cache)
CreateThread(function()
  while true do
    Wait(60000)
    for ent in pairs(_base) do
      if not DoesEntityExist(ent) then _base[ent] = nil end
    end
  end
end)
