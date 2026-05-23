# vHub Mirage — Módulos ([SCRIPTS])

Resources de gameplay construídos sobre o core vHub Mirage (FROZEN v1.0).
Cada resource é independente: possui schema próprio, exports declarados e sem SQL cross-resource.

---

## Dependências e ordem de carga

```
vHub Core (autoridade máxima)
  │
  ├── vhub_groups        → permissões e grupos por personagem
  ├── vhub_identity      → nome, registro civil, telefone
  ├── vhub_money         → carteira e banco
  ├── vhub_survival      → fome e sede
  │
  ├── vhub_player_state  → spawn, posição, armas, customização de ped
  │     └── depende de: vhub_survival (dano por inanição)
  │
  ├── vhub_inventory     → itens, peso, baús, chaves de veículo
  │     ├── depende de: vhub_survival (callbacks de comida/água)
  │     └── depende de: vhub_player_state (callbacks de bandagem/medkit)
  │
  ├── vhub_garage        → garagem, concessionária, leilão, aluguel,
  │     │                   impound, IPVA, reparo, clone/empréstimo,
  │     │                   transferência P2P
  │     ├── depende de: vhub_inventory (ler/dar chaves físicas)
  │     └── depende de: vhub_money (compra, taxa force-out, IPVA)
  │
  └── vhub_admin         → painel de administração (9 tabs NUI)
        └── delega a todos os modules acima via exports
```

---

## Fluxo de veículo (do zero ao volante)

```
1. Jogador vai à concessionária (zona em vhub_garage)
2. Abre menu → escolhe modelo e confirma compra
3. vhub_garage → valida saldo (vhub_money:tryFullPayment)
4. vhub_garage → registra em vh_vehicles com a placa
5. vhub_garage → salva estado inicial em vh_vehicle_data via vHub.setVData
6. vhub_garage → entrega chave: vhub_inventory:giveItem(src, "veh_key_PLACA", 1)
7. Inventário tem o item "veh_key_PLACA" + registro em vhub_vehicle_keys
8. Jogador vai à garagem (zona em vhub_garage)
9. vhub_garage → lê chaves: vhub_inventory:getVehicleKeys(src)
10. Menu mostra lista de placas disponíveis com status (garage/spawned/impound)
11. Jogador seleciona placa
12. vhub_garage → carrega estado físico: vHub.getVData(plate, "state")
13. vhub_garage → TriggerClientEvent("vhub_garage:do_spawn", src, plate, state, model)
14. Cliente spawna veículo com customização e condição salvas
15. Servidor registra spawn: vHub.Vehicle:onSpawned(plate, netid)
16. State Bags sincronizam fuel/eng/body/odo ao cliente (delta threshold)
17. Driver reporta estado 4Hz via vHub:vState → servidor valida + atualiza VRAM
18. Autosave a cada 60s → vHub.setVData(plate, "state", state) → batch SQL
19. Jogador guarda na garagem → estado salvo imediatamente + Vehicle:unregister
```

---

## Exports por resource

### vhub_core (exports do core vhub)

```lua
exports.vhub:getUID(src)              → number (user_id)
exports.vhub:getUser(src)             → User { id, char_id, name, source, data }
exports.vhub:hasPerm(uid, perm)       → boolean
exports.vhub:grantPerm(uid, perm)     -- requer trusted_resource
exports.vhub:getVehicle(plate)        → VehicleData ou nil
exports.vhub:transferKey(plate, key)  → boolean  -- requer trusted_resource
exports.vhub:banPlayer(uid, r, by)    -- requer trusted_resource
exports.vhub:unbanPlayer(uid)         -- requer trusted_resource
exports.vhub:Status()                 → snapshot { sessoes, veiculos, batch_pendente, ... }
```

### vhub_groups

```lua
exports.vhub_groups:addGroup(src, nome)          → boolean
exports.vhub_groups:removeGroup(src, nome)       → boolean
exports.vhub_groups:hasGroup(src, nome)          → boolean
exports.vhub_groups:hasPermission(src, perm)     → boolean
exports.vhub_groups:getGroups(src)               → { nome = true, ... }
exports.vhub_groups:getUsersByGroup(nome)        → { src, ... }
```

### vhub_identity

```lua
exports.vhub_identity:getIdentity(src)             → { firstname, lastname, dob, cpf, phone, ... }
exports.vhub_identity:getFullName(src)             → "Nome Sobrenome"
exports.vhub_identity:getCharByRegistration(cpf)  → char_id ou nil
exports.vhub_identity:getCharByPhone(phone)       → char_id ou nil
```

### vhub_money

```lua
exports.vhub_money:getWallet(src)               → number
exports.vhub_money:getBank(src)                 → number
exports.vhub_money:giveWallet(src, valor)       → boolean
exports.vhub_money:giveBank(src, valor)         → boolean
exports.vhub_money:setWallet(src, valor)
exports.vhub_money:setBank(src, valor)
exports.vhub_money:tryPayment(src, valor, dry)  → boolean  (só carteira)
exports.vhub_money:tryWithdraw(src, valor)      → boolean  (só banco)
exports.vhub_money:tryDeposit(src, valor)       → boolean
exports.vhub_money:tryFullPayment(src, valor)   → boolean  (carteira + banco)
```

### vhub_survival

```lua
exports.vhub_survival:getVital(src, nome)         → number (0.0–1.0)
exports.vhub_survival:setVital(src, nome, valor)
exports.vhub_survival:varyVital(src, nome, delta)
-- nomes canônicos: "food", "water"
```

### vhub_player_state

```lua
exports.vhub_player_state:giveWeapons(src, weapons, clear)
exports.vhub_player_state:setArmour(src, amount)
exports.vhub_player_state:setHealth(src, amount)
exports.vhub_player_state:teleport(src, x, y, z, heading)
exports.vhub_player_state:getPosition(src)        → x, y, z
```

### vhub_inventory

```lua
exports.vhub_inventory:giveItem(src, fullid, amount)     → boolean
exports.vhub_inventory:takeItem(src, fullid, amount)     → boolean
exports.vhub_inventory:hasItem(src, fullid, amount)      → boolean
exports.vhub_inventory:getItemAmount(src, fullid)        → number
exports.vhub_inventory:giveVehicleKey(src, plate)        → boolean
exports.vhub_inventory:takeVehicleKey(src, plate)        → boolean
exports.vhub_inventory:hasVehicleKey(src, plate)         → boolean
exports.vhub_inventory:getVehicleKeys(src)               → { plate, ... }
exports.vhub_inventory:clearInventory(src)               → boolean
exports.vhub_inventory:openChest(src, bau_id, peso_max)  → table
```

### vhub_garage

```lua
-- Estado físico
exports.vhub_garage:getVehicleState(plate)         → state table ou nil
exports.vhub_garage:forceStore(plate)              -- guarda veículo do mundo
exports.vhub_garage:spawnTo(src, plate)            -- spawna veículo para src

-- Negócio
exports.vhub_garage:getOwner(plate)                → char_id ou nil
exports.vhub_garage:transferVehicle(plate, new_cid)
exports.vhub_garage:giveVehicle(src, model, plate?) → plate
exports.vhub_garage:deleteVehicle(plate)
exports.vhub_garage:getVehiclesByChar(char_id)     → { { plate, model, status }, ... }

-- IPVA / Impound
exports.vhub_garage:renewIpva(plate)
exports.vhub_garage:releaseImpound(plate)

-- Leilão
exports.vhub_garage:cancelAuction(plate)

-- Chaves lógicas
exports.vhub_garage:grantKey(plate, char_id, kind)    -- kind: shared/clone/rental
exports.vhub_garage:revokeKey(plate, char_id)
```

### vhub_admin

```lua
exports.vhub_admin:isAdmin(src)                      → boolean
exports.vhub_admin:listAdmins()                      → { src, ... }
exports.vhub_admin:log(actor_src, action, target, payload)
```

---

## Eventos locais cliente (para HUD e scripts externos)

```lua
-- Inicialização do jogador
AddEventHandler("vHub:localReady", function(user_id, char_id, primeiro_spawn) end)
AddEventHandler("vHub:localCharSelected", function(char_id) end)

-- Dinheiro atualizado (vhub_money → cliente)
AddEventHandler("vhub_money:local_update", function(carteira, banco) end)

-- Inventário atualizado
AddEventHandler("vhub_inventory:local_update", function(inventario) end)

-- Vitais (a cada 1s via vhub_survival)
AddEventHandler("vhub_survival:hud_tick", function(vitais) end)
-- vitais = { food = 0.0..1.0, water = 0.0..1.0 }

-- Spawn do personagem aplicado
AddEventHandler("vhub_player_state:spawned", function(first_spawn) end)

-- Garagem
AddEventHandler("vhub_garage:entrou_zona",         function(idx, garagem) end)
AddEventHandler("vhub_garage:saiu_zona",           function() end)
AddEventHandler("vhub_garage:veiculo_spawnado",    function(plate, entity) end)
AddEventHandler("vhub_garage:veiculo_despawnado",  function(plate) end)

-- Concessionária (via vhub_garage)
AddEventHandler("vhub_garage:entrou_conc",  function(idx, concessionaria) end)
AddEventHandler("vhub_garage:saiu_conc",    function() end)
AddEventHandler("vhub_garage:abrir_compra", function(idx, catalogo) end)

-- Admin
AddEventHandler("vhub_admin:notificacao", function(msg) end)
```

---

## State Bags do jogador (LocalPlayer.state — definidos pelo core)

| Bag | Tipo | Descrição |
|-----|------|-----------|
| `vhub_uid` | number | user_id do jogador |
| `vhub_user_id` | number | alias de vhub_uid (legado) |
| `vhub_char_id` | number | char_id ativo |
| `vhub_pronto` | boolean | true após initDone |
| `vhub_primeiro_spawn` | boolean | true no primeiro spawn da sessão |
| `vhub_is_admin` | boolean | true se hasPerm("panel") |

---

## Regras para criar novos recursos

1. Resource em `resources/[SCRIPTS]/vhub_*`
2. Schema SQL próprio — aplicado via `LoadResourceFile('sql/schema.sql')` em `onResourceStart`
3. FKs ao core: `user_id` e `char_id` como `INT UNSIGNED` obrigatório
4. Valores persistidos: `BLOB` + msgpack **ou** tipo SQL nativo conforme o dado
5. SQL via `exports.oxmysql:*` diretamente — não via `vHub.State`
6. Consultar `metas/manual_dev_vhub.md` para template completo
