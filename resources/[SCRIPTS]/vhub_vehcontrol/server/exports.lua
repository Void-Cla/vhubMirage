-- server/exports.lua — API READ-ONLY do engine de skill (decisão #27)
--
-- Fonte ÚNICA de tier/score/afinidade derivados para TODOS os consumidores
-- (garage, racha, nitro, UI da chave). Ninguém recalcula por conta própria (L-04).
-- Derivação on-read pura via VHubVeh.TR; persiste-se só o alloc (customization.handling).
---@diagnostic disable: undefined-global, lowercase-global

local TR = VHubVeh.TR


-- ============================================================
-- CATÁLOGO (cache read-only do conce — dono é o conce)
-- ============================================================

-- índice por chave LOWERCASE: o catálogo do conce tem chaves de caixa mista
-- (TOYOTASUPRA, f8t, ...) e o model no DB pode vir em qualquer caixa. Indexamos por
-- lower(spawnName) E lower(displayName) — mesma estratégia do vhub_custom (zero mapa paralelo).
local _index = nil

local function buildIndex()
  if _index then return _index end
  local ok, raw = pcall(function() return exports.vhub_conce:getCatalog() end)
  if not ok or type(raw) ~= 'table' or not next(raw) then return {} end  -- conce ainda carregando
  local idx = {}
  for k, v in pairs(raw) do
    idx[string.lower(k)] = v                                   -- chave 1: spawn name
    local h = GetHashKey(k)
    if h and h ~= 0 then
      local dOk, disp = pcall(GetDisplayNameFromVehicleModel, h)
      if dOk and type(disp) == 'string' and disp ~= '' and disp ~= 'NULL' then
        idx[string.lower(disp)] = v                            -- chave 2: display name
      end
    end
  end
  _index = idx
  return idx
end

-- entrada p1 (identidade física) da placa: resolve model → índice lowercase → .p1
local function p1ByPlate(plate)
  local veh
  pcall(function() veh = exports.vhub_conce:getVehicle(plate) end)
  if not veh or not veh.model then return nil end
  local entry = buildIndex()[string.lower(tostring(veh.model))]
  return entry and entry.p1 or nil
end


-- ============================================================
-- FICHA DERIVADA (composição única reusada por todos os getters)
-- ============================================================

-- monta a ficha derivada da placa, ou nil se o carro não tem p1 (sem skill)
-- dbgSrc (opcional): src do jogador p/ notificação de diagnóstico (Config.skillDebug)
-- overrideAlloc (opcional): usa este alloc no lugar do persistido — ficha HIPOTÉTICA,
-- não lê nem escreve nada além do já necessário; usada só para prévia (nunca persiste)
local function sheetOf(plate, dbgSrc, overrideAlloc)
  local veh
  pcall(function() veh = exports.vhub_conce:getVehicle(plate) end)
  local model = veh and veh.model or nil
  local base  = model and buildIndex()[string.lower(tostring(model))]
  base = base and base.p1 or nil

  if Config and Config.skillDebug and dbgSrc then
    TriggerClientEvent('chat:addMessage', dbgSrc, { args = {
      '^3[vehcontrol]', ('placa=%s model=%s p1=%s'):format(tostring(plate), tostring(model), base and 'SIM' or 'NAO')
    } })
  end
  if not base then return nil end

  local st
  pcall(function() st = exports.vhub_conce:getVehicleState(plate) end)
  local cust  = (st and type(st.customization) == 'table') and st.customization or {}
  local alloc = overrideAlloc or cust.handling

  local sheet = TR.buildSheet(base, cust.mods, cust.turbo, alloc)

  -- nitro derivado da placa (read-only; fonte única = vhub_nitro). A ficha exibe e calibra;
  -- a ESCRITA é delegada aos exports do vhub_nitro (decisão #30). Aditivo: consumidores
  -- antigos da sheet ignoram este campo. defaults seguros vêm do próprio getNitro.
  if sheet then
    local nitro
    pcall(function() nitro = exports.vhub_nitro:getNitro(plate) end)
    sheet.nitro = (type(nitro) == 'table') and nitro or nil
  end

  return sheet
end

-- expõe internamente p/ server/skill.lua reusar (mesma composição, sem duplicar)
VHubVeh.sheetOf  = sheetOf
VHubVeh.p1Byplate = p1ByPlate


-- ============================================================
-- EXPORTS PÚBLICOS (read-only)
-- ============================================================

-- ficha completa (flat, primitivos L-19) — alimenta a UI da chave e consumidores ricos
exports('getVehicleSheet', function(plate)
  return sheetOf(plate)
end)

-- tier atual derivado ('D'..'S+') ou nil se sem p1
exports('getVehicleTier', function(plate)
  local s = sheetOf(plate); return s and s.tier or nil
end)

-- score 0..1000 ou nil
exports('getVehicleScore', function(plate)
  local s = sheetOf(plate); return s and s.score or nil
end)

-- afinidade por pista {reta,curva,montanha,drift,cidade} ou nil
exports('getVehicleAffinity', function(plate)
  local s = sheetOf(plate); return s and s.affinity or nil
end)

-- ficha HIPOTÉTICA com alloc proposto (nunca persiste) — prévia de score/tier para
-- UI de calibração (ex.: oficina) durante o arrasto, antes de confirmar via RECALIBRATE
exports('getVehicleSheetPreview', function(plate, draftAlloc)
  if type(draftAlloc) ~= 'table' then return nil end
  return sheetOf(plate, nil, draftAlloc)
end)


-- ============================================================
-- NET — ficha sob demanda para a UI da chave (read-only)
-- ============================================================

-- cliente pede a ficha derivada de uma placa → devolve flat (ou nil se sem p1)
-- info read-only derivada (mesma que a concessionária exibe) — sem gate de auth
RegisterNetEvent(VHubVeh.E.REQ_SHEET)
AddEventHandler(VHubVeh.E.REQ_SHEET, function(plate)
  local src = source
  local p = plate and tostring(plate):upper():gsub('%s+', ' '):match('^%s*(.-)%s*$') or ''
  if p == '' then return end
  TriggerClientEvent(VHubVeh.E.SHEET, src, sheetOf(p, src))
end)
