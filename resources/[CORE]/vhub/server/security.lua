-- server/security.lua — Helpers de segurança e validadores padrão
local Sec = {}; Sec.__index = Sec; vHub.Security = Sec

function Sec:requireAdmin(src, action)
  if IsPlayerAceAllowed and IsPlayerAceAllowed(src, "vhub.admin") then return true end
  local uid = vHub.Auth:getUID(src)
  if uid and vHub.Kernel:hasPerm(uid, "admin." .. action) then return true end
  self:_permFail(src, "admin." .. action, action)
  return false
end

function Sec:_permFail(src, event, perm)
  if vHub and vHub.Logger then vHub.Logger:warn("security", ("src=%d sem permissão '%s'"):format(src, tostring(perm))) end
  vHub.Notify:send("security",
    ("🚨 Acesso negado | src:`%d` perm:`%s`"):format(src, tostring(perm)))
end

function Sec:checkPayload(src, event, size)
  if size > (vHub.cfg.max_payload or 8192) then
    if vHub and vHub.Logger then vHub.Logger:warn("security", ("Payload grande src=%d evt=%s"):format(src, tostring(event)), {size=size}) end
    return false
  end
  return true
end

-- Default validator: pass-through
-- Specific validators added by modules: vHub.State:addValidator(fn)
-- fn(tx, snap, mem) → true | false, "reason"
vHub.State:addValidator(function(tx, snap, mem) return true end)
