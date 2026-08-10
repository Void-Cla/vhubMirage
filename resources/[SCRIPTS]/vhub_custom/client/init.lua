-- client/init.lua — lifecycle e intenção de abertura dos serviços
---@diagnostic disable: undefined-global

VHubCustom           = VHubCustom or {}
VHubCustom.running   = true
VHubCustom.near      = nil
VHubCustom.inMenu    = false
VHubCustom.opening   = nil
VHubCustom.service   = nil
VHubCustom.activeVeh = nil

local E = VHubCustom.E
local requestSeq = 0

for _, zone in ipairs(VHubCustom.cfg.zones) do zone._vec = vec3(zone.x, zone.y, zone.z) end

local function plateOf(vehicle)
  return (GetVehicleNumberPlateText(vehicle) or ''):upper():gsub('%s+', ' '):match('^%s*(.-)%s*$')
end

function VHubCustom.nextRequestId()
  requestSeq = (requestSeq + 1) % 0x10000
  return ('r%08x%04x'):format(math.abs(GetGameTimer()) % 0xffffffff, requestSeq)
end

function VHubCustom.endService(domain)
  if not domain or (VHubCustom.service and VHubCustom.service.domain == domain) then
    VHubCustom.service = nil
  end
end

function VHubCustom.requestService(zone, vehicle)
  if VHubCustom.inMenu or VHubCustom.opening or not DoesEntityExist(vehicle)
      or not NetworkGetEntityIsNetworked(vehicle) then return end
  local netId, plate = NetworkGetNetworkIdFromEntity(vehicle), plateOf(vehicle)
  if not netId or netId == 0 or not plate or plate == '' then
    return VHubCustom.notify('Veículo sem identidade de rede válida.', 'error')
  end

  local marker = VHubCustom.nextRequestId()
  VHubCustom.opening = { id = marker, domain = zone.domain, zone = zone }
  VHubCustom.activeVeh, VHubCustom.activeVehNet, VHubCustom.activePlate = vehicle, netId, plate
  TriggerServerEvent(E.SERVICE_AUTH, zone.domain, zone.id, plate, netId)

  SetTimeout(5000, function()
    if VHubCustom.opening and VHubCustom.opening.id == marker then
      VHubCustom.opening = nil
      VHubCustom.notify('Tempo esgotado ao autorizar o serviço.', 'error')
    end
  end)
end

RegisterNetEvent(E.SERVICE_AUTH_OK)
AddEventHandler(E.SERVICE_AUTH_OK, function(domain, ok, message, data)
  local opening = VHubCustom.opening
  if not opening or opening.domain ~= domain then return end
  VHubCustom.opening = nil
  if not ok or type(data) ~= 'table' then
    VHubCustom.service = nil
    return VHubCustom.notify(message or 'Acesso negado.', 'error')
  end

  local vehicle = VHubCustom.activeVeh
  if not DoesEntityExist(vehicle) or NetworkGetNetworkIdFromEntity(vehicle) ~= tonumber(data.net_id)
      or plateOf(vehicle) ~= data.plate then
    return VHubCustom.notify('Veículo mudou durante a autorização.', 'error')
  end
  VHubCustom.service = {
    domain = domain, lease_id = data.lease_id, plate = data.plate, net_id = data.net_id,
  }
  if domain == 'bennys' then VHubCustom.openBennys(data)
  elseif domain == 'mec' then VHubCustom.openMec(data)
  elseif domain == 'oficina' then VHubCustom.openOficina(data) end
end)

RegisterNetEvent(E.NOTIFY)
AddEventHandler(E.NOTIFY, function(message, kind)
  local prefix = ({ error = '~r~', success = '~g~', warning = '~y~', info = '~w~' })[kind] or '~w~'
  BeginTextCommandThefeedPost('STRING')
  AddTextComponentSubstringPlayerName(prefix .. tostring(message or ''))
  EndTextCommandThefeedPostTicker(false, true)
end)

function VHubCustom.notify(message, kind)
  TriggerEvent(E.NOTIFY, message, kind)
end

-- ao ENTRAR num veículo, pede reidratação dos State Bags visuais (stance/escapamento) da placa —
-- cobre carros que não passaram pelo respawn do garage (admin/atalho) e reafirma p/ o motorista.
AddEventHandler('gameEventTriggered', function(name, data)
  if name ~= 'CEventNetworkPlayerEnteredVehicle' then return end
  if not data or data[1] ~= PlayerId() then return end
  local veh = data[2]
  if not veh or veh == 0 or not DoesEntityExist(veh) or not NetworkGetEntityIsNetworked(veh) then return end
  local netId = NetworkGetNetworkIdFromEntity(veh)
  if netId and netId ~= 0 then TriggerServerEvent(E.REQUEST_VISUAL, netId) end
end)

AddEventHandler('onResourceStop', function(resource)
  if resource ~= GetCurrentResourceName() then return end
  VHubCustom.running, VHubCustom.opening, VHubCustom.service = false, nil, nil
  SetNuiFocus(false, false)
  VHubCustom.inMenu = false
  if Cam and Cam.active and Cam.active() then Cam.stop() end
end)
