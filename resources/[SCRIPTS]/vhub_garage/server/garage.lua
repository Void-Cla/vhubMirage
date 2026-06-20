-- server/garage.lua  opera  es de garagem (spawn, store, transferir/emprestar/clonar chave)
---@diagnostic disable: undefined-global

local SQL  = VHubGarage.SQL
local Core = VHubGarage.Core
local U    = VHubGarage.U
local CFG  = VHubGarage.cfg
local E    = VHubGarage.E

-- ----------------------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------------------
local function getGaragem(id)
  for _, g in ipairs(CFG.garagens) do
    if g.id == id then return g end
  end
end

local function spawnOffset(vtype)
  if vtype == 'bike'  then return CFG.spawn_offset_moto  end
  if vtype == 'boat'  then return CFG.spawn_offset_boat  end
  if vtype == 'plane' then return CFG.spawn_offset_plane end
  if vtype == 'heli'  then return CFG.spawn_offset_heli  end
  return CFG.spawn_offset_carro
end

local function garagemAceita(garagem, vtype)
  for _, t in ipairs(garagem.tipos or {}) do
    if t == vtype then return true end
  end
  return false
end

-- valida que IPVA est  em dia
local function ipvaOk(row)
  if not row.ipva_paid_until or row.ipva_paid_until == 0 then return true end
  return tonumber(row.ipva_paid_until) >= os.time()
end

-- ----------------------------------------------------------------------------
-- SPAWN (tirar ve culo da garagem)
-- ----------------------------------------------------------------------------
RegisterNetEvent(E.ACT_SPAWN)
AddEventHandler(E.ACT_SPAWN, function(plate, garagem_id)
  local src  = source
  local cid  = Core:getCharId(src); if not cid then return end
  local p    = U.normalizePlate(plate); if not p then return end
  local g    = getGaragem(garagem_id); if not g then return end

  Citizen.CreateThread(function()
    local v = SQL:getVehicle(p)
    if not v then
      Core.notify(src, 'Ve culo n o registrado.'); return
    end
    if not Core.hasKeyItem(src, p) then
      Core.notify(src, 'Voc  n o tem a chave deste ve culo.'); return
    end
    if not Core:authorized(src, p) then
      Core.notify(src, 'Voc  n o tem autoriza  o para esse ve culo.'); return
    end
    if not garagemAceita(g, v.vtype) then
      Core.notify(src, ('Esta garagem n o aceita ve culos do tipo %s.'):format(v.vtype))
      return
    end

    -- proximidade da garagem (server-authoritative) — espelho da regra do STORE.
    -- Impede retirar o veiculo de qualquer ponto do mapa (IT.4 / Void-Zero).
    local pc   = GetEntityCoords(GetPlayerPed(src))
    local raio = (g.raio or CFG.raio_guardar or 5.0) + 3.0
    if #(pc - g.coord) > raio then
      Core.notify(src, 'Aproxime-se da garagem para retirar o ve culo.')
      return
    end

    if v.status == 'impound' then
      Core.notify(src, 'Ve culo est  no p tio. Liberte-o primeiro.'); return
    end
    if v.status == 'auction' then
      Core.notify(src, 'Ve culo est  em leil o.'); return
    end
    if not ipvaOk(v) then
      Core.notify(src, 'IPVA vencido. Quite antes de retirar o ve culo.'); return
    end

    -- force-out: se j  estiver "out", cobra taxa
    if v.status == 'out' then
      if not Core.payWallet(src, CFG.taxa_force_out) then
        Core.notify(src, ('Ve culo j  est  na rua. Force-out custa R$ %d.')
          :format(CFG.taxa_force_out))
        return
      end
    end

    local off = spawnOffset(v.vtype)
    local pos = { x = g.coord.x + off.x, y = g.coord.y + off.y, z = g.coord.z + off.z, h = g.h }

    -- anti-dupe server-side: remove qualquer entidade no mundo com esta placa
    -- antes de criar a nova (cobre force-out de carro perdido e clone stale).
    for _, ent in ipairs(GetAllVehicles()) do
      if U.normalizePlate(GetVehicleNumberPlateText(ent) or '') == p then
        DeleteEntity(ent)
      end
    end

    SQL:updateStatus(p, 'out')
    SQL:updatePosition(p, U.jenc({ x = pos.x, y = pos.y, z = pos.z, h = pos.h }))
    Core:log(p, 'spawn', cid, { garagem = g.id })

    -- PRONTUÁRIO: fonte única do físico+cosmético (fallback à coluna legada
    -- vhub_vehicles.customization só p/ DB anterior ao backfill)
    local st
    pcall(function() st = exports.vhub_conce:getVehicleState(p) end)
    local snapshot = {
      plate         = p,
      model         = v.model,
      vtype         = v.vtype,
      customization = (st and st.customization) or U.jdec(v.customization),
      state         = st,   -- fuel/engine/body/damage aplicados no client pós-spawn
      locked        = v.locked == 1,
      surface       = VHubGarage.types.surface[v.vtype] or 'ground',
    }
    TriggerClientEvent(E.DO_SPAWN, src, snapshot, pos)
  end)
end)

-- ----------------------------------------------------------------------------
-- STORE (guardar ve culo na garagem)
-- ----------------------------------------------------------------------------
RegisterNetEvent(E.ACT_STORE)
AddEventHandler(E.ACT_STORE, function(plate, garagem_id, payload)
  local src  = source
  local cid  = Core:getCharId(src); if not cid then return end
  local p    = U.normalizePlate(plate); if not p then return end
  local g    = getGaragem(garagem_id); if not g then return end

  Citizen.CreateThread(function()
    local v = SQL:getVehicle(p)
    if not v then return end
    if not Core.hasKeyItem(src, p) then
      Core.notify(src, 'Voc  n o tem a chave do ve culo.'); return
    end
    if not Core:authorized(src, p) then return end
    if not garagemAceita(g, v.vtype) then
      Core.notify(src, 'Garagem inadequada para esse tipo de ve culo.'); return
    end

    -- proximidade da garagem (server-authoritative): impede guardar o veiculo de longe.
    -- GetEntityCoords do ped do jogador e confiavel server-side.
    local pc   = GetEntityCoords(GetPlayerPed(src))
    local raio = (g.raio or CFG.raio_guardar or 5.0) + 3.0
    if #(pc - g.coord) > raio then
      Core.notify(src, 'Aproxime-se da garagem para guardar o ve culo.')
      return
    end

    -- proximidade do VEICULO (server-authoritative, OneSync): o carro precisa estar
    -- fisicamente dentro do raio da garagem — acaba o "guardar de longe". Placa E
    -- raio no MESMO predicado: duplicata stale fora do raio nao veta o legitimo.
    local vent, plate_seen = nil, false
    for _, ent in ipairs(GetAllVehicles()) do
      if U.normalizePlate(GetVehicleNumberPlateText(ent) or '') == p then
        plate_seen = true
        if #(GetEntityCoords(ent) - g.coord) <= raio then
          vent = ent
          break
        end
      end
    end
    if not vent then
      Core.notify(src, plate_seen
        and 'O veiculo precisa estar dentro da garagem para ser guardado.'
        or  'Veiculo nao encontrado por perto. Traga-o ate a garagem.')
      return
    end

    -- ORDEM IMPORTA (gate persistência): status='garage' PRIMEIRO — telemetria
    -- em trânsito pós-store é rejeitada pelo escritor (só aceita status='out')
    SQL:updateStatus(p, 'garage')
    Core:log(p, 'store', cid, { garagem = g.id })

    -- snapshot FINAL do físico+cosmético via MÉTODO ÚNICO (prontuário no conce);
    -- payload do cliente é hostil → sanitize aqui + re-sanitize no escritor
    if type(payload) == 'table' then
      local cust = U.sanitizeCustomization(payload.customization)
      if cust then
        SQL:updateCustomization(p, U.jenc(cust), payload.locked == true)   -- locked + cosmético (redirect)
      end
      pcall(function()
        exports.vhub_conce:saveVehicleState(p, {
          fuel          = U.finiteNum(payload.fuel, 0.0, 100.0),
          engine_health = U.finiteNum(payload.engine_health, -4000.0, 1000.0),
          body_health   = U.finiteNum(payload.body_health, 0.0, 1000.0),
          damage        = (type(payload.damage) == 'table') and payload.damage or nil,
        }, 'store')
      end)
    end

    -- despawn AUTORITATIVO: o servidor deleta a entidade validada (anti-dupe);
    -- o DO_DESPAWN ainda vai ao cliente para limpar o mapa local e restos.
    if DoesEntityExist(vent) then DeleteEntity(vent) end

    TriggerClientEvent(E.DO_DESPAWN, src, p)
    Core.notify(src, ('Ve culo %s guardado.'):format(p))
  end)
end)

-- ----------------------------------------------------------------------------
-- TRANSFER (venda definitiva P2P)
-- ----------------------------------------------------------------------------
RegisterNetEvent(E.ACT_TRANSFER)
AddEventHandler(E.ACT_TRANSFER, function(plate, target_src, valor)
  local src    = source
  local cid    = Core:getCharId(src); if not cid then return end
  local target = tonumber(target_src); if not target then return end
  local valor_n = tonumber(valor) or 0
  local p      = U.normalizePlate(plate); if not p then return end

  Citizen.CreateThread(function()
    local tuser = Core:getSession(target); if not tuser then return end
    local v = SQL:getVehicle(p)
    if not v or v.char_id ~= cid then
      Core.notify(src, 'Voc  n o   o dono.'); return
    end
    if v.status ~= 'garage' then
      Core.notify(src, 'Ve culo precisa estar na garagem para transferir.'); return
    end
    -- comprador paga (carteira+banco), vendedor recebe na carteira
    if valor_n > 0 then
      if not Core.pay(target, valor_n) then
        Core.notify(target, 'Saldo insuficiente para a transfer ncia.')
        Core.notify(src,    'Comprador sem saldo.')
        return
      end
      Core.refund(src, valor_n)
    end
    -- transfere chave-item de forma at mica (toma   d  )
    Core.takeKeyItem(src, p)
    if not Core.giveKeyItem(target, p) then
      -- estorna
      Core.giveKeyItem(src, p)
      if valor_n > 0 then Core.refund(src, -valor_n); Core.refund(target, valor_n) end
      Core.notify(src, 'Falha ao entregar chave. Inventario do comprador cheio?')
      return
    end
    -- troca de dono atomica via conce: char_id + revoga owner antigo + concede owner novo
    -- (caminho unico de troca de dono — sem competir com o updateOwner manual)
    exports.vhub_conce:transferOwner(p, tuser.char_id)
    -- físico viaja com a placa no prontuário — nada a persistir na transferência
    Core:log(p, 'transfer', cid, { to = tuser.char_id, valor = valor_n })

    Core.notify(src,    ('Ve culo %s transferido.'):format(p))
    Core.notify(target, ('Voc  recebeu o ve culo %s.'):format(p))
  end)
end)

-- ----------------------------------------------------------------------------
-- LEND key (empr stimo tempor rio)
-- ----------------------------------------------------------------------------
RegisterNetEvent(E.ACT_LEND_KEY)
AddEventHandler(E.ACT_LEND_KEY, function(plate, target_src, dias)
  local src = source
  local cid = Core:getCharId(src); if not cid then return end
  local p   = U.normalizePlate(plate); if not p then return end
  local target = tonumber(target_src); if not target then return end
  dias = tonumber(dias) or CFG.emprestar_dias
  if dias < 1 then dias = 1 elseif dias > 365 then dias = 365 end

  Citizen.CreateThread(function()
    local tuser = Core:getSession(target); if not tuser then return end
    local v = SQL:getVehicle(p)
    if not v or v.char_id ~= cid then
      Core.notify(src, 'Apenas o dono pode emprestar.'); return
    end
    local expires = os.time() + dias * 86400
    -- Modelo por-chave (FASE 3): o emprestimo entrega uma CHAVE-ITEM temporaria ao
    -- destinatario (sem ela a garagem nao lista o carro p/ ele). O cron 24h a recolhe.
    if not Core.giveKeyItem(target, p) then
      Core.notify(src, 'Inventario do destinatario cheio. Emprestimo cancelado.'); return
    end
    SQL:grantKey(p, tuser.char_id, 'shared', cid, expires)
    Core:log(p, 'lend_key', cid, { to = tuser.char_id, days = dias })
    Core.notify(src,    ('Chave do ve culo %s emprestada por %d dias.'):format(p, dias))
    Core.notify(target, ('Voc  recebeu a chave do ve culo %s por %d dias.'):format(p, dias))
  end)
end)

-- ----------------------------------------------------------------------------
-- REVOKE key (cancelar empr stimo)
-- ----------------------------------------------------------------------------
RegisterNetEvent(E.ACT_REVOKE_KEY)
AddEventHandler(E.ACT_REVOKE_KEY, function(plate, target_char_id)
  local src = source
  local cid = Core:getCharId(src); if not cid then return end
  local p   = U.normalizePlate(plate); if not p then return end
  local tcid = tonumber(target_char_id); if not tcid then return end

  Citizen.CreateThread(function()
    local v = SQL:getVehicle(p)
    if not v or v.char_id ~= cid then
      Core.notify(src, 'Voc  n o   o dono.'); return
    end
    SQL:revokeKey(p, tcid)  -- remove tudo exceto 'owner'
    -- tira a chave-item do portador (se online) — alinha com o modelo por-chave
    for s, u in pairs(Core.sessions) do
      if u.char_id == tcid then Core.takeKeyItem(s, p); break end
    end
    Core:log(p, 'revoke_key', cid, { from = tcid })
    Core.notify(src, ('Empr stimos do ve culo %s revogados para char %d.'):format(p, tcid))
  end)
end)

-- ----------------------------------------------------------------------------
-- CLONE key (paga pra ter c pia da chave no invent rio)
-- ----------------------------------------------------------------------------
RegisterNetEvent(E.ACT_CLONE_KEY)
AddEventHandler(E.ACT_CLONE_KEY, function(plate)
  local src = source
  local cid = Core:getCharId(src); if not cid then return end
  local p   = U.normalizePlate(plate); if not p then return end

  Citizen.CreateThread(function()
    local v = SQL:getVehicle(p)
    if not v or v.char_id ~= cid then
      Core.notify(src, 'Voc  n o   o dono.'); return
    end
    if not Core.payWallet(src, CFG.clone_chave_taxa) then
      Core.notify(src, ('Saldo insuficiente. Custo: R$ %d.'):format(CFG.clone_chave_taxa))
      return
    end
    if not Core.giveKeyItem(src, p) then
      Core.refund(src, CFG.clone_chave_taxa)
      Core.notify(src, 'Invent rio cheio. Pagamento estornado.')
      return
    end
    SQL:grantKey(p, cid, 'clone', cid, nil)
    Core:log(p, 'clone_key', cid, {})
    Core.notify(src, 'Chave clonada. Mant m   no invent rio.')
  end)
end)
