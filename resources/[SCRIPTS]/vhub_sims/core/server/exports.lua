-- exports.lua — contratos públicos default-deny do SIMS
---@diagnostic disable: undefined-global

local Creation = VHubSimsCreation
local trusted = VHubSims.cfg.trusted

local function allowed(contract)
  local caller = GetInvokingResource()
  return type(caller) == 'string' and caller ~= '' and trusted[contract][caller] == true
end

-- informa ao login se o personagem atual exige criação
exports('needsCreation', function(src)
  if not allowed('needs_creation') then return { ok = false, err = 'forbidden' } end
  return Creation.needsCreation(tonumber(src))
end)

-- inicia criação idempotente a pedido exclusivo do login
exports('beginCreation', function(src, requestId)
  if not allowed('begin_creation') then return { ok = false, err = 'forbidden' } end
  return Creation.beginCreation(tonumber(src), requestId)
end)

-- cancela criação ativa server-side (login pediu voltar à seleção de char)
-- Sem saga (ADR #97): só encerra o stage físico e sinaliza cancelamento. O char nunca foi 'created'
-- (o commit é a última etapa) → o login descarta o rascunho com segurança.
exports('cancelCreation', function(src)
  if not allowed('cancel_creation') then return false end
  src = tonumber(src)
  if not src then return false end
  local session = VHubSimsSession.cleanup(src)
  if not session then return false end
  TriggerClientEvent(VHubSims.E.CLI_STUDIO_CLOSE, src, { reason = 'cancelled', restore = true })
  if session.mode == 'creator' and session.char_id then
    if session.stage_token then
      VHubSimsCore.call('vhub_hss', 'endPendingStage', src, session.stage_token)
    end
    TriggerEvent(VHubSims.E.CREATION_CANCELLED, session.char_id)
  end
  return true
end)

-- força saga presa em manual_reconcile → refunded para liberar a criação do personagem
exports('forceResolveSaga', function(charId)
  if not allowed('force_resolve_saga') then return false, 'forbidden' end
  return VHubSimsAdmin.forceResolveSaga(charId)
end)
