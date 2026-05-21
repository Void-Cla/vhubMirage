-- shared/logger.lua — Logger estruturado, robusto a cfg numérico ou string

vHub = vHub or {}

local LEVELS = { DEBUG=0, INFO=1, WARN=2, ERROR=3 }

local Logger = {}; Logger.__index = Logger

function Logger:_threshold()
  local cfg = type(vHub.cfg) == "table" and vHub.cfg or {}
  local lvl = cfg.log_level
  -- Aceita número (legado do GetConvarInt) ou string
  if type(lvl) == "number" then return lvl end
  return LEVELS[tostring(lvl or "INFO"):upper()] or 1
end

function Logger:log(level, mod, msg, data)
  if (LEVELS[level] or 1) < self:_threshold() then return end
  local line = ("[vHub][%s][%s] %s"):format(
    level, tostring(mod or "core"), tostring(msg))
  if data ~= nil then
    local ok, j = pcall(function() return json.encode(data) end)
    if ok and j then line = line .. " " .. j end
  end
  print(line)
end

function Logger:debug(m,msg,d) self:log("DEBUG",m,msg,d) end
function Logger:info(m,msg,d)  self:log("INFO", m,msg,d) end
function Logger:warn(m,msg,d)  self:log("WARN", m,msg,d) end
function Logger:error(m,msg,d) self:log("ERROR",m,msg,d) end

vHub.Logger = Logger
