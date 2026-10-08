-- Regressão do executor SQL HSS: nil/false válidos nunca viram strings truthy.
-- Uso: lua tools/test_hss_sql.lua [raiz]
local raiz = arg[1] or '.'
local total, falhas = 0, 0
local resposta, lancar = nil, false
local env = setmetatable({}, { __index = _G })

env.Citizen = { CreateThread = function(fn) fn() end }
env.SetTimeout = function() end
env.MySQL = {
  single = { await = function()
    if lancar then error('falha_sql_simulada') end
    return resposta
  end },
  update = { await = function() return 1 end },
}

assert(loadfile(raiz .. '/resources/[SCRIPTS]/vhub_hss/server/sql.lua', 't', env))()
local SQL = env.VHubHSS_SQL

local function verificar(nome, fn, esperadoOk, esperadoValor)
  total = total + 1
  local chamado, sucesso, valor = false
  fn(function(ok, result)
    chamado, sucesso, valor = true, ok, result
  end)
  local valorCerto = type(esperadoValor) == 'function'
    and esperadoValor(valor) or valor == esperadoValor
  local passou = chamado and sucesso == esperadoOk and valorCerto
  if not passou then falhas = falhas + 1 end
  io.write((passou and 'OK ' or 'FALHA ') .. nome .. '\n')
end

resposta = nil
verificar('load_sem_linha_preserva_nil', function(cb) SQL.load(7, cb) end, true, nil)
verificar('operacao_ausente_preserva_nil',
  function(cb) SQL.get_customization_operation('operacao', '{}', cb) end, true, nil)
verificar('personagem_ausente_preserva_false',
  function(cb) SQL.character_exists(7, cb) end, true, false)
verificar('digest_divergente_preserva_false',
  function(cb) SQL.matches(7, '{}', cb) end, true, false)

lancar = true
verificar('excecao_retorna_erro',
  function(cb) SQL.get_customization_operation('operacao', '{}', cb) end,
  false, function(valor) return type(valor) == 'string'
    and valor:find('falha_sql_simulada', 1, true) ~= nil end)

io.write(('%d testes; %d falhas\n'):format(total, falhas))
os.exit(falhas == 0 and 0 or 1)
