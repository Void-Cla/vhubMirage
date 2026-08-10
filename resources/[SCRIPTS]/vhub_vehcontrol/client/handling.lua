---@diagnostic disable: undefined-global, lowercase-global

-- client/handling.lua — L2/HAL: aplica a FÍSICA derivada do skill (F5, decisão #28).
--
-- Server-authoritative: os números vêm de sheet.hnd (o SERVIDOR calcula via
-- tier_rules.handlingFromAlloc a partir do alloc persistido). O cliente SÓ aplica,
-- RE-CLAMPADO, e SOMENTE no veículo que o jogador DIRIGE (seat -1). Nunca inventa
-- valor, nunca persiste (hnd é derivado; dono do alloc = conce).
--
-- ATENÇÃO model-wide (risco nº1 §5.2.1): SetVehicleHandlingFloat altera o handling
-- de TODAS as instâncias do modelo NO cliente local. Por isso cacheamos o valor base
-- do modelo no 1º toque e RESTAURAMOS ao sair do veículo (sem vazar pela sessão).
-- Carro de terceiros aparece com o handling base (fallback aceito da §5.2.1).


-- ============================================================
-- ESTADO
-- ============================================================

local E            = VHubVeh.E
local _drivenVeh   = 0        -- veículo que estou dirigindo agora (0 = nenhum)
local _drivenPlate = ''       -- placa do veículo dirigido (p/ filtrar SHEET_UPDATED)
local _modelBase   = {}       -- [model] = { [field] = valor original do .meta } (restauração)


-- ============================================================
-- HELPERS
-- ============================================================

-- bandas dos 5 eixos derivados do alloc (eixo → {field,min,max})
local function bands() return (Config and Config.skillHandling) or {} end

-- bandas do OVERLAY (stance + knobs livres) — campos disjuntos, com mode ('delta'|'abs')
local function extBands() return (Config and Config.skillHandlingExt) or {} end

-- normaliza placa p/ comparação (espelha o servidor: upper + trim)
local function normPlate(p)
  return (tostring(p or ''):upper():gsub('%s+', ' '):match('^%s*(.-)%s*$')) or ''
end

-- diagnóstico no chat (Config.skillDebug) — prova a cadeia em jogo; DESLIGAR em produção
local function dbg(msg)
  if Config and Config.skillDebug and Config.notify then Config.notify('[F5] ' .. msg) end
end

-- cacheia o valor BASE do modelo (1x por field) ANTES de qualquer override
-- inclui os campos do overlay (stance/knobs) — restauração cobre 5 eixos + overlay
local function ensureBase(veh, model)
  local b = _modelBase[model]
  if not b then b = {}; _modelBase[model] = b end
  local function cache(m)
    if b[m.field] == nil then
      b[m.field] = GetVehicleHandlingFloat(veh, 'CHandlingData', m.field)
    end
  end
  for _, m in pairs(bands())    do cache(m) end
  for _, m in pairs(extBands()) do cache(m) end
  return b
end

-- restaura o handling base do modelo (desfaz o override model-wide)
local function restoreBase(veh)
  if not veh or veh == 0 or not DoesEntityExist(veh) then return end
  local b = _modelBase[GetEntityModel(veh)]
  if not b then return end
  for field, val in pairs(b) do
    SetVehicleHandlingFloat(veh, 'CHandlingData', field, val + 0.0)
  end
end

-- aplica hnd (re-clampado às bandas) no veículo dirigido
local function applyHnd(veh, hnd)
  if not (Config and Config.skillApplyHandling) then return end
  if type(hnd) ~= 'table' or not veh or veh == 0 or not DoesEntityExist(veh) then return end

  ensureBase(veh, GetEntityModel(veh))
  local ratio = (Config and Config.skillGripMinRatio) or 0.85

  for axis, m in pairs(bands()) do
    local v = tonumber(hnd[axis])
    if v then
      -- re-clamp local (defesa em profundidade: payload do servidor é tratado como hostil)
      local lo, hi = math.min(m.min, m.max), math.max(m.min, m.max)
      v = math.max(lo, math.min(hi, v))
      SetVehicleHandlingFloat(veh, 'CHandlingData', m.field, v + 0.0)

      -- grip mexe no teto E no piso da curva de tração (mantém Min < Max)
      if axis == 'grip' then
        SetVehicleHandlingFloat(veh, 'CHandlingData', 'fTractionCurveMin', v * ratio + 0.0)
      end
    end
  end

  -- OVERLAY: stance (delta sobre base) + knobs livres. Campos DISJUNTOS dos 5 eixos →
  -- nunca colidem. Presente na ficha = aplica clampado; AUSENTE = volta à base (para o
  -- SHEET_UPDATED refletir corretamente um knob desligado sem esperar sair do carro).
  local base = _modelBase[GetEntityModel(veh)] or {}
  for axis, m in pairs(extBands()) do
    local v = tonumber(hnd[axis])
    local target
    if v then
      if m.mode == 'delta' then
        v = (base[m.field] or GetVehicleHandlingFloat(veh, 'CHandlingData', m.field)) + v
      end
      local lo, hi = math.min(m.min, m.max), math.max(m.min, m.max)
      target = math.max(lo, math.min(hi, v))
    else
      target = base[m.field]   -- ausente = restaura base do modelo
    end
    if target ~= nil then
      SetVehicleHandlingFloat(veh, 'CHandlingData', m.field, target + 0.0)
    end
  end

  -- prova em jogo: LÊ DE VOLTA o valor após aplicar — se "lido" != "alvo", o native não pegou
  if Config and Config.skillDebug then
    dbg(('aplicado: forca=%.3f grip=%.2f freio=%.2f drag=%.1f'):format(
      GetVehicleHandlingFloat(veh, 'CHandlingData', 'fInitialDriveForce'),
      GetVehicleHandlingFloat(veh, 'CHandlingData', 'fTractionCurveMax'),
      GetVehicleHandlingFloat(veh, 'CHandlingData', 'fBrakeForce'),
      GetVehicleHandlingFloat(veh, 'CHandlingData', 'fInitialDragCoeff')))
  end
end


-- ============================================================
-- GATILHOS (event-driven — pendurados na thread de motorista do main.lua)
-- ============================================================

-- virei motorista desta placa → peço a ficha; o servidor responde SHEET com hnd
AddEventHandler(E.BECAME_DRIVER, function(veh, plate)
  _drivenVeh   = veh or 0
  _drivenPlate = normPlate(plate)
  if Config and Config.skillApplyHandling and plate and plate ~= '' then
    dbg('motorista ' .. tostring(plate) .. ' -> pedindo ficha')
    TriggerServerEvent(E.REQ_SHEET, plate)
  elseif Config and not Config.skillApplyHandling then
    dbg('skillApplyHandling=false (fisica desligada)')
  end
end)

-- saí do banco do motorista → restauro o handling base do modelo
AddEventHandler(E.LEFT_VEHICLE, function(veh)
  restoreBase((veh and veh ~= 0) and veh or _drivenVeh)
  _drivenVeh   = 0
  _drivenPlate = ''
end)

-- ficha ATUALIZADA ao vivo (tuning/stance mudou enquanto dirijo) → reaplica no carro atual.
-- Server manda SÓ p/ o motorista (nunca -1). Filtra por placa: ignora se não é a que dirijo.
RegisterNetEvent(E.SHEET_UPDATED)
AddEventHandler(E.SHEET_UPDATED, function(plate, sheet)
  if _drivenVeh == 0 or _drivenPlate == '' then return end
  if normPlate(plate) ~= _drivenPlate then return end
  if type(sheet) ~= 'table' then return end
  applyHnd(_drivenVeh, sheet.hnd)
end)

-- ficha chegou (REQ_SHEET) → aplica hnd no carro dirigido (ignora se não estou dirigindo)
RegisterNetEvent(E.SHEET)
AddEventHandler(E.SHEET, function(sheet)
  if _drivenVeh == 0 then return end
  if type(sheet) ~= 'table' then dbg('ficha NULA (carro sem p1?)'); return end
  dbg('ficha recebida, hnd=' .. (type(sheet.hnd) == 'table' and 'SIM' or 'NAO'))
  applyHnd(_drivenVeh, sheet.hnd)
end)

-- recalibração concluída → reaplica o hnd novo no carro dirigido
RegisterNetEvent(E.RECAL_DONE)
AddEventHandler(E.RECAL_DONE, function(ok, _msg, _kind, sheet)
  if ok and _drivenVeh ~= 0 and type(sheet) == 'table' then applyHnd(_drivenVeh, sheet.hnd) end
end)


-- ============================================================
-- CLEANUP
-- ============================================================

-- ao parar o resource, restaura o modelo atualmente sob override (anti-vazamento)
AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  if _drivenVeh ~= 0 and DoesEntityExist(_drivenVeh) then restoreBase(_drivenVeh) end
end)
