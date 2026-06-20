# vhub_vehcontrol — Engine de Veículos (PLANO definitivo)

**Versão:** 1.0.0 · **Status:** Aprovado pelo arquiteto (decisão #27 candidata) · **Modelo:** Opus 4.8
**Escopo:** `vhub_vehcontrol` vira o **CENTRO ÚNICO do veículo** — controle (portas/luz/motor) +
identidade derivada (tier/score/afinidade) + redistribuição de pontos (skill) + gancho de nitro.
**Substitui** a ideia de um resource `vhub_p1skill` separado: o `carskill.md` permanece como
**referência conceitual** (fórmulas, taxonomia), não como resource.

> **Diretriz do dono (lei deste plano):** tudo do veículo num lugar só, consultável/editável por
> todos **sem competir, sem 2ª verdade, sem um invalidar o outro** (o anti-padrão mec×bennys).
> Fluxo coeso, mínimo de código, organização que um humano acha fácil, **espaço real para crescer**.

---

## 0. Princípio-mestre (a regra que evita o caos)

```
UMA fonte de verdade por dado · UM escritor · MUITOS leitores · ZERO recálculo paralelo.

PERSISTE (escolha do jogador):   customization.handling = { alloc dos 5 eixos }
DERIVA  (calculado on-read):     tier · score · afinidade · budget   (NUNCA persistido)
LÊ      (já persiste, reusado):  customization.mods  (peças da oficina) · catalog.p1 (identidade)
```

Se algo for derivável, **não se persiste** (senão diverge quando o catálogo mudar — L-04).
Se dois sistemas precisam do mesmo número, **ambos chamam o mesmo export** (nunca recalculam).

---

## 1. Camadas e ownership (dentro de UM resource, sub-módulos isolados)

O vehcontrol já é **L1 (autoridade trava/motor) + L2 (HAL de controle)**. O engine de skill entra
como **sub-módulos isolados** — nunca derramado no `server/main.lua` (anti-monolito L-09).

```
vhub_vehcontrol/
├── shared/
│   ├── config.lua        ← já existe; ganha BUDGET, ALLOC_RANGE, PART_POINTS, NITRO_LEVELS
│   ├── events.lua        ← NOVO (hoje há literais 'vhub_vehcontrol:' espalhados — anti-fantasma L-15)
│   └── tier_rules.lua    ← NOVO · L1-PURO (server+client, ZERO I/O):
│                            budgetOf · partsBonus · validateAlloc · scoreFromAlloc · calcTier · calcAffinity
├── server/
│   ├── main.lua          ← INTOCADO no núcleo (controle + telemetria). Só ganha require do skill.
│   ├── skill.lua         ← NOVO · L1: sessão de recálculo, validação server-auth, consumo de item,
│   │                        persist via conce, StateBag derivada. ÚNICO ponto de escrita do alloc.
│   ├── exports.lua       ← NOVO · API read-only pública: getVehicleTier/Score/Affinity/Sheet(plate)
│   └── item_handlers.lua ← já existe (chave→open_from_key); ganha hook da caixa de ferramentas
├── client/
│   ├── main.lua          ← já existe (controle); roteia a aba nova
│   └── handling.lua      ← NOVO · L2 (gated pela FÍSICA-PoC, fase tardia): aplica override grip/aero/susp
└── html/
    └── (painel iframe já existe) ← ganha aba "Ficha do Veículo" (infos + redistribuição)
```

**Cláusula de extração futura:** `shared/tier_rules.lua` + `server/skill.lua` são PUROS/ISOLADOS.
Se um dia o vehcontrol crescer demais, extraem-se para resource próprio com **zero reescrita**.
Regra dura: **o cálculo não conhece natives de controle; o controle não conhece skill.** Comunicam-se
só por export interno/evento.

---

## 2. O dado: o que mora onde (sem 2ª verdade)

### 2.1 PERSISTE — `customization.handling` (prontuário, dono = conce/VState)

```lua
vhub_vehicle_state.customization = {
  mods    = { [11]=lvl, ... },   -- peças da oficina (JÁ persiste — decisão #26)
  turbo   = bool,                -- toggle (JÁ persiste — decisão #26)
  handling = {                   -- NOVO: a ESCOLHA do jogador (alloc dos pontos livres)
    potencia=180, grip=160, frenagem=140, aero=160, suspensao=160
  },
}
```

- Adicionar `handling=true` ao `CUST_KEYS` do `vstate.lua` (cai no ramo "chave atômica" do `mergeCust`
  — substitui inteiro a cada recalibração; o merge por índice é só do `mods`).
- Escritor único = conce/VState. Único CHAMADOR autorizado = `vehcontrol/server/skill.lua`.
- `source='handling'` NOVO (não reusar `'tune'` da oficina — separa auditoria; aditivo ao guard
  cosmético do vstate que isola o patch a `customization`).

### 2.2 DERIVA on-read — tier · score · afinidade · budget (NUNCA persiste)

Funções PURAS em `shared/tier_rules.lua`, chamadas no servidor (autoridade) e no cliente (preview):

```
budget_total(plate) = BUDGET[tier_base] + partsBonus(mods)        -- teto de pontos do carro
score              = scoreFromAlloc(handling)                      -- 0..1000
tier_atual         = clampMax(calcTier(score), tier_max)           -- nunca acima do teto do catálogo
afinidade          = calcAffinity(handling, base)                  -- reta/curva/montanha/drift/cidade
```

### 2.3 LÊ (já existe) — `catalog.p1` (identidade física, dono = conce/catálogo)

Bloco `p1` por veículo no `catalog.lua` do conce (vindo do `tools/handling-balancer`, mesclado por
humano). Campos reais (do `out/catalog-patch.json`):

```lua
TOYOTASUPRA = {
  nome='Toyota Supra A80', preco=420000, ..., tags={'mod'},
  p1 = {
    handling_name='toyotasupra', tier_base='A', tier_max='S', archetype='rwd_heavy',
    grip_modifier=0.92, base_alloc={potencia=160,grip=160,frenagem=160,aero=160,suspensao=160},
    drive_bias=0.0, susp_raise=-0.02, mass=1615, inertia_z=1.3, low_speed_loss=1.8,
    seal='sha256:...'
  }
}
```

- `base_alloc` = a distribuição NATURAL do tier (é o ponto de partida do alloc do jogador).
- Carro **sem `p1`** → sem tier/budget → redistribuição **indisponível** (fail-closed). UI degrada.

---

## 3. Modelo de pontos HÍBRIDO (decisão do dono)

> Veículo tier X tem N pontos naturais. Cada peça comprada **adiciona** pontos: **metade FIXA** no
> eixo natural da peça, **metade LIVRE** para o jogador realocar em **combinações semânticas**.

```
budget_total = base_alloc (natural do tier)  +  Σ peças

Para cada peça instalada (customization.mods):
  bonus_total = PART_POINTS[peça].pontos              -- ex.: turbo = 15
  fixo  = floor(bonus_total / 2)  → vai DIRETO ao(s) eixo(s) natural(is) da peça (piso, não realocável)
  livre = bonus_total - fixo      → entra no pool que o jogador distribui nos eixos PERMITIDOS da peça
```

**Tabela semântica `PART_POINTS` (shared/config.lua) — cada peça declara pontos + eixos permitidos:**

```lua
PART_POINTS = {
  -- índice GTA → { pontos, eixo_fixo, eixos_livres = { permitidos p/ realocar o 'livre' } }
  [11] = { pontos=20, fixo='potencia', livres={'potencia','aero'} },        -- motor
  [18] = { pontos=15, fixo='potencia', livres={'potencia','grip'} },        -- turbo (torque↔aceleração)
  [12] = { pontos=12, fixo='frenagem', livres={'frenagem','suspensao'} },   -- freio
  [13] = { pontos=10, fixo='potencia', livres={'potencia','frenagem'} },    -- câmbio
  [15] = { pontos=10, fixo='suspensao', livres={'suspensao','grip'} },      -- suspensão
  [16] = { pontos=8,  fixo='suspensao', livres={'suspensao','frenagem'} },  -- blindagem (peso→estabilidade)
}
```

> Por que metade fixa: a peça TEM personalidade (turbo não vira grip puro). O fixo garante a
> identidade da peça; o livre dá a SKILL de calibração ("torque ou aceleração?"). É o "fácil de
> aprender, difícil de dominar" do carskill §1.0, sem expor 48 campos físicos.

**INVARIANTE server-side (validateAlloc):**
```
Σ alloc == budget_total                                  -- não pode criar/sumir pontos
cada eixo dentro de ALLOC_RANGE (% do budget, anti-P2W)  -- nada all-in num eixo
o 'livre' de cada peça só pode ir aos eixos 'livres' dela -- semântica respeitada
```
O servidor REJEITA qualquer alloc que quebre isso (não cobra, não persiste). L-01.

---

## 4. Os DOIS pontos de entrada da recalibração (mesma lógica, zero duplicação)

> "Os ajustes do score livre vão ser feitos no painel (caixa de ferramentas) **OU** na oficina pelo
> mecânico." — duas portas, **um** handler. É o oposto do mec×bennys (que competiam).

```
PORTA A — Chave-item + 'caixa de ferramentas'         PORTA B — Oficina + mecânico
  player abre painel do veículo (open_from_key)          player na zona da oficina (vhub_custom)
  aba "Ficha" → redistribui → confirma                   mecânico/UI → redistribui → confirma
                    │                                                   │
                    └───────────────┬───────────────────────────────────┘
                                    ▼
        vhub_vehcontrol/server/skill.lua : recalibrate(src, plate, allocDesejado, origem)
          1. canOperate(src, plate)            ← REUSA conce (chave-item + dono)
          2. st = getVehicleState(plate)       ← mods já sanitizados
          3. base = catalog[norm(model)].p1    ← identidade; se nil → aborta (fail-closed)
          4. budget = budgetOf(base, mods)     ← PURO
          5. validateAlloc(alloc, budget, base)← PURO (invariante §3)
          6. consumir 1× 'caixa de ferramentas'← exports.vhub_inventory (ver §4.1)
          7. saveVehicleState(...,'handling')  ← escritor único conce
          8. VState emite vehicleCommitted → skill REAGE → StateBag derivada + HUD
```

- `vhub_custom` (oficina) **NÃO duplica** a lógica: ele só chama
  `exports.vhub_vehcontrol:recalibrate(...)` (ou dispara o mesmo evento server). O dono do alloc é o
  vehcontrol; a oficina é só mais uma PORTA. Sem competição, sem invalidação mútua.

### 4.1 Consumo da 'caixa de ferramentas' (item sink)

- Ambas as portas consomem **1× caixa de ferramentas** por recalibração (decisão do dono).
- Ordem anti-perda: **validar → persistir → consumir** (perder o save é pior que perder o item; se
  consumisse antes e o save falhasse, o jogador perderia o item à toa). Decisão final no gate de segurança.
- Via `exports.vhub_inventory` (remover item). Se não tem o item → aborta antes de tudo.

---

## 5. Consumo por outros sistemas (export único, ninguém recalcula — L-04)

```
vhub_vehcontrol/server/exports.lua  (read-only, _invoker_allowed):
  getVehicleTier(plate)     → 'D'..'S+'  (derivado)
  getVehicleScore(plate)    → 0..1000    (derivado)
  getVehicleAffinity(plate) → {reta,curva,montanha,drift,cidade}
  getVehicleSheet(plate)    → ficha completa flat p/ UI {tier,tier_base,tier_max,score,budget_total,
                              budget_used,alloc,affinity,parts_bonus}  (L-19 primitivos)
```

| Consumidor | O que lê | Como |
|-----------|----------|------|
| Concessionária (conce) | `tier_base` | direto do `catalog.p1` (estático, não precisa de placa) |
| Garagem (garage) | `tier_atual` + `score` | `exports.vhub_vehcontrol:getVehicleTier/Score` |
| Chave-item (UI) | ficha completa | `getVehicleSheet` (read fresco; o dossiê-cópia da chave é só preview) |
| Racha (racha) | `tier` p/ gatekeeping | `getVehicleTier` |
| Nitro (futuro) | afinidade / hook | `getVehicleAffinity` + evento reservado |

**REPROVAÇÃO** se garage/racha implementarem `calcTier` local. **REPROVAÇÃO** se a redistribuição
usar o snapshot da chave como entrada de verdade (é stale; a fonte é o prontuário).

---

## 6. Gancho do NITRO (futuro — só reservar)

> "Futuramente ele vai poder calibrar em níveis: Duração (pouca potência, dura muito) ↔ Potência
> (acaba rápido, muita potência)."

- Mesmo modelo do alloc: uma escolha do jogador, calibrada nas MESMAS portas (chave/oficina).
- Reservar agora: `NITRO_LEVELS` em config + chave `customization.nitro = { level=0..N }` no CUST_KEYS
  (quando implementar) + `getVehicleNitro(plate)` no export. **Não implementar nesta janela** — só
  garantir que o desenho comporta (a tabela `PART_POINTS`/`validateAlloc` generaliza para isso).
- `vhub_nitro` consumirá `getVehicleNitro` + aplicará o efeito (duração×potência) no client.

---

## 7. Fases (cada uma testável; valor sem risco)

| Fase | Entrega | Critério de pronto | Gate |
|------|---------|--------------------|------|
| **F0** | Pipeline offline gera `catalog-patch.json` p/ ~15 carros | patches prontos, tiers decididos | simplicidade+contrato |
| **F1** | **BUNDLE CONCE** (pré-req de tudo): `handling` no CUST_KEYS + `source='handling'` no guard + bloco `catalog.p1` mesclado | restart limpo; carro com p1 retorna tier_base; sem p1 = degrada | **arquiteto+contrato+persistência** |
| **F2** | `shared/tier_rules.lua` (puras) + `shared/events.lua` + `server/exports.lua` (tier/score/sheet) | exports retornam tier_base/score derivado; carro sem p1 = nil seguro | simplicidade+contrato |
| **F3** | Aba "Ficha do Veículo" no NUI da chave (LEITURA: tier, score, barras, afinidade) | abre pela chave; mostra ficha; 0.00ms fechada | designer+runtime |
| **F4** | `server/skill.lua`: recalibração server-auth (2 portas) + consumo caixa + persist `handling` + HUD. **NÚMERO/HUD, sem física** | redistribui dentro do budget; persiste; sobrevive restart; oficina usa a mesma porta | **segurança+performance+contrato** |
| **F5a** | **PoC risco nº1** (`SetVehicleHandlingFloat` por-instância vs model-wide) | 2 players, mesmo modelo, builds diferentes, sem colisão | **natives (BLOQUEANTE de F5b)** |
| **F5b** | Física real (override grip/aero/susp) — SÓ se F5a aprovado | carro anda conforme alloc; clampado ao tier | natives+segurança+performance |
| **F6** | Gancho nitro (reservar evento/export/config) + integrar `vhub_nitro` | nitro lê tier/afinidade; calibração durável↔potente | arquiteto+natives |

**Disciplina:** balancear ~15-20 carros primeiro (carskill §9), nunca 400. F4 entrega o sistema
completo de número/HUD/redistribuição **sem tocar física**. A física é a única coisa atrás do PoC.

---

## 8. Registro de Ownership (decisão #27 candidata)

- **`customization.handling`** (alloc) | escritor único `conce/VState` (source='handling'); único
  chamador `vehcontrol/server/skill.lua` | leitores: vehcontrol (deriva), garage/racha (via export),
  UI chave (read-only) | persistência `vhub_vehicle_state.customization` (merge por chave atômica).
- **`catalog.p1`** (identidade física) | escritor único `conce/shared/catalog.lua` (humano, mesclado
  do handling-balancer) | leitores: vehcontrol (budget/tier), garage (tier_base vitrine) | estático.
- **Cálculo tier/score/afinidade** | dono = `vehcontrol` (sub-módulos `tier_rules`+`skill`+`exports`)
  | DERIVADO on-read, NUNCA persistido | consumido só via export do vehcontrol.
- **Relação com #26:** `vhub_custom` (oficina) continua dono da escrita de `mods`/`turbo`; vehcontrol
  é dono de `handling`. Chaves disjuntas no mesmo JSON, escritor único conce, `mergeCust` garante
  não-atropelo. A oficina, ao redistribuir, **chama** o vehcontrol (não escreve `handling`).

---

## 9. Condições de parada (sinalizar e reduzir escopo)

- Persistir tier/score/afinidade em qualquer lugar → 2ª fonte (L-04).
- Cálculo dentro de `server/main.lua` do vehcontrol → monolito (L-09).
- Física (F5b) antes do PoC (F5a) aprovado → risco nº1 (L-16). **Bloqueante absoluto.**
- garage/racha com `calcTier` próprio → recálculo paralelo (L-04).
- redistribuição lendo o dossiê-cópia da chave como verdade → estado stale.
- F1 (bundle conce) não preceder o código do vehcontrol → budget sem `catalog.p1` → entrega vazia.
- oficina duplicando a lógica de alloc em vez de chamar o vehcontrol → competição (anti mec×bennys).

---

## 10. Reaproveitamento (mínimo de código, máximo de reuso)

- `canOperate`/`getVehicleState`/`saveVehicleState` do conce: REUSADOS (não recriar autoridade).
- `mergeCust` do vstate (já existe): cobre `handling` de graça (chave atômica).
- Funções puras `tier_rules`: UMA implementação, usada por server (autoridade) e client (preview).
- NUI: aba nova no painel iframe que JÁ existe (não criar 2º painel).
- Chave→painel: evento `open_from_key` que JÁ existe (não criar 2º canal).
- `base_alloc` do catálogo: É o ponto de partida do alloc (não inventar default).
- 2 portas (chave/oficina) → 1 handler `recalibrate` (não duplicar validação/consumo/persist).

---

*Plano vhub_vehcontrol v1.0 — centro único do veículo. Persiste só a escolha (alloc), deriva o resto,
reusa o escritor único do conce, uma lógica para todas as portas. Modular, sem 2ª verdade, com
cláusula de extração para crescer. carskill.md = referência conceitual.*
