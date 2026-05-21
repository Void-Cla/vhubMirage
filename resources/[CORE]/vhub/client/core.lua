-- client/core.lua — inicialização do cliente e handlers de sessão (PT-BR)
-- Responsabilidade: notificar readiness ao servidor e receber eventos de inicialização

local function notificar_pronto()
  TriggerServerEvent("vHub:ready")
end

AddEventHandler("onClientResourceStart", function(resource)
  if resource ~= GetCurrentResourceName() then return end
  SetTimeout(0, notificar_pronto)
end)

AddEventHandler("playerSpawned", notificar_pronto)

RegisterNetEvent("vHub:initDone")
AddEventHandler("vHub:initDone", function(user_id, char_id, primeiro_spawn)
  if LocalPlayer and LocalPlayer.state then
    LocalPlayer.state:set("vhub_user_id", user_id, true)
    if char_id ~= nil then LocalPlayer.state:set("vhub_char_id", char_id, true) end
    LocalPlayer.state:set("vhub_pronto", true, true)
    LocalPlayer.state:set("vhub_primeiro_spawn", primeiro_spawn == true, true)
  end
end)
