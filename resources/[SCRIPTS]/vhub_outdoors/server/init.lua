-- server/init.lua - boot, comandos e fronteira de eventos

local CFG = VHubOutdoors.cfg
local E = VHubOutdoors.E
local SQL = VHubOutdoors.SQL
local Core = VHubOutdoors.Core

local function trace(level, message)
  Citizen.Trace(('[vhub_outdoors][%s] %s\n'):format(level, message))
end

local function admin_items()
  local items = Core.list()
  local result = {}
  for _, item in ipairs(items) do
    result[#result + 1] = {
      id = item.id,
      title = item.title,
      media_type = item.media_type,
      size = item.size,
    }
  end
  return result
end

local function create_command(src, args)
  if src == 0 then return end
  if type(args) ~= 'table' or #args < 2 then
    if Core.guard(src, 'open_create_ui') then
      TriggerClientEvent(E.OPEN_CREATE_UI, src, { items = admin_items() })
    end
    return
  end
  local size = args[1]
  local url = args[2]
  local title = #args > 2 and table.concat(args, ' ', 3) or ''
  Core.beginPlacement(src, size, url, title)
end

local function remove_command(src, args)
  if src == 0 or not Core.guard(src, 'remove_command') then return end
  local id = VHubOutdoors.finite(args[1])
  if not id or id % 1 ~= 0 or id < 1 then
    Core.notify(src, 'info', ('Use /%s <id>.'):format(CFG.commands.remove))
    return
  end
  local result = Core.removeCommand(src, id)
  if result.ok then
    Core.notify(src, 'sucesso', ('Outdoor #%d removido.'):format(id))
  else
    Core.notify(src, 'erro', result.err == 'not_found'
      and 'Outdoor ativo nao encontrado.'
      or 'Falha segura ao remover o outdoor.')
  end
end

local function list_command(src)
  if src == 0 or not Core.guard(src, 'list_command') then return end
  local items = Core.list()
  if #items == 0 then
    Core.notify(src, 'info', 'Nenhum outdoor ativo.')
    return
  end

  local chunk = ''
  for _, item in ipairs(items) do
    local preset = item.size and CFG.sizes[item.size] or nil
    local size_label = preset and preset.label or 'personalizado'
    local line = ('#%d | %s | %s | %s\n'):format(
      item.id,
      size_label,
      item.media_type,
      item.title
    )
    if #chunk + #line > 430 then
      Core.notify(src, 'info', chunk)
      chunk = ''
    end
    chunk = chunk .. line
  end
  if chunk ~= '' then Core.notify(src, 'info', chunk) end
end

RegisterCommand(CFG.commands.create, create_command, false)
RegisterCommand(CFG.commands.remove, remove_command, false)
RegisterCommand(CFG.commands.list, list_command, false)

RegisterNetEvent(E.REQUEST_PLACEMENT, function(payload)
  local src = source
  if not Core.rate(src, 'request_placement') or type(payload) ~= 'table' then return end
  for key in pairs(payload) do
    if key ~= 'size' and key ~= 'url' then return end
  end
  if type(payload.size) ~= 'string' or #payload.size > 16
      or type(payload.url) ~= 'string' or #payload.url > CFG.limits.max_url then
    return
  end
  Core.beginPlacement(src, payload.size, payload.url, '')
end)

RegisterNetEvent(E.SUBMIT_PLACEMENT, function(payload)
  Core.commitPlacement(source, payload)
end)

RegisterNetEvent(E.REQUEST_REMOVE, function(payload)
  local src = source
  if not Core.rate(src, 'remove_ui') then return end
  if type(payload) ~= 'table' then return end
  for key in pairs(payload) do
    if key ~= 'id' then return end
  end
  local id = VHubOutdoors.finite(payload.id)
  if not id or id % 1 ~= 0 or id < 1 or id > 2147483647 then return end

  if not Core.ready or not Core.hasPermission(src) then
    Core.notify(src, Core.ready and 'negado' or 'erro',
      Core.ready and 'Sem permissao para gerenciar outdoors.'
        or 'Sistema de outdoors indisponivel.')
    TriggerClientEvent(E.UPDATE_ADMIN, src, {
      ok = false,
      err = 'forbidden',
      items = {},
    })
    return
  end

  local result = Core.removeCommand(src, id)
  if result.ok then
    Core.notify(src, 'sucesso', ('Outdoor #%d removido.'):format(id))
  else
    Core.notify(src, 'erro', result.err == 'not_found'
      and 'Outdoor ativo nao encontrado.'
      or 'Falha segura ao remover o outdoor.')
  end
  TriggerClientEvent(E.UPDATE_ADMIN, src, {
    ok = result.ok == true,
    err = result.err,
    items = admin_items(),
  })
end)

AddEventHandler('playerDropped', function()
  Core.dropSource(source)
end)

AddEventHandler('onResourceStart', function(resource)
  if resource ~= GetCurrentResourceName() then return end
  CreateThread(function()
    local ok, error_message = pcall(function()
      if not SQL.initSchema() then error('schema ausente') end
      SQL.reconcileRemoteGrants()
      SQL.ensureRemoteGrantUniqueness()
      local loaded, load_error = Core.load(
        SQL.listActive(CFG.limits.max_outdoors),
        SQL.revision()
      )
      if not loaded then error(load_error) end
    end)
    if not ok then
      Core.shutdown()
      trace('ERRO', 'Inicializacao recusada: ' .. tostring(error_message))
      return
    end
    trace('INFO', 'Dominio inicializado.')
  end)
end)

AddEventHandler('onResourceStop', function(resource)
  if resource == GetCurrentResourceName() then Core.shutdown() end
end)
