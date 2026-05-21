-- server/spectator.lua  /spec <id>  ver tela do alvo
-- T cnica: cliente do admin entra em modo invis +  c mera presa ao alvo via NetworkSetInSpectatorMode.
-- Alvo recebe state bag "vhub_spec_by" (s  visual no HUD do admin, alvo n o sabe).
---@diagnostic disable: undefined-global

local Core = VHubAdmin.Core
local E    = VHubAdmin.E
local U    = VHubAdmin.U

local Spec = {}     -- [admin_src] = target_src

local function reqPerm(src, k)
  if not Core.hasPerm(src, k) then Core.notify(src, 'Sem permiss o.'); return false end
  return true
end

RegisterNetEvent(E.ACT_SPEC)
AddEventHandler(E.ACT_SPEC, function(target)
  local src = source; if not reqPerm(src, 'spec') then return end
  -- toggle: se j  est  espectando, sai
  if Spec[src] then
    TriggerClientEvent(E.SPEC_STOP, src)
    Core.notify(src, 'Espectador encerrado.')
    Core:audit(src, 'spec_stop', Spec[src], {})
    Spec[src] = nil
    return
  end
  local t = U.toSrc(target); if not t or t == src then return end
  if not GetPlayerName(t) then Core.notify(src, 'Alvo offline.'); return end
  Spec[src] = t
  local tped = GetPlayerPed(tostring(t))
  local c = tped and tped ~= 0 and GetEntityCoords(tped) or nil
  TriggerClientEvent(E.SPEC_START, src, {
    target = t,
    coords = c and { x = c.x, y = c.y, z = c.z } or nil,
  })
  Core.notify(src, ('Espectando [%d]. Use /spec novamente para sair.'):format(t))
  Core:audit(src, 'spec_start', t, {})
end)

-- atualiza  o peri dica (cliente pede)
RegisterNetEvent(E.SPEC_UPDATE)
AddEventHandler(E.SPEC_UPDATE, function()
  local src = source
  local t = Spec[src]; if not t then return end
  local tped = GetPlayerPed(tostring(t))
  if not tped or tped == 0 then
    -- alvo desconectou
    TriggerClientEvent(E.SPEC_STOP, src)
    Spec[src] = nil
    Core.notify(src, 'Alvo desconectou. Spec encerrado.')
    return
  end
  local c = GetEntityCoords(tped)
  TriggerClientEvent(E.SPEC_START, src, {
    target = t,
    coords = { x = c.x, y = c.y, z = c.z },
    keep   = true,
  })
end)

AddEventHandler('playerDropped', function()
  Spec[source] = nil
  -- se eu era alvo de algu m, derruba o spec dele
  for adm, tgt in pairs(Spec) do
    if tgt == source then
      TriggerClientEvent(E.SPEC_STOP, adm)
      Spec[adm] = nil
      Core.notify(adm, 'Alvo desconectou. Spec encerrado.')
    end
  end
end)
