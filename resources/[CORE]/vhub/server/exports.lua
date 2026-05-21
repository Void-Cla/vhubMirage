-- server/exports.lua — safe cross-resource exports
local function _invoker_allowed()
  local trust = vHub.cfg and vHub.cfg.trusted_resources
  if not trust or next(trust) == nil then return true end
  local caller = GetInvokingResource()
  if not caller then return true end
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
