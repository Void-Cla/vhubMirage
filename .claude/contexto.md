# vHub Mirage — Memória Institucional
_Escritor: `vhub_guardiao_revisao` | Atualizado: 2026-05-22 (pós Frozen v1.0) | Modelo: Claude Opus 4.7_

---

## Identidade do projeto

vHub Mirage é um framework FiveM GTARP server-authoritative escrito em Lua 5.4.
Objetivo: framework próprio — 100% nativo, sem dependência de legado vRP.
**Compatibilidade vRP: removida em Frozen v1.0 (2026-05-22). `compat: none`.**

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
| Boot | `server/boot.lua` | `vHub:init()`, net events, autosave, flush emergência |
| Exports | `server/exports.lua` | exports cross-resource com `_invoker_allowed()` |
| Config | `shared/config.lua` | cria `vHub = {}`, `mergeConfig`, `validateConfig` |
| Events | `shared/events.lua` | constantes `vHub.E.*` (read-only via metatable) |
| Utils | `shared/utils.lua` | utilitários puros sem side-effects |
| Logger | `shared/logger.lua` | único ponto de log — `vHub.Logger` |
| Client Bootstrap | `client/bootstrap.lua` | entry-point único: notifica `vHub:ready`, recebe `vHub:initDone`, State Bags locais |
| Client Vehicle | `client/vehicle.lua` | report de estado 4Hz (fuel, health, rpm, odômetro delta) |
| **vhub_garage** | `[SCRIPTS]/vhub_garage/*` | **garage + dealership + auction + rental + impound + ipva + maintenance + clone/lend/transfer** — fonte de verdade dos veículos de negócio (não-físico) |

### Regra de extensão
Toda extensão em `resources/[CORE]/vhub` deve ser inserida **antes** dos exports da API original.
Ordem obrigatória pós-freeze em `server/init.lua`: `kernel → state → sql → notify → auth → vehicle → security → boot → exports`
**Sem `compat` — shim vRP removido em Frozen v1.0 (2026-05-22). `compat: none`.**

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
| Ownership de entidade errado | `NetworkSetEntityOwner` aplicado em `Veh:onEnter` quando driver entra |
| `S:prepare()` cross-resource silenciosamente perdido | Resources externos usam `exports.oxmysql` direto; schema próprio em `sql/schema.sql` aplicado em `onResourceStart` |
| Spawn duplicado (core + player_state) | Core sem spawn modules; `vhub_player_state` é dono único do fluxo de spawn |

---

## Decisões congeladas

1. **Código em inglês** (identificadores, APIs, variáveis); **PT-BR** para saídas, `lang.*`, comentários
2. `oxmysql` upstream inalterado; `vhub_oxmysql` como adaptador externo (driver plugável via `registerStateDriver`)
3. `multipleStatements=true` obrigatório na connection string
4. `msgpack` para serialização VRAM→SQL (não `json` — menor tamanho, mais seguro para binários)
5. `shared/logger.lua` é o único ponto de `print()` — qualquer módulo usa `vHub.Logger`
6. **`compat: none`** — `server/compat.lua` foi removido em Frozen v1.0 (2026-05-22). Sem `_G.vRP`, `_G.Proxy`, `_G.Tunnel`. Resources externos usam exclusivamente `exports.vhub:*`
7. **Spawn é dono único de `vhub_player_state`** — core não tem mais `server/modules/spawn.lua` nem `client/modules/spawn.lua` (removidos 2026-05-17). Eventos `vHub:doSpawn`, `vHub:savePos`, `vHub:localSpawned`, `vHub:firstSpawn` foram aposentados.
8. **SQL em resources externos NÃO usa `S:prepare()/S:query()` cross-resource** — FiveM serializa tabelas em exports e modificações em `self._prepared`/`self.queries` não persistem no core. Resources externos com tabelas próprias (ex: `vhub_identity`) usam `exports.oxmysql:query/execute` diretamente e aplicam schema próprio via `LoadResourceFile('sql/schema.sql')` no `onResourceStart`. **A regra "todas queries via State" do AGENTS.md aplica ao CORE vhub apenas.**
9. **Spawn handshake estilo Mirage (natives GTA, sem depender de `spawnmanager`)**: `client/bootstrap.lua` tenta o caminho natural primeiro (`AddEventHandler("playerSpawned", enviarReady)`). Se em até ~2s após `NetworkIsPlayerActive` o evento não disparar (janela total 60s), executa **spawn nativo via `NetworkResurrectLocalPlayer` + `ShutdownLoadingScreen`/`ShutdownLoadingScreenNui`** — exatamente como o Mirage faz em `client/base.lua`. Debounce de 5s em `enviarReady` impede duplo dispatch quando `playerSpawned` natural e fallback disparam juntos. `vhub_player_state` permanece "burro" para o spawn inicial — apenas teleporta+customiza ao receber `apply`.
10. **`vHub:ready` é enviado APENAS por `client/bootstrap.lua`** (em `playerSpawned` OU no fallback nativo). Sem `onClientResourceStart`, sem `SetTimeout` arbitrário. `client/core.lua` foi removido (duplicava handlers sem guard, causando 2 `vHub:playerSpawn` server-side). State Bags (`vhub_uid`, `vhub_user_id`, `vhub_char_id`, `vhub_pronto`, `vhub_primeiro_spawn`) consolidados em `bootstrap.lua`.
11. **Filosofia "native-first"**: preferir natives GTA V (`NetworkResurrectLocalPlayer`, `ShutdownLoadingScreen`, `SetEntityCoordsNoOffset`, etc.) sobre dependências externas (`spawnmanager`, etc.). Mais leve, mais robusto a ambientes mínimos, alinhado com L-05.
12. **`vhub_garage` centralizado (2026-05-20)**: absorve `vhub_dealership` (removido). Resource único cobre garage + concessionária + leilão + aluguel + pátio + IPVA + reparo + clone/empréstimo de chave + transferência P2P. Fonte de verdade de **negócio** (model/owner/status/IPVA/pátio/leilão) em `vhub_vehicles` (+ aux: `vhub_vehicle_keys`, `vhub_auctions`, `vhub_auction_bids`, `vhub_impound`, `vhub_dealership_stock`, `vhub_vehicle_log`). Estado **físico** (fuel/engine_health/body_health/odometer/tuning) permanece no CORE via `vHub.Vehicle._veh[plate]` + State Bags (L-04 respeitado). Chave-item física continua em `vhub_inventory`; autorização lógica adicional vive em `vhub_vehicle_keys` (kind=owner/shared/clone/rental). Tipos suportados: car/bike/plane/heli/boat/truck/trailer com surface spawn diferenciado.
13. **Superfície admin (2026-05-20)**: `vhub_garage/server/admin.lua` expõe operações para `vhub_admin` (TRUSTED: `vhub_admin`, `vhub`). Permissão de jogador é validada pelo `vhub_admin` antes de invocar; `admin.lua` apenas executa + audita via `vhub_vehicle_log`. Cobre leitura (stats/list/get/orphans/logs), escrita (give/transfer/delete/setStatus/repair/renewIpva/releaseImpound/cancelAuction/setStock/grantKey/revokeKey/spawnTo/despawn) e manutenção (purgeExpiredKeys/purgeOldLogs/finalizeStaleAuctions). Todos exports recebem `actor_src` opcional para registrar quem fez a ação.
14. **NUI bg.png compartilhado (2026-05-20)**: `vhub_garage/nui/assets/bg.png` é o background visual padrão para todos os projetos vHub. Aplicado em `#vhub-bg` via CSS com overlay de gradiente + blur. `vhub_admin/nui/assets/bg.png` é cópia local do mesmo asset.
15. **`vhub_admin` v2 modular (2026-05-21)**: refatorado em `shared/{config,events,utils,actions}` + `server/{sql,core,init,moderation,teleport,player,vehicle,world,spectator,reports,info,exports}` + `client/{init,noclip,teleport,player,vehicle,world,spectator,jail,commands,ui}` + NUI SPA (9 tabs: dashboard, players, moderation, teleport, vehicle, world, economy, reports, logs). Fonte de verdade de **negócios admin** (auditoria/jail/mute/reports) em SQL próprio (`vhub_admin_log`, `vhub_admin_jail`, `vhub_admin_mute`, `vhub_admin_reports`). Operações em domínios específicos (veículos, dinheiro, inventário, grupos, identidade) **delegam** via exports admin dos resources donos — `vhub_admin` é a CASCA (UI + slash commands + auditoria), respeitando L-04. Comandos novos: `/tp`, `/tptome`, `/tpgo` (waypoint), `/tpcds <x y z>`, `/tpall`, `/tplast` (volta), `/spec <id>` (espectador novo do zero via `NetworkSetInSpectatorMode`), `/rg <id>` (ficha completa cross-resource), `/cds` (unificado), `/jail` e `/mute` persistentes via SQL+cron, `/report` (jogador) e `/reports` (admin) com fila de tickets, `/adv`, `/weather`, `/time`, `/blackout`, `/clearzone`, `/fix`, `/tuning`, `/carcolor`, `/staff`, `/healall`, `/reviveall`, `/invis`, `/kill`, `/skin`. Hotkey `F6` via RegisterKeyMapping.

16. **CORE FROZEN v1.0 (2026-05-22)** — Frozen Plan v1.0 aplicado:
    - Compat vRP removido (`compat: none`); shim `_G.vRP`/`_G.Proxy`/`_G.Tunnel` extinto.
    - `BATCH_MAX 150→800`, `BATCH_INT 5000→3000ms`; autosave chunked com `Wait(0)` a cada 50.
    - `vHub.SQL.uidByIdsIn(n)` lazy-cache (login N→1 round-trip).
    - State Bag com thresholds (fuel 0.5 / eng 5.0 / body 5.0 / odo 0.05 km) + bypass quando `value==0` (G1).
    - Adaptive client report (2000/1000/250 ms).
    - GC `_byNet` cron 5min; GC `Kernel._rate` em `playerDropped`.
    - Schema consolidado em `sql/schema.sql` único (idempotente, FK CASCADE, `utf8mb4_unicode_ci`).
    - 4 arquivos zumbis removidos (`client/core.lua`, `server/utils.lua`, `server/modules/`, `client/modules/`).
    - Core LOC: 2.813 → **2.432** (-381). Auditoria em `.claude/auditorias/core_audit_v1.md`.

17. **Tipos PK canônicos (2026-05-22)** — após zerar banco em testes, qualquer schema externo com FK ao core **DEVE** usar `INT UNSIGNED`:
    - `vh_users.id`, `vh_characters.id`, `vh_vehicles.plate` (não-INT) são as PKs canônicas.
    - FK com tipo divergente (ex: `INT` signed em `vh_identity.char_id`) dispara `errno 150 (foreign key constraint incorrectly formed)`.
    - `vhub_identity/sql/schema.sql` corrigido pós-incidente. `vhub_garage` e `vhub_admin` já estavam corretos.
    - Padrão obrigatório documentado em `metas/manual_dev_vhub.md` seção 3.4.1.

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

Todas as SPRINTs 0–7 foram **absorvidas pelo Frozen Plan v1.0** (2026-05-22). Core congelado por 12+ meses.

| Sprint | Foco | Status |
|--------|------|--------|
| SPRINT 0 | `shared/` foundation | ✅ Concluído |
| SPRINT 1 | Estabilidade (race, flush, assertThread) | ✅ Absorvido em Frozen F1+F2 |
| SPRINT 2 | Organização (split modular, remoção compat) | ✅ Absorvido em Frozen F2 |
| SPRINT 3 | Client-side (State Bags, report adaptive) | ✅ Absorvido em Frozen F4.3 |
| SPRINT 4 | Segurança (`_invoker_allowed`, payload check) | ✅ Pré-existente, validado em Frozen |
| SPRINT 5 | Performance (batch tuning, GC, thresholds) | ✅ Absorvido em Frozen F3+F4+F5 |
| SPRINT 6 | Observabilidade (logger, GC logs) | ✅ Absorvido em Frozen + patch G3 |
| SPRINT 7 | Testes e validação (T1..T11) | 🟡 T6–T11 PASS estático; T1–T5 dependem de runtime |

**Próxima janela de evolução:** 2027-05-22 (re-auditoria do core, ou bug crítico documentado).

---

## Ferramentas de teste

- `tools/run_tests.ps1` — checks estáticos no Windows
- `resources/[TOOLS]/vhub_testrunner` — runner server-side (comando: `vhub_run_tests`)
- **ATENÇÃO**: runner executa queries reais → usar APENAS em ambiente de teste

## Próximos passos imediatos

1. Executar smoke tests T1..T5 em runtime (instruções em `FROZEN_EXEC_LOG.md`)
2. Foco move-se para **resources externos** (`vhub_garage`, `vhub_admin`, `vhub_identity`, novos scripts) — usar `metas/manual_dev_vhub.md`
3. Toda nova feature: resource externo seguindo template do manual (FK `INT UNSIGNED`, `BLOB`, `CASCADE`, schema idempotente)

## Bloqueios ativos

- Smoke tests T1..T5 dependem de ambiente FXServer + MariaDB + injeção de carga
- `multipleStatements=true` na connection string deve ser verificado manualmente (pré-requisito do `bootstrap.lua:307` que aplica schema em multi-statement)
- Banco pré-existente com `MEDIUMBLOB` em `vh_*_data` continua funcionando (schema é `CREATE IF NOT EXISTS`). Otimização para `BLOB` documentada no header de `sql/schema.sql`

---

## Estado de congelamento

**CORE FROZEN v1.0 — selado em 2026-05-22**

| Aspecto | Valor |
|---|---|
| Data do congelamento | 2026-05-22 |
| Janela de revisão | +12 meses (próxima: 2027-05-22) |
| LOC do core (pós-freeze) | -257 (zumbis) -70 (compat) -42 (DRY) -11 (validateOwner) ≈ **-380 LOC líquido** |
| Arquivos removidos | `client/core.lua`, `server/utils.lua`, `server/modules/`, `client/modules/`, `server/compat.lua` (-5) |
| Schema SQL | `sql/schema.sql` único (idempotente), aplicado em `bootstrap.lua:307` a cada boot. Antigos `fix_*.sql` consolidados. |
| Tipo PK canônico | `vh_users.id`, `vh_characters.id` = `INT UNSIGNED AUTO_INCREMENT`. Schemas externos com FK **devem** usar `INT UNSIGNED`. |
| FK do core | `ON DELETE CASCADE ON UPDATE CASCADE` em todas as tabelas dependentes |
| Compat vRP | **`compat: none`** — shim totalmente removido |
| Ordem de carga `server/init.lua` | `kernel → state → sql → notify → auth → vehicle → security → boot → exports` |

### Itens aplicados (F1..F6)

- **F1** Purga de 4 arquivos zumbis (`client/core.lua`, `server/modules/`, `client/modules/`, `server/utils.lua`).
- **F2** Remoção integral de `server/compat.lua`; F2.1 confirmou zero call-sites externos.
- **F3** `BATCH_MAX 150→800`, `BATCH_INT 5000→3000`; autosave/onResourceStop/Auth via `vHub.Utils.dataCopy` + chunked `Wait(0)` a cada 50.
- **F4** `vh/uid_by_ids_in_N` lazy-cache (N round-trips → 1); cadência adaptiva client (2000/1000/250 ms); thresholds delta em State Bag (fuel 0.5 / eng 5.0 / body 5.0 / odo 0.05) com `_last_*_bag=-math.huge`.
- **F5** GC `_byNet` 300s yield/100; GC `Kernel._rate` por prefixo `src:` em `playerDropped`.
- **F6** Migration `BLOB` (era `MEDIUMBLOB`); `Veh:_validateOwner` removida; cache `_RES` em `boot.lua`/`base.lua`; comentário "KNOWN MINOR LEAK" em `bootstrap.lua`.

### Métricas alvo (smoke gate T1..T11 em runtime)

| Métrica | Alvo | Origem |
|---|---|---|
| Resmon server idle | < 0.05 ms | T1 |
| Resmon server tick (100 sessões) | < 0.20 ms | T2 |
| Resmon client idle | < 0.10 ms | T3 |
| Stall máx. autosave (200 sessões) | < 5 ms | T4 |
| Flushes/ciclo em pico | ≤ 5 | T5 |
| LOC final do core | ≤ 2.556 | T11 |

### Regra de modificação pós-freeze

Qualquer alteração em `resources/[CORE]/vhub/**` exige:
1. Justificativa por escrito (incidente, requisito legal, bug crítico).
2. Aprovação consolidada de `vhub_arquiteto` + `vhub_guardiao_revisao`.
3. Bump de major: `core-frozen-v2.0` (não patch).

Para extensões/novas features, criar resource externo em `resources/[SCRIPTS]/vhub_*` seguindo `metas/manual_dev_vhub.md`.
