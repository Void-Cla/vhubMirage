-- exports.lua — contratos públicos default-deny do SIMS
---@diagnostic disable: undefined-global

local Creation = VHubSimsCreation
local trusted = VHubSims.cfg.trusted

local function allowed(contract)
  local caller = GetInvokingResource()
  return type(caller) == 'string' and caller ~= '' and trusted[contract][caller] == true
end

-- informa ao login se o personagem atual exige criação
exports('needsCreation', function(src)
  if not allowed('needs_creation') then return { ok = false, err = 'forbidden' } end
  return Creation.needsCreation(tonumber(src))
end)

-- inicia criação idempotente a pedido exclusivo do login
exports('beginCreation', function(src, requestId)
  if not allowed('begin_creation') then return { ok = false, err = 'forbidden' } end
  return Creation.beginCreation(tonumber(src), requestId)
end)
