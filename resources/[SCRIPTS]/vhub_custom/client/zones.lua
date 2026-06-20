-- client/zones.lua — detecção de zona e markers (2 threads pré-criadas, sem spawn no loop)
-- Thread FRIA (1 Hz): detecta proximidade, sem render.
-- Thread QUENTE (pré-criada): DrawMarker + prompt [E], dorme 500 ms fora de zona.
---@diagnostic disable: undefined-global

local CFG = VHubCustom.cfg
local E   = VHubCustom.E

local MARKER_COLOR = { r = 220, g = 180, b = 90, a = 100 }
local PROMPT_KEY   = 38   -- tecla E


-- ============================================================
-- BLIPS (criados 1x no boot, nunca recriados em loop)
-- ============================================================

for _, z in ipairs(CFG.zones) do
  local b = AddBlipForCoord(z.x, z.y, z.z)
  SetBlipSprite(b, z.blip.sprite)
  SetBlipColour(b, z.blip.color)
  SetBlipScale(b, 0.7)
  SetBlipAsShortRange(b, true)
  BeginTextCommandSetBlipName('STRING')
  AddTextComponentSubstringPlayerName(z.blip.label)
  EndTextCommandSetBlipName(b)
end


-- ============================================================
-- THREAD FRIA — 1 Hz (só compara distância, zero render)
-- ============================================================

Citizen.CreateThread(function()
  while VHubCustom.running do
    local pPos = GetEntityCoords(PlayerPedId())
    local found = nil
    for _, z in ipairs(CFG.zones) do
      if #(pPos - z._vec) < z.raio_check then
        found = z; break
      end
    end
    -- só notifica em mudança de zona (evita eventos redundantes)
    if found ~= VHubCustom.near then
      VHubCustom.near = found
    end
    Citizen.Wait(1000)
  end
end)


-- ============================================================
-- THREAD QUENTE — dorme 500 ms fora de zona; 0 ms dentro
-- ============================================================

Citizen.CreateThread(function()
  while VHubCustom.running do
    local z = VHubCustom.near

    if not z then
      Citizen.Wait(500)
    else
      -- desenha marker na zona
      DrawMarker(1,
        z.x, z.y, z.z - 1.0,
        0.0, 0.0, 0.0,
        0.0, 0.0, 0.0,
        2.0, 2.0, 1.0,
        MARKER_COLOR.r, MARKER_COLOR.g, MARKER_COLOR.b, MARKER_COLOR.a,
        false, true, 2, false, nil, nil, false)

      -- prompt de interação (dentro do raio_interact)
      local pPos = GetEntityCoords(PlayerPedId())
      if #(pPos - z._vec) < z.raio_interact and not VHubCustom.inMenu then
        -- exibe instrução [E] na tela
        BeginTextCommandDisplayHelp('STRING')
        AddTextComponentSubstringPlayerName('[E] Abrir ' .. z.label)
        EndTextCommandDisplayHelp(0, false, true, -1)

        if IsControlJustReleased(0, PROMPT_KEY) then
          -- verifica se há veículo próximo para operar
          local veh = GetClosestVehicle(pPos.x, pPos.y, pPos.z, 8.0, 0, 70)
          if DoesEntityExist(veh) and veh ~= 0 then
            VHubCustom.activeZone   = z
            VHubCustom.activeVeh    = veh
            VHubCustom.activeVehNet = NetworkGetNetworkIdFromEntity(veh)
            VHubCustom.activePlate  = GetVehicleNumberPlateText(veh):upper():match('^%s*(.-)%s*$')

            if z.domain == 'bennys'  then VHubCustom.openBennys()
            elseif z.domain == 'mec' then VHubCustom.openMec()
            elseif z.domain == 'oficina' then VHubCustom.openOficina()
            end
          else
            BeginTextCommandDisplayHelp('STRING')
            AddTextComponentSubstringPlayerName('Aproxime um veículo para usar este serviço.')
            EndTextCommandDisplayHelp(0, false, true, -1)
          end
        end
      end

      Citizen.Wait(0)
    end
  end
end)
