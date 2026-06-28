-- client/bennys.lua — L2 HAL: preview cosmético efêmero, câmera orbital, anti-fantasma e rollback
--
-- PRINCÍPIOS:
--   * Preview é EFÊMERO (L-02): aplica nativos no veículo local, sem custo nem persistência.
--   * Anti-fantasma (GetNumVehicleMods): a NUI só renderiza/seleciona o que o carro REALMENTE
--     possui — a disponibilidade é enumerada aqui (server-truth é a placa; aqui é a entidade).
--   * Neon: índices SEMPRE explícitos 0..3 (0=esq,1=dir,2=frente,3=trás). Nunca iteramos um
--     array vindo do JSON (que chega 1-indexado e pulava o índice 0 = ESQUERDO → "só 3 lados").
--   * Cor: pintura RGB exata via SetVehicleCustom*Colour (não paleta de índices arcaica).
--   * Rollback (L-03): re-aplica o snapshot do estado anterior em qualquer falha.
---@diagnostic disable: undefined-global

local CFG = VHubCustom.cfg
local E   = VHubCustom.E
local Cam = VHubCustom.Cam

-- snapshot do estado cosmético antes do preview (para rollback)
local _snapshot = nil


-- ============================================================
-- TIPOS DE KIT COSMÉTICO ENUMERÁVEIS (índice GTA → nome PT-BR)
-- a disponibilidade real é resolvida por GetNumVehicleMods no carro
-- ============================================================

local KIT_TYPES = {
  { idx = 0,  name = 'Aerofólio',          part = 'traseira' },
  { idx = 1,  name = 'Para-choque dianteiro', part = 'frente' },
  { idx = 2,  name = 'Para-choque traseiro',  part = 'traseira' },
  { idx = 3,  name = 'Saias laterais',     part = 'lateral'  },
  { idx = 4,  name = 'Escapamento',        part = 'traseira' },
  { idx = 5,  name = 'Estrutura/Rollcage', part = 'lateral'  },
  { idx = 6,  name = 'Grade',              part = 'frente'   },
  { idx = 7,  name = 'Capô',               part = 'frente'   },
  { idx = 8,  name = 'Paralama esquerdo',  part = 'lateral'  },
  { idx = 9,  name = 'Paralama direito',   part = 'lateral'  },
  { idx = 10, name = 'Teto',               part = 'teto'     },
  { idx = 23, name = 'Rodas',              part = 'roda'     },
  { idx = 27, name = 'Acabamento',         part = 'lateral'  },
  { idx = 28, name = 'Ornamentos',         part = 'frente'   },
  { idx = 30, name = 'Painel',             part = 'lateral'  },
  { idx = 33, name = 'Volante',            part = 'lateral'  },
  { idx = 34, name = 'Câmbio',             part = 'lateral'  },
  { idx = 35, name = 'Placa decorativa',   part = 'traseira' },
  -- livery NÃO entra aqui: usa o sistema SetVehicleLivery na aba "Detalhes"
  -- (mod 48 é um 2º sistema de adesivo que duplicaria a UI)
}


-- ============================================================
-- ENUMERAÇÃO ANTI-FANTASMA (GetNumVehicleMods)
-- ============================================================

-- retorna { kits={[idx]=count}, liveryCount=n, wheelMods=n } só com o que existe
local function enumerateAvailable(veh)
  local avail = { kits = {}, liveryCount = -1, wheelMods = 0 }
  for _, k in ipairs(KIT_TYPES) do
    local n = GetNumVehicleMods(veh, k.idx)
    if n and n > 0 then avail.kits[tostring(k.idx)] = n end
  end
  avail.wheelMods  = GetNumVehicleMods(veh, 23) or 0
  avail.liveryCount = GetVehicleLiveryCount(veh) or -1
  return avail
end

-- mapa idx(string) → parte de câmera, para focar a peça ao abrir a categoria de kit
local _kitPart = {}
for _, k in ipairs(KIT_TYPES) do _kitPart[tostring(k.idx)] = k.part end


-- ============================================================
-- SNAPSHOT DO ESTADO COSMÉTICO (rollback + estado inicial da NUI)
-- ============================================================

-- captura tudo que é cosmético, incluindo pintura RGB custom (anti des-sync)
local function snapshotVeh(veh)
  if not DoesEntityExist(veh) or veh == 0 then return {} end

  local mods = {}
  for _, k in ipairs(KIT_TYPES) do mods[k.idx] = GetVehicleMod(veh, k.idx) end

  local p, s         = GetVehicleColours(veh)
  local pearl, wheel = GetVehicleExtraColours(veh)

  local neons = {}
  for i = 0, 3 do neons[i] = IsVehicleNeonLightEnabled(veh, i) end
  local nr, ng, nb = GetVehicleNeonLightsColour(veh)
  local sr, sg, sb = GetVehicleTyreSmokeColor(veh)

  -- pintura custom (RGB exato) — só relevante quando o flag custom está ligado
  local primCustom = GetIsVehiclePrimaryColourCustom(veh)
  local secCustom  = GetIsVehicleSecondaryColourCustom(veh)
  local cpr, cpg, cpb, csr, csg, csb
  if primCustom then cpr, cpg, cpb = GetVehicleCustomPrimaryColour(veh) end
  if secCustom  then csr, csg, csb = GetVehicleCustomSecondaryColour(veh) end

  -- xenon (índice 0..12) lido de forma defensiva
  local xenonIdx = 0
  pcall(function() xenonIdx = GetVehicleXenonLightsColor(veh) or 0 end)

  return {
    mods          = mods,
    colours       = { p, s },
    extra_colours = { pearl, wheel },
    custom_primary   = primCustom and { cpr, cpg, cpb } or nil,
    custom_secondary = secCustom  and { csr, csg, csb } or nil,
    neons         = neons,
    neon_colour   = { nr, ng, nb },
    tyre_smoke_color = { sr, sg, sb },
    window_tint   = GetVehicleWindowTint(veh),
    wheel_type    = GetVehicleWheelType(veh),
    livery        = GetVehicleLivery(veh),
    plate_index   = GetVehicleNumberPlateTextIndex(veh),
    smoke         = IsToggleModOn(veh, 20),
    xenon         = IsToggleModOn(veh, 22),
    xenon_color   = xenonIdx,
    -- turbo (18) NÃO é coletado: chave EXCLUSIVA da oficina (performance)
  }
end


-- ============================================================
-- APLICAÇÃO COSMÉTICA (preview, confirmação e rollback — tolerante a patch parcial)
-- ============================================================

-- detecta o layout do array de neon UMA vez e devolve um leitor por índice 0..3.
-- snapshot/servidor chegam 0-indexados ([0]); array JSON da NUI chega 1-indexado ([1]).
-- detectar por elemento quebraria (neons[1] existe nos DOIS layouts com sentidos diferentes).
local function neonReader(neons)
  local zeroBased = (neons[0] ~= nil) or (neons['0'] ~= nil)
  return function(i)
    local key = zeroBased and i or (i + 1)
    local on = neons[key]
    if on == nil then on = neons[tostring(key)] end
    return on == true
  end
end

-- aplica um patch cosmético no veículo vivo. SÓ toca chaves presentes (patch parcial seguro).
function VHubCustom.applyCosmetic(veh, c)
  if not DoesEntityExist(veh) or veh == 0 or type(c) ~= 'table' then return end
  SetVehicleModKit(veh, 0)

  -- pintura: índice como base, custom RGB sobrepõe (ordem importa)
  if c.colours then
    SetVehicleColours(veh, tonumber(c.colours[1] or c.colours['1']) or 0,
                            tonumber(c.colours[2] or c.colours['2']) or 0)
  end
  if c.extra_colours then
    SetVehicleExtraColours(veh, tonumber(c.extra_colours[1] or c.extra_colours['1']) or 0,
                                tonumber(c.extra_colours[2] or c.extra_colours['2']) or 0)
  end
  if type(c.custom_primary) == 'table' then
    SetVehicleCustomPrimaryColour(veh, tonumber(c.custom_primary[1] or c.custom_primary['1']) or 255,
                                       tonumber(c.custom_primary[2] or c.custom_primary['2']) or 255,
                                       tonumber(c.custom_primary[3] or c.custom_primary['3']) or 255)
  end
  if type(c.custom_secondary) == 'table' then
    SetVehicleCustomSecondaryColour(veh, tonumber(c.custom_secondary[1] or c.custom_secondary['1']) or 255,
                                         tonumber(c.custom_secondary[2] or c.custom_secondary['2']) or 255,
                                         tonumber(c.custom_secondary[3] or c.custom_secondary['3']) or 255)
  end

  -- NEON — FIX: sempre 0..3 explícito; índice 0 (ESQUERDO) nunca é pulado
  if type(c.neons) == 'table' then
    local read = neonReader(c.neons)
    for i = 0, 3 do SetVehicleNeonLightEnabled(veh, i, read(i)) end
  end
  if type(c.neon_colour) == 'table' then
    SetVehicleNeonLightsColour(veh, tonumber(c.neon_colour[1] or c.neon_colour['1']) or 255,
                                    tonumber(c.neon_colour[2] or c.neon_colour['2']) or 255,
                                    tonumber(c.neon_colour[3] or c.neon_colour['3']) or 255)
  end

  -- fumaça de pneu: toggle + cor RGB (cor só aparece com o toggle ligado)
  if c.smoke ~= nil then ToggleVehicleMod(veh, 20, c.smoke == true) end
  if type(c.tyre_smoke_color) == 'table' then
    SetVehicleTyreSmokeColor(veh, tonumber(c.tyre_smoke_color[1] or c.tyre_smoke_color['1']) or 255,
                                  tonumber(c.tyre_smoke_color[2] or c.tyre_smoke_color['2']) or 255,
                                  tonumber(c.tyre_smoke_color[3] or c.tyre_smoke_color['3']) or 255)
  end

  -- xenon: toggle + cor por índice (0..12)
  if c.xenon ~= nil then ToggleVehicleMod(veh, 22, c.xenon == true) end
  if c.xenon_color ~= nil then
    pcall(SetVehicleXenonLightsColor, veh, tonumber(c.xenon_color) or 0)
  end

  if c.window_tint ~= nil then SetVehicleWindowTint(veh, tonumber(c.window_tint) or 0) end
  if c.wheel_type  ~= nil then SetVehicleWheelType(veh, tonumber(c.wheel_type) or 0) end
  if c.livery      ~= nil then SetVehicleLivery(veh, tonumber(c.livery) or -1) end

  -- kits cosméticos (nunca performance — defesa em profundidade)
  if type(c.mods) == 'table' then
    for k, lvl in pairs(c.mods) do
      local idx = tonumber(k)
      if idx and not CFG.performance_mods[idx] then
        SetVehicleMod(veh, idx, tonumber(lvl) or -1, false)
      end
    end
  end
end


-- ============================================================
-- SNAPSHOT → ESTADO PLANO PARA A NUI (refletir realidade, sem fantasma)
-- ============================================================

-- converte o snapshot em dict plano que a NUI usa para iniciar a seleção
local function snapshotToCurrent(snap)
  local mods = {}
  for idx, lvl in pairs(snap.mods or {}) do mods[tostring(idx)] = lvl end
  local neons = {}
  for i = 0, 3 do neons[i + 1] = (snap.neons or {})[i] == true end  -- array p/ JSON
  return {
    colours          = snap.colours,
    custom_primary   = snap.custom_primary,
    custom_secondary = snap.custom_secondary,
    extra_on         = snap.extra_colours ~= nil,
    neons            = neons,
    neon_colour      = snap.neon_colour,
    smoke            = snap.smoke == true,
    tyre_smoke_color = snap.tyre_smoke_color,
    xenon            = snap.xenon == true,
    xenon_color      = snap.xenon_color,
    window_tint      = snap.window_tint,
    wheel_type       = snap.wheel_type,
    livery           = snap.livery,
    plate_index      = snap.plate_index,
    mods             = mods,
  }
end


-- ============================================================
-- HELPERS
-- ============================================================

-- normalização compatível com conce (mesma chave de placa)
local function plateOf(veh)
  return (GetVehicleNumberPlateText(veh) or ''):upper():gsub('%s+', ' '):match('^%s*(.-)%s*$')
end

-- converte tabela indexada por número em dict string-keyed (msgpack/JSON-safe p/ NUI)
local function priceDict(tbl)
  local out = {}
  if type(tbl) == 'table' then
    for k, v in pairs(tbl) do out[tostring(k)] = v end
  end
  return out
end


-- ============================================================
-- ABRIR / FECHAR
-- ============================================================

-- abre o menu bennys para o veículo ativo na zona
function VHubCustom.openBennys()
  local veh = VHubCustom.activeVeh
  if not DoesEntityExist(veh) or veh == 0 then return end
  if VHubCustom.inMenu then return end

  -- snapshot ANTES de qualquer preview (rollback + estado inicial real)
  _snapshot = snapshotVeh(veh)
  Cam.start(veh)
  VHubCustom.inMenu = true

  local plate = plateOf(veh)
  local model = GetEntityModel(veh)
  local dispName = string.lower(GetDisplayNameFromVehicleModel(model) or '')
  local catEntry = (VHubCustom.catalog or {})[dispName] or {}

  SendNUIMessage({
    action = 'openBennys',
    data   = {
      plate     = plate,
      nome      = catEntry.nome or GetDisplayNameFromVehicleModel(model) or plate,
      categoria = catEntry.categoria or '—',
      prices    = priceDict(CFG.prices),
      avail     = enumerateAvailable(veh),   -- ANTI-FANTASMA
      kit_types = KIT_TYPES,                  -- nomes PT-BR dos kits disponíveis
      current   = snapshotToCurrent(_snapshot),
    },
  })

  SetNuiFocus(true, true)
end

-- fecha o menu (rollback visual se não confirmado)
function VHubCustom.closeBennys(confirmed)
  if not confirmed and VHubCustom.activeVeh and _snapshot then
    VHubCustom.applyCosmetic(VHubCustom.activeVeh, _snapshot)
  end
  Cam.stop()
  _snapshot = nil
  VHubCustom.inMenu = false
  SetNuiFocus(false, false)
end


-- ============================================================
-- RESPOSTA DO SERVIDOR (confirma / rollback)
-- ============================================================

RegisterNetEvent(E.BENNYS_CONFIRM)
AddEventHandler(E.BENNYS_CONFIRM, function(_, ok, custPatch)
  local veh = VHubCustom.activeVeh
  if not veh or not DoesEntityExist(veh) then
    VHubCustom.closeBennys(false)
    SendNUIMessage({ action = 'fecharBennys' })
    return
  end

  if ok and type(custPatch) == 'table' then
    VHubCustom.applyCosmetic(veh, custPatch)   -- estado definitivo confirmado pelo servidor
  elseif _snapshot then
    VHubCustom.applyCosmetic(veh, _snapshot)   -- rollback
  end

  VHubCustom.closeBennys(ok)
  SendNUIMessage({ action = 'fecharBennys' })
end)


-- ============================================================
-- NUI CALLBACKS
-- ============================================================

-- NUI → fecha sem aplicar (botão Cancelar/✕ ou ESC). NUNCA por timeout (removido).
RegisterNUICallback('bennys:fechar', function(_, cb)
  VHubCustom.closeBennys(false)
  cb('ok')
end)

-- NUI → aplica preview efêmero local a cada seleção (sem custo, sem persistência)
RegisterNUICallback('bennys:preview', function(patch, cb)
  local veh = VHubCustom.activeVeh
  if DoesEntityExist(veh) and veh ~= 0 and type(patch) == 'table' then
    VHubCustom.applyCosmetic(veh, patch)
  end
  cb('ok')
end)

-- NUI → arrasto do mouse no palco central orbita a câmera
RegisterNUICallback('bennys:orbit', function(d, cb)
  Cam.orbit(d and d.dx, d and d.dy)
  cb('ok')
end)

-- NUI → scroll do mouse no palco aplica zoom
RegisterNUICallback('bennys:zoom', function(d, cb)
  Cam.zoom(d and d.delta)
  cb('ok')
end)

-- NUI → foca a câmera na peça da categoria selecionada
RegisterNUICallback('bennys:focus', function(d, cb)
  local part = type(d) == 'table' and d.part or 'geral'
  -- categoria de kit manda idx → resolve a parte da câmera
  if d and d.kitIdx ~= nil then part = _kitPart[tostring(d.kitIdx)] or part end
  Cam.focus(part)
  cb('ok')
end)

-- NUI → re-enumera as rodas após troca de tipo de roda (a lista 23 muda com o tipo)
RegisterNUICallback('bennys:rescanWheels', function(d, cb)
  local veh = VHubCustom.activeVeh
  if DoesEntityExist(veh) and veh ~= 0 and d and d.wheel_type ~= nil then
    SetVehicleWheelType(veh, tonumber(d.wheel_type) or 0)
    cb({ count = GetNumVehicleMods(veh, 23) or 0 })
    return
  end
  cb({ count = 0 })
end)

-- NUI → envia patch final ao servidor (validação, cobrança e persistência server-side)
RegisterNUICallback('bennys:aplicar', function(data, cb)
  local plate   = type(data.plate)   == 'string' and data.plate   or ''
  local payload = type(data.payload) == 'table'  and data.payload or {}
  local veh     = VHubCustom.activeVeh

  if plate == '' or not DoesEntityExist(veh) or veh == 0 then
    VHubCustom.closeBennys(false)
    SendNUIMessage({ action = 'fecharBennys' })
    cb({ ok = false })
    return
  end

  TriggerServerEvent(E.BENNYS_APPLY, plate, payload)
  cb({ ok = true })
end)
