# ADR #82 — Plataforma de Engenharia Automotiva (vhub_custom)

> **Status:** APROVADO pelo arquiteto (2026-08-08) · **Aguarda:** guardiões (natives+persistencia+contrato) → worker → revisao
> **Veredito do gate:** REDUZIR_ESCOPO — aprova a intenção (peças/trade-offs/personalidade); reprova
> (a) demolir o tier em bloco, (b) reativar handling runtime sem faseamento com evidência, (c) manter `handling_ext`.
> **Próximo ADR livre após este:** #83 (Camada B model-wide), #84 (enxugar CORE `vd.state`).

---

## Context (por que esta mudança existe)

O dono pediu para transformar `vhub_custom` na **plataforma central de engenharia automotiva** do vHub:
peças com **trade-offs reais** (não "maior número vence"), 3+ famílias de motor (original/aspirado/turbinado)
com identidade técnica, o **mesmo carro montável** para Sprint/Drift/Drag/Circuito, física **sentida** no carro,
**fim do ranking A/B/C/D/S** como autoridade de balanceamento, e a oficina refeita arquiteturalmente.

O diagnóstico (3 Explore + leitura direta) revelou **3 tensões reais** entre o pedido e o código, além de
**1 bug bloqueador** e **1 bug zumbi pré-existente**. Este ADR resolve as tensões e define o faseamento seguro.

### Fatos verificados que condicionam tudo
- **Handling runtime está DESLIGADO** (`Config.skillApplyHandling=false`, vehcontrol/shared/config.lua:52) —
  o **dono desligou em 2026-08-05 por instabilidade real**: `SetVehicleHandlingFloat` sobre `CHandlingData`
  é **model-wide no cliente** (muta todas as instâncias locais do modelo). Reativar em bloco = repetir o bug.
- **Bug FK (bloqueador):** `commitVehicleState({fuel})` do CORE reescreve o **blob `state` inteiro** em
  `vh_vehicle_data`; `vd.anchored` é calculado 1× no `register()` e o cache `Veh._veh[plate]` nunca revalida;
  `vhub_conce.deleteVehicle` apaga `vh_vehicles` mas **nunca chama `Veh:unregister`** (existe, vehicle.lua:106,
  ZERO callers). Cache stale → fuel commit por tick viola FK → 5 retries → DESCARTADA.
- **Bug zumbi:** `handling_ext` é gravado por `oficina.lua:456` mas **não está em `CUST_KEYS`** (vstate.lua:45-59)
  → `sanitizeCustJson` descarta silenciosamente. Nunca funcionou. L-15.

---

## Resolução das 3 tensões (decisões arquiteturais)

### T1 — Física real vs handling runtime desligado → **DUAS CAMADAS**
- **Camada A (per-entidade, SEGURA, ligada por padrão na FASE 2):** potência, top speed, torque, mods GTA.
  Natives **confirmadas na referência do projeto** (`metas/fivem_natives_organizadas_ptbr.md`):
  - `SetVehicleCheatPowerIncrease(vehicle, value)` (linha 40259) — boost de potência per-entidade.
    **Precedente vivo:** `vhub_custom/client/nitro.lua` já usa. ✓
  - `ModifyVehicleTopSpeed(vehicle, percentChange)` (linha 37474) — top speed per-entidade. ✓
  - `SetVehicleEngineTorqueMultiplier` — **NÃO confirmada na referência do projeto.** NÃO usar até validar
    a assinatura no runtime alvo (deixar fora da FASE 2 ou provar com teste isolado antes).
  - Mods GTA nativos (engine/brakes/transmission/suspension via `SetVehicleMod`) — já per-entidade, já ativos.
- **Camada B (model-wide, GATED por ADR #83 + evidência in-game):** grip fino (`fTractionCurveMax`),
  freio absoluto (`fBrakeForce`), suspensão (`fSuspensionForce`/`fAntiRollBarForce`), direção (`fSteeringLock`),
  freio de mão hidráulico (`fHandBrakeForce`), aero fina. Exige `SetVehicleHandlingFloat` = model-wide.
- **`Config.skillApplyHandling` NÃO é reativado em bloco.** É substituído por sub-flags:
  - `Config.applyPerEntity = true` (Camada A) — liga na FASE 2.
  - `Config.applyModelWide = false` até ADR #83 (Camada B, com evidência empírica da FASE 2 estável).
- **Escritor único da aplicação física = `vhub_vehcontrol` client/handling.lua** (já é hoje; NÃO criar 2º aplicador).
- **Freio de mão hidráulico** (`drift_capable`) só ganha efeito físico na Camada B (FASE 3). Até lá o item na
  aba Peças **persiste sem efeito** — honesto: a mecânica vem faseada.

### T2 — "Sem ranking A/B/C/D/S" vs tier ser o coração do motor → **TIER VIRA INTERNO**
O tier faz 2 coisas ortogonais:
1. **Budget orçamentário** (`BUDGET[tier_base]`) = teto de pontos do chassi = **anti-P2W estrutural**
   (Fusca nunca vira Skyline comprando peças). **MANTER.**
2. **Classe exibida (A/B/C/D/S)** = etiqueta derivada do score. **MATAR na NUI.**

- Manter `TR.BUDGET`, `TR.ALLOC_RANGE`, `TR.PART_POINTS` (motor de balanceamento server-side).
- **Renomear `tier_base` → `class_budget`** (nomenclatura honesta) com **shim R15** (aceita ambos por 1 versão).
- **Deletar bandas `TIER_SCORE` (D..S+)** — score vira número interno (0-1000) ou nada.
- **NUI nunca mostra "tier"/"classe".** Mostra os 5 eixos brutos + deltas da peça.

### T3 — Substituir OFICINA_TUNE vs contratos vivos → **DOMÍNIOS ORTOGONAIS**
Mod GTA (`customization.mods`) = **VISUAL/multiplicador nativo per-entidade** (turbo aparece, spoiler visível).
Peça (`customization.parts`, NOVO) = **vetor de deltas físicos**. **Não é 2ª fonte de verdade — dois eixos
ortogonais na mesma placa, um único escritor (`vhub_custom`).** Instalar "Turbo Stage 2" escreve
`parts[…]='turbo_s2'` **E** `mods[18]=1` em uma transação.

- **OFICINA_TUNE** (stage 1-2-3 dos mods GTA) e **OFICINA_INSTALL_PART** (PART_MAP da FASE 3 ADR #81) são o
  mesmo domínio (ambos escrevem `mods`). Manter só INSTALL_PART; **deprecar OFICINA_TUNE** (deleção na FASE 3).
- **OFICINA_HANDLING** (knobs livres via `handling_ext`) — **DEPRECAR** (o caminho zumbi some; peças cobrem).
- **OFICINA_RECALIBRATE** (alloc de pontos) — **MANTER** (é o "livre" distribuível entre eixos permitidos).
- **OFICINA_NITRO_KIT** — **MANTER** (nitro = domínio próprio de fuel químico, escritor `vhub_nitro`).

---

## Ownership (linhas novas do Registro)

| Verdade | Escritor único | Leitores | Onde vive | Como se escreve |
|---|---|---|---|---|
| Catálogo de peças (id, nome, deltas, custo, requisitos) | `vhub_custom/shared/parts_catalog.lua` | vehcontrol.TR (puro), NUI | Config estática | Deploy (versionado) |
| Peça instalada por placa | `vhub_custom` (source `'tune'`) | vehcontrol (sheet), garage (respawn) | `vhub_vehicle_state.customization.parts` (JSON, sparse merge) | `saveVehicleState(plate,{customization={parts=…}},'tune')` |
| Sheet físico derivado | `vhub_vehcontrol` (função pura, on-read) | NUI, client/handling | RAM (nunca persiste) | — |
| Camada A física (per-entidade) | `vhub_vehcontrol` client/handling.lua | — | RAM per-entidade | BECAME_DRIVER aplica; LEFT_VEHICLE restaura |
| Camada B física (model-wide) | `vhub_vehcontrol` client/handling.lua | — | RAM per-modelo (restaura ao sair) | Gated `Config.applyModelWide` (ADR #83) |
| `class_budget` (ex-`tier_base`) | `vhub_conce/shared/catalog.lua` (p1) | vehcontrol.TR | Config p1 por modelo | Deploy |

**Removidos do Registro:** `handling_ext` (código zumbi). **Renomeado:** `tier_base` → `class_budget`.

---

## Faseamento

### FASE 1 — Base honesta (ESTA sprint, ADR #82) · ZERO handling runtime
1. **Fix FK:**
   - Novo export `exports.vhub:unregisterVehicle(plate)` gated TRUSTED → chama `Veh:unregister(plate)`.
   - `vhub_conce.deleteVehicle` chama `unregisterVehicle(plate)` ANTES de apagar a row.
   - **Endurecer `Veh:_save`:** antes do `setVData(plate,'state',…)`, revalidar `vd.anchored` com query
     rápida em `vh/veh_key`. Sumiu → `anchored=false`, retorna sem escrever (fail-closed).
2. **`parts` em `CUST_KEYS` + `MERGE_SPARSE`** no conce (aditivo; merge por chave de peça).
3. **`vhub_custom/shared/parts_catalog.lua`** (NOVO) — dados: por família (motor original/aspirado/turbinado,
   freios, câmbio, suspensão, turbo, freio hidráulico), cada peça = vetor de deltas nos 5 eixos + custo +
   requisitos + mod GTA visual associado. **Apenas dados — sem aplicação física nesta fase.**
4. **Renomear `tier_base` → `class_budget`** com shim R15 (tier_rules.lua aceita ambos por 1 versão).
5. **Deletar `TIER_SCORE`/bandas D..S+** da NUI (só código NUI; motor server usa `class_budget`).
6. **Remover `handling_ext`** (código zumbi: caminho de escrita em oficina.lua + leitor em vehcontrol/exports).
7. **Deprecar OFICINA_HANDLING/OFICINA_TUNE** (mantém contrato com aviso; deleção FASE 3).
8. **NUI da oficina refeita** — aba "Engenharia": 5 eixos brutos + peças por família + delta ao vivo (preview),
   sem letras de tier. Continua usando `reserveWorkshopRecalibration/commit` para pontos livres.
- **Entregável mensurável:** peça persiste, aparece na oficina, orçamento respeita o `class_budget`,
  bug FK morto, código zumbi removido. **ZERO reativação de handling runtime.**

### FASE 2 — Camada A per-entidade (segura) · ADR #82 complementar
- `client/handling.lua` ganha `applyPerEntity(veh, sheet)` com `SetVehicleCheatPowerIncrease` +
  `ModifyVehicleTopSpeed` (torque só se a native for validada).
- `Config.applyPerEntity = true` (seguro por natureza). Testes in-game: potência/aceleração por família.
- **Ainda ZERO model-wide.** Freio hidráulico ainda inerte.

### FASE 3 — Camada B model-wide (reativação consciente) · **ADR #83 obrigatória**
- Só após FASE 2 estável in-game com evidência real. `Config.applyModelWide=true`. Freio hidráulico opera.
- Deleta OFICINA_HANDLING/OFICINA_TUNE (encerra deprecation R15).

### FASE 4 (opcional) — Enxugar CORE `vd.state` · **ADR #84**
- Reduz `vd.state` do CORE a `{fuel}`. Deleta os 8 campos que a decisão #24 já moveu p/ conce.

---

## multipleStatements (warning oxmysql)
Warning de infra (oxmysql upstream). Benigno enquanto o CORE usa apenas `S:prepare()`/`S:query()`
parametrizados (sem concatenação). **Não bloqueia a sprint.** Endereçar isolado se causar problema real.

## Leis invocadas
L-04 (mod visual vs peça física = ortogonais), L-13 (escritor único), L-15 (código morto: handling_ext,
TIER_SCORE, OFICINA_TUNE em fases certas), L-16 (único aplicador físico), L-18 (class_budget = orçamento),
R3 (export-first: unregisterVehicle), R15 (deprecation: tier_base/OFICINA_TUNE com shim).

## Regras de ouro do dono (permanentes)
- **skillApplyHandling NÃO reativa em bloco** — sub-flags per-entidade/model-wide faseadas.
- **Nunca "melhor peça"** — só trade-offs; peça = vetor de deltas, não stage escalar.
- **Tier nunca aparece na NUI** — `class_budget` é teto interno anti-P2W.
- **Uma verdade** — `parts` na placa via conce; mod GTA = visual ortogonal; sheet derivado nunca persiste.
