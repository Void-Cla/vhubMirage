-- Contrato offline do checkout do criador. Uso: lua tools/test_sims_creator.lua [raiz]
local raiz = arg[1] or '.'
local total, falhas = 0, 0

local function caso(nome, configurar, verificar)
  total = total + 1
  local ok, erro = pcall(function()
    local estado = {
      revisao = 0, aparencia = { apv = 2, model = 'mp_m_freemode_01' },
      resultados = {}, chamadas = {}, eventos = {},
    }
    local env = setmetatable({}, { __index = _G })
    env.VHubSims = {
      E = { CLI_STUDIO_OPEN = 'open', CLI_CHECKOUT_RESULT = 'result',
        CLI_STUDIO_CLOSE = 'close', CREATION_DONE = 'done',
        CREATION_CANCELLED = 'cancelled' },
      cfg = { creator_session_ttl_ms = 60000 },
      catalog = { modes = { creator = { label = 'Criador', tabs = {} } } },
      APShape = {
        profile = function(valor) return valor end,
        copy = function(valor) return valor end,
        merge = function(valor, patch)
          local copia = {}
          for chave, item in pairs(valor) do copia[chave] = item end
          for chave, item in pairs(patch) do copia[chave] = item end
          return copia
        end,
        digest = function(valor)
          if valor.model then return tostring(valor.model) .. ':' .. tostring(valor.apv) end
          return 'digest-creator-12345678'
        end,
      },
    }
    env.GetGameTimer = function() return 0 end
    env.GetPlayerName = function() return 'jogador' end
    env.Citizen = { Wait = function() end }
    env.TriggerClientEvent = function(evento, _, resultado)
      if evento == 'result' then estado.resultados[#estado.resultados + 1] = resultado end
    end
    env.TriggerEvent = function(evento) estado.eventos[evento] = (estado.eventos[evento] or 0) + 1 end
    env.VHubSimsCore = {
      ready = true,
      rate = function() return true end,
      getUser = function()
        estado.consultas_char = (estado.consultas_char or 0) + 1
        local char_id = estado.trocar_no_checkout and estado.consultas_char >= 3 and 8 or 7
        return { source = 1, char_id = char_id }, char_id
      end,
      token = function() return 'session-creator-12345678' end,
      sanitizePatch = function(patch) return patch end,
      resultOk = function(result) return result == true or type(result) == 'table' and result.ok == true end,
      resultError = function(result, fallback)
        return type(result) == 'table' and result.err or fallback
      end,
      log = function() end,
    }
    env.VHubSimsOutfits = { isAllowed = function() return true end }
    env.VHubSimsCore.call = function(recurso, metodo, ...)
      estado.chamadas[#estado.chamadas + 1] = recurso .. ':' .. metodo
      if metodo == 'getCustomization' then
        return true, { ok = true, customization = estado.aparencia, revision = estado.revisao }
      end
      if metodo == 'beginPendingStage' then return true, { ok = true, stage_token = 'stage:7:1:1' } end
      if metodo == 'commitCustomization' then
        local _, patch, revisao = ...
        estado.commits = (estado.commits or 0) + 1
        if estado.na_primeira and estado.commits == 1 then
          estado.revisao = estado.revisao + 1
          if estado.outra_aparencia then estado.aparencia = estado.outra_aparencia end
          return true, { ok = false, err = 'conflict', reason = 'revision_mismatch' }
        end
        if revisao ~= estado.revisao then return true, { ok = false, err = 'conflict' } end
        return true, { ok = true, customization = patch, new_revision = revisao + 1 }
      end
      if metodo == 'endPendingStage' then
        if estado.falha_estagio then return true, { ok = false, err = 'native' } end
        return true, { ok = true }
      end
      return true, { ok = true }
    end
    assert(loadfile(raiz .. '/resources/[SCRIPTS]/vhub_sims/core/server/session.lua', 't', env))()
    assert(loadfile(raiz .. '/resources/[SCRIPTS]/vhub_sims/core/server/creator.lua', 't', env))()
    configurar(estado)
    local aberto = env.VHubSimsCreator.begin(1, 'request-creator-12345678')
    assert(aberto.ok == true)
    assert(env.VHubSimsCreator.submitWizard(1, {
      session_id = aberto.session_id, firstname = 'Ana', lastname = 'Silva', age = 25,
    }))
    local concluido = env.VHubSimsCreator.checkout(1, {
      session_id = aberto.session_id, patch = { model = 'mp_f_freemode_01' },
    })
    verificar(estado, concluido)
  end)
  if not ok then falhas = falhas + 1 end
  io.write((ok and 'OK ' or 'FALHA ') .. nome .. (ok and '' or ': ' .. tostring(erro)) .. '\n')
end

caso('revisao_deriva_sem_alterar_aparencia',
  function(estado) estado.na_primeira = true end,
  function(estado, concluido)
    assert(concluido == true and estado.commits == 2)
    assert(estado.eventos.done == 1)
  end)

caso('edicao_concorrente_nao_sobrescreve',
  function(estado)
    estado.na_primeira = true
    estado.outra_aparencia = { apv = 2, model = 'mp_f_freemode_01' }
  end,
  function(estado, concluido)
    assert(concluido == false and estado.commits == 1)
    assert(estado.eventos.done == nil)
  end)

caso('falha_do_estagio_bloqueia_criacao',
  function(estado) estado.falha_estagio = true end,
  function(estado, concluido)
    assert(concluido == false and estado.eventos.done == nil)
    for _, chamada in ipairs(estado.chamadas) do
      assert(chamada ~= 'vhub:commitSimsCreation')
    end
  end)

caso('troca_de_char_invalida_sessao',
  function(estado) estado.trocar_no_checkout = true end,
  function(estado, concluido)
    assert(concluido == false and estado.commits == nil)
    assert(estado.eventos.done == nil)
  end)

io.write(('%d testes; %d falhas\n'):format(total, falhas))
os.exit(falhas == 0 and 0 or 1)
