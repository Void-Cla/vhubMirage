---@diagnostic disable: undefined-global, lowercase-global

-- server/p2p.lua — transferência direta de item entre jogadores próximos (P2P).
-- Módulo: Inventory.P2PSystem. Config: Inventory.P2P.range (config/inventory.lua).
-- Servidor valida: online, mesmo bucket, distância, slot, posse e capacidade do alvo.
-- Debit via takeFromSlot (slot exato) antes do credit; reembolso automático se falhar.

local M = {}; Inventory.P2PSystem = M

local U        = Inventory.Utils
local Backpack = Inventory.Bag
local E        = VHubInvE

local function range()
  local cfg = Inventory.P2P
  return (type(cfg) == 'table' and type(cfg.range) == 'number' and cfg.range) or 5.0
end


-- ============================================================
-- API
-- ============================================================

-- transfere item do slot de src para target.
-- `slot` = slot de origem na mochila de src.
-- `qty`  = quantidade já validada (U.validQty) — nil bloqueia aqui.
function M.send(src, target, slot, qty)
  -- tipo e validade básica
  target = tonumber(target)
  if type(target) ~= 'number' or not GetPlayerName(target) then return false, 'target' end
  if src == target then return false, 'self' end
  slot = U.validSlot(slot, Inventory.Backpack and Inventory.Backpack.slots or 30)
  if not slot then return false, 'slot' end
  qty = U.validQty(qty); if not qty then return false, 'qty' end

  -- mesmo bucket
  local ok_bs, bs = pcall(GetPlayerRoutingBucket, src)
  local ok_bt, bt = pcall(GetPlayerRoutingBucket, target)
  if not ok_bs or not ok_bt or bs ~= bt then return false, 'bucket' end

  -- distância server-side
  local ps, pt = GetPlayerPed(src), GetPlayerPed(target)
  if not ps or ps == 0 or not pt or pt == 0 then return false, 'ped' end
  local ok_ps, pos_s = pcall(GetEntityCoords, ps)
  local ok_pt, pos_t = pcall(GetEntityCoords, pt)
  if not ok_ps or not ok_pt then return false, 'pos' end
  if #(pos_s - pos_t) > range() then return false, 'longe' end

  -- resolve item do slot ANTES de mutar (snapshot atômico)
  local entry = Backpack.peek(src, slot)
  if not entry then return false, 'slot_vazio' end
  if qty > entry.amount then return false, 'qty_slot' end
  local def = U.itemDef(entry.id)
  if not def or def.negociavel == false then return false, 'bloqueado' end

  -- target pode receber?
  if not Backpack.canFit(target, entry.id, qty) then return false, 'cheio' end

  -- debit (slot exato — preserva meta correta)
  if not Backpack.takeFromSlot(src, slot, qty) then return false, 'debit' end

  -- credit (best-effort; reembolso em falha)
  local ok, err = Backpack.give(target, entry.id, qty, entry.meta)
  if not ok then
    Backpack.give(src, entry.id, qty, entry.meta)   -- reembolso (L-03)
    return false, err or 'credit'
  end

  local label = (def and def.label) or entry.id
  TriggerClientEvent(E.NOTIFY, src,    ('Você enviou %dx %s.'):format(qty, label))
  TriggerClientEvent(E.NOTIFY, target, ('Você recebeu %dx %s.'):format(qty, label))
  return true
end
