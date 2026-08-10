-- server/init.lua — handshake autoritativo dos serviços veiculares
---@diagnostic disable: undefined-global

local Core = VHubCustom.Core
local SQL  = VHubCustom.SQL
local E    = VHubCustom.E

local DOMAINS = { bennys = true, mec = true, oficina = true }
local TRUSTED_SERVICE_CALLERS = { vhub_admin = true, vhub_garage = true }
local ERRORS = {
  session = 'Personagem não carregado.', shape = 'Solicitação inválida.',
  ped = 'Jogador indisponível.', entity = 'Veículo não encontrado na rede.',
  distance = 'Jogador ou veículo fora da área de serviço.', bucket = 'Instância inconsistente.',
  moving = 'Pare o veículo antes de usar o serviço.', plate = 'Placa inconsistente.',
  occupied = 'O motorista deve sair do veículo.', forbidden = 'Sem autorização para este veículo.',
  state = 'Veículo indisponível no prontuário.', model = 'Modelo do veículo inconsistente.',
}

local function authorizeService(src, domain, zoneId, plate, netId)
  src = tonumber(src)
  if not SQL.ready then return false, 'Oficina inicializando.' end
  if not src or src <= 0 or src % 1 ~= 0 then return false, 'Jogador inválido.' end
  if not Core.rateOK(src, 'service_auth') then return false, 'Aguarde um instante.' end
  if type(domain) ~= 'string' or not DOMAINS[domain] then return false, 'Serviço inválido.' end

  local context, why = Core.validateVehicle(src, domain, plate, netId, zoneId)
  if not context then
    if why == 'plate' or why == 'model' or why == 'bucket' then
      Core.log(plate, 'service_auth_blocked_' .. tostring(why), Core.getCharId(src) or '?', { net_id = netId })
    end
    return false, ERRORS[why] or 'Acesso negado.'
  end

  local sheet, installedParts, partsStatus, oficinaCap
  if domain == 'oficina' then
    local ok, value = pcall(function() return exports.vhub_vehcontrol:getVehicleSheet(context.plate) end)
    if ok then sheet = value end
    local st; pcall(function() st = Core.getVehicleState(context.plate) end)
    local cust = (st and type(st.customization) == 'table') and st.customization or {}
    local curParts = type(cust.parts) == 'table' and cust.parts or {}
    -- ADR #82 F2.3: ids das peças instaladas (customization.parts truthy) — mantido p/ compat.
    if type(cust.parts) == 'table' then
      installedParts = {}
      for id, v in pairs(cust.parts) do
        if v ~= nil and v ~= false then installedParts[id] = true end
      end
    end
    -- ADR #85 D1: STATUS por peça pelo MESMO juízo do install (glue Core.computePartsStatus) — a NUI
    -- desenha estados honestos (ok/já-instalada/incompatível/dependência/sem-item) + hint + substitui.
    -- Não persiste; recomputado a cada auth/refreshSheet.
    oficinaCap = Core.stageCap(context.vehicle, sheet)
    partsStatus = Core.computePartsStatus(src, oficinaCap, curParts)
  end

  -- campos "virtuais" persistidos (não vivem na entidade: PTFX/RP/índice) — a UI do bennys
  -- inicializa por eles, senão o snapshot da entidade viva sempre mostraria default no reabrir.
  local saved
  if domain == 'bennys' then
    local st; pcall(function() st = Core.getVehicleState(context.plate) end)
    local cust = (st and type(st.customization) == 'table') and st.customization or {}
    saved = {
      exhaust_fx  = type(cust.exhaust_fx) == 'table' and cust.exhaust_fx or nil,
      stance      = type(cust.stance) == 'table' and cust.stance or nil,
      glass_armor = cust.glass_armor,
    }
  end

  local lease = Core.issueLease(context)
  local meta = Core.vehicleMeta(context.vehicle)
  return true, nil, {
    lease_id = lease.id,
    plate = context.plate,
    net_id = context.net_id,
    name = meta.name,
    category = meta.category,
    stage_cap = oficinaCap,
    sheet = sheet,
    installed_parts = installedParts,
    parts_status = partsStatus,   -- ADR #85 D1: estados honestos por peça (juízo único server-side)
    saved = saved,
  }
end

local function replyService(src, domain, ok, message, data)
  TriggerClientEvent(E.SERVICE_AUTH_OK, src, domain, ok == true, message, data)
end

RegisterNetEvent(E.SERVICE_AUTH)
AddEventHandler(E.SERVICE_AUTH, function(domain, zoneId, plate, netId)
  local src = source
  local ok, message, data = authorizeService(src, domain, zoneId, plate, netId)
  replyService(src, domain, ok, message, data)
end)

-- Abre um serviço para integrações server-side autorizadas, mantendo a mesma prova física.
exports('beginService', function(src, domain, zoneId, plate, netId)
  local caller = GetInvokingResource()
  if caller and not TRUSTED_SERVICE_CALLERS[caller] then return false, 'forbidden' end
  local ok, message, data = authorizeService(src, domain, zoneId, plate, netId)
  replyService(tonumber(src) or 0, domain, ok, message, data)
  return ok, message
end)

AddEventHandler('onResourceStart', function(resource)
  if resource == GetCurrentResourceName() then
    Citizen.CreateThread(function()
      local ok, err = SQL.applySchema()
      if not ok then
        VHubCustom.log('[CRITICAL] schema da saga indisponível | err=' .. tostring(err))
        return
      end
      Core.startRecovery()
      VHubCustom.log('iniciado — autoridade física, saga e serviços prontos')
    end)
  end
end)

AddEventHandler('onResourceStop', function(resource)
  if resource == GetCurrentResourceName() then Core.stop(); VHubCustom.log('encerrado') end
end)
