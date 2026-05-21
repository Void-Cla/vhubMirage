-- server/exports.lua  superf cie p blica do vhub_garage
-- Os exports sens veis exigem invoker confi vel (cheque por nome de resource).
---@diagnostic disable: undefined-global

local SQL  = VHubGarage.SQL
local Core = VHubGarage.Core
local CFG  = VHubGarage.cfg

local TRUSTED = {
  ['vhub']           = true,
  ['vhub_inventory'] = true,
  ['vhub_money']     = true,
  ['vhub_identity']  = true,
  ['vhub_groups']    = true,
  ['vhub_player_state'] = true,
  ['vhub_admin']     = true,
}

local function _invoker_allowed()
  local caller = GetInvokingResource()
  if not caller then return true end
  return TRUSTED[caller] == true
end

-- ---------- leitura --------------------------------------------------------
exports('getVehicle', function(plate)
  if type(plate) ~= 'string' then return nil end
  local p = VHubGarage.U.normalizePlate(plate); if not p then return nil end
  return SQL:getVehicle(p)
end)

exports('listOwnerVehicles', function(char_id)
  local cid = tonumber(char_id); if not cid then return {} end
  return SQL:listByOwner(cid) or {}
end)

exports('isImpound', function(plate)
  local p = VHubGarage.U.normalizePlate(plate); if not p then return false end
  local v = SQL:getVehicle(p)
  return v and v.status == 'impound' or false
end)

exports('ipvaUntil', function(plate)
  local p = VHubGarage.U.normalizePlate(plate); if not p then return 0 end
  local v = SQL:getVehicle(p)
  return v and tonumber(v.ipva_paid_until) or 0
end)

-- ---------- escrita (apenas resource confi vel) ----------------------------
exports('forceTransfer', function(plate, new_char_id)
  if not _invoker_allowed() then return false end
  local p = VHubGarage.U.normalizePlate(plate); if not p then return false end
  local cid = tonumber(new_char_id); if not cid then return false end
  Citizen.CreateThread(function()
    SQL:updateOwner(p, cid)
    SQL:grantKey(p, cid, 'owner', cid, nil)
    Core:log(p, 'force_transfer', cid, {})
  end)
  return true
end)

exports('forceImpound', function(plate, reason, fee_extra)
  if not _invoker_allowed() then return false end
  return exports[GetCurrentResourceName()]:impoundVehicle(plate, reason, fee_extra)
end)
