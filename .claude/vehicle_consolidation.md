# Plano de Consolidação Veicular — Drift + nitro → vhub_custom (ADR #81)

> **Status: FASE 0 (documentação) escrita 2026-08-07. FASES 1–6 NÃO executadas.**
> Gate `vhub_arquiteto` APROVOU (com condições) 2026-08-07. Cada fase é committável e
> reversível isoladamente, com STOP para teste in-game entre elas.

## Objetivo (ordem do dono 2026-08-07)
1. Absorver `resources/[SCRIPTS]/Drift` → dentro de `vhub_custom`.
2. Absorver `resources/[SCRIPTS]/vhub_nitro` → dentro de `vhub_custom`.
3. Nova mecânica: desempenho dirigido por **PEÇAS de inventário** instaláveis na oficina.
4. Separação limpa: **cosmético → bennys**; **qualquer mudança de desempenho → oficina**.
5. Validar/consertar o `mec` para identificar problemas de verdade.

**NÃO é rewrite.** O `vhub_custom` JÁ tem os 3 domínios (bennys/mec/oficina) e a separação
`performance_mods`×`cosmetic_mods`. Isto consolida o que já existe + move 2 resources órfãos/externos.

## Ownership pós-migração
| Dado / mecânica | Escritor único | Consumidores | Persistência | API |
|---|---|---|---|---|
| `customization.nitro={kit,qty,enabled,level}` | **vhub_custom** (source='nitro') | vehcontrol, velo, oficina | PLACA via conce | `exports.vhub_custom:nitro*` (TRUSTED) |
| mecânica de drift (efêmera) | **vhub_custom/client** (drift.lua) | vhub_racha (`getTelemetry`) | NÃO persiste | `exports.vhub_custom:driftTelemetry` (read-only) |
| peça-item → mod de performance | **vhub_custom/oficina** (source='tune') | — | inventory → PLACA (`customization.mods`) | `exports.vhub_custom:installPartFromItem` (TRUSTED) |

## Mapa de contratos a preservar (R15 — deprecation path via shim)
**Drift (1 export):**
- `exports.Drift:getTelemetry()` → **vhub_racha** (`client/modes/drift.lua:25`). Novo: `exports.vhub_custom:driftTelemetry`. Shim mantém `Drift:getTelemetry` por 1 sprint.

**vhub_nitro (5 exports + 5 eventos + 1 item):**
- exports: `getNitro / installKit / setEnabled / setLevel / chargeFromItem` → **vhub_custom** (interno) + **vhub_vehcontrol** (`nitro_bridge.lua:27,43,54,65`; `exports.lua:121`). Novos nomes: `getNitro / nitroInstallKit / nitroSetEnabled / nitroSetLevel / nitroChargeFromItem`.
- **eventos (MANTER nome legado)**: `vhub_nitro:state`, `vhub_nitro:hud`, `vhub_nitro:drain`, `vhub_nitro:notify`, `vhub_nitro:request` → **vhub_velo** e client boost dependem dos NOMES. NÃO renomear na FASE 2 (adiar FASE 6 opcional). Agora emitidos pelo próprio vhub_custom.
- item garrafa `nitro` (registerItemUse) + `vhub_hss:addAdrenaline` (soft-dep) + drain monotônico.

## FASES (menos → mais arriscado; cada uma STOP p/ teste in-game)

### FASE 0 — Preparação (SEM código de produção, 100% reversível) — **ESTA FASE**
- ADR **#81** aberta. Este arquivo criado. Memory `vehicle-consolidation-plan.md` gravada.
- Linha do Registro de Ownership a adicionar em CLAUDE.md (via gate `vhub_guardiao_revisao` — revisao morto, então o worker grava sob autonomia). **STOP p/ revisão do dono.**

### FASE 1 — Absorção do Drift (menor risco: código órfão, sem estado persistente)
- `Drift/cl.lua` → `vhub_custom/client/drift.lua` (sem mudança funcional). Export → `exports.vhub_custom:driftTelemetry`.
- **Shim R15**: `Drift/cl.lua` vira `exports('getTelemetry', function() return exports.vhub_custom:driftTelemetry() end)` + log deprecation.
- `vhub_racha/client/modes/drift.lua:25` consome `exports.vhub_custom:driftTelemetry()` com fallback pcall p/ `exports.Drift` (aditivo).
- fxmanifest do custom: adicionar `client/drift.lua`.
- **STOP in-game**: entrar em drift → smoke + boost + pontuação no racha OK.

### FASE 2 — Absorção do vhub_nitro (maior superfície de contrato)
- `vhub_nitro/{server,client}.lua` + `cfg/config.lua` → `vhub_custom/{server,client}/nitro.lua` + `shared/nitro_cfg.lua`.
- fxmanifest: `server/nitro.lua` DEPOIS de `core.lua` e ANTES de `oficina.lua` (que chama installKit); `client/nitro.lua`; `shared/nitro_cfg.lua`.
- Exports renomeados: `getNitro/nitroInstallKit/nitroSetEnabled/nitroSetLevel/nitroChargeFromItem`.
- **Eventos legados MANTIDOS** (`vhub_nitro:*`) — velo depende. Emitidos agora pelo custom.
- **Shim R15**: `vhub_nitro/{server,client}.lua` → re-exports p/ `exports.vhub_custom:nitro*`.
- `oficina.lua:141,169,179` → **função local** (chamada intra-resource, sem invoke gate).
- `vhub_vehcontrol/server/nitro_bridge.lua:27,43,54,65` + `exports.lua:121` → `exports.vhub_custom:nitro*`.
- conce TRUSTED: **NÃO mexer** (vhub_custom já é TRUSTED; remover vhub_nitro só na FASE 5).
- **STOP in-game**: kit na oficina → ficha liga/nível → garrafa abastece → RSHIFT boost → HUD velo.

### FASE 3 — Peças de inventário → desempenho (mecânica NOVA, cirúrgica)
- Item = peça (`part_engine_stage2`, `part_turbo_kit`, ...) com metadata `{index=11..18, stage=1..3}`.
- Handler `E.OFICINA_INSTALL_PART` (mesmo contrato de commit que `OFICINA_TUNE`) consome item via `exports.vhub_inventory:takeItem` (estorno em falha, padrão do `chargeFromItem`).
- **REUSA** `customization.mods[index]=stage-1` via `saveVehicleState(...,'tune')`. ZERO estrutura nova. Doutrina da Placa.
- Preço-do-item (loja) e preço-do-serviço (`prices.engine_stage[stage]`) coexistem (peça + mão de obra).
- **`skillApplyHandling` PERMANECE false** — peça altera `customization.mods` (GTA stage), o `getVehicleSheet` já lê. Reativar motor derivado = ADR SEPARADA.
- **STOP in-game**: comprar peça (coinshop) → instalar na oficina → sheet do vehcontrol reflete.

### FASE 4 — mec: identificação real de problemas (dono decide escopo)
- Auditar `vhub_custom/server/mec.lua:17-39` (`repairPatch`). Adicionar laudo estruturado via `exports.vhub_custom:mecDiagnose(plate)` (portas/vidros/pneus/motor/tanque). UI mostra checklist antes do reparo.
- **STOP p/ revisão do dono** com 3 opções concretas de diagnóstico ("identificar de verdade" é vago).

### FASE 5 — Deleção dos shims (L-15/R15)
- Após 1 sprint dos consumidores migrados: `git rm -rf` `Drift/` e `vhub_nitro/`.
- Remover `vhub_nitro` da whitelist TRUSTED em `vhub_conce/server/exports.lua:21`.
- Remover `ensure Drift`/`ensure vhub_nitro` de `config/resources.cfg`.
- Grep final zero: `exports.Drift`, `exports.vhub_nitro`, `require.*Drift`, `require.*vhub_nitro`.

### FASE 6 (OPCIONAL — só se dor real)
- Renomear eventos `vhub_nitro:*` → `vhub_custom:nitro_*` (atualiza velo+vehcontrol+custom). Dívida cosmética, não bug. Pode nunca acontecer.

## CONDIÇÕES DE PARADA / NÃO FAZER
1. **NÃO reativar `skillApplyHandling`** (motor runtime `SetVehicleHandlingFloat`). Peças = `customization.mods` (GTA stage), não handling runtime. Ativar motor = migração SEPARADA com ADR própria.
2. **NÃO renomear eventos `vhub_nitro:*` na FASE 2** — velo é puro consumidor; rename mal-coordenado apaga HUD de nitro p/ todos. Adiar FASE 6.
3. **NÃO tocar `nitro_bridge.lua` E conce TRUSTED na mesma fase** — separar consumidor (F2) de whitelist (F5).
4. **NÃO absorver Drift como parte da oficina** — mecânica efêmera (client live, não persiste) ≠ oficina transacional (commit→placa). Domínio `drift` AO LADO de bennys/mec/oficina.
5. **NÃO criar 2ª fonte de verdade para "peça instalada"** — peça vira `customization.mods[idx]`; item some do inventário. Uma verdade só (Doutrina da Placa).
6. **NÃO mexer no motor de handling** (`vhub_vehcontrol/server/skill.lua`) — congelado por decisão anterior.

## LEIS
L-04 (uma verdade — placa via conce) · L-07 (ownership novo no Registro) · L-13 (escritor único vhub_custom source='nitro') · L-15 (deletar shims F5) · L-16 (nenhum entity writer novo) · R15 (deprecation via shim) · R3 (export-first gated) · R4 (dono único).

## ADR livre: **#81** (Supra sprint consumiu #80 em 2026-08-04).
