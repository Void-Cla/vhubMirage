-- client/init.lua — vhub_groups
-- Comandos, atalho de teclado e estado local. NUI handlers ficam em nui.lua.

local Cfg = VHubGroupsCfg
local _open = false

-- ── State local ─────────────────────────────────────────────────────────────

local _self_groups = {}   -- { [group_id] = level }

AddStateBagChangeHandler('vhub_groups', ('player:%d'):format(GetPlayerServerId(PlayerId())),
  function(_bag, _key, value)
    _self_groups = type(value) == 'table' and value or {}
    -- Evento local — outros scripts client podem reagir
    TriggerEvent('vhub_groups:local_update', _self_groups)
  end)

RegisterNetEvent('vhub_groups:updated', function(list)
  _self_groups = type(list) == 'table' and list or {}
  TriggerEvent('vhub_groups:local_update', _self_groups)
end)

-- ── Abrir / fechar painel ───────────────────────────────────────────────────

local function abrirPainel()
  if _open then return end
  TriggerServerEvent('vhub_groups:admin:open')
end

-- Resposta do servidor (admin permitido) → abre NUI
RegisterNetEvent('vhub_groups:admin:opened', function(data)
  _open = true
  SetNuiFocus(true, true)
  SendNUIMessage({ action = 'open', data = data })
end)

-- Fechamento sinalizado pelo NUI (via callback) — atualiza estado local
RegisterNetEvent('vhub_groups:_panel_closed', function() _open = false end)

-- Atualizacoes pontuais
RegisterNetEvent('vhub_groups:admin:players', function(players)
  if not _open then return end
  SendNUIMessage({ action = 'players', data = players })
end)

RegisterNetEvent('vhub_groups:admin:result', function(payload)
  if not _open then return end
  SendNUIMessage({ action = 'result', data = payload })
end)

RegisterNetEvent('vhub_groups:admin:audit_data', function(rows)
  if not _open then return end
  SendNUIMessage({ action = 'audit', data = rows })
end)

RegisterNetEvent('vhub_groups:admin:status_data', function(status)
  if not _open then return end
  SendNUIMessage({ action = 'status', data = status })
end)

-- ── /meusgrupos — toast informativo (sem NUI completo) ─────────────────────

RegisterNetEvent('vhub_groups:self:data', function(data)
  if type(data) ~= 'table' then return end
  local groups = data.groups or {}
  if data.owner then
    print('[vhub_groups] Voce e o DONO da cidade (permissoes irrestritas).')
  end
  if #groups == 0 then
    print('[vhub_groups] Nenhum grupo atribuido.')
    return
  end
  print(('[vhub_groups] Seus grupos (%d):'):format(#groups))
  for _, g in ipairs(groups) do
    local exp = g.expires_at_unix
                and (' (expira em ' .. os.date('%d/%m/%Y %H:%M', g.expires_at_unix) .. ')')
                or ''
    print(('  • %s [%s] nivel %d%s'):format(g.label, g.id, g.level, exp))
  end
end)

-- ── Comandos ────────────────────────────────────────────────────────────────

RegisterCommand(Cfg.CMD_OPEN_PANEL, function() abrirPainel() end, false)
RegisterCommand(Cfg.CMD_MY_GROUPS,  function() TriggerServerEvent('vhub_groups:self:get') end, false)

RegisterKeyMapping('+vhub_groups_panel', 'vHub Groups — abrir painel admin', 'keyboard', Cfg.KEY_OPEN_PANEL)
RegisterCommand('+vhub_groups_panel', function() abrirPainel() end, false)
RegisterCommand('-vhub_groups_panel', function() end, false)

-- ── API local (read-only) ───────────────────────────────────────────────────

-- Outros scripts client podem checar grupos sem ir ao server
local function hasGroupLocal(group_id, min_level)
  local lvl = _self_groups[group_id]
  if not lvl then return false end
  return tonumber(lvl) >= (tonumber(min_level) or 1)
end
exports('hasGroupLocal', hasGroupLocal)

exports('getGroupsLocal', function() return _self_groups end)
