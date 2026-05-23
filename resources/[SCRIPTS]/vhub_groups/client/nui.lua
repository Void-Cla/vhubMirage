-- client/nui.lua — vhub_groups
-- L-D8 (designer): NUI nao decide regra — apenas relay de intencao.
-- Toda decisao (permissao admin, validacao, mutacao) e revalidada no servidor.

local function close_panel()
  SetNuiFocus(false, false)
  SendNUIMessage({ action = 'close' })
  TriggerEvent('vhub_groups:_panel_closed')
end

RegisterNUICallback('close', function(_data, cb)
  close_panel()
  cb({ ok = true })
end)

RegisterNUICallback('refresh_players', function(_data, cb)
  TriggerServerEvent('vhub_groups:admin:refresh_players')
  cb({ ok = true })
end)

RegisterNUICallback('add_group', function(data, cb)
  TriggerServerEvent('vhub_groups:admin:add', data or {})
  cb({ ok = true })
end)

RegisterNUICallback('remove_group', function(data, cb)
  TriggerServerEvent('vhub_groups:admin:remove', data or {})
  cb({ ok = true })
end)

RegisterNUICallback('set_level', function(data, cb)
  TriggerServerEvent('vhub_groups:admin:set_level', data or {})
  cb({ ok = true })
end)

RegisterNUICallback('audit', function(data, cb)
  TriggerServerEvent('vhub_groups:admin:audit', data or {})
  cb({ ok = true })
end)

RegisterNUICallback('status', function(_data, cb)
  TriggerServerEvent('vhub_groups:admin:status')
  cb({ ok = true })
end)
