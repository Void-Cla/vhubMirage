-- Regressões offline dos clientes reais. Uso: lua tools/test_fluxo_entrada.lua [raiz]
-- Scheduler determinístico; natives/HSS simulados. Não substitui smoke no FiveM.
local raiz = arg[1] or '.'
local scripts = raiz .. '/resources/[SCRIPTS]/'
local total, falhas = 0, 0

local function igual(atual, esperado, descricao)
  assert(atual == esperado, ('%s: esperado %s, recebido %s'):format(
    descricao, tostring(esperado), tostring(atual)))
end

local function ambiente(recurso)
  local estado = {
    agora = 0, fila = {}, eventos = {}, callbacks = {}, mensagens = {},
    enviados = {}, controles = {}, consultasFoco = 0, foco = false,
    escurecimentos = 0, telaEscura = false, conclusoes = 0, pronto = false,
    exportacoes = {},
  }
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
      assert(passos < 100000, 'Scheduler excedeu budget')
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
  function env.RegisterNUICallback(nome, funcao) estado.callbacks[nome] = funcao end
  function env.TriggerServerEvent(nome, payload)
    estado.enviados[#estado.enviados + 1] = { nome = nome, payload = payload }
  end
  function env.SendNUIMessage(mensagem)
    estado.mensagens[#estado.mensagens + 1] = mensagem
  end
  function env.SetNuiFocus(foco) estado.foco = foco end
  function env.IsNuiFocused()
    estado.consultasFoco = estado.consultasFoco + 1
    return estado.foco
  end
  function env.DisableControlAction(_, controle)
    if controle == 24 then
      estado.controles[estado.agora] = (estado.controles[estado.agora] or 0) + 1
    end
  end
  function env.DoScreenFadeIn() estado.telaEscura = false end
  function env.DoScreenFadeOut()
    estado.escurecimentos = estado.escurecimentos + 1
    estado.telaEscura = true
  end
  function env.GetGameTimer() return estado.agora end
  function env.GetCurrentResourceName() return recurso end
  local function nada() end
  env.ClearTimecycleModifier, env.SetNuiFocusKeepInput = nada, nada
  env.SetCursorLocation, env.AddStateBagChangeHandler = nada, nada
  env.Citizen = { CreateThread = agendar, Wait = coroutine.yield,
    SetTimeout = function(atraso, funcao) agendar(funcao, atraso) end }
  env.exports = setmetatable({ vhub_hss = {
    beginCustomizationPreview = function(_, _, exigirEstagio)
      estado.exigirEstagio = exigirEstagio
      return estado.pronto
    end,
    endCustomizationPreview = function() return true end,
    restoreCustomizationPreview = function() return true end,
    setCustomizationCamera = function() return true end,
  } }, { __call = function(_, nome, funcao) estado.exportacoes[nome] = funcao end })
  function estado.carregar(arquivo)
    assert(loadfile(scripts .. arquivo, 't', env))()
  end
  function estado.contar(tipo)
    local quantidade = 0
    for _, mensagem in ipairs(estado.mensagens) do
      if mensagem.type == tipo or mensagem.action == tipo then quantidade = quantidade + 1 end
    end
    return quantidade
  end
  estado.env = env
  return estado
end

local function seletor()
  local estado = ambiente('vhub_spawselector')
  estado.carregar('vhub_hss/shared/events.lua')
  estado.carregar('vhub_spawselector/shared/events.lua')
  estado.carregar('vhub_spawselector/client/main.lua')
  local env = estado.env
  local eventos = env.VHubSpawnSelector.E
  env.AddEventHandler(eventos.COMPLETE, function() estado.conclusoes = estado.conclusoes + 1 end)
  env.TriggerEvent(eventos.OPEN, { data = { { index = 1 } }, last = true, canBack = true })
  estado.avancar(100) -- esgota o fade de abertura; começa a janela de spawn
  estado.eventosSeletor = eventos
  function estado.spawn()
    env.DoScreenFadeIn(500) -- ordem efetiva de HSS.finish_spawn
    env.TriggerEvent(env.VHubHSS.E.SPAWNED)
  end
  return estado
end

local function sims()
  local estado = ambiente('vhub_sims')
  estado.carregar('vhub_sims/core/shared/events.lua')
  estado.carregar('vhub_sims/core/client/init.lua')
  function estado.abrir(modo)
    estado.env.TriggerEvent(estado.env.VHubSims.E.CLI_STUDIO_OPEN,
      { session_id = 'sessao_repetida', mode = modo or 'creator', current = {} })
  end
  function estado.fechar()
    estado.env.TriggerEvent(estado.env.VHubSims.E.CLI_STUDIO_CLOSE, { restore = true })
  end
  return estado
end

local function testar(nome, funcao)
  total = total + 1
  local ok, erro = pcall(funcao)
  if not ok then falhas = falhas + 1 end
  io.write((ok and 'OK ' or 'FALHA ') .. nome .. (ok and '' or ': ' .. tostring(erro)) .. '\n')
end

for _, ordem in ipairs({ 'fisico_primeiro', 'resultado_primeiro' }) do
  testar('spawn_' .. ordem, function()
    local estado = seletor()
    local function resultado()
      estado.env.TriggerEvent(estado.eventosSeletor.RESULT, { ok = true })
    end
    if ordem == 'fisico_primeiro' then estado.spawn() else resultado() end
    estado.avancar(110)
    igual(estado.conclusoes, 0, 'não concluir sem as duas confirmações')
    if ordem == 'fisico_primeiro' then resultado() else estado.spawn() end
    estado.avancar(500)
    igual(estado.conclusoes, 1, 'conclusão única')
    igual(estado.telaEscura, false, 'reveal físico preservado')
    igual(estado.escurecimentos, 0, 'nenhum fade tardio do selector')
    resultado()
    estado.spawn()
    igual(estado.conclusoes, 1, 'replay não duplica conclusão')
  end)
end

testar('spawn_recusado_permite_retentativa', function()
  local estado = seletor()
  local function enviar()
    estado.callbacks.teleport({ index = 1 }, function(resposta)
      igual(resposta.ok, true, 'intenção aceita')
    end)
  end
  enviar()
  estado.env.TriggerEvent(estado.eventosSeletor.RESULT, { ok = false, err = 'spawn_recusado' })
  igual(estado.conclusoes, 0, 'recusa mantém interface')
  enviar()
  igual(#estado.enviados, 2, 'segunda intenção enviada')
end)

testar('sims_replay_nao_acumula_controles', function()
  local estado = sims()
  estado.abrir()
  estado.avancar(0)
  estado.abrir() -- mesmo session_id; objeto/lifecycle novo
  estado.avancar(10)
  igual(estado.controles[10], 1, 'uma passagem de controles por frame')
  estado.fechar()
  estado.avancar(200)
  igual(#estado.fila, 0, 'cleanup encerra todas as threads')
end)

testar('sims_replay_invalida_reveal_anterior', function()
  local estado = sims()
  estado.abrir()
  estado.avancar(0) -- primeira abertura aguardando HSS
  estado.abrir()
  estado.pronto = true
  estado.avancar(100)
  igual(estado.contar('sims:open'), 1, 'somente abertura atual revela a NUI')
end)

testar('sims_replay_invalida_cursor_anterior', function()
  local estado = sims()
  estado.abrir()
  estado.avancar(0)
  estado.abrir()
  estado.avancar(149)
  local antes = estado.consultasFoco
  estado.avancar(150)
  igual(estado.consultasFoco - antes, 1, 'somente guard atual consulta foco')
end)

testar('sims_fechado_nao_reabre_apos_hss_pronto', function()
  local estado = sims()
  estado.abrir()
  estado.avancar(0)
  estado.fechar()
  estado.pronto = true
  estado.avancar(200)
  igual(estado.contar('sims:open'), 0, 'abertura encerrada não revela NUI')
  igual(#estado.fila, 0, 'nenhuma thread residual')
end)

testar('sims_criador_exige_estagio_fisico', function()
  local estado = sims()
  estado.pronto = true
  estado.abrir()
  estado.avancar(0)
  igual(estado.exigirEstagio, true, 'criador exige estágio HSS')
  igual(estado.contar('sims:open'), 1, 'abertura após prontidão')
end)

testar('hss_estagio_aguarda_apply_inicial', function()
  local estado = ambiente('vhub_hss')
  local env = estado.env
  local applyAtivo, aplicacoes = true, 0
  env.GetInvokingResource = function() return 'vhub_sims' end
  env.PlayerPedId = function() return 1 end
  env.DoesEntityExist = function() return true end
  env.VHubHSS_IsPedApplyActive = function() return applyAtivo end
  env.VHubHSS_ApplyModelAndCustomization = function()
    aplicacoes = aplicacoes + 1
    return true
  end
  env.VHubHSS_ApplyCustomization = function() return true end
  env.VHubHSS_MovePed = function() return true end
  env.SetEntityCollision = function() end
  env.HasCollisionLoadedAroundEntity = function() return true end
  env.SetEntityVisible = function() end
  env.SetEntityInvincible = function() end
  env.FreezeEntityPosition = function() end
  env.VHubHSS = { E = setmetatable({
    CUSTOMIZATION_STAGE_BEGIN = 'stage_begin', CUSTOMIZATION_STAGE_END = 'stage_end',
  }, { __index = function(_, chave) return chave end }), Appearance = {
    sanitize = function(valor) return valor end,
    copy = function(valor) return valor end,
  } }
  estado.carregar('vhub_hss/client/customization.lua')
  env.TriggerEvent('stage_begin', { position = { x = 1, y = 2, z = 3 }, customization = {} })
  igual(env.VHubHSS_IsCustomizationStageActive(), true, 'reserva síncrona do ped')
  igual(estado.exportacoes.beginCustomizationPreview({}, true).err, 'stage_not_ready',
    'SIMS bloqueado durante apply')
  estado.avancar(500)
  igual(aplicacoes, 0, 'estágio não altera ped durante apply inicial')
  applyAtivo = false
  estado.avancar(1000)
  igual(aplicacoes, 1, 'estágio monta ped após apply inicial')
  igual(estado.exportacoes.beginCustomizationPreview({}, true).ok, true,
    'SIMS abre somente com ped pronto')
  estado.carregar('vhub_hss/client/native_bridge.lua')
  local antes = #estado.fila
  env.TriggerEvent(env.VHubHSS.E.PED_APPLY, { position = { x = 9, y = 9, z = 9 } })
  igual(#estado.fila, antes, 'apply tardio não toma o ped do criador')
end)

io.write(('%d testes; %d falhas\n'):format(total, falhas))
os.exit(falhas == 0 and 0 or 1)
