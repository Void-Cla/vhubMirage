# vHub Mirage — Manual de Desenvolvimento

> **Quem deve ler:** todo dev que toca em `resources/[SCRIPTS]/vhub_*` ou em qualquer recurso que dependa do core vHub.
> **Premissa:** o core (`[CORE]/vhub`) está **CORE FROZEN v1.0 (2026-05-22)** — kernel imutável, mudanças apenas **aditivas** com gate duplo (única exceção registrada: contratos `commitVehicleState`/`getVehicleState` da IT.2).
> **Meta operacional (honesta, mensurável):** custo por player **O(1)** dentro dos **Orçamentos do CLAUDE.md** (idle CORE ≤ 0.05 ms, script ≤ 0.02 ms, tick p95 ≤ 0.10 ms/script, NUI fechada 0.00 ms), operando no **teto da plataforma** (OneSync Infinity = 2048 slots/processo) com 40 % de folga. Acima do teto = multi-instância sobre o KV do CORE — nunca prometa números que a plataforma não entrega.
> **Lei-mestra deste manual:** *peça ao dono, nunca escreva no que não é seu.* Todo dado tem UMA linha no **Registro de Ownership** (`CLAUDE.md`); seu script lê por export e escreve por **contrato de commit**.

## Contrato pós-freeze (o que o core garante)

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
| **Escrita de estado físico do veículo** | **`exports.vhub:commitVehicleState(plate, patch, reason)`** — único caminho p/ terceiros (IT.2); valida, clampa, marca dirty, sincroniza bags e loga o `reason` |
| **Leitura de estado físico** | `exports.vhub:getVehicleState(plate)` (snapshot) no servidor; State Bags no cliente |
| **Spawn do ped** | dono único = `vhub_player_state` (`spawnAt`, `teleport`, `giveWeapons`, `set*`) — nenhum script toca o ped |
| **Replay institucional** | `vHub:playerSpawn`/`vHub:characterLoad` são **re-disparados para todas as sessões** em `onResourceStart` de qualquer resource — todo handler precisa de replay-guard (L-17) |

**Schemas externos com FK ao core DEVEM usar `INT UNSIGNED`** (signed dispara `errno 150`).

---

## 0. Filosofia em uma página

| Princípio | Tradução prática |
|---|---|
| **Servidor é a única fonte de verdade crítica** | Dinheiro, inventário, ban, propriedade → SQL/VRAM server. Cliente nunca decide. |
| **Um dono por dado (L-04/L-13)** | Antes de criar/escrever um dado: qual a linha dele no Registro de Ownership? Sem linha = sem dado. Chave de outro domínio = proibido escrever. |
| **Peça, não escreva** | Estado do veículo → `commitVehicleState`. Ped → `spawnAt/teleport`. Dinheiro → exports do `vhub_money`. Seu script expressa *intenção*; o owner valida e comita. |
| **Cliente é tela, não cérebro** | Cliente renderiza, interage, envia intenção. Servidor valida e persiste. |
| **VRAM-first, SQL é backup** | Leitura: VRAM → SQL. Escrita: VRAM + batch. Sem round-trip síncrono no caminho quente. |
| **Native-first** | Antes de helper custom, procurar native (`metas/fivem_natives_organizadas_ptbr.md`). Com OneSync o **servidor** também tem natives de entidade (`NetworkGetEntityFromNetworkId`, `GetEntityCoords`, `GetVehicleNumberPlateText`). |
| **Evento + State Bag, não polling** | `AddStateBagChangeHandler`/`AddEventHandler` antes de `while true`. Estado de entidade para todos = State Bag, **nunca** `TriggerClientEvent(-1)`. |
| **Batch, não unitário** | Persistência de domínio via `setCData/setUData` (batch do core) ou multi-insert no oxmysql. |
| **Replay-safe por padrão** | Handler de evento institucional é idempotente (L-17). |
| **Deletar é entrega (L-15)** | Todo `.lua` referenciado no manifest **no mesmo commit**; substituiu um arquivo → remova o antigo. O hook bloqueia órfão e módulo-fantasma. |
| **Falha graciosa** | `pcall` nas fronteiras (export externo, payload). Nunca derrubar o tick. |
| **Saídas em PT-BR** | Comentário, log de usuário, NUI = PT-BR. Identificadores: convenção dominante do arquivo; arquivo novo = inglês (L-08). |

---

## 1. Anatomia de um resource vHub

```
resources/[SCRIPTS]/vhub_<dominio>/
├── shared/
│   ├── config.lua        ← constantes, coords, taxas, cooldowns, TABELA DE RATES
│   ├── events.lua        ← VHub<Dom>.E.* (constantes string)
│   └── utils.lua         ← helpers puros
├── server/
│   ├── sql.lua           ← queries via exports.oxmysql (NUNCA S:prepare cross-resource)
│   ├── core.lua          ← sessões, hasPerm local, rate helper
│   ├── init.lua          ← bootstrap (schema, sessões, replay-guard)
│   ├── <feature>.lua     ← 1 responsabilidade por arquivo (L-09)
│   └── exports.lua       ← API pública (contrato p/ outros resources)
├── client/
│   ├── init.lua          ← state local, NUI focus, callbacks
│   ├── zones.lua         ← markers/blips/[E] event-driven
│   └── <feature>.lua
├── nui/                  ← (se houver UI — padrão do guardião designer)
├── sql/
│   └── schema.sql        ← CREATE TABLE IF NOT EXISTS vhub_<dom>_*
└── fxmanifest.lua
```

Regras novas da estrutura (pós-auditoria):
- **L-15 mecânica:** o hook `post_lua_check.sh` bloqueia qualquer `.lua` que não esteja no `fxmanifest.lua` do resource — crie a entrada no manifest **junto** com o arquivo.
- **Anti-fantasma:** `shared/events.lua` define **tabela global** (`VHubDom = VHubDom or {}; VHubDom.E = {...}`). Jamais `local Events = {...} return Events` — o loader de manifest descarta o return (foi exatamente o padrão morto encontrado no spawnselector).
- Tabelas SQL próprias com prefixo do domínio (`vhub_<dom>_*`). **Proibido** `INSERT/UPDATE/DELETE` em `vh_users`, `vh_characters`, `vh_vehicles`, `vh_*_data` — essas pertencem ao core/owners; seu script só referencia por FK e conversa por export.

---

## 2. fxmanifest canônico

```lua
---@diagnostic disable: undefined-global, lowercase-global
fx_version 'cerulean'
game       'gta5'
lua54      'yes'

name        'vhub_<dominio>'
author      'vHub Mirage'
version     '1.0.0'
description '<frase única em PT-BR>'

dependencies {
  'vhub',               -- SEMPRE
  'oxmysql',            -- SE tiver SQL próprio
  'vhub_player_state',  -- SE mover/equipar o ped (teleport, armas, custom)
  'vhub_inventory',     -- SE consumir items/chaves
  'vhub_money',         -- SE mexer dinheiro
  'vhub_groups',        -- SE checar perms
}

shared_scripts { 'shared/config.lua', 'shared/events.lua', 'shared/utils.lua' }

server_scripts {
  'server/sql.lua',
  'server/core.lua',
  'server/init.lua',
  'server/<feature>.lua',
  'server/exports.lua',
}

client_scripts { 'client/init.lua', 'client/zones.lua', 'client/<feature>.lua' }

ui_page 'nui/index.html'
files   { 'nui/index.html', 'nui/css/style.css', 'nui/js/app.js', 'nui/assets/bg.png', 'nui/assets/logo.png' }
```

Ordem: o runtime carrega `shared → server → client`, linha a linha dentro de cada bloco — `sql.lua` antes de quem o usa. **Todo arquivo novo entra aqui no mesmo commit (L-15).**

---

## 3. O ciclo orgânico — onde o seu script se pluga (sem competir com o core)

Cada domínio tem um dono e um ciclo. Seu script **escuta os eventos do ciclo** e **pede ações pelos contratos** — nunca recria o ciclo por fora.

### 3.1 Ciclo do jogador

```
conexão → vHub:ready (client) → Auth (core) ─┬→ vHub:characterLoad(user)       ← carregue sua sessão aqui
                                             └→ vHub:playerSpawn(user, first)  ← REPLAY-GUARD obrigatório
player_state aplica ped → [selector elege coordenada] → release
                                             └→ client: 'vhub_player_state:spawned'(first)  ← inicie HUD/zonas aqui
morte → vHub:playerDeath(user) | queda → playerDropped
```

Handler canônico (sessão + replay-guard L-17):

```lua
-- server/init.lua — sessão por personagem (replay-safe)
local sessions, _seen = {}, {}

-- carrega sessão do domínio quando o personagem entra
AddEventHandler('vHub:characterLoad', function(user)
  if not user then return end
  sessions[user.source] = sessions[user.source] or { char_id = user.char_id }
end)

-- reage ao spawn UMA vez por spawn real (core re-dispara em onResourceStart!)
AddEventHandler('vHub:playerSpawn', function(user, first)
  if not user then return end
  local spawns = tonumber(user.spawns) or 0
  if _seen[user.source] == spawns then return end   -- replay → no-op
  _seen[user.source] = spawns
  -- ... setup por spawn (blips, estado de zona)
end)

AddEventHandler('playerDropped', function()
  sessions[source] = nil; _seen[source] = nil       -- L: sem leak por src
end)
```

Mexer no ped — **sempre pelo dono**:

```lua
exports.vhub_player_state:teleport(src, x, y, z, h)        -- mover
exports.vhub_player_state:giveWeapons(src, weapons, clear) -- armar
exports.vhub_player_state:setHealth(src, 200)              -- curar
exports.vhub_player_state:setCustomization(src, custom)    -- visual
-- Provedor de coordenada de spawn (estilo selector): escute
-- 'vhub_player_state:chooseSpawn'(src) e devolva via spawnAt(src, pos|nil).
```

**Proibido (L-16):** `SetPlayerModel`, `NetworkResurrectLocalPlayer`, `SetEntityCoords` no ped em fluxo de spawn fora do owner. O hook avisa; o gate reprova.

### 3.2 Ciclo do veículo

```
COMPRA (conce: registerVehicle → espelho vh_vehicles) → SPAWN (garage: valida chave/owner/status/proximidade)
→ ENTRADA (vehcontrol: vEnter → core registra driver) → USO (telemetria 4 Hz do core acumula fuel/odo/dano)
→ COMMIT (autosave/eventos via _save) → GUARDAR (garage: store) → PÁTIO (boot-scan/admin) → RECUPERAÇÃO
```

Seu script **lê** e **pede**:

```lua
-- LER estado físico (servidor): snapshot do owner
local s = exports.vhub:getVehicleState(plate)        -- {fuel, engine_health, body_health, odometer, ...} | nil

-- LER no cliente: State Bags do core (delta-gated) — zero evento custom
local fuel = Entity(veh).state.vh_fuel               -- chaves vh_* (ver _syncBags no core)
AddStateBagChangeHandler('vh_fuel', nil, function(bag, _, v) ... end)

-- ESCREVER: SEMPRE pelo contrato (valida, clampa, dirty, syncBags, loga reason)
exports.vhub:commitVehicleState(plate, { fuel = 100.0 }, 'vhub_<dom>:refuel')
exports.vhub:commitVehicleState(plate, { engine_health = 1000, body_health = 1000 }, 'vhub_<dom>:repair')

-- REAGIR a commits de qualquer origem (auditável pelo reason)
AddEventHandler('vHub:vehicleCommitted', function(vd, patch, reason) ... end)
```

**Proibido (L-13/L-14):** `setVData(...)` fora do core (hook **bloqueia**) e mutar `vd.state` obtido por `getVHub()`/`getVehicle()` — leitura só.

Veículo **persistente** nasce e morre pelos donos do ciclo: registre via exports do `vhub_conce`, spawn/guarde via `vhub_garage` (assinaturas no `server/exports.lua` de cada um). Veículo **efêmero** (missão/corrida) pode ser criado pelo seu script **se e somente se**: placa com prefixo reservado do domínio (ex.: `RC` + id), nunca passa por `commitVehicleState`, despawn garantido por timeout + `playerDropped`, e entidade marcada mission p/ delete confiável (§4.7 do despawn). Efêmero que vira persistente = bug de ownership.

### 3.3 Usuário e dados do SEU domínio (API pública KV)

```lua
RegisterNetEvent('vhub_dom:server:Acao')
AddEventHandler('vhub_dom:server:Acao', function(payload)
  local src = source
  if not Core.rate(src, 'acao', 1000) then return end       -- §4.6: throttle declarado
  Citizen.CreateThread(function()                            -- OBRIGATÓRIO p/ Await
    local user = exports.vhub:getUser(src)
    if not user or not user.char_id then return end
    if type(payload) ~= 'table' then return end              -- shape primeiro

    local saldo = exports.vhub:getCData(user.char_id, 'meu_dom_saldo') or 0
    exports.vhub:setCData(user.char_id, 'meu_dom_saldo', saldo + 100)  -- batch
  end)
end)
```

Regras: `set/getUData/CData/GData` são a API pública **para chaves do SEU domínio** — prefixe a chave (`meu_dom_*`), declare-a na linha do Registro de Ownership, e jamais escreva em chave alheia (ex.: `banco` é do `vhub_money`). O hook lembra; o guardião de persistência audita.

### 3.4 Permissão (3 caminhos, 1 função)

```lua
-- server/core.lua
-- verifica permissão: owner(uid=1) > ACE > grupos
function Core.hasPerm(src, perm)
  local uid = exports.vhub:getUID(src)
  if uid == 1 then return true end
  if IsPlayerAceAllowed(src, 'vhub.' .. perm) then return true end
  return exports.vhub_groups:hasPermission(src, perm) == true
end
```

### 3.5 Transação atômica via core (≥ 2 escritas juntas)

```lua
local tx = vHub.State:begin()
vHub.setCData(a_char, 'meu_dom_saldo', a - v, tx)
vHub.setCData(b_char, 'meu_dom_saldo', b + v, tx)
local ok, err = vHub.State:commit(tx)
if not ok then exports.vhub:notify(src, 'Falha: ' .. tostring(err)) end
```

### 3.6 SQL próprio (Decisão #8: nunca S:prepare cross-resource)

```lua
-- server/sql.lua
local function pquery(sql, args)
  local p = promise.new()
  exports.oxmysql:query(sql, args or {}, function(r) p:resolve(r or {}) end)
  return Citizen.Await(p)
end
local function pexec(sql, args)
  local p = promise.new()
  exports.oxmysql:execute(sql, args or {}, function(r) p:resolve(r) end)
  return Citizen.Await(p)
end
SQL = { query = pquery, execute = pexec }
```

Schema externo — regras canônicas: `CREATE TABLE IF NOT EXISTS` idempotente; `ENGINE=InnoDB CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`; FK ao core **`INT UNSIGNED`** com `ON DELETE CASCADE ON UPDATE CASCADE`; `updated_at ... ON UPDATE CURRENT_TIMESTAMP`; KV próprio em `BLOB` (64 KB) — `MEDIUMBLOB` só com justificativa de tamanho × frequência. Tabela própria = `vhub_<dom>_*`; tabelas `vh_*` do core são intocáveis por SQL de script.

### 3.7 Export sensível com `_invoker_allowed`

```lua
-- server/exports.lua
local TRUSTED = { ['vhub_admin'] = true }
local function _invoker_allowed()
  local caller = GetInvokingResource()
  if not caller then return true end
  return TRUSTED[caller] == true
end
exports('adminDeleteThing', function(id)
  if not _invoker_allowed() then return false end
  -- ...
  return true
end)
```

Export que **muta** = invoker validado. Export read-only pode ser público. Todo export novo é contrato (guardião de contratos): assinatura estável, retorno semântico, sem expor internals `_`.

### 3.8 Despawn confiável de entidade própria

Padrão do `vhub_garage/client/vehicles.lua`: `TaskLeaveVehicle(ped, veh, 16)` → `NetworkRequestControlOfEntity` + aguardar `NetworkHasControlOfEntity` → `SetEntityAsMissionEntity(veh, true, true)` → `DeleteEntity` → varredura `FindFirstVehicle/FindNextVehicle` apagando duplicatas pela placa nativa. `DecorSetString` não existe mais no FiveM.

### 3.9 NUI — abrir, fechar, callbacks (resumo; padrão completo no guardião designer)

```lua
RegisterNUICallback('act', function(data, cb)
  TriggerServerEvent('vhub_dom:server:Act', data)  -- só intenção; servidor decide
  cb({ ok = true })
end)
```

NUI nunca envia campo calculável (`cost/owner/balance`); `SetNuiFocus(false,false)` em todo close; RAF/interval mortos com NUI fechada (0.00 ms).

---

## 4. Padrões de performance (Orçamentos = contrato, L-18)

### 4.1 Frame loop só quando NECESSÁRIO (duas threads: fria + quente)

```lua
local proximo = false
Citizen.CreateThread(function()           -- fria: 1 Hz
  while true do
    Citizen.Wait(1000)
    proximo = #(GetEntityCoords(PlayerPedId()) - vector3(x, y, z)) < 30.0
  end
end)
Citizen.CreateThread(function()           -- quente: só perto
  while true do
    if not proximo then Citizen.Wait(500)
    else Citizen.Wait(0); DrawMarker(1, x, y, z, ...) end
  end
end)
```

### 4.2 State Bag antes de evento custom

Servidor decide → `Player(src).state:set('vhub_dom_role', v, true)` / `Entity(ent).state:set(...)`. Cliente lê `LocalPlayer.state.x` ou `AddStateBagChangeHandler`. **Estado de entidade para todos os clientes = State Bag, nunca `TriggerClientEvent(-1)`** (broadcast só para evento discreto/efeito momentâneo).

### 4.3 Cache de export externo + invalidação por evento

```lua
local _cache = {}
AddEventHandler('vhub_groups:changed', function(src) _cache[src] = nil end)
AddEventHandler('playerDropped', function() _cache[source] = nil end)
local function getRole(src)
  if _cache[src] ~= nil then return _cache[src] end
  local v = exports.vhub_groups:hasPermission(src, 'police')
  _cache[src] = v; return v
end
```

### 4.4 Adaptive rate em report cliente (espelhar o core)

morto 5000 ms · a pé 1000 ms · dirigindo 250 ms. O core já faz isso para veículo; replique a curva no seu HUD/report.

### 4.5 Batch no SQL próprio

1 multi-insert `VALUES (?,?),(?,?)...` em vez de N execuções; ou enfileire no batch do core via `setCData` quando o dado é de personagem.

### 4.6 Rate-limit declarado por evento (scripts não têm o Kernel:net)

```lua
-- server/core.lua — throttle O(1) por (src, chave)
local _last = {}
-- retorna true se a ação respeita o intervalo mínimo (ms)
function Core.rate(src, key, ms)
  local now = GetGameTimer()
  local k = src .. ':' .. key
  if (now - (_last[k] or 0)) < ms then return false end
  _last[k] = now; return true
end
AddEventHandler('playerDropped', function()
  local p = source .. ':'
  for k in pairs(_last) do if k:sub(1, #p) == p then _last[k] = nil end end
end)
```

Tabela de intervalos vive em `shared/config.lua` (`CFG.rates = { acao = 1000, ... }`) — evento novo nasce com rate declarado (checklist 6.6).

### 4.7 Doutrina de Escala no código

`GetPlayers()` para lógica de domínio exige justificativa no gate (multi-instância quebra a suposição). Custo por player O(1): nada de loop server iterando todos os players por tick para recomputar algo que um evento/bag entrega.

---

## 5. Antipadrões (não fazer)

| Antipadrão | Por quê | Pattern |
|---|---|---|
| `setVData(...)` fora do core | viola L-13; foi a causa do last-write-wins em `vh_vehicle_data` (8 casos históricos) — **hook bloqueia** | `commitVehicleState(plate, patch, reason)` |
| Mutar `vd.state`/internos via `getVHub()`/`getVehicle()` | L-14; repair-hack e corrupção de sessão | leitura: `getVehicleState`; escrita: contrato |
| Escrever chave KV de outro domínio (`setCData(cid,'banco',...)` fora do money) | segunda verdade (L-04/L-13) | chave própria prefixada + linha no Registro |
| `SetPlayerModel`/`SetEntityCoords` de spawn fora do `vhub_player_state` | 3 escritores disputaram o ped (caso real) | `spawnAt`/`teleport`/provider `chooseSpawn` |
| Handler `vHub:playerSpawn` sem replay-guard | core re-dispara em `onResourceStart` → re-teleporte global (caso real) | snapshot de `user.spawns` (§3.1) |
| Arquivo `.lua` fora do manifest / módulo `return M` sem global | código morto/fantasma (5 casos reais, 1 com `os.exit`) — **hook bloqueia** | manifest no mesmo commit; `VHubX = M` |
| `os.exit()`, version-check HTTP, anti-tamper vendor | derruba/expõe o servidor | deletar na chegada |
| `TriggerClientEvent(-1, ...)` p/ estado de entidade | N mensagens × players; bag faz delta de graça | State Bag |
| Comentar a lei violando-a (`-- L-04` num segundo escritor) | corrói toda a constituição — violação agravada | cumprir ou renegociar no gate |
| `while true do Wait(0)` sempre ativo | resmon spike | frame loop condicional (4.1) |
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

---

## 6. Checklist de release (Definition of Done — todo PR passa)

### 6.0 Ownership e governança
- [ ] Linha do **Registro de Ownership** criada/atualizada (dado novo → chave, owner, leitores, persistência, contrato)?
- [ ] Grep de fechamento limpo: `setVData` fora do core = 0; `getVHub` só leitura; spawn de ped só no owner?
- [ ] Todo `.lua` novo referenciado no `fxmanifest.lua` (L-15)? Arquivos substituídos foram deletados?
- [ ] Smoke test descrito e executável; rollback em 1 linha?

### 6.1 Estrutura
- [ ] Pastas no template (§1)? Dependências declaradas? Schema `IF NOT EXISTS`, InnoDB/utf8mb4, FK `INT UNSIGNED` + CASCADE? Tabelas com prefixo `vhub_<dom>_`?

### 6.2 Servidor
- [ ] Comentário PT-BR por função pública (L-10)? `CreateThread` onde há `Await`? Validação server-side em toda decisão crítica? Export sensível com `_invoker_allowed`? `playerDropped` limpa toda tabela `[src]`? Handlers institucionais com replay-guard (L-17)?

### 6.3 Cliente
- [ ] Frame loop condicional? Estado de veículo lido por State Bag? `SetNuiFocus(false,false)` em todo close? Cache de export externo?

### 6.4 NUI
- [ ] Theme vHub (guardião designer)? `lang="pt-BR"` + UTF-8? RAF/interval/observer mortos no close?

### 6.5 Performance (Orçamentos)
- [ ] resmon idle ≤ 0.02 ms (script) / ativo p95 ≤ 0.10 ms? Client idle fora de contexto 0.00 ms? NUI fechada 0.00 ms? resmon antes/depois anexado se tocou hot path?

### 6.6 Segurança
- [ ] Shape/range/tamanho do payload validados ANTES do domínio? **Rate declarado em `CFG.rates` para todo evento de cliente** (§4.6)? Ações sensíveis logadas com `reason`?

---

## 7. Como medir resmon

`resmon` · `profiler record` · `status`. Olhar: server-tick médio, cpu por resource, net out.
Baseline idle → +1 player → pico simulado (txAdmin) → atacar quem escala **superlinear** (quase sempre frame loop ativo ou broadcast).
Alertas: server tick > 0.5 ms · resource > 0.3 ms · net out > 500 KB/s constante = vermelho. Metas por resource: tabela de Orçamentos do `CLAUDE.md` (é contrato — estourou, renegocia no gate antes de mergear).

---

## 8. Como o vHub se diferencia de vRP/ESX/qbcore

| Característica | vRP1 | vRP2 | ESX | qbcore | **vHub** |
|---|---|---|---|---|---|
| VRAM-first | ❌ | ⚠️ | ⚠️ | ⚠️ | ✅ |
| Batch SQL transacional | ❌ | ❌ | ❌ | ⚠️ | ✅ |
| Driver plugável (`registerStateDriver`) | ❌ | ❌ | ❌ | ❌ | ✅ |
| State Bag canônica com gating delta | ❌ | ❌ | ⚠️ | ⚠️ | ✅ |
| `NetworkSetEntityOwner` controlado | ❌ | ❌ | ❌ | ⚠️ | ✅ |
| Rate-limit por evento O(1) | ❌ | ❌ | ❌ | ❌ | ✅ |
| Spawn com dono único + provider de coordenada | ❌ | ❌ | ❌ | ❌ | ✅ |
| `assertThread` em APIs com Await | ❌ | ❌ | ❌ | ❌ | ✅ |
| `_invoker_allowed` em exports sensíveis | ❌ | ❌ | ⚠️ | ⚠️ | ✅ |
| **Contrato de commit p/ estado de veículo (escritor único + reason auditável)** | ❌ | ❌ | ❌ | ❌ | ✅ |
| Adaptive client report | ❌ | ❌ | ❌ | ❌ | ✅ |
| Governança executável (leis com detector mecânico) | ❌ | ❌ | ❌ | ❌ | ✅ |

---

## 9. Novo resource em 15 minutos (ciclo completo)

0. **Linha do Registro de Ownership** (dado, owner, leitores, persistência, contrato) + gate `vhub_arquiteto`. Sem isso, não há passo 1.
1. Copiar template (§1); **cada arquivo entra no fxmanifest na hora** (§2).
2. `shared/config.lua`: `VHubDom = VHubDom or {}; VHubDom.cfg = {...}; VHubDom.cfg.rates = { acao = 1000 }`.
3. `shared/events.lua`: `VHubDom.E = { SRV_ACT = 'vhub_dom:server:Act', CLI_X = 'vhub_dom:client:X' }` (global — sem `return`).
4. `server/init.lua`: schema idempotente + sessões com replay-guard (§3.1).
5. `server/core.lua`: `hasPerm` (§3.4) + `rate` (§4.6).
6. `server/<feature>.lua`: handlers `shape → rate → getUser → domínio`; mundo físico **sempre pelos contratos** (`commitVehicleState`, `spawnAt/teleport`, exports money/inventory/garage).
7. `client/`: zonas frias/quentes (§4.1), leituras por State Bag (§4.2), NUI relay puro (§3.9).
8. `sql/schema.sql`: prefixo `vhub_<dom>_`, FK `INT UNSIGNED` CASCADE.
9. `restart vhub_<dom>` → resmon idle dentro do orçamento → smoke do §6.0.
10. Gate final `vhub_guardiao_revisao` (DoD completo).

---

## 10. Quando pedir ajuda dos agentes

| Situação | Agente |
|---|---|
| Estrutural, novo módulo, ownership, linha do Registro | `vhub_arquiteto` |
| `set*Data`, schema, batch/flush, contrato de commit, round-trip | `vhub_guardiao_persistencia` |
| API pública, exports, eventos, descontinuação | `vhub_guardiao_contrato` |
| Auth, permissão, payload, spawn, claim de entidade | `vhub_guardiao_seguranca` |
| Entity, ped, netid, State Bag, bucket | `vhub_guardiao_natives` |
| Thread, loop, batch, serialização, orçamento | `vhub_guardiao_performance` |
| Módulo/helper novo, refactor, código morto | `vhub_guardiao_simplicidade` |
| NUI/CEF/HUD | `vhub_guardiao_designer` / `vhub_designer` |
| Gate final | `vhub_guardiao_revisao` |

---

## 11. Resumo em uma linha

> **"Servidor decide, cliente executa. VRAM é verdade, SQL é backup. Um dono por dado: peça ao dono, nunca escreva no que não é seu. Native antes de helper, evento antes de polling, batch antes de unitário, replay-safe por padrão. PT-BR para o player."**

Se o seu código viola alguma dessas — pare, consulte o Registro de Ownership e o agente da área.

— **Manual** — vHub Mirage — **versão 2.0** (pós-auditoria Void-Zero + IT.1/IT.2 + Governança v2) — 2026-06-10