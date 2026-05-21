-- server/notify.lua — Notificador de webhook (Discord)
local Notify = {}; Notify.__index = Notify; vHub.Notify = Notify

function Notify:send(ch, msg, retries)
  local url = (vHub.cfg and vHub.cfg.webhooks or {})[ch]
  if url and url ~= "" then
    retries = tonumber(retries) or 3
    PerformHttpRequest(url, function(code)
      if type(code) == "number" and code >= 200 and code < 300 then return end
      if retries > 0 then
        SetTimeout(5000, function() self:send(ch, msg, retries - 1) end)
      elseif (vHub.cfg or {}).log_level > 0 then
        if vHub and vHub.Logger then vHub.Logger:warn("notify", ("falha webhook canal=%s code=%s"):format(tostring(ch), tostring(code)), {code=code, canal=ch}) end
      end
    end, "POST",
      json.encode({content=msg}), {["Content-Type"]="application/json"})
  end
end
