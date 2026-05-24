-- server/bootstrap.lua — handshake oficial (estilo Mirage).
-- Resolve "ensure manual": NAO permite registrar nada (callbacks, SQL, queries)
-- antes de exports.vhub:getVHub() responder. Outros modulos consultam
-- VHubRachaBoot.READY ou aguardam o evento 'vhub_racha:boot:ready'.
--
-- Esse arquivo carrega PRIMEIRO em server_scripts. Ele apenas inicia a thread
-- de espera. Os modulos seguintes (state, sql, lobby, etc.) registram suas
-- funcoes em VHubRachaBoot.on_ready(fn), que sao chamadas em ordem quando o
-- handshake completa.

VHubRachaBoot = {
  READY     = false,
  vHub      = nil,
  start_ms  = GetGameTimer(),
  ready_at  = 0,
  attempts  = 0,
  -- Fila de callbacks (modulos registram aqui o que rodar quando ready)
  _on_ready = {},
}
local B = VHubRachaBoot

-- Registra um callback para rodar quando o boot estiver pronto.
-- Se ja estiver ready, roda imediato.
function B.on_ready(fn, name)
  if type(fn) ~= 'function' then return end
  if B.READY then
    local ok, err = pcall(fn, B.vHub)
    if not ok then print(('[vhub_racha][boot] callback %s falhou: %s'):format(tostring(name or '?'), tostring(err))) end
    return
  end
  B._on_ready[#B._on_ready + 1] = { fn = fn, name = name or '?' }
end

local function _emit_ready()
  B.READY = true
  B.ready_at = GetGameTimer()
  print(('[vhub_racha][boot] vhub OK (%d tentativas, %dms). Rodando %d callbacks...'):
    format(B.attempts, B.ready_at - B.start_ms, #B._on_ready))

  -- Roda callbacks na ordem de registro
  for _, entry in ipairs(B._on_ready) do
    local ok, err = pcall(entry.fn, B.vHub)
    if not ok then
      print(('[vhub_racha][boot] callback %s falhou: %s'):format(entry.name, tostring(err)))
    else
      print(('[vhub_racha][boot] callback %s OK'):format(entry.name))
    end
  end
  B._on_ready = {}

  -- Notifica resources ouvintes (vhub_racha:boot:ready)
  TriggerEvent('vhub_racha:boot:ready')

  print('[vhub_racha][boot] pronto.')
end

-- Aguarda exports.vhub:getVHub() responder.
-- Polling lento (250ms) por ate 60s, depois aborta com erro logado.
AddEventHandler('onResourceStart', function(res)
  if res ~= GetCurrentResourceName() then return end

  Citizen.CreateThread(function()
    local MAX_ATTEMPTS = 240   -- 240 * 250ms = 60s
    for i = 1, MAX_ATTEMPTS do
      B.attempts = i
      local ok, ref = pcall(function() return exports.vhub:getVHub() end)
      if ok and type(ref) == 'table' and ref.Auth then
        B.vHub = ref
        _emit_ready()
        return
      end
      Citizen.Wait(250)
    end
    print('[vhub_racha][boot][ERRO] vhub indisponivel apos 60s — modulo nao iniciou.')
  end)
end)

-- Re-emite vHub:initDone sob demanda (resolve race condition no cliente).
-- Cliente que entrou apos o evento ja ter sido emitido pode solicitar a
-- re-emissao via este endpoint. Idempotente: so reemite para um usuario ja
-- autenticado. Confere apenas dados — sem efeito colateral.
RegisterNetEvent('vhub_racha:request_initDone')
AddEventHandler('vhub_racha:request_initDone', function()
  local src = source
  if not B.READY or not B.vHub or not B.vHub.Auth then return end
  local ok, user = pcall(function() return B.vHub.Auth:getUser(src) end)
  if not ok or type(user) ~= 'table' then return end
  -- Reenvia apenas para o solicitante
  TriggerClientEvent('vHub:initDone', src,
    user.id or user.user_id, user.char_id, false)
end)

-- Shutdown: libera referencias
AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  B.READY = false
end)
