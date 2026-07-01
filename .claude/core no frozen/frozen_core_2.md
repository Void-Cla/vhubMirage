# frozen_core_2.md
## Plano de Remediação do CORE — Caminho para descongelar o v1.0 e estabelecer o v2.0

> **Documento técnico de engenharia.** Referência interna do projeto vHub Mirage.
> **Escopo:** auditar toda falha, gap, lacuna, anti-padrão, decisão pragmática mal-pensada,
> violação de contrato ou semântica incorreta identificada no ecossistema veicular, e
> propor solução sólida, segura, server-side por padrão, com exports para tudo (anti-redundância),
> minimizando uso de rede / CPU / GPU / ms.
> **Linguagem:** Português brasileiro (PT-BR), código e identificadores em inglês.
> **Princípio norteador:** "colocar para funcionar" ≠ "fazer funcionar onde deveria e como deveria".
> Toda solução aqui proposta visa restaurar a intenção original da arquitetura, sem gambiarras.

---

## 0. Premissas, Princípios e Regras de Ouro (re-validadas)

Antes de qualquer proposta, fixamos as regras que **nenhuma solução pode violar**. Toda
remediação neste documento éValidada contra esta lista.

### 0.1 Regras imutáveis

| # | Regra | Justificativa |
|---|-------|---------------|
| **R1** | **Server-side por padrão.** Toda decisão crítica (estado, posse, dinheiro, validação) é tomada no server. Client só propõe, server dispõe. | Anti-cheat fundamental. Client é hostil por definição. |
| **R2** | **Exceções a R1 — apenas o estritamente necessário.** Replay, animações, partículas, som local, câmera, renderização NUI, input mapping, predição de movimento local. | Coisas que NÃO podem ser centralizadas sem degradar UX. |
| **R3** | **Tudo tem export.** Toda funcionalidade pública de um recurso é exposta via `exports.<resource>:<fn>()`. Recurso sem export é recurso morto ou duplicado. | Anti-redundância: outro recurso pode aplicar regra de negócio adicional sem reimplementar. |
| **R4** | **Um dono por dado.** Para cada campo persistente, existe exatamente UM escritor autorizado. Todos os demais são leitores. | Lei do escritor único (L-04 do manual). |
| **R5** | **Estado de entidade para todos = State Bag.** Eventos discretos/momentâneos = `TriggerClientEvent`. Estado contínuo (posição, fuel, health) NUNCA via broadcast `-1`. | Bandwidth + atomicidade. State Bags são delta-synced pela engine. |
| **R6** | **Replay-safe por padrão.** Resource restart não pode causar perda de estado crítico. Handlers institucionais (`playerSpawn`, `characterLoad`) têm replay-guard. | L-17 do manual. |
| **R7** | **Falha graciosa.** Toda fronteira externa (export de outro recurso, callback NUI, evento de outro resource) é envolta em `pcall`. Erro em um recurso não pode derrubar outro. | L-09 do manual (resiliência). |
| **R8** | **Orçamento é contrato.** Toda thread/loop declara seu budget (Hz, ms). Sem loops infinitos sem sleep. | L-18 do manual (performance). |
| **R9** | **Fonte única de nomes.** Eventos declarados em `shared/events.lua` do recurso. Zero literais hardcoded de evento. | L-19 do manual (manutenibilidade). |
| **R10** | **Nenhum `print()` em produção.** Logs via `vHub.Logger` (com níveis, rotação, sink configurável). | L-08 do manual. |
| **R11** | **PT-BR em comentários, logs e NUI.** Identificadores em inglês. | L-08/L-10 do manual. |
| **R12** | **Toda mutação de estado é auditada.** Toda escrita em prontuário/VRAM registra `source`, `actor`, `ts`, `field`, `before`, `after`. | Forensia + debug + rollback. |
| **R13** | **Anti-cheat em camadas.** Validação client (UX) + validação server (autoritativa) + audit log (forensia). Nunca apenas client. | Defesa em profundidade. |
| **R14** | **Idempotência.** Re-executar a mesma operação produz o mesmo estado. Sem side-effects surpresa em retry. | Tolerância a falhas de rede. |
| **R15** | **Backward-compat com deprecation path.** Mudanças de contrato quebram apenas com aviso prévio, versão deprecada funcionando por N releases, e migration script. | Não quebrar scripts terceiros. |

### 0.2 Princípios de performance

- **P1 — Single-pilot-channel:** quando um veículo tem motorista, o server fala **apenas com o motorista** sobre estado do veículo (fuel, handling, telemetry). Passageiros recebem apenas `vh_*` State Bags (read-only, lazy-synced pela engine). Reduz tráfego server→clients em N× onde N = passageiros.
- **P2 — Delta sync:** enviar apenas mudanças, nunca snapshot completo. State Bags já fazem isso nativamente; eventos manuais devem seguir o padrão.
- **P3 — Rate-limit por entidade:** cada placa tem rate-limit por tipo de evento (telemetria 4Hz, fuel 0.25Hz, position 1Hz). Evita flooding.
- **P4 — Lazy load:** dados só são carregados quando necessário. Prontuário não é pré-carregado para todos os veículos em boot — apenas quando `getVehicleState` é chamado.
- **P5 — Cache com TTL + LRU:** todo cache tem eviction. Sem cache cresce indefinidamente.
- **P6 — Batch SQL:** mutations são enfileiradas e executadas em batch atômico (BATCH_MAX=800). Sem write-through síncrono para cada mutation.

### 0.3 Princípios arquiteturais

- **A1 — CORE mínimo e estável.** Quanto menor o CORE, mais estável o contrato. CORE não tem lógica de negócio — apenas infraestrutura.
- **A2 — Domínios auto-contidos.** Cada recurso (vhub_garage, vhub_conce, vhub_custom, etc.) é dono de seu domínio. Sem overlap.
- **A3 — Delegação explícita.** Quando recurso A precisa de funcionalidade de B, A chama `exports.B:fn()`. Nunca reimplementa.
- **A4 — Contratos explícitos.** Toda interação entre recursos é via exports (síncrono) ou eventos declarados (assíncrono). Sem globals implícitas.
- **A5 — Failure isolation.** Um recurso quebrado não derruba o ecossistema. Dependências declaradas no fxmanifest, mas soft-deps via `pcall`.

---

## PARTE I — AUDITORIA COMPLETA (todas as falhas, por responsabilidade)

Cada falha é numerada (`F-XXX`), classificada por severidade (CRÍTICO / ALTO / MÉDIO / BAIXO),
e descrita com: sintoma, causa raiz, consequência, e referência ao código fonte quando aplicável.

### 1. Camada de Estado e Persistência (CORE/vhub)

Esta camada concentra a maioria das falhas críticas. O CORE foi FROZEN v1.0 com bugs
conhecidos, e a solução histórica foi desviar responsabilidade para vhub_conce — uma
gambiarra arquitetural que funcionou, mas matou a ideia original de "comunicação única
servidor↔piloto" que reduziria carga de processamento dos passageiros.

#### F-001 — Handlers de veículo DORMENTES (ADR #24)
- **Severidade:** CRÍTICO
- **Sintoma:** Os 5 net events de veículo (`vHub:vSpawned`, `vHub:vDespawned`,
  `vHub:vEnter`, `vHub:vLeave`, `vHub:vState`) estão registrados com handler NO-OP
  (`_vhDisarmed`). O `client/vehicle.lua` envia `vHub:vState` a 4Hz que é silenciosamente
  descartado pelo server.
- **Causa raiz:** Em 2026-Q1 foi identificado que um atacante poderia forjar `vEnter` com
  netID da vítima, levando o CORE a executar `NetworkSetEntityOwner` em entidade alheia —
  sequestro de posição do veículo. Como o CORE estava FROZEN, a solução foi desarmar os
  handlers.
- **Consequência:**
  - Pipeline de vehicle state do CORE está **efetivamente desligado em runtime**.
  - State Bags `vh_vehicle_state`, `vh_vehicle_driver`, `vh_fuel`, `vh_eng`, `vh_body`,
    `vh_odo`, `vh_tune`, `vh_on` **nunca são escritas pelo CORE em runtime**.
  - `Veh:register` ainda funciona, mas `Veh:onSpawned`/`onDespawned`/`onEnter`/`onLeave`/
    `onStateUpdate` **nunca são chamados** pelo fluxo natural.
  - Eventos `vHub:vehicleSpawned`, `vHub:vehicleEnter`, `vHub:vehicleLeave`,
    `vHub:vehicleDespawned`, `vHub:vehicleFuelEmpty`, `vHub:passengerMode` são emitidos
    dentro de `Veh:*` — logo, também ficam sem emitter.
  - Recursos que precisam de vehicle state precisam chamar
    `exports.vhub:getVHub().Vehicle` diretamente ou ter pipeline próprio (caso vhub_conce).
- **Localização:** `server/boot.lua` L171-178 (comentário "NUNCA reanimar"), `server/vehicle.lua`
  (handlers `_vhDisarmed`), `client/vehicle.lua` (envio a 4Hz desperdiçado).
- **Referência:** ADR #24, análise `02_CORE_vhub.md` §13.1.

#### F-002 — README desatualizado em `_invoker_allowed`
- **Severidade:** MÉDIO
- **Sintoma:** `readme.md` Seção 13 diz: "Se `trusted_resources` está vazio, qualquer
  resource pode chamar exports sensíveis." **Falso** desde hotfix N0-2.
- **Causa raiz:** Hotfix aplicado sem atualizar documentação.
- **Consequência:** Administradores que seguem o README não populam
  `vHub.cfg.trusted_resources` e todos os exports privilegiados retornam `false`
  silenciosamente em produção.
- **Localização:** `readme.md` Seção 13 vs `server/auth.lua` L-something (`if not trust or
  next(trust) == nil then return false`).

#### F-003 — `_defaults` de `shared/config.lua` é essencialmente morto
- **Severidade:** ALTO
- **Sintoma:** `mergeConfig` é exportado mas **nunca chamado** pelo `bootstrap.lua`. O
  `criar_config()` constrói a config do zero a partir de convars, deixando vários campos
  como `nil` em produção.
- **Causa raiz:** Refactor do bootstrap não propagou a chamada.
- **Consequência:** Campos como `trusted_resources`, `max_ping`, `veh_state_hz`,
  `max_speed_kmh`, `lang.banned` ficam `nil`. Recursos que dependem destes defaults
  quebram silenciosamente ou usam fallback inline inconsistente.
- **Localização:** `shared/config.lua:57-67` (`_defaults`), `bootstrap.lua:criar_config`.

#### F-004 — `fuel_rate` — defaults diferentes entre arquivos
- **Severidade:** BAIXO
- **Sintoma:** `shared/config.lua:_defaults.fuel_rate = 0.01` vs
  `bootstrap.lua:criar_config().fuel_rate = 0.005` vs `vehicle.lua:onStateUpdate` fallback
  `0.005`. Efetivo: `0.005`.
- **Causa raiz:** Default mudou mas `_defaults` não foi atualizado.
- **Consequência:** Confusão em leitura de código. Override parcialmente inútil.

#### F-005 — `max_speed_kmh` — defaults diferentes
- **Severidade:** BAIXO
- **Sintoma:** `_defaults.max_speed_kmh = 400` vs `vehicle.lua` fallback `350`. Efetivo:
  `350` (pois `criar_config` não seta o campo).

#### F-006 — KNOWN MINOR LEAK em `bootstrap.lua:Driver:_executar`
- **Severidade:** BAIXO
- **Sintoma:** `SetTimeout(15000, function() resolver(nil, "timeout_db") end)` mantém a
  closure viva por 15s mesmo se a query resolver antes.
- **Causa raiz:** Sem API cancelável nativa no CitizenFX.
- **Consequência:** Pico transitório de heap. Aceitável hoje, mas em alta carga pode
  degradar.

#### F-007 — `vHub:passengerMode` não registrado no client
- **Severidade:** BAIXO
- **Sintoma:** `Veh:onEnter` e `Veh:onLeave` chamam `vHub.Kernel:emit(src, "vHub:passengerMode",
  plate, bool)` mas o evento não tem `RegisterNetEvent` nem handler no client.
- **Consequência:** Mesmo se os handlers fossem reanimados, o evento seria perdido.
  Hoje é irrelevante (F-001 dispara primeiro), mas precisa ser corrigido junto com a
  remediação de F-001.

#### F-008 — `vehicleStateLoad` emitido apenas em `Veh:onEnter` (dorminte)
- **Severidade:** ALTO
- **Sintoma:** `client/vehicle.lua` registra handler para `vHub:vehicleStateLoad`
  (aplica fuel/engine/body ao veículo local), mas o emit acontece em `Veh:onEnter` —
  que nunca é chamado.
- **Consequência:** Estado físico do veículo não é aplicado pelo CORE. Workaround: cada
  recurso aplica seu próprio estado (vhub_garage seta fuel/health no spawn, vhub_vehcontrol
  seta handling, vhub_nitro seta nitro). Duplicação de lógica.

#### F-009 — Posição de spawn hard-coded no fallback
- **Severidade:** BAIXO
- **Sintoma:** `client/bootstrap.lua` L6: `local SPAWN_POS = { x = -538.70, y = -214.91,
  z = 37.65, h = 0.0 }`. Em servidores com spawn customizado, o fallback pode colocar o
  jogador na posição errada por ~500ms antes de `vhub_player_state` aplicar a posição
  correta.
- **Causa raiz:** Default hardcoded para garantir que o player não caia no vazio.
- **Solução:** Ler spawn position de config central (convar ou arquivo de config do
  vhub_player_state).

#### F-010 — Transações in-memory ≠ SQL atômico
- **Severidade:** ALTO
- **Sintoma:** `State:begin/commit/rollback` garante consistência de VRAM, mas as ops SQL
  vão para o batch e são executadas depois. Se o servidor crashar entre commit e flush,
  há perda.
- **Mitigação atual:** Flush emergencial em `onResourceStop` — não cobre `kill -9`.
- **Consequência:** Pode haver divergence entre VRAM (memory) e SQL após crash.
- **Solução proposta:** Implementar WAL (Write-Ahead Log) em arquivo — toda mutation é
  escrita no WAL antes de ser aplicada na VRAM. Em boot, replay do WAL.

#### F-011 — Batch contamination cross-player — resolvido mas com trade-off
- **Severidade:** MÉDIO
- **Sintoma:** Originalmente `Driver:batch` usava `oxmysql:transaction([op1, op2, ..., opN])`
  — uma falha em uma op revertia TODAS. Agora usa `api:update` isolado por op.
- **Trade-off:** Atomicidade SQL perdida; isolamento ganhou prioridade.
- **Consequência:** Para dados que precisam de atomicidade real (transferência de dinheiro),
  o chamador deve usar `begin/commit` de VRAM e aceitar que a persistência SQL pode chegar
  em flushes diferentes.
- **Solução proposta:** Adicionar modo `atomic: true` no `Driver:batch` que reabilita a
  transação SQL quando o chamador declara que quer atomicidade.

#### F-012 — `assertThread` apenas nos getters
- **Severidade:** BAIXO
- **Sintoma:** Getters chamam `assertThread`, setters não.
- **Causa raiz:** Setters não precisam (só enfileiram op no batch, sem Await).
- **Consequência:** Inconsistência com documentação ("todos exigem
  Citizen.CreateThread"). Não é bug, mas é doc drift.
- **Solução:** Atualizar documentação OU adicionar `assertThread` nos setters (mais caro,
  mas consistente).

#### F-013 — VRAM não tem TTL nem eviction
- **Severidade:** ALTO
- **Sintoma:** Dados em `_mem` **nunca expiram por tempo**. `Auth:disconnect` não limpa a
  VRAM (intencional: dados podem ser acessados por admin offline).
- **Consequência:** Para servidores com 10.000+ jogadores únicos por dia, a VRAM cresce
  linearmente. Memory leak gradual.
- **Solução proposta:** Implementar eviction LRU + TTL configurável. Hot keys
  (`ban.active`, `whitelist`, `permissions`) marcadas como non-expirable. Resto com TTL
  de 1h após último acesso.

#### F-014 — `print()` em `auth.lua`
- **Severidade:** BAIXO (violação de regra)
- **Sintoma:** `auth.lua` L174, L178, L184, L220 têm `print(...)`.
- **Solução:** Substituir por `vHub.Logger:debug(...)`.

#### F-015 — `print()` em `boot.lua`
- **Severidade:** BAIXO (violação de regra)
- **Sintoma:** `boot.lua` L80 tem `print(...)`.
- **Solução:** Substituir por `vHub.Logger:debug(...)`.

#### F-016 — Clampagem de odômetro suspeita em `vehicle.lua:onStateUpdate`
- **Severidade:** BAIXO
- **Sintoma:** `local applied = math.min(odometer_delta, math.max(0.0001, max_delta), 0.5)`.
  O `0.5` (km/tick) é um teto absoluto que parece amplo demais. A 350km/h com
  `veh_state_hz = 4`, max_delta ≈ 0.024 km/tick. O 0.5 nunca é atingido em condições
  normais — mas em edge cases (teleport, glitch) pode mascarar bugs.
- **Solução:** Revisar o limite. Possivelmente remover o 0.5 absoluto e confiar apenas em
  `max_delta` derivado da velocidade.

#### F-017 — `validar_config` exportado mas nunca usado
- **Severidade:** BAIXO
- **Sintoma:** `shared/config.lua` L57-67 define `vHub.validateConfig(cfg)` que retorna
  `(bool, errs)`. Não é chamado em nenhum lugar do CORE.
- **Solução:** Chamar em `boot.lua` pós-`criar_config`. Falhar boot se config inválida
  (fail-fast).

#### F-018 — Schema migration MEDIUMBLOB → BLOB não automatizada
- **Severidade:** BAIXO
- **Sintoma:** `schema.sql` L13-25 documenta que `CREATE TABLE IF NOT EXISTS` NÃO altera
  tipo de coluna existente. Migração requer `ALTER TABLE` manual.
- **Solução:** Adicionar migration step em `aplicar_schema` que verifica tipo atual e
  aplica `ALTER` se necessário (com warning se dados forem grandes).

#### F-019 — Estado do `client/vehicle.lua` — envia mas ninguém escuta
- **Severidade:** ALTO (bandwidth desperdiçado)
- **Sintoma:** Loop adaptativo envia `vHub:vState` a 0.5/1/4Hz. Handler server é NO-OP.
  Todo esse tráfego é desperdiçado.
- **Consequência:** Consumo de banda + CPU sem efeito. Em servidor com 200 players
  dirigindo, são ~800 eventos/seg de lixo.
- **Solução:** Desativar o loop no client até que o CORE reanime os handlers (F-001).
  Sinalizar via State Bag `vh_core_active` para o client saber se deve enviar ou não.

#### F-020 — `boot.lua` `vHub:savePos` removido sem migration clara
- **Severidade:** BAIXO
- **Sintoma:** Persistência de posição foi delegada ao `vhub_player_state`. O CORE só
  persiste `last_pos` em `vd.state.last_pos`.
- **Status:** Está OK (delegação explícita), mas merece nota no changelog do CORE.

#### F-021 — BLOB com blindagem `b64:` (hotfix 2026-06-11)
- **Severidade:** ALTO (sintoma de bug mais profundo)
- **Sintoma:** BLOBs são prefixados com `b64:` porque msgpack binário era MANGLED na
  fronteira Lua→JS.
- **Causa raiz:** Bug no serializer do CitizenFX ou incompatibilidade de encoding entre
  Lua 5.4 e o NUI.
- **Consequência:** BLOBs ficam 33% maiores (base64 overhead). Decodificação em cada
  leitura adiciona latência.
- **Solução proposta:** Investigar bug raiz. Se for CitizenFX, abrir issue. Se for
  código próprio, substituir por serializer correto. Workaround só deve existir com
  data de remoção.

#### F-022 — `trusted_resources` não populado por default
- **Severidade:** ALTO
- **Sintoma:** Em instalação nova, `vHub.cfg.trusted_resources` está vazio. Todos os
  exports privilegiados retornam `false` silenciosamente.
- **Consequência:** Recursos como vhub_conce, vhub_garage, vhub_custom não conseguem
  mutar estado. Bug report "nada funciona" sem mensagem de erro clara.
- **Solução proposta:** Boot valida `trusted_resources` e WARN no console se vazio.
  Sugere lista padrão (vhub_conce, vhub_garage, vhub_custom, vhub_vehcontrol, vhub_nitro,
  vhub_racha, vhub_admin). Admin deve confirmar explicitamente.

#### F-023 — Decisão pragmática "gambiarra que deu certo"
- **Severidade:** CRÍTICO (metodológico)
- **Sintoma:** Em vez de corrigir o bug raiz (vh_vehicle_data não persistia), foi criado
  um sistema paralelo (vhub_vehicle_state no vhub_conce) que funciona.
- **Causa raiz:** Pressão de tempo. CORE FROZEN não podia ser patcheado.
- **Consequência:**
  - Ideia original de "comunicação única servidor↔piloto" foi morta — agora cada recurso
    fala com cada recurso.
  - Passageiros recebem broadcasts que não precisariam receber.
  - Lógica de estado de veículo está fragmentada entre CORE (morto), vhub_conce (ativo),
    vhub_garage (relay), vhub_legacyfuel (relay).
  - Manutenibilidade degradada — mudar uma regra requer tocar 3+ arquivos.
- **Solução proposta (plano de remediação completo na PARTE II):** Reativar o CORE com
  gate de segurança correto, migrar vhub_conce para usar CORE exports, manter vhub_vehicle_state
  como cache SQL do CORE (não como fonte de verdade alternativa).

---

### 2. Camada de Identidade & Prontuário (vhub_conce)

#### F-024 — `vHub:vehicleCommitted` reservado mas NUNCA emitido
- **Severidade:** ALTO
- **Sintoma:** `events.lua:21` declara o evento, mas `vstate.lua:save` não faz
  `TriggerEvent`.
- **Consequência:** Consumers precisam pollar `getVehicleState` para detectar mudanças.
  Recursos como vhub_vehcontrol ficam com handling stale quando player compra peça sem
  reabrir a ficha.
- **Solução proposta:** Emitir `vHub:vehicleCommitted(plate, source, fields_changed)` ao
  final de cada `saveVehicleState` bem-sucedido. Listeners reagem em vez de pollar.

#### F-025 — `vhub_vehicles.customization` (LONGTEXT) DEPRECATED mas não droppada
- **Severidade:** MÉDIO
- **Sintoma:** Coluna `customization LONGTEXT` ainda presente no schema mas nunca lida/escrita.
- **Solução:** Drop em migration v2.0 com script de backup.

#### F-026 — Cache VRAM local `_cache` sem GC
- **Severidade:** MÉDIO
- **Sintoma:** `vstate.lua` mantém `_cache[plate]` em memory que cresce indefinidamente.
- **Solução:** Mesma solução de F-013 — LRU + TTL.

#### F-027 — `test_drive_segundos = 9999` (~2h47min) e `fator_test_drive = 0.00`
- **Severidade:** ALTO (vetor de abuso)
- **Sintoma:** Config default permite test drive de quase 3 horas, grátis.
- **Causa raiz:** Config de dev que foi para produção.
- **Solução:** Defaults realistas: `test_drive_segundos = 300` (5 min), `fator_test_drive = 0.10`
  (10% do preço/hora).

#### F-028 — `vstate.lua` é workaround, não solução definitiva
- **Severidade:** CRÍTICO (metodológico, relacionado a F-023)
- **Sintoma:** vhub_conce assumiu função do CORE. Estado de veículo persiste em
  vhub_vehicle_state em vez de vh_vehicle_data.
- **Status:** Documentado e funcional, mas arquiteturalmente incorreto. Prontuário
  deveria ser uma camada sobre o CORE, não uma substituição.
- **Solução proposta:** Ver PARTE II — Fase 2 (migrar vhub_conce para usar CORE exports).

#### F-029 — `reconcileOrphans()` nunca roda no boot do conce
- **Severidade:** MÉDIO
- **Sintoma:** Depende do garage disparar pós-DDL. Se o garage não sobe, órfãos se
  acumulam.
- **Solução:** `reconcileOrphans()` no próprio boot do conce.

#### F-030 — Backfill de collation em todo boot
- **Severidade:** BAIXO
- **Sintoma:** `ensureSchema` faz `SELECT TABLE_COLLATION FROM information_schema` +
  `ALTER TABLE` se divergente. Em DB grande, o `ALTER` é custoso.
- **Solução:** Cache do resultado da checagem em arquivo. Só re-verificar se hash do
  schema mudar.

#### F-031 — Hardcoded `'vhub_garage:doDespawn'` em `vhub_conce/server/core.lua:162`
- **Severidade:** MÉDIO (violação L-19)
- **Sintoma:** Conce aciona evento client do garage diretamente. Se garage não está
  rodando, evento é silenciosamente descartado. Acoplamento implícito.
- **Solução:** Declarar em `shared/events.lua`. Melhor ainda: usar State Bag
  `vh_despawn_pending` que o garage observa.

#### F-032 — `vhub_custom` e `vhub_vehcontrol` mantêm índice de catálogo independente
- **Severidade:** MÉDIO
- **Sintoma:** Ambos constroem `buildCatalogIndex` lowercase. Se catálogo muda em
  hot-reload, ambos precisam re-cache, mas nenhum invalida explicitamente.
- **Solução:** Export `vhub_conce:getCatalogIndex()` centralizado. Demais recursos
  consultam, não constroem.

#### F-033 — `vhub_custom` não tem `server/exports.lua`
- **Severidade:** ALTO (violação R3)
- **Sintoma:** `PLANO.md §2` prevê API pública read-only (getTier preview, etc.) mas não
  foi implementada.
- **Consequência:** Outro recurso não consegue chamar `vhub_custom` sincronamente. Só via
  eventos de rede (assíncrono, frágil).
- **Solução:** Criar `server/exports.lua` com API read-only (getMods, canModify, getTier,
  getVehicleSheetPreview).

#### F-034 — `vhub_custom/client/zones.lua:81` pega veículo errado em zona densa
- **Severidade:** MÉDIO
- **Sintoma:** `GetClosestVehicle(pPos.x, pPos.y, pPos.z, 8.0, 0, 70)` — `0` é model hash
  (qualquer modelo), `70` é flag (carros+motos+...). Pode pegar veículo errado.
- **Solução:** Validar "veículo mais próximo é do player" via placa no prontuário.

#### F-035 — NUI sem timeout de inatividade
- **Severidade:** BAIXO
- **Sintoma:** Se server cair e client não receber `CONFIRM`, NUI fica presa até
  Cancelar/ESC.
- **Solução:** Timeout client-side de 30s sem resposta do server → fecha NUI + notifica
  erro.

#### F-036 — 4 literais hardcoded de eventos no vhub_custom
- **Severidade:** MÉDIO (violação L-19)
- **Sintoma:** `'vhub_custom:server:mecTowDone'`, `'vhub_vehcontrol:recalibrate'`,
  `'vhub_vehcontrol:recalDone'`, `'vhub_garage:doDespawn'` (no conce) hardcoded.
- **Solução:** Mover para `shared/events.lua` de cada recurso.

---

### 3. Camada de Lifecycle (vhub_garage)

#### F-037 — `active_rental` sempre 0
- **Severidade:** MÉDIO
- **Sintoma:** Status `'rental'` declarado em ENUM mas nunca escrito. Veículos alugados
  recebem `status='garage'` + `rented_until`.
- **Consequência:** `adminStats` reporta `active_rental = 0` sempre. Admin não vê aluguel
  ativo.
- **Solução:** Escrever `status='rental'` em `rentVehicle`. Reverter para `'garage'` em
  `returnRental`.

#### F-038 — `max_veiculos_player = 25` não é enforced
- **Severidade:** ALTO
- **Sintoma:** Config existe mas nenhuma validação em `buyVehicle`.
- **Consequência:** Players podem comprar veículos ilimitados. Memory leak + DB bloat.
- **Solução:** Validar em `vhub_conce:buyVehicle` via `COUNT(*) FROM vhub_vehicles WHERE
  owner = ?`. Reject se exceder.

#### F-039 — `Config.Classes` e `Config.FuelUsage` vestigiais (vhub_garage)
- **Severidade:** BAIXO
- **Sintoma:** Definidos mas não usados (consumo migrou para CORE).
- **Solução:** Remover.

#### F-040 — 9 eventos `100fuel`/`90fuel`/.../`0fuel` vestigiais
- **Severidade:** BAIXO
- **Sintoma:** Handlers no `client.lua` do legacyfuel que usam `GetPlayersLastVehicle()`
  (não netid). Nenhum server code os emite.
- **Solução:** Remover.

#### F-041 — 4 eventos declarados sem emitter/handler
- **Severidade:** BAIXO
- **Sintoma:** `E.SPAWN_OUT`, `E.UPDATE_AUCTION`, `E.CLOSE_UI`, `E.RESCUE_DONE`
  declarados em `shared/events.lua` mas nunca disparados ou sem handler.
- **Solução:** Implementar ou remover.

#### F-042 — Lock pessimista de transferência é process-local
- **Severidade:** ALTO
- **Sintoma:** `TxLock` em `server/garage.lua:18-36` serializa transfers por placa
  dentro do processo. Multi-instance setup não é protegido.
- **Solução:** Lock distribuído via Redis (ou tabela SQL `vhub_locks` com TTL). Export
  `vhub_conce:acquireLock(plate, ttl)`.

#### F-043 — `TriggerClientEvent(-1)` para despawn/syncfuel
- **Severidade:** ALTO (violação R5)
- **Sintoma:** `DO_DESPAWN` é broadcast via `TriggerClientEvent(E.DO_DESPAWN, -1, p)` em
  `server/impound.lua:77`, `server/rental.lua:82`, `server/admin.lua:246,390`.
  `syncfuel` também é broadcast em `vhub_legacyfuel/server.lua:99,147`.
- **Consequência:** Broadcast para 200 clients de evento que interessa a 0-5.
- **Solução:** State Bag `vh_despawn_pending[plate] = true`. Clients com interesse
  (motorista atual + passageiros) observam. Ou `TriggerClientEvent` para driver atual +
  passageiros do veículo.

#### F-044 — Eventos `vrp_legacyfuel:*` mantêm prefixo não-vhub
- **Severidade:** MÉDIO (violação de convenção)
- **Sintoma:** Eventos ainda usam prefixo antigo `vrp_legacyfuel:*` em vez de `vhub_fuel:*`.
- **Solução:** Renomear + migration com backward-compat (escutar ambos por 1 release).

#### F-045 — `impoundVehicle` export não valida permissão
- **Severidade:** ALTO
- **Sintoma:** Caller deve gatear. Se esquecer, qualquer recurso pode impound.
- **Solução:** Validar permissão no export via `vhub_admin:hasPermission(src, 'police.patio')`.

#### F-046 — Leitura direta de `vhub_auctions` em `admin.lua`
- **Severidade:** MÉDIO
- **Sintoma:** `admin.lua:122-132` faz `SELECT * FROM vhub_auctions` direto. Conflita
  com `vhub_ferinha` (escritor do leilão).
- **Solução:** Export `vhub_ferinha:listAuctions()` que garage chama. Garage nunca lê
  tabela de ferinha direto.

#### F-047 — `/fuel` admin parser ambíguo
- **Severidade:** BAIXO
- **Sintoma:** `/fuel 50 100` é ambíguo (50 parece placa mas é número).
- **Solução:** Explicitar: `/fuel <plate|netid> <qty>` com validação de tipo.

#### F-048 — `PRICE_PER_PCT = 10` hardcoded
- **Severidade:** BAIXO
- **Sintoma:** Preço do combustível requer editar código, não config.
- **Solução:** Mover para `Config.price_per_pct`.

#### F-049 — Galão (jerrycan) custa R$ 300 fixo
- **Severidade:** BAIXO
- **Sintoma:** Preço hardcoded. E o fuel do galão não é persistido — só entrega arma com
  munição.
- **Solução:** Mover para config. Sincronizar fuel do galão via `saveVehicleState`.

#### F-050 — Decor `FUEL_LEVEL` e State Bag `vh_fuel` em paralelo
- **Severidade:** MÉDIO
- **Sintoma:** Dois mecanismos paralelos de fuel no client: Decor (legado, lido pela
  bomba) e State Bag (CORE, lida pelo HUD).
- **Consequência:** Se divergirem, bomba cobra errado.
- **Solução:** Unificar em State Bag. Manter Decor apenas como fallback read-only para
  compat com scripts terceiros.

---

### 4. Camada de Runtime Control (vhub_vehcontrol + Drift)

#### F-051 — `Config.skillDebug = true` em produção
- **Severidade:** ALTO
- **Sintoma:** Polui chat do jogador com `placa=X model=Y p1=SIM/NAO` a cada `REQ_SHEET`.
- **Solução:** `Config.skillDebug = false` por default.

#### F-052 — `Config.skillBruteTest = true` em produção
- **Severidade:** ALTO
- **Sintoma:** Libera alloc 0..100% por eixo (anti-P2W desligado). Jogador pode empilhar
  tudo num eixo.
- **Solução:** `Config.skillBruteTest = false` por default.

#### F-053 — Risco nº1 (SetVehicleHandlingFloat model-wide)
- **Severidade:** CRÍTICO
- **Sintoma:** `SetVehicleHandlingFloat(veh, "CHandlingBase", field, value)` aplica
  modificações em **todos os veículos do mesmo modelo no servidor**.
- **Mitigação atual:** `ensureBase/restoreBase` captura e restaura estado original.
- **Status:** Prova em jogo pendente (`carskill_testplan.md §6c`).
- **Consequência se falhar:** Dois players dirigindo o mesmo modelo com skills diferentes
  conflitam — último a entrar sobrescreve.
- **Solução proposta:** Investigar `SetVehicleHandlingField` (per-entity, se disponível).
  Se não disponível, implementar "skill sandbox" — aplicar handling apenas no veículo
  do player via entidade clone. Ver PARTE II — Fase 6.

#### F-054 — R-3 (ordem cobrança→persistência)
- **Severidade:** MÉDIO
- **Sintoma:** `server/skill.lua` RECALIBRATE cobra item/dinheiro ANTES de persistir. Se
  `saveVehicleState` falha, player perdeu a porta sem recalibrar.
- **Solução:** Transação com rollback. Persistir primeiro, cobrar depois, rollback em
  caso de falha de cobrança.

#### F-055 — `vHub:vehicleCommitted` não escutado
- **Severidade:** MÉDIO (depende de F-024)
- **Sintoma:** Spec carskill §5.2 prevê reagir a commits; vehcontrol só lê em `REQ_SHEET`
  on-demand.
- **Consequência:** Se player comprar peça e NÃO reabrir a ficha, `hnd` aplicado fica
  stale.
- **Solução:** Escutar `vHub:vehicleCommitted` (quando F-024 for implementado) e reemitir
  `SHEET` para o driver atual.

#### F-056 — `vhub_vehcontrol:applyLock`/`applyEngine` broadcast `-1`
- **Severidade:** MÉDIO (violação R5)
- **Sintoma:** Em vez de StateBag, usa broadcast p/ todos.
- **Justificativa atual:** Evento discreto/momentâneo.
- **Solução:** Migrar para State Bag `vh_lock_state[plate]` e `vh_engine_state[plate]`.
  Reduz broadcast.

#### F-057 — `vhub_wow:searchResults` pode ser broadcast
- **Severidade:** MÉDIO
- **Sintoma:** Se vhub_wow emitir p/ `-1`, todos recebem a lista de busca. Handler em
  `client/sound.lua` NÃO filtra por `src`.
- **Solução:** Filtrar por `src` no handler. Ou vhub_wow deve enviar apenas para o
  solicitante.

#### F-058 — Drift sem `onResourceStop`
- **Severidade:** ALTO
- **Sintoma:** Drift não limpa handling modificado no resource stop.
- **Consequência:** Veículos podem ficar com handling viciado após restart.
- **Solução:** Implementar `onResourceStop` que restaura handling de todos os veículos
  atualmente em drift.

#### F-059 — Conflito latente Drift ↔ vhub_vehcontrol
- **Severidade:** ALTO
- **Sintoma:** Ambos modificam handling em runtime. Se rodarem simultaneamente no mesmo
  veículo, podem sobrescrever um ao outro.
- **Solução:** Definir prioridade. Drift só modifica se veículo NÃO tem skill alloc.
  Ou: Drift modifica campos diferentes (grip/traction) que vehcontrol não toca
  (top speed/accel/brake).

#### F-060 — Rates em constantes locais vs `Config.rates` centralizado
- **Severidade:** BAIXO
- **Sintoma:** `RATE_WINDOW_MS`, `SEARCH_COOLDOWN`, `_opAt` em constantes locais.
- **Solução:** Mover para `Config.rates` centralizado para auditoria.

---

### 5. Camada de Corridas (vhub_racha)

#### F-061 — 11 eventos NUI mortos
- **Severidade:** BAIXO
- **Sintoma:** Eventos declarados em `runtime/bus.js` mas sem handler no Lua.
- **Solução:** Implementar ou remover.

#### F-062 — Chaves de lang com typos
- **Severidade:** BAIXO
- **Sintoma:** Algumas chaves em `shared/lang/pt_br.lua` têm typos que podem quebrar
  tradução.
- **Solução:** Spell check + test de missing keys.

#### F-063 — `print()` em `bootstrap.lua` do racha
- **Severidade:** BAIXO (violação R10)
- **Solução:** Substituir por Logger.

#### F-064 — Anti-cheat gaps
- **Severidade:** MÉDIO
- **Sintoma:** Algumas validações têm tolerância muito alta (ex.: 30% de margem em
  distância).
- **Solução:** Reduzir tolerância + machine learning para detecção de padrões anômalos.

---

### 6. Camada de Combustível (vhub_legacyfuel)

#### F-065 — Nome "legacy" enganador
- **Severidade:** BAIXO
- **Sintoma:** Apesar do nome, é o sistema ativo. Não há substituto implementado.
- **Solução:** Renomear para `vhub_fuel` em v2.0. Ou implementar substituto de fato.

#### F-066 — Sem sync client-client de fuel
- **Severidade:** MÉDIO
- **Sintoma:** Quando motorista reabastece, outros players não veem fuel level mudar em
  tempo real. Delay de até 4s.
- **Causa raiz:** F-001 (CORE dormente). State Bag `vh_fuel` nunca escrita.
- **Solução:** Reativar State Bags no CORE (PARTE II — Fase 2). Outros clients veem
  `vh_fuel` mudar automaticamente.

#### F-067 — Prefixo `vrp_legacyfuel:*` (já coberto em F-044)

---

### 7. Camada de Balanceamento Offline (handling-balancer)

#### F-068 — Override só clamp em `fInitialDriveForce`
- **Severidade:** MÉDIO
- **Sintoma:** Possível tier S+ disfarçado se outros campos forem overridados manualmente.
- **Solução:** Aplicar clamp em todos os 8 campos do NÚCLEO-8.

#### F-069 — `tierOrder` frágil
- **Severidade:** BAIXO
- **Sintoma:** Depende de ordem de inserção no JSON.
- **Solução:** Validar ordem no `verify`. Adicionar campo `order` explícito em cada tier.

#### F-070 — Rename não atualiza selo
- **Severidade:** MÉDIO
- **Sintoma:** Renomear `handlingName` na Web UI deixa arquivo sem selo até próximo apply.
- **Solução:** Atualizar selo automaticamente após rename.

#### F-071 — `deriveArchetype` threshold 1500kg hardcoded
- **Severidade:** BAIXO
- **Sintoma:** Veículos exatamente em 1500kg podem ser classificados de forma
  inconsistente.
- **Solução:** Mover threshold para config. Definir regra explícita (ex.: `<= 1500` =
  light, `> 1500` = heavy).

---

### 8. Falhas Transversais (afetam múltiplos recursos)

#### F-072 — Ausência de "single-pilot-channel"
- **Severidade:** CRÍTICO (performance)
- **Sintoma:** Server faz broadcast de estado de veículo para todos os clients, mesmo
  quando apenas 1 (o motorista) precisa agir.
- **Causa raiz:** F-001 (CORE dormente) → recursos implementam workaround que usa
  broadcast.
- **Consequência:** Em servidor com 200 players e 50 dirigindo, 200 clients recebem
  eventos que interessam a 50. 4× de tráfego desperdiçado.
- **Solução proposta:** Implementar "single-pilot-channel" no CORE. Server fala apenas
  com o motorista atual de cada veículo sobre telemetria/handling/nitro. Passageiros
  recebem apenas State Bags (read-only, lazy-synced pela engine). Ver PARTE II — Fase 3.

#### F-073 — Falta de audit log unificado
- **Severidade:** ALTO
- **Sintoma:** Cada recurso tem seu próprio log (vhub_vehicle_log, vh_race_*,
  audit no prontuário). Não há consolidação.
- **Consequência:** Forensia de incidente requer correlação manual entre múltiplas
  tabelas.
- **Solução proposta:** Tabela `vhub_audit_unified` com colunas
  `(ts, actor, action, target, source, before, after, ip)`. Todos os exports
  privilegiados logam aqui.

#### F-074 — Falta de testes automatizados
- **Severidade:** ALTO
- **Sintoma:** Não há `vhub_testrunner` apesar de existir em `[TOOLS]/`. Nenhum teste
  unitário, nenhum teste de integração.
- **Solução proposta:** Implementar `vhub_testrunner` com:
  - Testes unitários para exports de cada recurso.
  - Testes de integração para fluxos end-to-end.
  - Testes de stress (multi-player simulado).
  - Testes de anti-cheat (penetration).

#### F-075 — Falta de health check endpoint
- **Severidade:** MÉDIO
- **Sintoma:** Não há como verificar se todos os recursos estão saudáveis sem olhar
  console.
- **Solução proposta:** Export `vhub:healthcheck()` em cada recurso. Retorna
  `{ok: bool, errors: [...], warnings: [...]}`. Admin NUI consolida.

#### F-076 — Falta de métricas de performance
- **Severidade:** MÉDIO
- **Sintoma:** Não há como saber qual export é mais chamado, qual thread consome mais
  CPU, qual query é mais lenta.
- **Solução proposta:** Wrappers de profiling em exports. Tabela `vhub_metrics` com
  agregados (count, avg_ms, p99_ms) por export/event.

#### F-077 — Falta de migration framework
- **Severidade:** ALTO
- **Sintoma:** Schema migrations são feitas em `aplicar_schema` com `CREATE TABLE IF NOT
  EXISTS`. Não há versionamento nem rollback.
- **Solução proposta:** Tabela `vhub_schema_version` com `(resource, version, applied_at)`.
  Cada recurso tem pasta `migrations/001_*.sql`, `002_*.sql`, etc. Boot aplica pendentes
  em ordem.

#### F-078 — Falta de feature flags
- **Severidade:** MÉDIO
- **Sintoma:** Não há como desabilitar feature sem editar código. Ex.: desabilitar
  corridas sem remover vhub_racha do server.cfg.
- **Solução proposta:** `Config.features = {races = true, drift = true, nitro = true, ...}`.
  Recursos verificam em boot.

#### F-079 — Config espalhada em múltiplos arquivos
- **Severidade:** MÉDIO
- **Sintoma:** Cada recurso tem seu `shared/config.lua` com defaults. Não há centralização.
- **Consequência:** Mudar preço de combustível requer saber que está em vhub_legacyfuel.
  Mudar IPVA requer saber que está em vhub_garage.
- **Solução proposta:** Manter configs por recurso (autonomia), mas expor via
  `vhub_admin:getConfig(resource, key)` para auditoria centralizada.

---

## PARTE II — PLANO DE REMEDIAÇÃO (ordenado por cadeia de execução)

Cada fase depende da anterior. Fases paralelas são marcadas com `‖`. Dentro de cada fase,
a ordem respeita a cadeia de execução (o que precisa funcionar antes para o próximo
passar a funcionar).

### 🧊 FASE 0 — Preparação e Proteção (1-2 dias)

Antes de tocar no CORE, garantir que temos backup e rollback.

#### 0.1 Snapshot do estado atual
- Tag git `pre-frozen-core-2-remediation` no repositório.
- Dump completo do banco de dados.
- Snapshot da VRAM em runtime (via export `vhub:dumpVRAM()` a ser criado).

#### 0.2 Implementar `vhub_testrunner` mínimo
- Criar `[TOOLS]/vhub_testrunner/` com framework mínimo (assert, before, after, suite).
- 5 testes smoke: CORE boot, vhub_conce DDL, vhub_garage spawn/store, vhub_custom apply
  mod, vhub_racha create lobby.
- **Validação:** `node vhub_testrunner.js smoke` retorna exit 0.

#### 0.3 Implementar `vhub_audit_unified`
- Tabela SQL: `vhub_audit_unified (id BIGINT AUTO_INCREMENT, ts TIMESTAMP, actor VARCHAR(64),
  action VARCHAR(64), target VARCHAR(128), source VARCHAR(32), before JSON, after JSON,
  ip VARCHAR(45), PRIMARY KEY (id), KEY idx_ts (ts), KEY idx_actor (actor), KEY idx_target
  (target))`.
- Export `vhub:audit(actor, action, target, source, before, after)` no CORE.
- Wrap em todos os exports privilegiados (commitVehicleState, transferOwnership,
  buyVehicle, impoundVehicle, installKit, recalibrate, etc.).

---

### 🔥 FASE 1 — Reanimar o CORE (foundation) (3-5 dias)

Esta é a fase mais sensível. Estamos descongelando o CORE FROZEN v1.0. Toda mudança
deve ser testada com 200+ players antes de ir para produção.

#### 1.1 Implementar gate de segurança para handlers de veículo (resolve F-001, F-007, F-008, F-019, F-023)

**Problema original (ADR #24):** atacante forja `vEnter` com netID da vítima → server
executa `NetworkSetEntityOwner` em entidade alheia.

**Solução:** Antes de processar qualquer evento de veículo, o server valida:
1. `source` (player que disparou o evento) é o **network owner atual** da entidade
   (validado via `NetworkGetEntityOwner(netid) == source`).
2. `source` é o **driver atual** registrado no CORE (`Veh:getDriver(plate) == source`),
   ou está autorizado via export `vhub:canDriveVehicle(src, plate)`.
3. Para `vState` (telemetria): validar que `source` é driver E está dirigindo o veículo
   com esta placa (anti-spoofing de placa).

```lua
-- server/vehicle.lua (reanimado)
local function _vhArmed(eventName, handler)
  return function(src, plate, ...)
    -- 1. Validar source é network owner
    local veh = NetworkGetEntityFromNetworkId(plate_to_netid[plate])
    if not veh or veh == 0 then return end
    if NetworkGetEntityOwner(veh) ~= src then
      vHub.Logger:warn(("vHub: %s rejeitado: src=%s não é network owner"):format(eventName, src))
      return
    end
    -- 2. Validar source é driver atual (ou autorizado)
    local driver = Veh:getDriver(plate)
    if driver ~= src then
      local ok = Auth:canInvoke(GetInvokingResource(), 'vehicle.drive')
      if not ok then
        vHub.Logger:warn(("vHub: %s rejeitado: src=%s não é driver de %s"):format(eventName, src, plate))
        return
      end
    end
    -- 3. Validar placa está registrada
    if not Veh:isRegistered(plate) then
      vHub.Logger:warn(("vHub: %s rejeitado: placa %s não registrada"):format(eventName, plate))
      return
    end
    -- Tudo OK, chamar handler
    handler(src, plate, ...)
  end
end

RegisterNetEvent("vHub:vEnter", _vhArmed("vEnter", function(src, plate)
  Veh:onEnter(plate, src)
end))
RegisterNetEvent("vHub:vLeave", _vhArmed("vLeave", function(src, plate)
  Veh:onLeave(plate)
end))
RegisterNetEvent("vHub:vState", _vhArmed("vState", function(src, plate, patch)
  Veh:onStateUpdate(plate, patch, "telemetria")
end))
RegisterNetEvent("vHub:vSpawned", _vhArmed("vSpawned", function(src, plate, netid)
  Veh:onSpawned(plate, netid)
end))
RegisterNetEvent("vHub:vDespawned", _vhArmed("vDespawned", function(src, plate)
  Veh:onDespawned(plate)
end))
```

**Validação:**
- Teste unitário: atacante tenta forjar `vEnter` com netID de vítima → rejeitado.
- Teste de carga: 50 players dirigindo simultâneos, sem rejeição incorreta.
- Penetration test: tentar bypass via injecão de netID arbitrário.

#### 1.2 Implementar `commitVehicleState` e `getVehicleState` oficiais no CORE (resolve F-028)

O CORE agora tem handlers ativos. Implementar exports:

```lua
-- server/exports.lua (do CORE)
function vHub.commitVehicleState(plate, patch, source)
  -- source é gate que determina quais campos podem ser mutados
  -- equivalente ao saveVehicleState do vhub_conce, mas no CORE
  vHub.assertThread()
  local allowed = SOURCE_GATES[source]
  if not allowed then
    vHub.Logger:warn(("commitVehicleState: source %s não autorizado"):format(source))
    return false
  end
  -- Validar patch contra allowed fields
  for k, _ in pairs(patch) do
    if not allowed[k] then
      vHub.Logger:warn(("commitVehicleState: source %s não pode mutar %s"):format(source, k))
      return false
    end
  end
  -- Aplicar na VRAM
  local vd = vHub.getVData(plate, "state") or {}
  for k, v in pairs(patch) do
    vd[k] = v
  end
  vHub.setVData(plate, "state", vd)
  -- Agendar persistência SQL (write-through com batch)
  vHub.SQL:schedule("UPDATE vh_vehicle_data SET data = ? WHERE plate = ?", json.encode(vd), plate)
  -- Disparar State Bag
  Veh:_syncBags(plate, vd)
  -- Disparar evento de commit
  TriggerEvent("vHub:vehicleCommitted", plate, source, patch)
  -- Audit
  vHub:audit(GetInvokingResource(), "commitVehicleState", plate, source, nil, patch)
  return true
end

function vHub.getVehicleState(plate)
  vHub.assertThread()
  local vd = vHub.getVData(plate, "state")
  if not vd then
    -- Fallback para SQL
    local rows = Await(vHub.SQL:fetch("SELECT data FROM vh_vehicle_data WHERE plate = ?", plate))
    if rows and rows[1] then
      vd = json.decode(rows[1].data)
      vHub.setVData(plate, "state", vd)  -- populate VRAM
    end
  end
  return vd or {}
end
```

**Validação:**
- Teste: `commitVehicleState("ABC1234", {fuel=0.5}, "pump")` → persiste em VRAM + SQL +
  State Bag + dispara evento.
- Teste: `commitVehicleState("ABC1234", {fuel=0.5}, "telemetria")` com source errado →
  rejeitado.

#### 1.3 Migrar `vh_vehicle_data` para JSON estruturado (resolve F-021, F-028)

Hoje `vh_vehicle_data` é BLOB com blindagem `b64:`. Migrar para `JSON`:

```sql
-- migration 001_vehicle_data_to_json.sql
ALTER TABLE vh_vehicle_data ADD COLUMN state_json JSON DEFAULT NULL;
-- Backfill: para cada linha, decode b64 e parse para JSON
-- (script Python/Node separado para evitar timeout SQL)
UPDATE vh_vehicle_data SET state_json = ? WHERE plate = ?;
-- Remover coluna antiga após validação
ALTER TABLE vh_vehicle_data DROP COLUMN data;
ALTER TABLE vh_vehicle_data RENAME COLUMN state_json TO data;
```

**Validação:**
- Script Python que itera `vh_vehicle_data`, decodifica b64, valida JSON, migra para
  `state_json`.
- Comparação linha-a-linha antes/depois.
- Rollback script preparado.

#### 1.4 Implementar VRAM eviction LRU + TTL (resolve F-013, F-026)

```lua
-- server/state.lua
local VRAM_TTL = 3600  -- 1h
local VRAM_MAX = 10000  -- 10k entries
local HOT_KEYS = { ban.active = true, whitelist = true, permissions = true }

local function _evict()
  local now = os.time()
  local count = 0
  for etype, entities in pairs(_mem) do
    for eid, keys in pairs(entities) do
      for key, entry in pairs(keys) do
        if not HOT_KEYS[key] and entry.last_access < now - VRAM_TTL then
          entities[eid][key] = nil
        end
      end
      if not next(entities[eid]) then
        entities[eid] = nil
      end
    end
    count = count + 1
  end
  vHub.Logger:info(("vHub.VRAM: evicted expired entries, %d entities remaining"):format(count))
end

SetInterval(60000, _evict)  -- a cada 1min
```

**Validação:**
- Teste: criar 15k entries, esperar 1h, verificar que ~10k foram evictados.
- Hot keys permanecem.

#### 1.5 Corrigir `_defaults` merge (resolve F-003, F-004, F-005)

```lua
-- bootstrap.lua (modificado)
function criar_config()
  local cfg = {}
  -- 1. Começa com defaults
  mergeConfig(cfg, _defaults)
  -- 2. Override com convars
  cfg.fuel_rate = decimal("vhub_fuel_rate", cfg.fuel_rate, 0, 1)
  cfg.max_speed_kmh = integer("vhub_max_speed_kmh", cfg.max_speed_kmh, 0, 1000)
  -- ... etc
  return cfg
end
```

**Validação:**
- Teste: sem convars, `cfg.fuel_rate == 0.01` (default de `_defaults`).
- Teste: com `vhub_fuel_rate 0.003`, `cfg.fuel_rate == 0.003`.

#### 1.6 Remover `print()` e usar Logger (resolve F-014, F-015)

```lua
-- Em auth.lua:
-- print(('vHub.Auth:connect attempt src=%s'):format(tostring(src)))
vHub.Logger:debug(('vHub.Auth:connect attempt src=%s'):format(tostring(src)))
```

#### 1.7 Registrar `vHub:passengerMode` no client (resolve F-007)

```lua
-- client/vehicle.lua
RegisterNetEvent("vHub:passengerMode", function(plate, isPassenger)
  -- Aplicar/passar UI de passageiro
  SetTimeout(0, function()
    TriggerEvent("vhub_player_state:passengerMode", plate, isPassenger)
  end)
end)
```

#### 1.8 Atualizar README sobre `_invoker_allowed` (resolve F-002)

Atualizar `readme.md` Seção 13:

> Se `trusted_resources` está vazio, **nenhum** resource pode chamar exports sensíveis
> (default-deny desde hotfix N0-2). É obrigatório popular `vHub.cfg.trusted_resources`
> com a lista de recursos autorizados. Veja FASE 0 — 1.9.

#### 1.9 Popular `trusted_resources` com warning (resolve F-022)

```lua
-- server/boot.lua (em validar_base)
if not vHub.cfg.trusted_resources or next(vHub.cfg.trusted_resources) == nil then
  vHub.Logger:warn("vHub.cfg.trusted_resources está VAZIO. Exports privilegiados retornarão false.")
  vHub.Logger:warn("Lista sugerida (adicionar em config): vhub_conce, vhub_garage, vhub_custom, vhub_vehcontrol, vhub_nitro, vhub_racha, vhub_admin")
  -- Em dev, auto-popular com warning:
  if vHub.cfg.env == "dev" then
    vHub.cfg.trusted_resources = {
      vhub_conce = true, vhub_garage = true, vhub_custom = true,
      vhub_vehcontrol = true, vhub_nitro = true, vhub_racha = true,
      vhub_admin = true,
    }
    vHub.Logger:warn("Auto-populando trusted_resources em modo DEV. NUNCA usar em produção.")
  end
end
```

#### 1.10 Investigar e corrigir BLOB `b64:` (resolve F-021)

Após migration 1.3, o `b64:` não é mais necessário. Remover prefixo em todos os
pontos de leitura/escrita.

**Validação:** todos os testes do testrunner passam sem o `b64:`.

#### 1.11 Implementar WAL (Write-Ahead Log) (resolve F-010)

```lua
-- server/wal.lua
local WAL_PATH = "logs/vhub_wal.log"
local WAL = {}

function WAL.append(op)
  local line = json.encode({ts=os.time(), op=op}) .. "\n"
  local f = io.open(WAL_PATH, "a")
  f:write(line)
  f:close()
end

function WAL.replay()
  local f = io.open(WAL_PATH, "r")
  if not f then return end
  for line in f:lines() do
    local entry = json.decode(line)
    vHub.SQL:execute(entry.op.query, entry.op.params)
  end
  f:close()
  os.rename(WAL_PATH, WAL_PATH .. ".replayed")
end

-- Em commitVehicleState:
WAL.append({query="UPDATE vh_vehicle_data SET data = ? WHERE plate = ?", params={...}})
vHub.SQL:schedule(...)
```

Em boot, chamar `WAL.replay()` antes de aceitar conexões.

---

### 🔧 FASE 2 — Estado de Veículo Server-Authoritative (3-5 dias)

Agora que o CORE está reanimado, migrar vhub_conce para usar exports do CORE.

#### 2.1 Migrar `vhub_conce:saveVehicleState` para chamar `vhub:commitVehicleState`

```lua
-- vhub_conce/server/vstate.lua (modificado)
function VState.save(plate, patch, source)
  -- Antes: escrevia direto em vhub_vehicle_state
  -- Agora: delega para CORE
  local ok = exports.vhub:commitVehicleState(plate, patch, source)
  if not ok then
    error(("vhub_conce: saveVehicleState falhou para placa %s source %s"):format(plate, source))
  end
  -- Espelha em vhub_vehicle_state para retro-compatibilidade
  -- (será removido em Fase 5)
  local state = exports.vhub:getVehicleState(plate)
  MySQL.update("UPDATE vhub_vehicle_state SET state = ? WHERE plate = ?", json.encode(state), plate)
  -- Dispara evento local (para consumers que ainda escutam conce)
  TriggerEvent("vhub_conce:vehicleCommitted", plate, source, patch)
end
```

**Validação:**
- Teste: `saveVehicleState("ABC", {fuel=0.5}, "pump")` → chama CORE → CORE persiste em
  `vh_vehicle_data` → conce espelha em `vhub_vehicle_state` → ambas State Bags
  atualizadas.
- Performance: tempo total < 5ms.

#### 2.2 Reativar State Bags `vh_vehicle_state`, `vh_vehicle_driver`, `vh_fuel`, `vh_eng`, `vh_body`

```lua
-- server/vehicle.lua (em Veh:_syncBags)
function Veh:_syncBags(plate, vd)
  local veh = plate_to_entity[plate]
  if not veh then return end
  -- State Bags (escrita server-side, replica para todos os clients automaticamente)
  Entity(veh).state:set("vh_fuel", vd.fuel or 1.0, true)
  Entity(veh).state:set("vh_eng", vd.engine_health or 1.0, true)
  Entity(veh).state:set("vh_body", vd.body_health or 1.0, true)
  Entity(veh).state:set("vh_odo", vd.odometer or 0, true)
  Entity(veh).state:set("vh_tune", vd.tune or {}, true)
  Entity(veh).state:set("vh_on", vd.is_on or false, true)
  Entity(veh).state:set("vh_driver", vd.driver or nil, true)
end
```

#### 2.3 Implementar `vHub:vehicleCommitted` event (resolve F-024, F-055)

Já emitido por `commitVehicleState` (FASE 1.2). Listeners:

```lua
-- vhub_vehcontrol/server/skill.lua
RegisterNetEvent("vHub:vehicleCommitted", function(plate, source, patch)
  if source == "handling" or source == "tune" then
    -- Reemitir SHEET para o driver atual
    local driver = exports.vhub:getVehicleDriver(plate)
    if driver then
      TriggerClientEvent("vhub_vehcontrol:SHEET", driver, exports.vhub:getVehicleSheet(plate))
    end
  end
end)
```

#### 2.4 Migrar vhub_garage e vhub_legacyfuel para usar CORE exports (resolve F-043, F-050, F-066)

```lua
-- vhub_garage/server/garage.lua
function Garage.spawnVehicle(plate)
  -- Antes: aplicava fuel/health/etc localmente + saveVehicleState
  -- Agora: chama vHub:applyVehicleState(plate, veh)
  exports.vhub:applyVehicleState(plate, veh)  -- aplica State Bags
  exports.vhub:commitVehicleState(plate, {is_stored=false}, "system")
end

-- vhub_legacyfuel/server.lua
RegisterNetEvent("vrp_legacyfuel:updateFuel", function(plate, value)
  -- Antes: TriggerEvent("vhub_garage:relayFuelUpdate", plate, value)
  -- Agora: chama CORE diretamente
  exports.vhub:commitVehicleState(plate, {fuel=value}, "pump")
end)
```

#### 2.5 Eliminar `TriggerClientEvent(-1)` para despawn (resolve F-043)

```lua
-- vhub_garage/server/impound.lua
function Impound.impoundVehicle(plate, reason, fee)
  -- ...
  -- Antes: TriggerClientEvent(E.DO_DESPAWN, -1, plate)
  -- Agora: State Bag
  local veh = plate_to_entity[plate]
  if veh then
    Entity(veh).state:set("vh_despawn_pending", true, true)
    -- Driver atual e passageiros observam a State Bag e reagem
  end
  DeleteVehicle(veh)
end
```

```lua
-- vhub_garage/client/vehicles.lua
CreateThread(function()
  -- Observar State Bags de despawn
  AddStateBagChangeHandler("vh_despawn_pending", nil, function(bagName, _, value)
    if not value then return end
    local veh = GetEntityFromStateBagName(bagName)
    if veh and veh ~= 0 then
      -- Limpar blips, fechar NUI, etc.
      TriggerEvent("vhub_garage:vehicleDespawned", GetVehicleNumberPlateText(veh))
    end
  end)
end)
```

---

### 🚄 FASE 3 — Network Optimization: single-pilot-channel (3-5 dias)

Esta fase implementa a ideia original que foi morta pela gambiarra. Reduz tráfego
server→clients em N× onde N = passageiros.

#### 3.1 Implementar `vhub:getVehicleDriver(plate)` export

Já existe em VRAM, mas não é export. Expor:

```lua
function vHub.getVehicleDriver(plate)
  return Veh:getDriver(plate)
end
```

#### 3.2 Implementar `vhub:getVehiclePassengers(plate)` export

```lua
function vHub.getVehiclePassengers(plate)
  local veh = plate_to_entity[plate]
  if not veh then return {} end
  local passengers = {}
  for i = -1, GetVehicleModelNumberOfSeats(GetEntityModel(veh)) - 1 do
    local ped = GetPedInVehicleSeat(veh, i)
    if ped ~= 0 then
      local src = NetworkGetEntityOwner(veh)
      table.insert(passengers, src)
    end
  end
  return passengers
end
```

#### 3.3 Migrar broadcasts para "driver-only" onde aplicável

Para cada `TriggerClientEvent(event, -1, ...)`:

| Evento | Antes | Depois |
|--------|-------|--------|
| `vhub_vehcontrol:applyLock` | `-1` | `driver` (motorista aplica visualmente) |
| `vhub_vehcontrol:applyEngine` | `-1` | `driver` |
| `vhub_legacyfuel:syncfuel` | `-1` | `driver` (passageiros veem via State Bag `vh_fuel`) |
| `vhub_nitro:drainFx` | `-1` | `driver + passengers in vehicle` (precisam ver o efeito) |
| `vhub_racha:lobbyUpdate` | `-1` (todos no lobby) | `players_in_lobby` (filtrado) |
| `vhub_racha:raceStart` | `-1` (todos na sessão) | `players_in_session` |
| `vhub_racha:lapComplete` | `-1` (todos na corrida) | `players_in_race` |

```lua
-- Helper
function vHub.emitToVehicleOccupants(plate, event, ...)
  local driver = Veh:getDriver(plate)
  if driver then TriggerClientEvent(event, driver, ...) end
  for _, src in ipairs(Veh:getPassengers(plate)) do
    if src ~= driver then
      TriggerClientEvent(event, src, ...)
    end
  end
end
```

#### 3.4 Implementar delta sync manual para eventos frequentes

```lua
-- vhub_vehcontrol/server/main.lua (telemetria)
local LAST_TELEMETRY = {}  -- [plate][field] = last_value

function Telemetry.report(plate, telemetry)
  local deltas = {}
  for k, v in pairs(telemetry) do
    if LAST_TELEMETRY[plate] == nil or LAST_TELEMETRY[plate][k] ~= v then
      deltas[k] = v
      LAST_TELEMETRY[plate] = LAST_TELEMETRY[plate] or {}
      LAST_TELEMETRY[plate][k] = v
    end
  end
  if next(deltas) then
    -- Apenas deltas para o driver
    local driver = Veh:getDriver(plate)
    if driver then
      TriggerClientEvent("vhub_vehcontrol:telemetryDelta", driver, plate, deltas)
    end
  end
end
```

#### 3.5 Rate-limiting por event/plate

```lua
-- server/rate_limit.lua
local RATE_LIMITS = {
  ["vHub:vState"] = { hz = 4, bucket = "per_plate" },
  ["vhub_vehcontrol:telemetryDelta"] = { hz = 4, bucket = "per_plate" },
  ["vhub_legacyfuel:updateFuel"] = { hz = 0.25, bucket = "per_plate" },
  ["vhub_nitro:drain"] = { hz = 1, bucket = "per_plate" },
}

local BUCKETS = {}

local function rateLimited(eventName, src, plate)
  local limit = RATE_LIMITS[eventName]
  if not limit then return true end
  local key = limit.bucket == "per_plate" and (src .. ":" .. plate) or src
  local now = os.clock()
  BUCKETS[eventName] = BUCKETS[eventName] or {}
  local last = BUCKETS[eventName][key] or 0
  if now - last < 1 / limit.hz then
    return false
  end
  BUCKETS[eventName][key] = now
  return true
end
```

#### 3.6 State Bag replica para passageiros (read-only, lazy)

Para passageiros, em vez de `TriggerClientEvent`, usar State Bag que a engine já
sincroniza automaticamente:

```lua
-- State Bag replicada para TODOS os clients que têm o veículo em sua "área de interesse"
Entity(veh).state:set("vh_fuel", value, true)
Entity(veh).state:set("vh_speed", value, true)
Entity(veh).state:set("vh_hand_applied", value, true)  -- flag para o passageiro saber que handling foi modificado
```

Passageiros leem via `StateBagHandler` — não há tráfego server→client manual.

---

### 🛡️ FASE 4 — Anti-Cheat Hardening (2-3 dias)

#### 4.1 Validar source em todos os exports privilegiados (resolve F-045)

```lua
-- Em todos os exports privilegiados:
function Garage.impoundVehicle(plate, reason, fee)
  local src = source
  if not exports.vhub_admin:hasPermission(src, 'police.patio') then
    vHub.Logger:warn(("impoundVehicle: src=%s sem permissão"):format(src))
    return false
  end
  -- ...
end
```

#### 4.2 Lock distribuído cross-instance (resolve F-042)

```lua
-- vhub_conce/server/locks.lua
local LOCKS = {}  -- [resource][key] = {holder, expires}

function Locks.acquire(resource, key, ttl)
  local now = os.time()
  local existing = LOCKS[resource] and LOCKS[resource][key]
  if existing and existing.expires > now then
    return false  -- já held
  end
  LOCKS[resource] = LOCKS[resource] or {}
  LOCKS[resource][key] = { holder = resource, expires = now + ttl }
  -- Persistir em SQL para multi-instance
  MySQL.update("INSERT INTO vhub_locks (resource, key, holder, expires) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE holder = ?, expires = ?",
    resource, key, resource, now + ttl, resource, now + ttl)
  return true
end

function Locks.release(resource, key)
  LOCKS[resource] = LOCKS[resource] or {}
  LOCKS[resource][key] = nil
  MySQL.update("DELETE FROM vhub_locks WHERE resource = ? AND key = ? AND holder = ?", resource, key, resource)
end
```

#### 4.3 Rate-limit server events por IP/cid/plate (resolve F-019, F-057)

Implementar rate-limit server-side em todos os `RegisterNetEvent`:

```lua
local function rateLimitedHandler(eventName, hz, handler)
  local last = {}
  RegisterNetEvent(eventName, function(...)
    local src = source
    local now = os.clock()
    if last[src] and now - last[src] < 1/hz then
      vHub.Logger:warn(("rate-limit: %s from src=%s"):format(eventName, src))
      return
    end
    last[src] = now
    handler(src, ...)
  end)
end

rateLimitedHandler("vHub:vState", 4, function(src, plate, patch)
  Veh:onStateUpdate(plate, patch, "telemetria")
end)
```

#### 4.4 Anti-teleport com distância/time delta

```lua
-- vhub_racha/server/anti_cheat.lua (reforçado)
function AntiCheat.validatePosition(src, plate, new_pos, old_pos, time_delta)
  local dist = #(vector3(new_pos.x, new_pos.y, new_pos.z) - vector3(old_pos.x, old_pos.y, old_pos.z))
  local max_speed = exports.vhub_vehcontrol:getMaxSpeed(plate)  -- km/h
  local max_dist = max_speed * time_delta / 3.6  -- metros
  if dist > max_dist * 1.1 then  -- 10% tolerância
    vHub.Logger:warn(("anti-teleport: src=%s plate=%s dist=%.2f max=%.2f"):format(src, plate, dist, max_dist))
    vHub:audit(src, "teleport_suspect", plate, "anti_cheat", {dist=dist, max=max_dist}, nil)
    return false
  end
  return true
end
```

#### 4.5 Anti-speedhack com velocity cap por tier

```lua
function AntiCheat.validateSpeed(src, plate, reported_speed)
  local max_speed = exports.vhub_vehcontrol:getMaxSpeed(plate)
  if reported_speed > max_speed * 1.05 then  -- 5% tolerância
    vHub.Logger:warn(("anti-speedhack: src=%s plate=%s speed=%.2f max=%.2f"):format(src, plate, reported_speed, max_speed))
    vHub:audit(src, "speedhack_suspect", plate, "anti_cheat", {speed=reported_speed, max=max_speed}, nil)
    return false
  end
  return true
end
```

#### 4.6 Audit log imutável (append-only) (resolve F-073)

`vhub_audit_unified` já é append-only. Para garantir imutabilidade mesmo contra admin
malicioso, adicionar trigger SQL:

```sql
CREATE TRIGGER vhub_audit_no_update BEFORE UPDATE ON vhub_audit_unified
FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'vhub_audit_unified is append-only';
CREATE TRIGGER vhub_audit_no_delete BEFORE DELETE ON vhub_audit_unified
FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'vhub_audit_unified is append-only';
```

---

### 🧹 FASE 5 — Cleanup e Deprecation (1-2 dias)

#### 5.1 Drop `vh_vehicle_data` (após FASE 2 confirmada em produção por 30 dias)

```sql
-- migration 002_drop_vh_vehicle_data.sql
DROP TABLE vh_vehicle_data;
```

#### 5.2 Drop `vhub_vehicles.customization` (LONGTEXT DEPRECATED) (resolve F-025)

```sql
-- migration 003_drop_customization_column.sql
ALTER TABLE vhub_vehicles DROP COLUMN customization;
```

#### 5.3 Drop `vhub_nitro_state` (DEPRECATED)

```sql
-- migration 004_drop_vhub_nitro_state.sql
DROP TABLE vhub_nitro_state;
```

#### 5.4 Remover eventos vestigiais (resolve F-039, F-040, F-041, F-061)

- `Config.Classes`, `Config.FuelUsage` (vhub_garage) — remover.
- 9 handlers `100fuel`/.../`0fuel` (vhub_legacyfuel) — remover.
- 4 eventos sem emitter/handler — implementar ou remover.
- 11 eventos NUI mortos (vhub_racha) — implementar ou remover.

#### 5.5 Renomear `vrp_legacyfuel:*` → `vhub_fuel:*` (resolve F-044, F-065)

```lua
-- vhub_legacyfuel (renomeado para vhub_fuel em FASE 7)
-- Migration: manter handlers antigos por 1 release com warning
RegisterNetEvent("vrp_legacyfuel:updateFuel", function(...)
  vHub.Logger:warn("vrp_legacyfuel:updateFuel está DEPRECATED, use vhub_fuel:updateFuel")
  -- forward para novo nome
  TriggerEvent("vhub_fuel:updateFuel", ...)
end)
```

#### 5.6 Mover hardcoded events para `shared/events.lua` (resolve F-031, F-036)

```lua
-- vhub_custom/shared/events.lua (adicionar)
VHubCustom.E.mecTowDone = "vhub_custom:server:mecTowDone"
VHubCustom.E.vehControlRecalibrate = "vhub_vehcontrol:recalibrate"
VHubCustom.E.vehControlRecalDone = "vhub_vehcontrol:recalDone"
VHubCustom.E.garageDoDespawn = "vhub_garage:doDespawn"
```

Substituir todos os literais hardcoded por `VHubCustom.E.*`.

---

### ⚡ FASE 6 — Corrigir Risco #1 (handling model-wide) (3-5 dias)

#### 6.1 Investigar `SetVehicleHandlingField` (per-entity)

Pesquisar na documentação CitizenFX se existe API per-entity. Se sim, migrar:

```lua
-- Antes: SetVehicleHandlingFloat(veh, "CHandlingBase", "fInitialDriveForce", value)
-- Depois: SetVehicleHandlingField(veh, "CHandlingBase", "fInitialDriveForce", value)
--         (se per-entity, não afeta outros veículos do mesmo modelo)
```

#### 6.2 Se per-entity não disponível, implementar "skill sandbox"

Cada player tem seu próprio "clone" do veículo para aplicar handling:

```lua
-- vhub_vehcontrol/client/handling.lua
local SANDBOX_VEHICLES = {}  -- [src] = sandbox_vehicle

function Handling.applySandbox(src, plate, alloc)
  local real_veh = GetVehiclePedIsIn(GetPlayerPed(src), false)
  -- Criar clone invisível só para o player
  local sandbox_veh = CloneVehicle(real_veh, false, false)
  SetEntityVisible(sandbox_veh, false, false)
  SetEntityCollision(sandbox_veh, false, false)
  -- Aplicar handling no clone
  SetVehicleHandlingFloat(sandbox_veh, "CHandlingBase", "fInitialDriveForce", ...)
  -- ...
  -- Player dirige o clone; visualmente aparece no real_veh (que é só proxy)
  SANDBOX_VEHICLES[src] = { sandbox = sandbox_veh, real = real_veh }
end
```

⚠ Esta abordagem é complexa e tem trade-offs (sync de posição entre clone e proxy).
Avaliar se vale a pena vs aceitar limitação do GTA V.

#### 6.3 Drift: garantir `onResourceStop` (resolve F-058)

```lua
-- Drift/cl.lua
AddEventHandler("onResourceStop", function(resName)
  if resName ~= GetCurrentResourceName() then return end
  -- Restaurar handling de todos os veículos em drift
  for plate, _ in pairs(ACTIVE_DRIFTS) do
    local veh = plate_to_entity[plate]
    if veh and DoesEntityExist(veh) then
      RestoreVehicleHandling(veh)
    end
  end
end)
```

#### 6.4 Resolver conflito Drift ↔ vhub_vehcontrol (resolve F-059)

Definir prioridade via ADR nova:

```lua
-- Drift só aplica modificações em campos NÃO tocados pelo vehcontrol
-- vehcontrol: fInitialDriveForce, fInitialDriveMaxVel, fBrakeForce, fTractionCurveMax/Min
-- Drift: fTractionBias, fSteeringLock, fDownforceModifier (campos diferentes)

-- Em Drift/cl.lua:
local FORBIDDEN_FIELDS = {
  fInitialDriveForce = true,
  fInitialDriveMaxVel = true,
  fBrakeForce = true,
  fTractionCurveMax = true,
  fTractionCurveMin = true,
}
-- Drift só modifica campos não-FORBIDDEN
```

---

### 📦 FASE 7 — Consolidar Exports (anti-redundância) (2-3 dias)

#### 7.1 Criar `vhub_custom/server/exports.lua` (resolve F-033)

```lua
-- vhub_custom/server/exports.lua
local M = {}

function M.getMods(plate)
  local state = exports.vhub_conce:getVehicleState(plate)
  return state.customization.mods or {}
end

function M.canModify(src, plate, modType)
  -- Validar tier, ownership, etc.
  local tier = exports.vhub_vehcontrol:getTier(plate)
  local owner = exports.vhub_conce:getVehicleEntry(plate).owner
  if owner ~= GetPlayerIdentifierByType(src, "license") then
    return false, "not_owner"
  end
  if TIER_RESTRICTIONS[tier] and TIER_RESTRICTIONS[tier][modType] then
    return false, "tier_blocked"
  end
  return true
end

function M.getTier(plate)
  return exports.vhub_vehcontrol:getTier(plate)
end

function M.getVehicleSheetPreview(plate)
  return exports.vhub_vehcontrol:getVehicleSheetPreview(plate)
end

exports('getMods', M.getMods)
exports('canModify', M.canModify)
exports('getTier', M.getTier)
exports('getVehicleSheetPreview', M.getVehicleSheetPreview)
```

#### 7.2 Documentar API pública de cada recurso

Criar `<resource>/API.md` em cada recurso com lista de exports, assinaturas, exemplos.

#### 7.3 Migrar hardcoded events → exports

Para cada par de eventos call-reply, converter para export síncrono quando possível:

```lua
-- Antes:
-- TriggerServerEvent("vhub_vehcontrol:recalibrate", plate, alloc)
-- RegisterNetEvent("vhub_vehcontrol:recalDone", function(plate, success) ... end)

-- Depois:
local success = exports.vhub_vehcontrol:recalibrate(plate, alloc)  -- sync via lib.callback
```

#### 7.4 Criar `vhub_admin:getConfig(resource, key)` para auditoria (resolve F-079)

```lua
-- vhub_admin/server/exports.lua
function Admin.getConfig(resource, key)
  -- Retornar config de qualquer recurso que expõe getConfig
  local r = exports[resource]
  if not r or not r.getConfig then return nil end
  return r.getConfig(key)
end
```

Cada recurso expõe:

```lua
-- vhub_conce/server/exports.lua
function Conce.getConfig(key)
  return VHubConce.cfg[key]
end
exports('getConfig', Conce.getConfig)
```

---

### 🧪 FASE 8 — Testes e Validação (contínuo)

#### 8.1 Test suite para CORE

`[TOOLS]/vhub_testrunner/suites/core/`:
- `test_vram.lua` — set/get/evict
- `test_auth.lua` — trusted/untrusted
- `test_vehicle.lua` — register/onSpawned/onEnter/onLeave/onStateUpdate/onDespawned
- `test_state_bags.lua` — sync
- `test_wal.lua` — replay
- `test_audit.lua` — append/imutabilidade

#### 8.2 Test suite para contratos (exports)

Para cada export público, um teste que valida:
- Assinatura correta
- Retorno esperado
- Rejeição de input inválido
- Rate-limit se aplicável
- Audit log gerado

#### 8.3 Test suite para fluxos end-to-end

`[TOOLS]/vhub_testrunner/suites/e2e/`:
- `test_buy_spawn_store_respawn.lua`
- `test_fuel_full_cycle.lua`
- `test_customization_bennys_mec_oficina.lua`
- `test_nitro_install_activate_drain_refill.lua`
- `test_race_create_lobby_grid_finish_ranking.lua`
- `test_impound_admin_api_bootscan.lua`
- `test_auction_create_bid_finalize.lua`
- `test_rental_contract_expiry.lua`
- `test_ipva_overdue_block_spawn.lua`

#### 8.4 Stress test (multi-player)

Script que simula 200 players simultâneos:
- 50 dirigindo (com telemetria a 4Hz)
- 100 em zonas (interagindo com NUI)
- 50 idle
- Medir: CPU server, memória VRAM, tráfego rede, latência exports

#### 8.5 Anti-cheat penetration test

Tentar explorar cada vetor conhecido:
- Spoofing de netID
- Speedhack (tentar dirigir acima do max_speed do tier)
- Teleport (tentar mover sem tempo suficiente)
- Dupe (tentar duplicar veículo via race condition)
- SQL injection em exports que recebem string

---

## PARTE III — ROADMAP DE IMPLEMENTAÇÃO

### Sequência recomendada (com dependências)

```
FASE 0 (Preparação)
  │
  ├── 0.1 Snapshot
  ├── 0.2 vhub_testrunner mínimo
  └── 0.3 vhub_audit_unified
  │
  ▼
FASE 1 (Reanimar CORE) — 3-5 dias
  │
  ├── 1.1 Gate de segurança handlers
  ├── 1.2 commitVehicleState/getVehicleState
  ├── 1.3 Migrar vh_vehicle_data → JSON
  ├── 1.4 VRAM eviction LRU+TTL
  ├── 1.5 Corrigir _defaults merge
  ├── 1.6 Remover print()
  ├── 1.7 Registrar passengerMode no client
  ├── 1.8 Atualizar README
  ├── 1.9 Popular trusted_resources default
  ├── 1.10 Investigar e remover b64:
  └── 1.11 Implementar WAL
  │
  ▼
FASE 2 (Estado Server-Authoritative) — 3-5 dias
  │
  ├── 2.1 Migrar vhub_conce para CORE exports
  ├── 2.2 Reativar State Bags vh_*
  ├── 2.3 Implementar vHub:vehicleCommitted
  ├── 2.4 Migrar vhub_garage e vhub_legacyfuel para CORE exports
  └── 2.5 Eliminar TriggerClientEvent(-1) para despawn
  │
  ▼
FASE 3 (Network Optimization) — 3-5 dias
  │
  ├── 3.1 getVehicleDriver export
  ├── 3.2 getVehiclePassengers export
  ├── 3.3 Migrar broadcasts para driver-only
  ├── 3.4 Delta sync manual
  ├── 3.5 Rate-limiting por event/plate
  └── 3.6 State Bag replica para passageiros
  │
  ▼
FASE 4 (Anti-Cheat Hardening) — 2-3 dias ‖ FASE 5
  │
  ├── 4.1 Validar source em exports privilegiados
  ├── 4.2 Lock distribuído cross-instance
  ├── 4.3 Rate-limit server events
  ├── 4.4 Anti-teleport
  ├── 4.5 Anti-speedhack
  └── 4.6 Audit log imutável
  │
  ▼
FASE 5 (Cleanup) — 1-2 dias ‖ FASE 4
  │
  ├── 5.1 Drop vh_vehicle_data (após 30 dias em prod)
  ├── 5.2 Drop vhub_vehicles.customization
  ├── 5.3 Drop vhub_nitro_state
  ├── 5.4 Remover eventos vestigiais
  ├── 5.5 Renomear vrp_legacyfuel → vhub_fuel
  └── 5.6 Mover hardcoded events para events.lua
  │
  ▼
FASE 6 (Risco #1) — 3-5 dias ‖ FASE 7
  │
  ├── 6.1 Investigar SetVehicleHandlingField
  ├── 6.2 Skill sandbox (se 6.1 falhar)
  ├── 6.3 Drift onResourceStop
  └── 6.4 Resolver Drift vs vehcontrol
  │
  ▼
FASE 7 (Consolidar Exports) — 2-3 dias ‖ FASE 6
  │
  ├── 7.1 vhub_custom/server/exports.lua
  ├── 7.2 Documentar API pública
  ├── 7.3 Migrar eventos call-reply → exports síncronos
  └── 7.4 vhub_admin:getConfig centralizado
  │
  ▼
FASE 8 (Testes) — contínuo
  │
  ├── 8.1 Test suite CORE
  ├── 8.2 Test suite contratos
  ├── 8.3 Test suite E2E
  ├── 8.4 Stress test
  └── 8.5 Penetration test
```

### Estimativa total: 18-30 dias úteis (1 pessoa)

Com 2-3 engenheiros em paralelo (FASE 4 ‖ FASE 5 ‖ FASE 6 ‖ FASE 7): 12-18 dias.

### Priorização por risco

| Prioridade | Fases | Por quê |
|------------|-------|---------|
| P0 (urgente) | FASE 0, FASE 1 | Sem isso, nada mais funciona corretamente |
| P1 (alta) | FASE 2, FASE 4 | Restaura contratos + anti-cheat |
| P2 (média) | FASE 3, FASE 6 | Performance + Risco #1 |
| P3 (baixa) | FASE 5, FASE 7 | Cleanup + consolidação |
| Contínuo | FASE 8 | Sem fim — sempre |

---

## PARTE IV — RISCOS DA REMEDIAÇÃO

Cada fase tem riscos. Aqui estão os principais, com mitigações.

### Risco R-REM-1: Reanimar handlers quebra em produção
- **Probabilidade:** Média
- **Impacto:** Alto
- **Mitigação:** FASE 0.1 (snapshot) + FASE 8.4 (stress test) + deploy canário (10%
  dos servidores primeiro, 24h observação, depois 100%).

### Risco R-REM-2: Migration vh_vehicle_data corrompe dados
- **Probabilidade:** Baixa
- **Impacto:** Crítico
- **Mitigação:** Script Python com validação linha-a-linha. Backup completo antes.
  Rollback script preparado. Teste em DB clone primeiro.

### Risco R-REM-3: Lock distribuído (FASE 4.2) adiciona latência
- **Probabilidade:** Alta
- **Impacto:** Baixo
- **Mitigação:** Lock TTL curto (5s). Cache local + refresh em background. Fallback
  para lock local se Redis indisponível.

### Risco R-REM-4: Skill sandbox (FASE 6.2) é complexo demais
- **Probabilidade:** Média
- **Impacto:** Médio
- **Mitigação:** Aceitar limitação do GTA V. Documentar que 2 players no mesmo modelo
  com skills diferentes pode conflitar. Recomendar que players comprem modelos
  diferentes. Mitigação UX: warning no painel de skill se outro player está no mesmo
  modelo.

### Risco R-REM-5: Migration para CORE exports quebra scripts terceiros
- **Probabilidade:** Alta
- **Impacto:** Médio
- **Mitigação:** Manter `vhub_conce:saveVehicleState` como wrapper de `vhub:commitVehicleState`
  por 2 releases. Deprecation warning. Remover apenas em v2.0 final.

---

## PARTE V — CHECKLIST DE VALIDAÇÃO POR FASE

Cada fase só é considerada completa quando TODOS os itens do checklist passam.

### FASE 1 — Checklist
- [ ] Handlers `vHub:vEnter`/`vLeave`/`vState`/`vSpawned`/`vDespawned` ativos
- [ ] Penetration test: spoofing de netID rejeitado
- [ ] `vHub:commitVehicleState` funciona com source gates
- [ ] `vHub:getVehicleState` retorna dados de VRAM ou SQL
- [ ] `vh_vehicle_data` migrado para JSON (sem `b64:`)
- [ ] VRAM eviction roda a cada 1min
- [ ] `_defaults` é aplicado em `criar_config`
- [ ] Zero `print()` em auth.lua e boot.lua
- [ ] `vHub:passengerMode` registrado no client
- [ ] README atualizado sobre `_invoker_allowed`
- [ ] `trusted_resources` populado por default em dev, warning em prod
- [ ] WAL implementado e testado
- [ ] Stress test: 200 players, 50 dirigindo, sem crash

### FASE 2 — Checklist
- [ ] `vhub_conce:saveVehicleState` chama `vhub:commitVehicleState`
- [ ] State Bags `vh_fuel`, `vh_eng`, `vh_body`, `vh_odo`, `vh_tune`, `vh_on`, `vh_driver`
      escritas em runtime
- [ ] `vHub:vehicleCommitted` disparado em cada commit
- [ ] `vhub_vehcontrol:skill.lua` escuta `vHub:vehicleCommitted` e reemite `SHEET`
- [ ] `vhub_garage:spawnVehicle` usa `vhub:applyVehicleState`
- [ ] `vhub_legacyfuel:updateFuel` chama `vhub:commitVehicleState`
- [ ] Zero `TriggerClientEvent(-1)` para despawn — migrado para State Bag
- [ ] Passageiros veem fuel/health mudar em tempo real via State Bag

### FASE 3 — Checklist
- [ ] `vhub:getVehicleDriver(plate)` export funciona
- [ ] `vhub:getVehiclePassengers(plate)` export funciona
- [ ] `vhub_vehcontrol:applyLock` enviado apenas para driver
- [ ] `vhub_vehcontrol:applyEngine` enviado apenas para driver
- [ ] `vhub_nitro:drainFx` enviado para driver + passageiros
- [ ] Telemetria usa delta sync
- [ ] Rate-limit ativo em todos os eventos frequentes
- [ ] Bandwidth server→clients reduzido em ≥ 50% vs FASE 2

### FASE 4 — Checklist
- [ ] Todos os exports privilegiados validam source
- [ ] Lock distribuído funciona cross-instance
- [ ] Rate-limit ativo em todos os server events
- [ ] Anti-teleport detecta movimento impossível
- [ ] Anti-speedhack detecta velocidade acima do tier
- [ ] `vhub_audit_unified` é append-only (trigger SQL)
- [ ] Penetration test: nenhum vetor conhecido funciona

### FASE 5 — Checklist
- [ ] `vh_vehicle_data` dropada (após 30 dias em prod)
- [ ] `vhub_vehicles.customization` dropada
- [ ] `vhub_nitro_state` dropada
- [ ] Eventos vestigiais removidos
- [ ] `vrp_legacyfuel:*` renomeado para `vhub_fuel:*`
- [ ] Zero literais hardcoded de eventos

### FASE 6 — Checklist
- [ ] `SetVehicleHandlingField` investigado (per-entity ou não)
- [ ] Se per-entity: migrado e testado (2 players, mesmo modelo, skills diferentes)
- [ ] Se não per-entity: skill sandbox implementado OU limitação documentada
- [ ] Drift tem `onResourceStop` que restaura handling
- [ ] Drift e vehcontrol não modificam os mesmos campos

### FASE 7 — Checklist
- [ ] `vhub_custom/server/exports.lua` criado com API read-only
- [ ] Cada recurso tem `API.md` documentando exports
- [ ] Eventos call-reply migrados para exports síncronos onde possível
- [ ] `vhub_admin:getConfig(resource, key)` funciona para qualquer recurso

### FASE 8 — Checklist (contínuo)
- [ ] Test suite CORE: 100% pass
- [ ] Test suite contratos: 100% pass
- [ ] Test suite E2E: 100% pass
- [ ] Stress test: 200 players, CPU < 60%, mem < 4GB, latência < 50ms
- [ ] Penetration test: zero vulnerabilidades conhecidas

---

## PARTE VI — MÉTRICAS DE SUCESSO

Como saber se a remediação funcionou?

### Métricas técnicas

| Métrica | Antes | Depois (meta) |
|---------|-------|---------------|
| Tráfego server→clients (peak) | ~5 MB/s (200 players) | ~2 MB/s |
| CPU server (peak) | ~80% | < 60% |
| Memória VRAM (24h) | Crescimento linear | Estável (eviction LRU) |
| Latência `commitVehicleState` | N/A (não existe) | < 5ms p99 |
| Latência `getVehicleState` | ~50ms (SQL fallback) | < 5ms p99 (VRAM hit) |
| State Bags ativas em runtime | 0 (DORMANT) | 7+ por veículo |
| Eventos `TriggerClientEvent(-1)` | 15+ | 0 |
| `print()` em produção | ~5 | 0 |
| Tabelas SQL deprecated | 3 | 0 |
| Eventos vestigiais | 25+ | 0 |
| Exports públicos por recurso | Variável (1-37) | ≥ 5 por recurso |

### Métricas de segurança

| Métrica | Antes | Depois (meta) |
|---------|-------|---------------|
| Exports sem validação de source | 1 (impoundVehicle) | 0 |
| Locks cross-instance | Não | Sim |
| Audit log imutável | Não | Sim (trigger SQL) |
| Penetration test: vetores abertos | Não testado | 0 |

### Métricas de maintainability

| Métrica | Antes | Depois (meta) |
|---------|-------|---------------|
| Recursos sem `server/exports.lua` | 1 (vhub_custom) | 0 |
| Recursos sem `API.md` | Todos | 0 |
| Literais hardcoded de eventos | 4+ | 0 |
| Decisões pragmáticas sem ADR | 1+ (workaround conce) | 0 (todas em ADR) |

---

## PARTE VII — PRINCÍPIOS RECONFIRMADOS PARA v2.0

Após a remediação, o CORE v2.0 deve seguir estes princípios sem exceção:

1. **CORE é autoridade, não hospedeiro.** O CORE não delega responsabilidade crítica para
   outros recursos. Se algo é crítico (estado, posse, dinheiro), é do CORE.

2. **vhub_conce é cache + validação, não fonte de verdade.** Após FASE 2, vhub_conce
   usa CORE exports. `vhub_vehicle_state` (tabela) é cache SQL do CORE, não fonte
   alternativa.

3. **Single-pilot-channel é regra.** Server fala com o motorista sobre telemetria.
   Passageiros recebem State Bags. Sem broadcast para todos.

4. **Tudo tem export.** Não existe recurso sem API pública. Recurso sem export é
   redundante ou morto.

5. **Anti-cheat em 3 camadas.** Client (UX) + Server (autoritativo) + Audit (forensia).
   Nunca apenas uma.

6. **Testes são obrigatórios.** Sem teste, sem merge. Cobertura mínima: 70% para
   exports, 100% para fluxos críticos.

7. **Deprecation tem prazo.** Nada de "deprecated mas funciona" por mais de 2 releases.
   Se deprecated, tem data de remoção.

8. **ADR é lei.** Toda decisão arquitetural é registrada em ADR numerada. Sem ADR,
   não é decisão — é acaso.

9. **Performance é contrato.** Cada export declara p99 esperado. Cada thread declara
   budget. Sem surpresa em produção.

10. **Documentação é código.** README, API.md, ADRs são versionados junto com código.
    Se divergem, é bug.

---

## APÊNDICE A — Lista completa de falhas (F-001 a F-079)

| # | Severidade | Recurso | Resumo |
|---|------------|---------|--------|
| F-001 | CRÍTICO | CORE | Handlers de veículo DORMENTES |
| F-002 | MÉDIO | CORE | README desatualizado em _invoker_allowed |
| F-003 | ALTO | CORE | _defaults morto |
| F-004 | BAIXO | CORE | fuel_rate divergente |
| F-005 | BAIXO | CORE | max_speed_kmh divergente |
| F-006 | BAIXO | CORE | Leak em Driver:_executar |
| F-007 | BAIXO | CORE | passengerMode não registrado no client |
| F-008 | ALTO | CORE | vehicleStateLoad emitido só em onEnter (dorminte) |
| F-009 | BAIXO | CORE | Spawn position hardcoded |
| F-010 | ALTO | CORE | Transações in-memory ≠ SQL atômico |
| F-011 | MÉDIO | CORE | Batch contamination trade-off |
| F-012 | BAIXO | CORE | assertThread apenas nos getters |
| F-013 | ALTO | CORE | VRAM sem TTL |
| F-014 | BAIXO | CORE | print() em auth.lua |
| F-015 | BAIXO | CORE | print() em boot.lua |
| F-016 | BAIXO | CORE | Clampagem de odômetro suspeita |
| F-017 | BAIXO | CORE | validar_config nunca usado |
| F-018 | BAIXO | CORE | Schema migration não automatizada |
| F-019 | ALTO | CORE | client/vehicle.lua envia mas ninguém escuta |
| F-020 | BAIXO | CORE | savePos removido sem migration clara |
| F-021 | ALTO | CORE | BLOB com blindagem b64 (sintoma) |
| F-022 | ALTO | CORE | trusted_resources vazio por default |
| F-023 | CRÍTICO | CORE | Gambiarra que deu certo (metodológico) |
| F-024 | ALTO | conce | vHub:vehicleCommitted nunca emitido |
| F-025 | MÉDIO | conce | vhub_vehicles.customization DEPRECATED |
| F-026 | MÉDIO | conce | Cache _cache sem GC |
| F-027 | ALTO | conce | test_drive_segundos=9999 (abuso) |
| F-028 | CRÍTICO | conce | vstate.lua é workaround, não solução |
| F-029 | MÉDIO | conce | reconcileOrphans nunca roda no boot |
| F-030 | BAIXO | conce | Backfill de collation em todo boot |
| F-031 | MÉDIO | conce | Hardcoded vhub_garage:doDespawn |
| F-032 | MÉDIO | conce/custom/vehcontrol | Índices de catálogo independentes |
| F-033 | ALTO | custom | Sem server/exports.lua |
| F-034 | MÉDIO | custom | GetClosestVehicle pega errado em zona densa |
| F-035 | BAIXO | custom | NUI sem timeout |
| F-036 | MÉDIO | custom | 4 literais hardcoded de eventos |
| F-037 | MÉDIO | garage | active_rental sempre 0 |
| F-038 | ALTO | garage | max_veiculos_player não enforced |
| F-039 | BAIXO | garage | Config.Classes/FuelUsage vestigiais |
| F-040 | BAIXO | garage | 9 eventos fuel vestigiais |
| F-041 | BAIXO | garage | 4 eventos sem emitter/handler |
| F-042 | ALTO | garage | Lock process-local |
| F-043 | ALTO | garage | TriggerClientEvent(-1) para despawn |
| F-044 | MÉDIO | fuel | Prefixo vrp_legacyfuel:* |
| F-045 | ALTO | garage | impoundVehicle sem validação |
| F-046 | MÉDIO | garage | Leitura direta de vhub_auctions |
| F-047 | BAIXO | fuel | /fuel admin parser ambíguo |
| F-048 | BAIXO | fuel | PRICE_PER_PCT hardcoded |
| F-049 | BAIXO | fuel | Galão R$300 fixo |
| F-050 | MÉDIO | fuel | Decor FUEL_LEVEL e State Bag vh_fuel paralelos |
| F-051 | ALTO | vehcontrol | skillDebug=true em prod |
| F-052 | ALTO | vehcontrol | skillBruteTest=true em prod |
| F-053 | CRÍTICO | vehcontrol | SetVehicleHandlingFloat model-wide |
| F-054 | MÉDIO | vehcontrol | R-3 ordem cobrança→persistência |
| F-055 | MÉDIO | vehcontrol | vHub:vehicleCommitted não escutado |
| F-056 | MÉDIO | vehcontrol | applyLock/applyEngine broadcast |
| F-057 | MÉDIO | vehcontrol | vhub_wow:searchResults pode ser broadcast |
| F-058 | ALTO | Drift | Sem onResourceStop |
| F-059 | ALTO | Drift | Conflito latente com vehcontrol |
| F-060 | BAIXO | vehcontrol | Rates em constantes locais |
| F-061 | BAIXO | racha | 11 eventos NUI mortos |
| F-062 | BAIXO | racha | Chaves de lang com typos |
| F-063 | BAIXO | racha | print() em bootstrap |
| F-064 | MÉDIO | racha | Anti-cheat gaps |
| F-065 | BAIXO | fuel | Nome "legacy" enganador |
| F-066 | MÉDIO | fuel | Sem sync client-client de fuel |
| F-067 | (ver F-044) | fuel | (duplicado) |
| F-068 | MÉDIO | balancer | Override só clamp em 1 campo |
| F-069 | BAIXO | balancer | tierOrder frágil |
| F-070 | MÉDIO | balancer | Rename não atualiza selo |
| F-071 | BAIXO | balancer | deriveArchetype threshold hardcoded |
| F-072 | CRÍTICO | transversal | Ausência de single-pilot-channel |
| F-073 | ALTO | transversal | Falta de audit log unificado |
| F-074 | ALTO | transversal | Falta de testes automatizados |
| F-075 | MÉDIO | transversal | Falta de health check |
| F-076 | MÉDIO | transversal | Falta de métricas de performance |
| F-077 | ALTO | transversal | Falta de migration framework |
| F-078 | MÉDIO | transversal | Falta de feature flags |
| F-079 | MÉDIO | transversal | Config espalhada |

---

## APÊNDICE B — ADRs propostas para v2.0

Novas ADRs a serem registradas ao concluir cada fase:

- **ADR #36:** Reativação de handlers de veículo com gate de segurança (FASE 1.1)
- **ADR #37:** `commitVehicleState`/`getVehicleState` como exports oficiais do CORE (FASE 1.2)
- **ADR #38:** `vh_vehicle_data` migra para JSON sem `b64:` (FASE 1.3, 1.10)
- **ADR #39:** VRAM eviction LRU + TTL (FASE 1.4)
- **ADR #40:** WAL para consistência VRAM/SQL pós-crash (FASE 1.11)
- **ADR #41:** vhub_conce como cache do CORE, não fonte alternativa (FASE 2.1)
- **ADR #42:** State Bags `vh_*` reativadas em runtime (FASE 2.2)
- **ADR #43:** `vHub:vehicleCommitted` evento oficial de mutation (FASE 2.3)
- **ADR #44:** Single-pilot-channel — server fala só com motorista (FASE 3.3)
- **ADR #45:** Delta sync para telemetria (FASE 3.4)
- **ADR #46:** Rate-limit server-side por event/plate (FASE 3.5)
- **ADR #47:** Lock distribuído cross-instance (FASE 4.2)
- **ADR #48:** `vhub_audit_unified` append-only com trigger SQL (FASE 4.6)
- **ADR #49:** Deprecation path para `vh_vehicle_data`, `vhub_vehicles.customization`,
  `vhub_nitro_state` (FASE 5.1-5.3)
- **ADR #50:** Renomeação `vrp_legacyfuel` → `vhub_fuel` (FASE 5.5)
- **ADR #51:** Resolução do Risco #1 — per-entity handling ou skill sandbox (FASE 6)
- **ADR #52:** Drift restrito a campos não-vehcontrol (FASE 6.4)
- **ADR #53:** Exports obrigatórios para todo recurso público (FASE 7.1)
- **ADR #54:** `vhub_admin:getConfig` centralizado para auditoria (FASE 7.4)
- **ADR #55:** `vhub_testrunner` obrigatório em CI (FASE 8)

---

## APÊNDICE C — Quick Reference: regras de ouro para code review

Antes de aprovar qualquer PR, validar:

- [ ] **R1:** Decisões críticas são server-side? (exceto R2)
- [ ] **R2:** Se client-side, é replay/animação/som/câmera/render?
- [ ] **R3:** Funcionalidade pública tem export?
- [ ] **R4:** Apenas UM escritor por campo?
- [ ] **R5:** Estado contínuo usa State Bag (não TriggerClientEvent -1)?
- [ ] **R6:** Handler institucional tem replay-guard?
- [ ] **R7:** Fronteira externa envolta em pcall?
- [ ] **R8:** Loop declara budget (Hz/ms)?
- [ ] **R9:** Eventos declarados em shared/events.lua (sem literal)?
- [ ] **R10:** Zero print() (usar Logger)?
- [ ] **R11:** PT-BR em comentários, EN em identificadores?
- [ ] **R12:** Mutação audita (source, actor, ts, before, after)?
- [ ] **R13:** Validação em 3 camadas (client + server + audit)?
- [ ] **R14:** Operação é idempotente?
- [ ] **R15:** Mudança de contrato tem deprecation path?

Se qualquer item falhar, PR é rejeitado.

---

**Fim do documento.**

> Este é um documento vivo. Toda falha nova identificada deve ser adicionada com novo
> `F-XXX`. Toda fase concluída deve ser marcada com data e responsável. Toda ADR nova
> deve ser numerada sequencialmente. O objetivo final é um CORE v2.0 estável, seguro,
> performático e sem gambiarras — onde "fazer funcionar onde deveria e como deveria"
> é a regra, não a exceção.
