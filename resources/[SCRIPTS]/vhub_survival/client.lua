-- vhub_survival/client.lua
-- Responsabilidade: exibir barras de fome e sede no HUD.
-- Servidor é autoridade — cliente apenas exibe e reporta consumo por ação.

local _vitais  = { agua = 1.0, comida = 1.0 }
local _exibir  = false

-- Recebe configuração e estado inicial do servidor
RegisterNetEvent("vhub_survival:init")
AddEventHandler("vhub_survival:init", function(dados)
  if type(dados) ~= "table" then return end
  _vitais.agua   = tonumber(dados.agua)   or 1.0
  _vitais.comida = tonumber(dados.comida) or 1.0
  _exibir = dados.exibir ~= false
end)

-- Recebe atualização de vital específico
RegisterNetEvent("vhub_survival:vital_update")
AddEventHandler("vhub_survival:vital_update", function(nome, valor)
  if _vitais[nome] ~= nil then
    _vitais[nome] = tonumber(valor) or _vitais[nome]
  end
end)

-- Getter para scripts de HUD
function vHub_getVitais() return _vitais end
function vHub_getVital(nome) return _vitais[nome] or 0 end

-- Emite vitais periodicamente para scripts de HUD externos
Citizen.CreateThread(function()
  while true do
    Citizen.Wait(1000)
    if _exibir then
      TriggerEvent("vhub_survival:hud_tick", _vitais)
    end
  end
end)
