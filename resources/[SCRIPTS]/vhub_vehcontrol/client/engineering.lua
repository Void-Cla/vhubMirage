---@diagnostic disable: undefined-global, lowercase-global

-- client/engineering.lua — L2/HAL: aplica a CAMADA A (per-entidade, SEGURA) da física de peças.
--
-- ADR #82 FASE 2. Irmão de client/handling.lua (que é a Camada B model-wide, DESLIGADA).
-- Aqui aplicamos SÓ potência + velocidade máxima, via natives PER-ENTIDADE confirmadas seguras
-- pelo gate de natives (SetVehicleCheatPowerIncrease / ModifyVehicleTopSpeed). Elas NÃO tocam
-- CHandlingData — dois carros do mesmo modelo podem ter potências diferentes (objetivo da fase).
--
-- ESCRITOR ÚNICO de SetVehicleCheatPowerIncrease (L-04/L-16): os números vêm do SERVIDOR
-- (sheet.eng, derivado de tier_rules/engineering a partir das peças persistidas). O cliente SÓ
-- aplica, no carro que DIRIGE (seat -1), e RESTAURA a base ao sair. Nunca inventa, nunca persiste.
--
-- CONTRATO com overlays efêmeros (nitro): o boost químico SOMA sobre a base per-entidade e, ao
-- terminar, chama TriggerEvent('vhub_vehcontrol:reapplyBase', veh) — NÃO hardcode 0.0. Assim a
-- base de engenharia sobrevive ao fim do nitro. Com Config.applyPerEntity=false, a base é 0.0
-- (comportamento idêntico ao legado — zero regressão na migração).


-- ============================================================
-- ESTADO
-- ============================================================

local E            = VHubVeh.E
local _drivenVeh   = 0     -- veículo dirigido agora (0 = nenhum)
local _drivenPlate = ''    -- placa do veículo dirigido (filtra SHEET_UPDATED)
local _base        = {}    -- [veh] = { power=<abs>, top=<abs> } base per-entidade aplicada


-- ============================================================
-- HELPERS
-- ============================================================

-- soma 1e-5 p/ garantir que o valor cruze a fronteira float da native (padrão do nitro.lua)
local function f(n) return (tonumber(n) or 0.0) + 0.00001 end

-- normaliza placa p/ comparação (espelha o servidor: upper + trim)
local function normPlate(p)
  return (tostring(p or ''):upper():gsub('%s+', ' '):match('^%s*(.-)%s*$')) or ''
end

-- valores de base derivados do sheet.eng (ou 0 quando a Camada A está desligada / sem peça)
local function baseFromSheet(sheet)
  if not (Config and Config.applyPerEntity) then return 0.0, 0.0 end
  local eng = (type(sheet) == 'table' and type(sheet.eng) == 'table') and sheet.eng or nil
  if not eng then return 0.0, 0.0 end
  local power = tonumber(eng.power_boost) or 0.0
  local top   = tonumber(eng.top_speed_pct) or 0.0
  -- clamp defensivo (payload do servidor é tratado como hostil, mesmo sendo próprio)
  power = math.max(0.0, math.min(1.0, power))   -- SetVehicleCheatPowerIncrease: fração de boost
  top   = math.max(0.0, math.min(0.5, top))     -- ModifyVehicleTopSpeed: % de acréscimo (teto conservador)
  return power, top
end


-- ============================================================
-- APLICAÇÃO (escritor único da BASE per-entidade)
-- ============================================================

-- aplica a base ABSOLUTA no veículo (idempotente — natives são "set", não acumulam).
-- Guarda o par aplicado em _base[veh] p/ o overlay do nitro reconstruir a base depois.
local function applyBase(veh, power, top)
  if not veh or veh == 0 or not DoesEntityExist(veh) then return end
  SetVehicleCheatPowerIncrease(veh, f(power))
  ModifyVehicleTopSpeed(veh, f(top))
  _base[veh] = { power = power or 0.0, top = top or 0.0 }
end

-- restaura a base per-entidade (chamado pelo nitro no fim do boost, via REAPPLY_BASE).
-- Com applyPerEntity=false, a base registrada é 0.0 → equivale ao reset legado (zero regressão).
local function reapplyBase(veh)
  if not veh or veh == 0 or not DoesEntityExist(veh) then return end
  local b = _base[veh]
  applyBase(veh, b and b.power or 0.0, b and b.top or 0.0)
end
VHubVeh.reapplyBase = reapplyBase   -- interno ao resource (handling/main reusam se preciso)

-- zera a base per-entidade (saída do carro) — devolve o veículo ao .meta
local function clearBase(veh)
  if not veh or veh == 0 or not DoesEntityExist(veh) then _base[veh] = nil; return end
  SetVehicleCheatPowerIncrease(veh, 0.0)
  ModifyVehicleTopSpeed(veh, 0.0)
  _base[veh] = nil
end


-- ============================================================
-- GATILHOS (event-driven — sem loop, custo O(1) por virada de motorista — L-18)
-- ============================================================

-- virei motorista → peço a ficha (mesmo REQ_SHEET do handling; o SHEET traz sheet.eng)
AddEventHandler(E.BECAME_DRIVER, function(veh, plate)
  _drivenVeh   = veh or 0
  _drivenPlate = normPlate(plate)
  if Config and Config.applyPerEntity and plate and plate ~= '' then
    TriggerServerEvent(E.REQ_SHEET, plate)
  end
end)

-- saí do motorista → restauro a base (.meta). Não vaza boost per-entidade pela sessão.
AddEventHandler(E.LEFT_VEHICLE, function(veh)
  clearBase((veh and veh ~= 0) and veh or _drivenVeh)
  _drivenVeh   = 0
  _drivenPlate = ''
end)

-- ficha chegou (REQ_SHEET) → aplica a base no carro dirigido
RegisterNetEvent(E.SHEET)
AddEventHandler(E.SHEET, function(sheet)
  if _drivenVeh == 0 then return end
  applyBase(_drivenVeh, baseFromSheet(sheet))
end)

-- ficha ATUALIZADA ao vivo (peça instalada enquanto dirijo) → reaplica. Filtra por placa.
RegisterNetEvent(E.SHEET_UPDATED)
AddEventHandler(E.SHEET_UPDATED, function(plate, sheet)
  if _drivenVeh == 0 or _drivenPlate == '' then return end
  if normPlate(plate) ~= _drivenPlate then return end
  applyBase(_drivenVeh, baseFromSheet(sheet))
end)

-- overlay efêmero (nitro) pediu p/ restaurar a base após o boost — CONTRATO F2.0.
-- Aceita string 'vhub_vehcontrol:reapplyBase' cross-resource (nitro emite por literal).
AddEventHandler(E.REAPPLY_BASE, function(veh)
  reapplyBase(veh)
end)


-- ============================================================
-- CLEANUP
-- ============================================================

AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  if _drivenVeh ~= 0 and DoesEntityExist(_drivenVeh) then clearBase(_drivenVeh) end
end)
