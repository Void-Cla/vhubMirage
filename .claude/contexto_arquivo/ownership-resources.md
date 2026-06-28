# Arquivo — Ownership por resource externo (detalhe)

> Recorte de `contexto.md`. Carregar SOB DEMANDA por resource. Resumo de uma linha por resource vive em `contexto.md`.

## Ownership por resource externo

### vhub_login (resource externo — `resources/[SCRIPTS]/vhub_login`) — decisão #36

| Módulo | Arquivo | Responsabilidade canônica |
|--------|---------|--------------------------|
| **Credencial (ESCRITOR ÚNICO)** | `server/dominio/contas.lua` | **dono único da tabela `login_accounts`** (username/senha SHA2+salt per-conta, FAIL-CLOSED por uid); `exports.oxmysql` direto (#8); NUNCA loga senha |
| Fluxo | `server/dominio/fluxo.lua` | máquina de estados da sessão (login→charselect→spawning); DELEGA multichar ao CORE (`Auth:getCharacters`/`selectCharacter`); NÃO toca ped/bucket/coord |
| Gate + net | `server/init.lua` | intercepta `vhub_player_state:chooseSpawn`; rate-limit por-src; deadline 120s→DropPlayer; export `isGateActive` (ungated, p/ o selector ceder) |
| Exports | `server/api/exports.lua` | export-first default-deny (`isAuthenticated`/`getAccount`/`getSessionStep`; `login_trusted={}` vazio); nunca expõe hash/salt |
| Cliente | `client/main.lua` | bridge NUI (L2/L3); abre/fecha NUI + relay ao server; handoff ao selector via `RequestOpen` (preserva `_pending`/hold); watchdog 6s; `onResourceStop` solta focus (A-07) |
| NUI | `ui/{index.html,css/style.css,js/app.js}` | Mirage liquid glass; A-09 (#bg opaco) + A-10 (assets no `files{}`) + textContent anti-XSS |

**Estado**: `enabled=false` no merge — resource INERTE (não intercepta o spawn). ÚLTIMO passo de ativação = o dono virar `Config.enabled=true` (`config/config.lua`) APÓS runtime-validate. **Dependência operacional (fail-open)**: o gate só dispara com `vhub_spawselector` `started`; selector parado com gate ligado = player entra sem credencial — resolver/documentar no runbook antes do enable (ver risco ativo abaixo + #36). **Ponte criador** (`requestCreate`→`createUnavailable`) = stub consciente até existir `vhub_charcreator`.

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

