-- vhub_spawselector/server/init.lua — provedor de coordenada do Spawn Owner
-- PAPEL (Void-Zero/It.1): NÃO toca o ped, NÃO teleporta. Abre a UI quando o
--   vhub_player_state pede (chooseSpawn), valida a escolha server-side
--   (index + permissão por local) e devolve via exports.vhub_player_state:spawnAt.
-- ROLLBACK: parar este resource → player_state spawna direto (fluxo antigo).

local _open = {}  -- [src] = true → UI aberta por este fluxo (anti-spoof do RequestSpawn)

-- ── Permissão (uid=1 owner > ACE > vhub_groups) ───────────────────────────────

local function hasPerm(src, perm)
  local ok, uid = pcall(function() return exports.vhub:getUID(src) end)
  if ok and uid == 1 then return true end
  if IsPlayerAceAllowed(src, "vhub." .. perm) then return true end
  local okg, has = pcall(function() return exports.vhub_groups:hasPermission(src, perm) end)
  return okg and has == true
end

-- Locations visíveis ao jogador (filtra por Config.Location[i].Perm, se definida)
local function locationsPara(src)
  local out = {}
  for i, loc in ipairs(Config.Location) do
    if not loc.Perm or hasPerm(src, loc.Perm) then
      out[#out + 1] = {
        index       = i,            -- index CANÔNICO (pós-filtro a UI não pode renumerar)
        Name        = loc.Name,
        Description = loc.Description,
        Image       = loc.Image,
      }
    end
  end
  return out
end

-- ── Abertura: somente quando o Spawn Owner delega ─────────────────────────────

AddEventHandler("vhub_player_state:chooseSpawn", function(src)
  Citizen.CreateThread(function()
    local user = exports.vhub:getUser(src)
    if not user or not user.char_id then
      -- sem sessão válida: devolve o controle imediatamente (timeout não espera)
      pcall(function() exports.vhub_player_state:spawnAt(src, nil) end)
      return
    end
    _open[src] = true
    -- NOTA(IT.1/gate contrato): o CORE FROZEN NÃO expõe setCData via export
    --   (só global vHub.setCData). 'spawned'/'last_spawn' não tinham leitor algum
    --   (write-only morto) → removidos. O 1º-spawn é decidido por user.spawns no owner.
    TriggerClientEvent("vhub_spawselector:client:Open", src, {
      data = locationsPara(src),
      last = Config.LastLocation,
    })
  end)
end)

-- ── Escolha do jogador ────────────────────────────────────────────────────────
-- index válido → coordenada do Config | index nil/inválido (fechar) → pos salva.

RegisterNetEvent("vhub_spawselector:server:RequestSpawn")
AddEventHandler("vhub_spawselector:server:RequestSpawn", function(index)
  local src = source
  if not _open[src] then return end   -- só aceita se fomos nós que abrimos
  _open[src] = nil

  Citizen.CreateThread(function()
    local idx = tonumber(index)
    local loc = idx and Config.Location[idx] or nil
    local pos = nil

    if loc then
      -- revalida permissão (o filtro de UI não é fronteira de segurança)
      if loc.Perm and not hasPerm(src, loc.Perm) then loc = nil end
    end

    if loc then
      local c = loc.Coords
      pos = { x = c.x, y = c.y, z = c.z, heading = c.w }
    end

    local ok, done = pcall(function() return exports.vhub_player_state:spawnAt(src, pos) end)
    if not ok then
      print(("[vhub_spawselector] spawnAt indisponível src=%d"):format(src))
      return
    end
    -- Sem hold pendente (abertura manual via RequestOpen): teleporte simples
    if done ~= true and pos then
      pcall(function()
        exports.vhub_player_state:teleport(src, pos.x, pos.y, pos.z, pos.heading)
      end)
    end
  end)
end)

-- ── Abertura manual (export Open / admin) — throttle 5s por src ───────────────

local _open_at = {}
RegisterNetEvent("vhub_spawselector:server:RequestOpen")
AddEventHandler("vhub_spawselector:server:RequestOpen", function()
  local src = source
  local now = GetGameTimer()
  if (now - (_open_at[src] or 0)) < 5000 then return end
  _open_at[src] = now
  Citizen.CreateThread(function()
    local user = exports.vhub:getUser(src)
    if not user or not user.char_id then return end
    _open[src] = true
    TriggerClientEvent("vhub_spawselector:client:Open", src, {
      data = locationsPara(src),
      last = Config.LastLocation,
    })
  end)
end)

-- Higiene: jogador caiu com UI aberta → owner resolve via timeout próprio
AddEventHandler("playerDropped", function()
  local src = source
  _open[src]    = nil
  _open_at[src] = nil
end)
