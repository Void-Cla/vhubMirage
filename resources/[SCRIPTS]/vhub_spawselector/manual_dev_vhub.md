# vHub Mirage — Manual de Desenvolvimento

> **Quem deve ler:** todo dev que toca em `resources/[SCRIPTS]/vhub_*` ou em qualquer recurso que dependa do core vHub.
> **Premissa:** o core (`[CORE]/vhub`) está **CORE FROZEN v1.0 (2026-05-22)** — kernel imutável por 12+ meses. Toda nova feature vive em resource externo.
> **Meta operacional:** servidor com 3.000+ jogadores em resmon **server-total < 0.3 ms/tick**, **client-idle < 0.10 ms**.

## Contrato pós-freeze (o que o core garante)

| Garantia | Onde |
|---|---|
| **`compat: none`** — sem shim vRP. APIs vHub diretas | `server/init.lua` (sem `compat.lua`) |
| **Ordem fixa de carga** | `kernel → state → sql → notify → auth → vehicle → security → boot → exports` |
| **Batch SQL atômico** | `BATCH_MAX=800`, `BATCH_INT=3000ms`, autosave chunked com yield/50 |
| **Login N→1 round-trip** | `vHub.SQL.uidByIdsIn(n)` agrupa identifiers em `IN (?, ?, ?)` |
| **State Bag com threshold** | fuel ±0.5 / eng ±5 / body ±5 / odo ±0.05 km — bypass automático ao cruzar 0 |
| **Adaptive client report** | `client/vehicle.lua` 2000/1000/250 ms por speed/rpm |
| **GC ativo** | `_byNet` cron 5min; `Kernel._rate` purgado em `playerDropped` |
| **Schema único e idempotente** | `sql/schema.sql` aplicado em `bootstrap.lua:307` a cada boot |
| **Tipos PK canônicos** | `vh_users.id`, `vh_characters.id` = `INT UNSIGNED AUTO_INCREMENT` |

**Schemas externos com FK ao core DEVEM usar `INT UNSIGNED`** (signed dispara `errno 150`).

---

## 0. Filosofia em uma página

| Princípio | Tradução prática |
|---|---|
| **Servidor é a única fonte de verdade crítica** | Dinheiro, inventário, ban, propriedade → SQL/VRAM server. Cliente nunca decide. |
| **Cliente é tela, não cérebro** | Cliente renderiza, interage, envia *intenção*. Servidor valida e persiste. |
| **VRAM-first, SQL é backup** | Leitura: VRAM → SQL. Escrita: VRAM + enfileira batch. Sem round-trip síncrono no caminho quente. |
| **Native-first** | Antes de codar helper, ver se existe native FiveM/GTA (`GetVehicleNumberPlateText`, `NetworkRequestControlOfEntity`, etc.). |
| **Evento, não polling** | `AddEventHandler` + State Bags antes de `while true do Wait(N)`. Polling só quando absolutamente necessário (frame loop ativo). |
| **Batch, não unitário** | SQL via `setUData/setCData` → batch. Nunca executar query unitária no caminho quente. |
| **Cada cliente é processador** | Cálculos locais (HUD, física, animação) ficam no cliente; servidor recebe **delta** validado. |
| **Falha graciosa** | `pcall` em pontos de fronteira (export externo, payload de cliente). Nunca derrubar o tick do servidor. |
| **Saídas em PT-BR, código em inglês** | Comentário, log de usuário, NUI = PT-BR. Identificadores, eventos, funções = inglês. |

---

## 1. Anatomia de um resource vHub

Padrão obrigatório:

```
resources/[SCRIPTS]/vhub_<dominio>/
├── shared/
│   ├── config.lua        ← constantes, coords, taxas, cooldowns
│   ├── events.lua        ← VHub<Dom>.E.* (constantes string)
│   └── utils.lua         ← helpers puros (fmtMoney, validators)
├── server/
│   ├── sql.lua           ← queries via exports.oxmysql (NÃO usar S:prepare cross-resource)
│   ├── core.lua          ← sessões, perms locais, exports
│   ├── init.lua          ← bootstrap (LoadResourceFile schema, sessions)
│   ├── <feature>.lua     ← cada feature isolada (1 responsabilidade)
│   └── exports.lua       ← API pública para outros resources
├── client/
│   ├── init.lua          ← state local, NUI focus, callbacks
│   ├── zones.lua         ← markers/blips/[E] event-driven
│   └── <feature>.lua     ← cada feature isolada
├── nui/                  ← (se houver UI)
│   ├── assets/{bg.png, logo.png}
│   ├── css/style.css
│   ├── index.html
│   └── js/{app, sand, view-*}.js
├── sql/
│   └── schema.sql        ← CREATE TABLE IF NOT EXISTS ...
└── fxmanifest.lua
```

**Razões da estrutura:**
- `shared/` carrega primeiro — define namespace e helpers usados por server+client.
- `server/init.lua` faz `LoadResourceFile(name, 'sql/schema.sql')` + setup de sessões.
- `server/<feature>.lua` cada um com **1 responsabilidade** (princípio L-09). Função curta, sem deus-arquivo.
- `nui/` segue padrão do [guardião designer](../.claude/agents/vhub_guardiao_designer.md).

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
  'vhub',           -- SEMPRE
  'oxmysql',        -- SE tiver SQL próprio
  'vhub_inventory', -- SE consumir items
  'vhub_money',     -- SE mexer dinheiro
  'vhub_identity',  -- SE precisar de identidade
  'vhub_groups',    -- SE checar perms
}

shared_scripts {
  'shared/config.lua',
  'shared/events.lua',
  'shared/utils.lua',
}

server_scripts {
  'server/sql.lua',
  'server/core.lua',
  'server/init.lua',
  -- features
  'server/<feature>.lua',
  'server/exports.lua',
}

client_scripts {
  'client/init.lua',
  'client/zones.lua',
  'client/<feature>.lua',
}

ui_page 'nui/index.html'

files {
  'nui/index.html',
  'nui/css/style.css',
  'nui/js/app.js',
  'nui/js/sand.js',
  'nui/js/<view>.js',
  'nui/assets/bg.png',
  'nui/assets/logo.png',
}
```

**Por que essa ordem?** O runtime FiveM carrega `shared → server → client`. Dentro de cada bloco, lê linha a linha — então `sql.lua` tem que vir antes de `core.lua` que usa as queries.

---

## 3. Receitas canônicas (snippets prontos)

### 3.1 Acessar o usuário e dados persistentes

```lua
-- server/<feature>.lua  — em handler de evento, dentro de Citizen.CreateThread
RegisterNetEvent('vhub_dom:doSomething')
AddEventHandler('vhub_dom:doSomething', function(payload)
  local src = source
  Citizen.CreateThread(function()         -- OBRIGATÓRIO se for usar Await
    local user = exports.vhub:getUser(src)
    if not user or not user.char_id then return end

    -- Leitura: VRAM-first (sem round-trip se já cacheado)
    local saldo = exports.vhub:getCData(user.char_id, 'banco') or 0

    -- Escrita: batch (não bloqueia tick)
    exports.vhub:setCData(user.char_id, 'banco', saldo + 100)
  end)
end)
```

**Regras:**
- Sempre `getUser(src)` antes de qualquer coisa. Sem user válido → return.
- Sempre `Citizen.CreateThread` se a função usar `Await` internamente (todos os `get*Data` usam).
- `setCData` é **batch** — não confunda com query síncrona.

### 3.2 Validar permissão

```lua
-- 3 caminhos canônicos:
-- 1) uid == 1 (owner) → bypass
-- 2) ACE vhub.<perm>  → operador setou no server.cfg
-- 3) vhub_groups:hasPermission(src, perm) → grupo concedeu

local function hasPerm(src, perm)
  local uid = exports.vhub:getUID(src)
  if uid == 1 then return true end
  if IsPlayerAceAllowed(src, 'vhub.' .. perm) then return true end
  return exports.vhub_groups:hasPermission(src, perm) == true
end
```

**Anti-pattern:** rodar 3 chamadas duplicadas pelo código. **Pattern:** uma função `hasPerm` em `server/core.lua` do seu resource.

### 3.3 Transação SQL atômica via core

```lua
-- Ex: transferência de dinheiro (player A → B)
local tx = vHub.State:begin()
vHub.setCData(a_char, 'banco', a_saldo - valor, tx)
vHub.setCData(b_char, 'banco', b_saldo + valor, tx)
local ok, err = vHub.State:commit(tx)
if not ok then
  exports.vhub:notify(src, 'Falha: ' .. err)
end
```

**Quando usar TX:** sempre que ≥ 2 escritas precisam suceder/falhar juntas. Para escrita única, `setCData` direto basta.

### 3.4 SQL próprio em resource externo

**Decisão #8 do contexto.md:** resources externos **NÃO usam** `S:prepare/S:query` do core (FiveM serializa tabelas em exports e modificações em `self._prepared` não persistem).

Padrão correto:

```lua
-- server/sql.lua
local ox = function() return exports['oxmysql'] end

local function pquery(sql, args)
  local p = promise.new()
  ox():query(sql, args or {}, function(r) p:resolve(r or {}) end)
  return Citizen.Await(p)
end
local function pexec(sql, args)
  local p = promise.new()
  ox():execute(sql, args or {}, function(r) p:resolve(r) end)
  return Citizen.Await(p)
end
M.query = pquery; M.execute = pexec

-- Schema aplicado em onResourceStart
AddEventHandler('onResourceStart', function(res)
  if res ~= GetCurrentResourceName() then return end
  Citizen.CreateThread(function()
    local schema = LoadResourceFile(res, 'sql/schema.sql')
    if schema then ox():execute(schema, {}, function() end) end
  end)
end)
```

#### 3.4.1 Schema externo — regras canônicas pós-freeze

| Regra | Por quê |
|---|---|
| **`CREATE TABLE IF NOT EXISTS`** | Idempotente, schema aplicado a cada `onResourceStart` |
| **`ENGINE=InnoDB`** | Suporte a transações e FK |
| **`DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`** | Unicode/emoji em nomes |
| **FK ao core → `INT UNSIGNED`** | `vh_users.id` e `vh_characters.id` são `INT UNSIGNED`; FK com tipo divergente dispara MySQL `errno 150` |
| **`ON DELETE CASCADE ON UPDATE CASCADE`** | Apagar usuário/personagem purga dados dependentes automaticamente |
| **`updated_at DATETIME ... ON UPDATE CURRENT_TIMESTAMP`** | Observabilidade gratuita |
| **`dvalue BLOB` (não MEDIUMBLOB)** | Limite 64 KB; suficiente para 99% dos casos. msgpack binário |

Exemplo correto (`vhub_identity/sql/schema.sql`):

```sql
CREATE TABLE IF NOT EXISTS `vh_identity` (
  `char_id`      INT UNSIGNED     NOT NULL,  -- DEVE casar com vh_characters.id
  `firstname`    VARCHAR(50)      NOT NULL DEFAULT '',
  ...
  PRIMARY KEY (`char_id`),
  CONSTRAINT `fk_identity_char` FOREIGN KEY (`char_id`)
    REFERENCES `vh_characters` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

⚠️ Se seu valor pode exceder 64 KB (inventário gigante, log binário), usar `MEDIUMBLOB`. Mas pense antes — frequência de write × tamanho × N players = potencial flood de batch SQL.

### 3.5 Export sensível com `_invoker_allowed`

```lua
-- server/exports.lua
local TRUSTED = {
  ['vhub_admin'] = true,
  ['vhub_garage'] = true,  -- exemplo
}

local function _invoker_allowed()
  local caller = GetInvokingResource()
  if not caller then return true end   -- chamada local OK
  return TRUSTED[caller] == true
end

exports('adminDeleteThing', function(id)
  if not _invoker_allowed() then return false end
  -- ... operação destrutiva
  return true
end)
```

**Regra L-07 + L-04:** export que muta estado **DEVE** validar invoker. Export read-only pode ser público.

### 3.6 Spawn de veículo (servidor decide, cliente executa)

```lua
-- SERVIDOR — fonte da verdade do veículo (existência, dono, status)
RegisterNetEvent('vhub_dom:reqSpawn')
AddEventHandler('vhub_dom:reqSpawn', function(plate)
  local src = source
  Citizen.CreateThread(function()
    -- 1) validar autoridade (servidor decide se pode)
    local v = SQL:getVehicle(plate); if not v then return end
    if v.char_id ~= getCharId(src) then return end
    if v.status == 'impound' then return end

    -- 2) marcar como "out" no banco
    SQL:updateStatus(plate, 'out')

    -- 3) mandar cliente criar a entidade
    TriggerClientEvent('vhub_dom:doSpawn', src, {
      plate = plate, model = v.model,
      pos = { x=g.x, y=g.y, z=g.z, h=g.h },
    })
  end)
end)
```

```lua
-- CLIENTE — executa, sem decidir
RegisterNetEvent('vhub_dom:doSpawn')
AddEventHandler('vhub_dom:doSpawn', function(data)
  Citizen.CreateThread(function()
    local hash = GetHashKey(data.model)
    RequestModel(hash); while not HasModelLoaded(hash) do Citizen.Wait(50) end
    local veh = CreateVehicle(hash, data.pos.x, data.pos.y, data.pos.z + 0.5, data.pos.h, true, false)
    SetVehicleNumberPlateText(veh, data.plate)
    SetEntityAsMissionEntity(veh, true, true)
    SetPedIntoVehicle(PlayerPedId(), veh, -1)
    SetModelAsNoLongerNeeded(hash)
  end)
end)
```

### 3.7 Despawn confiável (mata duplicatas)

Veja [vhub_garage/client/vehicles.lua](../resources/[SCRIPTS]/vhub_garage/client/vehicles.lua) — usa:
1. `TaskLeaveVehicle(ped, veh, 16)` (flag 16 = warp out, sem animação).
2. `NetworkRequestControlOfEntity` + espera real `NetworkHasControlOfEntity`.
3. `SetEntityAsMissionEntity(veh, true, true)` + `DeleteEntity(veh)`.
4. **`scanAndDeleteByPlate`** — varre `FindFirstVehicle`/`FindNextVehicle` e apaga duplicatas pela placa nativa.

**Não use `DecorSetString`** — foi removido do FiveM. A placa do chassi (`GetVehicleNumberPlateText`) é replicada por sync nativo.

### 3.8 NUI — abrir, fechar, callbacks

Veja seção 7 do [`vhub_guardiao_designer.md`](../.claude/agents/vhub_guardiao_designer.md). Resumo:

```lua
-- CLIENTE
local function open()
  SetNuiFocus(true, true)
  SendNUIMessage({ action = 'open', data = { ... } })
end
local function close()
  SetNuiFocus(false, false)
end
RegisterNUICallback('close', function(_, cb) close(); cb({ok=true}) end)
RegisterNUICallback('act', function(data, cb)
  -- Apenas relay para o servidor — NUNCA decidir
  TriggerServerEvent('vhub_dom:act:' .. data.kind, data.fields)
  cb({ok=true})
end)
```

```javascript
// NUI/js/app.js
window.addEventListener('message', e => {
  if (e.data.action === 'open') { /* render */ }
  if (e.data.action === 'close') { /* hide */ }
});
async function call(cb, data) {
  return fetch(`https://${GetParentResourceName()}/${cb}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data || {}),
  }).then(r => r.json().catch(() => ({})));
}
```

---

## 4. Padrões de performance (resmon < 0.3 ms)

### 4.1 Frame loop só quando NECESSÁRIO

❌ **Errado:**
```lua
Citizen.CreateThread(function()
  while true do
    Citizen.Wait(0)
    -- desenha marker sempre, mesmo longe
    DrawMarker(1, x, y, z, ...)
  end
end)
```

✅ **Correto:**
```lua
local proximo = false

-- thread fria — só checa proximidade 1x/s
Citizen.CreateThread(function()
  while true do
    Citizen.Wait(1000)
    local d = #(GetEntityCoords(PlayerPedId()) - vector3(x, y, z))
    proximo = d < 30.0
  end
end)

-- thread quente — só roda quando perto
Citizen.CreateThread(function()
  while true do
    if not proximo then Citizen.Wait(500)
    else
      Citizen.Wait(0)
      DrawMarker(1, x, y, z, ...)
    end
  end
end)
```

**Ganho:** 99% do tempo o frame loop está dormindo. resmon idle ≈ 0.

### 4.2 State Bag antes de RegisterNetEvent

Para dados que o servidor já decidiu e precisam estar **disponíveis** em vários scripts client:

❌ **Errado:** RegisterNetEvent + TriggerServerEvent toda vez que precisa ler.

✅ **Correto:**
```lua
-- SERVIDOR
Player(src).state:set('vhub_dom_role', 'police', true)

-- CLIENTE (em qualquer resource)
local role = LocalPlayer.state.vhub_dom_role
-- ou listener:
AddStateBagChangeHandler('vhub_dom_role', `player:${GetPlayerServerId(PlayerId())}`,
  function(_, _, value) handle(value) end)
```

State Bag é **replicado por sync nativo do GTA** — sem custo de rede extra, sem evento custom, sem polling.

### 4.3 Cache de export externo

❌ **Errado:**
```lua
function getRole(src)
  return exports.vhub_groups:hasPermission(src, 'police')
end
-- chamado a cada interação
```

Cada `exports.X:func()` é um round-trip cross-resource. Em 3k players, hot path quebra.

✅ **Correto:**
```lua
local _role_cache = {}
AddEventHandler('vhub_groups:changed', function(src) _role_cache[src] = nil end)
AddEventHandler('playerDropped', function() _role_cache[source] = nil end)

local function getRole(src)
  if _role_cache[src] ~= nil then return _role_cache[src] end
  local v = exports.vhub_groups:hasPermission(src, 'police')
  _role_cache[src] = v
  return v
end
```

**Regra:** sempre que o valor for relativamente estável (perm, identidade, role), cachear e invalidar via evento.

### 4.4 Adaptive rate em report cliente

O core pós-freeze JÁ aplica isso em [client/vehicle.lua](../resources/[CORE]/vhub/client/vehicle.lua):
- parado (`speed_kmh < 1`) → **2000 ms** (0.5Hz)
- idle/motor baixo (`rpm < 0.2`) → **1000 ms** (1Hz)
- dirigindo → **250 ms** (4Hz)
- fora de veículo → **1000 ms**

Para um resource novo de UI/HUD, replicar o padrão:

```lua
local function adaptiveDelay()
  local ped = PlayerPedId()
  if IsEntityDead(ped) then return 5000 end       -- morto: 0.2Hz
  if not IsPedInAnyVehicle(ped, false) then return 1000 end  -- a pé: 1Hz
  return 250                                       -- dirigindo: 4Hz
end

Citizen.CreateThread(function()
  while true do
    Citizen.Wait(adaptiveDelay())
    -- coleta + envia
  end
end)
```

**Ganho real:** com 3k drivers e 30% parado em semáforo, sai de 12k events/s para ~1.5k events/s (-87%).

### 4.5 Batch de SQL próprio

Se o resource grava muito (ex: log de ações), use o **batch do core**:

```lua
-- ruim: 100 INSERTs unitários
for _, log in ipairs(logs) do
  exports.oxmysql:execute('INSERT INTO logs ...', { ... })
end

-- bom: 1 multi-insert
local values, args = {}, {}
for _, log in ipairs(logs) do
  values[#values+1] = '(?, ?, ?)'
  args[#args+1] = log.actor; args[#args+1] = log.action; args[#args+1] = log.payload
end
exports.oxmysql:execute(
  'INSERT INTO logs (actor, action, payload) VALUES ' .. table.concat(values, ','),
  args
)
```

Ou enfileira no batch do core via `vHub.setCData` se for dado de personagem.

### 4.6 NUI custom < 0.05 ms idle

- `vhubSand.stop()` em `close` (mata `requestAnimationFrame`).
- `setInterval` ou timer JS → `clearInterval` em `close`.
- `MutationObserver`/`ResizeObserver` apenas com debounce.
- Backdrop com `backdrop-filter` é **caro em GPU** — só renderiza quando NUI visível (`display: none` quando fechado).
- Fontes via Google Fonts: preconnect já é padrão; preload se for crítica.

---

## 5. Antipadrões (não fazer)

| Antipadrão | Por quê | Pattern |
|---|---|---|
| `while true do Wait(0)` sempre ativo | resmon spike, não desliga | Frame loop **condicional** (item 4.1) |
| `TriggerServerEvent` em response a `Wait(0)` (4Hz fixo) | 12k events/s em 3k drivers | Adaptive rate (4.4) |
| `exports.X:func()` em loop quente | round-trip × N | Cache + invalidação por evento (4.3) |
| `SetEntityCoords` sem `RequestCollisionAtCoord` + wait | player cai no void | Sempre carregar colisão antes |
| `DecorSetString` | **removido do FiveM** | `SetVehicleNumberPlateText` (placa nativa) ou State Bag |
| `print()` solto | poluição de log | `vHub.Logger:info/warn/error` |
| Lógica de negócio em NUI JS | bypassável | Server decide; NUI só envia intenção |
| `Citizen.Await` fora de thread | crash | `Citizen.CreateThread` + `vHub.assertThread()` |
| `exports.oxmysql:query` em loop hot | satura DB | Batch ou multi-insert |
| Tabela `[src]` sem limpeza em `playerDropped` | memory leak | Sempre handler de drop |
| Polling de player position via `GetEntityCoords` em loop frame | CPU spike | State Bag + listener |
| Validar payload no client | trivialmente burlado | Server revalida tudo |
| `for _ in pairs(big_table)` na thread principal | stall | Wait(0) a cada N (P0-5) |
| `SetTimeout` recursivo sem cap | stack overflow | Trocar por `Citizen.CreateThread` + while |
| FK `char_id INT` (signed) ao core | `errno 150` na criação | Sempre `INT UNSIGNED` em FK para `vh_users.id`/`vh_characters.id` |
| `dvalue MEDIUMBLOB` em tabela KV nova | desperdiça buffer InnoDB | `BLOB` (64 KB) basta para 99%; só usar MEDIUMBLOB se realmente passa de 64 KB |
| Chamar `_G.vRP`/`_G.Proxy`/`_G.Tunnel` | shim foi removido — `nil` em runtime | Usar `exports.vhub:*` direto |
| Listener de `vHub:doSpawn`/`vHub:savePos` | eventos aposentados na decisão #7 | Usar `vhub_player_state:apply` (resource externo) |
| Bloquear thread principal por > 5 ms | autosave atrasa, replicação trava | `Citizen.Wait(0)` a cada N iterações (padrão 50) |

---

## 6. Checklist de release (todo PR de resource passa)

### 6.1 Estrutura
- [ ] Pastas seguem o template da seção 1?
- [ ] `fxmanifest.lua` declara todas as dependências?
- [ ] `schema.sql` (se houver) usa `CREATE TABLE IF NOT EXISTS`?
- [ ] FK para `vh_users.id` ou `vh_characters.id` declarada como `INT UNSIGNED`?
- [ ] Schema tem `ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`?
- [ ] FK ao core com `ON DELETE CASCADE ON UPDATE CASCADE`?

### 6.2 Servidor
- [ ] Toda função pública tem comentário PT-BR de uma linha (L-10)?
- [ ] `Citizen.CreateThread` em toda função que usa `Await` (L-09)?
- [ ] Validação server-side em **toda** decisão crítica (L-01)?
- [ ] Export sensível tem `_invoker_allowed` (L-07)?
- [ ] Sem SQL inline — usa `exports.oxmysql:query/execute` em wrapper?
- [ ] Handler `playerDropped` limpa qualquer tabela `[src]`?

### 6.3 Cliente
- [ ] Frame loop está condicional (não roda em idle)?
- [ ] `SetNuiFocus(false, false)` em todo close?
- [ ] `requestAnimationFrame` cancelado quando NUI fecha?
- [ ] Cache de export externo (perm, identidade)?

### 6.4 NUI
- [ ] Theme vHub aplicado (logo, areia, dourado, liquid glass)? Ver [guardião designer](../.claude/agents/vhub_guardiao_designer.md).
- [ ] `<meta charset="UTF-8">` + `<html lang="pt-BR">`?
- [ ] Sem acentos quebrados (grep `c o`, `s o`, `n o`)?
- [ ] Glossário PT-BR (Curar/Expulsar/Prender, não Heal/Kick/Jail)?

### 6.5 Performance
- [ ] Medido com `resmon` em ambiente com 50+ players simulados?
- [ ] Server resmon < 0.1 ms/tick idle?
- [ ] Client resmon < 0.05 ms/tick idle (quando NUI fechado)?
- [ ] DB latency média < 5 ms por query simples?

### 6.6 Segurança
- [ ] Payload do cliente é validado (tipos, ranges, tamanho)?
- [ ] Rate limit em events de cliente (opts.rate)?
- [ ] Logs de ações sensíveis (`Core:audit` ou equivalente)?

---

## 7. Como medir resmon (e bater 0.3 server-total)

### 7.1 Comandos in-game
```
resmon          # janela com todos os resources, cpu/mem
strdbg          # streaming debugger
status          # players connected
profiler record # gravação detalhada
```

### 7.2 O que olhar
- **server-tick**: tempo médio que o servidor leva por tick. Alvo: < 0.3 ms com 100+ players.
- **resource cpu**: cada resource deve ficar < 0.05 ms idle e < 0.2 ms ativo.
- **net out**: tráfego enviado. Picos > 1 MB/s indicam State Bag flood.

### 7.3 Estratégia top-down
1. Rodar servidor em estado idle (sem ações). Anotar baseline.
2. Conectar 1 player. Anotar delta.
3. Simular pico (10/50/100 players via `txAdmin` simulator). Identificar resources que escalam **superlinear**.
4. Atacar os 3 mais caros — geralmente são scripts com loop frame ativo.

### 7.4 Threshold de alerta
- Server tick > 0.5 ms → vermelho.
- Single resource > 0.3 ms → vermelho.
- Net out > 500 KB/s constante → vermelho.

---

## 8. Como o vHub se diferencia de vRP/ESX/qbcore

| Característica | vRP1 | vRP2 | ESX | qbcore | **vHub** |
|---|---|---|---|---|---|
| VRAM-first | ❌ | ⚠️ | ⚠️ | ⚠️ | ✅ |
| Batch SQL transacional | ❌ | ❌ | ❌ | ⚠️ | ✅ |
| Driver plugável (`registerStateDriver`) | ❌ | ❌ | ❌ | ❌ | ✅ |
| Authoritative server bag (State Bag canônica) | ❌ | ❌ | ⚠️ | ⚠️ | ✅ |
| `NetworkSetEntityOwner` em driver | ❌ | ❌ | ❌ | ⚠️ | ✅ |
| Rate-limit por evento O(1) | ❌ | ❌ | ❌ | ❌ | ✅ |
| Spawn nativo (sem `spawnmanager`) | ❌ | ❌ | ❌ | ❌ | ✅ |
| `assertThread` em APIs com Await | ❌ | ❌ | ❌ | ❌ | ✅ |
| `_invoker_allowed` em exports sensíveis | ❌ | ❌ | ⚠️ | ⚠️ | ✅ |
| TX com rollback validável | ❌ | ❌ | ❌ | ❌ | ✅ |
| Adaptive client report (não-fixed Hz) | ❌ | ❌ | ❌ | ❌ | ✅ |
| State Bag com gating delta | ❌ | ❌ | ❌ | ❌ | ✅ |
| Schema único com FK CASCADE em todas as deps | ❌ | ❌ | ❌ | ⚠️ | ✅ |

**Conclusão técnica:** o vHub é o primeiro GTARP brasileiro que alinha:
1. **Memory-first** (VRAM como source of truth runtime)
2. **Persistência preguiçosa** (batch transacional `BATCH_MAX=800`)
3. **Autoridade GTA explícita** (NetworkSetEntityOwner controlado)
4. **Modularidade** (driver SQL plugável; spawn delegado a resource externo)
5. **Performance adaptativa** (cliente reduz Hz quando parado; servidor descarta delta abaixo do threshold)
6. **Zero legado** (`compat: none` — sem shim vRP/Proxy/Tunnel)

---

## 9. Como criar um novo resource em 15 minutos

1. Copiar a estrutura template (seção 1) para `resources/[SCRIPTS]/vhub_<dom>/`.
2. Editar `fxmanifest.lua` (seção 2).
3. Em `shared/config.lua`: criar `VHub<Dom> = {}; VHub<Dom>.cfg = { ... }`.
4. Em `shared/events.lua`: criar `VHub<Dom>.E = { ... }`.
5. Em `server/init.lua`: load schema + sessões:
```lua
AddEventHandler('onResourceStart', function(res)
  if res ~= GetCurrentResourceName() then return end
  Citizen.CreateThread(function()
    local schema = LoadResourceFile(res, 'sql/schema.sql')
    if schema then exports.oxmysql:execute(schema, {}, function() end) end
  end)
end)
AddEventHandler('vHub:characterLoad', function(user) sessions[user.source] = user end)
AddEventHandler('playerDropped', function() sessions[source] = nil end)
```
6. Em `server/<feature>.lua`: handlers de net + lógica.
7. Em `client/init.lua`: NUI open/close + callbacks.
8. Em `nui/`: copiar `bg.png` + `logo.png` do `vhub_garage` e seguir o **guardião designer**.
9. Em `sql/schema.sql`: usar template canônico (ver 3.4.1) — **FK ao core sempre `INT UNSIGNED`**.
10. `restart vhub_<dom>` e validar resmon.

---

## 10. Quando pedir ajuda dos agentes

| Situação | Agente |
|---|---|
| Mudança estrutural, novo módulo, dúvida de ownership | `vhub_arquiteto` |
| Tocar API pública, exports, schema, `shared/events.lua` | `vhub_guardiao_contrato` |
| Tocar auth, permissão, evento cliente, spawn, ban | `vhub_guardiao_seguranca` |
| Tocar entity, ped, netid, State Bag, spawn, vehicle | `vhub_guardiao_natives` |
| Tocar thread, loop, batch SQL, serialização | `vhub_guardiao_performance` |
| Criar módulo, helper, refactor | `vhub_guardiao_simplicidade` |
| Tocar NUI, CEF, HUD, client/, SendNUIMessage | `vhub_guardiao_designer` |
| Gate final antes de commit relevante | `vhub_guardiao_revisao` |

Invocação via `Agent` tool com `subagent_type` correspondente. **Sempre** rodar `vhub_guardiao_revisao` no final.

---

## 11. Resumo em uma linha

> **"Servidor decide, cliente executa. VRAM é verdade, SQL é backup. Native antes de helper. Evento antes de polling. Batch antes de unitário. PT-BR para o player, inglês para a máquina."**

Se o seu código viola alguma dessas 6 — pare e revise.

— **Manual** — vHub Mirage — versão 1.1 (pós Frozen v1.0) — 2026-05-22
