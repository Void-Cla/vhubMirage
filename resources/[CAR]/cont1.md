# 🏁 vHub Handling Balancer — v3.0 "AI Identity Edition"

**Versão:** 3.0.0 · **Status:** Spec completa (pronta para implementar)
**Base:** Evolução direta da v2.0 — mantém o motor cirúrgico e o selo, corrige a física, adiciona IA, identidade e tier fluido.

> **Leia primeiro:** Esta spec consolida o `script.md` (v2.0), o `Plano de Organização` e as ideias do `AI-Powered Identity Edition` em um único documento coeso. Seções marcadas com 🆕 são adições; as demais são refinamentos das já existentes.

---

## 0. Sumário de Mudanças v2.0 → v3.0

| # | Problema / Lacuna na v2.0 | Correção / Adição na v3.0 |
|---|---------------------------|---------------------------|
| 1 | **BUG FÍSICO CRÍTICO:** `fMass` não afeta aceleração em GTA5 (F=ma cancela). A fórmula `driveSeed = (tier.drive / massBase) × modMass` penalizava leves e bonificava pesados sem fundamento. | Força normalizada direto ao `tier.drive` com modificador `driveModifier` (±10%). Documentado em §1. |
| 2 | Tier = ranking de força. Dois carros no mesmo tier se comportam igual. | **Preservação de Identidade:** `fDriveBiasFront`, `vecInertiaMultiplier`, `fTractionCurveLateral` e `fSteeringLock` são intocados. Grip normalizado preserva proporção Min/Max original. Descrito em §3. |
| 3 | Sem referência ao handling nativo do GTA5 para calibração. | 🆕 `config/vanilla-reference.json` gerado pelo comando `init-vanilla` com todos os nativos. §2.1. |
| 4 | Tier atribuído manualmente (subjetivo, sem contexto real do carro). | 🆕 Comando `profile` integra a API do Gemini com engenharia de prompt estruturada. §4. |
| 5 | Sem previsão de impacto de upgrades Stage 3 no tier. | 🆕 **Tier Fluido:** `baseTier` + `maxTier`. CLI pré-calcula Stage 3 e aplica freio aerodinâmico preventivo. §5. |
| 6 | Sem camada runtime que exiba tier ao jogador. | 🆕 `vb-core` resource FiveM com HUD de tier, specs e corridas disponíveis. §7. |
| 7 | Sem arquivo central de deltas de upgrade. | 🆕 `config/mods-delta.json` usado pelo CLI (previsão) e pelo HUD (cálculo runtime). §2.5. |

---

## 1. 🔴 Correção Crítica de Física: fMass e Aceleração em GTA5

> **Esta é a correção mais importante da v3.0. Ignorá-la torna o balanceamento matematicamente incorreto.**

Em GTA5, a aceleração de um veículo é:

```
Aceleração ≈ 10 × fInitialDriveForce (m/s²)
```

O jogo calcula a força nas rodas como `fInitialDriveForce × fMass` (torque), mas ao dividir pela massa para obter aceleração (2ª Lei de Newton: a = F/m), o fMass **cancela completamente**. Isso foi confirmado empiricamente por Broughy1322 e documentado em GTACars.net:

> *"fMass — This only impacts collisions. It does not impact performance or handling behaviour in any way."*

**O que muda no algoritmo:**

```javascript
// ❌ v2.0 — errado: escala pelo fMass que não afeta aceleração
const driveSeed = (tier.drive / tier.massBase) * modMass;

// ✅ v3.0 — correto: força é o tier diretamente, com margem de identidade
const driveFinal = clamp(
  tier.drive * (ov.driveModifier ?? 1.0),
  tier.drive * 0.90,   // mínimo: 10% abaixo do tier (carro mais fraco da classe)
  tier.drive * 1.10    // máximo: 10% acima (carro mais forte da classe, sem cruzar teto)
);
```

**Como preservar a sensação de "pesado" sem fMass:**

A percepção de peso vem de outros campos — e estes são preservados como identidade (§3):

| Campo | O que simula |
|-------|-------------|
| `vecInertiaMultiplier.z` | Tempo para mudar de direção — carro "lento" em curvas |
| `vecInertiaMultiplier.x/y` | Balanço de pitch/roll — sensação de massa em frenagem |
| `fSuspensionForce` | Rigidez: mole = bodyroll que parece pesadão |
| `fTractionCurveLateral` | Ângulo de slip antes de deslizar — carros grandes "empurram" mais |
| `fSteeringLock` | Raio de giro — carro largo tem lock menor |

---

## 2. Modelo de Dados v3.0 — 7 Arquivos de Config

```
tools/handling-balancer/
├── balance.js                    ← motor (sem regras hardcoded)
├── package.json
├── .env                          ← GEMINI_API_KEY (não commitar)
├── config/
│   ├── vanilla-reference.json   ← 🆕 todos os nativos GTA5 (gerado por init-vanilla)
│   ├── tiers.json               ← Matriz Ouro (atualizada com campos de tier fluido)
│   ├── registry.json            ← handlingName → tier (agora aceita baseTier/maxTier)
│   ├── overrides.json           ← ajuste fino (agora com modificadores de identidade)
│   ├── mods-delta.json          ← 🆕 multiplicadores de upgrade por tipo/nível
│   └── scan-paths.json          ← caminhos a varrer (inalterado)
└── .seal/
    └── seal.json                ← hash selado por arquivo (inalterado da v2.0)
```

### 2.1 🆕 vanilla-reference.json — A Âncora Nativa

**Geração automática:**
```bash
node balance.js init-vanilla
# Faz fetch do GitHub (andrejmaricc/gta5-complete-handling-files, Aug 2025)
# Parseia e gera config/vanilla-reference.json com todos os nativos
# Roda uma vez; commitar o resultado no repositório
```

**Estrutura:**
```jsonc
{
  "source": "github:andrejmaricc/gta5-complete-handling-files",
  "generatedAt": "2025-08-20T10:00:00Z",
  "vehicles": {
    "BLISTA": {
      "fInitialDriveForce": 0.138, "fInitialDriveMaxFlatVel": 124.0,
      "fInitialDragCoeff": 11.5,   "fBrakeForce": 0.70,
      "fTractionCurveMax": 2.05,   "fTractionCurveMin": 1.90,
      "fDriveBiasFront": 1.0,      "nInitialDriveGears": 5,
      "fDriveInertia": 1.0,
      "vecInertiaMultiplier": { "x": 1.0, "y": 1.6, "z": 1.7 },
      "canonicalTier": "D",
      "identity": "Hatch compacto FWD, ágil em cidade, velocidade final limitada"
    },
    "KURUMA": {
      "fInitialDriveForce": 0.178, "fInitialDriveMaxFlatVel": 130.0,
      "fInitialDragCoeff": 10.5,   "fBrakeForce": 0.80,
      "fTractionCurveMax": 2.15,   "fTractionCurveMin": 2.00,
      "fDriveBiasFront": 0.0,      "nInitialDriveGears": 5,
      "fDriveInertia": 1.0,
      "vecInertiaMultiplier": { "x": 1.0, "y": 1.7, "z": 1.9 },
      "canonicalTier": "C",
      "identity": "Sedã esportivo RWD, equilibrado, bom para corridas de entrada"
    },
    "ELEGY2": {
      "fInitialDriveForce": 0.220, "fInitialDriveMaxFlatVel": 132.0,
      "fInitialDragCoeff": 10.0,   "fBrakeForce": 0.90,
      "fTractionCurveMax": 2.30,   "fTractionCurveMin": 2.15,
      "fDriveBiasFront": 0.0,      "nInitialDriveGears": 6,
      "fDriveInertia": 1.1,
      "vecInertiaMultiplier": { "x": 1.0, "y": 1.6, "z": 1.8 },
      "canonicalTier": "B",
      "identity": "Referência Tier B — esportivo RWD equilibrado e acessível"
    },
    "BANSHEE": {
      "fInitialDriveForce": 0.260, "fInitialDriveMaxFlatVel": 135.0,
      "fInitialDragCoeff": 9.5,    "fBrakeForce": 1.00,
      "fTractionCurveMax": 2.45,   "fTractionCurveMin": 2.30,
      "fDriveBiasFront": 0.0,      "nInitialDriveGears": 6,
      "fDriveInertia": 1.2,
      "vecInertiaMultiplier": { "x": 1.0, "y": 1.5, "z": 1.8 },
      "canonicalTier": "A",
      "identity": "Superesportivo RWD leve — alta velocidade, exige habilidade"
    },
    "ZENTORNO": {
      "fInitialDriveForce": 0.310, "fInitialDriveMaxFlatVel": 138.0,
      "fInitialDragCoeff": 9.2,    "fBrakeForce": 1.10,
      "fTractionCurveMax": 2.65,   "fTractionCurveMin": 2.50,
      "fDriveBiasFront": 0.3,      "nInitialDriveGears": 6,
      "fDriveInertia": 1.3,
      "vecInertiaMultiplier": { "x": 1.0, "y": 1.4, "z": 1.7 },
      "canonicalTier": "S",
      "identity": "Hipercarro AWD — aceleração brutal, colado no chão"
    },
    "KRIEGER": {
      "fInitialDriveForce": 0.350, "fInitialDriveMaxFlatVel": 140.0,
      "fInitialDragCoeff": 9.0,    "fBrakeForce": 1.20,
      "fTractionCurveMax": 2.80,   "fTractionCurveMin": 2.65,
      "fDriveBiasFront": 0.38,     "nInitialDriveGears": 7,
      "fDriveInertia": 1.4,
      "vecInertiaMultiplier": { "x": 1.0, "y": 1.3, "z": 1.6 },
      "canonicalTier": "S+",
      "identity": "Hipercarro de elite AWD — ceiling absoluto do servidor"
    }
    // ... todos os outros nativos populados pelo init-vanilla
  }
}
```

### 2.2 tiers.json — Atualizado com Campos de Tier Fluido

```jsonc
{
  "D":  {
    "drive": 0.140, "drag": 11.5, "maxVel": 125.0, "driveInertia": 1.00, "gears": 5,
    "gripMax": 2.05, "gripMin": 1.90,
    "brakeForce": 0.70, "brakeBiasFront": 0.62, "tractionBiasFront": 0.49,
    "antiRollBar": 0.55, "comZ": -0.05,
    "driveModifierRange": [0.90, 1.10],
    "tierCrossThreshold": 0.155,      // força que cruza para Tier C com Stage 3
    "nativeRef": "BLISTA"
  },
  "C":  {
    "drive": 0.180, "drag": 10.5, "maxVel": 130.0, "driveInertia": 1.00, "gears": 5,
    "gripMax": 2.15, "gripMin": 2.00,
    "brakeForce": 0.80, "brakeBiasFront": 0.62, "tractionBiasFront": 0.49,
    "antiRollBar": 0.60, "comZ": -0.06,
    "driveModifierRange": [0.90, 1.10],
    "tierCrossThreshold": 0.200,
    "nativeRef": "KURUMA"
  },
  "B":  {
    "drive": 0.220, "drag": 10.0, "maxVel": 132.0, "driveInertia": 1.10, "gears": 6,
    "gripMax": 2.30, "gripMin": 2.15,
    "brakeForce": 0.90, "brakeBiasFront": 0.60, "tractionBiasFront": 0.48,
    "antiRollBar": 0.65, "comZ": -0.08,
    "driveModifierRange": [0.90, 1.10],
    "tierCrossThreshold": 0.242,
    "nativeRef": "ELEGY2"
  },
  "A":  {
    "drive": 0.260, "drag": 9.5,  "maxVel": 135.0, "driveInertia": 1.20, "gears": 6,
    "gripMax": 2.45, "gripMin": 2.30,
    "brakeForce": 1.00, "brakeBiasFront": 0.58, "tractionBiasFront": 0.47,
    "antiRollBar": 0.70, "comZ": -0.10,
    "driveModifierRange": [0.90, 1.10],
    "tierCrossThreshold": 0.288,
    "nativeRef": "BANSHEE"
  },
  "S":  {
    "drive": 0.310, "drag": 9.2,  "maxVel": 138.0, "driveInertia": 1.30, "gears": 6,
    "gripMax": 2.65, "gripMin": 2.50,
    "brakeForce": 1.10, "brakeBiasFront": 0.56, "tractionBiasFront": 0.47,
    "antiRollBar": 0.75, "comZ": -0.10,
    "driveModifierRange": [0.90, 1.10],
    "tierCrossThreshold": 0.342,
    "nativeRef": "ZENTORNO"
  },
  "S+": {
    "drive": 0.350, "drag": 9.0,  "maxVel": 140.0, "driveInertia": 1.40, "gears": 7,
    "gripMax": 2.80, "gripMin": 2.65,
    "brakeForce": 1.20, "brakeBiasFront": 0.55, "tractionBiasFront": 0.46,
    "antiRollBar": 0.80, "comZ": -0.12,
    "driveModifierRange": [0.90, 1.05],   // range menor: S+ não tem "classe premium" acima
    "tierCrossThreshold": null,            // S+ é o teto — sem tier acima
    "nativeRef": "KRIEGER"
  }
}
```

### 2.3 registry.json — Agora com Tier Fluido

```jsonc
{
  // Notação simples: tier fixo (carro não muda de classe com upgrades)
  "370Z": "B",

  // Notação fluida: baseTier (stock) → maxTier (Stage 3 full)
  "UNO":    { "baseTier": "B",  "maxTier": "A"  },
  "SKYLINE": { "baseTier": "A",  "maxTier": "A"  },  // fica em A mesmo com S3
  "SUPRA":  { "baseTier": "S",  "maxTier": "S+" },

  // Gerado automaticamente pelo comando profile (Gemini)
  "ELEGY_RH8_FR": {
    "baseTier": "B", "maxTier": "A",
    "_profiledBy": "gemini",
    "_confidence": 0.91,
    "_profiledAt": "2025-10-01T12:00:00Z"
  }
}
```

Quando `maxTier > baseTier`, o pipeline:
1. Sela o `.meta` no **baseTier** (o carro entra na cidade como B)
2. Calcula e aplica o **freio aerodinâmico preventivo** para Stage 3 (§5)
3. Registra ambos no `vehicle-registry.json` para o HUD exibir `"B → A (S3)"`

### 2.4 overrides.json — Agora com Modificadores de Identidade

```jsonc
{
  "SUPRA": {
    // Performance (dentro dos clamps do tier — sem cruzar teto)
    "driveModifier": 1.08,          // +8% força: motor 3.0T forte pra classe
    "fBrakeForce": 0.95,
    "gripRatioModifier": 0.97,       // mantém quase toda a aderência original

    // Identidade (não afetam tier, mas afetam sensação de pilotagem)
    "preserveInertia": true,         // não toca em vecInertiaMultiplier
    "dragCompensation": 0.0          // calculado automaticamente pelo stage3 predict
  },

  "UNO": {
    "driveModifier": 0.95,           // carinho, não foguete
    "gripRatioModifier": 0.90,       // perde grip mais rápido ao deslizar (nervoso)
    "preserveInertia": false,
    // Override manual de inércia: Uno é leve e nervoso
    "vecInertiaMultiplier": { "x": 1.2, "y": 1.8, "z": 2.1 },
    "dragCompensation": 0.08         // Stage 3 precisaria de freio aerodinâmico
  },

  "SKYLINE": {
    "driveModifier": 1.02,
    "gripRatioModifier": 0.95,       // Skyline AWD lida melhor com perda de grip
    "preserveInertia": true          // sensação de peso do R34 preservada
  }
}
```

### 2.5 🆕 mods-delta.json — Multiplicadores de Upgrade

Define como cada melhoria da oficina in-game multiplica os valores de handling. Usado pelo CLI para prever Stage 3 e pelo HUD FiveM para calcular tier efetivo em tempo real.

```jsonc
{
  "_note": "Valores baseados em testes empíricos. Confirmar em pista após Fase 3.",
  "_sources": ["GTACars.net/upgrades", "Broughy1322"],
  "CAR": {
    "engine": {
      "modType": 11,
      "type": "DRIVE_FORCE_MULTIPLIER",
      "levels": { "0": 1.0, "1": 1.075, "2": 1.145, "3": 1.215, "4": 1.285 },
      "comment": "+7.5% por nível de motor"
    },
    "turbo": {
      "modType": 18,
      "type": "DRIVE_FORCE_TOGGLE",
      "onValue": 1.15,
      "affectsTopSpeed": true,
      "comment": "+15% quando turbo instalado"
    },
    "transmission": {
      "modType": 13,
      "type": "VELOCITY_MODIFIER",
      "levels": { "0": 1.0, "1": 1.03, "2": 1.06, "3": 1.09 },
      "affectsOnly": ["fInitialDriveMaxFlatVel"],
      "comment": "Afeta apenas o teto de velocidade (gear ratio)"
    },
    "brakes": {
      "modType": 12,
      "type": "BRAKE_FORCE_MULTIPLIER",
      "levels": { "0": 1.0, "1": 1.05, "2": 1.10, "3": 1.15 }
    },
    "suspension": {
      "modType": 15,
      "type": "GRIP_SUBMODIFIER",
      "effect": "fTractionCurveLateral_delta",
      "levels": { "0": 0, "1": -0.5, "2": -1.0, "3": -1.5, "4": -2.0 },
      "comment": "Suspensão reduz ângulo de slip (mais grip de curva)"
    }
  },
  "BIKE": {
    "engine": {
      "modType": 11,
      "type": "DRIVE_FORCE_MULTIPLIER",
      "levels": { "0": 1.0, "1": 1.09, "2": 1.18, "3": 1.27, "4": 1.36 },
      "comment": "Motos respondem mais ao motor que carros"
    }
  }
}
```

---

## 3. Identidade do Veículo: O Que o Tier Normaliza vs. Preserva

O tier define o **teto de poder**. A **identidade** do carro (como ele chega nesse teto) é preservada.

### 3.1 Campos Normalizados pelo Tier

| Campo | Fórmula v3.0 |
|-------|-------------|
| `fInitialDriveForce` | `tier.drive × driveModifier` — clamp ±10% do tier |
| `fInitialDragCoeff` | `tier.drag × (1 + dragCompensation)` |
| `fInitialDriveMaxFlatVel` | `tier.maxVel` (+ override transmissão no runtime) |
| `fBrakeForce` | `tier.brakeForce × brakeModifier` — clamp ±15% |
| `fTractionCurveMax` | `tier.gripMax × gripModifier` |
| `nInitialDriveGears` | `tier.gears` |
| `fDriveInertia` | `tier.driveInertia` |
| `fBrakeBiasFront` | `tier.brakeBiasFront` |
| `fTractionBiasFront` | `tier.tractionBiasFront` |
| `fAntiRollBarForce` | `tier.antiRollBar` |

### 3.2 Campos Normalizados com Proporção Preservada

O tier define o teto, mas a relação original do mod é mantida:

```javascript
// Grip Mínimo — preserva a proporção Min/Max original
const originalRatio = clamp(modGripMin / modGripMax, 0.75, 1.0);  // sanidade
const adjustedRatio = originalRatio * (ov.gripRatioModifier ?? 1.0);

targets.fTractionCurveMin = clamp(
  targets.fTractionCurveMax * adjustedRatio,
  tier.gripMin * 0.85,   // nunca menos que 85% do mínimo do tier
  targets.fTractionCurveMax  // nunca acima do Max (absurdo físico)
);
```

Um carro que "derrapa fácil" no original continuará derrapando mais que outro do mesmo tier — a diferença é menor (teto controlado), mas o caráter permanece.

### 3.3 Campos Intocados — A "Alma" do Carro

Estes campos **nunca são tocados** pelo balanceador, exceto se explicitamente listados em `overrides.json`:

```
fDriveBiasFront         → RWD / FWD / AWD: define o DNA do carro
fSteeringLock           → raio de curva original
vecInertiaMultiplier    → como o carro "pesa" ao girar (principal portador do "feeling")
fTractionCurveLateral   → ângulo de slip antes de deslizar
fHandBrakeForce         → freio de mão original
fSuspensionForce        → rigidez de suspensão
fSuspensionCompDamp     → amortecimento de compressão
fSuspensionReboundDamp  → amortecimento de rebote
vecCentreOfMassOffset   → COM original ± ajuste de anti-capotamento (somente z, clampado)
```

### 3.4 Exemplo Concreto — Supra vs. Skyline no Tier A

Ambos no Tier A, valores de performance idênticos no teto — experiências completamente distintas:

| Campo | SUPRA (Tier A) | SKYLINE AWD (Tier A) |
|-------|----------------|----------------------|
| `fInitialDriveForce` | **0.268** (drive × 1.03) | **0.261** (drive × 1.00) |
| `fTractionCurveMax` | **2.45** | **2.45** |
| `fTractionCurveMin` | **2.33** (ratio 0.95 — quase não desliza) | **2.18** (ratio 0.89 — desliza mais) |
| `fDriveBiasFront` | **0.0** (RWD puro) ← preservado | **0.38** (AWD) ← preservado |
| `vecInertiaMultiplier.z` | **1.75** ← preservado (gira rápido) | **2.10** ← preservado (sente mais pesado) |
| `fSteeringLock` | **35°** ← preservado | **40°** ← preservado (mais raio) |
| `fInitialDriveMaxFlatVel` | **135.0** | **135.0** |

**Resultado no jogo:**
- A Supra é mais rápida na reta mas desliza mais e exige o piloto a corrigir a traseira.
- O Skyline traciona melhor na saída das curvas e é mais estável na chuva, mas sente mais lento de girar.
- Ambos têm o mesmo teto de velocidade — mas um piloto bom escolhe o carro certo pro traçado.

---

## 4. 🆕 Integração Gemini — Comando `profile`

### 4.1 Visão Geral

O `profile` é o único passo assistido por IA do pipeline. Ele:
1. Lê os metadados do `.meta` do mod
2. Busca o nativo mais próximo em `vanilla-reference.json`
3. Constrói um prompt estruturado e chama o Gemini
4. Recebe JSON com tier sugerido + overrides de identidade
5. Grava em `registry.json` e `overrides.json` com tag `_profiledBy: "gemini"`
6. **Nunca aplica ao `.meta` — o dev revisa e roda `apply` depois**

### 4.2 Instalação

```bash
# No .env (nunca commitar)
GEMINI_API_KEY=sua-chave-aqui
GEMINI_MODEL=gemini-1.5-flash    # mais barato; gemini-1.5-pro para análises mais ricas
```

```json
// package.json — adicionar dependência
{
  "dependencies": {
    "@google/generative-ai": "^0.15.0"
  }
}
```

### 4.3 Uso

```bash
node balance.js profile --name "UNO"    --realname "Fiat Uno Mille 1.0 2001"
node balance.js profile --name "SUPRA"  --realname "Toyota Supra A90 3.0T Turbo 2022"
node balance.js profile --name "SKYLINE" --realname "Nissan Skyline GT-R R34 V-Spec"
```

### 4.4 Engenharia de Prompt — Versão Final

```javascript
function generateProfilePrompt({ name, realname, originalHandling, closestNative }) {
  const driveType = originalHandling.fDriveBiasFront < 0.1 ? 'RWD'
                  : originalHandling.fDriveBiasFront > 0.9 ? 'FWD' : 'AWD';

  return `Você é o Engenheiro Chefe de Física do vHub Handling Balancer para GTA5 FiveM.

HIERARQUIA DE TIERS DO SERVIDOR:
- D  (~170km/h) — carros populares de cidade. Ref. nativa: Blista. Drive: 0.140
- C  (~190km/h) — compactos esportivos de entrada. Ref.: Kuruma. Drive: 0.180
- B  (~220km/h) — esportivos acessíveis. Ref.: Elegy. Drive: 0.220
- A  (~245km/h) — alto desempenho. Ref.: Banshee. Drive: 0.260
- S  (~265km/h) — supercars. Ref.: Zentorno. Drive: 0.310
- S+ (~280km/h) — hipercars (ceiling do servidor). Ref.: Krieger. Drive: 0.350

VEÍCULO A CLASSIFICAR:
- handlingName: ${name}
- Nome real: ${realname}
- fInitialDriveForce (original do mod): ${originalHandling.fInitialDriveForce}
- Tipo de tração: ${driveType} (fDriveBiasFront = ${originalHandling.fDriveBiasFront})
- Marchas: ${originalHandling.nInitialDriveGears}
- vecInertiaMultiplier: ${JSON.stringify(originalHandling.vecInertiaMultiplier)}
- fTractionCurveMax: ${originalHandling.fTractionCurveMax}
- fTractionCurveMin: ${originalHandling.fTractionCurveMin}

NATIVO MAIS PRÓXIMO POR HANDLING (para calibração):
${JSON.stringify(closestNative, null, 2)}

REGRAS DE NEGÓCIO (invioláveis):
1. Carro popular de cidade (Uno, Gol, Fit, Celta, Palio) — MÁXIMO Tier B, mesmo com Stage 3.
2. Muscle car pesado americano (Mustang GT, Challenger, Camaro SS) — B a A, aceleração forte mas top speed ruim.
3. JDM leve esportivo (Integra, MR2, AE86, 86/BRZ) — B a A dependendo do motor.
4. Sedã GT europeu pesado (Panamera, Maserati Ghibli) — A no máximo; freios e grip compensam peso.
5. Supercar real (Ferrari, Lamborghini, McLaren road cars) — S.
6. Hipercars de produção (Bugatti Veyron/Chiron, Pagani, Koenigsegg) — S+.
7. Um carro pode cruzar de tier com Stage 3 (baseTier ≠ maxTier) se isso for realista pro carro real.

TAREFA:
Analise "${realname}" com os dados acima. Retorne ESTRITAMENTE o JSON abaixo, sem texto adicional:

{
  "baseTier": "B",
  "maxTier": "A",
  "confidence": 0.88,
  "justification": "Texto curto (máx 2 linhas) explicando o tier escolhido",
  "overrides": {
    "driveModifier": 0.95,
    "gripRatioModifier": 0.90,
    "preserveInertia": false,
    "vecInertiaMultiplier": { "x": 1.2, "y": 1.8, "z": 2.1 },
    "dragCompensation": 0.08
  },
  "archetype": {
    "driveType": "FWD",
    "category": "CITY_CAR",
    "strengths": ["agilidade_urbana", "economico_rp"],
    "weaknesses": ["velocidade_final", "instabilidade_alta_velocidade"],
    "trackAffinity": ["URBANA", "TECNICA", "CURTA"]
  }
}`;
}
```

### 4.5 Parsing e Gravação em Config

```javascript
async function runProfile(name, realname) {
  const { GoogleGenerativeAI } = require('@google/generative-ai');
  const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
  const model = genAI.getGenerativeModel({ model: process.env.GEMINI_MODEL || 'gemini-1.5-flash' });

  // Lê o handling original do mod
  const metaPath = findMetaByHandlingName(name);
  const content = fs.readFileSync(metaPath, 'utf8');
  const block = extractHandlingBlock(content, name);
  const originalHandling = parseHandlingFields(block);

  // Encontra o nativo mais próximo para calibração do prompt
  const vanilla = require('./config/vanilla-reference.json');
  const closestNative = findClosestNative(originalHandling, vanilla.vehicles);

  // Chama o Gemini
  const prompt = generateProfilePrompt({ name, realname, originalHandling, closestNative });
  const result = await model.generateContent(prompt);
  const rawText = result.response.text().trim().replace(/```json|```/g, '').trim();

  let geminiData;
  try {
    geminiData = JSON.parse(rawText);
  } catch (e) {
    console.error('[PROFILE ERROR] Gemini retornou JSON inválido:\n', rawText);
    process.exit(4);
  }

  // Valida campos obrigatórios
  const validTiers = ['D', 'C', 'B', 'A', 'S', 'S+'];
  if (!validTiers.includes(geminiData.baseTier) || !validTiers.includes(geminiData.maxTier)) {
    console.error('[PROFILE ERROR] Tier inválido:', geminiData.baseTier, geminiData.maxTier);
    process.exit(2);
  }

  // Grava em registry.json
  const registry = require('./config/registry.json');
  registry[name] = geminiData.baseTier === geminiData.maxTier
    ? geminiData.baseTier
    : {
        baseTier: geminiData.baseTier,
        maxTier: geminiData.maxTier,
        _profiledBy: 'gemini',
        _confidence: geminiData.confidence,
        _profiledAt: new Date().toISOString()
      };

  // Grava em overrides.json (preserva overrides manuais existentes se houver)
  const overrides = require('./config/overrides.json');
  overrides[name] = {
    ...(overrides[name] || {}),         // preserva overrides manuais
    ...geminiData.overrides,
    _archetype: geminiData.archetype,
    _justification: geminiData.justification
  };

  fs.writeFileSync('./config/registry.json', JSON.stringify(registry, null, 2));
  fs.writeFileSync('./config/overrides.json', JSON.stringify(overrides, null, 2));

  console.log(`\n✅  ${name} — "${realname}" perfilado com sucesso!`);
  console.log(`    Tier Stock:   ${geminiData.baseTier}`);
  console.log(`    Tier Stage 3: ${geminiData.maxTier}`);
  console.log(`    Confiança:    ${(geminiData.confidence * 100).toFixed(0)}%`);
  console.log(`    Justificativa: ${geminiData.justification}`);
  console.log('\n⚡  Revise e rode: node balance.js plan\n');
}
```

---

## 5. 🆕 Tier Fluido: Stage 3 Prediction

Para carros com `maxTier > baseTier`, o pipeline pré-calcula o impacto de Stage 3 completo e aplica um **freio aerodinâmico preventivo** — garantindo que o carro upgraded seja visivelmente mais rápido (a aceleração melhora) mas não cruze o teto de velocidade do tier acima.

### 5.1 Algoritmo de Compensação de Drag

```javascript
function calculateDragCompensation(name, baseTierKey, maxTierKey, ov) {
  if (!maxTierKey || maxTierKey === baseTierKey) return 0;  // tier fixo, sem compensação

  const baseTier = tiers[baseTierKey];
  const delta = require('./config/mods-delta.json').CAR;

  // Simula Stage 3 Full: Engine L4 + Turbo
  const baseDrive = baseTier.drive * (ov.driveModifier ?? 1.0);
  const engineL4  = delta.engine.levels['4'];     // 1.285
  const turbo     = delta.turbo.onValue;           // 1.15
  const driveS3Full = baseDrive * engineL4 * turbo;

  // Se com Stage 3 o carro cruzaria o threshold do tier acima:
  if (driveS3Full > baseTier.tierCrossThreshold) {
    const excessRatio = driveS3Full / baseTier.tierCrossThreshold;
    // Escalonamento suave — não cancela toda a melhoria, só limita o top speed
    const dragComp = (excessRatio - 1.0) * 0.55;
    return parseFloat(Math.min(dragComp, 0.18).toFixed(4));  // cap de 18% de drag extra
  }

  return 0;
}
```

### 5.2 O Que o Jogador Experimenta — Exemplo Fiat Uno (B → A)

| Configuração | 0-100 | Top Speed | Tier Runtime |
|---|---|---|---|
| Stock (sem peças) | ~8.5s | 218 km/h | **B** |
| Engine L1 + Suspensão | ~8.0s | 220 km/h | **B** |
| Engine L2 + Turbo | ~7.4s | 226 km/h | **B** |
| Engine L4 + Turbo + Trans | ~6.2s | 239 km/h | **A** ← cruza de tier |

O HUD exibe: `"B → A (S3)"` — indicando que o carro entrou no servidor como Tier B mas com tuning completo compete em A. Para correr em eventos A, o jogador precisa da **Licença Tier A** (progressão de habilidade) e o custo de manutenção sobe para o patamar de A.

---

## 6. Algoritmo de Normalização v3.0 — resolveTargets()

```javascript
function resolveTargets(handlingName, originalBlock) {
  // Suporte a registry.json com formato simples ou fluido
  const regEntry = registry[handlingName];
  const tierKey    = typeof regEntry === 'string' ? regEntry : regEntry.baseTier;
  const maxTierKey = typeof regEntry === 'string' ? regEntry : regEntry.maxTier;

  const tier = tiers[tierKey];
  const ov   = overrides[handlingName] || {};

  // ─── 1. FORÇA (sem scaling por massa — v3.0 fix) ───────────────────────────
  const driveRange = tier.driveModifierRange;
  const driveFinal = clamp(
    tier.drive * (ov.driveModifier ?? 1.0),
    tier.drive * driveRange[0],
    tier.drive * driveRange[1]
  );

  // ─── 2. DRAG (com compensação Stage 3 se baseTier ≠ maxTier) ─────────────
  const dragComp  = ov.dragCompensation ?? calculateDragCompensation(handlingName, tierKey, maxTierKey, ov);
  const dragFinal = tier.drag * (1 + dragComp);

  // ─── 3. GRIP MAX ────────────────────────────────────────────────────────────
  const gripMax = tier.gripMax * (ov.gripModifier ?? 1.0);

  // ─── 4. GRIP MIN — preserva proporção Min/Max original ──────────────────────
  const origGripMax = extractFloat(originalBlock, 'fTractionCurveMax') ?? tier.gripMax;
  const origGripMin = extractFloat(originalBlock, 'fTractionCurveMin') ?? tier.gripMin;
  const originalRatio  = clamp(origGripMin / origGripMax, 0.75, 1.0);
  const adjustedRatio  = originalRatio * (ov.gripRatioModifier ?? 1.0);
  const gripMin = clamp(gripMax * adjustedRatio, tier.gripMin * 0.85, gripMax);

  // ─── 5. FREIO ────────────────────────────────────────────────────────────────
  const brakeFinal = clamp(
    tier.brakeForce * (ov.brakeModifier ?? 1.0),
    tier.brakeForce * 0.85,
    tier.brakeForce * 1.15
  );

  const targets = {
    fInitialDriveForce:       ov.fInitialDriveForce      ?? driveFinal,
    fInitialDragCoeff:        ov.fInitialDragCoeff        ?? dragFinal,
    fInitialDriveMaxFlatVel:  ov.fInitialDriveMaxFlatVel  ?? tier.maxVel,
    fDriveInertia:            ov.fDriveInertia            ?? tier.driveInertia,
    fTractionCurveMax:        ov.fTractionCurveMax        ?? gripMax,
    fTractionCurveMin:        ov.fTractionCurveMin        ?? gripMin,
    fBrakeForce:              ov.fBrakeForce              ?? brakeFinal,
    fBrakeBiasFront:          ov.fBrakeBiasFront          ?? tier.brakeBiasFront,
    fTractionBiasFront:       ov.fTractionBiasFront       ?? tier.tractionBiasFront,
    fAntiRollBarForce:        ov.fAntiRollBarForce        ?? tier.antiRollBar,
  };

  // COM anti-capotamento: apenas se preserveInertia = false
  const comZ = ov.preserveInertia ? null : tier.comZ;

  // Override manual de inércia (gerado pelo Gemini ou definido manualmente)
  const inertiaOverride = !ov.preserveInertia && ov.vecInertiaMultiplier
    ? ov.vecInertiaMultiplier
    : null;

  return {
    tier, tierKey, maxTierKey, targets,
    gears: ov.nInitialDriveGears ?? tier.gears,
    comZ, inertiaOverride, dragComp,
    warnings: []
  };
}
```

---

## 7. 🆕 HUD Runtime FiveM — vb-core

### 7.1 vehicle-registry.json (output do CLI)

Arquivo gerado pelo `apply` e consumido pelo resource FiveM:

```jsonc
{
  "version": "3.0",
  "vehicles": {
    "SUPRA": {
      "displayName": "Toyota Supra A90",
      "baseTier": "S", "maxTier": "S+",
      "currentSeal": "sha256:8f4a2c1d...",
      "archetype": {
        "driveType": "RWD", "category": "JDM_SPORT",
        "strengths": ["aceleração_media", "curva_com_traseira"],
        "weaknesses": ["estabilidade_chuva"],
        "trackAffinity": ["CIRCUITO_SECO", "HIGHWAY"]
      },
      "specsByTier": {
        "S":  { "est0to100": 3.8, "topSpeedKmh": 265, "brakingM": 32, "gripRating": 0.88 },
        "S+": { "est0to100": 3.2, "topSpeedKmh": 278, "brakingM": 30, "gripRating": 0.90 }
      },
      "stageTiers": {
        "stage0": "S", "stage1": "S", "stage2": "S",
        "stage3": "S+", "stage3_full": "S+"
      }
    },
    "UNO": {
      "displayName": "Fiat Uno Mille 1.0",
      "baseTier": "B", "maxTier": "A",
      "archetype": {
        "driveType": "FWD", "category": "CITY_CAR",
        "strengths": ["agilidade_urbana", "economico_rp"],
        "weaknesses": ["velocidade_final", "instabilidade_velocidade"],
        "trackAffinity": ["URBANA", "TECNICA", "CURTA"]
      },
      "specsByTier": {
        "B": { "est0to100": 8.5, "topSpeedKmh": 218, "brakingM": 42, "gripRating": 0.70 },
        "A": { "est0to100": 6.2, "topSpeedKmh": 239, "brakingM": 37, "gripRating": 0.72 }
      },
      "stageTiers": {
        "stage0": "B", "stage1": "B", "stage2": "B",
        "stage3": "B", "stage3_full": "A"
      }
    }
  }
}
```

### 7.2 Layout do HUD — O Que o Jogador Vê

```
┌─────────────────────────────────────────┐
│  [A]  Fiat Uno Mille 1.0        [→ A]  │  ← Badge + seta indica "pode chegar em A"
│  ▓▓▓▓▓▓▓░░░░░░  680 / 749 pts         │  ← Posição dentro do tier
│─────────────────────────────────────────│
│  0-100: 7.4s      Top: 226 km/h        │
│  Freio: 39m       Grip: ★★★☆☆         │
│─────────────────────────────────────────│
│  ⟲ FWD · City Car                       │
│  ✦ Melhor: Circuito técnico / Cidade   │
│  ⚠ Cuidado: Instável acima de 180 km/h │
│─────────────────────────────────────────│
│  CORRIDAS DISPONÍVEIS               ▼  │
│  ● Downtown Drift B  — hoje às 20h     │
│  ● Highway Run B     — aberta agora    │
│─────────────────────────────────────────│
│  PRÓXIMO TIER A: Engine L4 + Turbo     │
│  (+2 upgrades para cruzar de tier)     │
└─────────────────────────────────────────┘
```

### 7.3 client.lua — TierHUD (núcleo)

```lua
-- vb-core/client.lua
local Registry = json.decode(LoadResourceFile(GetCurrentResourceName(), 'data/vehicle-registry.json'))
local currentVehicle = nil
local currentData = nil

-- Detecta entrada/saída de veículo
Citizen.CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)

        if vehicle ~= 0 and vehicle ~= currentVehicle then
            currentVehicle = vehicle
            local modelName = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle)):upper()
            currentData = Registry.vehicles[modelName]

            if currentData then
                local effectiveTier = CalculateEffectiveTier(vehicle, currentData)
                HUD.Show(currentData, effectiveTier)
                TriggerServerEvent('vb:validateTierEntry', modelName, effectiveTier)
            else
                HUD.ShowUnknown(modelName)
            end

        elseif vehicle == 0 and currentVehicle then
            currentVehicle = nil
            currentData = nil
            HUD.Hide()
        end

        Citizen.Wait(1000)
    end
end)

function CalculateEffectiveTier(vehicle, data)
    local engineLevel = math.max(0, GetVehicleMod(vehicle, 11)) + 1  -- 0-3 → 1-4
    local hasturbo    = IsToggleModOn(vehicle, 18)
    local transLevel  = math.max(0, GetVehicleMod(vehicle, 13)) + 1

    -- Estima o "stage" com base nas peças instaladas
    local stage = 0
    if engineLevel >= 4 and hasturbo and transLevel >= 3 then
        stage = 3
    elseif engineLevel >= 3 or (engineLevel >= 2 and hasturbo) then
        stage = 2
    elseif engineLevel >= 2 then
        stage = 1
    end

    local isFullS3 = (engineLevel >= 4 and hasturbo and transLevel >= 3)
    local stageKey = isFullS3 and 'stage3_full' or ('stage' .. stage)
    return data.stageTiers[stageKey] or data.baseTier
end

-- Comandos para o jogador
RegisterCommand('veiculo', function()
    if currentData and currentVehicle then
        local tier = CalculateEffectiveTier(currentVehicle, currentData)
        HUD.OpenFullPanel(currentData, tier)
    end
end)

RegisterCommand('tier', function()
    if currentData and currentVehicle then
        local tier = CalculateEffectiveTier(currentVehicle, currentData)
        TriggerEvent('chat:addMessage', { args = { string.format(
            '~g~[TIER]~w~ %s | Tier atual: ~b~%s~w~ | Base: ~y~%s~w~ | Max S3: ~o~%s~w~',
            currentData.displayName, tier, currentData.baseTier, currentData.maxTier
        )}})
    end
end)
```

---

## 8. CLI Completa v3.0 — Todos os Comandos

```bash
# ─── INICIALIZAÇÃO (uma vez) ────────────────────────────────────────────────────
node balance.js init-vanilla             # baixa e parseia os nativos do GTA5

# ─── DIAGNÓSTICO ────────────────────────────────────────────────────────────────
node balance.js scan                     # lista handlingName, tiers, órfãos, duplicatas

# ─── PROFILING COM IA ────────────────────────────────────────────────────────────
node balance.js profile --name UNO    --realname "Fiat Uno Mille 1.0 2001"
node balance.js profile --name SUPRA  --realname "Toyota Supra A90 3.0T 2022"

# ─── PIPELINE PRINCIPAL ─────────────────────────────────────────────────────────
node balance.js plan                     # diff completo — não grava
node balance.js apply                    # aplica: backup + cirúrgico + seal + report
node balance.js verify                   # confere seal de todos os .meta (exit 1 se drift)
node balance.js verify --name SUPRA      # verifica só um carro

# ─── STAGE 3 PREVIEW ────────────────────────────────────────────────────────────
node balance.js stage3 --name UNO        # simula Stage 3 full e exibe tier projetado

# ─── MANUTENÇÃO ─────────────────────────────────────────────────────────────────
node balance.js seal                     # re-sela estado atual (após edição aprovada)
node balance.js restore                  # restaura backup mais recente
node balance.js restore --backup <id>    # restaura backup específico
node balance.js report                   # exibe build-report.json formatado
```

**Exit codes:** `0` OK · `1` Seal drift · `2` Erro de config · `3` Erro de I/O · `4` Erro de API Gemini

---

## 9. CI/CD Pipeline v3.0

```yaml
# .github/workflows/vehicle-balance.yml
name: vHub Vehicle Balance CI

on:
  push:
    paths:
      - 'resources/**/handling.meta'
      - 'tools/handling-balancer/config/**'

jobs:
  balance:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
          cache-dependency-path: 'tools/handling-balancer/package-lock.json'

      - name: Instalar dependências
        working-directory: tools/handling-balancer
        run: npm ci

      - name: Init vanilla (usa cache do repositório se já existir)
        working-directory: tools/handling-balancer
        run: |
          [ -f "config/vanilla-reference.json" ] || node balance.js init-vanilla

      - name: Verificar seal (falha o PR se algum .meta foi editado à mão)
        working-directory: tools/handling-balancer
        run: node balance.js verify --json

      - name: Plan report (artefato para revisão)
        working-directory: tools/handling-balancer
        run: node balance.js plan --json > /tmp/balance-plan.json

      - uses: actions/upload-artifact@v4
        with:
          name: balance-plan-${{ github.sha }}
          path: /tmp/balance-plan.json

      - name: Apply e deploy (apenas na branch main)
        if: github.ref == 'refs/heads/main'
        working-directory: tools/handling-balancer
        run: node balance.js apply --no-backup
        env:
          GEMINI_API_KEY: ${{ secrets.GEMINI_API_KEY }}
```

---

## 10. Roadmap v3.0

| Fase | Entrega | Critério de Pronto |
|------|---------|-------------------|
| **0 — Fundação** | `init-vanilla` + correção física + `scan`/`plan` (read-only) | vanilla-reference gerado; plan sem scaling por fMass |
| **1 — Apply + Identidade** | `apply` com preservação de proporção + `build-report.json` | UNO / SKYLINE / SUPRA diferenciados no mesmo tier |
| **2 — Seal + CI** | `seal`/`verify` + GitHub Actions gate | PR com `.meta` manual falha o CI |
| **3 — Gemini Profile** | `profile` + `.env` + engenharia de prompt | UNO → B→A automaticamente; SUPRA → S→S+ |
| **4 — Stage 3 Predict** | `stage3` command + drag compensation | UNO S3 full não ultrapassa 239 km/h (teto A) |
| **5 — HUD FiveM** | `vb-core` resource + `vehicle-registry.json` + client.lua | Jogador vê tier, specs, corridas ao entrar no carro |
| **6 — Corridas + Licenças** | Race gatekeeper server-side + sistema de licenças | Primeiro evento Tier B funcional no servidor |
| **7 — Telemetria** | TelemetryCollector: mede 0-100 real → ajusta `overrides.json` | Loop de calibração fechado com dados reais |

---

## 11. Fontes e Referências

| Recurso | Uso |
|---------|-----|
| [andrejmaricc/gta5-complete-handling-files](https://github.com/andrejmaricc/gta5-complete-handling-files) | Base do `vanilla-reference.json` — todos os nativos do GTA5 (Ago 2025) |
| [GTACars.net — Tier Lists (Broughy1322)](https://gtacars.net/gta5/tiers) | Calibração dos tiers contra lap time e top speed reais medidos |
| [GTACars.net — Metadata Glossary](https://gtacars.net/gta5/glossary) | Confirmação de que `fMass` não afeta aceleração + fórmulas de física |
| [adam10603/GTAVHandlingParserJs](https://github.com/adam10603/GTAVHandlingParserJs) | Parser de referência para o `init-vanilla` |
| API Google Gemini | Profiling contextual do carro real: tier + overrides de identidade |

---

*vHub Handling Balancer v3.0 — "AI Identity Edition" · Motor determinístico + IA contextual · Zero impacto em runtime FiveM*











# Plano de Organização e Criação do Script de Balanceamento de Veículos vHub Handling Balancer

## 1. Visão Geral do Projeto

O objetivo principal deste projeto é desenvolver um pipeline robusto e auditável para a padronização do `handling.meta` de veículos mod (add-on) em servidores de GTA RP. A versão 2.0.0 do vHub Handling Balancer visa corrigir lacunas da versão anterior, garantindo uma hierarquia de Tiers (D → S+), integridade física (anti-capotamento), teto de velocidade coerente por tier e integridade competitiva, prevenindo edições manuais silenciosas e inconsistências.

Este pipeline será uma ferramenta de linha de comando (CLI) que opera offline, pré-processando os arquivos `.meta` antes do deploy no servidor FiveM, garantindo zero impacto em runtime. A inteligência do balanceamento reside em arquivos de configuração versionados, e o motor (`balance.js`) atua como um executor dessas regras.

## 2. Arquitetura e Componentes

A arquitetura do sistema é baseada em um motor Node.js (`balance.js`) que interage com arquivos de configuração JSON e os arquivos `.meta` dos veículos. A estrutura de diretórios proposta é:

```
tools/handling-balancer/
├── balance.js            ← motor (sem regras hardcoded)
├── package.json
├── config/
│   ├── tiers.json        ← a Matriz Ouro: valores-alvo por tier
│   ├── registry.json     ← handlingName → tier
│   ├── overrides.json    ← ajuste fino por carro (opcional)
│   └── scan-paths.json   ← onde varrer + exclusões
└── .seal/
    └── seal.json         ← hash selado por arquivo (gerado por `apply`/`seal`)
```

O `balance.js` será o ponto de entrada para todas as operações, lendo os arquivos de configuração e aplicando as regras de balanceamento aos arquivos `handling.meta` encontrados nos caminhos especificados em `scan-paths.json`.

## 3. Modelo de Dados

O sistema utiliza quatro arquivos de configuração principais, todos em formato JSON, para definir o comportamento do balanceamento:

### 3.1. `tiers.json` — Matriz de Normalização de Tiers

Este arquivo define os valores de referência e semente para cada tier (D, C, B, A, S, S+). Ele contém os alvos para força, arrasto, grip, freio, marchas e estabilidade. A tabela a seguir resume os campos principais:

| Tier | Ref. Nativa | Massa Base (kg) | Drive (force) | Drag | Grip Max | Grip Min | Marchas | DriveInertia | MaxFlatVel | Top Speed (a validar) |
|------|-------------|-----------------|---------------|------|----------|----------|---------|--------------|------------|------------------------|
| **D** | Blista | 1100 | 0.140 | 11.5 | 2.05 | 1.90 | 5 | 1.00 | 125 | ~170 km/h |
| **C** | Kuruma | 1400 | 0.180 | 10.5 | 2.15 | 2.00 | 5 | 1.00 | 130 | ~190 km/h |
| **B** | Elegy | 1500 | 0.220 | 10.0 | 2.30 | 2.15 | 6 | 1.10 | 132 | ~220 km/h |
| **A** | Banshee | 1400 | 0.260 | 9.5 | 2.45 | 2.30 | 6 | 1.20 | 135 | ~245 km/h |
| **S** | Zentorno | 1500 | 0.310 | 9.2 | 2.65 | 2.50 | 6 | 1.30 | 138 | ~265 km/h |
| **S+** | Krieger | 1500 | 0.350 | 9.0 | 2.80 | 2.65 | 7 | 1.40 | 140 | **280 km/h (cap-alvo)** |

Campos de freio e estabilidade por tier:

| Tier | BrakeForce | BrakeBiasFront | TractionBiasFront | AntiRollBar | COM z-offset (anti-capot.) |
|------|------------|----------------|-------------------|-------------|----------------------------|
| D | 0.70 | 0.62 | 0.49 | 0.55 | −0.05 |
| C | 0.80 | 0.62 | 0.49 | 0.60 | −0.06 |
| B | 0.90 | 0.60 | 0.48 | 0.65 | −0.08 |
| A | 1.00 | 0.58 | 0.47 | 0.70 | −0.10 |
| S | 1.10 | 0.56 | 0.47 | 0.75 | −0.10 |
| S+ | 1.20 | 0.55 | 0.46 | 0.80 | −0.12 |

### 3.2. `registry.json`

Mapeia o `handlingName` (normalizado para UPPERCASE e trim) de cada veículo para o seu respectivo tier. Carros não listados neste arquivo serão ignorados e reportados pelo comando `scan`.

Exemplo:
```json
{
  "SKYLINE": "A",
  "SUPRA":   "S",
  "370Z":    "B"
}
```

### 3.3. `overrides.json`

Permite ajustes finos em campos específicos de veículos individuais, sem quebrar a coerência do tier. A precedência é: **tier (base) → override (patch) → clamps de sanidade**. Overrides nunca podem ultrapassar os clamps absolutos do tier.

Exemplo:
```json
{
  "SUPRA": {
    "fBrakeForce": 0.92,
    "fTractionCurveMin": 2.55
  }
}
```

### 3.4. `scan-paths.json`

Define os diretórios raiz a serem varridos em busca de arquivos `handling.meta`, além de padrões de exclusão para pastas e arquivos.

Exemplo:
```json
{
  "roots": ["resources/[SCRIPTS]/carmod", "resources/[vehicles]"],
  "exclude": ["**/backup/**", "**/_archive/**"],
  "matchFiles": ["handling.meta"]
}
```

### 3.5. Validação de Configuração

No início de qualquer comando, o sistema validará a integridade dos arquivos de configuração, verificando se todos os tiers referenciados existem, se os overrides são válidos e se os campos obrigatórios estão presentes. Erros de configuração resultarão em `exit 2` com uma mensagem clara em PT-BR.

## 4. Algoritmo de Normalização

O algoritmo de normalização aplica as regras definidas nos arquivos de configuração aos valores do `handling.meta` de cada veículo.

### 4.1. Força Motriz

A força motriz é calculada com base na relação power-to-weight do tier, com um clamp para evitar valores extremos. A fórmula inicial é `driveSeed = (tier.drive / tier.massBase) * modMass`, e o valor final é `driveFinal = clamp(driveSeed, tier.drive * 0.85, tier.drive * 1.15)`.

### 4.2. Marchas, Inércia e Ceiling de Velocidade

Os campos `fInitialDriveMaxFlatVel`, `nInitialDriveGears`, `fDriveInertia` e `fInitialDragCoeff` são definidos diretamente pelos valores do tier, trabalhando em conjunto para caracterizar o comportamento de aceleração e velocidade máxima do veículo.

### 4.3. Anti-capotamento

O sistema implementa uma abordagem multifatorial para anti-capotamento, ajustando `vecCentreOfMassOffset.z` (relativo e com clamp), `fTractionBiasFront`, `fAntiRollBarForce`, `fRollCentreHeightFront/Rear` e `fSuspensionReboundDamp`. Para tiers S/S+, `fDownforceModifier` pode ser considerado se a `SubHandlingData` estiver presente.

### 4.4. Campos Preservados, Modificados e Injetados

O pipeline modifica campos específicos relacionados a desempenho e estabilidade, injeta/ajusta campos de estabilidade com clamps, e **preserva** a identidade intocável de outros campos (ex: `fDriveBiasFront`, `fSteeringLock`, etc.) para manter as características originais do veículo.

## 5. Parsing Seguro — Substituição Cirúrgica de XML

Para evitar a corrupção de arquivos `.meta` e a perda de informações (como comentários ou tags `NULL`), o sistema utilizará uma **substituição cirúrgica linha-a-linha** baseada em regex. O motor alterará apenas o conteúdo de `value="..."` (ou atributos como `z="..."`) dos campos-alvo, dentro do bloco `<Item type="CHandlingData">`, mantendo o restante do arquivo byte-a-byte idêntico.

Para arquivos com múltiplos carros, cada bloco `<Item type="CHandlingData">` será processado isoladamente pelo seu `handlingName` e recomposto. Guardas de I/O incluem a preservação de BOM/encoding (UTF-8), normalização de `handlingName` e a garantia de que o arquivo só será gravado se houver mudanças.

## 6. Normalização de Upgrades e Teto de Velocidade — Defesa em 3 Camadas

O teto de velocidade de 280 km/h será garantido por uma defesa em três camadas:

| Camada | Onde | Custo | Garante |
|--------|------|-------|---------|
| **1. Meta (este pipeline)** | `handling.meta` selado | zero runtime | chão físico coerente por tier; dificulta passar do cap |
| **2. Governor client-side** *(opcional)* | resource leve client, lê velocidade e suaviza acima do cap | mínimo (event/timer, L-06) | teto **exato** mesmo com upgrades; servidor segue autoritativo (L-01) |
| **3. Validação server-side** *(já existe)* | vHub valida posição/velocidade | já contabilizado | pega teleport/trainer (anti-cheat real) |

A camada 1 é sempre aplicada, e a camada 3 já existe. A camada 2 é opcional e será implementada se a validação em pista mostrar que upgrades furam o cap de forma relevante.

## 7. Interface de Linha de Comando (CLI)

O `balance.js` oferecerá os seguintes comandos:

- `node balance.js scan`: Lista `handlingName` reais, tier atual, órfãos e duplicatas. Não grava.
- `node balance.js plan`: Mostra o diff completo (campo a campo, por carro). Não grava.
- `node balance.js apply`: Grava com backup, atualiza `.seal/seal.json` e gera `build-report.json`.
- `node balance.js verify`: Confere se o `.meta` corresponde ao tier+override e ao selo. Retorna `exit≠0` se houver divergência (para uso em CI).
- `node balance.js seal`: Re-sela os hashes atuais (uso após edição manual aprovada).
- `node balance.js restore`: Restaura do backup mais recente (ou `--backup <id>`).

Flags adicionais como `--dry-run`, `--only`, `--tier`, `--json`, `--no-backup` e `--verbose` estarão disponíveis.

**Exit codes:** `0` (ok), `1` (drift/divergência), `2` (erro de config), `3` (erro de I/O).

## 8. Segurança Operacional

O pipeline incluirá as seguintes medidas de segurança:

- **Backup automático:** Antes de qualquer `apply`, o `.meta` original será copiado para `.backups/<timestamp>/<path>`.
- **Dry-run / plan first:** O comando `plan` será o padrão mental, e `apply` exigirá intenção explícita.
- **Idempotência:** Rodar `apply` múltiplas vezes não causará mudanças adicionais na segunda execução.
- **`build-report.json`:** Um relatório detalhado listando por carro o tier, campos alterados, valores antes/depois e warnings, facilitando a revisão.
- **Diffs limpos:** A substituição cirúrgica garantirá que os `git diff` mostrem apenas as linhas realmente alteradas.

## 9. Selo, Detecção de Drift e CI

Para garantir a integridade competitiva, o sistema implementará um mecanismo de selo e detecção de drift:

- **`seal.json`:** Um arquivo (commitado) que registrará um hash assinado (SHA256) do estado aprovado de cada `handling.meta`, juntamente com seu tier e caminho do arquivo.
- **`apply`/`seal`:** Regravarão o hash do estado aprovado no `seal.json`.
- **`verify`:** Recomputará o hash de cada `.meta` e comparará com o `seal.json`. Se houver divergência, retornará `exit 1` com o nome do carro.
- **Gate de CI:** Uma GitHub Action (ou pre-commit hook) rodará `node balance.js verify --json`. Pull Requests que alterem um `handling.meta` sem passar pelo pipeline serão bloqueados, garantindo que todas as mudanças sejam auditadas e controladas.

## 10. Protocolo de Validação em Jogo

Para "fechar" o tier, será necessário um protocolo de validação empírica em jogo:

1.  **Pista de teste:** Utilizar uma pista reta e plana (ex: aeroporto LSIA) com marcadores e cronômetro.
2.  **Medição:** Para cada carro do tier, medir o tempo de 0-100 km/h e a velocidade máxima com tuning completo (Stage 3 + nitro).
3.  **Comparação e ajuste:** Comparar os resultados com os alvos do tier. Se estiver fora da tolerância (ex: ±5%), ajustar `overrides.json`, re-`apply` e re-medir.
4.  **Registro:** Registrar os números medidos no `build-report.json` (campo `validated`).
5.  **Baseline:** Utilizar carros de referência nativa (Banshee para A, Zentorno para S, etc.) como baseline visual e de sensação.

## 11. Edge Cases e Guardas Obrigatórias

O sistema incluirá guardas para os seguintes edge cases:

-   `fMass` ausente, `0`, `NaN` ou negativo: `skip + WARN`.
-   `handlingName` ausente/duplicado entre arquivos: `WARN` com os caminhos.
-   Massa fora da faixa esperada do tier: `WARN`.
-   Campo-alvo ausente no bloco: `WARN`, não injeta.
-   Múltiplos `<Item type="CHandlingData">` no mesmo arquivo: processar cada um pelo seu `handlingName`.
-   `<Item type="NULL"/>` e `SubHandlingData`: intocados.
-   Override com campo desconhecido ou que estoura clamp do tier: `erro de config (exit 2)`.
-   Arquivo read-only / em uso: `erro de I/O (exit 3)`.
-   Preservação de Encoding/BOM e line-endings.

## 12. Roadmap Incremental

O desenvolvimento seguirá um roadmap incremental, com as seguintes fases:

| Fase | Entrega | Critério de pronto |
|------|---------|--------------------|
| **0 — MVP** | `scan` + `plan` (read-only) | lista handlingName reais; diff confere com a matriz; zero escrita |
| **1 — Apply seguro** | `apply` (backup + cirúrgico) + `build-report.json` | aplica nos 3 carros (370z/skyline/supra); diff só nas linhas-alvo |
| **2 — Selo + CI** | `seal`/`verify` + gate de CI | PR que edita `.meta` à mão falha o CI |
| **3 — Validação** | protocolo §12 + `overrides.json` afinado | 0-100 e top speed dentro da tolerância por tier |
| **4 — Upgrades/modkit** | leitura de `vehicles.meta`; report de upgrade que fura o cap | nenhum carro passa do cap do tier full-tuning (ou camada 2 ativada) |

Este plano detalha a organização e criação do script de balanceamento de veículos, abordando todos os pontos levantados na especificação `script.md`.