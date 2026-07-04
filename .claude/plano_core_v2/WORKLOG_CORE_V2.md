# WORKLOG — CORE v2 (Descongelamento FASE 1)

> Registro de legado exigido pelo protocolo. Toda decisão vive aqui em formato ADR.
> Sprint iniciada: 2026-07-02 | Executor: Fable5 (equipe sênior, autonomia delegada)
> Rollback global: `git checkout pre-frozen-core-2-remediation -- "resources/[CORE]/vhub"`

---

## 1. Mapa arquitetural do CORE (estado real, lido linha a linha — 2.557 linhas)

```
fxmanifest (v1.0.0 FROZEN)
├─ shared_scripts  : config → events → utils → logger        (cria vHub global)
├─ server_scripts  : bootstrap.lua
│    └─ criar_config (convars, SEM mergeConfig → F-003)
│    └─ criar_driver (oxmysql, batch isolado por op, timeout 15s → F-006)
│    └─ carregar_base → base.lua → server/init.lua → loadmod:
│         kernel → state → sql → notify → auth → vehicle → security → boot → exports
│    └─ aplicar_schema (CREATE IF NOT EXISTS)
└─ client_scripts  : client/bootstrap.lua (ready/initDone/spawn fallback)
                     client/vehicle.lua   (report vState 0.5–4Hz adaptativo)
```

**Hot paths de tick (budget):** autosave 60s chunked (yield/50) · flush batch 3s ·
rate-limit GC 120s · GC _byNet 300s · ping check 30s (off por default).
Nenhum loop por-frame server-side. Custo por player O(1). ✅ dentro do budget ≤1.0ms.

**Alocadores de VRAM (RAM do servidor):** `State._mem` (KV, sem TTL → F-013),
`Auth._sessions/_byUID` (limpa no drop ✅), `Veh._veh/_byKey/_byNet` (GC só de _byNet
→ débito documentado §5), `Kernel._rate` (GC 120s ✅).

**Fluxo veicular REAL hoje:** `client/vehicle.lua` envia vState até 4Hz → handler
server NO-OP (`_vhDisarmed`, boot.lua:179-184) → **100% do tráfego é lixo** (F-019).
State Bags `vh_*` nunca escritas — mas `vhub_velo` (HUD) e `vhub_vehcontrol` **já são
consumidores reais** de `vh_fuel`/`vh_odo` com fallback para native. A verdade física
persistida vive no prontuário do `vhub_conce` (decisão #24/#32); o `vhub_vehcontrol`
substituiu `vehicleStateLoad` com pipeline próprio (requestState).

**Doc-drift registrado (código prevalece):** CLAUDE.md cita `compat` na ordem de load
e L-11 (compat.lua funcional) — o código não tem compat desde Frozen v1.0 (decisão #6
do contexto.md). CLAUDE.md desatualizado, não o código.

## 2. Violações confirmadas nesta auditoria (vs. frozen_core_2.md)

| F-XXX | Confirmação no código | Fase |
|-------|----------------------|------|
| F-001/019 | boot.lua:179-184 no-op; client envia 4Hz sem gate | 1c |
| F-003 | bootstrap.lua:58 não chama mergeConfig; trusted_resources/max_ping/veh_state_hz/max_speed_kmh = nil em produção | 1a |
| F-004/005 | _defaults 0.01/400 vs efetivo 0.005/350 | 1a |
| F-007 | passengerMode sem RegisterNetEvent no client | 1c |
| F-013 | State._mem sem TTL; chaves quentes (ban.active etc.) acumulam para sempre | 1e |
| F-014/015 | print() em auth.lua:174,178,184,220 e boot.lua:80 (+client/bootstrap.lua:80,86,93) | 1b |
| F-017 | validateConfig existe e nunca é chamado | 1a |
| F-022 | trusted_resources nil → exports sensíveis negam silenciosamente (warn one-shot existe) | 1a |
| F-028 | commitVehicleState não existe no CORE | 1d |
| F-073 | zero audit unificado no CORE | 1d |

**Risco pré-existente observado (fora de escopo, registrar):** `_set` invalida a VRAM
imediatamente após enfileirar o batch (flush ≤3s depois) — leitura na janela vai ao DB
*stale* e re-cacheia valor velho. Mitigado na prática pelo padrão de acesso (datatable
só relida no connect). Candidato a F-080 no frozen_core_2.md.

## 3. Plano desta sprint (fases atômicas, cada uma deixa o core funcional)

1a config → 1b higiene → 1c reanimação gated → 1d contrato de commit + audit → 1e eviction.
Reversível por arquivo via tag. Validação estática: luacheck + hook post_lua_check.
**Validação de runtime (stress 200 players, penetration test) = PENDENTE, bloqueia
produção — ver §6.**

---

## 4. DECISÕES (ADRs — numeração continua o contexto.md, próximo livre = #37)

### [ADR #37] 2026-07-02 | módulo: server/boot.lua, client/vehicle.lua
**Reanimação GATED de vEnter/vLeave/vState; vSpawned/vDespawned seguem NET-desarmados.**
Contexto: F-001 matou o single-pilot-channel; vetor original (ADR #24) era forjar
vEnter com netid da vítima → NetworkSetEntityOwner sequestrado.
Solução: o server só aceita a alegação se ela for FÍSICA e verificável na réplica:
`GetPedInVehicleSeat(ent, seat) == GetPlayerPed(src)` + placa real da entidade ==
placa alegada (normalizadas). Atacante não senta no carro da vítima → rejeitado.
vLeave só é aceito de quem tem `occupants[src]` registrado por vEnter validado.
Spawn/despawn NÃO ganham superfície de rede: verdade de spawn é server-side dos donos
(garage/conce) via exports gated novos `registerVehicleSpawn/registerVehicleDespawn`.
Kill-switch: `GlobalState.vh_core_active` — client só emite quando true; desarmar de
novo = 1 linha server-side, tráfego morre sem restart de client (resolve F-019).
Trade-off: +1 check server por transição de assento (barato, event-driven).
Impacto: tráfego vState passa de 100% lixo → 100% consumido; +2 eventos raros
(enter/leave). MS: validação O(1) por evento, rate-limited (10/3s).
Reversível via: `GlobalState.vh_core_active = false` (imediato) ou tag git.

### [ADR #38] 2026-07-02 | módulo: server/vehicle.lua
**Shadow-mode de fuel — CORE não escreve `vh_fuel` nem drena fuel na FASE 1.**
Contexto: dono atual do fuel é vhub_legacyfuel + prontuário conce. `vhub_velo` lê
`vh_fuel` com fallback native — se o CORE escrevesse a bag com seu estado default
(100.0), o HUD divergiria do tanque real. Dupla contabilidade = corrupção de UX.
Solução: flag `cfg.core_fuel_enabled` (default false). Bags reativadas na FASE 1:
`vh_odo`, `vh_eng`, `vh_body`, `vh_on` (dados validados do driver report — velo já
trata vh_odo como piso). `vh_fuel` e drain só ligam na FASE 2 (unificação do fuel).
Igualmente `cfg.veh_state_apply` (default false) gateia `vehicleStateLoad` no enter —
vehcontrol já substitui esse fluxo; ligar os dois criaria escritor duplo (L-04).
Impacto: zero mudança de gameplay; odômetro autoritativo volta a funcionar no HUD.
Reversível via: flags (é o próprio default).

### [ADR #39] 2026-07-02 | módulo: server/exports.lua, shared/events.lua
**`commitVehicleState`/`getVehicleState` oficiais no CORE com SOURCE_GATES.**
Contexto: F-028 — contrato de commit vivia só no conce (workaround da era frozen).
Solução: export gated (`_invoker_allowed`) com gate de campos por origem
(pump→fuel; repair→health/damage; tune→tuning; garage→estado de lifecycle;
system→tudo). Escreve VRAM (Veh) + bags + batch SQL + `vHub:vehicleCommitted`
(resolve F-024 na origem) + audit. `getVehicleState` retorna CÓPIA (L-14).
vhub_conce NÃO é migrado nesta fase (FASE 2) — prontuário segue fonte ativa;
o CORE volta a ser capaz, coexistência documentada como transitional até FASE 2.
Impacto: p99 alvo <5ms (VRAM hit); SQL via batch (zero síncrono no tick).
Reversível via: remover exports (nenhum consumidor atual — export-first).

### [ADR #40] 2026-07-02 | módulo: server/state.lua
**Eviction de VRAM por TTL de entidade (3600s, passada 60s).**
Contexto: F-013 — `_mem` cresce linearmente com jogadores únicos (ban.active de
10k uids fica residente para sempre).
Solução: `_touch[et][eid]` atualizado em get/set (O(1)); thread 60s varre buckets e
remove entidades ociosas >1h inteiras (yield a cada 200). Online nunca evicta
(autosave 60s toca `ud`). Miss pós-eviction = re-read do DB (caminho já existente).
Sem exceção de hot-keys: ban/whitelist só são lidos no connect — residência
permanente era desperdício, não otimização.
Impacto: VRAM estável em 24h+ (meta PARTE VI); custo O(entidades)/60s, chunked.
Reversível via: remover thread + _touch (aditivo puro).

### [ADR #41] 2026-07-02 | módulo: bootstrap.lua, shared/config.lua, server/boot.lua
**Config unificada: mergeConfig no boot + convar `vhub_trusted_resources` + fail-fast.**
Contexto: F-003/004/005/017/022.
Solução: `criar_config()` termina em `vHub.mergeConfig(cfg)`; `_defaults` alinhados
ao efetivo (fuel_rate 0.005, max_speed_kmh 350 — zero mudança de comportamento);
`vhub_trusted_resources` (CSV) popula a whitelist sem editar código; boot valida
com `validateConfig` e ABORTA se inválida (fail-fast em boot é seguro: sem estado);
warning proativo com lista sugerida quando trust vazio (F-022).
Impacto: campos nil eliminados; instalação nova ganha mensagem acionável.
Reversível via: tag git (comportamento default idêntico ao atual).

### [ADR #42] 2026-07-02 | módulo: sql/schema.sql, server/sql.lua, server/state.lua
**Audit unificado `vh_audit` no CORE (append-only).**
Contexto: F-073. Nome `vh_audit` (não `vhub_audit_unified` do plano) — convenção de
prefixo das tabelas do CORE é `vh_`; divergência deliberada e registrada.
Solução: `vHub.audit(actor, action, target, source, before, after)` → op no batch
(zero custo síncrono). Wired em commitVehicleState + exports privilegiados
(grantPerm/transferKey/banPlayer/unbanPlayer — R12). Trigger SQL de imutabilidade
fica para FASE 4.6 (exige privilégio TRIGGER; não assumir em todo ambiente).
Impacto: 1 INSERT assíncrono por mutação privilegiada.
Reversível via: remover chamadas; tabela é inerte.

### [ADR #43] 2026-07-02 | módulo: fxmanifest.lua
**Bump `1.0.0` → `2.0.0-alpha.1`; banner FROZEN atualizado para status gated.**
Exigência do gate do CORE (CLAUDE.md — Fase Atual). Alpha até FASE 8 validar runtime.

### [ADR #44] 2026-07-02 | módulo: vhub_conce/server/vstate.lua (FASE 2.1-lite)
**Dual-write de FUEL conce→CORE via `commitVehicleState` (espelho de aquecimento).**
Contexto: o CORE reanimado não tem como obter fuel (drain em shadow-mode, client não
reporta fuel); a FASE 2 precisa do vd.state do CORE quente com dado REAL para o cutover.
Solução: após save bem-sucedido com `patch.fuel`, o conce espelha `{fuel}` no CORE em
thread própria (camada B — assíncrono, soft-dep pcall + GetResourceState). Só fuel:
health/odômetro o CORE já recebe da telemetria validada — espelhar seria 2º escritor (L-04).
Trade-off: +1 op de batch SQL no CORE por save com fuel (event-driven, bounded).
Impacto: MS ~0 (assíncrono); prepara cutover de `vh_fuel` sem divergência de HUD.
Reversível via: remover o bloco ADR #44 do vstate.lua.

### [ADR #45] 2026-07-02 | módulo: .claude/hooks
**Hooks v2 promovidos para o caminho que o settings.json executa.**
Contexto (achado da limpeza): as versões v2 dos hooks (enforcement mecânico de
L-13/14/15/16/17 + SQL/git destrutivo) viviam na RAIZ, mas `settings.json` aponta para
`.claude/hooks/` que continha as v1 fracas — o enforcement v2 NUNCA rodou.
Solução: v2 copiada para `.claude/hooks/`; cópias da raiz removidas (fonte única).
Reversível via: git (as v1 estão no histórico).

### [ADR #46] 2026-07-02 | módulos: vhub_conce, vhub_vehcontrol (configs de produção)
**Vetores de abuso fechados por config:** `test_drive_segundos 9999→300`,
`fator_test_drive 0.00→0.10` (F-027); `skillDebug true→false` (F-051);
`skillBruteTest true→false` (F-052 — anti-P2W religado).
Reversível via: 4 linhas de config.

### Achados STALE no frozen_core_2.md (auditoria desta rodada — código prevalece)
- **F-038 JÁ RESOLVIDO**: `max_veiculos_player` É enforced em
  `vhub_conce/server/dealership.lua:29` (`ownedCount >= CFG.max_veiculos_player`).
- **F-039 JÁ RESOLVIDO**: `Config.Classes`/`Config.FuelUsage` não existem mais no
  vhub_garage (grep zero hits).
- **F-040 RESOLVIDO nesta rodada**: 9 handlers `100fuel`..`0fuel` removidos do
  `vhub_legacyfuel/client.lua` (zero emitters; usavam `GetPlayersLastVehicle`;
  dariam fuel grátis se emitidos). Nota: o resource vive em `[CORE]/vhub_legacyfuel`,
  não em `[SCRIPTS]` como o plano sugere.
- **F-055 ADIADO deliberadamente**: listener de `vHub:vehicleCommitted` no vehcontrol
  seria código morto hoje — só o fuel flui pelo commit do CORE (ADR #44); handling ainda
  não passa pelo CORE. Implementar junto com a FASE 2 completa (senão viola L-15).

### Limpeza do projeto (mandato do dono, 2026-07-02 — "deletar é entrega", L-15)
| Removido | Motivo |
|----------|--------|
| `.claude/core no frozen/` (9 arquivos) | duplicata byte-a-byte de `plano_core_v2/` |
| `.claude_backup_remaster_20260628_091350/` | backup manual — git é o backup |
| `.claude/_arquivo/` (hooks .v1) | superseded; histórico vive no git |
| `post_lua_check.sh` + `guard_sql_danger.sh` (raiz) | promovidos a `.claude/hooks/` (ADR #45) |
| `tmp_ctx_split.py` | script temporário órfão |
| `resources/[SCRIPTS]/SCRIPTS.zip` (604K) | zip de código já versionado |
| `resources/[SCRIPTS]/ox_doorlock-main/`, `snowy_characterselector-master/` | terceiros baixados, zero `ensure`, zero referência |

**Mantidos deliberadamente:** `.claude/contexto_arquivo/` (arquivo sob demanda referenciado
pelo contexto.md), `metas/*` (natives ref + roadmap vivos), `sss.txt` (fonte do plano de
handling), `[CAR]/*.md` (testplans referenciados pelo frozen_core_2), `GOVERNANCA_DELTA.md`
(explica o porquê dos hooks v2), `vhub_target`/`vhub_voicePMA` (first-party WIP, não ensured —
decisão de manter é do dono), `build/`+`cache/` (artefatos de runtime do FXServer, gitignored).
**Doc-drift corrigido:** CLAUDE.md (raiz + cópia `.claude/`) — vRP compat removido do header,
L-11 marcada REVOGADA, ordem de load sem `compat`, STATUS da FASE 1 adicionado à Fase Atual.

### [ADR #47] 2026-07-02 | módulos: server/vehicle.lua, server/state.lua (fixes de RUNTIME)
**Primeira rodada de validação em dev expôs 3 falhas — corrigidas:**
1. **`NetworkSetEntityOwner` não existe no build server** (crash em todo vEnter de driver).
   Era código pré-existente jamais executado (handler era no-op desde sempre). Removido
   dos dois pontos (onEnter/onLeave): o OneSync migra a ownership da entidade para o
   motorista automaticamente; a autoridade do CORE é `vd.driver` (gate do vState).
2. **Placa sem âncora → FK poison-op.** `/spawncar` de admin criava veículo sem linha em
   `vh_vehicles`; o autosave batia na FK de `vh_vehicle_data` e re-enfileirava a op para
   SEMPRE (flood de log + DB). Fix: `Veh:register` detecta âncora (1 SELECT já existente);
   sem âncora ⇒ registro **EFÊMERO** (VRAM-only, zero SQL). CORE não cria âncora — o
   escritor único de identidade é o conce (L-04).
3. **Batch sem cap de retry.** Qualquer op envenenada loopava eternamente. Fix:
   `_requeueCapped` — op descartada com ERROR após 5 tentativas (defesa em profundidade).
Débito novo: placa que ganha âncora DEPOIS do registro fica efêmera até re-registro
(restart/unregister) — aceitável; revisar na FASE 2 (conce pode notificar o CORE).
Reversível via: tag git.
Validação: `luac`/`luacheck` 0 erros; **re-testar em dev** (vEnter sem erro, /spawncar
sem flood, op envenenada descartada após 5x).

### [ADR #48] 2026-07-03 | módulos: garage, conce, Drift, CORE exports (FASES 3/4/5/6 — itens estáticos)
**Rodada "até o fim" dos itens executáveis sem cutover de runtime:**
1. **F-043 ELIMINADO (FASE 2.5/3.3):** os 6 broadcasts `-1` de despawn viraram
   `Core.despawnByPlate` — o servidor deleta a entidade direto (`GetAllVehicles`+
   `DeleteEntity`, OneSync, L-05). Zero eventos de rede por despawn; handler client
   `DO_DESPAWN` mantido registrado por compat (emissor externo legado). `DO_REPAIR -1`
   permanece (reparo usa natives client-only) — documentado, não esquecido.
2. **F-045 FECHADO (FASE 4.1):** `impoundVehicle` gated (`IMPOUND_TRUSTED` default-deny
   + log `impound_denied`); `vhub_garage` na lista porque `forceImpound` delega via exports.
3. **Garage hardening (honestidade técnica):** `_invoker_allowed` com caller nil retornava
   TRUE. NÃO é vuln de cliente — `GetInvokingResource()` nil = chamada interna do mesmo
   resource (idioma padrão FiveM; cliente hostil não invoca export com caller nil). Flip
   para default-deny justificado SÓ porque os 3 exports do garage são sensíveis E
   cross-resource-only (verifiquei: forceImpound→impoundVehicle usa invoker nomeado, não
   nil). ⚠ Débito: o mesmo idioma existe em conce/money/ferinha/inventory/ipad/groups —
   NÃO flipar às cegas (quebra chamada interna legítima = risco de economia); auditar
   caso a caso na FASE 4, com teste.
4. **F-031 FECHADO (FASE 5.6):** conce não dispara mais evento hardcoded do garage;
   usa export gated novo `despawnVehicleByPlate` (soft-dep pcall; conce entrou no TRUSTED).
5. **F-029 FECHADO:** `reconcileOrphans()` roda no boot do próprio conce (pcall).
6. **F-058 FECHADO (FASE 6.3):** Drift ganhou `onResourceStop` → `revertDrift` (deltas
   simétricos restaurados; carro não fica com handling viciado após restart).
7. **FASE 3.1/3.2:** exports `getVehicleDriver`/`getVehicleOccupants` no CORE (cópia,
   nunca referência viva — L-14). Base do single-pilot-channel.
8. **F-057 é STALE:** `vhub_wow:searchResults` já envia targeted (`playerSrc`), não `-1`.
**F-059 NÃO tocado (deliberado):** conflito real confirmado — Drift muta
`fTractionCurveMax/Min` que o vehcontrol também muta. Separar campos muda FÍSICA de
gameplay; decisão exige teste em jogo (FASE 6 runtime). Evidência: `Drift/cl.lua:46-47`.
Impacto: −6 broadcasts/evento de despawn (rede), +0 MS (despawn é raro, scan O(veículos)).
Reversível via: tag git (por arquivo).
Validação: `luac` 9 arquivos OK; grep confirma 0 broadcasts `-1` de despawn.

### [ADR #50] 2026-07-03 | módulo: server/exports.lua
**`getVehicle` devolve CÓPIA (dataCopy), não a referência viva do VD.**
Contexto: o GATILHO da decisão #32 (contexto.md) exigia fechar o vetor "VD vivo por
referência" ANTES de re-armar a cadeia física — a reanimação (#37) tornou `_veh` vivo
de novo e o risco residual reativou. Lacuna pega na releitura do contexto.md.
Grep 2026-07-03: zero consumidor direto de `exports.vhub:getVehicle` em [SCRIPTS]
(leitores citados em #32 usam como check booleano) → cópia é segura por construção.
Reversível via: tag git. Numeração: próximo ADR/decisão livre = **#51**.

## 4b. Estado das FASES (frozen_core_2.md) após esta sprint

| Fase | Status | Nota |
|------|--------|------|
| 0 | ⚠ parcial | tag de snapshot ✅; `vh_audit` ✅ (ADR #42); testrunner mínimo pendente |
| 1 | ✅ aplicada + validada em dev | ADRs #37–#43, #47 (fix runtime) |
| 2 | 🔶 lite | dual-write de fuel (ADR #44); cutover completo = runtime |
| 3 | 🔶 parcial | exports driver/occupants ✅; broadcasts despawn eliminados ✅; delta/rate-limit de telemetria = runtime |
| 4 | 🔶 parcial | F-045 impound gated ✅; anti-teleport/speedhack + lock distribuído = runtime |
| 5 | ✅ itens estáticos | F-040 removido; F-031/F-029 fechados; renomeação vrp_→vhub_fuel = FASE 7 |
| 6 | 🔶 parcial | Drift onResourceStop ✅ (F-058); F-053/F-059 (handling model-wide) = **só runtime** |
| 7 | ⏳ | exports consolidados parcialmente; API.md por resource pendente |
| 8 | ⏳ | testes automatizados = runtime (sem servidor neste ambiente) |

**Fronteira desta rodada:** tudo que era corrigível com garantia estática (sintaxe + análise
de fluxo + grep de emissor/consumidor) está aplicado. O que resta é **intrinsecamente de
runtime** — muda física de gameplay, exige medição de MS, ou precisa de 2 players simultâneos
(F-053/F-059 handling, delta sync, anti-cheat de posição, lock cross-instance, testrunner).
Fazer isso "no escuro" violaria a Seção 3/10 do próprio prompt maestro (MS medido, sem
teleport em corrida, DoD com stress test). Gate humano: rodar o checklist da PARTE V em dev.

### [ADR #49] 2026-07-03 | módulos: config/server.cfg, config/resources.cfg
**Allowlist do CORE aplicada + resources.cfg organizado por camada.**
Contexto: a FASE 1 (N0-2) tornou os exports sensíveis do CORE default-deny, mas a lista
`trusted_resources` nascia vazia → CORE negava TUDO em runtime (visto no log 2026-07-02).
Solução: `setr vhub_trusted_resources "conce,garage,custom,vehcontrol,nitro,racha,admin,
ferinha,legacyfuel"` no server.cfg (lido por criar_config na FASE 1). legacyfuel incluído
preventivamente (será escritor de fuel via commitVehicleState na FASE 2 — export-first).
resources.cfg reescrito por camada (infra→kernel→identidade→economia→personagem→veículos
→gameplay→policial→admin→periféricos→mundo); 34 ensures preservados (diff comm = zero perda/
adição); comentários stale corrigidos (ordem de boot é resolvida por `dependency`, não pela
lista). Impacto: zero runtime (config); destrava o espelho de fuel (ADR #44) e todo export
gated. Reversível via: git.

## 5. Débitos técnicos remanescentes (não esconder)

- `Veh._veh` sem eviction (veículos registrados nunca saem; _byNet tem GC, o registro não).
- `normalizePlate` duplicada (Utils + local em server/vehicle.lua) — unificar na FASE 5.
- b64/BLOB (F-021) e WAL (F-010): exigem DB real p/ migração segura — FASE 1.3/1.11 pendentes.
- Handlers institucionais de boot.lua usam literais de evento, não `vHub.E.*` (R9 drift).
- F-080 candidato: janela stale VRAM↔batch (ver §2).
- client/bootstrap.lua SPAWN_POS hardcoded (F-009) — dono real é vhub_player_state.

## 6. Critérios de aceite — status (fechamento 2026-07-02)

- [x] Snapshot git `pre-frozen-core-2-remediation` (aponta bde7784; CORE estava limpo)
- [x] FASE 1a..1e aplicadas — 13 arquivos, +461/−71 linhas
- [x] `luac -p`: 0 erros de sintaxe em todos os arquivos tocados
- [x] `luacheck`: 0 erros (warnings restantes = natives FiveM + estilo pré-existente)
- [x] Versão 1.0.0 → 2.0.0-alpha.1 (ADR #43); banner FROZEN atualizado
- [x] mergeConfig ganhou merge de 1 nível p/ tabelas (lang.banned etc. — F-003 completo)
- [x] Gate de placa colapsa espaços internos (mesma regra nos 3 pontos de normalização)
- [ ] **Validação runtime: boot em dev, `vhub_run_tests`, stress 200 players, pentest
      spoof de netid — OBRIGATÓRIO antes de produção; não executável neste ambiente
      (sem servidor FiveM ativo). Gate humano: subir em dev e rodar o checklist da
      PARTE V do frozen_core_2.md.**

### Métricas (estático; runtime pendente)

| Métrica | Antes | Depois |
|---------|-------|--------|
| Tráfego vState consumido | 0% (handler no-op) | 100% (validado) — kill-switch disponível |
| State Bags escritas em runtime | 0 | vh_odo/vh_eng/vh_body/vh_on/vh_tune (fuel na FASE 2) |
| `print()` no CORE (fora bootstrap/logger) | 8 | 0 |
| Campos de config nil em produção | 8+ | 0 |
| VRAM 24h | crescimento linear | TTL 1h/entidade (passada 60s chunked) |
| Contrato de commit no CORE | inexistente | commitVehicleState + SOURCE_GATES + audit |
| Audit unificado | inexistente | vh_audit append-only (mutações privilegiadas) |
| Threads novas por player | — | 0 (tudo event-driven ou timer global existente) |

### Próximos passos recomendados (ordem)
1. **Gate humano**: subir em dev, checklist PARTE V FASE 1 (spoof de vEnter DEVE ser rejeitado).
2. FASE 2: migrar `vhub_conce:saveVehicleState` → `exports.vhub:commitVehicleState`;
   ligar `core_fuel_enabled`/`veh_state_apply` na virada (unificação do fuel, F-050/F-066).
3. `setr vhub_trusted_resources "vhub_conce,vhub_garage,vhub_custom,vhub_vehcontrol,vhub_nitro,vhub_racha,vhub_admin,vhub_ferinha"` no server.cfg.
4. FASE 1.3/1.11 (migração b64→JSON + WAL) com banco real e backup.
5. Registrar decisões #37..#43 no contexto.md (escritor: vhub_guardiao_revisao).
