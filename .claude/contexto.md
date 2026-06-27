# vHub Mirage — Memória Institucional
_Escritor: `vhub_guardiao_revisao` | Atualizado: 2026-06-22 (#34 — `vhub_wow` motor de áudio 3D standalone APROVADO: porta xsound, escritor único de execução de áudio via exports PlayAtEntity/Destroy/SetVolume; soundName derivado server-side fecha spoof; netId gated por hasVehicleAccess; pasta referencia/ removida; vhub_voicePMA negado como expansão, nasce separado) | Atualizado: 2026-06-22 (#33 — CONSULTIVA/REJEITADA: proposta externa `vhvehicle` centralizador para substituir `vhub_conce` REPROVADA pelo arquiteto — premissa falsa, viola L-14/L-04/Doutrina da Placa; vh.md deletado, zero código mudou) | Atualizado: 2026-06-17 (fix #26 — persistência de tuning: customization MERGE-não-REPLACE por chave/índice em `VState:save`; turbo exclusivo da oficina via campo booleano; oficina persiste GTA-level; `/tuning` admin = visual-only) | Atualizado: 2026-06-15 (decisão #25 — ownership da config de ZONA de veículo movida p/ os donos de negócio: concessionária→`vhub_conce`, leilão→`vhub_ferinha`; garage = consumidor via PULL `getZones` no boot; lei nova L-19 vec3/vec4 + fronteira flat) | Atualizado: 2026-06-19 (#27 engine de skill em vhub_vehcontrol + #28 F5 física do skill confirmada em jogo + #29 vhub_nitro reescrito vRP→vHub; **DOUTRINA DA PLACA** cravada: toda verdade veicular persistida mora na placa via conce, derivados nunca persistem) | Atualizado: 2026-06-19 (#30 — nitro vira EIXO da FICHA do veículo: uso por proximidade APOSENTADO; liga/desliga + nível 1..10 (trade-off durabilidade↔velocidade) + Abastecer pela ficha do vhub_vehcontrol; vhub_nitro segue escritor ÚNICO de customization.nitro={kit,qty,enabled,level}, vehcontrol DELEGA via 3 exports TRUSTED + bridge) | Atualizado: 2026-06-20 (#31 — vhub_notify = toast global PADRÃO vHub: canal canônico evento `vHub:notify` distinto de vHub.Notify/webhook; reescrita QDEV/vule→Mirage liquid glass; textContent/rate-limit/clamp; legacyfuel já consome; resource UNTRACKED exige git add) | Atualizado: 2026-06-21 (#32 — sprint hardening segurança: N0-1 lock+compensação ACT_TRANSFER, transferOwner atômico; N0-2 exports default-deny; N0-3 handlers veiculares do CORE desarmados; core-frozen-v2.0) | Modelo: Claude Opus 4.8_

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
| **vhub_conce** | `[SCRIPTS]/vhub_conce/*` | **ESCRITOR ÚNICO** de `vhub_vehicles`/`vhub_vehicle_keys`/`vhub_dealership_stock` + espelho `vh_vehicles` (CORE). Identidade do veículo (chave↔placa↔dono), concessionária (compra/test-drive/estoque/placa única), catálogo, cron 24h de posse temporária, status/IPVA. `transferOwner` = ÚNICO escritor de `char_id` |
| **vhub_ferinha** | `[SCRIPTS]/vhub_ferinha/*` | **ESCRITOR ÚNICO** de `vhub_auctions`/`vhub_auction_bids`. Leilão (escrow em VRAM + finalize + cron 60s + reconcileOrphans no boot). P2P/marketplace genérico = futuro. Nunca escreve `char_id` (delega a `conce:transferOwner`) |
| **vhub_garage** | `[SCRIPTS]/vhub_garage/*` | **ENXUTO (pós-reorg)**: guardar/spawnar veículo decidido por CHAVE-ITEM + NUI do hub de veículos + impound (DDL/DML local) + log de auditoria (append). `SQL:*` das 3 tabelas de negócio = PROXY fino → `vhub_conce`; auction = delegator → `vhub_ferinha`. **Camada de compat intencional** (mantém ~16 call-sites internos + consumidores externos: inventory, admin) |
| **vhub_custom** | `[SCRIPTS]/vhub_custom/*` | **Oficina (F0-F4)**: bennys (estética `source='cosmetic'`), mec (reparo `source='repair'` + reboque), oficina (tuning `source='tune'`). Sem schema SQL próprio. Escritor de `vhub_vehicle_state` VIA `exports.vhub_conce:saveVehicleState`. `canOperate` obrigatório antes de todo save. NUI (F5) pendente. |

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
| Export cross-resource sem controle | `_invoker_allowed()` + `cfg.trusted_resources` whitelist. **N0-2 (decisão #32): default-DENY** — trust vazio/`nil` ou `caller==nil` ⇒ `false` (era `true`); negação por trust-vazio loga `Logger:warn` one-shot. Blast radius nulo: os 4 exports gated do CORE (`grantPerm`/`transferKey`/`banPlayer`/`unbanPlayer`) não têm caller externo (grep) |
| Double-connect (race playerConnecting) | `Auth._sessions` guard — `connect` só roda em `vHub:ready` |
| datatable crescendo indefinidamente | Invalidação de VRAM após `_set`; cópia plana em flush emergência |
| Ownership de entidade errado | ~~`NetworkSetEntityOwner` em `Veh:onEnter`~~ **FECHADO (N0-3, decisão #32)**: handlers `vSpawned/vDespawned/vEnter/vLeave/vState` do CORE DESARMADOS (corpo no-op `_vhDisarmed`, mantidos registrados p/ rate-limit+contrato). Executor não move mais ownership forjando vEnter com netid da vítima — handler inerte |
| Camada vehicle-KV morta (typo `@dkey`) | Hotfix `@dkey`→`@key` em `vh/set_vd`/`vh/get_vd` (decisão #20). `getVData`/`setVData` reativados; cadeia física do CORE volta a persistir |
| ~~`onStateUpdate` dormente (sem driver registrado)~~ **OBSOLETO (decisão #24)** | Cadeia física do CORE descontinuada — `vEnter`/`vLeave` não são mais emitidos (listeners do CORE dormentes, zero emissor); o físico persiste no PRONTUÁRIO `vhub_vehicle_state` (escritor único `vhub_conce/server/vstate.lua`) |
| `S:prepare()` cross-resource silenciosamente perdido | Resources externos usam `exports.oxmysql` direto; schema próprio em `sql/schema.sql` aplicado em `onResourceStart` |
| Spawn duplicado (core + player_state) | Core sem spawn modules; `vhub_player_state` é dono único do fluxo de spawn |
| Escritor concorrente de Routing Bucket | `vhub_player_state` = ESCRITOR ÚNICO (decisão #35; grep confirma 0 outro writer). Buckets 999 (entrada)/1 (mundo)/2 (atividade). `setBucket` no-op quando igual; replay-guard antes do setBucket impede re-isolar player do mundo; export `setActivityBucket` default-deny + `n∈{1,2}` nunca 999 |
| Crédito offline sobrescrito por SELECT stale de login (leilão) | `Core._loading[cid]` (set síncrono antes do SELECT) + `give_bank_char` faz wait+reload do DB após `add_bank_offline` — fix validado por análise de interleaving (decisão #19) |
| Escrow de leilão volátil (perda no restart com leilão 'active') | `reconcileOrphans()` no boot do ferinha estorna `current_bidder` (offline-safe) + devolve carro; lances vêm de `vhub_auctions.current_bid`. Janela ínfima lance↔crash resta (risco residual aceito) |
| Duplo-estorno de perdedores no reconcile | reconcile credita SÓ `current_bidder`; perdedores já estornados ao vivo via `refundEscrow` quando superados |
| Escrita concorrente de `char_id` / 3 tabelas de negócio / auction | Escritor único por tabela: `char_id`↔`conce:transferOwner`; `vhub_vehicles`/`_keys`/`_stock`↔`vhub_conce/sql.lua`; `vhub_auctions`/`_bids`↔`vhub_ferinha/sql.lua` (auditado 2026-06-03, zero writer paralelo) |
| msgpack binário MANGLED na fronteira Lua→JS do oxmysql (byte ≥0x80 → par UTF-8 C2/C3) → datatable/`vd.state` ilegíveis na releitura ("Falha ao desserializar msgpack") | Blindagem `'b64:'+base64(msgpack)` em `state.lua _pack/_unpack` (decisão #22a); drivers transportam string opaca ASCII-safe e NUNCA re-encodam; linha legada sem prefixo = fallback msgpack raw (replay-safe) |
| `vEnter` de placa SEM âncora em `vh_vehicles` → FK violation derrubava o flush atômico e re-enfileirava a op para sempre (`vh_vehicle_data` VAZIA) | GATE DE REGISTRO no `vhub_vehcontrol/server/main.lua`: `exports.vhub_garage:getVehicle` sob pcall FAIL-CLOSED; placa gated recebe ack (para o retry do cliente) e NÃO entra na cadeia física (decisão #22c) |
| `vehicleStateLoad` nunca aplicava (placa padded do native vs normalizada do servidor) → fuel preso no default nativo 65 | `plateKey()` normaliza AMBOS os lados em `client/vehicle.lua` (CORE, hotfix gated #22) + guard `DoesEntityExist`/`type(state)` |
| Payload `customization` hostil do cliente (garage) | `U.sanitizeCustomization` (whitelist de chaves + cap 8KB pós-jenc) nos 2 pontos de escrita: ACT_STORE e REPORT_STATE |
| Dupe de veículo no spawn/store da garagem | ACT_SPAWN deleta entidades com a placa antes de criar (anti-dupe); ACT_STORE valida proximidade do VEÍCULO server-side (placa E raio no MESMO predicado — dupe stale fora do raio não veta o legítimo) + `DeleteEntity` autoritativo |

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
12. **Reorganização de veículos (2026-06-03 — reescreve a decisão #12 original de 2026-05-20)**. A divisão monolítica do `vhub_garage` foi desmembrada por responsabilidade única (plano `metas/organização estrutural.md`, FASES 0–4 aplicadas, gates por fase). **Nova divisão de ownership:**
    - **CORE** = FÍSICO (`vd.state`: fuel/engine/body/odometer/pos/tuning) + âncora `vh_vehicles(plate)`. Inalterado, frozen.
    - **`vhub_conce`** = chave↔placa↔dono + concessionária + cron 24h + catálogo + status/IPVA. **Escritor único** de `vhub_vehicles`, `vhub_vehicle_keys`, `vhub_dealership_stock` e do espelho `vh_vehicles`. `conce:transferOwner` é o **único** ponto que escreve `char_id` (P2P, admin force, forceTransfer, leilão — TODOS unificados nele; `updateOwner` proxy+export removido).
    - **`vhub_ferinha`** = leilão (escrow + finalize + cron 60s + reconcileOrphans). Escritor único de `vhub_auctions`/`vhub_auction_bids`. Nunca escreve `char_id`.
    - **`vhub_garage`** = guardar/spawnar por **CHAVE-ITEM** (não por `char_id`) + NUI + impound. Garagem lista por `inventory:getVehicleKeys` (FASE 3); self-heal dá chave 'owner' ao dono no login; lend/clone dão chave-item temporária; revoke a retira. `Core:authorized` → `conce:canOperate` (behavior-neutral, mantém ramo "é dono" até cron-only puro).
    - **Estado físico** permanece exclusivamente no CORE (L-04). Chave-item física permanece em `vhub_inventory`. Tipos car/bike/plane/heli/boat/truck/trailer mantidos.
    - `vh_vehicles` (CORE, âncora física, FK de `vh_vehicle_data`) vs `vhub_vehicles` (conce, negócio) = separação intencional, NÃO duplicação.
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

18. **Proxies/delegators do `vhub_garage` = CAMADA DE COMPAT INTENCIONAL (2026-06-03)**. `vhub_garage/server/sql.lua` proxia as 3 tabelas de negócio para `vhub_conce`; `auction.lua`/`admin.lua` delegam leilão para `vhub_ferinha`. **NÃO devem ser removidos** na janela atual: mantêm ~16 call-sites internos do garage + os contratos públicos consumidos externamente (`exports.vhub_garage:getVehicle/listOwnerVehicles/isImpound/ipvaUntil/forceTransfer/forceImpound` por `vhub_inventory` porta-malas e `vhub_admin`). Remoção é cosmética/futura (FASE 6 do plano). DDL das tabelas migradas permanece no garage (borrow) até FASE 6.

19. **Hardening de crédito offline (escrow de leilão) — 2026-06-03 — FECHA findings 2/3 da segurança**. `vhub_money` ganhou `Core.give_bank_char(char_id, amount, reason)` + export `giveBankChar` (`_invoker_allowed`, trusted += `vhub_ferinha`): credita o BANCO por `char_id` ONLINE (crédito vivo via `give_bank`) ou OFFLINE (`SQL.add_bank_offline` = `INSERT ... ON DUPLICATE KEY UPDATE bank=bank+VALUES(bank), total_in+=` atômico + `tx_insert`). **Race de login durante crédito offline (finding da segurança) está FECHADA** por: guard `Core._loading[cid]` setado SÍNCRONO antes do SELECT em `load_entry` + no `give_bank_char`, após o `add_bank_offline` retornar, espera `while _loading[cid]` (até 500ms) e então RECARREGA a cache do DB (que já contém o incremento) — a row stale do SELECT de login nunca sobrevive ao próximo flush. Análise de interleaving confirmou que não há janela residual de perda de saldo (o reload sempre ocorre após o commit do incremento, e o `_loading` é a barreira que garante que a cache já existe). `vhub_ferinha`: `payChar`→`giveBankChar` (payout do vendedor + estorno de perdedor superado, offline-safe). `reconcileOrphans()` no boot do ferinha estorna SÓ `current_bidder` o `current_bid` (perdedores já estornados ao vivo via `refundEscrow` → evita duplo-estorno) + devolve carro + cancela. Lock cooperativo `Busy[id]` serializa bid/finalize/cancel sobre os yields.

20. **INCIDENTE / BUG-CRÍTICO do CORE FROZEN — hotfix `@dkey`→`@key` (2026-06-04)**. Justificativa escrita exigida pela regra de modificação pós-freeze (seção "Estado de congelamento"). **Causa-raiz** (perseguida por várias sessões): `server/sql.lua` preparava `vh/set_vd` e `vh/get_vd` com o parâmetro `@dkey`, mas o `_set`/`_get` COMPARTILHADO em `server/state.lua` SEMPRE liga o parâmetro de chave como `key` (a tabela de bind é `{ [idf]=eid, key=key, value=packed }` — `idf` para `vd` é `"plate"`, então NÃO existe `dkey` no bind). Resultado: `@dkey` ficava NULO → escrita falhava com `Column 'dkey' cannot be null` (erro real colado pelo usuário) e leitura filtrava `dkey=NULL` (nunca casava). **A camada vehicle-KV `getVData`/`setVData` estava MORTA desde o freeze (2026-05-22)** — quebrava silenciosamente (sob `pcall`) o autosave físico do CORE e os save-triggers de garage/conce/legacyfuel. FIX = code-only, 2 linhas, sem schema (coluna `dkey` no banco preservada; só o nome do bind mudou para `@key`, alinhando a user/char data que já funcionavam). **Exige RESTART**. Aprovado: `vhub_arquiteto` + `vhub_guardiao_revisao` (este gate). Permissão emergencial via `.claude/settings.local.json` (gitignored). **Regressão = ZERO**: nada podia depender de uma escrita que nunca landava nem de uma leitura que sempre retornava `nil`; o fix apenas ATIVA um caminho dormente-mas-intencional. **Bump pendente**: a regra pede major `core-frozen-v2.0`; registrado como hotfix pontual sem reabrir o freeze (decisão de não re-auditar o core inteiro por 2 linhas — manter selo v1.0 + nota de hotfix). NOTA latente fora de escopo: `getGData/setGData` passa `idf="dkey"` e `set_gd` usa `VALUES(@dkey, @value)` → a coluna `dkey` do global data recebe o eid sintético `"__g"`, não a chave real `k` (provável bug pré-existente do global-KV; NÃO tocado nesta janela, sem consumidor crítico conhecido).

21. **Reconciliação single-writer do `vhub_vehcontrol` — fecha a cadeia física (2026-06-04)**. Segundo bug composto do mesmo sintoma: o client do CORE (`client/vehicle.lua`) só envia `vHub:vState` (telemetria), NUNCA `vEnter` → `_veh[plate]` ficava vazio → `Vehicle:onStateUpdate` abortava sempre (sem driver registrado, odo/fuel/dano nunca acumulavam nem persistiam). O elo que faltava era um `vEnter`→`onEnter` que REGISTRA a placa no CORE. **`vhub_vehcontrol` passou a ser dono desse elo, NÃO uma 2ª fonte (L-04)**: o server (`server/main.lua`) só AUTORIZA (chave/dono) + aciona `Vehicle:onEnter`/`onLeave` (sem `setVData`); o client (`client/main.lua`) detecta motorista e envia `vEnter` com retry+ack (cap 5, anti-flood 500ms server-side, `_running` guard L-06). **Removida a 2ª fonte que existia antes**: server `vLeave` com `setVData`, `applyPhys` emit, client `applyPhys` handler, e os eventos `vhub_odo_seed`/`vhub_odo_km` do velocímetro — TODOS deletados. **CORE = ESCRITOR ÚNICO de `vh_vehicle_data 'state'`**: `onStateUpdate` acumula + autosave 60s grava + `vehicleStateLoad` carrega; o client do CORE aplica fuel/eng/body no native; o velocímetro APENAS LÊ os State Bags `vh_fuel`/`vh_odo` + `vHub:vehicleStateLoad` e integra a distância de EXIBIÇÃO localmente (efêmero, nunca persiste; bag = piso, nunca override). **ATUALIZAÇÃO VELO-3 (2026-06-05): o velocímetro NÃO vive mais no `vhub_vehcontrol` — foi extraído para o resource `vhub_velo` (dono único do HUD de display; ver seção "Ownership por resource externo › vhub_velo"). O vehcontrol ficou só com controle + cinto + sync vEnter/vLeave. O contrato de leitura (bags + `vehicleStateLoad`, consumidor puro, nunca persiste) é idêntico, apenas mudou de resource.** `legacyfuel`/`garage`/`conce` mantêm `setVData(plate,'state',vd.state)` mas operam no MESMO objeto `vd` do CORE (via `getVehicle`/`getVHub`) — **save-triggers sobre o objeto compartilhado, não 2ª fonte**. Com o typo #20 corrigido, esses save-triggers AGORA LANDAM (antes eram no-op silencioso). **D1 (fuel com 3 autoridades) e o "/fuel zera no apply" / "odômetro não conta" só fecham após VALIDAÇÃO RUNTIME** — este path nunca esteve vivo; a ordenação de escrita entre save-triggers concorrentes sobre a mesma key `state` é agora ativa (último a serializar por flush vence; sem cópia divergente pois é o mesmo objeto). Risco residual: ver "Riscos residuais (reorg veículos)".

22. **Hotfix persistência veicular (2026-06-11) — blindagem b64 + vEnter gated + plateKey**. Root cause TRIPLO, evidência verificada no MySQL `vhub`: (1) msgpack binário MANGLED na fronteira Lua→JS do oxmysql (byte ≥0x80 → par UTF-8 C2/C3; hex real da row de `vh_user_data` confirmou) → `_unpack` falhava → datatable (incl. `user.data.state.position`) e `vd.state` = nil; (2) `vhub_vehcontrol` registrava QUALQUER placa dirigida no CORE → `vh/set_vd` sem âncora em `vh_vehicles` → FK violation re-enfileirava a op para sempre; (3) `client/vehicle.lua` comparava placa padded vs normalizada → `vehicleStateLoad` NUNCA aplicava fuel/engine/body.
    - **(a) FORMATO DE SERIALIZAÇÃO BLOB `vh_*_data` = `'b64:' + base64(msgpack)`.** ESCRITOR ÚNICO do formato: `state.lua _pack/_unpack`. Drivers transportam string opaca ASCII-safe e NUNCA re-encodam/decodam (contrato de escrita). Guard 60KB do `_set` vale PÓS-encode (cap raw efetivo ~45KB; BLOB 64KB protegido por construção). Linha legada sem prefixo = fallback msgpack raw (replay-safe, sem migração). CORE FROZEN tocado sob gate (vhub_arquiteto a8207b5e75a9cf697 + re-gate A2 adecade0943a78f1a; precedente #20) — aditivo, ~75 linhas, sem schema. Encode determinístico no funil único → double-armor impossível por construção.
    - **(b) DRIVER ATIVO em produção é o INTERNO do `bootstrap.lua`** (per-op, sem transação). O adaptador externo `vhub_oxmysql` NUNCA assume enquanto o boot síncrono existir (`registerStateDriver` recusa quando `State._ready`) — fix de serialização no driver externo nasce MORTO. `vhub_oxmysql/driver.lua` RESTAURADO ao committed nesta janela (L-15: a blindagem que tinha sido escrita nele era código morto; movida para `state.lua`).
    - **(c) vEnter GATED POR REGISTRO** (`vhub_vehcontrol/server/main.lua`): só placa com identidade no registro (`vhub_vehicles`, espelho `vh_vehicles`) entra na cadeia física do CORE — `exports.vhub_garage:getVehicle` sob pcall FAIL-CLOSED; placa gated recebe ack (para o retry) e NÃO persiste. Carro de rua/test-drive/rental NÃO persiste estado físico (status quo explicitado, sem âncora FK). Veredito 2026-06-02 "natives de entidade instáveis server-side" = OBSOLETO (`GetAllVehicles`/`GetEntityCoords`/`GetVehicleNumberPlateText` provados server-side com OneSync Infinity).
    - Endurecimentos da mesma janela: anti-spoof placa↔netId best-effort no vEnter (quando a entidade resolve, a placa declarada PRECISA bater) + collision-guard `_byNet`; garage ACT_STORE valida proximidade do VEÍCULO server-side + `DeleteEntity` autoritativo; ACT_SPAWN anti-dupe; `U.sanitizeCustomization` em ACT_STORE e REPORT_STATE; `findByPlate()` fallback p/ handle stale no `collectClientState` (mods não somem mais silenciosamente) + tolerância chave string em neons pós-JSON. Operação manual no DB documentada: auditoria nas 4 `vh_*_data` → única row legada provadamente mangled (`vh_user_data(uid=1,'datatable')`, só current_login/is_owner, regenerados no login) DELETADA.
    - **(d) RESIDUAIS ACEITOS:** (i) netId não-resolvível passa sem checagem placa↔netId (validação best-effort; telemetria segue protegida por `vd.driver==src` + lookup por placa gated); (ii) plate-swap em entidade ownada permanece vetor teórico de poluição do estado da própria placa (mitigado por DeleteEntity/anti-dupe; pendência futura); (iii) `_flush` do core segue descartando silenciosamente em falha total de batch (frozen, não tocado); (iv) valores DENTRO das chaves whitelisted de customization não são deep-validados (bounded pelo cap 8KB; aplicados client-side no próprio veículo).

23. **Hotfix padding de placa (2026-06-11) — `plateOf()` normalização bilateral + guard vEnter/vLeave**. Root cause: `GetVehicleNumberPlateText` retorna string de 8 chars com padding bilateral (`" MITAGE "` → trimming só de trailing → `" MITAGE"` → `normalizePlate` do CORE rejeita leading space → `register` retorna `nil` → `onSpawned` chama `vd:_syncBags()` com `vd=nil` → crash; `vh_vehicle_data` nunca escrito, fuel/mods/posição nunca persistem). **Dois arquivos modificados (ambos fora do CORE FROZEN):**
    - `vhub_vehcontrol/client/main.lua` (`plateOf`, linha ~37): adicionado `p:upper():gsub('%s+', ' '):match('^%s*(.-)%s*
    - Testes: `test_blob_armor_roundtrip` no testrunner (binário 0x00–0xFF, colisão de prefixo `'b64:'` em valor interno, 2º ciclo write→flush→read) + `tools/test_b64_roundtrip.lua` offline standalone (RFC 4648 + 200 aleatórios + bench — PASSOU em Lua 5.4.8; bench: blob 3KB <1ms, 45KB ~4-8ms). Rollback de 1 linha: `git checkout HEAD -- "resources/[CORE]/vhub/server/state.lua"` (legado raw segue legível; rows já blindadas exigiriam decode manual — rollback só ANTES de acumular escrita nova).

24. **PRONTUÁRIO físico veicular (2026-06-12) — `vhub_vehicle_state` substitui a cadeia física do CORE; escritor único = `vhub_conce` (supera #21; reescreve o item "Estado físico" da #12)**. MOTIVAÇÃO: a cadeia `vh_vehicle_data 'state'` quebrou 5x (#20 typo @dkey, #21 elo vEnter, #22 b64/FK/plateKey, #23 padding) e a premissa da #21 era FALSA — exports FiveM devolvem CÓPIA serializada, logo `legacyfuel`/`garage`/`admin`/`maintenance` mutando `vd.state` via `getVehicle`/`getVHub` eram NO-OP real (nunca houve "save-trigger sobre o mesmo objeto").
    - **Schema**: `vhub_vehicle_state` (DDL idempotente em `vhub_conce/server/vstate.lua`): 1 linha/placa — `plate VARCHAR(12) PK, fuel FLOAT, engine_health FLOAT, body_health FLOAT, odometer_km DOUBLE, customization MEDIUMTEXT(JSON), damage TEXT(JSON), damage_log MEDIUMTEXT(JSON, FIFO 30), updated_at INT`. DEFAULTs = estado de fábrica (telemetria manda snapshot FULL — row-miss nunca ressuscita default em veículo usado). **SEM FK** — substitutos: âncora fail-closed no escritor (`SELECT status FROM vhub_vehicles`; sem linha → NADA escrito), `reconcileVehicleState` disparado pelo GARAGE pós-DDL com guarda dupla (NUNCA no boot do conce; `COUNT(vhub_vehicles)>0` — DB parcial/restore não vira wipe), `deleteVehicle` limpa junto + evict do cache VRAM.
    - **Regras do escritor** (`VState:save(plate, patch, source)`): placa SEMPRE `normalizePlate` em todo read/write; `source='telemetry'` REJEITADA quando `status~='out'` (anti race store×telemetria — garage seta status ANTES de salvar) e health MONOTÔNICO não-crescente (anti repair-hack; só `source='repair'` eleva e limpa dano); `finiteNum` anti-NaN/Inf ANTES do clamp; odômetro é DELTA acumulativo (cap 2 km/snapshot); customization/damage com whitelist+cap (8KB/2KB); UPSERT IMEDIATO per-op (sem buffer — nada pendente em stop/drop). Backfill/seed/reconcile idempotentes (INSERT IGNORE / UPDATE gated / DELETE NOT IN).
    - **Fluxo**: vehcontrol client (motorista) drena fuel 1s por rpm/classe + decor (delta-gate 0.5) → snapshot FULL 15s + final no leave → server `stateSync` FAIL-CLOSED (netId resolve + placa bate + `GetPedInVehicleSeat(-1)==ped`; gate temporal 14s, final 2s, dedup leave×tick; GC dos mapas em playerDropped) → `exports.vhub_conce:saveVehicleState(...,'telemetry')`. Entrada: `requestState`→`applyState` com control-gate (`NetworkRequestControlOfEntity`), bone-check de janelas, tyres burst/rim separados (skip se `not GetVehicleTyresCanBurst`); evento LOCAL `stateApplied` semeia o odômetro do `vhub_velo`. **EXCEÇÃO consciente ao residual #22d-i**: aqui netId não-resolvível = DROP (este evento ESCREVE estado; o vEnter antigo só ancorava).
    - **CORE INERTE, FROZEN INTOCADO**: emitters `vEnter`/`vLeave` DELETADOS do vehcontrol; handlers `vHub:vEnter/vLeave` (`boot.lua`) e `NET_V_ENTER/LEAVE` (`events.lua`) do CORE permanecem listeners DORMENTES (zero emissor — nada foi tocado no CORE neste sprint; o diff do CORE no working tree é o dos hotfixes #22/#23). Bags `vh_fuel`/`vh_odo` ficam dormentes → painel vc-fuel opera pelo fallback native; velo usa `stateApplied`. NUNCA reanimar a cadeia do CORE sem gate do arquiteto.
    - **Customization MIGROU** para o prontuário: `backfillVehicleState` 1x (INSERT IGNORE + UPDATE onde NULL; garage dispara pós-DDL); `updateCustomization(plate, custJson, locked)` mantém a assinatura — persiste só o `locked` (negócio) e REDIRECIONA o cosmético ao VState. Coluna `vhub_vehicles.customization` = **DEPRECATED (2026-06-12), NÃO dropada**; leitores restantes são só FALLBACK pré-backfill (`garage.lua:117`, `admin.lua:377`). **VERDADE registrada por este gate**: `createVehicle` (conce/sql.lua:86/93) AINDA insere o valor de fábrica na coluna legada (idêntico ao seed do prontuário — safety net; contradiz o comentário "nunca mais escrita" de `conce/sql.lua:128`; inofensivo pois o leitor prefere o prontuário e o valor nunca diverge — limpar na FASE 6). **MERGE não-REPLACE (fix #26, 2026-06-17)**: `VState:save` MESCLA `customization` por chave sobre o persistido (`mods` por índice), nunca substitui a coluna inteira — patch parcial (bennys/oficina) preserva o resto; patch completo (garage store) == replace. `cur` em `VState:save` é REF VIVA do cache VRAM: `mergeCust` produz tabela nova (nunca muta `cur`/`cur.mods`).
    - **Fuel**: fonte única = native local da entidade, drenado pelo MOTORISTA. Bomba (`vhub_legacyfuel` REESCRITO; pokes na VRAM do CORE removidos): preço SERVER-SIDE do delta vs persistido; entidade que não resolve → aborta ANTES de cobrar; galão segue preço do cliente CLAMPADO 1..100000 (money sink, sem ganho — residual aceito, pré-existente no legado). **Posição NÃO entrou** (segue em `vhub_vehicles.position`). `meta.veiculo` da chave-item enriquecido com dossiê em CÓPIA (inventory `wireSnapshot`; JS nunca assume o campo).
    - **L-18 (gate performance APROVOU)**: gate temporal server 14s/2s; drain client 1s; decor delta-gate 0.5; snapshot 15s FULL; sem índice em `updated_at`; cache VRAM read-through com evict no delete; escrita per-op (volume ≈ 1 UPSERT/15s/motorista). Tabela completa de orçamento no transcript do gate (agente a68b06e9bde443ffb).
    - **Exports novos** (`_invoker_allowed`; TRUSTED += `vhub_vehcontrol`/`vhub_legacyfuel`/`vhub_testrunner`): `getVehicleState` (**NUNCA nil p/ placa registrada** — fábrica se nunca persistiu; difere do homônimo legado `exports.vhub:getVehicleState` do CORE), `saveVehicleState`, `repairVehicleState` (único que ELEVA health), `getVehicleDossier`, `backfillVehicleState`, `reconcileVehicleState`.
    - **RESIDUAIS NOVOS ACEITOS**: (i) telemetria pode ELEVAR fuel sem pagamento (motorista é a fonte; bounded 0..100, sem dinheiro envolvido); (ii) snapshot duplicado dentro da janela do gate somaria odômetro 2x (cap 2 km + dedup 14s/2s → desprezível); (iii) galão undercharge (clamp; legado); (iv) comentário stale em `vhub_vehcontrol/fxmanifest.lua:33` ainda cita "sync vEnter/vLeave ao CORE".
    - **TESTES_FALTANTES (runtime, antes de considerar o path fechado)**: dirigir→abastecer→guardar→restart→spawnar (fuel/health/odômetro/dano/customization vindos do prontuário); `vhub_run_tests` → `test_vstate_roundtrip` (placa suja, merge parcial, fail-closed); resmon do vehcontrol em uso (L-18). Rollback: reverter os 23 arquivos do sprint em `[SCRIPTS]` (`git checkout HEAD -- <paths>`) — a tabela nova é aditiva e fica órfã inofensiva. **`resources/[CORE]/vhub_legacyfuel/` está UNTRACKED no git — exige `git add` no commit do sprint.**

25. **Reorg de ownership da config de ZONA de veículo + lei L-19 (2026-06-15)**. MOTIVAÇÃO: a config de localização (blip/zona/test_spawn) da CONCESSIONÁRIA e da CASA DE LEILÕES vivia em `vhub_garage/shared/config.lua`, mas o dono do negócio é `vhub_conce` (concessionária) e `vhub_ferinha` (leilão) — `conce`/`ferinha` tinham zero config de localização própria. Movido para o dono; o garage virou CONSUMIDOR.
    - **Migração de ownership**: bloco `concessionarias` (5 zonas) → `vhub_conce/shared/config.lua` (`VHubConce.cfg.concessionarias`); `leilao_local` (1 zona) → `vhub_ferinha/shared/config.lua` (`VHubFerinha.cfg.leilao_local`). Ambos REMOVIDOS de `vhub_garage/shared/config.lua` (só `garagens` + `patio_local` permanecem no garage = zonas próprias). Confirmado por grep: nenhum leitor de `CFG.concessionarias`/`CFG.leilao_local` sobrou no garage.
    - **Novos exports read-only** (`_invoker_allowed`; ambos já whitelistam `vhub_garage`): `exports.vhub_conce:getZones()` → LISTA achatada `{id,label,x,y,z,raio,tipos,blip,test_spawn={x,y,z,h}}`; `exports.vhub_ferinha:getZones()` → OBJETO flat único `{id,label,x,y,z,raio,blip}` (ou nil). Config estática, sem schema/SQL novo.
    - **Garage = consumidor via PULL no boot** (`server/init.lua`, dentro do `onResourceStart` já existente): `VHubGarage.concessionarias = exports.vhub_conce:getZones() or {}` + `VHubGarage.leilao = exports.vhub_ferinha:getZones()`, ANTES dos emissores de SETUP. `VHubGarage.concessionarias` nunca-nil (default `{}` no load + `or {}` no PULL). Novo `buildSetup()` único alimenta os 2 emissores (boot broadcast + `vHub:playerSpawn`); helpers `flatZone`/`flatZones` achatam as zonas PRÓPRIAS do garage (garagens/patio: `coord` vec3→{x,y,z}, copiando antes de `coord=nil` — não muta a config). `Core:resolveConc(id)` UNIFICA os 3 `getConc` locais (dealership/rental/REQ_CATALOG); REQ_CATALOG passou a enviar à NUI só `conc = {id,label}` (era o objeto cru).
    - **Lei nova L-19** (CLAUDE.md "Leis estendidas"; ref. em AGENTS.md): coords = vetores nativos — `vec3(x,y,z)` p/ blip/zona/marker/raio, `vec4(x,y,z,w=heading)` SÓ p/ spawn de veículo/ped. vec é uso LOCAL: NÃO cruza `TriggerClientEvent`/`TriggerServerEvent`/`exports`/`SendNUIMessage` (msgpack entrega vetor como tabela indexada `{1,2,3}`; `json.encode(vec)`={}). Na fronteira a coord vai flat `{x,y,z[,h]}` e o consumidor reconstrói. Por isso `getZones` achata e `conc`→NUI virou `{id,label}`. Adoção INCREMENTAL (código novo + config tocada).
    - **Contrato de borda PRESERVADO**: cliente (`client/zones.lua`/`init.lua`) INALTERADO — SETUP segue FLAT (`g.x/g.y/g.z`, `state.leilao.x`, `state.patio.x`) e `findZone` reconstrói `vector3(...)` localmente. Round-trip `conc`→`exports.vhub_conce:buy/testDrive` íntegro: a forma flat do getZones preserva `tipos`, `id`, `test_spawn={x,y,z,h}` e o fallback `conc.x/.y/.z` (dealership.lua:136) — `test_spawn.h` mapeado de `vec4.w` no getZones. Regressão = ZERO por construção.
    - **Limpeza (L-15)**: `getConc` local removido de dealership.lua/rental.lua; `CFG` não usado removido de dealership.lua (rental mantém `CFG` p/ tarifas); `veh.zip` (lixo) removido; spec "Handling Balancer" (2× duplicada no arquivo + 2 pastas erradas, incl. `resources/[TOOLS]/vhub_testrunner/script.md` e `resources/[SCRIPTS]/script.md`) consolidada 1× em `tools/handling-balancer/script.md`. Working tree = exatamente os 12 arquivos do diff; zero órfão.
    - **Gates**: arquiteto APROVAR; performance APROVAR (PULL = custo único de boot, getZones estático); natives APROVAR (2 reparos aplicados); contrato/simplicidade REPROVAR/REDUZIR_ESCOPO com TODAS as correções aplicadas; este gate (revisão) APROVAR.
    - **RESIDUAIS ACEITOS**: (i) `vhub_ferinha` NÃO está no bloco `dependencies` do `fxmanifest.lua` do garage (só `vhub_conce` está) — o novo `getZones()` (init.lua:82) NÃO está sob pcall, igual aos exports ferinha já existentes em `auction.lua`/`admin.lua`/`sql.lua:111` (`getAuctionByPlate`); a coupling garage→ferinha é PRÉ-EXISTENTE, não introduzida aqui; recomendado adicionar `vhub_ferinha` às deps numa janela futura para blindar a ordem de start (se ferinha subir depois, leilao=nil → blip do leilão some até restart do garage). (ii) 2 `print()` de boot pré-existentes em `garage/init.lua:101/107` (hook L-08 flaga) — consistentes com todos os resources externos; `vHub.Logger` não é acessível cross-resource; NÃO introduzidos neste sprint; limpeza fica com o dono.
    - **TESTES_FALTANTES (runtime, antes do freeze)**: editar `vhub_conce/shared/config.lua` (mover concessionária) → restart → blip/zona na nova posição; comprar + test-drive + **aluguel** (3º call-site de `resolveConc`); abrir catálogo (REQ_CATALOG com `conc={id,label}`); resmon do garage. Rollback: `git checkout HEAD -- <12 arquivos do diff>` (sem schema/SQL — reversão limpa de 1 comando).
    - **NOTA DE MANUTENÇÃO**: `contexto.md` está em ~145 KB, MUITO acima do cap de 20 KB do protocolo — débito pré-existente acumulado; arquivamento para `contexto_arquivo/` pendente de janela dedicada (não feito aqui para não arriscar a memória mid-sprint).

26. **vhub_custom — Oficina (bennys/mec/oficina) (2026-06-16 — APROVADO COM RESIDUAIS)**. Resource novo `[SCRIPTS]/vhub_custom`: 1 resource / 3 domínios. Skeleton (F0+F1) + domínios server+client (F2-F4) implementados. NUI (F5) pendente — skeleton aprovado, menus por comando temporário. Escritor de `vhub_vehicle_state` via `exports.vhub_conce:saveVehicleState` com `source='cosmetic'/'tune'/'repair'`. Sem schema SQL novo.
    - **TRUSTED**: `['vhub_custom'] = true` adicionado em `vhub_conce/server/exports.lua`.
    - **Guard source no VState (vstate.lua:247)**: `source='cosmetic'/'tune'` isola patch a `customization` apenas — bloqueia elevação de health/fuel por essas fontes. `source='repair'` (mec.lua:90) usa caminho trusted de elevação de health (VState aceita; contrato #24 respeitado). `repairVehicleState` não é chamado pelo custom — usa `saveVehicleState(...,'repair')` com patch explícito; caminho válido.
    - **MOD_SPLIT server-side**: bennys rejeita `performance_mods` via `buildCosmeticPatch` + dupla defesa; oficina aceita SOMENTE `performance_mods`. Sem sobreposição por construção.
    - **`canOperate` antes de todo save**: bennys:127, mec:37, mec:126. `mecTowDone` NÃO revalida — server validou em `TOW_REQ` + lockrou migração; `mecTowDone` é resposta (não entrada fria). RESIDUAL: vetor de spoof de posição via `mecTowDone` direto (mitigação futura: revalidar `canOperate` no done).
    - **`playerDropped` limpa `_sessions`/`_rates`**: `core.lua:30-33`. Sem leak.
    - **Threads com condição de saída**: `while VHubCustom.running do` em `zones.lua:34/56`; flag `false` em `onResourceStop` (`init.lua:17`). L-06 ok. Blips 1x no boot.
    - **`vec3` pré-calculado no boot cliente**: `client/init.lua:11` — `z._vec = vec3(...)` fora de loop. L-19 ok. Coords no config são flat `{x,y,z}`.
    - **`print()` confinado ao logger**: único `print` em `shared/logger.lua:8`. L-08 ok.
    - **Câmera destruída**: `stopCam()` — `SetCamActive(false)` + `RenderScriptCams(false)` + `DestroyCam(_cam,false)` + `_cam=nil`. Chamada em `closeBennys()`. Ok.
    - **Animação com timeout**: `loadAnimDict` em `mec.lua:19-24` — guard `GetGameTimer()-t > 3000`. L-06 ok.
    - **`SetNetworkIdCanMigrate`**: `false` em TOW_REQ:152, `true` em mecTowDone:170. Ok.
    - **`vHub:vehicleCommitted` reservado em `vhub_conce/shared/events.lua`**: shape `{plate, source, changed={customization,health,fuel}}` (L-19 primitivo). Emissor fica para F2 (carskill).
    - **Ownership declarado (L-07)**: lifecycle `VHubCustom.running` + `onResourceStop` + `playerDropped`.
    - **RESIDUAIS ACEITOS**: (i) `mecTowDone` sem revalidação `canOperate` (spoof de posição); (ii) `veh_class` vem do cliente em `oficina.lua:66` — clampado `0..20` mas classe não validada server-side contra entidade real (residual de design; bounded pelo cap de stage); (iii) NUI não implementada (F5 = sprint separada); (iv) `fxmanifest.lua` não declara `dependency 'vhub_money'` (pcall silencia falha; recomendado adicionar).
    - **TESTES_FALTANTES (runtime)**: zona bennys → [E] → cor → cobra + persiste `source='cosmetic'`; reparo pneu/motor/lataria `source='repair'`; tuning stage dentro do cap por classe; reboque → `SetNetworkIdCanMigrate` off→on + posição persistida; resmon idle (2 threads, 1Hz + 0/500ms).
    - **Rollback**: `git checkout HEAD -- resources/[SCRIPTS]/vhub_custom/ resources/[SCRIPTS]/vhub_conce/server/exports.lua resources/[SCRIPTS]/vhub_conce/server/vstate.lua resources/[SCRIPTS]/vhub_conce/shared/events.lua` — sem schema novo, reversão limpa.
    - **CORE FROZEN**: não tocado. Arquivos tocados no conce são resource externo (não `[CORE]/vhub/**`).
    - **FIX PERSISTÊNCIA TUNING (2026-06-17 — APROVADO p/ runtime, gate revisão)**: turbo sumia no respawn (3 bugs). (1) **Convenção de `mods`**: garagem (dona do spawn) usa GTA-level cru (stock=-1); oficina migrou de "stage" p/ PERSISTIR GTA-level (`stage-1`) — UI/preview/snapshot client seguem em stage, conversão só na borda server (`oficina.lua:194-202`). (2) **Turbo (18)**: garagem dirige turbo pelo campo booleano `turbo` (`ToggleVehicleMod`), NÃO por `mods[18]`. Oficina extrai `clean[18]>=1 → patch_cust.turbo`, remove 18 de `mods`. **Turbo = chave EXCLUSIVA da oficina**: bennys parou de escrever `turbo` (server `buildCosmeticPatch` + client snapshot/rollback/preview). (3) **REPLACE→MERGE** em `VState:save`: era REPLACE da coluna `customization` inteira (bennys apagava tuning e vice-versa). Helper `mergeCust(base,patch)` (`vstate.lua:62-90`): TABELA NOVA, merge raso no topo, `mods` POR ÍNDICE; só dispara com `patch.customization ~= nil`; ANTES do `sanitizeCustJson` (cap 8KB/whitelist vencem). Patch completo (garage store via `updateCustomization`→`source='store'`) == replace (sem regressão). Merge em Lua, NUNCA `JSON_MERGE_PATCH`. `/tuning` admin (`vhub_admin`) é VISUAL-ONLY client (não persiste) — origem da confusão do dono.
      - **Round-trip key-safe**: `sanitizeMods` devolve chave INTEIRA → `gta_mods[idx]` inteiro → encode JSON vira string → garage aplica `SetVehicleMod(veh, tonumber(i), ...)` (tolera ambas). GTA-level `-1` sobrevive ao sanitize (`lvl>=-1`). Store-path re-popula `mods[18]` via `collectCustomization` (pré-existente, inalterado): `GetVehicleMod(veh,18)` num toggle = -1 (inofensivo); turbo real cavalga o booleano `turbo`.
      - **PENDÊNCIA LATENTE (fora deste fix, registrar)**: `VState:save` aliasa a ref VIVA do cache em `damage_log` (`vstate.lua:325` `log = cur.damage_log`) e MUTA in-place (`log[#log+1]`, `table.remove`) — MESMA classe do bug de customization recém-corrigido. Só em `source='telemetry'`(queda ≥150) ou `'repair'`, ambos com `_cache[p]=nil` ao fim (janela estreita). Aplicar o padrão "tabela nova" igual ao `mergeCust` quando tocar damage_log.
      - **Arquivos (5, todos resource externo, ZERO toque em CORE)**: `vhub_conce/server/{vstate.lua,exports.lua}`, `vhub_custom/server/{oficina.lua,bennys.lua}`, `vhub_custom/client/bennys.lua`. luac -p OK. Rollback: `git checkout HEAD --` desses 5.

27. **carskill — engine de skill do veículo (2026-06-17/18 — APROVADO)**. Tier/score/afinidade + redistribuição de pontos vivem DENTRO de `vhub_vehcontrol` (NÃO num resource `vhub_p1skill` separado — `[CAR]/carskill.md` virou referência conceitual com banner no topo; `vhub_vehcontrol/PLANO.md` = plano canônico do que foi construído). ZERO toque no CORE.
    - **Cálculo PURO** `shared/tier_rules.lua` (server+client, zero I/O): `budgetOf`/`partsBonus`/`scoreFromAlloc`/`calcTier`/`clampTier`/`defaultAlloc`/`freeRanges`/`validateAlloc`/`calcAffinity`/`buildSheet`. Identidade física vem do bloco `p1` do `catalog.lua` do conce (tier_base/tier_max/base_alloc/archetype/drive_bias/susp_raise/inertia_z). 6 carros com p1 (TOYOTASUPRA/SKYLINER34=S, NISSAN370Z/M3E46=A, F8T=S, FUSCA68=C); base_alloc soma == BUDGET[tier].
    - **Modelo de pontos híbrido**: budget = BUDGET[tier] + Σ peças; cada peça (`PART_POINTS`) dá metade FIXA no eixo natural + metade LIVRE p/ realocar. anti-P2W 8–35%/eixo (`ALLOC_RANGE`). score = âncora(budget→meio da faixa do tier) + delta de foco competitivo.
    - **Escritor ÚNICO do alloc** = `server/skill.lua` (`RECALIBRATE`): valida rate/sessão/placa/`canOperate`/budget/`validateAlloc` → cobra a PORTA → persiste via `conce:saveVehicleState(...,'handling')` → responde `RECAL_DONE(ok,msg,kind,sheet)`. DUAS PORTAS / um handler: caixa de ferramentas (consome item `caixadeferramentas`; `item_handlers.lua` abre a ficha em edição via `OPEN_EDIT`, não consome ao abrir) e oficina (cobra R$2500; `vhub_custom` CHAMA `recalibrate` com `origin='oficina'`, NÃO escreve alloc). `customization.handling` no `CUST_KEYS` + guard `source='handling'` no vstate.
    - **API read-only** (`server/exports.lua`): `getVehicleSheet/Tier/Score/Affinity/getVehicleSheetPreview` — fonte única p/ garage/racha/UI da chave (ninguém recalcula, L-04). `getVehicleSheetPreview(plate,draftAlloc)` = ficha hipotética da prévia ao vivo na oficina (`sheetOf` ganhou 3º arg `overrideAlloc`, nunca persiste).
    - **Higiene**: `vhub_custom/web/oficina.js` perdeu o score paralelo fake (consome o sheet real); deletado `vhub_vehcontrol/plan.md` (plano morto do velo); `OPEN_FROM_KEY` ligado à constante.
    - **Testes**: `tools/test_tier_rules.lua` (offline puro, dofile no engine+catálogo REAIS) + `tests.test_vehicle_sheet_export` (runtime end-to-end). Gates: arquiteto+contrato+simplicidade+revisão = APROVAR.
    - **RESIDUAL (R-3, DIFERIDO)**: `skill.lua` cobra item/dinheiro ANTES de persistir; save falho = jogador perde a porta. Fail-toward-house; pendente sessão dedicada seguranca+contrato (transação com rollback).

28. **F5 — manifestação FÍSICA do engine de skill (2026-06-18 — APROVADO; CONFIRMADO EM JOGO solo)**. Continuação da #27: o `alloc` agora vira handling REAL no carro dirigido. ZERO toque no CORE; tudo em `vhub_vehcontrol`.
    - **Derivação server-authoritative**: `tier_rules.handlingFromAlloc(alloc,budget,bands)` (PURO) → alvos físicos FLAT por LERP da fração NORMALIZADA do eixo (não valor absoluto, p/ brute-test não distorcer); `min>max` = eixo inverso (aero/drag). `buildSheet` inclui `sheet.hnd` SÓ quando `Config.skillApplyHandling`. bands = `Config.skillHandling` (eixo→{field,min,max}) — **recalibrar o "feel" = editar SÓ esse bloco em `shared/config.lua`** (sem tocar código).
    - **Aplicação (L2/HAL, `client/handling.lua` NOVO)**: `SetVehicleHandlingFloat` SÓ no carro dirigido (seat -1), RE-CLAMPADO às bands (payload do servidor tratado como hostil); `grip` ajusta `fTractionCurveMax` E `fTractionCurveMin`(=grip*`skillGripMinRatio` 0.85). Event-driven puro (L-06): eventos client-internos `BECAME_DRIVER`/`LEFT_VEHICLE` emitidos pelos pontos de transição de motorista JÁ EXISTENTES de `client/main.lua` — SEM thread/polling novo. hnd reaplica em SHEET e RECAL_DONE.
    - **Risco nº1 (model-wide)**: `SetVehicleHandlingFloat` afeta todas as instâncias do modelo no cliente local. Mitigação: `_modelBase[model]` cacheia o base do .meta no 1º toque e RESTAURA em `LEFT_VEHICLE` + `onResourceStop` (anti-vazamento; troca A→B restaura A antes de aplicar B — verificado pelo gate natives). Carro de terceiro aparece com handling base (fallback §5.2.1). **CONFIRMADO EM JOGO (solo, 2 Skylines builds opostas → diferença física sentida) pelo dono 2026-06-18; PoC MULTIPLAYER (2 players mesmo modelo) ainda PENDENTE.**
    - **hnd NUNCA persistido** (DERIVADO do alloc; escritor único do alloc segue `skill.lua`→conce). É o EXEMPLO canônico da DOUTRINA DA PLACA (abaixo).
    - **`coerceAlloc` (read-side)** + **`TR.range`** (fonte única da faixa: produção anti-P2W / brute-test 0–100%): `buildSheet` coage o alloc salvo p/ a faixa vigente na LEITURA → seguro ligar/desligar `skillBruteTest` sem travar/corromper veículo.
    - **TWEAKS pós-gate (2026-06-18, test/debug-only)**: (1) em brute-test o `freeRanges` libera o PISO (min=0 por eixo, não só o teto) — antes o piso base_alloc+fixo engolia a variação e nada era perceptível; só afeta brute-test. (2) diagnóstico `[F5]` no chat (gated `skillDebug`): BECAME_DRIVER, "hnd=SIM/NAO" e READBACK via `GetVehicleHandlingFloat` (prova que o native pegou).
    - **Testes**: `tools/test_tier_rules.lua` = 593 asserts / 0 falhas (handlingFromAlloc bounds/monotonia/nil, coerceAlloc, brute-mode floor liberado, sheet.hnd on/off). `luac -p` OK. Gates: arquiteto+natives+seguranca+performance+contrato+revisão = APROVAR.
    - **PRODUÇÃO**: garantir `Config.skillDebug=false` E `Config.skillBruteTest=false` antes do deploy.
    - **Arquivos**: NOVO `client/handling.lua`; MODIF `shared/{config,tier_rules,events}.lua`, `client/main.lua`, `fxmanifest.lua`, `tools/test_tier_rules.lua`. Rollback: `git checkout HEAD -- "resources/[SCRIPTS]/vhub_vehcontrol/"` (aditivo, sem schema, hnd não persiste → reversão limpa).

29. **vhub_nitro — nitro server-authoritative (2026-06-19 — APROVADO p/ runtime; EXEMPLO da Doutrina da Placa)**. Reescrita completa do `vhub_nitro` (era vRP puro com 2ª fonte em vRP SData) p/ o modelo vHub. ZERO toque no CORE. **O estado do nitro mora na PLACA** (`customization.nitro = {kit:bool, qty:0..100}` no prontuário `vhub_vehicle_state`) — aplicação direta da DOUTRINA DA PLACA (#28): escreve via `conce:saveVehicleState(...,'nitro')`, lê via `conce:getVehicleState`, NUNCA 2ª fonte.
    - **Escritor único** de `customization.nitro` = `vhub_nitro`, patch SEMPRE completo `{kit,qty}` (mergeCust do conce é raso no topo → nitro é chave atômica, replace do subobjeto inteiro = seguro). Conce: `CUST_KEYS += nitro`; guard `source=='nitro'` isola o patch a `customization` (bloqueia elevação de health/fuel); `TRUSTED += vhub_nitro`.
    - **4 arquivos** (cfg/config.lua, fxmanifest.lua, server.lua, client.lua). Removido o cruft vRP (cfg/functions.lua, cfg/lang.lua, nui/); fxmanifest sem @vrp/@wac (deps = `vhub`,`vhub_inventory`; conce/custom = soft-dep por pcall). `ensure vhub_nitro` adicionado em `config/resources.cfg` (sem ele o resource nunca subia — blocker pego no gate de revisão). luac -p OK.
    - **KIT = peça na OFICINA** (`vhub_custom`): cobra R$5000 (`NITRO_KIT_PRICE`) + `canOperate` → chama `exports.vhub_nitro:installKit(src,plate)` (restrito a `{vhub_custom,vhub_nitro}` + revalida `canOperate`; idempotente; preserva qty). Oficina NÃO escreve nitro. Estorno via `vhub_money:giveBank` se installKit falhar (`vhub_custom` += TRUSTED_RESOURCES do money). Botão "KIT NITRO" no NUI da oficina (reusa classe `btn-cancel`, PT-BR, zero CSS novo, sem regra de negócio no front — A-01 OK).
    - **CARGA via ITEM** `nitro` (garrafa, no catálogo do inventory): usar perto do carro → `registerItemUse` retorna `false` (não consome no dispatcher) → client resolve carro próximo → `applyCharge` server (resolveNear: netId+placa+distância FAIL-CLOSED) → `takeItem` → `writeNitro` (+carga); estorna `giveItem` se save falhar (ordem anti-perda).
    - **USO** = tecla SHIFT DIREITO (`RegisterKeyMapping '+nitro' RSHIFT`). Boost = `SetVehicleCheatPowerIncrease`+`ModifyVehicleTopSpeed`+fogo no escape (`veh_backfire`) SÓ no carro dirigido (seat -1). Drain client local, MONOTÔNICO decrescente (server aceita só qty MENOR), persiste 1x no release. Removidos efeito "maconha" (tela) e rastro de lanterna; mantido fogo no escape. Thread de boost captura `boosted`/`boostedPlate` no start e LIMPA/DRENA sempre essa entidade (fecha leak de cheat power na troca/saída de carro — correção do gate de natives). `onResourceStop` limpa boost.
    - **Gates**: arquiteto + persistência + segurança + performance APROVAR; natives + contrato REPROVAR → correções aplicadas → ambos RE-APROVARAM; revisão REPROVAR por `ensure` ausente → APROVADO após o fix.
    - **RESIDUAIS ACEITOS**: (i) 2 `applyCharge` concorrentes = auto-prejuízo (perde item, não dupe; write idempotente sobre fonte única); (ii) sair do carro segurando nitro = drain final descartado pelo resolveDriver (carga grátis ínfima, não-exploit); (iii) R-3-classe na cobrança do kit (charge→install em 2 passos), com estorno funcional.
    - **TESTES_FALTANTES (runtime)**: instalar kit na oficina (cobra+persiste `customization.nitro.kit`) → abastecer com a garrafa → usar no Shift Direito → respawn/restart (kit+qty vindos da placa); trocar de carro segurando o boost (sem leak no carro antigo); resmon. Calibração dos valores de `cfg/config.lua` = "depois" (ordem do dono).
    - **Rollback**: `git checkout HEAD -- "resources/[SCRIPTS]/vhub_conce/server/vstate.lua" "resources/[SCRIPTS]/vhub_conce/server/exports.lua" "resources/[SCRIPTS]/vhub_custom/" "resources/[SCRIPTS]/vhub_money/shared/config.lua" "resources/[SCRIPTS]/vhub_inventory/config/inventory.lua" "config/resources.cfg"` + remover `resources/[SCRIPTS]/vhub_nitro/` — sem schema novo, coluna `customization.nitro` fica órfã inofensiva no prontuário.

30. **Nitro vira EIXO da FICHA do veículo — proximidade APOSENTADA (2026-06-19 — APROVADO p/ runtime, gate revisão)**. O uso por PROXIMIDADE (usar a garrafa perto do carro, herdado do vRP) era frágil e não funcionava: REMOVIDO. O nitro agora é uma SEÇÃO da ficha do veículo (`vhub_vehcontrol`): liga/desliga + nível 1..10 + botão Abastecer. O KIT (oficina `vhub_custom`, R$5.000) continua sendo o gate. Ownership inalterado: **`vhub_nitro` segue ESCRITOR ÚNICO** de `customization.nitro` (Doutrina da Placa, #29) — vehcontrol só DELEGA. Arquiteto+segurança+contrato+designer (9/10) aprovaram com correções já aplicadas.
    - **Estado ampliado p/ 4 campos**: `customization.nitro = {kit, qty, enabled, level}` (era `{kit, qty}`). `enabled` (ligado na ficha) e `level` (1..10) são NOVOS; contrato ADITIVO — `readNitro` devolve defaults seguros p/ linha antiga (`enabled=false`, `level=1`). `writeNitro` exige os 4 args e SEMPRE escreve patch completo: a subtabela `nitro` é REPLACE atômico (o `mergeCust` do conce é raso no topo, #26 — `nitro` inteiro é substituído de uma vez, sem merge por campo).
    - **Física do nível** mora SÓ em `vhub_nitro/cfg/config.lua` (`LEVELS[1..10] = {powerMult, consumeMult}`): nível 1 = ganho pequeno/consumo pequeno (durabilidade), nível 10 = DOBRO de potência (powerMult 2.0)/consumo 3.5x (velocidade), ~10% em 10%. Boost base (`topSpeedBoost`/`torqueBoost`) × `powerMult`; drain = `(100/durationSec) × consumeMult`. `useDistance` e `debug` removidos.
    - **3 exports de escrita NOVOS no `vhub_nitro`** (TRUSTED `{vhub_custom, vhub_vehcontrol, vhub_nitro}` + `GetInvokingResource()` + `canOperate(src,plate)` re-prova o PLAYER dono/chave + rate-limit 350ms compartilhado `_opAt` + gate `kit`): `setEnabled(src,plate,on)`, `setLevel(src,plate,level)` (clamp 1..10), `chargeFromItem(src,plate)` (consome 1 'nitro'/Garrafa via `inventory:takeItem`; ordem anti-perda take→persist→estorno; recusa sem kit/cheio). `getNitro`/`installKit` ampliados (aditivo; `installKit` idempotente, preserva qty/enabled/level). Drain inalterado no formato (agora 4 campos; monotônico DECRESCENTE; FAIL-CLOSED via `resolveDriver` netId+placa+seat -1). GC `_opAt`/`_drainAt` em `playerDropped`.
    - **Ponte ficha→nitro** (`vhub_vehcontrol/server/nitro_bridge.lua`, NOVO, no fxmanifest após exports/skill): handlers `NITRO_TOGGLE/LEVEL/CHARGE` recebem a INTENÇÃO do cliente e DELEGAM aos exports do `vhub_nitro`; respondem `NITRO_DONE(ok,msg,nitro)` com `getNitro` FRESCO (a UI nunca recacheia — L-04). Toda autoridade/gate/clamp vive no escritor único; a ponte é call+reply. Eventos `NITRO_TOGGLE/LEVEL/CHARGE/DONE` em `vhub_vehcontrol/shared/events.lua` (payloads primitivos, L-19). `server/exports.lua sheetOf` injeta `sheet.nitro = getNitro(plate)` (read-only, aditivo). NUI: callbacks `nitroToggle/nitroLevel/nitroCharge` + handler `NITRO_DONE` em `client/main.lua`; seção Nitro (toggle+slider 1..10+abastecer) em `html/{index.html,app.js,style-dashboard.css}`.
    - **Caller do kit** (`vhub_custom/server/oficina.lua`): a OFICINA cobra R$5.000 + `canOperate` + checa `getNitro().kit` (não recobra) e CHAMA `installKit` (estorno via `giveBank` em falha). #29 inalterado.
    - **APOSENTADO** (par interno server/client do `vhub_nitro`, sem caller externo — grep zero): net `applyCharge`/`useItem`, busca por raio, efeitos "maconha"/rastro de lanterna. Mantido: fogo no escapamento (ptfx) + anti-leak (`boosted`/`boostedPlate` — limpa cheat-power SEMPRE na entidade boostada, não na atual). O `registerItemUse('nitro')` foi RECONVERTIDO: a garrafa usada pela mochila agora só AVISA "abasteça pela ficha" (`return false`, não consome) — sem item morto, e dá emissor real ao receptor `vhub_nitro:notify`.
    - **RESIDUAIS ACEITOS**: (i) ligar/abastecer nitro de carro PRÓPRIO à distância — a ponte confia em `canOperate` (dono/chave), não em co-presença; self-harm bounded, aprovado pela segurança; (ii) drain×charge intercalados na mesma placa: drain monotônico-decrescente + charge clampado, UPSERT per-op do conce (último a serializar vence) — sem perda material (carga = money-sink barato). [Os fantasmas `debug`/`vhub_nitro:notify`/item-sem-handler apontados no gate foram CORRIGIDOS, não aceitos: debug removido, notify ganhou emissor real, item ganhou handler de aviso.]
    - **TESTES_FALTANTES (runtime, antes do freeze)** — `resources/[CAR]/nitro_testplan.md`: instalar kit (cobra/idempotente/estorno); abastecer (consome 1 garrafa; recusa sem kit/cheio/sem garrafa); toggle+nível 1 vs 10 (trade-off potência↔consumo) + drain persistido ao soltar SHIFT/sair; restart no meio de carga parcial → `getNitro` 4 campos corretos (migração estado antigo); duplo-clique (rate 350ms, sem dupla cobrança); resmon `vhub_nitro`+`vhub_vehcontrol` (thread detecção 1Hz + thread boost só durante SHIFT, destruída ao soltar — L-18).
    - **CORE FROZEN**: não tocado. Arquivos (todos resource externo): `vhub_nitro/{cfg/config.lua, server.lua, client.lua}`; `vhub_vehcontrol/{shared/events.lua, server/exports.lua, server/nitro_bridge.lua (NOVO), fxmanifest.lua, client/main.lua, html/{index.html,app.js,style-dashboard.css}}`; `vhub_inventory/server/item_use.lua` (removido debug `[INV-USE]` de sessão anterior); `resources/[CAR]/nitro_testplan.md`. Rollback: `git checkout HEAD -- <esses paths>` + remover o arquivo novo `vhub_vehcontrol/server/nitro_bridge.lua` — sem schema novo, reversão limpa (a coluna `nitro` no prontuário já existia; campos enabled/level são aditivos no JSON).

31. **`vhub_notify` = TOAST GLOBAL PADRÃO vHub (2026-06-20 — APROVADO p/ runtime, gate revisão)**. Resource em `[CORE]` despadronizado (marca QDEV/vule; server emitia `vule:sendAlert`, client escutava `qdev_notify:client:sendAlert` → estava QUEBRADO) reescrito como toast único Mirage. **Canal canônico = evento `vHub:notify`** (NÃO confundir com `vHub.Notify` = webhook Discord server-side, módulo distinto). Consumidor real já existente: `vhub_legacyfuel/server.lua` (forma simples `(type,msg)` com `sucesso`/`negado`/`erro`) — contrato PRESERVADO. CORE FROZEN não tocado (resource é irmão em `[CORE]`, não `vhub/`). Arquiteto+contrato+segurança+designer aprovaram com correções já aplicadas.
    - **Contrato**: evento `vHub:notify` aceita `(type,msg)` OU tabela rica `{type,title|titulo,msg,duration|tempo}`. Exports `notify`+alias `sendAlert` (server `(source,data)`, client `(data)`). Map de tipo PT-BR→EN no client (`sucesso→success`,`negado/erro→error`,`aviso→warning`,`info→info`; desconhecido→`info`).
    - **Segurança**: render NUI via `textContent` (sem innerHTML — XSS fechado); whitelist de type; coerção+truncamento (title 200/msg 500); clamp `duration` 1000–10000ms (default 5000); rate-limit token-bucket local (~10/s). Server guarda `if not data` e `source==-1` (sem broadcast acidental). SEM `_invoker_allowed` — cosmético, decisão do gate de segurança.
    - **Design**: zero CDN (font-stack do sistema + glifos unicode); liquid glass `blur(14px) saturate(140%)`; paleta Areia/Dourado, aviso=âmbar; animações finitas (`vhIn`/`vhOut`/`progressDrain`, sem 60fps idle); `lang=pt-BR`.
    - **AÇÃO PENDENTE NO COMMIT**: resource UNTRACKED no git (`?? resources/[CORE]/vhub_notify/`) — exige `git add` (arquiteto ordenou COMMITAR). `src/sound.wav` (~151KB) entra junto.
    - **TESTES_FALTANTES (runtime)**: disparar `vHub:notify` nas 5 cores (forma simples + rica); abastecer no legacyfuel → toast `sucesso`/`negado` real; spam >10/s (rate-limit corta); title/msg longos (truncados, sem quebra de layout); `duration` fora de faixa (clamp); resmon NUI fechada (idle 0).
    - **Rollback**: remover `resources/[CORE]/vhub_notify/` (se não commitado, basta `rm -r`; se commitado, `git rm -r`) — nenhum consumidor depende do resource para funcionar (legacyfuel usa `pcall`, falha silenciosa).

32. **Sprint hardening de segurança (2026-06-21 — gate revisão APROVADO; arquiteto+segurança aprovaram o design).** Quatro itens, verificados no código real:
    - **N0-1 (vhub_garage, NÃO-frozen, hotfix):** `ACT_TRANSFER` ganhou `TxLock` cooperativo por placa (padrão ferinha #19, process-local) — `txAcquire` ANTES de qualquer yield de validação (anti-dupe de dois transfers concorrentes na mesma placa). Saga em `pcall` com `txRelease` garantido; ordem money→`transferOwner`→giveKey; captura o retorno de `transferOwner` (estorna money se `false`); falha de giveKey compensa TUDO na ordem inversa (devolve chave + `transferOwner(p, cid)` de volta + estorno). `playerDropped` SÓ libera lock órfão (NUNCA reverte money/key — reversão por desconexão é explorável). Compensação vive só no thread síncrono.
    - **Bônus (vhub_conce, NÃO-frozen):** `M:transferOwner` deixou de fazer 3 statements soltos. Novo `SQL:transferOwnerTx(plate,new_cid,old_cid)` = updateOwner + revokeKey + grantKey ('owner') numa transação atômica (`ptransaction`→`oxmysql:transaction`) — fecha o estado parcial (dono trocado sem chave-owner) em crash. `transferOwner` agora RETORNA o commit real (era sempre `true`); contrato `(plate,new_cid)→bool` mantido. Statements idênticos aos originais, só atômicos.
    - **N0-2 (CORE FROZEN):** `_invoker_allowed` invertido para DEFAULT-DENY — trust vazio/`nil` ⇒ `false`, `caller==nil` ⇒ `false` (era default-permissivo). Negação por trust-vazio loga `Logger:warn` one-shot; `return false` independe do Logger. `config.lua` NÃO alterado (`trusted_resources={}` correto — nenhum caller externo dos 4 exports gated, confirmado por grep).
    - **N0-3 (CORE FROZEN):** os 5 handlers veiculares dormentes desde #24 (`vSpawned/vDespawned/vEnter/vLeave/vState`) — superfície 100% hostil sem emissor legítimo (forjar vEnter com netid da vítima → `NetworkSetEntityOwner(entidade_alheia, atacante)`) — trocados por corpo no-op `_vhDisarmed`, mantidos REGISTRADOS (preserva rate-limit + contrato de evento). NUNCA reanimar a cadeia do CORE sem novo gate (regra da #24).
    - **CORE FROZEN tocado sob override** `settings.local.json` (`Write/Edit(resources/[CORE]/vhub/**)`), precedente #20/#22a → **core-frozen-v2.0** cobre N0-2+N0-3. `luac -p` OK nos 5 arquivos; encoding preservado (exports.lua CRLF; demais LF; zero U+FFFD; mojibake legado do garage CORRIGIDO).
    - **Riscos residuais registrados:** (1) `client/vehicle.lua:38` (CORE) ainda é thread `while true` emitindo `vHub:vState` ~4Hz/motorista → bate no no-op (inofensivo, tráfego/rate-limit desperdiçados; retirar em bump futuro do CORE). (2) `vhub_ferinha/server/auction.lua:71` `Core.transferOwner` não checa o agora-possível `false` (sem regressão; follow-up). (3) compensação giveKey-fail do garage não checa o retorno do `transferOwner` de reversão (split raro aceito). (4) `getVehicle` do CORE/conce devolve VD vivo por referência SEM `_invoker_allowed` — achado SEPARADO, não endereçado. **GATILHO (revisão autônoma 2026-06-22, gate segurança):** corrigir `getVehicle`/`getVehicleByKey` (cópia segura OU `_invoker_allowed`) é PRÉ-REQUISITO obrigatório ANTES de re-armar a cadeia física do CORE (#24) — hoje `_veh`/`_byNet` dormentes ⇒ vetor inerte (risco real ≈0); os 2 consumidores (`vehcontrol`/`lspdtool`) usam como check booleano sob pcall, nunca mutam o VD. (5) `TxLock` process-local (não cross-shard, igual #19).
    - **Revisão autônoma (2026-06-22) — relatório externo reconciliado contra o código atual; NENHUMA mudança nova de código justificada:** N0-4 (flush OCC) REJEITADO (raciocínio falso — `flush_all` sem yield entre snapshot e `dirty=false`; corrotina cooperativa não interleava); N0-5 (clone/lend leak) REJEITADO (clone JÁ estorna em `giveKeyItem` fail; lend não move dinheiro); P-1 (kernel estimativa de payload) REJEITADO pelo gate de performance (estimativa pode SUBESTIMAR → furo do cap anti-abuso `max_payload`; sem orçamento estourado, é inbound não-tick); P-2 (índice plate→entity) REJEITADO (`Veh._byNet` do CORE está DORMENTE pós-#24 → reuso não resolve; handler `entityCreated` global novo = over-engineering/ownership errado L-07; `GetAllVehicles` roda só em spawn/store, não por-tick); P-3/P-4/P-6/P-7/P-8 REJEITADOS (P-4 falso — `Wait` no topo do loop; resto over-engineering p/ a carga real). Gates: performance NÃO-VALE em P-1/P-2; segurança NÃO-CORRIGIR-DÍVIDA em getVehicle. Princípio: não tocar FROZEN sem ganho concreto presente (L-09/L-15).
    - **Validação RUNTIME PENDENTE:** transfer feliz; 2 transfers concorrentes na mesma placa; giveKey-fail→estorno completo; commit-fail do `transferOwnerTx`→abort; vEnter forjado com netid alheio→no-op; negação dos 4 exports com trust vazio + warn one-shot.

33. **CONSULTIVA / REJEITADA — proposta `vhvehicle` centralizador (2026-06-22, gate revisão).** Documento `vh.md` (IA externa, sem contexto do projeto) propunha novo módulo `resources/[CORE]/vhub/vhvehicle/` como escritor único de identidade+física veicular, substituindo `vhub_conce`. `vhub_arquiteto` REPROVOU; dono aceitou o veredito. **Achados:** (1) bugs citados (N0-1 race de transfer, N0-3 vandalismo via vEnter) já fechados nas #21/#24/#32 — premissa falsa; (2) plano usava `exports.vhub:getVHub().State:_queue(...)` — violação de L-14 (acesso a internals do CORE por terceiro) e da decisão #8 (exports cross-resource devolvem cópia); (3) reativaria a cadeia física do CORE (`entityCreated`/`NetworkSetEntityOwner`/vEnter-like) descontinuada deliberadamente na #24 a favor do prontuário — a frase "NUNCA reanimar a cadeia do CORE sem gate do arquiteto" (#24) já previa exatamente este gate, e ele NEGOU; (4) ignorava a DOUTRINA DA PLACA (#28/#29/#30) — migrar quebraria nitro/custom/vehcontrol/carskill, todos escritores via `conce:saveVehicleState`; (5) "shadow mode" proposto = 2ª fonte de verdade temporária, violação L-04. **Veredito:** arquitetura mantida — `vhub_conce` permanece escritor único de identidade (`vhub_vehicles`/`_keys`/`char_id`) e física (`vhub_vehicle_state`). **Ação executada (fora deste gate):** `resources/[CORE]/vhub/vhvehicle/vh.md` e diretório vazio DELETADOS. Zero código escrito, zero ownership alterado. **Nota do arquiteto p/ o futuro (não-decisão):** se surgir motivo concreto p/ "nome de API único" de veículos, única forma aceitável é fachada fina FORA do freeze (resource irmão, zero SQL/VRAM própria, repasse direto a `vhub_conce`) e só com consumidor real identificado — senão é módulo-fantasma (L-15).

34. **`vhub_wow` — motor de áudio 3D standalone (2026-06-22 — APROVADO, re-revisão; gate textual anterior fora desta invocação).** Resource NOVO em `[SCRIPTS]/vhub_wow/`: porta mínima de xsound, dono exclusivo da execução de áudio 3D. Consumidor inicial: `vhub_vehcontrol` (aba Som da ficha, fonte "URL" play/stop/volume).
    - **Ownership**: `vhub_wow` é escritor/dono único da execução de áudio 3D — exports `PlayAtEntity(targets, soundName, url, volume, netId, distance, loop)`, `Destroy(targets, soundName)`, `SetVolume(targets, soundName, volume)`. `vhub_vehcontrol` consome via soft-dep (`GetResourceState('vhub_wow')=='started'` + `pcall` em toda chamada) — sem `vhub_wow` rodando, o resto do vehcontrol funciona intacto, só o rádio não funciona.
    - **2 bloqueios da revisão anterior, AMBOS fechados nesta volta:**
      - (i) **SEGURANÇA** (antes REPROVADO): `soundName`/`netId` eram aceitos crus do payload do client em `server/sound.lua` — um player podia forjar nome de outro (parar/alterar som de terceiro) ou ancorar áudio em netId arbitrário. FIX: `soundName` agora é SEMPRE derivado server-side via `soundNameOf(src) = 'vc_radio_%d':format(src)` — nunca aceito do payload (client não envia mais `soundName` em nenhum evento). `netId` só é aceito após `VHubVeh.hasVehicleAccess(src, plate)` retornar true — reaproveita a MESMA função `hasAccess` já usada em `requestLock`/`requestEngine`, exposta via `VHubVeh.hasVehicleAccess = hasAccess` em `vhub_vehcontrol/server/main.lua:46-48` (fonte única, L-04/L-09, sem duplicação). Client (`client/sound.lua`) envia `(netId, plate, url, volume)` em vez de `(netId, soundName, url, volume)`; `plate` vem de `plateOf(v)` local espelhando o helper de `main.lua`. `url` validado com `type(url) ~= 'string'`. Confirmado por leitura: `server/sound.lua:1-48`, `client/sound.lua:1-67`, `server/main.lua:1-192` (ordem de `server_scripts{}`: `main.lua` carrega ANTES de `sound.lua` — `VHubVeh.hasVehicleAccess` já existe quando `sound.lua` executa). Grep confirmou zero ocorrência de `soundName` vindo de payload de client em todo o resource.
      - (ii) **HIGIENE** (antes REPROVADO): pasta `vhub_wow/referencia/` (~1.9MB de código de terceiros) dentro da árvore do resource final. FIX: removida — confirmado por listagem (`[SCRIPTS]/vhub_wow/` contém só `client/`, `fxmanifest.lua`, `html/`, `server/`, `shared/`) e busca recursiva por `*referencia*` sem resultado.
    - **Decisão do arquiteto nesta sprint**: expansão de `vhub_wow` para voice-chat foi AVALIADA e NEGADA — nasce como projeto SEPARADO `vhub_voicePMA` (ainda em design, diretório próprio em `[SCRIPTS]/vhub_voicePMA/`, NÃO confundir com #34, fora de escopo desta decisão).
    - **RESIDUAL ACEITO** (não é falha, é design correto): `soundStop`/`soundVolume` em `server/sound.lua` não fazem checagem de posse adicional — seguro por construção, pois o nome do som é sempre `soundNameOf(source)` do PRÓPRIO emissor do evento, nunca de terceiro, sem vetor de spoof.
    - **TESTES_FALTANTES (runtime, antes do freeze)**: play/stop/volume via aba Som com `vhub_wow` ativo; comportamento com `vhub_wow` parado (resto do vehcontrol intacto, pcall engole erro); tentativa de forjar `netId` de veículo sem acesso (deve recusar); resmon do motor de áudio.
    - **CORE FROZEN**: não tocado. Rollback: remover `resources/[SCRIPTS]/vhub_wow/` + `git checkout HEAD -- "resources/[SCRIPTS]/vhub_vehcontrol/"` (aditivo, sem schema, soft-dep — reversão limpa).

35. **Isolamento por Routing Bucket no spawn owner (2026-06-27 — gate revisão APROVADO; arquiteto+segurança+natives aprovaram).** `vhub_player_state` (já dono único do fluxo de spawn, decisão #7) ganha isolamento de sessão por routing bucket. **ZERO toque no CORE FROZEN; ZERO cascata.** Origem: pedido do dono mandava reescrever o core + todos os resources — REPROVADO pelo arquiteto (L-11/L-07/L-15) e entregue a versão mínima e correta (só `vhub_player_state/server.lua`, `luac -p` OK).
    - **Ownership novo**: `vhub_player_state` é **ESCRITOR ÚNICO de Routing Bucket** (grep confirmou: nenhum outro resource em `resources/` toca `SetPlayerRoutingBucket`/`SetEntityRoutingBucket`/`SetRoutingBucketPopulationEnabled`/`SetRoutingBucketEntityLockdownMode`). Buckets: **999** = entrada isolada (seleção de spawn, população OFF + lockdown `strict`, setado 1× no `onResourceStart`); **1** = mundo; **2** = atividade isolada (test-drive/arena/replay) via export. Bucket isola ENTIDADES DE REDE, NÃO a geometria do mapa.
    - **Helper `setBucket(src,b)`**: só troca quando difere (`GetPlayerRoutingBucket(src) ~= b`) — evita re-stream. Entrada no 999 SÓ no 1º spawn REAL com seleção (`isolar = selecionar and first_spawn==true`); o replay-guard (`_spawn_seen[src]==spawns`) barra ANTES de qualquer setBucket, então player já no mundo NUNCA volta ao 999 (bug pego pelo guardião de natives). Release (`liberar`) faz `setBucket(1)` ANTES do `TriggerClientEvent(:release)` (exigência da segurança) — todo caminho de saída (spawnAt, timeout AFK) passa por `liberar`, nenhum fica preso no 999. Caminho sem selector: `setBucket(1)` antes do apply (fecha janela em 999).
    - **Export novo `setActivityBucket(src, n)`**: `invokerOK()` default-deny (`BUCKET_TRUSTED={}` VAZIO até o arquiteto registrar ownership de cada consumidor, L-07) + `tonumber` + `n ∈ {1,2}` (NUNCA 999, evita isolar player num bucket de entrada vazio) + online-guard (`_pronto and Auth:getUser(src)`). Contratos `spawnAt`/`isPendingSpawn`/`give*`/`set*`/`teleport`/`getPosition` INALTERADOS.
    - **Sem 2ª fonte (L-04)**: bucket é dimensão de visibilidade de rede, não verdade persistida; a posição/estado segue persistindo via `user.data.state` (TX do CORE). Sem dupe.
    - **CORE FROZEN**: não tocado. Rejeitada a cascata (inflação L-07/L-15) e a reescrita do core (L-11). Rollback: `git checkout HEAD -- "resources/[SCRIPTS]/vhub_player_state/server.lua"` (1 comando, sem schema).
    - **TESTES_FALTANTES (runtime, antes do freeze)**: 1º login → entra no 999 (tela de seleção sem população) → escolhe spawn → cai no mundo (bucket 1, população visível); AFK na seleção → timeout libera no mundo; `usar_selector=false` → spawna direto no mundo sem passar pelo 999; restart de outro resource (replay) → player no mundo NÃO é jogado de volta ao 999; morte → respawn normal; resmon do player_state. Smoke do export `setActivityBucket` fica pendente até existir consumidor real registrado em `BUCKET_TRUSTED`.
    - **BACKLOG (separado, NÃO neste sprint)**: char-select interativo via o evento `vHub:selectChar` já existente (multichar já vive no CORE — L-04; não recriar). O 999 com população OFF é a fundação visual ("tela limpa") sobre a qual esse char-select pode montar depois.

> **🔑 DOUTRINA DA PLACA — governança veicular (ORDEM DO DONO, 2026-06-18; consolida L-04 + decisão #24).** Regra inegociável daqui pra frente: **TODA verdade veicular PERSISTIDA mora na PLACA**, no prontuário `vhub_vehicle_state` (keyed-by-plate), cujo escritor/dono ÚNICO é `vhub_conce` (`saveVehicleState`). Qualquer resource que "encoste no veículo" (oficina, bennys, mec, garagem, skill, nitro, telemetria, …) **ESCREVE por esse caminho** (com seu `source`) e **LÊ pelo mesmo lugar** (`getVehicleState`/exports do conce) — NUNCA tabela paralela, NUNCA 2ª fonte, NUNCA cópia divergente. Dados DERIVADOS (tier/score/afinidade/`hnd`) são computados ON-READ a partir do que está na placa e **JAMAIS persistidos/duplicados** (a #28 é o exemplo). Tudo que toca a placa funciona da MESMA forma → zero margem de erro, zero bug de duplicação. Antes de criar QUALQUER dado novo de veículo, pergunte: *"isso vai pra placa via conce, ou é derivável do que já está lá?"* — se não for nenhum dos dois, PARE (condição de parada, L-04).

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

### vhub_inventory (resource externo — `resources/[SCRIPTS]/vhub_inventory`)

| Módulo | Arquivo | Responsabilidade canônica |
|--------|---------|--------------------------|
| SQL | `server/sql.lua` | queries via `exports.oxmysql` direto (decisão #8); schema idempotente em `sql/schema.sql` |
| Mochila | `server/backpack.lua` | cache VRAM `_sess[src]` por `char_id`; flush triplo; isolamento por personagem (troca de char faz flush do anterior) |
| Baús | `server/containers.lua` | cache VRAM `_cache[cid]` por baú ABERTO; liberado quando sem viewers; mutex `_locks[cid]` 300ms; open-guard `_open[src]` (só muta o baú que o servidor autorizou); flush triplo (debounce 3s + último-viewer + onResourceStop) |
| Transfer | `server/transfer.lua` | mochila↔baú atômico sob mutex+open-guard; otimista só na origem; falha → revert autoritativo + notify |
| HAL Client | `client/containers.lua` | markers proximity-gated (thread única, Wait 0/1000); porta-malas via tecla K; tampa cosmética SetVehicleDoorOpen/Shut |
| Exports | `server/exports.lua` | `_invoker_allowed()` em todos os mutadores; `openContainer` novo (INV-2) |

**Regras de negócio congeladas (INV-2):**
- Capacidade do porta-malas vem do registro `vhub_garage` (`vtype_mult`) — **`GetVehicleClass` server-side proibido** (ambíguo, viola L-04).
- Acesso ao porta-malas: chave física (`veh_key` na mochila) OU ser dono no `vhub_garage`.
- Permissão de baú de facção via `exports.vhub_groups:hasPermission` (soft pcall).
- Isolamento por `char_id` — **nunca cruzar personagens** (L-04).
- Anti-spoof de entidade: `NetworkDoesEntityExistWithNetworkId` + `ent~=0` + `GetEntityType(ent)==2` + distância server-side + placa server-side.
- `vhub_inv_containers`: `container_id` composto (`static:<nome>`, `faction:<grupo>`, `trunk:<placa>`).

**Riscos residuais documentados (INV-2):**
- `while true` sem condição de saída em `client/containers.lua` (L-06 — risco baixo, FiveM limpa threads; a corrigir em INV-3 ou SPRINT-INV-4).
- `assertThread()` ausente nas funções públicas `M.load()` e `M.flush()` de `containers.lua` (chamam `Citizen.Await`/`CreateThread` internamente; não crasham pois são sempre invocadas de thread, mas violam o padrão declarativo).
- `onDestroy` do `container.js` não remove explicitamente o listener `.ct-close` (elemento destruído pelo `innerHTML=''`; sem leak real, mas inconsistente com A-07).

| Sprint | Foco | Status |
|--------|------|--------|
| SPRINT-INV-1 | Mochila server-authoritative (open/move/use/HUD/char_id) | ✅ Aprovado |
| SPRINT-INV-2 | Baús (static/faction/trunk), transfer atômico, UI otimista + revert | ✅ Aprovado (gate revisao 2026-05-29) — pendente validação runtime |
| SPRINT-INV-3 | Drops no chão (módulo de drops, perdivel, death) | ⏳ Pendente |

### vhub_lspdtool (resource externo — `resources/[SCRIPTS]/vhub_lspdtool`)

> Ownership canônico atual = tabela **"Ownership por módulo (atualizado LSPD-5)"** mais abaixo. O snapshot LSPD-1 histórico (bridge como adapter de `sd-policeradar`/`l2s-dispatch`, `client/hooks.lua`, eventos `RADAR_SCANNED`/`ON_PLATE_SCANNED`) foi SUPERADO: dispatch/BOLO nativizados em LSPD-3, radar nativizado em LSPD-5 (`client/hooks.lua` deletado).

**Decisão de arquitetura (2026-05-31 — LSPD-1):** bridge NÃO funde `l2s-dispatch`/`sd-policeradar` (escrow). Atua como adapter configurável: consome eventos/exports de terceiros via `pcall` + `GetResourceState`; UIs dos recursos escrow permanecem intactas. Pipeline é 100% server-authoritative.

**Decisão de arquitetura (2026-05-31 — LSPD-3):** dependência `l2s-dispatch` (escrow) eliminada completamente. BOLO + dispatch são agora 100% nativos vHub. `server/bolo.lua` é o módulo de domínio BOLO. Alerta com blip temporário (cap 8) + som nativo + thefeed. `ensure vhub_lspdtool` confirmado em `config/resources.cfg`. (LSPD-3 mantém-se intacto; ver LSPD-5 para a evolução do radar.)

**Decisão de arquitetura (2026-06-04 — LSPD-5 — RADAR NATIVO):** reverte PARCIALMENTE a LSPD-1 (apenas o RADAR volta a ser nativo; remove a dependência do escrow `sd-policeradar`). LSPD-3 (BOLO/dispatch nativo) INTACTO. Gate `vhub_arquiteto` = REDUZIR_ESCOPO com pré-condição cumprida: **deletado o spike ROGUE `web/`** (não carregado pelo manifest, mas violava L-04 — `web/config.lua` com `Config.BoloPlates` hardcoded = 2ª fonte de BOLO; `web/plate_handler.lua` = pipeline `processScan` PARALELO sem auth/rate/dedup/coords + `print()` + broadcast -1; `web/hooks.lua` = 3º listener). **`client/hooks.lua` (escrow listener) DELETADO.** Radar agora em **`client/radar.lua`** (HAL): loop adaptativo único (idle 700ms / update 200ms, gated driving+enabled, `running` guard L-06), raycast LOS SÍNCRONO frente/trás (`StartExpensiveSynchronousShapeTestLosProbe`, flags=2 = só veículos, `GetOffsetFromEntityInWorldCoords` z-aware — prescrição do gate de natives após REPROVAR→CORRIGIDO de capsule assíncrono), lê speed+placa LOCALMENTE (só UI, L-02), lock 'K', toggle 'X', auto-open pede `REQ_RADAR`. Placa NOVA → `TriggerServerEvent(PLATE_SCANNED)` REUSA o pipeline seguro (`processScan` NÃO tocado). NUI overlay PASSIVO em `web/{index.html,style.css,app.js}` (`pointer-events:none`, sem NuiFocus, escopo `.mod-radar`, fontes de sistema sem CDN, 1 listener + cleanup unload A-07, delta A-08). `fxmanifest`: +`client/radar.lua` +`ui_page` +3 files web; -`client/hooks.lua`. `RADAR_SCANNED`/`ON_PLATE_SCANNED` (escrow) REMOVIDOS de `events.lua`; `PLATE_SCANNED` (canônico seguro) mantido; +`VHubLspd.UI` (message types do overlay). `server/main.lua`: removido só o check de presença do escrow no `onResourceStart` (pipeline intacto). Gates: natives APROVAR (pós-correção), performance APROVAR, seguranca APROVAR (placa client = só UI; `processScan` deriva coords server-side e valida `canScan`), runtime APROVAR, designer APROVADO. Helicam = LSPD-6 (faseado); dispatch/MDT UI = LSPD-7 (faseado).

**Decisão de arquitetura (2026-06-04 — LSPD-6 — HELICAM NATIVO + REORG MODULAR DA NUI):** segundo dos 3 escrows nativizados (helicam; radar=LSPD-5 feito; dispatch/MDT=LSPD-7 próximo). **`server/main.lua` + `server/bolo.lua` INTOCADOS** (air-scan reusa o pipeline canônico `processScan`, que normaliza `kind` e deriva coords server-side). **Reorg modular da `web/` — 1 `ui_page`, DISPATCHER MÍNIMO SEM ENGINE (decisão do arquiteto: modular, mas sem store/bus/router/native-bridge):** `web/app.js` = dispatcher que expõe `LSPD.register(name,{onMessage,onDestroy})` + roteia pelo PREFIXO de `m.type` (`'radar:'`|`'helicam:'`|`'mdt:'` → módulo dono) com 1 listener `message` central + `unload` removendo o listener e chamando `_destroyAll`. `web/core.css` = tokens `:root` + reset compartilhados (CEF transparente). **Radar MIGRADO** de `web/style.css` (flat, DELETADO) p/ `web/modules/radar/{radar.css,radar.js}` — **comportamento IDÊNTICO** (mesmos `m.type` `radar:open/close/update`, mesmos seletores `.mod-radar*`/`is-open`/`is-locked`; único campo aditivo `m.unit` opcional). NOVO `web/modules/helicam/{helicam.css,helicam.js}` (overlay HUD passivo, `pointer-events:none`). `index.html` hospeda os 2 overlays + carrega `app.js` ANTES dos módulos. **Helicam nativo `client/helicam.lua` (L2/HAL):** câmera scriptada presa ao heli (`CreateCam`/`AttachCamToEntity`/`RenderScriptCams`/`SetCamFov`/`SetCamRot`/`PointCamAtEntity`); cleanup completo (`RenderScriptCams(false)`+`DestroyCam(cam,true)`+`SetNightvision(false)`+`SetSeethrough(false)`); zoom via scroll weapon-wheel 14/15 (NÃO 241/242 cursor-scroll, que exige NuiFocus — correção do gate de natives); look 1/2; visão normal/NV/thermal; holofote `DrawSpotLightWithShadow` (local, sem sync); lock por raycast SÍNCRONO próprio z-aware → lê placa → `PLATE_SCANNED kind='air'` (REUSA pipeline). HUD = overlay passivo (sem NuiFocus), delta+throttle (`updateHudMs`). Loop único adaptativo (`while running`, idle `Wait(250)` / ativo `Wait(0)`, guard L-06; idle-zero gated em `active`). **Coexistência tecla X (ambos bindam X, FiveM dispara os 2 keymaps):** `radar.lua` ganhou `isAircraft()` e EXCLUI heli/avião do `driving`-gate, do auto-open e do comando X (early-return em aeronave); `helicam.lua` early-return quando `not canOperate` (não-heli). Mutuamente exclusivos por contexto — **o auto-open terrestre NÃO regride** (só ganhou `and not isAircraft(veh)`). **Contrato aditivo:** `shared/events.lua` +`VHubLspd.UI.HELI_OPEN/CLOSE/UPDATE` (chaves `OPEN/CLOSE/UPDATE` do radar inalteradas, mesmos valores-string; `return VHubLspd.E` mantido). `shared/config.lua` +bloco `helicam`. `fxmanifest` +`client/helicam.lua` +files modulares; `web/style.css` removido dos files. **Exports públicos (reportPlate/getRecentScans/addBolo/removeBolo/checkBolo/listBolos) INALTERADOS.** Nenhum consumidor externo referenciava `web/style.css` nem a estrutura flat (verificado, zero matches). Gates: natives REPROVAR→CORRIGIDO (scroll 241/242→14/15; +`DestroyCam(cam,true)`) então APROVAR; performance APROVAR (idle-zero gated, HUD delta+throttle); runtime APROVAR (dispatcher A-01..A-08, isolamento, cleanup central); designer APROVADO (contorno do reticle p/ legibilidade sobre nightvision); seguranca NÃO acionado (server intocado; placa client = só UI, autoridade em `canScan`). **Residual cosmético:** `cfg.client.forwardAirScans=false` é flag MORTA (nada lê; helicam decide via `cfg.autoAirScan` próprio; único emissor de `kind='air'` é `attemptLock`) — limpeza futura, sem impacto funcional (sem duplicata de scan aéreo).

**Decisão de arquitetura (2026-06-04 — LSPD-7 — MDT / CENTRAL DE DESPACHO NATIVO — ÉPICO COMPLETO):** terceiro e último dos 3 escrow nativizados. **Suíte lspdtool agora 100% nativa vHub: radar (LSPD-5) + helicam (LSPD-6) + dispatch/MDT (LSPD-7) — fim do épico "versão vHub dos 3 escrow".** MDT é o **1º módulo NUI INTERATIVO** do resource (radar/helicam são overlays passivos); lista BOLOs ativos + scans recentes e cria/remove BOLO pela UI. **`server/main.lua` (pipeline `processScan`) e `server/bolo.lua` INTOCADOS** — o MDT REUSA o domínio BOLO (`VHubLspd.Bolo.create/remove/list`), sem 2ª fonte de verdade (cache VRAM `_cache`+`maxActive`+SQL preservados; create mantém cache otimista+rollback). **NOVO `server/mdt.lua` (L1):** net events `REQ_MDT` (gated `permScan` + throttle 1s/src `_req` + cleanup em `playerDropped`), `MDT_ADD`/`MDT_DEL` (gated `permManageBolo`). Snapshot lê scans via `exports.oxmysql:query` parametrizado (`SELECT plate, flagged, src_kind, created_at ... LIMIT ?`, limit = `cfg.mdt.scanLimit`). Sanitização da entrada hostil: `normalizePlate` + `reason:gsub('[%c]','')`+`sub(1,reasonMaxLen)` + clamp de `level` a `1..#cfg.bolo.levels` (aplicado no gate de segurança). **NOVO `client/mdt.lua` (L2):** abre SÓ após o servidor responder (`REQ_MDT`→`MDT_DATA`); `SetNuiFocus(true,true)` existe APENAS aqui (foco 100% Lua); fecha por botão/Esc/F7/`onResourceStop` devolvendo o foco. NUI callbacks `mdtClose`/`mdtAddBolo`/`mdtDelBolo`. **NOVO `web/modules/mdt/{mdt.css,mdt.js}` (L4)** registrado no dispatcher pelo prefixo `mdt:`: painel modal glass (único overlay com `pointer-events:auto`+dim de fundo); **render DOM SEGURO** (`textContent`/`createElement`, sem `innerHTML` de dado do servidor → sem XSS); delegação de clique (`data-act`/`.mdt-row__del` + `dataset.plate`); `fetch` SÓ em ação do usuário (A-06); `onDestroy` remove os 3 listeners (`click`/`submit`/`keydown` do document) — A-07. **Contrato ADITIVO:** `shared/events.lua` +`REQ_MDT`/`MDT_DATA`/`MDT_ADD`/`MDT_DEL` (valores-string distintos de `PLATE_SCANNED`/`REQ_RADAR`/`ENABLE_RADAR`) + `VHubLspd.UI.MDT_OPEN/CLOSE/DATA` (chaves radar/helicam inalteradas, `return VHubLspd.E` mantido). `shared/config.lua` +bloco `mdt` (`toggleKey='F7'`, `scanLimit=25`). `fxmanifest` +`server/mdt.lua` +`client/mdt.lua` +`web/modules/mdt/*` + `index.html` painel `#mdt`. **Exports públicos (reportPlate/getRecentScans/addBolo/removeBolo/checkBolo/listBolos) INALTERADOS.** Limpeza junto: removido o bloco MORTO `cfg.client.forwardAirScans` de `config.lua` (flagado no gate LSPD-6). Gates: seguranca APROVAR 6/6 (autoridade server-side, sanitização, sem SQL-injection via `?`, anti-flood, sem XSS via `textContent`, sem foco preso; clamp de level aplicado); runtime APROVAR 10/10 (A-01..A-08; render seguro, delegação, `onDestroy` remove `keydown` do document, foco 100% Lua); designer APROVADO 9/10 (identidade glass/areia/dourado; nota não-bloqueante: `.mdt-row`/`.mdt-empty` sem prefixo `.mod-` mas só vivem dentro de `#mdt`); natives/performance NÃO acionados (event-driven, sem loop/native). **Padrão do 1º módulo INTERATIVO (reuso futuro):** modal com FOCO concedido só pela camada Lua (`SetNuiFocus`) após autorização server-side, NUNCA pelo JS; render por `textContent`/`createElement`; delegação de evento via atributos `data-*`; `fetch` (callback NUI) só em ação explícita do usuário; `onDestroy` remove TODOS os listeners (inclusive os ligados ao `document`). **SEM schema novo** (reusa `vhub_lspd_scans`/`vhub_lspd_bolos`). **Residual:** F7 é default de 3 resources via `RegisterKeyMapping` (`vhub_groups` painel, `vhub_racha` painel, `vhub_lspdtool` MDT) — coexistem (cada keymapping é independente e rebindável em Settings), mas o default de fábrica dispara os 3 juntos = colisão de UX no default (não-bloqueante; rebind resolve). Corrida benigna: se o usuário fecha o MDT entre clicar "+BOLO" e a resposta `MDT_DATA` chegar, o painel reabre (mesmo painel do próprio policial autorizado; sem vazamento).

**Ownership por módulo (atualizado LSPD-7):**

| Módulo | Arquivo | Responsabilidade canônica |
|--------|---------|--------------------------|
| Config | `shared/config.lua` | cfg única: police perm+ACE+owner+dutyExport+cacheTtl; plate; rate; dedupTtl; radar (idle/update/range/skipAhead/keys/policeClass/`anyVehicle`); helicam (fov/look/pitch/vision/spot/lock/autoAirScan); **mdt (toggleKey F7/scanLimit)**; bolo; alert; log; trusted. (`client.forwardAirScans` MORTO removido em LSPD-7) |
| Events | `shared/events.lua` | `VHubLspd.E.*` — PLATE_SCANNED, BOLO_ALERT, NOTIFY, REQ_RADAR, ENABLE_RADAR **+ REQ_MDT, MDT_DATA, MDT_ADD, MDT_DEL** + `VHubLspd.UI` (radar:open/close/update + helicam:open/close/update **+ mdt:open/close/data** — tudo aditivo) |
| Bridge server | `server/main.lua` | **INTOCADO em LSPD-6/7.** pipeline L1: helpers (perm/plate/uid/notify/invokerAllowed); canScan (cache TTL); rateOk; dedupOk lazy-GC; broadcastAlert (direcionado); processScan (normaliza `kind` air/ground; deriva coords server-side); PLATE_SCANNED handler; REQ_RADAR→ENABLE_RADAR; lifecycle |
| BOLO | `server/bolo.lua` | **INTOCADO em LSPD-6/7.** cache VRAM `_cache[plate]`; loadAll; check O(1); list; create (otimista+rollback); remove; comandos /bolo /delbolo /bolos; exports addBolo/removeBolo/checkBolo/listBolos. **MDT reusa `Bolo.create/remove/list` (sem 2ª fonte)** |
| MDT server (L1) | `server/mdt.lua` | despacho server-authoritative: `REQ_MDT` (gated permScan + throttle 1s `_req` + cleanup playerDropped) → snapshot (bolos via `Bolo.list` + scans via oxmysql `LIMIT ?` + canManage + levels); `MDT_ADD`/`MDT_DEL` (gated permManageBolo) → sanitiza (normalizePlate + reason gsub/sub + clamp level 1..#levels) → `Bolo.create/remove` → refresca solicitante |
| MDT client (L2) | `client/mdt.lua` | NUI INTERATIVA: abre SÓ após `MDT_DATA` do servidor; `SetNuiFocus` existe APENAS aqui (foco 100% Lua); fecha por botão/Esc/F7/onResourceStop devolvendo foco; callbacks mdtClose/mdtAddBolo/mdtDelBolo (servidor revalida permissão) |
| NUI módulo MDT (L4) | `web/modules/mdt/{mdt.css,mdt.js}` | painel modal glass INTERATIVO (`pointer-events:auto`+dim); `onMessage(mdt:*)`; render DOM SEGURO (textContent/createElement, sem innerHTML → sem XSS); delegação data-act/data-plate; fetch só em ação do usuário (A-06); onDestroy remove 3 listeners click/submit/keydown (A-07) |
| HAL client RADAR | `client/radar.lua` | radar NATIVO solo: loop adaptativo único (idle/update gated, `running` guard L-06); raycast LOS síncrono frente/trás (flags=2, z-aware); leitura speed+placa (só UI); toggle X (**early-return em aeronave**) / lock K; auto-open→REQ_RADAR (excl. aeronave via `isAircraft`); encaminha placa nova→PLATE_SCANNED `kind='ground'`; overlay passivo via SendNUIMessage; cleanup onResourceStop (A-07) |
| HAL client HELICAM | `client/helicam.lua` | heli-câmera NATIVA (FLIR): cam scriptada presa ao heli; zoom (scroll 14/15) / look (1/2) / visão normal-NV-thermal / holofote (local) / lock raycast síncrono z-aware → placa → PLATE_SCANNED `kind='air'`; HUD passivo delta+throttle; loop único idle-zero gated em `active` (L-06); toggle X (só em heli via `canOperate`); cleanup completo (RenderScriptCams off + DestroyCam + NV/thermal off) em closeCam + onResourceStop (A-07) |
| HAL client policial | `client/police.lua` | thefeed NOTIFY; BOLO_ALERT → thefeed+som+blip temporário cap8+cleanup onResourceStop. (radar e helicam têm threads próprias; sem radar/keybind aqui) |
| NUI dispatcher (L3) | `web/app.js` | DISPATCHER mínimo SEM engine: `LSPD.register(name,spec)` + `_route` por prefixo de `m.type`; 1 listener central + `unload`→remove listener + `_destroyAll` (A-07) |
| NUI shared (L3) | `web/core.css` | tokens `:root` (sand/gold/glass) + reset; `background:transparent` (CEF) |
| NUI módulo RADAR (L4) | `web/modules/radar/{radar.css,radar.js}` | overlay PASSIVO do radar (migrado de `web/style.css`); `pointer-events:none`; `onMessage(radar:*)`; comportamento idêntico ao LSPD-5 |
| NUI módulo HELICAM (L4) | `web/modules/helicam/{helicam.css,helicam.js}` | HUD passivo da câmera; `pointer-events:none`; `onMessage(helicam:*)` (zoom/alt/hdg/vision/spot/lock/target) |
| Schema | `sql/schema.sql` | `vhub_lspd_scans` + `vhub_lspd_bolos`; FK INT UNSIGNED → vh_users.id ON DELETE SET NULL; idx_active_plate |

**Exports públicos:**

| Export | Proteção | Assinatura |
|--------|----------|------------|
| `reportPlate` | `invokerAllowed()` (trusted whitelist) | `(src, plate, opts) → bool` |
| `getRecentScans` | `invokerAllowed()` (trusted whitelist) | `(limit) → []scan` — DEVE ser chamado dentro de `Citizen.CreateThread` |
| `addBolo` | `invokerAllowed()` (trusted whitelist) | `(plate, reason, opts) → bool` |
| `removeBolo` | `invokerAllowed()` (trusted whitelist) | `(plate) → bool` |
| `checkBolo` | `invokerAllowed()` (trusted whitelist) | `(plate) → bolo\|nil` |
| `listBolos` | `invokerAllowed()` (trusted whitelist) | `() → []bolo` |

**Riscos residuais documentados (pós LSPD-3):**
- `getRecentScans` export: `Citizen.Await` sem `assertThread()` — caller fora de thread crasha; documentado no comentário mas sem fail-fast em runtime. Herdado de LSPD-2 (não corrigido nesta sprint). A corrigir em LSPD-4.
- `_dedup` sem cap absoluto de tamanho: GC lazy por chamada limpa TTL expirados; sem teto de entradas simultâneas. Aceitável em escala GTARP normal.
- `vhub_lspd_bolos`: sem `UNIQUE KEY (plate, active)` no schema — duplicate BOLOs por placa são prevenidos apenas pela cache VRAM. Se o banco for manipulado manualmente com dois registros `active=1` para a mesma placa, `loadAll()` sobrescreve o anterior (sem crash, sem dado perdido, mas sem alerta). Risco baixo, aceitável.
- Radar (`client/radar.lua`): loop único `while running do` + `Wait` adaptativo — guard `running` desliga em `onResourceStop` (L-06 ok). A thread de radar em `client/police.lua` foi REMOVIDA (migrou p/ radar.lua); sem double-listener.
- **`cfg.radar.anyVehicle = true` é flag de TESTE** (`shared/config.lua`) — abre o radar em QUALQUER veículo/heli, não só classe 18. **DEVE ser `false` em produção** (auto-open só em viatura policial). Não é regressão de segurança (a placa client é só UI; `processScan` valida `canScan` server-side independente da classe), mas é UX/produção-pendente. Trocar antes do go-live.
- Overlays do radar e do helicam (`web/modules/*`) são passivos standalone (`pointer-events:none`, sem NuiFocus) e o `web/app.js` é DISPATCHER mínimo SEM engine (`vhub.createModule`/router/store ausentes — decisão do arquiteto). A-01..A-08 satisfeitos pela forma mais simples correta (1 listener central + `_destroyAll` no unload + dedup/throttle no Lua). Não evoluir para engine sem necessidade real (LSPD-7/MDT pode reavaliar se a UI ganhar interatividade/foco).
- **`cfg.client.forwardAirScans` REMOVIDA em LSPD-7** (era config morta flagada no gate LSPD-6) — o helicam decide o encaminhamento aéreo pelo seu próprio `cfg.helicam.autoAirScan`. Único emissor de `kind='air'` é `attemptLock` em `client/helicam.lua`. Limpeza concluída; sem impacto funcional.
- **Conflito de keybind F7 (LSPD-7)** — F7 é o DEFAULT de `RegisterKeyMapping` em 3 resources: `vhub_groups` (painel admin), `vhub_racha` (painel corrida) e `vhub_lspdtool` (MDT). No FiveM cada keymapping é independente e rebindável em Settings → Key Bindings, então NÃO há erro de runtime, mas o default de fábrica dispara os 3 comandos juntos (UX ruim out-of-the-box). Não-bloqueante (rebind resolve; o MDT só abre para quem o servidor confirma policial). `vhub_admin` usa F6 (sem colisão). Sugestão futura: escolher tecla default livre p/ o MDT.
- **Corrida benigna de reabertura do MDT (LSPD-7)** — se o policial fecha o MDT (F7/Esc) entre clicar "+BOLO"/"✕" e a resposta `MDT_DATA` chegar, o cliente reabre o painel (re-concede foco). Mesmo painel do próprio usuário autorizado; sem vazamento de dados nem foco preso (Esc/F7 fecham de novo). Risco baixo aceito.
- **Helicam — pendências de runtime (LSPD-6)**: confirmar em FXServer dentro de heli — slew yaw/pitch, zoom por scroll (14/15), ciclo de visão NV/thermal, holofote, lock por raycast em ângulo íngreme (z-aware), placa → BOLO via `kind='air'`, e cleanup ao sair do heli / parar o resource (cam destruída, NV/thermal off, radar do mapa restaurado). Coexistência X: validar que em viatura terrestre o auto-open ainda abre e que em heli o radar NÃO abre.

| Sprint | Foco | Status |
|--------|------|--------|
| SPRINT-LSPD-1 | Bridge server-authoritative (autorização, anti-flood, dedup, BOLO, dispatch, auditoria) | ✅ Aprovado — gate revisao 2026-05-31 |
| SPRINT-LSPD-2 | `assertThread()` em `getRecentScans`; cap em `_dedup`; smoke tests documentados | ⏳ Absorvido em LSPD-3 (parcial) — assertThread pendente |
| SPRINT-LSPD-3 | BOLO+dispatch nativos vHub; alerta com blip; remoção l2s-dispatch | ✅ Aprovado — gate revisao 2026-05-31 — pendente: smoke tests runtime |
| SPRINT-LSPD-4 | `assertThread()` em `getRecentScans`; UNIQUE constraint em vhub_lspd_bolos; smoke tests | ⏳ Pendente |
| SPRINT-LSPD-5 | Radar NATIVO (`client/radar.lua` + overlay `web/`); reversão parcial de LSPD-1; remoção escrow `sd-policeradar` + `client/hooks.lua` + spike `web/` rogue; LOS síncrono z-aware | ✅ Aprovado — gate revisao 2026-06-04 — pendente: runtime (LOS frente/trás, auto-open, BOLO via radar) + `anyVehicle=false` |
| SPRINT-LSPD-6 | Helicam NATIVO (`client/helicam.lua`: cam scriptada/zoom/visão/holofote/lock raycast→`kind='air'`) + reorg modular da `web/` (dispatcher SEM engine `app.js`/`core.css`; radar migrado p/ `modules/radar`; novo `modules/helicam`; `web/style.css` deletado) + coexistência X (radar=solo via `isAircraft`, helicam=heli via `canOperate`); server INTOCADO; `VHubLspd.UI` aditivo | ✅ Aprovado — gate revisao 2026-06-04 — pendente: runtime (helicam: slew/zoom/visão/holofote/lock/BOLO aéreo/cleanup; coexistência X terrestre↔heli) |
| SPRINT-LSPD-7 | MDT/Central de Despacho NATIVO (`server/mdt.lua`+`client/mdt.lua`+`web/modules/mdt`): 1º módulo NUI INTERATIVO (foco via Lua); reusa domínio BOLO (sem 2ª fonte); server/main+bolo INTOCADOS; contrato aditivo; `forwardAirScans` morto removido | ✅ Aprovado — gate revisao 2026-06-04 — pendente: runtime (F7 abre só p/ policial; criar/remover BOLO reflete em /bolos+radar; scans recentes; Esc/F7 fecham e devolvem foco; conflito F7 groups/racha) |

> **ÉPICO COMPLETO (2026-06-04):** suíte `vhub_lspdtool` 100% nativa vHub — os 3 escrow originais (radar=`sd-policeradar`, helicam, dispatch=`l2s-dispatch`) substituídos por implementação própria server-authoritative. LSPD-5 (radar) + LSPD-6 (helicam) + LSPD-7 (MDT) ✅. Pendências remanescentes = validação runtime + housekeeping (LSPD-2/4: `assertThread` em `getRecentScans`, UNIQUE em `vhub_lspd_bolos`, `anyVehicle=false` em produção).

### vhub_velo (resource externo — `resources/[SCRIPTS]/vhub_velo`)

**Decisão de arquitetura (2026-06-05 — épico VELO-1/2/3/4 — SEPARAR):** o velocímetro foi EXTRAÍDO do `vhub_vehcontrol` para um resource próprio. **`vhub_velo` é o DONO ÚNICO do HUD de display do veículo** (velocímetro/odômetro/marcha/fuel/setas/cinto/trava/bússola); o `vhub_vehcontrol` cede o velocímetro e fica só com controle + cinto + sync vEnter/vLeave. **Há só UM velocímetro na tela** (o escolhido pelo jogador). Aprovado: arquiteto (plano SEPARAR; VELO-3 APROVAR; personalização REDUZIR_ESCOPO→aplicado; template APROVAR) + runtime 10/10 + designer 9/10 + seguranca APROVAR (fix do terminador CSS aplicado) + gate revisao (este).

**Invariante L-04 (consumidor puro):** `vhub_velo` **SÓ LÊ** — bags `vh_fuel`/`vh_odo`/`vhub_seatbelt` (leitura) + natives efêmeros + `vHub:vehicleStateLoad`. **NUNCA escreve bag, `setVData`, nem TriggerServerEvent de mutação** (verificado linha-a-linha em `client/main.lua`). O odômetro de EXIBIÇÃO integra local sempre (base = `vehicleStateLoad`/bag como PISO, nunca override; nunca persiste). KVP (`SetResourceKvp`) é usado SÓ para preferência de UI client-side (dado não-crítico, L-02). Cinto = dono é o `vhub_vehcontrol` (velo só lê o statebag `vhub_seatbelt`). Sem `server_scripts` (sem servidor).

| Módulo | Arquivo | Responsabilidade canônica |
|--------|---------|--------------------------|
| Config | `shared/config.lua` | `Config.VehicleCategories` (classe GTA→carro/moto/aero), `Config.Huds` (galeria, paths reais: carro/vrm_classic, moto/velo_moto_defaut, aero/helicoptero_defaut), `Config.DefaultHuds` |
| Client (L2/HAL) | `client/main.lua` | PURO CONSUMIDOR: loop adaptativo (80/350ms, `running` guard L-06) lê bags+natives → `velocimetro:update` (dedup + heading threshold 2°); categoria→`loadCategory`; `/velo` galeria (foco só ao abrir); KVP (HUD id + bg + accent, por categoria); sanitização da personalização (URL http(s)+extensão imagem+sem char que quebre CSS `url()`; cor hex); cleanup onResourceStop (foco+toggle) |
| NUI host (L3) | `nui/index.html` + `nui/velo-controller.js` | host IIFE com 1 iframe ISOLADO (`pointer-events:none`) + galeria glass/areia/dourado; roteia `velocimetro:loadHud/toggle/update/config/openConfig`; render DOM SEGURO (`textContent`/`createElement`); `fetch` só em ação do usuário (A-06); reaplica config+último update no `frame.onload` |
| NUI engine (L3 lib) | `nui/velo-core.js` | engine UNIVERSAL (porte de `vhub_vehcontrol/script-velocimetro.js`): gauges binary-search O(log n); odômetro RAF **GATED por `state.active`** (auto-termina quando inativo → idle ~0, satisfaz A-07 sem `onDestroy` formal — lib em iframe, não módulo `createModule`); `normalize` null-safe; `applyConfig`→CSS vars `--velo-bg`/`--velo-accent`; preview fora do FiveM. Incluído por TODA HUD via `../../velo-core.js` |
| NUI HUDs (L4) | `nui/huds/<cat>/<pasta>/` | 3 HUDs no contrato `velocimetro:update`: carro/vrm_classic (usa as vars de personalização), moto/velo_moto_defaut, aero/helicoptero_defaut |
| NUI template | `nui/huds/_template/` | template de produção (FORA de `Config.Huds` → não aparece na galeria) + README = guia de linha de produção de HUD |

**Contrato NUI (aditivo, não quebra nada):**
- `velocimetro:update { speed_kmh, rpm_percent, gear_label, fuel_percent, odometer_km, turn_left/right, seatbelt, locked, heading, visible, active }` — Lua→host→iframe.
- `velocimetro:config { bg, accent }` — ADITIVO (VELO-4); só seta CSS vars, HUD que não usa ignora.
- `velocimetro:loadHud/toggle/openConfig` — host↔Lua.
- NUI callbacks: `velo:closeConfig`, `velo:saveHud`, `velo:saveConfig`.
- KVP namespace: `vhub_velo:<cat>`, `vhub_velo:bg:<cat>`, `vhub_velo:accent:<cat>` — escopo per-resource (FiveM), sem colisão com qualquer outro resource.

| Sprint | Foco | Status |
|--------|------|--------|
| VELO-1/2 | Reorganizar `vhub_velo` (config paths reais; manifest sem server fantasma; client consumidor puro; engine portado `velo-core.js`; host 1 iframe + galeria; 3 HUDs) | ✅ Aprovado — gate revisao 2026-06-05 — pendente validação runtime |
| VELO-3 | Remover velocímetro do `vhub_vehcontrol` (4 arquivos + `<main>` + 4 refs no fxmanifest); controle/cinto/vEnter intactos | ✅ Aprovado — gate revisao 2026-06-05 — verificado: zero ref de código residual (só comentários) |
| VELO-4 | Personalização (`velocimetro:config` bg/accent → CSS vars; KVP; galeria "Personalizar"; sanitização) + template de produção | ✅ Aprovado — gate revisao 2026-06-05 — pendente validação runtime |

**Pendência:** validação runtime in-game — 1 só velocímetro aparece; troca de HUD por categoria (carro/moto/aero); `/velo` abre galeria e devolve foco; personalização (fundo por link + cor) aplica ao vivo e persiste no KVP; odômetro conta e usa o bag como piso; fuel do velo == fuel do painel `vc-fuel` (mesmo bag); cinto reflete a tecla G do vehcontrol.

---

### vhub_conce / vhub_ferinha (resources de veículo — reorg 2026-06-03)

**Boot order (resources.cfg):** `... money → ... inventory → vhub_conce → vhub_ferinha → vhub_garage → vhub_admin`. conce antes de ferinha antes de garage — exports registrados em file-load garantem disponibilidade no consumidor seguinte; chamadas cross-resource envolvidas em `safe(pcall)` em conce/ferinha core.

| Resource | Módulo | Responsabilidade canônica |
|----------|--------|---------------------------|
| vhub_conce | `server/sql.lua` | Escritor único `vhub_vehicles`/`_keys`/`_stock` + espelho `vh_vehicles`. `updateOwner` (chamado SÓ por `Core:transferOwner`) |
| vhub_conce | `server/vstate.lua` | **PRONTUÁRIO — escritor ÚNICO de `vhub_vehicle_state`** (físico: fuel/engine/body/odômetro/customization/damage/damage_log; decisão #24). DDL idempotente no boot do conce; backfill/reconcile disparados pelo GARAGE pós-DDL (guarda dupla); cache VRAM read-through com evict no delete |
| vhub_conce | `server/core.lua` | `canOperate` (chave-item + dono/autorização), `transferOwner` (atômico char_id + revoke owner antigo + grant owner novo), `newPlate`, `returnExpiredHoldings` (cron 24h), sessões próprias via `vHub:characterLoad` |
| vhub_conce | `server/dealership.lua` | buy/sellToShop/testDrive (retornam `{ok,msg}`; garage delega e fala com NUI) |
| vhub_conce | `server/init.lua` | `backfillMirror` + `backfillOwnerKeys` no boot; cron 24h (`while _running` + `Wait(cron_interval_ms)` + lote `Wait(0)`, L-06 ok) |
| vhub_ferinha | `server/sql.lua` | Escritor único `vhub_auctions`/`_bids` |
| vhub_ferinha | `server/auction.lua` | escrow VRAM `Escrow[id]`, lock cooperativo `Busy[id]`, finalize/bid/cancel, `finalizeExpired` (cron), `reconcileOrphans` (boot) |
| vhub_ferinha | `server/core.lua` | integração money/inventory/conce; `payChar`→`giveBankChar` (offline-safe); `transferOwner`→`conce` |
| **vhub_vehcontrol** | `server/main.lua` | controle de veículo (trava/motor/luzes/banco/câmera) + **funil de telemetria física (#24)**: `stateSync`/`requestState` FAIL-CLOSED (netId resolve + placa bate + `GetPedInVehicleSeat(-1)==ped`) → `exports.vhub_conce:saveVehicleState(...,'telemetry')`. Gate temporal 14s (final 2s, dedup leave×tick); GC dos mapas em playerDropped. **`vEnter`/`vLeave` REMOVIDOS** (cadeia do CORE inerte) |
| **vhub_vehcontrol** | `client/main.lua` | motorista: drena fuel 1s (rpm/classe) + decor delta-gate 0.5; snapshot FULL 15s + final no leave; `requestState`→`applyState` com control-gate + bone-check de janelas + tyres burst/rim; emite evento LOCAL `stateApplied` (velo semeia odômetro). Cinto/crash-eject; `_running` guard (L-06). **Cinto = DONO ÚNICO** (tecla G → statebag local `vhub_seatbelt`; o velo só lê) |
| **vhub_vehcontrol** | `client/main.lua` (dashboard) | painel `vc-panel` (NUI `html/`) só com barra de combustível própria (`updateFuel`): LÊ o MESMO bag `vh_fuel` do CORE (leitura independente, **NÃO é 2ª fonte** — mesma origem que o velo, com fallback ao native sem registro vHub). **Velocímetro REMOVIDO daqui (VELO-3 2026-06-05) — migrou para `vhub_velo`** (`client/velocimetro.lua`, `html/script-velocimetro.js`, `html/style-velocimetro.css`, `html/dashboard_fivem.svg` deletados; `<main id="velocimetro">` + 4 refs no fxmanifest removidos) **Pós-#24: bags `vh_fuel`/`vh_odo` do CORE dormentes — o painel opera pelo fallback native.** |

**Invariantes auditadas (2026-06-03; vehcontrol 2026-06-04) — não quebrar:**
1. `char_id` em `vhub_vehicles` escrito SÓ por `conce:transferOwner` (todos os call-sites: garage P2P, `forceTransfer`, admin transfer, ferinha finalize → passam por ele).
2. `vhub_vehicles`/`vhub_vehicle_keys`/`vhub_dealership_stock` mutados SÓ em `vhub_conce/sql.lua`.
3. `vhub_auctions`/`vhub_auction_bids` mutados SÓ em `vhub_ferinha/sql.lua`.
4. `vhub_vehicle_log` é log append-only compartilhado (conce/garage/ferinha inserem; admin purga) — NÃO é fonte de verdade.
5. Garagem lista por chave-item (`inventory:getVehicleKeys`), nunca por `char_id`.
6. FÍSICO (fuel/eng/body/odômetro/dano/customization) tem `vhub_conce/server/vstate.lua` como ESCRITOR ÚNICO de `vhub_vehicle_state` (decisão #24 — substitui `vh_vehicle_data 'state'`, hoje INERTE). Toda escrita passa por `exports.vhub_conce:saveVehicleState/repairVehicleState` (sources: telemetry/store/pump/seed/repair). NUNCA reintroduzir `setVData`/escrita física fora do VState nem reanimar a cadeia do CORE sem gate do arquiteto. Consumidores (velo/inventory/admin) só LEEM (`getVehicleState`/`getVehicleDossier` — exports devolvem CÓPIA).

**Riscos residuais documentados (reorg veículos):**
- **Cadeia física AGORA VIVA mas pendente de validação runtime (FASE 5 parcial)**: o typo `@dkey`→`@key` (decisão #20) e o elo `vEnter` do vehcontrol (decisão #21) reanimaram `getVData/setVData` e o autosave físico. **Antes desta janela o path inteiro era no-op silencioso** — logo "/fuel zera no apply" e "odômetro não conta" SÓ podem ser confirmados/refutados em RUNTIME (FXServer + entrar/dirigir/sair + /fuel + restart→reentrar). D1 (fuel com 3 save-triggers sobre o mesmo `vd.state`) não é mais 3 fontes divergentes (é 1 objeto), mas a ORDENAÇÃO de escrita entre triggers concorrentes na mesma key por flush é agora ativa — observar se há valor pisado inesperado. Restante de FASE 5 (reparo, absorção completa de HUD) segue pendente.
- **Escrow de leilão volátil mas blindado**: offline-credit + `reconcileOrphans`. Resta a janela ínfima lance↔crash (entre `Escrow[id][cid]=amt` e o commit de `add_bank_offline` num crash exatamente no meio) — risco baixo aceito.
- **Chave-item órfã de não-dono offline pós-cron**: o cron 24h só remove a chave-item se o portador estiver online (`srcByCharId`); offline a linha de autorização é revogada (fail-closed: garagem não lista, `canOperate` falha em `hasValidKey`), mas a chave-item física resta no inventário até limpeza no login (deferida).
- `give_bank_char` reload reaplica só `wallet/bank/dirty`; `total_in/out` da entry viva não re-sincroniza (drift de métrica agregada, sem impacto em saldo — `add_bank_offline` já bumpa `total_in` no DB).

| Sprint/Fase | Foco | Status |
|-------------|------|--------|
| FASE 0 | Limpeza órfãos (spawnmanager, .bak, #ensure morto) + criar conce/ferinha (L-07) | ✅ Aprovado |
| FASE 1 | conce escritor único de chave↔placa↔dono; garage SQL = proxy; `authorized`→`canOperate` | ✅ Aprovado (arquiteto+contrato+simplicidade) |
| FASE 2 | Concessionária → conce; catálogo `conce/shared/catalog.lua`; garage = delegator | ✅ Aprovado (contrato+simplicidade) |
| FASE 3 | Garagem por chave-item + self-heal + backfillOwnerKeys + cron 24h | ✅ Aprovado (seguranca+performance) |
| FASE 4 | Leilão → ferinha (escrow+finalize+cron+reconcile); `transferOwner` único escritor char_id; hardening crédito offline | ✅ Aprovado — gate revisao 2026-06-03 — pendente validação runtime |
| FASE 5 | Consolidar vehcontrol (HUD/velocímetro/fuel/reparo); resolver D1 fuel; absorver vrm_velocimetro | 🟡 PARCIAL (2026-06-05) — `vhub_vehcontrol` criado (L-07); `vrm_velocimetro` absorvido+deletado; elo `vEnter` + hotfix CORE #20 reanimam a cadeia física; single-writer reconciliado (#21). **VELO (2026-06-05): velocímetro EXTRAÍDO para resource próprio `vhub_velo` (dono único do HUD; consumidor puro) — VELO-1/2/3/4 ✅; ver seção `vhub_velo`. vehcontrol = só controle+cinto+sync.** Pendente: validação runtime de /fuel+odômetro+reparo+velocímetro único |
| FASE 6 | garage enxuto + remover proxies/delegators + migrar DDL para donos | ⏳ Pendente (cosmético) |

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

### vhub_inventory — exports públicos

| Export | Proteção | Assinatura |
|--------|----------|------------|
| `getInventory` | pública | `(src) → { slots, weight, max, size }` |
| `getItemAmount` | pública | `(src, id) → number` |
| `hasItem` | pública | `(src, id, qty) → bool` |
| `getInventoryWeight` | pública | `(src) → number` |
| `getItemDef` | pública | `(id) → def\|nil` |
| `getItemName` | pública | `(id) → string` |
| `hasVehicleKey` | pública | `(src, plate) → bool` |
| `getVehicleKeys` | pública | `(src) → []plate` |
| `giveItem` | `_invoker_allowed()` | `(src, id, amount, meta) → bool` |
| `takeItem` | `_invoker_allowed()` | `(src, id, amount) → bool` |
| `registerItemUse` | `_invoker_allowed()` | `(id, fn) → bool` |
| `openContainer` | `_invoker_allowed()` | `(src, desc) → bool` — desc = `{ kind, name\|group\|netId }` |
| `giveVehicleKey` | `_invoker_allowed()` | `(src, plate) → bool` |
| `takeVehicleKey` | `_invoker_allowed()` | `(src, plate) → bool` |

**Eventos canônicos (VHubInvE):** `vhub_inventory:open/close/delta/rollback/notify/container_open/container_delta/container_close/use/move/drop/pickup/p2p/store/retrieve/open_container/close_container/request_sync/hud_req/hud`

**NUI callbacks canônicos:** `nui_ready`, `close`, `use`, `move`, `container_close`, `store`, `retrieve`

**SendNUIMessage actions canônicos:** `open`, `close`, `delta`, `rollback`, `notify`, `container_open`, `container_close`, `container_delta`

---

### vHub.getUData / setUData / getCData / setCData / getVData / setVData / getGData / setGData
- Assinatura: `(id, key [, value [, tx]])` — estável
- Exige `Citizen.CreateThread` no chamador (usa `Citizen.Await` internamente via assertThread)
- **`getVData`/`setVData` ESTAVAM MORTOS desde o freeze por typo `@dkey` (decisão #20); corrigidos em 2026-06-04 — assinatura inalterada, comportamento agora VIVO.** Bind de chave é sempre `key` (nunca `dkey`).

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

> **N0-2 (decisão #32):** `_invoker_allowed` é DEFAULT-DENY — sem `trusted_resources` populado, `grantPerm`/`transferKey`/`banPlayer`/`unbanPlayer` NEGAM (warn one-shot). `getVehicle (plate)→VD` segue `K:export` (sem gate) e devolve VD vivo por referência — risco residual SEPARADO, não endereçado.

---

### exports do resource `vhub_conce` (todos `_invoker_allowed`; trusted: vhub, vhub_garage, vhub_ferinha, vhub_admin, vhub_inventory, vhub_vehcontrol, vhub_legacyfuel, vhub_testrunner)
| Export | Assinatura |
|--------|-----------|
| `canOperate` | `(src, plate) → bool` |
| `isOwner` | `(src, plate) → bool` |
| `transferOwner` | `(plate, new_cid) → bool` — ÚNICO escritor de `char_id`; **transação ATÔMICA** (char_id+revoke/grant 'owner', `SQL:transferOwnerTx`, decisão #32); retorna commit REAL (era sempre `true`) |
| `plateExists` / `getVehicle` / `listByOwner` / `listByStatus` | leitura de `vhub_vehicles` |
| `createVehicle` / `updateStatus` / `updatePosition` / `updateCustomization` / `updateIpva` / `updateRental` / `deleteVehicle` | escrita `vhub_vehicles` (+ espelho `vh_vehicles`) |
| `grantKey` / `revokeKey` / `hasValidKey` / `listKeys` / `listKeysOfChar` / `purgeExpiredKeys` | `vhub_vehicle_keys` |
| `stockGet` / `stockSet` / `stockDecrement` | `vhub_dealership_stock` |
| `getCatalog` | `() → catálogo` (garage cacheia no boot) |
| `buy` / `sellToShop` / `testDrive` | `(...) → {ok,msg}` (garage delega + fala com NUI) |
| `getVehicleState` / `getVehicleDossier` | leitura do prontuário `vhub_vehicle_state` — **NUNCA nil p/ placa registrada** (estado de fábrica se nunca persistiu); nil p/ placa inexistente (#24) |
| `saveVehicleState` / `repairVehicleState` | `(plate, patch, source)` / `(plate)` — escritor único do físico; repair é o ÚNICO que eleva health (#24) |
| `backfillVehicleState` / `reconcileVehicleState` | manutenção 1x/idempotente — disparados pelo garage pós-DDL (#24) |

### exports do resource `vhub_ferinha` (todos `_invoker_allowed`; trusted: vhub, vhub_garage, vhub_admin, vhub_conce)
| Export | Assinatura |
|--------|-----------|
| `listActiveAuctions` | `() → []auction` |
| `getAuctionByPlate` | `(plate) → auction\|nil` |
| `newAuction` | `(src, plate, min_bid, buyout, dur_min) → {ok,msg}` |
| `bid` | `(src, auction_id, amount) → {ok,msg}` |
| `cancelAuction` | `(id, actor_cid) → bool` |
| `finalizeExpired` | `() → count` |

### exports do resource `vhub_money` (mutadores `_invoker_allowed`; trusted += `vhub_ferinha`)
| Export | Assinatura | Proteção |
|--------|-----------|---------|
| `giveBankChar` | `(char_id, valor, reason) → bool` — credita banco ONLINE ou OFFLINE (offline-safe; fecha race de login) | `_invoker_allowed()` |

> Contratos do `vhub_garage` mantidos via proxy/delegator (decisão #18): `getVehicle`, `listOwnerVehicles`, `isImpound`, `ipvaUntil`, `forceTransfer`, `forceImpound` — assinaturas inalteradas (consumidos por `vhub_inventory`, `vhub_admin`).

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
5. **Higiene do contexto.md (DÍVIDA)**: arquivo ~139KB (cap 20KB) com o miolo DUPLICADO e divergente (blocos ~155-585 vs ~586-1006; a cópia B não tem vehcontrol/#24) — passada dedicada de dedup + arquivamento em `.claude/contexto_arquivo/`. A cópia VIVA é a primeira (A).

## Bloqueios ativos

- Smoke tests T1..T5 dependem de ambiente FXServer + MariaDB + injeção de carga
- `multipleStatements=true` na connection string deve ser verificado manualmente (pré-requisito do `bootstrap.lua:307` que aplica schema em multi-statement)
- Banco pré-existente com `MEDIUMBLOB` em `vh_*_data` continua funcionando (schema é `CREATE IF NOT EXISTS`). Otimização para `BLOB` documentada no header de `sql/schema.sql`
- `vhub_racha`: `while true` em `client/nui_bridge.lua` (loop de telemetria 250ms) sem condição de saída explícita — risco baixo (resource stop limpa threads FiveM), mas viola L-06. Registrado para SPRINT-RACHA-4.
- `vhub_racha`: `web/index.html` carrega Google Fonts e Font Awesome via CDN externo — risco de latência em ambiente sem internet. A migrar para assets locais na SPRINT-RACHA-5.
- `vhub_racha`: pendente **validação em runtime** das correções de 2026-05-29 (totem nativo aparecendo, cronômetro MM:SS, drift acumulando, card de chegada sumindo em 5s). Se o drift travar em 0 mesmo driftando → ajustar `Cfg.DRIFT.MIN_ANGLE_DEG`/`MIN_SPEED_KMH`.
- **Hotfix persistência veicular (decisão #22): VALIDAÇÃO RUNTIME (BOOT OK, AGUARDANDO FLUXO IN-GAME)** — Boot do FXServer 2026-06-11 OK; MySQL seeds capturados; `vhub_run_tests` (`test_vdata_roundtrip` + `test_blob_armor_roundtrip`) pendente; fluxo in-game (dirigir→guardar→restart→spawnar: fuel/mods/odômetro/posição) aguardando jogador online + resmon do flush (L-18).
- **Sprint PRONTUÁRIO (decisão #24): VALIDAÇÃO RUNTIME PENDENTE** — dirigir→abastecer→guardar→restart→spawnar; `vhub_run_tests` (`test_vstate_roundtrip`); resmon do vehcontrol. `resources/[CORE]/vhub_legacyfuel/` UNTRACKED — exige `git add` no commit do sprint.

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
)` + guard `#p >= 1`; espelha exatamente `normalizePlate` do CORE (preserva espaço interno legítimo como `"DJD 5470"`).
    - `vhub_vehcontrol/server/main.lua` (`vEnter` linha ~111, `vLeave` linha ~162): `plate = normPlate(plate)` + `if plate == '' then return end` — `normPlate` (linha 17) pré-existente retorna `''` no pior caso, nunca `nil`. Guard fecha loop de retry silencioso para placa não-normalizável.
    - CORE FROZEN: **não tocado**. `vehicle.lua` sem diff. `state.lua` — única modificação é o b64 da decisão #22a (pré-existente).
    - Sem `print`/`Logger:info` temporários (grep confirmado zero matches).
    - Placa com espaço interno legítimo (`"DJD 5470"`): `gsub('%s+', ' ')` colapsa múltiplos mas preserva único → comportamento idêntico ao CORE (`normalizePlate` linha 12).
    - **Gates anteriores:** vhub_guardiao_natives APROVOU; vhub_guardiao_seguranca APROVOU.
    - **Risco residual:** o retry do client (cap 5, 1500ms) continua emitindo `vEnter` até ack — para placa não-registrada o server responde com ack imediato (sem âncora FK) e o retry para. Sem loop infinito. Smoke test: entrar em veículo registrado → log `[vHub][INFO][vehcontrol] vEnter src=X plate=MITAGE gate ok` (sem leading space) → `_syncBags` não crasha → `vh_vehicle_data` escrita no próximo flush.
    - Testes: `test_blob_armor_roundtrip` no testrunner (binário 0x00–0xFF, colisão de prefixo `'b64:'` em valor interno, 2º ciclo write→flush→read) + `tools/test_b64_roundtrip.lua` offline standalone (RFC 4648 + 200 aleatórios + bench — PASSOU em Lua 5.4.8; bench: blob 3KB <1ms, 45KB ~4-8ms). Rollback de 1 linha: `git checkout HEAD -- "resources/[CORE]/vhub/server/state.lua"` (legado raw segue legível; rows já blindadas exigiriam decode manual — rollback só ANTES de acumular escrita nova).

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

### vhub_inventory (resource externo — `resources/[SCRIPTS]/vhub_inventory`)

| Módulo | Arquivo | Responsabilidade canônica |
|--------|---------|--------------------------|
| SQL | `server/sql.lua` | queries via `exports.oxmysql` direto (decisão #8); schema idempotente em `sql/schema.sql` |
| Mochila | `server/backpack.lua` | cache VRAM `_sess[src]` por `char_id`; flush triplo; isolamento por personagem (troca de char faz flush do anterior) |
| Baús | `server/containers.lua` | cache VRAM `_cache[cid]` por baú ABERTO; liberado quando sem viewers; mutex `_locks[cid]` 300ms; open-guard `_open[src]` (só muta o baú que o servidor autorizou); flush triplo (debounce 3s + último-viewer + onResourceStop) |
| Transfer | `server/transfer.lua` | mochila↔baú atômico sob mutex+open-guard; otimista só na origem; falha → revert autoritativo + notify |
| HAL Client | `client/containers.lua` | markers proximity-gated (thread única, Wait 0/1000); porta-malas via tecla K; tampa cosmética SetVehicleDoorOpen/Shut |
| Exports | `server/exports.lua` | `_invoker_allowed()` em todos os mutadores; `openContainer` novo (INV-2) |

**Regras de negócio congeladas (INV-2):**
- Capacidade do porta-malas vem do registro `vhub_garage` (`vtype_mult`) — **`GetVehicleClass` server-side proibido** (ambíguo, viola L-04).
- Acesso ao porta-malas: chave física (`veh_key` na mochila) OU ser dono no `vhub_garage`.
- Permissão de baú de facção via `exports.vhub_groups:hasPermission` (soft pcall).
- Isolamento por `char_id` — **nunca cruzar personagens** (L-04).
- Anti-spoof de entidade: `NetworkDoesEntityExistWithNetworkId` + `ent~=0` + `GetEntityType(ent)==2` + distância server-side + placa server-side.
- `vhub_inv_containers`: `container_id` composto (`static:<nome>`, `faction:<grupo>`, `trunk:<placa>`).

**Riscos residuais documentados (INV-2):**
- `while true` sem condição de saída em `client/containers.lua` (L-06 — risco baixo, FiveM limpa threads; a corrigir em INV-3 ou SPRINT-INV-4).
- `assertThread()` ausente nas funções públicas `M.load()` e `M.flush()` de `containers.lua` (chamam `Citizen.Await`/`CreateThread` internamente; não crasham pois são sempre invocadas de thread, mas violam o padrão declarativo).
- `onDestroy` do `container.js` não remove explicitamente o listener `.ct-close` (elemento destruído pelo `innerHTML=''`; sem leak real, mas inconsistente com A-07).

| Sprint | Foco | Status |
|--------|------|--------|
| SPRINT-INV-1 | Mochila server-authoritative (open/move/use/HUD/char_id) | ✅ Aprovado |
| SPRINT-INV-2 | Baús (static/faction/trunk), transfer atômico, UI otimista + revert | ✅ Aprovado (gate revisao 2026-05-29) — pendente validação runtime |
| SPRINT-INV-3 | Drops no chão (módulo de drops, perdivel, death) | ⏳ Pendente |

### vhub_lspdtool (resource externo — `resources/[SCRIPTS]/vhub_lspdtool`)

> Ownership canônico atual = tabela **"Ownership por módulo (atualizado LSPD-5)"** mais abaixo. O snapshot LSPD-1 histórico (bridge como adapter de `sd-policeradar`/`l2s-dispatch`, `client/hooks.lua`, eventos `RADAR_SCANNED`/`ON_PLATE_SCANNED`) foi SUPERADO: dispatch/BOLO nativizados em LSPD-3, radar nativizado em LSPD-5 (`client/hooks.lua` deletado).

**Decisão de arquitetura (2026-05-31 — LSPD-1):** bridge NÃO funde `l2s-dispatch`/`sd-policeradar` (escrow). Atua como adapter configurável: consome eventos/exports de terceiros via `pcall` + `GetResourceState`; UIs dos recursos escrow permanecem intactas. Pipeline é 100% server-authoritative.

**Decisão de arquitetura (2026-05-31 — LSPD-3):** dependência `l2s-dispatch` (escrow) eliminada completamente. BOLO + dispatch são agora 100% nativos vHub. `server/bolo.lua` é o módulo de domínio BOLO. Alerta com blip temporário (cap 8) + som nativo + thefeed. `ensure vhub_lspdtool` confirmado em `config/resources.cfg`. (LSPD-3 mantém-se intacto; ver LSPD-5 para a evolução do radar.)

**Decisão de arquitetura (2026-06-04 — LSPD-5 — RADAR NATIVO):** reverte PARCIALMENTE a LSPD-1 (apenas o RADAR volta a ser nativo; remove a dependência do escrow `sd-policeradar`). LSPD-3 (BOLO/dispatch nativo) INTACTO. Gate `vhub_arquiteto` = REDUZIR_ESCOPO com pré-condição cumprida: **deletado o spike ROGUE `web/`** (não carregado pelo manifest, mas violava L-04 — `web/config.lua` com `Config.BoloPlates` hardcoded = 2ª fonte de BOLO; `web/plate_handler.lua` = pipeline `processScan` PARALELO sem auth/rate/dedup/coords + `print()` + broadcast -1; `web/hooks.lua` = 3º listener). **`client/hooks.lua` (escrow listener) DELETADO.** Radar agora em **`client/radar.lua`** (HAL): loop adaptativo único (idle 700ms / update 200ms, gated driving+enabled, `running` guard L-06), raycast LOS SÍNCRONO frente/trás (`StartExpensiveSynchronousShapeTestLosProbe`, flags=2 = só veículos, `GetOffsetFromEntityInWorldCoords` z-aware — prescrição do gate de natives após REPROVAR→CORRIGIDO de capsule assíncrono), lê speed+placa LOCALMENTE (só UI, L-02), lock 'K', toggle 'X', auto-open pede `REQ_RADAR`. Placa NOVA → `TriggerServerEvent(PLATE_SCANNED)` REUSA o pipeline seguro (`processScan` NÃO tocado). NUI overlay PASSIVO em `web/{index.html,style.css,app.js}` (`pointer-events:none`, sem NuiFocus, escopo `.mod-radar`, fontes de sistema sem CDN, 1 listener + cleanup unload A-07, delta A-08). `fxmanifest`: +`client/radar.lua` +`ui_page` +3 files web; -`client/hooks.lua`. `RADAR_SCANNED`/`ON_PLATE_SCANNED` (escrow) REMOVIDOS de `events.lua`; `PLATE_SCANNED` (canônico seguro) mantido; +`VHubLspd.UI` (message types do overlay). `server/main.lua`: removido só o check de presença do escrow no `onResourceStart` (pipeline intacto). Gates: natives APROVAR (pós-correção), performance APROVAR, seguranca APROVAR (placa client = só UI; `processScan` deriva coords server-side e valida `canScan`), runtime APROVAR, designer APROVADO. Helicam = LSPD-6 (faseado); dispatch/MDT UI = LSPD-7 (faseado).

**Decisão de arquitetura (2026-06-04 — LSPD-6 — HELICAM NATIVO + REORG MODULAR DA NUI):** segundo dos 3 escrows nativizados (helicam; radar=LSPD-5 feito; dispatch/MDT=LSPD-7 próximo). **`server/main.lua` + `server/bolo.lua` INTOCADOS** (air-scan reusa o pipeline canônico `processScan`, que normaliza `kind` e deriva coords server-side). **Reorg modular da `web/` — 1 `ui_page`, DISPATCHER MÍNIMO SEM ENGINE (decisão do arquiteto: modular, mas sem store/bus/router/native-bridge):** `web/app.js` = dispatcher que expõe `LSPD.register(name,{onMessage,onDestroy})` + roteia pelo PREFIXO de `m.type` (`'radar:'`|`'helicam:'`|`'mdt:'` → módulo dono) com 1 listener `message` central + `unload` removendo o listener e chamando `_destroyAll`. `web/core.css` = tokens `:root` + reset compartilhados (CEF transparente). **Radar MIGRADO** de `web/style.css` (flat, DELETADO) p/ `web/modules/radar/{radar.css,radar.js}` — **comportamento IDÊNTICO** (mesmos `m.type` `radar:open/close/update`, mesmos seletores `.mod-radar*`/`is-open`/`is-locked`; único campo aditivo `m.unit` opcional). NOVO `web/modules/helicam/{helicam.css,helicam.js}` (overlay HUD passivo, `pointer-events:none`). `index.html` hospeda os 2 overlays + carrega `app.js` ANTES dos módulos. **Helicam nativo `client/helicam.lua` (L2/HAL):** câmera scriptada presa ao heli (`CreateCam`/`AttachCamToEntity`/`RenderScriptCams`/`SetCamFov`/`SetCamRot`/`PointCamAtEntity`); cleanup completo (`RenderScriptCams(false)`+`DestroyCam(cam,true)`+`SetNightvision(false)`+`SetSeethrough(false)`); zoom via scroll weapon-wheel 14/15 (NÃO 241/242 cursor-scroll, que exige NuiFocus — correção do gate de natives); look 1/2; visão normal/NV/thermal; holofote `DrawSpotLightWithShadow` (local, sem sync); lock por raycast SÍNCRONO próprio z-aware → lê placa → `PLATE_SCANNED kind='air'` (REUSA pipeline). HUD = overlay passivo (sem NuiFocus), delta+throttle (`updateHudMs`). Loop único adaptativo (`while running`, idle `Wait(250)` / ativo `Wait(0)`, guard L-06; idle-zero gated em `active`). **Coexistência tecla X (ambos bindam X, FiveM dispara os 2 keymaps):** `radar.lua` ganhou `isAircraft()` e EXCLUI heli/avião do `driving`-gate, do auto-open e do comando X (early-return em aeronave); `helicam.lua` early-return quando `not canOperate` (não-heli). Mutuamente exclusivos por contexto — **o auto-open terrestre NÃO regride** (só ganhou `and not isAircraft(veh)`). **Contrato aditivo:** `shared/events.lua` +`VHubLspd.UI.HELI_OPEN/CLOSE/UPDATE` (chaves `OPEN/CLOSE/UPDATE` do radar inalteradas, mesmos valores-string; `return VHubLspd.E` mantido). `shared/config.lua` +bloco `helicam`. `fxmanifest` +`client/helicam.lua` +files modulares; `web/style.css` removido dos files. **Exports públicos (reportPlate/getRecentScans/addBolo/removeBolo/checkBolo/listBolos) INALTERADOS.** Nenhum consumidor externo referenciava `web/style.css` nem a estrutura flat (verificado, zero matches). Gates: natives REPROVAR→CORRIGIDO (scroll 241/242→14/15; +`DestroyCam(cam,true)`) então APROVAR; performance APROVAR (idle-zero gated, HUD delta+throttle); runtime APROVAR (dispatcher A-01..A-08, isolamento, cleanup central); designer APROVADO (contorno do reticle p/ legibilidade sobre nightvision); seguranca NÃO acionado (server intocado; placa client = só UI, autoridade em `canScan`). **Residual cosmético:** `cfg.client.forwardAirScans=false` é flag MORTA (nada lê; helicam decide via `cfg.autoAirScan` próprio; único emissor de `kind='air'` é `attemptLock`) — limpeza futura, sem impacto funcional (sem duplicata de scan aéreo).

**Decisão de arquitetura (2026-06-04 — LSPD-7 — MDT / CENTRAL DE DESPACHO NATIVO — ÉPICO COMPLETO):** terceiro e último dos 3 escrow nativizados. **Suíte lspdtool agora 100% nativa vHub: radar (LSPD-5) + helicam (LSPD-6) + dispatch/MDT (LSPD-7) — fim do épico "versão vHub dos 3 escrow".** MDT é o **1º módulo NUI INTERATIVO** do resource (radar/helicam são overlays passivos); lista BOLOs ativos + scans recentes e cria/remove BOLO pela UI. **`server/main.lua` (pipeline `processScan`) e `server/bolo.lua` INTOCADOS** — o MDT REUSA o domínio BOLO (`VHubLspd.Bolo.create/remove/list`), sem 2ª fonte de verdade (cache VRAM `_cache`+`maxActive`+SQL preservados; create mantém cache otimista+rollback). **NOVO `server/mdt.lua` (L1):** net events `REQ_MDT` (gated `permScan` + throttle 1s/src `_req` + cleanup em `playerDropped`), `MDT_ADD`/`MDT_DEL` (gated `permManageBolo`). Snapshot lê scans via `exports.oxmysql:query` parametrizado (`SELECT plate, flagged, src_kind, created_at ... LIMIT ?`, limit = `cfg.mdt.scanLimit`). Sanitização da entrada hostil: `normalizePlate` + `reason:gsub('[%c]','')`+`sub(1,reasonMaxLen)` + clamp de `level` a `1..#cfg.bolo.levels` (aplicado no gate de segurança). **NOVO `client/mdt.lua` (L2):** abre SÓ após o servidor responder (`REQ_MDT`→`MDT_DATA`); `SetNuiFocus(true,true)` existe APENAS aqui (foco 100% Lua); fecha por botão/Esc/F7/`onResourceStop` devolvendo o foco. NUI callbacks `mdtClose`/`mdtAddBolo`/`mdtDelBolo`. **NOVO `web/modules/mdt/{mdt.css,mdt.js}` (L4)** registrado no dispatcher pelo prefixo `mdt:`: painel modal glass (único overlay com `pointer-events:auto`+dim de fundo); **render DOM SEGURO** (`textContent`/`createElement`, sem `innerHTML` de dado do servidor → sem XSS); delegação de clique (`data-act`/`.mdt-row__del` + `dataset.plate`); `fetch` SÓ em ação do usuário (A-06); `onDestroy` remove os 3 listeners (`click`/`submit`/`keydown` do document) — A-07. **Contrato ADITIVO:** `shared/events.lua` +`REQ_MDT`/`MDT_DATA`/`MDT_ADD`/`MDT_DEL` (valores-string distintos de `PLATE_SCANNED`/`REQ_RADAR`/`ENABLE_RADAR`) + `VHubLspd.UI.MDT_OPEN/CLOSE/DATA` (chaves radar/helicam inalteradas, `return VHubLspd.E` mantido). `shared/config.lua` +bloco `mdt` (`toggleKey='F7'`, `scanLimit=25`). `fxmanifest` +`server/mdt.lua` +`client/mdt.lua` +`web/modules/mdt/*` + `index.html` painel `#mdt`. **Exports públicos (reportPlate/getRecentScans/addBolo/removeBolo/checkBolo/listBolos) INALTERADOS.** Limpeza junto: removido o bloco MORTO `cfg.client.forwardAirScans` de `config.lua` (flagado no gate LSPD-6). Gates: seguranca APROVAR 6/6 (autoridade server-side, sanitização, sem SQL-injection via `?`, anti-flood, sem XSS via `textContent`, sem foco preso; clamp de level aplicado); runtime APROVAR 10/10 (A-01..A-08; render seguro, delegação, `onDestroy` remove `keydown` do document, foco 100% Lua); designer APROVADO 9/10 (identidade glass/areia/dourado; nota não-bloqueante: `.mdt-row`/`.mdt-empty` sem prefixo `.mod-` mas só vivem dentro de `#mdt`); natives/performance NÃO acionados (event-driven, sem loop/native). **Padrão do 1º módulo INTERATIVO (reuso futuro):** modal com FOCO concedido só pela camada Lua (`SetNuiFocus`) após autorização server-side, NUNCA pelo JS; render por `textContent`/`createElement`; delegação de evento via atributos `data-*`; `fetch` (callback NUI) só em ação explícita do usuário; `onDestroy` remove TODOS os listeners (inclusive os ligados ao `document`). **SEM schema novo** (reusa `vhub_lspd_scans`/`vhub_lspd_bolos`). **Residual:** F7 é default de 3 resources via `RegisterKeyMapping` (`vhub_groups` painel, `vhub_racha` painel, `vhub_lspdtool` MDT) — coexistem (cada keymapping é independente e rebindável em Settings), mas o default de fábrica dispara os 3 juntos = colisão de UX no default (não-bloqueante; rebind resolve). Corrida benigna: se o usuário fecha o MDT entre clicar "+BOLO" e a resposta `MDT_DATA` chegar, o painel reabre (mesmo painel do próprio policial autorizado; sem vazamento).

**Ownership por módulo (atualizado LSPD-7):**

| Módulo | Arquivo | Responsabilidade canônica |
|--------|---------|--------------------------|
| Config | `shared/config.lua` | cfg única: police perm+ACE+owner+dutyExport+cacheTtl; plate; rate; dedupTtl; radar (idle/update/range/skipAhead/keys/policeClass/`anyVehicle`); helicam (fov/look/pitch/vision/spot/lock/autoAirScan); **mdt (toggleKey F7/scanLimit)**; bolo; alert; log; trusted. (`client.forwardAirScans` MORTO removido em LSPD-7) |
| Events | `shared/events.lua` | `VHubLspd.E.*` — PLATE_SCANNED, BOLO_ALERT, NOTIFY, REQ_RADAR, ENABLE_RADAR **+ REQ_MDT, MDT_DATA, MDT_ADD, MDT_DEL** + `VHubLspd.UI` (radar:open/close/update + helicam:open/close/update **+ mdt:open/close/data** — tudo aditivo) |
| Bridge server | `server/main.lua` | **INTOCADO em LSPD-6/7.** pipeline L1: helpers (perm/plate/uid/notify/invokerAllowed); canScan (cache TTL); rateOk; dedupOk lazy-GC; broadcastAlert (direcionado); processScan (normaliza `kind` air/ground; deriva coords server-side); PLATE_SCANNED handler; REQ_RADAR→ENABLE_RADAR; lifecycle |
| BOLO | `server/bolo.lua` | **INTOCADO em LSPD-6/7.** cache VRAM `_cache[plate]`; loadAll; check O(1); list; create (otimista+rollback); remove; comandos /bolo /delbolo /bolos; exports addBolo/removeBolo/checkBolo/listBolos. **MDT reusa `Bolo.create/remove/list` (sem 2ª fonte)** |
| MDT server (L1) | `server/mdt.lua` | despacho server-authoritative: `REQ_MDT` (gated permScan + throttle 1s `_req` + cleanup playerDropped) → snapshot (bolos via `Bolo.list` + scans via oxmysql `LIMIT ?` + canManage + levels); `MDT_ADD`/`MDT_DEL` (gated permManageBolo) → sanitiza (normalizePlate + reason gsub/sub + clamp level 1..#levels) → `Bolo.create/remove` → refresca solicitante |
| MDT client (L2) | `client/mdt.lua` | NUI INTERATIVA: abre SÓ após `MDT_DATA` do servidor; `SetNuiFocus` existe APENAS aqui (foco 100% Lua); fecha por botão/Esc/F7/onResourceStop devolvendo foco; callbacks mdtClose/mdtAddBolo/mdtDelBolo (servidor revalida permissão) |
| NUI módulo MDT (L4) | `web/modules/mdt/{mdt.css,mdt.js}` | painel modal glass INTERATIVO (`pointer-events:auto`+dim); `onMessage(mdt:*)`; render DOM SEGURO (textContent/createElement, sem innerHTML → sem XSS); delegação data-act/data-plate; fetch só em ação do usuário (A-06); onDestroy remove 3 listeners click/submit/keydown (A-07) |
| HAL client RADAR | `client/radar.lua` | radar NATIVO solo: loop adaptativo único (idle/update gated, `running` guard L-06); raycast LOS síncrono frente/trás (flags=2, z-aware); leitura speed+placa (só UI); toggle X (**early-return em aeronave**) / lock K; auto-open→REQ_RADAR (excl. aeronave via `isAircraft`); encaminha placa nova→PLATE_SCANNED `kind='ground'`; overlay passivo via SendNUIMessage; cleanup onResourceStop (A-07) |
| HAL client HELICAM | `client/helicam.lua` | heli-câmera NATIVA (FLIR): cam scriptada presa ao heli; zoom (scroll 14/15) / look (1/2) / visão normal-NV-thermal / holofote (local) / lock raycast síncrono z-aware → placa → PLATE_SCANNED `kind='air'`; HUD passivo delta+throttle; loop único idle-zero gated em `active` (L-06); toggle X (só em heli via `canOperate`); cleanup completo (RenderScriptCams off + DestroyCam + NV/thermal off) em closeCam + onResourceStop (A-07) |
| HAL client policial | `client/police.lua` | thefeed NOTIFY; BOLO_ALERT → thefeed+som+blip temporário cap8+cleanup onResourceStop. (radar e helicam têm threads próprias; sem radar/keybind aqui) |
| NUI dispatcher (L3) | `web/app.js` | DISPATCHER mínimo SEM engine: `LSPD.register(name,spec)` + `_route` por prefixo de `m.type`; 1 listener central + `unload`→remove listener + `_destroyAll` (A-07) |
| NUI shared (L3) | `web/core.css` | tokens `:root` (sand/gold/glass) + reset; `background:transparent` (CEF) |
| NUI módulo RADAR (L4) | `web/modules/radar/{radar.css,radar.js}` | overlay PASSIVO do radar (migrado de `web/style.css`); `pointer-events:none`; `onMessage(radar:*)`; comportamento idêntico ao LSPD-5 |
| NUI módulo HELICAM (L4) | `web/modules/helicam/{helicam.css,helicam.js}` | HUD passivo da câmera; `pointer-events:none`; `onMessage(helicam:*)` (zoom/alt/hdg/vision/spot/lock/target) |
| Schema | `sql/schema.sql` | `vhub_lspd_scans` + `vhub_lspd_bolos`; FK INT UNSIGNED → vh_users.id ON DELETE SET NULL; idx_active_plate |

**Exports públicos:**

| Export | Proteção | Assinatura |
|--------|----------|------------|
| `reportPlate` | `invokerAllowed()` (trusted whitelist) | `(src, plate, opts) → bool` |
| `getRecentScans` | `invokerAllowed()` (trusted whitelist) | `(limit) → []scan` — DEVE ser chamado dentro de `Citizen.CreateThread` |
| `addBolo` | `invokerAllowed()` (trusted whitelist) | `(plate, reason, opts) → bool` |
| `removeBolo` | `invokerAllowed()` (trusted whitelist) | `(plate) → bool` |
| `checkBolo` | `invokerAllowed()` (trusted whitelist) | `(plate) → bolo\|nil` |
| `listBolos` | `invokerAllowed()` (trusted whitelist) | `() → []bolo` |

**Riscos residuais documentados (pós LSPD-3):**
- `getRecentScans` export: `Citizen.Await` sem `assertThread()` — caller fora de thread crasha; documentado no comentário mas sem fail-fast em runtime. Herdado de LSPD-2 (não corrigido nesta sprint). A corrigir em LSPD-4.
- `_dedup` sem cap absoluto de tamanho: GC lazy por chamada limpa TTL expirados; sem teto de entradas simultâneas. Aceitável em escala GTARP normal.
- `vhub_lspd_bolos`: sem `UNIQUE KEY (plate, active)` no schema — duplicate BOLOs por placa são prevenidos apenas pela cache VRAM. Se o banco for manipulado manualmente com dois registros `active=1` para a mesma placa, `loadAll()` sobrescreve o anterior (sem crash, sem dado perdido, mas sem alerta). Risco baixo, aceitável.
- Radar (`client/radar.lua`): loop único `while running do` + `Wait` adaptativo — guard `running` desliga em `onResourceStop` (L-06 ok). A thread de radar em `client/police.lua` foi REMOVIDA (migrou p/ radar.lua); sem double-listener.
- **`cfg.radar.anyVehicle = true` é flag de TESTE** (`shared/config.lua`) — abre o radar em QUALQUER veículo/heli, não só classe 18. **DEVE ser `false` em produção** (auto-open só em viatura policial). Não é regressão de segurança (a placa client é só UI; `processScan` valida `canScan` server-side independente da classe), mas é UX/produção-pendente. Trocar antes do go-live.
- Overlays do radar e do helicam (`web/modules/*`) são passivos standalone (`pointer-events:none`, sem NuiFocus) e o `web/app.js` é DISPATCHER mínimo SEM engine (`vhub.createModule`/router/store ausentes — decisão do arquiteto). A-01..A-08 satisfeitos pela forma mais simples correta (1 listener central + `_destroyAll` no unload + dedup/throttle no Lua). Não evoluir para engine sem necessidade real (LSPD-7/MDT pode reavaliar se a UI ganhar interatividade/foco).
- **`cfg.client.forwardAirScans` REMOVIDA em LSPD-7** (era config morta flagada no gate LSPD-6) — o helicam decide o encaminhamento aéreo pelo seu próprio `cfg.helicam.autoAirScan`. Único emissor de `kind='air'` é `attemptLock` em `client/helicam.lua`. Limpeza concluída; sem impacto funcional.
- **Conflito de keybind F7 (LSPD-7)** — F7 é o DEFAULT de `RegisterKeyMapping` em 3 resources: `vhub_groups` (painel admin), `vhub_racha` (painel corrida) e `vhub_lspdtool` (MDT). No FiveM cada keymapping é independente e rebindável em Settings → Key Bindings, então NÃO há erro de runtime, mas o default de fábrica dispara os 3 comandos juntos (UX ruim out-of-the-box). Não-bloqueante (rebind resolve; o MDT só abre para quem o servidor confirma policial). `vhub_admin` usa F6 (sem colisão). Sugestão futura: escolher tecla default livre p/ o MDT.
- **Corrida benigna de reabertura do MDT (LSPD-7)** — se o policial fecha o MDT (F7/Esc) entre clicar "+BOLO"/"✕" e a resposta `MDT_DATA` chegar, o cliente reabre o painel (re-concede foco). Mesmo painel do próprio usuário autorizado; sem vazamento de dados nem foco preso (Esc/F7 fecham de novo). Risco baixo aceito.
- **Helicam — pendências de runtime (LSPD-6)**: confirmar em FXServer dentro de heli — slew yaw/pitch, zoom por scroll (14/15), ciclo de visão NV/thermal, holofote, lock por raycast em ângulo íngreme (z-aware), placa → BOLO via `kind='air'`, e cleanup ao sair do heli / parar o resource (cam destruída, NV/thermal off, radar do mapa restaurado). Coexistência X: validar que em viatura terrestre o auto-open ainda abre e que em heli o radar NÃO abre.

| Sprint | Foco | Status |
|--------|------|--------|
| SPRINT-LSPD-1 | Bridge server-authoritative (autorização, anti-flood, dedup, BOLO, dispatch, auditoria) | ✅ Aprovado — gate revisao 2026-05-31 |
| SPRINT-LSPD-2 | `assertThread()` em `getRecentScans`; cap em `_dedup`; smoke tests documentados | ⏳ Absorvido em LSPD-3 (parcial) — assertThread pendente |
| SPRINT-LSPD-3 | BOLO+dispatch nativos vHub; alerta com blip; remoção l2s-dispatch | ✅ Aprovado — gate revisao 2026-05-31 — pendente: smoke tests runtime |
| SPRINT-LSPD-4 | `assertThread()` em `getRecentScans`; UNIQUE constraint em vhub_lspd_bolos; smoke tests | ⏳ Pendente |
| SPRINT-LSPD-5 | Radar NATIVO (`client/radar.lua` + overlay `web/`); reversão parcial de LSPD-1; remoção escrow `sd-policeradar` + `client/hooks.lua` + spike `web/` rogue; LOS síncrono z-aware | ✅ Aprovado — gate revisao 2026-06-04 — pendente: runtime (LOS frente/trás, auto-open, BOLO via radar) + `anyVehicle=false` |
| SPRINT-LSPD-6 | Helicam NATIVO (`client/helicam.lua`: cam scriptada/zoom/visão/holofote/lock raycast→`kind='air'`) + reorg modular da `web/` (dispatcher SEM engine `app.js`/`core.css`; radar migrado p/ `modules/radar`; novo `modules/helicam`; `web/style.css` deletado) + coexistência X (radar=solo via `isAircraft`, helicam=heli via `canOperate`); server INTOCADO; `VHubLspd.UI` aditivo | ✅ Aprovado — gate revisao 2026-06-04 — pendente: runtime (helicam: slew/zoom/visão/holofote/lock/BOLO aéreo/cleanup; coexistência X terrestre↔heli) |
| SPRINT-LSPD-7 | MDT/Central de Despacho NATIVO (`server/mdt.lua`+`client/mdt.lua`+`web/modules/mdt`): 1º módulo NUI INTERATIVO (foco via Lua); reusa domínio BOLO (sem 2ª fonte); server/main+bolo INTOCADOS; contrato aditivo; `forwardAirScans` morto removido | ✅ Aprovado — gate revisao 2026-06-04 — pendente: runtime (F7 abre só p/ policial; criar/remover BOLO reflete em /bolos+radar; scans recentes; Esc/F7 fecham e devolvem foco; conflito F7 groups/racha) |

> **ÉPICO COMPLETO (2026-06-04):** suíte `vhub_lspdtool` 100% nativa vHub — os 3 escrow originais (radar=`sd-policeradar`, helicam, dispatch=`l2s-dispatch`) substituídos por implementação própria server-authoritative. LSPD-5 (radar) + LSPD-6 (helicam) + LSPD-7 (MDT) ✅. Pendências remanescentes = validação runtime + housekeeping (LSPD-2/4: `assertThread` em `getRecentScans`, UNIQUE em `vhub_lspd_bolos`, `anyVehicle=false` em produção).

### vhub_velo (resource externo — `resources/[SCRIPTS]/vhub_velo`)

**Decisão de arquitetura (2026-06-05 — épico VELO-1/2/3/4 — SEPARAR):** o velocímetro foi EXTRAÍDO do `vhub_vehcontrol` para um resource próprio. **`vhub_velo` é o DONO ÚNICO do HUD de display do veículo** (velocímetro/odômetro/marcha/fuel/setas/cinto/trava/bússola); o `vhub_vehcontrol` cede o velocímetro e fica só com controle + cinto + sync vEnter/vLeave. **Há só UM velocímetro na tela** (o escolhido pelo jogador). Aprovado: arquiteto (plano SEPARAR; VELO-3 APROVAR; personalização REDUZIR_ESCOPO→aplicado; template APROVAR) + runtime 10/10 + designer 9/10 + seguranca APROVAR (fix do terminador CSS aplicado) + gate revisao (este).

**Invariante L-04 (consumidor puro):** `vhub_velo` **SÓ LÊ** — bags `vh_fuel`/`vh_odo`/`vhub_seatbelt` (leitura) + natives efêmeros + `vHub:vehicleStateLoad`. **NUNCA escreve bag, `setVData`, nem TriggerServerEvent de mutação** (verificado linha-a-linha em `client/main.lua`). O odômetro de EXIBIÇÃO integra local sempre (base = `vehicleStateLoad`/bag como PISO, nunca override; nunca persiste). KVP (`SetResourceKvp`) é usado SÓ para preferência de UI client-side (dado não-crítico, L-02). Cinto = dono é o `vhub_vehcontrol` (velo só lê o statebag `vhub_seatbelt`). Sem `server_scripts` (sem servidor).

| Módulo | Arquivo | Responsabilidade canônica |
|--------|---------|--------------------------|
| Config | `shared/config.lua` | `Config.VehicleCategories` (classe GTA→carro/moto/aero), `Config.Huds` (galeria, paths reais: carro/vrm_classic, moto/velo_moto_defaut, aero/helicoptero_defaut), `Config.DefaultHuds` |
| Client (L2/HAL) | `client/main.lua` | PURO CONSUMIDOR: loop adaptativo (80/350ms, `running` guard L-06) lê bags+natives → `velocimetro:update` (dedup + heading threshold 2°); categoria→`loadCategory`; `/velo` galeria (foco só ao abrir); KVP (HUD id + bg + accent, por categoria); sanitização da personalização (URL http(s)+extensão imagem+sem char que quebre CSS `url()`; cor hex); cleanup onResourceStop (foco+toggle) |
| NUI host (L3) | `nui/index.html` + `nui/velo-controller.js` | host IIFE com 1 iframe ISOLADO (`pointer-events:none`) + galeria glass/areia/dourado; roteia `velocimetro:loadHud/toggle/update/config/openConfig`; render DOM SEGURO (`textContent`/`createElement`); `fetch` só em ação do usuário (A-06); reaplica config+último update no `frame.onload` |
| NUI engine (L3 lib) | `nui/velo-core.js` | engine UNIVERSAL (porte de `vhub_vehcontrol/script-velocimetro.js`): gauges binary-search O(log n); odômetro RAF **GATED por `state.active`** (auto-termina quando inativo → idle ~0, satisfaz A-07 sem `onDestroy` formal — lib em iframe, não módulo `createModule`); `normalize` null-safe; `applyConfig`→CSS vars `--velo-bg`/`--velo-accent`; preview fora do FiveM. Incluído por TODA HUD via `../../velo-core.js` |
| NUI HUDs (L4) | `nui/huds/<cat>/<pasta>/` | 3 HUDs no contrato `velocimetro:update`: carro/vrm_classic (usa as vars de personalização), moto/velo_moto_defaut, aero/helicoptero_defaut |
| NUI template | `nui/huds/_template/` | template de produção (FORA de `Config.Huds` → não aparece na galeria) + README = guia de linha de produção de HUD |

**Contrato NUI (aditivo, não quebra nada):**
- `velocimetro:update { speed_kmh, rpm_percent, gear_label, fuel_percent, odometer_km, turn_left/right, seatbelt, locked, heading, visible, active }` — Lua→host→iframe.
- `velocimetro:config { bg, accent }` — ADITIVO (VELO-4); só seta CSS vars, HUD que não usa ignora.
- `velocimetro:loadHud/toggle/openConfig` — host↔Lua.
- NUI callbacks: `velo:closeConfig`, `velo:saveHud`, `velo:saveConfig`.
- KVP namespace: `vhub_velo:<cat>`, `vhub_velo:bg:<cat>`, `vhub_velo:accent:<cat>` — escopo per-resource (FiveM), sem colisão com qualquer outro resource.

| Sprint | Foco | Status |
|--------|------|--------|
| VELO-1/2 | Reorganizar `vhub_velo` (config paths reais; manifest sem server fantasma; client consumidor puro; engine portado `velo-core.js`; host 1 iframe + galeria; 3 HUDs) | ✅ Aprovado — gate revisao 2026-06-05 — pendente validação runtime |
| VELO-3 | Remover velocímetro do `vhub_vehcontrol` (4 arquivos + `<main>` + 4 refs no fxmanifest); controle/cinto/vEnter intactos | ✅ Aprovado — gate revisao 2026-06-05 — verificado: zero ref de código residual (só comentários) |
| VELO-4 | Personalização (`velocimetro:config` bg/accent → CSS vars; KVP; galeria "Personalizar"; sanitização) + template de produção | ✅ Aprovado — gate revisao 2026-06-05 — pendente validação runtime |

**Pendência:** validação runtime in-game — 1 só velocímetro aparece; troca de HUD por categoria (carro/moto/aero); `/velo` abre galeria e devolve foco; personalização (fundo por link + cor) aplica ao vivo e persiste no KVP; odômetro conta e usa o bag como piso; fuel do velo == fuel do painel `vc-fuel` (mesmo bag); cinto reflete a tecla G do vehcontrol.

---

### vhub_conce / vhub_ferinha (resources de veículo — reorg 2026-06-03)

**Boot order (resources.cfg):** `... money → ... inventory → vhub_conce → vhub_ferinha → vhub_garage → vhub_admin`. conce antes de ferinha antes de garage — exports registrados em file-load garantem disponibilidade no consumidor seguinte; chamadas cross-resource envolvidas em `safe(pcall)` em conce/ferinha core.

| Resource | Módulo | Responsabilidade canônica |
|----------|--------|---------------------------|
| vhub_conce | `server/sql.lua` | Escritor único `vhub_vehicles`/`_keys`/`_stock` + espelho `vh_vehicles`. `updateOwner` (chamado SÓ por `Core:transferOwner`) |
| vhub_conce | `server/core.lua` | `canOperate` (chave-item + dono/autorização), `transferOwner` (atômico char_id + revoke owner antigo + grant owner novo), `newPlate`, `returnExpiredHoldings` (cron 24h), sessões próprias via `vHub:characterLoad` |
| vhub_conce | `server/dealership.lua` | buy/sellToShop/testDrive (retornam `{ok,msg}`; garage delega e fala com NUI) |
| vhub_conce | `server/init.lua` | `backfillMirror` + `backfillOwnerKeys` no boot; cron 24h (`while _running` + `Wait(cron_interval_ms)` + lote `Wait(0)`, L-06 ok) |
| vhub_ferinha | `server/sql.lua` | Escritor único `vhub_auctions`/`_bids` |
| vhub_ferinha | `server/auction.lua` | escrow VRAM `Escrow[id]`, lock cooperativo `Busy[id]`, finalize/bid/cancel, `finalizeExpired` (cron), `reconcileOrphans` (boot) |
| vhub_ferinha | `server/core.lua` | integração money/inventory/conce; `payChar`→`giveBankChar` (offline-safe); `transferOwner`→`conce` |
| **vhub_vehcontrol** | `server/main.lua` | controle de veículo (trava/motor/luzes/banco/câmera) + **elo de ciclo de vida físico**: autoriza (chave/dono) e aciona `Vehicle:onEnter`/`onLeave` no CORE. NÃO escreve `setVData` (CORE é escritor único de `vh_vehicle_data 'state'`). Anti-flood `vEnter` 500ms + collision-guard `_byNet` |
| **vhub_vehcontrol** | `client/main.lua` | detecta motorista → envia `vEnter` (retry+ack cap 5) / `vLeave`; cinto/crash-eject; `_running` guard (L-06). Sem handler `applyPhys` (removido). **Cinto = DONO ÚNICO** da verdade (tecla G → escreve o statebag local `vhub_seatbelt`; o velo só lê) |
| **vhub_vehcontrol** | `client/main.lua` (dashboard) | painel `vc-panel` (NUI `html/`) só com barra de combustível própria (`updateFuel`): LÊ o MESMO bag `vh_fuel` do CORE (leitura independente, **NÃO é 2ª fonte** — mesma origem que o velo, com fallback ao native sem registro vHub). **Velocímetro REMOVIDO daqui (VELO-3 2026-06-05) — migrou para `vhub_velo`** (`client/velocimetro.lua`, `html/script-velocimetro.js`, `html/style-velocimetro.css`, `html/dashboard_fivem.svg` deletados; `<main id="velocimetro">` + 4 refs no fxmanifest removidos) |

**Invariantes auditadas (2026-06-03; vehcontrol 2026-06-04) — não quebrar:**
1. `char_id` em `vhub_vehicles` escrito SÓ por `conce:transferOwner` (todos os call-sites: garage P2P, `forceTransfer`, admin transfer, ferinha finalize → passam por ele).
2. `vhub_vehicles`/`vhub_vehicle_keys`/`vhub_dealership_stock` mutados SÓ em `vhub_conce/sql.lua`.
3. `vhub_auctions`/`vhub_auction_bids` mutados SÓ em `vhub_ferinha/sql.lua`.
4. `vhub_vehicle_log` é log append-only compartilhado (conce/garage/ferinha inserem; admin purga) — NÃO é fonte de verdade.
5. Garagem lista por chave-item (`inventory:getVehicleKeys`), nunca por `char_id`.
6. `vh_vehicle_data 'state'` (físico: fuel/eng/body/odo) tem CORE como ESCRITOR ÚNICO (autosave). `vhub_vehcontrol` só aciona `onEnter`/`onLeave` (não escreve). `legacyfuel`/`garage`/`conce` chamam `setVData(plate,'state',vd.state)` mas sobre o MESMO objeto `vd` do CORE (save-triggers, não 2ª fonte). O velocímetro só LÊ (bags/`vehicleStateLoad`). NUNCA reintroduzir `setVData` com objeto `vd` próprio/clonado.

**Riscos residuais documentados (reorg veículos):**
- **Cadeia física AGORA VIVA mas pendente de validação runtime (FASE 5 parcial)**: o typo `@dkey`→`@key` (decisão #20) e o elo `vEnter` do vehcontrol (decisão #21) reanimaram `getVData/setVData` e o autosave físico. **Antes desta janela o path inteiro era no-op silencioso** — logo "/fuel zera no apply" e "odômetro não conta" SÓ podem ser confirmados/refutados em RUNTIME (FXServer + entrar/dirigir/sair + /fuel + restart→reentrar). D1 (fuel com 3 save-triggers sobre o mesmo `vd.state`) não é mais 3 fontes divergentes (é 1 objeto), mas a ORDENAÇÃO de escrita entre triggers concorrentes na mesma key por flush é agora ativa — observar se há valor pisado inesperado. Restante de FASE 5 (reparo, absorção completa de HUD) segue pendente.
- **Escrow de leilão volátil mas blindado**: offline-credit + `reconcileOrphans`. Resta a janela ínfima lance↔crash (entre `Escrow[id][cid]=amt` e o commit de `add_bank_offline` num crash exatamente no meio) — risco baixo aceito.
- **Chave-item órfã de não-dono offline pós-cron**: o cron 24h só remove a chave-item se o portador estiver online (`srcByCharId`); offline a linha de autorização é revogada (fail-closed: garagem não lista, `canOperate` falha em `hasValidKey`), mas a chave-item física resta no inventário até limpeza no login (deferida).
- `give_bank_char` reload reaplica só `wallet/bank/dirty`; `total_in/out` da entry viva não re-sincroniza (drift de métrica agregada, sem impacto em saldo — `add_bank_offline` já bumpa `total_in` no DB).

| Sprint/Fase | Foco | Status |
|-------------|------|--------|
| FASE 0 | Limpeza órfãos (spawnmanager, .bak, #ensure morto) + criar conce/ferinha (L-07) | ✅ Aprovado |
| FASE 1 | conce escritor único de chave↔placa↔dono; garage SQL = proxy; `authorized`→`canOperate` | ✅ Aprovado (arquiteto+contrato+simplicidade) |
| FASE 2 | Concessionária → conce; catálogo `conce/shared/catalog.lua`; garage = delegator | ✅ Aprovado (contrato+simplicidade) |
| FASE 3 | Garagem por chave-item + self-heal + backfillOwnerKeys + cron 24h | ✅ Aprovado (seguranca+performance) |
| FASE 4 | Leilão → ferinha (escrow+finalize+cron+reconcile); `transferOwner` único escritor char_id; hardening crédito offline | ✅ Aprovado — gate revisao 2026-06-03 — pendente validação runtime |
| FASE 5 | Consolidar vehcontrol (HUD/velocímetro/fuel/reparo); resolver D1 fuel; absorver vrm_velocimetro | 🟡 PARCIAL (2026-06-05) — `vhub_vehcontrol` criado (L-07); `vrm_velocimetro` absorvido+deletado; elo `vEnter` + hotfix CORE #20 reanimam a cadeia física; single-writer reconciliado (#21). **VELO (2026-06-05): velocímetro EXTRAÍDO para resource próprio `vhub_velo` (dono único do HUD; consumidor puro) — VELO-1/2/3/4 ✅; ver seção `vhub_velo`. vehcontrol = só controle+cinto+sync.** Pendente: validação runtime de /fuel+odômetro+reparo+velocímetro único |
| FASE 6 | garage enxuto + remover proxies/delegators + migrar DDL para donos | ⏳ Pendente (cosmético) |

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

### vhub_inventory — exports públicos

| Export | Proteção | Assinatura |
|--------|----------|------------|
| `getInventory` | pública | `(src) → { slots, weight, max, size }` |
| `getItemAmount` | pública | `(src, id) → number` |
| `hasItem` | pública | `(src, id, qty) → bool` |
| `getInventoryWeight` | pública | `(src) → number` |
| `getItemDef` | pública | `(id) → def\|nil` |
| `getItemName` | pública | `(id) → string` |
| `hasVehicleKey` | pública | `(src, plate) → bool` |
| `getVehicleKeys` | pública | `(src) → []plate` |
| `giveItem` | `_invoker_allowed()` | `(src, id, amount, meta) → bool` |
| `takeItem` | `_invoker_allowed()` | `(src, id, amount) → bool` |
| `registerItemUse` | `_invoker_allowed()` | `(id, fn) → bool` |
| `openContainer` | `_invoker_allowed()` | `(src, desc) → bool` — desc = `{ kind, name\|group\|netId }` |
| `giveVehicleKey` | `_invoker_allowed()` | `(src, plate) → bool` |
| `takeVehicleKey` | `_invoker_allowed()` | `(src, plate) → bool` |

**Eventos canônicos (VHubInvE):** `vhub_inventory:open/close/delta/rollback/notify/container_open/container_delta/container_close/use/move/drop/pickup/p2p/store/retrieve/open_container/close_container/request_sync/hud_req/hud`

**NUI callbacks canônicos:** `nui_ready`, `close`, `use`, `move`, `container_close`, `store`, `retrieve`

**SendNUIMessage actions canônicos:** `open`, `close`, `delta`, `rollback`, `notify`, `container_open`, `container_close`, `container_delta`

---

### vHub.getUData / setUData / getCData / setCData / getVData / setVData / getGData / setGData
- Assinatura: `(id, key [, value [, tx]])` — estável
- Exige `Citizen.CreateThread` no chamador (usa `Citizen.Await` internamente via assertThread)
- **`getVData`/`setVData` ESTAVAM MORTOS desde o freeze por typo `@dkey` (decisão #20); corrigidos em 2026-06-04 — assinatura inalterada, comportamento agora VIVO.** Bind de chave é sempre `key` (nunca `dkey`).

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

### exports do resource `vhub_conce` (todos `_invoker_allowed`; trusted: vhub, vhub_garage, vhub_ferinha, vhub_admin, vhub_inventory)
| Export | Assinatura |
|--------|-----------|
| `canOperate` | `(src, plate) → bool` |
| `isOwner` | `(src, plate) → bool` |
| `transferOwner` | `(plate, new_cid) → bool` — ÚNICO escritor de `char_id` |
| `plateExists` / `getVehicle` / `listByOwner` / `listByStatus` | leitura de `vhub_vehicles` |
| `createVehicle` / `updateStatus` / `updatePosition` / `updateCustomization` / `updateIpva` / `updateRental` / `deleteVehicle` | escrita `vhub_vehicles` (+ espelho `vh_vehicles`) |
| `grantKey` / `revokeKey` / `hasValidKey` / `listKeys` / `listKeysOfChar` / `purgeExpiredKeys` | `vhub_vehicle_keys` |
| `stockGet` / `stockSet` / `stockDecrement` | `vhub_dealership_stock` |
| `getCatalog` | `() → catálogo` (garage cacheia no boot) |
| `buy` / `sellToShop` / `testDrive` | `(...) → {ok,msg}` (garage delega + fala com NUI) |

### exports do resource `vhub_ferinha` (todos `_invoker_allowed`; trusted: vhub, vhub_garage, vhub_admin, vhub_conce)
| Export | Assinatura |
|--------|-----------|
| `listActiveAuctions` | `() → []auction` |
| `getAuctionByPlate` | `(plate) → auction\|nil` |
| `newAuction` | `(src, plate, min_bid, buyout, dur_min) → {ok,msg}` |
| `bid` | `(src, auction_id, amount) → {ok,msg}` |
| `cancelAuction` | `(id, actor_cid) → bool` |
| `finalizeExpired` | `() → count` |

### exports do resource `vhub_money` (mutadores `_invoker_allowed`; trusted += `vhub_ferinha`)
| Export | Assinatura | Proteção |
|--------|-----------|---------|
| `giveBankChar` | `(char_id, valor, reason) → bool` — credita banco ONLINE ou OFFLINE (offline-safe; fecha race de login) | `_invoker_allowed()` |

> Contratos do `vhub_garage` mantidos via proxy/delegator (decisão #18): `getVehicle`, `listOwnerVehicles`, `isImpound`, `ipvaUntil`, `forceTransfer`, `forceImpound` — assinaturas inalteradas (consumidos por `vhub_inventory`, `vhub_admin`).

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
- **Hotfix persistência veicular (decisão #22): VALIDAÇÃO RUNTIME (BOOT OK, AGUARDANDO FLUXO IN-GAME)** — Boot do FXServer 2026-06-11 OK; MySQL seeds capturados; `vhub_run_tests` (`test_vdata_roundtrip` + `test_blob_armor_roundtrip`) pendente; fluxo in-game (dirigir→guardar→restart→spawnar: fuel/mods/odômetro/posição) aguardando jogador online + resmon do flush (L-18).

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
