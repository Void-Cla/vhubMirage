local VOID = VOID or {}
local Config = VOID.cfg
local Const = VOID.const
local vRPPrime = VOID.interface

VOID.bausAbertos = VOID.bausAbertos or {}
VOID.bauCooldown = VOID.bauCooldown or {}

local function normalizarNomeBau(nome)
    if not nome then return nil end
    local str = tostring(nome)
    str = str:gsub('^%s+', ''):gsub('%s+$', '')
    return string.lower(str)
end

local function getPermissaoBauFaccao(chestName)
    if Config and Config.baus_faccao and Config.baus_faccao.permissoes then
        local perms = Config.baus_faccao.permissoes
        local normal = normalizarNomeBau(chestName)
        return perms[chestName] or (normal and perms[normal]) or nil
    end
    return nil
end

local function obterInfoBauFaccao(chestName)
    if not chestName then return nil end
    local normal = normalizarNomeBau(chestName)
    local perm = getPermissaoBauFaccao(chestName)
    local maxPeso = (perm and perm.capacidade) or (Config.baus_faccao and Config.baus_faccao.capacidade_padrao) or 50000
    local containerId = 'faccao_' .. (normal or tostring(chestName))
    return {
        nome = tostring(chestName),
        nome_normalizado = normal,
        permissao = perm,
        peso_max = maxPeso,
        container_id = containerId
    }
end

local function obterCooldownBau(tipo)
    if tipo == Const.TIPO_ARMAZENAMENTO.BAU_VEICULO then
        return (Config.bau_veiculo and Config.bau_veiculo.cooldown_acao_segundos)
            or (Config.baus_faccao and Config.baus_faccao.cooldown_acao_segundos)
            or 0
    end
    return (Config.baus_faccao and Config.baus_faccao.cooldown_acao_segundos) or 0
end

local function temJogadorProximo(source, raio)
    if not raio or raio <= 0 then return false end
    if not vRPclient or not vRPclient.getNearestPlayer then return false end
    local ok, player = pcall(vRPclient.getNearestPlayer, source, raio)
    if ok and player and player ~= 0 then
        return true
    end
    return false
end

local function notificar(src, tipo, msg)
    if VOID.notificar then
        VOID.notificar(src, tipo, msg)
        return
    end
    TriggerClientEvent('Notify', src, tipo or 'aviso', msg or '', (Config.notificacoes and Config.notificacoes.tempo_exibicao) or 5000)
end

local function setTrunkState(vnetid, aberto)
    if not vnetid then return end
    TriggerClientEvent('void_mochila_prime:trunkState', -1, vnetid, aberto == true)
end

local function podeUsarBauFaccao(source, user_id, chestName)
    if not user_id then return false, 'usuario_invalido' end

    if vRP.searchReturn then
        local ok, ret = pcall(vRP.searchReturn, source, user_id)
        if ok and ret then
            return false, 'em_busca'
        end
    end

    if Config and Config.baus_faccao and Config.baus_faccao.permissoes then
        local perm = getPermissaoBauFaccao(chestName)
        if not perm then
            return false, 'bau_invalido'
        end
        if perm.permissao and not vRP.hasPermission(user_id, perm.permissao) then
            return false, 'sem_permissao'
        end
    end

    return true
end

VOID.normalizarNomeBau = normalizarNomeBau
VOID.obterPermissaoBauFaccao = getPermissaoBauFaccao
VOID.obterInfoBauFaccao = obterInfoBauFaccao
VOID.podeUsarBauFaccao = function(user_id, source, chestName)
    return podeUsarBauFaccao(source, user_id, chestName)
end
VOID.validarCooldownBau = function(user_id, tipo)
    local cooldown = obterCooldownBau(tipo)
    if cooldown <= 0 then return true end

    local key = tostring(user_id) .. ':' .. tostring(tipo or 'bau')
    local agora = os.time()
    local ultimo = VOID.bauCooldown[key] or 0
    if agora - ultimo < cooldown then
        return false, cooldown - (agora - ultimo)
    end

    VOID.bauCooldown[key] = agora
    return true
end

function vRPPrime.checkIntPermissions(chestName)
    local source = source
    local user_id = vRP.getUserId(source)
    local ok = podeUsarBauFaccao(source, user_id, chestName)
    return ok == true
end

function vRPPrime.abrirBauVeiculo()
    local source = source
    local user_id = vRP.getUserId(source)
    if not user_id then return false end

    local vehicle, vnetid, placa, vname, lock, banned = vRPclient.vehList(source, 7)
    if not vehicle then return false end
    if lock and lock ~= 1 then return false end
    if banned then return false end

    local raio = (Config.bau_veiculo and Config.bau_veiculo.limite_proximidade) or Const.LIMITE_PROXIMIDADE_PADRAO
    if temJogadorProximo(source, raio) then
        notificar(source, 'negado', 'Voce esta muito proximo de alguem para abrir o bau.')
        return false
    end

    local owner_id = vRP.getUserByRegistration(placa)
    if not owner_id then return false end

    local containerId = 'veh_' .. owner_id .. '_' .. vname
    local maxPeso = vRP.vehicleChest and vRP.vehicleChest(vname) or (Config.bau_veiculo and Config.bau_veiculo.peso_padrao_por_veh) or 100

    VOID.bausAbertos[user_id] = {
        tipo = Const.TIPO_ARMAZENAMENTO.BAU_VEICULO,
        container_id = containerId,
        peso_max = maxPeso,
        nome = vname,
        vnetid = vnetid
    }

    setTrunkState(vnetid, true)

    return true
end

function vRPPrime.abrirBauFaccao(chestName)
    local source = source
    local user_id = vRP.getUserId(source)
    if not user_id or not chestName then return false end

    local okPerm, motivo = podeUsarBauFaccao(source, user_id, chestName)
    if not okPerm then
        return false
    end

    local raio = (Config and Config.baus_faccao and Config.baus_faccao.limite_proximidade) or Const.LIMITE_PROXIMIDADE_PADRAO
    if temJogadorProximo(source, raio) then
        notificar(source, 'negado', 'Voce esta muito proximo de alguem para abrir o bau.')
        return false
    end

    local info = obterInfoBauFaccao(chestName)
    if not info then return false end

    VOID.bausAbertos[user_id] = {
        tipo = Const.TIPO_ARMAZENAMENTO.BAU_FACCAO,
        container_id = info.container_id,
        peso_max = info.peso_max,
        nome = info.nome,
        nome_normalizado = info.nome_normalizado
    }

    return true
end

function vRPPrime.fecharBau()
    local source = source
    local user_id = vRP.getUserId(source)
    local bau = VOID.bausAbertos[user_id]
    if bau and bau.tipo == Const.TIPO_ARMAZENAMENTO.BAU_VEICULO and bau.vnetid then
        setTrunkState(bau.vnetid, false)
    end
    VOID.bausAbertos[user_id] = nil
    return true
end

AddEventHandler('vRP:playerLeave', function(user_id, source)
    VOID.bausAbertos[user_id] = nil
end)

AddEventHandler('vRP:playerSpawn', function(user_id, source, first_spawn)
    if Config and Config.seguranca and Config.seguranca.recuperacao_automatica then
        VOID.recuperarFalhasInventario(user_id)
    end
end)

RegisterCommand((Config.marketplace and Config.marketplace.comando) or 'market', function(source)
    TriggerClientEvent('void_mochila_prime:openMarket', source)
end)

RegisterCommand('inventario_relatorio', function(source, args)
    if source ~= 0 then return end
    local alvo = tonumber(args[1])
    local limite = tonumber(args[2]) or 20
    local linhas = alvo and VOID.obterRelatorioUsuario(alvo, limite) or VOID.obterRelatorioRecente(limite)
    print('[void_mochila_prime] Relatorio auditoria:')
    for _, linha in ipairs(linhas or {}) do
        print(string.format('#%s user:%s acao:%s data:%s', linha.id, linha.user_id or 'n/a', linha.acao or 'n/a', linha.data_criacao or 'n/a'))
    end
end)

RegisterCommand('inventario_teste', function(source, args)
    if source ~= 0 then return end
    local user_id = tonumber(args[1])
    local item = args[2] or 'maca'
    if not user_id then
        print('[void_mochila_prime] uso: inventario_teste <user_id> [item]')
        return
    end
    local src = vRP.getUserSource(user_id)
    if not src then
        print('[void_mochila_prime] usuario nao esta online.')
        return
    end

    local okAdd, errAdd = VOID.adicionarItemSeguro(user_id, item, 1, 'teste', VOID.const.TIPO_ARMAZENAMENTO.MOCHILA)
    if not okAdd then
        print('[void_mochila_prime] teste falhou ao adicionar: ' .. tostring(errAdd))
        return
    end

    local okRem, errRem = VOID.removerItemSeguro(user_id, item, 1, VOID.const.TIPO_ARMAZENAMENTO.MOCHILA)
    if not okRem then
        print('[void_mochila_prime] teste falhou ao remover: ' .. tostring(errRem))
        return
    end

    print('[void_mochila_prime] teste de transacao concluido com sucesso.')
end)

return VOID
