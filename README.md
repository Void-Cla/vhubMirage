# Mirage Framework — Arquitetura Base do Projeto

## Visão Geral

O Mirage é uma base proprietária para servidores FiveM/GTA RP construída sobre o ecossistema vRP, porém completamente reestruturada para remover limitações históricas de arquitetura, sincronização, persistência e escalabilidade encontradas nas versões tradicionais do framework.

O projeto abandona definitivamente o modelo legado baseado em Proxy/Tunnel como núcleo operacional e substitui essa abordagem por uma arquitetura orientada a kernel modular, baseada em eventos nativos do FiveM, controle de ownership via natives oficiais e gerenciamento de estado centralizado em VRAM.

A proposta do Mirage não é ser apenas uma “base editada de vRP”, mas sim um framework moderno de alta performance, preparado para ambientes de produção de larga escala, com foco extremo em:

* Performance real de runtime.
* Escalabilidade horizontal de módulos.
* Baixo consumo de resmon.
* Persistência segura.
* Segurança de eventos.
* Redução de tráfego de rede.
* Modularidade profissional.
* Compatibilidade gradual com legado vRP.
* Observabilidade e rastreabilidade.
* Estrutura limpa para equipes grandes.

O objetivo técnico final é manter o servidor operando abaixo de 0.2ms de resmon médio nos principais recursos core, mesmo em cenários de alta densidade de entidades, veículos e eventos concorrentes.

---

# Filosofia Arquitetural

## Kernel-Centric Architecture

O Mirage utiliza uma arquitetura baseada em Kernel.

O kernel atua como camada central responsável por:

* Registro de módulos.
* Controle de eventos.
* Rate limiting.
* Segurança de rede.
* Gerenciamento de permissões.
* Orquestração de persistência.
* APIs públicas.
* Ciclo de vida dos recursos.
* Controle transacional.
* Observabilidade.

Cada módulo possui responsabilidade isolada e comunicação desacoplada.

Nenhum módulo acessa diretamente estruturas internas de outro módulo.
Toda comunicação ocorre através de interfaces públicas registradas no kernel.

Isso elimina:

* Acoplamento circular.
* Dependências implícitas.
* Side effects silenciosos.
* Race conditions comuns do vRP.
* Dificuldade de manutenção.

---

# Estrutura Modular

## Separação Estrita por Responsabilidade

O Mirage segue rigorosamente os princípios:

* SOLID
* DRY
* KISS
* SRP
* Fail Fast
* Defensive Programming

Cada arquivo possui uma única responsabilidade.

Exemplo estrutural:

```txt
resources/
 └── [CORE]/
      └── mirage/
           ├── client/
           │    ├── core.lua
           │    ├── player.lua
           │    ├── vehicle.lua
           │    ├── inventory.lua
           │    └── modules/
           │
           ├── server/
           │    ├── kernel.lua
           │    ├── state.lua
           │    ├── auth.lua
           │    ├── vehicle.lua
           │    ├── inventory.lua
           │    ├── security.lua
           │    ├── persistence.lua
           │    ├── economy.lua
           │    ├── queue.lua
           │    └── modules/
           │
           ├── shared/
           │    ├── config.lua
           │    ├── logger.lua
           │    ├── utils.lua
           │    ├── enums.lua
           │    └── events.lua
           │
           ├── .claude/
           │    ├── agents/
           │    ├── instructions/
           │    ├── patterns/
           │    └── architecture/
           │
           └── metas/
                ├── roadmap.md
                ├── implementacao.md
                ├── auditoria.md
                └── plan.md
```

---

# Sistema de Persistência

## VRAM First Architecture

O Mirage opera sob a filosofia:

> VRAM é a verdade. SQL é persistência de segurança.

Toda leitura prioritariamente ocorre em memória.

O SQL não é tratado como fonte principal de runtime.

Fluxo:

```txt
Runtime -> VRAM -> Queue -> Batch SQL -> Persistência Física
```

Benefícios:

* Redução massiva de queries.
* Redução de IO.
* Menor latência.
* Escalabilidade.
* Menor lock de banco.
* Melhor throughput.
* Redução de stutter.

---

## Sistema de Fila Assíncrona

As operações de persistência não executam writes diretos síncronos.

Toda alteração crítica entra em uma fila de persistência.

A fila:

* Consolida operações.
* Remove writes redundantes.
* Agrupa queries.
* Executa batch SQL.
* Controla retry.
* Evita deadlocks.
* Controla flush por tempo e volume.

Modelo:

```txt
setState()
  -> enqueue()
      -> batch merge
          -> validation
              -> atomic sql save
```

---

## Transações Atômicas

Toda operação financeira, inventário, garagem ou sincronização crítica utiliza transações atômicas.

Fluxo:

```txt
begin()
  -> snapshot()
  -> mutation()
  -> validation()
  -> commit()
  -> persist()
```

Caso qualquer etapa falhe:

```txt
rollback()
```

Isso elimina:

* Dupes.
* Corrupção de estado.
* Race conditions.
* Inconsistência entre VRAM e SQL.
* Exploits financeiros.

---

# Nova Modelagem de Entidades

## Identidade Separada por Contexto

O Mirage abandona o conceito antigo de identidade única do vRP.

A arquitetura passa a utilizar:

```txt
user_id
character_id
veh_uid
session_id
instance_id
```

---

## user_id

Representa a conta global do jogador.

Responsável por:

* Autenticação.
* Licenciamento.
* Banimentos.
* Dados persistentes globais.
* Vinculação social.

---

## character_id

Representa personagens independentes.

Permite:

* Multi-char.
* Inventários separados.
* Progressões independentes.
* Estados persistentes isolados.
* Economias segmentadas.

---

## veh_uid

Nova entidade persistente exclusiva para veículos.

Cada veículo possui:

* UID único.
* Ownership persistente.
* Estado individual.
* Quilometragem.
* Histórico.
* Damage state.
* Fuel state.
* Metadata.
* Trunk state.
* Lock state.
* Network ownership.

Isso remove dependência de placa como identificador lógico.

---

# Sistema de Sincronização

## FiveM Native Authority Model

O Mirage utiliza o próprio modelo de autoridade de entidade do FiveM.

Não existe:

* Broadcast manual de posição.
* Sync loop artificial.
* Tunnel sync.
* Replicação customizada desnecessária.

Ownership é delegado utilizando:

```lua
NetworkSetEntityOwner()
```

O servidor trata apenas:

* Regras.
* Validação.
* Autoridade lógica.
* Segurança.

O cliente trata:

* Renderização.
* Interpolação.
* Predição.
* Simulação local.

Resultado:

* Menor tráfego.
* Menor CPU.
* Menor resmon.
* Melhor estabilidade.
* Menor desync.
* Melhor escalabilidade.

---

# Segurança

## Zero Trust Client Model

O cliente nunca é considerado confiável.

Todo payload recebido passa por:

* Sanitização.
* Type checking.
* Rate limiting.
* Auth validation.
* Ownership validation.
* Distance validation.
* Permission validation.
* State validation.

---

## Rate Limiter O(1)

Todos os net events possuem proteção obrigatória.

O sistema utiliza sliding window em O(1) com garbage collector interno.

Proteções:

* Spam.
* Flood.
* Trigger abuse.
* Packet abuse.
* Event overflow.
* RPC spam.

---

## Proteções Internas

O Mirage implementa:

* Anti-dupe.
* Anti-state corruption.
* Payload verification.
* Event signature validation.
* Session validation.
* Ownership reconciliation.
* Timeout recovery.
* Reentrancy protection.
* Safe await assertions.
* Export isolation.

---

# Performance

## Meta de Resmon

Meta final:

```txt
0.02 ~ 0.20ms
```

Mesmo sob:

* Alto volume de players.
* Frota massiva de veículos.
* Inventários persistentes.
* Eventos simultâneos.
* Sistemas complexos.

---

## Estratégias de Otimização

### Client

* Zero loops desnecessários.
* Tick adaptativo.
* Lazy loading.
* Cache local.
* Event-driven updates.
* Zone streaming.
* State bags.
* Thread pooling.

### Server

* Batch SQL.
* Cache em VRAM.
* Query deduplication.
* Queue pipeline.
* Async persistence.
* Ownership authority.
* Low allocation patterns.
* Memory reuse.

---

# Compatibilidade vRP

## Camada de Compatibilidade Progressiva

Apesar da reestruturação completa, o Mirage mantém compatibilidade controlada com ecossistema vRP.

Inclui:

* Proxy shim.
* Tunnel shim.
* Compat exports.
* Legacy adapters.
* Migration helpers.

Objetivo:

Permitir migração gradual de servidores antigos sem rewrite completo imediato.

---

# Multi Mundo / Instâncias

O Mirage implementa suporte nativo para múltiplos mundos.

Cada instância possui:

* Population isolada.
* Sync separado.
* Ownership independente.
* Regras locais.
* Streaming contextual.
* Controle de entidades.

Aplicações:

* Arenas.
* Interiores.
* Eventos.
* Matchmaking.
* Sessões privadas.
* Dimensões.

---

# Observabilidade

## Logger Estruturado

O sistema possui logger centralizado.

Nenhum módulo utiliza print bruto.

Logs incluem:

* Timestamp.
* Contexto.
* Módulo.
* Severity.
* Trace.
* Payload.
* Correlation ID.

---

## Métricas

Planejamento inclui:

* Profiling interno.
* Health checks.
* Tempo de flush.
* Tempo de query.
* Queue pressure.
* RTT médio.
* Ownership metrics.
* Tick metrics.
* Resmon analytics.

---

# Estrutura de Desenvolvimento Assistido por IA

## Integração com Claude Code

O projeto foi estruturado para desenvolvimento assistido por IA.

A pasta `.claude/` contém:

* Regras arquiteturais.
* Agentes especializados.
* Padrões de código.
* Fluxos de revisão.
* Convenções obrigatórias.
* Regras de performance.
* Checklists de segurança.
* Diretrizes de modularização.

Cada agente possui escopo delimitado.

Exemplo:

```txt
vhub_arquiteto
vhub_security
vhub_performance
vhub_sync
vhub_database
vhub_client
```

Objetivo:

Padronizar decisões técnicas e impedir degradação arquitetural durante evolução do projeto.

---

# Objetivo Final

O Mirage busca se tornar uma das arquiteturas mais modernas já desenvolvidas para FiveM no ecossistema brasileiro.

A proposta é entregar:

* Framework modular.
* Performance extrema.
* Segurança avançada.
* Sync nativo.
* Persistência robusta.
* Escalabilidade real.
* Base limpa para longo prazo.
* Estrutura preparada para equipes grandes.
* Compatibilidade gradual com legado.
* Engenharia de software de padrão profissional.

O foco principal do projeto não é quantidade de features, mas qualidade estrutural, previsibilidade operacional, estabilidade e capacidade de evolução contínua sem degradação da base.
