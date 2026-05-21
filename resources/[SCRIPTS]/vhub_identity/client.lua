-- vhub_identity/client.lua
-- Responsabilidade: exibir identidade localmente e enviar número de registro
--   para scripts de placa/HUD via evento local.

local _identity = nil  -- cache local da identidade do jogador

-- Recebe identidade do servidor
RegisterNetEvent("vhub_identity:load")
AddEventHandler("vhub_identity:load", function(identity)
  _identity = identity

  -- Emite para scripts de HUD e placa
  TriggerEvent("vhub_identity:local_loaded", identity)

  -- State Bag para leitura por outros scripts sem net event
  if LocalPlayer and LocalPlayer.state then
    LocalPlayer.state:set("vhub_registration", identity.registration, false)
    LocalPlayer.state:set("vhub_phone",        identity.phone,        false)
  end
end)

-- Getter local para outros scripts client-side
function vHub_getIdentity() return _identity end

-- Solicita identidade ao servidor ao ficar pronto
AddEventHandler("vHub:localReady", function()
  TriggerServerEvent("vhub_identity:get")
end)

RegisterNetEvent("vhub_identity:error")
AddEventHandler("vhub_identity:error", function(codigo)
  local msgs = {
    nome_invalido = "Nome inválido. Use letras, espaços e hífens (2-50 chars).",
    idade_invalida = "Idade inválida. Use entre 16 e 120.",
    sem_dinheiro  = "Saldo insuficiente para trocar identidade.",
  }
  BeginTextCommandThefeedPost("STRING")
  AddTextComponentSubstringPlayerName(msgs[codigo] or "Erro ao atualizar identidade.")
  EndTextCommandThefeedPostTicker(false, true)
end)
