# vhub_garage — Garagem Centralizada

**Versão:** 2.0.1 | **Owner:** vhub_garage

Garagem server-authoritative: spawn/guarda de veículos persistentes, pátio de apreensão, aluguel, IPVA e integração com concessionária e leilão. Consome o prontuário do `vhub_conce` e o contrato de spawn do CORE.

---

## O que faz

- Spawn e guarda de veículos do player com validação de chave/owner/status/proximidade
- Pátio de apreensão com taxa configurável e resgate
- Aluguel de veículos por tempo com bloqueio automático
- IPVA: exibe validade e impede uso em inadimplência
- Integra com `vhub_ferinha` para delegação de leilão
- Expõe API admin completa para painel vhub_admin

---

## Dependências

```
vhub, vhub_conce, vhub_ferinha, vhub_inventory, vhub_money, vhub_identity, vhub_groups, oxmysql
```

---

## Exports disponíveis (server-side)

### Consulta pública

```lua
-- dados completos do veículo (via conce)
local veh = exports.vhub_garage:getVehicle('ABC1234')

-- lista veículos de um char_id
local lista = exports.vhub_garage:listOwnerVehicles(char_id)

-- true se a placa está no pátio
local ok = exports.vhub_garage:isImpound('ABC1234')

-- timestamp unix de vencimento do IPVA (ou nil)
local ts = exports.vhub_garage:ipvaUntil('ABC1234')
```

### Ações de gestão

```lua
-- transfere veículo sem passar por UI (admin/missão)
local ok = exports.vhub_garage:forceTransfer('ABC1234', new_char_id)

-- apreende veículo no pátio com razão e taxa extra opcional
local ok = exports.vhub_garage:forceImpound('ABC1234', 'policial_blitz', 500)
```

### API Admin (TRUSTED)

```lua
exports.vhub_garage:adminStats()
exports.vhub_garage:adminListVehicles(filter, limit, offset)
exports.vhub_garage:adminGetVehicle('ABC1234')
exports.vhub_garage:adminListByOwner(char_id)
exports.vhub_garage:adminListAuctions(status)
exports.vhub_garage:adminListImpound()
exports.vhub_garage:adminListLogs('ABC1234', 50)
exports.vhub_garage:adminFindOrphans()

-- dar veículo a um char_id (placa_custom = nil para gerar automático)
exports.vhub_garage:adminGiveVehicle(char_id, 'sultan', nil, actor_src)

-- transferir dono
exports.vhub_garage:adminTransfer('ABC1234', new_char_id, actor_src)

-- deletar veículo
exports.vhub_garage:adminDelete('ABC1234', actor_src)

-- alterar status manualmente
exports.vhub_garage:adminSetStatus('ABC1234', 'parked', actor_src)

-- reparar via export (usa commitVehicleState no CORE)
exports.vhub_garage:adminRepair('ABC1234', actor_src)

-- renovar IPVA por N dias
exports.vhub_garage:adminRenewIpva('ABC1234', 30, actor_src)

-- liberar do pátio
exports.vhub_garage:adminReleaseImpound('ABC1234', actor_src)

-- cancelar leilão
exports.vhub_garage:adminCancelAuction(auction_id, actor_src)

-- estoque de concessionária
exports.vhub_garage:adminSetStock('sultan', 5, 120000, actor_src)

-- chaves
exports.vhub_garage:adminGrantKey('ABC1234', char_id, 'full', 30, actor_src)
exports.vhub_garage:adminRevokeKey('ABC1234', char_id, actor_src)

-- spawn/despawn admin
exports.vhub_garage:adminSpawnTo(src, 'ABC1234', { x=0,y=0,z=0,h=0 }, actor_src)
exports.vhub_garage:adminDespawn('ABC1234', actor_src)

-- manutenção
exports.vhub_garage:adminPurgeExpiredKeys(actor_src)
exports.vhub_garage:adminPurgeOldLogs(30, actor_src)
exports.vhub_garage:adminFinalizeStaleAuctions(actor_src)
```

---

## Ciclo de vida do veículo (§3.2 do manual)

```
COMPRA (conce) → SPAWN (garage valida chave+status) → USO (core acumula estado)
→ GUARDAR (garage store) → PÁTIO (impound/admin) → RECUPERAÇÃO
```

A garagem **nunca** escreve estado físico diretamente — usa `commitVehicleState` do CORE para reparos e sync.

---

## Regras aplicáveis (manual_dev_vhub.md)

| Lei | Aplicação aqui |
|-----|---------------|
| L-04 | Dono do veículo = conce; garage consome via `conce:isOwner`/`conce:canOperate` |
| L-13 | Estado físico escrito via `commitVehicleState` (CORE); nunca `setVData` |
| §3.2 | Ciclo completo documentado: compra→spawn→store→pátio |
| §3.8 | Despawn de entidade usa padrão `TaskLeaveVehicle` + `NetworkRequestControlOfEntity` + `DeleteEntity` |

---

## Mapa de Integração

| # | Export | Assinatura resumida | Quem consome |
|---|--------|---------------------|--------------|
| 1 | `openGarage` | `(src) → ok` | vhub_ipad (app), vhub_admin |
| 2 | `storeVehicle` | `(src, plate) → ok` | vhub_admin, vhub_lspdtool (via forceImpound) |
| 3 | `retrieveVehicle` | `(src, plate, coord) → netid` | vhub_admin |
| 4 | `getPlayerVehicles` | `(src) → lista` | vhub_admin |
| 5 | `forceImpound` | `(plate, actor) → ok` | vhub_lspdtool |
| 6 | `adminSpawnVehicle` | `(src, model) → netid` | vhub_admin |
| 7 | `updateStatus` | `(plate, status) → ok` | vhub_ferinha (após leilão) |

## Consome de

| Resource | Exports usados |
|----------|----------------|
| `vhub` (CORE) | `getUser`, `getCharacterId`, `notify` |
| `vhub_conce` | `getPlayerVehicles`, `spawnVehicle`, `despawnVehicle`, `saveVehicleState`, `loadVehicleState`, `forceImpound`, `givePhysicalKey`, `takePhysicalKey`, `getZones`, `resolveConc` |
| `vhub_ferinha` | `listActiveAuctions`, `getZones` (boot) |
| `vhub_inventory` | `hasVehicleKey`, `giveVehicleKey`, `takeVehicleKey` |
| `vhub_money` | `tryPayment` (taxa de retirada) |
| `vhub_identity` | `getIdentity` (opcional, prontuário) |
| `vhub_groups` | `hasPermission` (ações admin) |

## Eventos emitidos

| Evento | Direção | Payload resumido |
|--------|---------|-----------------|
| `vhub_garage:vehicleStored` | server→client (player) | `{plate}` |
| `vhub_garage:vehicleRetrieved` | server→client (player) | `{plate, netid}` |
