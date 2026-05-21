-- shared/config.lua — Cria vHub global e define configuração
-- PRIMEIRO shared_script a rodar — não pode depender de nada.

-- Cria o namespace global vHub se não existir
if type(rawget(_G, "vHub")) ~= "table" then
  rawset(_G, "vHub", {})
end

local _defaults = {
  log_level           = "INFO",   -- sempre string aqui
  save_interval       = 60,
  max_payload         = 8192,
  modules             = {},
  whitelist_enabled   = false,
  trusted_resources   = {},
  max_ping            = 800,
  ping_check_interval = 30,
  ping_check_enabled  = false,
  fuel_rate           = 0.01,
  max_speed_kmh       = 400,
  veh_state_hz        = 4,
  db                  = {},
  webhooks = { join="", leave="", ban="", security="" },
  lang = {
    not_whitelisted = "Sem whitelist. Seu ID: ",
    banned          = "Você foi banido.",
    duplicate_login = "Você entrou de outro lugar.",
    ping_kick       = "Ping muito alto: %dms.",
  },
}

-- Normaliza log_level: aceita número (legado do GetConvarInt) ou string
local function _normLevel(v)
  if type(v) == "number" then
    return ({[0]="DEBUG",[1]="INFO",[2]="WARN",[3]="ERROR"})[v] or "INFO"
  end
  return tostring(v or "INFO"):upper()
end

function vHub.mergeConfig(user_cfg)
  local merged = user_cfg or {}
  for k, v in pairs(_defaults) do
    if merged[k] == nil then
      if type(v) == "table" then
        local cp = {}
        for ik, iv in pairs(v) do cp[ik] = iv end
        merged[k] = cp
      else
        merged[k] = v
      end
    end
  end
  merged.log_level = _normLevel(merged.log_level)
  return merged
end

function vHub.validateConfig(cfg)
  local errs = {}
  local function chk(f, t)
    if type((cfg or {})[f]) ~= t then
      errs[#errs+1] = ("cfg.%s deve ser %s"):format(f, t)
    end
  end
  chk("log_level","string"); chk("save_interval","number")
  chk("max_payload","number"); chk("whitelist_enabled","boolean")
  return #errs == 0, errs
end

-- Expõe _normLevel para o Logger poder normalizar cfg externo
vHub._normLevel = _normLevel
