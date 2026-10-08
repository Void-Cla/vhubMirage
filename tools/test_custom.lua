-- Regressões offline: orçamento, owner físico, saga de reparo e escritor canônico.
-- Executar da raiz: lua tools/test_custom.lua (Lua 5.4). Natives/SQL são doubles, não FiveM real.
local raiz = 'resources/[SCRIPTS]/'
local total = 0
local function verificar(condicao, mensagem)
  total = total + 1
  assert(condicao, mensagem)
end
local function copiar(valor)
  if type(valor) ~= 'table' then return valor end
  local novo = {}
  for k, v in pairs(valor) do novo[k] = copiar(v) end
  return novo
end
dofile(raiz .. 'vhub_custom/shared/config.lua')
dofile(raiz .. 'vhub_custom/shared/events.lua')
dofile(raiz .. 'vhub_custom/shared/utils.lua')
local U, E, B = VHubCustom.U, VHubCustom.E, VHubCustom.BAG
local precos = { pneu = 300, motor_parcial = 800, lataria_parcial = 500 }
local patch, custo, semDano = U.reparo({ engine_health = 400, body_health = 750,
  damage = { tyres = { 4, 45, 45 }, tyres_rim = { 4, 47 }, doors = { 2 }, windows = { 0 } } }, 'tyre', precos)
verificar(custo == 900 and not semDano, 'pneu duplicado/aro não pode cobrar duas vezes')
verificar(#patch.damage.tyres == 0 and #patch.damage.tyres_rim == 0 and patch.damage.doors[1] == 2, 'pneus preservam estrutura')
patch, custo = U.reparo({ engine_health = 400, body_health = 1000, damage = { doors = { 0 }, tyres = { 45 } } }, 'body', precos)
verificar(custo == 500 and patch.body_health == 1000 and #patch.damage.doors == 0, 'lataria inclui portas e tarifa mínima')
verificar(patch.engine_health == nil and patch.damage.tyres[1] == 45, 'lataria não concede motor/pneus')
patch, custo = U.reparo({ engine_health = 400, damage = {} }, 'engine', precos)
verificar(custo == 4800 and patch.engine_health == 1000 and patch.damage == nil, 'motor tem preço determinístico e patch isolado')
verificar(U.reparo({ engine_health = 0/0 }, 'engine', precos) == nil, 'NaN rejeitado')
verificar(math.type(U.integer(23.0, 0, 49)) == 'integer', 'inteiro finito vira subtipo inteiro para natives GTA')
verificar(#U.indicesDano({ 0, 45, 47, 46, -1, 2.5 }, 7, true) == 3, 'índices especiais válidos; índices hostis descartados')

-- Réplica de natives para testar a aplicação real do client/mec.lua.
local eventos, callbacks, instante, timers = {}, {}, 0, {}
function RegisterNetEvent() end
function AddEventHandler(nome, fn) eventos[nome] = fn end
function RegisterNUICallback(nome, fn) callbacks[nome] = fn end
function SetTimeout(ms, fn) timers[#timers + 1] = { prazo = instante + ms, fn = fn } end
function GetGameTimer() return instante end
Citizen = { CreateThread = function(fn) fn() end, Wait = function(ms)
  instante = instante + ms
  for _, timer in ipairs(timers) do
    if not timer.executado and instante >= timer.prazo then timer.executado = true; timer.fn() end
  end
end }
local bolsas = { [B.REPAIR] = 'k1', [B.REVISION] = 1 }
function bolsas:set(chave, valor) self[chave] = valor end
function Entity() return { state = bolsas } end
function DoesEntityExist(entidade) return entidade == 10 end
function NetworkGetEntityFromNetworkId(netId) return netId == 20 and 10 or 0 end
function NetworkGetNetworkIdFromEntity() return 20 end
function GetVehicleNumberPlateText() return 'ABC1234' end
local controle = true
function NetworkHasControlOfEntity() return controle end
function NetworkRequestControlOfEntity() end
local fisico = { motor = 400, lataria = 700, tanque = 620, fuel = 37, sujeira = 12,
  ligado = false, dirigivel = false, portas = { [2] = true }, vidros = { [0] = true }, pneus = { [45] = 'aro', [47] = 'furado' } }
function GetVehicleEngineHealth() return fisico.motor end
function GetVehicleBodyHealth() return fisico.lataria end
function GetVehiclePetrolTankHealth() return fisico.tanque end
function GetVehicleFuelLevel() return fisico.fuel end
function GetVehicleDirtLevel() return fisico.sujeira end
function GetIsVehicleEngineRunning() return fisico.ligado end
function IsVehicleDriveable() return fisico.dirigivel end
function IsVehicleDoorDamaged(_, i) return fisico.portas[i] == true end
function GetEntityBoneIndexByName() return 0 end
function IsVehicleWindowIntact(_, i) return not fisico.vidros[i] end
function IsVehicleTyreBurst(_, i, aro) return fisico.pneus[i] ~= nil and (not aro or fisico.pneus[i] == 'aro') end
function SetVehicleEngineHealth(_, v) fisico.motor = v end
function SetVehicleBodyHealth(_, v) fisico.lataria = v end
function SetVehiclePetrolTankHealth(_, v) fisico.tanque = v end
function SetVehicleFuelLevel(_, v) fisico.fuel = v end
function SetVehicleDirtLevel(_, v) fisico.sujeira = v end
function SetVehicleUndriveable(_, v) fisico.dirigivel = not v end
function SetVehicleEngineOn(_, v) fisico.ligado = v end
function SetVehicleFixed()
  fisico.motor, fisico.lataria, fisico.tanque, fisico.fuel = 1000, 1000, 1000, 100
  fisico.portas, fisico.vidros, fisico.pneus = {}, {}, {}
end
function SetVehicleDeformationFixed() fisico.deformacaoCorrigida = true end
function SetVehicleTyreFixed(_, i) fisico.pneus[i] = nil end
function SetVehicleTyreBurst(_, i, aro) fisico.pneus[i] = aro and 'aro' or 'furado' end
local ack
function TriggerServerEvent(_, token, ok, snapshot) ack = { token = token, ok = ok, snapshot = snapshot } end
dofile(raiz .. 'vhub_custom/client/mec.lua')
source = 65535
eventos[E.MEC_PHYSICAL]('k1:body', 20, 'ABC1234', 'body')
verificar(ack.ok and fisico.lataria == 1000 and fisico.deformacaoCorrigida, 'lataria física confirmada')
verificar(fisico.motor == 400 and fisico.tanque == 620 and fisico.fuel == 37, 'lataria preserva motor/tanque/fuel')
verificar(fisico.pneus[45] == 'aro' and fisico.pneus[47] == 'furado' and not fisico.dirigivel, 'lataria preserva pneus e dirigibilidade')
eventos[E.MEC_PHYSICAL]('k1:tyre', 20, 'ABC1234', 'tyre')
verificar(ack.ok and next(fisico.pneus) == nil and fisico.motor == 400, 'pneus 45/47 corrigidos, motor preservado')
controle = false
eventos[E.MEC_PHYSICAL]('k1:engine', 20, 'ABC1234', 'engine')
verificar(not ack.ok and fisico.motor == 400, 'sem controle: recusa antes de mutar')
controle = true
eventos[E.MEC_PHYSICAL]('k1:engine', 20, 'ABC1234', 'engine')
verificar(ack.ok and fisico.motor == 1000, 'motor aplicado após obter controle')
eventos[E.MEC_PHYSICAL]('k1:invalid', 20, 'OUTRA', 'engine')
verificar(not ack.ok, 'netId/placa não podem ser reutilizados')

-- Saga: físico precede SQL; timeout não estorna resultado ambíguo nem solta write em voo.
local salvo, estornado, completo, fisicaConfirmada, desconhecido, rejeitado, demora = 0, 0, 0, false, false, false, false
local estado = { engine_health = 400, body_health = 700, damage = { tyres = { 45 } } }
local contexto = { entity = 10, src = 7, plate = 'ABC1234', net_id = 20, bucket = 0, char_id = 70 }
function GetPlayerName() return 'Teste' end
function GetEntityRoutingBucket() return 0 end
function GetEntityType() return 2 end
function NetworkGetEntityOwner() return 99 end
function GetCurrentResourceName() return 'vhub_custom' end
function GetInvokingResource() return 'vhub_admin' end
local revisaoServidor = 0
exports = setmetatable({ vhub_conce = {
  getVehicleState = function() return estado end,
  iniciarManutencaoVeicular = function(_, _, _, token)
    revisaoServidor = revisaoServidor + 1
    bolsas[B.REPAIR], bolsas[B.REVISION] = token, revisaoServidor
    return revisaoServidor
  end,
  encerrarManutencaoVeicular = function()
    revisaoServidor = revisaoServidor + 1
    bolsas[B.REPAIR], bolsas[B.REVISION] = nil, revisaoServidor
    return true
  end,
} }, { __call = function() end })
local liberado = false
VHubCustom.Core = {
  rateOK = function() return true end, requestId = function() return true end,
  beginMutation = function() liberado = false; return contexto, 'k1' end,
  releaseLock = function() liberado = true end, lockValid = function() return not liberado end,
  getVehicleState = function() return copiar(estado) end, refreshOperation = function() return true end,
  commitPayment = function() return true, 'op1', nil, false, true, { amount = 4800 } end,
  compensatePayment = function() estornado = estornado + 1; return true, 'refunded' end,
  saveVehicleState = function(_, p)
    verificar(fisicaConfirmada, 'SQL não pode preceder confirmação física')
    verificar(p._repair_operation_id == 'op1', 'reparo persistido leva marker da saga')
    if demora then
      Citizen.Wait(31000)
      verificar(not liberado, 'watchdog não pode soltar escrita em voo')
    end
    salvo = salvo + 1; estado.engine_health = p.engine_health or estado.engine_health; return true
  end,
  completeOperation = function() completo = completo + 1 end,
  auditVehicle = function() end, notify = function() end, log = function() end,
}
function TriggerClientEvent(evento, _, token, _, _, componente)
  if evento ~= E.MEC_PHYSICAL then return end
  local remetente = source
  source = 99
  if componente == 'inspect' then eventos[E.MEC_PHYSICAL_OK](token, true, { damage = estado.damage })
  elseif rejeitado then eventos[E.MEC_PHYSICAL_OK](token, false, { nao_aplicado = true })
  elseif not desconhecido then
    fisicaConfirmada = true
    fisico.motor = 1000
    eventos[E.MEC_PHYSICAL_OK](token, true)
  end
  source = remetente
end
dofile(raiz .. 'vhub_custom/server/mec.lua')
fisico.motor = 400
source = 7
eventos[E.MEC_REPAIR]('lease', 'request01', 'engine')
verificar(salvo == 1 and completo == 1 and estornado == 0 and bolsas[B.REPAIR] == nil, 'reparo confirmado, persistido e sem lock órfão')
desconhecido, fisicaConfirmada = true, false
estado.engine_health = 400
eventos[E.MEC_REPAIR]('lease', 'request02', 'engine')
verificar(salvo == 1 and completo == 1 and estornado == 0, 'ACK perdido: não salvar intenção nem estornar física ambígua')
desconhecido, rejeitado = false, true
eventos[E.MEC_REPAIR]('lease', 'request03', 'engine')
verificar(estornado == 0 and salvo == 1, 'ACK hostil com nao_aplicado não prova ausência nem permite estorno')
rejeitado, demora, fisicaConfirmada = false, true, false
eventos[E.MEC_REPAIR]('lease', 'request04', 'engine')
verificar(salvo == 2 and completo == 2 and liberado, 'escrita demorada mantém exclusão até concluir')

-- Writer real com SQL double: serialização, merge esparso e telemetria velha.
local codificados, sequencia, linha, gravados = {}, 0, nil, 0
local function codificar(v) sequencia = sequencia + 1; local k = 'json' .. sequencia; codificados[k] = copiar(v); return k end
VHubConce = { U = { normalizePlate = U.normalizePlate, jenc = codificar,
  jdec = function(v) return copiar(codificados[v]) or {} end }, SQL = {} }
VHubConce.SQL.scalar = function() return 'out' end
VHubConce.SQL.query = function() return linha and { copiar(linha) } or {} end
VHubConce.SQL.execute = function(sql, valores)
  if demora then coroutine.yield('sql') end
  linha = linha or { engine_health = 1000, body_health = 1000, customization = codificar({}), damage = codificar({}) }
  local colunas = assert(sql:match('vhub_vehicle_state %(plate, (.-)%)'))
  local indice = 2
  for coluna in colunas:gmatch('[%w_]+') do linha[coluna] = valores[indice]; indice = indice + 1 end
  gravados = gravados + 1
  return 1
end
local M = dofile(raiz .. 'vhub_conce/server/vstate.lua')
demora = false
verificar(M:save('ABC1234', { customization = { mods = { ['23'] = 4 }, custom_primary = { 1, 2, 3 } } }, 'cosmetic'), 'save cosmético')
verificar(M:save('ABC1234', { customization = { mods = { [23] = -1, [11] = 2 }, custom_primary = false } }, 'tune'), 'merge canônico')
local atual = M:get('ABC1234')
verificar(atual.customization.mods['23'] == -1 and atual.customization.mods[23] == nil
  and atual.customization.mods['11'] == 2 and atual.customization.custom_primary == false, 'stock/false e mods performance preservados sem chave duplicada')
verificar(M:iniciarManutencao('ABC1234', 20, 'manutencao') == 1, 'barreira nasce no writer canônico')
local resolverOriginal, existeOriginal = NetworkGetEntityFromNetworkId, DoesEntityExist
NetworkGetEntityFromNetworkId = function(netId) return netId == 21 and 11 or resolverOriginal(netId) end
DoesEntityExist = function(entidade) return entidade == 11 or existeOriginal(entidade) end
verificar(M:obterRevisaoFisica('ABC1234', 21) == nil, 'placa duplicada em outra entidade não elimina token ativo')
NetworkGetEntityFromNetworkId, DoesEntityExist = resolverOriginal, existeOriginal
bolsas[B.REPAIR], bolsas[B.REVISION] = nil, 'hostil'
local bloqueado = { engine_health = 1, _physical_net_id = 20, _physical_revision = 1 }
verificar(not M:save('ABC1234', bloqueado, 'telemetry'), 'owner não remove barreira privada adulterando bag')
verificar(M:encerrarManutencao('ABC1234', 'manutencao'), 'barreira encerrada por token')
local telemetria = { engine_health = 500, damage = { tyres = { 45, 47 } }, _physical_net_id = 20, _physical_revision = 0 }
verificar(not M:save('ABC1234', telemetria, 'telemetry') and M:get('ABC1234').engine_health == 1000, 'snapshot pré-reparo rejeitado')
telemetria._physical_revision = 2
bolsas[B.REVISION] = { hostil = true }
verificar(M:save('ABC1234', telemetria, 'telemetry') and M:get('ABC1234').engine_health == 500, 'telemetria compara revisão privada, não bag hostil')
verificar(M:get('ABC1234').damage.tyres[2] == 47, 'pneus especiais persistem no writer')
demora = true
local anterior = coroutine.create(function() M:save('ABC1234', { customization = { mods = { [0] = 1 } } }, 'cosmetic') end)
assert(coroutine.resume(anterior))
Citizen.Wait = function() coroutine.yield('lock') end
local posterior = coroutine.create(function() M:save('ABC1234', { customization = { mods = { [1] = 2 } } }, 'cosmetic') end)
assert(coroutine.resume(posterior))
verificar(coroutine.status(posterior) == 'suspended', 'write concorrente aguarda lock da placa')
assert(coroutine.resume(anterior)); demora = false; assert(coroutine.resume(posterior))
atual = M:get('ABC1234')
verificar(atual.customization.mods['0'] == 1 and atual.customization.mods['1'] == 2, 'merge concorrente não perde cosméticos')

-- Bennys: tombstones false, índice zero e stock; performance continua exclusiva da oficina.
VHubCustom.Cam = { stop = function() end }
local cores, primarioLimpo, secundarioLimpo, modAplicado = nil, false, false, {}
function SetVehicleModKit() end
function SetVehicleColours(_, p, s) cores = { p, s } end
function ClearVehicleCustomPrimaryColour() primarioLimpo = true end
function ClearVehicleCustomSecondaryColour() secundarioLimpo = true end
function GetNumVehicleMods() return 10 end
function SetVehicleMod(_, indice, nivel) modAplicado[indice] = nivel end
dofile(raiz .. 'vhub_custom/client/bennys.lua')
VHubCustom.applyCosmetic(10, { colours = { 0.0, 27.0 }, custom_primary = false, custom_secondary = false,
  mods = { [23] = -1, [11] = 3 } })
verificar(cores[1] == 0 and cores[2] == 27 and math.type(cores[1]) == 'integer', 'paleta zero preservada; natives recebem inteiros')
verificar(primarioLimpo and secundarioLimpo, 'RGB false limpa ambas as cores')
verificar(modAplicado[23] == -1 and modAplicado[11] == nil, 'stock aplicado; performance rejeitada na estética')
local valorCobrado, respostaCosmetica, replay = nil, nil, false
VHubCustom.Core.commitPayment = function(_, _, _, valor)
  valorCobrado = valor; return true, 'op2', nil, replay, true, { amount = valor }
end
VHubCustom.Core.saveVehicleState = function(_, p)
  estado.customization = estado.customization or {}
  for k, v in pairs(p.customization or {}) do estado.customization[k] = v end
  return true
end
function TriggerClientEvent(evento, _, _, _, cosm)
  if evento == E.BENNYS_CONFIRM then respostaCosmetica = cosm end
end
dofile(raiz .. 'vhub_custom/server/bennys.lua')
source = 7
estado.customization = { smoke = true, mods = { ['23'] = 2 }, custom_primary = { 200, 10, 10 } }
eventos[E.BENNYS_APPLY]('lease', 'bennys01', { smoke = false, mods = { [23] = 2 }, custom_primary = false })
verificar(valorCobrado == VHubCustom.cfg.prices.fumaca and estado.customization.custom_primary == false,
  'só campo alterado é cobrado; false persiste no servidor')
replay = true
estado.customization.colours = { 10, 20 }
eventos[E.BENNYS_APPLY]('lease', 'bennys01', { colours = { 1, 2 } })
verificar(respostaCosmetica.colours[1] == 10 and respostaCosmetica.colours[2] == 20,
  'replay reflete estado atual, nunca reaplica compra antiga')

-- Oficina: mutação única e resposta vinculada à lease/request.
local enviado, mensagens, reqSeq = nil, {}, 0
function TriggerServerEvent(evento, lease, requestId, payload)
  enviado = { evento = evento, lease = lease, requestId = requestId, payload = payload }
end
function SendNUIMessage(mensagem) mensagens[#mensagens + 1] = mensagem end
VHubCustom.nextRequestId = function() reqSeq = reqSeq + 1; return ('request%02d'):format(reqSeq) end
VHubCustom.notify = function() end
VHubCustom.inMenu = true
VHubCustom.service = { domain = 'oficina', lease_id = 'lease_nova' }
dofile(raiz .. 'vhub_custom/client/oficina.lua')
local recibo
callbacks['oficina:instalarParte']({ part_id = 'teste' }, function(r) recibo = r end)
verificar(recibo.ok and enviado.lease == 'lease_nova', 'intenção oficina usa lease atual')
local pedido = enviado.requestId
callbacks['oficina:instalarKitNitro']({}, function(r) recibo = r end)
verificar(not recibo.ok, 'segunda mutação bloqueada enquanto instalação está em voo')
eventos[E.OFICINA_INSTALL_PART_OK](true, '', {}, 'lease_antiga', pedido)
verificar(#mensagens == 0, 'resposta de lease antiga descartada')
eventos[E.OFICINA_INSTALL_PART_OK](true, '', { installed_parts = { teste = true } }, 'lease_nova', pedido)
verificar(#mensagens == 1 and mensagens[1].data.installed_parts.teste, 'resposta atual re-renderiza estado autoritativo')
callbacks['oficina:instalarKitNitro']({}, function(r) recibo = r end)
verificar(recibo.ok, 'trava liberada após resposta correspondente')

-- Recovery de lataria saudável não confunde intenção com aplicação física.
verificar(M:save('ABC1234', { engine_health = 1000.0, _repair_operation_id = 'vc:comprovada' }, 'repair'), 'marker persistido no UPSERT')
VHubCustom.SQL = {}
json = { decode = VHubConce.U.jdec }
exports.vhub_conce.getVehicleState = function() return M:get('ABC1234') end
dofile(raiz .. 'vhub_custom/server/core.lua')
local resultado = codificar({ engine_health = 1000 })
verificar(not VHubCustom.Core.operationApplied({ action = 'repair_engine', operation_id = 'vc:sem_ack', plate = 'ABC1234', after_json = resultado }),
  'health igual não autoriza recovery sem marker de ACK')
verificar(VHubCustom.Core.operationApplied({ action = 'repair_engine', operation_id = 'vc:comprovada', plate = 'ABC1234', after_json = resultado }),
  'marker durável permite concluir recovery após queda')
print(('PASS: %d verificações custom; natives/SQL simulados.'):format(total))
