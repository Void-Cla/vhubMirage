# 🏁 vHub Handling Balancer — Pipeline de Balanceamento de Veículos (AAA+)

**Versão:** 2.0.0 · **Status:** Spec revisada (pronta para implementar) · **Classificação:** Strict Standard
**Objetivo:** Padronização **determinística e auditável** do `handling.meta` de veículos mod (add-on),
garantindo hierarquia de Tiers (D → S+), integridade física (anti-capotamento), teto de velocidade
coerente por tier e **integridade competitiva** (nenhum carro fora do padrão, nenhum edit manual silencioso).

> **Mudança em relação à v1.0:** a v1.0 estava conceitualmente correta no ponto mais importante
> (pré-processar offline em vez de processar em runtime no servidor), mas tinha lacunas que **quebrariam
> em produção**. Esta versão corrige o parsing, o casamento de registro, o cálculo de força/freio, o
> anti-capotamento, e adiciona as camadas que faltavam: **selagem, detecção de drift, validação em jogo,
> normalização de upgrades e segurança operacional (backup/dry-run/relatório).**

---

## 0. Sumário das correções v1.0 → v2.0 (leia primeiro)

| # | Problema na v1.0 | Correção na v2.0 |
|---|------------------|------------------|
| 1 | `registry.json` usava `skyline_r34` mas o `handlingName` real é `SKYLINE` → **0 carros classificados** | Registro casa por `handlingName` (normalizado). Comando `scan` lista os nomes reais. |
| 2 | `xml2js` Parser→Builder **reescreve o arquivo inteiro** (reordena atributos, destrói `<Item type="NULL"/>`, remove comentários, muda formatação) | **Substituição cirúrgica linha-a-linha** por regex escopada ao bloco do `<Item>`. Só os campos-alvo mudam; o resto fica **byte-a-byte idêntico**. |
| 3 | Teto de 280 km/h "garantido" e "impossível de burlar" | **Falso isoladamente.** Upgrades (Stage 1-3) multiplicam `fInitialDriveForce` em runtime, e top speed depende de marchas/inércia. Cap real = **3 camadas** (§8). |
| 4 | `fBrakeForce` calculado por power-to-weight (copiado da fórmula de força) | Freio tem **modelo próprio** (decel-alvo por tier + bias), não escala com potência. |
| 5 | Anti-capotamento = só `vecCentreOfMassOffset z=-0.15` em **todos** os carros | COM offset **relativo, com clamp e opt-out**; anti-capotamento real combina `fTractionBiasFront`, `fRollCentre*`, `fAntiRollBarForce`, suspensão e downforce (§5.3). |
| 6 | Sobrescreve `.meta` in-place, sem rede de segurança | **Backup automático**, `--dry-run`, diff preview, relatório de build, exit codes para CI. |
| 7 | Sem como detectar edit manual ("selado" era só retórica) | **Seal + drift detection**: hash assinado por arquivo, commitado; CI falha se um `.meta` divergir do tier selado. |
| 8 | Sem camada de override por carro | `overrides.json`: tier define o padrão, override afina **um campo de um carro** sem quebrar o tier. |
| 9 | Pasta errada (`[TOOLS]/vhub_testrunner/`) | Ferramenta Node própria em `tools/handling-balancer/` (§14). Este `.md` é a spec. |

---

## 1. Decisão arquitetural: pré-processamento (CLI) — **mantida e correta**

O balanceamento **não roda em Lua no servidor**. O servidor FiveM apenas lê os `.meta` nativamente (C++ da
engine) no boot — zero loop, zero thread, zero impacto em `resmon` (alinhado a **L-05/L-06** do vHub Mirage).

```
[1] Dev coloca o carro mod na árvore local de recursos
[2] Dev classifica o carro em registry.json (tier por handlingName)
[3] node balance.js plan        → mostra o diff, NÃO grava
[4] node balance.js apply       → grava (com backup) + gera build-report.json + atualiza seal
[5] node balance.js verify      → confere que tudo bate com tier+seal (roda no CI também)
[6] commit + deploy → servidor lê os .meta já selados
```

**Por que CLI e não runtime:** reescrever XML por restart adiciona latência de boot e CPU; pior, criaria
uma segunda fonte de verdade física em runtime (proibido por **L-04**). O `.meta` é a fonte estática; o
estado dinâmico do veículo já vive no PRONTUÁRIO (`vhub_vehicle_state`) e não tem relação com este pipeline.

---

## 2. Escopo honesto — o que o pipeline resolve e o que **não** resolve sozinho

**Resolve (offline, determinístico):**
- Normaliza força, arrasto, grip, freio, marchas e estabilidade de cada carro para o padrão do seu tier.
- Garante consistência de identidade física entre dezenas/centenas de carros.
- Detecta e bloqueia (no CI) qualquer `.meta` editado fora do padrão.

**NÃO resolve sozinho (precisa das camadas dos §5.3, §7, §8):**
- **Teto de velocidade absoluto.** `fInitialDriveMaxFlatVel` é apenas o ceiling *do drive force base*. O top
  speed real também depende de `nInitialDriveGears`, `fDriveInertia`, arrasto **e dos upgrades comprados**.
  Dois carros no mesmo tier com marchas diferentes terão top speed diferente. → §5.2 normaliza marchas; §8
  trata upgrades; §12 valida empiricamente.
- **Anti-cheat de velocidade.** O `.meta` define o **chão físico**; quem injeta velocidade por trainer/teleport
  é pego pelo servidor (validação de posição/velocidade server-side já existente no vHub). As duas coisas são
  complementares, não a mesma.
- **Sensação de direção (feel).** Números de tier são **ponto de partida**, não verdade final. Tier só fica
  "fechado" depois da validação em pista (§12).

> ⚠️ **Premissa física a validar:** os valores de "Top Speed Esperado" da matriz (§4) são **estimativas a
> confirmar in-game**. A relação entre `fInitialDriveMaxFlatVel` e km/h real não é linear nem documentada
> oficialmente e varia com marchas/upgrades. Trate a matriz como *seed*, não como garantia.

---

## 3. Modelo de dados — 4 arquivos de config (com schema e validação)

Toda a "inteligência" mora em config versionada, não no código. O `balance.js` é só o motor.

```
tools/handling-balancer/
├── balance.js            ← motor (sem regras hardcoded)
├── package.json
├── config/
│   ├── tiers.json        ← a Matriz Ouro (§4): valores-alvo por tier
│   ├── registry.json     ← handlingName → tier
│   ├── overrides.json    ← ajuste fino por carro (opcional)
│   └── scan-paths.json   ← onde varrer + exclusões
└── .seal/
    └── seal.json         ← hash selado por arquivo (gerado por `apply`/`seal`)
```

### 3.1 `registry.json` — **chave = `handlingName`, não nome de pasta**

```jsonc
{
  // chave normalizada (UPPERCASE, trim) deve casar com <handlingName> do .meta
  "SKYLINE": "A",
  "SUPRA":   "S",
  "370Z":    "B"
  // carro fora daqui = IGNORADO + reportado por `scan` (nunca tocado silenciosamente)
}
```

> **Por que isso importa:** no `skyline/common/handling.meta` real o `<handlingName>` é `SKYLINE`. A v1.0
> usava `skyline_r34` → não casava → nenhum carro seria balanceado e o dev não saberia. Use `node balance.js
> scan` para listar os `handlingName` reais e detectar duplicatas/órfãos.

### 3.2 `overrides.json` — camada de afinação por carro

```jsonc
{
  "SUPRA": {
    "fBrakeForce": 0.92,          // este S específico freia um pouco melhor
    "fTractionCurveMin": 2.55     // sem sair do tier; sobrescreve só estes campos
  }
}
```
Precedência: **tier (base) → override (patch) → clamps de sanidade (§5.4)**. Override nunca pode ultrapassar
os clamps absolutos do tier (evita "tier S+ disfarçado de A").

### 3.3 `scan-paths.json`

```jsonc
{
  "roots": ["resources/[SCRIPTS]/carmod", "resources/[vehicles]"],
  "exclude": ["**/backup/**", "**/_archive/**"],
  "matchFiles": ["handling.meta"]   // futuro: vehicles.meta para checar modkit/flags
}
```

### 3.4 Validação de config (falha cedo, falha claro)

No início de qualquer comando, validar: todo tier do `registry` existe em `tiers.json`; toda chave de
`overrides` existe no `registry`; nenhum campo de override é desconhecido; `tiers.json` tem todos os campos
obrigatórios. Erro de config → **exit 2** com mensagem PT-BR apontando a linha.

---

## 4. Matriz de Normalização de Tiers (Padrão Ouro) — `tiers.json`

Valores de **referência/seed**. Cada tier define alvos para força, arrasto, grip, freio, marchas e
estabilidade. Coluna de top speed = **a validar** (§12).

| Tier | Ref. Nativa | Massa Base (kg) | Drive (force) | Drag | Grip Max | Grip Min | Marchas | DriveInertia | MaxFlatVel | Top Speed (a validar) |
|------|-------------|-----------------|---------------|------|----------|----------|---------|--------------|------------|------------------------|
| **D** | Blista   | 1100 | 0.140 | 11.5 | 2.05 | 1.90 | 5 | 1.00 | 125 | ~170 km/h |
| **C** | Kuruma   | 1400 | 0.180 | 10.5 | 2.15 | 2.00 | 5 | 1.00 | 130 | ~190 km/h |
| **B** | Elegy    | 1500 | 0.220 | 10.0 | 2.30 | 2.15 | 6 | 1.10 | 132 | ~220 km/h |
| **A** | Banshee  | 1400 | 0.260 | 9.5  | 2.45 | 2.30 | 6 | 1.20 | 135 | ~245 km/h |
| **S** | Zentorno | 1500 | 0.310 | 9.2  | 2.65 | 2.50 | 6 | 1.30 | 138 | ~265 km/h |
| **S+** | Krieger | 1500 | 0.350 | 9.0  | 2.80 | 2.65 | 7 | 1.40 | 140 | **280 km/h (cap-alvo)** |

**Campos de freio e estabilidade por tier** (separados — freio NÃO escala com potência):

| Tier | BrakeForce | BrakeBiasFront | TractionBiasFront | AntiRollBar | COM z-offset (anti-capot.) |
|------|------------|----------------|-------------------|-------------|----------------------------|
| D    | 0.70 | 0.62 | 0.49 | 0.55 | −0.05 |
| C    | 0.80 | 0.62 | 0.49 | 0.60 | −0.06 |
| B    | 0.90 | 0.60 | 0.48 | 0.65 | −0.08 |
| A    | 1.00 | 0.58 | 0.47 | 0.70 | −0.10 |
| S    | 1.10 | 0.56 | 0.47 | 0.75 | −0.10 |
| S+   | 1.20 | 0.55 | 0.46 | 0.80 | −0.12 |

> `MaxFlatVel`/`DriveInertia`/marchas juntos definem o **caráter** do tier (acelera rápido e estica pouco vs.
> estica muito). Esses três precisam andar juntos — mexer só em um quebra a coerência (lição da v1.0).

---

## 5. Algoritmo de normalização

### 5.1 Força motriz — seed por power-to-weight, depois **clamp**

A fórmula da v1.0 mantém **aceleração** constante por tier (accel ≈ F/m → F = (F_base/M_base)·M_mod):

```
driveSeed = (tier.drive / tier.massBase) * modMass
```

**Ressalva técnica importante:** `fInitialDriveForce` é um **coeficiente da engine**, não Newtons. A
aceleração percebida é proporcional principalmente a `fInitialDriveForce` e só fracamente à massa interna —
então escalar por massa **super-recompensa carros pesados**. Por isso o seed é só ponto de partida:

```
driveFinal = clamp(driveSeed, tier.drive * 0.85, tier.drive * 1.15)
```

Carro cuja massa o joga para fora do clamp gera **WARN** (provavelmente está no tier errado, ou a massa do mod
é absurda). O objetivo final é igualar o **tempo 0-100 alvo do tier** (§12), não casar uma fórmula no papel.

### 5.2 Marchas, inércia e ceiling de velocidade

```
fInitialDriveMaxFlatVel = tier.maxVel
nInitialDriveGears      = tier.gears
fDriveInertia           = tier.driveInertia
fInitialDragCoeff       = tier.drag       // "paredão de vento" contra Stage 3
```

### 5.3 Anti-capotamento — feito direito (não só COM offset)

Capotamento em curva alta é **multifatorial**. Aplicar só `COM z=-0.15` em todo carro afunda uns no chão e
deixa outros instáveis. Fazemos um pacote coerente, **com clamp e opt-out por override**:

```
vecCentreOfMassOffset.z = clamp(currentZ + tier.comZ, -0.20, 0.00)   // relativo, nunca absurdo
fTractionBiasFront      = tier.tractionBiasFront                      // equilíbrio dianteira/traseira
fAntiRollBarForce       = tier.antiRollBar                            // resiste à rolagem
fRollCentreHeightFront  = min(current, 0.20)                          // baixa o eixo de rolagem
fRollCentreHeightRear   = min(current, 0.20)
fSuspensionReboundDamp  = clamp(current, 1.6, 2.4)                    // evita quique em meio-fio
```

Em **S/S+** considerar `fDownforceModifier` na `CCarHandlingData` (SubHandlingData) para grudar em alta —
mas isso é opt-in por tier, pois exige a sub-handling presente. Carro com override `"antiRoll": false` pula
este bloco (ex.: off-road que precisa rolar).

### 5.4 Campos preservados vs. modificados vs. injetados

```
MODIFICA (do tier/override):
  fInitialDriveForce, fBrakeForce, fBrakeBiasFront, fInitialDragCoeff,
  fInitialDriveMaxFlatVel, nInitialDriveGears, fDriveInertia,
  fTractionCurveMax, fTractionCurveMin, fTractionBiasFront, fAntiRollBarForce

INJETA/AJUSTA (estabilidade, com clamp):
  vecCentreOfMassOffset.z, fRollCentreHeightFront/Rear, fSuspensionReboundDamp

PRESERVA (identidade intocável — NUNCA toca):
  fDriveBiasFront (RWD/FWD/AWD), fSteeringLock, fSuspensionRaise/Upper/Lower,
  fSeatOffset*, vecInertiaMultiplier, AIHandling, strModelFlags, strHandlingFlags,
  nMonetaryValue, fPetrolTankVolume, qualquer campo não listado acima
```

> **Drivetrain importa:** preservar `fDriveBiasFront` é correto, mas um AWD e um RWD com a mesma força
> *sentem* diferente. A validação (§12) é por carro; o tier é o ponto de partida.

---

## 6. Parsing seguro — **substituição cirúrgica, NÃO round-trip de XML**

Este é o erro mais perigoso da v1.0. O `handling.meta` real do `skyline` tem `<Item type="NULL" />`,
tags self-closing e ordem específica de atributos. `xml2js` Parser→Builder **reescreve tudo** → diff enorme,
risco de quebrar o load no FiveM, e comentários perdidos.

**Regra:** o motor só altera o conteúdo de `value="..."` (ou o atributo `z="..."`) dos campos-alvo, **escopado
ao bloco `<Item type="CHandlingData">`**, deixando o resto do arquivo byte-a-byte idêntico.

```js
// substitui <fName value="..."/> preservando indentação/formato, escopado a um bloco
function setValue(block, field, num) {
  const re = new RegExp(`(<${field}\\s+value=")[^"]*("\\s*/>)`);
  if (!re.test(block)) return { block, changed: false, missing: true };
  return { block: block.replace(re, `$1${num.toFixed(6)}$2`), changed: true };
}

// substitui um atributo (ex.: z) de uma tag vetor
function setAttr(block, tag, attr, num) {
  const re = new RegExp(`(<${tag}\\b[^>]*\\b${attr}=")[^"]*(")`);
  return re.test(block) ? block.replace(re, `$1${num.toFixed(6)}$2`) : block;
}
```

Arquivos com **múltiplos carros** (add-on packs): dividir por `<Item type="CHandlingData">`, processar cada
bloco isolado pelo seu `handlingName`, recompor. Campo-alvo ausente no bloco → **WARN** (não cria campo novo;
criar campo fora de ordem pode corromper o parse nativo).

Guardas de I/O: preservar BOM/encoding (UTF-8), normalizar `handlingName` com `trim().toUpperCase()`,
e **nunca** gravar se nada mudou (mantém o `mtime` e o diff limpo).

---

## 7. Normalização de upgrades / modkit (onde o cap de verdade vaza)

Em servidor RP competitivo o jogador compra **Stage 1-3** na oficina. A engine aplica esses upgrades como
**multiplicadores sobre `fInitialDriveForce`** — ou seja, o carro balanceado para tier A pode virar um foguete
com Stage 3. O `.meta` de handling sozinho **não** controla isso.

Opções (escolher por política do servidor — ver §8):
1. **Normalizar o ganho de upgrade por tier:** o multiplicador de performance da oficina é definido em
   `vehicles.meta`/economia do servidor; o pipeline pode **reportar** carros cujo upgrade os tira do cap.
2. **Travar via drag/MaxFlatVel:** subir `fInitialDragCoeff` e travar `fInitialDriveMaxFlatVel` cria o
   "paredão" — funciona, mas custa aceleração e não é um teto exato.
3. **Governor leve client-side (opcional, §8 camada 2):** cap de velocidade aplicado quando excede o
   teto do tier — barato, determinístico, complementa o meta. Servidor permanece autoritativo.

> A v2 do `scan` deve futuramente ler `vehicles.meta` para reportar carros sem modkit ou com modkit que
> permita upgrades acima do cap do tier. Marcado como **fase 2** (§16).

---

## 8. Teto de 280 km/h — defesa em 3 camadas

Nenhuma camada sozinha garante o cap. Em produção competitiva, combine:

| Camada | Onde | Custo | Garante |
|--------|------|-------|---------|
| **1. Meta (este pipeline)** | `handling.meta` selado | zero runtime | chão físico coerente por tier; dificulta passar do cap |
| **2. Governor client-side** *(opcional)* | resource leve client, lê velocidade e suaviza acima do cap | mínimo (event/timer, L-06) | teto **exato** mesmo com upgrades; servidor segue autoritativo (L-01) |
| **3. Validação server-side** *(já existe)* | vHub valida posição/velocidade | já contabilizado | pega teleport/trainer (anti-cheat real) |

Recomendação: **camada 1 sempre + camada 3 já existe**. Camada 2 só se a validação em pista (§12) mostrar
que upgrades furam o cap de forma relevante. Decisão de produto — não fechar agora.

---

## 9. CLI — comandos e flags

```bash
node balance.js scan      # lista handlingName reais, tier atual, órfãos e duplicatas. NÃO grava.
node balance.js plan      # diff completo (campo a campo, por carro). NÃO grava. Default seguro.
node balance.js apply     # grava com backup + atualiza .seal/seal.json + build-report.json
node balance.js verify    # confere meta == tier+override e meta == seal. Exit≠0 se drift. (CI)
node balance.js seal      # re-sela os hashes atuais (uso após edição aprovada manual)
node balance.js restore   # restaura do backup mais recente (ou --backup <id>)
```

Flags: `--dry-run` (força não gravar em qualquer comando), `--only <handlingName,...>`,
`--tier <D..S+>` (filtra), `--json` (saída machine-readable p/ CI), `--no-backup` (proibido no apply sem
`--force`), `--verbose`.

**Exit codes:** `0` ok · `1` drift/divergência encontrada · `2` erro de config · `3` erro de I/O.

---

## 10. Segurança operacional

- **Backup automático** antes de qualquer `apply`: copia o `.meta` para `.backups/<timestamp>/<path>`. Sem
  backup, sem escrita (a menos de `--no-backup --force`).
- **Dry-run / plan first:** `plan` é o comportamento mental padrão; `apply` exige intenção explícita.
- **Idempotência:** rodar `apply` 2x não muda nada na 2ª vez (valores são absolutos do tier; o seed P2W lê a
  massa *preservada*). `verify` logo após `apply` deve dar exit 0.
- **build-report.json:** lista por carro o tier, campos alterados, valor antes→depois, e warnings. Vai junto
  no commit → revisão fica trivial (e casa com o estilo auditável do vHub).
- **Diffs limpos:** como só os `value=""` mudam, o `git diff` mostra exatamente as linhas tocadas.

---

## 11. Selo + detecção de drift + CI (o "impossível de burlar" de verdade)

A v1.0 dizia "selado" mas não selava nada. Selar = **registrar um hash assinado** do estado aprovado e
**falhar o CI** se alguém editar um `.meta` à mão (dev rogue, merge errado, carro pirata colado na pasta).

```jsonc
// .seal/seal.json (commitado)
{
  "SKYLINE": { "tier": "A", "sha256": "9f2c…", "file": "resources/[SCRIPTS]/carmod/skyline/common/handling.meta" },
  "SUPRA":   { "tier": "S", "sha256": "a17b…", "file": "…" }
}
```

- `apply`/`seal` regravam o hash do estado aprovado.
- `verify` recomputa o hash de cada `.meta` e compara: **divergiu → exit 1** com o nome do carro.
- **Gate de CI** (GitHub Action / pre-commit): roda `node balance.js verify --json`. PR que mexa num
  `handling.meta` sem passar pelo pipeline **não mergeia**. Isso, sim, é integridade competitiva.

> Limite honesto da claim: isto bloqueia **edição na fonte (repo/deploy)**. Não impede um trainer client-side —
> esse é trabalho do anti-cheat server-side (§8 camada 3), que é complementar.

---

## 12. Protocolo de validação em jogo (fecha o tier)

Tier não está "fechado" enquanto não for medido. Protocolo mínimo:

1. **Pista de teste reta e plana** (ex.: aeroporto LSIA) com 2 marcadores e cronômetro (pode reusar telemetria
   do `vhub_velo`/`vhub_racha`).
2. Por carro do tier, medir **0-100 km/h** e **top speed full-tuning (Stage 3 + nitro)**.
3. Comparar com os alvos do tier. Fora da tolerância (ex.: ±5%) → ajustar `overrides.json`, re-`apply`,
   re-medir.
4. Registrar os números medidos no `build-report.json` (campo `validated`) — vira o golden do tier.
5. Carros de referência nativa (Banshee p/ A, Zentorno p/ S…) servem de baseline visual/sensação.

---

## 13. Edge cases e guardas obrigatórias

- `fMass` ausente, `0`, `NaN` ou negativo → **skip + WARN** (não dá pra calcular P2W).
- `handlingName` ausente/duplicado entre arquivos → **WARN** com os dois caminhos (registro fica ambíguo).
- Massa fora da faixa esperada do tier → **WARN** (provável tier errado).
- Campo-alvo ausente no bloco → **WARN**, não injeta (ordem do `.meta` importa para o parse nativo).
- Múltiplos `<Item type="CHandlingData">` no mesmo arquivo → processa cada um pelo seu `handlingName`.
- `<Item type="NULL"/>` e `SubHandlingData` → **intocados** (a substituição cirúrgica nem os enxerga).
- Override com campo desconhecido ou que estoura clamp do tier → **erro de config (exit 2)**.
- Arquivo read-only / em uso → **erro de I/O (exit 3)** com caminho.
- Encoding/BOM preservados; nunca converter line-endings.

---

## 14. Skeleton Node corrigido (núcleo seguro)

`package.json`: `{ "type": "commonjs" }`, sem dependências externas (só `fs`/`path`/`crypto` nativos — adeus
`xml2js`). Isso remove a maior fonte de risco da v1.0.

```js
// balance.js — motor de balanceamento de handling.meta (vHub Handling Balancer)
const fs   = require('fs');
const path = require('path');
const crypto = require('crypto');

const tiers     = require('./config/tiers.json');
const registry  = require('./config/registry.json');
const overrides = require('./config/overrides.json');

const f6 = (n) => Number(n).toFixed(6);
const clamp = (n, lo, hi) => Math.min(hi, Math.max(lo, n));
const norm  = (s) => String(s).trim().toUpperCase();

// substitui <field value="..."/> dentro de um bloco, preservando o resto
function setValue(block, field, num) {
  const re = new RegExp(`(<${field}\\s+value=")[^"]*("\\s*/>)`);
  return re.test(block)
    ? { block: block.replace(re, `$1${f6(num)}$2`), missing: false }
    : { block, missing: true };
}

// computa os valores-alvo de um carro (tier base → override → clamp de sanidade)
function resolveTargets(handlingName, modMass) {
  const tierKey = registry[handlingName];
  const tier = tiers[tierKey];
  const ov = overrides[handlingName] || {};

  const driveSeed = (tier.drive / tier.massBase) * modMass;
  const drive = clamp(driveSeed, tier.drive * 0.85, tier.drive * 1.15);

  const t = {
    fInitialDriveForce:      ov.fInitialDriveForce      ?? drive,
    fInitialDragCoeff:       ov.fInitialDragCoeff        ?? tier.drag,
    fInitialDriveMaxFlatVel: ov.fInitialDriveMaxFlatVel  ?? tier.maxVel,
    fDriveInertia:           ov.fDriveInertia            ?? tier.driveInertia,
    fTractionCurveMax:       ov.fTractionCurveMax        ?? tier.gripMax,
    fTractionCurveMin:       ov.fTractionCurveMin        ?? tier.gripMin,
    fBrakeForce:             ov.fBrakeForce              ?? tier.brakeForce,
    fBrakeBiasFront:         ov.fBrakeBiasFront          ?? tier.brakeBiasFront,
    fTractionBiasFront:      ov.fTractionBiasFront       ?? tier.tractionBiasFront,
    fAntiRollBarForce:       ov.fAntiRollBarForce        ?? tier.antiRollBar,
  };
  // nInitialDriveGears é inteiro — tratado à parte (sem .toFixed)
  return { tier, tierKey, targets: t, gears: ov.nInitialDriveGears ?? tier.gears, comZ: tier.comZ };
}

// processa UM bloco <Item type="CHandlingData"> e devolve o bloco novo + relatório
function processBlock(block) {
  const m = block.match(/<handlingName>([^<]+)<\/handlingName>/);
  if (!m) return { block, report: null };
  const name = norm(m[1]);
  if (!registry[name]) return { block, report: { name, skipped: 'sem-tier' } };

  const massM = block.match(/<fMass\s+value="([^"]+)"/);
  const modMass = massM ? parseFloat(massM[1]) : NaN;
  if (!Number.isFinite(modMass) || modMass <= 0)
    return { block, report: { name, skipped: 'massa-invalida' } };

  const { targets, gears, comZ } = resolveTargets(name, modMass);
  const warnings = [];

  for (const [field, num] of Object.entries(targets)) {
    const r = setValue(block, field, num);
    block = r.block;
    if (r.missing) warnings.push(`campo ausente: ${field}`);
  }
  // marchas (inteiro) + anti-capotamento relativo — omitidos aqui por brevidade

  return { block, report: { name, tier: registry[name], warnings } };
}

// … scan/plan/apply/verify/restore/seal: ler args, varrer scan-paths,
//    dividir por blocos <Item type="CHandlingData">, processar, e:
//      plan   → imprimir diff, não grava
//      apply  → backup + gravar só se mudou + sha256 → .seal/seal.json + build-report.json
//      verify → recomputar sha256 e comparar com seal (exit 1 se divergir)
```

---

## 15. Ownership, lifecycle e placement (L-07)

- **Dono:** equipe de veículos / dev de física. **Lifecycle:** roda **pré-deploy** (local + gate de CI), nunca
  em runtime do servidor.
- **Placement:** mover para `tools/handling-balancer/` (junto dos outros tools de manutenção). Não pertence a
  `[TOOLS]/vhub_testrunner/` — o testrunner é runner Lua server-side e roda queries reais; misturar confunde
  ownership. Este `.md` permanece como a spec do tool (pode virar `tools/handling-balancer/README.md`).
- **npm scripts** (`package.json`):
  ```jsonc
  { "scripts": {
      "scan":   "node balance.js scan",
      "plan":   "node balance.js plan",
      "apply":  "node balance.js apply",
      "verify": "node balance.js verify --json"   // usado no CI
  } }
  ```
- **PT-BR/EN (L-08):** identificadores e flags em inglês; mensagens, warnings e este doc em PT-BR.

---

## 16. Roadmap incremental (MVP → produção competitiva)

| Fase | Entrega | Critério de pronto |
|------|---------|--------------------|
| **0 — MVP** | `scan` + `plan` (read-only) | lista handlingName reais; diff confere com a matriz; zero escrita |
| **1 — Apply seguro** | `apply` (backup + cirúrgico) + `build-report.json` | aplica nos 3 carros (370z/skyline/supra); diff só nas linhas-alvo |
| **2 — Selo + CI** | `seal`/`verify` + gate de CI | PR que edita `.meta` à mão falha o CI |
| **3 — Validação** | protocolo §12 + `overrides.json` afinado | 0-100 e top speed dentro da tolerância por tier |
| **4 — Upgrades/modkit** | leitura de `vehicles.meta`; report de upgrade que fura o cap | nenhum carro passa do cap do tier full-tuning (ou camada 2 ativada) |

---

## 17. Vantagens da abordagem (revisadas, sem exagero)

1. **Zero impacto em runtime:** FiveM lê `.meta` nativamente; nenhum loop/thread Lua no `resmon` (L-05/L-06).
2. **Diffs e revisão triviais:** substituição cirúrgica + `build-report.json` → todo balanceamento é auditável
   linha a linha (combina com o padrão auditável do vHub).
3. **Integridade competitiva real:** o **selo + CI** (§11) impede edição manual na fonte — não é retórica.
4. **Gestão massiva:** mudar um tier em `tiers.json` + `apply` rebalanceia dezenas de carros em segundos, de
   forma reproduzível e reversível (backup/restore).
5. **Honesto sobre limites:** o cap de velocidade é defesa em camadas (§8) e os tiers só fecham após validação
   em pista (§12) — não promete o que `.meta` sozinho não entrega.
```
