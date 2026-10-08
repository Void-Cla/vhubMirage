-- scrypt.lua — ponte local Lua para o KDF Node do mesmo resource consumidor.

VHubScrypt = VHubScrypt or {}

local resource = GetCurrentResourceName()
local channel = "__vhub_crypto:" .. resource
local sequence = 0
local pending = {}

AddEventHandler(channel .. ":response", function(id, ok, value, elapsed_ms)
  local request = pending[id]
  if not request then return end
  pending[id] = nil
  request:resolve({ ok = ok == true, value = value, elapsed_ms = tonumber(elapsed_ms) or 0 })
end)

local function execute(op, password, pepper, encoded)
  sequence = (sequence + 1) % 2147483647
  local id = ("%s:%d:%d"):format(resource, GetGameTimer(), sequence)
  local request = promise.new()
  pending[id] = request

  SetTimeout(30000, function()
    if pending[id] ~= request then return end
    pending[id] = nil
    request:resolve({ ok = false, value = "kdf_timeout", elapsed_ms = 30000 })
  end)

  TriggerEvent(channel .. ":request", id, op, password, pepper, encoded)
  return Citizen.Await(request)
end

-- Gera hash scrypt autocontido; retorna hash, latencia ou nil, erro.
function VHubScrypt.hash(password, pepper)
  local response = execute("hash", password, pepper, nil)
  if not response.ok or type(response.value) ~= "string" then
    return nil, tostring(response.value or "kdf_indisponivel")
  end
  return response.value, response.elapsed_ms
end

-- Verifica hash em tempo constante; retorna valido, rehash, erro, latencia.
function VHubScrypt.verify(password, pepper, encoded)
  local response = execute("verify", password, pepper, encoded)
  if not response.ok or type(response.value) ~= "table" then
    return false, false, tostring(response.value or "kdf_indisponivel"), response.elapsed_ms
  end
  return response.value.valid == true, response.value.rehash == true,
    response.value.error, response.elapsed_ms
end
