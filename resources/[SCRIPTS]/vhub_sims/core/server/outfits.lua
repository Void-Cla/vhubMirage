-- outfits.lua — presets de vestuário e blacklist server-side
---@diagnostic disable: undefined-global

VHubSimsOutfits = VHubSimsOutfits or {}

local Outfits = VHubSimsOutfits
local Core = VHubSimsCore
local SQL = VHubSimsSQL
local Session = VHubSimsSession
local AP = VHubSims.APShape
local E = VHubSims.E
local CFG = VHubSims.cfg


-- ============================================================
-- BLACKLIST
-- ============================================================

local function matches(entry, kind, index, value)
  if type(entry) ~= 'table' or (entry.kind and entry.kind ~= kind)
    or tonumber(entry.index) ~= index then return false end
  if tonumber(entry.drawable) ~= tonumber(value[1] or value.d) then return false end
  return entry.texture == nil or tonumber(entry.texture) == tonumber(value[2] or value.t)
end

-- valida peças restritas por permissão derivada no servidor
function Outfits.isAllowed(src, patch)
  for key, value in pairs(patch or {}) do
    local kind, rawIndex = key:match('^(drawable):(%d+)$')
    if not kind then kind, rawIndex = key:match('^(prop):(%d+)$') end
    local index = tonumber(rawIndex)
    if kind and index and type(value) == 'table' then
      for _, entry in ipairs(VHubSims.blacklist[kind] or {}) do
        if matches(entry, kind, index, value) then
          if type(entry.permission) ~= 'string' then return false end
          local ok, allowed = Core.call('vhub_groups', 'hasPermission', src, entry.permission)
          if not ok or allowed ~= true then return false end
        end
      end
    end
  end
  return true
end


-- ============================================================
-- CRUD
-- ============================================================

local function normalizeLabel(value)
  if type(value) ~= 'string' then return nil end
  value = value:match('^%s*(.-)%s*$'):gsub('[%c]', ''):gsub('%s+', ' '):sub(1, 48)
  return #value >= 2 and value or nil
end

local function publicRows(rows)
  local output = {}
  for _, row in ipairs(rows or {}) do
    output[#output + 1] = {
      id = tonumber(row.id),
      label = tostring(row.label or ''),
      group_name = row.group_name,
    }
  end
  return output
end

local function sendList(src, session)
  local rows = SQL.listOutfits(session.char_id)
  TriggerClientEvent(E.CLI_OUTFITS, src, {
    ok = rows ~= nil,
    items = publicRows(rows),
    session_id = session.session_id,
  })
end

local function validClothesSession(src, session)
  return session and session.mode == 'clothes' and not Session.expired(session)
    and VHubSimsShops and VHubSimsShops.validate(src, session.shop_id, session.mode)
end

-- lista outfits da sessão ativa
function Outfits.list(src, payload)
  if type(payload) ~= 'table' or not Core.rate(src, 'outfit_list') then return false end
  local session = Session.require(src, payload.session_id, 'studio')
  if not validClothesSession(src, session) then return false end
  sendList(src, session)
  return true
end

-- salva vestuário sanitizado como outfit próprio
function Outfits.save(src, payload)
  if type(payload) ~= 'table' or not Core.rate(src, 'outfit_save') then return false end
  local session = Session.require(src, payload.session_id, 'studio')
  if not validClothesSession(src, session) then return false end

  local label = normalizeLabel(payload.label)
  local patch = Core.sanitizePatch(payload.patch, 'clothes')
  if not label or not patch or not Outfits.isAllowed(src, patch) then return false end

  local count = SQL.countOutfits(session.char_id)
  if count == nil or count >= CFG.max_outfits then
    TriggerClientEvent(E.CLI_CHECKOUT_RESULT, src, { ok = false, err = 'outfit_limit' })
    return false
  end

  local outfit = AP.outfitOnly(AP.merge(session.current, patch))
  local encoded = json.encode(outfit)
  if type(encoded) ~= 'string' or #encoded > CFG.max_payload_bytes
    or not SQL.insertOutfit(session.char_id, label, encoded) then
    TriggerClientEvent(E.CLI_CHECKOUT_RESULT, src, { ok = false, err = 'storage' })
    return false
  end

  TriggerClientEvent(E.CLI_CHECKOUT_RESULT, src, { ok = true, outfit_saved = true })
  sendList(src, session)
  return true
end

-- remove outfit pertencente ao personagem
function Outfits.delete(src, payload)
  if type(payload) ~= 'table' or not Core.rate(src, 'outfit_delete') then return false end
  local session = Session.require(src, payload.session_id, 'studio')
  local outfitId = tonumber(payload.outfit_id)
  if not validClothesSession(src, session) or not outfitId or outfitId < 1 then return false end
  if not SQL.deleteOutfit(session.char_id, math.floor(outfitId)) then return false end
  sendList(src, session)
  return true
end

-- aplica outfit pelo pipeline autoritativo de checkout
function Outfits.apply(src, payload)
  if type(payload) ~= 'table' or not Core.rate(src, 'outfit_apply') then return false end
  local session = Session.require(src, payload.session_id, 'studio')
  local outfitId = tonumber(payload.outfit_id)
  if not validClothesSession(src, session) or not outfitId or outfitId < 1 then return false end

  local row = SQL.getOutfit(session.char_id, math.floor(outfitId))
  if not row or type(row.outfit) ~= 'string' then return false end
  local ok, outfit = pcall(json.decode, row.outfit)
  if not ok or type(outfit) ~= 'table' then return false end
  return VHubSimsCreation.checkout(src, payload, outfit)
end


-- ============================================================
-- EVENTOS
-- ============================================================

RegisterNetEvent(E.SRV_OUTFIT_LIST, function(payload) Outfits.list(source, payload) end)
RegisterNetEvent(E.SRV_OUTFIT_SAVE, function(payload) Outfits.save(source, payload) end)
RegisterNetEvent(E.SRV_OUTFIT_DELETE, function(payload) Outfits.delete(source, payload) end)
RegisterNetEvent(E.SRV_OUTFIT_APPLY, function(payload) Outfits.apply(source, payload) end)
