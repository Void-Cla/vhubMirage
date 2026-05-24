-- client/bootstrap.lua — handshake cliente (espelha o server bootstrap).
-- Modulos client registram callbacks em VHubRachaBoot.on_ready(fn) para
-- rodarem so depois que o vhub estiver pronto E o vHub:initDone tiver chegado.
-- Resolve "callbacks mortos no boot" sem precisar de ensure manual.

VHubRachaBoot = {
  READY      = false,           -- vhub core disponivel + initDone recebido
  AUTH_READY = false,           -- vHub:initDone foi recebido
  vHub       = nil,
  user_id    = nil,
  char_id    = nil,
  start_ms   = GetGameTimer(),
  ready_at   = 0,
  _on_ready  = {},
}
local B = VHubRachaBoot

function B.on_ready(fn, name)
  if type(fn) ~= 'function' then return end
  if B.READY then
    local ok, err = pcall(fn)
    if not ok then print(('[vhub_racha][client] callback %s erro: %s'):format(tostring(name or '?'), tostring(err))) end
    return
  end
  B._on_ready[#B._on_ready + 1] = { fn = fn, name = name or '?' }
end

local function _emit_ready()
  if B.READY then return end
  B.READY = true
  B.ready_at = GetGameTimer()
  print(('[vhub_racha][client] pronto em %dms (rodando %d callbacks)'):format(
    B.ready_at - B.start_ms, #B._on_ready))
  for _, entry in ipairs(B._on_ready) do
    local ok, err = pcall(entry.fn)
    if not ok then print(('[vhub_racha][client] %s erro: %s'):format(entry.name, tostring(err))) end
  end
  B._on_ready = {}
  TriggerEvent('vhub_racha:boot:ready')
end

-- Tenta resolver vhub core
local function try_resolve_vhub()
  -- Primeiro tenta o global (shared scripts do vHub podem ter criado a tabela)
  local gv = rawget(_G, 'vHub')
  if type(gv) == 'table' then
    B.vHub = gv
    return true
  end
  -- Fallback: tenta via export (compatibilidade com implementações que expõem getVHub)
  local ok, ref = pcall(function() return exports and exports.vhub and exports.vhub.getVHub and exports.vhub:getVHub() end)
  if ok and type(ref) == 'table' then
    B.vHub = ref
    return true
  end
  return false
end

-- Listener: vHub:initDone informa user_id/char_id (handshake oficial do vhub)
RegisterNetEvent('vHub:initDone')
AddEventHandler('vHub:initDone', function(user_id, char_id, primeiro_spawn)
  B.user_id = tonumber(user_id) or nil
  B.char_id = tonumber(char_id) or nil
  B.AUTH_READY = true
  if try_resolve_vhub() then _emit_ready() end
end)

-- Listener alternativo (compat): vHub:localReady
RegisterNetEvent('vHub:localReady')
AddEventHandler('vHub:localReady', function(user_id, char_id, primeiro_spawn)
  B.user_id = tonumber(user_id) or B.user_id
  B.char_id = tonumber(char_id) or B.char_id
  B.AUTH_READY = true
  if try_resolve_vhub() then _emit_ready() end
end)

-- Polling fallback + retry de re-emissao do vHub:initDone.
-- O cliente pode ter registrado o listener APOS o servidor ja ter emitido o
-- evento (race condition). Por isso solicitamos a re-emissao explicitamente.
-- Sinais aceitos como ready:
--   (a) listener vHub:initDone disparou (AUTH_READY=true)
--   (b) LocalPlayer.state.vhub_pronto == true (sinal redundante via State Bag)
--   (c) try_resolve_vhub() retornou e bag esta ok
CreateThread(function()
  -- Pede re-emissao em momentos espalhados: cobre boot rapido (200ms) e
  -- recuperacao em caso de boot lento do core (3s, 8s).
  Wait(200);  TriggerServerEvent('vhub_racha:request_initDone')
  Wait(3000)
  if not B.READY then TriggerServerEvent('vhub_racha:request_initDone') end
  Wait(5000)   -- 5s + 3s = 8s total
  if not B.READY then TriggerServerEvent('vhub_racha:request_initDone') end
end)

CreateThread(function()
  for _ = 1, 120 do   -- 120 * 500ms = 60s (mais tolerante)
    if B.READY then return end
    local sb = (LocalPlayer and LocalPlayer.state) and LocalPlayer.state or nil
    -- Sinal (b): vhub_pronto via State Bag → marca AUTH_READY e tenta resolver vHub
    if sb and sb.vhub_pronto == true then
      B.AUTH_READY = true
      B.user_id = tonumber(sb.vhub_uid) or B.user_id
      B.char_id = tonumber(sb.vhub_char_id) or B.char_id
      pcall(try_resolve_vhub)
      _emit_ready()
      return
    end
    -- Sinal (c): vHub resolvido + bag confirma
    if try_resolve_vhub() then
      local sb2 = (LocalPlayer and LocalPlayer.state) and LocalPlayer.state or nil
      if sb2 and sb2.vhub_pronto == true then
        B.AUTH_READY = true
        B.user_id = tonumber(sb2.vhub_uid) or B.user_id
        B.char_id = tonumber(sb2.vhub_char_id) or B.char_id
        _emit_ready()
        return
      end
    end
    Wait(500)
  end
  if not B.READY then
    -- Diagnostico final (sem spam): so loga 1x.
    local gv = rawget(_G, 'vHub')
    local exports_ok = (type(exports) == 'table' and type(exports.vhub) == 'table')
    local sb3 = (LocalPlayer and LocalPlayer.state) and LocalPlayer.state or nil
    local sb_ready3 = sb3 and sb3.vhub_pronto == true
    print(('[vhub_racha][client] vhub indisponivel apos 60s. debug: global_vhub=%s exports_vhub=%s auth_ready=%s state_ready=%s b_user=%s b_char=%s')
      :format(tostring(gv and 'ok' or 'nil'), tostring(exports_ok),
              tostring(B.AUTH_READY), tostring(sb_ready3),
              tostring(B.user_id), tostring(B.char_id)))
  end
end)

AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  B.READY = false
end)
