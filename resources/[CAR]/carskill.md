# vHub P1 Skill — Especificação de Arquitetura (realista para o vHub Mirage)
**Versão:** 2.2.0 · **Status:** Spec definitiva, alinhada ao CORE FROZEN v1.0 + manual_dev_vhub + leis L/A

> ⚠️ **ESTADO REAL DA IMPLEMENTAÇÃO (2026-06-18) — LEIA ANTES.** O engine de skill NÃO foi
> implementado como um resource `vhub_p1skill` separado. Ele vive DENTRO de
> `resources/[SCRIPTS]/vhub_vehcontrol` (decisão #27 — plano canônico em `vhub_vehcontrol/PLANO.md`).
> O que EXISTE hoje: ficha derivada **read-only on-demand** (`REQ_SHEET`→`SHEET` + exports
> `getVehicleSheet/Tier/Score/Affinity/SheetPreview` em `server/exports.lua`) e o **escritor único do
> alloc** `server/skill.lua` (`RECALIBRATE`, 2 portas: caixa de ferramentas + oficina). As fórmulas
> (§3.6, §5.3, §5.4) e a taxonomia de campos (§3.4) estão refletidas em `shared/tier_rules.lua`.
>
> As seções **§2 (estrutura `vhub_p1skill/`), §5.2.1 (StateBags `vhub_p1`/`vhub_p1_hnd`, manifestação
> física híbrida via `SetVehicleHandlingFloat`), §5.5–§5.8 (HUD client, telemetria
> `vhub_p1skill_telemetry`, snapshot/racha)** descrevem a arquitetura p1skill **NÃO construída** —
> valem como **referência conceitual / roadmap futuro**, não como código atual. O pipeline offline
> (`tools/handling-balancer/`) e o bloco `catalog.p1` no conce permanecem válidos como desenho.

> **Decisões do dono (2026-06-15):** (1) o pipeline **reescreve só o núcleo de performance
> (8 campos)** e **PRESERVA todo o resto, incluindo a LATARIA** (multiplicadores de
> colisão/deformação/dano e arquivos visuais — §3.4); (2) o carmod **permanece em
> `resources/[SCRIPTS]/carmod`** por enquanto (o move para `[CAR]` foi adiado — os arquivos
> reais nunca saíram de `[SCRIPTS]`; `[CAR]/carmod` está vazio).
**Nome canônico do resource runtime:** `vhub_p1skill` · **Pipeline offline:** `tools/handling-balancer/`

> **Reescrita honesta da v1.1.** A spec anterior assumia coisas que NÃO existem no vHub
> (core como dono de `customization.mods`, tabela própria de identidade do veículo,
> `exports.vhub:getVehicleState`). Esta versão corrige cada ponto contra o código real:
> **`vhub_conce` é o dono único da identidade do veículo** (`shared/catalog.lua`) e do
> estado físico (`vhub_vehicle_state`, sprint PRONTUÁRIO). O p1skill é uma **camada
> derivada read-only** — nunca um segundo dono de dado. Tudo que cruza fronteira segue L-19.

---

## 0. Premissas inegociáveis do ambiente (lidas do código, não inventadas)

| # | Fato verificado no repo | Consequência para o p1skill |
|---|---|---|
| P-1 | `vhub_conce/shared/catalog.lua` é o **único** dono da identidade/preço do veículo. `garage` cacheia read-only via `getCatalog()` no boot. | Tier/score/arquétipo nascem como **campos do catálogo** (configurar num lugar só). p1skill **lê** o catálogo; não duplica. |
| P-2 | A chave do catálogo = `<modelName>` do `vehicles.meta` em **minúsculo**. | `handling_name` e tier ficam ancorados nessa MESMA chave. Zero mapa paralelo. |
| P-3 | Estado físico do veículo = `exports.vhub_conce:getVehicleState(plate)` (PRONTUÁRIO). O homônimo `exports.vhub:getVehicleState` (CORE) está **inerte**. | p1skill lê upgrades por `getVehicleState(plate).customization.mods`, via conce. NUNCA pelo core. |
| P-4 | `customization.mods` já é sanitizado/whitelistado pelo conce (`CUST_KEYS`). | p1skill consome `mods` como dado **já validado** — não revalida shape de mod, só interpreta. |
| P-5 | CORE FROZEN v1.0: nada de novo arquivo no core; mudanças no conce/garage exigem gate. | p1skill é **resource externo novo** com ownership e lifecycle próprios (L-07). Não toca core. |
| P-6 | `carmod` permanece em `resources/[SCRIPTS]/carmod` (62 arquivos reais lá; `[CAR]/carmod` vazio). FiveM resolve por NOME, não por caminho — `ensure carmod` é válido em qualquer pasta. | Pipeline offline varre por **glob de `handling.meta`** (path-agnóstico). Mover a pasta no futuro não quebra nada. |
| P-7 | L-19: vetor é uso LOCAL; ao cruzar event/export/NUI vai como primitivo. | HUD recebe números/strings achatados via StateBag — nunca tabela-vetor. |

**Regra de ouro mantida:** a Fase 1 (offline) não conhece FiveM. A Fase 2 (runtime) não toca `.meta`.
**Regra nova (L-04):** a Fase 2 não tem fonte de verdade própria de identidade — ela DERIVA do catálogo do conce.

---

## 1. Fundamentos do Sistema (o "porquê" do projeto)

### 1.0 Filosofia, diferencial e disciplina de escopo

> Validação externa (2026-06-15): uma revisão independente convergiu para o MESMO núcleo deste doc
> — inclusive a mesma ponderação de score (§3.6: 30/30/15/15/10) e o mesmo princípio "UX de 5 eixos
> sobre ~48 campos". Convergência independente = o desenho não é arbitrário; é o que o problema pede.

Princípios que regem TODA decisão do projeto:

- **Carro = identidade do player, não item descartável.** O diferencial do Mirage não é "ter sistema
  de carros" — é a RELAÇÃO que o player cria com o próprio carro. Norteia toda escolha de UX e feel.
- **Balancear ≠ nerfar.** Normalizar é dar CONTEXTO (tier + trade-off) preservando a personalidade:
  um R34 continua R34, dentro das regras do Mirage. Ninguém quer um R34 fraco — quer um R34 JUSTO.
  O inimigo é o "carro roubado" da comunidade (driveForce/grip/topspeed absurdos → dsync, atravessa
  curva, ninguém alcança); o balanceador existe para matar essa cultura, não a personalidade.
- **Fácil de aprender, difícil de dominar.** 5 eixos na superfície; complexidade física escondida.
  Expor caster/camber/toe/spring-rate na UX = 80% dos players desistem. UX simples, motor complexo.
- **GATE DE ESCOPO (obrigatório, todo sistema novo):** "isto aumenta a HABILIDADE do player ou só a
  COMPLEXIDADE do código?". Se for só complexidade → NÃO entra. O maior ativo do Mirage é
  CONSISTÊNCIA; o maior risco não é inovar — é inovar demais ao mesmo tempo.
- **Determinístico primeiro; IA só cosmética.** Tier é matemática (§3.6). A IA, se mantida, apenas
  descreve/nomeia — nunca decide, e o pipeline roda inteiro sem ela.

### 1.1 Grip — definido pelo tuning do player
Grip (`fTractionCurveMax/Min`) é atributo físico do pneu, ajustado na oficina. O player decide
quanto grip colocar. O servidor lê o estado atual (mods instalados) e computa o impacto no score,
com **punição orgânica** (§1.4).

### 1.2 Suspensão — preservada como identidade, lida como afinidade
`fSuspensionRaise/Upper/Lower` definem a altura/caráter do carro. São **PRESERVADOS** pelo
pipeline offline (identidade). Em runtime são lidos do catálogo (campo derivado do `.meta` selado)
para calcular afinidade por tipo de pista — carro baixo performa melhor em asfalto, alto em terreno.

### 1.3 Tier fluido
O `.meta` selado define o **chão físico base** (Fase 1) → vira `tier_base` no catálogo. O tier
exibido em jogo é **recalculado pelo servidor** a cada mudança de upgrade, mas nunca sobe mais de
1 tier acima do base (anti-salto).

### 1.4 Trade-offs orgânicos — o coração do projeto

**Problema:** se todo upgrade só beneficia, dois carros iguais "no máximo" são idênticos. Sem skill
de montagem, sem diversidade no mesmo tier.

**Solução:** orçamento de pontos fixo por tier. Aumentar um atributo acima do padrão obriga a
reduzir outro. O player escolhe ONDE alocar.

```
Orçamento fixo por tier (5 atributos):
  D=500  C=600  B=700  A=800  S=900  S+=1000

Atributos:
  [1] POTÊNCIA   → fInitialDriveForce + stage engine
  [2] GRIP       → fTractionCurveMax  + tipo de pneu
  [3] FRENAGEM   → fBrakeForce        + tipo de freio
  [4] AERO       → fInitialDragCoeff  (inverso: + downforce = + arrasto)
  [5] SUSPENSÃO  → altura + rigidez   → estabilidade vs. terreno
```

> Cada eixo é a **UX da oficina** e agrega um **cluster** de campos reais do `.meta` (mapa completo
> em §3.4). O score lê o cluster pleno; a reescrita toca só o campo representante de cada eixo.

```
INVARIANTE: soma(atributos_normalizados) == BUDGET[tier_base]  (sempre)

+15 em POTÊNCIA → o servidor distribui −15 nos outros. O player escolhe onde perder;
se não escolher, distribui nos menos prioritários. O servidor REJEITA qualquer alocação
que quebre a invariante.
```

Exemplos (Tier A, budget 800, base 160/atributo):

```
Build "Drag":     POT 220 GRIP 120 FRE 120 AERO 180 SUSP 160 → reta/0-100
Build "Circuit":  POT 140 GRIP 200 FRE 200 AERO 120 SUSP 140 → curva/controle
→ Dois Tier A completamente diferentes. Nenhum "melhor" — especializados.
```

**Anti-P2W:** "tudo no máximo" não existe (orçamento + `ALLOC_RANGE` ≤ 35% por atributo). Copiar o
build do campeão não garante vitória — ainda exige skill de pilotagem na pista certa.

### 1.5 Cruzamento físico — como os campos interagem (peso · torque · wheelspin · embalo)

Nenhum campo age sozinho. O que o player SENTE emerge da **relação** entre eles. Esta seção é o
cruzamento honesto com a física real do GTA5 (validado contra `cont1.md`, Broughy1322, GTACars.net)
— é o que faz a ideia "cada carro é único" funcionar de verdade em vez de no papel.

**Verdade sobre o PESO (`fMass`) — leia antes de modelar qualquer coisa:**

```
Aceleração ≈ 10 × fInitialDriveForce
Torque na roda = fInitialDriveForce × fMass   →   mas  a = F/m   →   fMass CANCELA
```

Dois carros com o mesmo `fInitialDriveForce` **aceleram igual em reta**, pesando 1000 ou 2000 kg.
A intuição "pesado precisa de mais torque" é verdade no mundo real, mas o GTA5 NÃO simula na
arrancada. → **NUNCA escalar driveForce por massa** (foi o bug da v2 do balancer).

**Onde o peso REALMENTE pesa no GTA5 (e como o p1skill usa):**

| Efeito real do peso | Campo(s) | Uso no p1skill |
|---|---|---|
| Colisão / momento de impacto | `fMass` | Identidade — lido, NUNCA escrito |
| Sensação de peso ao girar/trocar de direção | `vecInertiaMultiplier` | Preservado; lido → afinidade (agilidade/drift) |
| Rolagem de carroceria em curva | `fSuspensionForce`, `fAntiRollBarForce` | (B) modifica antiRoll; resto preservado |
| Classificação de tier | power-to-weight (`driveForce ÷ massa`) | Score: balizado vs. carro nativo de referência |

**O "canta pneu" (wheelspin) — ISSO o GTA5 modela bem, e é o coração do trade-off:**

```
torque demais para a aderência disponível  →  patina na saída  →  "canta pneu até pegar embalo"

EMERGE DE:  fInitialDriveForce (↑torque)
          × fTractionCurveMax/Min (↓grip → patina mais)
          × fLowSpeedTractionLossMult (↑perda de tração em baixa velocidade)
          × fDriveBiasFront (RWD solta traseira; AWD agarra; FWD puxa)
```

Pôr POTÊNCIA sem investir GRIP gera um carro que canta pneu, **larga mal e sai mal de curva**, mas
tem top speed alto — péssimo em arrancada técnica e circuit, bom em reta longa. AWD (preservado)
disfarça; RWD puro (preservado) sofre. **Skill de montagem = equilibrar torque × aderência × largada.**

**Top speed × aceleração (o paradoxo do drag):**

```
fInitialDriveForce (arrancada)  ⟂  fInitialDragCoeff (arrasto/teto)  ⟂  fInitialDriveMaxFlatVel (cap duro)
```

Mais downforce/arrasto = estável em alta e teto menor + arrancada pior. Build reta aceita arrasto
baixo (instável em alta, mas voa); build circuit aceita arrasto maior por estabilidade.

> **Conclusão de design:** o score e a afinidade (§3.6, §5.4) NÃO somam campos isolados — eles
> cruzam **relações** (torque÷grip, power-to-weight, arrasto÷força, inércia÷antiRoll). É esse
> cruzamento que faz duas builds do mesmo carro divergirem de verdade na pista.

### 1.6 Por que o mesmo carro, dois players, é genuinamente diferente

A física em jogo = baseline do `.meta` (offline, 8 campos) + mods **NATIVOS** do GTA
(engine/turbo/freio/transmissão) + **override server-authoritative** de grip/aero/suspensão (§5.2.1).
Pelas relações da §1.5, mexer em UM eixo desloca VÁRIOS comportamentos ao mesmo tempo:

```
Build A "circuit": grip alto · freio cedo · traseira firme · arrasto moderado
   → o piloto freia tarde, confia na curva, sai limpo

Build B "drag" (MESMO carro): potência alta · grip baixo · RWD solto · arrasto baixo
   → larga cantando pneu, traseira escapa na saída, freia antes, mas voa na reta
```

Quem domina a build A, ao pegar a build B **do mesmo modelo**, precisa REAPRENDER largada, ponto de
freio e controle de traseira. A diferença é física e emergente — não um número no HUD. É isso que o
modelo híbrido (§5.2.1) entrega; e o **risco técnico nº1** da §5.2.1 é o que decide se isso vale
**por instância** (sem ele confirmado, dois carros iguais com builds diferentes colidiriam).

---

## 2. Separação em dois projetos (ciclos de vida distintos)

```
tools/handling-balancer/            ← FASE 1: CLI Node.js (offline, pré-deploy, ZERO FiveM)
├── balance.js                      ← motor (sem regras hardcoded)
├── package.json
├── .env                            ← GEMINI_API_KEY (NUNCA commitar; .gitignore)
├── config/
│   ├── vanilla-reference.json      ← nativos GTA5 (âncora de calibração)
│   ├── tiers.json                  ← matriz-ouro por tier
│   ├── registry.json               ← handlingName → tier_base/maxTier
│   ├── overrides.json              ← ajuste fino + identidade por carro
│   ├── archetypes.json             ← drivetrain+peso → modificadores
│   ├── mods-delta.json             ← multiplicadores de upgrade (CLI prevê Stage 3)
│   └── scan-paths.json             ← raízes do glob (inclui resources/[SCRIPTS]/carmod)
├── out/
│   └── catalog-patch.json          ← SAÍDA: bloco a colar/mesclar em conce/catalog.lua
└── .seal/seal.json                 ← sha256 selado por arquivo

resources/[SCRIPTS]/vhub_p1skill/   ← FASE 2: resource FiveM runtime (camada DERIVADA)
├── fxmanifest.lua
├── shared/
│   ├── config.lua                  ← VHubP1Skill.cfg (+ cfg.rates) — global, sem return
│   ├── events.lua                  ← VHubP1Skill.E (global)
│   └── tier_rules.lua              ← funções PURAS calcTier/scoreFromAlloc (server+client)
├── server/
│   ├── core.lua                    ← sessões, rate O(1), cache de catálogo
│   ├── init.lua                    ← boot: PULL do catálogo do conce + replay-guard
│   ├── tier.lua                    ← recálculo server-authoritative + StateBag writer
│   ├── snapshot.lua                ← telemetria de corrida (escuta vhub_racha)
│   ├── sql.lua                     ← exports.oxmysql (append-only telemetria)
│   └── exports.lua                 ← getVehicleTier/Score/Affinity (read-only público)
└── client/
    ├── handling.lua                ← aplica override server-auth (grip/aero/susp) — só lê StateBag
    └── hud.lua                     ← lê StateBag, renderiza. Zero lógica, zero polling.
```

> **NÃO HÁ tabela própria de identidade do veículo.** A v1 propunha
> `vhub_p1skill_vehicles`/`_alloc`. Removidas: violavam L-04 (segunda fonte de verdade) e seu
> requisito de "configurar num lugar só". A identidade mora no catálogo do conce; a alocação atual
> por placa deriva de `getVehicleState(plate).customization.mods` (já persistido pelo conce).
> A ÚNICA tabela do p1skill é `vhub_p1skill_telemetry` (append-only, dado que é genuinamente seu).

---

## 3. Fase 1 — Pipeline offline (CLI Node.js)

### 3.1 Responsabilidades

| Módulo | Responsabilidade única |
|--------|------------------------|
| `importer.js` | Extrai `.zip/.rar/.oiv`, descobre `.meta` por glob, normaliza nome canônico em TODOS os arquivos do mod |
| `profiler.js` | Fingerprint do veículo + match com nativo + score determinístico + tier sugerido |
| `balance.js` | Lê config, aplica valores-alvo, substituição **cirúrgica** linha-a-linha no XML |
| `catalogEmitter.js` | Gera `out/catalog-patch.json` — o bloco do catálogo (key→{tier_base,handling_name,archetype,...}) pronto p/ mesclar em `conce/shared/catalog.lua` |
| `gemini.js` | IA **assistente** de identidade (não decisora). Degrada se sem chave/quota. |

### 3.2 Pipeline de importação (`node balance.js import <arquivo>`)

```
1. EXTRAIR      → .zip/.rar/.oiv → workspace/imports/<CANONICAL>/
2. DESCOBRIR    → vehicles.meta, handling.meta, carcols.meta, carvariations.meta (glob)
3. NORMALIZAR   → nome canônico = <modelName> do vehicles.meta (minúsculo) → aplica em
                  handlingName/gameName/modelName de TODOS os .meta (1 nome canônico — L-07)
4. FINGERPRINT  → mass, driveForce, driveBias, gears, gripMax/Min, drag, steeringLock, suspRaise
5. MATCH NATIVO → similaridade cosine contra vanilla-reference.json → top-3 {native,similarity,tier}
6. SCORE GLOBAL → 0–1000 (§3.6), normalizado por tier (sem viés)
7. TIER SUGERIDO→ score → tier (determinístico). IA só ajusta gripModifier e nomeia arquétipo.
8. EMITIR PATCH → grava out/catalog-patch.json (NÃO escreve no catalog.lua direto: o dev revisa
                  e mescla; respeita CORE/owner do conce)
```

### 3.3 IA como assistente (Gemini) — não decisora

A IA recebe: fingerprint + nome real + top-3 nativos + tier determinístico. Retorna **apenas**:

```json
{
  "identity": "Muscle car traseiro pesado, instável em curvas rápidas",
  "archetype": "rwd_heavy",
  "gripModifier": 0.92,
  "confidenceNote": "Tier A compatível com Banshee nativo"
}
```

O **tier é definido pelo score determinístico**. A IA ajusta o `gripModifier` de identidade e nomeia
o arquétipo. Se a IA falhar (timeout, quota, sem chave) → pipeline continua com `gripModifier: 1.0`
e arquétipo derivado por regra (drivetrain+peso de `archetypes.json`). **Nenhum passo de runtime
depende da IA** — ela só toca config offline, sempre revisada pelo dev.

```bash
# .env (NUNCA commitar — entra no .gitignore)
GEMINI_API_KEY=...
GEMINI_MODEL=gemini-1.5-flash      # padrão econômico; -pro para análise mais rica
```

> O package usa `@google/generative-ai`. A chamada Gemini é o ÚNICO ponto de rede do pipeline e é
> sempre opcional. Saída da IA entra em `overrides.json`/`registry.json` com tag `_profiledBy:"gemini"`
> e `_confidence` — auditável e reversível.

### 3.4 Taxonomia de campos — LER tudo, MODIFICAR pouco, PRESERVAR o resto (+ LATARIA)

O `handling.meta` real da skyline tem ~48 campos físicos (verificado no arquivo). O pipeline os
trata em **três baldes**. Decisão do dono (2026-06-15): **reescrever só o núcleo de performance;
preservar todo o resto, incluindo a LATARIA**. Ler ≠ escrever.

```
(A) LÊ — fingerprint completo (alimenta o score; NUNCA é escrito)
    O profiler lê TODOS os campos para classificar com honestidade. Leitura pura.
      fMass · vecInertiaMultiplier · vecCentreOfMassOffset · fDriveBiasFront · nInitialDriveGears
      fInitialDriveForce · fDriveInertia · fClutchChangeRateScaleUp/DownShift · fInitialDriveMaxFlatVel
      fInitialDragCoeff · fBrakeForce · fBrakeBiasFront · fHandBrakeForce · fSteeringLock
      fTractionCurveMax/Min/Lateral · fTractionBiasFront · fTractionLossMult · fLowSpeedTractionLossMult
      fTractionSpringDeltaMax · fCamberStiffnesss · fSuspensionForce · fSuspensionComp/ReboundDamp
      fSuspensionUpper/Lower/Raise/BiasFront · fAntiRollBarForce/BiasFront · fRollCentreHeightFront/Rear
      SubHandlingData(CCarHandlingData) · AIHandling · strModelFlags · strHandlingFlags · fPercentSubmerged

(B) MODIFICA — núcleo de performance (8 campos: tier → override → clamp)
      fInitialDriveForce      ← potência (sem scaling por fMass — §3.6)
      fInitialDragCoeff       ← arrasto / teto de velocidade
      fInitialDriveMaxFlatVel ← teto de velocidade
      fBrakeForce             ← frenagem
      fTractionCurveMax       ← grip (teto)
      fTractionCurveMin       ← grip (piso; preserva proporção Min/Max original)
      fAntiRollBarForce       ← estabilidade base
      fDriveInertia           ← resposta de aceleração

(C) PRESERVA — identidade + feel + LATARIA (NUNCA escreve; QUALQUER campo fora de (B))
    Drivetrain/feel : fDriveBiasFront · fSteeringLock · vecInertiaMultiplier · vecCentreOfMassOffset
                      fClutchChangeRateScale* · fTractionCurveLateral · fLowSpeedTractionLossMult
                      fTractionSpringDeltaMax · fCamberStiffnesss · fHandBrakeForce · fBrakeBiasFront
                      fTractionBiasFront · fTractionLossMult · nInitialDriveGears · AIHandling · flags
    Suspensão       : fSuspensionForce · fSuspensionComp/ReboundDamp · fSuspensionUpper/Lower/Raise
                      fSuspensionBiasFront · fAntiRollBarBiasFront · fRollCentreHeightFront/Rear · SubHandlingData
 🛑 LATARIA / dano  : fCollisionDamageMult · fDeformationDamageMult · fWeaponDamageMult
    (NUNCA, JAMAIS)   fEngineDamageMult · strDamageFlags
                      + arquivos visuais INTEIROS: carcols.meta · carvariations.meta · *.yft · *.ytd
                      + vehicles.meta (defaultBodyHealth · damageMapScale · weaponForceMult · modelo)
```

**Regra dura da LATARIA:** os multiplicadores de colisão/deformação/dano e todo o conteúdo visual
(kits de mod, variações de carroceria, modelos `.yft/.ytd`) definem como o carro **bate, deforma e
parece**. São identidade pura — o pipeline **NUNCA** os lê para modificar nem os reescreve. Só
`handling.meta`, e dentro dele só os 8 campos do balde (B).

> **Sem injeção de anti-capotamento (mudança vs. v3 do balancer).** Como o dono mandou preservar
> COM, suspensão e inércia, o pipeline **não injeta** `vecCentreOfMassOffset.z`/`fRollCentreHeight`/
> `fSuspensionReboundDamp`. Confia-se na geometria original do mod. Se um carro capotar demais, o
> ajuste é manual via `overrides.json` (revisado), nunca automático.

#### Mapa dos 5 eixos do orçamento → clusters reais (a ponte UX ↔ física)

Os 5 eixos que o player aloca na oficina (§1.4) são a **camada de UX**; cada um agrega um cluster de
campos reais. MODIFICA toca só o **representante** do eixo; o resto do cluster é PRESERVADO e só LIDO:

```
POTÊNCIA  → representante: fInitialDriveForce   | lê também: fDriveInertia, nInitialDriveGears, clutch
GRIP      → representante: fTractionCurveMax/Min | lê também: Lateral, BiasFront, LossMult, LowSpeed
FRENAGEM  → representante: fBrakeForce           | lê também: fBrakeBiasFront, fHandBrakeForce
AERO      → representante: fInitialDragCoeff      | lê também: fInitialDriveMaxFlatVel
SUSPENSÃO → representante: fAntiRollBarForce      | lê também: suspensão completa, rollcentre, inércia
```

A altura da suspensão e a inércia carregam o "feeling": preservá-las mantém dois carros do mesmo
tier com personalidades distintas (baixo → asfalto, alto → off-road). O HUD usa esses valores
preservados (espelhados no catálogo via `drive_bias`/`susp_raise`) para a afinidade por pista.

### 3.5 `archetypes.json`

```json
{
  "rwd_light":  { "gripModifier": 1.05, "comZOffset": -0.02, "note": "ágil, sai de traseira fácil" },
  "rwd_heavy":  { "gripModifier": 0.92, "comZOffset": -0.05, "note": "instável em curva rápida" },
  "fwd_light":  { "gripModifier": 1.02, "comZOffset": -0.03, "note": "subesterçante no limite" },
  "fwd_heavy":  { "gripModifier": 0.95, "comZOffset": -0.04, "note": "difícil de rotar traseiro" },
  "awd_light":  { "gripModifier": 1.08, "comZOffset": -0.04, "note": "equilibrado, versátil" },
  "awd_heavy":  { "gripModifier": 1.00, "comZOffset": -0.06, "note": "estável, acelera bem" }
}
```

Arquétipo = `fDriveBiasFront` (0=RWD, ~0.5=AWD, 1=FWD) + `fMass`.

### 3.6 Score global (0–1000) — cruzando relações, ancorado no nativo

O score NÃO soma campos isolados — ele cruza as **relações** da §1.5 e normaliza cada eixo contra o
**carro nativo de referência do tier** (lógica comparativa nativa para travar limites):

```js
// normalizeVsNative(valor, ref) = posição do carro relativa ao nativo do tier (0..1)

// 1. ACELERAÇÃO em jogo: SÓ driveForce (massa cancela — §1.5). Nunca escalar por fMass.
const accel  = normalizeVsNative(driveForce, ref.driveForce)

// 2. LARGADA/wheelspin: torque sem grip patina (emergente real do GTA5)
const launch = clamp01(gripRel / driveRel) * (isAWD ? 1.0 : isRWD ? 0.85 : 0.92)

// 3. GRIP de curva   4. FRENAGEM   5. ESTABILIDADE (antiRoll + suspensão + inércia)
const grip      = normalizeVsNative(gripMax, ref.gripMax)
const brake     = normalizeVsNative(brakeForce, ref.brakeForce)
const stability = stabilityFrom(antiRollBar, suspForce, inertiaZ)   // peso entra AQUI

const score = Math.round(
  ( accel*0.30 + launch*0.10 + grip*0.30 + brake*0.15 + stability*0.15 ) * 1000
)

// 6. LIMITE COMPARATIVO NATIVO: power-to-weight baliza o tier_max (não vira accel em jogo,
//    mas impede um caminhão com driveForce absurdo de virar S+). pwr = driveForce / (mass/1000)
const tier = clampToNativeBand(calcTier(score), pwrToWeight, ref)
```

> **Por que assim:** `fMass` NÃO afeta aceleração (§1.5) → o eixo accel usa só `driveForce`. O peso
> entra em `stability` (inércia/rolagem) e no **clamp comparativo nativo** (`power-to-weight` trava o
> teto de tier). A largada (`launch`) penaliza torque sem grip — o "canta pneu" vira custo de score.

| Tier | Score | Nativo de referência |
|------|-------|----------------------|
| D | 0–199   | Blista |
| C | 200–399 | Kuruma |
| B | 400–599 | Elegy |
| A | 600–749 | Banshee |
| S | 750–899 | Zentorno |
| S+| 900–1000| Krieger |

`normalizeVsNative` e `clampToNativeBand` garantem que **nenhum carro mod ultrapasse o limite físico
do nativo do seu tier** — é a "lógica comparativa de carro nativo para definir limites de tier".

### 3.7 Substituição cirúrgica de XML

Edição linha-a-linha por regex: só o conteúdo de `value="..."` / `z="..."` dos campos-alvo, dentro
do bloco `<Item type="CHandlingData">` do `handlingName` correto. Preserva BOM/UTF-8, line-endings,
comentários, `<Item type="NULL"/>` e `SubHandlingData`. Arquivo só grava se houver mudança real
(diff limpo). Múltiplos carros no mesmo arquivo → cada bloco processado pelo seu `handlingName`.

### 3.8 CLI completa

```bash
node balance.js init-vanilla       # baixa/parseia nativos GTA5 → vanilla-reference.json (1x, commitar)
node balance.js import <arquivo>   # extrai, normaliza nome, fingerprint, score, tier sugerido
node balance.js profile --name <N> --realname "<carro real>"   # IA Gemini (opcional)
node balance.js scan               # lista handlingNames reais, tier, órfãos, duplicatas
node balance.js plan               # diff campo-a-campo + preview do catalog-patch. NÃO grava
node balance.js apply              # backup + cirúrgico + seal + build-report + catalog-patch.json
node balance.js verify             # sha256 vs seal (exit 1 se drift — gate de CI)
node balance.js seal               # re-sela estado atual (pós-edição manual aprovada)
node balance.js restore [--backup <id>]   # restaura backup
node balance.js stage3 --name <N>  # simula Stage 3 full e projeta maxTier
```

**Exit codes:** `0` ok · `1` seal drift · `2` erro de config · `3` erro de I/O · `4` erro Gemini.

### 3.9 Segurança operacional + selo

- Backup automático antes de todo `apply` (`.backups/<ts>/<path>`).
- `plan` é o padrão mental; `apply` exige intenção explícita; idempotente (2ª run = no-op).
- `seal.json` (commitado) = sha256 do estado aprovado por `.meta`. `verify` recomputa e falha o PR
  se alguém editou `.meta` à mão. GitHub Action roda `verify --json` no PR.

---

## 4. A ponte: catálogo único estendido (conce é o dono)

### 4.1 Campos novos no `catalog.lua` (proposta de extensão — gate do conce)

O catálogo já tem `stats={vel,acel,freio,dir}` por veículo. A extensão **adiciona** os campos do
p1skill na MESMA entrada, mantendo o conce como dono único:

```lua
-- shared/catalog.lua (conce) — EXTENSÃO PROPOSTA (campos opcionais, retrocompatíveis)
a80 = {
  nome='Toyota Supra A80', preco=420000, tipo='car', categoria='sport',
  stats={vel=90,acel=88,freio=78,dir=86}, tags={'mod'},
  -- ↓ campos do p1skill (gerados/revisados pelo pipeline offline; default seguro se ausentes)
  p1 = {
    handling_name = 'a80',          -- âncora ao <handlingName> do .meta selado (== key)
    tier_base     = 'A',            -- chão físico do .meta
    tier_max      = 'S',            -- teto com Stage 3 (anti-salto: ≤ +1? ver §5)
    archetype     = 'rwd_heavy',
    grip_modifier = 0.92,
    base_alloc    = { potencia=160, grip=120, frenagem=120, aero=180, suspensao=160 },
    drive_bias    = 0.0,            -- preservado do .meta (afinidade + wheelspin §1.5)
    susp_raise    = -0.02,          -- preservado do .meta (afinidade off-road)
    mass          = 1615,           -- preservado (power-to-weight + agilidade §1.5)
    inertia_z     = 1.3,            -- preservado (sensação de peso ao girar)
    low_speed_loss= 1.8,            -- preservado (fLowSpeedTractionLossMult — wheelspin)
    seal          = 'sha256:...'    -- hash do .meta no momento do apply (auditoria)
  }
}
```

> **Por que dentro do catálogo e não em tabela do p1skill:** atende seu pedido literal — "configurar
> o catálogo num lugar só e valer para todos". conce, garage, racha e p1skill já leem `getCatalog()`.
> Adicionar `p1` ali significa **zero segunda fonte de verdade** (L-04) e zero novo mapa de nomes.

### 4.2 Como cada resource consome (sem competir — L-04/L-09)

```
vhub_conce   → DONO. Define catalog.p1 (campos vindos do pipeline, revisados por humano).
vhub_garage  → já cacheia getCatalog() no boot; passa a exibir tier_base na vitrine (read-only).
vhub_p1skill → PULL do getCatalog() no boot; calcula score/tier/afinidade DINÂMICOS por placa.
vhub_racha   → lê tier via exports.vhub_p1skill:getVehicleTier(plate) p/ gatekeeping de evento.
```

Nenhum deles escreve identidade fora do conce. O p1skill escreve apenas **StateBags efêmeras** e
**sua tabela de telemetria** (append-only).

---

## 5. Fase 2 — Resource FiveM `vhub_p1skill` (camada derivada)

### 5.1 Responsabilidades por arquivo

| Arquivo | Responsabilidade única |
|---------|------------------------|
| `shared/tier_rules.lua` | `calcTier(score)`, `scoreFromAlloc(alloc,budget)` — PURAS, sem I/O |
| `shared/config.lua` | thresholds, `cfg.rates`, campos do HUD (global `VHubP1Skill.cfg`, sem return) |
| `server/init.lua` | boot: `catalog = exports.vhub_conce:getCatalog()`; schema telemetria; replay-guard |
| `server/tier.lua` | lê mods via conce, calcula alloc/score/tier/afinidade, escreve StateBag |
| `server/snapshot.lua` | escuta `vHub:raceFinished` → grava telemetria (append-only) |
| `server/exports.lua` | `getVehicleTier/Score/Affinity(plate)` — read-only público |
| `client/handling.lua` | aplica override server-auth (grip/aero/susp) lido da StateBag `vhub_p1_hnd`; re-clampa antes de `SetVehicleHandlingFloat`; zero decisão |
| `client/hud.lua` | lê StateBag, renderiza. Zero lógica, zero polling, 0.00 ms NUI fechada |

### 5.2 Tier dinâmico — fluxo server-authoritative (L-01)

```
TRIGGER: vHub:vehicleCommitted(ev)   ← emitido pelo VState do conce (escritor único)
         -- shape (primitivo L-19): { plate=string, source=string, changed={customization=bool,health=bool,fuel=bool} }
         -- decisão #26/F0: shape de tabela único; CORE chain inerte desde PRONTUÁRIO (#24)
         (a oficina comita customization via conce; o p1skill REAGE ao commit)
         filtro: ev.changed.customization == true OU ev.source == 'tune'

SERVIDOR (server/tier.lua, dentro de CreateThread — usa Await):
  1. st    = exports.vhub_conce:getVehicleState(plate)          -- PRONTUÁRIO (nunca core)
  2. mods  = (st.customization or {}).mods or {}                -- já sanitizado pelo conce (P-4)
  3. entry = catalog[ norm(st.model) ]                          -- model vem do vstate/dossier
  4. base  = entry and entry.p1                                 -- identidade do .meta (conce é dono)
     if not base then return end                                -- carro fora do p1 → sem HUD tier
  5. budget = BUDGET[base.tier_base]
  6. alloc  = calcAllocation(mods, base, budget)                -- soma == budget (invariante)
  7. score  = scoreFromAlloc(alloc, budget)                     -- 0–1000 (pura)
  8. tier   = clampMax(calcTier(score), base.tier_max)          -- nunca acima do teto do catálogo
  9. aff    = calcAffinity(alloc, base)                         -- 5 contextos 0..1
 10. Entity(veh).state:set('vhub_p1', {                         -- 1 StateBag agregada (delta-gated)
        tier=tier, score=score,
        alloc=alloc,                  -- {potencia,grip,frenagem,aero,suspensao} primitivos
        affinity=aff,                 -- {reta,curva,montanha,drift,cidade} primitivos
        base=base.tier_base, max=base.tier_max, arch=base.archetype
      }, true)
```

> **Diferenças críticas vs. v1:**
> - Gatilho real = `vHub:vehicleCommitted` (existe no PRONTUÁRIO), não um evento inventado.
> - Leitura de mods = `exports.vhub_conce:getVehicleState` (P-3), não `exports.vhub:getVehicleState`.
> - **Uma** StateBag `vhub_p1` agregada (não 4) — menos sync, payload primitivo (L-19, A-08).
> - O servidor mantém `alloc` como **dado derivado em memória/telemetria** — NÃO escreve em SQL de
>   identidade (não existe). O `.meta` (arquivo) continua estático (P-1). O que muda fisicamente em
>   runtime é um **override de entidade viva** (grip/aero/susp), server-authoritative — §5.2.1.

### 5.2.1 Manifestação física híbrida (decisão do dono 2026-06-15)

A build só é "sentível" se virar física. Como o GTA5 **não tem mod nativo de grip/aero/suspensão
fina**, o p1skill usa um modelo **híbrido server-authoritative** — cada eixo vira física pelo
caminho que existe:

| Eixo | Como vira física real |
|------|-----------------------|
| POTÊNCIA  | mod **NATIVO** do GTA (`engine` 11 + `turbo` 18) — o jogo aplica sozinho |
| FRENAGEM  | mod **NATIVO** (`brakes` 12) |
| (top speed) | mod **NATIVO** (`transmission` 13) |
| GRIP      | **OVERRIDE** server-auth: `fTractionCurveMax/Min` |
| AERO      | **OVERRIDE** server-auth: `fInitialDragCoeff` |
| SUSPENSÃO | **OVERRIDE** server-auth: `fAntiRollBarForce` (altura visual = mod nativo `suspension` 15) |

```lua
-- SERVIDOR (server/tier.lua, após o recalc do alloc) — fonte única da verdade
local hnd = handlingFromAlloc(alloc, base)          -- valores-alvo CLAMPADOS à banda do tier_base
Entity(veh).state:set('vhub_p1_hnd', {              -- 2ª StateBag, só primitivos (L-19)
  grip = hnd.gripMax, gripMin = hnd.gripMin, drag = hnd.drag, antiRoll = hnd.antiRoll
}, true)

-- CLIENTE (client/handling.lua) — SÓ aplica o que o servidor mandou; nunca inventa valor
AddStateBagChangeHandler('vhub_p1_hnd', nil, function(bagName, _, v)
  local veh = <entidade resolvida do bagName>
  if not v then return end
  -- defesa em profundidade: re-clampa no cliente ANTES de aplicar (payload é hostil — manual §6.6)
  SetVehicleHandlingFloat(veh, 'CHandlingData', 'fTractionCurveMax', clamp(v.grip,    1.0, 3.0))
  SetVehicleHandlingFloat(veh, 'CHandlingData', 'fTractionCurveMin', clamp(v.gripMin, 0.8, v.grip))
  SetVehicleHandlingFloat(veh, 'CHandlingData', 'fInitialDragCoeff', clamp(v.drag,    5.0, 20.0))
  SetVehicleHandlingFloat(veh, 'CHandlingData', 'fAntiRollBarForce', clamp(v.antiRoll, 0.1, 1.5))
end)
```

Regras (gates segurança + natives):
- O cliente **NUNCA** inventa handling — só aplica o que veio da StateBag escrita pelo **servidor**.
- Todo valor é clampado à banda física do `tier_base` no servidor **E** re-clampado no cliente.
- O `.meta` (arquivo) permanece intocado — isto é override de entidade viva, não escrita de arquivo.

> ⚠️ **RISCO TÉCNICO Nº1 — VALIDAR ANTES DA FASE 4 (gate `vhub_guardiao_natives`):** em FiveM,
> `SetVehicleHandlingFloat` historicamente altera o handling **compartilhado do MODELO** (todas as
> instâncias do mesmo carro), não da instância. Se for model-wide, **dois players no mesmo modelo
> com builds diferentes COLIDEM** — quebrando exatamente a premissa "o mesmo carro, configurado
> diferente". Validar suporte a override **POR INSTÂNCIA**; se não existir nativamente, o fallback é
> aplicar o override **só ao veículo do player local ao entrar/atualizar** (cada cliente ajusta o
> próprio carro; o de terceiros aparece com handling do tier-base). **Sem essa validação, a Fase 4
> não começa.**

### 5.3 Orçamento e regras (shared/tier_rules.lua — puro)

```lua
-- shared/tier_rules.lua — funções PURAS de tier (server + client, sem I/O)
VHubP1Skill = VHubP1Skill or {}
local TR = {}; VHubP1Skill.TR = TR

TR.BUDGET = { D=500, C=600, B=700, A=800, S=900, ['S+']=1000 }

-- range de alocação por atributo (% do budget) — anti-P2W (máx 35%)
TR.ALLOC_RANGE = {
  potencia={min=0.10,max=0.35}, grip={min=0.08,max=0.35},
  frenagem={min=0.08,max=0.30}, aero={min=0.08,max=0.30}, suspensao={min=0.08,max=0.28},
}

TR.TIER_SCORE = {
  D={min=0,max=199}, C={min=200,max=399}, B={min=400,max=599},
  A={min=600,max=749}, S={min=750,max=899}, ['S+']={min=900,max=1000},
}

-- score 0-1000 a partir da alocação (pesos = impacto competitivo real)
function TR.scoreFromAlloc(alloc, budget)
  local w = { potencia=0.35, grip=0.30, frenagem=0.15, aero=0.10, suspensao=0.10 }
  local s = 0
  for k, wt in pairs(w) do s = s + ((alloc[k] or 0) / budget) * wt * 1000 end
  return math.floor(math.min(s, 1000))
end

-- score → tier key (ordem determinística, sem depender de pairs)
function TR.calcTier(score)
  local order = { 'D','C','B','A','S','S+' }
  for _, t in ipairs(order) do
    local r = TR.TIER_SCORE[t]
    if score >= r.min and score <= r.max then return t end
  end
  return 'D'
end
```

### 5.4 Afinidade por tipo de pista (server/tier.lua)

```lua
-- afinidade 0..1 por contexto, cruzando alocação + identidade preservada do .meta (§1.5)
local function calcAffinity(alloc, base, budget)
  local isRWD = base.drive_bias < 0.2
  local isAWD = base.drive_bias >= 0.2 and base.drive_bias <= 0.8
  local heightBonus = math.max(0, base.susp_raise * 20)
  local n = function(k) return (alloc[k] or 0) / budget end   -- normaliza 0..1
  local c01 = function(v) return math.max(0, math.min(1, v)) end

  -- agilidade penalizada por inércia/peso (carro pesado gira devagar — §1.5)
  local agility = c01(1.30 - (base.inertia_z or 1.0) * 0.30)   -- ~1.0 leve, ~0.7 pesado
  -- déficit de largada: torque sem grip canta pneu (wheelspin — §1.5); AWD disfarça
  local launch  = c01((n('grip') / math.max(n('potencia'), 0.01)) * (isAWD and 1.0 or 0.85))

  return {
    -- Reta: potência + aero, mas largada ruim atrasa quem só tem torque
    reta     = c01(n('potencia')*0.50 + n('aero')*0.35 + launch*0.15),
    -- Curva: grip + frenagem + tração, modulado por agilidade (peso)
    curva    = c01((n('grip')*0.50 + n('frenagem')*0.30
                    + (isAWD and 0.10 or isRWD and -0.05 or 0.05)) * (0.70 + agility*0.30)),
    -- Montanha: suspensão alta + frenagem + grip + bônus de altura
    montanha = c01(n('suspensao')*0.40 + n('frenagem')*0.30 + n('grip')*0.20 + heightBonus),
    -- Drift: grip BAIXO favorece + RWD + potência; carro leve roda mais fácil
    drift    = c01((1 - n('grip')*0.6) + (isRWD and 0.25 or 0.05) + n('potencia')*0.15
                    + (agility-0.8)*0.10),
    -- Cidade: frenagem + grip + suspensão, modulado por agilidade
    cidade   = c01((n('frenagem')*0.45 + n('grip')*0.35 + n('suspensao')*0.20) * (0.80 + agility*0.20)),
  }
end
```

Cruzamentos reais embutidos: **drift inverte grip** (circuit é ruim em drift, drag é bom); **largada
(launch)** penaliza torque sem grip na reta (o "canta pneu" da §1.5); **agilidade** dampeia
curva/cidade/drift conforme a inércia/peso preservados. Mesma plataforma, contextos opostos.

### 5.5 HUD client (client/hud.lua)

```
Regras rígidas:
- NUNCA calcula tier/alloc no client (L-01/A-01)
- NUNCA lê handling.meta em runtime (P-1)
- Lê APENAS a StateBag agregada: Entity(veh).state.vhub_p1
- AddStateBagChangeHandler (zero polling — L-06)
- onVehicleEnter abre; onVehicleExit fecha; NUI fechada = 0.00 ms (sem Draw*)
- onDestroy/cleanup: cancela RAF/interval/listeners (A-07)
```

3 painéis: **Status** (tier+cor, score X/teto, arquétipo, indicador "→ tier max"), **Build**
(barras % POT/GRIP/FRE/AERO/SUSP, total 100%), **Afinidade** (barras reta/curva/montanha/drift/cidade).

### 5.6 SQL — só telemetria (append-only, dado genuinamente do p1skill)

```sql
-- sql/schema.sql — ÚNICA tabela do p1skill (não há tabela de identidade)
CREATE TABLE IF NOT EXISTS vhub_p1skill_telemetry (
  id              INT UNSIGNED NOT NULL AUTO_INCREMENT,
  handling_name   VARCHAR(32)  NOT NULL,
  tier_at_time    VARCHAR(3)   NOT NULL,
  score_at_time   SMALLINT UNSIGNED NOT NULL,
  alloc_snapshot  TEXT         NULL,          -- JSON do alloc no momento da corrida
  accel_0_100_s   FLOAT        NULL,
  top_speed_kmh   FLOAT        NULL,
  race_kind       VARCHAR(16)  NULL,
  measured_at     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  INDEX idx_handling (handling_name),
  INDEX idx_tier (tier_at_time)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

### 5.7 Integração com vhub_racha (telemetria real)

```lua
-- server/snapshot.lua — fecha o loop: teoria → validação in-game → ajuste de overrides offline
AddEventHandler('vHub:raceFinished', function(results)
  if type(results) ~= 'table' then return end
  for _, r in ipairs(results) do
    Citizen.CreateThread(function()
      local st = exports.vhub_conce:getVehicleState(r.plate); if not st then return end
      local entry = Catalog[norm(st.model)]; local base = entry and entry.p1; if not base then return end
      exports.oxmysql:execute(
        'INSERT INTO vhub_p1skill_telemetry (handling_name,tier_at_time,score_at_time,accel_0_100_s,top_speed_kmh,race_kind) VALUES (?,?,?,?,?,?)',
        { base.handling_name, base.tier_base, base.score_base or 0, r.accel0100, r.topSpeed, r.kind })
    end)
  end
end)
```

> Verificar no `vhub_racha` real o **nome exato** do evento de fim de corrida e o **shape** de
> `results` antes de implementar (gate de contrato). O `vHub:raceFinished` acima é placeholder.

### 5.8 Eventos / StateBags

```lua
-- shared/events.lua — global, sem return (anti-fantasma do manual §1)
VHubP1Skill = VHubP1Skill or {}
VHubP1Skill.E = {
  RECALC = 'vhub_p1skill:recalc',         -- server interno (placa mudou mods)
  -- Server → Client: StateBag 'vhub_p1' por entidade-veículo (não evento)
}
```

---

## 6. Constraints (mapeadas às leis reais do vHub)

```
L-01  Servidor autoritativo: tier/score/alloc/afinidade calculados SÓ no server.
L-04  Sem 2ª fonte de verdade: identidade do veículo mora no catalog.lua do conce.
      O p1skill DERIVA; nunca escreve identidade. Única tabela própria = telemetria.
L-05  Native-first: GetVehicleMod/StateBag nativos antes de infra custom.
L-06  Sem polling: AddStateBagChangeHandler + reação a vHub:vehicleCommitted.
L-07  Resource novo com ownership e lifecycle explícitos (este doc + linha no Registro).
L-08  Código em inglês; comentários/HUD/lang em PT-BR.
L-19  Tudo que cruza event/export/NUI vai como primitivo {x=,y=,...}/número/string.
      A StateBag 'vhub_p1' carrega alloc/affinity como tabelas de PRIMITIVOS (sem vetor).
A-01  JS/HUD não decide regra crítica; Lua kernel não renderiza.
A-07  onDestroy cancela RAF/interval/listeners.
A-08  StateBag agregada + delta-gating; nunca 60fps de payload bruto.
PRONTUÁRIO  Estado físico só por exports.vhub_conce:{getVehicleState,saveVehicleState}.
INVARIANTE  soma(alloc) == BUDGET[tier_base]. Servidor rejeita o que quebrar.
ANTI-P2W    Nenhum atributo passa de 35% do budget (ALLOC_RANGE).
META-ESTÁTICO  O ARQUIVO .meta nunca é lido/escrito em runtime; só pelo pipeline offline. Override
            de handling de ENTIDADE VIVA (SetVehicleHandlingFloat) é permitido — mas SÓ
            server-authoritative via StateBag, clampado ao tier (§5.2.1). Não é escrita de arquivo.
HÍBRIDO     Potência/freio/topspeed = mod NATIVO do GTA; grip/aero/suspensão = override server-auth.
            Cliente nunca inventa valor de handling — só aplica o que o servidor escreveu na StateBag.
NÚCLEO-8    A reescrita offline toca SÓ 8 campos de performance (§3.4 balde B). Todo o resto
            do handling.meta é PRESERVADO.
LATARIA     Multiplicadores de colisão/deformação/dano (fCollisionDamageMult, fDeformationDamageMult,
            fWeaponDamageMult, fEngineDamageMult, strDamageFlags) e TODO o conteúdo visual
            (carcols.meta, carvariations.meta, .yft, .ytd, modelo, vehicles.meta) NUNCA são tocados.
```

---

## 7. Dependências do resource

```lua
-- fxmanifest.lua
dependencies {
  'vhub',          -- core (eventos institucionais, getUser)
  'oxmysql',       -- telemetria própria (vhub_p1skill_telemetry)
  'vhub_conce',    -- DONO do catálogo (getCatalog) e do estado físico (getVehicleState)
  'vhub_racha',    -- telemetria de corrida (evento de fim) — confirmar contrato real
}
```

---

## 8. O que `vhub_p1skill` NÃO faz

- Não modifica `.meta` em runtime (isso é o pipeline offline).
- Não é dono da identidade do veículo (isso é `vhub_conce/shared/catalog.lua`).
- Não escreve estado físico (isso é `exports.vhub_conce:saveVehicleState`, via owners).
- Não controla a loja de upgrades, preço, propriedade ou spawn (conce/garage/oficina/economia).
- Não impõe limite de velocidade (anti-cheat do core + governor client opcional).

Cada sistema **consome** o tier via `exports.vhub_p1skill:getVehicleTier(plate)`.

---

## 9. Roadmap incremental (gate por fase)

| Fase | Entrega | Critério de pronto | Gate sugerido |
|------|---------|--------------------|---------------|
| **F0** | Pipeline `init-vanilla`+`scan`+`plan` (read-only) | vanilla-reference gerado; plan sem scaling por fMass; catalog-patch preview | simplicidade |
| **F1** | `apply`+`seal`+CI + `out/catalog-patch.json` | `.meta` selado; CI bloqueia edição manual; patch mesclável | contrato |
| **F2** | Extensão `catalog.p1` no conce (campos opcionais) | conce dono; garage exibe tier_base; retrocompatível | **arquiteto+contrato** (toca conce) |
| **F3** | Resource p1skill: tier ESTÁTICO via catálogo | HUD mostra tier_base do catálogo; PULL no boot | runtime+designer |
| **F4a** | **Validar override POR INSTÂNCIA** (risco nº1 §5.2.1) | PoC: 2 players, mesmo modelo, builds diferentes, sem colisão de handling | **natives (bloqueante)** |
| **F4b** | Tier DINÂMICO + manifestação híbrida | reação a `vHub:vehicleCommitted` recalcula StateBag `vhub_p1` + `vhub_p1_hnd`; cliente aplica grip/aero/susp | natives+performance+seguranca |
| **F5** | Afinidade por pista | HUD com 5 barras de contexto | designer |
| **F6** | Telemetria + validação | integra `vhub_racha`; 0-100/top speed reais → ajusta overrides offline | contrato+performance |

> **Disciplina de rollout (não negociável):** balancear **~15–20 carros primeiro**, nunca 400 de uma
> vez. Os tiers se ajustam EMPIRICAMENTE — ex.: um R34 "de pista" pode acabar acima de um R35
> "pesado"; isso é CORRETO (contexto > números no papel), e a telemetria (F6) confirma. Expandir o
> catálogo só depois do lote inicial estabilizar na pista. Cada fase passa pelo gate de escopo (§1.0).

| Item v1 (carskill.md 1.1) | Por que era irreal | Correção v2.0 |
|---------------------------|--------------------|---------------|
| Tabelas `vhub_p1skill_vehicles`/`_alloc` | 2ª fonte de verdade de identidade (viola L-04 + "configurar num lugar só") | Identidade em `catalog.p1` do conce; p1skill só tem telemetria |
| `exports.vhub:getVehicleState()` | É o homônimo legado/inerte do CORE (PRONTUÁRIO migrou p/ conce) | `exports.vhub_conce:getVehicleState()` |
| Evento `vHub:vehicleModified` | Não existe no código | `vHub:vehicleCommitted(vd,patch,reason)` (contrato real do PRONTUÁRIO) |
| 4 StateBags (`vhub:p1:tier/score/alloc/affinity`) | 4× sync; payload solto | 1 StateBag `vhub_p1` agregada e delta-gated (A-08) |
| Catálogo do p1skill "substitui stats do conce" | inverte o ownership (conce é dono) | catálogo do conce **estendido**; p1skill consome |
| `dependencies vhub_conce` "lê catalog.lua" | leitura de arquivo de outro resource | leitura por `exports.vhub_conce:getCatalog()` (contrato) |
| StateBag entregando tabelas-vetor | msgpack mangle (L-19) | só primitivos cruzam a fronteira |

---

*vHub P1 Skill v2.0 — pipeline offline determinístico (IA Gemini assistente) + camada runtime
derivada do catálogo único do conce. Zero segunda fonte de verdade, zero toque no CORE FROZEN.*
