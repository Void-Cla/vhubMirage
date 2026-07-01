# 06 — Análise Profunda: `vhub_racha` + `Drift`

> Recursos analisados a partir de `SCRIPTS/vhub_racha` (v3.1.0, 60+ arquivos) e `SCRIPTS/Drift` (v0.2.0, 3 arquivos). Comparação com `vhubMirage/resources/[SCRIPTS]/` → **zero diferença de conteúdo** (apenas CRLF vs LF em `relatorio.md`). Referência cruzada com `manual_dev_vhub.md` v2.0 e com os 4 relatórios anteriores (02–05) já entregues.

---

## 1. Visão Geral

### 1.1 Papel no ecossistema vHub
`vhub_racha` é a **"liga clandestina premium"** de corridas — uma plataforma competitiva com 7 modos de jogo, lobby/sessions/grid, ranking persistido, sistema ranqueado PDL estilo CS2 (Elo FFA), editor visual de pistas, anti-cheat server-side, telemetria adaptativa e HUD/NUI componentizada. Depende explicitamente (fxmanifest.lua:11-17) de `oxmysql`, `vhub`, `vhub_money`, `vhub_identity`, `vhub_groups`.

- `fx_version 'cerulean'`, `lua54 'yes'`, v3.1.0
- `ui_page 'web/index.html'` — NUI componentizada (runtime + shared + módulos)
- Arquitetura server-authoritative; cliente só envia "intenção" (checkpoint, tick, abort) — tudo é validado.
- 27 eventos centralizados em `shared/events.lua` (VHubRachaE.*); 7 tabelas SQL em `vh_race_*`.

### 1.2 Modos de corrida (7 kinds)
Definidos em `shared/enums.lua` (VHubRachaKind):

| Kind | Mecânica principal | Implementação |
|---|---|---|
| `sprint` | A→B simples, 1+ voltas | `client/modes/sprint.lua` (no-op, base) |
| `circuit` | Voltas múltiplas, melhor volta | `client/modes/circuit.lua` (calcula `best_lap_ms`) |
| `drag` | 1/4 milha (árvore de largada) | `client/modes/drag.lua` (no-op — visual via `countdown.lua`) |
| `drift` | Pontuação por drift | `client/modes/drift.lua` + recurso **Drift** (export `getTelemetry`) |
| `speedtrap` | Soma velocidade nos radares + combo | `client/modes/speedtrap.lua` |
| `timeattack` | Solo contra o tempo | `client/modes/timeattack.lua` (no-op) |
| `freerun` | Exploração livre, sem CPs | `client/modes/freerun.lua` (no-op) |

### 1.3 Papel do recurso `Drift` (separado)
`Drift` (v0.2.0, `cl.lua` + `fxmanifest.lua` + `README.md`) é o **fabricante da mecânica de drift** e da **pontuação bruta**. Não tem UI, não banca pontos, não persiste. Apenas:

- Aplica **handling drift** (`SetVehicleHandlingFloat` para 7 campos: `fSteeringLock`, `fTractionCurveMax/Min/Lateral`, `fLowSpeedTractionLossMult`, `fDriveInertia`, `fInitialDragCoeff`) quando o player acelera + freio de mão > 20 km/h.
- Ativa **boost** controlado (anti-exploit): exige ângulo ≥ 20°, cooldown 4 s, duração 1.2 s, multiplicador de potência `1.2 * 2.0` ou `1.2` (com tapering por ângulo em curvas <100 km/h).
- **Fabrica** `totalEarned` (monotônico, `pps = min(ângulo*velocidade/65, 100) * combo * dt`), `crashCount`, `combo`, `angle`, `speed`, `drifting`, `active` — exposto por `exports.Drift:getTelemetry()`.
- **`vhub_racha/client/modes/drift.lua`** é o **banco** — consome o `getTelemetry()`, calcula `drift_score` (bancado) vs `drift_live` (bancado + pendente), descarta o lote pendente ao bater, banca a cada `BANK_MS=5000` ms sem bater.

### 1.4 Diferença: drift como MODO vs drift como FÍSICA
- **Modo `drift`** (vhub_racha): regra de **banco** (5 s sem bater → válido), HUD, persistência no `vh_race_results.drift_score`, ranqueado, payout. Vencedor = maior `drift_score` (desempate por `total_time_ms` — `server/history.lua:38-40`).
- **Física de drift** (Drift): modifica handling do veículo em tempo real + calcula pontuação bruta. Não sabe que há uma corrida; independe do vhub_racha. Pode ser usada em qualquer cenário (free-roam, eventos), mas a bancagem só vira ranking quando vhub_racha/modes/drift está ativo.

---

## 2. SQL Schema (DETAILED)

`sql/schema.sql` — 7 tabelas InnoDB `utf8mb4_unicode_ci`. **Nenhuma tabela `race_laps`, `drift_scores`, `drag_times` separada** — todas as modalidades usam as mesmas tabelas genéricas. FKs CASCADE para `vh_race_tracks(id)` e `vh_characters(id)` (core).

### 2.1 `vh_race_tracks` (pistas — config + custom)
```sql
CREATE TABLE IF NOT EXISTS `vh_race_tracks` (
  `id`              VARCHAR(48)      NOT NULL,
  `label`           VARCHAR(80)      NOT NULL DEFAULT '',
  `district`        VARCHAR(60)      NOT NULL DEFAULT '',
  `kind`            VARCHAR(24)      NOT NULL DEFAULT 'sprint',
  `creator_char`    INT UNSIGNED     NOT NULL DEFAULT 0,
  `illegal`         TINYINT UNSIGNED NOT NULL DEFAULT 1,
  `alerts_police`   TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `laps`            INT UNSIGNED     NOT NULL DEFAULT 1,
  `min_players`     INT UNSIGNED     NOT NULL DEFAULT 1,
  `max_players`     INT UNSIGNED     NOT NULL DEFAULT 8,
  `vehicle_class`   VARCHAR(16)      NOT NULL DEFAULT 'car',
  `default_fee`     INT UNSIGNED     NOT NULL DEFAULT 0,
  `limit_seconds`   INT UNSIGNED     NOT NULL DEFAULT 300,
  `start_x/y/z/h`   DOUBLE,
  `source`          ENUM('config','custom') NOT NULL DEFAULT 'config',
  `category`        ENUM('ranqueada','normal','personalizada') NOT NULL DEFAULT 'normal',
  `enabled`         TINYINT UNSIGNED NOT NULL DEFAULT 1,
  `created_at`      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `updated_at`      TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_tracks_kind` (`kind`),
  KEY `idx_tracks_source` (`source`)
)
```
Sem FK — `creator_char` é "mole" (INT sem FK para permitir `0` em pistas do config). Categoria é fixa da pista (FAIL-CLOSED — nunca vem do cliente, `server/lobby.lua:150`).

### 2.2 `vh_race_checkpoints` (CPs por pista)
PK composta `(track_id, idx)`. FK CASCADE para `vh_race_tracks(id)`. Colunas `x, y, z DOUBLE`, `radius DOUBLE DEFAULT 11.0`, `kind VARCHAR(16) DEFAULT 'normal'`.

### 2.3 `vh_race_grid` (slots de largada)
PK composta `(track_id, slot)`. FK CASCADE. Colunas `x, y, z DOUBLE, h DOUBLE DEFAULT 0`.

### 2.4 `vh_race_history` (corrida finalizada — 1 linha por corrida)
```sql
CREATE TABLE IF NOT EXISTS `vh_race_history` (
  `id`              BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  `track_id`        VARCHAR(48),
  `kind`            VARCHAR(24)      DEFAULT 'sprint',
  `mode`            ENUM('rankeada','treino','privada') DEFAULT 'rankeada',
  `category`        ENUM('ranqueada','normal','personalizada') DEFAULT 'normal',
  `creator_char`    INT UNSIGNED,
  `players_total`   INT UNSIGNED,
  `winner_char`     INT UNSIGNED,
  `winner_time_ms`  BIGINT UNSIGNED,
  `pot_total`       BIGINT UNSIGNED,
  `started_at`      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `finished_at`     TIMESTAMP NULL,
  PRIMARY KEY (`id`),
  KEY idx_hist_track (track_id), KEY idx_hist_winner (winner_char),
  KEY idx_hist_kind (kind), KEY idx_hist_mode (mode),
  KEY idx_hist_category (category), KEY idx_hist_started (started_at)
)
```
`mode` (sessão: como rodou) e `category` (pista: dimensão ortogonal) — filtro de temporada = `WHERE category='ranqueada' AND mode='rankeada'` (comentário schema.sql:65-66).

### 2.5 `vh_race_results` (1 linha por jogador por corrida)
PK composta `(history_id, char_id)`. FK CASCADE para `vh_race_history(id)`. Colunas: `placement`, `total_time_ms`, `best_lap_ms`, `drift_score`, `top_speed`, `finished TINYINT`, `payout BIGINT`.

### 2.6 `vh_race_records` (record pessoal por pista)
PK composta `(track_id, char_id)`. FK dupla CASCADE para `vh_race_tracks(id)` e `vh_characters(id)`. Colunas: `best_time_ms`, `best_drift`, `top_speed`, `runs`, `wins`. Atualizado por `SQL.update_records` com `INSERT ... ON DUPLICATE KEY UPDATE` idempotente (`best_time_ms = IF(? > 0 AND (best_time_ms = 0 OR ? < best_time_ms), ?, best_time_ms)`).

### 2.7 `vh_race_stats` (estatísticas por personagem por modalidade)
PK composta `(char_id, kind)`. FK CASCADE para `vh_characters(id)`. Colunas: `runs`, `wins`, `podiums`, `dnf`, `total_payout`, `total_drift`, `top_speed`, `best_time_ms`. Atualização monotônica (GREATEST/IF).

### 2.8 `vh_race_ranked` (PDL global por personagem — escritor único = `server/ranked.lua`)
```sql
CREATE TABLE IF NOT EXISTS `vh_race_ranked` (
  `char_id`        INT UNSIGNED     NOT NULL,
  `pdl`            INT              NOT NULL DEFAULT 1000,   -- com sinal: delta Elo pode ser negativo
  `peak_pdl`       INT              NOT NULL DEFAULT 1000,
  `matches`        INT UNSIGNED     NOT NULL DEFAULT 0,
  `wins`           INT UNSIGNED     NOT NULL DEFAULT 0,
  `last_match_at`  INT UNSIGNED     NOT NULL DEFAULT 0,
  `updated_at`     TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`char_id`),
  KEY `idx_ranked_pdl` (`pdl`),
  CONSTRAINT `fk_ranked_char` FOREIGN KEY (`char_id`)
    REFERENCES `vh_characters` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
)
```
`pdl` é `INT` (signed) — delta Elo pode ser negativo; clamp ≥ `MIN_PDL=100` no escritor evita rating abaixo do piso.

### 2.9 Compat schema (upgrades)
`SQL.apply_schema()` em `server/sql.lua:388-421` aplica o `schema.sql` raw + 3 ALTERs idempotentes via `ensure_column('vh_race_history', 'mode'|'category')` e `ensure_column('vh_race_tracks', 'category')` — cobre migração de schemas antigos sem `ALTER TABLE` destrutivo.

---

## 3. Arquitetura Server

### 3.1 `server/bootstrap.lua` — handshake com CORE
Carrega **PRIMEIRO** em `server_scripts`. Cria `VHubRachaBoot = { READY=false, vHub=nil, _on_ready={} }`. Inicia thread que faz polling lento (250 ms × 240 = 60 s) por `exports.vhub:getVHub()` até responder com tabela que tem `.Auth`. Quando OK, `_emit_ready()`:
1. Seta `B.READY = true`
2. Roda callbacks registrados via `B.on_ready(fn, name)` em ordem de registro (cada um em pcall).
3. `TriggerEvent('vhub_racha:boot:ready')`.

**Registra o evento** `REQUEST_INIT_DONE` (client→server) — re-emite `vHub:initDone` para o src autenticado (fonte: `VHubRachaSessions.get(src)`). Idempotente. Resolve race de listener tardio no cliente.

### 3.2 `server/sessions.lua` — cache de usuários
Cache local `_cache = { [src] = user }` populado por 2 eventos públicos do vhub core:
- `vHub:characterLoad` (server-side) → `_cache[src] = user`
- `playerDropped` → `_cache[src] = nil`

API: `S.get(src)` retorna imediato (zero Wait/retry); `S.put(src,user)` (manual, testes); `S.count()`. Substitui o antigo `user_of()` que violava contrato acessando `_vHub.Auth._sessions`.

### 3.3 `server/state.lua` — VRAM da liga
`VHubRachaState` é o cache em memória:
- `_catalog = {}` — pistas (config + custom), chaveado por `id` (populado por `SQL.load_catalog()` no boot).
- `_instances = {}` — instâncias de corrida ativas, chaveadas por `inst_id` (8-char `short_id()`).
- `_by_src = {}` — mapeia `src → inst_id` (jogador em corrida).
- `_drafts = {}` — drafts do editor por `char_id`.
- `metrics = { instances_created, instances_started, instances_finished, drafts_saved }`.

API: `set_catalog/catalog/track/put_instance/instance/remove_instance/instance_by_src/bind_src/unbind_src/count_players/public_lobbies/draft_get/draft_set/draft_clear/gc_drafts/status_snapshot`.

`public_lobbies()` retorna lista de instâncias em estado `'lobby'|'pending'` com `has_password=true/false` (senha **nunca** é exposta).

### 3.4 `server/sql.lua` — wrapper oxmysql + queries
Camada fina sobre `exports.oxmysql:query/execute`. Três funções base (`query/execute/execute_raw`) usam `promise.new()` + `Citizen.Await()`. Queries de domínio:
- `upsert_track(t)` — `INSERT ... ON DUPLICATE KEY UPDATE` (20 colunas).
- `set_checkpoints(track_id, cps)` — DELETE + multi-INSERT.
- `set_grid(track_id, grid)` — DELETE + multi-INSERT.
- `load_catalog()` — SELECT de tracks + CPs + grid (3 queries).
- `delete_track(track_id, only_custom)`.
- `insert_history(row)` — retorna `insertId`.
- `insert_results(history_id, results)` — multi-INSERT.
- `update_records(track_id, char_id, time, drift, top_speed, was_win)` — UPSERT.
- `update_stats(char_id, kind, ...)` — UPSERT.
- `history_recent(filters, limit)` — filtros dinâmicos (char_id, track_id, kind, mode, category).
- `results_of(history_id)`, `stats_of_char(char_id)`, `records_of_char(char_id, limit)`.
- `ranking_kind(kind, mode, limit)` — `ORDER BY` dinâmico (wins/time/drift).
- **Ranqueado PDL**: `ranked_one(char_id)`, `ranked_many(char_ids)` (IN...), `upsert_ranked_batch(rows)` (UPSERT atomic em 1 statement), `ranked_top(limit)`, `ranked_decay(floor, amount, threshold, cutoff)`.
- `valid_category(c)` — fail-safe: enum inválido → `'normal'`.
- `apply_schema()` — `LoadResourceFile('sql/schema.sql')` + `execute_raw(schema)` + 3 `ensure_column`.

### 3.5 `server/lobby.lua` — máquina de estados (lobby→pending→warmup)
**Maquinário central do lobby.** Ordem de transições (uma fonte de verdade, sem ramificação por kind):
1. `L.create(src, payload)` → cria instância estado `'lobby'`, calcula `mode/category/fee/password/laps`, aloca `ready_zone` via `Grid.compute_ready_zone(track)`, faz auto-join do criador.
2. `L.join(src, inst_id, password)` → valida senha (se houver), cobra fee via `Rewards.charge_entry`, aloca grid slot via `Grid.alloc_slot`, transiciona `'lobby'→'pending'` na primeira entrada (inicia deadline `PENDING_TTL_MS=300000`), `TriggerClientEvent(LOBBY_PENDING)`.
3. `L.confirm_presence(src, inst_id, force)` → valida `inst.state=='pending'`, valida `Grid.in_ready_zone(src, inst.ready_zone)` (server-side via `GetEntityCoords(GetPlayerPed(src))`), marca `player.confirmed=true`. Se todos confirmados + `min_players` atendido → `L.start(inst.id, false)`.
4. `L._handle_pending_deadline(inst)` → remove não-confirmados (sem refund), inicia se restou mínimo, senão cancela.
5. `L.start(inst_id, solo)` → remove não-confirmados (sem refund), transiciona `'pending'→'warmup'`, agenda `starts_at = ms() + COUNTDOWN_MS(7000)`, envia `RACE_PREPARE` com `grid_pos` para cada player, agenda `SetTimeout(COUNTDOWN_MS)` → `Runtime.begin_racing(inst)`. Dispara `_police_alert(inst)` se `inst.alerts_police`.
6. `L.leave(src, inst_id)` → refund se estado lobby/pending, libera grid slot, se host saiu antes do início → `L.cancel`.
7. `L.cancel(inst_id, reason)` → refund a todos, remove instância.
8. `L.gc_idle()` — GC de lobbies estagnados (TTL_MS = 300000 ms sem confirmar) e drafts (TTL 1800000 ms). Chamado por cron no `init.lua` a cada 30 s.
9. `L.on_player_dropped(src)` → trata como leave.
10. `L._police_alert(inst)` → itera `GetPlayers()`, checa `exports.vhub_groups:hasPermission(psrc, 'policia.radio')`, `TriggerClientEvent(RACE_POLICE)` com blip de 90 s.

**Mode resolver**: `resolve_mode(payload, track)` → `'treino'` se track.kind == 'freerun'; senão `payload.mode == 'treino' ? 'treino' : 'rankeada'`.

**Password resolver**: `resolve_password(payload, category, mode)` → `nil` se treino; se `'personalizada'` exige senha; se `'normal'` senha opcional (lobby privado). Senha nunca cruza fronteira.

**State Bag sync**: `broadcast_lobby_state(inst)` faz `Player(src).state:set('vhub_racha', { inst_id, track_id, kind, mode, category, state, confirmed, grid_slot, players_total, pending_deadline, ready_zone, starts_at }, true)` para todos os players da instância.

### 3.6 `server/grid.lua` — geometria de largada
Isolamento de concerns geométricos:
- `Grid.compute_ready_zone(track)` → `{ x, y, z, radius=18.0, z_tol=5.0 }` centrada no `track.start`, ou override `track.ready_zone`.
- `Grid.in_ready_zone(src, zone)` → **server-authoritative**: `GetPlayerPed(src)` → `GetEntityCoords(ped)` → checa Z tolerância + `point_in_circle`. Zero confiança no cliente.
- `Grid.alloc_slot(inst)` → primeiro índice livre (1..max_players).
- `Grid.free_slot(inst, slot)`.
- `Grid.spawn_for(track, slot)` → `track.grid[slot]` ou fallback `track.start`.

### 3.7 `server/runtime.lua` — corrida ativa (warmup→racing→finished)
Recebe instância em `warmup` do Lobby e gerencia o ciclo:
- `RT.begin_racing(inst)` → `inst.state='racing'`, `started_ms=last_cp_ms=now_ms` para cada player, `TriggerClientEvent(RACE_START)`, agenda timeout duro `RACE_SAFETY_TIMEOUT_S=1800s` (rede de segurança — nunca guilhotina corrida em andamento, só encerra abandonada/travada). **Soft-dep VRCS**: `pcall(exports['vhub_vrcs']:onRaceStart({...}))` se o replay estiver disponível.
- `RT.on_checkpoint(src, payload)` → `AC.validate_checkpoint(inst, src, payload)` → incrementa `cp_done`, atualiza `lap`, `apply_telemetry(player, payload)` (top_speed/drift com cap), sincroniza state bag. Se `cp_done >= cp_total` → `_player_finish`.
- `RT.on_tick(src, payload)` → `apply_telemetry` + atualiza `best_lap_ms`. Smoothing anti-spike: drift limitado por `CAP_PER_SEC * dt_sec`.
- `RT._player_finish(inst, src)` → marca `finished=true`, se foi primeiro → inicia `FINISH_GRACE_MS=60000` para os demais, se todos terminaram → `RT.finish(inst.id, 'todos_terminaram')`.
- `RT.on_abort(src, reason)` → se já finished → ignora (correção do bug "vitória e derrota ao mesmo tempo"); senão marca `'dnf'`, se todos DNF/finished → finish.
- `RT.finish(inst_id, reason)` → `inst.state='finished'`, chama `History.finalize(inst)`, paga prêmios via `Rewards.pay`, `TriggerClientEvent(RACE_FINISH)` com `pdl_delta/pdl_new/division` (se ranqueada), limpa state bags, `ST.remove_instance`. **Soft-dep VRCS**: `pcall(exports['vhub_vrcs']:onRaceClose(inst.id, {...}))`.
- `RT.on_player_dropped(src)` → se estado `'racing'` → `on_abort(src, 'dropped')`.

**`apply_telemetry(player, payload)`** (fonte única para top_speed/drift): top_speed monotônico com clamp em `MAX_SPEED_KMH=400`; drift com cap por segundo `CAP_PER_SEC * dt_sec` (alinhado com `SCORE_CAP_PER_SEC=100` do Drift).

**`race_bag(inst, p)`** (fonte única do payload do state bag): superset coerente — sempre os mesmos campos (`inst_id, track_id, kind, mode, state, cp_done, cp_total, lap, laps, placement, players_total, drift_score, starts_at, started_ms`) para o HUD nunca perder estado entre ticks.

### 3.8 `server/ranked.lua` — escritor único de `vh_race_ranked`
Rating PDL **global por personagem** (cross-kind, estilo CS2). `Ranked._running=false` (guard do cron de decay, L-06).

Matemática em `shared/math.lua` (PURO): `expected_score(a, b, c) = 1 / (1 + 10^((b-a)/c))`, `division_of(pdl, divisions)` → `{ key, label, tier (1..3), index, floor, next_min }`.

- `Ranked.division(pdl)` → `Mth.division_of(pdl, Cfg.RANKED.DIVISIONS)`.
- `Ranked.get(char_id)` → retorna linha PDL ou default `{ pdl=PDL_START=1000, provisional=true }` se nunca correu.
- `Ranked.has_played(char_id)` → true se `matches > 0` (usado para fechar enumeração de perfil de terceiro).
- `Ranked.top(limit)` → leaderboard enriquecido com divisão.
- **`Ranked.apply_race(participants)`** — núcleo do Elo FFA:
  1. Dedupe por char_id preservando placement.
  2. **Anti-farm**: se `< 2` char_ids distintos → retorna `{}` (sem adversário real, sem PDL).
  3. **Snapshot-read**: `SQL.ranked_many(ids)` busca TODOS os ratings ATUAIS antes de qualquer escrita (independe de ordem).
  4. Para cada participante: `expected = Σ E(i,j)`, `actual = Σ score(pi.placement vs pj.placement)` (1.0 vitória, 0.5 empate), `K = matches < CALIBRATION_MATCHES(10) ? K_CALIBRATION(1500) : K_FACTOR(500)`, `delta = floor(K * (actual-expected) / (n-1) + 0.5)`, `new_pdl = max(MIN_PDL=100, old_pdl + delta)`.
  5. `SQL.upsert_ranked_batch(batch)` — 1 statement INSERT...ON DUPLICATE (atômico no MySQL).
  6. Retorna `out[char_id] = { delta, old_pdl, new_pdl, division }`.
- `Ranked.decay_sweep()` — 1 UPDATE set-based: elite inativa (>14 dias, PDL>2200) perde 25/dia até o piso 2200.
- `Ranked.start_decay_cron()` — SetTimeout-chain re-schedulável (sem `while true`), cadência por dia-calendário real (`os.date('%Y-%m-%d')`), 1 verificação/hora. Cancela em `onResourceStop`.

Config em `Cfg.RANKED`: `ENABLED=true, PDL_START=1000, MIN_PDL=100, C_FACTOR=4000, K_FACTOR=500, K_CALIBRATION=1500, CALIBRATION_MATCHES=10, DECAY={ ENABLED=true, ABOVE_PDL=2200, PER_DAY=25, INACTIVE_DAYS=14, INTERVAL_MS=3600000 }`, `DIVISIONS = { bronze(0), prata(1200), ouro(1600), platina(2200), diamante(3000), mestre(4000), lendario(5500) }`.

### 3.9 `server/ranking.lua` — leitura agregada para NUI/iPad
Camada de leitura pura sobre `SQL`:
- `R.top(kind, mode, limit)` — ranking por modalidade, resolve nicks via `vh_identity`.
- `R.recent(filters, limit)` — histórico recente.
- `R.results_of(history_id)`, `R.stats_of_char(char_id)`, `R.records_of_char(char_id, limit)`.
- `R.ranked_ladder(limit)` — leaderboard PDL com nicks.
- **`R.profile_of(char_id)`** — perfil COMPOSTO versionado (`schema = 'vhub_racha.profile.v1'`) para o site da cidade: identidade, ranqueado, stats por modo, records, agregados de carreira (somatório cross-kind: `runs/wins/podiums/dnf/total_payout/total_drift/top_speed/best_time_ms/winrate/favorite_kind`), atividade recente (8 últimas). JSON-friendly (sem vec/função).

`resolve_nicks(char_ids)` — query em `vh_identity` (`SELECT char_id, firstname, lastname WHERE char_id IN (...)`), fallback `'char_<id>'`.

### 3.10 `server/history.lua` — finalize: persiste resultado
`H.finalize(inst)`:
1. Coleta players da instância, calcula `total_time_ms = finished_ms - started_ms`, aplica `AC.cap_drift_score` e `AC.cap_top_speed` (anti-spike server-side).
2. **Sort por kind**: drift → maior `drift_score` (desempate `total_time_ms`); speedtrap → maior `top_speed` (desempate `total_time_ms`); demais → menor `total_time_ms`. DNFs vão para o fim (ordenados por `cp_done` desc).
3. Atribui `placement = i`.
4. **Payout** via `payout_dist(n_finalists)`: `{0.70, 0.20, 0.10}` p/ 3+, `{0.80, 0.20}` p/ 2, `{1.00}` solo. Modo treino/freerun → sem payout (`dist = {}`). Timeattack → bonus `TIMEATTACK_BONUS_PCT=50%`.
5. `SQL.insert_history` → `history_id`.
6. `SQL.insert_results(history_id, players)`.
7. Se `mode == 'rankeada'`: `SQL.update_records` + `SQL.update_stats` para cada player. Se `category == 'ranqueada'` → `VHubRachaRanked.apply_race(pdl_parts)` (gate de temporada AQUI no history; `apply_race` fica agnóstico). Anexa `pdl_delta/pdl_new/division` ao player (propagado ao `RACE_FINISH`).
8. Retorna `{ history_id, players, winner_char }`.

### 3.11 `server/rewards.lua` — fronteira única com vhub_money
Tudo passa por aqui. Outros módulos **nunca** chamam `exports.vhub_money` direto. pcall em todas as chamadas (vhub_money pode estar indisponível — racha sobrevive):
- `R.charge_entry(src, fee, reason)` → `exports.vhub_money:tryFullPayment(src, fee, false)` (debita carteira+banco).
- `R.refund(src, amount, reason)` → `exports.vhub_money:giveBank(src, amount, reason)`.
- `R.pay(src, amount, reason)` → `exports.vhub_money:giveBank(src, amount, 'race_payout')`.
- `R.has_balance(src, amount)` → `exports.vhub_money:tryFullPayment(src, amount, true)` (dry-run).

### 3.12 `server/anti_cheat.lua` — validações
- **`AC.validate_checkpoint(inst, src, payload)`**:
  1. Payload é tabela, player na instância.
  2. `cp_index >= 1` e `idx == player.cp_done + 1` (ordem estrita — `cp_fora_de_ordem:%d!=%d`).
  3. `idx <= cp_total` (não ultrapassa).
  4. `(now - last_cp_ms) >= MIN_CHECKPOINT_MS(400)` (anti-spam — `cp_muito_rapido`).
  5. **Distância server-side**: `ped = GetPlayerPed(src)`, `pos = (ped != 0) ? GetEntityCoords(ped) : payload.pos` (fail-closed se ped resolver; residual aceito #22d-i). Se `pos.x/y` existem → checa `d² = (pos.x-cp.x)² + (pos.y-cp.y)²` vs `(CP_MAX_TELEPORT_DIST=300)²`. Se `d² > max²` → `teleport_suspeito:%.1f`.
  6. `speed > MAX_SPEED_KMH(400)` → incrementa `player.warns` (não bloqueia — só conta).
- **`AC.cap_drift_score(reported, started_ms, ended_ms)`** — cap por tempo de corrida: `cap = CAP_PER_SEC * secs * max_combo_mult`. Se `reported > cap` → retorna `cap`.
- **`AC.cap_top_speed(reported)`** — clamp em `MAX_SPEED_KMH=400`.

### 3.13 `server/editor.lua` — editor visual de pistas
3 fases (`EditorPhase: IDLE/GRID/CPS/META/DONE`):
- `ED.is_allowed(src)` — ACE `vhub.racha.admin`, OU `user.char_id == OWNER_CHAR_ID=1`, OU `exports.vhub_groups:hasPermission(src, 'vhub.racha.editor')`.
- `ED.open(src)` — cria/recupera draft em `ST._drafts[char_id]` com `phase='grid'`, envia `EDITOR_OPENED` + draft.
- `ED.set_phase(src, phase)` — só permite `grid/cps/meta/idle`.
- `ED.add_grid(src)` — captura `GetEntityCoords(veh or ped)` + heading, adiciona entrada ao `draft.grid` (até `EDITOR_MAX_GRID=12`), define `draft.start` no 1º slot.
- `ED.add_cp(src)` — captura posição, adiciona CP (até `EDITOR_MAX_CPS=80`).
- `ED.undo(src)` — remove último CP.
- `ED.discard(src)` — limpa draft.
- `ED.save(src, meta)` — valida `id` sanitizado (regex `[^a-z0-9_%-]`, max 48 chars), `label` (max 80), exige ≥1 grid slot, ≥1 CP (exceto freerun), rejeita `id` se bate com pista do config (`source != 'custom'`) ou se pertence a outro criador. Aplica metadados (`kind/laps/illegal/alerts_police/vehicle_class/default_fee/limit_seconds`). **Categoria sempre `'personalizada'`** (editor cria pistas pessoais, #36). `SQL.upsert_track + set_checkpoints + set_grid`, atualiza `ST._catalog`.
- `ED.snapshot(src)` — retorna draft atual.

**Coord capture** é server-side (`get_pos_h(src)` via `GetPlayerPed` + `GetVehiclePedIsIn` + `GetEntityCoords/Heading`) — cliente não propõe coords.

### 3.14 `server/exports.lua` — API pública
Default-DENY (N0-2 #32) para mutações; leitura é livre.

**Read-only (8):**
| Export | Assinatura |
|---|---|
| `catalog` | `() → array<{ id, label, district, kind, illegal, alerts_police, laps, min_players, max_players, vehicle_class, default_fee, limit_seconds, source, cps }>` |
| `lobbies` | `() → array<public_lobby>` |
| `isInRace` | `(src) → bool` |
| `isReady` | `() → bool` |
| `Status` | `() → status_snapshot` |
| `topRanking` | `(kind, mode, limit) → array<row>` |
| `historyRecent` | `(filters, limit) → array<row>` |
| `resultsOf` | `(history_id) → array<row>` |
| `statsOfChar` | `(char_id) → array<row>` |
| `recordsOfChar` | `(char_id, limit) → array<row>` |
| `rankedLadder` | `(limit) → array<row>` |
| `profile` | `(char_id) → profile_v1` |

**Mutators (TRUSTED via `_invoker_allowed`):**
| Export | Assinatura | Gate |
|---|---|---|
| `createLobby` | `(src, payload) → (ok, data)` | whitelist `{vhub, vhub_admin}` |
| `cancelLobby` | `(inst_id, reason) → (ok, err)` | whitelist |
| `deleteTrack` | `(track_id) → (ok, err)` | whitelist; só `source='custom'` |

**iPad Relay** (export especial, `server/init.lua:144`):
| Export | Assinatura |
|---|---|
| `ipadRelay` | `(src, action, data) → true` |

Ações suportadas (rodadas em `CreateThread` próprio — `Citizen.Await` não cruza fronteira C do export):
- `open`/`refresh` → `appPush(src, 'racha', 'data', build_panel_data())`
- `create`/`join` → `LB.create/LB.join` + `appPush('result')` se erro + `closeIpad` se sucesso
- `ranking`/`history`/`results`/`ranked`/`profile` → consultas read-only via `appPush`
- `editor_open`/`editor_phase`/`editor_discard`/`editor_save` → delega para `ED.*`

**Anti-enumeracao de perfil**: `profile` de terceiro só retorna se `cid == own_cid` ou `VHubRachaRanked.has_played(cid)` (só quem competiu).

---

## 4. Arquitetura Client

### 4.1 `client/bootstrap.lua` — handshake client
Idêntico em padrão ao server: `VHubRachaBoot = { READY=false, user_id, char_id, _queue={} }`. **3 caminhos determinísticos** para READY (primeiro resolve, demais viram noop pelo guard):
1. Evento oficial `vHub:initDone` (RegisterNetEvent).
2. State Bag `LocalPlayer.state.vhub_pronto == true` (loop 250 ms × 120 = 30 s).
3. Re-emissão explícita: `TriggerServerEvent(REQUEST_INIT_DONE)` 200 ms após boot.

`B.on_ready(fn, name)` executa imediato se READY ou enfileira. `_emit_ready()` roda fila em pcall e `TriggerEvent('vhub_racha:boot:ready')`.

### 4.2 `client/state.lua` — estado local do player
`VHubRachaLocal` — VRAM client-side:
- `open_nui/open_editor` — flags de UI.
- `bag = {}` — snapshot da state bag `vhub_racha` (atualizada por `AddStateBagChangeHandler`).
- `pending = nil` — estado do lobby pending (`{ inst_id, ready_zone, pending_deadline, mode, track_label }`).
- `confirmed` — boolean.
- `active` — corrida ativa (preenchido em `race.lua`).
- `_cp_blips` — blips dos próximos CPs.

State Bag handler em `player:<server_id>` (escopo local) → `L.bag = value; L.confirmed = value.confirmed; TriggerEvent('vhub_racha:local:bag_update', L.bag)`.

**Notify**: `VHubRachaLocal.notify(msg, kind)` — `exports.vhub_notify:notify({type, msg})` com fallback `BeginTextCommandThefeedPost` se vhub_notify indisponível.

**Exports locais**: `isInRace`, `isInLobby`, `currentKind`, `driftScore`, `isReady`.

### 4.3 `client/lobby.lua` — ready zone visual + confirmação
- `RegisterNetEvent(LOBBY_PENDING)` → `VHubRachaLocal.set_pending(...)`, cria blip de rota (`AddBlipForCoord`, sprite 38, cor 5, `SetBlipRoute(true)`), `SendNUIMessage({type='vhub_racha.lobby.pending', data})`.
- `RegisterNetEvent(LOBBY_CONFIRMED)` → remove blip, `L.confirmed = true`, `SendNUIMessage('vhub_racha.lobby.confirmed')`.
- **Thread principal** (DrawMarker): quando `pending.ready_zone` existe e player está a <300 m, desenha a 60+ FPS:
  - Cronômetro de deadline (DrawText 7).
  - Gas de areia dourada (DrawMarker 1, alpha 32) no chão.
  - Anel de borda (alpha +22).
  - Hint in-world `[E] Confirmar presenca` se dentro da zona e não confirmado.
  - Fumaça/gas subindo (N=14 baforadas, DrawMarker 28, fade com altura).
  - **[E]** (control 38) ou buzina → `TriggerServerEvent(LOBBY_CONFIRM, inst_id)`.
- **Thread NUI** (20 Hz) → `SendNUIMessage('vhub_racha.readyzone.project', { visible, x, y, dist, dist_label, inside, confirmed, remaining_ms, track_label, mode })` para overlay HTML/CSS anchor.
- **Thread [E] fallback** — confirma mesmo se ready-zone não visível (rate-limited 800 ms).
- Handler `bag_update` → limpa pending/blip quando estado vira `racing/warmup` ou bag é nil.
- `onResourceStop` → remove blip.

### 4.4 `client/race.lua` — cliente da corrida
- **Proxy TOT** — `setmetatable({}, __index)` encaminha para `VHubRachaTotem` quando disponível (evita erro de ordem de carga).
- `mode_for(kind)` → `VHubRachaModes[kind] or VHubRachaModes.base`.
- `next_target(active)` → CP atual `cps[((cp_index-1) % #cps) + 1]`.
- **Blips dos próximos 2 CPs** — `update_next_blips` cria blips 1 e 2 com rotas; `clear_next_blips` no cleanup.
- `refresh_totem(active)` → `TOT.set_target({x, y, z, kind, is_finish, label})` + `update_next_blips`.
- `RegisterNetEvent(RACE_PREPARE)` → monta `active` (inst_id, track, laps, mode, cp_index=1, cp_total, grid_pos, etc.), teleporta veículo/ped para grid (`SetEntityCoordsNoOffset` + `SetEntityHeading` + `FreezeEntityPosition(true)`), chama `mode.start(active, payload)`, `refresh_totem`.
- `RegisterNetEvent(RACE_START)` → descongela (`FreezeEntityPosition(false)`), chama `mode.on_start`, notify de modo.
- **Thread de detecção de CP (20 Hz)**: para cada `active`, se `CP.inside(pos, target, radius)` → atualiza `top_speed`, chama `mode.on_checkpoint` ANTES de enviar (garante drift bancado no último CP), `TriggerServerEvent(RACE_CHECKPOINT, {cp_index, pos, speed, top_speed, drift_score, t_ms})`, incrementa `cp_index`, se `cp_index > cp_total` → `active.finished=true, TOT.clear()`, senão `refresh_totem`.
- `RegisterNetEvent(RACE_FINISH)` → `mode.on_finish`, `TOT.clear()`, `clear_next_blips`, `SendNUIMessage({action='race_finish', data})`, notify, `VHubRachaLocal.clear_active()`.
- **Thread de detecção de abort (2.5 s)**: se kind != `freerun` e `veh == 0` → `active.aborted=true, TOT.clear(), TriggerServerEvent(RACE_ABORT, 'fora_do_veiculo')`.
- `RegisterNetEvent(RACE_POLICE)` → blip 161 (flash, vermelho) por `ttl_ms=90000` + notify.
- `onResourceStop` → cleanup.

### 4.5 `client/sync.lua` — telemetria 1 Hz para o server
Thread adaptativa:
- Sem corrida ativa → `Wait(2000)`.
- `active.finished` → flush final (1x) + `Wait(2000)`.
- Caso contrário → `Wait(1000)` + `TriggerServerEvent(RACE_TICK, {drift_score, top_speed, best_lap_ms, t_ms})`. Atualiza `active.top_speed` local com `V.speed_kmh(veh)`.

### 4.6 `client/totem.lua` — totem 3D nativo
Design "estilo Forza": UMA linha fina e longa (areia de ouro neon), ancorada no chão, sobe até 999 m, encolhe linearmente até `MIN_HEIGHT=5.0` em distância 0. Base com 2 discos de areia quase transparentes. Label de distância (`%m` ou `%.2f KM`) no topo.

- `T.set_target(target)` / `T.clear()` / `T.current()`.
- `height_for(dist_m)` — interpolação linear `MIN_HEIGHT + (MAX_HEIGHT - MIN_HEIGHT) * clamp(dist_m/SCALE_DIST, 0, 1)`.
- `color_for(target)` — `COLOR_DEFAULT` (areia ouro), `COLOR_FINISH` (verde) se `is_finish`, `COLOR_SPEEDTRAP` (verde radar), `COLOR_DRIFT_ZONE` (roxo).
- Thread: `Wait(0)` se dentro do `RENDER_RANGE=999m`, senão `Wait(500)`. `draw_totem(target, dist_m)` → DrawMarker 1 (base) + DrawMarker 1 (coluna) + `draw_top_label`.
- `onResourceStop` → `_target = nil`.

### 4.7 `client/countdown.lua` — camera shake no GO
Mínimo: `RegisterNetEvent(RACE_START)` → `ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', 0.35)`. A contagem visual (3/2/1/GO) é NUI (HUD).

### 4.8 `client/nui.lua` — adaptador de notify + reflexo do editor
- `RegisterNetEvent(NOTIFY)` → `L.notify(msg, kind)`.
- `RegisterNetEvent(EDITOR_OPENED)` → `L.open_editor=true; L.editor_draft=draft; L.notify('Editor ativo...')`.
- `RegisterNetEvent(EDITOR_DRAFT)` → `L.editor_draft = draft`.
- `RegisterNetEvent(EDITOR_PHASE)` → atualiza `L.editor_draft.phase`; se `meta` → notify "abra o iPad para salvar".

### 4.9 `client/nui_bridge.lua` — ponte Lua↔NUI
- `TELEMETRY_INTERVAL = 250 ms` (4 Hz).
- `bag_key(bag)` — diff leve (concat de state/cp_done/lap/placement/confirmed) sem `json.encode` em hot path.
- `send_bag_if_changed(bag)` — só envia se `bag_key` mudou.
- `cp_telemetry(active)` — distância 2D do player ao próximo CP.
- `speed_kmh()` — `V.speed_kmh(veh)`.
- Eventos RACE_PREPARE/START/FINISH/ABORT → `nui('hud_show'/'hud_start'/'hud_finish'/'hud_hide', data)`.
- `bag_update` handler → `send_bag_if_changed`.
- **Thread de telemetria (4 Hz)**: `bridge('vhub_racha.telemetry', { state, elapsed_ms, speed_kmh, cp_index, cp_total, cp_done, lap, laps, placement, players_total, drift_score, drift_banked, drift_combo, distance_m })`.
- **NUI Callbacks**:
  - `nui_ready` → `VHubRachaNui.ready=true`, responde `{ ok, use_nui, ready }`.
  - `vhub_racha.action` → `{ confirm_presence, leave_lobby, request_join }` → `TriggerServerEvent(LOBBY_CONFIRM/LOBBY_LEAVE/LOBBY_JOIN)`.
  - `vhub_racha.request_sync` → re-envia bag.

### 4.10 `client/editor.lua` — editor visual in-game (keyboard)
- Thread: quando `L.open_editor && L.editor_draft`, `Wait(0)`:
  - Render CPs salvos (DrawMarker 28 + 1 laranja).
  - Render grid slots (DrawMarker 1 verde).
  - Banner de fase (grid/cps/meta) com instruções.
  - Contadores (`Slots: x/12   CPs: x/80`).
  - **Input por fase**:
    - GRID: E (38) ou buzina (86) → `EDITOR_ADD_GRID`; G (47) → `EDITOR_PHASE cps`.
    - CPS: E → `EDITOR_ADD_CP`; H/headlight (74) → `EDITOR_UNDO`; G → `EDITOR_PHASE meta`.

---

## 5. Modos de Corrida (client/modes/*.lua)

### 5.1 `base.lua` — interface no-op
```lua
VHubRachaModes.base = {
  id = 'base',
  start         = function(_active, _payload) end,
  on_start      = function(_active) end,
  on_checkpoint = function(_active, _idx) end,
  on_finish     = function(_active, _payload) end,
}
```
Todos os modos fazem fallback para `base` se não implementados.

### 5.2 `drift.lua` — banco de pontuação
O mais complexo. Regra: lote pendente vira válido após `BANK_MS=5000ms` sem bater; bater descarta o lote pendente (bancado permanece).

- `start` → zera `drift_score=0, drift_live=0, drift_combo=1.0, _pending=0, _window_ms=0, _last_total=nil, _last_crashes=nil`.
- `on_checkpoint(active, cp_idx)` → se último CP (`cp_idx >= cp_total`) → banca o pendente (idempotente).
- `on_finish(active)` → banca o pendente (idempotente).
- **Bank loop (10 Hz)**:
  - `drift_telemetry()` → `exports.Drift:getTelemetry()` (pcall, nil-safe).
  - 1ª leitura: baseline `_last_total = snap.total`, `_last_crashes = snap.crashes`.
  - `d_total = snap.total - _last_total` (delta desde último tick).
  - `crashed = snap.crashes != _last_crashes` → reseta `_pending=0, _window_ms=0`.
  - `d_total > 0` → acumula em `_pending`.
  - Se `_pending > 0`: `_window_ms += dt`; se `>= BANK_MS` → `drift_score += _pending; _pending=0; _window_ms=0`.
  - `drift_combo = snap.combo`, `drift_live = drift_score + _pending`.

### 5.3 `drag.lua` — 1/4 milha (placeholder)
Apenas `start` seta `best_lap_ms=0, false_start=false`. Semáforo visual é renderizado pelo `countdown.lua` (camera shake no GO) + HUD NUI. `LANE_SEPARATION=4.5` configurado mas não usado no client (geometria vem do grid).

### 5.4 `sprint.lua` — A→B simples
No-op além de `start` setar `best_lap_ms=0`. Lógica de detecção de CP é genérica em `race.lua`.

### 5.5 `circuit.lua` — voltas múltiplas
- `start` → `best_lap_ms=0, last_lap_at=0`.
- `on_start` → `last_lap_at = GetGameTimer()`.
- `on_checkpoint(active, idx)` → se `(idx % cps_per_lap) == 0` (fechou volta): `lap_ms = now - last_lap_at`, atualiza `best_lap_ms` se `lap_ms` menor, `last_lap_at = now`.

### 5.6 `freerun.lua` — exploração livre
No-op. Não conta CPs (lobby trata `laps=0`), não pontua, sem ranking.

### 5.7 `timeattack.lua` — solo contra o tempo
No-op no client. `BANK_MS`/`TIMEATTACK_BONUS_PCT` no server (`history.lua` aplica +50% payout se vencedor).

### 5.8 `speedtrap.lua` — soma velocidade nos radares + combo
- `start` → `trap_total=0, trap_combo=1.0, trap_hits=0`.
- `on_checkpoint(active, _idx)` → `kmh = V.speed_kmh(veh)`, `trap_hits++`, `trap_combo *= COMBO_BONUS=1.05`, `trap_total += floor(kmh * trap_combo)`. **Reaproveita `drift_score` como score visível** pro server (`active.drift_score = active.trap_total` — HUD lê este campo).

---

## 6. Exports (Server & Client)

### Server (15 exports — `server/exports.lua` + `server/init.lua`)
| # | Export | Assinatura | Gate |
|---|---|---|---|
| 1 | `catalog` | `() → array` | livre |
| 2 | `lobbies` | `() → array` | livre |
| 3 | `isInRace` | `(src) → bool` | livre |
| 4 | `isReady` | `() → bool` | livre |
| 5 | `Status` | `() → snapshot` | livre |
| 6 | `topRanking` | `(kind, mode, limit) → array` | livre |
| 7 | `historyRecent` | `(filters, limit) → array` | livre |
| 8 | `resultsOf` | `(history_id) → array` | livre |
| 9 | `statsOfChar` | `(char_id) → array` | livre |
| 10 | `recordsOfChar` | `(char_id, limit) → array` | livre |
| 11 | `rankedLadder` | `(limit) → array` | livre |
| 12 | `profile` | `(char_id) → profile_v1` | livre |
| 13 | `createLobby` | `(src, payload) → (ok, data)` | TRUSTED |
| 14 | `cancelLobby` | `(inst_id, reason) → (ok, err)` | TRUSTED |
| 15 | `deleteTrack` | `(track_id) → (ok, err)` | TRUSTED (só custom) |
| 16 | `ipadRelay` | `(src, action, data) → true` | implícito (src válido) |

### Client (5 exports — `client/state.lua`)
| # | Export | Assinatura |
|---|---|---|
| 1 | `isInRace` | `() → bool` |
| 2 | `isInLobby` | `() → bool` |
| 3 | `currentKind` | `() → string|nil` |
| 4 | `driftScore` | `() → int` |
| 5 | `isReady` | `() → bool` |

### Drift (1 export — `cl.lua`)
| # | Export | Assinatura |
|---|---|---|
| 1 | `getTelemetry` | `() → { total, crashes, combo, angle, speed, drifting, active }` |

---

## 7. Eventos (NetEvents + ClientEvents)

### 7.1 NetEvents (client → server) — 10
| Evento | Constante | Payload | Handler | Rate-limit (server/init.lua) |
|---|---|---|---|---|
| `vhub_racha:request_initDone` | `REQUEST_INIT_DONE` | — | `bootstrap.lua:85` | — (idempotente) |
| `vhub_racha:lobby:join` | `LOBBY_JOIN` | `inst_id` | `init.lua:238` | 800 ms |
| `vhub_racha:lobby:leave` | `LOBBY_LEAVE` | `inst_id` | `init.lua:249` | 500 ms |
| `vhub_racha:lobby:confirm` | `LOBBY_CONFIRM` | `inst_id` | `init.lua:228` | 500 ms |
| `vhub_racha:race:checkpoint` | `RACE_CHECKPOINT` | `{ cp_index, pos, speed, top_speed, drift_score, t_ms }` | `init.lua:258` → `RT.on_checkpoint` | — (AC tem `MIN_CHECKPOINT_MS=400`) |
| `vhub_racha:race:tick` | `RACE_TICK` | `{ drift_score, top_speed, best_lap_ms, t_ms }` | `init.lua:263` → `RT.on_tick` | — (1 Hz client-side) |
| `vhub_racha:race:abort` | `RACE_ABORT` | `reason: string` | `init.lua:268` → `RT.on_abort` | — |
| `vhub_racha:editor:phase` | `EDITOR_PHASE` | `{ phase }` | `init.lua:278` | — |
| `vhub_racha:editor:add_grid` | `EDITOR_ADD_GRID` | — | `init.lua:281` | — |
| `vhub_racha:editor:add_cp` | `EDITOR_ADD_CP` | — | `init.lua:282` | — |
| `vhub_racha:editor:undo` | `EDITOR_UNDO` | — | `init.lua:283` | — |

`LOBBY_CANCEL` e `LOBBY_FORCE_START` declarados em `events.lua` mas **não registrados** (sem consumidor in-game — `init.lua:227` comentário).

### 7.2 ClientEvents (server → client) — 13
| Evento | Constante | Payload | Emissor | Ouvinte |
|---|---|---|---|---|
| `vhub_racha:nui:opened` | `NUI_OPENED` | — | (sem uso — painel vive no iPad) | — |
| `vhub_racha:lobby:pending` | `LOBBY_PENDING` | `{ inst_id, ready_zone, pending_deadline, mode, track_label }` | `lobby.lua:282` (server) | `client/lobby.lua:16` |
| `vhub_racha:lobby:confirmed` | `LOBBY_CONFIRMED` | `{ inst_id }` | `lobby.lua:386` (server) | `client/lobby.lua:54` |
| `vhub_racha:race:prepare` | `RACE_PREPARE` | `{ inst_id, track, laps, mode, grid_pos, starts_at, countdown, players_total }` | `lobby.lua:459` (server) | `client/race.lua:100` + `client/nui_bridge.lua:76` |
| `vhub_racha:race:start` | `RACE_START` | `{ inst_id, started_ms }` | `runtime.lua:118` (server) | `client/race.lua:155` + `client/countdown.lua:13` + `client/nui_bridge.lua:90` |
| `vhub_racha:race:finish` | `RACE_FINISH` | `{ inst_id, placement, time_ms, drift, payout, history_id, winner_char, reason, mode, pdl_delta, pdl_new, division }` | `runtime.lua:321` (server) | `client/race.lua:227` + `client/nui_bridge.lua:96` |
| `vhub_racha:race:abort` | `RACE_ABORT` | `reason` (não usado — abort só client→server) | — | `client/nui_bridge.lua:102` |
| `vhub_racha:race:police_alert` | `RACE_POLICE` | `{ track_id, label, start, ttl_ms, kind }` | `lobby.lua:507` (server) | `client/race.lua:274` |
| `vhub_racha:editor:opened` | `EDITOR_OPENED` | draft | `editor.lua:94` (server) | `client/nui.lua:27` |
| `vhub_racha:editor:phase` | `EDITOR_PHASE` | `{ phase }` | `editor.lua:104` (server) | `client/nui.lua:38` |
| `vhub_racha:editor:draft` | `EDITOR_DRAFT` | draft | `editor.lua:63/238` (server) | `client/nui.lua:34` |
| `vhub_racha:notify` | `NOTIFY` | `msg, kind` | vários | `client/nui.lua:17` |

### 7.3 Server-local events
- `vhub_racha:boot:ready` — emitido por `bootstrap.lua:52` quando CORE handshake OK.
- `vHub:characterLoad` — ouvido por `sessions.lua:33`.
- `playerDropped` — ouvido por `sessions.lua:42` e `init.lua:93`.
- `vHub:playerDeath` — ouvido por `init.lua:101` → `RT.on_abort(src, 'morte')`.
- `onResourceStart`/`onResourceStop` — handlers em `bootstrap.lua:59/96` e `ranked.lua:230`.

### 7.4 NUI Callbacks (RegisterNUICallback em `client/nui_bridge.lua`)
| Callback | Payload | Resposta |
|---|---|---|
| `nui_ready` | `{ href }` | `{ ok, use_nui, ready }` |
| `vhub_racha.action` | `{ action: 'confirm_presence'\|'leave_lobby'\|'request_join', inst_id }` | `{ ok }` ou `{ ok:false, err:'acao_invalida' }` |
| `vhub_racha.request_sync` | — | `{ ok }` (re-envia bag) |

### 7.5 NUI Messages (Lua → JS via SendNUIMessage)
- `nui_bridge.lua`: `{ action: 'hud_show'/'hud_countdown'/'hud_start'/'hud_finish'/'hud_hide', data }` (legado), `{ type: 'vhub_racha.telemetry', payload }`, `{ type: 'vhub_racha.bag_update', bag }`.
- `lobby.lua`: `{ type: 'vhub_racha.lobby.pending'/'lobby.confirmed', data }`, `{ type: 'vhub_racha.readyzone.project', payload }`, `{ type: 'vhub_racha.readyzone.clear' }`.
- `race.lua:236`: `{ action: 'race_finish', data }`.

---

## 8. Callbacks

Não há `lib.callback`/`ox_lib.callback` tradicionais. Toda comunicação Lua↔Lua é via `TriggerEvent`/`TriggerServerEvent`/`TriggerClientEvent` + `RegisterNetEvent`. A "fila de callbacks" do bootstrap (`B.on_ready`) é interna (não exposta).

---

## 9. NUI Bridge

### 9.1 Módulos web (2)
| Módulo | Responsabilidade | HTML/CSS/JS |
|---|---|---|
| `hud` | Overlay in-race (countdown, timer, pos, lap, CP, drift, finish card) | `web/modules/hud/hud.{html,css,js}` |
| `race` | Overlay ready-zone (instrução, anchor 3D, countdown de deadline) | `web/modules/race/race.{html,css,js}` |

O **painel completo** (pistas/lobbies/ranqueado/perfil/ranking/historico/editor) vive **exclusivamente no iPad** (`vhub_ipad/web/modules/racha/` — confirmado em `/home/z/my-project/workspace/vhubMirage/resources/[SCRIPTS]/vhub_ipad/web/modules/racha/racha.{html,css,js}`, 16 KB+25 KB+40 KB). vhub_racha não tem painel NUI com cursor.

### 9.2 Runtime (engine SPA — L3)
5 arquivos IIFE (`'use strict'`) que montam `window.vhub`:
- **`bus.js`** — event bus central. `bus.emit(name, payload)`, `bus.listen(name, fn) → off()`, `bus.off(name, fn)`. Handler em try/catch (erro em 1 não impede outros). Regra A-07: módulos guardam `off()` e chamam no `onDestroy`.
- **`store.js`** — slices por domínio (`store(domain) → { get, set(patch) }`). Ownership único por slice. Merge raso.
- **`bridge.js`** — POST central para Lua. `vhub.post(action, data) → Promise<{ok, data?, err?}>`. `fetchWithTimeout` com `AbortController` (8 s). Errors: `timeout`/`network`/`action_invalida`.
- **`sand.js`** — partículas de areia canvas (N=40, L-D2). `vhub.sand.start()/stop()`. Cancela RAF fantasma antes de re-start (guardiao_performance #1).
- **`core.js`** — mini-framework. `createModule(name, spec)` registra com lifecycle `onInit/onMount/onShow/onHide/onDestroy`. `mount(name)` faz fetch lazy de HTML+CSS. Dispatcher único: `window.addEventListener('message', ...)` despacha `{action}` e `{type}` para `bus.emit('nui:'+name, body)`.

### 9.3 Shared (CSS + JS)
- **`tokens.css`** — design tokens: paleta (`--vh-sand/gold/amber/black/danger/ok/text`), glass (`--vh-glass-bg` gradiente areia+preto alpha 0.55, L-D1), sombras (dourado 0.10), raios (`--vh-r-pan:16px/card:12px/btn:8px/pill:999px`), fontes (Barlow Condensed/Inter/Rajdhani/Orbitron/JetBrains Mono), espaçamentos, transições.
- **`reset.css`** — normalize mínimo, `box-sizing: border-box`, `body { background: transparent; overflow: hidden; user-select: none; }`, `.hidden { display: none !important; }` (A-07: para CSS animations).
- **`components.css`** — `.vh-panel/.vh-card/.vh-btn (.primary/.danger/.ghost)/.vh-input/.vh-toast/.vh-chip/#vhub-sand`.
- **`utils.js`** — formatadores puros: `fmtTime(ms) → "MM:SS.fff"`, `fmtTimeShort`, `fmtNum`, `fmtMoney(n) → "R$ X"`, `fmtSpeed`, `fmtDist`, `el(tag, attrs, children)` (DOM helper).
- **`icons.js`** — registro ÚNICO de 24 ícones SVG inline (A-10): road, flag, flag-checkered, ranking-star, clock-rotate-left, pen-ruler, xmark, magnifying-glass, arrows-rotate, plus, car, list, trash, floppy-disk, right-to-bracket, eye, map-marker, users, bolt, wind, gauge-high, stopwatch, circle-check/triangle-exclamation/circle-info, user, medal, crown, shield-halved, chart-simple. API: `svg(name, cls)`, `get(name, cls)` (elemento), `hydrate(root)` (markup estático `[data-icon]`).

### 9.4 Mensagens Lua↔JS trocadas
**Lua → JS** (via `SendNUIMessage`, despachadas em `core.js:208`):
- `{ action: 'hud_show', data: { cps_total, laps_total, players_total, mode, kind } }` → `nui:hud_show`
- `{ action: 'hud_countdown', data: { seconds } }` → `nui:hud_countdown`
- `{ action: 'hud_start', data: { elapsed_ms } }` → `nui:hud_start`
- `{ action: 'hud_finish', data: payload }` → `nui:hud_finish`
- `{ action: 'hud_hide', data: {} }` → `nui:hud_hide`
- `{ action: 'race_finish', data }` → `nui:race_finish`
- `{ type: 'vhub_racha.telemetry', payload: { state, elapsed_ms, speed_kmh, cp_index, cp_total, cp_done, lap, laps, placement, players_total, drift_score, drift_banked, drift_combo, distance_m } }`
- `{ type: 'vhub_racha.bag_update', bag }`
- `{ type: 'vhub_racha.lobby.pending', data }`
- `{ type: 'vhub_racha.lobby.confirmed', data }`
- `{ type: 'vhub_racha.readyzone.project', payload: { visible, x, y, dist, dist_label, inside, confirmed, remaining_ms, track_label, mode } }`
- `{ type: 'vhub_racha.readyzone.clear' }`

**JS → Lua** (via `vhub.post(action, data)`, registrados em `client/nui_bridge.lua`):
- `nui_ready { href }`
- `vhub_racha.action { action, inst_id }`
- `vhub_racha.request_sync`

---

## 10. Checkpoints & Vehicle

### 10.1 `shared/checkpoints.lua` — normalizador multi-formato + helpers
`VHubRachaCP.normalize(raw, default_h)` aceita 5 formatos (record nomeado, `vec3`, array curto, string `/cds`, `{cds=vec3, h=N}`) → canoniza para `{ x, y, z, h }`. `normalize_list(list, default_h)` adiciona `idx`. `inside(px, py, pz, cp, radius)` — círculo 2D com margem Z ampliada (25 m — rampas/pontes). `route_length(checkpoints)` — soma de distâncias 3D.

### 10.2 `shared/vehicle.lua` — wrapper de natives com pcall + log 1-shot
`VHubRachaVeh` isola natives de veículo com `_call(name, fn, default, ...)` (pcall + warn 1-shot `_MISSING[name]`):
- `is_alive(veh)`, `class(veh)`, `coords(veh)`, `heading(veh)`, `velocity(veh)`, `speed_kmh(veh)`, `is_in_air(veh)`.
- **`local_velocity(veh)`** — velocidade local (forward/lateral) para drift scoring: projeta velocidade no forward vector do heading, retorna `(fwd_kmh, lat_kmh, h)`.
- `ped_vehicle(ped)`, `is_driver(ped)` (seat -1), `is_horn_pressed(ped)` (control 86).

**Anti-cheat de tier/clone**: NÃO HÁ. vhub_racha não valida tier do veículo (vhub_vehcontrol faz isso fora do racha). `vehicle_class` da pista é `car/bike/off/truck/any` (bitmap em `VHubRachaVClass`) mas **não é enforceado** em runtime — `track.vehicle_class` é só metadado. Não há checagem anti-clone.

---

## 11. Anti-Cheat

### 11.1 `server/anti_cheat.lua` — validações server-side
Implementado como funções PURAS chamadas por `runtime.lua`:

1. **`validate_checkpoint(inst, src, payload)`** — fail-closed:
   - `payload` é tabela; player está na instância.
   - `cp_index >= 1` e `cp_index == player.cp_done + 1` (ordem estrita — `cp_fora_de_ordem`).
   - `idx <= cp_total` (`#track.checkpoints * laps`).
   - `(now_ms - last_cp_ms) >= MIN_CHECKPOINT_MS(400)` (`cp_muito_rapido`).
   - **Distância server-side OBRIGATÓRIA** (fail-closed #22d-i): `ped = GetPlayerPed(src)`, `pos = (ped && ped != 0) ? GetEntityCoords(ped) : payload.pos`. Se `pos.x/y` existem → `d² = (pos.x - cp_target.x)² + (pos.y - cp_target.y)²`; se `d² > (CP_MAX_TELEPORT_DIST=300)²` → `teleport_suspeito:%.1f`.
   - `speed > MAX_SPEED_KMH(400)` → `player.warns++` (não bloqueia — só conta).

2. **`cap_drift_score(reported, started_ms, ended_ms)`** — cap por tempo de corrida: `cap = CAP_PER_SEC(100) * secs * max_combo_mult(3.0)`. Se `reported > cap` → `cap`. Anti-spike server-side.

3. **`cap_top_speed(reported)`** — clamp em `MAX_SPEED_KMH=400`.

### 11.2 Outras validações anti-cheat embutidas
- **Server-authoritative ready zone** (`grid.lua:57`): `GetEntityCoords(GetPlayerPed(src))` no servidor, `point_in_circle` com `Z_TOLERANCE=5.0`. Zero confiança no cliente.
- **Snapshot-read atômico PDL** (`ranked.lua:128`): `SQL.ranked_many(ids)` lê TODOS os ratings antes de qualquer escrita — independe de ordem de processamento. Escrita em 1 statement `upsert_ranked_batch` (atômico no MySQL).
- **Anti-farm PDL** (`ranked.lua:122`): `< 2` char_ids distintos → sem PDL (sem adversário real).
- **Anti-enumeracao de perfil** (`init.lua:198`): perfil de terceiro só retorna se `cid == own_cid` OU `Ranked.has_played(cid)` (só quem competiu ranqueada).
- **Rate-limit por src+tag** (`init.lua:26`): `_rl[src][tag]` com sliding window. Tags: `lobby_join=800ms`, `lobby_confirm=500ms`, `lobby_leave=500ms`. Gameplay (`RACE_CHECKPOINT`/`RACE_TICK`) fora do rate-limit (têm cap próprio em AC).
- **`apply_telemetry`** (`runtime.lua:69`): top_speed monotônico clampado em `MAX_SPEED_KMH`; drift com cap por segundo `CAP_PER_SEC * dt_sec` — anti-spike em runtime (não só no finalize).
- **Telemetria carregada no próprio CP** (`runtime.lua:182`): no último CP (que dispara o finalize) o drift bancado e o top_speed já entram no payload — causa-raiz do bug `top_speed/drift = 0` resolvido.
- **Categoria FAIL-CLOSED** (`lobby.lua:150`): `category` vem da pista (SQL), nunca do cliente. PDL/temporada exige `category='ranqueada' E mode='rankeada'` (gate em `history.finalize`).
- **Senha nunca cruza fronteira**: `public_lobbies()` só expõe `has_password` boolean.
- **Editor coords server-side** (`editor.lua:42`): `GetPlayerPed(src) → GetVehiclePedIsIn → GetEntityCoords/Heading`. Cliente não propõe coords.
- **Editor ID rejeita colisão**: `id` do config (`source != 'custom'`) ou de outro criador → rejeitado.
- **TRUSTED exports** (`exports.lua:10`): `_invoker_allowed()` default-DENY. Whitelist `{vhub, vhub_admin}`. Mutations (`createLobby/cancelLobby/deleteTrack`) bloqueadas se caller não for trusted.

### 11.3 Gaps de anti-cheat identificados
1. **`MIN_CHECKPOINT_MS=400`** é curto demais para distâncias curtas — um teleport hack poderia disparar 2 CPs em 800 ms com distância ≈0. O `CP_MAX_TELEPORT_DIST=300` ajuda, mas um CP seguido do outro a 200 m em 400 ms seria válido (50 km/h médio — plausível).
2. **`speed > MAX_SPEED_KMH` só conta `warns`** — não bloqueia nem kicka. Sem threshold de warns para ação administrativa.
3. **Sem validação de tier/clone**: `track.vehicle_class` não é enforceado. Player pode entrar numa corrida "car" com bike/off-road (desde que o servidor não valide `GetVehicleClass` no join).
4. **`payload.pos` aceito como fallback** quando `GetPlayerPed(src) == 0` — atacante poderia forjar `ped == 0` (raro em produção) e enviar pos arbitrária. Comentário `#22d-i` reconhece o residual.
5. **Sem detecção de speedhack fora de CP**: `RACE_TICK` reporta `top_speed` mas o cap é só no finalize/runtime. Um speedhack contínuo só seria detectado se passasse do `MAX_SPEED_KMH` (400 km/h) — abaixo disso é aceito.
6. **`RACE_ABORT` com reason string**: cliente envia reason livre (`'fora_do_veiculo'`, `'morte'`); servidor aceita qualquer string. Sem impacto direto mas permite log spam.

---

## 12. Fluxos Principais (passo-a-passo)

### 12.1 Criar lobby (via iPad)
1. Player abre iPad → app "racha" → botão "Criar".
2. iPad chama `exports.vhub_racha:ipadRelay(src, 'create', { track_id, mode, laps, password, ... })`.
3. `ipadRelay` cria `CreateThread` (yield-safe), chama `LB.create(src, payload)`.
4. `LB.create`: resolve `mode/category/fee/password/laps`, cria instância `state='lobby'`, `ST.put_instance`, `ST.metrics.instances_created++`, auto-join do criador via `LB.join(src, inst.id, password)`.
5. `LB.join`: valida senha, `RW.charge_entry(src, fee)` (cobra fee), `Grid.alloc_slot`, adiciona player, transiciona `'lobby'→'pending'`, agenda deadline `PENDING_TTL_MS`, `broadcast_lobby_state`, `TriggerClientEvent(LOBBY_PENDING)`.
6. `ipadRelay` faz `exports.vhub_ipad:closeIpad(src)` → player vai ao totem físico no mundo.
7. Se erro → `appPush(src, 'racha', 'result', { ok:false, kind:'create', data })`.

### 12.2 Entrar em lobby (in-game — sem senha)
1. Player vê lobby na lista (via iPad) ou caminha até a ready-zone.
2. **Pelo iPad**: `ipadRelay(src, 'join', { inst_id, password })` → `LB.join(src, inst_id, password)`.
3. **In-game (NUI bridge)**: `RegisterNUICallback('vhub_racha.action')` com `action='request_join'` → `TriggerServerEvent(LOBBY_JOIN, inst_id)` → `init.lua:238` rate-limit 800 ms → `LB.join(src, inst_id)` (sem senha — só lobbies abertos).
4. `LB.join` cobra fee, aloca slot, `TriggerClientEvent(LOBBY_PENDING)`.
5. Player recebe `LOBBY_PENDING` → `client/lobby.lua` cria blip de rota, mostra overlay ready-zone.

### 12.3 Iniciar corrida (lobby → grid)
1. Player vai à ready-zone (raio 18 m do `track.start`).
2. Aperta **[E]** (control 38) — `client/lobby.lua:135` → `TriggerServerEvent(LOBBY_CONFIRM, inst_id)`.
3. Server `init.lua:228` rate-limit 500 ms → `LB.confirm_presence(src, inst_id, false)`.
4. `LB.confirm_presence`: valida `state='pending'`, `Grid.in_ready_zone(src, inst.ready_zone)` (server-side), marca `player.confirmed=true`. Se todos confirmados + `min_players` → `L.start(inst.id, false)`.
5. `L.start`: remove não-confirmados (sem refund), `state='warmup'`, `starts_at = ms() + COUNTDOWN_MS(7000)`, envia `RACE_PREPARE` com `grid_pos` para cada player, agenda `SetTimeout(7000) → Runtime.begin_racing(inst)`. Se `alerts_police` → `_police_alert`.

### 12.4 Countdown (warmup)
1. Client recebe `RACE_PREPARE` → `client/race.lua:100` monta `active`, teleporta para grid, `FreezeEntityPosition(true)`, chama `mode.start`, `refresh_totem`. `client/nui_bridge.lua:76` envia `hud_show` + `hud_countdown`.
2. HUD NUI (`web/modules/hud/hud.js:118`) mostra contagem 3..2..1..GO (setInterval 1 Hz, 800 ms após GO esconde).
3. Após 7000 ms no server → `Runtime.begin_racing(inst)` → `state='racing'`, `TriggerClientEvent(RACE_START, src, { inst_id, started_ms })`.
4. Client `RACE_START`: `FreezeEntityPosition(false)`, `mode.on_start`, notify. `countdown.lua:13` → `ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', 0.35)`. `nui_bridge.lua:90` → `hud_start` (inicia cronometro local).

### 12.5 Execução de volta (checkpoint por checkpoint)
1. Client `race.lua:173` thread 20 Hz: se `CP.inside(pos, target, radius)`:
   - Atualiza `active.top_speed`.
   - Chama `mode.on_checkpoint(active, cp_index)` (drift banca no último CP, circuit calcula volta, speedtrap soma velocidade).
   - `TriggerServerEvent(RACE_CHECKPOINT, { cp_index, pos, speed, top_speed, drift_score, t_ms })`.
   - `cp_index++`, se `cp_index > cp_total` → `active.finished=true, TOT.clear()`, senão `refresh_totem`.
2. Server `runtime.lua:161`: `AC.validate_checkpoint` (ordem, tempo, distância, speed), `player.cp_done++`, `apply_telemetry`, atualiza `lap`, `sync_state_bag`.
3. Se `cp_done >= cp_total` → `_player_finish`.
4. Paralelamente `client/sync.lua` envia `RACE_TICK` 1 Hz com drift/top_speed/best_lap.
5. `client/nui_bridge.lua` envia `vhub_racha.telemetry` 4 Hz para o HUD (distância ao próximo CP, speed, drift live/banked, combo).
6. `client/totem.lua` desenha o totem 3D nativo para o CP atual.

### 12.6 Finalização (ordem de chegada)
1. `_player_finish(inst, src)`: `player.finished=true, finished_ms=now`. Se primeiro → inicia `FINISH_GRACE_MS=60000` para os demais. Se todos terminaram → `RT.finish(inst.id, 'todos_terminaram')`.
2. `RT.finish`: `state='finished'`, `ST.metrics.instances_finished++`, `HIS.finalize(inst)`:
   - Coleta players, calcula `total_time_ms`, aplica `AC.cap_drift_score`/`AC.cap_top_speed`.
   - Sort por kind (drift/speedtrap/tempo), atribui `placement`.
   - Payout via `payout_dist(finalists)`.
   - `SQL.insert_history`, `SQL.insert_results`.
   - Se `mode='rankeada'`: `SQL.update_records + update_stats` para cada player; se `category='ranqueada'`: `VHubRachaRanked.apply_race(pdl_parts)` (Elo FFA).
   - Anexa `pdl_delta/pdl_new/division` ao player.
3. Para cada player: se `payout > 0` → `RW.pay(src, payout, 'race_payout')`. `TriggerClientEvent(RACE_FINISH, src, { placement, time_ms, drift, payout, history_id, winner_char, reason, mode, pdl_delta, pdl_new, division })`. Limpa state bag, `unbind_src`.
4. `ST.remove_instance(inst.id)`. `state='closed'`.

### 12.7 Persistência de resultado
- `vh_race_history` (1 linha por corrida): track/kind/mode/category/players_total/winner_char/winner_time_ms/pot_total/started_at/finished_at.
- `vh_race_results` (1 linha por player): placement/total_time_ms/best_lap_ms/drift_score/top_speed/finished/payout.
- `vh_race_records` (UPSERT por track+char): best_time_ms/best_drift/top_speed/runs/wins.
- `vh_race_stats` (UPSERT por char+kind): runs/wins/podiums/dnf/total_payout/total_drift/top_speed/best_time_ms.
- `vh_race_ranked` (UPSERT atomic batch por char): pdl/peak_pdl/matches/wins/last_match_at (SÓ se `category='ranqueada' E mode='rankeada'`).

### 12.8 Atualização de ranking
- `R.top(kind, mode, limit)` — query em `vh_race_stats` com `ORDER BY` dinâmico (wins DESC, podiums DESC, runs DESC; ou `best_time_ms ASC`; ou `total_drift DESC`).
- `R.ranked_ladder(limit)` — query em `vh_race_ranked WHERE matches > 0 ORDER BY pdl DESC, peak_pdl DESC`, enriquecida com `division` e nicks.

### 12.9 Recompensas
- `pot_total = Σ entry_fee` (somado em `LB.join`).
- Distribuição: `PAYOUT_3P = {0.70, 0.20, 0.10}` p/ 3+ finalistas; `PAYOUT_2P = {0.80, 0.20}`; `PAYOUT_SOLO = {1.00}`. Timeattack com `TIMEATTACK_BONUS_PCT=50%` no vencedor.
- Modo treino/freerun → sem payout (`dist = {}`).
- `RW.pay(src, payout, 'race_payout')` → `exports.vhub_money:giveBank`.
- Em cancelamento/leave antes do início → `RW.refund` (devolve fee).

### 12.10 Editor: criar/editar/salvar pista
1. Player abre iPad → app "racha" → aba "Editor" → "Iniciar".
2. `ipadRelay(src, 'editor_open')` → `ED.open(src)` → cria draft `phase='grid'` em `ST._drafts[char_id]`, `TriggerClientEvent(EDITOR_OPENED)`. `closeIpad` (vai in-game).
3. Client `client/nui.lua:27` → `L.open_editor=true, L.editor_draft=draft`. `client/editor.lua` thread renderiza overlays + captura input:
   - **Fase GRID**: estaciona veículo, [E] ou buzina → `EDITOR_ADD_GRID` → `ED.add_grid(src)` captura coords server-side. [G] → `EDITOR_PHASE cps`.
   - **Fase CPS**: dirige, [E] em cada CP → `EDITOR_ADD_CP`. [H] (headlight) → `EDITOR_UNDO`. [G] → `EDITOR_PHASE meta`.
   - **Fase META**: notify "abra o iPad para preencher dados e salvar".
4. Player reabre iPad → preenche `id/label/kind/laps/illegal/alerts_police/vehicle_class/default_fee/limit_seconds/min_players/max_players` → "Salvar".
5. `ipadRelay(src, 'editor_save', meta)` → `ED.save(src, meta)`:
   - Sanitiza `id` (regex, max 48), `label` (max 80).
   - Valida ≥1 grid slot, ≥1 CP (exceto freerun).
   - Rejeita `id` se bate com config ou com outro criador.
   - Aplica metadados. **Categoria sempre `'personalizada'`**.
   - `SQL.upsert_track + set_checkpoints + set_grid`, atualiza `ST._catalog`.
   - `appPush(src, 'racha', 'data', build_panel_data())` (refresh da lista).

### 12.11 Modo drift (física + scoring)
1. Player entra em corrida `kind='drift'`.
2. `client/race.lua` → `mode_for('drift')` → `VHubRachaModes.drift.start(active)` zera `drift_score=0, drift_live=0, drift_combo=1.0, _pending=0, _window_ms=0, _last_total=nil`.
3. **Drift resource** (`cl.lua`): thread principal detecta `speedKMH > 20 && isAccelerating && isHandbraking && IsVehicleOnAllWheels` → `activateDrift(veh)` (aplica `DRIFT_MODS` + `powerMult`), ativa boost se `currentAngle >= MIN_BOOST_ANGLE=20°` e cooldown OK. Fabrica `totalEarned += min(ângulo*velocidade/65, 100) * combo * dt/1000`.
4. **`client/modes/drift.lua`** bank loop (10 Hz): consome `exports.Drift:getTelemetry()`:
   - Baseline `_last_total`/`_last_crashes` na 1ª leitura.
   - `d_total = snap.total - _last_total` acumula em `_pending`.
   - `crashed` (snap.crashes mudou) → zera `_pending, _window_ms`.
   - `_window_ms >= BANK_MS(5000)` → `drift_score += _pending; _pending=0`.
   - `drift_live = drift_score + _pending`.
5. `client/sync.lua` envia `RACE_TICK` 1 Hz com `drift_score` (bancado).
6. `client/nui_bridge.lua` envia `vhub_racha.telemetry` 4 Hz com `drift_score` (live) + `drift_banked` (bancado) + `drift_combo`. HUD mostra pts + % bancado + combo.
7. **No último CP**: `mode.on_checkpoint` banca o pendente (idempotente).
8. Server `apply_telemetry` cap por segundo: `cap = CAP_PER_SEC(100) * dt_sec`. `AC.cap_drift_score` no finalize: `cap = CAP_PER_SEC * secs * max_combo_mult(3.0)`.
9. Persistência: `vh_race_results.drift_score` + `vh_race_stats.total_drift` + `vh_race_records.best_drift`.

### 12.12 Modo drag (árvore de largada, tempo)
- `client/modes/drag.lua` é no-op (`start` seta `best_lap_ms=0, false_start=false`).
- **Semáforo visual**: renderizado pela NUI HUD (`hud_countdown` 3..2..1..GO) + `countdown.lua` (camera shake no GO).
- **Geometria**: `LANE_SEPARATION=4.5` configurado mas definido pelo `track.grid` (cada slot é uma lane).
- **False start**: `DRAG.FALSE_START_MS=500` configurado mas **não implementado** no client (placeholder).
- **Tempo**: medido por `total_time_ms = finished_ms - started_ms` (genérico em `history.finalize`).

### 12.13 Modo timeattack
- `client/modes/timeattack.lua` no-op.
- `lobby.lua`: `track.kind == 'timeattack'` → `entry_fee=0`, `min_players=1` (solo).
- `history.lua`: `TIMEATTACK_BONUS_PCT=50%` no payout do vencedor.
- Sem PDL (só `category='ranqueada' E mode='rankeada'` conta PDL — timeattack costuma ser `mode='treino'`).

### 12.14 Modo speedtrap
- `client/modes/speedtrap.lua`: `on_checkpoint` soma `kmh * trap_combo` (combo cresce 5% a cada CP), `trap_total` reutiliza `drift_score` como score visível.
- Vencedor = maior `top_speed` (desempate `total_time_ms` — `history.lua:42-44`).
- `SPEEDTRAP.RADIUS_M=6.0` (config, mas CP radius vem da pista), `COMBO_BONUS=1.05`.

### 12.15 Modo circuit (voltas)
- `client/modes/circuit.lua`: `on_checkpoint` se `(idx % cps_per_lap) == 0` (fechou volta) → calcula `lap_ms`, atualiza `best_lap_ms`.
- Vencedor = menor `total_time_ms` (soma de todas as voltas).

### 12.16 Modo sprint (A→B)
- `client/modes/sprint.lua` no-op. Detecção de CP genérica em `race.lua`.
- Vencedor = menor `total_time_ms`.

### 12.17 Modo freerun
- `client/modes/freerun.lua` no-op.
- `lobby.lua`: `track.kind == 'freerun'` → `laps=0, mode='treino'`, sem fee, sem CPs obrigatórios.
- `history.lua`: `inst.kind == 'freerun'` → `dist = {}` (sem payout).
- Sem ranking, sem PDL.

---

## 13. Drift (recurso separado) — detalhamento

### 13.1 O que faz
`Drift/cl.lua` (296 linhas, 1 thread) implementa:
1. **Mecânica de drift**: quando `speedKMH > 20 && isAccelerating && isHandbraking && IsVehicleOnAllWheels` → aplica 7 modificadores de handling (`fSteeringLock+15`, `fTractionCurveMax-0.65`, etc.) + `SetVehicleEnginePowerMultiplier(veh, powerMult)` (150 p/ RWD, 120 p/ AWD). Reverte ao sair do drift.
2. **Boost controlado** (anti-exploit):
   - Ativa se `currentAngle >= MIN_BOOST_ANGLE=20°` E `(now - lastBoostEnd) > BOOST_COOLDOWN=4000ms`.
   - Dura `BOOST_DURATION=1200ms`: potência `powerMult * 2.0` durante, `powerMult` após.
   - Soltar handbrake aborta boost e força cooldown imediato (anti-spam).
   - Tapering por ângulo em curvas <100 km/h: `potência = 1.0 + (powerMult-1.0) * max(ângulo/30, 0.12)` (elimina drop abrupto).
3. **Fabricação de pontuação bruta**:
   - `pps = min(currentAngle * speedKMH / SCORE_DIVISOR=65, SCORE_CAP_PER_SEC=100)` por segundo.
   - `combo = comboFor(driftTimeMs)`: 1.0 → 1.5 (5s) → 2.0 (12s) → 3.0 (25s) de drift contínuo.
   - `totalEarned += pps * combo * dt/1000` (monotônico — nunca zera).
   - `crashCount` incrementa a cada queda de `body health > CRASH_HEALTH_DROP=8.0`.
   - `breakMs >= COMBO_BREAK_MS=700` zera combo (oscilação normal não derruba).

### 13.2 Como modifica física do veículo
- `setHandling(veh, enable)`: `SetVehicleHandlingFloat(veh, "CHandlingData", field, current + delta * ±1)` para os 7 campos. Reverte com sinal oposto.
- `SetVehicleEnginePowerMultiplier(veh, mult)`: 1.0 (normal), `powerMult` (drift ativo), `powerMult * 2.0` (boost).
- `DisableControlAction(0, 76, true)`: desabilita freio de mão nativo durante drift (mecânica custom).
- Whitelist de classes GTA: `{0,1,2,3,4,5,6,7,9}` (carros + off-road). Bicicletas (8), caminhões (10,11), etc. não são elegíveis.

### 13.3 Integração com vhub_racha (modo drift)
- **Export único**: `exports.Drift:getTelemetry() → { total, crashes, combo, angle, speed, drifting, active }`. Consumido por `client/modes/drift.lua:24` via pcall (nil-safe).
- **Divisão de responsabilidade** (README.md):
  - Drift: mecânica (handling + boost) + fabrica pontuação bruta + telemetria.
  - vhub_racha (modo drift): **banca** pontuação (5 s sem bater → válido), envia ao server, mostra HUD.
- **Alinhamento de config** (comentário `cl.lua:59-68`): `SCORE_CAP_PER_SEC=100` e `COMBO_MULT={1.5,2.0,3.0}` devem manter alinhados com `Cfg.DRIFT.CAP_PER_SEC=100` e `Cfg.DRIFT.COMBO_MULT={1.5,2.0,3.0}` do vhub_racha. Server é autoridade final (cap por segundo em `apply_telemetry`).

### 13.4 Integração com CORE/vhub
- **Nenhuma direta**. Drift é isolado (só `client_script 'cl.lua'`). Não depende de `vhub`, `vhub_money`, etc.
- Indiretamente: o veículo que Drift modifica é o mesmo que vhub_vehcontrol pode aplicar handling (F5 física). **Potencial conflito**: ambos chamam `SetVehicleHandlingFloat` — Drift em runtime (enter/exit drift), vehcontrol no F5 (skill alloc). Se um player estiver em drift com skill allocada, os 7 campos do Drift (`fSteeringLock`, `fTractionCurveMax`, etc.) podem sobrepor os do vehcontrol. Não há coordenação.

### 13.5 Integração com vhub_vehcontrol
- **Não há**. Drift não consulta `vhub_vehcontrol:getVehicleSheet`. vehcontrol não conhece Drift.
- **Risco**: handling do Drift é aplicado por `cur + delta` (incremental sobre o current). Se vehcontrol já aplicou um `fSteeringLock` modificado, Drift soma +15 em cima. Ao reverter, subtrai 15 — volta ao valor vehcontrol. Em princípio correto, mas se o player sair do veículo durante drift (sem revert), o handling fica "viciado" +15 para sempre. Drift tem `revertDrift(lastVehicle)` em troca de veículo/drop, mas não em `onResourceStop` do vehcontrol.

### 13.6 Estado interno (monotônico vs resetável)
- **Monotônico** (nunca zera): `totalEarned`, `crashCount`.
- **Resetável** (por sessão de drift contínuo): `driftTimeMs`, `breakMs`, `combo`, `isScoring`.
- **Por veículo**: `lastVehicle`, `lastHealth`, `lastTick`, `driftActive`, `boostActive`, `boostStartTime`, `lastBoostEnd`, `powerMult`.

---

## 14. Integração Cross-Resource

### 14.1 vhub_racha ↔ CORE/vhub
- **Handshake**: `bootstrap.lua` aguarda `exports.vhub:getVHub()` responder com `.Auth` (até 60 s, 250 ms poll). `B.vHub` guardado.
- **Sessões**: `sessions.lua` escuta `vHub:characterLoad` e `playerDropped` (eventos públicos do CORE). `_cache[src] = user`.
- **Re-emissão**: `REQUEST_INIT_DONE` (client→server) → `bootstrap.lua:85` re-emite `vHub:initDone` para o src autenticado.
- **Identity**: `vhub_identity:getFullName(src)` para nicks (`lobby.lua:60`).
- **Groups**: `vhub_groups:hasPermission(src, 'vhub.racha.editor')` (editor), `vhub_groups:hasPermission(psrc, 'policia.radio')` (police alert).
- **State Bags**: `Player(src).state:set('vhub_racha', { ... }, true)` (lobby/runtime).
- **NÃO usa** `commitVehicleState`/`getVehicleState` — vhub_racha não escreve estado de veículo (só teleporta no `RACE_PREPARE`).

### 14.2 vhub_racha ↔ vhub_conce
- **Nenhuma direta**. vhub_racha não valida veículo via conce (sem tier check, sem clone check). `track.vehicle_class` é só metadado.

### 14.3 vhub_racha ↔ vhub_vehcontrol
- **Nenhuma direta**. vhub_racha não consulta tier/sheet. vhub_vehcontrol não conhece racha.

### 14.4 vhub_racha ↔ vhub_money
- **Fronteira única**: `server/rewards.lua`. pcall em todas as chamadas.
  - `charge_entry(src, fee, reason)` → `exports.vhub_money:tryFullPayment(src, fee, false)` (debita carteira+banco).
  - `refund(src, amount, reason)` → `exports.vhub_money:giveBank(src, amount, reason)`.
  - `pay(src, amount, reason)` → `exports.vhub_money:giveBank(src, amount, 'race_payout')`.
  - `has_balance(src, amount)` → `exports.vhub_money:tryFullPayment(src, amount, true)` (dry-run).

### 14.5 vhub_racha ↔ vhub_inventory
- **Nenhuma**. vhub_racha não consome itens nem chama exports de inventário.

### 14.6 vhub_racha ↔ vhub_ipad
- **Painel completo** vive no iPad (`vhub_ipad/web/modules/racha/racha.{html,css,js}` — 40 KB JS).
- **Relay**: `exports.vhub_racha:ipadRelay(src, action, data)` (server). iPad chama via `vhub.app.channel('racha').send(action, data)`.
- **Push**: `exports.vhub_ipad:appPush(src, 'racha', kind, payload)` para enviar dados ao app (data/ranking/history/results/ranked/profile/result).
- **Close**: `exports.vhub_ipad:closeIpad(src)` para forçar fechamento (pós create/join/editor_open).

### 14.7 vhub_racha ↔ vhub_vrcs (replay cinematográfico)
- **Soft-dep** (pcall): `exports['vhub_vrcs']:onRaceStart({ inst_id, track_id, kind, mode, category, players })` em `runtime.begin_racing`, `exports['vhub_vrcs']:onRaceClose(inst.id, { winner_char, players })` em `RT.finish`.
- Recurso pode não existir — início da corrida nunca quebra.
- Recorder nunca grava nick/PII no `.vhr` (só char_id).

### 14.8 Drift ↔ vhub_vehcontrol
- **Nenhum**. Conflito latente em `SetVehicleHandlingFloat` (Drift modifica 7 campos em runtime; vehcontrol aplica alloc de skill no F5). Sem coordenação.

### 14.9 Drift ↔ vhub_racha/modes/drift.lua
- **Export único**: `getTelemetry()`. vhub_racha consome via pcall.
- **Sem escrita reversa**: vhub_racha não passa nada de volta ao Drift (Drift é agnóstico ao estado da corrida).

---

## 15. Configuração (Cfg = VHubRachaCfg)

### 15.1 Brand
- `BRAND_NAME = 'Mirage Racha'`, `BRAND_TAG = 'Liga clandestina'`.

### 15.2 Owner / Permissões
- `OWNER_CHAR_ID = 1`.
- `ADMIN_ACE = 'vhub.racha.admin'`, `ADMIN_PERMISSION = 'vhub.racha.admin'`, `EDITOR_PERMISSION = 'vhub.racha.editor'`.
- `TRUSTED_RESOURCES = { ['vhub'] = true, ['vhub_admin'] = true }`.

### 15.3 Comandos
- `CMD_TRAINING = 'racha_treino'` (`/racha_treino <track_id>` → solo sem prêmio).
- `CMD_EDITOR_DEBUG = 'racha_editor'`, `CMD_EDITOR_PT = 'racha_editor_pos'` (backup debug).
- **Painel /racha + F7 REMOVIDOS** — abre exclusivamente pelo iPad.

### 15.4 Lobby / Timing
| Config | Default | Descrição |
|---|---|---|
| `LOBBY_TTL_MS` | 300000 (5 min) | lobby sem confirmar = cancela |
| `PENDING_TTL_MS` | 300000 (5 min) | tempo para confirmar presença |
| `COUNTDOWN_MS` | 7000 | countdown na grid (3..2..1..GO) |
| `FINISH_GRACE_MS` | 60000 | grace após primeiro terminar |
| `MIN_CHECKPOINT_MS` | 400 | anti-spam de CP |
| `TICK_INTERVAL_MS` | 1000 | (não usado em runtime — sync.lua usa 1000 hard) |
| `RACE_SAFETY_TIMEOUT_S` | 1800 (30 min) | rede de segurança — nunca guilhotina |
| `CATEGORY_DEFAULT` | 'normal' | (não usado — category vem da pista) |

### 15.5 Ready Zone
- `RADIUS_M = 18.0`, `Z_TOLERANCE = 5.0`, `REQUIRE_VEHICLE = false`, `GAS_COLOR = {r=232, g=198, b=130}` (areia dourada), `GAS_ALPHA = 32`, `GAS_WISPS = 14`. Compat legado: `GLOW_COLOR/HEIGHT`.

### 15.6 Editor
- `EDITOR_MAX_CPS = 80`, `EDITOR_MAX_GRID = 12`, `EDITOR_DRAFT_TTL_MS = 1800000` (30 min).

### 15.7 Anti-cheat
- `CP_MAX_TELEPORT_DIST = 300.0` (m), `MAX_SPEED_KMH = 400`.

### 15.8 Payout
- `MAX_ENTRY_FEE = 100000`, `DEFAULT_ENTRY_FEE = 1000`.
- `PAYOUT_3P = {0.70, 0.20, 0.10}`, `PAYOUT_2P = {0.80, 0.20}`, `PAYOUT_SOLO = {1.00}`.
- `TIMEATTACK_BONUS_PCT = 50`.

### 15.9 Ranqueado (RANKED)
- `ENABLED = true`, `PDL_START = 1000`, `MIN_PDL = 100`, `C_FACTOR = 4000`, `K_FACTOR = 500`, `K_CALIBRATION = 1500`, `CALIBRATION_MATCHES = 10`.
- `DECAY`: `ENABLED=true, ABOVE_PDL=2200, PER_DAY=25, INACTIVE_DAYS=14, INTERVAL_MS=3600000` (1h).
- `DIVISIONS`: bronze(0), prata(1200), ouro(1600), platina(2200), diamante(3000), mestre(4000), lendario(5500).

### 15.10 Drift (Cfg.DRIFT)
- `BANK_MS = 5000`, `CAP_PER_SEC = 100` (alinhado com Drift `SCORE_CAP_PER_SEC`), `COMBO_MULT = {1.5, 2.0, 3.0}`.

### 15.11 Drag (Cfg.DRAG)
- `SEMAFORO_GREEN_MS = 3000`, `FALSE_START_MS = 500` (não implementado), `LANE_SEPARATION = 4.5`.

### 15.12 Speedtrap (Cfg.SPEEDTRAP)
- `RADIUS_M = 6.0`, `COMBO_BONUS = 1.05`.

### 15.13 Polícia (Cfg.POLICE)
- `PERMISSION = 'policia.radio'`, `BLIP_TTL_MS = 90000`, `HEAT_PER_MIN = 1` (não usado em runtime).

### 15.14 HUD
- `USE_NUI = true` (flag que libera envio de telemetria/statebag para NUI).

### 15.15 Totem (Cfg.TOTEM)
- `RENDER_RANGE = 999.0`, `SCALE_DIST = 999.0`, `MIN_HEIGHT = 5.0`, `MAX_HEIGHT = 150.0`, `COLUMN_W = 0.55`, `GROUND_OFFSET = 1.5`, `BASE_RADIUS = 8.0`.
- Cores: `COLOR_DEFAULT = {r=248, g=200, b=105}` (areia ouro neon), `COLOR_FINISH = {r=120, g=230, b=140}` (verde), `COLOR_SPEEDTRAP = {r=38, g=220, b=80}`, `COLOR_DRIFT_ZONE = {r=190, g=120, b=255}` (roxo).

### 15.16 Estilo / Blip
- `COLOR = {r=243, g=181, b=58}`, `BLIP = {show=false, sprite=38, color=5, scale=0.75}` (desligado por padrão — totem já marca).

### 15.17 Catálogo de pistas (VHubRachaTracks)
3 pistas pré-definidas no config:
1. `corrida_atk` ('atk 1') — sprint, ranqueada, 2 max players, 11 CPs, fee 1000, limit 900s.
2. `banham_blitz` ('Banham Blitz') — sprint, normal, 4 max players, 12 CPs, fee 1000, limit 150s.
3. `vinewood_descent` ('Vinewood Descent') — sprint, normal, 4 max players, 20 CPs, fee 1000, limit 300s.

Aceita 5 formatos de coords (normalizado em `checkpoints.lua`): record nomeado, `vec3`, array curto, string `/cds`, `{cds=vec3, h=N}` (preferido p/ grid).

### 15.18 Drift resource config (em `cl.lua`, não-vhub_racha)
- `CLASS_WHITELIST = {0,1,2,3,4,5,6,7,9}` (carros + off-road).
- `DRIFT_MODS` — 7 campos de handling.
- `BOOST_COOLDOWN = 4000`, `BOOST_DURATION = 1200`, `MIN_BOOST_ANGLE = 20.0`.
- `SCORE_MIN_ANGLE = 15.0`, `SCORE_MIN_SPEED = 30.0`, `SCORE_DIVISOR = 65.0`, `SCORE_CAP_PER_SEC = 100.0`, `CRASH_HEALTH_DROP = 8.0`, `COMBO_BREAK_MS = 700`, `COMBO_THRESHOLDS = {5.0, 12.0, 25.0}`, `COMBO_MULT = {1.5, 2.0, 3.0}`.

---

## 16. Pontos de Atenção

### 16.1 Possíveis violações do manual_dev_vhub
| Lei | Observância | Notas |
|---|---|---|
| **L-04** (um dono por dado) | ✅ | vh_race_* é domínio próprio do racha. PDL só escrito por `ranked.lua`. |
| **L-08** (PT-BR para usuário, EN para identificador) | ⚠️ | Comentários de função em PT-BR ✅, mas `VHubRachaLog` é o único `print()` autorizado — porém `bootstrap.lua:28,37,44,46,54,74` usa `print()` direto (não `VHubRachaLog`). Justificado no cabeçalho do logger ("VHubRachaLog existe em todos os módulos"), mas `bootstrap.lua` carrega antes do logger? Não — `shared/logger.lua` é o PRIMEIRO em `shared_scripts` (fxmanifest.lua:20), então `VHubRachaLog` já existe quando `bootstrap.lua` roda. **Violação menor**: `print()` em `bootstrap.lua` deveria ser `VHubRachaLog.info`. |
| **L-09** (1 responsabilidade por arquivo) | ✅ | `grid.lua` (geometria), `lobby.lua` (máquina de estados), `runtime.lua` (corrida ativa), `history.lua` (persistência), `rewards.lua` (dinheiro), `anti_cheat.lua` (validação), `ranked.lua` (PDL), `ranking.lua` (leitura), `editor.lua` (editor), `sessions.lua` (cache), `state.lua` (VRAM), `sql.lua` (queries). Separação excelente. |
| **L-10** (comentário PT-BR por função pública) | ✅ | Todas as funções públicas têm cabeçalho PT-BR. |
| **L-13** (escrita só no owner) | ✅ | vh_race_* é domínio do racha. vh_identity é só leitura (ranking.lua:22). vh_characters só FK. |
| **L-14** (não mutar vd.state) | ✅ | vhub_racha não toca em vd.state. Só teleporta no RACE_PREPARE (`SetEntityCoordsNoOffset` no veículo do player — não é vd.state). |
| **L-15** (todo .lua no manifest) | ✅ | Verificado: todos os 60+ arquivos .lua estão no fxmanifest. |
| **L-17** (replay-safe) | ✅ | `sessions.lua` é idempotente (sobrescreve _cache no re-fire). `bootstrap.lua` on_ready fila é idempotente. |
| **L-18** (orçamentos de performance) | ✅ | Idle: threads client usam `Wait(500/800/1000)` quando inativas. Hot path: `Wait(0)` só quando necessário (totem <999m, lobby <300m, editor ativo, race ativa). NUI fechada: `USE_NUI=true` mas `enabled()` gateia envio. |
| **L-19** (shape versionado) | ✅ | `profile_of` retorna `schema = 'vhub_racha.profile.v1'`. |
| **TriggerClientEvent(-1)** | ✅ | NÃO usado. Tudo é state bag ou TriggerClientEvent(src) direto. `_police_alert` itera GetPlayers() e dispara 1 evento por player com perm (não é -1). |

### 16.2 Anti-cheat gaps
1. **`MIN_CHECKPOINT_MS=400`** curto demais para distâncias curtas — teleport hack poderia disparar 2 CPs em 800 ms a 200 m (50 km/h plausível).
2. **`speed > MAX_SPEED_KMH` só conta `warns`** — sem threshold de ação. Sem log administrativo de warns.
3. **Sem validação de tier/clone** — `track.vehicle_class` não é enforceado. Player pode entrar em corrida "car" com bike.
4. **`payload.pos` aceito como fallback** quando `GetPlayerPed(src) == 0` — residual reconhecido (#22d-i).
5. **Sem detecção de speedhack contínuo** — só `top_speed` é capado no finalize. Speedhack abaixo de 400 km/h é aceito sem flag.
6. **`RACE_ABORT` com reason string livre** — permite log spam (sem impacto direto).
7. **`RACE_TICK` sem rate-limit** — client envia 1 Hz; server aceita sem checar frequência. Atacante poderia enviar 100 Hz. Mitigado por `apply_telemetry` cap por segundo (drift) e monotonic (top_speed), mas não bloqueia.
8. **Editor não valida veículo** — player pode editar pista em qualquer veículo (até a pé). `get_pos_h` aceita ambos.

### 16.3 Performance (telemetria sync)
- **Server hot path**: `RT.on_tick` (1 Hz por player) faz `apply_telemetry` (cálculo simples) + `Player.state:set` (state bag — delta gating nativo). Custo O(1) por player.
- **Server `RT.on_checkpoint`**: `AC.validate_checkpoint` (distância 2D + tempo) + `apply_telemetry` + state bag. O(1).
- **Client `race.lua` thread 20 Hz**: `CP.inside` (2 ops) + `TriggerServerEvent` (1 packet). 20 Hz é razoável — RACE_CHECKPOINT só dispara quando dentro do CP (raro).
- **Client `nui_bridge.lua` 4 Hz**: `SendNUIMessage` com `bag_key` diff (sem json.encode em hot path). Bom.
- **Client `totem.lua` `Wait(0)` quando <999m**: sempre ativo em corrida. `draw_totem` faz 3 DrawMarker + 1 DrawText por frame. Custo baixo mas constante.
- **Client `lobby.lua` `Wait(0)` quando <300m + pending**: thread de DrawMarker (gas + anel + N wisps) + thread NUI 20 Hz + thread [E]. 3 threads ativas simultaneamente — potencia 0.3-0.5 ms.
- **Server `L.gc_idle`** roda a cada 30 s (init.lua:84) — itera todas as instâncias. O(N) mas N é pequeno (instâncias ativas).
- **Server `Ranked.start_decay_cron`** roda 1x/hora, sweep 1x/dia — SetTimeout-chain, sem while-true.

### 16.4 Drift vs vhub_racha/modes/drift.lua — duplicação?
**NÃO há duplicação** — divisão de responsabilidade clara:
- `Drift/cl.lua`: **fabrica** pontuação bruta (ângulo × velocidade × combo) + mecânica (handling + boost). Não sabe que há corrida.
- `vhub_racha/client/modes/drift.lua`: **banca** pontuação (5 s sem bater → válido; bater perde lote pendente) + envia ao server + HUD.
- **Alinhamento necessário**: `SCORE_CAP_PER_SEC=100` (Drift) ↔ `Cfg.DRIFT.CAP_PER_SEC=100` (racha); `COMBO_MULT={1.5,2.0,3.0}` idem. Comentário explícito em ambos os arquivos alertando para manter alinhado. Se desalinharem, o cap do server (`apply_telemetry`) cortaria o drift abaixo do fabricado — score real seria menor que o HUD mostra.

### 16.5 Outros pontos de atenção
1. **`lobby.lua:60` `L.notify(Lang.t('lobby: Presensa confirmada.'), 'info')`** — typo na chave de lang (`'lobby: Presensa confirmada.'` não existe em `pt_br.lua`; `Lang.t` retorna a própria chave como fallback). Deveria ser uma chave válida ou string direta. Bug cosmético.
2. **`lobby.lua:28`** chaves de lang com `:` (`'lobby: Presensa confirmada.'`) e `'Voce esta comfirmado na corrida.'` (typo "comfirmado") — strings não estão no `pt_br.lua`. `Lang.t` retorna a chave como fallback. Bug.
3. **`race.lua:167-168`** `Lang.t('Modo Treino')` / `Lang.t('Modo Ranqued')` — chaves com espaços e typo "Ranqued". Em `pt_br.lua` existe `'Modo de treino'` e `'Mode de ranqued'` (também com typo "Mode" e "ranqued"). Inconsistência de chaves.
4. **`race.lua:241`** `Lang.t('Modo treino : Sem recompensas.')` — chave com espaços não existe. Fallback retorna a própria string.
5. **`race.lua:244`** `Lang.t('Fim da corrida', { placement })` — chave `'Fim da corrida'` não existe em `pt_br.lua`. Fallback.
6. **`race.lua:265`** `Lang.t('Voce esta fora do veiculo')` — chave não existe. Fallback.
7. **`race.lua:286`** `Lang.t('ALERTA de Policia', { data.label, data.kind })` — chave não existe. Fallback.
8. **`lobby.lua:60` (client)** `L.notify(Lang.t('Voce esta comfirmado na corrida.') or 'Presença confirmada — aguarde o início.', 'success')` — `Lang.t` sempre retorna string (nunca nil), então o `or` nunca dispara. Bug lógico.
9. **`Cfg.POLICE.HEAT_PER_MIN = 1`** declarado mas **não usado** em runtime.
10. **`Cfg.TICK_INTERVAL_MS = 1000`** declarado mas **não usado** (sync.lua usa 1000 hard-coded).
11. **`Cfg.DRAG.FALSE_START_MS = 500`** declarado mas **não implementado** no client.
12. **`Cfg.DRAG.SEMAFORO_GREEN_MS = 3000`** declarado mas **não usado** (countdown é genérico em `COUNTDOWN_MS=7000`).
13. **`LOBBY_CANCEL` e `LOBBY_FORCE_START`** declarados em `events.lua:50,54` mas **não registrados** (sem consumidor in-game — `init.lua:227` comentário).
14. **`NUI_OPEN`, `NUI_OPENED`, `NUI_REFRESH`, `NUI_RESULT`, `NUI_RANKING`, `NUI_RANKING_DATA`, `NUI_HISTORY`, `NUI_HISTORY_DATA`, `NUI_RESULTS`, `NUI_RESULTS_DATA`** — declarados em `events.lua:27-36` mas **não usados** (painel vive no iPad; overlay NUI usa mensagens tipadas `vhub_racha.*`). Mortos.
15. **`runtime.lua:138-151`** `exports['vhub_vrcs']:onRaceStart` — soft-dep a recurso que pode não existir. Se existir, envia `players = [{ src, char_id }]` — vazamento de `src` para recurso externo? Não é PII, mas é informação de sessão. pcall protege contra ausência mas não contra recurso malicioso.
16. **`bootstrap.lua:28,37,44,46,54,74`** usa `print()` direto em vez de `VHubRachaLog`. Violação menor de L-08 (logger é o único autorizado). Justificativa: bootstrap carrega antes do logger? Não — logger é 1º em shared_scripts. **Deveria usar VHubRachaLog**.
17. **`client/lobby.lua`** tem 3 threads `Wait(0)` simultâneas quando pending + <300m: DrawMarker + NUI projection + [E] fallback. Soma ~0.5 ms. Aceitável mas poderia ser consolidado.
18. **`client/editor.lua:36`** thread `Wait(0)` quando editor ativo — sempre ativo durante edição. DrawMarker para cada CP + cada grid slot. Com 80 CPs + 12 slots = 92 DrawMarkers por frame. Pode pesar em pistas grandes.
19. **`Drift/cl.lua:179`** thread principal `Wait(0)` quando `speedKMH > 20 && in vehicle`. Sempre ativo quando dirigindo — mesmo fora de corrida. Custo: getDriftAngle (sqrt + acos), getEntityVelocity, getEntityForwardVector, getVehicleBodyHealth. ~0.05-0.1 ms. Aceitável mas constante.
20. **`Drift` não tem `onResourceStop`** — se o resource for reiniciado durante drift ativo, o handling fica "viciado" (+15 steering lock, etc.) no veículo atual. Player precisa re-entrar o veículo para reverter. Bug.
21. **`Drift` não valida quem é o player** — qualquer player em qualquer contexto (free-roam, missão, etc.) tem o handling modificado quando acelera + freio de mão. Pode interferir com outros recursos que dependem de handling vanilla.
22. **`vhub_racha` não depende explicitamente de `Drift`** no fxmanifest (só `oxmysql, vhub, vhub_money, vhub_identity, vhub_groups`). `client/modes/drift.lua` usa `exports.Drift:getTelemetry()` com pcall — degrada sem pontuar se Drift não estiver ativo. Soft-dep correto.
23. **`vhub_racha` não depende de `vhub_ipad`** no fxmanifest. `ipadRelay` chama `exports.vhub_ipad:appPush/closeIpad` sem pcall — se o iPad não estiver ativo, o export retorna nil e o `CreateThread` interno ainda roda (sem efeito). Não quebra, mas não é graceful.
24. **`vhub_racha` não depende de `vhub_notify`** no fxmanifest. `client/state.lua:38` faz pcall com fallback `BeginTextCommandThefeedPost`. Correto.
25. **`vhub_racha` não depende de `vhub_vrcs`** — soft-dep pcall em `runtime.lua`. Correto.

---

## 17. Resumo Final

`vhub_racha` é uma **plataforma de corridas competitivas** de maturidade elevada dentro do ecossistema vHub — adere ao manual_dev_vhub v2.0 em quase tudo (L-04/09/10/13/14/15/17/18/19; pequenas violações em L-08 com `print()` em `bootstrap.lua`). Arquitetura server-authoritative consistente: cliente só envia intenção (CP/tick/abort/confirm), servidor valida tudo (anti_cheat.lua com fail-closed em distância e ordem), persistência centralizada em `sql.lua` (7 tabelas `vh_race_*`), escritor único para PDL (`ranked.lua`), fronteira única para dinheiro (`rewards.lua`).

**Pontos fortes**:
- Separação de responsabilidades exemplar (12 arquivos server, cada um com 1 domínio).
- Anti-farm PDL com snapshot-read atômico + dedupe por char_id + gate de temporada (`category='ranqueada' E mode='rankeada'`).
- Anti-cheat fail-closed em distância server-side (`GetEntityCoords(GetPlayerPed(src))`).
- Divisão de responsabilidade Drift↔racha/modes/drift.lua limpa (fabricante vs banco).
- NUI componentizada (runtime SPA + módulos isolados com lifecycle A-02 e cleanup A-07).
- Painel completo delegado ao iPad (single source of truth da UI com cursor); NUI do racha só tem overlays in-game (HUD + ready-zone).
- State Bags com `bag_key` diff (sem json.encode em hot path 4 Hz).
- Totem 3D nativo (sem NUI para o checkpoint) — performático e confiável.
- Editor visual hibrido (in-game captura coords server-side, iPad preenche metadados).
- Replay-safe (sessions.lua idempotente, bootstrap.on_ready fila).
- Soft-deps (vhub_vrcs, Drift, vhub_notify) todas com pcall.

**Pontos fracos**:
- Anti-cheat gaps: `MIN_CHECKPOINT_MS=400` curto, `warns` sem threshold de ação, sem validação de tier/clone, `payload.pos` fallback residual.
- 11 eventos NUI declarados mas mortos (painel migrou para iPad, eventos não foram limpos — violação de "deletar é entrega" L-15 em espírito, embora o hook só valide `.lua`).
- Chaves de lang inconsistentes (`'lobby: Presensa confirmada.'`, `'Voce esta comfirmado na corrida.'`, typos "Ranqued/Mode"). `Lang.t` retorna fallback (própria chave), então mensagens aparecem cruas na UI.
- `print()` em `bootstrap.lua` em vez de `VHubRachaLog` (viola L-08 menor).
- Drift não tem `onResourceStop` (handling viciado se reiniciado durante drift).
- Conflito latente Drift↔vhub_vehcontrol em `SetVehicleHandlingFloat` (sem coordenação).
- 3 configs declarados mas não usados (`HEAT_PER_MIN`, `TICK_INTERVAL_MS`, `FALSE_START_MS`, `SEMAFORO_GREEN_MS`).

**Próximos passos sugeridos**:
1. Limpar eventos NUI mortos (`NUI_OPEN`, `NUI_OPENED`, etc.) — são API pública mas sem consumidor.
2. Corrigir chaves de lang (adicionar em `pt_br.lua` ou trocar por strings diretas).
3. Trocar `print()` em `bootstrap.lua` por `VHubRachaLog.info`.
4. Adicionar `onResourceStop` no Drift para reverter handling em todos os veículos ativos.
5. Implementar `FALSE_START_MS` no modo drag (atualmente placeholder).
6. Enforcear `track.vehicle_class` no `LB.join` (check `GetVehicleClass` do veículo do player).
7. Adicionar threshold de `warns` (ex: 3 warns → kick + log admin).
8. Documentar o conflito Drift↔vehcontrol no Registro de Ownership (ownership de `SetVehicleHandlingFloat` em runtime).

---

*Fim do relatório — 17 seções, ~1500 linhas. Cruzar com `02_CORE_vhub.md` (state bags, Auth, events institucionais), `03_garage_fuel.md` (vhub_money/identity), `04_conce_custom.md` (PRONTUÁRIO), `05_vehcontrol_nitro.md` (handling/tier) para visão completa do ecossistema.*
