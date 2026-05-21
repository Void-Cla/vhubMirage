-- client/modules/spawn.lua — Aplica spawn recebido do servidor
-- CORREÇÃO DO BUG DE NÃO SPAWNAR:
--   Antes: SetEntityCoords rodava antes de NetworkIsPlayerActive ser true,
--     e o ped mudava após SetPlayerModel — coordenadas aplicadas no ped errado.
--   Agora: aguarda NetworkIsPlayerActive, depois SetPlayerModel, depois
--     pega o novo ped e só então teleporta. FreezeEntityPosition durante
--     a troca evita queda no void.

local _spawned     = false  -- true após primeiro spawn completo
local _report_on   = false  -- true quando deve reportar posição ao servidor

-- ── Recebe e aplica spawn ────────────────────────────────────────────────────

RegisterNetEvent("vHub:doSpawn")
AddEventHandler("vHub:doSpawn", function(data)
  if type(data) ~= "table" then return end

  -- Roda em thread própria para poder usar Wait e Await
  Citizen.CreateThread(function()

    -- Passo 1: aguarda o player estar completamente ativo no mundo
    -- Sem isso, SetEntityCoords não tem efeito
    local tentativas = 0
    while not NetworkIsPlayerActive(PlayerId()) and tentativas < 100 do
      Citizen.Wait(100)
      tentativas = tentativas + 1
    end
    if not NetworkIsPlayerActive(PlayerId()) then
      -- Se após 10s ainda não ativo, desiste mas loga
      print("[vHub][SPAWN] Player não ficou ativo após 10s — abortando spawn")
      return
    end

    -- Passo 2: fade out da tela durante a transição para evitar tela preta
    DoScreenFadeOut(200)
    Citizen.Wait(300)

    -- Passo 3: pega o ped ANTES de trocar o modelo
    local ped = PlayerPedId()

    -- Passo 4: carrega e aplica o modelo de ped
    local model_name = (type(data.model)=="string" and data.model~="") 
                        and data.model or "mp_m_freemode_01"
    local model_hash = GetHashKey(model_name)

    -- Só troca o modelo se for diferente do atual (evita reset de customização)
    if GetEntityModel(ped) ~= model_hash then
      RequestModel(model_hash)
      local wait_model = 0
      while not HasModelLoaded(model_hash) and wait_model < 5000 do
        Citizen.Wait(100)
        wait_model = wait_model + 100
      end

      if HasModelLoaded(model_hash) then
        SetPlayerModel(PlayerId(), model_hash)
        SetModelAsNoLongerNeeded(model_hash)
        -- ped muda após SetPlayerModel — precisa pegar o novo
        Citizen.Wait(0)
        ped = PlayerPedId()
      end
    end

    -- Passo 5: teleporta para a posição de spawn
    local pos = type(data.pos)=="table" and data.pos or nil

    if pos and tonumber(pos.x) and tonumber(pos.y) and tonumber(pos.z) then
      -- Congela para evitar queda durante o teleporte
      FreezeEntityPosition(ped, true)

      -- Teleporta — false em todos os bools = não reset velocidade/rotação
      SetEntityCoords(ped,
        tonumber(pos.x), tonumber(pos.y), tonumber(pos.z),
        false, false, false, false)

      if tonumber(pos.heading) then
        SetEntityHeading(ped, tonumber(pos.heading))
      end

      -- Aguarda o chunk do mundo carregar antes de descongelar
      -- RequestCollisionAtCoord diz ao engine para priorizar a área
      RequestCollisionAtCoord(pos.x, pos.y, pos.z)
      local wait_col = 0
      while not HasCollisionLoadedAroundEntity(ped) and wait_col < 3000 do
        Citizen.Wait(100)
        wait_col = wait_col + 100
      end

      FreezeEntityPosition(ped, false)
    end

    -- Passo 6: aplica saúde
    local health = tonumber(data.health) or 200
    health = math.max(100, math.min(200, health))
    SetEntityHealth(ped, health)

    -- Passo 7: garante visibilidade e remove invencibilidade de loading
    SetEntityVisible(ped, true, false)
    SetEntityInvincible(ped, false)

    -- Passo 8: fade in da tela
    DoScreenFadeIn(500)

    -- Marca como pronto
    _spawned   = true
    _report_on = true

    -- Notifica outros scripts client-side
    TriggerEvent("vHub:localSpawned", data)

    if data.first then
      TriggerEvent("vHub:firstSpawn", data)
      -- Pequena notificação nativa de boas-vindas
      BeginTextCommandThefeedPost("STRING")
      AddTextComponentSubstringPlayerName("Bem-vindo ao servidor!")
      EndTextCommandThefeedPostTicker(false, true)
    end

    print(("[vHub][SPAWN] Spawn aplicado — pos=(%.1f,%.1f,%.1f) model=%s first=%s"):format(
      (pos and pos.x or 0), (pos and pos.y or 0), (pos and pos.z or 0),
      model_name, tostring(data.first)))
  end)
end)

-- ── Report de posição a cada 10s ────────────────────────────────────────────
-- Salva posição para que ao reconectar o player volte ao mesmo lugar

Citizen.CreateThread(function()
  while true do
    Citizen.Wait(10000)
    if not _report_on then goto continue end

    local ped = PlayerPedId()
    if not ped or ped == 0 or IsEntityDead(ped) then goto continue end

    local coords  = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)

    TriggerServerEvent("vHub:savePos", {
      x       = coords.x,
      y       = coords.y,
      z       = coords.z,
      heading = heading,
    })

    ::continue::
  end
end)

-- ── Limpa report ao morrer ───────────────────────────────────────────────────

AddEventHandler("baseevents:onPlayerDied", function()
  _report_on = false   -- para de salvar posição ao morrer
end)

AddEventHandler("vHub:localSpawned", function()
  _report_on = true
end)

-- Getter para outros scripts
function vHub_isSpawned() return _spawned end
