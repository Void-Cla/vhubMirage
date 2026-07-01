# Plano de Implementação: Ecossistema de Veículos e Handling (Padrão vhub)

**Autor:** Manus AI
**Data:** 28 de Junho de 2026

## 1. Visão Geral e Objetivos

Este documento detalha o plano de implementação para integrar e otimizar o ecossistema de veículos do servidor FiveM, incorporando as diretrizes de balanceamento físico (handling) descritas no documento de requisitos (`sss.txt`) e as ferramentas de balanceamento offline (`handling-balancer`). O objetivo é criar um sistema resiliente, seguro e de alta performance, alinhado com os padrões de qualidade da arquitetura `vhub`.

A premissa central de design é estabelecer um "skill gap" significativo nas corridas, onde o peso do veículo (`fMass`) e a tração (`fDriveBiasFront`, `fTractionCurveMax`) são matematicamente ancorados para punir erros de pilotagem e recompensar a precisão, evitando o efeito "pinball" de carros excessivamente leves.

## 2. Análise Arquitetural Atual

O ecossistema `vhub` atual é composto por múltiplos recursos interligados:

*   **`vhub_conce` (Concessionária):** Autoridade sobre a propriedade, criação e status dos veículos. Expõe exports críticos (`canOperate`, `isOwner`, `createVehicle`).
*   **`vhub_garage` (Garagem):** Gerencia o armazenamento, spawn, leilões e aluguéis. Depende fortemente do `vhub_conce` para validação de propriedade.
*   **`vhub_custom` (Customização/Mecânica):** Lida com modificações visuais (Bennys) e de performance (Oficina), além de reparos.
*   **`vhub_vehcontrol` (Controle de Veículos):** Gerencia o sistema de "Tiers" (categorias de performance), alocação de pontos de habilidade (handling dinâmico) e afinidade por tipo de pista.
*   **`vhub_racha` (Corridas):** Sistema de corridas com múltiplos modos (circuito, drag, drift), que se beneficia diretamente do balanceamento de handling.
*   **`handling-balancer` (Ferramenta Offline):** Utilitário Node.js para escanear, perfilar e gerar patches de handling (`catalog-patch.json`) baseados em regras matemáticas (arquétipos).

### 2.1. Oportunidades de Integração e Conflitos

A principal oportunidade reside na integração fluida entre o balanceamento estático (gerado pelo `handling-balancer` e validado no boot) e o balanceamento dinâmico (gerenciado pelo `vhub_vehcontrol` através de Tiers e alocação de pontos).

**Ponto de Atenção:** O `vhub_vehcontrol` já possui uma lógica de `handlingFromAlloc` que modifica parâmetros físicos em tempo real. É crucial garantir que essas modificações dinâmicas respeitem os limites (clamping) estabelecidos pelas regras de integridade do `sss.txt` para não quebrar a premissa de punição por peso e tração.

## 3. Plano de Implementação: O Motor de Integridade (Self-Healing)

Conforme exigido no `sss.txt`, implementaremos um serviço de validação e autocorreção no boot do servidor. Este serviço garantirá que nenhum veículo no banco de dados viole as regras de balanceamento, corrigindo anomalias automaticamente (Clamping).

### 3.1. Camada de Domínio (Regras de Negócio)

As regras matemáticas serão centralizadas em um módulo compartilhado, acessível tanto pelo validador de boot quanto pelo sistema de controle de veículos (`vhub_vehcontrol`).

```lua
-- vhub_conce/shared/handling_rules.lua (Novo Arquivo)
VehicleIntegrity = {}

VehicleIntegrity.Rules = {
    ['balanced'] = {
        fMass           = { min = 1300.0, max = 1450.0 },
        fDriveBiasFront = { min = 0.3,    max = 0.4 },
        fTractionMax    = { min = 1.8,    max = 2.2 }
    },
    ['muscle'] = {
        fMass           = { min = 1450.0, max = 1750.0 },
        fDriveBiasFront = { min = 0.0,    max = 0.1 },
        fTractionMax    = { min = 2.0,    max = 2.4 }
    },
    ['sport'] = {
        fMass           = { min = 1100.0, max = 1350.0 },
        fDriveBiasFront = { min = 0.0,    max = 0.3 },
        fTractionMax    = { min = 2.5,    max = 2.9 }
    },
    ['drift'] = {
        fMass           = { min = 1200.0, max = 1400.0 },
        fDriveBiasFront = { min = 0.0,    max = 0.0 },
        fTractionMax    = { min = 1.4,    max = 1.8 }
    }
}
```

### 3.2. Camada de Validação e Clamping

A lógica de validação será pura, sem dependências de banco de dados, facilitando testes unitários.

```lua
-- vhub_conce/shared/validator_service.lua (Novo Arquivo)
function VehicleIntegrity.ValidateAndCorrectHandling(vehicleData)
    local category = vehicleData.category
    local rules = VehicleIntegrity.Rules[category]
    local anomalies = {}
    local corrections = {}
    local hasViolations = false

    if not rules then
        table.insert(anomalies, string.format("Categoria inválida ou nula: '%s'", tostring(category)))
        return false, anomalies, corrections
    end

    local function evaluateAndClamp(field, value, min, max)
        if type(value) ~= 'number' then
            table.insert(anomalies, string.format("Campo '%s' corrompido ou nulo. Forçando valor mínimo seguro.", field))
            corrections[field] = min
            hasViolations = true
            return
        end

        if value < min then
            table.insert(anomalies, string.format("Campo '%s' abaixo do limite (%.2f). Corrigido para o mínimo (%.2f).", field, value, min))
            corrections[field] = min
            hasViolations = true
        elseif value > max then
            table.insert(anomalies, string.format("Campo '%s' acima do limite (%.2f). Corrigido para o máximo (%.2f).", field, value, max))
            corrections[field] = max
            hasViolations = true
        end
    end

    evaluateAndClamp('fMass', vehicleData.fMass, rules.fMass.min, rules.fMass.max)
    evaluateAndClamp('fDriveBiasFront', vehicleData.fDriveBiasFront, rules.fDriveBiasFront.min, rules.fDriveBiasFront.max)
    evaluateAndClamp('fTractionMax', vehicleData.fTractionMax, rules.fTractionMax.min, rules.fTractionMax.max)

    return not hasViolations, anomalies, corrections
end
```

### 3.3. Camada de Integração (Boot Service)

Este serviço rodará no `vhub_conce` (autoridade de veículos) durante a inicialização, utilizando `oxmysql` para consultas e atualizações dinâmicas.

```lua
-- vhub_conce/server/boot_service.lua (Novo Arquivo)
local function RunHandlingSanityCheckWithAutofix()
    print("^3[INTEGRIDADE] A iniciar verificação física com Autocorreção Ativa...^0")

    -- Nota: A tabela 'vehicles' precisa ter as colunas fMass, fDriveBiasFront, fTractionMax
    -- Caso os dados de handling base venham do catalog.lua, a validação deve ocorrer no carregamento do catálogo.
    -- Assumindo que os overrides de handling por veículo são salvos no banco:
    MySQL.Async.fetchAll('SELECT plate, category, fMass, fDriveBiasFront, fTractionMax FROM player_vehicles', {}, function(vehicles)
        if not vehicles or #vehicles == 0 then return end

        local totalVehicles = #vehicles
        local fixedVehicles = 0

        for i = 1, totalVehicles do
            local veh = vehicles[i]
            local isValid, anomalies, corrections = VehicleIntegrity.ValidateAndCorrectHandling(veh)

            if not isValid and next(corrections) then
                fixedVehicles = fixedVehicles + 1
                
                local sqlSetParts = {}
                local queryParams = { ['@plate'] = veh.plate }

                for field, correctedValue in pairs(corrections) do
                    table.insert(sqlSetParts, string.format("%s = @%s", field, field))
                    queryParams['@' .. field] = correctedValue
                end

                local sqlQuery = string.format("UPDATE player_vehicles SET %s WHERE plate = @plate", table.concat(sqlSetParts, ", "))

                MySQL.Async.execute(sqlQuery, queryParams, function(rowsChanged)
                    if rowsChanged == 0 then
                        print(string.format("^1[ERRO CRÍTICO] Falha ao persistir correção do veículo %s no banco.^0", veh.plate))
                    end
                end)
            end
        end
        
        if fixedVehicles > 0 then
            print(string.format("^3[INTEGRIDADE] Diagnóstico Concluído. %d de %d veículos foram retificados automaticamente.^0", fixedVehicles, totalVehicles))
        else
            print(string.format("^2[INTEGRIDADE] Sucesso absoluto. Todos os %d veículos cumprem as regras de handling.^0", totalVehicles))
        end
    end)
end

AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        SetTimeout(1500, RunHandlingSanityCheckWithAutofix)
    end
end)
```

## 4. Integração com o `handling-balancer` (Offline)

O `handling-balancer` é a ferramenta primordial para garantir que os arquivos `.meta` originais dos mods estejam dentro dos arquétipos antes mesmo de entrarem no servidor.

### 4.1. Fluxo de Trabalho Recomendado

1.  **Importação de Mods:** Novos veículos são adicionados à pasta de mods.
2.  **Scan e Profiling:** Executar `node balance.js scan` para ler os `.meta` e gerar o perfil de cada veículo.
3.  **Aplicação de Arquétipos:** O balancer cruza os dados com `config/archetypes.json` (ex: `rwd_light`, `awd_heavy`).
4.  **Geração de Patch:** Executar `node balance.js plan` e `node balance.js apply` para gerar o `catalog-patch.json`.
5.  **Integração no Servidor:** O `catalog-patch.json` é consumido pelo `vhub_conce/shared/catalog.lua` para definir a base de performance (Tier, Budget, Base Handling) de cada modelo.

### 4.2. Sincronização de Regras

As regras definidas no `sss.txt` (ex: Sweet Spot de Massa 1.450kg - 1.750kg) devem ser refletidas no `config/archetypes.json` do balancer para garantir consistência entre a ferramenta offline e o validador online.

## 5. Ajustes no `vhub_vehcontrol` (Handling Dinâmico)

O `vhub_vehcontrol` permite que os jogadores ajustem o handling através de pontos (alloc). É imperativo que a função `TR.handlingFromAlloc` (em `tier_rules.lua`) seja modificada para respeitar os limites (clamping) definidos pelo `VehicleIntegrity.Rules`.

**Modificação Necessária em `vhub_vehcontrol/shared/tier_rules.lua`:**

Ao calcular os novos valores de handling baseados na alocação do jogador, o resultado final deve passar pela função `VehicleIntegrity.ValidateAndCorrectHandling` (ou uma variação dela que atue apenas sobre os limites, sem gerar logs de anomalia) antes de ser aplicado ao veículo no cliente. Isso garante que um jogador não consiga, através de customização, transformar um "Muscle" em um carro com peso de "Sport", quebrando o balanceamento da categoria.

## 6. Resumo de Entregáveis e Próximos Passos

1.  **Criar Módulos de Integridade:** Implementar `handling_rules.lua`, `validator_service.lua` e `boot_service.lua` no `vhub_conce`.
2.  **Atualizar Esquema do Banco de Dados:** Garantir que a tabela de veículos possua as colunas necessárias para armazenar os overrides de handling (`fMass`, `fDriveBiasFront`, `fTractionMax`), caso o design exija persistência por veículo e não apenas por modelo no catálogo.
3.  **Sincronizar Balancer Offline:** Atualizar `archetypes.json` no `handling-balancer` com os valores exatos do `sss.txt`.
4.  **Refatorar `vhub_vehcontrol`:** Injetar a validação de limites no cálculo de handling dinâmico (`TR.handlingFromAlloc`).
5.  **Testes de Estresse:** Realizar testes com dados corrompidos no banco para validar a eficácia do sistema de Self-Healing no boot.

Este plano garante que a visão de design de jogo (punição por peso e tração assimétrica) seja implementada de forma robusta, sem brechas técnicas, mantendo a alta performance e a separação de responsabilidades exigidas pela arquitetura `vhub`.
