---@diagnostic disable: undefined-global, lowercase-global

-- server/bootstrap.lua — boot, logger e lifecycle de sessão (per-char).
-- Único ponto de print() do resource (isenção L-08, padrão vhub_racha).

VHubIpad = VHubIpad or {}


-- ============================================================
-- LOGGER (único ponto de saída de console do resource)
-- ============================================================

-- imprime uma linha de diagnóstico do vhub_ipad
function IpadLog(msg)
  print('[vhub_ipad] ' .. tostring(msg))
end


-- ============================================================
-- BOOT — schema + registro dos builtins + rescan de online
-- ============================================================

AddEventHandler('onResourceStart', function(res)
  if res ~= GetCurrentResourceName() then return end
  CreateThread(function()
    VHubIpad.SQL:initSchema()
    VHubIpad.Registry:registerBuiltins()

    -- restart com players online: recarrega o estado per-char de cada um
    for _, sid in ipairs(GetPlayers()) do
      local src  = tonumber(sid)
      local user = exports.vhub:getUser(src)
      if user and user.char_id then
        VHubIpad.State.load(src, user.char_id)
      end
    end

    IpadLog(('pronto — %d app(s) no catálogo.'):format(VHubIpad.Registry:version()))
  end)
end)


-- ============================================================
-- LIFECYCLE — sessão viva via evento público do core
-- ============================================================

-- carrega o estado do personagem ao logar (troca de char re-dispara)
AddEventHandler('vHub:characterLoad', function(user)
  if not user or not user.source or not user.char_id then return end
  local src = user.source
  CreateThread(function()
    VHubIpad.State.load(src, user.char_id)
  end)
end)

-- flush final + libera sessão ao sair
AddEventHandler('playerDropped', function()
  VHubIpad.State.unload(source)
end)

-- flush de tudo ao parar o resource
AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  VHubIpad.State.flushAll()
end)
