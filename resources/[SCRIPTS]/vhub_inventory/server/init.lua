---@diagnostic disable: undefined-global, lowercase-global

-- server/init.lua — boot, schema, sessoes e net events (intencao do cliente).
-- Toda entrada de rede passa por cooldown + validacao antes de tocar o backpack.

local Backpack    = Inventory.Bag
local ItemUse     = Inventory.ItemUse
local Containers  = Inventory.Containers
local Transfer    = Inventory.Transfer
local DropSystem  = Inventory.DropSystem
local P2PSystem   = Inventory.P2PSystem
local U           = Inventory.Utils
local E           = VHubInvE

local _cd = {}   -- [src] = { [action] = expires_ms } — anti double-action


-- ============================================================
-- COOLDOWN (anti double-action por jogador)
-- ============================================================

-- true se a acao pode rodar agora; arma o cooldown
local function cooled(src, action)
  local now = GetGameTimer()
  local t = _cd[src]; if not t then t = {}; _cd[src] = t end
  if t[action] and t[action] > now then return false end
  t[action] = now + (Inventory.Security.action_cooldown_ms or 250)
  return true
end


-- ============================================================
-- BOOT
-- ============================================================

AddEventHandler('onResourceStart', function(res)
  if res ~= GetCurrentResourceName() then return end
  CreateThread(function()
    Inventory.SQL:initSchema()

    -- migrações forward-only (sempre, independente de vnext)
    local ok = Inventory.Migrations.runAll()
    if not ok then
      -- fail-closed: resource não sinaliza ready; mantém estado anterior intacto
      U.quarantine(0, 'boot:migrations', 'runAll retornou false — resource bloqueado')
      return
    end

    -- restart com players online: recarrega mochilas e re-sincroniza HUD
    for _, sid in ipairs(GetPlayers()) do
      local src  = tonumber(sid)
      local user = exports.vhub:getUser(src)
      if user and user.char_id then
        Backpack.load(src, user.char_id)
        TriggerClientEvent(E.HUD, src, { charId = user.char_id })
        Backpack.pushHotbar(src)
      end
    end
    -- F6: drops — reconcilia ativos do banco e inicia expiração periódica
    DropSystem.boot()
    DropSystem.startExpireLoop()

    TriggerEvent('vhub_inventory:server:ready')
  end)
end)


-- ============================================================
-- SESSOES (referencia viva via evento publico do core)
-- ============================================================

AddEventHandler('vHub:characterLoad', function(user)
  if not user or not user.source or not user.char_id then return end
  local src = user.source
  CreateThread(function()
    Backpack.load(src, user.char_id)
    -- envia o ID do PERSONAGEM ao HUD (troca de char re-dispara characterLoad)
    TriggerClientEvent(E.HUD, src, { charId = user.char_id })
    Backpack.pushHotbar(src)
    DropSystem.syncPlayer(src)   -- F6: envia drops ativos do bucket ao entrar
  end)
end)

-- morte/respawn: fecha bau aberto (spawn = pos-morte = distancia/bucket invalidos)
AddEventHandler('vHub:playerSpawn', function(user)
  if not user or not user.source then return end
  local src = tonumber(user.source)
  if not src or not GetPlayerName(src) then return end
  local cid = Containers.openedBy(src)
  if not cid then return end
  Containers.close(src)
  TriggerClientEvent(E.CONTAINER_CLOSE, src)
end)

AddEventHandler('playerDropped', function()
  local src = source
  Containers.close(src)       -- sai do baú aberto (flush se foi o ultimo viewer)
  Backpack.unload(src)        -- flush final (preserva o cliente)
  ItemUse.resetSession(src)   -- limpa contador de request_id (VNext op dedup)
  _cd[src] = nil
end)

AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  Backpack.flushAll()    -- flush triplo #3 (resource stop)
  Containers.flushAll()
end)

-- veículo de porta-malas deletado: fecha UI/lease dos viewers antes do handle expirar
AddEventHandler('entityRemoved', function(entity)
  Containers.forceCloseTrunkEntity(entity)
end)


-- ============================================================
-- NET EVENTS — INTENCAO (cliente nunca decide verdade)
-- ============================================================

-- cliente pede o snapshot completo (abrir mochila).
-- Em thread: o dossie da chave de veiculo usa Citizen.Await no cache-miss do conce.
RegisterNetEvent(E.REQUEST_SYNC)
AddEventHandler(E.REQUEST_SYNC, function()
  local src = source
  if not cooled(src, 'request_sync') then return end
  CreateThread(function()
    local snap = Backpack.wireSnapshot(src)
    if snap then TriggerClientEvent(E.OPEN, src, snap) end
  end)
end)

-- cliente pede o id do personagem para o HUD (NUI recem-pronta)
RegisterNetEvent(E.HUD_REQ)
AddEventHandler(E.HUD_REQ, function()
  local src = source
  if not cooled(src, 'hud_req') then return end
  local cid = Backpack.charId(src)
  if cid then TriggerClientEvent(E.HUD, src, { charId = cid }) end
end)

-- usar item de um slot
RegisterNetEvent(E.USE)
AddEventHandler(E.USE, function(payload)
  local src = source
  if type(payload) ~= 'table' then return end
  if not cooled(src, 'use') then return end

  local slot = U.validSlot(payload.slot, Inventory.Backpack.slots or 30)
  if not slot then return end

  ItemUse.run(src, slot, payload.id)
end)

-- mover/split/merge/swap dentro da mochila (drag-and-drop)
RegisterNetEvent(E.MOVE)
AddEventHandler(E.MOVE, function(payload)
  local src = source
  if type(payload) ~= 'table' then return end
  if not cooled(src, 'move') then return end

  local ok = Backpack.move(src, payload.from, payload.to, payload.qty)
  if not ok then
    -- reenviamos o estado real dos slots tocados
    Backpack.rollback(src, { payload.from, payload.to }, 'mov_negado')
  end
end)


-- ============================================================
-- NET EVENTS — BAÚS (containers)
-- ============================================================

-- abrir baú: proximidade, permissao e anti-spoof validados no servidor
RegisterNetEvent(E.OPEN_CONTAINER)
AddEventHandler(E.OPEN_CONTAINER, function(desc)
  local src = source
  if not cooled(src, 'open_container') then return end
  Containers.requestOpen(src, desc)
end)

-- cliente avisa que fechou o baú
RegisterNetEvent(E.CLOSE_CONTAINER)
AddEventHandler(E.CLOSE_CONTAINER, function()
  Containers.close(source)
end)

-- mochila -> baú
RegisterNetEvent(E.STORE)
AddEventHandler(E.STORE, function(p)
  local src = source
  if type(p) ~= 'table' then return end
  if not cooled(src, 'store') then return end
  Transfer.store(src, p.from, p.to, p.qty)
end)

-- baú -> mochila
RegisterNetEvent(E.RETRIEVE)
AddEventHandler(E.RETRIEVE, function(p)
  local src = source
  if type(p) ~= 'table' then return end
  if not cooled(src, 'retrieve') then return end
  Transfer.retrieve(src, p.from, p.to, p.qty)
end)


-- vincular item a um slot (1-5) da hotbar (ou limpar com id=nil)
RegisterNetEvent(E.SET_BIND)
AddEventHandler(E.SET_BIND, function(p)
  local src = source
  if type(p) ~= 'table' then return end
  if not cooled(src, 'set_bind') then return end
  Backpack.setBind(src, p.slot, p.id)
end)


-- ============================================================
-- NET EVENTS — DROPS E P2P (F6)
-- ============================================================

-- jogar item no chão: tira do slot e cria drop na posição do jogador
RegisterNetEvent(E.DROP)
AddEventHandler(E.DROP, function(p)
  local src = source
  if type(p) ~= 'table' then return end
  if not cooled(src, 'drop') then return end
  local slot = U.validSlot(p.slot, Inventory.Backpack and Inventory.Backpack.slots or 30)
  local qty  = U.validQty(p.qty)
  if not slot or not qty then return end
  CreateThread(function()
    local entry = Backpack.peek(src, slot)
    if not entry or qty > entry.amount then return end
    local def = U.itemDef(entry.id)
    if not def or def.perdivel == false then return end
    if not Backpack.takeFromSlot(src, slot, qty) then return end
    local ok = DropSystem.create(src, entry.id, qty, entry.meta)
    if not ok then
      -- restituição: drop não persistido, devolve ao slot original
      Backpack.giveToSlot(src, slot, entry.id, qty, entry.meta)
    end
  end)
end)

-- pegar item do chão (CAS — só um vence)
RegisterNetEvent(E.PICKUP)
AddEventHandler(E.PICKUP, function(p)
  local src = source
  if type(p) ~= 'table' then return end
  if not cooled(src, 'pickup') then return end
  if type(p.id) ~= 'string' or p.id == '' then return end
  CreateThread(function()
    DropSystem.pickup(src, p.id)
  end)
end)

-- enviar item para jogador próximo (slot-based, meta preservada)
RegisterNetEvent(E.P2P)
AddEventHandler(E.P2P, function(p)
  local src = source
  if type(p) ~= 'table' then return end
  if not cooled(src, 'p2p') then return end
  local slot = U.validSlot(p.slot, Inventory.Backpack and Inventory.Backpack.slots or 30)
  local qty  = U.validQty(p.qty)
  if not slot or not qty then return end
  CreateThread(function()
    P2PSystem.send(src, tonumber(p.target), slot, qty)
  end)
end)


-- ============================================================
-- NET EVENTS — HOTBAR (continuação)
-- ============================================================

-- usar item pela hotbar: resolve item do bind -> acha slot -> dispara uso
RegisterNetEvent(E.USE_HOTBAR)
AddEventHandler(E.USE_HOTBAR, function(p)
  local src = source
  if type(p) ~= 'table' then return end
  if not cooled(src, 'use') then return end

  local n = U.validSlot(p.slot, 5); if not n then return end
  local id = Backpack.getBind(src, n); if not id then return end

  local slot = Backpack.findItemSlot(src, id)
  if not slot then TriggerClientEvent(E.NOTIFY, src, 'Você não tem esse item'); return end

  ItemUse.run(src, slot, id)
end)
