---@diagnostic disable: undefined-global, lowercase-global

-- server/drops.lua — itens no chão: persistentes, bucket-scoped, CAS pickup, TTL.
-- Budget: expireLoop 1/60s (~0.02 ms idle); broadcastBucket O(players_no_bucket).
-- Zero broadcast -1: todos os TriggerClientEvent são por src (bucket-scoped).

local M = {}; Inventory.DropSystem = M

local U        = Inventory.Utils
local Backpack = Inventory.Bag
local E        = VHubInvE

local _drops = {}   -- [drop_id] = { id, amount, meta, bucket, x, y, z }


-- ============================================================
-- HELPERS
-- ============================================================

local function getSQL()  return Inventory.SQL  end

local function ttl()
  return (Inventory.Drops and Inventory.Drops.ttl_seconds) or 300
end

local function pickupRange()
  return (Inventory.Drops and Inventory.Drops.pickup_range) or 3.0
end

local function makeDropId()
  return ('drop%d%05d'):format(GetGameTimer(), math.random(0, 99999)):sub(1, 20)
end

-- notifica todos os players no bucket (sem -1; sem filtro de distância no servidor)
local function broadcastBucket(bucket, event, payload)
  for _, sid in ipairs(GetPlayers()) do
    local s  = tonumber(sid)
    local ok, b = pcall(GetPlayerRoutingBucket, s)
    if ok and b == bucket then TriggerClientEvent(event, s, payload) end
  end
end


-- ============================================================
-- BOOT — carrega drops ativos do banco
-- ============================================================

-- reconcilia drops ativos do banco (restart sem dupe/perda)
function M.boot()
  local s = getSQL()
  local rows = s.query(
    [[SELECT drop_id, payload, bucket, x, y, z
      FROM vhub_inv_drops WHERE status='available' AND expires_at > NOW()]],
    {}
  )
  if not rows then return end
  for _, row in ipairs(rows) do
    local ok, data = pcall(json.decode, tostring(row.payload or ''))
    if ok and type(data) == 'table' and data.id then
      _drops[row.drop_id] = {
        id     = data.id,
        amount = data.amount or 1,
        meta   = data.meta,
        bucket = tonumber(row.bucket) or 0,
        x = tonumber(row.x), y = tonumber(row.y), z = tonumber(row.z),
      }
    end
  end
end


-- ============================================================
-- LIFECYCLE
-- ============================================================

-- cria drop na posição do jogador e persiste no banco (chamar em thread)
function M.create(src, item_id, amount, meta)
  if not U.itemDef(item_id) then return false, 'item' end
  amount = U.validQty(amount); if not amount then return false, 'qty' end

  local ped = GetPlayerPed(src)
  if not ped or ped == 0 then return false, 'ped' end
  local ok_pos, pos = pcall(GetEntityCoords, ped)
  if not ok_pos or not pos then return false, 'pos' end

  local ok_bk, bucket = pcall(GetPlayerRoutingBucket, src)
  if not ok_bk then bucket = 0 end

  local drop_id = makeDropId()
  local payload = json.encode({ id = item_id, amount = amount, meta = meta })

  getSQL().execute(
    [[INSERT INTO vhub_inv_drops (drop_id, payload, bucket, x, y, z, status, expires_at)
      VALUES (?, ?, ?, ?, ?, ?, 'available', DATE_ADD(NOW(), INTERVAL ? SECOND))
      ON DUPLICATE KEY UPDATE drop_id=drop_id]],
    { drop_id, payload, bucket, pos.x, pos.y, pos.z, ttl() }
  )

  _drops[drop_id] = {
    id = item_id, amount = amount, meta = meta,
    bucket = bucket, x = pos.x, y = pos.y, z = pos.z,
  }

  broadcastBucket(bucket, E.DROP_ADD, {
    id = drop_id, item = item_id, amount = amount,
    x = pos.x, y = pos.y, z = pos.z,
  })

  return true, drop_id
end

-- CAS pickup: só um jogador vence (chamar em thread)
function M.pickup(src, drop_id)
  if type(drop_id) ~= 'string' or drop_id == '' then return false, 'invalido' end
  local d = _drops[drop_id]
  if not d then return false, 'inexistente' end

  -- bucket
  local ok_bk, bucket = pcall(GetPlayerRoutingBucket, src)
  if not ok_bk or bucket ~= d.bucket then return false, 'bucket' end

  -- distância server-side
  local ped = GetPlayerPed(src)
  if not ped or ped == 0 then return false, 'ped' end
  local ok_pos, ppos = pcall(GetEntityCoords, ped)
  if not ok_pos or not ppos then return false, 'pos' end
  if #(ppos - vector3(d.x, d.y, d.z)) > pickupRange() then return false, 'longe' end

  -- CAS atômico no banco: claimed só se ainda available e não expirado
  local affected = getSQL().execute(
    [[UPDATE vhub_inv_drops SET status='claimed', revision=revision+1
      WHERE drop_id=? AND status='available' AND expires_at > NOW()]],
    { drop_id }
  )
  if not affected or affected < 1 then return false, 'claimed' end

  -- vencedor do CAS: adiciona ao inventário
  local ok, err = Backpack.give(src, d.id, d.amount, d.meta)
  if not ok then
    -- reverte claim para não perder o drop
    getSQL().execute(
      [[UPDATE vhub_inv_drops SET status='available' WHERE drop_id=?]],
      { drop_id }
    )
    return false, err or 'cheio'
  end

  _drops[drop_id] = nil
  broadcastBucket(d.bucket, E.DROP_DEL, { id = drop_id })
  return true
end

-- envia todos os drops do bucket do jogador ao entrar
function M.syncPlayer(src)
  local ok_bk, bucket = pcall(GetPlayerRoutingBucket, src)
  if not ok_bk then bucket = 0 end
  local list = {}
  for did, d in pairs(_drops) do
    if d.bucket == bucket then
      list[#list + 1] = { id = did, item = d.id, amount = d.amount, x = d.x, y = d.y, z = d.z }
    end
  end
  if #list > 0 then TriggerClientEvent(E.DROP_ADD, src, list) end
end


-- ============================================================
-- EXPIRE LOOP (budget: 1/60 Hz; cleanup de TTL expirado)
-- ============================================================

-- inicia o loop de expiração de drops (chamar uma vez no boot)
function M.startExpireLoop()
  CreateThread(function()
    while true do
      Wait(60000)   -- 1 Hz/60 = 0.017 Hz; budget declarado (L-18)
      local expired = getSQL().query(
        [[SELECT drop_id, bucket FROM vhub_inv_drops
          WHERE status='available' AND expires_at <= NOW()]],
        {}
      )
      if expired then
        for _, row in ipairs(expired) do
          if _drops[row.drop_id] then
            broadcastBucket(tonumber(row.bucket) or 0, E.DROP_DEL, { id = row.drop_id })
            _drops[row.drop_id] = nil
          end
          getSQL().execute(
            [[UPDATE vhub_inv_drops SET status='expired' WHERE drop_id=?]],
            { row.drop_id }
          )
        end
      end
    end
  end)
end
