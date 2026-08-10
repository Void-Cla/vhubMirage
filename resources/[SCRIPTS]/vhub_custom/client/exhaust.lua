-- client/exhaust.lua — L2/HAL: chamas coloridas no escapamento (SEGURAS, não-ignitáveis).
--
-- ATENÇÃO histórica: o antigo fogo usava PTFX LOOPADO 'ent_amb_trash_fire' preso à entidade,
-- que INCENDIAVA o carro (queimava/quebrava sozinho). Aqui o efeito é backfire NÃO-LOOPADO
-- (veh_backfire), disparado em levas curtas no carro DIRIGIDO ao acelerar forte / em rotação
-- alta. Nunca incendeia. A cor vem do State Bag `vhub_custom:exhaust` (setado pelo servidor a
-- partir da placa). Estado persistido = customization.exhaust_fx = { enabled, r, g, b, scale }.
---@diagnostic disable: undefined-global

local BAG = VHubCustom.BAG

local EX = {}; VHubCustom.Exhaust = EX

local FX_ASSET = 'core'
local FX_NAME  = 'veh_backfire'
local BONES    = { 'exhaust', 'exhaust_2', 'exhaust_3', 'exhaust_4', 'exhaust_5', 'exhaust_6' }

local _cfg = {}   -- [entity] = { enabled, r, g, b, scale }


-- dispara UMA leva de chamas coloridas (não-loopado) no(s) bone(s) de escapamento.
-- Estratégia de posicionamento (entity-local — efeito SEGUE o veículo sem lag):
--   1. GetEntityBonePosition_2(veh, idx)            → posição MUNDIAL do bone
--   2. GetOffsetFromEntityGivenWorldCoords(veh, ...) → converte mundial→local-entidade
--   3. StartParticleFxNonLoopedOnEntity com o offset convertido
-- Ambas em pcall (natives não são conhecidas no meta Rockstar → podem ser nil em builds
-- futuros). Fallback: dual-offset traseiro simulado (±0.35m) caso os bones não existam.
local function pop(veh, c)
  if not veh or veh == 0 or not DoesEntityExist(veh) then return end
  if not HasNamedPtfxAssetLoaded(FX_ASSET) then RequestNamedPtfxAsset(FX_ASSET); return end
  local r  = (tonumber(c.r) or 255) / 255
  local g  = (tonumber(c.g) or 80)  / 255
  local b  = (tonumber(c.b) or 0)   / 255
  local sc = math.max(0.4, math.min(3.0, tonumber(c.scale) or 1.0))

  local function fire(ox, oy, oz)
    UseParticleFxAssetNextCall(FX_ASSET)
    SetParticleFxNonLoopedColour(r, g, b)
    SetParticleFxNonLoopedAlpha(1.0)
    StartParticleFxNonLoopedOnEntity(FX_NAME, veh, ox + 0.0, oy + 0.0, oz + 0.0,
                                     0.0, 0.0, 0.0, sc, false, false, false)
  end

  local fired = false
  for _, boneName in ipairs(BONES) do
    local idx = GetEntityBoneIndexByName(veh, boneName)
    if idx ~= -1 then
      -- GetEntityBonePosition_2 = GET_ENTITY_BONE_POSTION (nome FiveM, typo no original Rockstar)
      local okW, wp = pcall(function() return GetEntityBonePosition_2(veh, idx) end)
      if okW and wp and wp.x then
        -- GetOffsetFromEntityGivenWorldCoords converte coordenada mundial → local-entidade
        local okL, lo = pcall(function()
          return GetOffsetFromEntityGivenWorldCoords(veh, wp.x, wp.y, wp.z)
        end)
        if okL and lo and lo.x then
          fire(lo.x, lo.y, lo.z)
          fired = true
        end
      end
    end
  end

  if not fired then
    -- fallback: dual-escapamento simulado (±0.35m, traseira) — melhor que centro único
    fire(-0.35, -1.8, 0.2)
    fire( 0.35, -1.8, 0.2)
  end
end

-- preview do bennys: uma leva imediata p/ o jogador ver a cor escolhida
function EX.preview(veh, c)
  if type(c) == 'table' and c.enabled then pop(veh, c) end
end


-- ============================================================
-- SYNC — State Bag guarda a config por entidade
-- ============================================================

AddStateBagChangeHandler(BAG.EXHAUST, nil, function(bagName, _, value)
  local ent = GetEntityFromStateBagName(bagName)
  if not ent or ent == 0 then return end
  _cfg[ent] = (type(value) == 'table' and value.enabled == true) and value or nil
end)


-- ============================================================
-- MOTOR — dispara chamas ao acelerar forte no carro que DIRIJO (budget O(1))
-- ============================================================

-- budget (L-18): 500 ms ocioso, 60 ms só dirigindo com fx ativo. O(1) por player (só o local).
CreateThread(function()
  RequestNamedPtfxAsset(FX_ASSET)
  local lastPop = 0
  while true do
    local wait = 500
    local ped  = PlayerPedId()
    local veh  = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then
      local c = _cfg[veh]
      if c and c.enabled then
        local now = GetGameTimer()
        local rpm = GetVehicleCurrentRpm(veh)
        local revving = IsControlPressed(0, 71) and rpm > 0.75   -- acelerando em rotação alta
        if (revving or rpm > 0.92) and (now - lastPop) > 220 then
          pop(veh, c); lastPop = now
        end
        wait = 60
      end
    end
    Wait(wait)
  end
end)

AddEventHandler('onResourceStop', function(res)
  if res == GetCurrentResourceName() then _cfg = {} end
end)
