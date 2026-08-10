-- server/exports.lua - API publica default-deny do dominio

local CFG = VHubOutdoors.cfg
local Core = VHubOutdoors.Core

local function trusted_caller()
  local caller = GetInvokingResource()
  return type(caller) == 'string'
    and CFG.trusted_resources[caller] == true
    and caller
    or nil
end

-- Cria outdoor validado para um administrador online.
exports('CreateOutdoor', function(actor_src, data)
  local caller = trusted_caller()
  if not caller then return { ok = false, err = 'forbidden' } end
  if not Core.ready then return { ok = false, err = 'not_ready' } end
  return Core.createDirect(tonumber(actor_src), data, caller)
end)

-- Remove outdoor validado para um administrador online.
exports('RemoveOutdoor', function(actor_src, id, operation_id, reason)
  local caller = trusted_caller()
  if not caller
      or not VHubOutdoors.validOperationId(operation_id, 64) then
    return { ok = false, err = 'forbidden' }
  end
  if not Core.ready then return { ok = false, err = 'not_ready' } end
  if not Core.guard(actor_src, 'export_remove') then
    return { ok = false, err = 'forbidden' }
  end
  return Core.remove(
    tonumber(actor_src),
    id,
    caller .. ':' .. operation_id,
    reason or ('Remocao pelo resource %s'):format(caller)
  )
end)

-- Retorna copia dos outdoors ativos apenas a resources autorizados.
exports('ListOutdoors', function()
  if not trusted_caller() then return { ok = false, err = 'forbidden' } end
  if not Core.ready then return { ok = false, err = 'not_ready' } end
  return { ok = true, revision = Core.revision, items = Core.list() }
end)
