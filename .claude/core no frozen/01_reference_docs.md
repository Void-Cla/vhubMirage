# 01 — Síntese dos Documentos Fundacionais do vHub Mirage

> **Task ID:** 1 · **Agente:** Reference Docs Synthesizer
> **Escopo:** síntese exaustiva dos 15 documentos fundacionais do ecossistema vHub, com citações literais de leis, decisões e IDs.
> **Idioma:** Português (Brasil).

---

## 1. Visão Geral do Projeto vHub

### 1.1 O que é o vHub (do `README.md`)

> *"vHub Mirage é um framework FiveM GTARP completo, construído do zero, sem dependência de legado vRP. O objetivo é entregar uma base estável, previsível e extensível para servidores de médio/grande porte."* — `README.md` linha 12-13.

**Decisões arquiteturais centrais (README):**
- **Servidor é a única fonte de verdade** — cliente trata UI, física e estado efêmero.
- **VRAM-first** — toda leitura vai à memória primeiro; SQL é backup, não runtime.
- **Batch SQL atômico** — writes agrupados em transações de até 800 ops a cada 3s.
- **Compat: none** — shim vRP (`_G.vRP`, `_G.Proxy`, `_G.Tunnel`) removido definitivamente em Frozen v1.0.

**Status de congelamento:**
```
╔═════════════════════════════════════════════════════════╗
║ vHub Mirage — CORE FROZEN v1.0                          ║
║ Data      : 2026-05-22                                  ║
║ Revisão   : 2027-05-22                                  ║
║ Compat vRP: none                                        ║
║ LOC core  : 2.432 (de 2.813 — -381 líquido)            ║
║ Resmon    : 0.02ms idle (alvo: < 0.05ms)               ║
╚═════════════════════════════════════════════════════════╝
```

Qualquer alteração em `resources/[CORE]/vhub/**` exige: (1) justificativa por escrito; (2) aprovação `vhub_arquiteto` + `vhub_guardiao_revisao`; (3) bump de versão para `core-frozen-v2.0`.

### 1.2 Arquitetura macro

```
vhubMirage/
├── config/             ← server.cfg + resources.cfg (ordem de ensure) + sub-configs
├── resources/
│   ├── [CORE]/         ← vhub (FROZEN), oxmysql, vhub_oxmysql, vhub_legacyfuel, vhub_notify
│   ├── [SCRIPTS]/      ← vhub_groups, vhub_identity, vhub_money, vhub_survival,
│   │                     vhub_player_state, vhub_inventory, vhub_garage, vhub_admin,
│   │                     vhub_conce, vhub_custom, vhub_vehcontrol, vhub_nitro,
│   │                     vhub_racha, vhub_vrcs, vhub_velo, Drift, carmod, …
│   ├── [CAR]/          ← specs: carskill.md, carskill_testplan.md, nitro_testplan.md, cont1.md
│   ├── [mapas]/        ← bob74_ipl, blodline, CityHall, depzitamadasptlnd
│   └── [TOOLS]/        ← vhub_testrunner (Lua server-side)
├── tools/
│   ├── handling-balancer/  ← pipeline offline Node.js (Fase 1 do carskill)
│   ├── test_tier_rules.lua, test_b64_roundtrip.lua
│   └── limpardadossql.ps1, fix_vhub_db.ps1
├── metas/
│   ├── manual_dev_vhub.md (referência de desenvolvimento ativa — cópia em resources/[SCRIPTS]/)
│   └── fivem_natives_organizadas_ptbr.md (referência de natives em PT-BR)
├── CLAUDE.md, README.md, FROZEN_EXEC_LOG.md
```

> **Nota:** o `README.md` lista estrutura "resumida" sem `vhub_conce`, `vhub_vehcontrol`, `vhub_nitro`, `vhub_custom`, `vhub_racha`, `Drift`, `carmod`, `vhub_vrcs`, `vhub_velo`, `vhub_ferinha`, `vhub_lspdtool`, `vhub_ipad`, `vhub_wow` — estes só aparecem no `config/resources.cfg`. A árvore do README está desatualizada em relação ao boot real.

### 1.3 Quem mantém, status atual

- **Projeto:** vHub Mirage — Framework FiveM GTARP, Lua 5.4, server-authoritative.
- **Mantenedor:** "vHub Mirage" (autor nos fxmanifest). Dono = "Void-Cla" (GitHub `Void-Cla/vhubMirage`).
- **Status:** Core FROZEN v1.0 (2026-05-22); revisão prevista 2027-05-22.
- **Recursos ativos confirmados em `config/resources.cfg`:** oxmysql, vhub, vhub_notify, vhub_groups, vhub_identity, vhub_money, vhub_survival, vhub_player_state, vhub_inventory, vhub_conce, carmod, vhub_ferinha, vhub_garage, vhub_admin, vhub_legacyfuel, vhub_login, vhub_racha, vhub_vrcs, vhub_custom, vhub_lspdtool, vhub_loading, vhub_vehcontrol, vhub_velo, vhub_nitro, vhub_spawselector, Drift, vhub_ipad, vhub_wow + mapas (bob74_ipl, blodline, audi, depzitamadasptlnd, fav_barragem, hayes-dean).
- **Meta operacional declarada (`manual_dev_vhub.md`):** custo por player **O(1)** dentro dos Orçamentos do CLAUDE.md (idle CORE ≤ 0.05 ms, script ≤ 0.02 ms, tick p95 ≤ 0.10 ms/script, NUI fechada 0.00 ms), operando no teto da plataforma (OneSync Infinity = 2048 slots/processo) com 40% de folga.

### 1.4 Convenções do CLAUDE.md (resumo executivo — ver §7 para detalhe)

| Lei | Regra |
|-----|-------|
| L-01 | Servidor é autoritativo para toda verdade crítica |
| L-02 | Cliente: UI/HUD/física efêmera. Servidor valida e persiste |
| L-03 | Fallback de dado cliente = rollback para último estado válido do servidor |
| L-04 | Sem segunda fonte de verdade; sem ownership duplicado |
| L-05 | Native FiveM antes de infraestrutura custom |
| L-06 | Sem loop/polling — preferir evento, State Bag ou timer mínimo |
| L-07 | Sem novo resource/módulo sem ownership e lifecycle explícitos |
| L-08 | Código em inglês; comentários, saídas e `lang.*` em PT-BR |
| L-09 | Funções curtas, sem redundância, máximo reaproveitamento sem acoplamento rígido |
| L-10 | Toda função pública comentada com uma linha objetiva em PT-BR |
| L-11 | `server/compat.lua` permanece funcional até vHub ter nome no mercado |
| L-12 | Transações SQL são atômicas e exclusivamente server-side |
| L-15 | (pós-auditoria) Todo `.lua` referenciado no manifest no mesmo commit; deletar é entrega |
| L-16 | (implícita em manual §3.1) `SetPlayerModel`/`SetEntityCoords` de spawn fora do `vhub_player_state` é proibido |
| L-17 | (manual §3.1) Handlers institucionais devem ter replay-guard |
| L-18 | Orçamentos de performance = contrato |
| L-19 | Coordenadas como tipos vetoriais nativos `vec3`/`vec4` — uso local, nunca cruzam fronteira |

Leis A-01..A-10 regem NUI/componentização (ver §7).

---

## 2. A "Doutrina" do CORE (manual_dev_vhub.md)

> *"Manual** — vHub Mirage — **versão 2.0** (pós-auditoria Void-Zero + IT.1/IT.2 + Governança v2) — 2026-06-10*

> **Lei-mestra deste manual:** *peça ao dono, nunca escreva no que não é seu.* Todo dado tem UMA linha no **Registro de Ownership** (`CLAUDE.md`); seu script lê por export e escreve por **contrato de commit**.

### 2.1 Contratos congelados (o que o core garante — tabela literal do manual)

| Garantia | Onde |
|---|---|
| **`compat: none`** — sem shim vRP. APIs vHub diretas | `server/init.lua` |
| **Ordem fixa de carga** | `kernel → state → sql → notify → auth → vehicle → security → boot → exports` |
| **Batch SQL atômico** | `BATCH_MAX=800`, `BATCH_INT=3000ms`, autosave chunked com yield/50 |
| **Login N→1 round-trip** | `vHub.SQL.uidByIdsIn(n)` |
| **State Bag com threshold** | fuel ±0.5 / eng ±5 / body ±5 / odo ±0.05 km — bypass ao cruzar 0 |
| **Adaptive client report** | `client/vehicle.lua` 2000/1000/250 ms por speed/rpm |
| **GC ativo** | `_byNet` cron 5 min; `Kernel._rate` purgado em `playerDropped` |
| **Schema único e idempotente** | `sql/schema.sql` aplicado no boot |
| **Tipos PK canônicos** | `vh_users.id`, `vh_characters.id` = `INT UNSIGNED AUTO_INCREMENT` |
| **Escrita de estado físico do veículo** | `exports.vhub:commitVehicleState(plate, patch, reason)` — único caminho p/ terceiros (IT.2); valida, clampa, marca dirty, sincroniza bags e loga o `reason` |
| **Leitura de estado físico** | `exports.vhub:getVehicleState(plate)` (snapshot) no servidor; State Bags no cliente |
| **Spawn do ped** | dono único = `vhub_player_state` (`spawnAt`, `teleport`, `giveWeapons`, `set*`) — nenhum script toca o ped |
| **Replay institucional** | `vHub:playerSpawn`/`vHub:characterLoad` são re-disparados para todas as sessões em `onResourceStart` de qualquer resource — todo handler precisa de replay-guard (L-17) |

> **Schemas externos com FK ao core DEVEM usar `INT UNSIGNED`** (signed dispara `errno 150`).

### 2.2 "CORE FROZEN v1.0" — o que significa

- Selado em **2026-05-22**. Próxima revisão **2027-05-22**.
- Kernel imutável. Mudanças apenas **aditivas** com gate duplo (`vhub_arquiteto` + `vhub_guardiao_revisao`).
- **Única exceção registrada:** contratos `commitVehicleState`/`getVehicleState` da IT.2.
- LOC core: **2.432** (de 2.813 — -381 líquido).
- `resmon` medido: **0.02 ms** (alvo < 0.05 ms idle, < 0.20 ms sob carga).
- `compat: none` — shim vRP removido definitivamente.
- Proteção mecânica: `settings.json` tem deny rule `"Write(resources/[CORE]/vhub/**)"`. Edições emergenciais exigem `.claude/settings.local.json` (gitignored).
- `lua54 yes` obrigatório. `oxmysql` 2.x com `multipleStatements=true`. MariaDB 10.3+ / MySQL 8.0+ InnoDB utf8mb4.

### 2.3 Conceito de "escritor único"

> *"Antes de criar/escrever um dado: qual a linha dele no Registro de Ownership? Sem linha = sem dado. Chave de outro domínio = proibido escrever."* — manual §0.

Aplicado ao veículo:

- **Estado físico do veículo:** `exports.vhub:commitVehicleState(plate, patch, reason)` é o **único caminho** para terceiros escreverem. Valida, clampa, marca dirty, sincroniza State Bags, loga `reason`.
- **Leitura:** `exports.vhub:getVehicleState(plate)` no servidor; State Bags (`vh_fuel`, `vh_eng`, `vh_body`, `vh_odo`, `vh_tune`, `vh_on`) no cliente.
- **Ped:** dono único `vhub_player_state` — `spawnAt`, `teleport`, `giveWeapons`, `setCustomization`.
- **Dinheiro/inventário/ban:** exports do `vhub_money` / `vhub_inventory` / `vhub_conce` + `vhub`.
- **Proibido (L-13/L-14):** `setVData(...)` fora do core (hook **bloqueia**) e mutar `vd.state`/internos via `getVHub()`/`getVehicle()` — leitura só.
- **Veículo efêmero** (missão/corrida) pode ser criado pelo seu script **se e somente se**: placa com prefixo reservado do domínio (ex.: `RC` + id), nunca passa por `commitVehicleState`, despawn garantido por timeout + `playerDropped`, e entidade marcada mission para delete confiável.

### 2.4 Conceito de "VRAM-first"

```
Leitura:   VRAM hit → retorna direto (sem DB)
           VRAM miss → query DB → armazena em VRAM → retorna

Escrita:   atualiza VRAM → enfileira no batch → invalida VRAM*
           (*hot keys: ban.active, whitelist, permissions ficam em VRAM)

Flush:     automático a cada 3s OU ao atingir 800 ops
           emergencial em onResourceStop (chunked, yield a cada 50)
```

Trade-off: **transações in-memory** (não SQL atômico) garantem consistência de VRAM. Ops SQL vão para batch. Risco de perda dos últimos segundos em crash abrupto (kill -9 / power outage).

### 2.5 Conceito de "replay-safe"

> *"Handler canônico (sessão + replay-guard L-17)"* — manual §3.1.

O CORE re-dispara `vHub:playerSpawn` e `vHub:characterLoad` em `onResourceStart` de qualquer resource (para que resources recém-reiniciados vejam sessões já ativas). Logo, todo handler precisa deduplicar por contador (`user.spawns`) ou ID de sessão.

```lua
-- padrão replay-guard
AddEventHandler('vHub:playerSpawn', function(user, first)
  local spawns = tonumber(user.spawns) or 0
  if _seen[user.source] == spawns then return end   -- replay → no-op
  _seen[user.source] = spawns
  -- ... setup por spawn real
end)
```

### 2.6 Conceito de "driver"

No CORE, **"driver"** é **uma das três formas de ownership** de um veículo vivo:

- **driver** (`vd.driver`) — source atual do motorista (runtime).
- **key_uid** (`vd.key_uid`) — dono persistente via `vh_vehicles`.
- **Network Owner** — `NetworkSetEntityOwner` em `onEnter/onLeave`.

**Network ownership:** só o cliente com `seat == -1` (motorista) envia `vState`. Servidor valida `vd.driver == src` em `onStateUpdate` antes de mutar estado físico.

### 2.7 Network ownership & State Bags

| Bag | Tipo | Delta mínimo para write |
|-----|------|------------------------|
| `vh_fuel` | number (0–100) | 0.5 L |
| `vh_eng` | number (0–1000) | 5.0 HP |
| `vh_body` | number (0–1000) | 5.0 HP |
| `vh_odo` | number (km) | 0.05 km |
| `vh_tune` | table | sempre |
| `vh_on` | boolean | sempre |

> **Estado de entidade para todos os clientes = State Bag, NUNCA `TriggerClientEvent(-1)`** — manual §4.2.

> **⚠️ HANDLERS DE VEÍCULO DORMENTES (decisão #24, N0-3 2026-06-21):** `vHub:vSpawned/vDespawned/vEnter/vLeave/vState` registrados com corpo NO-OP (`_vhDisarmed`) por risco de grief (atacante forjava `vEnter` com netid da vítima → `onEnter` concedia `NetworkSetEntityOwner` da entidade alheia). Consequência: `Veh:onStateUpdate` nunca é chamado em runtime; State Bags `vh_*` nunca escritas pelo CORE; `client/vehicle.lua` envia `vState` a 4Hz que é silenciosamente descartado. **O CORE NÃO é fonte ativa de vehicle state em runtime** — resources externos (`vhub_conce`, `vhub_vehcontrol`, `vhub_garage`) precisam chamar `Veh:onSpawned/onStateUpdate` diretamente via `getVHub` export ou implementar pipeline próprio. (Fonte: worklog Task 2 / análise `02_CORE_vhub.md`.)

### 2.8 Vehicle state model (CORE)

```lua
vd.state = {
  fuel         = 100,          -- 0..100
  engine_health= 1000,         -- 0..1000
  body_health  = 1000,
  damage       = {},           -- categorias (pneu, motor, lataria...)
  tuning       = {},
  garage       = nil,          -- status: nil|stored|impound|...
  last_pos     = {x, y, z, h},
  odometer     = 0,            -- km
  engine_on    = false,
}
```

Persistido via `vHub.setVData(plate, "state", vd.state)` → `vh_vehicle_data`. State Bags em entidade: `vh_fuel/vh_eng/vh_body/vh_odo/vh_tune/vh_on` com delta gating + zero-crossing (`bagSet`).

> **PRONTUÁRIO:** na prática o estado físico do veículo migrou para `vhub_conce/server/vstate.lua` (tabela `vhub_vehicle_state`, DDL própria) que substitui `vh_vehicle_data` do CORE. O homônimo `exports.vhub:getVehicleState` (CORE) está **inerte** — todo mundo usa `exports.vhub_conce:getVehicleState`. (carskill.md P-3.)

### 2.9 Lei-mestra e antipadrões do manual (tabela §5)

| Antipadrão | Por quê | Pattern correto |
|---|---|---|
| `setVData(...)` fora do core | viola L-13; causa last-write-wins em `vh_vehicle_data` (8 casos históricos) — **hook bloqueia** | `commitVehicleState(plate, patch, reason)` |
| Mutar `vd.state`/internos via `getVHub()`/`getVehicle()` | L-14; repair-hack e corrupção de sessão | leitura: `getVehicleState`; escrita: contrato |
| Escrever chave KV de outro domínio (`setCData(cid,'banco',...)` fora do money) | segunda verdade (L-04/L-13) | chave própria prefixada + linha no Registro |
| `SetPlayerModel`/`SetEntityCoords` de spawn fora do `vhub_player_state` | 3 escritores disputaram o ped (caso real) | `spawnAt`/`teleport`/provider `chooseSpawn` |
| Handler `vHub:playerSpawn` sem replay-guard | core re-dispara em `onResourceStart` → re-teleporte global (caso real) | snapshot de `user.spawns` (§3.1) |
| Arquivo `.lua` fora do manifest / módulo `return M` sem global | código morto/fantasma (5 casos reais, 1 com `os.exit`) — **hook bloqueia** | manifest no mesmo commit; `VHubX = M` |
| `os.exit()`, version-check HTTP, anti-tamper vendor | derruba/expõe o servidor | deletar na chegada |
| `TriggerClientEvent(-1, ...)` p/ estado de entidade | N mensagens × players; bag faz delta de graça | State Bag |
| Comentar a lei violando-a (`-- L-04` num segundo escritor) | corrói toda a constituição — violação agravada | cumprir ou renegociar no gate |
| `while true do Wait(0)` sempre ativo | resmon spike | frame loop condicional (§4.1) |
| `exports.X:func()` em loop quente | round-trip × N | cache + invalidação (4.3) |
| `SetEntityCoords` sem `RequestCollisionAtCoord` + wait | player cai no void | carregar colisão antes |
| `DecorSetString` | removido do FiveM | placa nativa / State Bag |
| `print()` solto | poluição | `vHub.Logger` |
| Lógica de negócio em NUI JS | bypassável | servidor decide |
| `Citizen.Await` fora de thread | crash | `CreateThread` + `assertThread` |
| `oxmysql:query` em loop hot / N+1 | satura DB | batch/multi-insert |
| Tabela `[src]` sem limpeza em `playerDropped` | leak | handler de drop sempre |
| Payload sem validação de shape/range | exploit trivial | validar antes do domínio |
| FK signed ao core / `MEDIUMBLOB` por padrão | `errno 150` / buffer | `INT UNSIGNED` / `BLOB` |
| `_G.vRP/Proxy/Tunnel` | shim removido | `exports.vhub:*` |
| Bloquear tick > 5 ms | autosave atrasa | `Wait(0)` a cada N (50) |

### 2.10 Ordem de boot recomendada (config/resources.cfg, arquivo canônico)

```
oxmysql
vhub
vhub_notify
vhub_groups
vhub_identity
vhub_money
vhub_survival
vhub_player_state
vhub_inventory
vhub_conce
carmod
vhub_ferinha
vhub_garage
vhub_admin
vhub_legacyfuel
vhub_login
vhub_racha
vhub_vrcs
vhub_custom
vhub_lspdtool
vhub_loading
vhub_vehcontrol
vhub_velo
vhub_nitro
vhub_spawselector
Drift
vhub_ipad
vhub_wow
[mapas] bob74_ipl-master, blodline, audi, depzitamadasptlnd, fav_barragem, hayes-dean
```

---

## 3. Filosofia de Balanceamento (sss.txt)

### 3.1 Premissa de design

> *"Em um ecossistema de alta performance focado em corridas, punir o erro é fundamental para recompensar a precisão e o planejamento de rota. Carros extremamente leves no motor RAGE (GTA V) agem como 'bolas de pinball': batem, quicam, perdem pouca inércia e, por terem uma relação peso/potência absurda, recuperam a velocidade de cruzeiro em dois ou três segundos. Isso tira o peso da consequência."*

### 3.2 Conceito de Categorias / Tiers / Sweet Spots

**Categoria "Heavy-Sport / GT" (punição):**

| Faixa de peso (`fMass`) | Comportamento esperado |
|---|---|
| Muito Leve (< 1.150 kg) | Aceleração brutal; batida perde controle mas retomada imediata; favorece pilotos imprudentes |
| **Sweet Spot (1.450 kg a 1.750 kg)** | Física de transferência sentida; batida absorve energia cinética; retomada luta contra 1.600 kg; piloto pensa duas vezes antes de ultrapassagem suicida |
| Muito Pesado (> 1.950 kg) | Subesterço crônico; frenagem inviável em circuitos urbanos; derrapagens retas 30–50 m; arrancada punitiva; corrida monótona |

**Regra de engenharia (especificação técnica):**
> **Classe de Veículos de Alta Punição:**
> **Peso Alvo (`fMass`):** 1.450.000 a 1.750.000
> **Comportamento Esperado:** Alta estabilidade direcional e aderência. Punição severa na curva de aceleração (0-100 km/h) após perda total de energia cinética (colisões), exigindo cálculo preciso de frenagem e traçados limpos para manutenção do *momentum*.

### 3.3 Categoria "Equilibrada" (All-Rounder — AWD com viés traseiro)

> **Truque mecânico:** Tração Integral Assimétrica (AWD com viés traseiro).

| Campo | Valor Alvo |
|---|---|
| `fDriveBiasFront` | 0.300 a 0.400 (30–40% dianteira) |
| `fMass` | 1.300 kg a 1.450 kg |
| `fTractionCurveMax` (Grip Máximo) | ~2.200000 (moderado) |
| `fTractionCurveMin` (Grip Escorregando) | ~1.800000 (alto) |
| `nInitialDriveMaxFlatVel` | alta |
| `fDragMult` | ~8.500000 a 9.000000 (mais alto que o normal) |

Dinâmica de corrida mista: Equilibrado larga melhor que Muscle (AWD), curva pior que Esportivo (menos grip), perde na reta para Muscle (maior arrasto após 140 km/h).

### 3.4 Pilares da arquitetura lógica do handling (Heavy-Sport)

**1. Relação de Retomada (Torque vs. Inércia):**
- `fInitialDriveForce` (potência pura): 0.300000 a 0.350000 — força para empurrar peso.
- `fDriveInertia` (inércia do motor): **diminuir levemente** (ex.: 1.000000 → 0.850000) — marchas demoram mais para encher; 200 km/h voa, mas batida cai para 0 km/h → marcha 1/2 sofrem para embalar massa.

**2. Frenagem Proporcional à Massa:**
- `fBrakeForce`: 0.850000 a 1.100000 (elevado).
- `fBrakeBiasFront`: ~0.550000 (joga peso para dianteiro em freada).

**3. Tração e Força G:**
- `fTractionCurveMax` / `Min`: alta aderência (grudar no chão). Punição é perda de tempo na retomada, não escorregar.

### 3.5 Fórmulas matemáticas (regra de domínio VehicleIntegrity.Rules)

```lua
VehicleIntegrity.Rules = {
    ['balanced'] = { fMass={min=1300.0,max=1450.0}, fDriveBiasFront={min=0.3,max=0.4}, fTractionMax={min=1.8,max=2.2} },
    ['muscle']   = { fMass={min=1450.0,max=1750.0}, fDriveBiasFront={min=0.0,max=0.1}, fTractionMax={min=2.0,max=2.4} },
    ['sport']    = { fMass={min=1100.0,max=1350.0}, fDriveBiasFront={min=0.0,max=0.3}, fTractionMax={min=2.5,max=2.9} },
    ['drift']    = { fMass={min=1200.0,max=1400.0}, fDriveBiasFront={min=0.0,max=0.0}, fTractionMax={min=1.4,max=1.8} },
}
```

### 3.6 Conceito de peso, tração, potência — interação no GTA5

> *"O peso sozinho não resolve o problema; ele precisa estar matematicamente ancorado na inércia do motor e na tração."*

- **Peso (`fMass`)** afeta colisão e inércia, mas **NÃO aceleração** (a = F/m cancela em GTA5 — §1.5 carskill.md).
- **Tração (`fTractionCurveMax/Min`)** define aderência e capacidade de "cortar" curva.
- **Potência (`fInitialDriveForce`)** define aceleração; deve vir ancorada em `fDriveInertia` para regular retomada.

### 3.7 Boot validation (Self-Healing)

**Camada de Domínio** (`handling_rules.lua`): tabela de regras matemáticas isolada da lógica.

**Camada de Validação** (`validator_service.lua`):
- `VehicleIntegrity.ValidateHandling(vehicleData)` — pura, sem I/O; retorna `(isValid, anomalies)`.
- Trata nulos/tipos errados sem runtime error.

**Camada de Integração e Boot** (`boot_service.lua`):
- `RunHandlingSanityCheck()` rodando em `onResourceStart` (delay 1.5s p/ estabilizar BD).
- Itera veículos, valida, log em cascata `->`.

### 3.8 Self-Healing (Clamping + SQL dinâmico)

**Evolução do validador:** `ValidateAndCorrectHandling(vehicleData)` retorna `(isValid, anomalies, corrections)`. Para cada campo violado, aplica **Clamping** (min/max do tier).

**Geração dinâmica de SQL:**
```lua
-- Constrói UPDATE apenas para campos violados
local sqlSetParts, queryParams = {}, {['@plate']=veh.plate}
for field, val in pairs(corrections) do
  table.insert(sqlSetParts, string.format("%s = @%s", field, field))
  queryParams['@'..field] = val
end
local sql = string.format("UPDATE player_vehicles SET %s WHERE plate = @plate", table.concat(sqlSetParts, ", "))
MySQL.Async.execute(sql, queryParams, function(rows) ... end)
```

Vantagens: I/O otimizado (só campos alterados), proteção de tipo defensiva, persistência definitiva no boot.

### 3.9 Handling

**Pilares** (sss.txt):
- **Relação de Retomada:** `fInitialDriveForce` (potência) × `fDriveInertia` (inércia do motor).
- **Frenagem Proporcional:** `fBrakeForce` × `fBrakeBiasFront`.
- **Tração e Força G:** `fTractionCurveMax/Min`.

**Três pilares do balanceador offline (script.md):** força motriz (drive force × power-to-weight clamp), marchas/inércia/ceiling de velocidade, anti-capotamento (COM offset + antiRollBar + roll centre + suspension rebound).

### 3.10 Relação sss.txt ↔ handling-balancer

O `sss.txt` é a **filosofia matemática original** (categorias com `fMass`/`fDriveBiasFront`/`fTractionMax`). O `PLANO_IMPLEMENTACAO_VEICULOS.md` propõe um **Self-Healing em runtime** (`boot_service.lua` no `vhub_conce`) que clamparia veículos violadores no boot do servidor.

O `handling-balancer/script.md` (v2.0) **supera** essa abordagem: o balanceamento **não roda em runtime Lua** (segunda fonte de verdade, L-04); é **pré-processado offline** (CLI Node.js) — o FXServer apenas lê os `.meta` já balanceados no boot, com **zero** impacto em `resmon` (alinhado a L-05/L-06). O selo sha256 + CI garante integridade competitiva.

> *"Por que CLI e não runtime: reescrever XML por restart adiciona latência de boot e CPU; pior, criaria uma segunda fonte de verdade física em runtime (proibido por L-04). O `.meta` é a fonte estática; o estado dinâmico do veículo já vive no PRONTUÁRIO (`vhub_vehicle_state`) e não tem relação com este pipeline."* — `script.md` §1.

A ponte entre os dois mundos é o `out/catalog-patch.json` (gerado pelo balancer offline, mesclado manualmente no `catalog.lua` do `vhub_conce` sob gate do arquiteto).

---

## 4. Plano de Implementação de Veículos (`PLANO_IMPLEMENTACAO_VEICULOS.md`)

**Autor:** Manus AI · **Data:** 28 de Junho de 2026

### 4.1 Visão geral

> *"Este documento detalha o plano de implementação para integrar e otimizar o ecossistema de veículos do servidor FiveM, incorporando as diretrizes de balanceamento físico (handling) descritas no documento de requisitos (`sss.txt`) e as ferramentas de balanceamento offline (`handling-balancer`)."*

Premissa central: estabelecer "skill gap" significativo nas corridas, ancorando peso (`fMass`) e tração (`fDriveBiasFront`, `fTractionCurveMax`) matematicamente para punir erros de pilotagem e recompensar precisão — evitando o efeito "pinball".

### 4.2 Análise arquitetural atual (recursos interligados)

| Resource | Responsabilidade |
|---|---|
| `vhub_conce` (Concessionária) | Autoridade sobre propriedade, criação e status dos veículos. Exports críticos: `canOperate`, `isOwner`, `createVehicle`. |
| `vhub_garage` (Garagem) | Armazenamento, spawn, leilões, aluguéis. Depende do `vhub_conce` para validação de propriedade. |
| `vhub_custom` (Customização/Mecânica) | Modificações visuais (Bennys) e de performance (Oficina), além de reparos. |
| `vhub_vehcontrol` (Controle de Veículos) | Sistema de "Tiers", alocação de pontos de habilidade (handling dinâmico), afinidade por tipo de pista. |
| `vhub_racha` (Corridas) | Modos (circuito, drag, drift), beneficiário direto do balanceamento de handling. |
| `handling-balancer` (Ferramenta Offline) | Utilitário Node.js para escanear, perfilar e gerar patches de handling (`catalog-patch.json`). |

**Ponto de atenção (§2.1):** `vhub_vehcontrol` já possui `handlingFromAlloc` que modifica parâmetros físicos em tempo real. É crucial que essas modificações **respeitem os limites (clamping) estabelecidos pelas regras de integridade do sss.txt**.

### 4.3 Plano: Motor de Integridade (Self-Healing) — 3 camadas

**Camada 1 — Domínio (`handling_rules.lua`):** tabela `VehicleIntegrity.Rules` (balanced/muscle/sport/drift com min/max de fMass/fDriveBiasFront/fTractionMax). Fonte da verdade.

**Camada 2 — Validação (`validator_service.lua`):** `ValidateAndCorrectHandling` — pura, sem I/O, retorna `(isValid, anomalies, corrections)`.

**Camada 3 — Integração (`boot_service.lua` no `vhub_conce`):** roda no `onResourceStart` com delay 1.5s, busca veículos, valida, gera `UPDATE` dinâmico só com campos violados, executa assíncrono.

### 4.4 Integração com handling-balancer (offline) — fluxo recomendado

1. **Importação de Mods:** novos veículos na pasta de mods.
2. **Scan e Profiling:** `node balance.js scan` — ler `.meta`, gerar perfil de cada veículo.
3. **Aplicação de Arquétipos:** cruzamento com `config/archetypes.json` (`rwd_light`, `awd_heavy`...).
4. **Geração de Patch:** `node balance.js plan` + `node balance.js apply` → `catalog-patch.json`.
5. **Integração no Servidor:** `catalog-patch.json` consumido por `vhub_conce/shared/catalog.lua` para definir Tier, Budget, Base Handling.

### 4.5 Sincronização de regras

Regras do `sss.txt` (Sweet Spot de Massa 1.450–1.750 kg) **devem ser refletidas no `config/archetypes.json`** do balancer — consistência entre ferramenta offline e validador online.

### 4.6 Ajustes no `vhub_vehcontrol`

> *"É imperativo que a função `TR.handlingFromAlloc` (em `tier_rules.lua`) seja modificada para respeitar os limites (clamping) definidos pelo `VehicleIntegrity.Rules`."*

Resultado final deve passar por `VehicleIntegrity.ValidateAndCorrectHandling` antes de aplicar ao veículo no cliente — garante que jogador não transforme "Muscle" em peso de "Sport" via customização.

### 4.7 Entregáveis e próximos passos (§6)

1. Criar `handling_rules.lua`, `validator_service.lua`, `boot_service.lua` no `vhub_conce`.
2. Atualizar esquema do BD: garantir colunas `fMass`, `fDriveBiasFront`, `fTractionMax` se persistência por veículo.
3. Sincronizar Balancer Offline: `archetypes.json` com valores exatos do `sss.txt`.
4. Refatorar `vhub_vehcontrol`: injetar validação de limites em `TR.handlingFromAlloc`.
5. Testes de estresse com dados corrompidos no banco.

> **Status (conforme worklog Task 5):** o `vhub_vehcontrol` real implementou `tier_rules.lua` (6 tiers D..S+ com BUDGET 500..1000, ALLOC_RANGE anti-P2W, PART_POINTS híbrido), mas a injeção do `VehicleIntegrity.Rules` no `handlingFromAlloc` foi **substituída** pelo modelo híbrido do `carskill.md` (mod nativo para POT/FRE/transmissão; override server-auth para GRIP/AERO/SUSP). O `boot_service.lua` proposto aqui **não foi implementado como descrito** — a integridade física migrou para o **pipeline offline** + `catalog.p1` + `coerceAlloc` na leitura da ficha. A `tabela player_vehicles` não existe; o catálogo é estático em `conce/shared/catalog.lua`.

---

## 5. Carskill Design (`carskill.md`)

**Versão:** 2.2.0 · **Status:** Spec definitiva, alinhada ao CORE FROZEN v1.0 + manual_dev_vhub + leis L/A.

### 5.1 O que é carskill

> *"vHub P1 Skill — Especificação de Arquitetura (realista para o vHub Mirage)"*

Sistema de "skill de configuração" do veículo. **NÃO foi implementado como resource `vhub_p1skill` separado** — vive **DENTRO** de `vhub_vehcontrol` (decisão #27). `carskill.md` é **referência conceitual** (fórmulas, taxonomia, roadmap futuro), não código atual.

**O que EXISTE hoje (banner ESTADO REAL 2026-06-18):**
- Ficha derivada **read-only on-demand** (`REQ_SHEET`→`SHEET` + exports `getVehicleSheet/Tier/Score/Affinity/SheetPreview` em `server/exports.lua`).
- **Escritor único do alloc** `server/skill.lua` (`RECALIBRATE`, 2 portas: caixa de ferramentas + oficina).
- Fórmulas (§3.6, §5.3, §5.4) e taxonomia de campos (§3.4) refletidas em `shared/tier_rules.lua`.

**O que é roadmap (não existe):** StateBags `vhub_p1`/`vhub_p1_hnd` (§5.2.1), manifestação física híbrida via `SetVehicleHandlingFloat` (parcialmente implementado pela decisão #28 — ver `carskill_testplan.md`), HUD client, telemetria `vhub_p1skill_telemetry`, snapshot/racha (§5.5–§5.8).

### 5.2 Premissas inegociáveis (§0)

| # | Fato verificado | Consequência |
|---|---|---|
| P-1 | `vhub_conce/shared/catalog.lua` é o único dono da identidade/preço do veículo | Tier/score/arquétipo nascem como **campos do catálogo** |
| P-2 | Chave do catálogo = `<modelName>` em minúsculo | `handling_name` e tier ancorados na mesma chave |
| P-3 | Estado físico = `exports.vhub_conce:getVehicleState(plate)` (PRONTUÁRIO); `exports.vhub:getVehicleState` está **inerte** | p1skill lê mods via conce, nunca via core |
| P-4 | `customization.mods` já sanitizado pelo conce (`CUST_KEYS`) | p1skill consome `mods` como dado já validado |
| P-5 | CORE FROZEN v1.0 | p1skill é resource externo novo com ownership próprio (L-07); não toca core |
| P-6 | `carmod` permanece em `resources/[SCRIPTS]/carmod` (62 arquivos reais; `[CAR]/carmod` vazio) | Pipeline offline varre por glob path-agnóstico |
| P-7 | L-19: vetor é uso LOCAL | HUD recebe primitivos via StateBag |

### 5.3 Os 5 eixos (skill allocation — §1.4)

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

**INVARIANTE: `soma(atributos_normalizados) == BUDGET[tier_base]` (sempre).**

### 5.4 Budget por tier

| Tier | Score | BUDGET | Nativo de referência |
|------|-------|--------|----------------------|
| D | 0–199 | 500 | Blista |
| C | 200–399 | 600 | Kuruma |
| B | 400–599 | 700 | Elegy |
| A | 600–749 | 800 | Banshee |
| S | 750–899 | 900 | Zentorno |
| S+ | 900–1000 | 1000 | Krieger |

**Modelo híbrido de pontos (decisão do dono):**
```
budget_total = base_alloc (natural do tier) + Σ peças

Para cada peça instalada:
  bonus_total = PART_POINTS[peça].pontos         -- ex.: turbo = 15
  fixo  = floor(bonus_total / 2)                 -- piso, não realocável
  livre = bonus_total - fixo                     -- pool para realocar
```

`PART_POINTS` (exemplos):
- `[11]` motor: 20 pts, fixo=potencia, livres={potencia,aero}
- `[18]` turbo: 15 pts, fixo=potencia, livres={potencia,grip}
- `[12]` freio: 12 pts, fixo=frenagem, livres={frenagem,suspensao}
- `[13]` câmbio: 10 pts, fixo=potencia, livres={potencia,frenagem}
- `[15]` suspensão: 10 pts, fixo=suspensao, livres={suspensao,grip}
- `[16]` blindagem: 8 pts, fixo=suspensao, livres={suspensao,frenagem}

**ALLOC_RANGE (anti-P2W):** cada eixo deve ficar dentro de X% do budget:
- potencia: 10%–35%
- grip: 8%–35%
- frenagem: 8%–30%
- aero: 8%–30%
- suspensao: 8%–28%

### 5.5 Persistência

**PERSISTE — `customization.handling`** (prontuário, dono = conce/VState):
```lua
vhub_vehicle_state.customization = {
  mods    = { [11]=lvl, ... },   -- peças (decisão #26)
  turbo   = bool,
  handling = {                   -- ESCOLHA do jogador (alloc dos pontos livres)
    potencia=180, grip=160, frenagem=140, aero=160, suspensao=160
  },
}
```

**DERIVA on-read** (nunca persiste): tier, score, afinidade, budget.
**LÊ** (já existe): `customization.mods` (peças) + `catalog.p1` (identidade).

### 5.6 Integração com handling (§5.2.1 — Manifestação física híbrida)

| Eixo | Como vira física real |
|------|-----------------------|
| POTÊNCIA | mod **NATIVO** do GTA (`engine` 11 + `turbo` 18) — o jogo aplica sozinho |
| FRENAGEM | mod **NATIVO** (`brakes` 12) |
| (top speed) | mod **NATIVO** (`transmission` 13) |
| GRIP | **OVERRIDE** server-auth: `fTractionCurveMax/Min` |
| AERO | **OVERRIDE** server-auth: `fInitialDragCoeff` |
| SUSPENSÃO | **OVERRIDE** server-auth: `fAntiRollBarForce` (altura visual = mod nativo `suspension` 15) |

> **⚠️ RISCO TÉCNICO Nº1 — gate `vhub_guardiao_natives` bloqueante:** em FiveM, `SetVehicleHandlingFloat` historicamente altera o handling **compartilhado do MODELO** (model-wide), não da instância. Se model-wide, **dois players no mesmo modelo com builds diferentes COLIDEM** — quebrando a premissa "o mesmo carro, configurado diferente". Sem essa validação, a Fase 4 (física) não começa.
>
> **Status (carskill_testplan.md):** F5 está LIGADA (decisão #28). O build vira handling real no carro dirigido via `SetVehicleHandlingFloat`, server-authoritative + re-clampado. O carro de terceiros aparece com handling base (fallback aceito). A mitigação: aplicar só no carro dirigido + restaurar ao sair. **A prova in-game do risco nº1 ainda pendente.**

### 5.7 Progressão

- `tier_base` (do catálogo) é o **chão físico base** (definido pelo `.meta` selado offline).
- Tier exibido em jogo é **recalculado pelo servidor** a cada mudança de upgrade, mas **nunca sobe mais de 1 tier acima do base** (anti-salto, conforme `tier_max` do catálogo).

### 5.8 Casos de uso

- **Build "Drag":** POT 220 / GRIP 120 / FRE 120 / AERO 180 / SUSP 160 → reta/0-100.
- **Build "Circuit":** POT 140 / GRIP 200 / FRE 200 / AERO 120 / SUSP 140 → curva/controle.
- Dois Tier A completamente diferentes. Nenhum "melhor" — especializados.

### 5.9 Score global (§3.6 — cruzamento de relações, ancorado no nativo)

```js
const score = Math.round(
  ( accel*0.30 + launch*0.10 + grip*0.30 + brake*0.15 + stability*0.15 ) * 1000
)
```

Onde:
- `accel` = `normalizeVsNative(driveForce, ref.driveForce)` — sem escalar por massa (§1.5).
- `launch` = `clamp01(gripRel / driveRel) * (isAWD ? 1.0 : isRWD ? 0.85 : 0.92)` — wheelspin.
- `grip` = `normalizeVsNative(gripMax, ref.gripMax)`.
- `brake` = `normalizeVsNative(brakeForce, ref.brakeForce)`.
- `stability` = `stabilityFrom(antiRollBar, suspForce, inertiaZ)` — peso entra aqui.

Tier por `clampToNativeBand(calcTier(score), pwrToWeight, ref)`.

### 5.10 Afinidade por tipo de pista (§5.4)

5 contextos 0..1: `reta`, `curva`, `montanha`, `drift`, `cidade`. Cruzamentos reais:
- **drift inverte grip** (circuit é ruim em drift, drag é bom);
- **largada** penaliza torque sem grip;
- **agilidade** dampeada conforme inércia/peso preservados.

### 5.11 O que `vhub_p1skill` NÃO faz (§8)

- Não modifica `.meta` em runtime (isso é o pipeline offline).
- Não é dono da identidade do veículo (isso é `vhub_conce/shared/catalog.lua`).
- Não escreve estado físico (isso é `exports.vhub_conce:saveVehicleState`).
- Não controla loja de upgrades, preço, propriedade ou spawn.
- Não impõe limite de velocidade (anti-cheat do core + governor client opcional).

---

## 6. Contexto Adicional (`cont1.md`)

### 6.1 O que é `cont1.md`

Arquivo de contexto de **1.192 linhas** em `resources/[CAR]/cont1.md`. Compõe **três documentos** colados:
1. **vHub Handling Balancer v3.0 "AI Identity Edition"** (linhas 1–974) — evolução da v2.0 com IA Gemini, tier fluido e HUD runtime FiveM.
2. **Plano de Organização e Criação do Script de Balanceamento** (linhas 986–1192) — recapitula o v2.0 em prosa (matriz ouro, fórmulas, anti-capotamento, selo + drift + CI).

> **É um documento de trabalho histórico** que consolida a spec v3.0 do `handling-balancer` (especificamente a edição "AI Identity") antes da reversão ao NÚCLEO-8 preservado definido no `carskill.md` v2.2. Vários elementos (injeção de COM offset, anti-capotamento automático, vehicle-registry.json com `specsByTier`) **foram supersedidos** pela decisão do dono (2026-06-15) de **reescrever só 8 campos** e **preservar todo o resto, incluindo a lataria**.

### 6.2 Resumo dos principais pontos (v3.0 AI Identity Edition)

**Correção crítica de física (§1):** `fMass` NÃO afeta aceleração em GTA5 — F=ma cancela. Bug da v2.0: `driveSeed = (tier.drive/massBase)*modMass` penalizava leves e bonificava pesados sem fundamento. v3.0 normaliza direto ao `tier.drive` com modificador `driveModifier` (±10%).

**Tier Fluido (§5):** `baseTier` (stock) + `maxTier` (Stage 3 full). Pipeline pré-calcula Stage 3 completo e aplica **freio aerodinâmico preventivo** (`dragCompensation` cap 18%). HUD exibe `"B → A (S3)"`.

**7 arquivos de config (v3.0):** `vanilla-reference.json` (âncora nativa), `tiers.json` (com `tierCrossThreshold`), `registry.json` (suporta `baseTier`/`maxTier`), `overrides.json` (modificadores de identidade), `mods-delta.json` (multiplicadores de upgrade), `scan-paths.json`, `seal.json`.

**Integração Gemini (§4):** comando `profile` chama API Google Gemini com prompt estruturado, retorna JSON com `baseTier`/`maxTier`/`confidence`/`justification`/`overrides`/`archetype`. **Nunca aplica ao `.meta`** — dev revisa e roda `apply` depois. Degrada graciosa se sem chave/quota.

**mods-delta.json (§2.5):**
- `engine` modType 11, DRIVE_FORCE_MULTIPLIER, levels 0→1.0, 1→1.075, 2→1.145, 3→1.215, 4→1.285 (+7.5% por nível).
- `turbo` modType 18, DRIVE_FORCE_TOGGLE, onValue 1.15 (+15%).
- `transmission` modType 13, VELOCITY_MODIFIER, levels 0→1.0, 1→1.03, 2→1.06, 3→1.09.
- `brakes` modType 12, BRAKE_FORCE_MULTIPLIER, 0→1.0, 1→1.05, 2→1.10, 3→1.15.
- `suspension` modType 15, GRIP_SUBMODIFIER (reduz ângulo de slip).

**HUD runtime (§7):** resource `vb-core` FiveM lê `vehicle-registry.json` (output do CLI). Detecta entrada no veículo, calcula tier efetivo baseado em mods instalados, exibe HUD com badge + seta "→ maxTier", specs (0-100, top, freio, grip), arquétipo, corridas disponíveis, próximo tier. Comandos `/veiculo` e `/tier`.

**Roadmap v3.0 (§10):** 8 fases — Fundação, Apply+Identidade, Seal+CI, Gemini Profile, Stage 3 Predict, HUD FiveM, Corridas+Licenças, Telemetria.

### 6.3 Como se relaciona com o resto

`cont1.md` é a **origem histórica** do que viria a ser simplificado em `carskill.md` v2.2. Decisões como `baseTier`/`maxTier` fluíram para `catalog.p1` (`tier_base`/`tier_max`). A regra de "preservar identidade" virou a decisão do dono 2026-06-15 (PRESERVAR LATARIA + reescrever só NÚCLEO-8). O `vehicle-registry.json` v3.0 foi **substituído** por `out/catalog-patch.json` mesclado em `catalog.lua`. O HUD `vb-core` separado foi **substituído** pela aba "Ficha do Veículo" no painel existente do `vhub_vehcontrol`.

**Conclusão:** `cont1.md` é referência histórica/roadmap; **não é código atual**. Para spec vigente, ler `carskill.md` v2.2 (com banner "ESTADO REAL") e `vhub_vehcontrol/PLANO.md`.

---

## 7. Convenções do `CLAUDE.md`

### 7.1 Convenções de código (padrões obrigatórios)

- **Módulo server-side mínimo (Lua 5.4):**
  ```lua
  -- módulo.lua — <descrição em PT-BR>
  local M = {}; M.__index = M; vHub.NomeModulo = M
  function M:init(cfg, driver) ... end
  return M
  ```
- **OOP via `vHub.class()`** para domínios com estado; tabela simples para utilitários puros.
- **`vHub.assertThread()`** obrigatório em toda função pública com `Citizen.Await`.
- **`Citizen.CreateThread`** apenas para operações assíncronas reais; destruir ao fim.
- **Sem `while true do`** sem condição de saída explícita.
- **Sem `print()`** fora de `shared/logger.lua` e `bootstrap.lua`.
- **Sem SQL inline** — CORE usa `S:prepare()` + `S:query()`; resources externos usam `exports.oxmysql` diretamente.
- **Exports sensíveis:** `_invoker_allowed()` + `GetInvokingResource()`.
- **Export-first (decisão do dono 2026-06-27):** todo resource expõe `exports(...)` das suas ações públicas **mesmo sem consumidor atual** — obrigatoriamente gated default-deny.

### 7.2 Convenções de nomenclatura

- **Identificadores e flags:** inglês (L-08).
- **Comentários, saídas, `lang.*`, NUI:** PT-BR (L-08).
- **Tabelas SQL próprias:** prefixo `vhub_<dom>_*`. **Proibido** `INSERT/UPDATE/DELETE` em `vh_users`, `vh_characters`, `vh_vehicles`, `vh_*_data`.
- **`shared/events.lua`:** `VHubDom.E = { SRV_ACT = 'vhub_dom:server:Act', CLI_X = 'vhub_dom:client:X' }` (global — sem `return`). **Anti-fantasma:** nunca `local Events = {...} return Events` (loader descarta o return; foi o padrão morto do spawnselector).
- **Vetores (L-19):** `vec3`/`vec4` são de uso LOCAL — NÃO cruzam `TriggerClientEvent`/`TriggerServerEvent`/`exports`/`SendNUIMessage` (msgpack entrega como tabela indexada `{1,2,3}`). Payload que cruza fronteira carrega coord como primitivo `{x=,y=,z=[,h=]}`.
- **Banners `=` (60 colunas)** separam grandes contextos; cabeçalho em CAIXA ALTA.
- **Duas linhas em branco antes** de cada banner; **uma depois**.
- **Função pública:** uma linha de comentário PT-BR objetiva imediatamente acima.
- **Largura de linha alvo:** 100 colunas; máximo absoluto 120.

### 7.3 Convenções de SQL

- **CORE:** único ponto de escrita SQL é `state.lua`; queries centralizadas em `sql.lua` (24 prepares).
- **Recursos externos:** `exports.oxmysql` diretamente (não via `vHub.State`).
- **Schema externo canônico:** `CREATE TABLE IF NOT EXISTS` idempotente; `ENGINE=InnoDB CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`; FK ao core **`INT UNSIGNED`** com `ON DELETE CASCADE ON UPDATE CASCADE`; `updated_at ... ON UPDATE CURRENT_TIMESTAMP`; KV próprio em `BLOB` (64 KB) — `MEDIUMBLOB` só com justificativa.
- **Pré-requisito:** oxmysql com `multipleStatements=true` (validado em `Driver:init`).
- **BLOB com blindagem b64** (hotfix 2026-06-11): msgpack binário era MANGLED na fronteira Lua→JS.
- **BLOB guard 60KB** previne envenenar transaction.

### 7.4 Convenções de eventos

- **`vHub.E.*` read-only** — metatable protege constantes contra escrita (16 constantes: 8 net events c→s, 5 server-local, 3 client-bound).
- **Server-side `TriggerEvent` local** (12 institucionais): `vHub:playerJoin/Leave/Spawn/Death/characterLoad + vehicleLoaded/Spawned/Despawned/Enter/Leave/KeyTransferred/FuelEmpty`.
- **Client-bound (5):** `vHub:initDone/charSelected/charSelectFailed/vehicleStateLoad/passengerMode` (último não registrado no client).
- **Net events c→s (8):** 5 veículo DORMENTES (`vHub:vSpawned/vDespawned/vEnter/vLeave/vState` — decisão #24) + `vHub:ready/died/selectChar` ATIVOS.
- **Sem callbacks tradicionais** (sem `lib.callback`/`ox_lib.callback`/`RegisterNUICallback`).
- **Estado de entidade para todos = State Bag, nunca `TriggerClientEvent(-1)`** (broadcast só para evento discreto/efeito momentâneo).
- **`AddStateBagChangeHandler`/`AddEventHandler`** antes de `while true`.

### 7.5 Convenções de segurança

- **Payload size check** em todo `K:net` (padrão: 8192 bytes).
- **Rate limit O(1) sliding window** em todos os net events (ex: `vHub:vState` — 8 por 1s; `vHub:ready` — 5 por 15s).
- **Silent block** — cliente nunca sabe que foi bloqueado por rate limit.
- **Permission guard** — `K:net` com `opts.perm` verifica antes do handler.
- **`_invoker_allowed()`** em exports sensíveis — whitelist por resource (`vHub.cfg.trusted_resources`).
- **Type-safe ban** — `ban.reason` e `ban.by` são sempre strings.
- **Guard `src <= 0`** — rejeita eventos do servidor ou sources inválidas.
- **Guard de double-connect** — `Auth._sessions` impede sessão duplicada.
- **`Sec:requireAdmin`** dupla verificação (ACE FiveM + perms internas, admin.* curinga). `Sec:_permFail` silencioso (não kicka — não informa atacante).
- **`checkPayload`** com validators de TX (default pass-through, extensível).
- **`pcall`** nas fronteiras (export externo, payload). Nunca derrubar o tick.

### 7.6 O que é esperado de um agente desenvolvedor

**Condições de parada obrigatórias (pare e reduza escopo imediatamente ao detectar):**
- Segunda fonte de verdade para o mesmo dado.
- Novo resource/módulo sem ownership e lifecycle documentados.
- Cliente decidindo verdade crítica sem validação server-side.
- SQL inline fora de `state.lua`/`sql.lua` (CORE only).
- Export sensível sem `_invoker_allowed()`.
- Loop sem condição de saída explícita.

**Fluxo preferencial multi-agente:**
1. Ler `.claude/contexto.md`.
2. Mapear arquivos tocados.
3. `vhub_arquiteto` → ownership, placement, fase.
4. Guardiões relevantes em PARALELO (somente os pertinentes ao risco).
5. Worker executa SOMENTE após todos aprovarem.
6. `vhub_guardiao_revisao` → gate final + atualiza `contexto.md`.

**Economia de tokens (obrigatório):**
- Enviar ao agente: objetivo + restrições + diff + arquivos tocados (nunca histórico completo).
- Agente para na menor evidência suficiente para o veredito.
- `SEM ACHADOS CRÍTICOS` quando não houver problema real — nunca fabricar achados.

**Mapa de modelos por agente (CLAUDE.md):**
- `vhub_arquiteto`: Opus 4.7 xhigh.
- `vhub_guardiao_revisao`: Opus 4.8 xhigh.
- `vhub_guardiao_seguranca`: Opus 4.8 high.
- `vhub_designer`: Opus 4.7 high.
- `vhub_guardiao_contrato`/`natives`/`performance`/`designer`/`runtime`: Sonnet 4.6 high.
- `vhub_guardiao_simplicidade`: Sonnet 4.6 medium.

**Autonomia de produção (decisão do dono 2026-06-27):** agir sem pedir confirmação a cada passo, tomando decisões de engenharia. Autonomia ≠ pular governança — continue rodando gates. `contexto.md` é o segundo cérebro COMPLETO — não enxugar por tamanho.

---

## 8. Planos Individuais (PLANO.md de cada recurso)

### 8.1 `vhub_custom/PLANO.md`

**Versão:** 1.0.0 · **Status:** Plano aprovado pela arquitetura (decisão #26 candidata) · **Modelo:** Opus 4.8.

**Escopo:** `resources/[SCRIPTS]/vhub_custom` = UM resource, três domínios — `bennys` (estética), `mec` (reparo + reboque), `oficina` (performance/tuning).

**Premissa-mestra:** *peça ao dono, nunca escreva no que não é seu.* `vhub_custom` é **CONSUMIDOR** do PRONTUÁRIO (`vhub_vehicle_state`, dono = `vhub_conce`). **Não ganha ownership de nenhum dado existente.**

> **CORREÇÃO HONESTA:** a expectativa de "adicionar tabelas/colunas ao `vhub_vehicle_state`" foi **REPROVADA**. Tuning de stage nativo já cabe em `customization.mods` (whitelist `CUST_KEYS`). Coluna nova de handling override só entra **na F2** sob dono do `vstate.lua`.

**Veredito de arquitetura (5 itens A–E):**
- A. Topologia: 1 resource, 3 sub-pastas, 1 `fxmanifest`.
- B. Persistência tuning: stages nativos em `customization.mods` AGORA; alloc/score/handling = derivado pelo `vhub_p1skill` (F2), sem coluna nova.
- C. Quem persiste: `vhub_custom` chama `exports.vhub_conce:saveVehicleState` direto; entra no `TRUSTED`; `source='cosmetic'` (bennys) / `'tune'` (oficina).
- D. mec vs garage: mec **DELEGA** o ato de reparo (não duplica fórmula); reboque = domínio novo no mec.
- E. Sync carskill F2: evento `vHub:vehicleCommitted` emitido pelo **VState do conce** (escritor único), não pela oficina.

**Fluxo canônico server-authoritative (5 passos):** cliente previsualiza no veículo VIVO (efêmero) → envia INTENÇÃO ao servidor → `canOperate(src,plate)` → calcula CUSTO server-side → `Core.pay` → persiste via escritor único → confirma + log.

**Split obrigatório cosmético × performance (§7.1):**
- PERFORMANCE (oficina, PROIBIDO no bennys): mods 11, 12, 13, 15, 16, 18.
- COSMÉTICO (bennys): TODO o resto — cor, neon, fumaça (20), xenon (22), window_tint, livery, plate_index, wheel_type, mods visuais de lataria (0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 23, 24, 25..49).

**Roadmap por fase (F0–F6):**
- F0: Registro de Ownership + bundle de contrato no conce.
- F1: Esqueleto (fxmanifest, shared, server/core+init, zonas client) + replay-guard.
- F2: `mec` (reparo delegação + reboque).
- F3: `bennys` (estética).
- F4: `oficina` (stages nativos dentro do cap de tier, sem carskill).
- F5: NUI completa (Liquid Glass + Areia + Dourado).
- F6: **Acoplamento carskill F2** (`vhub_p1skill`): `validateAlloc`, evento `vehicleCommitted`, override de handling.

> **Status (worklog Task 4):** implementado. 1 resource, 3 domínios (bennys=cosmético source='cosmetic', mec=reparo+reboque source='repair', oficina=stages+calibração+nitro source='tune'). Zero SQL direto. Câmera orbital L2 HAL. NUI Liquid Glass. Conflito dealership conce×garage é por design (decisão #25).

### 8.2 `vhub_vehcontrol/PLANO.md`

**Versão:** 1.0.0 · **Status:** Aprovado pelo arquiteto (decisão #27 candidata) · **Modelo:** Opus 4.8.

**Escopo:** `vhub_vehcontrol` vira o **CENTRO ÚNICO do veículo** — controle (portas/luz/motor) + identidade derivada (tier/score/afinidade) + redistribuição de pontos (skill) + gancho de nitro. **Substitui** a ideia de um resource `vhub_p1skill` separado: o `carskill.md` permanece como **referência conceitual**.

> **Diretriz do dono:** tudo do veículo num lugar só, consultável/editável por todos **sem competir, sem 2ª verdade, sem um invalidar o outro** (o anti-padrão mec×bennys).

**Princípio-mestre:** `UMA fonte de verdade por dado · UM escritor · MUITOS leitores · ZERO recálculo paralelo.`

**O dado:**
- **PERSISTE:** `customization.handling` (alloc dos 5 eixos) — prontuário, dono = conce/VState.
- **DERIVA on-read:** tier, score, afinidade, budget (nunca persistido).
- **LÊ (já existe):** `customization.mods` (peças) + `catalog.p1` (identidade).

**Modelo de pontos HÍBRIDO (decisão do dono):** veículo tier X tem N pontos naturais. Cada peça comprada **adiciona** pontos: metade FIXA no eixo natural da peça, metade LIVRE para realocar em combinações semânticas.

**INVARIANTE server-side (`validateAlloc`):**
```
Σ alloc == budget_total                                  -- não pode criar/sumir pontos
cada eixo dentro de ALLOC_RANGE (% do budget, anti-P2W)  -- nada all-in num eixo
o 'livre' de cada peça só pode ir aos eixos 'livres' dela -- semântica respeitada
```

**Os DOIS pontos de entrada da recalibração (mesma lógica):**
- PORTA A — Chave-item + 'caixa de ferramentas' (player abre painel do veículo).
- PORTA B — Oficina + mecânico (player na zona da oficina, vhub_custom).

Ambas chamam `vhub_vehcontrol/server/skill.lua : recalibrate(src, plate, allocDesejado, origem)`.

**Consumo de 'caixa de ferramentas':** ambas portas consomem 1× item por recalibração. Ordem anti-perda: **validar → persistir → consumir** (perder o save é pior que perder o item).

**Exports públicos (read-only):**
- `getVehicleTier(plate)` → 'D'..'S+' (derivado).
- `getVehicleScore(plate)` → 0..1000.
- `getVehicleAffinity(plate)` → {reta, curva, montanha, drift, cidade}.
- `getVehicleSheet(plate)` → ficha completa flat {tier, tier_base, tier_max, score, budget_total, budget_used, alloc, affinity, parts_bonus}.

**Gancho NITRO (futuro, só reservar):** `NITRO_LEVELS` em config + `customization.nitro = { level=0..N }` no `CUST_KEYS`. Calibração Duração ↔ Potência.

**Roadmap por fase (F0–F6):**
- F0: Pipeline offline gera `catalog-patch.json` p/ ~15 carros.
- F1: **BUNDLE CONCE** (pré-req): `handling` no `CUST_KEYS` + `source='handling'` + bloco `catalog.p1` mesclado.
- F2: `shared/tier_rules.lua` (puras) + `shared/events.lua` + `server/exports.lua`.
- F3: Aba "Ficha do Veículo" no NUI da chave (LEITURA).
- F4: `server/skill.lua`: recalibração server-auth (2 portas) + consumo caixa + persist + HUD. **NÚMERO/HUD, sem física.**
- F5a: **PoC risco nº1** (`SetVehicleHandlingFloat` por-instância vs model-wide) — BLOQUEANTE de F5b.
- F5b: Física real (override grip/aero/susp) — SÓ se F5a aprovado.
- F6: Gancho nitro + integrar `vhub_nitro`.

> **Status (worklog Task 5):** implementado. Server-authoritative. Modular (1 responsabilidade por arquivo). Decisões #27/#28/#30/#34. F5 (física) está LIGADA (decisão #28). TIER é derivado on-read (nunca persistido, L-04). Skill system NÃO tem progressão/XP — é "skill de configuração". Item handlers: `veh_key` abre painel; `caixadeferramentas` abre Ficha em edição. 5 exports vhub_vehcontrol (todos read-only). Pontos de atenção: `Config.skillDebug=true` e `Config.skillBruteTest=true` LIGADOS em produção (devem ser false); risco nº1 model-wide pendente de prova in-game; R-3 dívida ordem cobrança→persistência.

### 8.3 `vhub_racha/relatorio.md`

**Documento:** "VHUB RACHA - MASTER PROMPT DEFINITIVO (ENTERPRISE EDITION)".

> *"Transformar o `vhub_racha` em uma plataforma profissional de corridas competitivas para FiveM, comparável a um jogo standalone, mantendo alta escalabilidade, segurança máxima, excelente experiência do usuário e desempenho extremo."*

**Princípios fundamentais (prioridade máxima, nunca inverter):**
1. Segurança  2. Estabilidade  3. Performance  4. Escalabilidade  5. Manutenibilidade  6. UX  7. UI  8. Estética.

**REGRAS ABSOLUTAS:** sempre — escolher a solução mais lógica/segura/escalável/eficiente/sustentável; eliminar gaps lógicos/semânticos/gargalos/comportamentos implícitos/redundâncias; antecipar problemas futuros. Nunca — criar código temporário/paliativo; duplicar lógica; criar dependências circulares; loops permanentes desnecessários; polling excessivo; espalhar regras de negócio.

**Performance (resmon):**
- Idle: próximo de 0.00ms.
- Client: priorizar eventos; evitar loops; Wait(0) desnecessário; atualizar só em mudança; cache inteligente; debounce/throttle; lazy loading.
- NUI: atualizações incrementais; virtualização de listas; evitar re-renderizações; listeners duplicados; DOM excessivo.
- Banco: queries indexadas; cache; carregamento sob demanda.

**Segurança (server-authoritative):** validar eventos, checkpoints, distâncias, tempos, posições, veículos, recompensas, apostas, PDL, participantes. Proteger contra trigger injection, event spam, packet spam, teleporte, speed hack, manipulação de tempo/checkpoints, corridas fantasmas, participações duplicadas, exploits de PDL/apostas, farm de ranking.

**Sistema de estado global da corrida:** Idle, WaitingPlayers, Lobby, Starting, Countdown, Racing, Paused, Finishing, Results, Canceled, Closed. Nenhuma corrida sem estado definido.

**Sistema ranqueado (PDL próprio):** Bronze → Prata → Ouro → Platina → Diamante → Mestre → Grão-Mestre → Lendário. Considera PDL individual, diferença de habilidade, jogadores, colocação, consistência. Impede boosting, smurfing, farm.

**Modos:** Normal (apostas, sem PDL), Personalizada (creator editor), Ranqueada (PDL, modo espectador).

**Modo espectador:** só em ranqueadas; trocar corredor; câmera livre/automática; estatísticas.

**Replay e ghost run:** infraestrutura futura para trajetória, velocidade, inputs, tempos. Replay, fantasma pessoal, fantasma global.

**Sistema de temporadas, achievements, reputação.**

**Observabilidade:** monitorar CPU, GPU, memória, rede, eventos, latência, gargalos.

**Feature flags:** toda nova funcionalidade ativável/desativável/testável sem alterar arquitetura.

**Escalabilidade futura:** clãs, equipes, torneios, campeonatos, eventos especiais, passe de corrida, IA analítica, API externa.

**Checklist obrigatório (10 perguntas internas antes de implementar):** existe gap lógico? gap semântico? gargalo? risco de segurança? risco de escalabilidade? inconsistência visual? regra implícita? possibilidade de exploit? dependência circular? funcionará daqui a 2 anos?

**Instrução final:** nunca gerar todo o código de uma vez; sempre em etapas — Analisar → Encontrar gaps → Propor soluções → Validar arquitetura → Implementar → Testar → Medir performance → Validar segurança → Refatorar → Limpar e garantir ausência de segundas verdades ou lixo, então Documentar.

### 8.4 `Drift/README.md`

> *"Mecânica de drift para FiveM: ajusta o **handling** em tempo real (handbrake + acelerador) e dá um **boost** controlado (anti-exploit). Além da mecânica, ele **fabrica a pontuação bruta** de drift (ângulo × velocidade × combo) e a expõe via export. **Não desenha UI** — o HUD e o 'banco' da pontuação são do `vhub_racha`."*

**Como pontua (ângulo ≥ 15°, ≥ 30 km/h, sem bater):**
```
pontos/seg = min(ângulo × velocidade / 40, 150) × combo
combo = 1.0 → 1.5 (5s) → 2.0 (12s) → 3.0 (25s) de drift contínuo
```

- Bater (queda de body health) reseta combo + conta como "crash".
- Soltar drift por > 700 ms zera combo.

> `SCORE_CAP_PER_SEC`, divisor e combo devem ficar **alinhados** com `vhub_racha` (`shared/config.lua → DRIFT`) — servidor é autoridade e faz cap final por segundo.

**Export (consumido pelo vhub_racha):**
```lua
local t = exports.Drift:getTelemetry()
-- t.total, t.crashes, t.combo, t.angle, t.speed, t.drifting, t.active
```

**Divisão de responsabilidade:**
| Camada | Faz |
|--------|-----|
| Drift | mecânica (handling + boost) + fabrica pontuação bruta + telemetria |
| vhub_racha (modo drift) | banca pontuação: a cada 5s sem bater vira válido; bater perde lote pendente. Envia ao servidor (autoridade) + mostra no HUD |

**Controles:** Acelerador + Freio de mão (entra em drift); ângulo ≥ 20° ativa boost (1.2s, cooldown 4s).

**Créditos:** Base *MoravianLion* / *VoidMods*. Adaptado ao vHub Mirage (remoção de UI, fabricação de pontuação, export `getTelemetry`).

### 8.5 `handling-balancer/script.md` e `README.md`

**Versão:** 2.0.0 · **Status:** Spec revisada (pronta para implementar) · **Classificação:** Strict Standard.

**Objetivo:** Padronização **determinística e auditável** do `handling.meta` de veículos mod (add-on), garantindo hierarquia de Tiers (D → S+), integridade física (anti-capotamento), teto de velocidade coerente por tier e **integridade competitiva**.

**Decisão arquitetural:** pré-processamento (CLI) — **não roda em Lua no servidor**. Servidor FiveM apenas lê os `.meta` nativamente (C++ da engine) no boot — zero loop, zero thread, zero impacto em `resmon` (alinhado a L-05/L-06).

**9 correções v1.0 → v2.0 (script.md §0):**
1. `registry.json` casa por `handlingName` (normalizado UPPERCASE), não nome de pasta.
2. Substituição cirúrgica linha-a-linha (sem `xml2js` que reescreve tudo).
3. Cap real de 280 km/h = **3 camadas** (§8) — não é isolado.
4. `fBrakeForce` tem modelo próprio (decel-alvo por tier + bias), não escala com potência.
5. Anti-capotamento real combina `fTractionBiasFront`, `fRollCentre*`, `fAntiRollBarForce`, suspensão e downforce.
6. Backup automático, `--dry-run`, diff preview, relatório, exit codes para CI.
7. Seal + drift detection: hash sha256 por arquivo commitado; CI falha se `.meta` divergir.
8. `overrides.json`: tier define padrão, override afina campo de carro sem quebrar tier.
9. Pasta correta: `tools/handling-balancer/` (não `[TOOLS]/vhub_testrunner/`).

**Matriz de Normalização de Tiers (Padrão Ouro) — `tiers.json` (script.md §4):**

| Tier | Ref. Nativa | Massa Base (kg) | Drive (force) | Drag | Grip Max | Grip Min | Marchas | DriveInertia | MaxFlatVel | Top Speed (a validar) |
|------|-------------|-----------------|---------------|------|----------|----------|---------|--------------|------------|------------------------|
| D | Blista | 1100 | 0.140 | 11.5 | 2.05 | 1.90 | 5 | 1.00 | 125 | ~170 km/h |
| C | Kuruma | 1400 | 0.180 | 10.5 | 2.15 | 2.00 | 5 | 1.00 | 130 | ~190 km/h |
| B | Elegy | 1500 | 0.220 | 10.0 | 2.30 | 2.15 | 6 | 1.10 | 132 | ~220 km/h |
| A | Banshee | 1400 | 0.260 | 9.5 | 2.45 | 2.30 | 6 | 1.20 | 135 | ~245 km/h |
| S | Zentorno | 1500 | 0.310 | 9.2 | 2.65 | 2.50 | 6 | 1.30 | 138 | ~265 km/h |
| S+ | Krieger | 1500 | 0.350 | 9.0 | 2.80 | 2.65 | 7 | 1.40 | 140 | **280 km/h (cap-alvo)** |

**Campos de freio e estabilidade por tier (script.md §4):**

| Tier | BrakeForce | BrakeBiasFront | TractionBiasFront | AntiRollBar | COM z-offset (anti-capot.) |
|------|------------|----------------|-------------------|-------------|----------------------------|
| D | 0.70 | 0.62 | 0.49 | 0.55 | −0.05 |
| C | 0.80 | 0.62 | 0.49 | 0.60 | −0.06 |
| B | 0.90 | 0.60 | 0.48 | 0.65 | −0.08 |
| A | 1.00 | 0.58 | 0.47 | 0.70 | −0.10 |
| S | 1.10 | 0.56 | 0.47 | 0.75 | −0.10 |
| S+ | 1.20 | 0.55 | 0.46 | 0.80 | −0.12 |

**Algoritmo de normalização (script.md §5):**
- **5.1 Força motriz:** seed por power-to-weight, depois **clamp** (`driveSeed = (tier.drive / tier.massBase) * modMass`, `driveFinal = clamp(driveSeed, tier.drive * 0.85, tier.drive * 1.15)`).
- **5.2 Marchas, inércia e ceiling:** `fInitialDriveMaxFlatVel = tier.maxVel`, `nInitialDriveGears = tier.gears`, `fDriveInertia = tier.driveInertia`, `fInitialDragCoeff = tier.drag`.
- **5.3 Anti-capotamento:** pacote coerente com clamp e opt-out (COM z relativo, tractionBiasFront, antiRollBar, rollCentreHeight ≤ 0.20, suspensionReboundDamp clamp 1.6–2.4).
- **5.4 Campos preservados vs. modificados vs. injetados:** MODIFICA 11 campos de performance + INJETA 3 campos de estabilidade com clamp + PRESERVA drivetrain/feel/suspensão.

> **⚠️ IMPORTANTE (README.md NÚCLEO-8):** a v2.0 do `script.md` injeta 11 campos (incluindo anti-capotamento). O `carskill.md` v2.2 e o README do handling-balancer **SUPERARAM** essa abordagem — o pipeline escreve **SÓ 8 campos de performance** (`fInitialDriveForce`, `fInitialDragCoeff`, `fInitialDriveMaxFlatVel`, `fDriveInertia`, `fBrakeForce`, `fTractionCurveMax`, `fTractionCurveMin`, `fAntiRollBarForce`). **NUNCA toca** lataria/dano, suspensão, COM, inércia, drivetrain, marchas, flags, SubHandlingData e todo conteúdo visual. O `script.md` v2.0 §5.3 (injeção de anti-capotamento / 11 campos) está **SUPERADO** — não reintroduzir.

**Teto de 280 km/h — defesa em 3 camadas (script.md §8):**

| Camada | Onde | Custo | Garante |
|--------|------|-------|---------|
| 1. Meta (este pipeline) | `handling.meta` selado | zero runtime | chão físico coerente por tier |
| 2. Governor client-side (opcional) | resource leve client | mínimo (event/timer, L-06) | teto exato mesmo com upgrades |
| 3. Validação server-side (já existe) | vHub valida posição/velocidade | já contabilizado | pega teleport/trainer |

**Selo + detecção de drift + CI (§11):** `seal.json` (commitado) = sha256 por `.meta`. `verify` recomputa e falha o PR com exit 1 se divergir. GitHub Action roda `verify --json` no PR.

**Protocolo de validação em jogo (§12):** pista LSIA, 2 marcadores + cronômetro, medir 0-100 e top speed full-tuning (Stage 3 + nitro), comparar com alvos do tier (±5%), ajustar `overrides.json`, re-`apply`, re-medir.

**Roadmap incremental (script.md §16):** F0 MVP (scan + plan read-only) → F1 Apply seguro → F2 Selo + CI → F3 Validação → F4 Upgrades/modkit.

**README do balancer:** foco operacional. Interface web (`node balance.js serve`, porta 7920) com cards de decisão (rename, análise, decisão de tier). Renomear veículo em TODOS os arquivos do mod. Áudio de veículos com som próprio (alinhamento de `.awc/.rel/audioNameHash`). Backup automático + selo sha256 + `catalog-patch.json`.

**Contrato do `catalog-patch.json` (ponte para a Fase 2):**
```jsonc
{
  "a80": {
    "handling_name": "a80",
    "tier_base": "A", "tier_max": "S",
    "archetype": "rwd_heavy",
    "grip_modifier": 0.92,
    "base_alloc": { "potencia":160, "grip":160, "frenagem":160, "aero":160, "suspensao":160 },
    "drive_bias": 0.0, "susp_raise": 0.0, "mass": 1750.0,
    "inertia_z": 1.8, "low_speed_loss": 1.2,
    "seal": "sha256:..."
  }
}
```

**Invariante travada:** se `base_alloc` for definido, **soma deve ser exatamente igual ao `budget` do `tier_base`** (D=500, C=600, B=700, A=800, S=900, S+=1000). Caso contrário, exit 2.

**Ownership/lifecycle (L-07):** Dono = equipe veículos/física. Lifecycle = pré-deploy (local + CI), **nunca** em runtime do servidor. Placement = `tools/handling-balancer/`.

**Roadmap (README):**
- **F1 (esta):** CLI + selo + catalog-patch + interface web. ✅
- F2: Extensão `catalog.p1` no `vhub_conce` (gate do conce); garage exibe `tier_base`. ⏳
- Futuro: IA Gemini assistente (nomear arquétipo), leitura de `vehicles.meta` para upgrades/Stage 3. ⏳ adiado.

---

## 9. Decisões Arquiteturais (Architecture Decision Records)

As decisões numeradas são referenciadas em vários documentos. **Mapeamento coletado:**

| # | Título | Contexto | Decisão | Consequências | Recurso afetado |
|---|---|---|---|---|---|
| **#8** | Nunca `S:prepare` cross-resource | Resources externos tentavam usar `S:prepare()` do CORE | Resources externos usam `exports.oxmysql` diretamente | Isolamento de SQL; CORE permanece único dono das queries `vh_*` | Todos `[SCRIPTS]/vhub_*` |
| **#24** | Handlers de veículo dormintes (N0-3 2026-06-21) | Risco de grief: atacante forjava `vEnter` com netid da vítima → `onEnter` concedia `NetworkSetEntityOwner` da entidade alheia | `vHub:vSpawned/vDespawned/vEnter/vLeave/vState` registrados com corpo NO-OP (`_vhDisarmed`) | `Veh:onStateUpdate` nunca é chamado em runtime; State Bags `vh_*` nunca escritas pelo CORE; `client/vehicle.lua` envia `vState` a 4Hz silenciosamente descartado | CORE `vhub` |
| **#25** | Conflito dealership conce×garage | `vhub_garage` e `vhub_conce` ambos lidam com concessionária | `garage` é delegator fino (NUI/eventos); `conce` é autoridade (transações) | Não há conflito — papéis distintos | `vhub_conce`, `vhub_garage` |
| **#26** | vhub_custom: 1 resource, 3 domínios | Oficina mecânica/estética/reparo | UM resource com 3 sub-pastas `bennys/mec/oficina`, 1 `fxmanifest` | Stages nativos em `customization.mods` AGORA; alloc/score/handling = derivado por `vhub_p1skill` (F2), sem coluna nova | `vhub_custom` |
| **#27** | vhub_vehcontrol: CENTRO ÚNICO do veículo | `vhub_p1skill` seria resource separado; `vhub_vehcontrol` já é controle | `carskill.md` permanece como **referência conceitual**; engine de skill vive DENTRO de `vhub_vehcontrol` | Substitui `vhub_p1skill` separado; `customization.handling` é o alloc persistido; tier/score/afinidade derivados on-read | `vhub_vehcontrol` |
| **#28** | F5 (física) LIGADA | Override de handling por `SetVehicleHandlingFloat` | Física real aplicada no carro dirigido (potência/grip/freio/aero/suspensão); mitigação: aplicar só no dirigido + restaurar ao sair | Risco nº1 (model-wide) pendente de prova in-game; carro de terceiros aparece com handling base (fallback aceito); `Config.skillApplyHandling = true` liga/desliga | `vhub_vehcontrol` |
| **#29** | vhub_nitro: escritor único do estado do nitro | Nitro precisava de fonte única server-authoritative | `customization.nitro={kit,qty,enabled,level}` na PLACA via conce; exports TRUSTED-gated | Drain monotônico decrescente; boost por Shift Direito com fogo no escapamento; rate-limit 350ms | `vhub_nitro`, `vhub_conce` |
| **#30** | vhub_nitro + ficha do vehcontrol (Doutrina da Placa) | Uso por proximidade era frágil | Tudo mora na PLACA; FICHA do veículo só EXIBE e DELEGA via exports (`setEnabled`/`setLevel`/`chargeFromItem`). Uso por proximidade **aposentado** | Instalação do kit R$ 5.000 na oficina; abastecer pela ficha (consome 1 garrafa); nível 1..10 (durabilidade↔velocidade) | `vhub_nitro`, `vhub_vehcontrol` |
| **#34** | (mencionada em worklog Task 5, sem detalhe no docs lidos) | — | — | — | `vhub_vehcontrol` |
| **#35** | Export-first (decisão do dono 2026-06-27) | Resources futuros poderiam precisar de exports ainda não existentes | Todo resource expõe `exports(...)` das suas ações públicas **mesmo sem consumidor atual** — gated default-deny | Não conta como dead code (L-15) — é superfície de API deliberada; ownership ainda exigido (L-07); referência: `setActivityBucket` em `vhub_player_state` | Todos `[SCRIPTS]/vhub_*` |

> **Notas:**
> - **#1–#7, #9–#23, #31–#33** não aparecem explicitamente nos 15 docs lidos — são referenciados em outros artefatos (`.claude/contexto.md`, `FROZEN_EXEC_LOG.md`).
> - **#10** implícito no `PLANO_IMPLEMENTACAO_VEICULOS.md` §3.6 (Decisão #8: nunca `S:prepare` cross-resource).
> - As **N0-N** (N0-2, N0-3) referem-se a notas/notificações do `FROZEN_EXEC_LOG.md` (default-deny em `_invoker_allowed`; handlers dormintes).
> - A doutrina **PRONTUÁRIO** (vhub_vehicle_state substituindo vh_vehicle_data do CORE) é uma decisão arquitetural majoritária implícita na IT.2 (mencionada no manual como exceção ao freeze).

---

## 10. Metas e Configs

### 10.1 `/home/z/my-project/workspace/vhubMirage/metas/`

Conteúdo:
- `fivem_natives_organizadas_ptbr.md` — Referência organizada de natives FiveM em PT-BR. Mencionado no manual_dev_vhub.md §0 ("Native-first — `metas/fivem_natives_organizadas_ptbr.md`") como fonte para procurar natives antes de helper custom.

> **Observação:** o `README.md` cita `metas/manual_dev_vhub.md`, mas o arquivo real está em `resources/[SCRIPTS]/manual_dev_vhub.md` (cópia idêntica). O `metas/` contém apenas o arquivo de natives.

### 10.2 `/home/z/my-project/workspace/vhubMirage/config/`

| Arquivo | Conteúdo (relevante a veículos) |
|---|---|
| `server.cfg` | Ordem: `network → database → identity → acl → resources`. Convars: `vhub_log_level=1`, `wow_jamendo_id`, `vrcs_discord_webhook`. |
| `resources.cfg` | **Ordem de ensure obrigatória** (ver §2.10). Inclui `oxmysql → vhub → vhub_notify → vhub_groups → vhub_identity → vhub_money → vhub_survival → vhub_player_state → vhub_inventory → vhub_conce → carmod → vhub_ferinha → vhub_garage → vhub_admin → vhub_legacyfuel → vhub_login → vhub_racha → vhub_vrcs → vhub_custom → vhub_lspdtool → vhub_loading → vhub_vehcontrol → vhub_velo → vhub_nitro → vhub_spawselector → Drift → vhub_ipad → vhub_wow` + mapas. |
| `database.cfg` | `mysql_connection_string = "mysql://root@127.0.0.1/vhub?charset=utf8mb4&multipleStatements=true"` — **`multipleStatements=true` obrigatório**. `mysql_slow_query_warning=200`, `mysql_debug=false`, `mysql_ui=false`. |
| `network.cfg` | `endpoint_add_tcp/udp 0.0.0.0:30120`. `sv_maxclients 7`. `onesync on`, `onesync_enabled true`, `onesync_enableInfinity 1`. `onesync_distanceCullVehicles true`, `onesync_forceMigration true`. `rateLimiter_stateBag_rate 2000`, `rateLimiter_stateBag_burst 3000`. `sv_enforceGameBuild 2189`. |
| `identity.cfg` | `sv_licenseKey`, `sv_hostname "MIRAGE RP - VoidHub"`. `sv_projectName "Mirage RP"`, `sv_projectDesc "Base vHUB"`, `locale "pt-BR"`, `tags "+18, RACE, NO P2W, GOLPE, ROUBO, darkrp"`. Banners Discord. `setr vhub_log_level 1`. |
| `acl.cfg` | `add_ace group.admin vhub.admin.full/allow`, `vhub.player.kick/allow`, `vhub.player.ban/allow`. Admins por `identifier.license:<hash>` (placeholder comentado). |
| `logo.png` | Ícone do servidor (`load_server_icon logo.png` em `identity.cfg`). |

### 10.3 Configs de ferramentas relacionadas a veículos

- `tools/handling-balancer/config/`:
  - `tiers.json` — Matriz-Ouro por tier + `budget` de pontos + carro nativo de referência.
  - `registry.json` — `handlingName` (UPPERCASE) → `{ tier_base, tier_max }`.
  - `overrides.json` — Afinação fina por carro.
  - `archetypes.json` — `fDriveBiasFront` + `fMass` → arquétipo (`rwd_heavy`...) + `grip_modifier`.
  - `scan-paths.json` — Raízes do glob, exclusões, nomes de arquivo.

---

## 11. Mapa de Dependências

### 11.1 Ordem de boot recomendada (ver §2.10 para lista completa)

```
[BD]            oxmysql
[CORE]          vhub, vhub_notify
[Identidade]    vhub_groups, vhub_identity
[Economia]      vhub_money
[Vida]          vhub_survival
[Jogador]       vhub_player_state, vhub_inventory
[Veículos]      vhub_conce → carmod → vhub_ferinha → vhub_garage
[Admin]         vhub_admin, vhub_legacyfuel, vhub_login
[Gameplay]      vhub_racha, vhub_vrcs, vhub_custom
[Policial]      vhub_lspdtool
[Outros]        vhub_loading, vhub_vehcontrol, vhub_velo, vhub_nitro,
                vhub_spawselector, Drift, vhub_ipad, vhub_wow
[Mapas]         bob74_ipl-master, blodline, audi, depzitamadasptlnd,
                fav_barragem, hayes-dean
```

### 11.2 Quem chama exports de quem (TRUSTED lists)

**`vhub_conce` — TRUSTED list** (confirmed by vhub_custom PLANO §5):
> Hoje TRUSTED: `vhub`, `garage`, `ferinha`, `admin`, `inventory`, `vehcontrol`, `legacyfuel`, `testrunner`. **Faltando:** `vhub_custom` (adicionar em F0).

**`vhub_nitro` — exports TRUSTED-gated** (1 read + 4 mutators):
- `getVehicleNitro(plate)` (read).
- `installKit` / `setEnabled` / `setLevel` / `chargeFromItem` (mutators).

**`vhub_vehcontrol` — 5 exports read-only:**
- `getVehicleTier` / `getVehicleScore` / `getVehicleAffinity` / `getVehicleSheet` / `getVehicleSheetPreview`.

**CORE `vhub` — exports:**

| Export | Proteção |
|--------|----------|
| `getVHub()` | pública |
| `getUser(src)` | pública |
| `getUID(src)` | pública |
| `hasPerm(uid, perm)` | pública |
| `grantPerm(uid, perm)` | `_invoker_allowed()` |
| `getVehicle(plate)` | pública |
| `transferKey(plate, key)` | `_invoker_allowed()` |
| `banPlayer(uid, r, by)` | `_invoker_allowed()` |
| `unbanPlayer(uid)` | `_invoker_allowed()` |
| `Status()` | pública |

> `_invoker_allowed()` default-deny desde N0-2 (readme do core desatualizado neste ponto). Se `vHub.cfg.trusted_resources` vazio → todos aceitos (atenção em produção).

### 11.3 Dependências de resources (declarações de fxmanifest)

**`vhub_p1skill` (spec, não implementado):**
```lua
dependencies { 'vhub', 'oxmysql', 'vhub_conce', 'vhub_racha' }
```

**`vhub_custom`** (PLANO §2): 1 resource, 3 domínios. Depende de `vhub_conce` (PRONTUÁRIO), `vhub_money` (pagamento), `vhub_inventory` (itens/chaves), `vhub_vehcontrol` (F6 — validateAlloc).

**`vhub_vehcontrol`**: depende de `vhub`, `vhub_conce` (getCatalog, getVehicleState, saveVehicleState), `vhub_inventory` (caixa de ferramentas), `vhub_player_state` (HAL).

**`vhub_garage`**: delega para `vhub_conce` (catálogo/registro/prontuário) e `vhub_ferinha` (leilão).

**`vhub_nitro`**: depende de `vhub_conce` (escrita `customization.nitro` na PLACA).

**`Drift`**: produz telemetria consumida por `vhub_racha`.

**`vhub_racha`**: lê tier via `exports.vhub_vehcontrol:getVehicleTier(plate)` para gatekeeping. Consome `Drift:getTelemetry()`.

---

## 12. Glossário

| Termo | Definição |
|---|---|
| **VRAM** | Memória volátil in-process do CORE (state.lua `_mem`). "VRAM-first" = leitura vai à memória antes do SQL; SQL é backup. Hot keys (`ban.active`, `whitelist`, `permissions`) ficam em VRAM mesmo após `_set`. |
| **State Bag** | Mecanismo nativo FiveM para sync de estado de entidade/player entre server e clientes. Server escreve via `Entity(ent).state:set(key, val, true)` / `Player(src).state:set(...)`. Client lê via `Entity(ent).state.<key>` ou `AddStateBagChangeHandler`. **Sempre preferido a `TriggerClientEvent(-1)`** para estado de entidade. |
| **Driver** | No CORE, source atual do motorista do veículo (`vd.driver`). Distinto de **key_uid** (dono persistente) e **Network Owner** (cliente com controle de rede da entidade). |
| **Owner / Network Owner** | Cliente responsável por simular a entidade. Definido por `NetworkSetEntityOwner` em `onEnter/onLeave`. |
| **Tier** | Classificação de performance do veículo: D < C < B < A < S < S+. Definido pelo `tier_base` do catálogo (`catalog.p1`) derivado do `.meta` selado offline. Tier exibido em jogo é **recalculado on-read** (nunca persistido, L-04), clampado a `tier_max`. |
| **Archetype** | Arquétipo físico do veículo (drivetrain + peso): `rwd_light`, `rwd_heavy`, `fwd_light`, `fwd_heavy`, `awd_light`, `awd_heavy`. Definido por `fDriveBiasFront` (0=RWD, ~0.5=AWD, 1=FWD) + `fMass`. Modifica `grip_modifier` e `comZOffset`. |
| **Prontuário** | Tabela `vhub_vehicle_state` (DDL própria do `vhub_conce/server/vstate.lua`). **Substitui** `vh_vehicle_data` do CORE para estado físico do veículo. Escritor único = `vhub_conce/VState`. Cabeçalho documenta 9 regras (âncora fail-closed, source gates, monotonic health, NaN/Inf rejection, merge por chave exceto mods por índice, caps 8/2/16KB, escrita imediata). |
| **`commitVehicleState(plate, patch, reason)`** | Contrato congelado (IT.2) do CORE. Único caminho para terceiros escreverem estado físico do veículo. Valida, clampa, marca dirty, sincroniza bags, loga `reason`. |
| **`getVehicleState(plate)`** | Snapshot read-only do estado físico do veículo. **Dois homônimos:** `exports.vhub:getVehicleState` (CORE, **inerte**) e `exports.vhub_conce:getVehicleState` (PRONTUÁRIO, **ativo**). |
| **Registro de Ownership** | Tabela em `CLAUDE.md` que mapeia cada dado a (dado, owner, leitores, persistência, contrato). Sem linha = sem dado. |
| **Replay-safe** | Handler de evento institucional idempotente (L-17). CORE re-dispara `vHub:playerSpawn`/`vHub:characterLoad` em `onResourceStart` de qualquer resource — todo handler precisa deduplicar por `user.spawns` ou ID de sessão. |
| **VRAM-first** | Padrão de leitura: VRAM hit → retorna direto (sem DB); VRAM miss → query DB → armazena em VRAM → retorna. Escrita: atualiza VRAM + enfileira no batch + invalida VRAM (exceto hot keys). |
| **NÚCLEO-8** | Os 8 campos de performance que o pipeline offline do `handling-balancer` escreve no `.meta`: `fInitialDriveForce`, `fInitialDragCoeff`, `fInitialDriveMaxFlatVel`, `fDriveInertia`, `fBrakeForce`, `fTractionCurveMax`, `fTractionCurveMin`, `fAntiRollBarForce`. (Decisão do dono 2026-06-15; supersed a v2.0 do script.md que injetava 11.) |
| **LATARIA** | Multiplicadores de colisão/deformação/dano (`fCollisionDamageMult`, `fDeformationDamageMult`, `fWeaponDamageMult`, `fEngineDamageMult`, `strDamageFlags`) + todo conteúdo visual (`carcols.meta`, `carvariations.meta`, `.yft`, `.ytd`, `vehicles.meta`). **NUNCA tocados** pelo pipeline offline. |
| **HÍBRIDO** | Modelo de manifestação física do carskill: potência/freio/topspeed = mod NATIVO do GTA; grip/aero/suspensão = override server-authoritative via StateBag. Cliente nunca inventa valor de handling. |
| **Alloc** | Alocação dos pontos do jogador nos 5 eixos (POT/GRIP/FRE/AERO/SUSP). Persistido em `customization.handling`. Escritor único = conce/VState; único chamador autorizado = `vehcontrol/server/skill.lua`. |
| **BUDGET** | Teto de pontos por tier: D=500, C=600, B=700, A=800, S=900, S+=1000. Invariante: `soma(alloc) == BUDGET[tier_base]`. |
| **ALLOC_RANGE** | Range de alocação por atributo (% do budget) — anti-P2W. Máx 35% por eixo. |
| **PART_POINTS** | Tabela semântica (shared/config.lua do vehcontrol): cada peça declara pontos + eixo fixo + eixos livres. Ex.: `[18] turbo: 15 pts, fixo=potencia, livres={potencia,grip}`. |
| **`base_alloc`** | Distribuição NATURAL do tier (ponto de partida do alloc do jogador). Vem do `catalog.p1`. Soma deve ser exatamente igual ao `budget` do `tier_base`. |
| **Afinidade** | Vetor 5-contextos 0..1: `reta`, `curva`, `montanha`, `drift`, `cidade`. Cruzamentos reais: drift inverte grip; largada penaliza torque sem grip; agilidade dampeada por inércia/peso. |
| **Seal** | Hash sha256 selado por arquivo `.meta` em `.seal/seal.json` (commitado). `verify` recomputa e falha CI (exit 1) se divergir. |
| **Drift detection** | Detecção de edição manual não-autorizada de `.meta` comparando com seal. Bloqueia edição na fonte (repo/deploy); não impede trainer client-side (trabalho do anti-cheat server-side). |
| **CORE FROZEN** | Estado do `[CORE]/vhub` selado em 2026-05-22. Kernel imutável; mudanças apenas aditivas com gate duplo (`vhub_arquiteto` + `vhub_guardiao_revisao`) + bump para `core-frozen-v2.0`. |
| **Doutrina da Placa** | Tudo do nitro mora na PLACA (`customization.nitro={kit,qty,enabled,level}`); FICHA do veículo só EXIBE e DELEGA via exports (decisão #30). |
| **L0..L19 / A0..A10** | Leis imutáveis (L) e de componentização (A) do CLAUDE.md. Ver §2.1 e §7. |

---

## 13. Pontos de Atenção Documentados

### 13.1 Pendências conhecidas

- **R-3 (ordem cobrança→persistência):** hoje cobra item/dinheiro **antes** de persistir. Se o save falhar (raro — placa fora do registro), o jogador perde a porta sem recalibrar. Decisão de design da #27 (fail-toward-house); pendente de sessão dedicada com `vhub_guardiao_seguranca` + `vhub_guardiao_contrato` para transação com rollback. (carskill_testplan.md §7.)
- **`vHub:vehicleCommitted` NÃO escutado:** o hnd aplicado pode ficar stale se player comprar peça sem reabrir ficha. Mitigado por `coerceAlloc` na leitura. (worklog Task 5.)
- **`vHub:vehicleCommitted` reservado em events.lua:21 mas NUNCA emitido:** TriggerEvent ausente no vstate.lua. (worklog Task 4 — vhub_conce.)
- **F2 do handling-balancer pendente:** Extensão `catalog.p1` no `vhub_conce` (gate do conce); garage exibe `tier_base`. (handling-balancer/README.md Roadmap.)

### 13.2 Bugs conhecidos

- **Config flags em produção:** `Config.skillDebug=true` e `Config.skillBruteTest=true` LIGADOS em produção no `vhub_vehcontrol/shared/config.lua` — **devem ser false** (carskill_testplan.md §0).
- **`vhub_garage` divergências do manual:** `TriggerClientEvent(-1)` vs State Bag; prefixo `vrp_` em eventos; leitura direta de `vhub_auctions` competindo com `ferinha` (worklog Task 3).
- **`vhub_garage` bugs:** status 'rental' não usado; `max_veiculos_player` não enforced; configs vestigiais; eventos vestigiais; eventos declarados sem handler (worklog Task 3).
- **`vhub_garage` riscos de segurança:** `impoundVehicle` sem gate de perm; `TxLock` process-local (worklog Task 3).
- **`vhub_conce` gaps:** `vhub_vehicles.customization LONGTEXT` deprecated mas não droppado; 4 literais de evento hardcoded (`'vhub_custom:server:mecTowDone'`, `'vhub_vehcontrol:recalibrate'`, `'vhub_vehcontrol:recalDone'`, `'vhub_garage:doDespawn'`) violam L-19; cache VRAM `_cache` sem GC; `vhub_custom` não tem `server/exports.lua` apesar de PLANO.md prever (worklog Task 4).
- **CORE minor leak** em `Driver:_executar` (closure 15s) — worklog Task 2.
- **`auth.lua` e `boot.lua` ainda têm `print()` de debug** (viola regra do Logger) — worklog Task 2.
- **`vHub:passengerMode` não registrado no client.**
- **`vehicleStateLoad` handler existe mas nunca invocado** (onEnter dorminte).
- **`validateConfig` exportado mas nunca usado.**
- **Schema migration `MEDIUMBLOB`→`BLOB` requer ALTER manual.**
- **`client/vehicle.lua` envia vState que é descartado** — tráfego morto (handlers dormintes #24).

### 13.3 Riscos mapeados

- **Risco Técnico nº1 (carskill §5.2.1, veículo-control PLANO F5a):** `SetVehicleHandlingFloat` historicamente altera handling **compartilhado do MODELO** (model-wide), não da instância. Se model-wide, dois players no mesmo modelo com builds diferentes COLIDEM. **Status:** mitigado por código (aplicar só no dirigido + restaurar ao sair), mas **prova in-game pendente** (carskill_testplan.md §6c). Sem essa validação, a Fase 4 (física) seria bloqueante — mas decisão #28 já ligou a F5 aceitando o fallback.
- **CORE handlers de veículo dormintes (decisão #24):** cadeia física morta por design. Resources externos precisam chamar `Veh:onSpawned/onStateUpdate` diretamente ou implementar pipeline próprio.
- **Transações in-memory (não SQL atômico):** risco de perda dos últimos segundos em crash abrupto (kill -9/power outage).
- **`_defaults` de `shared/config.lua` é essencialmente morto:** bootstrap não chama `mergeConfig`.
- **Divergências de defaults entre arquivos:** `fuel_rate` 0.01 vs 0.005 vs fallback 0.005; `max_speed_kmh` 400 vs 350.
- **`SPAWN_POS` hard-coded no fallback.**
- **`assertThread` apenas nos getters** (setters não chamam).
- **VRAM sem TTL:** cresce linearmente.
- **`clampagem 0.5km/tick de odômetro parece ampla demais.**

### 13.4 Áreas marcadas como "caixa preta"

> **`vstate.lua` NÃO é mais caixa preta** (worklog Task 4): cabeçalho documenta 9 regras (âncora fail-closed, source gates, monotonic health, NaN/Inf rejection, merge por chave exceto mods por índice, caps 8/2/16KB, escrita imediata).

Áreas ainda **caixa preta / divergências arquiteturais conhecidas** (carskill.md banner ESTADO REAL):

- **§2 do carskill.md (estrutura `vhub_p1skill/` separado):** não construída — vive dentro do vehcontrol.
- **§5.2.1 StateBags `vhub_p1`/`vhub_p1_hnd`:** não implementadas (a decisão #28 usa mecanismo próprio em `client/handling.lua`).
- **§5.5–§5.8 HUD client, telemetria `vhub_p1skill_telemetry`, snapshot/racha:** não construídos.
- **`[CAR]/carmod` vazio:** os 62 arquivos reais do carmod permanecem em `resources/[SCRIPTS]/carmod`. Move para `[CAR]` foi adiado.
- **Tier Fluido v3.0 (`baseTier`/`maxTier` com `tierCrossThreshold` e `dragCompensation`):** superado pela decisão do dono 2026-06-15 (reescrever só NÚCLEO-8). O `tier_max` do `catalog.p1` sobrevive como teto anti-salto, mas o `dragCompensation` preventivo do `cont1.md` v3.0 não foi implementado.
- **HUD `vb-core` separado com `vehicle-registry.json` (cont1.md §7):** substituído pela aba "Ficha do Veículo" no painel existente do `vhub_vehcontrol`.

### 13.5 Pontos de atenção documentados pelos planos individuais

- **vhub_custom PLANO §12 — Riscos e mitigações:**
  - 2ª fonte de verdade de tuning (coluna alloc/score): **não criar**.
  - Cliente injeta mod de performance pelo bennys: `MOD_SPLIT` server-side rejeita.
  - Duas fórmulas de custo de reparo (mec×garage): mec **delega**.
  - Override de handling model-wide: **F6 bloqueado** até PoC por-instância.
  - Derivador (p1skill) dessincronizado: evento `vehicleCommitted` nasce no escritor único.
  - Reboque duplica/teleporta entidade errada: `NetworkRequestControlOfEntity` + anti-dupe + validação placa↔netId.
  - Carro de rua persiste tuning: âncora fail-closed do vstate.
  - NUI a 60fps / loop quente sempre ligado: A-08 + zonas fria/quente.

- **vhub_vehcontrol PLANO §9 — Condições de parada:**
  - Persistir tier/score/afinidade em qualquer lugar → 2ª fonte (L-04).
  - Cálculo dentro de `server/main.lua` do vehcontrol → monolito (L-09).
  - Física (F5b) antes do PoC (F5a) aprovado → risco nº1 (L-16). **Bloqueante absoluto.**
  - garage/racha com `calcTier` próprio → recálculo paralelo (L-04).
  - Redistribuição lendo o dossiê-cópia da chave como verdade → estado stale.
  - F1 (bundle conce) não preceder o código do vehcontrol → budget sem `catalog.p1` → entrega vazia.
  - Oficina duplicando a lógica de alloc em vez de chamar o vehcontrol → competição (anti mec×bennys).

- **vhub_racha relatorio §1 — Principais pontos que faltavam:** replay e ghost run; anti-cheat específico; temporadas; achievements; reputação; telemetria completa; eventos especiais; arquitetura para expansão; observabilidade; rollback e recuperação; feature flags; versionamento; sincronização tolerante a lag; anti-abuso de PDL; anti-farm; previsibilidade de rede; estados global da corrida; pipeline de assets SVG; regras obrigatórias de desenvolvimento.

---

## 14. Resumo Executivo

O vHub Mirage é um framework FiveM GTARP **server-authoritative**, **VRAM-first**, com **batch SQL atômico** (800 ops / 3s) e **CORE FROZEN v1.0** selado em 2026-05-22. Sua "constituição" reside em **L-01 a L-19** (leis imutáveis) + **A-01 a A-10** (componentização NUI) no `CLAUDE.md`, operacionalizadas pelo `manual_dev_vhub.md` v2.0.

A **lei-mestra** é *"peça ao dono, nunca escreva no que não é seu"* — todo dado tem UMA linha no Registro de Ownership; escrita por **contrato de commit** (`commitVehicleState`, `saveVehicleState`, `spawnAt`/`teleport`). O **PRONTUÁRIO** (`vhub_vehicle_state`, dono = `vhub_conce`) substituiu `vh_vehicle_data` do CORE como fonte ativa de estado físico do veículo; `commitVehicleState`/`getVehicleState` do CORE estão inertes (handlers dormintes, decisão #24).

O **ecossistema de veículos** tem 3 pilares:
1. **Balanceamento estático offline** (`handling-balancer` CLI Node.js) — reescreve apenas **NÚCLEO-8** campos de performance no `.meta`, preserva lataria e identidade, selo sha256 + CI; produz `catalog-patch.json` mesclado no `catalog.lua` do conce.
2. **Balanceamento dinâmico runtime** (`vhub_vehcontrol` — decisão #27) — engine de skill vive dentro do vehcontrol; **5 eixos** (POT/GRIP/FRE/AERO/SUSP) com **BUDGET** fixo por tier (D=500..S+=1000); modelo **híbrido** (mods nativos para POT/FRE/transmissão; override server-auth para GRIP/AERO/SUSP); persiste só `customization.handling` (alloc); tier/score/afinidade derivados on-read; 2 portas de recalibração (caixa de ferramentas + oficina) com 1 handler.
3. **Filosofia matemática** (`sss.txt`) — Sweet Spot de peso 1.450–1.750 kg para "Heavy-Sport/GT"; AWD com viés traseiro (0.30–0.40 `fDriveBiasFront`) para categoria "Equilibrada"; punição por peso ancorada em `fDriveInertia` e `fTractionCurveMax/Min`.

**Decision records numeradas (#8, #24, #25, #26, #27, #28, #29, #30, #34, #35)** mapeiam a evolução arquitetural: do "conflito dealership" (#25) à "centralização do veículo no vehcontrol" (#27), passando pela "F5 física ligada" (#28), "Doutrina da Placa do nitro" (#30) e "Export-first" (#35).

**Pontos críticos pendentes:**
- **Risco Técnico nº1** (`SetVehicleHandlingFloat` model-wide): prova in-game pendente — sem ela, dois carros do mesmo modelo com builds diferentes podem colidir fisicamente.
- **R-3** (ordem cobrança→persistência): dívida conhecida no `vhub_vehcontrol`.
- **`vHub:vehicleCommitted` reservado mas não emitido** no vstate do conce.
- **Config flags** `skillDebug`/`skillBruteTest` ligados em produção.
- **F2 do handling-balancer**: extensão `catalog.p1` no conce + garage exibindo `tier_base`.

A governança é multi-agente (`vhub_arquiteto` + 7 guardiões + `vhub_guardiao_revisao` como gate final), com fluxo preferencial: ler `contexto.md` → mapear arquivos → arquiteto → guardiões paralelo → worker → revisão. Autonomia de produção concedida em 2026-06-27 (agir sem pedir confirmação, mas sem pular gates).

---

*Fim do documento — Síntese dos Documentos Fundacionais do vHub Mirage (Task 1, Reference Docs Synthesizer).*
