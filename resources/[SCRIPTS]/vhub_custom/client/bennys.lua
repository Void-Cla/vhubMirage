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
local _snapshot    = nil
-- stance persistido no momento da abertura — rollback do preview volta ao SALVO, não ao stock
local _savedStance = nil

-- coerção INT: natives de índice (tint/placa/livery/xenon) são int; float do
-- msgpack/JSON (ex.: 3.0) pode ser bit-reinterpretado pelo native → valor errado.
-- math.floor força o subtipo integer (espelha o '+0.0' usado p/ floats no garage).
local function toint(v, d)
  local n = tonumber(v)
  return n and math.floor(n) or (d or 0)
end

-- NB: stance e fogo de escapamento saíram DESTE arquivo. Stance agora é per-entidade em
-- client/stance.lua (VHubCustom.Stance) e o fogo é backfire não-ignitável em client/exhaust.lua
-- (VHubCustom.Exhaust). Aqui só disparamos PREVIEW via esses módulos.


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
  { idx = 14, name = 'Buzina',              part = 'frente'   },
  { idx = 23, name = 'Rodas',              part = 'roda'     },
  { idx = 25, name = 'Suporte de placa',    part = 'frente'   },
  { idx = 26, name = 'Placa de vaidade',    part = 'frente'   },
  { idx = 27, name = 'Acabamento',         part = 'lateral'  },
  { idx = 28, name = 'Ornamentos',         part = 'frente'   },
  { idx = 29, name = 'Painel',              part = 'lateral'  },
  { idx = 30, name = 'Mostradores',         part = 'lateral'  },
  { idx = 31, name = 'Alto-falantes das portas', part = 'lateral' },
  { idx = 32, name = 'Bancos',              part = 'lateral'  },
  { idx = 33, name = 'Volante',            part = 'lateral'  },
  { idx = 34, name = 'Câmbio',             part = 'lateral'  },
  { idx = 35, name = 'Placa decorativa',   part = 'traseira' },
  { idx = 36, name = 'Alto-falantes',       part = 'traseira' },
  { idx = 37, name = 'Porta-malas',         part = 'traseira' },
  { idx = 38, name = 'Conjunto hidráulico', part = 'traseira' },
  { idx = 39, name = 'Bloco do motor',      part = 'frente'   },
  { idx = 40, name = 'Filtro de ar',        part = 'frente'   },
  { idx = 41, name = 'Barras estruturais',  part = 'frente'   },
  { idx = 42, name = 'Cobertura dos arcos', part = 'lateral'  },
  { idx = 43, name = 'Antenas',             part = 'teto'     },
  { idx = 44, name = 'Acabamento interno',  part = 'lateral'  },
  { idx = 45, name = 'Tanque',              part = 'traseira' },
  { idx = 46, name = 'Janelas',             part = 'lateral'  },
  { idx = 47, name = 'Detalhe adicional',   part = 'geral'    },
  { idx = 48, name = 'Adesivagem',          part = 'lateral'  },
  { idx = 49, name = 'Barra de luz',        part = 'teto'     },
}


-- ============================================================
-- ENUMERAÇÃO ANTI-FANTASMA (GetNumVehicleMods)
-- ============================================================

-- retorna { kits={[idx]=count}, liveryCount=n, wheelMods=n, extras={[idx]=true} } só com o que existe
local function enumerateAvailable(veh)
  local avail = { kits = {}, liveryCount = -1, wheelMods = 0, extras = {} }
  for _, k in ipairs(KIT_TYPES) do
    local n = GetNumVehicleMods(veh, k.idx)
    if n and n > 0 then avail.kits[tostring(k.idx)] = n end
  end
  avail.wheelMods   = GetNumVehicleMods(veh, 23) or 0
  avail.liveryCount = GetVehicleLiveryCount(veh) or -1
  for i = 0, (CFG.extras_max or 14) - 1 do
    if DoesExtraExist(veh, i) then avail.extras[tostring(i)] = true end
  end
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

  -- cores de interior/painel (índice GTA) — lidas defensivamente
  local interiorCol, dashboardCol = 0, 0
  pcall(function() interiorCol = GetVehicleInteriorColour(veh) or 0 end)
  pcall(function() dashboardCol = GetVehicleDashboardColour(veh) or 0 end)

  -- extras do modelo (acessórios — toggle por idx)
  local extras = {}
  for i = 0, (CFG.extras_max or 14) - 1 do
    if DoesExtraExist(veh, i) then
      extras[tostring(i)] = IsVehicleExtraTurnedOn(veh, i)
    end
  end

  -- turbo (18) NÃO é coletado: chave EXCLUSIVA da oficina (performance)
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
    interior_color  = interiorCol,
    dashboard_color = dashboardCol,
    extras = extras,
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
    pcall(SetVehicleXenonLightsColor, veh, toint(c.xenon_color, 0))
  end

  if c.window_tint ~= nil then SetVehicleWindowTint(veh, toint(c.window_tint, 0)) end
  if c.wheel_type  ~= nil then SetVehicleWheelType(veh, toint(c.wheel_type, 0)) end
  if c.livery      ~= nil then SetVehicleLivery(veh, toint(c.livery, -1)) end
  if c.plate_index ~= nil then SetVehicleNumberPlateTextIndex(veh, toint(c.plate_index, 0)) end
  if c.interior_color  ~= nil then pcall(SetVehicleInteriorColour, veh, toint(c.interior_color, 0)) end
  if c.dashboard_color ~= nil then pcall(SetVehicleDashboardColour, veh, toint(c.dashboard_color, 0)) end

  -- kits cosméticos (nunca performance — defesa em profundidade)
  if type(c.mods) == 'table' then
    for k, lvl in pairs(c.mods) do
      local idx = tonumber(k)
      if idx and not CFG.performance_mods[idx] then
        SetVehicleMod(veh, idx, tonumber(lvl) or -1, false)
      end
    end
  end

  -- acessórios extras do modelo (SetVehicleExtra: 3º param = "disable", não "enable")
  if type(c.extras) == 'table' then
    for k, enabled in pairs(c.extras) do
      local idx = tonumber(k)
      if idx and DoesExtraExist(veh, idx) then
        SetVehicleExtra(veh, idx, not enabled)
      end
    end
  end

  -- stance (rebaixamento visual REAL, per-entidade) — delega ao módulo client/stance.lua, que
  -- aplica altura/bitola/roda via natives per-entidade (sem vazar model-wide como o antigo).
  if c.stance ~= nil and VHubCustom.Stance then
    VHubCustom.Stance.apply(veh, c.stance)
  end

  -- glass_armor é puramente RP; sem efeito visual client-side (não interfere com window_tint)

  -- fogo no escapamento (PREVIEW): uma leva colorida p/ o jogador ver a cor escolhida. O efeito
  -- contínuo ao dirigir é do módulo client/exhaust.lua (backfire NÃO-ignitável, via State Bag).
  if type(c.exhaust_fx) == 'table' and c.exhaust_fx.enabled and VHubCustom.Exhaust then
    VHubCustom.Exhaust.preview(veh, c.exhaust_fx)
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
    interior_color   = snap.interior_color,
    dashboard_color  = snap.dashboard_color,
    window_tint      = snap.window_tint,
    wheel_type       = snap.wheel_type,
    livery           = snap.livery,
    plate_index      = snap.plate_index,
    mods             = mods,
    extras           = snap.extras or {},
    stance           = {},   -- stance vive na PLACA (não na entidade) → vem de auth.saved.stance
    glass_armor      = snap.glass_armor or 0,
    exhaust_fx       = snap.exhaust_fx or { enabled = false },
  }
end


-- ============================================================
-- HELPERS
-- ============================================================

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
function VHubCustom.openBennys(auth)
  local veh = VHubCustom.activeVeh
  if not DoesEntityExist(veh) or veh == 0 then return end
  if VHubCustom.inMenu then return end
  if type(auth) ~= 'table' or not VHubCustom.service or VHubCustom.service.domain ~= 'bennys' then return end

  -- snapshot ANTES de qualquer preview (rollback + estado inicial real)
  _snapshot = snapshotVeh(veh)
  Cam.start(veh)
  VHubCustom.inMenu = true

  local plate = auth.plate
  local model = GetEntityModel(veh)

  -- estado inicial = snapshot da entidade + campos virtuais persistidos (PTFX/RP/índice),
  -- que não vivem na entidade viva. Sem isso a UI mostraria default no reabrir.
  local current = snapshotToCurrent(_snapshot)
  _savedStance = nil
  if type(auth.saved) == 'table' then
    if type(auth.saved.exhaust_fx) == 'table' then current.exhaust_fx = auth.saved.exhaust_fx end
    if type(auth.saved.stance) == 'table' then
      current.stance = auth.saved.stance
      _savedStance   = auth.saved.stance   -- referência p/ rollback do preview de stance
    end
    if auth.saved.glass_armor ~= nil then current.glass_armor = auth.saved.glass_armor end
  end

  SendNUIMessage({
    action = 'openBennys',
    data   = {
      plate              = plate,
      nome               = auth.name or GetDisplayNameFromVehicleModel(model) or plate,
      categoria          = auth.category or '—',
      prices             = priceDict(CFG.prices),
      avail              = enumerateAvailable(veh),
      kit_types          = KIT_TYPES,
      current            = current,
      stance             = CFG.stance,
      glass_armor_tiers  = CFG.glass_armor_tiers,
      paint_palettes     = CFG.paint_palettes,
    },
  })

  SetNuiFocus(true, true)
end

-- fecha o menu. No CANCELAR: rollback — reaplica o snapshot cosmético e volta o stance ao estado
-- SALVO (não ao stock; o carro já vinha com o stance persistido). O escapamento de preview é
-- backfire não-loopado (auto-extingue) → nada a parar. No CONFIRMAR: mantém o preview (o servidor
-- persiste e o State Bag reafirma stance/escapamento p/ TODOS os clientes).
function VHubCustom.closeBennys(confirmed)
  local veh = VHubCustom.activeVeh
  if not confirmed then
    if veh and _snapshot then VHubCustom.applyCosmetic(veh, _snapshot) end
    if veh and veh ~= 0 and DoesEntityExist(veh) and VHubCustom.Stance then
      VHubCustom.Stance.apply(veh, _savedStance)   -- rollback do stance → estado salvo
    end
  end
  Cam.stop()
  _snapshot = nil
  _savedStance = nil
  VHubCustom.inMenu = false
  VHubCustom.endService('bennys')
  SetNuiFocus(false, false)
end


-- ============================================================
-- RESPOSTA DO SERVIDOR (confirma / rollback)
-- ============================================================

RegisterNetEvent(E.BENNYS_CONFIRM)
AddEventHandler(E.BENNYS_CONFIRM, function(_, ok, custPatch, netId)
  local veh = VHubCustom.activeVeh
  if not veh or not DoesEntityExist(veh) or NetworkGetNetworkIdFromEntity(veh) ~= tonumber(netId) then
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

  local service = VHubCustom.service
  if not service or service.domain ~= 'bennys' then cb({ ok = false }); return end
  TriggerServerEvent(E.BENNYS_APPLY, service.lease_id, VHubCustom.nextRequestId(), payload)
  cb({ ok = true })
end)


-- ============================================================
-- CLEANUP — desfaz o preview de stance se parar com o menu aberto
-- ============================================================

AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  local veh = VHubCustom.activeVeh
  if VHubCustom.inMenu and veh and veh ~= 0 and DoesEntityExist(veh) and VHubCustom.Stance then
    VHubCustom.Stance.apply(veh, _savedStance)   -- volta ao stance salvo (não deixa preview vazar)
  end
end)
