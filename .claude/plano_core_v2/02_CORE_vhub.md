# 02 — Análise Profunda do `[CORE]/vhub`

> **Resource:** `resources/[CORE]/vhub`
> **Versão:** CORE FROZEN v1.0 — selado em 2026-05-22
> **resmon medido (declarado):** 0.02ms idle (alvo < 0.05ms) · LOC ≈ 2.432
> **Próxima janela de revisão:** +12 meses. Qualquer alteração exige bump para v2.0 e aprovação dos guardiões.

---

## 1. Arquitetura Geral

### 1.1 O que é o CORE/vhub

O `vhub` é a **espinha dorsal autoritativa** do framework vHub Mirage. É o único resource que detém autoridade máxima sobre o estado do servidor: identidade de jogadores, sessões, permissões, persistência KV (user/char/vehicle/global), vehicle state, rate-limiting e segurança de net events. Todos os outros recursos do ecossistema (vhub_conce, vhub_garage, vhub_vehcontrol, vhub_nitro, vhub_racha, etc.) dependem dele.

**Os três problemas estruturais que o core resolve** (segundo o `readme.md`):
1. **Race condition em `user_id`** — alocador server-side (`vHub._next_user_id` / `_next_char_id`) seedado de `MAX(id)`, com `INSERT IGNORE` de id explícito e fallback `AUTO_INCREMENT + LAST_INSERT_ID`. Como Lua é single-thread, não há race entre conexões simultâneas.
2. **Latência de SQL** — VRAM-first: dados lidos de memória; o banco só é consultado quando a memória não tem o valor (cache `S._mem[etype][eid][key]`).
3. **Acoplamento total de SQL** — único ponto de escrita SQL é `server/state.lua`; queries centralizadas em `server/sql.lua` com nomes semânticos prefixados `vh/`.

**O que o core NÃO faz** (intencionalmente delegado):
- Inventário, dinheiro, grupos, identidade → resources externos via KV (`vHub.getCData(cid, "money")`)
- Spawn do jogador → `vhub_player_state` (resource externo)
- Spawn de veículo → `vhub_player_state` (comentado em `fxmanifest.lua` L42, `init.lua` L73)
- UI → core é 100% server-side exceto por 2 arquivos client leves (`client/bootstrap.lua`, `client/vehicle.lua`)

### 1.2 Ordem de Carga (fxmanifest.lua)

```lua
fx_version 'cerulean'
game      'gta5'
lua54     'yes'
dependency 'oxmysql'

shared_scripts {
  'shared/config.lua',   -- [1] cria vHub = {} e define mergeConfig
  'shared/events.lua',   -- [2] vHub.E (constantes de eventos)
  'shared/utils.lua',    -- [3] vHub.Utils (helpers puros)
  'shared/logger.lua',   -- [4] vHub.Logger (único ponto de log)
}

server_scripts {
  'bootstrap.lua',       -- ÚNICO server_script declarado
}

client_scripts {
  'client/bootstrap.lua', -- ready único, initDone, charSelected, State Bags
  'client/vehicle.lua',   -- report de veículo 4Hz
}
```

A ordem de execução no runtime FiveM é garantida: **shared_scripts → server_scripts → client_scripts**.

### 1.3 Bootstrap Flow

#### Server-side (sequência completa em `bootstrap.lua`)

`bootstrap.lua` é o único `server_script` declarado e é executado **depois** dos 4 shared_scripts. Ele:

1. **`criar_config()`** (L58-80) — lê convars via `GetConvarInt`/`GetConvarFloat`/`GetConvar`:
   ```lua
   {
     db = { driver = "oxmysql", resource = "oxmysql" },
     log_level = inteiro("vhub_log_level", 1, 0, 3),
     max_payload = inteiro("vhub_max_payload", 8192, 512, 65536),
     save_interval = inteiro("vhub_save_interval", 60, 15, 3600),
     fuel_rate = decimal("vhub_fuel_rate", 0.005, 0.0, 1.0),
     whitelist_enabled = booleano("vhub_whitelist", false),
     modules = {},
     lang = { not_whitelisted = "Sem whitelist. ID: " },
     webhooks = { join, leave, ban, security }
   }
   ```
   > ⚠️ **Atenção:** esse `criar_config` **NÃO** chama `vHub.mergeConfig` e **NÃO** herda `_defaults` de `shared/config.lua`. Campos como `trusted_resources`, `max_ping`, `ping_check_interval`, `ping_check_enabled`, `max_speed_kmh`, `veh_state_hz`, `lang.banned`, `lang.duplicate_login`, `lang.ping_kick` ficam **nil** em `vHub.cfg`. O boot usa fallbacks inline (`vHub.cfg.save_interval or 60`, etc.) — ver Seção 13.

2. **`criar_driver()`** (L101-288) — instancia o driver oxmysql interno com `_executar`, `init`, `prepare`, `query`, `batch`. Cada query tem timeout de 15s via `SetTimeout(15000, ...)` — comentário admite "KNOWN MINOR LEAK: closure permanece viva até 15s mesmo após resolver".
3. **`validar_driver(driver)`** (L290-296) — verifica que `init/prepare/query/batch` existem no driver; se faltar um, `falhar("driver_invalido", ...)`.
4. **`carregar_base()`** (L298-312) — `LoadResourceFile("base.lua")` + `load()` com `_ENV = _G` + `pcall`.
5. **`base.lua`** então:
   - Verifica `rawget(_G, "vHub")` e flag `_server_ready` (evita duplo loadmod em reload) — L11-14.
   - `LoadResourceFile("server/init.lua")` + `load()` + `pcall`.
6. **`server/init.lua`** (L64-72) chama `loadmod()` na ordem obrigatória:
   ```
   kernel → state → sql → notify → auth → vehicle → security → boot → exports
   ```
7. **`validar_base(vhub)`** (L314-330) — confirma que `init`, `State`, `Kernel`, `Auth`, `Vehicle`, `Security`, `Notify` existem e têm o tipo correto.
8. **`vHubRuntime:init(config, driver)`** → `boot.lua:vHub:init()` (L7-220):
   - Normaliza `log_level` (número→string: `{[0]="DEBUG",[1]="INFO",[2]="WARN",[3]="ERROR"}`)
   - `vHub.State:setDriver(db_driver)` → conecta ao banco, aplica prepares enfileirados, dispara seeds de `_next_user_id` e `_next_char_id` em threads separadas
   - Registra `AddEventHandler("onResourceStop")`, `onResourceStart`, `playerDropped`, `playerConnecting`
   - Registra todos os `K:net` (vHub:ready, vHub:died, vHub:selectChar, vHub:vSpawned/vDespawned/vEnter/vLeave/vState)
   - Inicia timer de autosave (`SetTimeout((vHub.cfg.save_interval or 60) * 1000, doSave)`)
   - Inicia ping check se `vHub.cfg.ping_check_enabled`
9. **`aplicar_schema(driver)`** (L332-340) — executa `sql/schema.sql` inteiro como UMA query multi-statement (exige `multipleStatements=true` na connection string — validado em `Driver:init` L187).
10. **`Boot.pronto = true`** — sistema pronto.

Qualquer falha chama `falhar(codigo, mensagem, meta)` que loga FATAL e lança `error()` — impedindo o resource de ficar "started" em estado parcial.

#### Client-side (sequência em `client/bootstrap.lua`)

1. Aguarda `playerSpawned` (nativo do FiveM, disparado por `spawnmanager`).
2. Se disparado → `enviarReady()` → `TriggerServerEvent("vHub:ready")`.
3. **Fallback nativo** (thread monitora por 60s): se `NetworkIsPlayerActive(PlayerId()) = true` e `playerSpawned` não disparou em 2s, executa `spawnNativo()` que faz `NetworkResurrectLocalPlayer` + `ShutdownLoadingScreen` + `SetPlayerModel` + `DoScreenFadeIn` na posição hard-coded `{ x = -538.70, y = -214.91, z = 37.65, h = 0.0 }` com modelo `mp_m_freemode_01`. Depois `enviarReady()`.
4. **Debounce de 5s** (`DEBOUNCE_MS = 5000`) impede duplo `vHub:ready` se spawnmanager + fallback dispararem quase juntos.
5. **Retry em 15s**: se `_init_done == false`, reenvia `vHub:ready` (cobre perda de pacote).
6. Ao receber `vHub:initDone` (server → client): seta State Bags locais em `LocalPlayer.state`:
   ```lua
   LocalPlayer.state:set("vhub_uid",            user_id,               true)
   LocalPlayer.state:set("vhub_user_id",        user_id,               true)  -- alias legado
   LocalPlayer.state:set("vhub_char_id",        char_id,               true)
   LocalPlayer.state:set("vhub_pronto",         true,                  true)
   LocalPlayer.state:set("vhub_primeiro_spawn", primeiro_spawn == true, true)
   ```
   E dispara `TriggerEvent("vHub:localReady", user_id, char_id, primeiro_spawn)`.

### 1.4 Conceito de "kernel"

`server/kernel.lua` define `vHub.Kernel` — o **barramento central** de comunicação. Não gerencia dados de negócio; gerencia:
- **`K:net(name, handler, opts)`** — registrador de net events seguro (rejeita `src<=0`, calcula payload size, aplica `checkPayload`, rate-limit O(1), permission guard, dispatch em thread ou inline).
- **`K:on(name, fn)`** — wrapper para `AddEventHandler` server-local.
- **`K:emit(src, name, ...)`** — `TriggerClientEvent(name, src, ...)`.
- **`K:broadcast(name, ...)`** — `TriggerClientEvent(name, -1, ...)`.
- **`K:export(name, fn)`** — usa `__cfx_export_<resource>_<name>` (mecanismo interno do FiveM) para registrar exports dinamicamente sem declarar no fxmanifest.
- **`K:call(res, name, ...)`** — `exports[res][name](...)`.
- **`K:grantPerm/revokePerm/hasPerm/clearPerms`** — sistema de permissões em `K._perms[uid][perm] = true`. `"admin.*"` é curinga para qualquer `"admin.X"`.
- **`K:_rateOK(src, action, max, win, block)`** — sliding window O(1) com chaves `"src:action"`.

O kernel orquestra o resto do core indiretamente: os módulos usam `K:net` para registrar net events (em `boot.lua`) e `K:export` para expor API (em `exports.lua`).

---

## 2. Vehicle State Model

### 2.1 O que é "vehicle state"

Vehicle state é o conjunto de campos físicos/lógicos que descrevem o veículo em tempo real:
```lua
-- server/vehicle.lua L26-30 (VD:init)
self.state = {
  fuel=100.0,
  engine_health=1000.0,
  body_health=1000.0,
  damage={},
  tuning={},
  garage=nil,
  last_pos={x=0,y=0,z=0,h=0},
  odometer=0.0,
  engine_on=false,
}
```

Esse estado **vive na VRAM** dentro do objeto `VehicleData` (`vd.state`) e é **persistido** no banco como KV `vh_vehicle_data(plate, "state", dvalue)` via `vHub.setVData(plate, "state", vd.state)`.

### 2.2 Estrutura completa do VehicleData (VD)

```lua
-- server/vehicle.lua L17-37
local VD = vHub.class()
function VD:init(plate, key_uid)
  self.plate     = plate
  self.key_uid   = key_uid   -- nil = server/auction owns it
  self.netid     = nil       -- FiveM network entity ID (válido só quando spawned=true)
  self.spawned   = false
  self.driver    = nil       -- source do motorista atual (nil se vazio)
  self.occupants = {}        -- { [source] = seat_index }
  self.dirty     = false
  self.state = { ... }       -- tabela acima
  -- Cache do último valor replicado ao State Bag (gating por delta)
  self._last_fuel_bag = -math.huge   -- garante primeiro write sempre
  self._last_eng_bag  = -math.huge
  self._last_body_bag = -math.huge
  self._last_odo_bag  = -math.huge
end
```

### 2.3 VRAM (Vehicle RAM) — como funciona o cache

A VRAM não é um conceito isolado de veículos; é o cache geral do `server/state.lua`:
```lua
-- server/state.lua L6-13
S._mem        = {}    -- VRAM { [etype][eid][key] = value }
S._snap       = {}    -- snapshots de TX para rollback
S._batch      = {}    -- ops SQL pendentes
S._batchN     = 0
S._flushing   = false
S._validators = {}
S._driver     = nil
S._ready      = false
S._cprepare   = {}    -- fila de prepares antes do driver
S._cquery     = {}    -- fila de queries antes do driver
S._prepared   = {}
```

**Estrutura de `_mem`** (a VRAM):
```lua
_mem["ud"][user_id][key] = value  -- user data (ban.active, datatable, permissions)
_mem["cd"][char_id][key] = value  -- char data (money, inventory, position)
_mem["vd"][plate][key]   = value  -- vehicle data (state, tuning, damage)
_mem["gd"]["__g"][key]   = value  -- global data (server_economy, day_count)
```

**Leitura (`S:get`)**:
```lua
function S:get(et, eid, key)
  local t = self._mem[et]; if not t then return nil end
  local e = t[eid];        if not e then return nil end
  if key ~= nil then return e[key] end
  return e
end
```

**Escrita (`S:set`)** com snapshot para TX/rollback:
```lua
function S:set(et, eid, key, val, tx)
  if not self._mem[et]      then self._mem[et] = {} end
  if not self._mem[et][eid] then self._mem[et][eid] = {} end
  if tx then
    if not self._snap[tx] then self._snap[tx] = {} end
    local sk = et.."\0"..tostring(eid).."\0"..key
    if self._snap[tx][sk] == nil then
      self._snap[tx][sk] = { et=et, eid=eid, key=key,
        prev = self._mem[et][eid][key] }
    end
  end
  self._mem[et][eid][key] = val
end
```

**Invalidação após write** (`S:invalidate`):
```lua
function S:invalidate(et, eid, key)
  local t = self._mem[et]; if not t then return end
  local e = t[eid];        if not e then return end
  e[key] = nil
end
```
Após `_set`, a maioria das chaves é invalidada para forçar leitura do banco na próxima consulta (evita o bug "datatable crescente"). **Exceções (hot keys)**: `ban.active`, `whitelist`, `permissions` — permanecem em VRAM para acesso instantâneo sem round-trip.

### 2.4 API pública de dados (state.lua L389-397)

```lua
function vHub.getUData(uid, k)        vHub.assertThread(); return _get("ud",uid,k,"vh/get_ud","user_id") end
function vHub.setUData(uid, k, v, tx)                       _set("ud",uid,k,v,"vh/set_ud","user_id",tx)  end
function vHub.getCData(cid, k)        vHub.assertThread(); return _get("cd",cid,k,"vh/get_cd","char_id") end
function vHub.setCData(cid, k, v, tx)                       _set("cd",cid,k,v,"vh/set_cd","char_id",tx)  end
function vHub.getVData(pl, k)         vHub.assertThread(); return _get("vd",pl,k,"vh/get_vd","plate")    end
function vHub.setVData(pl, k, v, tx)                        _set("vd",pl,k,v,"vh/set_vd","plate",tx)     end
function vHub.getGData(k)             vHub.assertThread(); return _get("gd","__g",k,"vh/get_gd","dkey")  end
function vHub.setGData(k, v, tx)                            _set("gd","__g",k,v,"vh/set_gd","dkey",tx)   end
```

> **Atenção:** `assertThread()` é chamado apenas nos **getters** (que fazem `Citizen.Await` internamente se VRAM miss). Os **setters** NÃO chamam `assertThread` (não precisam — só enfileiram op no batch). O readme diz "todos exigem Citizen.CreateThread" mas isso é inexato.

### 2.5 State Bags registrados

#### State Bags em entidades de veículo (server-side, escrita)

Registrados dinamicamente em `VD:_syncBags()` (server/vehicle.lua L52-63) via `Entity(ent).state:set(key, value, true)` (o `true` = replicated):

| State Bag key | Tipo | Threshold delta | Quem escreve |
|---------------|------|-----------------|--------------|
| `vh_fuel`     | float | 0.5             | `VD:_syncBags`, `Veh:onStateUpdate` |
| `vh_eng`      | float | 5.0             | `VD:_syncBags`, `Veh:onStateUpdate` |
| `vh_body`     | float | 5.0             | `VD:_syncBags`, `Veh:onStateUpdate` |
| `vh_odo`      | float | 0.05            | `VD:_syncBags`, `Veh:onStateUpdate` |
| `vh_tune`     | table | (sempre)        | `VD:_syncBags` |
| `vh_on`       | bool  | (sempre)        | `VD:_syncBags`, `Veh:onStateUpdate` |

`bagSet` aplica gating por delta **+ zero-crossing** (força write quando `value==0 and last~=0`):
```lua
local function bagSet(bag, key, value, vd, last_field, threshold)
  local last = vd[last_field]
  local cruzou_zero = (value == 0 and last ~= 0)
  if cruzou_zero or math.abs(value - last) >= threshold then
    bag:set(key, value, true)
    vd[last_field] = value
  end
end
```

#### State Bags em `LocalPlayer.state` (client-side, escrita)

Definidos em `client/bootstrap.lua` L106-111 ao receber `vHub:initDone`:
```lua
LocalPlayer.state:set("vhub_uid",            user_id,               true)
LocalPlayer.state:set("vhub_user_id",        user_id,               true)  -- alias legado
LocalPlayer.state:set("vhub_char_id",        char_id,               true)
LocalPlayer.state:set("vhub_pronto",         true,                  true)
LocalPlayer.state:set("vhub_primeiro_spawn", primeiro_spawn == true, true)
```

E no `boot.lua` L110 para `uid=1`:
```lua
Player(src).state:set("vhub_is_admin", true, true)
```

#### State Bags lidos pelo client

`client/vehicle.lua` L26-35 lê `state.fuel`, `state.engine_health`, `state.body_health` recebidos via net event `vHub:vehicleStateLoad` (não via State Bag direta). Não há leitura de State Bags do veículo pelo cliente nos arquivos do core (leitura é responsabilidade de HUDs externos, ex: `vhub_vehcontrol`).

### 2.6 Diferença entre state interno (Lua table) e state bag (networked)

- **State interno** (`vd.state`, `_mem["vd"][plate]["state"]`) — tabela Lua em memória no servidor. Não é replicada. É a fonte de verdade autoritativa. Persistida em `vh_vehicle_data` como BLOB msgpack.
- **State Bag** (`Entity(ent).state.vh_fuel`, etc.) — mecanismo nativo do FiveM. Replicada a todos os clients via protocolo interno do FiveM. O servidor escreve via `bag:set(key, value, true)`; os clients leem via `Entity(veh).state.vh_fuel`. É uma **projeção** do state interno, com gating por delta para reduzir tráfego.

---

## 3. Ownership & Driver Model

### 3.1 Os três conceitos de "ownership"

| Conceito | Definição | Onde vive | Muda quando |
|----------|-----------|-----------|-------------|
| **`driver`** | Quem está atualmente no banco do motorista (seat=-1) | `vd.driver` (em `VehicleData`) | `Veh:onEnter(src, plate, netid, -1)` seta `vd.driver = src`; `Veh:onLeave` limpa |
| **`key_uid`** | Dono persistente da chave (UID livre — hash de item, uuid, etc.) | `vd.key_uid` + tabela `vh_vehicles(key_uid)` no banco | `Veh:transferKey(plate, new_key_uid)` muda; `vh/veh_set_key` persiste |
| **Network Owner** | FiveM entity owner (quem tem autoridade de posição) | Resolvido por `NetworkSetEntityOwner(ent, src)` | `Veh:onEnter` (driver→src) e `Veh:onLeave` (driver→próximo ocupante) |

### 3.2 Como ownership é transferida

#### Driver → src (em `Veh:onEnter`, server/vehicle.lua L158-180)
```lua
function Veh:onEnter(src, plate, netid, seat)
  -- ... registra em vd.occupants[src] = seat
  if seat == -1 then   -- DRIVER → becomes sole position authority
    vd.driver = src
    local ent = vd.netid and NetworkGetEntityFromNetworkId(vd.netid)
    if ent and ent ~= 0 then
      NetworkSetEntityOwner(ent, src)   -- GTA native: only driver writes pos
    end
    vHub.Kernel:emit(src, "vHub:vehicleStateLoad", plate, vd.state)
  else                 -- PASSENGER → passive, GTA delivers position
    vHub.Kernel:emit(src, "vHub:passengerMode", plate, true)
  end
  TriggerEvent("vHub:vehicleEnter", vd, src, seat)
end
```

#### Driver → próximo ocupante (em `Veh:onLeave`, L182-199)
```lua
function Veh:onLeave(src, plate, seat)
  -- ... remove de vd.occupants
  if seat == -1 and vd.driver == src then
    vd.driver = nil
    local next_src = next(vd.occupants)
    if next_src and vd.netid then
      local ent = NetworkGetEntityFromNetworkId(vd.netid)
      if ent and ent ~= 0 then NetworkSetEntityOwner(ent, next_src) end
    end
  else
    vHub.Kernel:emit(src, "vHub:passengerMode", plate, false)
  end
  TriggerEvent("vHub:vehicleLeave", vd, src, seat)
end
```

#### Transferência de key (ownership persistente)
```lua
function Veh:transferKey(plate, new_key_uid)
  plate = normalizePlate(plate)
  if not plate then return false end
  local vd = self._veh[plate]
  if not vd then
    vd = self:register(plate, nil)  -- registra sob demanda se não está em VRAM
  end
  if not vd then return false end
  if vd.key_uid then self._byKey[vd.key_uid] = nil end
  vd.key_uid = new_key_uid; vd.dirty = true
  if new_key_uid then self._byKey[new_key_uid] = plate end
  vHub.State:_queue({"vh/veh_set_key", {plate=plate, key_uid=new_key_uid}})
  TriggerEvent("vHub:vehicleKeyTransferred", vd, new_key_uid)
  return true
end
```

### 3.3 Lei do "escritor único" — como é enforceada

A regra é: **apenas o `driver` (motorista, seat=-1) pode reportar estado do veículo ao servidor**.

#### Client-side (client/vehicle.lua L72-75)
```lua
-- Enviar apenas se for driver: somente o motorista tem autoridade para reportar intent
if seat == -1 then
  TriggerServerEvent("vHub:vState", plate, payload)
end
```
O client descobre se é driver comparando `GetPedInVehicleSeat(veh, -1) == ped`.

#### Server-side (vehicle.lua L201-205)
```lua
function Veh:onStateUpdate(src, plate, upd)
  plate = normalizePlate(plate)
  if not plate or type(upd) ~= "table" then return end
  local vd = self._veh[plate]
  if not vd or vd.driver ~= src then return end   -- only driver authorized
  -- ... aplica update
end
```
O servidor valida `vd.driver == src` antes de aplicar qualquer update. Se o cliente não for o driver registrado, o update é silenciosamente descartado.

> ⚠️ **CAIXA PRETA — handlers DISARMED:** Os net events `vHub:vEnter`, `vHub:vLeave`, `vHub:vSpawned`, `vHub:vDespawned`, `vHub:vState` estão registrados em `boot.lua` L179-184 com corpo **NO-OP** (função `_vhDisarmed` vazia) por decisão #24 (N0-3, 2026-06-21, gate arquiteto+segurança). O comentário explica:
> ```
> Cadeia física do CORE DORMENTE por design desde a decisão #24 (verdade no
> prontuário vhub_vehicle_state do conce; emitters deletados do vhub_vehcontrol).
> Sem emissor legítimo, estes handlers eram superfície 100% hostil: um executor
> forjava vEnter/vSpawned com o netid da VÍTIMA → onEnter concedia
> NetworkSetEntityOwner(entidade_alheia, atacante) = sequestro de posição (grief).
> Mantidos REGISTRADOS (rate-limit + contrato de evento) com corpo NO-OP. NUNCA
> reanimar onEnter/onLeave/onStateUpdate/onSpawned sem novo gate (regra da #24).
> ```
> **Consequência prática:** `Veh:onEnter`, `Veh:onLeave`, `Veh:onStateUpdate`, `Veh:onSpawned`, `Veh:onDespawned` **EXISTEM** no código mas **nunca são chamados** por nenhum handler ativo. O client ainda envia `vHub:vState` a 4Hz, mas o server descarta silenciosamente. Os State Bags `vh_fuel/vh_eng/vh_body/vh_odo/vh_tune/vh_on` só são escritos quando `Veh:_syncBags` é chamado, e isso só acontece em `Veh:onSpawned` (que nunca é chamado) ou se um resource externo chamar `Veh:onSpawned`/`Veh:onStateUpdate` diretamente via `exports.vhub:getVHub().Vehicle`. **A cadeia de vehicle state está DORMENTE no CORE.**

---

## 4. Contratos Principais (Exports)

### 4.1 Exports registrados em `server/exports.lua` (via `K:export`)

Todos registrados via `AddEventHandler("__cfx_export_vhub_<name>", function(setCb) setCb(fn) end)`. Chamados externamente como `exports.vhub:<name>(...)`.

| Export | Assinatura | `_invoker_allowed()` | Descrição |
|--------|------------|----------------------|-----------|
| `getVHub` | `() → vHub table` | não | Retorna o namespace vHub completo (debug/avançado) |
| `getUser` | `(src: number) → User \| nil` | não | Objeto User da sessão: `{source, id, name, endpoint, char_id, spawns, data}` |
| `getUID` | `(src: number) → uid: number \| nil` | não | user_id do src ou nil se sem sessão |
| `hasPerm` | `(uid: number, perm: string) → boolean` | não | Consulta `K._perms[uid][perm]` (curinga `admin.*`) |
| `grantPerm` | `(uid: number, perm: string) → false \| void` | **sim** | Concede permissão em runtime |
| `getVehicle` | `(plate: string) → VehicleData \| nil` | não | Lookup direto em `Veh._veh[plate:upper()]` |
| `transferKey` | `(plate: string, key: string) → false \| true` | **sim** | Muda ownership persistente da chave (`Veh:transferKey`) |
| `getVehicleByKey` | `(key: string) → plate: string \| nil` | não | Resolve chave→placa (`Veh:byKey`, exige thread) |
| `banPlayer` | `(uid: number, reason: string, by: string) → false \| void` | **sim** | Ban permanente (`Auth:ban`) — dropa se online |
| `unbanPlayer` | `(uid: number) → false \| void` | **sim** | Remove ban (`Auth:unban`) |

#### `_invoker_allowed` (default-deny desde hotfix N0-2)
```lua
local function _invoker_allowed()
  local trust = vHub.cfg and vHub.cfg.trusted_resources
  if not trust or next(trust) == nil then
    -- N0-2: era return true (default-permissivo)
    return false  -- default-deny se trusted_resources VAZIO
  end
  local caller = GetInvokingResource()
  if not caller then return false end
  return trust[caller] == true
end
```

> ⚠️ **DISCREPÂNCIA README × CÓDIGO:** o `readme.md` Seção 13 ainda diz "Se `trusted_resources` está vazio, qualquer resource pode chamar exports sensíveis". Isso é **falso** desde o hotfix N0-2 — agora é default-deny. **O readme está desatualizado neste ponto.**

### 4.2 Exports adicionais em `bootstrap.lua`

Registrados via `exports("name", fn)` (sintaxe direta do fxmanifest):

| Export | Assinatura | Descrição |
|--------|------------|-----------|
| `API` | `() → vHub table` | Retorna `vHubRuntime` (mesma coisa que `getVHub`) |
| `Status` | `() → snapshot table` | Retorna snapshot de saúde |
| `Health` | `() → snapshot table` | Alias de `Status` |

Snapshot:
```lua
{
  recurso = RECURSO,
  pronto = Boot.pronto,           -- bool
  falha = Boot.falha,             -- código de falha ou nil
  uptime_ms = GetGameTimer() - Boot.inicio_ms,
  db_ready = state._ready,
  batch_pendente = state._batchN,
  sessoes = <count _sessions>,
  veiculos = <count _veh>,
  metricas = { batches, batch_falhas, batch_reenfileirados, ultima_latencia_db_ms },
  driver = { queries, transacoes, falhas, ultima_latencia_ms }
}
```

### 4.3 Exports em `server/init.lua`

| Export | Assinatura | Descrição |
|--------|------------|-----------|
| `registerStateDriver` | `(drv: table) → boolean` | Permite substituir o driver interno (oxmysql) por outro. Só aceita se `State._ready == false`. Valida `init/prepare/query/batch`. |
| `getVHub` | `() → vHub table` | Acesso ao namespace (duplicado do exports.lua) |

### 4.4 Contratos mencionados no enunciado da tarefa — VERIFICAÇÃO

A tarefa pedia citar especialmente `commitVehicleState()`, `getVehicleState()`, `createVehicle()`, `spawnVehicle()`, `deleteVehicle()`, `despawnVehicle()`, `setVehicleDriver()`, `getVehicleDriver()`, `transferOwnership()`. **Estes nomes NÃO EXISTEM no CORE.** Os contratos reais são:

| Contrato esperado (tarefa) | Real no CORE | Observação |
|----------------------------|--------------|------------|
| `commitVehicleState()` | `vHub.setVData(plate, "state", vd.state)` (em `Veh:_save`) | Persiste `vd.state` no KV `vh_vehicle_data` |
| `getVehicleState()` | `vHub.getVData(plate, "state")` OU acesso direto `vd.state` | Leitura do KV ou do objeto vivo |
| `createVehicle()` | `Veh:register(plate, key_uid)` | Cria VehicleData em VRAM (NÃO spawna entidade) |
| `spawnVehicle()` | `Veh:onSpawned(plate, netid)` | Notifica que entidade existe; chamado por resource externo |
| `deleteVehicle()` | `Veh:unregister(plate)` | Salva + remove da VRAM (NÃO despawna entidade) |
| `despawnVehicle()` | `Veh:onDespawned(plate)` | Notifica despawn; chamado por resource externo |
| `setVehicleDriver()` | `vd.driver = src` (em `Veh:onEnter`) | Atribuição direta; não é export |
| `getVehicleDriver()` | `vd.driver` (acesso direto ao campo) | Não é export |
| `transferOwnership()` | `Veh:transferKey(plate, new_key_uid)` | Renomeado para transferKey; export com whitelist |

> 🔑 **Conclusão:** o CORE usa uma API de **verbos imperativos (`onSpawned`, `onDespawned`, `onEnter`, `onLeave`, `onStateUpdate`)** que modelam eventos do ciclo de vida do veículo, e a persistência é feita via API KV genérica (`getVData`/`setVData`). Não há uma API "vehicle-state-specific" nomeada como `commitVehicleState`.

---

## 5. Eventos (NetEvents, ClientEvents)

### 5.1 Constantes em `shared/events.lua` (`vHub.E.*`)

Tabela read-only (metatable bloqueia `__newindex`):
```lua
-- Net events cliente → servidor
NET_READY        = "vHub:ready"
NET_DIED         = "vHub:died"
NET_V_SPAWNED    = "vHub:vSpawned"
NET_V_DESPAWNED  = "vHub:vDespawned"
NET_V_ENTER      = "vHub:vEnter"
NET_V_LEAVE      = "vHub:vLeave"
NET_V_STATE      = "vHub:vState"
NET_SELECT_CHAR  = "vHub:selectChar"

-- Eventos server-side (TriggerEvent local)
EVT_PLAYER_JOIN   = "vHub:playerJoin"
EVT_PLAYER_LEAVE  = "vHub:playerLeave"
EVT_PLAYER_SPAWN  = "vHub:playerSpawn"
EVT_PLAYER_DEATH  = "vHub:playerDeath"
EVT_CHAR_LOAD     = "vHub:characterLoad"

-- Eventos cliente-bound (servidor → cliente)
CLI_INIT_DONE    = "vHub:initDone"
CLI_CHAR_SEL     = "vHub:charSelected"
CLI_CHAR_FAIL    = "vHub:charSelectFailed"
```

### 5.2 Net events registrados via `K:net` (boot.lua)

Todos têm `RegisterNetEvent` automático, validação `src > 0`, `checkPayload`, rate-limit e dispatch protegido por `pcall`.

| Evento | Lado | Rate limit | Handler | Estado |
|--------|------|------------|---------|--------|
| `vHub:ready` | client→server | `{5, 15000, 60000}` (5/15s, block 60s) | `boot.lua` L79-147 | **ATIVO** — ponto único de autenticação (`Auth:connect`) |
| `vHub:died` | client→server | `{5, 20000, 30000}` (5/20s, block 30s) | `boot.lua` L150-157 | ATIVO — reseta `last_position`/`last_health` |
| `vHub:selectChar` | client→server | `{3, 10000, 30000}` (3/10s, block 30s) | `boot.lua` L160-166 | ATIVO — `Auth:selectCharacter` |
| `vHub:vSpawned` | client→server | `{15, 5000, 15000}` | `_vhDisarmed` (NO-OP) | **DORMENTE** |
| `vHub:vDespawned` | client→server | `{15, 5000, 15000}` | `_vhDisarmed` (NO-OP) | **DORMENTE** |
| `vHub:vEnter` | client→server | `{10, 3000, 10000}` | `_vhDisarmed` (NO-OP) | **DORMENTE** |
| `vHub:vLeave` | client→server | `{10, 3000, 10000}` | `_vhDisarmed` (NO-OP) | **DORMENTE** |
| `vHub:vState` | client→server | `{8, 1000, 5000}`, `async=false` | `_vhDisarmed` (NO-OP) | **DORMENTE** — client ainda envia, server descarta |

#### Payload do `vHub:ready` (client→server)
Sem payload. Apenas o `src` é usado.

#### Payload do `vHub:vState` (client→server)
```lua
TriggerServerEvent("vHub:vState", plate, {
  rpm = <0..1>,
  engine_health = <0..1000>,
  body_health = <0..1000>,
  engine_on = <bool>,
  odometer_delta = <km float>,
})
```
Cadência adaptativa: 0.5Hz parado, 1Hz idle, 4Hz dirigindo.

#### Payload do `vHub:died`
Sem payload.

#### Payload do `vHub:selectChar`
`cid: number` (char_id desejado).

### 5.3 Eventos server-local (`TriggerEvent`) emitidos pelo CORE

| Evento | Emitido em | Payload | Quem escuta (resources externos) |
|--------|------------|---------|----------------------------------|
| `vHub:playerJoin` | `auth.lua:connect` L241 | `(user)` | Resources que populam sessões locais |
| `vHub:playerLeave` | `auth.lua:disconnect` L250 | `(user, reason)` | Limpeza de sessões |
| `vHub:playerSpawn` | `boot.lua` L88, L142 | `(user, primeiro_spawn: bool)` | Spawn físico (vhub_player_state), HUDs |
| `vHub:playerDeath` | `boot.lua` L155 | `(user)` | Death handling |
| `vHub:characterLoad` | `auth.lua:selectCharacter` L325, `boot.lua` L125/L135 | `(user)` | Carregar dados de personagem |
| `vHub:vehicleLoaded` | `vehicle.lua:register` L92 | `(vd)` | Resources que dependem de veículo registrado |
| `vHub:vehicleSpawned` | `vehicle.lua:onSpawned` L142 | `(vd)` | HUDs, fuel systems |
| `vHub:vehicleDespawned` | `vehicle.lua:onDespawned` L155 | `(vd)` | Cleanup |
| `vHub:vehicleEnter` | `vehicle.lua:onEnter` L179 | `(vd, src, seat)` | ocupantes |
| `vHub:vehicleLeave` | `vehicle.lua:onLeave` L198 | `(vd, src, seat)` | |
| `vHub:vehicleKeyTransferred` | `vehicle.lua:transferKey` L119 | `(vd, new_key_uid)` | Atualizar chaves em inventário |
| `vHub:vehicleFuelEmpty` | `vehicle.lua:onStateUpdate` L216 | `(vd, src)` | Engine cutoff |

### 5.4 Eventos server→client (`K:emit` / `TriggerClientEvent`)

| Evento | Emitido em | Payload | Registrado no client? |
|--------|------------|---------|----------------------|
| `vHub:initDone` | `boot.lua` L89, L143 | `(user_id, char_id, primeiro_spawn)` | ✅ `client/bootstrap.lua:101` |
| `vHub:charSelected` | `auth.lua:selectCharacter` L326 | `(char_id)` | ✅ `client/bootstrap.lua:119` |
| `vHub:charSelectFailed` | `boot.lua` L164 | `(reason: string)` | ✅ `client/bootstrap.lua:127` |
| `vHub:vehicleStateLoad` | `vehicle.lua:onEnter` L175 | `(plate, state)` | ✅ `client/vehicle.lua:21` |
| `vHub:passengerMode` | `vehicle.lua:onEnter` L177 / `onLeave` L196 | `(plate, bool)` | ❌ **NÃO registrado no client** |

### 5.5 Eventos client-local (`TriggerEvent` no client)

| Evento | Emitido em | Payload |
|--------|------------|---------|
| `vHub:localReady` | `client/bootstrap.lua:114` | `(uid, cid, primeiro_spawn)` |
| `vHub:localCharSelected` | `client/bootstrap.lua:124` | `(cid)` |
| `vHub:localCharFailed` | `client/bootstrap.lua:129` | `(reason)` |

### 5.6 Segurança (validação de source, anti-spoofing)

- **`K:net`** rejeita `src <= 0` (eventos do servidor ou sources inválidas) — `kernel.lua` L27.
- **`checkPayload`** rejeita payloads > `max_payload` (default 8192 bytes) — `security.lua:checkPayload`.
- **Rate limit** por `src:action` — bloqueia após exceder (silencioso).
- **Permission guard** opcional via `opts.perm` ou `opts.admin`.
- **`pcall`** em todos os handlers — erros nunca crasham o servidor.
- **`vHub:ready`** é o **único ponto de autenticação**. `playerConnecting` faz apenas `deferrals.done()` — comentário em `boot.lua` L67-69 explica: "Fazer Auth:connect aqui causava double-connect e criação duplicada de user."
- **`Auth:connect`** tem guard de sessão dupla: `if self._sessions[src] then return self._sessions[src] end` — L177-180.

---

## 6. Callbacks

**NÃO HÁ callbacks tradicionais no CORE.** Não há uso de:
- `lib.callback` / `ox_lib.callback`
- `RegisterNUICallback`
- `RegisterServerCallback` / `TriggerCallback`

Toda comunicação client→server é **assíncrona via eventos** (`TriggerServerEvent` + `K:net`). Toda comunicação cross-resource é **via exports** (`K:export` / `__cfx_export_*`).

> 🔍 **Observação:** o `vHub.Kernel:export` é o mecanismo mais próximo de "callback":
> ```lua
> function K:export(name, fn)
>   AddEventHandler("__cfx_export_" .. GetCurrentResourceName() .. "_" .. name,
>     function(setCb) setCb(fn) end)
> end
> ```
> Quando um resource externo chama `exports.vhub:getUID(src)`, o FiveM dispara esse handler interno, que registra `fn` no registry do exports. Não é um callback no sentido tradicional (não há round-trip de resposta), mas sim um mecanismo de lookup de função.

---

## 7. SQL Schema

### 7.1 Tabelas criadas em `sql/schema.sql` (8 tabelas)

Engine: InnoDB · Charset: utf8mb4 · Collation: utf8mb4_unicode_ci · Idempotente (`CREATE TABLE IF NOT EXISTS`).

#### 7.1.1 `vh_users` — usuário (entidade-pai)
```sql
CREATE TABLE IF NOT EXISTS vh_users (
  id          INT UNSIGNED NOT NULL AUTO_INCREMENT
              COMMENT 'PK alocada server-side ou AUTO_INCREMENT',
  created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
              ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id)
);
```
- **Quem escreve:** `vh/create_user_with_id` (alocador server-side, INSERT IGNORE), `vh/create_user` (fallback AUTO_INCREMENT).
- **Quem lê:** `vh/max_userid` (seed do alocador).
- **Sem FK.** É a raiz da hierarquia.

#### 7.1.2 `vh_user_ids` — identifiers FiveM → user_id
```sql
CREATE TABLE IF NOT EXISTS vh_user_ids (
  identifier  VARCHAR(64)  NOT NULL,
  user_id     INT UNSIGNED NOT NULL,
  created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (identifier),
  KEY idx_vh_user_ids_user_id (user_id),
  CONSTRAINT fk_vh_user_ids_user
    FOREIGN KEY (user_id) REFERENCES vh_users(id)
    ON DELETE CASCADE ON UPDATE CASCADE
);
```
- **Quem escreve:** `vh/add_id` (INSERT IGNORE, em `Auth:_resolveUID` L102/L160).
- **Quem lê:** `vh/uid_by_id` (1 identifier), `vh/uid_by_ids_in_<N>` (N identifiers, query dinâmica em `vHub.SQL.uidByIdsIn(n)`).

#### 7.1.3 `vh_characters` — personagens por usuário
```sql
CREATE TABLE IF NOT EXISTS vh_characters (
  id          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id     INT UNSIGNED NOT NULL,
  created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
              ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_vh_characters_user_id (user_id),
  CONSTRAINT fk_vh_characters_user
    FOREIGN KEY (user_id) REFERENCES vh_users(id)
    ON DELETE CASCADE ON UPDATE CASCADE
);
```
- **Quem escreve:** `vh/create_char_with_id` (alocador), `vh/create_char` (fallback).
- **Quem lê:** `vh/get_chars` (lista por user_id), `vh/max_charid` (seed).
- **Quem deleta:** `vh/delete_char` (valida `id AND user_id`).

#### 7.1.4 `vh_user_data` — KV por usuário
```sql
CREATE TABLE IF NOT EXISTS vh_user_data (
  user_id     INT UNSIGNED NOT NULL,
  dkey        VARCHAR(64)  NOT NULL,
  dvalue      BLOB         -- msgpack binário, máx 64KB (pós-freeze v1.0)
  updated_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
              ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, dkey),
  CONSTRAINT fk_vh_user_data_user
    FOREIGN KEY (user_id) REFERENCES vh_users(id)
    ON DELETE CASCADE ON UPDATE CASCADE
);
```
- **Quem escreve:** `vh/set_ud` (REPLACE INTO) — usado por `vHub.setUData`.
- **Quem lê:** `vh/get_ud` (SELECT dvalue) — usado por `vHub.getUData`.
- **Chaves típicas:** `datatable`, `ban.active`, `ban.reason`, `ban.by`, `whitelist`, `permissions`, `last_login`, `current_login`, `last_character`, `is_owner`.

#### 7.1.5 `vh_char_data` — KV por personagem
```sql
CREATE TABLE IF NOT EXISTS vh_char_data (
  char_id     INT UNSIGNED NOT NULL,
  dkey        VARCHAR(64)  NOT NULL,
  dvalue      BLOB,
  updated_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
              ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (char_id, dkey),
  CONSTRAINT fk_vh_char_data_char
    FOREIGN KEY (char_id) REFERENCES vh_characters(id)
    ON DELETE CASCADE ON UPDATE CASCADE
);
```
- **Quem escreve:** `vh/set_cd` — `vHub.setCData`.
- **Quem lê:** `vh/get_cd` — `vHub.getCData`.

#### 7.1.6 `vh_global_data` — KV global do servidor
```sql
CREATE TABLE IF NOT EXISTS vh_global_data (
  dkey        VARCHAR(64)  NOT NULL,
  dvalue      BLOB,
  updated_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
              ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (dkey)
);
```
- **Sem FK** (dados independentes).
- **Quem escreve:** `vh/set_gd` — `vHub.setGData`.
- **Quem lê:** `vh/get_gd` — `vHub.getGData`.

#### 7.1.7 `vh_vehicles` — registro físico de veículo
```sql
CREATE TABLE IF NOT EXISTS vh_vehicles (
  plate       VARCHAR(10)  NOT NULL,
  key_uid     VARCHAR(64)  DEFAULT NULL,
  created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
              ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (plate),
  KEY idx_vh_vehicles_key_uid (key_uid)
);
```
- **Sem FK em `key_uid`** — pode apontar para entidade externa (uuid, hash de item).
- **Quem escreve:** `vh/veh_create` (INSERT IGNORE), `vh/veh_set_key` (UPDATE — usado em `transferKey`).
- **Quem lê:** `vh/veh_key` (por plate), `vh/veh_by_key` (por key_uid — usado em `Veh:byKey`).
- **Comentário no schema:** "Negócio (owner, status, IPVA, leilão) fica em `vhub_garage`."

#### 7.1.8 `vh_vehicle_data` — KV por placa
```sql
CREATE TABLE IF NOT EXISTS vh_vehicle_data (
  plate       VARCHAR(10)  NOT NULL,
  dkey        VARCHAR(64)  NOT NULL,
  dvalue      BLOB,
  updated_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
              ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (plate, dkey),
  CONSTRAINT fk_vh_vehicle_data_vehicle
    FOREIGN KEY (plate) REFERENCES vh_vehicles(plate)
    ON DELETE CASCADE ON UPDATE CASCADE
);
```
- **Quem escreve:** `vh/set_vd` — `vHub.setVData`.
- **Quem lê:** `vh/get_vd` — `vHub.getVData`.
- **Chaves típicas:** `state` (table completa: fuel, engine_health, body_health, damage, tuning, garage, last_pos, odometer, engine_on), `tuning`, `damage`.

> ⚠️ **Hotfix 2026-06-04 documentado no `sql.lua` L101-104:** as queries `vh/set_vd` e `vh/get_vd` usavam `@dkey` mas o `_set/_get` compartilhado em `state.lua` sempre liga o parâmetro como `key`. Com `@dkey` o bind ficava nulo → escrita falhava ("Column 'dkey' cannot be null") e leitura filtrava `dkey=NULL` (nunca casava) → `vh_vehicle_data` ficou **morto desde o freeze**. Alinhado a `@key` no hotfix.

### 7.2 Queries registradas em `server/sql.lua` (lista completa)

```lua
-- Usuários
S:prepare("vh/create_user_with_id",
  "INSERT IGNORE INTO vh_users(id, created_at) VALUES(@id, NOW())")
S:prepare("vh/create_user",
  "INSERT INTO vh_users(created_at) VALUES(NOW())")
S:prepare("vh/max_userid",
  "SELECT COALESCE(MAX(id), 0) AS maxid FROM vh_users")
S:prepare("vh/last_insert_id",
  "SELECT LAST_INSERT_ID() AS id")
S:prepare("vh/add_id",
  "INSERT IGNORE INTO vh_user_ids(identifier, user_id) VALUES(@identifier, @user_id)")
S:prepare("vh/uid_by_id",
  "SELECT user_id FROM vh_user_ids WHERE identifier = @identifier")

-- Query dinâmica lazy-cached para N identifiers
function vHub.SQL.uidByIdsIn(n)
  local name = "vh/uid_by_ids_in_" .. tostring(n)
  if not S._prepared[name] then
    local qs = {}
    for i = 1, n do qs[i] = "?" end
    S:prepare(name,
      "SELECT identifier, user_id FROM vh_user_ids WHERE identifier IN ("..table.concat(qs,",")..")")
  end
  return name
end

-- Personagens
S:prepare("vh/max_charid",
  "SELECT COALESCE(MAX(id), 0) AS maxid FROM vh_characters")
S:prepare("vh/create_char_with_id",
  "INSERT IGNORE INTO vh_characters(id, user_id, created_at) VALUES(@id, @user_id, NOW())")
S:prepare("vh/create_char",
  "INSERT INTO vh_characters(user_id, created_at) VALUES(@user_id, NOW())")
S:prepare("vh/get_chars",
  "SELECT id FROM vh_characters WHERE user_id = @user_id ORDER BY id")
S:prepare("vh/delete_char",
  "DELETE FROM vh_characters WHERE id = @id AND user_id = @user_id")

-- Dados KV (user / char / global)
S:prepare("vh/set_ud",
  "REPLACE INTO vh_user_data(user_id, dkey, dvalue) VALUES(@user_id, @key, @value)")
S:prepare("vh/get_ud",
  "SELECT dvalue FROM vh_user_data WHERE user_id = @user_id AND dkey = @key")
S:prepare("vh/set_cd",
  "REPLACE INTO vh_char_data(char_id, dkey, dvalue) VALUES(@char_id, @key, @value)")
S:prepare("vh/get_cd",
  "SELECT dvalue FROM vh_char_data WHERE char_id = @char_id AND dkey = @key")
S:prepare("vh/set_gd",
  "REPLACE INTO vh_global_data(dkey, dvalue) VALUES(@dkey, @value)")
S:prepare("vh/get_gd",
  "SELECT dvalue FROM vh_global_data WHERE dkey = @dkey")

-- Veículos
S:prepare("vh/veh_create",
  "INSERT IGNORE INTO vh_vehicles(plate, key_uid) VALUES(@plate, @key_uid)")
S:prepare("vh/veh_set_key",
  "UPDATE vh_vehicles SET key_uid = @key_uid WHERE plate = @plate")
S:prepare("vh/veh_key",
  "SELECT key_uid FROM vh_vehicles WHERE plate = @plate")
S:prepare("vh/veh_by_key",
  "SELECT plate FROM vh_vehicles WHERE key_uid = @key_uid")
S:prepare("vh/set_vd",
  "REPLACE INTO vh_vehicle_data(plate, dkey, dvalue) VALUES(@plate, @key, @value)")
S:prepare("vh/get_vd",
  "SELECT dvalue FROM vh_vehicle_data WHERE plate = @plate AND dkey = @key")
```

### 7.3 Pré-requisito obrigatório do oxmysql

`bootstrap.lua` L187-190 valida:
```lua
if not conexao:lower():find("multiplestatements=true", 1, true) then
  logar("ERROR", "mysql_connection_string sem multipleStatements=true")
  return false
end
```
Necessário porque `aplicar_schema` envia o `schema.sql` inteiro como UMA query multi-statement via `driver:_executar("query", schema, {})`.

---

## 8. Security Model

### 8.1 `server/security.lua` — helpers

#### `Sec:requireAdmin(src, action)` → boolean
```lua
function Sec:requireAdmin(src, action)
  if IsPlayerACEAllowed and IsPlayerAceAllowed(src, "vhub.admin") then return true end
  local uid = vHub.Auth:getUID(src)
  if uid and vHub.Kernel:hasPerm(uid, "admin." .. action) then return true end
  self:_permFail(src, "admin." .. action, action)
  return false
end
```
Dupla verificação: **ACE nativo do FiveM** (configurado em `server.cfg` via `add_ace`) tem prioridade; depois **permissão interna** em `K._perms[uid]`. `admin.*` é curinga.

#### `Sec:_permFail(src, event, perm)` → void
```lua
function Sec:_permFail(src, event, perm)
  vHub.Logger:warn("security", ("src=%d sem permissão '%s'"):format(src, tostring(perm)))
  vHub.Notify:send("security",
    ("🚨 Acesso negado | src:`%d` perm:`%s`"):format(src, tostring(perm)))
end
```
**Não kicka** o jogador (silencioso por design — kick daria informação ao atacante).

#### `Sec:checkPayload(src, event, size)` → boolean
```lua
function Sec:checkPayload(src, event, size)
  if size > (vHub.cfg.max_payload or 8192) then
    vHub.Logger:warn("security", ("Payload grande src=%d evt=%s"):format(src, tostring(event)), {size=size})
    return false
  end
  return true
end
```
Proteção contra flood via payloads grandes. **Não valida conteúdo** — cada handler é responsável por validar tipos/ranges.

#### Validators de TX (default pass-through)
```lua
vHub.State:addValidator(function(tx, snap, mem) return true end)
```
Recursos externos podem adicionar validators via `vHub.State:addValidator(fn)` onde `fn(tx, snap, mem) → true | false, "reason"`.

### 8.2 Anti-cheat / anti-spoofing no `K:net`

```lua
function K:net(name, handler, opts)
  RegisterNetEvent(name)
  AddEventHandler(name, function(...)
    local src = source
    if (not src) or src <= 0 then return end   -- reject server/invalid
    -- 1. Payload size check (msgpack preferido, json fallback)
    local payload_size = ...
    if vHub.Security and not vHub.Security:checkPayload(src, name, payload_size) then return end
    -- 2. Rate limit
    if opts.rate then
      if not self:_rateOK(src, name, opts.rate[1], opts.rate[2], opts.rate[3]) then
        -- silent: nunca avisar o cliente que foi bloqueado
        return
      end
    end
    -- 3. Permission guard
    local perm = opts.perm or (opts.admin and "admin.*")
    if perm then
      local uid = vHub.Auth:getUID(src)
      if not uid or not self:hasPerm(uid, perm) then
        vHub.Security:_permFail(src, name, perm); return
      end
    end
    -- 4. Protected dispatch — errors never crash the server
    if opts.async == false then
      local ok, err = pcall(handler, src, table.unpack(args))
    else
      Citizen.CreateThread(function()
        local ok, err = pcall(handler, src, table.unpack(args))
      end)
    end
  end)
end
```

### 8.3 `_invoker_allowed` — whitelist de exports

**Default-deny** (hotfix N0-2): se `trusted_resources` está vazio ou nil, exports sensíveis são **NEGADOS**. Se populado, apenas resources na lista podem chamar.

```lua
local function _invoker_allowed()
  local trust = vHub.cfg and vHub.cfg.trusted_resources
  if not trust or next(trust) == nil then
    -- warn uma vez
    return false  -- N0-2: era return true (default-permissivo)
  end
  local caller = GetInvokingResource()
  if not caller then return false end  -- N0-2: era return true
  return trust[caller] == true
end
```

> ⚠️ **Atenção:** `criar_config` em `bootstrap.lua` **NÃO** popula `trusted_resources`. Ele fica nil em `vHub.cfg`. Para os exports sensíveis funcionarem, um resource externo (ou convar) deve popular `vHub.cfg.trusted_resources = { vhub_admin = true, vhub_garage = true, ... }` em runtime. Sem isso, todos os exports privilegiados retornam `false` silenciosamente.

### 8.4 Lei do "escritor único" do estado de veículo

- Apenas `vd.driver == src` pode chamar `Veh:onStateUpdate` com sucesso (L205).
- Client só envia `vHub:vState` se `seat == -1` (client/vehicle.lua L73).
- Odometer delta é clampado server-side: `applied = math.min(odometer_delta, math.max(0.0001, max_delta), 0.5)` onde `max_delta = rpm * max_speed_kmh * time_per_tick / 3600` — anti-cheat para odômetro inflado.
- Fuel é computado **server-side**: `s.fuel = math.max(0, s.fuel - rpm * (vHub.cfg.fuel_rate or 0.005))` — client não reporta fuel, só RPM.

### 8.5 Boot validation (em `bootstrap.lua`)

Sequência de validações em `iniciar()` (L410-431):
1. `validar_driver(driver)` — verifica `init/prepare/query/batch` no driver.
2. `carregar_base()` — `base.lua` compila e executa via `pcall`.
3. `validar_base(vhub)` — verifica símbolos obrigatórios: `init` (function), `State/Kernel/Auth/Vehicle/Security/Notify` (table).
4. `vHubRuntime:init(config, driver)` — chama `boot.lua:vHub:init`.
5. `if not vHubRuntime.State._ready then falhar("db_indisponivel", ...)` — verifica DB conectado.
6. `aplicar_schema(driver)` — executa `sql/schema.sql` (falha se DB indisponível ou sem `multipleStatements=true`).

E em `Driver:init` (bootstrap.lua L173-205):
- Verifica `GetResourceState("oxmysql") == "started"`.
- Verifica `mysql_connection_string` não vazio.
- Verifica `multipleStatements=true` na connection string.
- Verifica `exports.oxmysql` é table.
- Faz ping SQL: `SELECT 1` → espera `1`.

Se qualquer passo falhar, `falhar()` é chamado, que seta `Boot.pronto = false`, `Boot.falha = codigo`, loga FATAL e lança `error()` — impedindo o resource de iniciar.

---

## 9. Boot & Init Flow

### 9.1 Ordem exata de boot no SERVER

```
[Fase 1 — runtime FiveM carrega shared_scripts]
1. shared/config.lua    → rawset(_G, "vHub", {}) se não existe
                         define vHub.mergeConfig, vHub.validateConfig, vHub._normLevel
                         _defaults table (NUNCA aplicado automaticamente)
2. shared/events.lua    → vHub.E = setmetatable({}, read-only)
3. shared/utils.lua     → vHub.Utils (formatNumber, formatTime, clamp, tableSize,
                         normalizePlate, shallowCopy, dataCopy)
4. shared/logger.lua    → vHub.Logger:debug/info/warn/error

[Fase 2 — runtime FiveM carrega server_scripts]
5. bootstrap.lua        → (único server_script declarado)
   a. criar_config()    → lê convars
   b. criar_driver()    → instancia driver oxmysql interno
   c. validar_driver()  → verifica contrato init/prepare/query/batch
   d. carregar_base()   → LoadResourceFile("base.lua") + load() + pcall
   e. base.lua          → verifica _server_ready flag
                         LoadResourceFile("server/init.lua") + load() + pcall
   f. server/init.lua   → pega vHub dos shared (rawget(_G, "vHub"))
                         define vHub.class(), vHub.assertThread(), loadmod()
                         loadmod("server/kernel.lua")
                         loadmod("server/state.lua")
                         loadmod("server/sql.lua")
                         loadmod("server/notify.lua")
                         loadmod("server/auth.lua")
                         loadmod("server/vehicle.lua")
                         loadmod("server/security.lua")
                         loadmod("server/boot.lua")
                         loadmod("server/exports.lua")
                         exports("registerStateDriver", ...)
                         exports("getVHub", ...)
                         return vHub
   g. validar_base()    → verifica init/State/Kernel/Auth/Vehicle/Security/Notify
   h. vHubRuntime:init(cfg, driver) → boot.lua:vHub:init()
      - normaliza log_level
      - vHub.State:setDriver(driver)
        → driver:init(cfg.db) [valida oxmysql started, connection string,
          multipleStatements=true, ping SELECT 1]
        → aplica _cprepare enfileirados
        → dispara _cquery enfileirados
        → S._ready = true
        → Citizen.CreateThread → S:query("vh/max_userid") → vHub._next_user_id
        → Citizen.CreateThread → S:query("vh/max_charid") → vHub._next_char_id
      - AddEventHandler("onResourceStop") → flush de emergência chunked
      - AddEventHandler("onResourceStart") → replay de sessões (200ms delay)
      - AddEventHandler("playerDropped") → Auth:disconnect + GC _rate
      - AddEventHandler("playerConnecting") → apenas deferrals.done()
      - K:net("vHub:ready") → Auth:connect
      - K:net("vHub:died") → reseta last_position
      - K:net("vHub:selectChar") → Auth:selectCharacter
      - K:net("vHub:vSpawned") → _vhDisarmed (NO-OP)
      - K:net("vHub:vDespawned") → _vhDisarmed
      - K:net("vHub:vEnter") → _vhDisarmed
      - K:net("vHub:vLeave") → _vhDisarmed
      - K:net("vHub:vState", async=false) → _vhDisarmed
      - SetTimeout(autosave) → doSave() periódico
      - if ping_check_enabled → Citizen.CreateThread ping check
   i. if not vHubRuntime.State._ready → falhar("db_indisponivel")
   j. aplicar_schema(driver) → driver:_executar("query", schema_sql, {})
   k. Boot.pronto = true
   l. exports("API"/"Status"/"Health") já registrados acima
   m. RegisterCommand("vhub_status") → logs snapshot (console only)
   n. AddEventHandler("onResourceStop") para flush final (em bootstrap.lua)
```

### 9.2 Ordem exata de boot no CLIENT

```
[Fase 1 — runtime carrega shared_scripts]
(igual ao server — config.lua, events.lua, utils.lua, logger.lua)

[Fase 3 — runtime carrega client_scripts]
1. client/bootstrap.lua
   - Define SPAWN_POS, SPAWN_MODEL, FALLBACK_WINDOW_MS=60000,
     FALLBACK_DELAY_MS=2000, DEBOUNCE_MS=5000
   - AddEventHandler("playerSpawned", enviarReady)
   - Citizen.CreateThread (fallback monitor)
     por 60s: se NetworkIsPlayerActive() e _ultimo_ready <= 0
       Wait(2s), spawnNativo(), enviarReady()
   - Citizen.CreateThread (retry 15s)
     se _init_done == false: reenvia ready
   - RegisterNetEvent("vHub:initDone") → seta State Bags locais + TriggerEvent("vHub:localReady")
   - RegisterNetEvent("vHub:charSelected") → seta vhub_char_id + TriggerEvent("vHub:localCharSelected")
   - RegisterNetEvent("vHub:charSelectFailed") → TriggerEvent("vHub:localCharFailed")
2. client/vehicle.lua
   - RegisterNetEvent("vHub:vehicleStateLoad") → aplica state ao veículo local
   - Citizen.CreateThread (loop report adaptativo 0.5/1/4Hz)
     se for driver: TriggerServerEvent("vHub:vState", plate, payload)
```

### 9.3 Quando o CORE está "ready" para outros recursos

**Server-side:** o CORE está pronto quando:
1. `Boot.pronto == true` (após `aplicar_schema` em `bootstrap.lua:iniciar()`)
2. `vHub.State._ready == true` (após `setDriver` conectar ao banco)
3. `vHub._next_user_id` e `vHub._next_char_id` populados (em threads, alguns ms depois)

Resources externos podem checar via `exports.vhub:Status().pronto` ou `exports.vhub:Health().db_ready`.

**Client-side:** o CORE está pronto quando recebe `vHub:initDone` (dispara `vHub:localReady`). Antes disso, o jogador não tem uid/char_id nas State Bags locais.

> 🔑 **Ordem de dependência para spawn:** `vhub` (core) → `vhub_player_state` (spawn) → outros resources. O `vhub_player_state` escuta `vHub:characterLoad` e aplica spawn físico; sem ele, o fallback nativo do `client/bootstrap.lua` spawna em posição hard-coded.

---

## 10. Replay-Safety & Persistence

### 10.1 Como autosave funciona

`boot.lua` L186-201:
```lua
local function doSave()
  local n_sess = 0
  for _, user in pairs(vHub.Auth._sessions) do
    n_sess = n_sess + 1
    vHub.setUData(user.id, "datatable", vHub.Utils.dataCopy(user.data))
    if n_sess % 50 == 0 then Citizen.Wait(0) end  -- yield a cada 50
  end
  vHub.Vehicle:saveAll()
  vHub.State:_flush()
  vHub.Logger:info("boot",
    ("autosave — %d sessão(ões), %d veículo(s)"):format(
      n_sess, vHub.Utils.tableSize(vHub.Vehicle._veh)))
  SetTimeout((vHub.cfg.save_interval or 60) * 1000, doSave)
end
SetTimeout((vHub.cfg.save_interval or 60) * 1000, doSave)
```

- Persiste `datatable` de cada user (cópia profunda via `dataCopy` — evita acúmulo).
- `Veh:saveAll()` itera `_veh` e salva os `dirty`.
- `State:_flush()` dispara o batch SQL.
- Yield a cada 50 sessões evita stall (importante para 200+ players).
- Recursivo via `SetTimeout`.

### 10.2 O que acontece em resource restart

#### `onResourceStop` (boot.lua L17-29)
```lua
AddEventHandler("onResourceStop", function(res)
  if res ~= _RES then return end
  vHub.Logger:warn("boot", "Resource encerrando — flush de emergência...")
  local i = 0
  for _, user in pairs(vHub.Auth._sessions) do
    i = i + 1
    vHub.setUData(user.id, "datatable", vHub.Utils.dataCopy(user.data))
    if i % 50 == 0 then Citizen.Wait(0) end
  end
  vHub.Vehicle:saveAll()
  vHub.State:_flush()
  vHub.Logger:warn("boot", "Flush de emergência concluído.")
end)
```

#### `onResourceStop` (bootstrap.lua L388-408) — flush final
```lua
AddEventHandler("onResourceStop", function(resource)
  if resource == "oxmysql" and Boot.pronto then
    Boot.pronto = false
    Boot.falha = "oxmysql_parado"
  end
  if resource == RECURSO and vHubRuntime and vHubRuntime.State then
    local State = vHubRuntime.State
    if State._batchN > 0 and State._ready then
      local operacoes, total = State._batch, State._batchN
      State._batch, State._batchN = {}, 0
      local ok, resultado = pcall(State._driver.batch, State._driver, operacoes, total)
      if not ok or resultado == false then
        logar("ERROR", "flush final falhou", ...)
      else
        logar("INFO", "flush final concluido", {total = total})
      end
    end
  end
end)
```

#### `onResourceStart` (boot.lua L35-44) — replay de sessões
```lua
AddEventHandler("onResourceStart", function(res)
  if res == _RES then return end  -- ignora self
  SetTimeout(200, function()
    for _, user in pairs(vHub.Auth._sessions) do
      TriggerEvent("vHub:characterLoad", user)
      TriggerEvent("vHub:playerSpawn",   user, false)
    end
  end)
end)
```

Quando um resource externo reinicia com jogadores online, seus handlers de `vHub:characterLoad`/`playerSpawn` foram registrados depois dos eventos já terem disparado. O CORE re-dispara os eventos para todos os jogadores ativos após 200ms (delay dá tempo de registrar handlers).

### 10.3 Restauração após crash

- **VRAM é lost** em crash (memória). Banco é fonte de verdade persistente.
- Em reboot: `State:setDriver` dispara seeds `vh/max_userid` e `vh/max_charid` → `_next_user_id = MAX(id)+1`.
- Jogadores reconectam → `Auth:connect` → `_resolveUID` encontra identifiers no banco → recria User com mesmo uid.
- `user.data` (datatable) é recarregado via `vHub.getUData(uid, "datatable")`.
- `vd.state` (vehicle state) é recarregado em `Veh:register` via `vHub.getVData(plate, "state")`.

### 10.4 "Replay-safe" no contexto do CORE

Replay-safe significa que **dados escritos antes de um crash/restart são preservados e podem ser relidos sem corrupção**. Mecanismos:

1. **B64 blindagem (hotfix 2026-06-11)** — todos os `dvalue` agora são gravados como `"b64:" + base64(msgpack.pack(val))`. Antes, msgpack binário era MANGLED na fronteira Lua→JS do oxmysql (bytes >= 0x80 viravam par UTF-8). Linhas legadas sem prefixo `b64:` seguem o caminho msgpack raw — **replay-safe, sem migração obrigatória**.

2. **VRAM invalidation after `_set`** — após escrever, invalida a VRAM (exceto hot keys) para que a próxima leitura vá ao banco e receba o valor limpo serializado. Evita o bug "datatable crescente" (referência viva em VRAM cresceria a cada autosave).

3. **`_pack` ignora campos `_*`** — metadados internos (`_dirty`, `_loaded`, etc.) não são serializados para o banco.

4. **Cópia rasa em `_pack`** — evita serializar referências vivas com subitems já atualizados.

5. **Batch com re-enfileiramento seletivo** — apenas ops que o driver reportou como falha voltam para o batch; ops de outros jogadores que tiveram sucesso não são re-executadas.

6. **BLOB guard de 60KB** — ops com payload > 61440 bytes são descartadas (não enfileiradas) para não envenenar a transaction do batch. O BLOB SQL tem limite de 64KB.

### 10.5 Transações in-memory (não SQL)

O `begin/commit/rollback` garante consistência de VRAM entre início e commit, mas **as ops SQL vão para o batch e são executadas depois** — não no mesmo momento atômico do commit de VRAM.

**Trade-off aceito (readme Seção 21):** se o servidor crashar entre commit de VRAM e flush do batch, as ops SQL se perdem. Para crashes abruptos (kill -9, power outage), há risco de perda dos últimos segundos. O flush emergencial em `onResourceStop` tenta salvar o batch.

Exemplo de uso (transferência de dinheiro):
```lua
local tx = vHub.State:begin()
vHub.setUData(uid_de,   "money", saldo_de   - valor, tx)
vHub.setUData(uid_para, "money", saldo_para + valor, tx)
local ok, err = vHub.State:commit(tx)
-- se falhar, rollback automático restaura os valores anteriores em VRAM
```

---

## 11. Dependencies

### 11.1 Dependencies obrigatórias no fxmanifest

```lua
dependency 'oxmysql'
```

Único dependency explícito. O CORE usa `exports.oxmysql:query/scalar/update/transaction` via driver interno.

### 11.2 Exports externos usados pelo CORE

| Export | Onde | Uso |
|--------|------|-----|
| `exports.oxmysql` (table) | `bootstrap.lua:Driver:init` L192 | Verifica disponibilidade |
| `exports.oxmysql:query(sql, params, cb)` | `bootstrap.lua:_executar` | Query genérica |
| `exports.oxmysql:scalar(sql, params, cb)` | `bootstrap.lua:_executar` | Scalar |
| `exports.oxmysql:update(sql, params, cb)` | `bootstrap.lua:_executar`, `Driver:batch` | Update/execute |
| `exports.oxmysql:transaction(sql, params, cb)` | `bootstrap.lua:_executar` | Transaction (NÃO usado em `Driver:batch` — batch usa `update` isolado por op) |

### 11.3 Nativas FiveM usadas (não exaustivo)

- `GetCurrentResourceName()`, `LoadResourceFile()`, `GetResourceState()`, `GetInvokingResource()`
- `GetConvar`, `GetConvarInt`, `GetConvarFloat`
- `GetGameTimer()`, `Citizen.Wait()`, `Citizen.CreateThread()`, `Citizen.GetCurrentThread()`, `Citizen.Await()`
- `RegisterNetEvent`, `AddEventHandler`, `TriggerEvent`, `TriggerClientEvent`, `TriggerServerEvent`
- `GetPlayerName`, `GetPlayerEP`, `GetPlayerIdentifiers`, `GetPlayerPing`, `DropPlayer`, `IsPlayerACEAllowed`, `Player(src).state:set`
- `NetworkGetEntityFromNetworkId`, `NetworkSetEntityOwner`, `GetEntityCoords`, `GetEntityHeading`
- `promise.new()`, `msgpack.pack/unpack`, `json.encode/decode`
- `PerformHttpRequest` (webhooks Discord)
- `SetTimeout`, `print`

### 11.4 Resources externos esperados (não declarados como deps)

- **`vhub_player_state`** — dono do spawn físico (mencionado em `fxmanifest.lua` L42 e `init.lua` L73). Aplica spawn quando recebe `vHub:characterLoad`. Sem ele, o fallback nativo do client/bootstrap.lua spawna em posição hard-coded.
- **`vhub_garage`** — dono do negócio de veículos (owner, status, IPVA, leilão). Mencionado no `schema.sql` L154: "Negócio (owner, status, IPVA, leilão) fica em `vhub_garage`."
- **`vhub_oxmysql`** — driver alternativo (pode substituir o interno via `registerStateDriver`).
- **`vhub_admin`**, **`vhub_conce`**, **`vhub_vehcontrol`**, **`vhub_nitro`**, **`vhub_racha`** — resources do ecossistema que consomem o CORE.

---

## 12. Configuração

### 12.1 Defaults em `shared/config.lua` (`_defaults`)

```lua
local _defaults = {
  log_level           = "INFO",
  save_interval       = 60,
  max_payload         = 8192,
  modules             = {},
  whitelist_enabled   = false,
  trusted_resources   = {},
  max_ping            = 800,
  ping_check_interval = 30,
  ping_check_enabled  = false,
  fuel_rate           = 0.01,
  max_speed_kmh       = 400,
  veh_state_hz        = 4,
  db                  = {},
  webhooks = { join="", leave="", ban="", security="" },
  lang = {
    not_whitelisted = "Sem whitelist. Seu ID: ",
    banned          = "Você foi banido.",
    duplicate_login = "Você entrou de outro lugar.",
    ping_kick       = "Ping muito alto: %dms.",
  },
}
```

> ⚠️ **CAIXA PRETA:** `_defaults` **NÃO** é aplicado automaticamente. `mergeConfig` só é chamado se um resource externo a invocar. O `bootstrap.lua:criar_config()` constrói a config do zero a partir de convars e **NÃO** herda `_defaults`. Resultado: campos como `trusted_resources`, `max_ping`, `ping_check_*`, `max_speed_kmh`, `veh_state_hz`, `lang.banned`, `lang.duplicate_login`, `lang.ping_kick` ficam **nil** em `vHub.cfg` a menos que explicitamente populados.

### 12.2 Convars lidas por `bootstrap.lua:criar_config`

| Convar | Default | Min | Max | Campo em `vHub.cfg` |
|--------|---------|-----|-----|---------------------|
| `vhub_log_level` | 1 (INFO) | 0 | 3 | `log_level` (int; normalizado para string em `boot.lua:init`) |
| `vhub_max_payload` | 8192 | 512 | 65536 | `max_payload` |
| `vhub_save_interval` | 60 | 15 | 3600 | `save_interval` (segundos) |
| `vhub_fuel_rate` | 0.005 | 0.0 | 1.0 | `fuel_rate` |
| `vhub_whitelist` | 0 (false) | — | — | `whitelist_enabled` |
| `vhub_webhook_join` | "" | — | — | `webhooks.join` |
| `vhub_webhook_leave` | "" | — | — | `webhooks.leave` |
| `vhub_webhook_ban` | "" | — | — | `webhooks.ban` |
| `vhub_webhook_security` | "" | — | — | `webhooks.security` |

### 12.3 Convars NÃO lidas (mas usadas com fallback inline)

| Campo esperado | Fallback usado | Onde |
|----------------|----------------|------|
| `trusted_resources` | nil → default-deny | `exports.lua:_invoker_allowed` |
| `max_ping` | `or 800` | `boot.lua` ping check |
| `ping_check_interval` | `or 30` | `boot.lua` ping check |
| `ping_check_enabled` | nil → falsy → não roda | `boot.lua` if |
| `max_speed_kmh` | `or 350` | `vehicle.lua:onStateUpdate` |
| `veh_state_hz` | `or 4` | `vehicle.lua:onStateUpdate` |
| `lang.banned` | nil → `or "Você foi banido."` inline | `auth.lua:connect` |
| `lang.duplicate_login` | `or "Sessão encerrada: você entrou em outro lugar."` | `auth.lua:connect` |
| `lang.ping_kick` | `or "Ping alto: %dms."` | `boot.lua` ping check |
| `lang.not_whitelisted` | set em criar_config | `auth.lua:connect` |

### 12.4 Como override (recomendado)

```lua
-- Em um resource externo (ex: vhub_admin/server/init.lua), antes do primeiro uso:
Citizen.CreateThread(function()
  -- mergeConfig aplica _defaults onde nil e sobrescreve com user_cfg
  vHub.cfg = vHub.mergeConfig({
    trusted_resources = {
      vhub_admin   = true,
      vhub_garage  = true,
      vhub_conce   = true,
    },
    max_ping            = 600,
    ping_check_enabled  = true,
    max_speed_kmh       = 400,
    veh_state_hz        = 4,
    lang = {
      banned          = "Você foi banido permanentemente.",
      duplicate_login = "Conta em uso em outro dispositivo.",
    },
  })
end)
```

> 🔑 **Risco:** se `vHub.cfg.trusted_resources` não for populado, exports privilegiados (`grantPerm`, `transferKey`, `banPlayer`, `unbanPlayer`) retornam `false` silenciosamente. O warn é emitido **uma única vez** (`_warned_empty_trust`).

---

## 13. Pontos de Atenção / "Caixa Preta"

### 13.1 Handlers de veículo DORMENTES (decisão #24)

**O mais crítico.** Os 5 net events de veículo (`vHub:vSpawned`, `vHub:vDespawned`, `vHub:vEnter`, `vHub:vLeave`, `vHub:vState`) estão registrados com handler **NO-OP** (`_vhDisarmed`). Isso significa:
- `Veh:onSpawned`, `Veh:onDespawned`, `Veh:onEnter`, `Veh:onLeave`, `Veh:onStateUpdate` **EXISTEM** no código mas **NUNCA são chamados** pelo fluxo de net events.
- O `client/vehicle.lua` continua enviando `vHub:vState` a 4Hz, mas o server descarta silenciosamente.
- `Veh:_syncBags` (que escreve State Bags `vh_fuel/vh_eng/vh_body/vh_odo/vh_tune/vh_on`) só é chamado em `Veh:onSpawned` — que nunca é chamado. **State Bags de veículo nunca são escritas pelo CORE em runtime.**
- `Veh:register` ainda funciona (chamado por resources externos via export indireto), mas não há quem chame `onSpawned` naturalmente.

**Consequência para o ecossistema:** qualquer resource que queira sincronizar vehicle state **não pode depender do CORE** — precisa chamar `Veh:onSpawned`/`Veh:onStateUpdate` diretamente via `exports.vhub:getVHub().Vehicle` ou implementar seu próprio pipeline. Os eventos `vHub:vehicleSpawned`, `vHub:vehicleEnter`, `vHub:vehicleLeave`, `vHub:vehicleDespawned`, `vHub:vehicleFuelEmpty` são emitidos dentro das funções `Veh:*`, então também ficam sem emitter.

O comentário em `boot.lua` L171-178 é explícito:
> NUNCA reanimar onEnter/onLeave/onStateUpdate/onSpawned sem novo gate (regra da #24).

### 13.2 README desatualizado em `_invoker_allowed`

`readme.md` Seção 13 diz: "Se `trusted_resources` está vazio, qualquer resource pode chamar exports sensíveis." **Falso** desde hotfix N0-2. O código atual é **default-deny**:
```lua
if not trust or next(trust) == nil then
  return false  -- N0-2: era return true (default-permissivo)
end
```

### 13.3 `_defaults` de `shared/config.lua` é essencialmente morto

`mergeConfig` é exportado mas **nunca chamado** pelo `bootstrap.lua`. O `criar_config()` constrói a config do zero a partir de convars, deixando vários campos como nil. Os defaults em `_defaults` só têm efeito se um resource externo chamar `mergeConfig` explicitamente. **Isso provavelmente é um bug** ou pelo menos uma documentação enganosa.

### 13.4 `fuel_rate` — defaults diferentes entre arquivos

| Arquivo | Default |
|---------|---------|
| `shared/config.lua:_defaults.fuel_rate` | `0.01` |
| `bootstrap.lua:criar_config().fuel_rate` | `0.005` (via `decimal("vhub_fuel_rate", 0.005, ...)`) |
| `vehicle.lua:onStateUpdate` | `vHub.cfg.fuel_rate or 0.005` |

O efetivo é `0.005` (bootstrap ganha). O `_defaults` está errado/inconsistente.

### 13.5 `max_speed_kmh` — defaults diferentes

| Arquivo | Default |
|---------|---------|
| `shared/config.lua:_defaults.max_speed_kmh` | `400` |
| `vehicle.lua:onStateUpdate` fallback | `350` |

Como `criar_config` não seta `max_speed_kmh`, o fallback `350` é o efetivo.

### 13.6 KNOWN MINOR LEAK em `bootstrap.lua:Driver:_executar`

Comentário em L125-126:
```
-- KNOWN MINOR LEAK: closure permanece viva até 15s mesmo após resolver.
-- Aceitável: pico transitório de heap, GC absorve. Não substituir sem API cancelável nativa.
```
O `SetTimeout(15000, function() resolver(nil, "timeout_db") end)` mantém a closure viva por 15s mesmo se a query resolver antes. Pico transitório de heap.

### 13.7 `vHub:passengerMode` não registrado no client

`Veh:onEnter` e `Veh:onLeave` chamam `vHub.Kernel:emit(src, "vHub:passengerMode", plate, bool)`. Esse evento **não tem `RegisterNetEvent` nem handler no client** em nenhum arquivo do CORE. Provavelmente é responsabilidade de um resource externo registrar (`AddEventHandler("vHub:passengerMode", ...)`). Mas como os handlers estão DORMENTES (13.1), isso nunca é emitido em runtime.

### 13.8 `vehicleStateLoad` emitido apenas em `Veh:onEnter` (dorminte)

`client/vehicle.lua` registra handler para `vHub:vehicleStateLoad` (L21-36) — aplica fuel/engine/body ao veículo local. Mas o emit acontece em `Veh:onEnter` (L175), que é chamado em handler **DORMENTE**. Logo, o handler client existe mas nunca é invocado pelo CORE em runtime.

### 13.9 Posição de spawn hard-coded no fallback

`client/bootstrap.lua` L6:
```lua
local SPAWN_POS   = { x = -538.70, y = -214.91, z = 37.65, h = 0.0 }
```
Em servidores com spawn customizado, o fallback pode colocar o jogador na posição errada por ~500ms antes de `vhub_player_state` aplicar a posição correta. Comentário no readme admite: "O jogador mal percebe."

### 13.10 Transações in-memory ≠ SQL atômico

`State:begin/commit/rollback` garante consistência de VRAM, mas as ops SQL vão para o batch e são executadas **depois**. Se o servidor crashar entre commit e flush, há perda. O flush emergencial em `onResourceStop` mitiga mas não cobre `kill -9`.

### 13.11 Batch contamination cross-player — resolvido mas com trade-off

Originalmente `Driver:batch` usava `oxmysql:transaction([op1, op2, ..., opN])` — uma falha em uma op revertia TODAS. Agora usa `api:update` isolado por op (em paralelo, cada uma com seu promise). Trade-off: atomicidade SQL perdida; isolamento ganhou prioridade. Para dados que precisam de atomicidade real (transferência de dinheiro), o chamador deve usar `begin/commit` de VRAM e aceitar que a persistência SQL pode chegar em flushes diferentes.

### 13.12 `assertThread` apenas nos getters

```lua
function vHub.getUData(uid, k) vHub.assertThread(); return _get(...) end   -- getter: assert
function vHub.setUData(uid, k, v, tx)                 _set(...)  end       -- setter: SEM assert
```
O readme diz "todos exigem Citizen.CreateThread", mas os setters não chamam `assertThread` (não precisam — só enfileiram op no batch, sem Await). Se chamado fora de thread, funciona mas a op vai para o batch normalmente. Não é bug, mas é inconsistente com a documentação.

### 13.13 VRAM não tem TTL

Dados em `_mem` **nunca expiram por tempo**. Para servidores com 10.000+ jogadores únicos por dia, a VRAM cresce linearmente. Mitigação: invalidação após write (exceto hot keys). Não há eviction automático para entradas de usuários offline — `Auth:disconnect` não limpa a VRAM (intencional: dados podem ser acessados por admin offline). Uma feature de GC periódico está marcada como "poderia ser adicionada em v2.0".

### 13.14 `Auth:connect` ainda tem `print()` de debug

`auth.lua` L174, L178, L184, L220 têm `print(...)` (não `vHub.Logger`). São resquícios de debug:
```lua
print(('vHub.Auth:connect attempt src=%s'):format(tostring(src)))
print(('vHub.Auth:connect already session src=%s uid=%s'):format(...))
print(('vHub.Auth:connect fail no uid src=%s'):format(tostring(src)))
print(('vHub.Auth:connect ok src=%s uid=%s'):format(tostring(src), tostring(uid)))
```
Viola a regra de ouro do readme: "nenhum módulo usa `print()` — apenas `vHub.Logger`". Pequeno, mas é uma inconsistência.

### 13.15 `boot.lua` também tem `print()`

L80: `print(('vHub.boot: ready received src=%s'):format(tostring(src)))` — também viola a regra do Logger.

### 13.16 `vehicle.lua:onStateUpdate` — clampagem de odômetro suspeita

```lua
local max_delta = (rpm or 0) * max_speed_kmh * time_per_tick / 3600
local applied = math.min(odometer_delta, math.max(0.0001, max_delta), 0.5)
```
O `0.5` (km/tick) é um teto absoluto. Com `veh_state_hz = 4` → `time_per_tick = 0.25s` → a 350km/h, max_delta = `350 * 0.25 / 3600 ≈ 0.024 km`. O `0.5` parece ser um safety net amplo demais. Provavelmente OK na prática, mas merece revisão.

### 13.17 `validar_config` exportado mas nunca usado

`shared/config.lua` L57-67 define `vHub.validateConfig(cfg)` que retorna `(bool, errs)`. Não é chamado em nenhum lugar do core. Útil para resources externos, mas inerte no CORE.

### 13.18 Schema migration MEDIUMBLOB → BLOB

`schema.sql` L13-25 documenta que `CREATE TABLE IF NOT EXISTS` **NÃO altera tipo de coluna existente**. Se o banco já tem MEDIUMBLOB e quiser otimizar para BLOB, deve rodar manualmente:
```sql
ALTER TABLE vh_user_data    MODIFY COLUMN dvalue BLOB;
ALTER TABLE vh_char_data    MODIFY COLUMN dvalue BLOB;
ALTER TABLE vh_global_data  MODIFY COLUMN dvalue BLOB;
ALTER TABLE vh_vehicle_data MODIFY COLUMN dvalue BLOB;
```
Verificar `SELECT MAX(LENGTH(dvalue)) FROM vh_user_data;` antes — se > 65000, manter MEDIUMBLOB.

### 13.19 Estado do `client/vehicle.lua` — envia mas ninguém escuta

O loop adaptativo envia `vHub:vState` a 0.5/1/4Hz. Como o handler server é NO-OP, todo esse tráfego é desperdiçado (consumo de banda + CPU sem efeito). O cliente poderia pular o envio até que o CORE reanime os handlers. Hoje é "tráfego morto".

### 13.20 `boot.lua` `vHub:savePos` removido

L168-169:
```lua
-- vHub:savePos removido — vhub_player_state é o dono da persistência de posição
-- via evento vhub_player_state:update (resource externo).
```
A persistência de posição foi delegada ao `vhub_player_state`. O CORE só persiste `last_pos` em `vd.state.last_pos` (via `Veh:_atualizarPosicao` em `_save`).

---

## Apêndice A: Mapa de arquivos (confirmação)

```
resources/[CORE]/vhub/
├── fxmanifest.lua              -- 1 server_script, 2 client_scripts, 4 shared_scripts
├── bootstrap.lua               -- Entry server: criar_config, criar_driver, validar, iniciar
├── base.lua                    -- Carrega server/init.lua via load() no _ENV=_G
├── readme.md                   -- 1517 linhas de documentação (parcialmente desatualizada)
├── shared/
│   ├── config.lua              -- vHub global, _defaults, mergeConfig, validateConfig
│   ├── events.lua              -- vHub.E.* (read-only metatable)
│   ├── utils.lua               -- Helpers puros: formatNumber, dataCopy, normalizePlate...
│   └── logger.lua              -- vHub.Logger:debug/info/warn/error
├── server/
│   ├── init.lua                -- class(), assertThread(), loadmod(), ordem obrigatória
│   ├── kernel.lua              -- K:net, K:on, K:emit, K:broadcast, K:export, perms, rate-limit
│   ├── state.lua               -- VRAM (_mem), TX (begin/commit/rollback), batch SQL, B64, KV API
│   ├── sql.lua                 -- TODOS S:prepare() centralizados
│   ├── notify.lua              -- Notify:send (webhooks Discord com retry 3x)
│   ├── auth.lua                -- User class, _sessions/_byUID, _resolveUID, connect, ban
│   ├── vehicle.lua             -- VehicleData, State Bags, autoridade de entidade
│   ├── security.lua            -- requireAdmin, _permFail, checkPayload, validators
│   ├── boot.lua                -- vHub:init(), net events, autosave, GC, lifecycle
│   └── exports.lua             -- Exports cross-resource com _invoker_allowed
├── client/
│   ├── bootstrap.lua           -- playerSpawned + fallback nativo + State Bags locais
│   └── vehicle.lua             -- Report adaptativo 0.5/1/4Hz + vehicleStateLoad handler
└── sql/
    └── schema.sql              -- 8 tabelas InnoDB, idempotente, FK CASCADE
```

## Apêndice B: Linhas de código por arquivo (aprox.)

| Arquivo | LOC |
|---------|-----|
| `bootstrap.lua` | 434 |
| `readme.md` | 1517 |
| `base.lua` | 42 |
| `fxmanifest.lua` | 44 |
| `shared/config.lua` | 71 |
| `shared/events.lua` | 39 |
| `shared/utils.lua` | 70 |
| `shared/logger.lua` | 34 |
| `server/init.lua` | 99 |
| `server/kernel.lua` | 112 |
| `server/state.lua` | 398 |
| `server/sql.lua` | 109 |
| `server/notify.lua` | 19 |
| `server/auth.lua` | 359 |
| `server/vehicle.lua` | 281 |
| `server/security.lua` | 30 |
| `server/boot.lua` | 221 |
| `server/exports.lua` | 40 |
| `client/bootstrap.lua` | 131 |
| `client/vehicle.lua` | 86 |
| `sql/schema.sql` | 191 |
| **Total Lua (sem readme)** | **≈ 2.432** (confirma declaração do readme) |

---

**Fim da análise.**
