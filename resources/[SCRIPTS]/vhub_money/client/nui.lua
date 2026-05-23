-- client/nui.lua — vhub_money (Fleeca Camell)
-- NUI focus + relay puro de callbacks. L-D8: nada de logica de negocio aqui.

local _open = false

-- ── Server → NUI ────────────────────────────────────────────────────────────

RegisterNetEvent('vhub_money:nui:opened', function(data)
  _open = true
  SetNuiFocus(true, true)
  SendNUIMessage({ action = 'open', data = data })
end)

RegisterNetEvent('vhub_money:nui:result', function(payload)
  if not _open then return end
  SendNUIMessage({ action = 'result', data = payload })
end)

RegisterNetEvent('vhub_money:nui:refresh', function(payload)
  if not _open then return end
  SendNUIMessage({ action = 'refresh', data = payload })
end)

-- ── NUI → Server ────────────────────────────────────────────────────────────

RegisterNUICallback('close', function(_data, cb)
  _open = false
  SetNuiFocus(false, false)
  SendNUIMessage({ action = 'close' })
  cb({ ok = true })
end)

RegisterNUICallback('withdraw', function(data, cb)
  TriggerServerEvent('vhub_money:nui:withdraw', data or {})
  cb({ ok = true })
end)

RegisterNUICallback('deposit', function(data, cb)
  TriggerServerEvent('vhub_money:nui:deposit', data or {})
  cb({ ok = true })
end)

RegisterNUICallback('transfer', function(data, cb)
  TriggerServerEvent('vhub_money:nui:transfer', data or {})
  cb({ ok = true })
end)
