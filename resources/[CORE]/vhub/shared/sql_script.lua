-- Executa scripts SQL locais como instruções isoladas, sem multipleStatements.
VHubSQLScript = VHubSQLScript or {}

local LIMITE_SCRIPT = 4 * 1024 * 1024
local LIMITE_INSTRUCAO = 1024 * 1024
local LIMITE_INSTRUCOES = 512

local function aparar(valor)
  return valor:match('^%s*(.-)%s*$')
end

-- Separa SQL sem cortar ponto e vírgula dentro de strings, identificadores ou comentários.
function VHubSQLScript.separar(script)
  if type(script) ~= 'string' or script == '' then return nil, 'script_invalido' end
  if #script > LIMITE_SCRIPT then return nil, 'script_excede_limite' end

  local instrucoes, buffer = {}, {}
  local estado, indice, tamanho = 'normal', 1, #script

  local function anexar(valor)
    buffer[#buffer + 1] = valor
  end

  local function concluir()
    local instrucao = aparar(table.concat(buffer))
    buffer = {}
    if instrucao == '' then return true end
    if #instrucao > LIMITE_INSTRUCAO then return false, 'instrucao_excede_limite' end
    if #instrucoes >= LIMITE_INSTRUCOES then return false, 'excesso_de_instrucoes' end
    instrucoes[#instrucoes + 1] = instrucao
    return true
  end

  while indice <= tamanho do
    local atual = script:sub(indice, indice)
    local proximo = indice < tamanho and script:sub(indice + 1, indice + 1) or ''

    if estado == 'normal' then
      if atual == "'" then estado = 'aspas_simples'; anexar(atual)
      elseif atual == '"' then estado = 'aspas_duplas'; anexar(atual)
      elseif atual == '`' then estado = 'identificador'; anexar(atual)
      elseif atual == '-' and proximo == '-' then estado = 'comentario_linha'; indice = indice + 1
      elseif atual == '#' then estado = 'comentario_linha'
      elseif atual == '/' and proximo == '*' then estado = 'comentario_bloco'; indice = indice + 1
      elseif atual == ';' then
        local ok, erro = concluir()
        if not ok then return nil, erro end
      else anexar(atual) end
    elseif estado == 'comentario_linha' then
      if atual == '\n' then estado = 'normal'; anexar('\n') end
    elseif estado == 'comentario_bloco' then
      if atual == '*' and proximo == '/' then
        estado = 'normal'
        indice = indice + 1
        anexar(' ')
      end
    else
      anexar(atual)
      if atual == '\\' then
        if proximo ~= '' then anexar(proximo); indice = indice + 1 end
      elseif estado == 'aspas_simples' and atual == "'" then
        if proximo == "'" then anexar(proximo); indice = indice + 1 else estado = 'normal' end
      elseif estado == 'aspas_duplas' and atual == '"' then
        if proximo == '"' then anexar(proximo); indice = indice + 1 else estado = 'normal' end
      elseif estado == 'identificador' and atual == '`' then
        if proximo == '`' then anexar(proximo); indice = indice + 1 else estado = 'normal' end
      end
    end

    indice = indice + 1
  end

  if estado ~= 'normal' and estado ~= 'comentario_linha' then
    return nil, 'script_nao_terminado:' .. estado
  end
  local ok, erro = concluir()
  if not ok then return nil, erro end
  if #instrucoes == 0 then return nil, 'script_sem_instrucoes' end
  return instrucoes
end

-- Executa sequencialmente e interrompe na primeira falha.
function VHubSQLScript.aplicar(script, executor)
  if type(executor) ~= 'function' then return false, 'executor_invalido' end
  local instrucoes, erro = VHubSQLScript.separar(script)
  if not instrucoes then return false, erro end

  for indice, instrucao in ipairs(instrucoes) do
    local ok, resultado = pcall(executor, instrucao, indice)
    if not ok or resultado == false then
      local detalhe = tostring(resultado or 'falha'):sub(1, 256)
      return false, ('instrucao_%d_falhou:%s'):format(indice, detalhe)
    end
  end
  return true, #instrucoes
end
