# ADR #85 — FASE 2.5: Compatibilidade como gate de instalação, remoção de peças, e massa derivada

> **Status:** APROVADA (gate `vhub_arquiteto` 2026-08-09, APROVADO COM AJUSTES) · **EM IMPLEMENTAÇÃO**
> **Sucede:** [[ADR_82_engenharia_automotiva]] (Camada A per-entidade) e complementa [[ADR_83_camada_b_model_wide]] (Camada B gated).
> **ADR #84** permanece **reservado** a "enxugar CORE `vd.state`" (não canibalizar). **Próximo livre após esta = #86.**
> **Não toca CORE.** Escreve em `[SCRIPTS]/vhub_custom`, `[SCRIPTS]/vhub_vehcontrol` (só derivador), `tools/handling-balancer` e `[SCRIPTS]/vhub_conce/shared/catalog.lua` (p1 gerado, revisado por humano).

---

## Context — o bug relatado, provado

"Veículo novo, praticamente nenhuma peça pode ser instalada." A causa raiz **não** é `if pontos + custo > class_budget` (esse `if` não existe). O bloqueio real é `Core.stageCap`:

- `oficina.lua:360-368` (OFICINA_INSTALL_PART) rejeita a peça quando `gta_mod.stage > cap`, com `cap = min(stage_cap_by_type, stage_cap_by_category, stage_cap_by_tier)` (`core.lua:194-204` + `config.lua:179-188`).
- Em `parts_catalog.lua:68-172`, **toda** peça de motor/câmbio/freio/suspensão é `stage ≥ 2`; só `turbo_kit` é `stage 1`. As sem `gta_mod` (`engine_original`, `turbo_none`, `handbrake_hydraulic`) escapam do cap, mas duas são "voltar ao original".
- **Trava circular** (Fusca `class_budget='C'`, `tierCap=1`): só instala `turbo_kit` (+15 de budget → 600→615) → score continua tier C → `tierCap` continua 1 → nunca libera `stage-2`. O veículo fica preso para sempre. `class_budget` bloqueia **indiretamente** via `tier → tierCap`.
- A NUI (`oficina.js:74-78`) só conhece `installed | available`; não distingue sem-item / incompatível / excede-cap / já-instalada — o server só recusa no clique. Daí a confusão entre "não tenho o item" e "incompatível".

## Decisão

Mover o **balanceamento** do teto artificial de pontos para **compatibilidade + trade-offs + baseline (DNA)**. `class_budget` e o sistema A/B/C/D/S **continuam existindo como conceito interno** (potencial, âncora de score/tier, anti-P2W por trade-off), mas **deixam de bloquear instalação** e **não voltam a aparecer como ranking visual**.

### D1 — Gate de instalação: `stageCap` (barreira) → COMPATIBILIDADE

- Nasce `Core.resolvePartStatus(context, part, curParts, hasItemFn) → { state, hint?, replaces? }` em `vhub_custom/server/oficina.lua` (mesmo escritor, L-13). Enum de `state`:
  `ok | already_installed | missing_item | conflict | requires_missing`.
- Uma peça instala se: **família aceita no chassi** (sempre, na F2.5-A) · **`requires` satisfeitos** · **sem `conflicts`** (checados contra o **SET COMPLETO** de peças instaladas, não só a mesma família — cond. 1) · **item no inventário** (se `part.item`) · **não já instalada**. Sem teto de pontos.
- `Core.stageCap` **NÃO é deletado nem renomeado**: continua servindo o `OFICINA_TUNE` deprecado (cond. 7) e vira **fonte de `hint`** no install (`stage > cap` → `hint = "acima do ideal para esta classe"`, **sem bloquear**). O gate `if gta_mod.stage > cap → finish(false)` sai do install de peças.
- Status por peça no payload de auth (`init.lua`): `parts_status = { [partId] = { state, hint?, replaces? } }` — **não persistido**, recomputado a cada `refreshSheet`. `requires/conflicts/replaces` são lidos do catálogo declarativo; **zero lógica nova em `parts_catalog.lua`** (L-04).
- `class_min` (declarado só em comentário, nunca implementado) é **removido do comentário** — compatibilidade é família/requires/conflicts/item, **não** piso de classe (senão volta a ser gate de budget, contra a filosofia). Sem meio-termo, sem dead comment.

### D2 — `OFICINA_REMOVE_PART` (remoção como primeira classe)

- Novo evento `E.OFICINA_REMOVE_PART` (`shared/events.lua`), handler em `oficina.lua`. Idempotente via `commitPayment` + fingerprint (`action='tune'` continua válido), custo 0 na F2.5-A.
- Projeção reversa **na mesma transação** (L-13, via `saveVehicleState`): `parts[id]=false` · se `gta_mod.index==18` → `turbo=false` · senão → `mods[idx] = -1` (GTA "original"; **-1**, não 0, pois 0 = stage 1) · se `capabilities` contém `'drift'` → `drift_capable=false`.
- **Não** reinstala automaticamente o "original" da família (remover `engine_turbo` não instala `engine_original`; o jogador escolhe). Evita 2ª verdade.
- **Refund fora do escopo** F2.5-A (remover não devolve item). Se um dia virar `true`, é R7 (deprecation path).

### D3 — F2.5-B: massa **derivada** (aplicação física fica na Camada B / ADR #83)

- `parts_catalog` declara `mass` (kg, +/-) por peça.
- **Um único derivador**: `sheet.mass = base_mass + Σ mass_deltas` nasce no **mesmo pipeline** de `sheet.eng/hnd/score/tier` — em `vhub_vehcontrol` (`tier_rules`/`engineering`), **nunca** em `vhub_custom` (derivar lá = 2ª derivação = REPROVA). Efêmero, nunca persistido.
- **Não existe native de massa per-entidade** no FiveM: `fMass` só via `SetVehicleHandlingFloat` = model-wide = **Camada B gated** (ADR #83, que já marca massa como "candidato a ficar FORA mesmo na ativação"). A F2.5-B **só deriva e exibe**; a física de massa **não é aplicada**. Limite honesto de plataforma.
- `base_mass` vem do `catalog.p1` (preenchido em F2.5-C). Carro sem `base_mass` → NUI mostra `—`.

### D4 — F2.5-C: baseline nativo via `tools/handling-balancer`

- A ferramenta (offline) passa a **emitir candidato** `p1{ base_alloc, class_budget, base_mass, tier_max }` para veículos **nativos** a partir do handling nativo — nativo e mod no **mesmo pipeline** de DNA.
- **Ownership:** `catalog.lua` (conce) continua a **fonte declarativa** de `p1`. A ferramenta gera; **humano revisa e cola**. **Zero import** da tool em runtime (runtime não roda o balancer).
- **ADENDO (decisão do dono 2026-08-09, pós-gate):** além do caminho offline, um **baseline DEFAULT em runtime** cobre TODO carro sem `p1` explícito. `Config.defaultBaselineFromStats=true` (vhub_vehcontrol) → `TR.defaultP1(entry)` deriva classe D..S+ / `base_alloc` balanceado / `mass` dos `stats` autorados no catálogo (vel/acel/freio/dir). **Não fabrica** — usa o desempenho autorado; nativo e mod caem no MESMO sistema de classes (anti-P2W). O `p1` explícito (balancer/.meta selado) **SEMPRE vence**. `TR.classifyStats`/`TR.defaultP1`/`TR.nextTier` são puros (tools/test_baseline.lua 20/20). **Isto MUDA a invariante "carro sem p1 = sem skill (fail-closed)"** de catalog.lua → **gate `vhub_arquiteto` PENDENTE** (bloqueado por limite de uso 2026-08-09; blindado por kill-switch = flag `false` volta ao fail-closed). A ferramenta offline (native.md) é o caminho de **precisão** por cima do default. Versão vehcontrol → 1.10.0.

### D5 — Numeração

`ADR #85 — FASE 2.5: Compatibilidade como gate de instalação, remoção de peças, e massa derivada`. (`#84` reservado a `vd.state`; próximo livre = `#86`.)

### D6 — Ordem de execução (árvore semântica)

`A (compat gate + parts_status + remove + NUI 5 estados) → C (baseline nativo p/ carros nativos priorizados) → B (mass no catálogo + derivar sheet.mass + exibir)`.
Racional: **A** é independente e destrava o bug sozinha. **B** exibiria `—` em quase tudo sem **C** ter alimentado `base_mass`; por isso **C precede B**. **C** é offline, independe de A/B.

## Condições de parada obrigatórias (embutidas nesta ADR)

1. **Anti-loop de `conflicts`/`replaces`:** checar `conflicts` contra o **SET COMPLETO** de peças instaladas (famílias diferentes — ex.: `engine_turbo.conflicts={turbo_none}`), não só a mesma família.
2. **Staleness de `parts_status` vs inventário:** sem hook barato de mudança de inventário, aceitar staleness. **O server é o juiz no clique**; a NUI só perde informação, nunca engana. Documentado.
3. **Migração zero:** peças já instaladas permanecem válidas — nenhuma é retroativamente invalidada. Só o **gate de install** muda. Sem `deprecation path` de dado.
4. **A-11 (CSS escopo local):** tokens de cor dos 5 estados vivem em `.mod-oficina`, **nunca** em `:root`.
5. **Invariante de física (reafirmado):** `applyModelWide=false`, `skillApplyHandling=false`, `client/handling.lua` **intocado**. F2.5 é gate + write-path + derivador de massa — **não** muda Camada A nem B.
6. **`Core.stageCap` (L-15):** mantido (consumido pelo `OFICINA_TUNE` deprecado + fonte de `hint`). Não deixar zumbi; se algum dia o tune morrer, deletar junto.
7. **`OFICINA_TUNE` deprecado:** **mantém** o `stageCap` como cap (path legado, deleção na F3). Não uniformizar o deprecado.

## O que esta ADR NÃO faz (não-regressão)

- **NÃO** liga `applyModelWide`/`skillApplyHandling`; **NÃO** toca `client/handling.lua`; **NÃO** aplica `SetVehicleHandlingFloat`.
- **NÃO** persiste derivado (`sheet.eng/hnd/mass/score/tier`).
- **NÃO** cria 2ª fonte de verdade: `customization.parts` continua o dado bruto único; compat/massa só **leem e derivam**.
- **NÃO** deleta `class_budget`/`TR.BUDGET`/`ALLOC_RANGE`/`PART_POINTS`/A-B-C-D-S — eles seguem como DNA interno.
- **NÃO** remove `Core.stageCap` (cond. 6/7).

## Migração e rollback

- **Migração:** nenhuma de dado (cond. 3). Só código: o gate de install deixa de bloquear por cap; NUI ganha estados; nasce `OFICINA_REMOVE_PART`; catálogo ganha `mass`; `tier_rules` ganha `sheet.mass`.
- **Rollback:** reverter os commits das fases; nenhum schema mudou. `parts_status`/`sheet.mass` são campos aditivos e opcionais (consumidores toleram ausência).

## Gates de execução (pings)

`vhub_guardiao_persistencia` (parts[id]=false no MERGE_SPARSE) · `vhub_guardiao_contrato` (`parts_status` + `E.OFICINA_REMOVE_PART`) · `vhub_guardiao_seguranca` (server-authority no install/remove) · `vhub_guardiao_designer` (5 estados + A-11) · `vhub_guardiao_simplicidade` (varrer morto pós-rebaixamento) · fecho `vhub_guardiao_revisao`.

Relaciona [[adr-82-fase2-engineering]], [[conce-getvehiclestate-shallow-copy]], [[derivador_onread_cross_resource]], [[vehicle-consolidation-plan]].
