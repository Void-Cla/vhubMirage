-- server/exports.lua — safe cross-resource exports
local _warned_empty_trust = false
local function _invoker_allowed()
  local trust = vHub.cfg and vHub.cfg.trusted_resources
  if not trust or next(trust) == nil then
    if not _warned_empty_trust and vHub.Logger then
      _warned_empty_trust = true
      vHub.Logger:warn("exports",
        "trusted_resources VAZIO — exports sensíveis NEGADOS (default-deny). Popule vHub.cfg.trusted_resources.")
    end
    return false                      -- N0-2: era return true (default-permissivo)
  end
  local caller = GetInvokingResource()
  if not caller then return false end -- N0-2: era return true
  return trust[caller] == true
end

vHub.Kernel:export("getVHub",      function()           return vHub            end)
vHub.Kernel:export("getUser",      function(src)        return vHub.Auth:getUser(src) end)
vHub.Kernel:export("getUID",       function(src)        return vHub.Auth:getUID(src)  end)
vHub.Kernel:export("hasPerm",      function(u,p)        return vHub.Kernel:hasPerm(u,p)   end)
vHub.Kernel:export("grantPerm",    function(u,p)
  if not _invoker_allowed() then return false end
  vHub.Kernel:grantPerm(u,p)
end)
vHub.Kernel:export("getVehicle",   function(plate)      local p=plate and plate:upper() or nil; return p and vHub.Vehicle._veh[p] end)
vHub.Kernel:export("transferKey",  function(pl,key)
  if not _invoker_allowed() then return false end
  return vHub.Vehicle:transferKey(pl,key)
end)
vHub.Kernel:export("getVehicleByKey", function(key)     return vHub.Vehicle:byKey(key)   end)
vHub.Kernel:export("banPlayer",    function(u,r,by)
  if not _invoker_allowed() then return false end
  vHub.Auth:ban(u,r,by)
end)
vHub.Kernel:export("unbanPlayer",  function(u)
  if not _invoker_allowed() then return false end
  vHub.Auth:unban(u)
end)
