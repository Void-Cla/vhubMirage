# vHub Mirage — Memória Institucional
_Escritor: `vhub_guardiao_revisao` | Atualizado: 2026-05-17 | Modelo: Claude Sonnet 4.6_

---

## Identidade do projeto

vHub Mirage é um framework FiveM GTARP server-authoritative escrito em Lua 5.4.
Objetivo: alternativa poderosa compatível com vRP1/2 (e futuramente vRP3) até ganhar nome no mercado.
Compatibilidade via `server/compat.lua` (shim `_G.vRP`, `_G.Proxy`, `_G.Tunnel`) — imutável até decisão explícita.

---

## Arquitetura e ownership

### Fluxo de runtime
```
K:net (evento cliente) → Auth:connect / Auth:getUser
  → State (VRAM-first → DB fallback)
  → Vehicle (registro, entidade, State Bags, autoridade NetworkSetEntityOwner)
  → Notify / Exports
  Autosave → State:_flush() (batch SQL atômico)
```

### Ownership por módulo

| Módulo | Arquivo | Responsabilidade canônica |
|--------|---------|--------------------------|
| Kernel | `server/kernel.lua` | event bus, rate limit, permissões, exports cross-resource |
| State | `server/state.lua` | VRAM, TX com rollback, batch SQL, get/set*Data |
| SQL | `server/sql.lua` | todos os `S:prepare()` — único lugar de SQL declarado |
| Auth | `server/auth.lua` | identidade (identifier priority), sessão, personagem, ban |
| Vehicle | `server/vehicle.lua` | registro, entidade, State Bags, odômetro, autoridade |
| Security | `server/security.lua` | ACE, payload check, `_permFail`, validators |
| Notify | `server/notify.lua` | webhooks Discord com retry |
| Compat | `server/compat.lua` | shim vRP1/2/3, Proxy, Tunnel — NÃO alterar API pública |
| Boot | `server/boot.lua` | `vHub:init()`, net events, autosave, flush emergência |
| Exports | `server/exports.lua` | exports cross-resource com `_invoker_allowed()` |
| Spawn | `server/modules/spawn.lua` | spawn server-side — carregado por último |
| Config | `shared/config.lua` | cria `vHub = {}`, `mergeConfig`, `validateConfig` |
| Events | `shared/events.lua` | constantes `vHub.E.*` (read-only via metatable) |
| Utils | `shared/utils.lua` | utilitários puros sem side-effects |
| Logger | `shared/logger.lua` | único ponto de log — `vHub.Logger` |
| Client Core | `client/core.lua` | notifica `vHub:ready`, recebe `vHub:initDone`, State Bags locais |
| Client Vehicle | `client/vehicle.lua` | report de estado 4Hz (fuel, health, rpm, odômetro delta) |
| Client Spawn | `client/modules/spawn.lua` | aplica `vHub:doSpawn` do servidor |

### Regra de extensão
Toda extensão em `resources/[CORE]/vhub` deve ser inserida **antes** dos exports da API original.
Ordem obrigatória em `server/init.lua`: `kernel → state → sql → notify → auth → vehicle → security → compat → boot → exports → modules/*`

---

## Padrão cliente–servidor (carga compartilhada)

- **Cliente processa**: física local, UI/HUD, odômetro delta, fuel delta, rpm — estado efêmero
- **Servidor valida**: recebe report do cliente 4Hz via `vHub:vState`, valida ranges (odômetro, fuel), aplica ao VRAM
- **Fallback**: se validação falhar por qualquer motivo → rollback para último estado válido salvo
- **State Bags**: servidor escreve (`VD:_syncBags()`), cliente lê — nunca o inverso para dados críticos
- **SQL**: exclusivamente server-side, transação atômica via `State:_flush()` (batch)

---

## Riscos ativos e mitigações aplicadas

| Risco | Mitigação |
|-------|-----------|
| Race em user_id | `vHub._next_user_id` seedado de `MAX(id)` + `vh/create_user_with_id` |
| Re-entrância em `_flush` | `S._flushing` guard + reenqueue com preservação de ordem |
| `Citizen.Await` fora de thread | `vHub.assertThread()` em todas as APIs públicas que usam Await |
| Payload malicioso do cliente | `vHub.Security:checkPayload()` em todo `K:net` antes do handler |
| Export cross-resource sem controle | `_invoker_allowed()` + `cfg.trusted_resources` whitelist |
| Double-connect (race playerConnecting) | `Auth._sessions` guard — `connect` só roda em `vHub:ready` |
| datatable crescendo indefinidamente | Invalidação de VRAM após `_set`; cópia plana em flush emergência |
| Ownership de entidade errado | `Veh:_validateOwner()` antes de salvar; `NetworkSetEntityOwner` |
| `S:prepare()` cross-resource silenciosamente perdido | Resources externos usam `exports.oxmysql` direto; schema próprio em `sql/schema.sql` aplicado em `onResourceStart` |
| Spawn duplicado (core + player_state) | Core sem spawn modules; `vhub_player_state` é dono único do fluxo de spawn |

---

## Decisões congeladas

1. **Código em inglês** (identificadores, APIs, variáveis); **PT-BR** para saídas, `lang.*`, comentários
2. `oxmysql` upstream inalterado; `vhub_oxmysql` como adaptador externo (driver plugável via `registerStateDriver`)
3. `multipleStatements=true` obrigatório na connection string
4. `msgpack` para serialização VRAM→SQL (não `json` — menor tamanho, mais seguro para binários)
5. `shared/logger.lua` é o único ponto de `print()` — qualquer módulo usa `vHub.Logger`
6. `server/compat.lua` mantém `_G.vRP`, `_G.Proxy`, `_G.Tunnel` enquanto compatibilidade vRP for ativa
7. **Spawn é dono único de `vhub_player_state`** — core não tem mais `server/modules/spawn.lua` nem `client/modules/spawn.lua` (removidos 2026-05-17). Eventos `vHub:doSpawn`, `vHub:savePos`, `vHub:localSpawned`, `vHub:firstSpawn` foram aposentados.
8. **SQL em resources externos NÃO usa `S:prepare()/S:query()` cross-resource** — FiveM serializa tabelas em exports e modificações em `self._prepared`/`self.queries` não persistem no core. Resources externos com tabelas próprias (ex: `vhub_identity`) usam `exports.oxmysql:query/execute` diretamente e aplicam schema próprio via `LoadResourceFile('sql/schema.sql')` no `onResourceStart`. **A regra "todas queries via State" do AGENTS.md aplica ao CORE vhub apenas.**
9. **Spawn handshake estilo Mirage (natives GTA, sem depender de `spawnmanager`)**: `client/bootstrap.lua` tenta o caminho natural primeiro (`AddEventHandler("playerSpawned", enviarReady)`). Se em até ~2s após `NetworkIsPlayerActive` o evento não disparar (janela total 60s), executa **spawn nativo via `NetworkResurrectLocalPlayer` + `ShutdownLoadingScreen`/`ShutdownLoadingScreenNui`** — exatamente como o Mirage faz em `client/base.lua`. Debounce de 5s em `enviarReady` impede duplo dispatch quando `playerSpawned` natural e fallback disparam juntos. `vhub_player_state` permanece "burro" para o spawn inicial — apenas teleporta+customiza ao receber `apply`.
10. **`vHub:ready` é enviado APENAS por `client/bootstrap.lua`** (em `playerSpawned` OU no fallback nativo). Sem `onClientResourceStart`, sem `SetTimeout` arbitrário. `client/core.lua` foi removido (duplicava handlers sem guard, causando 2 `vHub:playerSpawn` server-side). State Bags (`vhub_uid`, `vhub_user_id`, `vhub_char_id`, `vhub_pronto`, `vhub_primeiro_spawn`) consolidados em `bootstrap.lua`.
11. **Filosofia "native-first"**: preferir natives GTA V (`NetworkResurrectLocalPlayer`, `ShutdownLoadingScreen`, `SetEntityCoordsNoOffset`, etc.) sobre dependências externas (`spawnmanager`, etc.). Mais leve, mais robusto a ambientes mínimos, alinhado com L-05.

---

## Contratos de API pública (não quebrar)

### vHub.getUData / setUData / getCData / setCData / getVData / setVData / getGData / setGData
- Assinatura: `(id, key [, value [, tx]])` — estável
- Exige `Citizen.CreateThread` no chamador (usa `Citizen.Await` internamente via assertThread)

### exports do resource `vhub`
| Export | Assinatura | Proteção |
|--------|-----------|---------|
| `API` | `() → vHub` | pública (bootstrap) |
| `Status` / `Health` | `() → snapshot` | pública |
| `getVHub` | `() → vHub` | K:export |
| `getUser` | `(src) → User` | K:export |
| `getUID` | `(src) → uid` | K:export |
| `hasPerm` | `(uid, perm) → bool` | K:export |
| `grantPerm` | `(uid, perm)` | `_invoker_allowed()` |
| `getVehicle` | `(plate) → VD` | K:export |
| `transferKey` | `(plate, key)` | `_invoker_allowed()` |
| `banPlayer` | `(uid, r, by)` | `_invoker_allowed()` |
| `unbanPlayer` | `(uid)` | `_invoker_allowed()` |
| `registerStateDriver` | `(drv) → bool` | só aceita antes de `State._ready` |

---

## Status das sprints

| Sprint | Foco | Status |
|--------|------|--------|
| SPRINT 0 | `shared/` foundation | ✅ Concluído |
| SPRINT 1 | Estabilidade (race, flush, assertThread, exports guard, odômetro, owner) | ✅ Aplicado — **smoke tests em runtime pendentes** |
| SPRINT 2 | Organização (split `base.lua`, compat vRP) | 🔄 Gate `vhub_arquiteto` pendente |
| SPRINT 3 | Client-side (State Bags, report 4Hz) | 🔄 Estrutura inicial criada |
| SPRINT 4 | Segurança (ACE completo, payload hardening, rate stricter) | ⏳ |
| SPRINT 5 | Performance (flush tuning, GC, overhead threads) | ⏳ |
| SPRINT 6 | Observabilidade (logger estruturado, metrics, health) | ⏳ |
| SPRINT 7 | Testes e validação (smoke, integração DB, simulate players) | ⏳ |

---

## Ferramentas de teste

- `tools/run_tests.ps1` — checks estáticos no Windows
- `resources/[TOOLS]/vhub_testrunner` — runner server-side (comando: `vhub_run_tests`)
- **ATENÇÃO**: runner executa queries reais → usar APENAS em ambiente de teste

## Próximos passos imediatos

1. Executar smoke tests SPRINT 1 em runtime (ver `FREEZE_CANDIDATE_SPRINT1.md`)
2. Gate formal `vhub_arquiteto` para iniciar SPRINT 2 (split modular)
3. Varredura completa de strings expostas a operador/jogador → PT-BR
4. Completar client-side (SPRINT 3): State Bags de personagem, posição

## Bloqueios ativos

- Smoke tests SPRINT 1 dependem de ambiente FXServer com MySQL configurado
- SPRINT 2 bloqueada até aprovação formal do `vhub_arquiteto`
- `multipleStatements=true` na connection string deve ser verificado manualmente
