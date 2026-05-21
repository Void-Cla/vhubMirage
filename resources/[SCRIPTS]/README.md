# vHub Mirage — Módulos

Sistema modular de gameplay para FiveM sobre o core vHub Mirage.

## Arquitetura

```
vHub Core (autoridade máxima)
  │
  ├── vhub_groups       → permissões e grupos por personagem
  ├── vhub_identity     → nome, registro, telefone
  ├── vhub_money        → carteira e banco
  ├── vhub_survival     → fome e sede
  │
  ├── vhub_player_state → spawn, posição, armas, customização de ped
  │     └── depende de: vhub_survival (dano por inanição)
  │
  ├── vhub_inventory    → itens, peso, baús, chaves de veículo
  │     ├── depende de: vhub_survival (callbacks de comida/água)
  │     └── depende de: vhub_player_state (callbacks de bandagem/medkit)
  │
  ├── vhub_garage       → garagem via chave do inventário
  │     ├── depende de: vhub_inventory (ler chaves)
  │     └── depende de: vhub_money (taxa force-out)
  │
  ├── vhub_dealership   → compra/venda de veículos
  │     ├── depende de: vhub_inventory (entregar chave)
  │     └── depende de: vhub_money (cobrar/creditar)
  │
  └── vhub_admin        → ferramentas de administração
        └── depende de: todos os módulos acima
```

## Fluxo de veículo (do zero ao volante)

```
1. Jogador vai à concessionária
2. Escolhe modelo e confirma compra
3. vhub_dealership → valida saldo (vhub_money:tryFullPayment)
4. vhub_dealership → registra em vh_vehicles com a placa
5. vhub_dealership → salva estado inicial em vh_char_data("veh_state|PLACA")
6. vhub_dealership → entrega chave: vhub_inventory:giveVehicleKey(src, placa)
7. Inventário agora tem "veh_key|PLACA"
8. Jogador vai à garagem
9. vhub_garage → lê inventário: vhub_inventory:getVehicleKeys(src)
10. Garagem mostra lista de placas disponíveis
11. Jogador seleciona placa
12. vhub_garage → carrega estado: getCData(char_id, "veh_state|PLACA")
13. vhub_garage → TriggerClientEvent("vhub_garage:do_spawn", ...)
14. Cliente spawna veículo com customização e condição salvas
15. Report periódico a cada 30s → "vhub_garage:update_state"
16. Servidor salva estado atualizado em getCData
17. Jogador volta à garagem e guarda → estado salvo imediatamente
```

## Contratos de exports

### vhub_inventory
```lua
exports.vhub_inventory:giveItem(src, fullid, amount)    → boolean
exports.vhub_inventory:takeItem(src, fullid, amount)    → boolean
exports.vhub_inventory:hasItem(src, fullid, amount)     → boolean
exports.vhub_inventory:getItemAmount(src, fullid)       → number
exports.vhub_inventory:giveVehicleKey(src, plate)       → boolean
exports.vhub_inventory:takeVehicleKey(src, plate)       → boolean
exports.vhub_inventory:hasVehicleKey(src, plate)        → boolean
exports.vhub_inventory:getVehicleKeys(src)              → { plate, ... }
exports.vhub_inventory:openChest(src, bau_id, peso_max) → table
```

### vhub_money
```lua
exports.vhub_money:getWallet(src)              → number
exports.vhub_money:getBank(src)                → number
exports.vhub_money:giveWallet(src, valor)      → boolean
exports.vhub_money:giveBank(src, valor)        → boolean
exports.vhub_money:tryPayment(src, valor, dry) → boolean
exports.vhub_money:tryWithdraw(src, valor)     → boolean
exports.vhub_money:tryDeposit(src, valor)      → boolean
exports.vhub_money:tryFullPayment(src, valor)  → boolean (carteira + banco)
```

### vhub_groups
```lua
exports.vhub_groups:addGroup(src, nome)         → boolean
exports.vhub_groups:removeGroup(src, nome)      → boolean
exports.vhub_groups:hasGroup(src, nome)         → boolean
exports.vhub_groups:hasPermission(src, perm)    → boolean
exports.vhub_groups:getGroups(src)              → { nome=true, ... }
exports.vhub_groups:getUsersByGroup(nome)       → { src, ... }
```

### vhub_player_state
```lua
exports.vhub_player_state:giveWeapons(src, weapons, clear)
exports.vhub_player_state:setArmour(src, amount)
exports.vhub_player_state:setHealth(src, amount)
exports.vhub_player_state:teleport(src, x, y, z, heading)
exports.vhub_player_state:getPosition(src)  → x, y, z
```

### vhub_garage
```lua
exports.vhub_garage:getVehicleState(src, plate)  → state table ou nil
exports.vhub_garage:forceStore(src, plate, state)
```

### vhub_dealership
```lua
exports.vhub_dealership:getCatalogo()        → { modelo = {...}, ... }
exports.vhub_dealership:getModeloInfo(model) → { nome, preco, cat, desc }
```

### vhub_survival
```lua
exports.vhub_survival:getVital(src, nome)         → number (0-1)
exports.vhub_survival:setVital(src, nome, valor)
exports.vhub_survival:varyVital(src, nome, delta)
```

### vhub_identity
```lua
exports.vhub_identity:getIdentity(src)              → { firstname, lastname, age, ... }
exports.vhub_identity:getFullName(src)              → "Firstname Lastname"
exports.vhub_identity:getCharByRegistration(reg)   → char_id ou nil
exports.vhub_identity:getCharByPhone(phone)        → char_id ou nil
```

## Eventos locais do cliente (para scripts de HUD)

```lua
-- Dinheiro atualizado
AddEventHandler("vhub_money:local_update", function(carteira, banco) end)

-- Inventário atualizado
AddEventHandler("vhub_inventory:local_update", function(inventario) end)

-- Vitais atualizados (a cada 1s)
AddEventHandler("vhub_survival:hud_tick", function(vitais) end)

-- Estado do jogador pronto após spawn
AddEventHandler("vhub_player_state:spawned", function(first_spawn) end)

-- Zona de garagem
AddEventHandler("vhub_garage:entrou_zona", function(idx, garagem) end)
AddEventHandler("vhub_garage:saiu_zona", function() end)

-- Veículo spawnado/despawnado
AddEventHandler("vhub_garage:veículo_spawnado", function(plate, entity) end)
AddEventHandler("vhub_garage:veículo_despawnado", function(plate) end)

-- Zona de concessionária
AddEventHandler("vhub_dealership:entrou_zona", function(idx, conc) end)
AddEventHandler("vhub_dealership:saiu_zona", function() end)
AddEventHandler("vhub_dealership:abrir_menu", function(idx, catalogo) end)
```
