-- client/nui.lua — adaptador de notificacao + reflexo do estado do editor.
--
-- O PAINEL (pistas/perfil/ranqueado/ranking/historico/editor) vive
-- EXCLUSIVAMENTE no iPad (vhub_ipad/web/modules/racha). Nenhuma NUI com cursor
-- mora mais neste resource — restam so os overlays in-game (HUD, ready-zone) e
-- o totem nativo. Aqui sobra apenas:
--   1) rotear E.NOTIFY do server para o toast global (vhub_notify);
--   2) refletir o estado do editor (server → VHubRachaLocal) para o overlay
--      in-game keyboard-only de client/editor.lua.

local E = VHubRachaE
local L = VHubRachaLocal


-- ── Notify — delega ao toast global do core (vhub_notify) ──────────────────

RegisterNetEvent(E.NOTIFY, function(msg, kind)
  L.notify(msg, kind)
end)


-- ── Editor in-game (overlay nativo em client/editor.lua) ───────────────────
-- Keyboard-only: grade/checkpoints marcados in-game (E adiciona, H desfaz,
-- G avanca de fase). Metadados e SAVE sao preenchidos no iPad (aba Editor).
-- Aqui so espelhamos o estado vindo do server para o overlay desenhar.

RegisterNetEvent(E.EDITOR_OPENED, function(draft)
  L.open_editor  = true
  L.editor_draft = draft or {}
  L.notify('Editor ativo. Marque a grade e os checkpoints in-game ' ..
    '(E adiciona, H desfaz, G avanca). Depois abra o iPad para salvar.', 'info')
end)

RegisterNetEvent(E.EDITOR_DRAFT, function(draft)
  L.editor_draft = draft or {}
end)

RegisterNetEvent(E.EDITOR_PHASE, function(payload)
  local phase = (payload and payload.phase) or 'idle'
  if type(L.editor_draft) == 'table' then L.editor_draft.phase = phase end
  if phase == 'meta' then
    L.notify('Fase final: abra o iPad → Editor para preencher os dados e salvar.', 'info')
  end
end)
