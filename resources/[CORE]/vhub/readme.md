# vHub Mirage — Core vHub: Documentação Técnica Completa

> **Status:** CORE FROZEN v1.0 — selado em 2026-05-22.
> Qualquer alteração exige justificativa + aprovação dos guardiões + bump para v2.0.
>
> **resmon medido:** 0.02ms idle (alvo < 0.05ms). LOC: 2.432.

---

## Sumário

1. [O que é e para que serve](#1-o-que-é-e-para-que-serve)
2. [Mapa de arquivos](#2-mapa-de-arquivos)
3. [Fluxo de inicialização — do boot ao primeiro jogador](#3-fluxo-de-inicialização)
4. [shared/ — Fundação comum](#4-shared--fundação-comum)
5. [server/kernel.lua — Barramento central](#5-serverkernel)
6. [server/state.lua — Gerenciador de estado VRAM-first](#6-serverstate)
7. [server/sql.lua — Repositório de queries](#7-serversql)
8. [server/auth.lua — Autenticação e sessões](#8-serverauth)
9. [server/vehicle.lua — Gestão de veículos](#9-servervehicle)
10. [server/security.lua — Camada de segurança](#10-serversecurity)
11. [server/notify.lua — Notificações](#11-servernotify)
12. [server/boot.lua — Lifecycle e net events](#12-serverboot)
13. [server/exports.lua — API cross-resource](#13-serverexports)
14. [client/bootstrap.lua — Entry point cliente](#14-clientbootstrap)
15. [client/vehicle.lua — Report adaptativo](#15-clientvehicle)
16. [sql/schema.sql — Schema idempotente](#16-sqlschema)
17. [Sistema de transações com rollback](#17-transações)
18. [Rate limiting O(1)](#18-rate-limiting)
19. [Serialização msgpack](#19-serialização-msgpack)
20. [Pontos fortes — o que funciona muito bem](#20-pontos-fortes)
21. [Limitações e trade-offs honestos](#21-limitações-e-trade-offs)
22. [Guia do desenvolvedor — construindo sobre o core](#22-guia-do-desenvolvedor)
23. [Referência rápida de API](#23-referência-rápida-de-api)

---

## 1. O que é e para que serve

O core `vhub` é a espinha dorsal do framework vHub Mirage. É o único resource que detém
autoridade máxima sobre o estado do servidor. Tudo o que outros resources fazem passa por
ele, seja para ler dados de jogadores, registrar veículos, emitir eventos ou verificar permissões.

**Por que existe:**
Frameworks FiveM tradicionais (vRP 1/2/3) sofriam com três problemas estruturais:

1. **Race conditions em user_id**: múltiplos LAST_INSERT_ID sem transação criavam IDs duplicados
2. **Latência de SQL**: toda leitura ia ao banco, mesmo para dados consultados 100× por segundo
3. **Acoplamento total**: qualquer resource podia escrever SQL diretamente, sem validação

O core resolve os três:
1. Alocador server-side com `_next_user_id` seedado de `MAX(id)` — Lua é single-thread, sem race
2. VRAM-first: dados lidos de memória; banco só quando a memória não tem
3. Único ponto de escrita SQL: `server/state.lua` gerencia toda a persistência

**O que o core NÃO faz:**
- Não gerencia inventário, dinheiro, grupos ou identidade — esses são resources externos
- Não decide onde o jogador spawna — isso é responsabilidade de `vhub_player_state`
- Não tem UI — o core é 100% server-side (exceto 2 arquivos client leves)

---

## 2. Mapa de arquivos

```
resources/[CORE]/vhub/
│
├── fxmanifest.lua         Declaração FiveM: dependências, ordem de carga, versão
├── bootstrap.lua          Ponto de entrada: cria driver oxmysql, valida, inicia tudo
├── base.lua               Carrega server/init.lua via load() no _ENV global
│
├── shared/                Carregados em AMBOS server e client — rodam antes de tudo
│   ├── config.lua         Cria vHub = {}, mergeConfig, validateConfig, _normLevel
│   ├── events.lua         vHub.E.* — constantes read-only de todos os eventos
│   ├── utils.lua          Helpers puros: formatNumber, dataCopy, clamp, tableSize...
│   └── logger.lua         Único ponto de log estruturado (vHub.Logger)
│
├── server/
│   ├── init.lua           OOP helper (vHub.class), assertThread, loadmod, registerStateDriver
│   ├── kernel.lua         K:net, K:on, K:emit, K:export — barramento central
│   ├── state.lua          VRAM (_mem), TX (begin/commit/rollback), batch SQL
│   ├── sql.lua            Todos os S:prepare() — SQL centralizado aqui
│   ├── notify.lua         Webhooks Discord com retry automático
│   ├── auth.lua           Sessões, identifiers, ban, multi-char
│   ├── vehicle.lua        VehicleData, State Bags, autoridade de entidade
│   ├── security.lua       checkPayload, requireAdmin, _permFail
│   ├── boot.lua           vHub:init(), net events, autosave, GC, lifecycle
│   └── exports.lua        Exports cross-resource com whitelist de invocadores
│
├── client/
│   ├── bootstrap.lua      Ready único via playerSpawned + fallback nativo
│   └── vehicle.lua        Report de estado (fuel, rpm, health) 0.5–4Hz adaptativo
│
└── sql/
    └── schema.sql         8 tabelas InnoDB, idempotente, FK CASCADE, aplicado a cada boot
```

---

## 3. Fluxo de inicialização

Entender a ordem de carga é fundamental para debugar problemas de startup.

### Fase 1 — FiveM carrega os shared_scripts (ambos lados)

```
shared/config.lua    → cria rawset(_G, "vHub", {}) se não existir
                       define mergeConfig, validateConfig
shared/events.lua    → popula vHub.E com constantes read-only
shared/utils.lua     → popula vHub.Utils com helpers puros
shared/logger.lua    → popula vHub.Logger
```

Depois dessa fase, `vHub` existe mas está incompleto — tem Logger e Utils,
mas não tem State, Auth, Kernel, nem a função `init`.

### Fase 2 — FiveM executa bootstrap.lua (server-side)

`bootstrap.lua` é o único `server_script` declarado no fxmanifest. Ele:

1. Chama `criar_config()` — lê convars (`vhub_log_level`, `vhub_save_interval`, etc.)
2. Chama `criar_driver()` — instancia o driver oxmysql interno
3. Chama `validar_driver(driver)` — verifica que `init/prepare/query/batch` existem
4. Chama `carregar_base()` — faz `LoadResourceFile("base.lua")` e executa via `load()`
5. `base.lua` então faz `LoadResourceFile("server/init.lua")` e executa
6. `server/init.lua` chama `loadmod()` para cada módulo na ordem obrigatória:
   `kernel → state → sql → notify → auth → vehicle → security → boot → exports`
7. `validar_base(vhub)` — confirma que `init, State, Kernel, Auth, Vehicle, Security, Notify` existem
8. `vHubRuntime:init(config, driver)` — chama `boot.lua:vHub:init()` que:
   - Chama `vHub.State:setDriver(driver)` → conecta ao banco, aplica prepares, seed de alocadores
   - Registra todos os `AddEventHandler` (playerDropped, onResourceStart, etc.)
   - Registra todos os `K:net` (vHub:ready, vHub:vState, etc.)
   - Inicia o timer de autosave
9. `aplicar_schema(driver)` — executa `sql/schema.sql` (CREATE TABLE IF NOT EXISTS)
10. `Boot.pronto = true` — sistema pronto

**Se qualquer etapa falhar**, `falhar()` é chamado, que loga e lança `error()`,
impedindo o resource de ficar no estado "started" parcialmente.

### Fase 3 — FiveM carrega os client_scripts

```
client/bootstrap.lua   → aguarda playerSpawned (ou executa fallback nativo)
client/vehicle.lua     → loop adaptativo de report
```

### Fase 4 — Jogador conecta

```
playerConnecting  → apenas deferrals.done() (sem autenticação aqui)
playerSpawned     → cliente envia TriggerServerEvent("vHub:ready")
vHub:ready        → servidor chama Auth:connect(src)
                  → Auth:connect resolve identifiers → cria/recupera uid
                  → verifica ban → verifica whitelist
                  → cria User object → carrega datatable
                  → TriggerEvent("vHub:characterLoad", user)
                  → SetTimeout(500) → TriggerEvent("vHub:playerSpawn", user, true)
                  → K:emit(src, "vHub:initDone", uid, char_id, true)
```

**Por que playerConnecting não autentica?**
Se a autenticação ocorresse em `playerConnecting`, a janela entre o connecting e o
`vHub:ready` poderia ser explorada para duplicar sessões. Autenticar apenas no
`vHub:ready` garante que o jogador já está no servidor e ativo.

---

## 4. shared/ — Fundação comum

### shared/config.lua

Primeiro script a executar — não pode ter dependências.

```lua
-- Cria o namespace global vHub, se não existir
if type(rawget(_G, "vHub")) ~= "table" then
  rawset(_G, "vHub", {})
end
```

Usa `rawget/_G_` ao invés de `vHub` direto para não acionar metatables no
processo de reload. Detalhe crítico: se um resource recarregar, os shared_scripts
executam de novo. O `rawget` garante que o vHub existente não seja sobrescrito.

**mergeConfig(user_cfg)** — aplica defaults em cima da config do usuário.
Só preenche campos que estão `nil` no user_cfg. Nunca sobrescreve o que o usuário definiu.

**validateConfig(cfg)** — retorna `(bool, { "campo: msg", ... })`.
Útil para resources externos validarem a config antes de usar.

**Defaults documentados:**

| Campo | Default | Descrição |
|-------|---------|-----------|
| `log_level` | `"INFO"` | `DEBUG/INFO/WARN/ERROR` |
| `save_interval` | `60` | Segundos entre autosaves |
| `max_payload` | `8192` | Bytes máx. por net event |
| `whitelist_enabled` | `false` | Exige whitelist para conectar |
| `trusted_resources` | `{}` | Resources que podem usar exports sensíveis |
| `max_ping` | `800` | ms acima = kick (se `ping_check_enabled`) |
| `fuel_rate` | `0.01` | Consumo de combustível por RPM/tick |
| `veh_state_hz` | `4` | Hz de report de estado do veículo |

### shared/events.lua

Define `vHub.E` como tabela read-only via metatable:

```lua
vHub.E = setmetatable({}, {
  __index    = _E,
  __newindex = function(_, k)
    error("[vHub][EVENTS] Constante somente-leitura: " .. tostring(k), 2)
  end,
})
```

Por que read-only? Scripts mal escritos (ou maliciosos) não conseguem
redirecionar eventos ao trocar o valor de uma constante.

Qualquer tentativa de `vHub.E.NET_READY = "outra_coisa"` lança erro com stacktrace.

### shared/utils.lua

Helpers puros — sem side-effects, sem `print`, sem dependências externas.

**dataCopy(t)** — cópia profunda de 1 nível. Suficiente para `user.data` porque
os valores são escalares ou tabelas rasas (não há hierarquias de 3+ níveis em dados de jogador).

```lua
-- Correto: grava uma cópia, não a referência viva
vHub.setUData(uid, "datatable", vHub.Utils.dataCopy(user.data))
-- Errado: gravaria a referência — user.data cresceria indefinidamente no msgpack
vHub.setUData(uid, "datatable", user.data)
```

**normalizePlate(p)** — uppercase, trim, valida charset GTA (`[A-Z0-9 ]`).
Idêntica à `normalizePlate` local em `server/vehicle.lua`. A duplicação é
intencional: a `Utils` é client+server, a local em vehicle é server-only.

### shared/logger.lua

```lua
vHub.Logger:info("meu_modulo", "mensagem", { dados = opcionalJSON })
vHub.Logger:debug("meu_modulo", "só em log_level=DEBUG")
vHub.Logger:warn("meu_modulo", "algo suspeito")
vHub.Logger:error("meu_modulo", "algo crítico")
```

**Aceita `log_level` como número (0–3) ou string (`"DEBUG"–"ERROR"`).**
Isso é necessário porque o convar `GetConvarInt` retorna número, mas a config
normalizada usa strings. O logger lida com ambos via `_normLevel`.

Output: `[vHub][LEVEL][modulo] mensagem {"campo":"valor"}`

**Regra de ouro:** nenhum módulo usa `print()` — apenas `vHub.Logger`.
Isso permite filtrar logs por nível (convar `vhub_log_level`) sem alterar código.

---

## 5. server/kernel.lua

O Kernel é o barramento central. Não gerencia dados de negócio — gerencia
comunicação e controle de acesso.

### K:net — registrador de net events seguro

```lua
vHub.Kernel:net("meu:evento", function(src, arg1, arg2)
  -- src já validado (> 0)
  -- payload já checado por checkPayload
  -- rate limit já verificado
  -- permissão já verificada (se opts.perm)
  -- esta função roda em Citizen.CreateThread (async = true por padrão)
end, {
  rate  = { max_hits, janela_ms, block_ms },
  perm  = "minhaPermissao",        -- opcional: bloqueia sem a permissão
  admin = true,                    -- alias para perm = "admin.*"
  async = false,                   -- opcional: roda inline (sem thread)
})
```

**Sequência interna de um K:net:**
1. Rejeita `src <= 0` (eventos do servidor ou sources inválidos)
2. Calcula tamanho do payload (msgpack preferido, json como fallback)
3. `Security:checkPayload` — rejeita se exceder `max_payload`
4. `_rateOK` — sliding window O(1)
5. Verifica permissão (se `opts.perm`)
6. Executa handler em thread (async=true) ou inline (async=false)
7. Erros no handler são capturados por `pcall` — nunca crasham o servidor

**async=false** é para eventos críticos de alta frequência como `vHub:vState`
(8× por segundo por jogador) onde o custo de criar uma thread supera o benefício.

### K:_rateOK — sliding window O(1)

```lua
-- Estrutura: _rate["src:acao"] = { hits, window, blocked }
-- max=8, win=1000ms, block=5000ms
-- significa: máximo 8 chamadas por 1s; se exceder, bloqueia por 5s
```

A chave `src:acao` é limpa em `playerDropped` (GC imediato) e por
uma thread de limpeza geral a cada 2 minutos (entradas inativas > 3min).

**Por que O(1)?** Com 300 players e 10 eventos cada = 3.000 entradas no hash.
Uma verificação é `table[key]` — tempo constante independente do tamanho.

### K:export — exports via evento interno FiveM

```lua
function K:export(name, fn)
  AddEventHandler("__cfx_export_" .. GetCurrentResourceName() .. "_" .. name,
    function(setCb) setCb(fn) end)
end
```

Este é o mecanismo que o próprio FiveM usa internamente quando você chama
`exports[resource]:method()`. Usar diretamente permite registrar exports sem
declará-los no fxmanifest. **Isso é uma decisão intencional**: os exports do
core são dinâmicos (registrados em runtime) e não precisam de declaração estática.

### K:emit / K:broadcast

```lua
vHub.Kernel:emit(src, "evento:cliente", arg1, arg2)  -- para 1 jogador
vHub.Kernel:broadcast("evento:cliente", arg1)         -- para todos
```

Wrappers finos sobre `TriggerClientEvent`. Existem para documentar explicitamente
que o evento vai para o cliente — diferente de `TriggerEvent` que é server-local.

---

## 6. server/state.lua

O módulo mais crítico do core. Toda leitura e escrita de dados persistentes passa por aqui.

### Estrutura de memória

```lua
S._mem = {}  -- { [etype][eid][key] = value }
```

`etype` = tipo de entidade: `"ud"` (user data), `"cd"` (char data), `"vd"` (vehicle data), `"gd"` (global data)
`eid` = identificador: user_id, char_id, plate, ou `"__g"` para global
`key` = chave lógica: `"datatable"`, `"ban.active"`, `"state"`, etc.

Exemplo: `S._mem["ud"][42]["ban.active"]` = estado de ban do usuário 42 em memória.

### S:get — leitura VRAM

```lua
function S:get(et, eid, key)
  local t = self._mem[et]; if not t then return nil end
  local e = t[eid];        if not e then return nil end
  if key ~= nil then return e[key] end  -- retorna e[key] (pode ser nil)
  return e                              -- sem key: retorna a tabela inteira
end
```

**Bug histórico corrigido:** antes desta versão, a linha era:
```lua
return key ~= nil and e[key] or e  -- BUG: retornava e quando e[key] era nil
```
Quando `key = "ban.active"` e o valor era `nil` (não banido), o `and/or` retornava
`e` (a tabela inteira do usuário) — truthy — causando falso-positivo no ban check.
O `if/then` resolve sem ambiguidade.

### S:set — escrita VRAM com snapshot de TX

```lua
function S:set(et, eid, key, val, tx)
  -- cria hierarquia se não existe
  if not self._mem[et]      then self._mem[et] = {} end
  if not self._mem[et][eid] then self._mem[et][eid] = {} end
  -- se tem TX ativa, salva o valor ANTERIOR para rollback
  if tx then
    local sk = et.."\0"..tostring(eid).."\0"..key
    if self._snap[tx][sk] == nil then
      self._snap[tx][sk] = { et=et, eid=eid, key=key, prev = self._mem[et][eid][key] }
    end
  end
  self._mem[et][eid][key] = val
end
```

O snapshot guarda o valor ANTERIOR (antes da mutação). Se `rollback` for chamado,
restaura `prev` para cada chave modificada. A chave composta `et\0eid\0key` usa
`\0` como separador porque `\0` não pode aparecer em strings normais de dados.

### S:invalidate — força leitura do banco na próxima consulta

```lua
S:invalidate(et, eid, key)  -- seta e[key] = nil
```

Após `_set`, a maioria das chaves é invalidada para que a próxima leitura
vá ao banco e receba o valor limpo serializado. Isso evita o "datatable crescente":
sem invalidação, a VRAM manteria uma referência para o objeto vivo de `user.data`,
e ao serializar via msgpack, o tamanho cresceria a cada autosave.

**Hot keys que NÃO são invalidadas:**
- `ban.active` — precisa de acesso instantâneo no `Auth:connect` sem round-trip
- `whitelist` — idem
- `permissions` — idem

Essas 3 chaves têm semântica especial: uma vez em VRAM, permanecem até
`S:invalidate` ser chamado explicitamente ou o resource reiniciar.

### S:_queue e S:_flush — batch SQL

```lua
S:_queue(op)  -- op = { "vh/nome_query", { param = valor } }
```

Toda operação de escrita vai para `_batch`. A cada BATCH_MAX=800 operações,
ou a cada BATCH_INT=3000ms, `_flush` é chamado.

**Flush com re-entrância controlada:**
```lua
function S:_flush()
  if self._batchN == 0 or not self._ready or self._flushing then return end
  self._flushing = true
  local ops, n = self._batch, self._batchN
  self._batch, self._batchN = {}, 0   -- troca atômica: batch novo já pronto
  Citizen.CreateThread(function()
    local ok, r = pcall(self._driver.batch, ...)
    if not ok then
      -- falha: reinsere as ops no INÍCIO do batch atual
      -- preserva ordem: ops antigas antes das novas
    end
    self._flushing = false
    if self._batchN > 0 then self:_flush() end  -- drena ops que chegaram durante flush
  end)
end
```

O `_flushing` guard previne que o timer (3s) e o gate de 800 ops disparem
simultaneamente dois flushes. A troca `self._batch = {}` antes de chamar o
driver garante que novas ops que chegam durante o flush vão para um batch
novo, não para o que está sendo processado.

### Fluxo completo de read/write

```
vHub.getUData(uid, "money")
  → S:get("ud", uid, "money")
  → se != nil: retorna diretamente (zero DB)
  → se nil: Citizen.Await(S:scalar("vh/get_ud", {user_id=uid, key="money"}))
  → desserializa msgpack → armazena em _mem["ud"][uid]["money"] → retorna

vHub.setUData(uid, "money", 5000, tx?)
  → S:set("ud", uid, "money", 5000, tx?) — atualiza VRAM + snapshot TX
  → S:_queue({"vh/set_ud", {user_id=uid, key="money", value=msgpack.pack(5000)}})
  → S:invalidate("ud", uid, "money") — se não for hot key
```

### API pública de dados

```lua
-- Todos exigem Citizen.CreateThread no chamador
vHub.getUData(user_id, "chave")           → value | nil
vHub.setUData(user_id, "chave", val, tx?) → void
vHub.getCData(char_id, "chave")           → value | nil
vHub.setCData(char_id, "chave", val, tx?) → void
vHub.getVData(plate,   "chave")           → value | nil
vHub.setVData(plate,   "chave", val, tx?) → void
vHub.getGData("chave")                    → value | nil
vHub.setGData("chave", val, tx?)          → void
```

**Por que exigem Citizen.CreateThread?**
Se a VRAM não tiver o valor, a função faz `Citizen.Await()` internamente.
`Citizen.Await` só funciona dentro de uma coroutine (thread Citizen). Chamar
essas funções fora de thread causaria crash silencioso ou bloqueio do servidor.

`vHub.assertThread()` lança erro explícito se a chamada for fora de thread,
tornando o problema fácil de diagnosticar.

---

## 7. server/sql.lua

Único lugar onde SQL é declarado no core. Regra inviolável:
**nenhum outro arquivo do core tem SQL hardcoded**.

### Estrutura de um prepare

```lua
S:prepare("vh/nome_semantico",
  "SELECT dvalue FROM vh_user_data WHERE user_id = @user_id AND dkey = @key")
```

O nome usa prefixo `vh/` para evitar colisão com queries de resources externos.
Parâmetros nomeados (`@nome`) são mais legíveis e resistentes a injeção SQL
do que posicionais (`?`) — o oxmysql substitui por valores sanitizados.

### uidByIdsIn — query dinâmica lazy-cached

```lua
-- Problema: o jogador pode ter 2, 3, 4... identifiers
-- Solução: preparar uma query diferente para cada N
function vHub.SQL.uidByIdsIn(n)
  local name = "vh/uid_by_ids_in_" .. tostring(n)
  if not S._prepared[name] then
    -- monta "WHERE identifier IN (?, ?, ?)" com N placeholders
    S:prepare(name, "SELECT identifier, user_id FROM vh_user_ids WHERE identifier IN (...)")
  end
  return name
end
```

Antes desta função, `Auth:_resolveUID` fazia N round-trips (1 por identifier).
Agora faz 1 round-trip independente de quantos identifiers o jogador tem.
O cache lazy evita re-preparar para o mesmo N.

---

## 8. server/auth.lua

### Classe User

```lua
User {
  source    -- número FiveM do jogador na sessão atual (muda a cada reconexão)
  id        -- user_id permanente (nunca muda)
  name      -- GetPlayerName()
  endpoint  -- IP do jogador
  char_id   -- personagem selecionado (nil até selectCharacter)
  spawns    -- contador de spawns na sessão
  data      -- tabela plana: datatable persistido + dados efêmeros da sessão
}
```

`user.data` é carregado do banco em `Auth:connect` via `vHub.getUData(uid, "datatable")`.
É uma CÓPIA profunda via `vHub.Utils.dataCopy` — não é a referência viva da VRAM.
Isso é essencial: modificar `user.data` não modifica a VRAM diretamente.

### _resolveUID — resolução de identifiers

O FiveM associa múltiplos identifiers a um jogador: `license:`, `license2:`, `steam:`, `discord:`, `fivem:`, `ip:`.

**Prioridade:** `license:` > `license2:` > `steam:` > `discord:` > `fivem:` > demais (sem `ip:`)

O algoritmo em Fase 1 consulta TODOS os identifiers em 1 query. Se encontrar UIDs
divergentes para identifiers diferentes do mesmo jogador (raro, ocorre em casos de
conta transferida ou mudança de hardware), usa o primeiro UID encontrado e loga aviso.

**Alocador server-side:**
```lua
-- Lua é single-thread — sem race entre conexões simultâneas
local uid_new = vHub._next_user_id
vHub._next_user_id = vHub._next_user_id + 1
-- Insere com id explícito (INSERT IGNORE evita erro se já existir)
Citizen.Await(vHub.State:exec("vh/create_user_with_id", {id = uid_new}))
```

O `INSERT IGNORE` é o seguro de última instância: se por alguma razão de
timing extremo o ID já existir, a query não falha, e o code abaixo faz fallback
para `AUTO_INCREMENT` + `LAST_INSERT_ID`.

### Ban e reconnect

```lua
-- ban.active é hot key — permanece em VRAM após _set
vHub.setUData(uid, "ban.active", true, tx)

-- Na próxima conexão deste uid:
if vHub.getUData(uid, "ban.active") then
  -- VRAM hit → sem round-trip ao banco
  DropPlayer(src, tostring(reason))
end
```

Por que `tostring(reason)`? Historicamente, `reason` poderia ser uma tabela
Lua se mal-formada, o que causava o FiveM exibir `"table: 0x..."` para o cliente.
O `tostring()` garante que o cliente sempre recebe uma string legível.

### Multi-char

O core suporta múltiplos personagens por jogador nativamente:
- `Auth:getCharacters(uid)` — lista todos os chars do usuário
- `Auth:createCharacter(uid)` — cria novo com alocador server-side
- `Auth:selectCharacter(user, cid)` — valida ownership e seleciona

O personagem padrão é criado automaticamente no primeiro login se o jogador não
tiver nenhum. O `last_character` em `user.data` salva qual foi usado por último.

---

## 9. server/vehicle.lua

### VehicleData (VD)

```lua
VD {
  plate       -- "ABC1234" — PK física do GTA
  key_uid     -- UID da chave (pode ser hash de item do inventário)
  netid       -- network entity ID (válido só quando spawned = true)
  spawned     -- bool
  driver      -- source do motorista atual (nil se sem motorista)
  occupants   -- { [source] = seat_index }
  dirty       -- true = tem mudanças não salvas
  state {
    fuel, engine_health, body_health, damage, tuning,
    last_pos, odometer, engine_on, garage
  }
  _last_fuel_bag  -- último valor enviado ao State Bag (gating de delta)
  _last_eng_bag
  _last_body_bag
  _last_odo_bag
}
```

### bagSet — delta threshold + zero-crossing

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

**Por que zero-crossing?** Sem ele, o combustível chegaria a 0.4L e pararia
de atualizar (abaixo do threshold de 0.5L). O HUD cliente mostraria "0.4L" para
sempre. Com o zero-crossing, quando o valor chega a exato `0`, um write é forçado.

`_last_*_bag = -math.huge` no init garante que o primeiro write SEMPRE ocorre,
mesmo que o primeiro valor seja próximo de zero.

### Autoridade de entidade

```lua
-- Quando alguém entra no banco do motorista (seat = -1):
NetworkSetEntityOwner(ent, src)
```

Isso delega ao cliente `src` a autoridade de posição dessa entidade.
O FiveM então sincroniza a posição desse veículo para todos os outros clientes
via protocolo nativo — o servidor não precisa fazer nada.

Quando o motorista sai, o próximo ocupante assume a autoridade. Se não há
ocupantes, o veículo fica "fantasma" até alguém entrar.

### GC de _byNet

```lua
Citizen.CreateThread(function()
  while true do
    Citizen.Wait(300000)  -- 5 minutos
    for netid in pairs(Veh._byNet) do
      local ent = NetworkGetEntityFromNetworkId(netid)
      if not ent or ent == 0 then Veh._byNet[netid] = nil end
      if checados % 100 == 0 then Citizen.Wait(0) end  -- não bloqueia tick
    end
  end
end)
```

Veículos despawnados normalmente removem-se via `onDespawned`. O GC é seguro
de última instância: se o cliente crashar durante o despawn, o netid fica
"preso" em `_byNet`. Sem GC, acumularia indefinidamente.

---

## 10. server/security.lua

### checkPayload

```lua
function Sec:checkPayload(src, event, size)
  if size > (vHub.cfg.max_payload or 8192) then
    vHub.Logger:warn("security", "Payload grande src=%d evt=%s", {size=size})
    return false
  end
  return true
end
```

Protege contra ataques de flood via payloads grandes. O limite padrão de 8KB
é generoso para uso legítimo (inventários, configs) mas bloqueia ataques de
amplificação onde o atacante envia MBs de dados por evento.

**O que não faz:** não valida o conteúdo do payload. Cada handler é responsável
por validar tipos, ranges e propriedade. O Security só garante que o payload
não é absurdamente grande.

### requireAdmin

```lua
function Sec:requireAdmin(src, action)
  if IsPlayerAceAllowed and IsPlayerAceAllowed(src, "vhub.admin") then return true end
  local uid = vHub.Auth:getUID(src)
  if uid and vHub.Kernel:hasPerm(uid, "admin." .. action) then return true end
  self:_permFail(src, "admin." .. action, action)
  return false
end
```

Dupla verificação: ACE nativo do FiveM (configurado no `server.cfg`) e
o sistema de permissões interno (`K:_perms`). A verificação ACE tem prioridade
porque é gerenciada pelo operador do servidor fora do jogo.

### _permFail

```lua
function Sec:_permFail(src, event, perm)
  vHub.Logger:warn("security", "src=%d sem permissão '%s'")
  vHub.Notify:send("security", "🚨 Acesso negado | src:`%d` perm:`%s`")
end
```

Loga + envia webhook de segurança. **Não kicka o jogador** — o kick seria
informação para o atacante saber que foi detectado. O comportamento silencioso
é intencional.

---

## 11. server/notify.lua

```lua
vHub.Notify:send("join", "✅ Fulano conectou")
vHub.Notify:send("ban",  "🔨 Banido: uid=42")
-- canais: join, leave, ban, security
```

Faz POST para o webhook Discord configurado. Com retry automático:
```
tentativa 1 → se falhar → espera 5s → tentativa 2 → se falhar → espera 5s → tentativa 3
```
Se as 3 tentativas falharem, loga warn (se log_level > 0). Não lança erro.

Canais são configurados individualmente para permitir webhooks diferentes por tipo
de notificação (ex: "joins" num canal, "bans" em outro com ping de moderação).

---

## 12. server/boot.lua

### vHub:init — orquestrador central

`boot.lua` define a função `vHub:init(cfg, db_driver)` que é chamada pelo
`bootstrap.lua` após validar que o core carregou corretamente.

**O que init faz:**
1. Normaliza `cfg.log_level` (número → string)
2. Chama `State:setDriver(db_driver)` — conecta ao banco
3. Registra `onResourceStop` — flush de emergência chunked
4. Registra `onResourceStart` — re-dispara sessões para resources reiniciados
5. Registra `playerDropped` — Auth:disconnect + GC do rate-limit
6. Registra `playerConnecting` — apenas deferrals.done()
7. Registra `K:net("vHub:ready", ...)` — ponto de autenticação
8. Registra K:net para todos os eventos de veículo
9. Inicia timer de autosave

### onResourceStart — replay de sessões

```lua
AddEventHandler("onResourceStart", function(res)
  if res == _RES then return end
  SetTimeout(200, function()
    for _, user in pairs(vHub.Auth._sessions) do
      TriggerEvent("vHub:characterLoad", user)
      TriggerEvent("vHub:playerSpawn",   user, false)
    end
  end)
end)
```

**Problema que resolve:** quando `vhub_groups` é reiniciado com 50 jogadores online,
seus handlers de `vHub:characterLoad` foram registrados depois dos eventos já terem
disparado — então `_sessions` do groups está vazio. O core re-dispara os eventos
para todos os jogadores ativos após o resource iniciar, populando as sessões.

O delay de 200ms dá tempo para o resource novo registrar todos os handlers antes
do replay.

### Autosave periódico

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
  SetTimeout((vHub.cfg.save_interval or 60) * 1000, doSave)
end
```

O `Citizen.Wait(0)` a cada 50 sessões é crítico para servidores com 200+ jogadores.
Sem o yield, o loop processaria todas as sessões em 1 tick, causando stall (spike
visível no resmon). Com o yield, cada grupo de 50 é processado em ticks separados.

---

## 13. server/exports.lua

### _invoker_allowed

```lua
local function _invoker_allowed()
  local trust = vHub.cfg and vHub.cfg.trusted_resources
  if not trust or next(trust) == nil then return true end  -- lista vazia = todos OK
  local caller = GetInvokingResource()
  if not caller then return true end
  return trust[caller] == true
end
```

Se `trusted_resources` está vazio, qualquer resource pode chamar exports sensíveis.
Se tiver valores, apenas os listados podem.

**Configuração recomendada para produção:**
```lua
-- shared/config.lua do seu servidor:
vHub.mergeConfig({
  trusted_resources = {
    vhub_admin   = true,
    vhub_garage  = true,
    meu_script   = true,
  }
})
```

### Exports disponíveis

| Export | `_invoker_allowed()` | Notas |
|--------|---------------------|-------|
| `getVHub()` | não | Retorna namespace vHub completo — use com cuidado |
| `getUser(src)` | não | Objeto User com `id, char_id, name, data` |
| `getUID(src)` | não | Retorna user_id ou nil se não tem sessão |
| `hasPerm(uid, perm)` | não | Consulta `K._perms[uid][perm]` |
| `grantPerm(uid, perm)` | **sim** | Concede permissão em runtime |
| `getVehicle(plate)` | não | VehicleData ou nil |
| `transferKey(plate, key)` | **sim** | Muda ownership lógico da chave |
| `getVehicleByKey(key)` | não | Encontra placa pela chave |
| `banPlayer(uid, r, by)` | **sim** | Ban permanente |
| `unbanPlayer(uid)` | **sim** | Remove ban |

---

## 14. client/bootstrap.lua

### Estratégia de spawn dual-path

O cliente tem duas formas de avisar o servidor que está pronto:

**Caminho 1 (natural):**
```
FiveM dispara "playerSpawned" → enviarReady() → TriggerServerEvent("vHub:ready")
```

**Caminho 2 (fallback nativo):**
```
Thread monitora por até 60s
→ se NetworkIsPlayerActive() = true E playerSpawned não disparou em 2s
→ executa spawnNativo() (NetworkResurrectLocalPlayer + ShutdownLoadingScreen)
→ enviarReady()
```

**Por que o fallback?** `playerSpawned` depende do `spawnmanager` do FiveM.
Em algumas configurações mínimas de servidor, `spawnmanager` não está carregado.
O fallback garante que o jogador entra no servidor mesmo sem ele.

**Debounce de 5s:** se `playerSpawned` disparar E o fallback executar quase
simultaneamente (janela de 2s foi curta), o debounce impede dois `vHub:ready`
do mesmo cliente.

**Retry em 15s:** se o servidor nunca responder com `vHub:initDone`, o cliente
reenvia `vHub:ready`. Isso cobre o caso raro de perda de pacote no evento.

### State Bags locais

```lua
-- Após receber initDone:
LocalPlayer.state:set("vhub_uid",            user_id, true)
LocalPlayer.state:set("vhub_char_id",        char_id, true)
LocalPlayer.state:set("vhub_pronto",         true,    true)
LocalPlayer.state:set("vhub_primeiro_spawn", ...,     true)
```

Qualquer script cliente pode ler `LocalPlayer.state.vhub_uid` sem precisar
de event handler ou exports. State Bags são replicadas pelo FiveM para todos
os clientes — outros jogadores também podem ler o `vhub_uid` de outros.

---

## 15. client/vehicle.lua

### Cadência adaptativa

```lua
local function adaptiveDelay(speed_kmh, rpm)
  if speed_kmh < 1 then return 2000 end   -- parado: 0.5Hz (economiza ~8× CPU)
  if rpm < 0.2     then return 1000 end   -- idle: 1Hz
  return 250                              -- dirigindo: 4Hz
end
```

**Impacto real:** em um servidor com 100 carros parados em uma garagem,
o report iria a 4Hz × 100 = 400 eventos/s. Com adaptiveDelay, vai a
0.5Hz × 100 = 50 eventos/s. Redução de 8× no tráfego de rede para esse cenário.

### Payload mínimo

O report envia apenas deltas e estados — não envia posição:
```lua
{
  rpm, engine_health, body_health, engine_on,
  odometer_delta  -- km rodados desde o último tick (não posição absoluta)
}
```

Posição absoluta nunca é enviada pelo cliente ao servidor. O servidor obtém
posição via `GetEntityCoords(ent)` quando necessário (em `_atualizarPosicao`).

### Validação server-side do odômetro

```lua
-- server/vehicle.lua:onStateUpdate
local max_delta = (rpm or 0) * max_speed_kmh * time_per_tick / 3600
local applied = math.min(odometer_delta, math.max(0.0001, max_delta), 0.5)
```

O servidor calcula o delta máximo fisicamente possível baseado no RPM e
velocidade máxima configurada. Um hack que envie `odometer_delta = 99999`
seria cortado para o valor físico real.

---

## 16. sql/schema.sql

### Filosofia do schema

**Idempotente:** `CREATE TABLE IF NOT EXISTS` garante que executar o schema
múltiplas vezes (a cada boot) não cause erros ou perda de dados.

**Self-contained:** o schema documenta a si mesmo via `COMMENT` em cada
tabela e coluna. Nenhuma documentação externa é necessária para entender o DB.

**Foreign Keys com CASCADE:**
```sql
CONSTRAINT fk_vh_user_data_user
  FOREIGN KEY (user_id) REFERENCES vh_users(id)
  ON DELETE CASCADE ON UPDATE CASCADE
```

Deletar um usuário remove automaticamente: identifiers, personagens, dados KV
de usuário, dados KV de personagem, dados de veículo (via plate FK).

**Por que BLOB e não TEXT/JSON?**
- msgpack binário não é texto UTF-8 válido — `TEXT` causaria corrupção
- BLOB até 64KB é suficiente para 99% dos datatables (típico < 4KB)
- Menor que MEDIUMBLOB (16MB) → buffer pool InnoDB menor → mais eficiente
- JSON seria 2–3× maior e mais lento para serializar/desserializar

### Tipo PK canônico: INT UNSIGNED

**Regra crítica para resources externos:**
```sql
-- CORRETO:
char_id INT UNSIGNED NOT NULL,
FOREIGN KEY (char_id) REFERENCES vh_characters(id)

-- ERRADO (errno 150 — foreign key constraint):
char_id INT NOT NULL,  -- signed vs unsigned = tipo incompatível no InnoDB
```

---

## 17. Transações

O sistema de TX do State é in-memory — não usa transações SQL diretamente.
A "transação" é um snapshot de VRAM com rollback.

### Exemplo completo

```lua
-- Transferência de dinheiro segura (dentro de Citizen.CreateThread)
local tx = vHub.State:begin()

local saldo_de = vHub.getUData(uid_de, "money")
local saldo_para = vHub.getUData(uid_para, "money")

if not saldo_de or saldo_de < valor then
  -- não precisa rollback: nada foi modificado
  return false, "saldo_insuficiente"
end

vHub.setUData(uid_de,   "money", saldo_de   - valor, tx)
vHub.setUData(uid_para, "money", saldo_para + valor, tx)

-- commit gera as ops SQL e limpa o snapshot
local ok, err = vHub.State:commit(tx)
if not ok then
  -- vHub.State:commit já chamou rollback automaticamente
  return false, err
end
return true
```

### Validators

```lua
vHub.State:addValidator(function(tx, snap, mem)
  -- snap = { ["ud\0uid\0money"] = { prev=5000, et="ud", eid=uid, key="money" } }
  -- mem = _mem atual (após mutações)
  -- Verificar invariantes: saldo nunca negativo, etc.
  for _, s in pairs(snap) do
    if s.key == "money" then
      local novo = mem[s.et] and mem[s.et][s.eid] and mem[s.et][s.eid][s.key]
      if type(novo) == "number" and novo < 0 then
        return false, "saldo_negativo"
      end
    end
  end
  return true
end)
```

Validators são executados no commit antes de enfileirar as ops SQL.
Se qualquer validator retornar false, o rollback é feito automaticamente.

### SQL ops no commit

```lua
vHub.State:commit(tx, {
  -- ops SQL adicionais para executar atomicamente junto com as do batch
  {"vh/log_transaction", { from=uid_de, to=uid_para, amount=valor }},
})
```

As ops SQL passadas no commit entram no batch e serão executadas na próxima
transação de banco. Não são literalmente atômicas com o VRAM (que é imediato),
mas são executadas juntas na transação SQL do próximo flush.

---

## 18. Rate limiting O(1)

```
K:net("evento", handler, { rate = { max, window_ms, block_ms } })

Exemplos do core:
  vHub:ready      { 5, 15000, 60000 }   5 por 15s, bloqueia 60s se exceder
  vHub:died       { 5, 20000, 30000 }   5 por 20s, bloqueia 30s
  vHub:vState     { 8, 1000,  5000  }   8 por 1s,  bloqueia 5s
  vHub:vSpawned   { 15, 5000, 15000 }   15 por 5s, bloqueia 15s
```

**Como funciona:**
- Primeiro acesso: cria `{ hits=1, window=agora, blocked=0 }`
- Acesso subsequente no mesmo janela: incrementa hits
- Se `hits > max`: seta `blocked = agora + block_ms` → bloqueia por N ms
- Se `(agora - window) >= win`: reseta hits e window (nova janela)

**Por que bloquear e não só rejeitar?**
Se o bloco fosse apenas "nada acontece", um spammer poderia mandar eventos
numa taxa de `max+1` por janela indefinidamente com zero consequência.
O block_ms garante penalidade progressiva.

**O bloqueio é silencioso** — o cliente recebe silêncio, não uma mensagem
de erro. Informar o cliente que foi bloqueado ajudaria o atacante a calibrar
a taxa de spam.

---

## 19. Serialização msgpack

**Por que msgpack e não json?**

| Critério | json | msgpack |
|----------|------|---------|
| Tamanho | ~100% | ~60-70% (binários = mais compacto) |
| Velocidade | médio | rápido |
| Tipos binários | não | sim |
| Legível por humanos | sim | não |
| Corrupção de dados | não | não |

Dados como inventários contêm arrays de objetos complexos. Em json, `[{"item":"water","qty":3}]`
são 30 bytes; em msgpack, ~20 bytes. Com centenas de itens, a diferença é significativa
para storage em BLOB e para a velocidade de serialização a cada autosave.

**BLOB retornado como array de bytes pelo oxmysql:**
```lua
-- O oxmysql retorna BLOBs como { [1]=65, [2]=66, [3]=67, ... }
-- (array de valores ASCII/byte)
-- _unpack em state.lua converte para string antes do msgpack.unpack
local function _unpack(raw)
  if type(raw) == "table" then
    local chars = {}
    for _, b in ipairs(raw) do chars[#chars+1] = string.char(b) end
    raw = table.concat(chars)
  end
  ...
end
```

**_pack ignora campos `_` (underscore):**
```lua
if type(k) == "string" and k:sub(1,1) == "_" then
  -- ignora _dirty, _loaded, etc. (metadados internos)
end
```

Campos que começam com `_` são considerados metadados internos da VRAM
e não são serializados para o banco. Isso permite adicionar campos de controle
sem poluir os dados persistidos.

---

## 20. Pontos fortes

### Confiabilidade de dados
- **Zero corrupção por race condition em user_id**: alocador server-side + INSERT IGNORE
- **Rollback de VRAM**: se um validator falhar, o estado volta ao anterior sem partial writes
- **Flush emergencial com chunked yield**: mesmo em shutdown abrupto, dados são salvos
- **Re-entrância controlada no flush**: impossível corromper o batch via double-flush

### Performance real medida
- **resmon 0.02ms idle**: 6× melhor que o alvo de 0.05ms
- **VRAM-first elimina ~80% das queries de leitura** em sessões longas
- **N→1 login**: identificação de jogador em 1 query independente de quantos identifiers tem
- **State Bag delta thresholds**: ≥8× menos writes de State Bag vs. update a cada tick
- **Adaptive client report**: 8× menos eventos de veículo parado vs. report fixo 4Hz

### Extensibilidade
- **KV data model aberto**: qualquer string é uma chave válida; não há schema fixo para dados de jogo
- **Driver plugável**: `registerStateDriver` permite substituir oxmysql por outro driver
- **Validator chain**: qualquer módulo pode adicionar validadores de TX sem modificar o State
- **onResourceStart replay**: resources externos reiniciados recebem sessões automaticamente

### Segurança
- **Silent fail por design**: rate limit, payload reject e permissão negada são silenciosos
- **_invoker_allowed whitelist**: exports sensíveis não são acessíveis por qualquer resource
- **vHub.E read-only**: eventos não podem ser redirecionados por código mal escrito
- **assertThread**: erros de thread são detectados com stacktrace em vez de crash silencioso

---

## 21. Limitações e trade-offs honestos

### VRAM não tem TTL

Dados na VRAM **nunca expiram por tempo**. Se um dado é lido uma vez, fica
em memória para sempre (enquanto o resource estiver rodando).

**Impacto:** em servidores que rodam por dias sem restart, a VRAM cresce
linearmente com o número de chaves distintas acessadas. Para servidores com
10.000+ jogadores únicos por dia, isso pode acumular milhares de entradas.

**Mitigação atual:** invalida após write (exceto hot keys). Dados de jogadores
offline são descartados quando eles saem (`Auth:disconnect` não limpa a VRAM,
apenas a sessão — isso é intencional: dados podem ser acessados por admin offline).

**Limitação real:** não há mecanismo de eviction automático para entradas antigas.
Para casos extremos (servidores de alta rotatividade), um GC periódico de
entradas de usuarios offline poderia ser adicionado em v2.0.

### Transações são in-memory, não SQL

O `begin/commit/rollback` garante consistência de VRAM entre o início e o commit,
mas as ops SQL vão para o batch e são executadas depois — não no mesmo momento
atômico do commit de VRAM.

**Impacto:** se o servidor crashar entre o commit de VRAM e o flush do batch,
as ops SQL se perdem. Os dados em VRAM foram mudados, mas o banco não reflete isso.

**Mitigação:** o flush emergencial em `onResourceStop` tenta salvar o batch.
Para crashes abruptos (kill -9, power outage), há risco de perda dos últimos
segundos de dados. Este é o trade-off fundamental de toda arquitetura VRAM-first.

### ~~Batch contamination cross-player~~ — RESOLVIDO em Frozen v1.0

> **Status:** corrigido antes do congelamento. Descrito aqui para documentar a decisão de design.

**Problema original:** `Driver:batch` enviava todas as ops do flush em uma única
`oxmysql:transaction([op1, op2, ..., opN])`. Se uma op falhasse (ex: BLOB > 64 KB),
a transação inteira era revertida — incluindo ops válidas de outros jogadores.
O erro de *um* jogador derrubava o dado de *todos* no mesmo ciclo de flush.

**Solução aplicada (três partes coordenadas):**

1. **BLOB guard em `_set`** — ops com payload > 60 KB (61 440 bytes) são descartadas
   antes de entrar no batch, com log de erro. Remove a causa raiz mais provável de falha:
   ```lua
   if type(packed) == "string" and #packed > 61440 then
     vHub.Logger:error("state", "BLOB overflow — op descartada ...")
     return  -- não enfileira
   end
   ```

2. **Executes isolados em paralelo em `Driver:batch`** — cada op vira um `api:update`
   independente com seu próprio `promise`. Uma falha não cancela as outras:
   ```lua
   -- N promises disparadas em paralelo
   -- Cada uma resolve individualmente: { ok = true } ou { ok = false }
   -- Collect: Citizen.Await em sequência acumula só as que falharam
   local falhas = {}
   for _, item in ipairs(promessas) do
     local env = Citizen.Await(item.p)
     if not env.ok then falhas[#falhas + 1] = item.op end
   end
   return (#falhas == 0), falhas   -- (bool, lista_de_falhas)
   ```

3. **Re-enfileiramento seletivo em `_flush`** — apenas as ops que o driver reportou
   como falhas voltam para o batch. Ops de outros jogadores que tiveram sucesso
   não são reenfileiradas:
   ```lua
   if not batch_ok and type(batch_falhas) == "table" then
     -- só as ops falhas + pendentes novas
     for i = 1, nf    do fila[i]    = batch_falhas[i] end
     for i = 1, pendN do fila[nf+i] = pend[i]         end
   end
   ```

**Trade-off aceito:** o batch deixou de ser uma SQL transaction atômica — isolamento
ganhou prioridade sobre atomicidade. Para dados que precisam de atomicidade SQL real
(ex: transferência de dinheiro entre duas colunas), o chamador deve usar a TX de VRAM
(`begin/commit`) e aceitar que a persistência SQL pode chegar em flushes diferentes.
Na prática, para o modelo KV (`REPLACE INTO vh_*_data`), atomicidade por op é suficiente.

### Smoke tests T1–T5 dependem de runtime

Os testes de performance (resmon, stall, flushes/ciclo) exigem FiveM rodando
com carga real. Não há ambiente de CI/CD automático para esses testes.

**Impacto:** mudanças no core não podem ser validadas automaticamente em CI.
A aprovação depende de testes manuais em ambiente de staging.

### Client/bootstrap.lua tem posição de spawn hard-coded

```lua
local SPAWN_POS = { x = -538.70, y = -214.91, z = 37.65, h = 0.0 }
```

A posição de spawn do fallback nativo é fixa no arquivo. Em servidores com
spawn customizado, o fallback pode colocar o jogador na posição errada por
~500ms antes de `vhub_player_state` aplicar a posição correta.

**Mitigação:** `vhub_player_state` recebe `vHub:characterLoad` e teleporta
imediatamente. O jogador mal percebe. Mas é uma posição visível por
uma fração de segundo.

---

## 22. Guia do desenvolvedor

### Padrão mínimo de um resource externo

```lua
-- vhub_meumodulo/fxmanifest.lua
fx_version 'cerulean'
game      'gta5'
lua54     'yes'

dependency 'vhub'

server_scripts { 'server/*.lua' }
client_scripts { 'client/*.lua' }
```

```lua
-- vhub_meumodulo/server/init.lua
local M = {}; M.__index = M

-- Sessões locais deste módulo
M._sessions = {}  -- { [src] = { uid, char_id, ... } }

AddEventHandler("vHub:characterLoad", function(user)
  -- user = { id=uid, char_id=cid, source=src, name=..., data={} }
  Citizen.CreateThread(function()
    -- OK usar Citizen.Await aqui — estamos em thread
    local dinheiro = vHub.getCData(user.char_id, "money") or 0
    M._sessions[user.source] = {
      uid     = user.id,
      char_id = user.char_id,
      money   = dinheiro,
    }
  end)
end)

AddEventHandler("vHub:playerLeave", function(user)
  M._sessions[user.source] = nil
end)

-- Net event seguro com rate limit
vHub.Kernel:net("meumodulo:comprar", function(src, item_id, qty)
  local sess = M._sessions[src]
  if not sess then return end

  -- validação server-side obrigatória
  if type(item_id) ~= "string" or #item_id > 32 then return end
  qty = math.floor(math.abs(tonumber(qty) or 0))
  if qty <= 0 or qty > 100 then return end

  -- transação: débito de dinheiro + adição de item
  local tx = vHub.State:begin()
  vHub.setCData(sess.char_id, "money", sess.money - preco * qty, tx)
  local ok, err = vHub.State:commit(tx)
  if ok then
    exports.vhub_inventory:giveItem(src, item_id, qty)
    sess.money = sess.money - preco * qty
  end
end, { rate = { 5, 3000, 10000 } })
```

### Schema externo correto

```sql
-- vhub_meumodulo/sql/schema.sql
CREATE TABLE IF NOT EXISTS mm_transacoes (
  id          INT UNSIGNED     NOT NULL AUTO_INCREMENT,
  user_id     INT UNSIGNED     NOT NULL,   -- DEVE ser UNSIGNED para FK funcionar
  char_id     INT UNSIGNED     NOT NULL,   -- DEVE ser UNSIGNED
  valor       DECIMAL(12,2)    NOT NULL,
  descricao   VARCHAR(128)     DEFAULT NULL,
  created_at  DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_mm_trans_user (user_id),
  CONSTRAINT fk_mm_trans_user
    FOREIGN KEY (user_id) REFERENCES vh_users(id)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

```lua
-- Aplicação automática do schema:
AddEventHandler("onResourceStart", function(res)
  if res ~= GetCurrentResourceName() then return end
  local schema = LoadResourceFile(res, "sql/schema.sql")
  if schema then
    exports.oxmysql:execute(schema, {}, function(ok)
      print("[meumodulo] schema aplicado: " .. tostring(ok))
    end)
  end
end)
```

### Boas práticas críticas

**1. Nunca usar `vHub.State:prepare/query` fora do core:**
```lua
-- ERRADO — o State é do core; não serializa para resources externos
exports.vhub:getVHub().State:prepare("minha_query", "SELECT ...")

-- CORRETO — use oxmysql diretamente
exports.oxmysql:query("SELECT ...", params, callback)
```

**2. Sempre `tonumber` + range check em dados do cliente:**
```lua
-- ERRADO:
local valor = arg1

-- CORRETO:
local valor = math.floor(math.abs(tonumber(arg1) or 0))
if valor <= 0 or valor > 1000000 then return end
```

**3. dataCopy antes de persistir tabelas de user.data:**
```lua
-- ERRADO: persiste referência viva
vHub.setUData(uid, "meus_dados", user.data.meus_dados)

-- CORRETO: persiste cópia plana
vHub.setUData(uid, "meus_dados", vHub.Utils.dataCopy(user.data.meus_dados))
```

**4. assertThread antes de Citizen.Await:**
```lua
function M:minhaFuncao(uid)
  vHub.assertThread()  -- falha explicitamente se não estiver em thread
  local val = vHub.getUData(uid, "chave")  -- OK: assertThread passou
  ...
end
```

**5. Limpar sessão em playerLeave, não playerDropped:**
```lua
-- CORRETO: vHub já processou o disconnect, user está disponível
AddEventHandler("vHub:playerLeave", function(user)
  M._sessions[user.source] = nil
end)

-- ERRADO: playerDropped pode disparar antes do vHub processar
AddEventHandler("playerDropped", function()
  M._sessions[source] = nil  -- pode conflitar com Auth:disconnect
end)
```

---

## 23. Referência rápida de API

### Dados KV (exigem Citizen.CreateThread)

```lua
-- User data (por user_id — conta, ban, whitelist, datatable)
vHub.getUData(uid, "chave")                → valor | nil
vHub.setUData(uid, "chave", valor)         → void
vHub.setUData(uid, "chave", valor, tx)     → void (dentro de TX)

-- Char data (por char_id — dinheiro, inventário, posição, skills)
vHub.getCData(cid, "chave")                → valor | nil
vHub.setCData(cid, "chave", valor)         → void

-- Vehicle data (por plate — estado físico: fuel, health, odo)
vHub.getVData(plate, "chave")              → valor | nil
vHub.setVData(plate, "chave", valor)       → void

-- Global data (por chave — economia do servidor, contadores)
vHub.getGData("chave")                     → valor | nil
vHub.setGData("chave", valor)              → void
```

### Sessões e usuários

```lua
local user = vHub.Auth:getUser(src)      -- User object ou nil
local uid  = vHub.Auth:getUID(src)       -- user_id ou nil
local user = vHub.Auth:byUID(uid)        -- User object pelo uid
```

### Permissões

```lua
vHub.Kernel:grantPerm(uid, "minha.perm")
vHub.Kernel:revokePerm(uid, "minha.perm")
vHub.Kernel:hasPerm(uid, "minha.perm")   → boolean
-- "admin.*" é uma perm curinga que concede acesso a qualquer "admin.X"
```

### Transações

```lua
local tx = vHub.State:begin()
vHub.setUData(uid, "chave", novo_valor, tx)
vHub.setCData(cid, "outra", outro_valor, tx)
local ok, err = vHub.State:commit(tx)
if not ok then
  -- rollback já foi feito automaticamente
  -- 'err' contém o motivo (string)
end
```

### Veículos

```lua
vHub.Vehicle:register(plate, key_uid)         -- cria VehicleData (exige thread)
vHub.Vehicle:unregister(plate)                -- salva e remove da VRAM
vHub.Vehicle:transferKey(plate, new_key_uid)  -- muda ownership da chave
vHub.Vehicle:byKey(key_uid)                   → plate (exige thread)
vHub.Vehicle._veh[plate]                      → VehicleData | nil
```

### Eventos (listen via AddEventHandler)

```lua
-- Server-side
AddEventHandler("vHub:playerJoin",     function(user) end)
AddEventHandler("vHub:playerLeave",    function(user, reason) end)
AddEventHandler("vHub:playerSpawn",    function(user, primeiro_spawn) end)
AddEventHandler("vHub:playerDeath",    function(user) end)
AddEventHandler("vHub:characterLoad",  function(user) end)
AddEventHandler("vHub:vehicleLoaded",  function(vd) end)
AddEventHandler("vHub:vehicleSpawned", function(vd) end)
AddEventHandler("vHub:vehicleEnter",   function(vd, src, seat) end)
AddEventHandler("vHub:vehicleLeave",   function(vd, src, seat) end)
AddEventHandler("vHub:vehicleFuelEmpty", function(vd, src) end)

-- Client-side
AddEventHandler("vHub:localReady",     function(uid, cid, primeiro) end)
AddEventHandler("vHub:localCharSelected", function(cid) end)
```

### Exports cross-resource (server-side)

```lua
-- De qualquer resource externo:
local uid     = exports.vhub:getUID(src)
local user    = exports.vhub:getUser(src)
local perm    = exports.vhub:hasPerm(uid, "minha.perm")
local vd      = exports.vhub:getVehicle("ABC1234")
local status  = exports.vhub:Status()

-- Requer trusted_resource:
exports.vhub:grantPerm(uid, "minha.perm")
exports.vhub:banPlayer(uid, "motivo", "admin")
exports.vhub:unbanPlayer(uid)
exports.vhub:transferKey("ABC1234", novo_key_uid)
```

### Net events (cliente → servidor, via K:net)

```lua
-- Registrar handler server-side:
vHub.Kernel:net("meu:evento", function(src, a, b, c)
  -- ...
end, {
  rate  = { 5, 3000, 15000 },   -- 5 por 3s, bloqueia 15s
  perm  = "permissao",           -- opcional
  async = true,                  -- padrão; false = sem thread
})

-- Disparar do cliente:
TriggerServerEvent("meu:evento", a, b, c)
```
