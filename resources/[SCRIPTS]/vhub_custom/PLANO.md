# vhub_custom — Plano de Ação (oficina mecânica / estética / reparo)

**Versão:** 1.0.0 · **Status:** Plano aprovado pela arquitetura (decisão #26 candidata) · **Modelo:** Opus 4.8
**Escopo:** `resources/[SCRIPTS]/vhub_custom` = UM resource, três domínios — `bennys` (estética), `mec` (reparo + reboque), `oficina` (performance/tuning).
**Premissa-mestra:** *peça ao dono, nunca escreva no que não é seu.* O `vhub_custom` é **CONSUMIDOR** do PRONTUÁRIO (`vhub_vehicle_state`, dono = `vhub_conce`). Ele **não ganha ownership de nenhum dado existente**.

> ⚠️ **CORREÇÃO HONESTA AO PEDIDO INICIAL:** a expectativa de "adicionar mais tabelas/colunas ao `vhub_vehicle_state`" foi **REPROVADA para esta sprint** (ver §4). O tuning de stage nativo (motor/freio/câmbio/suspensão/turbo) **já cabe** em `customization.mods` (whitelist `CUST_KEYS` no `vstate.lua`). Criar coluna de "alocação"/"score" agora cria **2ª fonte de verdade (L-04)**, pois o `carskill`/`vhub_p1skill` (F2) declara-se **derivador** de `customization.mods`. Coluna nova de _handling override_ só entra **na F2**, sob dono do `vstate.lua` (gate de conce). Detalhe e alternativa em §4 e §10.

---

## 0. O que aprendemos dos exemplos (e por que rejeitamos o padrão deles)

Estudados: `nation_bennys` (mod menu completo cosmético+performance), `vrp_vehCustom` (idem + engine/brakes/transmission/suspension/shield/turbo), `vrp_vehColor` (pintura).

| Padrão vRP dos exemplos | Por que **não** seguimos | O que fazemos no vHub |
|---|---|---|
| Cliente decide os mods e o servidor só cobra (`tryFullPayment`) e salva um blob por dono (`setSData("custom:u"..uid.."veh_"..nome)`) | Cliente-autoritativo (viola L-01/L-02); 2ª fonte de verdade por dono em vez de placa (L-04) | Cliente só **previsualiza** (efêmero); servidor **valida `canOperate` + cobra + persiste** no PRONTUÁRIO por **placa** |
| `while true do ... DrawMarker` sempre ativo (nation_bennys) | Frame loop quente sempre ligado (L-06/L-18) | Zonas fria (1 Hz) + quente (só perto) — §7 |
| Salva por `vehName` (display name) + owner id | Colisão entre 2 carros do mesmo modelo do mesmo dono; chave instável | Chave canônica = **placa** (já normalizada pelo `vstate`) |
| `SetVehicleHandlingFloat` aplicado por cliente sem autoridade (nation tunnerchip) | Override de física sem validação server-auth; model-wide vs instância (risco nº1 carskill §5.2.1) | **F2 apenas**, server-authoritative via StateBag, clampado ao tier (carskill §5.2.1) |
| Camera/preview por `CreateCam`+`PointCamAtBone` | (bom) — reaproveitável | Adaptamos como **L2/HAL client**, native-first |

**Conclusão:** os exemplos servem de **referência de UX e de natives** (lista de mods, câmera, fumaça, neon, cores) — **nunca** de arquitetura de persistência/autoridade.

---

## 1. Veredito de arquitetura (resumo — detalhe nos §)

| Item | Veredito | Lei | Onde |
|---|---|---|---|
| **A. Topologia** | **1 resource**, 3 sub-pastas `bennys/mec/oficina`, 1 `fxmanifest` | L-07, L-09, L-15 | §2 |
| **B. Persistência tuning** | Stages nativos em `customization.mods` AGORA; alloc/score/handling = **derivado** pelo `vhub_p1skill` (F2), **sem coluna nova** | L-04, L-13 | §4 |
| **C. Quem persiste** | `vhub_custom` chama `exports.vhub_conce:saveVehicleState` **direto**; entra no `TRUSTED`; `source='cosmetic'` (bennys) / `'tune'` (oficina) | L-04, L-13, L-14 | §5 |
| **D. mec vs garage** | mec **DELEGA** o ato de reparo (não duplica fórmula); reboque = **domínio novo** no mec | L-15, L-16 | §6 |
| **E. Sync carskill F2** | Evento `vHub:vehicleCommitted` emitido pelo **VState do conce** (escritor único), não pela oficina; `validateAlloc` com degradação graciosa | L-04, L-17, L-19 | §10 |

---

## 2. Topologia do resource (camadas e arquivos)

UM `fxmanifest`. Camadas explícitas: **L1 = server-authoritative**, **L2 = HAL client (natives de entidade)**, **L3/L4 = NUI** (runtime + componentes, fase posterior).

```
resources/[SCRIPTS]/vhub_custom/
├── fxmanifest.lua
├── shared/
│   ├── config.lua        ← VHubCustom.cfg (zonas, preços, rates, MOD_SPLIT cosmético×performance)
│   ├── events.lua        ← VHubCustom.E.* (global, sem return — anti-fantasma)
│   └── utils.lua         ← helpers puros (split de payload, normalização)
├── server/
│   ├── core.lua          ← sessões, rate O(1), Core.pay (wrap vhub_money), Core.canOperate (cache + invalidação)
│   ├── init.lua          ← schema próprio (se houver) + replay-guard + boot
│   ├── bennys.lua        ← L1: valida+cobra+persiste customization COSMÉTICA (source='cosmetic')
│   ├── mec.lua           ← L1: reparo parcial (pneu/motor/lataria) + reboque (delegação)
│   ├── oficina.lua       ← L1: tuning stages nativos dentro do budget/tier (source='tune') [F2: handling]
│   └── exports.lua       ← API pública read-only (getTier preview, etc.) — mínima
├── client/
│   ├── init.lua          ← estado local, foco NUI, callbacks de relay
│   ├── zones.lua         ← markers/blips fria(1Hz)+quente(perto) p/ as 3 estações
│   ├── bennys.lua        ← L2: preview de cor/neon/roda/kit; câmera (adapta vrp_vehColor); coleta cosmética
│   ├── mec.lua           ← L2: animação de reparo, reboque (TaskLeaveVehicle/attach), coleta de dano
│   └── oficina.lua       ← L2: preview de stage; [F2] aplica override de handling lido de StateBag
├── web/                  ← L3/L4 NUI (runtime + módulos bennys/oficina) — FASE 4 (gate designer/runtime)
└── PLANO.md              ← este arquivo
```

**Por que 1 resource:** os 3 domínios são variações da mesma operação ("estação de serviço sobre uma placa"), compartilham 100% do contrato com o conce (mesma entrada `TRUSTED`, mesmo `canOperate`, mesmo round-trip de customization). 3 resources = 3 entradas `TRUSTED`, 3 ordens de start, 3 manifests divergindo — superfície de contrato 3× sem ganho. A dependência do `vhub_p1skill` (só a oficina) fica isolada na sub-pasta `oficina/` com **degradação graciosa** (FiveM não tem dependência opcional limpa no manifest).

---

## 3. Fluxo canônico server-authoritative (vale para os 3 domínios)

```
1. Cliente entra na zona (estação) → abre NUI (foco) — PREVIEW é efêmero (L-02)
2. Cliente previsualiza no veículo VIVO (SetVehicleMod/cor/neon) — sem custo, sem persistência
3. Cliente clica "aplicar/pagar" → envia INTENÇÃO ao servidor (delta desejado), nunca o custo
4. SERVIDOR (CreateThread; usa Await):
   a. shape do payload (type(payload)=='table') + rate (CFG.rates)
   b. user = getUser(src); char_id válido
   c. AUTORIZAÇÃO: exports.vhub_conce:canOperate(src, plate)  ← OBRIGATÓRIO antes de tudo
   d. valida domínio (bennys: só chaves cosméticas; oficina: stages dentro do budget/tier)
   e. calcula CUSTO server-side (CFG.prices) e cobra: Core.pay(src, custo)  (vhub_money)
   f. PERSISTE via escritor único: exports.vhub_conce:saveVehicleState(plate, patch, source)
   g. confirma ao cliente (aplica final no veículo vivo) + log de auditoria
5. Falha em qualquer passo → rollback visual no cliente (re-aplica o estado salvo do servidor) (L-03)
```

**Regra de ouro:** `_invoker_allowed` (no conce) só prova **qual resource** chamou; **não** prova o player. Por isso **`canOperate(src,plate)` é obrigatório no server do `vhub_custom`** antes de qualquer save (gate de segurança).

---

## 4. Persistência do tuning — a decisão crítica (B)

### 4.1 O que cabe HOJE (sem schema novo)
Stages de performance nativos do GTA **já são representáveis** em `customization.mods` (índice→nível), e a whitelist `CUST_KEYS` do `vstate.lua` já aceita `mods`:

```
engine=11 · brakes=12 · transmission=13 · suspension=15 · armor=16 · turbo=18
```

A oficina escreve **apenas esses índices** em `customization.mods` via `saveVehicleState(plate, {customization={mods={[11]=lvl,...}}}, 'tune')`. **Estado autoritativo = `vstate`. Zero coluna nova.** ✅

### 4.2 O que está BLOQUEADO até a F2 (e por quê)
- **Alocação 5-eixos** (POT/GRIP/FRE/AERO/SUSP do carskill §1.4) e **score/tier derivados**: são **propriedade computada**, não dado de origem. Dono = `vhub_p1skill` (deriva de `customization.mods` + tier do catálogo; grava só StateBag efêmero + telemetria própria). A oficina **não persiste alloc/score em lugar nenhum** — senão vira **2ª fonte de verdade (L-04)**, exatamente o que o carskill v2 removeu.
- **Override server-auth de handling** (`fTractionCurveMax`/`fInitialDragCoeff`/`fAntiRollBarForce` — sem mod nativo de leitura): só faz sentido **com o `vhub_p1skill` existindo** para validar/aplicar/clampar ao tier (carskill §5.2.1, com o **risco técnico nº1**: model-wide vs por-instância — precisa PoC do gate de natives antes da F2). Enquanto o resource não existe, **não há override**.

### 4.3 Se a F2 precisar persistir o vetor de override (decisão a tomar NA F2)
A coluna entra em `vhub_vehicle_state` sob **dono = `vhub_conce`/`VState`** (nova chave whitelisted `handling` em `CUST_KEYS`, escritor único = `VState:save`, `source='tune'`). **Não** criar tabela própria da oficina (`vhub_custom_tuning`) — seria o 3º espelho. **Gate obrigatório na F2:** contrato + persistência.

> **Linha de Registro candidata (NÃO registrar agora, só F2):**
> `Override de handling (grip/aero/susp) | vhub_conce/VState (customization.handling) | vhub_p1skill (deriva/aplica), oficina (escreve via saveVehicleState 'tune') | vhub_vehicle_state.customization JSON | gate F2`

---

## 5. Contratos no conce que precisam de gate (bundle único, antes de codar)

Tudo isto é **mudança no contrato do `vhub_conce`** — fazer **de uma vez**, com os gates, antes de qualquer código de domínio:

1. **`TRUSTED += ['vhub_custom']=true`** em `vhub_conce/server/exports.lua` (hoje TRUSTED: vhub, garage, ferinha, admin, inventory, vehcontrol, legacyfuel, testrunner — **sem** vhub_custom).
2. **Legitimar `source='cosmetic'` e `source='tune'`** em `VState:save`. Hoje só `telemetry` e `repair` têm regras especiais; qualquer outra `source` escreve customization pelo caminho genérico — o que **funciona** para customization, mas o **contrato de `source`** precisa ser explicitado (comentário +, se o gate de persistência pedir, validação de que `cosmetic`/`tune` **não tocam health/fuel**, só `customization`).
3. **Reservar o evento `vHub:vehicleCommitted`** (emitido pelo `VState` após `save` bem-sucedido) no `shared/events.lua` do conce. Shape **primitivo** (L-19): `{ plate=<string>, source=<string>, changed={ customization=bool, health=bool, fuel=bool } }`. **Sem** payload de mods (o consumidor re-lê via `getVehicleState` — replay-safe, L-17). **Implementação do emissor pode ficar para a F2**, mas o nome/shape se reserva agora para o carskill ancorar.

> **Gates do bundle:** `vhub_guardiao_contrato` (TRUSTED, sources, evento) + `vhub_guardiao_persistencia` (cosmetic/tune não tocam health; âncora fail-closed) + `vhub_guardiao_seguranca` (`canOperate` antes do save).

---

## 6. Domínio `mec` — reparo + reboque (D)

### 6.1 Reparo — DELEGA, não duplica (L-15)
O ato de reparo **já existe** e é correto: `vhub_garage/server/maintenance.lua` (ACT_REPAIR → custo por dano → `Core.pay` → `exports.vhub_conce:repairVehicleState` + `DO_REPAIR` no client). **Reimplementar a mesma fórmula = REPROVADO.**

- **Reparo TOTAL no campo** (equivalente ao da garagem): mec **delega** — dispara o caminho único de reparo (preferência: extrair o "ato de reparo" para um export único reusado por garage+mec, OU mec aciona o fluxo do garage). **Uma** fórmula de custo, **um** dono do ato.
- **Reparo PARCIAL** (pneu OU motor OU lataria, eventualmente com item/kit do inventário) — **produto diferente**, não duplicação:
  - Lê o estado real: `st = exports.vhub_conce:getVehicleState(plate)` (`damage`, `engine_health`, `body_health`).
  - Custo próprio por parte (config), pago via `Core.pay`.
  - Persiste via escritor único com `source='repair'` (que **pode elevar health** e reescrever `damage`):
    - pneu: `saveVehicleState(plate, { damage = <damage_atual sem a categoria reparada> }, 'repair')`
    - motor/lataria: `saveVehicleState(plate, { engine_health=cap, body_health=cap }, 'repair')`
  - **Server recompõe o `damage`** a partir do `vstate` (autoritativo) — **não** confia no cliente para "quais pneus já estão bons".
  - Aplica no veículo vivo no client (`SetVehicleTyreFixed`/`SetVehicleFixed` parcial, sob `NetworkRequestControlOfEntity`).

> **Gate de persistência:** validar que `source='repair'` com campos parciais respeita as regras (eleva health só por `repair`, `damage={}` limpa, âncora fail-closed). Hoje `M:repair()` faz reparo TOTAL; o parcial usa `M:save(...,'repair')` com campos específicos — **suportado pelo writer**, precisa de aval explícito.

### 6.2 Reboque (towing) — domínio NOVO, sem dono hoje
Não existe owner de reboque. Cabe em `vhub_custom/mec` ("assistência"). Mexe em **ENTIDADE/posição** → toca **L-16** (escritor único de entidade) e `updateStatus`/`updatePosition` do conce.

- Cenários: (a) reboque de veículo **preso/atolado** (recuperação → reposiciona p/ estrada/pátio); (b) levar veículo **apreendido/abandonado** ao pátio (status).
- Autoridade: a persistência de posição/status **só** via `exports.vhub_conce:updatePosition`/`updateStatus` (TRUSTED). O movimento físico (attach ao caminhão-reboque, `AttachEntityToEntity`) é **L2 client**, com `NetworkRequestControlOfEntity` no entity-writer.
- **Gate obrigatório de natives:** quem é o entity-writer durante o reboque, netId, ownership da entidade rebocada, anti-dupe.

> **Linha de Registro (reboque — domínio novo):**
> `Reboque/recuperação (posição+status) | vhub_custom/mec orquestra → vhub_conce escreve | — | vhub_vehicles.status/position via updateStatus/updatePosition | ação de entidade L2; persistência só via export TRUSTED`

---

## 7. Domínio `bennys` — estética pura (zero gameplay)

### 7.1 Split obrigatório cosmético × performance (anti-overlap)
`shared/config.lua` define `MOD_SPLIT`:
```
PERFORMANCE (oficina, PROIBIDO no bennys): mods 11,12,13,15,16,18
COSMÉTICO   (bennys): TODO o resto — cor primária/secundária/perolado/roda, neon, fumaça (20),
            xenon (22), window_tint, livery, plate_index, wheel_type, e mods visuais de lataria
            (0 spoiler, 1/2 parachoques, 3 saias, 4 escapamento, 5 rollcage, 6 grade, 7 capô,
             8/9 paralamas, 10 teto, 23/24 rodas, 25..49 interior/visual)
```
O server do bennys **rejeita** qualquer chave fora do conjunto cosmético antes de persistir (defesa em profundidade além do `CUST_KEYS` do conce).

### 7.2 Persistência
- `source='cosmetic'`; patch = `{ customization = <só chaves cosméticas> }`.
- Reusa exatamente o formato de `collectCustomization`/`applyCustomization` do `vhub_garage/client/vehicles.lua` (mesmo shape → round-trip íntegro no spawn).
- Custo server-side por item (config espelha tabela de preços do nation_bennys como ponto de partida).

### 7.3 Câmera/preview
Adapta a câmera do `vrp_vehColor`/`nation_bennys` (`CreateCam` + `PointCamAtBone`/`MoveVehCam`) como **L2 HAL client** — native-first, destruída no `onDestroy`/close (A-07).

---

## 8. Domínio `oficina` — performance dentro do tier

### 8.1 Esta sprint (sem carskill F2 materializado)
- Aplica **stages nativos** (11/12/13/15/16/18) em `customization.mods`, `source='tune'`.
- **Limite por tier:** consulta o campo de tier do catálogo do conce (`getCatalog()[model].p1.tier_base`/`tier_max` quando existir) e um **cap estático** de stage por tier definido em `config.lua` (ex.: tier D ⇒ engine máx 1; tier S ⇒ engine máx 3). Enquanto `p1`/tier não existir no catálogo, opera por um **cap padrão conservador** por classe GTA (config), **bloqueando overrides de handling**.
- **Degradação graciosa:** `GetResourceState('vhub_p1skill') == 'started'` + `pcall`. Resource ausente ⇒ só stages nativos no cap estático; **nunca** override de handling.

### 8.2 F2 (acoplada ao `vhub_p1skill` — fora desta sprint)
- Consulta `exports.vhub_p1skill:validateAlloc(plate, proposedMods)` (dono do contrato = `vhub_p1skill`) para validar o budget/score 5-eixos antes de cobrar/persistir.
- Após persistir, o **VState do conce** emite `vHub:vehicleCommitted` (§5.3) → o `vhub_p1skill` recalcula tier/score/afinidade e escreve a StateBag (`vhub_p1`/`vhub_p1_hnd`). A oficina **não** emite o evento (senão o derivador perde commits de outras origens — store/telemetry).
- Override de handling: **só** se o PoC do **risco técnico nº1** (carskill §5.2.1: `SetVehicleHandlingFloat` por-instância vs model-wide) passar no gate de natives.

---

## 9. Segurança, performance e NUI (contratos transversais)

**Segurança (gate seguranca):**
- `canOperate(src,plate)` antes de **todo** save (autoridade de player, não só de resource).
- Shape/range/tamanho do payload validados **antes** do domínio; `CFG.rates` por evento (manual §4.6).
- Custo **sempre** server-side; NUI nunca envia preço/saldo.
- Ações sensíveis logadas com `reason` (auditoria).
- Carro de rua/test-drive (sem registro em `vhub_vehicles`) ⇒ `saveVehicleState` retorna `false` por âncora fail-closed ⇒ preview ephemeral, **nada persiste** (comportamento desejado).

**Performance (gate performance, L-18):**
- Zonas: thread fria 1 Hz (perto?) + thread quente só quando perto (markers). NUI fechada = 0.00 ms.
- Sem polling de estado de veículo: ler State Bag / `getVehicleState` sob demanda.
- Cache de `canOperate`/catálogo com invalidação por evento + `playerDropped` limpa tabelas `[src]`.

**NUI (FASE 4 — gates designer/runtime):**
- Identidade Liquid Glass + Areia + Dourado; `lang="pt-BR"` UTF-8.
- Engine de runtime própria (`web/runtime`) + módulos `web/modules/{bennys,oficina}` com lifecycle (A-02) e cleanup (A-07).
- `SendNUIMessage` sem 60fps de payload bruto (A-08); native bridge centralizado (A-06).

---

## 10. Roadmap por fase (gate por fase)

| Fase | Entrega | Critério de pronto | Gates |
|---|---|---|---|
| **F0** | Registro de Ownership (CLAUDE.md) + bundle de contrato no conce (TRUSTED+sources+reserva de evento) | linhas registradas; conce aceita `vhub_custom`/`cosmetic`/`tune`; evento reservado | arquiteto + **contrato + persistência + segurança** |
| **F1** | Esqueleto do resource (fxmanifest, shared, server/core+init, zonas client) + replay-guard | restart limpo; resmon idle no orçamento; zonas aparecem | simplicidade + performance |
| **F2** | `mec`: reparo (delegação) + reboque | reparo parcial persiste via `repair`; reboque move+persiste sob controle de rede | **natives** + persistência + simplicidade |
| **F3** | `bennys`: estética (split cosmético, câmera, persistência `cosmetic`) | cor/neon/roda/kit persistem por placa; sobrevivem a restart/spawn | designer + runtime + segurança |
| **F4** | `oficina`: stages nativos dentro do cap de tier (sem carskill) | stage respeita cap; persiste `tune`; degradação graciosa | natives + performance + segurança |
| **F5** | NUI completa (runtime + módulos) | Liquid Glass; 0.00 ms NUI fechada; cleanup | **designer + runtime** |
| **F6** | **Acoplamento carskill F2** (`vhub_p1skill`): `validateAlloc`, evento `vehicleCommitted` no VState, override de handling | PoC do risco nº1 OK; budget 5-eixos validado; StateBag de tier | **natives (bloqueante)** + contrato + persistência + revisão |

**Disciplina:** F2→F4 entregáveis e testáveis **sem** a NUI completa (usar comandos/marker simples). A NUI (F5) é polimento. O carskill (F6) só começa após F4 estável.

---

## 11. Gates obrigatórios antes de QUALQUER código (resumo)

1. **`vhub_arquiteto`** — registrar as linhas A–E no Registro de Ownership do `CLAUDE.md` (decisão #26).
2. **`vhub_guardiao_contrato`** — `TRUSTED += vhub_custom`; sources `cosmetic`/`tune`; reserva de `vHub:vehicleCommitted`.
3. **`vhub_guardiao_persistencia`** — `cosmetic`/`tune` não tocam health/fuel; reparo parcial via `repair`; âncora fail-closed.
4. **`vhub_guardiao_seguranca`** — `canOperate(src,plate)` antes de todo save; payload hostil.
5. **`vhub_guardiao_natives`** — entity-writer do reboque (D); [F6] override de handling por-instância (risco nº1).
6. **`vhub_guardiao_revisao`** — gate final por fase + atualiza `contexto.md`.

---

## 12. Riscos e mitigações

| Risco | Mitigação |
|---|---|
| 2ª fonte de verdade de tuning (coluna alloc/score) | **Não criar.** Stages em `customization.mods`; alloc/score = derivado pelo p1skill (§4) |
| Cliente injeta mod de performance pelo bennys | `MOD_SPLIT` server-side rejeita chaves performance no `cosmetic` (§7.1) |
| Duas fórmulas de custo de reparo (mec×garage) | mec **delega** o ato de reparo total; parcial é produto distinto, não cópia (§6.1) |
| Override de handling model-wide (carros idênticos colidem) | **F6 bloqueado** até PoC por-instância no gate de natives (carskill §5.2.1) |
| Derivador (p1skill) dessincronizado | Evento `vehicleCommitted` nasce no **escritor único** (VState), não na oficina (§5.3) |
| Reboque duplica/teleporta entidade errada | `NetworkRequestControlOfEntity` + anti-dupe + validação placa↔netId (gate natives) |
| Carro de rua persiste tuning | âncora fail-closed do `vstate` (placa precisa existir em `vhub_vehicles`) |
| NUI a 60fps / loop quente sempre ligado | A-08 (batch/delta) + zonas fria/quente (§9) |

---

## 13. Definition of Done (por fase)
- [ ] Linhas do Registro de Ownership criadas/atualizadas.
- [ ] `canOperate` antes de todo save; payload validado; `CFG.rates` por evento.
- [ ] Persistência só via `exports.vhub_conce:*` (zero SQL próprio de estado físico; zero `setVData`).
- [ ] `playerDropped` limpa toda tabela `[src]`; handlers institucionais com replay-guard (L-17).
- [ ] Todo `.lua` no `fxmanifest` no mesmo commit (L-15); resmon idle no orçamento.
- [ ] Smoke test descrito + rollback em 1 linha (`git checkout HEAD -- <paths>`; schema aditivo órfão inofensivo).
- [ ] Gate final `vhub_guardiao_revisao`.

---

*Plano vhub_custom v1.0 — consumidor do PRONTUÁRIO, três domínios, zero 2ª fonte de verdade, zero toque no CORE FROZEN. Tuning de stage nativo em `customization.mods`; alloc/score/handling derivado pelo `vhub_p1skill` na F2.*
