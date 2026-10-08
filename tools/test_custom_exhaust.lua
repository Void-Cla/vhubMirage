-- Regressões do emissor único. Executar na raiz com Lua 5.4; natives simuladas, sem jogo real.
local total = 0
local function verificar(condicao, mensagem)
  total = total + 1
  assert(condicao, mensagem)
end

dofile('resources/[SCRIPTS]/vhub_custom/shared/config.lua')
dofile('resources/[SCRIPTS]/vhub_custom/shared/nitro_cfg.lua')
local FX = VHubCustom.cfg.exhaust_fx
verificar(FX.asset == 'mirage_backfire_rgb' and FX.effect == 'chama_rgb'
  and FX.colour_mode == 'rgb' and FX.resource == nil, 'provedor RGB privado incluído no custom')
verificar(FX.scale_factor == 0.5 and FX.max_scale == 1.5 and FX.outlet_push == 0.12,
  'escala linear até máximo 1.5 sem alterar deslocamento durante calibração de tamanho')
-- Dicionário RGB simulado; não certifica recoloração de qualquer asset real.
FX.asset, FX.effect, FX.colour_mode = 'rgb_teste', 'chama_teste', 'rgb'
VHubCustom.BAG = { EXHAUST = 'vhub_custom:exhaust' }
local instante, carregado, controle, motorista, veiculo, modelo = 1000, true, true, true, 10, 100
local bolsa, emissoes, pedidos, consultas, eventos, threads = {}, {}, 0, 0, {}, {}
local bones = { exhaust = 100, exhaust_1 = 100, exhaust_16 = 116 }
local modEscapamento, extras, rotacoes, comandos = -1, {}, {}, {}
local cor, falhar, iniciado, logs = nil, false, true, {}
function vec3(x,y,z) return {x=x,y=y,z=z} end
function VHubCustom.log(msg) logs[#logs+1] = msg end
function GetResourceState() return iniciado and 'started' or 'stopped' end
function GetCurrentResourceName() return 'vhub_custom' end
function AddEventHandler(nome, fn) eventos[nome] = fn end
function CreateThread(fn) threads[#threads + 1] = coroutine.create(fn) end
function RegisterCommand(nome, fn) comandos[nome] = fn end
function Wait(ms) coroutine.yield(ms) end
function GetGameTimer() return instante end
function DoesEntityExist(entidade) return entidade == 10 end
function PlayerPedId() return 20 end
function GetVehiclePedIsIn() return veiculo end
function GetPedInVehicleSeat() return motorista and 20 or 30 end
function NetworkHasControlOfEntity() return controle end
function Entity() return { state = bolsa } end
function GetEntityModel() return modelo end
function GetDisplayNameFromVehicleModel() return 'VEICULO_TESTE' end
function GetVehicleMod(_, indice) assert(indice == 4); return modEscapamento end
function IsVehicleExtraTurnedOn(_, id) return extras[id] == true end
function GetEntityBoneRotationLocal(_, indice) return rotacoes[indice] or vec3(0,0,0) end
function GetEntityBoneIndexByName(_, nome) consultas = consultas + 1; return bones[nome] or -1 end
function GetEntityBonePosition_2() error('native de rotação não pode posicionar PTFX') end
function GetWorldPositionOfEntityBone(_, indice) return { x = 1000 + indice / 100, y = 1997, z = 3000.2 } end
function GetOffsetFromEntityGivenWorldCoords(_, x, y, z) return { x = x - 1000, y = y - 2000, z = z - 3000 } end
function GetModelDimensions() return { x = -1, y = -4, z = -0.5 }, { x = 1, y = 4, z = 1.5 } end
function HasNamedPtfxAssetLoaded() return carregado end
function RequestNamedPtfxAsset() pedidos = pedidos + 1 end
function UseParticleFxAssetNextCall(asset) assert(asset == FX.asset) end
function SetParticleFxNonLoopedColour(r, g, b) cor = { r, g, b } end
function SetParticleFxNonLoopedAlpha(alpha) assert(alpha == 1.0) end
local function emitir(rede, nome, entidade, x, y, z, rx, ry, rz, escala)
  emissoes[#emissoes + 1] = { rede = rede, nome = nome, entidade = entidade,
    x = x, y = y, z = z, rx = rx, ry = ry, rz = rz, escala = escala, cor = cor }
  return not falhar
end
function StartParticleFxNonLoopedOnEntity(...) return emitir(false, ...) end
function StartNetworkedParticleFxNonLoopedOnEntity(...) return emitir(true, ...) end
function GetVehicleCurrentRpm() return 1.0 end
function IsControlPressed() return true end

dofile('resources/[SCRIPTS]/vhub_custom/client/exhaust.lua')
local EX = VHubCustom.Exhaust
verificar(EX.intervalMs == 450 and EX.supportsRGB(), 'provedor RGB declarado/carregado e budget único')
local config = { enabled = true, r = 0, g = 255, b = 0, scale = 1.5 }
verificar(not EX.preview(10, { enabled = false, r = 255, g = 0, b = 0 }), 'preview desligado não emite')
carregado = false
verificar(not EX.preview(10, config) and pedidos == 1 and #emissoes == 0, 'asset ausente não bloqueia nem cria partículas')
carregado = true
verificar(EX.preview(10, config) and #emissoes == 2, 'bones únicos incluem exhaust_16 e não duplicam exhaust_1')
verificar(not emissoes[1].rede and math.abs(emissoes[1].x - 1.0) < 0.001
  and math.abs(emissoes[1].y + 3.12) < 0.001, 'preview usa boca real e avança 12 cm para fora')
verificar(emissoes[1].cor[1] == 0 and emissoes[1].cor[2] == 1 and emissoes[1].cor[3] == 0, 'RGB zero preservado')
local consultasPrimeira = consultas
instante = instante + EX.intervalMs
EX.preview(10, config)
verificar(consultas == consultasPrimeira, 'bones cacheados somente para a entidade/modelo atual')

bolsa[VHubCustom.BAG.EXHAUST] = { enabled = true, r = 10, g = 20, b = 250, scale = 4.0 }
instante = instante + EX.intervalMs
verificar(EX.nitro(10, { r = 255, g = 0, b = 0 }), 'nitro emite com driver/controle válido')
local ultima = emissoes[#emissoes]
verificar(ultima.rede and ultima.escala == 1.5 and ultima.cor[3] == 250 / 255.0, 'bag único, escala antiga limitada ao teto seguro')
local maxima = ultima.escala
instante = instante + EX.intervalMs
verificar(EX.preview(10, {enabled=true,r=10,g=20,b=250,scale=3.0})
  and emissoes[#emissoes].escala == maxima and emissoes[#emissoes].y == ultima.y,
  'máximo selecionado chega a1.5; preview e nitro usam mesma escala e origem')
local quantidade = #emissoes
instante = instante + EX.intervalMs - 1
verificar(not EX.nitro(10) and #emissoes == quantidade, 'nitro respeita intervalo mínimo')
instante = instante + 1
bolsa[VHubCustom.BAG.EXHAUST] = { enabled = true, r = 255, g = 12, b = 0, scale = 0.5 }
verificar(EX.nitro(10) and emissoes[#emissoes].escala == 0.25
  and emissoes[#emissoes].cor[1] == 1, 'cor/escala do bag aparecem sem reentrar e sem piso exclusivo do nitro')
controle = false; instante = instante + EX.intervalMs; quantidade = #emissoes
verificar(not EX.nitro(10) and #emissoes == quantidade, 'sem controle não replica')
controle = true; motorista = false
verificar(not EX.nitro(10) and #emissoes == quantidade, 'passageiro não replica')
motorista = true; veiculo = 0
verificar(not EX.nitro(10) and #emissoes == quantidade, 'não emite em veículo diferente do dirigido')
veiculo = 10
bolsa[VHubCustom.BAG.EXHAUST] = { enabled = true, r = 0/0, g = 0, b = 0 }
verificar(not EX.nitro(10, { r = 8, g = 16, b = 32 }) and #emissoes == quantidade,
  'bag inválido não cria segundo perfil via fallback legado')
bolsa[VHubCustom.BAG.EXHAUST] = nil
verificar(not EX.nitro(10) and #emissoes == quantidade, 'nitro sem kit de chamas não emite')
bolsa[VHubCustom.BAG.EXHAUST] = { enabled = false, r = 255, g = 0, b = 0 }
verificar(not EX.nitro(10) and #emissoes == quantidade, 'kit desligado também desliga chama nitro')
verificar(not EX.preview(10, {enabled=true,r=math.huge,g=0,b=0}) and #emissoes == quantidade,
  'NaN/infinito não chegam à native')

modelo = 101; bones = {}; quantidade = #emissoes
instante = instante + EX.intervalMs
EX.preview(10, config)
verificar(#emissoes == quantidade and #logs == 1,
  'modelo sem bones não inventa saídas e registra ausência')
instante = instante + EX.intervalMs; EX.preview(10, config)
verificar(#logs == 1, 'ausência de saídas não produz log a cada pulso')
modelo = 102; bones = { exhaust = 100 }; falhar = true; quantidade = #emissoes
instante = instante + EX.intervalMs
verificar(not EX.preview(10, config) and #emissoes == quantidade + 1,
  'retorno false não cria cópia nas saídas de fallback')
quantidade = #emissoes
verificar(not EX.preview(10, config) and #emissoes == quantidade, 'tentativa falha também consome cooldown')
falhar = false
modelo = 103; bones = { exhaust = 0 }
for i = 1, 16 do bones['exhaust_' .. i] = i * 10 end
instante = instante + EX.intervalMs
quantidade = #emissoes; EX.preview(10, config)
verificar(#emissoes == quantidade + 16, 'cap de 16 saídas por leva')

modelo = 104; bones = {exhaust=100, exhaust_1=101}
local posicaoOriginal = GetWorldPositionOfEntityBone
function GetWorldPositionOfEntityBone() return {x=1001,y=1997,z=3000.2} end
instante = instante + EX.intervalMs; quantidade = #emissoes
verificar(EX.preview(10, config) and #emissoes == quantidade+1, 'bones diferentes na mesma saída não duplicam chama')
GetWorldPositionOfEntityBone = posicaoOriginal

-- Orientação local do escapamento; efeito -Y avança lateralmente ou para cima, nunca sempre atrás.
modelo = 105; bones = {exhaust=100}; rotacoes[100] = vec3(0,0,90)
instante = instante + EX.intervalMs; EX.preview(10, config)
ultima = emissoes[#emissoes]
verificar(math.abs(ultima.x-1.12)<0.001 and math.abs(ultima.y+3)<0.001 and ultima.rz==90,
  'saída lateral +X: avanço acompanha yaw local, rotação enviada ao PTFX')
rotacoes[100] = vec3(-90,0,0); instante = instante + EX.intervalMs; EX.preview(10, config)
ultima = emissoes[#emissoes]
verificar(math.abs(ultima.z-0.32)<0.001 and ultima.rx==-90, 'saída vertical: pitch dirige extrusão')
rotacoes[100] = vec3(0,70,180); instante = instante + EX.intervalMs; EX.preview(10, config)
ultima = emissoes[#emissoes]
verificar(math.abs(ultima.y+2.88)<0.001 and ultima.ry==70, 'roll preservado e saída +Y avança no sentido escolhido')
rotacoes = {}

local consultasAntes = consultas
modEscapamento = 0; bones = {exhaust=116}; instante = instante + EX.intervalMs; EX.preview(10, config)
verificar(consultas>consultasAntes and math.abs(emissoes[#emissoes].x-1.16)<0.001,
  'troca mod4 invalida índices e não reaproveita escapamento original')
consultasAntes = consultas
extras[14] = true; bones = {exhaust=100}; instante = instante + EX.intervalMs; EX.preview(10, config)
verificar(consultas>consultasAntes and math.abs(emissoes[#emissoes].x-1)<0.001,
  'troca extra invalida descoberta de bones')

-- Posição é lida de novo sem invalidar índices; veículo rotacionado não duplica yaw mundial.
local converterOriginal = GetOffsetFromEntityGivenWorldCoords
function GetWorldPositionOfEntityBone() return vec3(1003,2002,3000.3) end
function GetOffsetFromEntityGivenWorldCoords(_,x,y,z) return vec3(y-2000,-(x-1000),z-3000) end
instante = instante + EX.intervalMs; EX.preview(10, config)
ultima = emissoes[#emissoes]
verificar(math.abs(ultima.x-2)<0.001 and math.abs(ultima.y+3.12)<0.001 and ultima.rz==0,
  'posição fresca convertida do mundo ao carro; rotação local sem aplicar yaw mundial duas vezes')
function GetWorldPositionOfEntityBone() return vec3(1000,2000,3000) end
instante = instante + EX.intervalMs; quantidade = #emissoes
verificar(not EX.preview(10,config) and #emissoes==quantidade, 'bone no centro do carro não vira escapamento')
function GetWorldPositionOfEntityBone() return vec3(math.huge,2000,3000) end
instante = instante + EX.intervalMs
verificar(not EX.preview(10,config) and #emissoes==quantidade, 'coordenada mundial infinita não passa à native')
GetWorldPositionOfEntityBone, GetOffsetFromEntityGivenWorldCoords = posicaoOriginal, converterOriginal

modelo = 106; modEscapamento = -1; bones = {}
FX.model_outlets[modelo] = {
  [-1] = {{pos=vec3(-0.7,-2.1,0.3),rot=vec3(0,0,-90)}, {pos=vec3(0.7,-2.1,0.3),rot=vec3(0,0,90)}},
  [0] = {{pos=vec3(0,-2.2,0.4),rot=vec3(0,0,0)}},
  [1] = {},
  [2] = {{pos=vec3(100,0,0),rot=vec3(0,0,0)}},
}
instante = instante + EX.intervalMs; quantidade = #emissoes
verificar(EX.preview(10,config) and #emissoes==quantidade+2
  and math.abs(emissoes[#emissoes].x-0.82)<0.001, 'perfil medido: duas saídas reais com direções opostas')
modEscapamento = 0; instante = instante + EX.intervalMs; quantidade = #emissoes
verificar(EX.preview(10,config) and #emissoes==quantidade+1
  and math.abs(emissoes[#emissoes].y+2.32)<0.001, 'perfil mod4 troca quantidade e localização')
modEscapamento = 1; instante = instante + EX.intervalMs; quantidade = #emissoes
verificar(not EX.preview(10,config) and #emissoes==quantidade, 'perfil vazio não cai nos bones nem fabrica chama')
modEscapamento = 2; instante = instante + EX.intervalMs
verificar(not EX.preview(10,config) and #emissoes==quantidade, 'perfil fora dos limites rejeitado sem saturar coordenadas')
modelo = 107; modEscapamento = -1; bones = {exhaust=100}; logs = {}

FX.colour_mode = 'fixed'; instante = instante + EX.intervalMs
verificar(not EX.supportsRGB() and EX.preview(10,config) and emissoes[#emissoes].cor[1] == 1
  and emissoes[#emissoes].cor[2] == 1, 'modo fixo não aplica RGB selecionado; tint neutro')
FX.colour_mode = 'rgb'; FX.resource = 'ptfx_externo'; iniciado = false
instante = instante + EX.intervalMs; quantidade = #emissoes
verificar(not EX.preview(10,config) and #emissoes == quantidade and #logs == 1, 'resource externo ausente falha explícita sem fallback nativo')
EX.preview(10,config); verificar(#logs == 1, 'diagnóstico externo limitado a uma ocorrência')
iniciado = true
verificar(EX.supportsRGB() and EX.preview(10,config), 'asset externo iniciado libera o mesmo emissor')
FX.resource = nil

-- O loop lê o bag já existente: não depende de evento antigo perdido no culling.
veiculo = 0
local ok, espera = coroutine.resume(threads[1])
verificar(ok and espera == 500, 'budget ocioso 500 ms; sem polling por frame')
veiculo = 10; instante = instante + 1000
bolsa[VHubCustom.BAG.EXHAUST] = config
ok, espera = coroutine.resume(threads[1])
verificar(ok and espera == 60, 'bag preexistente ativa loop restrito de 60 ms')
quantidade = #emissoes; EX.nitro(10)
instante = instante + 60
ok, espera = coroutine.resume(threads[1])
verificar(ok and #emissoes == quantidade, 'backfire não duplica emissor enquanto nitro está ativo')
verificar(not EX.preview(10,config) and #emissoes == quantidade, 'preview e nitro compartilham cooldown')
VHubCustom.inMenu = true; instante = instante + 1000
quantidade = #emissoes; ok, espera = coroutine.resume(threads[1])
verificar(ok and espera == 500 and #emissoes == quantidade and not EX.nitro(10), 'menu permite só preview local, sem nitro/backfire concorrente')
verificar(EX.preview(10,config) and not emissoes[#emissoes].rede, 'preview prioritário no menu permanece local')
VHubCustom.inMenu = false
-- Diagnóstico é visual/read-only, temporário e sem um segundo emissor.
local marcadores, linhas = {}, {}
function GetOffsetFromEntityInWorldCoords(_,x,y,z) return vec3(x+1000,y+2000,z+3000) end
function DrawMarker(tipo,x,y,z) marcadores[#marcadores+1] = {tipo=tipo,x=x,y=y,z=z} end
function DrawLine(...) linhas[#linhas+1] = {...} end
local threadsAntes, logsAntes = #threads, #logs
quantidade = #emissoes; comandos.vhub_escapamento()
verificar(#threads==threadsAntes+1 and #logs==logsAntes+2 and #emissoes==quantidade,
  'diagnóstico informa quantidade e coordenadas sem emitir PTFX')
instante = instante + EX.intervalMs; logsAntes = #logs
EX.preview(10,config)
verificar(#logs == logsAntes+1 and logs[#logs]:find('escala=0.750',1,true)
  and logs[#logs]:find('origem=1.000,-3.120,0.200',1,true),
  'diagnóstico registra escala e origem realmente enviadas no preview, não outro perfil salvo')
instante = instante + EX.intervalMs; EX.preview(10,config)
verificar(#logs == logsAntes+1, 'log de emissão real limitado a1Hz durante diagnóstico')
local diagnostico = threads[#threads]
ok, espera = coroutine.resume(diagnostico)
verificar(ok and espera==0 and #marcadores==2 and #linhas==1,
  'overlay marca boca/origem e direção de uma única saída')
verificar(math.abs(marcadores[2].y-marcadores[1].y+0.12)<0.001,
  'marcador de chama mostra avanço real utilizado pelo emissor')
comandos.vhub_escapamento(); ok = coroutine.resume(diagnostico)
verificar(ok and coroutine.status(diagnostico)=='dead' and #threads==threadsAntes+1,
  'segundo comando interrompe overlay sem criar loop concorrente')
comandos.vhub_escapamento(); diagnostico = threads[#threads]
instante = instante+10001; ok = coroutine.resume(diagnostico)
verificar(ok and coroutine.status(diagnostico)=='dead', 'diagnóstico expira em dez segundos')
veiculo = 0; threadsAntes = #threads; comandos.vhub_escapamento()
verificar(#threads==threadsAntes, 'sem veículo não cria thread de diagnóstico')
VHubCustom.inMenu=true; VHubCustom.activeVeh=10; comandos.vhub_escapamento()
diagnostico = threads[#threads]; ok, espera = coroutine.resume(diagnostico)
verificar(ok and espera==0, 'diagnóstico também funciona no veículo da oficina com ped fora')
veiculo=10; VHubCustom.inMenu=false
eventos.onResourceStop('vhub_custom')
ok = coroutine.resume(threads[1])
verificar(ok and coroutine.status(threads[1]) == 'dead' and not EX.nitro(10)
  and not EX.preview(10, config), 'cleanup termina loop e impede emissão posterior')
ok = coroutine.resume(diagnostico)
verificar(ok and coroutine.status(diagnostico)=='dead', 'resource stop também encerra overlay')

-- Novo lifecycle: dicionário externo inexistente tem timeout, sem requests infinitos/fallback.
carregado = false; pedidos = 0; logs = {}; instante = 10000
dofile('resources/[SCRIPTS]/vhub_custom/client/exhaust.lua'); EX = VHubCustom.Exhaust
verificar(not EX.preview(10, config) and pedidos == 1, 'novo lifecycle pede asset uma única vez')
instante = instante + 5000
verificar(not EX.preview(10, config) and #logs == 1 and pedidos == 1, 'timeout PTFX é explícito e limitado')
EX.preview(10, config)
verificar(#logs == 1 and pedidos == 1 and not EX.supportsRGB(), 'asset falho não mascara ausência com core')
eventos.onResourceStop('vhub_custom')

carregado = true; FX.asset = '../hostil'; logs = {}
dofile('resources/[SCRIPTS]/vhub_custom/client/exhaust.lua'); EX = VHubCustom.Exhaust
verificar(not EX.preview(10, config) and #logs == 1, 'config inválida não alcança native')
eventos.onResourceStop('vhub_custom')

print(('OK: %d verificações de escapamento/nitro.'):format(total))
