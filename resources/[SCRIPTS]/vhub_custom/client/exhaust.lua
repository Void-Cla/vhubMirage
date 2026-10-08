-- client/exhaust.lua — emissor único de backfire cosmético, preview e nitro; sem fogo ambiental.
---@diagnostic disable: undefined-global

local BAG, NCfg = VHubCustom.BAG, VHubCustom.NitroCfg
local EX = {}; VHubCustom.Exhaust = EX
local FX = VHubCustom.cfg and VHubCustom.cfg.exhaust_fx
if type(FX) ~= 'table' then FX = {} end
local _running = true
local _cache = nil       -- somente a última entidade; no máximo 16 bones únicos
local _lastVeh, _lastPop = nil, nil
local _nitroVeh, _nitroUntil = nil, 0
local _assetRequestedAt, _assetFailed, _warned = nil, false, {}
local _diagnosticToken, _diagnosticActive = 0, false
local _diagnosticLastEmission = nil

local function finite(value, minimum, maximum)
  local number = tonumber(value)
  if not number or number ~= number or math.abs(number) == math.huge then return nil end
  return math.max(minimum, math.min(maximum, number))
end

EX.intervalMs = finite(FX.interval_ms, 200, 2000) or 450

local function provedor()
  local function falha(motivo)
    if not _warned[motivo] then VHubCustom.log('escapamento indisponível: ' .. motivo); _warned[motivo] = true end
    return nil
  end
  if type(FX.asset) ~= 'string' or #FX.asset < 1 or #FX.asset > 64 or not FX.asset:match('^[%w_-]+$')
      or type(FX.effect) ~= 'string' or #FX.effect < 1 or #FX.effect > 64 or not FX.effect:match('^[%w_-]+$')
      or (FX.colour_mode ~= 'fixed' and FX.colour_mode ~= 'rgb') then return falha('configuração inválida') end
  if FX.resource ~= nil and (type(FX.resource) ~= 'string' or GetResourceState(FX.resource) ~= 'started') then
    return falha('recurso de partículas não iniciado')
  end
  if _assetFailed then return nil end
  if not HasNamedPtfxAssetLoaded(FX.asset) then
    if not _assetRequestedAt then RequestNamedPtfxAsset(FX.asset); _assetRequestedAt = GetGameTimer() end
    if GetGameTimer() - _assetRequestedAt >= 5000 then _assetFailed = true; return falha('dicionário PTFX não carregou em 5 s') end
    return nil
  end
  return FX
end

-- Reflete capacidade declarada do PTFX carregado; não promete recoloração do backfire nativo.
function EX.supportsRGB()
  return provedor() ~= nil and FX.colour_mode == 'rgb'
end

local function visual(value)
  if type(value) ~= 'table' then return nil end
  local r, g, b = finite(value.r, 0, 255), finite(value.g, 0, 255), finite(value.b, 0, 255)
  if not r or not g or not b then return nil end
  local escala = (finite(value.scale, 0.5, 3.0) or 1.0) * (finite(FX.scale_factor, 0.1, 1.0) or 0.5)
  return { r = r, g = g, b = b, scale = math.min(escala, finite(FX.max_scale, 0.2, 1.5) or 1.5) }
end

-- Geometria não é saturada: dado inválido não pode criar uma saída artificial no limite.
local function vetor(value, limite)
  if type(value) ~= 'table' and type(value) ~= 'vector3' then return nil end
  local x, y, z = tonumber(value.x), tonumber(value.y), tonumber(value.z)
  for _, eixo in ipairs({x or false, y or false, z or false}) do
    if not eixo or eixo ~= eixo or math.abs(eixo) == math.huge or math.abs(eixo) > limite then return nil end
  end
  return vec3(x, y, z)
end

local function outlets(veh)
  local model, mod, extras = GetEntityModel(veh), GetVehicleMod(veh, 4), 0
  for id = 0, 20 do
    if IsVehicleExtraTurnedOn(veh, id) then extras = extras | (1 << id) end
  end
  if _cache and _cache.veh == veh and _cache.model == model
      and _cache.mod == mod and _cache.extras == extras then return _cache end
  local perfis = type(FX.model_outlets) == 'table' and FX.model_outlets[model]
  local perfil = type(perfis) == 'table' and (perfis[mod] or perfis.default) or nil
  local indices, seen = {}, {}
  for i = 0, 16 do
    local nome = i == 0 and 'exhaust' or ('exhaust_' .. i)
    local index = GetEntityBoneIndexByName(veh, nome)
    if index and index >= 0 and not seen[index] then
      indices[#indices + 1], seen[index] = { index = index, nome = nome }, true
      if #indices == 16 then break end
    end
  end
  _cache = { veh = veh, model = model, mod = mod, extras = extras, indices = indices, perfil = perfil }
  return _cache
end

-- Resolve bocas únicas com posições/rotações atuais; jamais inventa duas saídas pelo chassi.
local function saidas(veh)
  local cache, resultado, pontos = outlets(veh), {}, {}
  local avanco = finite(FX.outlet_push, 0.0, 0.5) or 0.12
  local function adicionar(nome, pos, rot)
    pos, rot = vetor(pos, 20), vetor(rot, 360)
    if not pos or not rot or pos.x*pos.x + pos.y*pos.y + pos.z*pos.z < 0.0025 then return end
    local chave = ('%d:%d:%d'):format(math.floor(pos.x*20+0.5), math.floor(pos.y*20+0.5),
      math.floor(pos.z*20+0.5))
    if pontos[chave] or #resultado >= 16 then return end
    pontos[chave] = true
    -- Chama/glow dos YPT privados apontam -Y. Pitch/yaw locais orientam a extrusão.
    local pitch, yaw = math.rad(rot.x), math.rad(rot.z)
    local direcao = vec3(math.sin(yaw)*math.cos(pitch), -math.cos(yaw)*math.cos(pitch), -math.sin(pitch))
    resultado[#resultado + 1] = { nome = nome, pos = pos, rot = rot, direcao = direcao,
      origem = vec3(pos.x + direcao.x*avanco, pos.y + direcao.y*avanco, pos.z + direcao.z*avanco) }
  end
  if cache.perfil ~= nil then
    if type(cache.perfil) == 'table' and #cache.perfil <= 16 then
      for i, item in ipairs(cache.perfil) do
        if type(item) == 'table' then adicionar('perfil:' .. i, item.pos, item.rot) end
      end
    end
  else
    for _, bone in ipairs(cache.indices) do
      local world = vetor(GetWorldPositionOfEntityBone(veh, bone.index), math.huge)
      if world then
        adicionar(bone.nome, GetOffsetFromEntityGivenWorldCoords(veh, world.x, world.y, world.z),
          GetEntityBoneRotationLocal(veh, bone.index))
      end
    end
  end
  if #resultado == 0 and not cache.avisado then
    cache.avisado = true
    VHubCustom.log(('sem saídas válidas de escapamento: modelo=%s mod4=%s; conferir /vhub_escapamento e model_outlets')
      :format(cache.model, cache.mod))
  end
  return resultado, cache
end

local function pop(veh, config, networked)
  if not _running or not veh or veh == 0 or not DoesEntityExist(veh) then return false end
  if networked then
    local ped = PlayerPedId()
    if GetVehiclePedIsIn(ped, false) ~= veh or GetPedInVehicleSeat(veh, -1) ~= ped
        or not NetworkHasControlOfEntity(veh) then return false end
  end
  local now = GetGameTimer()
  if _lastVeh == veh and _lastPop and now - _lastPop < EX.intervalMs then return false end
  if not provedor() then return false end
  _lastVeh, _lastPop = veh, now -- inclusive preview/falha: não empilha tentativas no mesmo pulso
  local r, g, b = config.r / 255.0, config.g / 255.0, config.b / 255.0
  local function fire(saida)
    UseParticleFxAssetNextCall(FX.asset)
    if FX.colour_mode == 'rgb' then SetParticleFxNonLoopedColour(r, g, b)
    else SetParticleFxNonLoopedColour(1.0, 1.0, 1.0) end
    SetParticleFxNonLoopedAlpha(1.0)
    local native = networked and StartNetworkedParticleFxNonLoopedOnEntity or StartParticleFxNonLoopedOnEntity
    local pos, rot = saida.origem, saida.rot
    return native(FX.effect, veh, pos.x + 0.0, pos.y + 0.0, pos.z + 0.0,
      rot.x + 0.0, rot.y + 0.0, rot.z + 0.0, config.scale + 0.0, false, false, false) == true
  end
  local emitted, lista = false, saidas(veh)
  if _diagnosticActive and #lista > 0
      and (not _diagnosticLastEmission or now - _diagnosticLastEmission >= 1000) then
    _diagnosticLastEmission = now
    local origem, rot = lista[1].origem, lista[1].rot
    VHubCustom.log(('PTFX tentativa %s: veículo=%s escala=%.3f saídas=%d RGB=%.3f,%.3f,%.3f primeira=%s origem=%.3f,%.3f,%.3f rot=%.3f,%.3f,%.3f')
      :format(networked and 'rede' or 'preview', veh, config.scale, #lista, config.r, config.g, config.b,
        lista[1].nome, origem.x, origem.y, origem.z, rot.x, rot.y, rot.z))
  end
  for _, saida in ipairs(lista) do emitted = fire(saida) or emitted end
  return emitted
end

-- Diagnóstico local por 10 s: boca laranja, origem verde, linha de direção; sem emitir PTFX.
RegisterCommand('vhub_escapamento', function()
  _diagnosticToken = _diagnosticToken + 1
  if _diagnosticActive then _diagnosticActive = false; return end
  if not _running then return end
  local veh = GetVehiclePedIsIn(PlayerPedId(), false)
  if veh == 0 and VHubCustom.inMenu then veh = VHubCustom.activeVeh end
  if not veh or veh == 0 or not DoesEntityExist(veh) then
    return VHubCustom.log('diagnóstico: entre no veículo ou abra a oficina')
  end
  local lista, cache = saidas(veh)
  VHubCustom.log(('escapamento %s: modelo=%s mod4=%s extras=%s bones=%d saídas=%d fonte=%s; laranja=boca verde=chama')
    :format(GetDisplayNameFromVehicleModel(cache.model), cache.model, cache.mod, cache.extras,
      #cache.indices, #lista, cache.perfil ~= nil and 'perfil' or 'bones'))
  for i, saida in ipairs(lista) do
    local p, r = saida.pos, saida.rot
    VHubCustom.log(('%d %s: pos=vec3(%.3f,%.3f,%.3f), rot=vec3(%.3f,%.3f,%.3f)')
      :format(i, saida.nome, p.x, p.y, p.z, r.x, r.y, r.z))
  end
  _diagnosticActive = true
  _diagnosticLastEmission = nil
  local token, limite, atualizar = _diagnosticToken, GetGameTimer() + 10000, GetGameTimer() + 250
  CreateThread(function()
    -- Somente diagnóstico solicitado: <=16 saídas, leitura geométrica 4 Hz, desenho por frame por 10 s.
    while _running and _diagnosticActive and token == _diagnosticToken
        and DoesEntityExist(veh) and GetGameTimer() < limite do
      if GetGameTimer() >= atualizar then lista = saidas(veh); atualizar = GetGameTimer() + 250 end
      for _, saida in ipairs(lista) do
        local p, o, d = saida.pos, saida.origem, saida.direcao
        local boca = GetOffsetFromEntityInWorldCoords(veh, p.x, p.y, p.z)
        local origem = GetOffsetFromEntityInWorldCoords(veh, o.x, o.y, o.z)
        local fim = GetOffsetFromEntityInWorldCoords(veh, o.x+d.x*0.5, o.y+d.y*0.5, o.z+d.z*0.5)
        DrawMarker(28, boca.x,boca.y,boca.z, 0.0,0.0,0.0, 0.0,0.0,0.0,
          0.06,0.06,0.06, 255,140,0,220, false,false,2,false,nil,nil,false)
        DrawMarker(28, origem.x,origem.y,origem.z, 0.0,0.0,0.0, 0.0,0.0,0.0,
          0.04,0.04,0.04, 0,255,80,220, false,false,2,false,nil,nil,false)
        DrawLine(origem.x,origem.y,origem.z, fim.x,fim.y,fim.z, 0,255,80,255)
      end
      Wait(0)
    end
    if token == _diagnosticToken then _diagnosticActive = false end
  end)
end, false)

-- Preview local: não replica nem altera o estado persistido.
function EX.preview(veh, config)
  local clean = visual(config)
  if clean and config.enabled == true then return pop(veh, clean, false) end
  return false
end

-- Nitro usa exclusivamente o kit de chamas ativo da oficina, com a mesma escala/cor/cadência.
function EX.nitro(veh)
  if not _running or VHubCustom.inMenu or not NCfg.exhaustFire or not veh or veh == 0 or not DoesEntityExist(veh) then return false end
  local saved = Entity(veh).state[BAG.EXHAUST]
  if type(saved) ~= 'table' or saved.enabled ~= true then return false end
  local config = visual(saved); if not config then return false end
  _nitroVeh, _nitroUntil = veh, GetGameTimer() + EX.intervalMs + 100
  return pop(veh, config, true)
end

-- Budget: 500 ms ocioso/menu; 60 ms somente motorista com FX ativo; <= 2,23 levas/s padrão.
-- Preview/nitro/backfire compartilham cadência; até 16 saídas únicas, sem fallback geométrico.
CreateThread(function()
  provedor()
  while _running do
    local wait, ped = 500, PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if not VHubCustom.inMenu and veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then
      -- Leitura O(1) da entidade atual: não perde configuração por culling/restart do resource.
      local saved = Entity(veh).state[BAG.EXHAUST]
      local config = visual(saved)
      if config and saved.enabled == true then
        wait = 60
        local now, rpm = GetGameTimer(), GetVehicleCurrentRpm(veh)
        if not (_nitroVeh == veh and now < _nitroUntil)
            and ((IsControlPressed(0, 71) and rpm > 0.75) or rpm > 0.92) then
          pop(veh, config, true)
        end
      end
    else
      _cache = nil -- cooldown sobrevive ao menu/saída/reentrada para não duplicar preview
    end
    Wait(wait)
  end
end)

AddEventHandler('onResourceStop', function(resource)
  if resource ~= GetCurrentResourceName() then return end
  _running = false
  _diagnosticActive = false
  _cache, _lastVeh, _lastPop, _nitroVeh = nil, nil, nil, nil
end)
