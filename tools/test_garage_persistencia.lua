-- Contrato real de lifecycle/boot com natives e SQL simulados; não substitui OneSync em jogo.
local raiz = 'resources/[SCRIPTS]/'
local total = 0
local function conferir(valor, nome)
  assert(valor, nome); total = total + 1
end
local function vetor(x, y, z)
  return setmetatable({x = x, y = y, z = z}, {
    __sub = function(a, b) return vetor(a.x-b.x, a.y-b.y, a.z-b.z) end,
    __len = function(a) return math.sqrt(a.x*a.x+a.y*a.y+a.z*a.z) end,
  })
end
local function ambiente()
  local a = { agora = 0, entidades = {}, eventos = {}, threads = {}, writes = 0,
    cobrancas = 0, char = 70, bucket = 1, vivos = {}, journals = {}, trilha = {}, logs = {} }
  local env = setmetatable({}, {__index = _G})
  local codificadas, serial = {}, 0
  env.json = {
    encode = function(v) serial = serial + 1; local s = 'json' .. serial; codificadas[s] = v; return s end,
    decode = function(v) return codificadas[v] end,
  }
  env.vHub = {Logger = {error = function(_, _, _, dados) a.erroNativo = dados end}}
  env.vec3 = vetor
  env.VHubGarage = {cfg = {persist_intervalo_s = 30, patio_boot_scan = true,
    patio_boot_destino = 'impound', patio_taxa = 500, garagens = {}},
    types = {surface = {car = 'ground'}}}
  local g = env.VHubGarage
  local function carregar(path) assert(loadfile(raiz .. path, 't', env))() end
  carregar('vhub_garage/shared/utils.lua'); carregar('vhub_garage/shared/events.lua')
  env.GetGameTimer = function() return a.agora end
  env.Citizen = {CreateThread = function(fn) a.threads[#a.threads+1] = fn end,
    Wait = function(ms) a.agora = a.agora + math.max(1, ms); if a.aoEsperar then a.aoEsperar() end end}
  env.RegisterNetEvent = function(nome, fn) if fn then a.eventos[nome] = fn end end
  env.AddEventHandler = function(nome, fn) a.eventos[nome] = fn end
  env.GetCurrentResourceName = function() return 'vhub_garage' end
  env.GlobalState = {}
  env.GetPlayers = function() return {} end
  env.GetPlayerPed = function(src) return a.char and src == 7 and 700 or 0 end
  env.GetPlayerRoutingBucket = function() return a.bucket end
  env.GetHashKey = function(modelo) return modelo == 'sultan' and 42 or 43 end
  env.DoesEntityExist = function(ent) return a.entidades[ent] ~= nil end
  env.GetEntityType = function() return 2 end
  env.GetEntityModel = function(ent) return a.entidades[ent].model end
  env.GetEntityCoords = function(ent) return ent == 700 and vetor(10,20,30) or a.entidades[ent].pos end
  env.GetEntityHeading = function(ent) return a.entidades[ent].h end
  env.GetEntityRoutingBucket = function(ent) return a.entidades[ent].bucket end
  env.GetVehicleNumberPlateText = function(ent) return a.entidades[ent].plate end
  env.GetPedInVehicleSeat = function(ent) return a.entidades[ent].driver or 0 end
  env.NetworkGetEntityOwner = function(ent) return a.entidades[ent].owner or -1 end
  env.NetworkGetNetworkIdFromEntity = function(ent) return ent + 100 end
  env.GetAllVehicles = function()
    local lista = {}; for ent in pairs(a.entidades) do lista[#lista+1] = ent end; return lista
  end
  env.CreateVehicleServerSetter = function(modelo, tipo, x,y,z,h)
    a.tipo = tipo
    if a.falhaCriar then return 0 end
    a.entidades[1] = {model = modelo, pos = vetor(x,y,z), h = h, plate = '', bucket = 0}
    return 1
  end
  env.SetEntityOrphanMode = function(ent, mode) a.entidades[ent].orphan = mode end
  env.SetEntityRoutingBucket = function(ent, bucket) a.entidades[ent].bucket = bucket end
  env.FreezeEntityPosition = function(ent, estado) a.entidades[ent].frozen = estado end
  env.SetVehicleNumberPlateText = function(ent, plate) a.entidades[ent].plate = plate end
  env.DeleteEntity = function(ent)
    a.deletes = (a.deletes or 0) + 1
    if not a.reterDelete and (not a.deleteAtrasado or a.deletes >= 3) then a.entidades[ent] = nil end
  end
  env.TriggerClientEvent = function(nome, src, snap)
    if nome ~= g.E.DO_SPAWN then return end
    a.snap = snap
    if a.semAck then return end
    a.entidades[1].owner = a.owner or src
    a.entidades[1].driver = a.semMotorista and 0 or 700
    local antes = a.agora
    env.source = 99; a.eventos[g.E.SPAWN_READY](snap.plate, snap.pedido, snap.net_id, true)
    conferir(a.agora == antes, 'ACK hostil não cria espera artificial')
    env.source = src; a.eventos[g.E.SPAWN_READY](snap.plate, snap.pedido, snap.net_id, a.ack ~= false, a.fase)
    if a.aoAck then a.aoAck() end
  end
  g.Core = {
    getCharId = function() return a.char end,
    notify = function(_, msg) a.aviso = msg end,
    log = function(_, placa, acao, _, dados) a.logs[#a.logs+1] = acao; a.ultimoLog = dados end,
    payWallet = function(_, _) a.cobrancas = a.cobrancas + 1; a.cobradoChar = a.char; return not a.semSaldo end,
    setSession = function() end, dropSession = function() end,
  }
  local row = {plate = 'ABC1234', model = 'sultan', vtype = 'car', char_id = 55, status = 'garage', position = nil}
  a.row = row
  g.SQL = {
    listByStatus = function(_, status)
      if a.falhaLeitura then error('SQL indisponível') end
      if a.listaVazia then return {} end
      return row.status == status and {row} or {}
    end,
    updatePosition = function(_, _, pos)
      if a.falhaWrite then return nil end
      a.writes = a.writes + 1; row.position = pos; return 1
    end,
    confirmarRetirada = function(_, _, _, pos)
      if a.falhaCAS then return false end
      row.status, row.position = 'out', pos
      a.confirmado = true
      if a.aoCAS then a.aoCAS() end
      return true
    end,
    cancelarRetirada = function(_, _, anterior, pos)
      a.cancelamentos = (a.cancelamentos or 0) + 1
      if row.status ~= 'out' or row.position ~= pos then return false end
      row.status, row.position = anterior.status, anterior.position
      return true
    end,
    initSchema = function() return true end,
    updateStatus = function(_, placa, status)
      a.trilha[#a.trilha+1] = 'status'
      if a.falhaStatus then return nil end
      row.status = status; return 1
    end,
    impoundPut = function(_, placa)
      a.trilha[#a.trilha+1] = 'journal'; a.journals[placa] = a.journals[placa] or {fee = 500}; return 1
    end,
    impoundGetActive = function(_, placa) return a.journals[placa] end,
  }
  env.exports = {
    vhub = {registerVehicleSpawn = function()
      a.registrado = true; if a.aoRegistro then a.aoRegistro() end; return true
    end, registerVehicleDespawn = function() a.desregistrado = true end},
    vhub_custom = {refreshVisualBag = function() return true end},
    vhub_conce = setmetatable({getVehicleState = function() return {customization = {}} end,
      getCatalog = function() return {} end, getZones = function() return {} end}, {__index = function() return function() return true end end}),
    vhub_ferinha = {getZones = function() return {} end},
  }
  carregar('vhub_garage/server/vehicles.lua')
  local m = g.Veiculos; m.pronto = true
  local function tirar(taxa)
    local copia = {}; for k,v in pairs(row) do copia[k] = v end
    local resultado
    assert(m.executar(row.plate, 7, function() resultado, a.erro = m.retirar(7, copia, {x=10,y=20,z=30,h=90}, taxa) end))
    a.threads[#a.threads]()
    return resultado
  end
  return a, env, m, tirar, carregar
end

local a,e,m,tirar = ambiente(); a.owner = 99
a.aoEsperar = function() if a.agora >= 2000 and a.entidades[1] then a.entidades[1].owner = 7 end end
conferir(tirar(0) == true, 'migração de owner em 2s não rejeita ACK legítimo')
a,e,m,tirar = ambiente(); a.ack = false; a.fase = 'solo'; a.deleteAtrasado = true
conferir(tirar(50) == false and a.deletes == 3 and not a.entidades[1], 'delete assíncrono confirmado por retry')
conferir(a.erro:find('cliente_solo', 1, true) and a.ultimoLog.fase_cliente == 'solo', 'diagnóstico allowlist preservado')
a,e,m,tirar = ambiente(); a.ack = false; a.fase = 'texto_hostil'; a.reterDelete = true
conferir(tirar(50) == false and a.entidades[1] ~= nil and a.deletes == 11, 'resíduo não some do rastreamento')
conferir(a.ultimoLog.fase_cliente == nil and a.ultimoLog.motivo == 'cliente_desconhecido', 'diagnóstico hostil descartado')
conferir(tirar(50) == false and a.erro:find('Remoção pendente', 1, true), 'retry não cria duplicata sobre resíduo')
a.reterDelete = false; a.ack = true
conferir(tirar(0) == true and a.cobrancas == 0, 'remoção convergente libera nova retirada sem débito antigo')
a,e,m,tirar = ambiente(); a.semAck = true; a.reterDelete = true
a.aoEsperar = function()
  if a.deletes and a.deletes > 0 then
    e.source = 7; a.eventos[e.VHubGarage.E.SPAWN_READY]('ABC1234', a.snap.pedido, 101, true, 'pronto')
  end
end
conferir(tirar(0) == false and a.row.status == 'garage' and not a.confirmado, 'ACK durante cleanup não promove operação cancelada')
local deletes = a.deletes
a.entidades[1].model, a.entidades[1].plate = 43, 'XYZ9999'
a.eventos.onResourceStop('vhub_garage')
conferir(a.deletes == deletes and a.entidades[1] ~= nil, 'stop não apaga handle reciclado de resíduo')

a,e,m,tirar = ambiente()
conferir(tirar(0) == true and a.tipo == 'automobile', 'server setter retira carro')
conferir(a.entidades[1].orphan == 2 and a.entidades[1].frozen == false, 'KeepEntity e release após confirmação')
conferir(a.confirmado and a.registrado and a.row.status == 'out', 'CAS e registro canônico')
conferir(tirar(50) == false and a.cobrancas == 0, 'duplicata viva não é apagada/cobrada')
m.salvarPosicoes(); local writes = a.writes
m.salvarPosicoes(); conferir(a.writes == writes, 'estacionado não escreve novamente')
a.entidades[1].h = 96; m.salvarPosicoes(); conferir(a.writes == writes+1, 'giro no mesmo lugar persiste')
a.entidades[1].pos = vetor(12,20,30); a.falhaWrite = true; m.salvarPosicoes()
a.falhaWrite = false; m.salvarPosicoes(); conferir(a.writes == writes+2, 'write falho não avança baseline')
a.listaVazia = true; a.entidades[1].pos = vetor(15,20,30); m.salvarPosicoes()
a.listaVazia = false; m.salvarPosicoes(); conferir(a.writes == writes+3 and not a.desregistrado, 'leitura vazia conserva binding')
a.falhaLeitura = true; conferir(pcall(m.salvarPosicoes) == false, 'leitura falha explícita')
a.falhaLeitura = false; a.entidades[1].pos = vetor(17,20,30); m.salvarPosicoes()
conferir(a.writes == writes+4, 'binding sobrevive falha SQL')
a.entidades[1].model = 43; m.salvarPosicoes(); conferir(a.desregistrado, 'handle reciclado não recebe writes')

for _, caso in ipairs({'semAck','ack','owner','semMotorista','falhaCAS','semSaldo','aoRegistro','aoCAS'}) do
  a,e,m,tirar = ambiente()
  if caso == 'ack' then a.ack = false
  elseif caso == 'owner' then a.owner = 99
  elseif caso == 'aoRegistro' then a.aoRegistro = function() a.bucket = 2 end
  elseif caso == 'aoCAS' then a.aoCAS = function() a.char = 80 end
  else a[caso] = true end
  local status = a.row.status
  conferir(tirar(50) == false, 'rejeitar ' .. caso)
  conferir(a.entidades[1] == nil and a.row.status == status, 'cleanup/status ' .. caso)
  if caso ~= 'semSaldo' then conferir(a.cobrancas == 0, 'sem débito ' .. caso) end
end

local carregar
a,e,m,tirar,carregar = ambiente()
a.row.status = 'out'
carregar('vhub_garage/server/init.lua')
e.onResourceStart = nil
a.eventos.onResourceStart('vhub_garage'); a.threads[#a.threads]()
conferir(a.row.status == 'impound' and a.trilha[1] == 'journal' and a.trilha[2] == 'status', 'journal antes status no boot')
conferir(e.GlobalState['vhub_garage:boot_reconciled'] == true, 'sentinel somente após sucesso')
a.row.status = 'out'; a.eventos.onResourceStart('vhub_garage'); a.threads[#a.threads]()
conferir(a.row.status == 'out' and #a.trilha == 2, 'restart resource vazio não recolhe')
a,e,m,tirar,carregar = ambiente(); a.row.status = 'out'; a.falhaStatus = true
carregar('vhub_garage/server/init.lua'); a.eventos.onResourceStart('vhub_garage')
conferir(pcall(a.threads[#a.threads]) == false and not e.GlobalState['vhub_garage:boot_reconciled'], 'boot falho não sela sentinel')
a.falhaStatus = false; a.eventos.onResourceStart('vhub_garage'); a.threads[#a.threads]()
conferir(a.row.status == 'impound' and a.journals.ABC1234.fee == 500, 'retry converge sem duplicar journal')

-- Executa o escritor SQL e os gates dos exports reais (driver callback simulado).
local sqlEnv = setmetatable({}, {__index = _G})
local publico, chamador, afetadas, respostaQuery, ultimaQuery, argumentos = {}, 'vhub_garage', 1, {}, nil, nil
sqlEnv.VHubConce = {Core = {}}
sqlEnv.json = {encode = function() return 'pos' end, decode = function()
  return {x = 10, y = 20, z = 30, h = 90}
end}
sqlEnv.promise = {new = function() return {
  resolve = function(self, valor) self.valor = valor end,
  reject = function(self, erro) self.erro = erro end,
} end}
sqlEnv.Citizen = {Await = function(p) if p.erro then error(p.erro) end; return p.valor end}
sqlEnv.GetInvokingResource = function() return chamador end
sqlEnv.exports = setmetatable({oxmysql = {
  execute = function(_, query, args, cb) ultimaQuery, argumentos = query, args; cb(afetadas) end,
  query = function(_, _, _, cb) cb(respostaQuery) end,
}}, {__call = function(_, nome, fn) publico[nome] = fn end})
assert(loadfile(raiz .. 'vhub_conce/shared/utils.lua', 't', sqlEnv))()
assert(loadfile(raiz .. 'vhub_conce/server/sql.lua', 't', sqlEnv))()
assert(loadfile(raiz .. 'vhub_conce/server/exports.lua', 't', sqlEnv))()
local anterior = {model = 'sultan', char_id = 55, status = 'garage', position = nil}
conferir(publico.confirmarRetirada('ABC1234', anterior, 'pos'), 'export CAS aprovado para garage')
conferir(ultimaQuery:find('char_id <=> ?', 1, true) and argumentos[7] == 55
  and argumentos[5] == 'garage', 'CAS proprietário persistido, não portador da chave')
afetadas = 0
conferir(not publico.confirmarRetirada('ABC1234', anterior, 'pos'), 'CAS zero não promove')
afetadas = {affectedRows = 1}
conferir(publico.cancelarRetirada('ABC1234', anterior, 'pos')
  and ultimaQuery:find('BINARY position <=> BINARY ?', 1, true), 'rollback null-safe condicionado à posição exata')
chamador = nil; conferir(not publico.confirmarRetirada('ABC1234', anterior, 'pos'), 'caller nil bloqueado')
chamador = 'vhub_admin'; conferir(not publico.cancelarRetirada('ABC1234', anterior, 'pos'), 'outro trusted não cancela retirada')
chamador = 'vhub_garage'; anterior.char_id = 0/0
conferir(not publico.confirmarRetirada('ABC1234', anterior, 'pos'), 'NaN proprietário rejeitado')
respostaQuery = nil
conferir(not pcall(function() sqlEnv.VHubConce.SQL:listByStatus('out') end), 'leitura estrita não converte erro em lista vazia')

-- HAL real: resolve netId/colisão, sem CreateVehicle nem mission ownership local.
for _, caso in ipairs({'sucesso', 'controle', 'colisao', 'ground', 'ground_retry', 'motorista_retry', 'excecao', 'origem'}) do
  a,e,m,tirar,carregar = ambiente()
  local g = e.VHubGarage
  g.state = {veiculos = {}}
  a.entidades[1] = {model = 42, plate = 'ABC1234', pos = vetor(10,20,30), h = 90, bucket = 1}
  e.PlayerPedId = function() return 700 end
  e.IsModelInCdimage = function() return true end
  e.RequestModel = function() end
  e.HasModelLoaded = function() return true end
  e.SetModelAsNoLongerNeeded = function() a.modeloLiberado = true end
  e.NetworkDoesEntityExistWithNetworkId = function() return true end
  e.NetToVeh = function() return 1 end
  e.NetworkHasControlOfEntity = function() return caso ~= 'controle' end
  e.NetworkRequestControlOfEntity = function() end
  e.HasCollisionLoadedAroundEntity = function() return caso ~= 'colisao' end
  e.RequestCollisionAtCoord = function() end
  e.SetVehicleOnGroundProperly = function(_, tolerancia)
    assert(tolerancia == 5.0 and math.type(tolerancia) == 'float', 'p1 float explícito')
    assert(not a.modeloLiberado, 'modelo permanece carregado durante preparação')
    a.assentamentos = (a.assentamentos or 0) + 1
    return caso ~= 'ground' and (caso ~= 'ground_retry' or a.assentamentos >= 3)
  end
  e.SetVehicleHasBeenOwnedByPlayer = function() end
  e.SetVehicleModKit = function() a.tuning = true; if caso == 'excecao' then error('native falhou') end end
  e.NetworkGetEntityIsNetworked = function() return false end
  e.SetPedIntoVehicle = function(_, ent)
    a.entradas = (a.entradas or 0) + 1
    if caso ~= 'motorista_retry' or a.entradas >= 3 then a.entidades[ent].driver = 700 end
  end
  e.SetEntityAsMissionEntity = function() error('mission ownership indevido') end
  e.CreateVehicle = function() error('spawn client indevido') end
  e.IsEntityAVehicle = function() return true end
  e.GetVehiclePedIsIn = function() return 1 end
  e.FindFirstVehicle = function() return 1, 1 end
  e.FindNextVehicle = function() return false end
  e.EndFindVehicle = function() end
  e.TriggerServerEvent = function(_, _, _, _, ack, fase) a.ackClient, a.faseClient = ack, fase end
  carregar('vhub_garage/client/vehicles.lua')
  e.source = caso == 'origem' and 7 or 65535
  local anteriores = #a.threads
  a.eventos[g.E.DO_SPAWN]({plate = 'ABC1234', model = 'sultan', net_id = 101,
    pedido = 'pedido', customization = {}, state = {}, surface = 'ground'}, {x=10,y=20,z=30,h=90})
  if #a.threads > anteriores then a.threads[#a.threads]() end
  if caso == 'sucesso' or caso == 'ground_retry' or caso == 'motorista_retry' then
    conferir(a.ackClient == true and g.state.veiculos.ABC1234 == 1, 'HAL inicializa entidade do servidor')
    conferir(a.modeloLiberado and a.tuning and a.faseClient == 'pronto', 'tuning concluído antes ACK/model release')
    if caso == 'ground_retry' then conferir(a.assentamentos == 3, 'solo transitório retentado') end
    if caso == 'motorista_retry' then conferir(a.entradas == 3, 'motorista confirmado após retry') end
    a.entidades[1].plate = 'XYZ9999' -- reciclagem local do handle após culling
    a.eventos[g.E.DO_DESPAWN]('ABC1234')
    conferir(a.entidades[1] ~= nil, 'handle reciclado não deleta veículo alheio')
    local coletado = false
    a.eventos['vhub_garage:collectClientState']('ABC1234', function(valor) coletado = valor end)
    conferir(coletado == nil, 'snapshot nunca usa handle de outra placa')
  elseif caso == 'origem' then
    conferir(#a.threads == anteriores and a.ackClient == nil, 'evento spawn local hostil rejeitado')
  else
    conferir(a.ackClient == false and g.state.veiculos.ABC1234 == nil, 'HAL falha segura ' .. caso)
    conferir(a.modeloLiberado and a.faseClient == ({controle='controle', colisao='colisao', ground='solo', excecao='tuning'})[caso], 'fase exata e release na falha ' .. caso)
    if caso == 'excecao' then conferir(a.erroNativo and a.erroNativo.fase == 'tuning', 'exceção preservada pelo Logger oficial') end
  end
end
print(('PASS: %d verificações de garagem; natives/SQL simulados.'):format(total))
