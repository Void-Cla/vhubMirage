-- server/init.lua  bootstrap do vhub_garage
-- Ordem de carregamento (fxmanifest):
--   shared/{config,events,types,utils}
--   server/{sql, core, init,
--           garage, dealership, auction, rental,
--           impound, ipva, maintenance, exports}
---@diagnostic disable: undefined-global

local SQL  = VHubGarage.SQL
local Core = VHubGarage.Core
local CFG  = VHubGarage.cfg
local E    = VHubGarage.E
local U    = VHubGarage.U

-- ----------------------------------------------------------------------------
-- Zonas agregadas (decis o #25)
--   concession ria vem do vhub_conce e leil o do vhub_ferinha via PULL no boot
--   (exports getZones, que ja devolvem coord ACHATADA). As zonas PR PRIAS do
--   garage (garagens/p tio) usam vec3 na config e s o achatadas aqui antes de
--   cruzar a fronteira do SETUP — vec n o sobrevive ao msgpack do evento (L-19).
-- ----------------------------------------------------------------------------
VHubGarage.concessionarias = VHubGarage.concessionarias or {}   -- cache do PULL (conce)
VHubGarage.leilao          = VHubGarage.leilao                  -- cache do PULL (ferinha)

-- achata coord vec3 de uma zona p/ primitivo {x,y,z} (preserva os demais campos)
local function flatZone(z)
  if not z then return nil end
  local f = {}
  for k, v in pairs(z) do f[k] = v end
  if z.coord then f.x, f.y, f.z = z.coord.x, z.coord.y, z.coord.z; f.coord = nil end
  return f
end

local function flatZones(list)
  local out = {}
  for i, z in ipairs(list or {}) do out[i] = flatZone(z) end
  return out
end

-- zonas pr prias do garage achatadas 1x no load (config est tica)
VHubGarage.setupGaragens = flatZones(CFG.garagens)
VHubGarage.setupPatio    = flatZone(CFG.patio_local)

-- payload  nico de SETUP (zonas agregadas + cat logo) — usado pelos 2 emissores
local function buildSetup()
  return {
    garagens        = VHubGarage.setupGaragens,
    concessionarias = VHubGarage.concessionarias,
    leilao          = VHubGarage.leilao,
    patio           = VHubGarage.setupPatio,
    catalog         = VHubGarage.catalog,
    types           = VHubGarage.types,
  }
end

-- ----------------------------------------------------------------------------
-- Boot
-- ----------------------------------------------------------------------------
AddEventHandler('onResourceStart', function(res)
  if res ~= GetCurrentResourceName() then return end
  Citizen.CreateThread(function()
    SQL:initSchema()
    -- Backfill da ancora fisica: vhub_vehicles JA existe aqui (initSchema acabou de criar).
    -- O conce sobe ANTES do garage, entao nao consegue popular vh_vehicles no proprio boot;
    -- e o garage que dispara, garantindo a FK que habilita a persistencia fisica em
    -- vh_vehicle_data (fuel/odo/dano). Sem isto a FK rejeita TODA gravacao de estado fisico.
    pcall(function() exports.vhub_conce:backfillMirror() end)
    pcall(function() exports.vhub_conce:backfillOwnerKeys() end)
    -- PRONTU RIO (vhub_vehicle_state): backfill 1x da customization legada +
    -- limpeza de  rf os. S  AQUI (p s-DDL de vhub_vehicles, NUNCA no boot do
    -- conce)  guarda dupla interna impede wipe em DB parcial/restore.
    pcall(function() exports.vhub_conce:backfillVehicleState() end)
    pcall(function() exports.vhub_conce:reconcileVehicleState() end)
    -- Cache read-only do catalogo canonico (dono = vhub_conce desde a FASE 2).
    -- Todos os read-sites de VHubGarage.catalog passam a ler este cache.
    VHubGarage.catalog = exports.vhub_conce:getCatalog() or VHubGarage.catalog

    -- PULL das zonas dos donos de negocio (decisao #25): concessionaria do conce,
    -- leilao do ferinha. Custo UNICO de boot; getZones devolve config estatica ja
    -- ACHATADA (vec nao cruza fronteira). Ambos sao dependencia no manifest; pcall
    -- defensivo p/ que falha de export nao aborte o boot (fallback = sem zona ate restart).
    pcall(function() VHubGarage.concessionarias = exports.vhub_conce:getZones() or {} end)
    pcall(function() VHubGarage.leilao          = exports.vhub_ferinha:getZones() end)

    -- ── Boot-scan do patio (IT.3 / Void-Zero) ───────────────────────────────
    -- Só roda em BOOT REAL do servidor (0 players). Em restart do resource com
    -- players online as entidades ainda existem — recolher seria roubo de carro.
    -- Auditoria por veiculo via Core:log (persistida em vhub_vehicle_log).
    if CFG.patio_boot_scan ~= false and #GetPlayers() == 0 then
      local destino = CFG.patio_boot_destino or 'impound'
      for _, v in ipairs(SQL:listByStatus('out') or {}) do
        if destino == 'garage' then
          SQL:updateStatus(v.plate, 'garage')
        else
          SQL:updateStatus(v.plate, 'impound')
          SQL:impoundPut(v.plate, 'recolhido (queda do servidor)', CFG.patio_taxa or 0, nil)
        end
        Core:log(v.plate, 'boot_scan', nil, { destino = destino })
      end
    end

    print('[vhub_garage] schema verificado')
    -- envia setup a quem est  online (resource restart em produ  o)
    local setup = buildSetup()
    for _, src in ipairs(GetPlayers()) do
      TriggerClientEvent(E.SETUP, tonumber(src), setup)
    end
    print('[vhub_garage] pronto')
  end)
end)

-- ----------------------------------------------------------------------------
-- Sess es (referencia viva do user para todos os m dulos)
-- ----------------------------------------------------------------------------
AddEventHandler('vHub:characterLoad', function(user)
  Core:setSession(user.source, user)
end)

AddEventHandler('vHub:playerSpawn', function(user)
  Core:setSession(user.source, user)
  TriggerClientEvent(E.SETUP, user.source, buildSetup())
end)

AddEventHandler('playerDropped', function()
  Core:dropSession(source)
end)

-- ----------------------------------------------------------------------------
-- Listagens (pedidas pelo cliente ao abrir uma view do NUI)
-- ----------------------------------------------------------------------------
RegisterNetEvent(E.REQ_LIST)
AddEventHandler(E.REQ_LIST, function()
  local src = source
  local cid = Core:getCharId(src); if not cid then return end
  Citizen.CreateThread(function()
    -- FASE 3a (self-heal): todo veiculo que o player POSSUI deve ter sua chave-item
    -- (chave original do dono). Garante que o dono nao some da lista por-chave.
    local owned = SQL:listByOwner(cid) or {}
    for _, v in ipairs(owned) do
      if not Core.hasKeyItem(src, v.plate) then Core.giveKeyItem(src, v.plate) end
    end

    -- FASE 3c: lista POR CHAVE-ITEM no inventario (nao julga dono char_id).
    -- Quem tem a chave ve/opera; quem nao tem, nao ve. O cron 24h devolve posse temporaria.
    local plates = exports.vhub_inventory:getVehicleKeys(src) or {}
    local seen, snaps = {}, {}
    for _, plate in ipairs(plates) do
      local p = U.normalizePlate(plate)
      if p and not seen[p] then
        seen[p] = true
        local v = SQL:getVehicle(p)
        if v then
          local snap = Core:vehicleSnapshot(v)
          snap.role = (v.char_id == cid) and 'owner' or 'key'   -- dono real x portador de chave
          snaps[#snaps+1] = snap
        end
      end
    end
    TriggerClientEvent(E.OPEN_UI, src, {
      view = VHubGarage.UI.OPEN_GARAGE,
      payload = { vehicles = snaps, types = VHubGarage.types.list },
    })
  end)
end)

RegisterNetEvent(E.REQ_CATALOG)
AddEventHandler(E.REQ_CATALOG, function(conc_id)
  local src  = source
  local conc = Core:resolveConc(conc_id)   -- decisao #25: config mora no vhub_conce
  if not conc then return end
  Citizen.CreateThread(function()
    -- monta cat logo aplicando estoque + custom_price
    local out = {}
    for model, entry in pairs(VHubGarage.catalog) do
      local match_tipo = false
      for _, t in ipairs(conc.tipos) do
        if t == entry.tipo then match_tipo = true; break end
      end
      if match_tipo then
        local stock = SQL:stockGet(model)
        local qty   = stock and stock.qty or -1
        local preco = (stock and stock.custom_price) or entry.preco
        if qty ~= 0 then
          out[#out+1] = {
            model = model, nome = entry.nome, preco = preco,
            tipo = entry.tipo, categoria = entry.categoria,
            stats = entry.stats, tags = entry.tags or {},
            estoque = qty,
          }
        end
      end
    end
    table.sort(out, function(a, b) return a.preco < b.preco end)
    TriggerClientEvent(E.OPEN_UI, src, {
      view = VHubGarage.UI.OPEN_DEALERSHIP,
      payload = {
        -- so id+label vao p/ a NUI (decisao #25 / L-19): nenhuma coord/vetor cru
        -- pode cair no SendNUIMessage (json.encode de vec vira {}).
        conc = { id = conc.id, label = conc.label }, catalog = out,
        cfg = {
          taxa_placa = CFG.taxa_placa_custom,
          fator_revenda = CFG.fator_revenda_loja,
          fator_test = CFG.fator_test_drive,
          test_seg = CFG.test_drive_segundos,
          fator_aluguel = CFG.fator_aluguel,
          aluguel_h = CFG.aluguel_periodo_h,
        },
      },
    })
  end)
end)

-- A limpeza/devolução de chaves expiradas agora é do cron de vhub_conce (FASE 3b):
-- conce:returnExpiredHoldings() revoga a linha + tira a chave-item + devolve o carro.
