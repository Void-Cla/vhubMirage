-- server/reports.lua - tickets persistentes e concorrencia controlada
---@diagnostic disable: undefined-global

local SQL = VHubAdmin.SQL
local Core = VHubAdmin.Core
local CFG = VHubAdmin.cfg
local E = VHubAdmin.E
local U = VHubAdmin.U

local reportStates = { open = true, claimed = true, closed = true }

local function affected(result)
  if type(result) == 'table' then return tonumber(result.affectedRows or result.affected_rows) or 0 end
  return tonumber(result) or 0
end

-- Cria um ticket com rate local e verificacao persistente apos restart.
local function submit(src, rawMessage)
  local message = U.safeText(rawMessage, CFG.limits.report_chars)
  if message == '' then return Core:notify(src, 'Mensagem do report vazia.', 'erro') end
  if not Core:rate(src, 'report', CFG.rates.report) then
    return Core:notify(src, 'Aguarde antes de enviar outro report.', 'info')
  end

  Citizen.CreateThread(function()
    local charId = Core:getCharId(src)
    if not charId or not GetPlayerName(src) then return end
    if os.time() - SQL:reportLastByReporter(charId) < CFG.limits.report_cd_secs then
      return Core:notify(src, 'Aguarde antes de enviar outro report.', 'info')
    end

    local id = SQL:reportCreate(charId, src, message)
    if not id then return Core:notify(src, 'Falha ao registrar report.', 'erro') end

    Core:notify(src, ('Report #%d enviado.'):format(id), 'sucesso')
    Core:eachAdmin(function(adminSrc)
      Core:notify(adminSrc, ('Report #%d de [%d]: %s'):format(id, src, message), 'info')
    end)
    Core:audit(src, 'report_create', nil, { id = id, message = message })
  end)
end

RegisterCommand('report', function(src, args)
  src = tonumber(src)
  if not src or src < 1 then return end
  submit(src, table.concat(args, ' '))
end, false)

RegisterNetEvent(E.ACT_REPORT)
AddEventHandler(E.ACT_REPORT, function(message)
  submit(source, message)
end)


-- ============================================================
-- CONSULTAS ADMINISTRATIVAS
-- ============================================================

RegisterNetEvent(E.REQ_REPORTS)
AddEventHandler(E.REQ_REPORTS, function(rawStatus)
  local src = source
  if not Core:guard(src, 'reports', 'reports') then return end

  local status = nil
  if rawStatus ~= nil then
    status = U.identifier(rawStatus, 16)
    if not status or not reportStates[status] then return Core:notify(src, 'Filtro invalido.', 'erro') end
  end

  Citizen.CreateThread(function()
    local rows = SQL:reportList(status) or {}
    TriggerClientEvent(E.REPORT_LIST, src, rows)
  end)
end)

RegisterNetEvent(E.ACT_REPORT_CLAIM)
AddEventHandler(E.ACT_REPORT_CLAIM, function(rawId)
  local src = source
  if not Core:guard(src, 'reports', 'reports') then return end

  local id = U.number(rawId, 1, 2147483647)
  local adminId = Core:getUid(src)
  if not id or id % 1 ~= 0 or not adminId then return Core:notify(src, 'Report invalido.', 'erro') end

  Citizen.CreateThread(function()
    if affected(SQL:reportClaim(math.floor(id), adminId)) < 1 then
      return Core:notify(src, 'Report indisponivel para reivindicacao.', 'erro')
    end
    Core:notify(src, ('Report #%d reivindicado.'):format(id), 'sucesso')
    Core:audit(src, 'report_claim', nil, { id = id })
  end)
end)

RegisterNetEvent(E.ACT_REPORT_CLOSE)
AddEventHandler(E.ACT_REPORT_CLOSE, function(rawId, rawNotes)
  local src = source
  if not Core:guard(src, 'reports', 'reports') then return end

  local id = U.number(rawId, 1, 2147483647)
  local adminId = Core:getUid(src)
  local notes = U.safeText(rawNotes, 220)
  if not id or id % 1 ~= 0 or not adminId then return Core:notify(src, 'Report invalido.', 'erro') end

  Citizen.CreateThread(function()
    if affected(SQL:reportClose(math.floor(id), adminId, notes)) < 1 then
      return Core:notify(src, 'Report ja estava fechado ou nao existe.', 'erro')
    end
    Core:notify(src, ('Report #%d fechado.'):format(id), 'sucesso')
    Core:audit(src, 'report_close', nil, { id = id, notes = notes })
  end)
end)
