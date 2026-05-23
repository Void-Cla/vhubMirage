-- server/init.lua — vhub_groups
-- Bootstrap: aguarda vhub disponivel, aplica schema, carrega cache em characterLoad,
-- limpa em playerDropped, roda cron de expiracao.

local Cfg   = VHubGroupsCfg
local Core  = VHubGroupsCore
local SQL   = VHubGroupsSQL
local Cache = VHubGroupsCache

-- ── Boot ────────────────────────────────────────────────────────────────────

AddEventHandler('onResourceStart', function(res)
  if res ~= GetCurrentResourceName() then return end

  Citizen.CreateThread(function()
    -- 1) Aguarda vhub core disponivel
    local vh = nil
    for _ = 1, 60 do
      local ok, ref = pcall(function() return exports.vhub:getVHub() end)
      if ok and type(ref) == 'table' and ref.Auth then vh = ref; break end
      Citizen.Wait(250)
    end
    if not vh then
      print('[vhub_groups][ERRO] vhub indisponivel apos 15s — abortando init.')
      return
    end
    Core.set_vhub(vh)

    -- 2) Aplica schema (idempotente)
    local ok, err = SQL.apply_schema()
    if not ok then
      print('[vhub_groups][ERRO] falha ao aplicar schema: ' .. tostring(err))
      return
    end

    -- 3) Re-popula cache para sessoes que ja estavam ativas (restart do resource)
    if vh.Auth and vh.Auth._sessions then
      for _, user in pairs(vh.Auth._sessions) do
        if user.char_id then
          Core.load_entry(user.source, user.char_id)
        end
      end
    end

    Core.mark_ready()
    print('[vhub_groups] Pronto.')
  end)
end)

-- ── Lifecycle de personagem ─────────────────────────────────────────────────

-- Carrega grupos quando o personagem entra no mundo
AddEventHandler('vHub:characterLoad', function(user)
  if not Core.is_ready() then
    -- Tenta novamente em 1s — bootstrap pode estar terminando
    Citizen.SetTimeout(1000, function()
      if Core.is_ready() and user and user.char_id then
        Core.load_entry(user.source, user.char_id)
      end
    end)
    return
  end
  if not user or not user.char_id then return end
  Citizen.CreateThread(function()
    Core.load_entry(user.source, user.char_id)
  end)
end)

-- Reenvia state bag ao spawnar (cliente pode ter perdido o evento)
AddEventHandler('vHub:playerSpawn', function(user, _first_spawn)
  if not user or not user.source then return end
  local entry = Cache.by_src(user.source)
  if entry then Core.notify(entry) end
end)

-- Limpa cache quando o jogador sai
AddEventHandler('playerDropped', function()
  local src = source
  Cache.unregister_src(src)
end)

-- ── Cron: limpa grupos expirados ────────────────────────────────────────────

Citizen.CreateThread(function()
  local interval = tonumber(Cfg.EXPIRE_CHECK_INTERVAL_MS) or 60000
  if interval < 10000 then interval = 10000 end
  while true do
    Citizen.Wait(interval)
    if Core.is_ready() then
      local removed = SQL.delete_expired()
      if removed and tonumber(removed) and tonumber(removed) > 0 then
        -- Invalida cache de TODOS para forcar recarga (raro acontecer)
        Cache.clear_all()
        local vh = Core.get_vhub()
        if vh and vh.Auth and vh.Auth._sessions then
          for _, user in pairs(vh.Auth._sessions) do
            if user.char_id then
              Core.load_entry(user.source, user.char_id)
            end
          end
        end
        Core.log('info', 'grupos expirados removidos', { removed = removed })
      end
    end
  end
end)

-- ── Status snapshot ─────────────────────────────────────────────────────────

exports('Status', function()
  return {
    ready      = Core.is_ready(),
    sql_ready  = SQL.ready,
    cache      = Cache.status(),
  }
end)
