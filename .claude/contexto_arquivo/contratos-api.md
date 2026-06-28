# Arquivo — Contratos de API pública (detalhe)

> Recorte de `contexto.md`. Carregar SOB DEMANDA ao tocar export/evento de um resource. `vhub_guardiao_contrato` é o dono.

## Contratos de API pública (não quebrar)

### vhub_racha — exports públicos

| Export | Proteção | Assinatura |
|--------|----------|------------|
| `catalog` | pública | `() → []track` |
| `lobbies` | pública | `() → []lobby` |
| `isInRace` | pública | `(src) → bool` |
| `isReady` | pública | `() → bool` |
| `Status` | pública | `() → snapshot` |
| `topRanking` | pública | `(kind, mode, limit) → []` |
| `historyRecent` | pública | `(filters, limit) → []` |
| `resultsOf` | pública | `(history_id) → []` |
| `statsOfChar` | pública | `(char_id) → stat` |
| `recordsOfChar` | pública | `(char_id, limit) → []` |
| `createLobby` | `_invoker_allowed()` | `(src, payload) → ok, data` |
| `cancelLobby` | `_invoker_allowed()` | `(inst_id, reason) → ok` |
| `deleteTrack` | `_invoker_allowed()` | `(track_id) → ok` |

**Eventos de rede canônicos (VHubRachaE):** nomes migrados de `shared/enums.lua` para `shared/events.lua` em SPRINT-RACHA-1. Os nomes em si NÃO mudaram — apenas o arquivo de origem. Contratos mantidos.

**NUI callbacks canônicos:** `nui_ready`, `vhub_racha.action`, `vhub_racha.request_sync`

**SendNUIMessage types canônicos (web/):**
- HUD: `hud_show` (inclui `kind` p/ chip de drift), `hud_hide`, `hud_start`, `hud_countdown`, `hud_finish`, `vhub_racha.telemetry`, `vhub_racha.bag_update`
- Painel: `{ action = 'open'|'close'|'refresh'|'result'|'ranking'|'history'|'results'|'race_finish' }`
- Ready-zone: `vhub_racha.lobby.pending`, `vhub_racha.lobby.confirmed`, `vhub_racha.readyzone.project`, `vhub_racha.readyzone.clear`
- **REMOVIDO**: `vhub_racha.totem.*` (totem é nativo, não NUI). Dispatcher único em `web/runtime/core.js` roteia `action`/`type` → bus `nui:*`.

---

### vhub_inventory — exports públicos

| Export | Proteção | Assinatura |
|--------|----------|------------|
| `getInventory` | pública | `(src) → { slots, weight, max, size }` |
| `getItemAmount` | pública | `(src, id) → number` |
| `hasItem` | pública | `(src, id, qty) → bool` |
| `getInventoryWeight` | pública | `(src) → number` |
| `getItemDef` | pública | `(id) → def\|nil` |
| `getItemName` | pública | `(id) → string` |
| `hasVehicleKey` | pública | `(src, plate) → bool` |
| `getVehicleKeys` | pública | `(src) → []plate` |
| `giveItem` | `_invoker_allowed()` | `(src, id, amount, meta) → bool` |
| `takeItem` | `_invoker_allowed()` | `(src, id, amount) → bool` |
| `registerItemUse` | `_invoker_allowed()` | `(id, fn) → bool` |
| `openContainer` | `_invoker_allowed()` | `(src, desc) → bool` — desc = `{ kind, name\|group\|netId }` |
| `giveVehicleKey` | `_invoker_allowed()` | `(src, plate) → bool` |
| `takeVehicleKey` | `_invoker_allowed()` | `(src, plate) → bool` |

**Eventos canônicos (VHubInvE):** `vhub_inventory:open/close/delta/rollback/notify/container_open/container_delta/container_close/use/move/drop/pickup/p2p/store/retrieve/open_container/close_container/request_sync/hud_req/hud`

**NUI callbacks canônicos:** `nui_ready`, `close`, `use`, `move`, `container_close`, `store`, `retrieve`

**SendNUIMessage actions canônicos:** `open`, `close`, `delta`, `rollback`, `notify`, `container_open`, `container_close`, `container_delta`

---

### vHub.getUData / setUData / getCData / setCData / getVData / setVData / getGData / setGData
- Assinatura: `(id, key [, value [, tx]])` — estável
- Exige `Citizen.CreateThread` no chamador (usa `Citizen.Await` internamente via assertThread)
- **`getVData`/`setVData` ESTAVAM MORTOS desde o freeze por typo `@dkey` (decisão #20); corrigidos em 2026-06-04 — assinatura inalterada, comportamento agora VIVO.** Bind de chave é sempre `key` (nunca `dkey`).

### exports do resource `vhub`
| Export | Assinatura | Proteção |
|--------|-----------|---------|
| `API` | `() → vHub` | pública (bootstrap) |
| `Status` / `Health` | `() → snapshot` | pública |
| `getVHub` | `() → vHub` | K:export |
| `getUser` | `(src) → User` | K:export |
| `getUID` | `(src) → uid` | K:export |
| `hasPerm` | `(uid, perm) → bool` | K:export |
| `grantPerm` | `(uid, perm)` | `_invoker_allowed()` |
| `getVehicle` | `(plate) → VD` | K:export |
| `transferKey` | `(plate, key)` | `_invoker_allowed()` |
| `banPlayer` | `(uid, r, by)` | `_invoker_allowed()` |
| `unbanPlayer` | `(uid)` | `_invoker_allowed()` |
| `registerStateDriver` | `(drv) → bool` | só aceita antes de `State._ready` |

> **N0-2 (decisão #32):** `_invoker_allowed` é DEFAULT-DENY — sem `trusted_resources` populado, `grantPerm`/`transferKey`/`banPlayer`/`unbanPlayer` NEGAM (warn one-shot). `getVehicle (plate)→VD` segue `K:export` (sem gate) e devolve VD vivo por referência — risco residual SEPARADO, não endereçado.

---

### exports do resource `vhub_conce` (todos `_invoker_allowed`; trusted: vhub, vhub_garage, vhub_ferinha, vhub_admin, vhub_inventory, vhub_vehcontrol, vhub_legacyfuel, vhub_testrunner)
| Export | Assinatura |
|--------|-----------|
| `canOperate` | `(src, plate) → bool` |
| `isOwner` | `(src, plate) → bool` |
| `transferOwner` | `(plate, new_cid) → bool` — ÚNICO escritor de `char_id`; **transação ATÔMICA** (char_id+revoke/grant 'owner', `SQL:transferOwnerTx`, decisão #32); retorna commit REAL (era sempre `true`) |
| `plateExists` / `getVehicle` / `listByOwner` / `listByStatus` | leitura de `vhub_vehicles` |
| `createVehicle` / `updateStatus` / `updatePosition` / `updateCustomization` / `updateIpva` / `updateRental` / `deleteVehicle` | escrita `vhub_vehicles` (+ espelho `vh_vehicles`) |
| `grantKey` / `revokeKey` / `hasValidKey` / `listKeys` / `listKeysOfChar` / `purgeExpiredKeys` | `vhub_vehicle_keys` |
| `stockGet` / `stockSet` / `stockDecrement` | `vhub_dealership_stock` |
| `getCatalog` | `() → catálogo` (garage cacheia no boot) |
| `buy` / `sellToShop` / `testDrive` | `(...) → {ok,msg}` (garage delega + fala com NUI) |
| `getVehicleState` / `getVehicleDossier` | leitura do prontuário `vhub_vehicle_state` — **NUNCA nil p/ placa registrada** (estado de fábrica se nunca persistiu); nil p/ placa inexistente (#24) |
| `saveVehicleState` / `repairVehicleState` | `(plate, patch, source)` / `(plate)` — escritor único do físico; repair é o ÚNICO que eleva health (#24) |
| `backfillVehicleState` / `reconcileVehicleState` | manutenção 1x/idempotente — disparados pelo garage pós-DDL (#24) |

### exports do resource `vhub_ferinha` (todos `_invoker_allowed`; trusted: vhub, vhub_garage, vhub_admin, vhub_conce)
| Export | Assinatura |
|--------|-----------|
| `listActiveAuctions` | `() → []auction` |
| `getAuctionByPlate` | `(plate) → auction\|nil` |
| `newAuction` | `(src, plate, min_bid, buyout, dur_min) → {ok,msg}` |
| `bid` | `(src, auction_id, amount) → {ok,msg}` |
| `cancelAuction` | `(id, actor_cid) → bool` |
| `finalizeExpired` | `() → count` |

### exports do resource `vhub_money` (mutadores `_invoker_allowed`; trusted += `vhub_ferinha`)
| Export | Assinatura | Proteção |
|--------|-----------|---------|
| `giveBankChar` | `(char_id, valor, reason) → bool` — credita banco ONLINE ou OFFLINE (offline-safe; fecha race de login) | `_invoker_allowed()` |

> Contratos do `vhub_garage` mantidos via proxy/delegator (decisão #18): `getVehicle`, `listOwnerVehicles`, `isImpound`, `ipvaUntil`, `forceTransfer`, `forceImpound` — assinaturas inalteradas (consumidos por `vhub_inventory`, `vhub_admin`).

---

