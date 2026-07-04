# 05 — Análise Profunda: `vhub_vehcontrol` + `vhub_nitro`

**Task ID:** 5 · **Agente:** VehControl+Nitro Analyzer · **Versão analisada:**
- `vhub_vehcontrol` v1.1.0 (fxmanifest.lua)
- `vhub_nitro` v2.0.0 (fxmanifest.lua — "Reescrito de vRP p/ vHub (decisão #29)")

**Origem:** `workspace/SCRIPTS/` (extraído do `SCRIPTS.zip`).
**Idempotência GitHub:** `diff -r` contra `vhubMirage/resources/[SCRIPTS]/vhub_vehcontrol` e `/vhub_nitro` → **zero diferenças**. ZIP == GitHub.

**Documentação de referência cruzada:**
- `[CAR]/carskill.md` v2.2.0 — spec conceitual do engine de skill (fonte dos eixos/pesos/afinidade).
- `[CAR]/carskill_testplan.md` — roteiro de teste do skill em jogo.
- `[CAR]/nitro_testplan.md` — roteiro de teste do nitro (pós #30).
- `vhub_vehcontrol/PLANO.md` — plano canônico (decisão #27).
- `manual_dev_vhub.md` v2.0 — leis L-xx e A-xx citadas ao longo do texto.

> **Decisões arquiteturais citadas:** #24 (cadeia CORE vEnter desconectada, sprint PRONTUÁRIO), #26 (conce dono de mods/turbo), #27 (vehcontrol = centro único do veículo + skill + nitro_bridge), #28 (F5 física derivada), #29 (reescrita vRP→vHub do nitro), #30 (Doutrina da Placa: nitro na ficha), #34 (som via vhub_wow soft-dep).

---

## 1. Visão Geral

### 1.1 Papel de cada recurso

| Resource | Versão | Papel | Dependências hard |
|---|---|---|---|
| `vhub_vehcontrol` | 1.1.0 | **Centro único do veículo**: controle (portas/luz/motor), identidade derivada (tier/score/afinidade), redistribuição de pontos (skill), gancho de nitro (delega), ponte de som (vhub_wow) e telemetria física do motorista (sprint PRONTUÁRIO) | `vhub`, `vhub_inventory` |
| `vhub_nitro` | 2.0.0 | **Escritor único do nitro server-authoritative**. Estado mora na PLACA (`customization.nitro`). Ativa por SHIFT Direito no client. Reescrito de vRP (decisão #29); aposentou uso por proximidade (#30) | `vhub`, `vhub_inventory` |

Soft-deps (via `pcall` em `exports`, **não** declaradas em `dependencies` para não travar boot):
- `vhub_conce` — dono do catálogo + prontuário (`getVehicle`, `getVehicleState`, `saveVehicleState`, `canOperate`, `getCatalog`). Sem ele, skill/nitro degradam (fail-closed).
- `vhub_garage` — caminho "dono do veículo" da trava/motor (sem ele, vale só a chave física).
- `vhub_wow` — provider de áudio 3D (sem ele, o rádio não funciona; o resto do vehcontrol intacto).
- `vhub_money` — cobrança da porta "oficina" (`tryFullPayment`).

### 1.2 Conceito de TIER (categoria de veículo)

TIER = classificação derivada **em tempo de leitura** (nunca persistida — L-04). Definida em `shared/tier_rules.lua`:

```lua
TR.TIER_ORDER = { 'D', 'C', 'B', 'A', 'S', 'S+' }
TR.BUDGET     = { D=500, C=600, B=700, A=800, S=900, ['S+']=1000 }
TR.TIER_SCORE = {
  D  = { min=0,   max=199  }, C  = { min=200, max=399 },
  B  = { min=400, max=599  }, A  = { min=600, max=749 },
  S  = { min=750, max=899  }, ['S+'] = { min=900, max=1000 },
}
```

Tier **base** (`tier_base`) e tier **teto** (`tier_max`) vêm do bloco `catalog.p1` do `vhub_conce` (gerado pelo pipeline offline `tools/handling-balancer/`, selado com `sha256`). O tier exibido é `clampTier(calcTier(score), tier_max)` — nunca ultrapassa o teto do catálogo.

### 1.3 Relação com handling-balancer

O `handling-balancer` (pipeline Node.js offline, descrito em `carskill.md` §3) produz o `out/catalog-patch.json` — um bloco `.p1` por veículo que é **mesclado por humano** no `vhub_conce/shared/catalog.lua`:

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

O vehcontrol **lê** `catalog.p1` via `exports.vhub_conce:getCatalog()` (com cache por índice lowercase em `server/exports.lua` — função `buildIndex()`). **Nunca** escreve no catálogo. A relação é unidirecional: balancer → conce → vehcontrol(lê).

### 1.4 Diferença entre `vhub_nitro` (standalone) e o `nitro_bridge` dentro de vehcontrol

| | `vhub_nitro` (standalone) | `server/nitro_bridge.lua` (dentro vehcontrol) |
|---|---|---|
| **Dono do dado** | Sim — escritor único de `customization.nitro` via `saveVehicleState(...,'nitro')` | Não — só **delega** via exports |
| **Exports sensíveis** | `installKit`/`setEnabled`/`setLevel`/`chargeFromItem` (TRUSTED gate) | nenhum — apenas eventos |
| **Eventos que escuta** | `vhub_nitro:request`, `vhub_nitro:drain` | `vhub_vehcontrol:nitroToggle`, `:nitroLevel`, `:nitroCharge` |
| **Quem chama** | vehcontrol(nitro_bridge), vhub_custom(installKit), client.lua própria | NUI `nitroToggle`/`nitroLevel`/`nitroCharge` via client/main.lua |
| **Física (boost)** | `client.lua`: `SetVehicleCheatPowerIncrease` + `ModifyVehicleTopSpeed` + fogo escapamento | Nenhuma |
| **Persistência** | patcheia `customization.nitro = {kit,qty,enabled,level}` na placa | nenhuma |

**Contrato claro:** o vehcontrol tem um **handler de intenção** (UI da ficha → `NITRO_TOGGLE`/`LEVEL`/`CHARGE`), e o `nitro_bridge.lua` traduz essa intenção em chamadas `pcall(function() exports.vhub_nitro:setEnabled(src, p, on) end)`. O `vhub_nitro` re-prova `canOperate`, valida `kit`, clamp `level 1..10`, e responde via `TriggerClientEvent('vhub_vehcontrol:nitroDone', src, ok, msg, nitro)`.

**Source of truth do estado do nitro** = `vhub_vehicle_state.customization.nitro` (propriedade da PLACA), escritor único `vhub_nitro`. O vehcontrol lê via `getNitro(plate)` para enxertar na ficha (`sheet.nitro` em `server/exports.lua`).

---

## 2. Sistema de TIERS (`shared/tier_rules.lua`)

Módulo PURO (`VHubVeh.TR`) — zero I/O, zero natives, zero SQL. Roda **idêntico** em server (autoridade) e client (preview da UI).

### 2.1 Constantes

```lua
TR.AXES        = { 'potencia', 'grip', 'frenagem', 'aero', 'suspensao' }      -- ordem canônica
TR.BUDGET      = { D=500, C=600, B=700, A=800, S=900, ['S+']=1000 }
TR.TIER_ORDER  = { 'D', 'C', 'B', 'A', 'S', 'S+' }
TR.TIER_SCORE  = { D={min=0,max=199}, C={min=200,max=399}, B={min=400,max=599},
                   A={min=600,max=749}, S={min=750,max=899}, ['S+']={min=900,max=1000} }
TR.ALLOC_RANGE = { potencia={min=0.10,max=0.35}, grip={min=0.08,max=0.35},
                   frenagem={min=0.08,max=0.30}, aero={min=0.08,max=0.30},
                   suspensao={min=0.08,max=0.28} }                              -- anti-P2W
TR.PART_POINTS = {
  [11]={pontos=20, fixo='potencia',  livres={'potencia','aero'}},          -- motor
  [18]={pontos=15, fixo='potencia',  livres={'potencia','grip'}},          -- turbo (torque↔acel)
  [12]={pontos=12, fixo='frenagem',  livres={'frenagem','suspensao'}},     -- freio
  [13]={pontos=10, fixo='potencia',  livres={'potencia','frenagem'}},      -- câmbio
  [15]={pontos=10, fixo='suspensao', livres={'suspensao','grip'}},         -- suspensão
  [16]={pontos=8,  fixo='suspensao', livres={'suspensao','frenagem'}},     -- blindagem
}
-- Pesos do score (espelha carskill §5.3)
local SCORE_W = { potencia=0.35, grip=0.30, frenagem=0.15, aero=0.10, suspensao=0.10 }
```

### 2.2 Lista de Tiers (faixas, regras, permissões)

| Tier | Score | Budget base | Observações |
|---|---|---|---|
| **D** | 0–199 | 500 | Tier natural de "Blista" (referência nativa) |
| **C** | 200–399 | 600 | "Kuruma" |
| **B** | 400–599 | 700 | "Elegy" |
| **A** | 600–749 | 800 | "Banshee" — Tier base do TOYOTASUPRA no exemplo |
| **S** | 750–899 | 900 | "Zentorno" — `tier_max` do Supra no exemplo |
| **S+** | 900–1000 | 1000 | "Krieger" — teto absoluto |

Regras/permissões:
- **Faixa de alocação por eixo** (`ALLOC_RANGE`): piso 8–10% e teto 28–35% do budget — anti-P2W (nada de "all-in num eixo").
- **`TR.range(ax)`**: fonte única da faixa vigente. Em produção retorna `ALLOC_RANGE[ax]`. Se `Config.skillBruteTest = true`, retorna `{0.0, 1.0}` (permite builds extremas p/ teste). Tudo que valida/clampa/desenha slider passa por aqui.
- **`TR.clampTier(tier, tierMax)`**: tier exibido nunca ultrapassa `tier_max` do catálogo (anti-salto).

### 2.3 Como um veículo é classificado em um tier

Fluxo (em `server/exports.lua::sheetOf(plate)`):

1. `exports.vhub_conce:getVehicle(plate)` → pega `model`.
2. `buildIndex()[string.lower(model)]` → entrada do catálogo (cacheia por spawn name **e** display name).
3. `entry.p1` → identidade física (fail-closed: sem `p1` → sem skill).
4. `exports.vhub_conce:getVehicleState(plate)` → lê `customization.{mods, turbo, handling}`.
5. `TR.buildSheet(base, cust.mods, cust.turbo, cust.handling)` → ficha derivada completa.

### 2.4 Como o tier é aplicado (handling, performance, etc.)

A ficha derivada (`TR.buildSheet`) retorna um FLAT de primitivos (L-19) — pronto p/ cruzar fronteira:

```lua
return {
  tier      = clampTier(calcTier(score), base.tier_max),     -- D..S+
  tier_base = base.tier_base,                                -- estático do catálogo
  tier_max  = base.tier_max,                                 -- estático
  archetype = base.archetype,
  score     = score,                                         -- 0..1000
  budget    = budget,                                        -- tier + peças
  used      = sumAlloc(alloc),
  alloc     = alloc,                                         -- {potencia,grip,...}
  affinity  = affinity,                                      -- {reta,curva,montanha,drift,cidade} 0..1
  parts     = partsBonus,                                    -- {total, fixed, free}
  ranges    = ranges,                                        -- faixa editável por eixo p/ slider
  free      = free,                                          -- pontos livres
  hnd       = (skillApplyHandling) and handlingFromAlloc() or nil,
  nitro     = (lido via exports.vhub_nitro:getNitro(plate))
}
```

A **aplicação física** (F5, decisão #28) só roda no **client que dirige** (`client/handling.lua`), `hnd` nunca é persistido (é derivado).

---

## 3. Handling Runtime (`client/handling.lua`)

### 3.1 Como o handling é aplicado em runtime

Caminho **server-authoritative**:
1. Server calcula `sheet.hnd` em `TR.handlingFromAlloc(alloc, budget, Config.skillHandling)`.
2. Client (`BECAME_DRIVER` event) pede a ficha: `TriggerServerEvent(E.REQ_SHEET, plate)`.
3. Server responde `TriggerClientEvent(E.SHEET, src, sheetOf(p, src))`.
4. Client aplica `applyHnd(_drivenVeh, sheet.hnd)`.
5. Ao sair do banco (`LEFT_VEHICLE` event), restaura o handling base do modelo (`restoreBase`).

### 3.2 Campos de handling modificados (Config.skillHandling)

Definidos em `shared/config.lua`:

```lua
Config.skillHandling = {
  potencia  = { field = 'fInitialDriveForce', min = 0.14, max = 0.46 },
  grip      = { field = 'fTractionCurveMax',  min = 1.55, max = 2.95 },
  frenagem  = { field = 'fBrakeForce',        min = 0.55, max = 1.65 },
  aero      = { field = 'fInitialDragCoeff',  min = 6.0,  max = 18.0 },
  suspensao = { field = 'fAntiRollBarForce',  min = 0.05, max = 1.50 },
}
```

`min > max` é OK (eixo inverso). `Config.skillGripMinRatio = 0.85` — quando o eixo é `grip`, também seta `fTractionCurveMin = v * 0.85` (mantém `Min < Max`).

Campos LIDOS (não modificados) para afinidade (em `TR.calcAffinity`): `drive_bias`, `susp_raise`, `inertia_z` (do `catalog.p1`).

### 3.3 Quem chama (evento/export)

- `AddEventHandler(E.BECAME_DRIVER, function(veh, plate))` — disparado por `client/main.lua` quando vira motorista.
- `RegisterNetEvent(E.SHEET)` — resposta do servidor com a ficha.
- `RegisterNetEvent(E.RECAL_DONE)` — após recalibração, reaplica `sheet.hnd` no carro dirigido.

### 3.4 Conversa com handling-balancer

**Indireta.** O vehcontrol NÃO fala com `handling-balancer` em runtime. A ponte é o `catalog.p1` no `vhub_conce` (escrito offline pelo balancer). Em runtime, vehcontrol lê `p1` via `getCatalog()` e deriva `hnd` via `TR.handlingFromAlloc`.

**Modelo híbrido (§5.2.1 do carskill.md):**
- `fInitialDriveForce` (potência), `fBrakeForce` (frenagem) — **override server-auth** (`SetVehicleHandlingFloat` no client).
- `fTractionCurveMax/Min` (grip), `fInitialDragCoeff` (aero), `fAntiRollBarForce` (suspensão) — idem override.
- Mods NATIVOS (`engine` 11, `turbo` 18, `brakes` 12, `transmission` 13) são aplicados pela oficina (`vhub_custom`) — o jogo GTA aplica sozinho.

### 3.5 Risco nº1 — model-wide (mitigado por código, prova pendente)

`SetVehicleHandlingFloat` em FiveM é historicamente **model-wide no cliente**: altera todas as instâncias do modelo na máquina local. Mitigação em `client/handling.lua`:
- `ensureBase(veh, model)` cacheia o valor ORIGINAL do `.meta` por field (1ª vez).
- `restoreBase(veh)` desfaz o override ao sair do veículo (`LEFT_VEHICLE` e `onResourceStop`).
- Aplica só no veículo que o jogador DIRIGE (seat -1).
- Carro de terceiros aparece com handling base (fallback aceito pela §5.2.1).

**Prova em jogo pendente** (carskill_testplan.md §6c): 2 players, mesmo modelo, builds diferentes — cada um sente o próprio build?

---

## 4. Skill System (`server/skill.lua`)

### 4.1 O que é "skill" (carskill)

O **skill** = **alocação dos 5 eixos** (potencia/grip/frenagem/aero/suspensao) que o jogador escolhe dentro do budget do veículo. É a "calibração" do carro — o ponto onde o jogador coloca a personalidade no build (drag vs circuit vs drift). Conceito do `carskill.md` §1.0 ("fácil de aprender, difícil de dominar"): UX de 5 eixos sobre ~48 campos físicos.

**Não é** skill de pilotagem do player (não há XP, levels de player). É skill de **configuração do veículo** — o que o carskill.md chama de "skill de montagem".

### 4.2 Como funciona progressão

O sistema **não tem progressão de skill em si**. A progressão é **do veículo**:
1. Compra peças na oficina (`vhub_custom`) → `customization.mods` aumenta.
2. Cada peça adiciona `PART_POINTS[idx].pontos` ao budget (metade fixa no eixo natural, metade livre).
3. Jogador redistribui os pontos livres via UI da ficha (sliders) → `customization.handling = {alloc}`.
4. Score/tier são derivados on-read do alloc — sobem quando o build foca em eixos de maior peso (potencia 35%, grip 30%, ...).

### 4.3 Persistência (SQL)

**NÃO há tabela SQL própria do vehcontrol** para skill. A persistência vive no `vhub_vehicle_state.customization.handling` (escritor único `vhub_conce` via `saveVehicleState(plate, {customization={handling=alloc}}, 'handling')`).

A única tabela mencionada no carskill.md (`vhub_p1skill_telemetry`, append-only) **não foi implementada** no vehcontrol atual (carskill.md banner "ESTADO REAL DA IMPLEMENTAÇÃO").

### 4.4 Integração com o skill do player

**Não há integração direta com skill de player.** O vehcontrol integra com:
- `vhub_inventory` — consome `caixadeferramentas` (porta toolbox) ou cobra dinheiro (porta oficina).
- `vhub_money` — `tryFullPayment(src, 2500)` na porta oficina.
- `vhub_conce` — `canOperate(src, plate)` (autoridade), `getVehicleState`, `saveVehicleState`.

### 4.5 Referência cruzada com `[CAR]/carskill.md`

| carskill.md (spec) | vhub_vehcontrol (implementado) | Status |
|---|---|---|
| §2 estrutura `vhub_p1skill/` resource separado | vive DENTRO de vehcontrol (decisão #27) | ✅ plano canônico PLANO.md |
| §3.6 score 0..1000 com `normalizeVsNative` | `TR.scoreFromAlloc` simplificado (âncora+delta) | ⚠️ simplificado |
| §5.2 StateBags `vhub_p1`/`vhub_p1_hnd` | NÃO implementado (usa `REQ_SHEET`/`SHEET` events + `RECAL_DONE`) | ❌ roadmap |
| §5.2.1 física híbrida via SetVehicleHandlingFloat | `client/handling.lua` (F5 ligado) | ✅ decisão #28 |
| §5.5 HUD client StateBag | NUI painel da chave (aba Ficha) | ✅ alternativa |
| §5.7 telemetria `vhub_p1skill_telemetry` | NÃO implementado | ❌ roadmap |

---

## 5. Sound System (`server/sound.lua` + `client/sound.lua` + `html/sound.js`)

### 5.1 Como sons são tocados

Caminho: NUI `soundPlay` → client → server → `vhub_wow:PlayAtEntity`.

```
Player clica "Play" no aside Som (sound.js)
  → fetch POST 'soundPlay' {url, volume}
  → RegisterNUICallback('soundPlay', client/sound.lua)
  → TriggerServerEvent('vhub_vehcontrol:soundPlay', VehToNet(v), pl, url, volume)
  → server/sound.lua valida: wowAvailable + hasVehicleAccess + shape
  → exports.vhub_wow:PlayAtEntity({src}, 'vc_radio_<src>', url, volume, netId, 10.0, true)
  → som 3D ancorado no veículo (outros players escutam via vhub_wow)
```

O `soundName` NUNCA vem do payload do cliente — derivado de `src`: `('vc_radio_%d'):format(src)` (anti-spoof — um player não pode parar/alterar o som de outro).

### 5.2 Catálogo de sons

3 fontes (segmented tabs no aside Som):

| Fonte | Fluxo | Provider |
|---|---|---|
| **Buscar** (default) | Input → `soundSearch` query → server rate-limit (1.5s/player) → `exports.vhub_wow:RequestSearch(src, query)` → Jamendo API → `vhub_wow:searchResults` event → NUI renderiza lista | vhub_wow/Jamendo |
| **Rádio** | `soundRadio` → server escolhe faixa aleatória (`GetRadioTrack`, síncrono, cache vhub_wow) → `PlayAtEntity` + `soundNow` event (title/artist) | vhub_wow (top-semana) |
| **Link** | `soundPlay` com URL direta (YouTube/SoundCloud/.mp3) → server valida URL string | vhub_wow |

### 5.3 Customização por veículo

**Não há catálogo de som por veículo.** O som é **ancorado no veículo** (`PlayAtEntity` com `netId, 10.0` range), mas o _conteúdo_ (URL/faixa) é escolhido pelo motorista. Não há persistência — ao sair do carro, o som para automaticamente (`LEFT_VEHICLE` event → `soundStop`).

Volume: slider 0..100 no NUI → `volume/100` (0.0..1.0) → server clampa `0..1`.

Rate-limit busca: `SEARCH_COOLDOWN = 1500` ms por player.

---

## 6. Item Handlers (`server/item_handlers.lua`)

### 6.1 Itens tratados

| Item ID | Comportamento | Integração |
|---|---|---|
| `veh_key` | Usar a chave → lê `meta.plate` do slot → `TriggerClientEvent('vhub_vehcontrol:open_from_key', src, plate)` → abre painel do vehcontrol | `vhub_inventory:getInventory(src).slots[slot].meta.plate` |
| `caixadeferramentas` | Usar a caixa → `TriggerClientEvent('vhub_vehcontrol:openEdit', src)` → abre painel **direto na aba Ficha em modo edição**. **NÃO consome o item** (`return false, nil`) — só abre a UI. Consumo real acontece no `RECALIBRATE` via `consumeItem` em `server/skill.lua`. | `vhub_inventory:registerItemUse` |

### 6.2 Integração com vhub_inventory

Ambos via `inv:registerItemUse(id, function(src, slot, id) ... end)` (soft-dep com `Wait(500)` p/ aguardar inventário pronto). O handler retorna `(bool, msg)`:
- `true, msg` = consumiu 1 unidade.
- `false, nil/msg` = NÃO consumiu (apenas abre UI/avisa).

**Crítico:** o handler da caixa de ferramentas **NÃO consome** ao abrir — autoridade real (chave/dono) é provada no `RECALIBRATE` via `canOperate` quando o player confirma. Padrão "L-04: sem 2ª verificação de proximidade".

---

## 7. Nitro Bridge (`server/nitro_bridge.lua`)

### 7.1 Como vehcontrol conversa com vhub_nitro

3 eventos net no vehcontrol, cada um chama 1 export do vhub_nitro via `pcall`:

| Evento (vehcontrol) | Export (vhub_nitro) | Payload |
|---|---|---|
| `vhub_vehcontrol:nitroToggle` | `setEnabled(src, plate, on)` | `(plate, on==true)` |
| `vhub_vehcontrol:nitroLevel` | `setLevel(src, plate, level)` | `(plate, level)` |
| `vhub_vehcontrol:nitroCharge` | `chargeFromItem(src, plate)` | `(plate)` |

Resposta: `TriggerClientEvent('vhub_vehcontrol:nitroDone', src, ok, msg, nitro_novo)` — `nitro_novo` vem de `exports.vhub_nitro:getNitro(plate)` (fonte única; UI nunca recacheia estado).

### 7.2 Contrato entre os dois

**Vehcontrol assume:**
- `vhub_nitro` valida `canOperate` (prova o player, não só o resource).
- `vhub_nitro` valida `kit` instalado (sem kit → `setEnabled`/`setLevel`/`chargeFromItem` retornam `false`).
- `vhub_nitro` clampa `level` 1..10.
- `vhub_nitro` faz rollback do item se `writeNitro` falhar (`chargeFromItem`).
- `vhub_nitro` tem rate-limit interno (350ms por src) anti-churn.

**Vehcontrol garante:**
- Placa normalizada antes de chamar (`normPlate`).
- Responde SEMPRE ao cliente (mesmo em erro de placa vazia).
- Não escreve `customization.nitro` direto (zero-trust entre resources).

### 7.3 Source of truth do estado do nitro

**`vhub_vehicle_state.customization.nitro = {kit, qty, enabled, level}`** — propriedade da PLACA.

- **Escritor único:** `vhub_nitro` via `exports.vhub_conce:saveVehicleState(plate, patch, 'nitro')`. Patch SEMPRE completo (mergeCust do conce é raso: `nitro` é REPLACE atômico).
- **Leitores:** `vhub_vehcontrol` (enxerta `sheet.nitro` em `sheetOf`), `vhub_nitro/client.lua` (ao virar motorista).
- **TRUSTED list:** `{vhub_custom, vhub_vehcontrol, vhub_nitro}` — só estes podem chamar exports sensíveis (cheque `GetInvokingResource()`).

---

## 8. `vhub_nitro` (standalone)

### 8.1 Configuração (`cfg/config.lua`)

```lua
NitroCfg = {
  item         = 'nitro',           -- id da Garrafa de Nitro (mochila)
  chargePerUse = 100,               -- 1 garrafa = 100% de carga

  durationSec   = 30,               -- duração de carga cheia (nível 1, base)
  topSpeedBoost = 1.0,              -- ModifyVehicleTopSpeed BASE (×powerMult do nível)
  torqueBoost   = 2.0,              -- SetVehicleCheatPowerIncrease BASE
  exhaustFire   = true,             -- ptfx no escapamento
  fireSize      = 2.0,

  -- trade-off durabilidade ↔ velocidade (10 níveis)
  LEVELS = {
    [1]  = { powerMult = 1.00, consumeMult = 0.50 },   -- durabilidade máxima
    [2]  = { powerMult = 1.11, consumeMult = 0.67 },
    [3]  = { powerMult = 1.22, consumeMult = 0.83 },
    [4]  = { powerMult = 1.33, consumeMult = 1.00 },
    [5]  = { powerMult = 1.44, consumeMult = 1.22 },
    [6]  = { powerMult = 1.56, consumeMult = 1.50 },
    [7]  = { powerMult = 1.67, consumeMult = 1.83 },
    [8]  = { powerMult = 1.78, consumeMult = 2.25 },
    [9]  = { powerMult = 1.89, consumeMult = 2.75 },
    [10] = { powerMult = 2.00, consumeMult = 3.50 },   -- velocidade máxima (dobro)
  },

  blacklist = { ['kuruma'] = true },    -- modelos que não aceitam nitro
}
```

`NITRO_KIT_PRICE` (R$5.000) mora em `vhub_custom/server/oficina.lua` — a oficina é quem vende o kit.

### 8.2 Como o nitro é ativado (`client.lua`)

Tecla: **SHIFT Direito** (`RegisterKeyMapping('+nitro', 'Veículo: ativar nitro', 'keyboard', 'RSHIFT')`).

Fluxo do boost:
```
+nitro command → _holding = true → startBoost()
  gates: _boosting==false, _kit, _enabled, _qty>0, motorista (seat -1), não blacklist
  CreateThread:
    boosted = veh, boostedPlate = _plate (fixados no início)
    ratePerSec = (100 / durationSec) × consumeMult do nível
    while _holding and _qty > 0:
      setBoost(boosted, true, lp.powerMult)         -- SetVehicleCheatPowerIncrease + ModifyVehicleTopSpeed
      _qty -= ratePerSec × dt
      a cada 5 ticks: exhaustFire(boosted)           -- ptfx 'veh_backfire' nos bones 'exhaust'..'exhaust_4'
      Wait(50)
    setBoost(boosted, false)                          -- sempre limpa o boost na entidade original
    TriggerServerEvent('vhub_nitro:drain', VehToNet(boosted), boostedPlate, math.floor(_qty))
```

**Crítico anti-leak:** `boosted` e `boostedPlate` são **fixados no início** do thread — se o player trocar de carro segurando o shift, o boost é limpo no carro ANTIGO (não fica turbinado para sempre).

### 8.3 Como é validado (`server.lua`)

3 exports de escrita + 1 export de leitura + 2 net events:

| Export/Event | Validação | Lógica |
|---|---|---|
| `exports('getNitro', plate)` | `normPlate` | `readNitro(plate)` (always retorna 4 campos) |
| `exports('installKit', src, plate)` | `TRUSTED[caller]` + `canOperate` + `cur.kit` idempotente | `writeNitro(p, true, cur.qty, cur.enabled, cur.level)` |
| `exports('setEnabled', src, plate, on)` | `TRUSTED` + `rateOK(src)` + `canOperate` + `cur.kit` | patch completo `{kit,qty,enabled:bool,level}` |
| `exports('setLevel', src, plate, level)` | `TRUSTED` + `rateOK` + `canOperate` + `cur.kit` | clamp `lvl10(level)` |
| `exports('chargeFromItem', src, plate)` | `TRUSTED` + `rateOK` + `canOperate` + `cur.kit` + `cur.qty<100` | `takeItem(nitro,1)` → se write falhar, `giveItem(nitro,1)` estorna |
| `RegisterNetEvent('vhub_nitro:request', plate)` | `normPlate` | `readNitro(p)` → `TriggerClientEvent('vhub_nitro:state', src, p, n)` |
| `RegisterNetEvent('vhub_nitro:drain', netId, plate, reportedQty)` | `resolveDriver(src, netId, plate)` (FAIL-CLOSED) + rate 700ms + `rq` número + **monotônico** | `writeNitro(p, kit, math.min(rq, cur.qty), enabled, level)` — só aceita valor MENOR que o atual (uso gasta; subir só pela garrafa) |

### 8.4 Persistência (Doutrina da Placa)

Estado mora em `vhub_vehicle_state.customization.nitro` — propriedade da PLACA (não do player, não do veículo em runtime). Patch SEMPRE completo:

```lua
local function writeNitro(plate, kit, qty, enabled, level)
  local patch = { customization = { nitro = {
    kit = kit == true, qty = q100(qty), enabled = enabled == true, level = lvl10(level),
  } } }
  return exports.vhub_conce:saveVehicleState(plate, patch, 'nitro') == true
end
```

`source = 'nitro'` no `saveVehicleState` para auditoria (separado de `'tune'` da oficina, `'handling'` do skill, `'telemetry'` do prontuário).

### 8.5 Integração com items

| Item | Origem | Handler | Efeito |
|---|---|---|---|
| `nitro` (Garrafa de Nitro) | `vhub_inventory` | `registerItemUse('nitro', ...)` em `vhub_nitro/server.lua` | **NÃO consome** — apenas notifica: "Abasteça o nitro pela ficha do veículo (aba Ficha → Nitro → Abastecer)." (decisão #30 — uso por proximidade aposentado) |
| `caixadeferramentas` | `vhub_inventory` | `registerItemUse('caixadeferramentas', ...)` em `vhub_vehcontrol/server/item_handlers.lua` | Abre painel direto na Ficha em modo edição. Consome 1 unidade ao confirmar RECALIBRATE. |
| `veh_key` | `vhub_inventory` | `registerItemUse('veh_key', ...)` em `vhub_vehcontrol/server/item_handlers.lua` | Abre painel do vehcontrol para a placa da chave. |

Kit de nitro (instalação na oficina) é via `exports.vhub_nitro:installKit(src, plate)` chamado pelo `vhub_custom` após cobrar R$5.000.

---

## 9. Exports (Server & Client)

### 9.1 `vhub_vehcontrol` exports

Todos em `server/exports.lua` — **read-only**, qualquer caller pode chamar:

| Export | Assinatura | Retorna |
|---|---|---|
| `getVehicleSheet` | `getVehicleSheet(plate)` | ficha FLAT completa (primitivos L-19) ou `nil` (sem p1) |
| `getVehicleTier` | `getVehicleTier(plate)` | `'D'..'S+'` ou `nil` |
| `getVehicleScore` | `getVehicleScore(plate)` | `0..1000` (int) ou `nil` |
| `getVehicleAffinity` | `getVehicleAffinity(plate)` | `{reta,curva,montanha,drift,cidade}` 0..1 ou `nil` |
| `getVehicleSheetPreview` | `getVehicleSheetPreview(plate, draftAlloc)` | ficha HIPOTÉTICA (nunca persiste; usa `draftAlloc` no lugar do salvo) ou `nil` |

Internos (não-exportados mas expostos via tabela `VHubVeh`):
- `VHubVeh.sheetOf(plate, dbgSrc, overrideAlloc)` — composição única reusada pelos exports.
- `VHubVeh.p1Byplate(plate)` — resolve `catalog.p1` da placa.
- `VHubVeh.hasVehicleAccess(src, plate)` — autoridade chave+dono (usado por `server/sound.lua`).
- `VHubVeh.TR` — a tabela do `tier_rules.lua` inteira (funções puras).

### 9.2 `vhub_nitro` exports

Em `server.lua`. **TRUSTED gate** (`GetInvokingResource()`) em todos os mutadores:

| Export | Assinatura | Gate | Retorna |
|---|---|---|---|
| `getNitro` | `getNitro(plate)` | nenhum (read-only) | `{kit,qty,enabled,level}` ou `nil` |
| `installKit` | `installKit(src, plate)` | TRUSTED + `canOperate` | `bool` (idempotente se já tem kit) |
| `setEnabled` | `setEnabled(src, plate, on)` | TRUSTED + rateOK + `canOperate` + `kit` | `bool` |
| `setLevel` | `setLevel(src, plate, level)` | TRUSTED + rateOK + `canOperate` + `kit` | `bool` (clamp 1..10) |
| `chargeFromItem` | `chargeFromItem(src, plate)` | TRUSTED + rateOK + `canOperate` + `kit` + `qty<100` | `bool` (estorna item se write falhar) |

`TRUSTED = { vhub_custom=true, vhub_vehcontrol=true, vhub_nitro=true }`.

---

## 10. Eventos (NetEvents, ClientEvents, NUI)

### 10.1 `vhub_vehcontrol` — NetEvents (c→s)

| Evento | Listener | Payload | Validação server |
|---|---|---|---|
| `vhub_vehcontrol:requestLock` | `server/main.lua` | `(netId:number, plate:string)` | `hasAccess(src, plate)` → `_lock[plate]` alternar → broadcast `applyLock` + `lockNotify` |
| `vhub_vehcontrol:requestEngine` | `server/main.lua` | `(netId:number, plate:string)` | `hasAccess(src, plate)` → `_engine[plate]` alternar → broadcast `applyEngine` |
| `vhub_vehcontrol:stateSync` | `server/main.lua` | `(netId:number, plate:string, snap:table)` | `resolveDriven(src, netId, plate)` (FAIL-CLOSED) + rate 14s/2s-final + `finiteNum` clamp + `odo_delta` não-negativo + `saveVehicleState(...,'telemetry')` |
| `vhub_vehcontrol:requestState` | `server/main.lua` | `(netId:number, plate:string)` | `resolveDriven` + rate 2s + `getVehicleState(p)` → `applyState` |
| `vhub_vehcontrol:reqSheet` (`E.REQ_SHEET`) | `server/exports.lua` | `(plate:string)` | normPlate + `sheetOf(p, src)` → `SHEET` reply |
| `vhub_vehcontrol:recalibrate` (`E.RECALIBRATE`) | `server/skill.lua` | `(plate:string, alloc:table, origin:'toolbox'\|'oficina')` | rate 5s + shape + `canOperate` + `p1Byplate` + `validateAlloc` + cobra porta + `saveVehicleState(...,'handling')` → `RECAL_DONE` |
| `vhub_vehcontrol:nitroToggle` (`E.NITRO_TOGGLE`) | `server/nitro_bridge.lua` | `(plate:string, on:bool)` | normPlate → `exports.vhub_nitro:setEnabled(src, p, on)` → `NITRO_DONE` |
| `vhub_vehcontrol:nitroLevel` (`E.NITRO_LEVEL`) | `server/nitro_bridge.lua` | `(plate:string, level:number)` | normPlate → `exports.vhub_nitro:setLevel(src, p, level)` → `NITRO_DONE` |
| `vhub_vehcontrol:nitroCharge` (`E.NITRO_CHARGE`) | `server/nitro_bridge.lua` | `(plate:string)` | normPlate → `exports.vhub_nitro:chargeFromItem(src, p)` → `NITRO_DONE` |
| `vhub_vehcontrol:soundPlay` | `server/sound.lua` | `(netId:number, plate:string, url:string, volume:number)` | `wowAvailable` + shape + `hasVehicleAccess` → `exports.vhub_wow:PlayAtEntity({src}, 'vc_radio_<src>', url, vol, netId, 10.0, true)` |
| `vhub_vehcontrol:soundStop` | `server/sound.lua` | `()` | `wowAvailable` → `exports.vhub_wow:Destroy({src}, 'vc_radio_<src>')` |
| `vhub_vehcontrol:soundVolume` | `server/sound.lua` | `(volume:number)` | `wowAvailable` → `exports.vhub_wow:SetVolume({src}, 'vc_radio_<src>', vol)` |
| `vhub_vehcontrol:soundSearch` | `server/sound.lua` | `(query:string)` | `wowAvailable` + 1≤len≤80 + rate 1.5s/player → `exports.vhub_wow:RequestSearch(src, query)` |
| `vhub_vehcontrol:soundRadio` | `server/sound.lua` | `(netId:number, plate:string, volume:number)` | `wowAvailable` + `hasVehicleAccess` → `GetRadioTrack()` → `PlayAtEntity` + `soundNow` event |

### 10.2 `vhub_vehcontrol` — ClientEvents (s→c)

| Evento | Emissor | Listener (client) | Payload | Efeito |
|---|---|---|---|---|
| `vhub_vehcontrol:applyLock` | `server/main.lua` broadcast `-1` | `client/main.lua` | `(netId, plate, state)` | `SetVehicleDoorsLocked` + sound (só se `plateOf(v)==pl`) |
| `vhub_vehcontrol:applyEngine` | `server/main.lua` broadcast `-1` | `client/main.lua` | `(netId, plate, on)` | `SetVehicleEngineOn` |
| `vhub_vehcontrol:lockNotify` | `server/main.lua` só p/ src | `client/main.lua` | `(state)` | `Config.notify` "trancado/destrancado" |
| `vhub_vehcontrol:applyState` | `server/main.lua` só p/ src | `client/main.lua` | `(plate, st:table)` | `SetVehicleFuelLevel`+Decor+`SetVehicleEngineHealth`+`SetVehicleBodyHealth`+damage (portas/janelas/pneus); `+0.0` força FLOAT subtipo |
| `vhub_vehcontrol:sheet` (`E.SHEET`) | `server/exports.lua` | `client/main.lua` + `client/handling.lua` | `(sheet:table)` | repassa à NUI `{type:'sheet', data:sheet}`; se dirigindo, aplica `sheet.hnd` |
| `vhub_vehcontrol:recalDone` (`E.RECAL_DONE`) | `server/skill.lua` | `client/main.lua` + `client/handling.lua` | `(ok:bool, msg:string, kind:string, sheet:table)` | `Config.notify(msg)` + NUI `{type:'recalDone'}`; se dirigindo, reaplica `sheet.hnd` |
| `vhub_vehcontrol:open_from_key` (`E.OPEN_FROM_KEY`) | `server/item_handlers.lua` | `client/main.lua` | `(plate:string)` | `openPanel()` |
| `vhub_vehcontrol:openEdit` (`E.OPEN_EDIT`) | `server/item_handlers.lua` | `client/main.lua` | `()` | `openPanel(true)` (modo edição) |
| `vhub_vehcontrol:nitroDone` (`E.NITRO_DONE`) | `server/nitro_bridge.lua` | `client/main.lua` | `(ok:bool, msg:string, nitro:table)` | notify + NUI `{type:'nitroDone', ok, nitro}` |
| `vhub_vehcontrol:soundRejected` | `server/sound.lua` | `client/sound.lua` | `()` | `_playing=false` + NUI `{type:'soundRejected'}` |
| `vhub_vehcontrol:soundNow` | `server/sound.lua` | `client/sound.lua` | `(title:string, artist:string)` | NUI `{type:'soundNow', title, artist}` |
| `vhub_wow:searchResults` | `vhub_wow` (externo) | `client/sound.lua` | `(query, items)` | NUI `{type:'soundResults', items}` |

### 10.3 Client-internal events (`client/main.lua` → `client/handling.lua`)

| Evento | Emissor | Listener | Payload |
|---|---|---|---|
| `vhub_vehcontrol:becameDriver` (`E.BECAME_DRIVER`) | `client/main.lua` thread motorista | `client/handling.lua` | `(veh, plate)` |
| `vhub_vehcontrol:leftVehicle` (`E.LEFT_VEHICLE`) | `client/main.lua` `finishDriving()` | `client/handling.lua` + `client/sound.lua` | `(veh)` — restaura handling base + para som |
| `vhub_vehcontrol:stateApplied` (LOCAL `TriggerEvent`) | `client/main.lua` `applyState` handler | HUDs externos (vhub_velo) | `(plate, st)` |

### 10.4 `vhub_nitro` — NetEvents

| Evento | Lado | Payload | Validação |
|---|---|---|---|
| `vhub_nitro:request` | c→s | `(plate:string)` | `normPlate` → `readNitro(p)` → `vhub_nitro:state` reply |
| `vhub_nitro:state` | s→c | `(plate:string, n:table)` | client checa `plate == _plate` antes de aplicar |
| `vhub_nitro:drain` | c→s | `(netId:number, plate:string, reportedQty:number)` | `resolveDriver` + rate 700ms + monotônico (`newQty < cur.qty`) |
| `vhub_nitro:notify` | s→c | `(msg:string)` | `notify(msg)` (usado p/ avisar que recarga é pela ficha) |

### 10.5 NUI Callbacks (`vhub_vehcontrol`)

| NUI Callback | Listener | Payload | Efeito |
|---|---|---|---|
| `exit` | `client/main.lua` | `{}` | `closePanel()` |
| `door` | `client/main.lua` | `{door:'lfdoor'\|...}` | `SetVehicleDoorOpen`/`Shut` (toggle local) |
| `window` | `client/main.lua` | `{window:'lfdoor'\|...}` | `RollDownWindow`/`RollUpWindow` (toggle local) |
| `light` | `client/main.lua` | `{}` | `SetVehicleInteriorlight` (toggle local) |
| `lights` | `client/main.lua` | `{}` | `SetVehicleLights(veh, 2\|0)` (toggle local) |
| `seat` | `client/main.lua` | `{}` | troca para próximo assento livre |
| `emergency` | `client/main.lua` | `{}` | `toggleHazard()` (pisca-alerta) |
| `lock` | `client/main.lua` | `{}` | `TriggerServerEvent('vhub_vehcontrol:requestLock', ...)` |
| `engine` | `client/main.lua` | `{}` | `TriggerServerEvent('vhub_vehcontrol:requestEngine', ...)` |
| `recalibrate` | `client/main.lua` | `{alloc:table}` | `TriggerServerEvent(E.RECALIBRATE, plate, alloc, 'toolbox')` |
| `nitroToggle` | `client/main.lua` | `{on:bool}` | `TriggerServerEvent(E.NITRO_TOGGLE, plate, on)` |
| `nitroLevel` | `client/main.lua` | `{level:number}` | `TriggerServerEvent(E.NITRO_LEVEL, plate, level)` |
| `nitroCharge` | `client/main.lua` | `{}` | `TriggerServerEvent(E.NITRO_CHARGE, plate)` |
| `soundPlay` | `client/sound.lua` | `{url:string, volume:number}` | server `soundPlay` |
| `soundStop` | `client/sound.lua` | `{}` | server `soundStop` |
| `soundVolume` | `client/sound.lua` | `{volume:number}` | server `soundVolume` |
| `soundSearch` | `client/sound.lua` | `{query:string}` | server `soundSearch` |
| `soundRadio` | `client/sound.lua` | `{volume:number}` | server `soundRadio` |

### 10.6 NUI Messages (Lua → JS)

Tipos disparados por `SendNUIMessage` em `client/main.lua`/`client/sound.lua`:

| `type` | Payload | Handler JS |
|---|---|---|
| `ui` | `{status:bool, windows:bool, editTab:bool}` | `showPanel(d.editTab)` / `hidePanel()` |
| `updateFuel` | `{fuel:number}` | `updateFuel(fuel)` |
| `emergency` | `{emergencystatus:bool}` | `setEmergency(on)` |
| `sheet` | `{data:sheet\|nil}` | `onSheet(data, false)` |
| `recalDone` | `{ok:bool, kind:string, data:sheet\|nil}` | `onRecalDone(ok, data)` |
| `nitroDone` | `{ok:bool, nitro:nitro\|nil}` | `onNitroDone(ok, nitro)` |
| `soundRejected` | `{}` | `onSoundRejected()` |
| `soundResults` | `{items:array}` | `onSoundResults(items)` |
| `soundNow` | `{title, artist}` | `onSoundNow(title, artist)` |

---

## 11. Callbacks

Não há `vhub_vehcontrol`/`vhub_nitro` Callbacks no sentido `RegisterServerCallback`/`vHub:serverCallback`. Toda comunicação cliente→servidor usa `TriggerServerEvent` + `RegisterNetEvent` de reply (padrão fire-and-reply, não callback registration).

A "callback" no sentido FiveM clássico só existe no nível NUI (`RegisterNUICallback`) — listados em §10.5.

---

## 12. NUI Bridge

### 12.1 Páginas HTML (`html/`)

| Arquivo | Papel |
|---|---|
| `html/index.html` | Documento único; 3 asides (Controles · Som · Ficha) dentro de `#vc-panel`. Carrega `core.js` → `controls.js` → `ficha.js` → `sound.js` |
| `html/core.js` | Núcleo: namespace `vhub`/`el`, `showPanel`/`hidePanel`, `switchTab`, `post()`, `attachDrag` (genérico por `[data-drag-root]`), `window.addEventListener('message', ...)` dispatcher |
| `html/controls.js` | Aside esquerda: `updateFuel`, `setEmergency`, `attachHandlers` (door/window/engine/lock/lights/light/seat) |
| `html/ficha.js` | Aside direita: `onSheet`, `renderFicha`, `enterEditMode`/`exitEditMode`, `onSliderDrag` (soma sempre == budget), `onRecalDone`, `attachNitro`, `renderNitro`, `onNitroDone` |
| `html/sound.js` | Aside topo-centro: 3 fontes (Rádio/Buscar/Link), `playTrack`, `playRadio`, `togglePlayUrl`, `onSoundResults`, `onSoundNow`, `onSoundRejected` |
| `html/style-core.css` | Tokens vHub (cores, glass, fontes, sombras, raios) + reset + `.vc-aside` base + responsivo 1280×720 |
| `html/style-controls.css` | Aside esquerda: `.vc-fuel`, `.vc-btn-grid`, `.vc-btn` (hover/active/toggle) |
| `html/style-ficha.css` | Aside direita: `.vc-ficha`, `.vc-tier-badge[data-tier]`, `.vc-bar-row`, `.vc-bar-slider`, `.vc-nitro-*` |
| `html/style-sound.css` | Aside topo-centro: `.vc-sound-meta`, `.vc-sound-viz` (10 barrinhas animadas), `.vc-sound-tab`, `.vc-sound-result` |

### 12.2 Mensagens trocadas com Lua

(Ver §10.5 — NUI Callbacks JS→Lua — e §10.6 — SendNUIMessage Lua→JS.)

Padrão arquitetural:
- **Lua é autoridade** — NUI é "relay puro" (manual §3.9). Nenhum cálculo de negócio no JS (ex.: o slider sempre soma `== budget` em `onSliderDrag`, mas o servidor RE-VALIDA em `validateAlloc` — defesa em profundidade).
- **Anti-XSS:** resultados de busca Jamendo inseridos via `textContent` (nunca `innerHTML`) — `renderResults` em `sound.js`.
- **Drag independente:** cada aside é arrastável separadamente (`[data-drag-root]` + `[data-drag-handle]` em `_wireDrag`); clampado no viewport.

---

## 13. Fluxos Principais (passo-a-passo com nomes reais)

### 13.1 Aplicar tier a um veículo (do spawn ao despawn)

```
SPAWN (vhub_garage spawna o veículo; dá a propriedade)
  ↓
Motorista entra (seat -1)
  ↓ client/main.lua thread (1s) detecta:
  vc_plate ~= pl → TriggerEvent(VHubVeh.E.BECAME_DRIVER, v, pl)
  ↓
client/handling.lua:AddEventHandler(E.BECAME_DRIVER)
  _drivenVeh = veh
  if Config.skillApplyHandling → TriggerServerEvent(E.REQ_SHEET, plate)
  ↓
server/exports.lua:RegisterNetEvent(E.REQ_SHEET)
  p = normPlate(plate)
  sheet = sheetOf(p, src)        -- p1 → budget → coerceAlloc(savedAlloc) → scoreFromAlloc → calcTier → clampTier → affinity → hnd → nitro
  TriggerClientEvent(E.SHEET, src, sheet)
  ↓
client/main.lua:RegisterNetEvent(E.SHEET)
  SendNUIMessage({type='sheet', data=sheet})     -- mostra na aba Ficha
  ↓
client/handling.lua:RegisterNetEvent(E.SHEET)
  if _drivenVeh ~= 0: applyHnd(_drivenVeh, sheet.hnd)
    ensureBase(veh, model)      -- cacheia .meta base
    for ax, m in pairs(bands): SetVehicleHandlingFloat(veh, 'CHandlingData', m.field, clamp(hnd[ax]))
    if ax == 'grip': SetVehicleHandlingFloat(..., 'fTractionCurveMin', v * 0.85)
  ↓
DESPAWN (motorista sai do banco)
  client/main.lua finishDriving()
    if vc_plate: sendSnapshot(v, vc_plate, true)         -- snapshot FINAL
    TriggerEvent(VHubVeh.E.LEFT_VEHICLE, vc_veh)
  ↓
client/handling.lua:AddEventHandler(E.LEFT_VEHICLE)
  restoreBase(_drivenVeh)        -- desfaz override model-wide (risco nº1 mitigado)
  _drivenVeh = 0
```

### 13.2 Modificar handling em runtime (ex.: turbo instalado)

```
Player compra turbo na OFICINA (vhub_custom)
  ↓ vhub_custom/server/oficina.lua instala peça:
  exports.vhub_conce:saveVehicleState(plate, {customization={mods={[18]=0}, turbo=true}}, 'tune')
  ↓
vhub_conce emite 'vHub:vehicleCommitted' (não escutado pelo vehcontrol atualmente — ver §16)
  ↓ (mas a FICHA é on-demand)
Player abre painel (segurar L ou usar chave)
  openPanel() → TriggerServerEvent(E.REQ_SHEET, plate)
  ↓
server/exports.lua sheetOf(plate):
  st = getVehicleState(plate)                 -- mods agora inclui turbo
  partsBonus = TR.partsBonus(cust.mods, cust.turbo)   -- turbo: 15 pontos (7 fixo + 8 livre)
  budget = TR.budgetOf(base, mods, turbo) = BUDGET[tier_base] + partsBonus.total
  ↓
TR.buildSheet(base, mods, turbo, savedAlloc):
  - se não tem alloc salvo → defaultAlloc (distribui o livre na ordem, respeitando ALLOC_RANGE)
  - se tem alloc salvo → coerceAlloc (read-side clamp p/ faixa vigente)
  - score = scoreFromAlloc(alloc, budget)    -- âncora + delta de distribuição
  - tier = clampTier(calcTier(score), base.tier_max)
  - hnd = handlingFromAlloc(alloc, budget, Config.skillHandling)  -- F5
  ↓
NUI mostra ficha atualizada (budget subiu 15, ranges ampliados)
  ↓
Player redistribui nos sliders → post('recalibrate', {alloc})
  ↓
server/skill.lua RECALIBRATE:
  rateOK + canOperate + p1Byplate + validateAlloc + consumeItem('caixadeferramentas') OR payMoney(2500)
  + saveVehicleState(p, {customization={handling=alloc}}, 'handling')
  → TriggerClientEvent(E.RECAL_DONE, src, ok, msg, kind, VHubVeh.sheetOf(plate))
  ↓
client/handling.lua RECAL_DONE:
  if ok and _drivenVeh ~= 0: applyHnd(_drivenVeh, sheet.hnd)  -- física re-aplicada
```

### 13.3 Ativar nitro (do keypress ao efeito)

```
Player vira motorista → client.lua thread 1Hz detecta placa nova
  TriggerServerEvent('vhub_nitro:request', pl)
  ↓
server.lua 'vhub_nitro:request': TriggerClientEvent('vhub_nitro:state', src, p, readNitro(p))
  ↓
client.lua 'vhub_nitro:state': _kit, _enabled, _level, _qty atualizados (só se plate==_plate)
  ↓
Player SEGURA RSHIFT
  RegisterCommand('+nitro'): _holding=true; startBoost()
  ↓
startBoost():
  gates: _boosting==false, _kit, _enabled, _qty>0, motorista, não blacklist
  boosted, boostedPlate = veh, _plate   (fixados)
  CreateThread:
    while _holding and _qty>0:
      setBoost(boosted, true, lp.powerMult):
        SetVehicleCheatPowerIncrease(veh, (torqueBoost * powerMult) + 0.00001)
        ModifyVehicleTopSpeed(veh, (topSpeedBoost * powerMult) + 0.00001)
      _qty -= (100/durationSec * consumeMult) * dt
      a cada 5 ticks: exhaustFire(boosted) — ptfx 'veh_backfire' em 'exhaust'..'exhaust_4'
      Wait(50)
    setBoost(boosted, false)              -- sempre limpa
    TriggerServerEvent('vhub_nitro:drain', VehToNet(boosted), boostedPlate, math.floor(_qty))
  ↓
server.lua 'vhub_nitro:drain':
  resolveDriver (FAIL-CLOSED) + rate 700ms + monotônico (newQty < cur.qty)
  writeNitro(p, cur.kit, newQty, cur.enabled, cur.level)
  ↓
Player SOLTA RSHIFT
  RegisterCommand('-nitro'): _holding=false
  → thread sai do while, limpa boost, persiste o gasto (já feito acima)
```

### 13.4 Usar item que afeta veículo (ex.: caixa de ferramentas)

```
Player usa 'caixadeferramentas' (mochila)
  ↓ vhub_inventory dispara handler registrado:
  server/item_handlers.lua: inv:registerItemUse('caixadeferramentas', function(src)
    TriggerClientEvent(VHubVeh.E.OPEN_EDIT, src)
    return false, nil       -- NÃO consome
  end)
  ↓
client/main.lua OPEN_EDIT:
  if controlledVehicle() == 0: notify('Nenhum veículo próximo.') return
  openPanel(true)           -- editTab=true
  ↓
openPanel(true):
  SendNUIMessage({type='ui', status=true, editTab=true})
  vhub._pendingAutoEdit = true (em showPanel)
  ↓
core.js showPanel(editTab=true): switchTab('ficha'); vhub._pendingAutoEdit = true
  ↓
ficha.js onSheet(s): 
  if vhub._pendingAutoEdit and s.tier: vhub._pendingAutoEdit=false; enterEditMode()
  → sliders aparecem; Player redistribui
  ↓
Player clica "Salvar calibração":
  post('recalibrate', {alloc: draftAlloc})
  → TriggerServerEvent(E.RECALIBRATE, plate, alloc, 'toolbox')
  ↓
server/skill.lua RECALIBRATE:
  ... validateAlloc ... consumeItem(src, 'caixadeferramentas')   -- AQUI consome 1 unidade
  saveVehicleState(...,'handling')
  → RECAL_DONE (ok, msg, kind='success', ficha nova)
  ↓
client: Config.notify('Veículo recalibrado!') + NUI recalDone → onRecalDone → onSheet(sheet, true) → renderFicha (sai do modo edição)
```

### 13.5 Subir de nível no skill

**Não há "subir de nível" no skill** (skill é alloc, não XP). O equivalente é **"aumentar o score trocando o alloc"**:

```
Player abre ficha em edição
  → distribui mais pontos em 'potencia' (peso 0.35) e 'grip' (peso 0.30)
  → onSliderDrag: tira dos outros eixos, soma sempre == budget
  → salva → recalDone → ficha nova
  ↓
sheetOf recalcula:
  score = scoreFromAlloc(alloc, budget)
       = budgetToScore(budget) + (weighted - uniforme) * 750
       = anchor + delta
  Se weighted > 0.20 (foco em eixos de alto peso): delta positivo → score sobe
  → se score cruza faixa TIER_SCORE: tier exibido muda (clampado a tier_max)
```

Subir de tier por redistribuição é possível, mas clampado ao `tier_max` do catálogo (anti-salto).

### 13.6 Tocar som customizado para um veículo

```
Player dirige o veículo (radio só funciona dentro do carro)
  abre painel → aside Som → aba "Buscar"
  digita "AC/DC Thunderstruck" (input event com debounce 450ms)
  ↓
sound.js doSearch(): post('soundSearch', {query: q})
  ↓
client/sound.lua 'soundSearch' → TriggerServerEvent('vhub_vehcontrol:soundSearch', q)
  ↓
server/sound.lua:
  wowAvailable + 1≤len≤80 + rate 1.5s/player
  exports.vhub_wow:RequestSearch(src, query)   -- Jamendo API
  ↓
vhub_wow responde: TriggerClientEvent('vhub_wow:searchResults', src, query, items)
  ↓
client/sound.lua: SendNUIMessage({type:'soundResults', items})
  ↓
sound.js onSoundResults: renderResults(items) — lista clicável
  ↓
Player clica numa faixa: playTrack(it, li)
  setTrackMeta(it.title, it.artist)
  post('soundPlay', {url: it.url, volume: _sound.volume/100})
  setPlaying(true)
  ↓
client/sound.lua 'soundPlay':
  v = drivingVehicle(); pl = plateOf(v)
  TriggerServerEvent('vhub_vehcontrol:soundPlay', VehToNet(v), pl, url, vol)
  ↓
server/sound.lua:
  wowAvailable + shape + hasVehicleAccess(src, pl)
  soundName = 'vc_radio_'..src       -- derivado de src, não do payload
  exports.vhub_wow:PlayAtEntity({src}, soundName, url, vol, netId, 10.0, true)
  ↓
Som 3D ancorado no veículo — outros players escutam (vhub_wow cuida da propagação)
  ↓
Player sai do carro → LEFT_VEHICLE event:
  client/sound.lua: TriggerServerEvent('vhub_vehcontrol:soundStop')
  server: exports.vhub_wow:Destroy({src}, soundName)
```

---

## 14. Integração com CORE/vhub

### 14.1 Exports do CORE (`vhub`) chamados

| Export | Quem chama | Uso |
|---|---|---|
| `exports.vhub:getUser(src)` | `server/main.lua::hasAccess` | Caminho "dono do veículo": `user.char_id` compara com `veh.char_id` (via `vhub_garage:getVehicle`) |

> Observação: `exports.vhub:getVehicleState` (homônimo do conce) é **inerte** no CORE FROZEN (P-3 do carskill.md). O vehcontrol usa `exports.vhub_conce:getVehicleState` (prontuário).

### 14.2 Exports de outros resources chamados

| Resource | Export | Quem chama |
|---|---|---|
| `vhub_conce` | `getCatalog()` | `server/exports.lua::buildIndex` |
| `vhub_conce` | `getVehicle(plate)` | `server/exports.lua::sheetOf`/`p1ByPlate` |
| `vhub_conce` | `getVehicleState(plate)` | `server/exports.lua`, `server/skill.lua`, `vhub_nitro/server.lua::readNitro` |
| `vhub_conce` | `saveVehicleState(plate, patch, source)` | `server/main.lua` ('telemetry'), `server/skill.lua` ('handling'), `vhub_nitro/server.lua::writeNitro` ('nitro') |
| `vhub_conce` | `canOperate(src, plate)` | `server/skill.lua`, `vhub_nitro/server.lua` |
| `vhub_inventory` | `hasVehicleKey(src, plate)` | `server/main.lua::hasAccess` |
| `vhub_inventory` | `hasItem(src, id, qty)` | `server/skill.lua::consumeItem` |
| `vhub_inventory` | `takeItem(src, id, qty)` | `server/skill.lua::consumeItem`, `vhub_nitro/server.lua::chargeFromItem` |
| `vhub_inventory` | `giveItem(src, id, qty)` | `vhub_nitro/server.lua::chargeFromItem` (estorno) |
| `vhub_inventory` | `getInventory(src)` | `server/item_handlers.lua` (veh_key) |
| `vhub_inventory` | `registerItemUse(id, fn)` | `server/item_handlers.lua`, `vhub_nitro/server.lua` |
| `vhub_garage` | `getVehicle(plate)` | `server/main.lua::hasAccess` (caminho dono) |
| `vhub_money` | `tryFullPayment(src, amount)` | `server/skill.lua::payMoney` |
| `vhub_wow` | `PlayAtEntity`, `Destroy`, `SetVolume`, `RequestSearch`, `GetRadioTrack` | `server/sound.lua` |
| `vhub_nitro` | `getNitro`, `setEnabled`, `setLevel`, `chargeFromItem`, `installKit` | `server/exports.lua` (getNitro p/ ficha), `server/nitro_bridge.lua` (escrita) |

### 14.3 State Bags lidas/escritas

| State Bag | Lado | Quem escreve | Quem lê |
|---|---|---|---|
| `LocalPlayer.state.vhub_seatbelt` | client | `client/main.lua::setSeatbelt` (`set('vhub_seatbelt', bool, false)` — **false = local**, não replicado) | HUDs externos (vhub_velo, vhub_seatbelt) |
| `Entity(veh).state.vh_fuel` | server (CORE) | CORE | `client/main.lua` dashboard thread (`Entity(veh).state.vh_fuel`) — fallback p/ `GetVehicleFuelLevel` |

> **State Bags do skill não implementadas** (`vhub_p1`, `vhub_p1_hnd` da spec carskill.md §5.2). O vehcontrol usa `REQ_SHEET`/`SHEET` events e `RECAL_DONE` em vez de StateBags — divergência arquitetural da spec (ver §16).

---

## 15. Configuração

### 15.1 `vhub_vehcontrol/shared/config.lua`

```lua
Config = {}

Config.keys = {
  lock        = 'L',         -- TOQUE trava/destranca | SEGURAR abre painel
  signalLeft  = 'LEFT',      -- seta esq
  signalRight = 'RIGHT',     -- seta dir
  windowUp    = 'UP',
  windowDown  = 'DOWN',
}
Config.command      = 'vehcontrol'   -- comando chat p/ abrir painel ('' = desliga)
Config.skillDebug   = true           -- DEBUG: diagnostica ficha no chat (DESLIGAR em prod)
Config.holdToOpenMs = 1000           -- tempo segurando L p/ abrir painel
Config.distance     = 2.0            -- distância (m) p/ controlar veículo próximo a pé
Config.viewWindows  = true           -- exibe botões de janela na NUI
Config.indicator    = { left = 1, right = 0 }   -- índice do pisca por lado
Config.requireKey   = true           -- trava/motor exigem chave ou dono
Config.doorIndex    = { lfdoor=0, rfdoor=1, lrdoor=2, rrdoor=3, hood=4, trunk=5 }
Config.windowIndex  = { lfdoor=0, rfdoor=1, lrdoor=2, rrdoor=3 }

-- ENGINE DE SKILL (F5, decisão #28)
Config.skillApplyHandling = true    -- liga a física derivada (false = só números, .meta intacto)
Config.skillBruteTest     = true    -- TESTE: libera alloc 0..100% por eixo. Produção = false
Config.skillGripMinRatio  = 0.85    -- fTractionCurveMin = grip * isto

Config.skillHandling = {
  potencia  = { field = 'fInitialDriveForce', min = 0.14, max = 0.46 },
  grip      = { field = 'fTractionCurveMax',  min = 1.55, max = 2.95 },
  frenagem  = { field = 'fBrakeForce',        min = 0.55, max = 1.65 },
  aero      = { field = 'fInitialDragCoeff',  min = 6.0,  max = 18.0 },
  suspensao = { field = 'fAntiRollBarForce',  min = 0.05, max = 1.50 },
}

-- function Config.notify(msg): feed nativo do GTA
```

**Atenção:** `Config.skillDebug = true` e `Config.skillBruteTest = true` estão **LIGADOS em produção** — ambos deveriam estar `false` (ver carskill_testplan.md §0 e §8).

### 15.2 `vhub_vehcontrol/server/skill.lua` (constantes)

```lua
local TOOLBOX_ITEM   = 'caixadeferramentas'   -- item consumido na porta toolbox
local OFICINA_PRICE  = 2500                    -- R$ cobrados na porta oficina
local RATE_WINDOW_MS = 5000                    -- anti-spam de recalibração
```

### 15.3 `vhub_vehcontrol/server/sound.lua` (constantes)

```lua
local SEARCH_COOLDOWN = 1500   -- 1 busca por jogador a cada 1.5s
```

### 15.4 `vhub_vehcontrol/server/main.lua` (constantes)

```lua
local SYNC_MIN_MS  = 14000   -- gate temporal: snapshot periódico ≥14s (L-18)
local FINAL_MIN_MS = 2000    -- snapshot final (sair do banco) ≥2s
-- CLASS_DRAIN (multiplicador de drenagem de combustível por classe GTA)
local CLASS_DRAIN = { [13]=0.0, [14]=0.0, [15]=0.0, [16]=0.0, [17]=0.3, [18]=0.3, [21]=0.0 }
-- WINDOW_BONES (índice → bone name para IsVehicleWindowIntact/SmashVehicleWindow)
-- SNAP_MS = 15000 (cadência do snapshot periódico no client)
```

### 15.5 `vhub_nitro/cfg/config.lua`

(Ver §8.1 — tabela completa.)
Defaults: `durationSec=30`, `topSpeedBoost=1.0`, `torqueBoost=2.0`, `chargePerUse=100`, `fireSize=2.0`, `exhaustFire=true`, `blacklist={kuruma=true}`.

### 15.6 `vhub_nitro/server.lua` (constantes)

```lua
local ITEM   = NitroCfg.item or 'nitro'
local CHARGE = NitroCfg.chargePerUse or 100
local _opAt  = {}              -- [src] = lastMs (rate-limit 350ms compartilhado)
local _drainAt = {}            -- [src] = lastMs (rate-limit 700ms para drain)
local TRUSTED = { ['vhub_custom']=true, ['vhub_vehcontrol']=true, ['vhub_nitro']=true }
```

---

## 16. Pontos de Atenção

### 16.1 Possíveis duplicações entre `vhub_nitro` e `nitro_bridge`

**NÃO há duplicação de lógica.** O `nitro_bridge.lua` é **ponte pura** (call + reply, sem lógica de negócio). Toda autoridade (canOperate, kit gate, clamp, rate-limit, estorno) vive em `vhub_nitro`. O vehcontrol só normaliza placa e repassa.

**Verificado por leitura:**
- `nitro_bridge.lua` chama apenas `setEnabled`/`setLevel`/`chargeFromItem`/`getNitro`.
- `vhub_nitro` re-prova `canOperate(src, plate)` em todos os exports de escrita.
- Zero re-cálculo de clamp `1..10` no bridge.
- Zero leitura/escrita direta de `customization.nitro` no vehcontrol.

### 16.2 Possíveis violações do `manual_dev_vhub.md`

| Lei | Verificação | Status |
|---|---|---|
| **L-01** (server-authoritative em decisões críticas) | trava/motor/recalibração/nitro-kits todos validados server-side | ✅ |
| **L-04** (um dono por dado) | `customization.handling` (writer=vhub_conce, caller=vehcontrol/skill); `customization.nitro` (writer=vhub_nitro); `customization.mods`/`turbo` (writer=vhub_custom) — chaves disjuntas no mesmo JSON | ✅ |
| **L-06** (evento antes de polling) | skill usa `REQ_SHEET` event-driven; nitro usa `request` ao virar motorista (1Hz thread, mas só dispara quando muda placa); handling aplica por evento `BECAME_DRIVER`/`SHEET`/`RECAL_DONE` | ✅ |
| **L-09** (1 responsabilidade por arquivo) | cada arquivo server tem papel único: `main`(controle+telemetria), `skill`(recalibração), `nitro_bridge`(delega), `sound`(wow), `item_handlers`(inventory hooks), `exports`(API read-only) | ✅ |
| **L-13** (`setVData` fora do core) | vehcontrol/nitro usam `exports.vhub_conce:saveVehicleState` (contrato) — não chamam `setVData` | ✅ |
| **L-15** (todo .lua no manifest) | todos os 7 server + 3 client + 3 shared + 9 html arquivos estão no `fxmanifest.lua` | ✅ |
| **L-17** (replay-guard em handlers institucionais) | vehcontrol/nitro não escutam `vHub:playerSpawn`/`characterLoad` — não precisam de replay-guard | ✅ (n/a) |
| **L-18** (orçamentos = contrato) | `SYNC_MIN_MS=14s`, `FINAL_MIN_MS=2s`, `RATE_WINDOW_MS=5s`, `SEARCH_COOLDOWN=1.5s`, nitro `_opAt=350ms`/`_drainAt=700ms` — todos declarados como constantes | ✅ |
| **L-19** (vetor é local; primitivo em fronteira) | `sheet` é FLAT de primitivos (number, string, bool, tables de primitivos) — pronto p/ msgpack | ✅ |
| §3.7 `_invoker_allowed` em exports sensíveis | `vhub_nitro` usa `TRUSTED[GetInvokingResource()]` (equivalente funcional) | ✅ |
| §4.6 rate declarado em `CFG.rates` | ⚠️ rates estão em constantes locais (`RATE_WINDOW_MS`, `SEARCH_COOLDOWN`, `_opAt`), **não** em `Config.rates` centralizado | ⚠️ divergência menor |
| §6.6 validação shape/range antes do domínio | todos os handlers validam `type()` + clamp antes do domínio | ✅ |
| Antipadrão `print()` solto | ⚠️ `Config.skillDebug` usa `TriggerClientEvent('chat:addMessage', ...)` p/ debug — não é `print`, mas é "poluição" em produção (`Config.skillDebug=true`) | ⚠️ |

### 16.3 Possíveis problemas de sync entre client/server

| Problema | Onde | Impacto | Status |
|---|---|---|---|
| **Risco nº1 (model-wide SetVehicleHandlingFloat)** | `client/handling.lua::applyHnd` | Dois players no mesmo modelo com builds diferentes podem sentir o mesmo handling (não o próprio) | ⚠️ Mitigado por `ensureBase`/`restoreBase`, **prova em jogo pendente** (carskill_testplan §6c) |
| **StateBag `vh_fuel` legada do CORE** | `client/main.lua` dashboard thread | Se o CORE não escrever `vh_fuel`, cai no fallback `GetVehicleFuelLevel(veh)` — funciona, mas pode divergir do servidor | ⚠️ aceitável |
| **`getVehicleState` do CORE inerte** | — | vehcontrol chama `vhub_conce:getVehicleState` (correto). Se um dev desavisitado trocar p/ `vhub:getVehicleState`, o skill quebra silenciosamente | ⚠️ risco educacional |
| **`vHub:vehicleCommitted` NÃO escutado** | spec carskill §5.2 prevê reagir a commits; vehcontrol só lê em `REQ_SHEET` on-demand | Se o player comprar peça e NÃO reabrir a ficha, o `hnd` aplicado no carro dirigido fica STALE até próximo `RECAL_DONE` | ⚠️ divergência da spec; mitigar escutando `vehicleCommitted` e reemitindo `SHEET` |
| **`Config.skillDebug = true` em produção** | `shared/config.lua` | Polui chat do jogador com `placa=X model=Y p1=SIM/NAO` a cada `REQ_SHEET` | ⚠️ deve ser `false` |
| **`Config.skillBruteTest = true` em produção** | `shared/config.lua` | Libera alloc 0..100% por eixo (anti-P2W desligado) — jogador pode empilhar tudo num eixo. `coerceAlloc` na leitura puxa de volta, mas um alloc extremo salvo em teste será renormalizado em produção (perde a build) | ⚠️ deve ser `false` |
| **R-3 (ordem cobrança→persistência)** | `server/skill.lua` RECALIBRATE | Cobra o item/dinheiro **ANTES** de persistir (passo 5 antes do passo 6). Se `saveVehicleState` falhar (raro — placa fora do registro), o jogador perde a porta sem recalibrar | ⚠️ dívida conhecida (carskill_testplan §7); pendente transação com rollback |
| **`vehcontrol:soundRadio` chama `GetRadioTrack` síncrono** | `server/sound.lua` | Se cache do vhub_wow estiver frio, retorna `nil` → `rejectSound`. Player precisa clicar de novo | ✅ aceitável (defensivo) |
| **Thread 1Hz do nitro client** | `client.lua` detecção de motorista | Roda a 1Hz sempre (mesmo a pé) — leve, mas poderia ser ligada só quando `IsPedInAnyVehicle` | ✅ dentro do orçamento |
| **`vhub_wow:searchResults` é broadcast?** | `client/sound.lua` | Se vhub_wow emitir p/ `-1`, todos recebem a lista de busca. O handler em `client/sound.lua` NÃO filtra por `src` — possivelmente todos os clients renderizam resultados de busca de outros players | ⚠️ verificar no `vhub_wow` |
| **`vhub_vehcontrol:applyLock`/`applyEngine` broadcast `-1`** | `server/main.lua` | Em vez de StateBag, usa broadcast p/ todos. Justificável (evento discreto/momentâneo), mas diverge de §4.2 "estado de entidade p/ todos = State Bag" | ⚠️ divergência menor (lock/engine são transitórios) |
| **Drenagem de combustível só no motorista local** | `client/main.lua` thread fuel | Se dois players no mesmo veículo (passageiro não drena), OK. Mas o `SetVehicleFuelLevel` local só atualiza a entidade do motorista — passageiros veem o fuel via `vh_fuel` StateBag do CORE | ✅ depende do CORE |
| **Persistência do alloc só por RECALIBRATE** | spec previa `vehicleCommitted` trigger; impl atual é on-demand | Se o player comprar peça e NÃO abrir a ficha, `customization.handling` salvo pode estar desatualizado vs novo `budget` — `coerceAlloc` na leitura compensa, mas o alloc "ótimo" muda | ✅ mitigado por `coerceAlloc` |
| **`registerItemUse('nitro', ...)` retorna `false`** | `vhub_nitro/server.lua` | Item "morto" — não consome, só avisa. Player pode achar que é bug ("cliquei e não aconteceu nada"). Decisão #30 explícita, mas UX pode confundir | ✅ aceitável (instrução clara no notify) |

### 16.4 Outras observações

- **`fx_version 'cerulean'`** em ambos — compatível com artifacts recentes.
- **`lua54 'yes'`** em ambos — usa Lua 5.4 (operador `//` integer division disponível, mas não utilizado).
- **`+ 0.0` trick** em `client/main.lua::applyState` — força subtipo FLOAT em números vindos do msgpack (1000 → 1.4e-42 sem o trick). Crítico p/ `SetVehicleFuelLevel`/`SetVehicleEngineHealth`.
- **`Config.notify`** usa feed nativo do GTA — não há sistema de notificação vHub centralizado; cada resource tem o seu.
- **NUI foco:** `SetNuiFocus(b, b)` + `SetNuiFocusKeepInput(b)` — permite input do jogo enquanto painel aberto (configurar a tecla L segurada).
- **Drag de painel:** cada aside é independente (`_wireDrag`), clampado no viewport — bom padrão.
- **Anti-XSS:** `textContent` em todos os inserts de dados externos (Jamendo) — bom padrão.
- **Teclas rebindáveis:** todas via `RegisterKeyMapping` (L, LEFT, RIGHT, UP, DOWN, G, RSHIFT) — configurable em Configurações > Atribuição de teclas.

---

## 17. Conclusão

O `vhub_vehcontrol` é o **centro único do veículo** (decisão #27): controla portas/motor/luzes, deriva tier/score/afinidade da placa, recalcibra o alloc (skill), faz ponte para nitro/som, e coleta telemetria física do motorista (sprint PRONTUÁRIO). Modular, server-authoritative, sem 2ª fonte de verdade (L-04 respeitado).

O `vhub_nitro` é o **escritor único do estado do nitro na placa** (decisão #30): server-authoritative, com exports TRUSTED-gated, rate-limit, rollback de item em caso de falha de persistência, e monotonicidade no drain (uso só gasta; subir só pela garrafa). A FICHA do vehcontrol só exibe e delega — zero competição.

**Pontos a corrigir antes de produção:**
1. `Config.skillDebug = false` (debug polui chat).
2. `Config.skillBruteTest = false` (anti-P2W desligado em produção).
3. Validar risco nº1 (model-wide `SetVehicleHandlingFloat`) — 2 players, mesmo modelo, builds diferentes.
4. Considerar escutar `vHub:vehicleCommitted` para reemitir `SHEET` quando o player comprar peça sem reabrir a ficha (mitiga stale `hnd`).
5. Avaliar R-3 (ordem cobrança→persistência) com `vhub_guardiao_seguranca` para transação com rollback.

**Aderência ao manual_dev_vhub:** ✅ alta. L-01/04/06/09/13/15/18/19 todas respeitadas. Apenas divergências menores (rates em constantes locais vs `Config.rates` centralizado; broadcasts `applyLock`/`applyEngine` em vez de StateBag — justificável por serem transitórios).

**Aderência ao carskill.md spec:** parcial. A **Fase 2 runtime** foi implementada de forma **diferente da spec**:
- Sem StateBags `vhub_p1`/`vhub_p1_hnd` (usa events `REQ_SHEET`/`SHEET`/`RECAL_DONE`).
- Sem tabela `vhub_p1skill_telemetry` (append-only de corrida).
- Sem HUD client separado (a NUI do painel da chave cumpre o papel).
- Sem `normalizeVsNative` no score (usa `budgetToScore` âncora + delta de distribuição).

Essas divergências são **conscientes** (banner do carskill.md §0 "ESTADO REAL DA IMPLEMENTAÇÃO" declara isso) — o plano canônico (`PLANO.md`) consolidou o skill no vehcontrol em vez de um resource `vhub_p1skill` separado.
