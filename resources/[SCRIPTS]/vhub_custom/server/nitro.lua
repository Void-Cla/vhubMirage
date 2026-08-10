---@diagnostic disable: undefined-global, lowercase-global

-- server/nitro.lua — escritor único de customization.nitro (FASE 2 ADR #81).
--
-- Absorveu vhub_nitro/server.lua. Escritor único de {kit,qty,enabled,level} via conce.
-- Exports gated: getNitro / nitroInstallKit / nitroSetEnabled / nitroSetLevel / nitroChargeFromItem.
-- Eventos legados `vhub_nitro:*` MANTIDOS (vhub_velo e vehcontrol client dependem dos nomes — FASE 6).
-- Doutrina da Placa: estado mora na PLACA, nunca em cache local.

local NCfg = VHubCustom.NitroCfg
local ITEM   = NCfg.item or 'nitro'
local CHARGE = NCfg.chargePerUse or 100

local TRUSTED = { ['vhub_custom'] = true, ['vhub_vehcontrol'] = true }


-- ============================================================
-- HELPERS INTERNOS
-- ============================================================

local function normPlate(p)
  local s = tostring(p or ''):upper():gsub('%s+', ' ')
  return s:match('^%s*(.-)%s*$') or ''
end

local function q100(v) return math.max(0, math.min(100, math.floor(tonumber(v) or 0))) end
local function lvl10(v) return math.max(1, math.min(10, math.floor(tonumber(v) or 1))) end

local function readNitro(plate)
  local st
  pcall(function() st = exports.vhub_conce:getVehicleState(plate) end)
  local cust = (st and type(st.customization) == 'table') and st.customization or {}
  local n    = (type(cust.nitro) == 'table') and cust.nitro or {}
  local ef   = (type(cust.exhaust_fx) == 'table') and cust.exhaust_fx or {}
  local fr, fg, fb = tonumber(ef.r), tonumber(ef.g), tonumber(ef.b)
  return {
    kit     = n.kit == true,
    qty     = q100(n.qty),
    enabled = n.enabled == true,
    level   = lvl10(n.level),
    fire    = (fr and fg and fb) and { r = fr, g = fg, b = fb } or nil,
  }
end

local function writeNitro(plate, kit, qty, enabled, level)
  local patch = { customization = { nitro = {
    kit     = kit == true,
    qty     = q100(qty),
    enabled = enabled == true,
    level   = lvl10(level),
  } } }
  local ok = false
  pcall(function() ok = exports.vhub_conce:saveVehicleState(plate, patch, 'nitro') == true end)
  return ok
end

local function canOperate(src, plate)
  local ok = false
  pcall(function() ok = exports.vhub_conce:canOperate(src, plate) == true end)
  return ok
end

local _opAt = {}
local function rateOK(src)
  local now = GetGameTimer()
  if now - (_opAt[src] or -1000) < 350 then return false end
  _opAt[src] = now
  return true
end

local function resolveDriver(src, netId, plate)
  netId = tonumber(netId); if not (netId and netId > 0) then return nil end
  local p = normPlate(plate); if p == '' then return nil end
  local ent = NetworkGetEntityFromNetworkId(netId)
  if not ent or ent == 0 then return nil end
  if normPlate(GetVehicleNumberPlateText(ent) or '') ~= p then return nil end
  if GetPedInVehicleSeat(ent, -1) ~= GetPlayerPed(src) then return nil end
  return p
end

-- empurra estado fresco ao client após escrita (HUD e gate do boost sincronizam na hora)
local function pushState(src, p)
  if src and tonumber(src) and tonumber(src) > 0 then
    TriggerClientEvent('vhub_nitro:state', src, p, readNitro(p))
  end
end


-- ============================================================
-- EXPORTS PÚBLICOS (gated — default-deny)
-- ============================================================

-- leitura derivada da placa (fonte única, L-04)
exports('getNitro', function(plate)
  local p = normPlate(plate); if p == '' then return nil end
  return readNitro(p)
end)

-- ADR #82 F2.1: catálogo de deltas das peças p/ o derivador do vhub_vehcontrol (Camada A).
-- Fonte única dos deltas = parts_catalog.lua (namespace ISOLADO deste resource). vehcontrol
-- monta sheet.eng a partir disto + customization.parts persistido. Devolve uma CÓPIA ESTÁTICA
-- (nunca a referência mutável de PARTS — L-19: o consumidor não pode envenenar o catálogo).
-- Gated default-deny: só o dono da ficha (vhub_vehcontrol) lê. Catálogo é imutável no boot →
-- construído 1x e cacheado.
local _deltasSnapshot = nil
local function buildDeltasSnapshot()
  if _deltasSnapshot then return _deltasSnapshot end
  local cat = VHubCustom.PartsCatalog
  if not cat or type(cat.PARTS) ~= 'table' then return nil end
  local out = {}
  for _, p in ipairs(cat.PARTS) do
    local deltas = {}
    if type(p.deltas) == 'table' then
      for ax, n in pairs(p.deltas) do deltas[ax] = tonumber(n) or 0 end
    end
    local caps = nil
    if type(p.capabilities) == 'table' then
      caps = {}
      for i, c in ipairs(p.capabilities) do caps[i] = c end
    end
    -- ADR #85 F2.5-B: delta de peso (kg) — alimenta sheet.mass no vehcontrol (derivado, gated ADR #83)
    out[p.id] = { deltas = deltas, mass = tonumber(p.mass) or 0, capabilities = caps }
  end
  _deltasSnapshot = out
  return out
end

exports('getPartsDeltas', function()
  if GetInvokingResource() ~= 'vhub_vehcontrol' then return nil end
  return buildDeltasSnapshot()
end)

-- instala o kit (chamado pela oficina após cobrar + canOperate)
exports('nitroInstallKit', function(src, plate)
  local caller = GetInvokingResource()
  if caller and not TRUSTED[caller] then return false end
  local p = normPlate(plate); if p == '' then return false end
  if not canOperate(src, p) then return false end
  local cur = readNitro(p)
  if cur.kit then return true end
  local ok = writeNitro(p, true, cur.qty, cur.enabled, cur.level)
  if ok then pushState(src, p) end
  return ok
end)

-- liga/desliga (FICHA do vehcontrol); requer kit
exports('nitroSetEnabled', function(src, plate, on)
  local caller = GetInvokingResource()
  if caller and not TRUSTED[caller] then return false end
  if not rateOK(src) then return false end
  local p = normPlate(plate); if p == '' then return false end
  if not canOperate(src, p) then return false end
  local cur = readNitro(p)
  if not cur.kit then return false end
  local ok = writeNitro(p, cur.kit, cur.qty, on == true, cur.level)
  if ok then pushState(src, p) end
  return ok
end)

-- ajusta nível 1..10 (FICHA do vehcontrol); requer kit
exports('nitroSetLevel', function(src, plate, level)
  local caller = GetInvokingResource()
  if caller and not TRUSTED[caller] then return false end
  if not rateOK(src) then return false end
  local p = normPlate(plate); if p == '' then return false end
  if not canOperate(src, p) then return false end
  local cur = readNitro(p)
  if not cur.kit then return false end
  local ok = writeNitro(p, cur.kit, cur.qty, cur.enabled, lvl10(level))
  if ok then pushState(src, p) end
  return ok
end)

-- recarrega consumindo 1 garrafa; estorna em falha de persistência
exports('nitroChargeFromItem', function(src, plate)
  local caller = GetInvokingResource()
  if caller and not TRUSTED[caller] then return false end
  if not rateOK(src) then return false end
  local p = normPlate(plate); if p == '' then return false end
  if not canOperate(src, p) then return false end
  local cur = readNitro(p)
  if not cur.kit then return false end
  if cur.qty >= 100 then return false end

  local took = false
  pcall(function() took = exports.vhub_inventory:takeItem(src, ITEM, 1) == true end)
  if not took then return false end

  if not writeNitro(p, cur.kit, math.min(100, cur.qty + CHARGE), cur.enabled, cur.level) then
    pcall(function() exports.vhub_inventory:giveItem(src, ITEM, 1) end)
    return false
  end
  pushState(src, p)
  return true
end)

-- função interna usada por server/oficina.lua (sem invoke gate — mesmo resource)
function VHubCustom.nitroInstallKitInternal(src, plate)
  local p = normPlate(plate); if p == '' then return false end
  if not canOperate(src, p) then return false end
  local cur = readNitro(p)
  if cur.kit then return true end
  local ok = writeNitro(p, true, cur.qty, cur.enabled, cur.level)
  if ok then pushState(src, p) end
  return ok
end

-- função interna usada por server/core.lua para checar se kit está instalado
function VHubCustom.nitroGetInternal(plate)
  local p = normPlate(plate); if p == '' then return nil end
  return readNitro(p)
end


-- ============================================================
-- ITEM 'nitro' (Garrafa) — avisa que recarga é pela ficha
-- ============================================================

CreateThread(function()
  Wait(500)
  local ok, inv = pcall(function() return exports.vhub_inventory end)
  if not ok or not inv then return end
  pcall(function()
    inv:registerItemUse(ITEM, function(src)
      TriggerClientEvent('vhub_nitro:notify', src,
        'Abasteça o nitro pela ficha do veículo (aba Ficha → Nitro → Abastecer).')
      return false
    end)
  end)
end)


-- ============================================================
-- LEITURA p/ o client (ao virar motorista)
-- ============================================================

RegisterNetEvent('vhub_nitro:request')
AddEventHandler('vhub_nitro:request', function(plate)
  local src = source
  local p = normPlate(plate); if p == '' then return end
  TriggerClientEvent('vhub_nitro:state', src, p, readNitro(p))
end)


-- ============================================================
-- DRAIN (uso do nitro) — qty MONOTÔNICO DECRESCENTE
-- ============================================================

local _drainAt = {}

RegisterNetEvent('vhub_nitro:drain')
AddEventHandler('vhub_nitro:drain', function(netId, plate, reportedQty)
  local src = source
  local now = GetGameTimer()
  if now - (_drainAt[src] or -3000) < 700 then return end
  _drainAt[src] = now

  local p = resolveDriver(src, netId, plate)
  if not p then return end

  local cur = readNitro(p)
  local rq = tonumber(reportedQty); if not rq then return end
  local newQty = math.max(0, math.min(math.floor(rq), cur.qty))
  if newQty >= cur.qty then return end
  writeNitro(p, cur.kit, newQty, cur.enabled, cur.level)

  local spent = cur.qty - newQty
  if spent > 0 then
    pcall(function() exports.vhub_hss:addAdrenaline(src, math.min(spent * 0.6, 30)) end)
  end
end)

AddEventHandler('playerDropped', function()
  _drainAt[source] = nil
  _opAt[source]    = nil
end)
