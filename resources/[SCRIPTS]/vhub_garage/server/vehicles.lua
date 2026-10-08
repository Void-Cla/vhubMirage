-- Entidade é do garage; posição durável é do conce. OneSync conserva órfãos sem simulação.
---@diagnostic disable: undefined-global
local SQL, Core, U, E = VHubGarage.SQL, VHubGarage.Core, VHubGarage.U, VHubGarage.E
local M = {}; VHubGarage.Veiculos = M
local ativos, pendentes, locks = {}, {}, {}
local fases = {payload=true, modelo=true, rede=true, controle=true, colisao=true,
  solo=true, tuning=true, estado=true, motorista=true, pronto=true}
local rodando, sequencia = true, 0
local tipos = { car = 'automobile', truck = 'automobile', bike = 'bike',
  boat = 'boat', plane = 'plane', heli = 'heli', trailer = 'trailer' }
M.pronto = false

local function falha(valor) return valor == nil or valor == false end

local function identidade(ent, placa, modelo)
  return ent and ent ~= 0 and DoesEntityExist(ent) and GetEntityType(ent) == 2
    and U.normalizePlate(GetVehicleNumberPlateText(ent)) == placa
    and (not modelo or GetEntityModel(ent) == modelo)
end

local function removerPendente(pedido)
  local limite = GetGameTimer() + 1000
  local function corresponde()
    return DoesEntityExist(pedido.ent) and GetEntityModel(pedido.ent) == pedido.model
      and (not pedido.net or NetworkGetNetworkIdFromEntity(pedido.ent) == pedido.net)
  end
  while corresponde() do
    DeleteEntity(pedido.ent)
    if not corresponde() or GetGameTimer() >= limite then break end
    Citizen.Wait(100)
  end
  return not corresponde()
end

local function contextoAtual(placa, pedido)
  local lock = locks[placa]
  local ped = GetPlayerPed(pedido.src)
  if not rodando or not lock or lock.src ~= pedido.src or lock.char ~= pedido.char
      or Core:getCharId(pedido.src) ~= pedido.char or not ped or ped == 0 then return false, 'sessao' end
  if not identidade(pedido.ent, placa, pedido.model)
      or NetworkGetNetworkIdFromEntity(pedido.ent) ~= pedido.net then return false, 'identidade' end
  if GetPlayerRoutingBucket(pedido.src) ~= pedido.bucket
      or GetEntityRoutingBucket(pedido.ent) ~= pedido.bucket then return false, 'bucket' end
  if NetworkGetEntityOwner(pedido.ent) ~= pedido.src then return false, 'replica_owner' end
  if GetPedInVehicleSeat(pedido.ent, -1) ~= ped then return false, 'replica_motorista' end
  return true
end

-- Serializa spawn/store por placa; desconexão não rouba lock de SQL em andamento.
function M.executar(placa, src, executar)
  if not M.pronto or locks[placa] then Core.notify(src, 'Garagem ocupada. Tente novamente.'); return false end
  local token = {src = src, char = Core:getCharId(src)}; locks[placa] = token
  Citizen.CreateThread(function()
    local ok = pcall(executar)
    if locks[placa] == token then locks[placa] = nil end
    if not ok then
      Core:log(placa, 'vehicle_operation_failed', Core:getCharId(src), {})
      Core.notify(src, 'Falha na operação veicular. Verifique a garagem.')
    end
  end)
  return true
end

-- Remove somente a referência física; nunca altera status persistido.
function M.esquecer(placa)
  ativos[placa] = nil
  pcall(function() exports.vhub:registerVehicleDespawn(placa) end)
end

-- Cria a entidade no servidor e aguarda a inicialização física do cliente destinatário.
local function retirar(src, row, pos, taxa)
  local placa = U.normalizePlate(row.plate)
  local tipo = tipos[row.vtype]
  if not placa or not tipo or not U.validCoords(pos) then return false, 'Posição ou tipo inválido.' end
  local residuo = pendentes[placa]
  if residuo and residuo.cancelado then
    if not removerPendente(residuo) then return false, 'Remoção pendente. Avise a administração.' end
    pendentes[placa] = nil
  end
  local ped = GetPlayerPed(src)
  if not ped or ped == 0 or not Core:getCharId(src) then return false, 'Sessão indisponível.' end
  local bucket = GetPlayerRoutingBucket(src)
  for _, ent in ipairs(GetAllVehicles()) do
    if identidade(ent, placa) then return false, 'Veículo já está na rua. Busque-o na posição atual.' end
  end
  local st = exports.vhub_conce:getVehicleState(placa)
  if type(st) ~= 'table' then return false, 'Prontuário indisponível.' end
  local lock = locks[placa]
  if not lock or lock.src ~= src or lock.char ~= Core:getCharId(src)
      or GetPlayerRoutingBucket(src) ~= bucket then return false, 'Sessão alterada.' end
  local modelo = GetHashKey(row.model)
  local ent = CreateVehicleServerSetter(modelo, tipo, pos.x + 0.0, pos.y + 0.0,
    pos.z + 0.5, (tonumber(pos.h) or 0.0) + 0.0)
  if not ent or ent == 0 or not DoesEntityExist(ent) then return false, 'Falha ao criar veículo.' end
  sequencia = sequencia + 1
  local pedido = { src = src, char = lock.char, ent = ent, bucket = bucket,
    model = modelo, token = ('%d:%d'):format(GetGameTimer(), sequencia) }
  pendentes[placa] = pedido
  SetEntityOrphanMode(ent, 2)
  SetEntityRoutingBucket(ent, bucket)
  FreezeEntityPosition(ent, true) -- aguarda colisão carregada, sem cair através do mapa
  SetVehicleNumberPlateText(ent, placa)
  local nid = NetworkGetNetworkIdFromEntity(ent)
  if not nid or nid <= 0 then DeleteEntity(ent); return false, 'Rede indisponível.' end
  pedido.net = nid
  TriggerClientEvent(E.DO_SPAWN, src, {
    plate = placa, model = row.model, vtype = row.vtype, net_id = nid, pedido = pedido.token,
    customization = st.customization, state = st, locked = row.locked == 1,
    surface = VHubGarage.types.surface[row.vtype] or 'ground',
  }, pos)
  local limite = GetGameTimer() + 25000 -- inclui carregamento, controle, colisão, solo e assento
  while rodando and pedido.resposta == nil and GetGameTimer() < limite do Citizen.Wait(50) end
  -- ACK não prova identidade: corroborar réplica após o lag de sync.
  local replica = GetGameTimer() + 5000
  while pedido.resposta == true and not contextoAtual(placa, pedido)
      and DoesEntityExist(ent) and GetGameTimer() < replica do Citizen.Wait(50) end
  if pedido.resposta ~= true or not contextoAtual(placa, pedido) then
    local _, motivo = contextoAtual(placa, pedido)
    pedido.falha = pedido.resposta == nil and 'timeout' or
      (pedido.resposta == false and ('cliente_' .. (pedido.fase or 'desconhecido')) or motivo)
    if DoesEntityExist(ent) then
      pedido.ownerObservado = NetworkGetEntityOwner(ent)
      pedido.motoristaObservado = GetPedInVehicleSeat(ent, -1)
    end
    return false, ('Retirada cancelada (%s). Nenhuma cobrança.'):format(pedido.falha)
  end
  local registrado, resultado = pcall(function() return exports.vhub:registerVehicleSpawn(placa, nid) end)
  if not registrado or resultado ~= true then
    return false, 'Registro físico indisponível.'
  end
  pedido.registrado = true
  if not contextoAtual(placa, pedido) then return false, 'Contexto alterado.' end
  local c = GetEntityCoords(ent)
  pedido.posJson = U.jenc({x = c.x, y = c.y, z = c.z, h = GetEntityHeading(ent)})
  pedido.escritaIniciada = true
  pedido.persistido = SQL:confirmarRetirada(placa, row, pedido.posJson) == true
  if not pedido.persistido then return false, 'Registro alterado ou persistência indisponível.' end
  if not contextoAtual(placa, pedido) then return false, 'Contexto alterado. Retirada cancelada.' end
  -- tryPayment do money altera cache sem Await; nenhum yield entre este gate e a promoção.
  if taxa and taxa > 0 and not Core.payWallet(src, taxa) then
    return false, ('Saldo insuficiente. Recuperação custa R$ %d.'):format(taxa)
  end
  ativos[placa] = { ent = ent, net = nid, model = modelo, pos = nil }
  FreezeEntityPosition(ent, false)
  pcall(function() exports.vhub_custom:refreshVisualBag(nid) end)
  return true
end

-- Garante cleanup de criação parcial mesmo se RPC/export/SQL lançar erro.
function M.retirar(src, row, pos, taxa)
  local placa = type(row) == 'table' and U.normalizePlate(row.plate)
  if not placa then return false, 'Placa inválida.' end
  local ok, resultado, erro = pcall(retirar, src, row, pos, taxa)
  local pedido = pendentes[placa]
  if (not ok or resultado ~= true) and pedido and not pedido.cancelado then
    if pedido.escritaIniciada then
      local compensou, restaurado = pcall(function() return SQL:cancelarRetirada(placa, row, pedido.posJson) end)
      if not compensou or restaurado ~= true then Core:log(placa, 'spawn_rollback_failed', pedido.char, {}) end
    end
    if pedido.registrado then M.esquecer(placa) end
    -- DeleteEntity pode não remover imediatamente; nunca apagar um handle reciclado.
    pedido.cancelado = true -- ACK tardio não revive a operação cancelada.
    if not removerPendente(pedido) then
      Core:log(placa, 'spawn_cleanup_failed', pedido.char, {net_id=pedido.net})
      erro = 'Retirada cancelada; remoção pendente. Avise a administração.'
    end
    if pedido.falha then
      Core:log(placa, 'spawn_initialization_failed', pedido.char,
        {motivo=pedido.falha, fase_cliente=pedido.fase, net_id=pedido.net,
          owner=pedido.ownerObservado, motorista=pedido.motoristaObservado})
    end
  end
  if not pedido or not pedido.cancelado or not DoesEntityExist(pedido.ent)
      or GetEntityModel(pedido.ent) ~= pedido.model
      or (pedido.net and NetworkGetNetworkIdFromEntity(pedido.ent) ~= pedido.net) then pendentes[placa] = nil end
  if not ok then
    Core:log(placa, 'spawn_failed', Core:getCharId(src), {})
    return false, 'Falha ao retirar veículo. Tente novamente.'
  end
  return resultado, erro
end

RegisterNetEvent(E.SPAWN_READY, function(placa, token, netId, ok, fase)
  local p = U.normalizePlate(placa)
  local pedido = p and pendentes[p]
  if not pedido or pedido.cancelado or source ~= pedido.src or token ~= pedido.token
      or netId ~= pedido.net or type(ok) ~= 'boolean' or pedido.resposta ~= nil then return end
  pedido.resposta = ok
  -- Diagnóstico não autoriza efeitos e não aceita texto arbitrário do cliente.
  pedido.fase = type(fase) == 'string' and fases[fase] and fase or nil
end)

-- Adota entidades já vivas após restart do resource; jamais recria veículo ausente.
function M.reanexar()
  local fora = {}
  for _, row in ipairs(SQL:listByStatus('out') or {}) do
    local placa = U.normalizePlate(row.plate); if placa then fora[placa] = row end
  end
  for i, ent in ipairs(GetAllVehicles()) do
    local placa = U.normalizePlate(GetVehicleNumberPlateText(ent))
    local row = placa and fora[placa]
    if row and identidade(ent, placa, GetHashKey(row.model)) and not ativos[placa] then
      SetEntityOrphanMode(ent, 2)
      ativos[placa] = { ent = ent, net = NetworkGetNetworkIdFromEntity(ent), model = GetHashKey(row.model) }
      pcall(function() exports.vhub:registerVehicleSpawn(placa, ativos[placa].net) end)
    end
    if i % 50 == 0 then Citizen.Wait(0) end
  end
end

-- Um tick global/30 s; parado não escreve SQL e não gera tráfego de cliente.
function M.salvarPosicoes()
  local fora = {}
  for _, row in ipairs(SQL:listByStatus('out') or {}) do
    local placa = U.normalizePlate(row.plate); if placa then fora[placa] = true end
  end
  local contagem = 0
  for placa, ref in pairs(ativos) do
    if not identidade(ref.ent, placa, ref.model)
        or NetworkGetNetworkIdFromEntity(ref.ent) ~= ref.net then
      M.esquecer(placa)
    elseif fora[placa] and not locks[placa] then
      local c = GetEntityCoords(ref.ent)
      local pos = { x = c.x, y = c.y, z = c.z, h = GetEntityHeading(ref.ent) }
      if U.validCoords(pos) and U.finiteNum(pos.h, 0, 360) then
        local antiga = ref.pos
        local giro = antiga and math.abs(((pos.h - antiga.h + 180) % 360) - 180) or 360
        local deslocou = not antiga or (pos.x-antiga.x)^2 + (pos.y-antiga.y)^2 + (pos.z-antiga.z)^2 > 1.0
        if (deslocou or giro > 5) and not falha(SQL:updatePosition(placa, U.jenc(pos))) then ref.pos = pos end
      end
    end
    contagem = contagem + 1
    if contagem % 50 == 0 then Citizen.Wait(0) end
  end
end

Citizen.CreateThread(function()
  local intervalo = math.max(30, tonumber(VHubGarage.cfg.persist_intervalo_s) or 30) * 1000
  while rodando do
    Citizen.Wait(intervalo)
    if rodando and M.pronto then
      local ok = pcall(M.salvarPosicoes)
      if not ok then Core:log('GARAGE', 'position_save_failed', nil, {}) end
    end
  end
end)

AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  rodando, M.pronto = false, false
  -- As entidades confirmadas sobrevivem ao restart do resource.
  for _, pedido in pairs(pendentes) do
    if DoesEntityExist(pedido.ent) and GetEntityModel(pedido.ent) == pedido.model
        and (not pedido.net or NetworkGetNetworkIdFromEntity(pedido.ent) == pedido.net) then DeleteEntity(pedido.ent) end
  end
end)
