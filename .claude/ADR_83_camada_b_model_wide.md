# ADR #83 — Camada B: física model-wide de handling (peso/grip/freio/suspensão)

> **Status:** ESCRITA · **NÃO ATIVADA** · **NÃO IMPLEMENTADA EM RUNTIME**
> `Config.applyModelWide = false` (vhub_vehcontrol/shared/config.lua) e `Config.skillApplyHandling = false`
> permanecem **intocados**. `client/handling.lua` **não é modificado por este ADR**. Este documento é o
> **projeto** da Camada B — o terreno, os riscos e os critérios de ativação — para que, quando (e se) o dono
> decidir ligar, exista um caminho governado em vez de improviso.
> **Sucede:** [[ADR_82_engenharia_automotiva]] (Camada A, FASE 2 — per-entidade, LIGÁVEL e segura).
> **Próximo ADR livre após este:** #84 (enxugar CORE `vd.state`).

---

## Context (por que esta camada é um ADR próprio, e não parte da FASE 2)

A ADR #82 dividiu a física das peças em **duas camadas** por uma razão de plataforma, não de estilo:

- **Camada A (per-entidade):** `SetVehicleCheatPowerIncrease` + `ModifyVehicleTopSpeed` mudam **UMA instância**
  do veículo. Dois carros do mesmo modelo podem ter potências diferentes. É seguro, é o núcleo da FASE 2,
  e está **ligável** (`applyPerEntity`).
- **Camada B (model-wide):** peso (`fMass`), aderência (`fTractionCurveMax`), freio (`fBrakeForce`),
  suspensão (`fSuspensionForce`/`fAntiRollBarForce`) só têm um caminho no FiveM: `SetVehicleHandlingFloat`,
  que muta **`CHandlingData` — a ficha COMPARTILHADA do modelo**. Não existe native per-entidade para esses
  eixos. Mudar o grip de "um" Sultan muda o grip de **todos os Sultan carregados no cliente**.

O dono **desligou o handling runtime em 2026-08-05 por instabilidade real** (`skillApplyHandling=false`):
aplicar `SetVehicleHandlingFloat` em runtime, model-wide, sem um protocolo de restauração robusto, produziu
carros que "herdavam" o handling de outro do mesmo modelo e não voltavam ao `.meta`. **Reativar em bloco =
repetir o bug.** Por isso a Camada B **não entra junto** com a FASE 2 — ela precisa de um contrato próprio de
segurança (abaixo) e de evidência in-game antes de qualquer flag virar `true`.

---

## Decisão

**Projetar** a Camada B agora (para não improvisar depois), mas **não ativá-la**. A ativação é uma decisão
futura do dono, condicionada aos **critérios de ativação** e ao **protocolo de segurança** desta ADR. Enquanto
`applyModelWide=false`, nada deste documento toca o veículo — as peças de handling (freio de mão hidráulico,
etc.) instalam e persistem (Camada A já cobre potência), mas seus **deltas de handling não viram física**.

### Escopo dos eixos da Camada B (o que só existe model-wide)

| Eixo (peça) | Campo `CHandlingData` | Observação |
|-------------|----------------------|------------|
| peso        | `fMass` + `fInitialDragCoeff` | **identidade física crítica** — mexer em massa altera tudo; candidato a ficar FORA mesmo na ativação |
| aderência   | `fTractionCurveMax` / `fTractionCurveMin` | grip de curva; `Min = Max * skillGripMinRatio` (mantém curva coerente) |
| frenagem    | `fBrakeForce` | |
| suspensão   | `fSuspensionForce` / `fAntiRollBarForce` | rigidez; stance visual é OUTRA coisa (per-entidade, vhub_custom/stance.lua) |
| freio de mão| `fHandBrakeForce` | habilita o **efeito** do Freio de Mão Hidráulico (hoje a peça só habilita a capability `drift`) |
| direção     | `fSteeringLock` | |

> `fMass`/bias ficam sob suspeita: são a espinha da identidade do carro. Recomendação de projeto: **começar a
> ativação SEM massa** (só grip/freio/handbrake/steering), medir, e só então avaliar massa.

---

## Protocolo de segurança OBRIGATÓRIO antes de qualquer ativação

A instabilidade de 2026-08-05 tem causa conhecida: **base compartilhada + restauração frágil**. O contrato de
ativação precisa fechar exatamente isso.

1. **Base por modelo capturada 1×, ANTES de qualquer escrita** (`_modelBase[model][field] = valor do .meta`).
   O `client/handling.lua` já tem esse esqueleto (`_modelBase`) — reusar, não reinventar.
2. **Escritor único de `SetVehicleHandlingFloat` por modelo.** Como é model-wide, o "dono" do valor é o
   **último motorista que aplicou** — e ao SAIR ele DEVE restaurar a base do modelo, senão o próximo carro
   daquele modelo herda. Restauração no `LEFT_VEHICLE` é **inegociável** (já é o gatilho da Camada A).
3. **Reaplicação idempotente no BECAME_DRIVER** (R14): entrar num carro reaplica a ficha DELE por cima da base,
   nunca acumula. Sair restaura a base. Nunca escrever sem ter capturado a base primeiro.
4. **Clamp por banda** (`Config.skillHandling` já define min/max por eixo) — nunca aplicar valor cru do delta;
   sempre `lerp(banda.min, banda.max, frac)` re-clampado no cliente (defesa em profundidade, payload do server
   é tratado como hostil mesmo sendo próprio).
5. **Kill-switch global** (`GlobalState.vh_handling_active`): server derruba a Camada B em 1 linha sem restart
   de client — se a instabilidade voltar em produção, desarma na hora (padrão do [[validacao_fisica_replica]]).
6. **Derivação server-side, NUNCA persistir.** `sheet.hnd` (já existe em tier_rules.handlingFromAlloc) é o alvo
   derivado; é efêmero, igual a `sheet.eng`/score/tier. O dado bruto (peças) persiste; a física é recomposta.

---

## Critérios de ativação (gate para virar `applyModelWide=true`)

Só ligar quando **TODOS** forem verdade — e mesmo assim, atrás de flag, com rollback pronto:

1. Camada A (FASE 2) validada in-game e estável em produção por tempo suficiente (potência/velocidade não
   regridem, nitro sobre a base funciona, sair reseta).
2. Protocolo de segurança acima **implementado e testado** com o cenário que quebrou em 2026-08-05:
   **dois carros do mesmo modelo**, um com peças de handling e outro stock, dirigidos em sequência —
   o stock **precisa** dirigir como `.meta` depois que o tunado sai. Se herdar, REPROVA.
3. Kill-switch testado (server derruba, carros voltam ao `.meta` em ≤2s sem restart).
4. Gate de `vhub_arquiteto` + `vhub_guardiao_natives` (autoridade de entidade/model-wide) + evidência do teste
   acima anexada. Bump de versão do vehcontrol. ADR marcada como ATIVADA com data.

> Enquanto qualquer critério faltar: `applyModelWide=false`. Instalar peça de handling continua **honesto** —
> ela instala, custa, aparece no histórico e habilita a capability; o **efeito físico** fica "aguardando
> Camada B" (é o que a F2.5 comunicaria na NUI, se/quando o dono pedir o ponto de instalação com badge).

---

## O que este ADR NÃO faz (invariantes de não-regressão)

- **NÃO** modifica `client/handling.lua` (permanece como está, desligado por `skillApplyHandling=false`).
- **NÃO** liga `applyModelWide` nem `skillApplyHandling`.
- **NÃO** aplica `SetVehicleHandlingFloat` em runtime.
- **NÃO** persiste `sheet.hnd`/`sheet.eng` — derivados nunca viram verdade.
- **NÃO** cria 2ª fonte de verdade: as peças (`customization.parts`) continuam sendo o dado bruto único; a
  Camada B, quando ligada, só as LÊ e deriva alvos de handling.

---

## Relação com o modelo de peças (Camada A já entregue — ADR #82 F2.1)

O derivador `VHubVeh.Engineering.derive` (vehcontrol/shared/engineering.lua) hoje traduz os deltas de
**potência→power_boost** e **aero→top_speed_pct** (Camada A). Quando a Camada B ligar, o **mesmo** vetor de
deltas das peças (grip/frenagem/suspensão) alimenta `tier_rules.handlingFromAlloc` → `sheet.hnd` → o applier
model-wide gated. **Um dado bruto (peças), dois derivadores (eng per-entidade + hnd model-wide), zero
persistência de derivado.** É a arquitetura que a ADR #82 já montou — a Camada B é só o segundo consumidor,
ligado sob este gate.

Relaciona [[handling-engine-blueprint]] (motor model-wide original), [[adr-82-fase2-engineering]],
[[supra-poison-fix]] (perfil de dano — outro eixo de "física sentida", ortogonal), [[validacao_fisica_replica]]
(kill-switch + gate físico).
