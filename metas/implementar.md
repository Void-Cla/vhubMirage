# vHub — Análise Técnica Comparativa & Roadmap de Melhorias

---

STATUS DE IMPLEMENTAÇÃO (resumo parcial)

- SPRINT 0: `shared/config.lua`, `shared/events.lua`, `shared/utils.lua`, `shared/logger.lua` criados.
- SPRINT 1 (estabilidade): correções aplicadas em `base.lua`: verificação de payload (msgpack/json), `vHub.assertThread()` em APIs que usam `Citizen.Await`, proteção de exports via `GetInvokingResource`, mitigação de `LAST_INSERT_ID` com `vHub._next_user_id`, reentrância de `_flush` tratada.
- Melhorias adicionais: validação de odômetro por velocidade máxima por tick, reconciliador de ownership (`Veh:_validateOwner`) e thread opcional de kick por ping (configurável via `cfg.ping_check_enabled`).

Próximo passo: rodar smoke tests S0.x, validar SPRINT 1 em ambiente de teste e submeter à revisão do `vhub_arquiteto` antes de SPRINT 2.


## 1. Posicionamento: onde o vHub está agora

| Critério | vRP1 (Unity) | vRP2 (oficial) | vRP3-Dev | **vHub** |
|---|---|---|---|---|
| Arquitetura | Monolítica, Proxy/Tunnel | Extension system, OOP fraco | Extension OOP, Lua puro | Kernel + módulos separados por responsabilidade |
| Sync de veículo | Manual / sem controle | Manual | Manual | FiveM-native (NetworkSetEntityOwner) ✅ |
| State management | JSON simples no disco | UData em DB | UData em DB | VRAM → TX → Batch SQL ✅ |
| Rate limiting | Inexistente | Inexistente | Inexistente | O(1) sliding window ✅ |
| Segurança de net events | `RegisterServerEvent` nu | `RegisterServerEvent` nu | `RegisterServerEvent` nu | Protegido com perm + rate + async ✅ |
| Transações (rollback) | ❌ | ❌ | ❌ | ✅ |
| Compatibilidade vRP | ❌ | Native | Native | Shim completo (Proxy + Tunnel + Extension) ✅ |
| Anti-dupe / payload check | ❌ | ❌ | ❌ | Básico ✅ |
| State Bags (FiveM) | ❌ | ❌ | ❌ | ✅ para veículos |
| Client-side architecture | Inline no servidor | Tunnel RPC | Tunnel RPC | Só eventos — **sem client.lua estruturado** ⚠️ |
| Separação de arquivos | Monolítico (1 file) | Multi-file via `module()` | Multi-file via `module()` | **Monolítico (1 file)** ⚠️ |

**Veredito**: o vHub está entre vRP2 e vRP3 em maturidade arquitetural, e **supera todos os três** nas áreas de sync de veículo, segurança de rede e state management. Os gap críticos são na organização por arquivo/responsabilidade e na camada client-side.

---

## 2. O que está excelente (não mexa)

### 2.1 FiveM Native Authority Model
O `NetworkSetEntityOwner(ent, src)` é a escolha certa e os vRPs nunca chegaram lá. Isso resolve o problema de desync sem nenhum broadcast manual. Mantenha.

### 2.2 VRAM → Batch SQL
O pipeline de escrita assíncrona com flush por volume (BATCH_MAX=150) ou tempo (BATCH_INT=5s) é production-grade. A maioria dos frameworks BR faz um `MySQL.Async.execute` por tecla pressionada.

### 2.3 Sliding Window Rate Limiter
O `_rateOK` em O(1) com GC automático a cada 2 minutos é correto. Funciona em 3000 players sem pressure de memória.

### 2.4 Transações com Snapshot/Rollback
Nenhum vRP tem isso. O padrão `begin → set(tx) → commit(sql_ops)` garante que a VRAM e o SQL nunca ficam em estado inconsistente.

---

## 3. Problemas identificados — críticos

### 3.1 Arquivo único — violação de SRP (Single Responsibility Principle)
**Impacto**: impossível ter times diferentes trabalhando, impossível testar módulos isolados, hot-reload de só uma parte é impossível.

**Solução**: separar em arquivos por responsabilidade:

```
vhub/
  fxmanifest.lua
  server/
    kernel.lua       -- [1] Kernel, rate, perms, exports
    state.lua        -- [2] State, VRAM, TX, batch
    auth.lua         -- [3] Auth, session, char, ban
    vehicle.lua      -- [4] Vehicle
    security.lua     -- [5] Security
    notify.lua       -- [6] Notify
    sql.lua          -- [9] SQL prepares + schema
    compat.lua       -- [A] vRP shim
    init.lua         -- [8] Boot (depende de todos acima)
  client/
    core.lua         -- player spawn, char sync, death
    vehicle.lua      -- state reporting, bag reader
    hud.lua          -- (opcional) fuel/damage HUD
  shared/
    utils.lua        -- [7] formatters
    config.lua       -- cfg
```

### 3.2 Client-side inexistente
O vHub não tem `client.lua`. Os eventos `vHub:vehicleStateLoad`, `vHub:passengerMode`, `vHub:charSelected` são emitidos mas ninguém os recebe de forma estruturada. Qualquer resource que queira usar o framework tem que reimplementar a lógica de recepção.

**O que o client deve fazer minimamente**:
```lua
-- client/core.lua
AddEventHandler("onClientGameTypeStart", function()
  TriggerServerEvent("vHub:ready")
end)

-- Recebe o estado salvo do veículo e aplica nos State Bags locais
AddEventHandler("vHub:vehicleStateLoad", function(plate, state)
  -- aplicar fuel/tuning via GetVehicleFuelLevel etc.
end)

-- Reporta estado do veículo para o servidor (~4hz)
-- usa GetVehicleEngineHealth, GetVehicleBodyHealth, GetVehicleFuelLevel
-- NUNCA envia position — FiveM já faz isso
CreateThread(function()
  while true do
    Wait(250) -- 4hz
    local veh = GetVehiclePedIsIn(PlayerPedId(), false)
    if veh ~= 0 then
      local plate = GetVehicleNumberPlateText(veh)
      local seat  = GetPedSeatInVehicle(PlayerPedId(), veh)
      TriggerServerEvent("vHub:vState", plate, {
        rpm            = GetVehicleCurrentRpm(veh),
        engine_health  = GetVehicleEngineHealth(veh),
        body_health    = GetVehicleBodyHealth(veh),
        engine_on      = GetIsVehicleEngineRunning(veh),
        odometer_delta = 0.0, -- calcular delta via GetVehicleSpeed
      })
    end
  end
end)
```

### 3.3 `GetPlayerIdentifiers` retorna IP — já filtrado, mas a ordem importa
O `_ids` filtra IPs corretamente, mas ao iterar `GetPlayerIdentifiers` a ordem dos identificadores pode variar por versão do FiveM. O primeiro identifier usado para lookup pode não ser o mais estável.

**Solução**: priorizar `license:` (Rockstar), depois `steam:`, depois `discord:`:
```lua
function Auth:_ids(src)
  local raw = GetPlayerIdentifiers(src) or {}
  local ids, prio = {}, {"license:", "steam:", "discord:", "fivem:"}
  -- primeiro passagem: prioridade
  for _, prefix in ipairs(prio) do
    for _, id in ipairs(raw) do
      if id:sub(1, #prefix) == prefix then ids[#ids+1] = id end
    end
  end
  -- segunda passagem: resto (exceto ip:)
  for _, id in ipairs(raw) do
    if not id:find("^ip:") then
      local found = false
      for _, existing in ipairs(ids) do if existing == id then found=true; break end end
      if not found then ids[#ids+1] = id end
    end
  end
  return ids
end
```

### 3.4 `CREATE_USER` usa `SELECT LAST_INSERT_ID()` — race condition em alta concorrência
Com 3000 players, dois connects simultâneos podem colidir se o driver não garantir atomicidade na transação. O padrão correto para MySQL 8+ é `INSERT RETURNING` ou usar uma transação explícita no driver.

### 3.5 `_flush()` sem proteção contra re-entância
Se `_flush()` for chamado enquanto o batch anterior ainda está sendo processado pelo driver (raro mas possível com BATCH_MAX=150 e servidor lento), pode haver duplicate writes.

**Solução**:
```lua
S._flushing = false

function S:_flush()
  if self._batchN == 0 or not self._ready or self._flushing then return end
  self._flushing = true
  local ops, n = self._batch, self._batchN
  self._batch, self._batchN = {}, 0
  Citizen.CreateThread(function()
    self._driver:batch(ops, n)
    self._flushing = false
  end)
end
```

---

## 4. Problemas identificados — moderados

### 4.1 `validPlate` bloqueia placas com letras minúsculas
GTA gera placas com maiúsculas, mas scripts externos podem passar minúsculas. O regex `^[A-Z0-9%s]+$` rejeita isso silenciosamente.

**Solução**: normalizar antes de validar:
```lua
local function normalizePlate(p)
  return type(p) == "string" and p:upper():gsub("%s+", " "):match("^%s*(.-)%s*$") or nil
end
```

### 4.2 `odometer_delta` capped a 0.5 km/update — pode ser bypassado
4hz × 0.5km = 120 km/h de odômetro falso se alguém enviar exatamente o cap. A proteção correta é verificar a velocidade máxima possível dado o `rpm` reportado.

```lua
-- velocidade máxima em 1/4 de segundo com RPM reportado
local max_speed_per_tick = (upd.rpm or 0) * vHub.cfg.max_speed_kmh / 4 / 3600
if upd.odometer_delta then
  s.odometer = s.odometer + math.min(upd.odometer_delta, max_speed_per_tick)
end
```

### 4.3 Webhook bloqueante sem retry
`PerformHttpRequest` pode falhar silenciosamente. Webhooks críticos (ban, security) devem ter retry:
```lua
function Notify:send(ch, msg, retries)
  retries = retries or 3
  local url = (vHub.cfg and vHub.cfg.webhooks or {})[ch]
  if not url or url == "" then return end
  PerformHttpRequest(url, function(code)
    if code ~= 200 and retries > 0 then
      SetTimeout(5000, function() self:send(ch, msg, retries - 1) end)
    end
  end, "POST", json.encode({content=msg}), {["Content-Type"]="application/json"})
end
```

### 4.4 `Auth:connect` chama `vHub.getUData` sem estar em thread separada
`_get` usa `Citizen.Await(S:query(...))` — isso requer estar dentro de `Citizen.CreateThread`. O `Auth:connect` já é chamado de dentro de uma thread (via `K:net`), mas a documentação interna não deixa isso claro. Uma chamada acidental fora de thread causará deadlock.

**Solução**: adicionar assert no topo de funções que requerem thread:
```lua
local function assertThread()
  assert(Citizen.GetCurrentThread() ~= nil,
    "[vHub] Esta função deve ser chamada dentro de Citizen.CreateThread")
end
```

---

## 5. Melhorias de performance (client + server)

### 5.1 State Bags no client — ler fuel/damage sem round-trip
O client já pode ler State Bags localmente sem pedir ao server:
```lua
-- client/vehicle.lua
AddStateBagChangeHandler("vh_fuel", nil, function(bagName, _, value)
  local netid = tonumber(bagName:gsub("entity:", ""))
  local ent   = NetworkGetEntityFromNetworkId(netid)
  if DoesEntityExist(ent) then
    SetVehicleFuelLevel(ent, value) -- nativo GTA
  end
end)

AddStateBagChangeHandler("vh_tune", nil, function(bagName, _, tuning)
  -- aplicar mods de veículo via SetVehicleMod
end)
```

### 5.2 `GetVehicleSpeed` + conversão para odômetro delta no client
```lua
-- no loop de 4hz:
local speed_ms   = GetEntitySpeed(veh)              -- metros/segundo
local delta_km   = speed_ms * 0.25 / 1000           -- 0.25s = 1/4hz
```

### 5.3 Usar `GetPlayerRoutingBucket` para instâncias
O vHub não aproveita Routing Buckets do FiveM para separar instâncias (eventos, zonas privadas). É um nativo poderoso:
```lua
-- colocar jogador em instância privada
SetPlayerRoutingBucket(src, instance_id)
-- tirar
SetPlayerRoutingBucket(src, 0)
```

### 5.4 `GetEntityPopulationType` — distinguir veículos de NPC de player
Antes de registrar um veículo, verificar se é do jogador:
```lua
-- no onSpawned: se poptype == 7 (POPTYPE_MISSION) é do jogador
-- evita registrar veículos de NPC aleatórios
```

### 5.5 `NetworkGetEntityOwner` como health check
```lua
-- verificar se o owner atual do veículo ainda está online
function Veh:_validateOwner(vd)
  if not vd.netid then return end
  local ent = NetworkGetEntityFromNetworkId(vd.netid)
  if ent and ent ~= 0 then
    local owner = NetworkGetEntityOwner(ent)
    if owner ~= vd.driver then
      -- transferir autoridade para o owner atual
      vd.driver = owner
    end
  end
end
```

---

## 6. Melhorias de segurança

### 6.1 `IsPlayerAceAllowed` para admin — não depender só de VRAM
O FiveM tem ACE nativo que persiste mesmo sem DB:
```lua
function Sec:requireAdmin(src, action)
  -- ACE tem prioridade — admin declarado no server.cfg nunca é bloqueado
  if IsPlayerAceAllowed(src, "vhub.admin") then return true end
  local uid = Auth:getUID(src)
  if uid and K:hasPerm(uid, "admin." .. action) then return true end
  self:_permFail(src, "admin." .. action, action)
  return false
end
```

### 6.2 `GetInvokingResource` — bloquear chamadas externas não autorizadas
Para exports sensíveis (banPlayer, transferKey), verificar o resource que chama:
```lua
K:export("banPlayer", function(u, r, by)
  local caller = GetInvokingResource()
  -- só resources na whitelist podem banir
  local allowed = vHub.cfg.trusted_resources or {}
  if caller and not allowed[caller] then
    print("[vHub][SEC] banPlayer chamado por resource não autorizado: " .. tostring(caller))
    return false
  end
  Auth:ban(u, r, by)
end)
```

### 6.3 `GetPlayerPing` — desconectar jogadores com ping impossível (potencial de exploit)
```lua
-- no loop de auto-save ou periodicamente
for src, _ in pairs(Auth._sessions) do
  local ping = GetPlayerPing(src)
  if ping > (vHub.cfg.max_ping or 800) then
    DropPlayer(src, "Ping muito alto: " .. ping .. "ms")
  end
end
```

### 6.4 `VerifyPasswordHash` — nunca armazenar senha em texto plano
Se o vHub vier a ter sistema de senha (discord auth, etc.):
```lua
-- FiveM expõe bcrypt nativo:
local hash = VerifyPasswordHash(password, stored_hash)
```

---

## 7. Melhorias de organização lógica

### 7.1 EventBus tipado — substituir strings literais por constantes
```lua
-- shared/events.lua
vHub.Events = {
  PLAYER_JOIN    = "vHub:playerJoin",
  PLAYER_LEAVE   = "vHub:playerLeave",
  PLAYER_SPAWN   = "vHub:playerSpawn",
  PLAYER_DEATH   = "vHub:playerDeath",
  CHAR_LOAD      = "vHub:characterLoad",
  VEH_SPAWNED    = "vHub:vehicleSpawned",
  VEH_DESPAWNED  = "vHub:vehicleDespawned",
  VEH_ENTER      = "vHub:vehicleEnter",
  VEH_LEAVE      = "vHub:vehicleLeave",
  VEH_FUEL_EMPTY = "vHub:vehicleFuelEmpty",
}
```

### 7.2 Logger estruturado — substituir `print` direto
```lua
-- shared/logger.lua
local Logger = {}
local LEVELS = {DEBUG=0, INFO=1, WARN=2, ERROR=3}

function Logger:log(level, module, msg, data)
  local cfg_level = LEVELS[(vHub.cfg or {}).log_level or "INFO"] or 1
  if LEVELS[level] < cfg_level then return end
  local line = ("[vHub][%s][%s] %s"):format(level, module, msg)
  if data then line = line .. " " .. json.encode(data) end
  print(line)
end

function Logger:debug(m, msg, d) self:log("DEBUG", m, msg, d) end
function Logger:info(m, msg, d)  self:log("INFO",  m, msg, d) end
function Logger:warn(m, msg, d)  self:log("WARN",  m, msg, d) end
function Logger:error(m, msg, d) self:log("ERROR", m, msg, d) end

vHub.Logger = Logger
```

### 7.3 Config com schema e defaults — evitar nil panic
```lua
-- shared/config.lua
local defaults = {
  log_level          = "INFO",
  whitelist_enabled  = false,
  fuel_rate          = 0.005,
  max_payload        = 8192,
  save_interval      = 60,
  max_ping           = 800,
  max_speed_kmh      = 300,
  trusted_resources  = {},
  modules            = {},
  webhooks           = {},
  lang               = {
    not_whitelisted  = "Sem whitelist. Seu ID: ",
  },
}

function vHub.mergeConfig(user_cfg)
  for k, v in pairs(defaults) do
    if user_cfg[k] == nil then user_cfg[k] = v end
  end
  return user_cfg
end
```

---

## 8. Nativos FiveM subutilizados — oportunidades

| Nativo | Uso sugerido no vHub |
|---|---|
| `GetPlayerRoutingBucket` / `SetPlayerRoutingBucket` | Instâncias privadas (eventos, apartamentos, missões) |
| `SetEntityDistanceCullingRadius` | Forçar render de veículos em garagem ao spawnar |
| `NetworkGetEntityOwner` | Health check periódico de ownership |
| `GetPlayerServerId` | Validação extra de source em eventos |
| `IsPlayerAceAllowed` | Admin bypass sem depender de VRAM |
| `GetInvokingResource` | Whitelist de resources que chamam exports sensíveis |
| `GetPlayerPing` | Anti-exploit de ping e kick automático |
| `VerifyPasswordHash` | Futura camada de auth local |
| `AddStateBagChangeHandler` | Client reage a mudanças de fuel/tuning sem polling |
| `GetVehicleCurrentRpm` | Cálculo server-side de consumo de combustível mais preciso |
| `GetEntitySpeed` | Validação de odômetro delta no server |
| `SetVehicleFuelLevel` | Client aplica fuel do State Bag |
| `NetworkResurrectLocalPlayer` | Hook em respawn para lógica de morte |

---

## 9. Roadmap de implementação sugerido

### Sprint 1 — Estabilidade (sem quebrar compatibilidade)
1. Adicionar `S._flushing` guard no `_flush()`
2. Normalizar placa em `validPlate`
3. Priorizar identificadores em `Auth:_ids`
4. Webhook com retry
5. `Logger` estruturado substituindo `print`

### Sprint 2 — Organização (refactor sem features novas)
6. Separar em arquivos por responsabilidade (server/, client/, shared/)
7. `vHub.Events` constantes de eventos
8. Config com defaults e validação
9. `assertThread()` nas funções que precisam

### Sprint 3 — Features e Segurança
10. `client/vehicle.lua` completo com State Bag handlers
11. `client/core.lua` com loop de report (4hz, sem position)
12. `IsPlayerAceAllowed` no Sec
13. `GetInvokingResource` nos exports críticos
14. `GetPlayerRoutingBucket` como API de instância

### Sprint 4 — Performance e Nativos
15. `AddStateBagChangeHandler` no client para fuel/tuning
16. `NetworkGetEntityOwner` health check periódico
17. `GetPlayerPing` auto-kick
18. Odômetro validado por velocidade real

---

## 10. Resumo executivo

O **vHub está no nível de um framework de produção intermediário-avançado** — muito acima dos vRPs brasileiros típicos, tecnicamente equivalente ao vRP2 oficial em maturidade de design e **superior em sincronização de veículo, segurança de rede e consistência de dados**.

O que o impede de ser tier S:
- Monolítico (1 arquivo para 3000+ LOC)
- Sem camada client estruturada
- Alguns race conditions de borda em alta concorrência
- Nativos FiveM importantes não aproveitados

Nenhum desses problemas exige reescrever do zero. São evoluções incrementais sobre uma base sólida.