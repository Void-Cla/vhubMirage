-- server/reports.lua  tickets: jogador   admin
-- Jogador comum: /report <msg>
-- Admin: /reports (lista), claim, close.
---@diagnostic disable: undefined-global

local SQL  = VHubAdmin.SQL
local Core = VHubAdmin.Core
local CFG  = VHubAdmin.cfg
local E    = VHubAdmin.E
local U    = VHubAdmin.U

-- ----------------------------------------------------------------------------
-- /report  qualquer jogador
-- ----------------------------------------------------------------------------
RegisterCommand('report', function(src, args)
  src = tonumber(src); if not src or src == 0 then return end
  local msg = U.safeText(table.concat(args, ' '), CFG.limits.report_chars)
  if msg == '' then Core.notify(src, 'Uso: /report <mensagem>'); return end
  Citizen.CreateThread(function()
    local cid = Core:getCharId(src); if not cid then return end
    local last = SQL:reportLastByReporter(cid)
    if os.time() - last < CFG.limits.report_cd_secs then
      Core.notify(src, 'Aguarde antes de enviar outro report.'); return
    end
    local id = SQL:reportCreate(cid, src, msg)
    Core.notify(src, ('Report #%s enviado. Aguarde um admin.'):format(id))
    -- notifica admins online
    Core:eachAdmin(function(s)
      Core.notify(s, ('   Report #%s de [%d]: %s'):format(id, src, msg))
    end)
    Core:audit(nil, 'report_create', src, { id = id, message = msg })
  end)
end, false)

-- ----------------------------------------------------------------------------
-- Admin: listar
-- ----------------------------------------------------------------------------
RegisterNetEvent(E.REQ_REPORTS)
AddEventHandler(E.REQ_REPORTS, function()
  local src = source
  if not Core.hasPerm(src, 'reports') then return end
  Citizen.CreateThread(function()
    local rows = SQL:reportList(nil) or {}
    TriggerClientEvent(E.REPORT_LIST, src, rows)
  end)
end)

RegisterNetEvent(E.ACT_REPORT_CLAIM)
AddEventHandler(E.ACT_REPORT_CLAIM, function(id)
  local src = source
  if not Core.hasPerm(src, 'reports') then return end
  local rid = tonumber(id); if not rid then return end
  Citizen.CreateThread(function()
    SQL:reportClaim(rid, Core:getUid(src))
    Core.notify(src, ('Report #%s reivindicado.'):format(rid))
    Core:audit(src, 'report_claim', nil, { id = rid })
  end)
end)

RegisterNetEvent(E.ACT_REPORT_CLOSE)
AddEventHandler(E.ACT_REPORT_CLOSE, function(id, notes)
  local src = source
  if not Core.hasPerm(src, 'reports') then return end
  local rid = tonumber(id); if not rid then return end
  notes = U.safeText(notes, 220)
  Citizen.CreateThread(function()
    SQL:reportClose(rid, Core:getUid(src), notes)
    Core.notify(src, ('Report #%s fechado.'):format(rid))
    Core:audit(src, 'report_close', nil, { id = rid, notes = notes })
  end)
end)

-- ----------------------------------------------------------------------------
-- ACT_REPORT  via NUI tamb m
-- ----------------------------------------------------------------------------
RegisterNetEvent(E.ACT_REPORT)
AddEventHandler(E.ACT_REPORT, function(message)
  local src = source
  local msg = U.safeText(message, CFG.limits.report_chars)
  if msg == '' then return end
  Citizen.CreateThread(function()
    local cid = Core:getCharId(src); if not cid then return end
    local last = SQL:reportLastByReporter(cid)
    if os.time() - last < CFG.limits.report_cd_secs then
      Core.notify(src, 'Aguarde antes de enviar outro report.'); return
    end
    local id = SQL:reportCreate(cid, src, msg)
    Core.notify(src, ('Report #%s enviado.'):format(id))
    Core:eachAdmin(function(s)
      Core.notify(s, ('   Report #%s de [%d]: %s'):format(id, src, msg))
    end)
  end)
end)
