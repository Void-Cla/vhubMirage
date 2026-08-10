-- server/engine_bay.lua — LEITURA contextual do compartimento do motor (ADR #82 F2.2)
--
-- Imersão do fluxo capô→engine bay: quando o jogador abre o capô e escolhe "Inspecionar Motor",
-- o cliente pede este resumo. É LEITURA pura, mas GATED pelo MESMO gate físico do serviço
-- (Core.validateVehicle): precisa estar a pé, perto da zona/carro, mesmo bucket, carro parado,
-- dono (canOperate). Não confia no cliente nem para LER — devolve só um subset read-only.
--
-- Zero-trust (gate seguranca F2.2): rate-limit ANTES do gate (anti-enumeração como oráculo de
-- presença), resposta UNICAST ao src (nunca -1, R5), e nenhum campo além de eng/parts derivados.
---@diagnostic disable: undefined-global

local Core = VHubCustom.Core
local E    = VHubCustom.E


-- ============================================================
-- HELPERS
-- ============================================================

-- resumo read-only das peças instaladas (nome + família) resolvidas contra o catálogo.
-- Lê customization.parts (mapa esparso; valor falsy = removido → ignora, espelha o derivador).
local function installedPartsSummary(customization)
  local out = {}
  local cat = VHubCustom.PartsCatalog
  local parts = (type(customization) == 'table' and type(customization.parts) == 'table')
    and customization.parts or {}
  if not cat then return out end
  for id, v in pairs(parts) do
    if v ~= nil and v ~= false then
      local def = cat.get(id)
      if def then
        out[#out + 1] = { id = id, name = def.name, family = def.family }
      end
    end
  end
  return out
end


-- ============================================================
-- HANDLER (read gated)
-- ============================================================

-- inspeciona o motor de um veículo próximo — devolve engenharia derivada (read-only, gated)
RegisterNetEvent(E.ENGINE_BAY_INSPECT)
AddEventHandler(E.ENGINE_BAY_INSPECT, function(zoneId, plate, netId)
  local src = source
  local function reply(ok, summary)
    TriggerClientEvent(E.ENGINE_BAY_INSPECT_OK, src, ok == true, summary)
  end

  -- rate-limit ANTES do gate: impede usar o OK/erro como oráculo de presença veicular (anti-spam)
  if not Core.rateOK(src, 'engine_bay_inspect') then return reply(false) end

  -- MESMO gate físico do serviço (recomputa distância/bucket/velocidade/placa/dono/status server-side)
  local context = Core.validateVehicle(src, 'oficina', plate, netId, zoneId)
  if not context then return reply(false) end

  -- ficha derivada read-only (fonte única = vhub_vehcontrol). Só o subset de engenharia cruza.
  local sheet
  pcall(function() sheet = exports.vhub_vehcontrol:getVehicleSheet(context.plate) end)
  local eng = (type(sheet) == 'table' and type(sheet.eng) == 'table') and sheet.eng or nil

  local st = Core.getVehicleState(context.plate)
  local customization = st and type(st.customization) == 'table' and st.customization or nil

  reply(true, {
    plate = context.plate,
    name  = Core.vehicleMeta(context.vehicle).name,
    -- efeito físico derivado da Camada A (0 quando applyPerEntity off / sem peça) — read-only
    power_boost   = eng and eng.power_boost or 0.0,
    top_speed_pct = eng and eng.top_speed_pct or 0.0,
    parts = installedPartsSummary(customization),
  })
end)
