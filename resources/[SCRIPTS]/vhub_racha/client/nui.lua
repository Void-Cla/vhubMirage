-- client/nui.lua — focus + callbacks NUI (relay puro).

local Cfg = VHubRachaCfg
local E   = VHubRachaE
local L   = VHubRachaLocal

local function require_ready(cb)
  if not (VHubRachaBoot and VHubRachaBoot.READY) then
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName('Mirage Racha ainda nao esta pronto.')
    EndTextCommandThefeedPostTicker(false, true)
    if cb then cb({ ok = false }) end
    return false
  end
  return true
end

-- ── Notify (toast nativo) ──────────────────────────────────────────────────

RegisterNetEvent(E.NOTIFY, function(msg, _kind)
  BeginTextCommandThefeedPost('STRING')
  AddTextComponentSubstringPlayerName(tostring(msg or ''))
  EndTextCommandThefeedPostTicker(false, true)
end)

-- ── NUI principal ─────────────────────────────────────────────────────────

RegisterNetEvent(E.NUI_OPENED, function(data)
  L.open_nui = true
  SetNuiFocus(true, true)
  SendNUIMessage({ action = 'open', data = data })
end)

RegisterNetEvent(E.NUI_REFRESH, function(data)
  if not L.open_nui then return end
  SendNUIMessage({ action = 'refresh', data = data })
end)

RegisterNetEvent(E.NUI_RESULT, function(payload)
  if not L.open_nui then return end
  SendNUIMessage({ action = 'result', data = payload })
end)

RegisterNetEvent(E.NUI_RANKING_DATA, function(d)
  if L.open_nui then SendNUIMessage({ action = 'ranking', data = d }) end
end)
RegisterNetEvent(E.NUI_HISTORY_DATA, function(d)
  if L.open_nui then SendNUIMessage({ action = 'history', data = d }) end
end)
RegisterNetEvent(E.NUI_RESULTS_DATA, function(d)
  if L.open_nui then SendNUIMessage({ action = 'results', data = d }) end
end)

-- ── Editor NUI ─────────────────────────────────────────────────────────────
-- IMPORTANTE: o editor e IN-GAME (keyboard-only). NAO ativa SetNuiFocus aqui —
-- caso contrario o cursor aparece e o jogador nao consegue dirigir.
-- O painel principal /racha (com cursor) so reabre na fase 'meta' para o form
-- de metadados.

RegisterNetEvent(E.EDITOR_OPENED, function(draft)
  L.open_editor = true
  L.editor_draft = draft or {}
  -- Se o painel principal estava aberto (jogador clicou 'Iniciar' na aba editor),
  -- fecha-o para liberar inputs e devolver controle do veiculo ao jogador.
  if L.open_nui then
    L.open_nui = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
  end
  -- Feedback nativo (sem cursor): o overlay in-game (client/editor.lua) renderiza
  -- instrucoes contextuais por fase. Aqui apenas notificamos.
  BeginTextCommandThefeedPost('STRING')
  AddTextComponentSubstringPlayerName(
    'Editor ativo. Use comandos in-game: E adicionar | H undo | G proxima fase.')
  EndTextCommandThefeedPostTicker(false, true)
end)

RegisterNetEvent(E.EDITOR_DRAFT, function(draft)
  L.editor_draft = draft or {}
  -- So envia pra NUI se ela estiver aberta (fase meta)
  if L.open_nui then SendNUIMessage({ action = 'editor_draft', data = draft }) end
end)

RegisterNetEvent(E.EDITOR_PHASE, function(payload)
  local phase = (payload and payload.phase) or 'idle'
  -- Repassa para a NUI se ja estiver aberta
  if L.open_nui then
    SendNUIMessage({ action = 'editor_phase', data = payload })
  end
  -- Quando entra na fase META: reabre o painel /racha para preencher o form.
  -- Server ja enviou EDITOR_DRAFT recente, NUI mostra o estado correto.
  if phase == 'meta' and not L.open_nui then
    TriggerServerEvent(E.NUI_OPEN)
  end
end)

-- ── NUI callbacks ─────────────────────────────────────────────────────────

RegisterNUICallback('close', function(_data, cb)
  L.open_nui = false
  SetNuiFocus(false, false)
  SendNUIMessage({ action = 'close' })
  cb({ ok = true })
end)

RegisterNUICallback('editor_close', function(_data, cb)
  L.open_editor = false
  SetNuiFocus(false, false)
  SendNUIMessage({ action = 'editor_close' })
  cb({ ok = true })
end)

-- Lobby
RegisterNUICallback('create', function(data, cb)
  if not require_ready(cb) then return end
  TriggerServerEvent(E.LOBBY_CREATE, data or {})
  cb({ ok = true })
end)
RegisterNUICallback('join', function(data, cb)
  if not require_ready(cb) then return end
  TriggerServerEvent(E.LOBBY_JOIN, (data and data.inst_id) or '')
  cb({ ok = true })
end)
RegisterNUICallback('leave', function(data, cb)
  TriggerServerEvent(E.LOBBY_LEAVE, (data and data.inst_id) or '')
  cb({ ok = true })
end)
RegisterNUICallback('cancel', function(data, cb)
  TriggerServerEvent(E.LOBBY_CANCEL, (data and data.inst_id) or '')
  cb({ ok = true })
end)
RegisterNUICallback('confirm', function(data, cb)
  if not require_ready(cb) then return end
  TriggerServerEvent(E.LOBBY_CONFIRM, (data and data.inst_id) or '')
  cb({ ok = true })
end)
RegisterNUICallback('force_start', function(data, cb)
  if not require_ready(cb) then return end
  TriggerServerEvent(E.LOBBY_FORCE_START, (data and data.inst_id) or '')
  cb({ ok = true })
end)
RegisterNUICallback('refresh_lobbies', function(_data, cb)
  TriggerServerEvent(E.NUI_OPEN)
  cb({ ok = true })
end)

-- Queries
RegisterNUICallback('ranking', function(data, cb)
  TriggerServerEvent(E.NUI_RANKING, data or {})
  cb({ ok = true })
end)
RegisterNUICallback('history', function(data, cb)
  TriggerServerEvent(E.NUI_HISTORY, data or {})
  cb({ ok = true })
end)
RegisterNUICallback('results', function(data, cb)
  TriggerServerEvent(E.NUI_RESULTS, (data and data.history_id) or 0)
  cb({ ok = true })
end)

-- Editor relays
RegisterNUICallback('editor_open',     function(_d, cb) TriggerServerEvent(E.EDITOR_OPEN);      cb({ ok = true }) end)
RegisterNUICallback('editor_phase',    function(d, cb)  TriggerServerEvent(E.EDITOR_PHASE, d or {}); cb({ ok = true }) end)
RegisterNUICallback('editor_add_grid', function(_d, cb) TriggerServerEvent(E.EDITOR_ADD_GRID);  cb({ ok = true }) end)
RegisterNUICallback('editor_add_cp',   function(_d, cb) TriggerServerEvent(E.EDITOR_ADD_CP);   cb({ ok = true }) end)
RegisterNUICallback('editor_undo',     function(_d, cb) TriggerServerEvent(E.EDITOR_UNDO);     cb({ ok = true }) end)
RegisterNUICallback('editor_save',     function(d, cb)  if not require_ready(cb) then return end; TriggerServerEvent(E.EDITOR_SAVE, d or {});   cb({ ok = true }) end)
RegisterNUICallback('editor_discard',  function(_d, cb) TriggerServerEvent(E.EDITOR_DISCARD);  cb({ ok = true }) end)

-- ── Comando / atalho ─────────────────────────────────────────────────────

RegisterCommand(Cfg.CMD_OPEN, function()
  if not (VHubRachaBoot and VHubRachaBoot.READY) then
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName('Mirage Racha ainda nao esta pronto.')
    EndTextCommandThefeedPostTicker(false, true)
    return
  end
  TriggerServerEvent(E.NUI_OPEN)
end, false)

RegisterKeyMapping('+vhub_racha_panel', 'Mirage Racha — abrir painel',
  'keyboard', Cfg.KEY_OPEN)
RegisterCommand('+vhub_racha_panel', function() TriggerServerEvent(E.NUI_OPEN) end, false)
RegisterCommand('-vhub_racha_panel', function() end, false)
