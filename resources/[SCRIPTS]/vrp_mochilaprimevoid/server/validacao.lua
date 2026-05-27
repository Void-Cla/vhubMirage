local VOID = VOID or {}
local Utils = VOID.utils
local Config = VOID.cfg

function VOID.verificarIntegridadeInventario(userId)
    local resultado = {
        erros = {},
        avisos = {},
        checksums_invalidas = {},
        serialkeys_duplicadas = {},
        itens_orfaos = {}
    }

    local itens = vRP.query('inventario/obter_todos_itens', { user_id = userId })

    local serialkeysMap = {}
    for _, item in ipairs(itens or {}) do
        if not Utils.validarSerialKey(item.serialkey) then
            resultado.erros[#resultado.erros + 1] = 'Serialkey invalida: ' .. tostring(item.serialkey)
        end

        local checksumEsperado = Utils.calcularChecksum(item.user_id, item.item_name, item.serialkey)
        if item.checksum and checksumEsperado ~= item.checksum then
            resultado.checksums_invalidas[#resultado.checksums_invalidas + 1] = item.serialkey
        end

        if serialkeysMap[item.serialkey] then
            resultado.serialkeys_duplicadas[#resultado.serialkeys_duplicadas + 1] = {
                serialkey = item.serialkey,
                ocorrencias = serialkeysMap[item.serialkey] + 1
            }
        end
        serialkeysMap[item.serialkey] = (serialkeysMap[item.serialkey] or 0) + 1
    end

    local tempoLimite = (Config and Config.seguranca and Config.seguranca.timeout_transacao) or 3600
    local pendentes = vRP.query('inventario/obter_transacoes_pendentes', {
        user_id = userId,
        tempo_limite = tempoLimite
    })

    if #pendentes > 0 then
        resultado.avisos[#resultado.avisos + 1] = 'Existem ' .. #pendentes .. ' transacoes pendentes'
    end

    return resultado
end

function VOID.recuperarFalhasInventario(userId)
    local problemas = VOID.verificarIntegridadeInventario(userId)

    if #problemas.serialkeys_duplicadas > 0 then
        for _, dup in ipairs(problemas.serialkeys_duplicadas) do
            vRP.execute('inventario/remover_serialkeys_duplicadas', {
                serialkey = dup.serialkey,
                manter_primeira = true
            })

            VOID.registrarAuditoria(Utils.gerarUUID(), userId,
                'AUTO: Removida serialkey duplicada ' .. dup.serialkey,
                { ocorrencias = dup.ocorrencias }
            )
        end
    end

    local tempoLimite = (Config and Config.seguranca and Config.seguranca.timeout_transacao) or 3600
    local pendentes = vRP.query('inventario/obter_transacoes_pendentes', {
        user_id = userId,
        tempo_limite = tempoLimite
    })

    for _, trans in ipairs(pendentes or {}) do
        local dados = Utils.jsonDecode(trans.dados_transacao) or {}
        if trans.tipo_operacao == 'comprar' and trans.status == 'pendente' then
            if dados.preco then
                vRP.giveMoney(userId, dados.preco)
                VOID.registrarAuditoria(trans.transaction_id, userId,
                    'AUTO: Transacao compra revertida (timeout)',
                    { preco = dados.preco }
                )
            end
        end

        vRP.execute('inventario/marcar_transacao_revertida', {
            transaction_id = trans.transaction_id
        })
    end

    return {
        serialkeys_duplicadas_removidas = #problemas.serialkeys_duplicadas,
        transacoes_revertidas = #pendentes
    }
end

return VOID