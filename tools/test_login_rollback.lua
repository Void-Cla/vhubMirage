-- Regress?es offline da compensa??o de cria??o. Uso: lua tools/test_login_rollback.lua [raiz]
-- Executa fluxo/init reais; exports simulados com falhas e yields controlados. Sem banco/FiveM.
local raiz = arg[1] or '.'
local scripts = raiz .. '/resources/[SCRIPTS]/'
local total, falhas = 0, 0

local function igual(atual, esperado, descricao)
  assert(atual == esperado, ('%s: esperado %s, recebido %s'):format(
    descricao, tostring(esperado), tostring(atual)))
end

local function ambiente(recurso)
  local estado = { agora = 0, fila = {}, eventos = {} }
  local env = setmetatable({}, { __index = _G })
  local function agendar(funcao, atraso)
    estado.fila[#estado.fila + 1] = {
      rotina = coroutine.create(funcao), prazo = estado.agora + (atraso or 0),
    }
  end
  function estado.avancar(destino)
    local passos = 0
    while true do
      local indice, prazo
      for i, item in ipairs(estado.fila) do
        if item.prazo <= destino and (not prazo or item.prazo < prazo) then
          indice, prazo = i, item.prazo
        end
      end
      if not indice then break end
      passos = passos + 1
      assert(passos < 10000, 'Scheduler excedeu budget')
      estado.agora = prazo
      local item = table.remove(estado.fila, indice)
      local ok, atraso = coroutine.resume(item.rotina)
      assert(ok, atraso)
      if coroutine.status(item.rotina) ~= 'dead' then
        item.prazo = estado.agora + math.max(1, atraso or 0)
        estado.fila[#estado.fila + 1] = item
      end
    end
    estado.agora = destino
  end
  function env.AddEventHandler(nome, funcao)
    estado.eventos[nome] = estado.eventos[nome] or {}
    table.insert(estado.eventos[nome], funcao)
  end
  function env.RegisterNetEvent(nome, funcao)
    if funcao then env.AddEventHandler(nome, funcao) end
  end
  function env.TriggerEvent(nome, ...)
    for _, funcao in ipairs(estado.eventos[nome] or {}) do funcao(...) end
  end
  function env.GetGameTimer() return estado.agora end
  function env.GetCurrentResourceName() return recurso end
  env.Citizen = { CreateThread = agendar, Wait = coroutine.yield,
    SetTimeout = function(atraso, funcao) agendar(funcao, atraso) end }
  env.exports = setmetatable({ vhub_hss = {} }, { __call = function() end })
  function estado.carregar(arquivo)
    assert(loadfile(scripts .. arquivo, 't', env))()
  end
  estado.env = env
  return estado
end

local function testar(nome, funcao)
  total = total + 1
  local ok, erro = pcall(funcao)
  if not ok then falhas = falhas + 1 end
  io.write((ok and 'OK ' or 'FALHA ') .. nome .. (ok and '' or ': ' .. tostring(erro)) .. '\n')
end

local function login(criando)
  local estado = ambiente('vhub_login')
  local env = estado.env
  estado.descartes, estado.criacoes, estado.selecoes, estado.cancelamentos = 0, 0, 0, 0
  estado.logs, estado.retornoCliente = {}, {}
  estado.resultadoDescarte = { ok = false, err = 'storage' }
  estado.resultadoAbertura = { ok = false, err = 'dependency' }
  env.VHubLogin = { Config = { auth_deadline = 120 }, Contas = {} }
  env.GetResourceState = function() return 'started' end
  env.GetPlayerName = function() return 'jogador_teste' end
  env.GetInvokingResource = function() return 'vhub_sims' end
  env.TriggerClientEvent = function(nome, src, ...)
    estado.retornoCliente[#estado.retornoCliente + 1] = { nome = nome, src = src, args = { ... } }
  end
  env.exports.vhub = {
    discardDraftCharacter = function(_, src, char_id)
      igual(src, 1, 'source canônico')
      igual(char_id, 77, 'alvo do descarte')
      estado.descartes = estado.descartes + 1
      if estado.aoDescartar then estado.aoDescartar() end
      if estado.lancarDescarte then error('CORE indisponível') end
      return estado.resultadoDescarte
    end,
    createCharacter = function(_, _, pedido)
      estado.criacoes = estado.criacoes + 1
      estado.ultimoPedido = pedido
      return { ok = true, char_id = 77 }
    end,
    selectCharacter = function()
      estado.selecoes = estado.selecoes + 1
      return true
    end,
    getCharacterIds = function() return { ok = true, items = { 77, 78 } } end,
    log = function(_, _, _, _, dados) estado.logs[#estado.logs + 1] = dados end,
  }
  env.exports.vhub_hss.holdForCreation = function() return true end
  env.exports.vhub_hss.releaseCreationHold = function() return true end
  env.exports.vhub_hss.isolateEntrySession = function() return 101 end
  env.exports.vhub_hss.getCharacterSummaries = function() return { ok = true, items = {} } end
  env.exports.vhub_identity = { getCharacterSummaries = function() return { ok = true, items = {} } end }
  env.exports.vhub_sims = {
    needsCreation = function() return { ok = true, needed = true } end,
    beginCreation = function() return estado.resultadoAbertura end,
    cancelCreation = function() estado.cancelamentos = estado.cancelamentos + 1; return true end,
  }
  estado.carregar('vhub_hss/shared/events.lua')
  estado.carregar('vhub_sims/core/shared/events.lua')
  estado.carregar('vhub_spawselector/shared/events.lua')
  estado.carregar('vhub_login/shared/events.lua')
  estado.carregar('vhub_login/server/dominio/fluxo.lua')
  local fluxo = env.VHubLogin.Fluxo
  local sessao = { uid = 42, step = criando and 'creating' or 'charselect',
    create_request_id = 'pedido_original' }
  if criando then
    sessao.creating_char_id, sessao.creating_is_new = 77, true
    sessao.creation_session_id = 'criador_original'
    fluxo.creatingByChar[77] = 1
  end
  fluxo.sessions[1] = sessao
  estado.fluxo, estado.sessao = fluxo, sessao
  return estado
end

for _, causa in ipairs({ 'storage', 'not_draft', 'excecao' }) do
  testar('login_rollback_criar_' .. causa, function()
    local estado = login(false)
    estado.resultadoDescarte.err = causa
    estado.lancarDescarte = causa == 'excecao'
    local ok, erro = estado.fluxo.criar(1)
    igual(ok, false, 'criação falhou')
    igual(erro, 'rollback_pendente', 'compensação recusada explícita')
    igual(estado.sessao.create_request_id, 'pedido_original', 'request preservado')
    igual(estado.sessao.rascunho_pendente, 77, 'referência preservada')
    igual(estado.logs[1].erro, causa == 'excecao' and 'core_indisponivel' or causa,
      'causa canônica observável')
    ok, erro = estado.fluxo.criar(1)
    igual(ok, false, 'nova criação bloqueada')
    igual(erro, 'rollback_pendente', 'retry ainda recusado')
    ok, erro = estado.fluxo.selecionar(1, 78)
    igual(ok, false, 'seleção bloqueada')
    igual(erro, 'rollback_pendente', 'seleção não contorna compensação')
    igual(estado.criacoes, 1, 'não criou segundo rascunho')
    igual(estado.selecoes, 1, 'não selecionou após falha')
    igual(estado.descartes, 3, 'retry usa descarte do owner')
  end)
end

testar('login_retry_confirmado_libera_criacao', function()
  local estado = login(false)
  estado.fluxo.criar(1)
  estado.resultadoDescarte = { ok = true, discarded = false, replayed = true }
  estado.resultadoAbertura = { ok = true, session_id = 'criador_novo' }
  local ok, erro, transicao = estado.fluxo.criar(1)
  igual(ok, true, 'replay confirmado libera criação')
  igual(erro, nil, 'sem erro residual')
  igual(transicao, 'creating', 'handoff preservado')
  igual(estado.sessao.rascunho_pendente, nil, 'compensação consumida')
  assert(estado.ultimoPedido ~= 'pedido_original', 'não reutilizar request do char descartado')
  igual(estado.criacoes, 2, 'uma criação após confirmação')
end)

testar('login_cancelado_retorna_erro_e_preserva_compensacao', function()
  local estado = login(true)
  estado.carregar('vhub_login/server/init.lua')
  estado.env.TriggerEvent(estado.env.VHubLogin.E.CREATION_CANCELLED, 77)
  estado.avancar(0)
  igual(estado.sessao.step, 'charselect', 'criador encerrado retorna à seleção')
  igual(estado.sessao.rascunho_pendente, 77, 'alvo transferido para compensação')
  igual(estado.sessao.create_request_id, 'pedido_original', 'request de retry preservado')
  igual(estado.fluxo.creatingByChar[77], nil, 'criador encerrado remove índice')
  igual(estado.retornoCliente[1].args[2], 'rollback_pendente', 'erro chega ao contrato NUI existente')
  igual(#estado.retornoCliente[1].args[1], 1, 'não oferece rascunho aguardando descarte')
  igual(estado.retornoCliente[1].args[1][1].id, 78, 'outro personagem continua visível')
  local ok, erro = estado.fluxo.selecionar(1, 78)
  igual(ok, false, 'não avança com descarte pendente')
  igual(erro, 'rollback_pendente', 'retentativa reportada')
  igual(estado.selecoes, 0, 'nenhuma seleção no CORE')
end)

testar('login_voltar_preserva_estado_ate_descarte_confirmado', function()
  local estado = login(true)
  local personagens, erro = estado.fluxo.voltarPersonagens(1)
  igual(personagens, nil, 'retorno recusado')
  igual(erro, 'rollback_pendente', 'falha explícita')
  igual(estado.sessao.step, 'creating', 'etapa preservada')
  igual(estado.sessao.creating_char_id, 77, 'referência do criador preservada')
  igual(estado.fluxo.creatingByChar[77], 1, 'índice preservado')
  igual(estado.sessao.create_request_id, 'pedido_original', 'request preservado')
  igual(estado.cancelamentos, 0, 'não encerra SIMS antes da confirmação')
  estado.resultadoDescarte = { ok = true, discarded = true }
  personagens, erro = estado.fluxo.voltarPersonagens(1)
  igual(type(personagens), 'table', 'retry retorna seleção')
  igual(erro, nil, 'retry sem erro')
  igual(estado.sessao.rascunho_pendente, nil, 'alvo consumido')
  igual(estado.sessao.create_request_id, nil, 'request descartado após sucesso')
  igual(estado.fluxo.creatingByChar[77], nil, 'índice removido após sucesso')
  igual(estado.cancelamentos, 1, 'encerra SIMS uma vez')
end)

for _, caso in ipairs({ 'concluido', 'rascunho_preexistente' }) do
  testar('login_nao_descarta_' .. caso, function()
    local estado = login(true)
    if caso == 'rascunho_preexistente' then estado.sessao.creating_is_new = false end
    local src, isolado, erro = estado.fluxo.concluirCriacao(77, caso == 'concluido')
    igual(src, 1, 'sessão encontrada')
    igual(isolado, true, 'seleção isolada')
    igual(erro, nil, 'conclusão limpa')
    igual(estado.descartes, 0, 'owner não recebe descarte')
    igual(estado.sessao.rascunho_pendente, nil, 'sem compensação indevida')
  end)
end

testar('login_encerramento_serializa_descarte_com_yield', function()
  local estado = login(true)
  local retorno
  estado.aoDescartar = function() estado.env.Citizen.Wait(50) end
  estado.env.Citizen.CreateThread(function()
    retorno = { estado.fluxo.concluirCriacao(77, false) }
  end)
  estado.avancar(0)
  igual(estado.fluxo.concluirCriacao(77, false), nil, 'evento duplicado não encerra em paralelo')
  local personagens, erro = estado.fluxo.voltarPersonagens(1)
  igual(personagens, nil, 'volta concorrente recusada')
  igual(erro, 'rollback_pendente', 'compensação em voo')
  igual(estado.descartes, 1, 'um único descarte durante yield')
  estado.avancar(50)
  igual(retorno[3], 'rollback_pendente', 'erro entregue pelo encerramento original')
  igual(estado.sessao.rascunho_pendente, 77, 'referência não perdida')
end)

for _, troca in ipairs({ 'sessao', 'rascunho', 'pedido' }) do
  testar('login_resposta_antiga_preserva_' .. troca, function()
    local estado = login(false)
    estado.sessao.rascunho_pendente = 77
    estado.resultadoDescarte = { ok = true, discarded = true }
    estado.aoDescartar = function() estado.env.Citizen.Wait(50) end
    local retorno
    estado.env.Citizen.CreateThread(function() retorno = { estado.fluxo.criar(1) } end)
    estado.avancar(0)
    if troca == 'sessao' then
      estado.fluxo.sessions[1] = {
        uid = 90, step = 'charselect', rascunho_pendente = 88, create_request_id = 'pedido_novo',
      }
    elseif troca == 'rascunho' then estado.sessao.rascunho_pendente = 88
    else estado.sessao.create_request_id = 'pedido_novo' end
    local atual = estado.fluxo.sessions[1]
    local alvo, pedido = atual.rascunho_pendente, atual.create_request_id
    estado.avancar(50)
    igual(retorno[1], false, 'operação antiga abortada')
    igual(retorno[2], 'estado_invalido', 'mudança de operação reconhecida')
    igual(atual.rascunho_pendente, alvo, 'nova referência intacta')
    igual(atual.create_request_id, pedido, 'novo request intacto')
    igual(estado.criacoes, 0, 'nenhuma criação pela rotina antiga')
  end)
end

io.write(('%d testes; %d falhas\n'):format(total, falhas))
os.exit(falhas == 0 and 0 or 1)
