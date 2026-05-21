-- server/compat.lua — shims de compatibilidade vRP
local vRP_compat = {}; _G.vRP = vRP_compat

function vRP_compat:getUserId(src)     return vHub.Auth:getUID(src) end
function vRP_compat:getUser(src)       return vHub.Auth:getUser(src) end
function vRP_compat:setUData(u,k,v)    vHub.setUData(u,k,v) end
function vRP_compat:getUData(u,k)      return vHub.getUData(u,k) end
function vRP_compat:setCData(c,k,v)    vHub.setCData(c,k,v) end
function vRP_compat:getCData(c,k)      return vHub.getCData(c,k) end
function vRP_compat:setGData(k,v)      vHub.setGData(k,v) end
function vRP_compat:getGData(k)        return vHub.getGData(k) end

function vRP_compat:prepare(n,sql)     vHub.State:prepare(n,sql) end
function vRP_compat:query(n,p)
  vHub.assertThread()
  return Citizen.Await(vHub.State:query(n,p))
end
function vRP_compat:execute(n,p)
  vHub.assertThread()
  return Citizen.Await(vHub.State:exec(n,p))
end
function vRP_compat:scalar(n,p)
  vHub.assertThread()
  return Citizen.Await(vHub.State:scalar(n,p))
end

function vRP_compat:registerExtension(ext)
  if ext.event then
    for evname, fn in pairs(ext.event) do
      local bound = function(...) fn(ext, ...) end
      vHub.Kernel:on("vHub:" .. evname, bound)
      vHub.Kernel:on("vRP:"  .. evname, bound)
    end
  end
  if ext.remote then
    for fname, fn in pairs(ext.remote) do
      vHub.Kernel:net("vRP:ext:" .. fname, function(src, ...)
        fn(ext, vHub.Auth:getUser(src), ...)
      end, {rate={20, 2000, 5000}})
    end
  end
end

-- Proxy / Tunnel shims
local _ifaces = {}
_G.Proxy = {
  addInterface = function(_, name, iface)
    _ifaces[name] = iface
  end,
  getInterface = function(_, name)
    return _ifaces[name] or vRP_compat
  end,
}

_G.Tunnel = {
  bindInterface = function(_, name)
    if vHub and vHub.Logger then vHub.Logger:info("compat", ("Tunnel.bindInterface('%s') → usar Kernel:net"):format(tostring(name))) end
  end,
  getInterface = function(_, name, src)
    return setmetatable({}, {
      __index = function(_, fname)
        return function(...)
          vHub.Kernel:emit(src, "vRP:tunnel:" .. name .. ":" .. fname, ...)
        end
      end
    })
  end,
}
