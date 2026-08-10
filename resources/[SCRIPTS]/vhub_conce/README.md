# vhub_conce — Concessionária + Autoridade Chave/Placa/Dono

**Versão:** 0.4.1 | **Owner:** vhub_conce

**Responsabilidade única:** identidade e prontuário do veículo. Relação CHAVE↔PLACA↔DONO, compra, estoque, status/IPVA, health, dano e customização. Fuel permanece no CORE; dinheiro no `vhub_money`.

---

## O que faz

- Fonte única de verdade sobre quem é dono de qual placa
- Registra, transfere e deleta veículos persistentes
- Emite e revoga chaves de veículo (sistema de chaves físicas)
- Mantém prontuário físico do veículo via `VState` (fuel, engine, body, odo, customization)
- Cron diário de expiração de IPVA e chaves temporárias

---

## Dependências

```
vhub, vhub_inventory, vhub_money, oxmysql
```

---

## Exports disponíveis (server-side)

### Dono e chave

```lua
-- true se o player pode operar o veículo (é dono ou tem chave válida)
local ok = exports.vhub_conce:canOperate(src, 'ABC1234')

-- true se o player é o dono registrado da placa
local ok = exports.vhub_conce:isOwner(src, 'ABC1234')

-- transfere dono (por char_id — para compra/leilão/P2P)
local ok = exports.vhub_conce:transferOwner('ABC1234', new_char_id)

-- true se a placa existe no banco de dados
local ok = exports.vhub_conce:plateExists('ABC1234')

-- dados completos do veículo (snapshot)
local veh = exports.vhub_conce:getVehicle('ABC1234')

-- lista veículos por dono
local lista = exports.vhub_conce:listByOwner(char_id)

-- lista por status ('parked', 'spawned', 'impound', ...)
local lista = exports.vhub_conce:listByStatus('parked')
```

### Auditoria veicular do custom

```lua
-- exact-gated para vhub_custom; char_id é capturado antes dos awaits
local ok = exports.vhub_conce:appendVehicleAudit(src, actor_char_id, plate, action, payload)
```

Grava apenas `INSERT` append-only em `vhub_vehicle_log`; não altera o estado operacional.

### CRUD de veículo

```lua
-- cria registro de veículo novo (retorna true ou false)
local ok = exports.vhub_conce:createVehicle({
  plate     = 'ABC1234',
  model     = 'sultan',
  owner_cid = char_id,
  status    = 'parked',
})

-- atualiza status do veículo
local ok = exports.vhub_conce:updateStatus('ABC1234', 'spawned')

-- atualiza posição (JSON com x, y, z, h)
local ok = exports.vhub_conce:updatePosition('ABC1234', json.encode({ x=0, y=0, z=0, h=0 }))

-- atualiza customização
local ok = exports.vhub_conce:updateCustomization('ABC1234', customJson, locked)

-- atualiza IPVA e aluguel (unix timestamp de expiração)
local ok = exports.vhub_conce:updateIpva('ABC1234', os.time() + 86400 * 30)
local ok = exports.vhub_conce:updateRental('ABC1234', os.time() + 86400 * 7)

-- remove veículo permanentemente
local ok = exports.vhub_conce:deleteVehicle('ABC1234')
```

### Chaves físicas

```lua
-- emite chave (kind: 'full'|'temp'|'valet'; exp = unix timestamp ou nil = permanente)
local ok = exports.vhub_conce:grantKey('ABC1234', char_id, 'full', actor_cid, nil)

-- revoga chave
local ok = exports.vhub_conce:revokeKey('ABC1234', char_id, 'full')

-- verifica se char_id tem chave válida
local ok = exports.vhub_conce:hasValidKey('ABC1234', char_id)

-- lista todas as chaves de uma placa
local keys = exports.vhub_conce:listKeys('ABC1234')

-- lista todas as chaves de um char_id
local keys = exports.vhub_conce:listKeysOfChar(char_id)

-- purga chaves expiradas
exports.vhub_conce:purgeExpiredKeys()
```

### Estado físico (prontuário VState)

```lua
-- snapshot do estado físico (fuel, engine_health, body_health, odometer, customization)
-- equivalente a exports.vhub:getVehicleState no CORE
local state = exports.vhub_conce:getVehicleState('ABC1234')

-- salva patch no prontuário (escritor único — use em vez de commitVehicleState quando
-- a origem é o próprio conce; outros resources usam exports.vhub:commitVehicleState)
exports.vhub_conce:saveVehicleState('ABC1234', { fuel = 100.0 }, 'refuel')

-- dossiê completo (state + dados de ownership)
local dossie = exports.vhub_conce:getVehicleDossier('ABC1234')

-- utilitários de manutenção (admin)
exports.vhub_conce:repairVehicleState('ABC1234')
exports.vhub_conce:backfillVehicleState()
exports.vhub_conce:reconcileVehicleState()
```

### Estoque (concessionária)

```lua
-- retorna entrada de estoque por model
local entry = exports.vhub_conce:stockGet('sultan')
```

---

## Como escrever estado de veículo (§3.2 do manual)

**De outros resources:** sempre via contrato do CORE:

```lua
-- CORRETO — contrato canônico
exports.vhub:commitVehicleState('ABC1234', { fuel = 100.0 }, 'vhub_meudom:refuel')

-- ERRADO — viola L-13 (escritor único)
-- exports.vhub_conce:saveVehicleState(...)  ← apenas o conce usa internamente
```

---

## Regras aplicáveis (manual_dev_vhub.md)

| Lei | Aplicação aqui |
|-----|---------------|
| L-04 / L-13 | conce é escritor único de identidade de veículo; scripts terceiros transferem via `transferOwner` |
| L-14 | Não mute internos via `getVehicle()` — use os exports de atualização |
| §3.2 | Estado físico: leia por `getVehicleState`, escreva por `commitVehicleState` (CORE) |
| Doutrina da Placa | Toda verdade veicular mora na placa; derivados não persistem |

---

## Mapa de Integração

| # | Export | Assinatura resumida | Quem consome |
|---|--------|---------------------|--------------|
| 1 | `getVehicle` | `(plate) → row\|nil` | garage, custom, vehcontrol |
| 2 | `canOperate` | `(src, plate) → bool` | garage, custom, vehcontrol, nitro |
| 3 | `getVehicleState` | `(plate) → state\|nil` | garage, custom, vehcontrol, nitro |
| 4 | `saveVehicleState` | `(plate, patch, source) → bool` | garage, custom, vehcontrol, nitro |
| 5 | `updatePosition` | `(plate, position_json) → affected` | custom, garage |
| 6 | `createVehicle` | `(row) → bool` | garage, coinshop |
| 7 | `updateStatus` | `(plate, status) → affected` | garage |
| 8 | `transferOwner` | `(plate, char_id) → bool` | ferinha, garage |
| 9 | `grantKey` / `revokeKey` / `hasValidKey` | chave por placa | garage, inventory |
| 10 | `getCatalog` / `getCatalogSnapshot` | catálogo autoritativo | custom, vehcontrol, admin |
| 11 | `appendVehicleAudit` | `(src, actor_char_id, plate, action, payload) → bool` | custom |

## Consome de

| Resource | Exports usados |
|----------|----------------|
| `vhub` (CORE) | `getUser`, `getCharacterId`, `getCData`, `commitVehicleState`, `getVehicleState` |
| `oxmysql` | Persistência direta via `exports.oxmysql` |
| `vhub_inventory` | `giveVehicleKey`, `takeVehicleKey`, `hasVehicleKey` |

## Eventos emitidos

Nenhum. Consumidores leem pelos exports autoritativos.
