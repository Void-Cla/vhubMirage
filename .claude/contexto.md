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

## Ownership por resource externo

### vhub_racha (resource externo — `resources/[SCRIPTS]/vhub_racha`)

| Módulo | Arquivo | Responsabilidade canônica |
|--------|---------|--------------------------|
| Boot server | `server/bootstrap.lua` | handshake com vhub core; fila `on_ready`; re-emite `vHub:initDone` |
| Boot client | `client/bootstrap.lua` | 3 caminhos determinísticos para READY; sem polling 60s |
| Sessions | `server/sessions.lua` | cache `{ [src] = user }` via `vHub:characterLoad` + `playerDropped` |
| Grid | `server/grid.lua` | geometria: ready-zone, alloc/free de slot, spawn_for |
| Lobby | `server/lobby.lua` | máquina de estados: lobby → pending → warmup (totem obrigatório) |
| Runtime | `server/runtime.lua` | corrida ativa: begin_racing → checkpoint → tick → finish |
| Rewards | `server/rewards.lua` | fronteira única com `vhub_money` (charge/refund/pay) |
| Editor | `server/editor.lua` | editor visual de pistas (draft + save → SQL) |
| Events | `shared/events.lua` | fonte única de nomes de eventos `VHubRachaE.*` |
| NUI Bridge | `client/nui_bridge.lua` | ponte Lua→NUI: bag_key diff, **telemetria 4Hz (FONTE ÚNICA)**, NUICallbacks |
| Totem | `client/totem.lua` | **totem 3D NATIVO** (DrawMarker/DrawText) — fonte única, sem versão NUI |
| Countdown | `client/countdown.lua` | só camera shake nativo no GO (a contagem visual é NUI) |
| Web Runtime (L3) | `web/runtime/{bus,store,bridge,sand,core}.js` | engine NUI: bus, store, bridge, sand, lifecycle |
| HUD (L4) | `web/modules/hud/hud.js` | overlay in-race (timer/pos/volta/cp/drift) — **sem fundo, texto+glow** |
| Panel (L4) | `web/modules/panel/panel.js` | menu /racha: shell + 5 views (tracks/lobbies/ranking/history/editor) + modal |
| Race (L4) | `web/modules/race/race.js` | overlay da ready-zone (card de instrução + ancora) |

**Decisão de arquitetura (2026-05-28):** `manager.lua` (606 LOC, órfão) deletado. `VHubRachaSessions` é o único cache de sessão — alimentado por evento público `vHub:characterLoad` (confirmado em `core/server/auth.lua:325`; `user.source` existe), não por acesso a `_sessions` privado.

**Fluxo de confirmação (totem obrigatório):** TODOS os modos (rankeada, treino, timeattack, freerun) passam pelo totem. Nenhum modo teleporta sem `L.confirm_presence` server-side, validado por `GetEntityCoords` server-side (L-01).

**Decisão TOTEM nativo (2026-05-29):** o totem é 3D world-space → **só existe como DrawMarker nativo** (`client/totem.lua`), nunca NUI. Tentativas de totem NUI (projeção 2D) foram descartadas: não renderizavam de forma confiável no CEF e duplicavam o nativo ("totem fantasma"). Native-first (L-05) + zero duplicação. O totem escala 999m=mais alto → 0m=some.

**Decisão FONTE ÚNICA de telemetria (2026-05-29):** `race.lua` enviava `vhub_racha.telemetry` em paralelo ao `nui_bridge.lua` (20Hz vs 4Hz) com `elapsed_ms` divergente → cronômetro do HUD pulava. Consolidado: **telemetria só em `nui_bridge.lua`; totem só em `totem.lua`; `race.lua` só detecta CP + define alvo do totem.** Um emissor por concern.

**Decisão NUI migrada para `web/` (2026-05-28/29):** `ui_page` aponta para `web/index.html`; o legado `nui/` (app.js 1051 LOC + style.css 1831 LOC) foi **deletado**. HUD Lua DrawText (`client/hud.lua`) também deletado — o HUD é 100% NUI. `client/race.lua` não tem mais HUD.

---

## Contratos de API pública (não quebrar)

### vhub_racha — exports públicos

| Export | Proteção | Assinatura |
|--------|----------|------------|
| `catalog` | pública | `() → []track` |
| `lobbies` | pública | `() → []lobby` |
| `isInRace` | pública | `(src) → bool` |
| `isReady` | pública | `() → bool` |
| `Status` | pública | `() → snapshot` |
| `topRanking` | pública | `(kind, mode, limit) → []` |
| `historyRecent` | pública | `(filters, limit) → []` |
| `resultsOf` | pública | `(history_id) → []` |
| `statsOfChar` | pública | `(char_id) → stat` |
| `recordsOfChar` | pública | `(char_id, limit) → []` |
| `createLobby` | `_invoker_allowed()` | `(src, payload) → ok, data` |
| `cancelLobby` | `_invoker_allowed()` | `(inst_id, reason) → ok` |
| `deleteTrack` | `_invoker_allowed()` | `(track_id) → ok` |

**Eventos de rede canônicos (VHubRachaE):** nomes migrados de `shared/enums.lua` para `shared/events.lua` em SPRINT-RACHA-1. Os nomes em si NÃO mudaram — apenas o arquivo de origem. Contratos mantidos.

**NUI callbacks canônicos:** `nui_ready`, `vhub_racha.action`, `vhub_racha.request_sync`

**SendNUIMessage types canônicos (web/):**
- HUD: `hud_show` (inclui `kind` p/ chip de drift), `hud_hide`, `hud_start`, `hud_countdown`, `hud_finish`, `vhub_racha.telemetry`, `vhub_racha.bag_update`
- Painel: `{ action = 'open'|'close'|'refresh'|'result'|'ranking'|'history'|'results'|'race_finish' }`
- Ready-zone: `vhub_racha.lobby.pending`, `vhub_racha.lobby.confirmed`, `vhub_racha.readyzone.project`, `vhub_racha.readyzone.clear`
- **REMOVIDO**: `vhub_racha.totem.*` (totem é nativo, não NUI). Dispatcher único em `web/runtime/core.js` roteia `action`/`type` → bus `nui:*`.

---

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

### vhub_racha — Sprints externas

| Sprint | Foco | Status |
|--------|------|--------|
| SPRINT-RACHA-1 | Arquitetura base (sessions, grid, lobby, runtime) | ✅ Aprovado (gate revisao 2026-05-28) |
| SPRINT-RACHA-2 | Refactor estilo humano (rewards, editor, checkpoints) | ✅ Aprovado (gate revisao 2026-05-28) |
| SPRINT-RACHA-3 | Web runtime + módulos (hud/panel/race) + migração total | ✅ Concluído; `ui_page`→web/, `nui/` legado deletado |
| SPRINT-RACHA-3.1 | Totem nativo único + fonte única telemetria + HUD sem fundo + fixes (timer MM:SS, drift sempre visível em drift, card 5s) | ✅ Concluído (2026-05-29) — pendente validação runtime |
| SPRINT-RACHA-4 | `while true` telemetria client/nui_bridge.lua (deferido) | ⏳ Pendente — risco baixo documentado |
| SPRINT-RACHA-5 | Assets locais (fonts/icons) em vez de CDN; drift tuning se necessário | ⏳ Pendente |

---

## Ferramentas de teste

- `tools/run_tests.ps1` — checks estáticos no Windows
- `resources/[TOOLS]/vhub_testrunner` — runner server-side (comando: `vhub_run_tests`)
- **ATENÇÃO**: runner executa queries reais → usar APENAS em ambiente de teste

## Próximos passos imediatos

1. Executar smoke tests T1..T5 em runtime (instruções em `FROZEN_EXEC_LOG.md`)
2. Foco move-se para **resources externos** (`vhub_garage`, `vhub_admin`, `vhub_identity`, novos scripts) — usar `metas/manual_dev_vhub.md`
3. Toda nova feature: resource externo seguindo template do manual (FK `INT UNSIGNED`, `BLOB`, `CASCADE`, schema idempotente)
4. **SPRINT-RACHA-4**: substituir `while true` em `client/nui_bridge.lua:112` por `CreateThread` com condição de saída explícita (variável `_running` ligada a `onResourceStop`)

## Bloqueios ativos

- Smoke tests T1..T5 dependem de ambiente FXServer + MariaDB + injeção de carga
- `multipleStatements=true` na connection string deve ser verificado manualmente (pré-requisito do `bootstrap.lua:307` que aplica schema em multi-statement)
- Banco pré-existente com `MEDIUMBLOB` em `vh_*_data` continua funcionando (schema é `CREATE IF NOT EXISTS`). Otimização para `BLOB` documentada no header de `sql/schema.sql`
- `vhub_racha`: `while true` em `client/nui_bridge.lua` (loop de telemetria 250ms) sem condição de saída explícita — risco baixo (resource stop limpa threads FiveM), mas viola L-06. Registrado para SPRINT-RACHA-4.
- `vhub_racha`: `web/index.html` carrega Google Fonts e Font Awesome via CDN externo — risco de latência em ambiente sem internet. A migrar para assets locais na SPRINT-RACHA-5.
- `vhub_racha`: pendente **validação em runtime** das correções de 2026-05-29 (totem nativo aparecendo, cronômetro MM:SS, drift acumulando, card de chegada sumindo em 5s). Se o drift travar em 0 mesmo driftando → ajustar `Cfg.DRIFT.MIN_ANGLE_DEG`/`MIN_SPEED_KMH`.

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
