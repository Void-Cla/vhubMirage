-- Provedor de destino. O vhub_hss continua sendo o unico owner de ped e bucket.

local E = VHubSpawnSelector.E
local _open = {}
local _openAt = {}

local function hasPerm(src, perm)
  local ok, uid = pcall(function() return exports.vhub:getUID(src) end)
  if ok and uid == 1 then return true end
  if IsPlayerAceAllowed(src, "vhub." .. perm) then return true end
  local okGroup, allowed = pcall(function()
    return exports.vhub_groups:hasPermission(src, perm)
  end)
  return okGroup and allowed == true
end

local function locationsFor(src)
  local result = {}
  for index, location in ipairs(Config.Location) do
    if not location.Perm or hasPerm(src, location.Perm) then
      result[#result + 1] = {
        index = index,
        Name = location.Name,
        Description = location.Description,
        Image = location.Image,
      }
    end
  end
  return result
end

local function loginGateActive()
  local ok, active = pcall(function() return exports.vhub_login:isGateActive() end)
  return ok and active == true
end

local function preparePending(src)
  src = tonumber(src)
  if not src or not GetPlayerName(src) then return nil, "player_invalido" end

  if loginGateActive() then
    local stepOk, step = pcall(function() return exports.vhub_login:getSessionStep(src) end)
    if not stepOk or step ~= "spawning" then return nil, "gate_invalido" end
  end

  local pendingOk, pending = pcall(function()
    return exports.vhub_hss:isPendingSpawn(src)
  end)
  if not pendingOk or pending ~= true then return nil, "spawn_nao_pendente" end

  local charOk, charId = pcall(function() return exports.vhub:getCharacterId(src) end)
  if not charOk or not tonumber(charId) then return nil, "personagem_invalido" end

  local data = locationsFor(src)
  if #data == 0 then return nil, "sem_destinos" end

  _open[src] = true
  return { data = data, last = Config.LastLocation, canBack = loginGateActive() }
end

-- Handoff atomico: o login recebe o payload antes de fechar sua NUI.
exports("preparePending", function(src)
  if GetInvokingResource() ~= "vhub_login" then return nil, "nao_autorizado" end
  return preparePending(src)
end)

AddEventHandler(VHubHSS.E.SPAWN_CHOOSE, function(src)
  if loginGateActive() then return end
  Citizen.CreateThread(function()
    local payload = preparePending(src)
    if payload then
      TriggerClientEvent(E.OPEN, src, payload)
      return
    end
    pcall(function() exports.vhub_hss:spawnAt(src, nil) end)
  end)
end)

local function sendResult(src, ok, err)
  TriggerClientEvent(E.RESULT, src, { ok = ok == true, err = err })
end

RegisterNetEvent(E.REQUEST_SPAWN)
AddEventHandler(E.REQUEST_SPAWN, function(index, useLast)
  local src = source
  if not _open[src] then return end
  _open[src] = nil

  Citizen.CreateThread(function()
    local position = nil
    if useLast ~= true then
      local idx = tonumber(index)
      if not idx or idx < 1 or idx % 1 ~= 0 then
        _open[src] = true
        sendResult(src, false, "destino_invalido")
        return
      end

      local location = Config.Location[idx]
      if not location or (location.Perm and not hasPerm(src, location.Perm)) then
        _open[src] = true
        sendResult(src, false, "destino_indisponivel")
        return
      end

      local coords = location.Coords
      position = { x = coords.x, y = coords.y, z = coords.z, heading = coords.w }
    end

    local called, spawned = pcall(function()
      return exports.vhub_hss:spawnAt(src, position)
    end)
    if not called or spawned ~= true then
      _open[src] = true
      sendResult(src, false, "spawn_recusado")
      return
    end
    if loginGateActive() then
      local completedOk, completed = pcall(function()
        return exports.vhub_login:completeEntry(src)
      end)
      if not completedOk or completed ~= true then
        DropPlayer(tostring(src), "Falha ao concluir o fluxo de entrada.")
        return
      end
    end
    sendResult(src, true)
  end)
end)

RegisterNetEvent(E.REQUEST_BACK)
AddEventHandler(E.REQUEST_BACK, function()
  local src = source
  if not _open[src] then return end
  if not loginGateActive() then
    sendResult(src, false, "retorno_indisponivel")
    return
  end
  _open[src] = nil

  Citizen.CreateThread(function()
    local returnedOk, characters = pcall(function()
      return exports.vhub_login:returnToCharacters(src)
    end)
    if not returnedOk or type(characters) ~= "table" then
      _open[src] = true
      sendResult(src, false, "retorno_recusado")
      return
    end
    TriggerClientEvent(E.BACK, src, characters)
  end)
end)

RegisterNetEvent(E.REQUEST_OPEN)
AddEventHandler(E.REQUEST_OPEN, function()
  local src = source
  local now = GetGameTimer()
  local previous = _openAt[src]
  if previous and now - previous < 5000 then return end
  _openAt[src] = now

  Citizen.CreateThread(function()
    local payload = preparePending(src)
    if payload then TriggerClientEvent(E.OPEN, src, payload) end
  end)
end)

AddEventHandler("playerDropped", function()
  local src = source
  _open[src] = nil
  _openAt[src] = nil
end)
