---@diagnostic disable: undefined-global, lowercase-global

-- server.lua — nitro server-authoritative (vHub, decisão #30).
--
-- ÚNICO escritor de `customization.nitro = {kit, qty, enabled, level}` — sempre via conce
-- (`saveVehicleState(...,'nitro')`), patch SEMPRE completo (mergeCust do conce é raso: a
-- subtabela `nitro` é REPLACE atômico). Doutrina da Placa: o estado mora na PLACA.
--   - kit     : instalado na OFICINA (export installKit, chamado pelo vhub_custom)
--   - qty     : carga 0..100; sobe via garrafa (chargeFromItem, pela ficha); cai via drain
--   - enabled : nitro ligado? (escolhido na FICHA do vehcontrol via export setEnabled)
--   - level   : 1..10, trade-off durabilidade↔velocidade (FICHA, via export setLevel)
--
-- Terceiros NUNCA escrevem `customization.nitro` direto: chamam os exports TRUSTED daqui.
-- O fluxo antigo de uso por PROXIMIDADE foi APOSENTADO (#30): recarga e calibração na ficha.


-- ============================================================
-- HELPERS
-- ============================================================

local ITEM   = NitroCfg.item or 'nitro'
local CHARGE = NitroCfg.chargePerUse or 100

-- normaliza placa (espelha o conce)
local function normPlate(p)
  local s = tostring(p or ''):upper():gsub('%s+', ' ')
  return s:match('^%s*(.-)%s*$') or ''
end

-- clamp inteiro 0..100
local function q100(v) return math.max(0, math.min(100, math.floor(tonumber(v) or 0))) end

-- clamp inteiro de nível 1..10
local function lvl10(v) return math.max(1, math.min(10, math.floor(tonumber(v) or 1))) end

-- lê o nitro atual da PLACA (derivado do prontuário; defaults seguros — fonte única).
-- SEMPRE devolve os 4 campos: estado antigo {kit,qty} → enabled=false, level=1 (contrato aditivo).
local function readNitro(plate)
  local st
  pcall(function() st = exports.vhub_conce:getVehicleState(plate) end)
  local cust = (st and type(st.customization) == 'table') and st.customization or {}
  local n = (type(cust.nitro) == 'table') and cust.nitro or {}
  return {
    kit     = n.kit == true,
    qty     = q100(n.qty),
    enabled = n.enabled == true,
    level   = lvl10(n.level),
  }
end

-- escreve o nitro na placa (patch SEMPRE completo {kit,qty,enabled,level}; clamp interno; source='nitro')
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

-- autoridade dono/chave (reusa o conce) — prova o PLAYER, não só o resource
local function canOperate(src, plate)
  local ok = false
  pcall(function() ok = exports.vhub_conce:canOperate(src, plate) == true end)
  return ok
end

-- rate-limit por jogador compartilhado pelos exports de escrita (anti-churn/anti-spam).
-- Não é gate de segurança (canOperate é); fecha o resíduo de duplo-clique e poupa SQL.
local _opAt = {}
local function rateOK(src)
  local now = GetGameTimer()
  if now - (_opAt[src] or -1000) < 350 then return false end
  _opAt[src] = now
  return true
end

-- resolve placa quando o player é o MOTORISTA do netId (seat -1) — FAIL-CLOSED.
-- Único uso de netId remanescente: o drain do boost (o motorista gasta a própria carga).
local function resolveDriver(src, netId, plate)
  netId = tonumber(netId); if not (netId and netId > 0) then return nil end
  local p = normPlate(plate); if p == '' then return nil end
  local ent = NetworkGetEntityFromNetworkId(netId)
  if not ent or ent == 0 then return nil end
  if normPlate(GetVehicleNumberPlateText(ent) or '') ~= p then return nil end
  if GetPedInVehicleSeat(ent, -1) ~= GetPlayerPed(src) then return nil end
  return p
end


-- ============================================================
-- EXPORTS (read derivado + escrita DELEGADA: kit/carga/liga/nível)
-- ============================================================

-- só estes resources podem CHAMAR os exports de escrita (export sensível → invoker check)
local TRUSTED = { ['vhub_custom'] = true, ['vhub_vehcontrol'] = true, ['vhub_nitro'] = true }

-- estado do nitro da placa (read-only derivado; fonte única, ninguém recacheia — L-04)
exports('getNitro', function(plate)
  local p = normPlate(plate); if p == '' then return nil end
  return readNitro(p)
end)

-- instala o kit (chamado pela OFICINA após cobrar + canOperate). Restrito + valida de novo.
exports('installKit', function(src, plate)
  local caller = GetInvokingResource()
  if caller and not TRUSTED[caller] then return false end
  local p = normPlate(plate); if p == '' then return false end
  if not canOperate(src, p) then return false end
  local cur = readNitro(p)
  if cur.kit then return true end                                 -- idempotente
  return writeNitro(p, true, cur.qty, cur.enabled, cur.level)     -- liga o kit, preserva o resto
end)

-- liga/desliga o nitro (FICHA do vehcontrol). Gate: precisa de kit. Patch completo.
exports('setEnabled', function(src, plate, on)
  local caller = GetInvokingResource()
  if caller and not TRUSTED[caller] then return false end
  if not rateOK(src) then return false end
  local p = normPlate(plate); if p == '' then return false end
  if not canOperate(src, p) then return false end
  local cur = readNitro(p)
  if not cur.kit then return false end                            -- sem kit não liga
  return writeNitro(p, cur.kit, cur.qty, on == true, cur.level)
end)

-- ajusta o nível 1..10 (FICHA do vehcontrol). Gate: precisa de kit. Clamp server-side.
exports('setLevel', function(src, plate, level)
  local caller = GetInvokingResource()
  if caller and not TRUSTED[caller] then return false end
  if not rateOK(src) then return false end
  local p = normPlate(plate); if p == '' then return false end
  if not canOperate(src, p) then return false end
  local cur = readNitro(p)
  if not cur.kit then return false end
  return writeNitro(p, cur.kit, cur.qty, cur.enabled, lvl10(level))
end)

-- recarrega a carga consumindo 1 garrafa (FICHA do vehcontrol). Ordem anti-perda:
-- takeItem → persist; se persist falhar, estorna o item. Gate: kit + não estar cheio.
exports('chargeFromItem', function(src, plate)
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
    pcall(function() exports.vhub_inventory:giveItem(src, ITEM, 1) end)   -- estorno
    return false
  end
  return true
end)


-- ============================================================
-- ITEM 'nitro' (Garrafa) — usar pela mochila só AVISA (recarga é pela ficha, #30)
-- ============================================================

-- a garrafa não é mais usada por proximidade; abastecer é pela FICHA do veículo.
-- registra um handler que NÃO consome (return false) e orienta o jogador — sem item morto.
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
-- DRAIN (uso do nitro) — qty MONOTÔNICO DECRESCENTE (nunca eleva via drain)
-- ============================================================

local _drainAt = {}

RegisterNetEvent('vhub_nitro:drain')
AddEventHandler('vhub_nitro:drain', function(netId, plate, reportedQty)
  local src = source
  local now = GetGameTimer()
  if now - (_drainAt[src] or -3000) < 700 then return end   -- anti-flood
  _drainAt[src] = now

  local p = resolveDriver(src, netId, plate)   -- só o MOTORISTA drena o próprio carro
  if not p then return end

  local cur = readNitro(p)
  local rq = tonumber(reportedQty); if not rq then return end
  -- MONOTÔNICO: aceita só valor MENOR que o atual (uso gasta; subir só pela garrafa, server-auth)
  local newQty = math.max(0, math.min(math.floor(rq), cur.qty))
  if newQty >= cur.qty then return end
  writeNitro(p, cur.kit, newQty, cur.enabled, cur.level)
end)

AddEventHandler('playerDropped', function()
  _drainAt[source] = nil
  _opAt[source] = nil
end)
