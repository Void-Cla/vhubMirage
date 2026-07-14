-- server/core.lua — fronteiras, autorização, sessões e delegações do vhub_admin
---@diagnostic disable: undefined-global

local SQL = VHubAdmin.SQL
local CFG = VHubAdmin.cfg
local U = VHubAdmin.U
local E = VHubAdmin.E

local M = {}
VHubAdmin.Core = M


-- ============================================================
-- AUTORIZAÇÃO E RATE-LIMIT
-- ============================================================

M._rates = {}

-- Verifica a permissão administrativa sem confiar no cliente.
function M.hasPerm(src, key)
  src = tonumber(src)
  if not src or src < 1 then return false end

  local perm = CFG.perms[key] or key
  local ok, uid = pcall(function() return exports.vhub:getUID(src) end)
  if ok and tonumber(uid) == 1 then return true end

  if IsPlayerAceAllowed then
    if IsPlayerAceAllowed(src, 'vhub.admin.full') then return true end
    local ace = perm:sub(1, 5) == 'vhub.' and perm or ('vhub.' .. perm)
    if IsPlayerAceAllowed(src, ace) then return true end
  end

  local allowed, result = pcall(function()
    return exports.vhub_groups:hasPermission(src, perm)
  end)
  return allowed and result == true
end

-- Aceita uma chamada somente após o intervalo mínimo declarado.
function M:rate(src, key, ms)
  src = tonumber(src)
  if not src then return false end

  local now = GetGameTimer()
  local bySource = self._rates[src] or {}
  local last = bySource[key] or 0
  local interval = tonumber(ms) or CFG.rates[key] or CFG.rates.default
  if now - last < interval then return false end

  bySource[key] = now
  self._rates[src] = bySource
  return true
end

-- Valida origem, permissão e frequência de uma intenção de cliente.
function M:guard(src, perm, rateKey)
  src = tonumber(src)
  if not src or src < 1 or not GetPlayerName(src) then return false end

  if not self.hasPerm(src, perm) then
    self:notify(src, 'Sem permissão para esta ação.', 'negado')
    return false
  end

  if not self:rate(src, rateKey or perm) then return false end
  return true
end


-- ============================================================
-- SESSÕES E CAPACIDADES
-- ============================================================

M.sessions = {}
M.adminIds = {}
M._playersCache = { at = 0, data = nil }

-- Mantém o snapshot de sessão vivo sem criar uma segunda fonte de verdade.
function M:setSession(src, user)
  src = tonumber(src)
  if not src then return end

  self.sessions[src] = user
  if user and self.hasPerm(src, 'panel') then self.adminIds[src] = true
  else self.adminIds[src] = nil end
end

-- Libera dados transitórios do jogador desconectado.
function M:dropSession(src)
  src = tonumber(src)
  if not src then return end

  self.sessions[src] = nil
  self.adminIds[src] = nil
  self._rates[src] = nil
  self._playersCache.data = nil
end

-- Retorna a sessão viva quando existe.
function M:getSession(src)
  return self.sessions[tonumber(src)]
end

-- Retorna o UID da sessão viva.
function M:getUid(src)
  local user = self:getSession(src)
  return user and tonumber(user.id) or nil
end

-- Retorna o personagem da sessão viva.
function M:getCharId(src)
  local user = self:getSession(src)
  return user and tonumber(user.char_id) or nil
end

-- Confirma que um alvo continua conectado e tem personagem carregado.
function M:onlineTarget(raw)
  local src = U.toSrc(raw)
  if not src or not GetPlayerName(src) or not self:getCharId(src) then return nil end
  return src
end

-- Replica somente a capacidade de abrir o painel ao cliente.
function M:syncAdminBag(src)
  src = tonumber(src)
  if not src or not GetPlayerName(src) then return end
  Player(src).state:set('vhub_is_admin', self.hasPerm(src, 'panel'), true)
end

-- Retorna somente as ações que o servidor permite ao administrador atual.
function M:allowedActions(src)
  local out = {}
  for key, action in pairs(VHubAdmin.ACTIONS) do
    if self.hasPerm(src, action.perm) then
      out[key] = {
        cat = action.cat,
        label = action.label,
        desc = action.desc,
        dangerous = action.dangerous == true,
        fields = action.fields,
      }
    end
  end
  return out
end

-- Monta seletores curados sem enviar segredos ou verdade de domínio ao cliente.
function M:selectors()
  local selectors = {
    zones = {},
    weather = {},
    routes = CFG.selectors.money_routes,
    minutes = CFG.selectors.discipline_minutes,
    vehicleStatuses = CFG.selectors.vehicle_statuses,
    groups = {},
  }

  for id, zone in pairs(CFG.teleport_zones) do
    selectors.zones[#selectors.zones + 1] = { value = id, label = zone.label }
  end
  table.sort(selectors.zones, function(a, b) return a.label < b.label end)

  for code, label in pairs(CFG.world.weathers) do
    selectors.weather[#selectors.weather + 1] = { value = code, label = label }
  end
  table.sort(selectors.weather, function(a, b) return a.label < b.label end)

  local ok, groups = pcall(function() return exports.vhub_groups:getCatalog() end)
  if ok and type(groups) == 'table' then
    for _, group in ipairs(groups) do
      if type(group.id) == 'string' then
        selectors.groups[#selectors.groups + 1] = {
          value = group.id,
          label = tostring(group.label or group.id),
          maxLevel = tonumber(group.max_level) or 1,
        }
      end
    end
    table.sort(selectors.groups, function(a, b) return a.label < b.label end)
  end

  return selectors
end


-- ============================================================
-- NOTIFICAÇÃO E AUDITORIA
-- ============================================================

-- Entrega uma notificação pelo canal canônico e pela NUI aberta.
function M:notify(src, message, kind)
  src = tonumber(src)
  if not src or src < 1 then return end

  local text = U.safeText(message, 300)
  TriggerClientEvent('vHub:notify', src, kind or 'info', text)
  TriggerClientEvent(E.NOTIFY, src, text, kind or 'info')
end

-- Registra uma ação administrativa sem fazer Await no handler de rede.
function M:audit(actorSrc, action, targetSrc, payload)
  local actor = actorSrc and self:getSession(actorSrc) or nil
  local row = {
    actor_id = actor and tonumber(actor.id) or nil,
    actor_name = actor and U.safeText(actor.name or GetPlayerName(actorSrc), 64) or 'console',
    action = U.safeText(action, 48),
    target_id = targetSrc and self:getUid(targetSrc) or nil,
    target_src = targetSrc and tonumber(targetSrc) or nil,
    payload = U.jenc(payload or {}),
  }

  Citizen.CreateThread(function()
    SQL:log(row)
  end)

  local webhook = GetConvar('vhub_admin_webhook', '')
  if webhook ~= '' then self:sendWebhook(webhook, row) end
end

-- Envia auditoria resumida ao webhook configurado somente no servidor.
function M:sendWebhook(url, row)
  local body = {
    embeds = { {
      title = ('[ADMIN] %s'):format(row.action),
      description = ('Por **%s** · alvo `%s`\n```%s```'):format(
        row.actor_name or 'console', tostring(row.target_id or '-'), row.payload or '{}'),
      color = 0xF3B53A,
      timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
    } },
  }
  PerformHttpRequest(url, function() end, 'POST', json.encode(body), {
    ['Content-Type'] = 'application/json',
  })
end


-- ============================================================
-- DELEGAÇÕES AOS DONOS
-- ============================================================

local function call(fn)
  local ok, first, second = pcall(fn)
  return ok and first == true, second
end

-- Cura pelo owner de estado do ped.
function M:heal(src)
  local healthOk = call(function() return exports.vhub_player_state:setHealth(src, 200) end)
  local armourOk = call(function() return exports.vhub_player_state:setArmour(src, 100) end)
  return healthOk and armourOk
end

-- Revive pelo owner de estado do ped.
function M:revive(src)
  return call(function() return exports.vhub_player_state:revive(src) end)
end

-- Move pelo owner de posição do ped.
function M:teleport(src, pos)
  if not U.validCoords(pos) then return false end
  return call(function()
    return exports.vhub_player_state:teleport(src, pos.x, pos.y, pos.z, pos.h or pos.heading or 0.0)
  end)
end

-- Credita ou define saldo pelo owner financeiro.
function M:mutateMoney(src, route, amount, setValue, reason)
  if route ~= 'bank' and route ~= 'wallet' then return false, 'rota_inválida' end
  local value = math.floor(tonumber(amount) or 0)
  if value < 0 or value > CFG.limits.money_max then return false, 'valor_inválido' end

  if setValue then
    if route == 'wallet' then
      return call(function() return exports.vhub_money:setWallet(src, value, reason) end)
    end
    return call(function() return exports.vhub_money:setBank(src, value, reason) end)
  end

  if value < 1 then return false, 'valor_inválido' end
  if route == 'wallet' then
    return call(function() return exports.vhub_money:giveWallet(src, value, reason) end)
  end
  return call(function() return exports.vhub_money:giveBank(src, value, reason) end)
end

-- Debita saldo pelo owner financeiro (valor positivo = quanto retirar).
function M:removeMoney(src, route, amount, _reason)
  if route ~= 'bank' and route ~= 'wallet' then return false, 'rota_inválida' end
  local value = math.floor(tonumber(amount) or 0)
  if value < 1 or value > CFG.limits.money_max then return false, 'valor_inválido' end

  if route == 'wallet' then
    return call(function() return exports.vhub_money:removeWallet(src, value, _reason) end)
  end
  return call(function() return exports.vhub_money:removeBank(src, value, _reason) end)
end

-- Entrega item existente pelo owner de inventário.
function M:giveItem(src, item, quantity, reason)
  local id = U.identifier(item, 64)
  local amount = math.floor(tonumber(quantity) or 0)
  if not id or amount < 1 or amount > CFG.limits.item_max then return false end

  local exists, definition = pcall(function() return exports.vhub_inventory:getItemDef(id) end)
  if not exists or type(definition) ~= 'table' then return false end
  return call(function() return exports.vhub_inventory:giveItem(src, id, amount, nil) end)
end

-- Concede grupo validado pelo owner de grupos.
function M:addGroup(src, group, level, days, reason)
  local id = U.identifier(group, 48)
  if not id then return false end

  local ok, catalog = pcall(function() return exports.vhub_groups:getCatalog() end)
  if not ok or type(catalog) ~= 'table' then return false end
  local maxLevel = nil
  for _, entry in ipairs(catalog) do
    if entry.id == id then maxLevel = math.max(1, math.floor(tonumber(entry.max_level) or 1)); break end
  end
  if not maxLevel then return false end

  local lvl = U.number(level, 1, maxLevel)
  local duration = U.number(days, 0, 3650)
  if not lvl or not duration or lvl % 1 ~= 0 or duration % 1 ~= 0 then return false end

  local applied, result = pcall(function()
    return exports.vhub_groups:addGroup(src, id, math.floor(lvl), math.floor(duration), reason)
  end)
  return applied and result == true
end

-- Remove grupo validado pelo owner de grupos.
function M:removeGroup(src, group, reason)
  local id = U.identifier(group, 48)
  if not id then return false end
  local allowed, catalog = pcall(function() return exports.vhub_groups:getCatalog() end)
  if not allowed or type(catalog) ~= 'table' then return false end
  local found = false
  for _, entry in ipairs(catalog) do if entry.id == id then found = true; break end end
  if not found then return false end

  local ok, result = pcall(function() return exports.vhub_groups:removeGroup(src, id, reason) end)
  return ok and result == true
end

-- Retorna a identidade pública de uma sessão conectada.
function M:getIdentity(src)
  local ok, value = pcall(function() return exports.vhub_identity:getIdentity(src) end)
  return ok and value or nil
end

-- Retorna grupos de uma sessão conectada.
function M:getGroups(src)
  local ok, value = pcall(function() return exports.vhub_groups:getGroups(src) end)
  return ok and type(value) == 'table' and value or {}
end

-- Retorna saldos de uma sessão conectada.
function M:getBalances(src)
  local wallet = 0
  local bank = 0
  pcall(function() wallet = tonumber(exports.vhub_money:getWallet(src)) or 0 end)
  pcall(function() bank = tonumber(exports.vhub_money:getBank(src)) or 0 end)
  return wallet, bank
end

-- Retorna posição atual pelo servidor.
function M:coordsOf(src)
  local ped = GetPlayerPed(tostring(src))
  if not ped or ped == 0 then return nil end
  local pos = GetEntityCoords(ped)
  if not pos then return nil end
  return { x = pos.x, y = pos.y, z = pos.z, h = GetEntityHeading(ped) }
end


-- ============================================================
-- LEITURAS PARA O PAINEL
-- ============================================================

-- Itera administradores conectados sem varrer jogadores comuns.
function M:eachAdmin(fn)
  for src in pairs(self.adminIds) do
    if GetPlayerName(src) then fn(src) else self.adminIds[src] = nil end
  end
end

-- Lista jogadores com cache curto para reduzir chamadas cross-resource.
function M:listPlayers()
  local now = GetGameTimer()
  if self._playersCache.data and now - self._playersCache.at < 3000 then
    return self._playersCache.data
  end

  local out = {}
  for _, raw in ipairs(GetPlayers()) do
    local src = tonumber(raw)
    local user = self.sessions[src]
    local tags = {}
    for groupId, group in pairs(self:getGroups(src)) do
      tags[#tags + 1] = type(group) == 'table' and tostring(groupId) or tostring(group)
    end
    table.sort(tags)
    out[#out + 1] = {
      src = src,
      uid = user and tonumber(user.id) or 0,
      char = user and tonumber(user.char_id) or 0,
      name = U.safeText(GetPlayerName(src) or '?', 64),
      ping = math.max(0, tonumber(GetPlayerPing(src)) or 0),
      groups = tags,
    }
    if #out >= (CFG.limits.players or 256) then break end
  end

  table.sort(out, function(a, b) return a.src < b.src end)
  self._playersCache = { at = now, data = out }
  return out
end

-- Monta métricas de painel somente a partir dos donos e do SQL administrativo.
function M:dashboard()
  local reports = SQL:reportCounts()
  local fleet = {}
  pcall(function() fleet = exports.vhub_garage:adminStats() or {} end)

  local staff = {}
  self:eachAdmin(function(src)
    staff[#staff + 1] = { src = src, name = U.safeText(GetPlayerName(src) or '?', 64) }
  end)
  table.sort(staff, function(a, b) return a.name < b.name end)

  -- resumo econômico sobre jogadores online
  local eco = { total = 0, wallet_total = 0, bank_total = 0, counted = 0, top = {} }
  for _, raw in ipairs(GetPlayers()) do
    local src = tonumber(raw)
    local wallet, bank = self:getBalances(src)
    eco.wallet_total = eco.wallet_total + wallet
    eco.bank_total   = eco.bank_total   + bank
    eco.total        = eco.total + wallet + bank
    eco.counted      = eco.counted + 1
    eco.top[#eco.top + 1] = {
      src = src,
      name = U.safeText(GetPlayerName(src) or '?', 48),
      total = wallet + bank,
    }
  end
  table.sort(eco.top, function(a, b) return a.total > b.total end)
  if #eco.top > 10 then eco.top = { table.unpack(eco.top, 1, 10) } end

  return {
    online       = #GetPlayers(),
    max_slots    = tonumber(GetConvar('sv_maxclients', '32')) or 32,
    reports_open = reports.open or 0,
    reports      = reports,
    fleet        = fleet,
    staff        = staff,
    economy      = eco,
    uptime_ms    = GetGameTimer(),
  }
end
