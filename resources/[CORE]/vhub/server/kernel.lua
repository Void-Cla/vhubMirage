-- server/kernel.lua — Kernel (barramento de eventos, rate limit, permissões, exports)
-- Responsabilidade: fornecer `vHub.Kernel` (API pública de eventos e exports)

local K = {}; K.__index = K; vHub.Kernel = K

K._rate  = {}   -- { [src..":"..action] = {hits,window,blocked} }
K._perms = {}   -- { [uid] = { [perm] = true } }

-- Rate-limiter GC — runs every 2 min to prevent memory bloat
Citizen.CreateThread(function()
  while true do
    Citizen.Wait(120000)
    local now = GetGameTimer()
    for key, r in pairs(K._rate) do
      if (now - r.window) > 180000 and r.blocked < now then
        K._rate[key] = nil
      end
    end
  end
end)

function K:net(name, handler, opts)
  opts = opts or {}
  RegisterNetEvent(name)
  AddEventHandler(name, function(...)
    local src = source
    if (not src) or src <= 0 then return end   -- reject server/invalid
    local args = {...}
    -- Compute payload size (bytes) for security check. Prefer msgpack, fallback to json.
    local payload_size = 0
    do
      local ok, packed = pcall(function() return msgpack.pack(args) end)
      if ok and type(packed) == "string" then
        payload_size = #packed
      else
        local ok2, encoded = pcall(function() return json.encode(args) end)
        if ok2 and type(encoded) == "string" then payload_size = #encoded end
      end
    end
    if vHub.Security and not vHub.Security:checkPayload(src, name, payload_size) then return end

    -- 1. Rate limit
    if opts.rate then
      if not self:_rateOK(src, name, opts.rate[1], opts.rate[2], opts.rate[3]) then
        if vHub and vHub.Logger then vHub.Logger:warn("kernel", ("src=%d bloqueado no evento '%s'"):format(src, name)) end
        return  -- silent: nunca avisar o cliente que foi bloqueado
      end
    end

    -- 2. Permission guard
    local perm = opts.perm or (opts.admin and "admin.*")
    if perm then
      local uid = vHub.Auth:getUID(src)
      if not uid or not self:hasPerm(uid, perm) then
        vHub.Security:_permFail(src, name, perm); return
      end
    end

    -- 3. Protected dispatch — errors never crash the server
    if opts.async == false then
      local ok, err = pcall(handler, src, table.unpack(args))
      if not ok then if vHub and vHub.Logger then vHub.Logger:error("kernel", ("ERRO NET %s → %s"):format(name, tostring(err))) end end
    else
      Citizen.CreateThread(function()   -- própria thread: seguro para Citizen.Await
        local ok, err = pcall(handler, src, table.unpack(args))
        if not ok then if vHub and vHub.Logger then vHub.Logger:error("kernel", ("ERRO NET %s → %s"):format(name, tostring(err))) end end
      end)
    end
  end)
end

function K:on(name, fn)
  AddEventHandler(name, function(...) fn(...) end)
end

function K:emit(src, name, ...)  TriggerClientEvent(name, src, ...) end
function K:broadcast(name, ...) TriggerClientEvent(name, -1, ...) end

-- Cross-resource via FiveM low-level export API (no manifest needed)
function K:export(name, fn)
  AddEventHandler("__cfx_export_" .. GetCurrentResourceName() .. "_" .. name,
    function(setCb) setCb(fn) end)
end
function K:call(res, name, ...) return exports[res][name](...) end

-- Permissions
function K:grantPerm(uid, perm)
  if not self._perms[uid] then self._perms[uid] = {} end
  self._perms[uid][perm] = true
end
function K:revokePerm(uid, perm)
  if self._perms[uid] then self._perms[uid][perm] = nil end
end
function K:hasPerm(uid, perm)
  local p = self._perms[uid]
  return p ~= nil and (p[perm] == true or p["admin.*"] == true)
end
function K:clearPerms(uid) self._perms[uid] = nil end

-- O(1) sliding window rate check
function K:_rateOK(src, action, max, win, block)
  local now = GetGameTimer()
  local key = src .. ":" .. action
  local r   = self._rate[key]
  if not r then self._rate[key]={hits=1,window=now,blocked=0}; return true end
  if r.blocked > now then return false end
  if (now - r.window) >= win then r.hits=1; r.window=now; return true end
  r.hits = r.hits + 1
  if r.hits > max then r.blocked=now+(block or win); return false end
  return true
end
