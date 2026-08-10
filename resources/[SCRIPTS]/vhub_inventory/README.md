# vhub_inventory — Inventário (Mochila, Baús, Drops e Chaves)

**Versão:** 2.9.1 | **Owner:** vhub_inventory

Inventário server-authoritative com sistema de mochila por personagem, baús físicos, drops no mundo, chaves de veículo e Player Info HUD. UI autoritativa: o servidor decide toda mutação.

O item serial `controle_outdoor` pertence ao inventário, não é negociável, não pode ser
perdido nem armazenado em baú. O efeito é registrado pelo owner `vhub_outdoors`; a metadata
`outdoor_id/access_key` é opaca e nunca autoriza mutação sem revalidação do slot no servidor.

---

## O que faz

- Mochila por `char_id` com peso e slots configuráveis
- Baús físicos posicionados no mundo (interação via `vhub_target`)
- Drops de item no chão com expiração
- Chaves de veículo como item especial rastreado
- Catálogo de itens em `config/inventory.lua`
- Registra handlers de uso de item por export
- HSS integração soft-dep (via `exports.vhub_hss:applyItem`)

---

## Dependências

```
vhub, oxmysql
```

---

## Exports disponíveis (server-side)

### Leitura (pública)

```lua
-- snapshot enxuta do catálogo (retorna lista de {id, name, category})
-- disponível apenas para resources CATALOG_SNAPSHOT_TRUSTED
local cat = exports.vhub_inventory:getCatalogSnapshot()

-- snapshot da mochila: { slots, weight, max, size }
local inv = exports.vhub_inventory:getInventory(src)

-- quantidade de um item na mochila
local qty = exports.vhub_inventory:getItemAmount(src, 'agua_mineral')

-- true se o player tem qty unidades do item
local ok  = exports.vhub_inventory:hasItem(src, 'agua_mineral', 2)

-- peso total da mochila
local peso = exports.vhub_inventory:getInventoryWeight(src)

-- definição do item (cópia segura — sem referência interna)
local def = exports.vhub_inventory:getItemDef('agua_mineral')

-- nome display do item
local nome = exports.vhub_inventory:getItemName('agua_mineral')

-- chaves de veículo
local ok        = exports.vhub_inventory:hasVehicleKey(src, 'ABC1234')
local todas     = exports.vhub_inventory:getVehicleKeys(src)
```

### Mutações (TRUSTED — requer whitelist em `Inventory.TrustedResources`)

```lua
-- dar item ao player (meta opcional: { serial, ... })
local ok, err = exports.vhub_inventory:giveItem(src, 'agua_mineral', 2, nil)

-- remover item (por id + quantidade)
local ok, err = exports.vhub_inventory:takeItem(src, 'agua_mineral', 1)

-- remover item por slot específico
local ok, err = exports.vhub_inventory:takeItemFromSlot(src, slot, 1)

-- dar chave de veículo (item especial)
local ok = exports.vhub_inventory:giveVehicleKey(src, 'ABC1234')

-- remover chave de veículo
local ok = exports.vhub_inventory:takeVehicleKey(src, 'ABC1234')

-- abrir baú para o player (desc: { id, label, capacity, ... })
exports.vhub_inventory:openContainer(src, { id = 'bau_123', label = 'Baú da Oficina', capacity = 20 })
```

### Registrar handler de uso de item

```lua
-- server/init.lua ou server/item_use.lua do seu resource
-- chame isso no boot (após o inventory estar carregado)
exports.vhub_inventory:registerItemUse('bandagem', function(src, slot, meta)
  Citizen.CreateThread(function()
    local ok = exports.vhub_inventory:takeItemFromSlot(src, slot, 1)
    if not ok then return end
    exports.vhub_hss:addBleeding(src, -30)
  end)
end)
```

Para owner cross-resource, prefira o nome de export:

```lua
exports.vhub_inventory:registerItemUse('controle_outdoor', 'useOutdoorRemote')
-- export owner: function(src, item_id, slot, meta)
```

---

## Como adicionar um item novo

Edite `config/inventory.lua` e adicione uma entrada na tabela `Items`:

```lua
['agua_mineral'] = {
  nome      = 'Água Mineral',
  categoria = 'consumivel',
  peso      = 0.5,
  stackavel = true,
  max_stack = 10,
  usavel    = true,
},
```

Depois `restart vhub_inventory` ou reinicie o servidor.

---

## Regras aplicáveis (manual_dev_vhub.md)

| Lei | Aplicação aqui |
|-----|---------------|
| L-04 / L-13 | Itens e chaves são verdade do `vhub_inventory`; nunca `setCData('items', ...)` de fora |
| L-01 | Servidor decide quantidade; cliente nunca subtrai localmente |
| §3.3 | Chave KV dos itens é `inv_*`; não escreva com prefixo alheio |
| §4.6 | Eventos de uso de item devem ter rate em `CFG.rates` |

---

## Mapa de Integração

| # | Export | Assinatura resumida | Quem consome |
|---|--------|---------------------|--------------|
| 1 | `getCatalogSnapshot` | `() → catalogo` | vhub_coinshop, vhub_admin |
| 2 | `getItemsSnapshot` | `() → items_live` | vhub_admin |
| 3 | `getInventory` | `(src) → lista` | vhub_admin, vhub_coinshop, vhub_outdoors |
| 4 | `getItemAmount` | `(src, item) → qtd` | vhub_nitro, vhub_vehcontrol |
| 5 | `hasItem` | `(src, item, qtd?) → bool` | vhub_nitro, vhub_vehcontrol, vhub_voicePMA, vhub_racha |
| 6 | `giveItem` | `(src, item, qtd, meta?) → ok` | vhub_coinshop, vhub_admin, vhub_conce, vhub_outdoors |
| 7 | `takeItem` | `(src, item, qtd) → ok` | vhub_nitro, vhub_vehcontrol |
| 8 | `registerItemUse` | `(item, handler) → ok` | vhub_hss, vhub_nitro, vhub_outdoors |
| 9 | `openContainer` | `(src, container_id) → ok` | vhub_admin |
| 10 | `giveVehicleKey` | `(src, plate) → ok` | vhub_conce, vhub_garage |
| 11 | `hasVehicleKey` | `(src, plate) → bool` | vhub_conce, vhub_garage, vhub_vehcontrol |
| 12 | `takeVehicleKey` | `(src, plate) → ok` | vhub_garage |
| 13 | `getVehicleKeys` | `(src) → lista de plates` | vhub_garage |

## Consome de

| Resource | Exports usados |
|----------|----------------|
| `vhub` (CORE) | `getUser`, `getCharacterId`, `getCData`, `setCData` |
| `oxmysql` | Persistência de inventário |
| `vhub_groups` | `hasPermission` (ações admin de inventário) |

## Eventos emitidos

| Evento | Direção | Payload resumido |
|--------|---------|-----------------|
| `vhub_inventory:itemGiven` | server→client (player) | `{item, qtd, meta}` |
| `vhub_inventory:itemTaken` | server→client (player) | `{item, qtd}` |
