# vHub — Plano Mestre de Construção S+ AAA
## Guia Arquitetural Definitivo com Checklist de Fluxo Lógico

> **Objetivo**: Transformar o vHub de B+/A− para S+ AAA militar — robustez de servidor de produção,  
> segurança de grau bancário, organização modular de engenharia de software profissional,  
> aproveitamento máximo dos nativos FiveM e zero tolerância a race conditions ou perda de dados.

> **Regra de ouro**: Nenhum item de checklist pode ser marcado como concluído sem que o item  
> anterior esteja 100% funcional e testado. A ordem é rígida. Não existe "mais ou menos pronto".

---

## ÍNDICE

```
[FASE 0]  Lei do Projeto — regras imutáveis
[FASE 1]  Estrutura de Arquivos — árvore final
[SPRINT 0] Fundação — shared/ (utils, config, events, logger)
[SPRINT 1] Estabilidade — correções críticas sem features novas
[SPRINT 2] Organização — refactor em multi-arquivo sem quebrar compat
[SPRINT 3] Client-side — camada client completa e estruturada
[SPRINT 4] Segurança — hardening de grau militar
[SPRINT 5] Performance — nativos FiveM máximos + otimizações
[SPRINT 6] Observabilidade — logs estruturados, métricas, health check
[SPRINT 7] Testes e Validação — checklist de smoke test por módulo
[APÊNDICE A] SQL Schema final completo
[APÊNDICE B] fxmanifest.lua final
[APÊNDICE C] Glossário de decisões arquiteturais
```

---

## FASE 0 — LEI DO PROJETO (regras imutáveis)

Estas regras não são sugestões. Qualquer PR, commit ou mudança que viole uma dessas leis é  
automaticamente rejeitado, sem discussão.

### L-01 · VRAM é a verdade, SQL é o backup

Toda leitura começa na VRAM. SQL só é consultado se a chave não existir na VRAM.  
Toda escrita vai para VRAM imediatamente e para o batch SQL na sequência.  
**Nunca** ler do SQL quando a chave existe na VRAM. **Nunca** escrever no SQL sem atualizar a VRAM.

### L-02 · O servidor nunca confia no cliente

Qualquer valor numérico, string de placa, enum de assento, delta de odômetro ou flag de estado  
vindo do cliente é tratado como dado hostil até ser validado pelo servidor.  
O cliente é uma fonte de eventos de intenção, não de dados autoritativos.

### L-03 · FiveM native authority model — zero broadcast manual de posição

Posição de veículo é responsabilidade exclusiva de `NetworkSetEntityOwner`.  
**Nunca** enviar `TriggerClientEvent` com coordenadas de veículo.  
**Nunca** implementar um loop de sincronização de posição.  
Se um módulo precisar da posição de um veículo no servidor, usa `GetEntityCoords` na entidade.

### L-04 · Toda função que usa `Citizen.Await` deve estar em thread

Funções que chamam `Citizen.Await(S:query(...))` só podem ser invocadas de dentro de  
`Citizen.CreateThread`. Funções que têm esse requisito devem ter `assertThread()` como  
primeira linha. Violação causa deadlock silencioso — o pior tipo de bug.

### L-05 · Rate limit em todo net event, sem exceções

Todo `K:net(...)` deve ter `opts.rate` definido. Não existe net event "tão simples que não  
precisa de rate limit". O padrão mínimo aceitável é `{10, 5000, 30000}`.  
Net events administrativos têm rate mais restritivo, não mais permissivo.

### L-06 · Nenhum `print` direto — sempre `Logger`

Mensagens de log vão para `vHub.Logger`. `print(...)` puro é proibido após o Sprint 0.  
O Logger respeita o nível configurado e formata com módulo, nível e dados estruturados.

### L-07 · Separação de responsabilidade por arquivo

Um arquivo = uma responsabilidade. `kernel.lua` não toca em Auth. `auth.lua` não toca em  
Vehicle. `vehicle.lua` não toca em State diretamente — usa a API pública.  
Importações cruzadas só através das interfaces públicas (`vHub.Auth`, `vHub.State`, etc.).

### L-08 · Transações para toda operação multi-chave

Qualquer operação que escreva em mais de uma chave de dados simultaneamente usa  
`S:begin() → S:set(..., tx) → S:commit(tx, sql_ops)`.  
Operações de chave única podem escrever diretamente.

### L-09 · State Bags são read-only no cliente

O cliente lê State Bags com `AddStateBagChangeHandler` e aplica localmente.  
O cliente **nunca** escreve em State Bags — isso é responsabilidade exclusiva do servidor.

### L-10 · Flush forçado antes de qualquer desconexão

`playerDropped`, `onResourceStop`, emergência: sempre chamar `S:_flush()` síncrono  
antes de liberar a sessão. Dados não flushados são dados perdidos.

---

## FASE 1 — ESTRUTURA DE ARQUIVOS FINAL

Esta é a árvore canônica do projeto após todos os sprints.  
Cada arquivo tem uma e apenas uma responsabilidade definida.

```
vhub/
│
├── fxmanifest.lua                  ← declaração de resource, scripts em ordem de carga
│
├── shared/                         ← carregado em AMBOS server e client
│   ├── config.lua                  ← definições de cfg com defaults e validação
│   ├── events.lua                  ← constantes de nomes de eventos (sem strings literais)
│   ├── utils.lua                   ← formatadores, helpers puros (sem side effects)
│   └── logger.lua                  ← sistema de log estruturado por nível
│
├── server/
│   ├── kernel.lua                  ← [1] Event bus, rate limit, perms, exports FiveM
│   ├── state.lua                   ← [2] VRAM, TX, rollback, batch SQL, drivers
│   ├── auth.lua                    ← [3] Identidade, sessão, personagens, ban, whitelist
│   ├── vehicle.lua                 ← [4] Entidade soberana de veículo, State Bags
│   ├── security.lua                ← [5] Anti-dupe, admin guard, payload, ACE, invoker
│   ├── notify.lua                  ← [6] Discord webhooks com retry
│   ├── instance.lua                ← [NEW] Routing Buckets — instâncias privadas
│   ├── metrics.lua                 ← [NEW] Contadores de performance e health check
│   ├── sql.lua                     ← [9] Todos os S:prepare() + schema DDL
│   ├── compat.lua                  ← [A] vRP1/2/3 shim (Proxy, Tunnel, Extension)
│   └── init.lua                    ← [8] Boot: carrega tudo na ordem correta, registra net events
│
├── client/
│   ├── core.lua                    ← spawn, death, char sync, vHub:ready
│   ├── vehicle.lua                 ← State Bag handlers, report loop 4hz, enter/leave
│   ├── hud.lua                     ← (opcional) exibição de fuel/damage via State Bags
│   └── instance.lua                ← [NEW] reação a mudança de Routing Bucket
│
└── docs/
    ├── ARCHITECTURE.md             ← este arquivo (ou referência a ele)
    ├── EVENTS.md                   ← catálogo de todos os eventos com payload documentado
    └── SQL_SCHEMA.sql              ← schema completo pronto para executar
```

### Ordem de carga declarada no fxmanifest (crítica)

```
shared/config.lua       → primeiro, sem dependências
shared/events.lua       → segundo, define constantes
shared/utils.lua        → terceiro, helpers puros
shared/logger.lua       → quarto, depende de config

server/state.lua        → quinto, base de tudo no servidor
server/kernel.lua       → sexto, depende de state (para perms)
server/security.lua     → sétimo, depende de kernel
server/notify.lua       → oitavo, sem dependências internas
server/auth.lua         → nono, depende de state + kernel + security + notify
server/vehicle.lua      → décimo, depende de state + kernel + auth
server/instance.lua     → décimo-primeiro, depende de kernel + auth
server/metrics.lua      → décimo-segundo, depende de kernel
server/sql.lua          → décimo-terceiro, depende de state (usa S:prepare)
server/compat.lua       → décimo-quarto, depende de tudo acima
server/init.lua         → último no servidor, une tudo

client/core.lua         → primeiro no client
client/vehicle.lua      → segundo no client
client/instance.lua     → terceiro no client
client/hud.lua          → último no client (opcional)
```

---

## SPRINT 0 — FUNDAÇÃO: shared/

**Objetivo**: Criar os quatro arquivos compartilhados que todos os outros dependem.  
**Pré-requisito**: Nenhum. Este é o ponto zero.  
**Critério de conclusão**: Os 4 arquivos existem, carregam sem erro, e os testes de smoke passam.

```
┌─────────────────────────────────────────────────────────────────┐
│  SPRINT 0 · CHECKLIST                                           │
├─────────────────────────────────────────────────────────────────┤
│  ARQUIVO: shared/config.lua                                     │
├─────────────────────────────────────────────────────────────────┤
│  [ ] S0.01  Definir tabela _defaults com TODOS os campos        │
│             necessários para os Sprints 1–7                     │
│  [ ] S0.02  Implementar vHub.mergeConfig(user_cfg) que          │
│             preenche campos ausentes com defaults sem           │
│             sobrescrever o que o usuário definiu                │
│  [ ] S0.03  Implementar vHub.validateConfig(cfg) que            │
│             valida tipos (fuel_rate deve ser number, etc.)      │
│             e retorna lista de erros                            │
│  [ ] S0.04  Implementar vHub.requireConfig(field) que           │
│             lança erro claro se campo obrigatório ausente       │
│  [ ] S0.05  Garantir que config.lua não escreve em _G           │
│             (exceto vHub que já existe)                         │
│  [ ] S0.06  Smoke test: vHub.mergeConfig({}) retorna objeto     │
│             com todos os defaults preenchidos                   │
└─────────────────────────────────────────────────────────────────┘

---

IMPLEMENTATION STATUS (resumo rápido):

- SPRINT 0: concluído — `shared/config.lua`, `shared/events.lua`, `shared/utils.lua`, `shared/logger.lua` criados.
- SPRINT 1: correções de estabilidade aplicadas parcialmente em `base.lua`: payload size check, `vHub.assertThread()` nas APIs com `Citizen.Await`, _flush reentrância tratada, odometer validation, owner reconciliation, exports guard, e inicializador `vHub._next_user_id` para reduzir risco de `LAST_INSERT_ID`.
- Próximo: rodar smoke tests S0.x, validar SPRINT 1 em ambiente de teste, then proceed to SPRINT 2 with architect approval.

┌─────────────────────────────────────────────────────────────────┐
│  ARQUIVO: shared/events.lua                                     │
├─────────────────────────────────────────────────────────────────┤
│  [ ] S0.07  Criar vHub.E (alias de vHub.Events) como tabela     │
│             imutável (setmetatable com __newindex que lança)    │
│  [ ] S0.08  Definir constante para CADA evento do projeto:      │
│             NET_READY, NET_DIED, NET_V_SPAWNED, NET_V_DESPAWNED │
│             NET_V_ENTER, NET_V_LEAVE, NET_V_STATE,             │
│             NET_SELECT_CHAR, NET_RELOAD, NET_V_REFUEL,         │
│             EVT_PLAYER_JOIN, EVT_PLAYER_LEAVE, EVT_PLAYER_SPAWN │
│             EVT_PLAYER_DEATH, EVT_CHAR_LOAD,                   │
│             EVT_VEH_LOADED, EVT_VEH_SPAWNED,                   │
│             EVT_VEH_DESPAWNED, EVT_VEH_ENTER, EVT_VEH_LEAVE,   │
│             EVT_VEH_FUEL_EMPTY, EVT_VEH_KEY_TRANSFERRED        │
│  [ ] S0.09  Smoke test: tentar vHub.E.FOO = "x" lança erro     │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  ARQUIVO: shared/utils.lua                                      │
├─────────────────────────────────────────────────────────────────┤
│  [ ] S0.10  Mover vHub.formatNumber de base.lua para utils.lua  │
│  [ ] S0.11  Mover vHub.formatTime de base.lua para utils.lua    │
│  [ ] S0.12  Adicionar vHub.clamp(val, min, max)                 │
│  [ ] S0.13  Adicionar vHub.safeUnpack(msgpack_str) que retorna  │
│             nil em caso de erro de decode (sem panic)           │
│  [ ] S0.14  Adicionar vHub.safePack(val) que retorna ""         │
│             em caso de erro de encode                           │
│  [ ] S0.15  Adicionar vHub.normalizePlate(str) — upper(),       │
│             trim espaços, validação de charset                  │
│  [ ] S0.16  Adicionar vHub.tableSize(t) — conta entradas de     │
│             tabela (para tabelas com chaves não numéricas)      │
│  [ ] S0.17  Smoke tests: cada função com entrada válida         │
│             e inválida                                          │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  ARQUIVO: shared/logger.lua                                     │
├─────────────────────────────────────────────────────────────────┤
│  [ ] S0.18  Definir LEVELS = {DEBUG=0, INFO=1, WARN=2, ERROR=3} │
│  [ ] S0.19  Implementar vHub.Logger:log(level, module, msg, data)│
│             que formata: [vHub][LEVEL][MODULE] msg {data_json} │
│  [ ] S0.20  Implementar atalhos :debug, :info, :warn, :error    │
│  [ ] S0.21  Logger respeita vHub.cfg.log_level (padrão "INFO")  │
│  [ ] S0.22  Logger funciona ANTES de vHub.cfg estar definido    │
│             (usar nível INFO como fallback)                     │
│  [ ] S0.23  Smoke test: Logger:warn("auth", "teste") imprime    │
│             no formato correto                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Código canônico — shared/config.lua

```lua
-- shared/config.lua
-- Responsabilidade: defaults, merge, validação de cfg
-- Depende de: nada
-- NÃO modificar sem atualizar ARCHITECTURE.md

local _defaults = {
  -- Sistema
  log_level           = "INFO",       -- DEBUG | INFO | WARN | ERROR
  save_interval       = 60,           -- segundos entre auto-saves
  max_payload         = 8192,         -- bytes máximos por net event
  modules             = {},           -- lista de resources a reiniciar no reload

  -- Segurança
  whitelist_enabled   = false,
  trusted_resources   = {},           -- resources que podem chamar exports críticos
  max_ping            = 800,          -- ms; acima → kick automático
  ping_check_interval = 30,           -- segundos entre ping checks

  -- Veículo
  fuel_rate           = 0.005,        -- consumo por unidade de RPM por tick
  max_speed_kmh       = 350,          -- limite físico para validação de odômetro
  veh_state_hz        = 4,            -- frequência de update de estado (server-side cap)

  -- DB
  db = {},                            -- passado para o driver (host, port, etc.)

  -- Webhooks
  webhooks = {
    join     = "",
    leave    = "",
    ban      = "",
    security = "",
  },

  -- i18n
  lang = {
    not_whitelisted = "Sem whitelist. Seu ID: ",
    banned          = "Você foi banido.",
    duplicate_login = "Você entrou de outro lugar.",
  },
}

function vHub.mergeConfig(user_cfg)
  local merged = user_cfg or {}
  for k, v in pairs(_defaults) do
    if merged[k] == nil then
      -- deep copy para tabelas evita aliasing
      if type(v) == "table" then
        merged[k] = {}
        for ik, iv in pairs(v) do merged[k][ik] = iv end
      else
        merged[k] = v
      end
    end
  end
  return merged
end

function vHub.validateConfig(cfg)
  local errors = {}
  local function expect(field, typ)
    if type(cfg[field]) ~= typ then
      errors[#errors+1] = ("cfg.%s deve ser %s, recebido %s"):format(
        field, typ, type(cfg[field]))
    end
  end
  expect("log_level",         "string")
  expect("save_interval",     "number")
  expect("max_payload",       "number")
  expect("whitelist_enabled", "boolean")
  expect("fuel_rate",         "number")
  expect("max_speed_kmh",     "number")
  expect("max_ping",          "number")
  return #errors == 0, errors
end

function vHub.requireConfig(field)
  assert(vHub.cfg and vHub.cfg[field] ~= nil,
    ("[vHub][CONFIG] Campo obrigatório ausente: cfg.%s"):format(field))
end
```

### Código canônico — shared/events.lua

```lua
-- shared/events.lua
-- Responsabilidade: nomes canônicos de eventos como constantes imutáveis
-- Depende de: nada

local _events = {
  -- Net events (client → server)
  NET_READY          = "vHub:ready",
  NET_DIED           = "vHub:died",
  NET_V_SPAWNED      = "vHub:vSpawned",
  NET_V_DESPAWNED    = "vHub:vDespawned",
  NET_V_ENTER        = "vHub:vEnter",
  NET_V_LEAVE        = "vHub:vLeave",
  NET_V_STATE        = "vHub:vState",
  NET_V_REFUEL       = "vHub:vRefuel",
  NET_SELECT_CHAR    = "vHub:selectChar",
  NET_RELOAD         = "vHub:reload",

  -- Eventos internos (TriggerEvent server-side)
  EVT_PLAYER_JOIN    = "vHub:playerJoin",
  EVT_PLAYER_LEAVE   = "vHub:playerLeave",
  EVT_PLAYER_SPAWN   = "vHub:playerSpawn",
  EVT_PLAYER_DEATH   = "vHub:playerDeath",
  EVT_CHAR_LOAD      = "vHub:characterLoad",

  -- Eventos de veículo
  EVT_VEH_LOADED             = "vHub:vehicleLoaded",
  EVT_VEH_SPAWNED            = "vHub:vehicleSpawned",
  EVT_VEH_DESPAWNED          = "vHub:vehicleDespawned",
  EVT_VEH_ENTER              = "vHub:vehicleEnter",
  EVT_VEH_LEAVE              = "vHub:vehicleLeave",
  EVT_VEH_FUEL_EMPTY         = "vHub:vehicleFuelEmpty",
  EVT_VEH_KEY_TRANSFERRED    = "vHub:vehicleKeyTransferred",

  -- Eventos client → client (emitidos pelo servidor)
  CLI_INIT_DONE      = "vHub:initDone",
  CLI_CHAR_SELECTED  = "vHub:charSelected",
  CLI_CHAR_FAILED    = "vHub:charSelectFailed",
  CLI_VEH_STATE_LOAD = "vHub:vehicleStateLoad",
  CLI_PASSENGER_MODE = "vHub:passengerMode",
}

-- Tabela imutável — qualquer tentativa de adicionar campo em runtime é erro
vHub.Events = setmetatable({}, {
  __index    = _events,
  __newindex = function(_, k, _)
    error(("[vHub][EVENTS] Tentativa de modificar constante de evento: %s"):format(tostring(k)), 2)
  end,
})
vHub.E = vHub.Events  -- alias curto
```

### Código canônico — shared/logger.lua

```lua
-- shared/logger.lua
-- Responsabilidade: log estruturado com nível, módulo e dados
-- Depende de: shared/config.lua (opcional — fallback para INFO)

local LEVELS = { DEBUG = 0, INFO = 1, WARN = 2, ERROR = 3 }

local Logger = {}; Logger.__index = Logger
vHub.Logger = Logger

function Logger:_lvl()
  local cfg_level = (vHub.cfg or {}).log_level or "INFO"
  return LEVELS[cfg_level] or 1
end

function Logger:log(level, module, msg, data)
  if (LEVELS[level] or 0) < self:_lvl() then return end
  local line = ("[vHub][%s][%s] %s"):format(level, module, tostring(msg))
  if data ~= nil then
    local ok, encoded = pcall(json.encode, data)
    if ok then line = line .. " " .. encoded end
  end
  print(line)
end

function Logger:debug(m, msg, d) self:log("DEBUG", m, msg, d) end
function Logger:info(m, msg, d)  self:log("INFO",  m, msg, d) end
function Logger:warn(m, msg, d)  self:log("WARN",  m, msg, d) end
function Logger:error(m, msg, d) self:log("ERROR", m, msg, d) end
```

---

## SPRINT 1 — ESTABILIDADE: correções críticas no código existente

**Objetivo**: Corrigir todos os bugs identificados na análise sem adicionar features.  
**Pré-requisito**: Sprint 0 concluído e todos os smoke tests passando.  
**Regra**: Nenhuma linha nova de feature. Só correções e o Logger substituindo `print`.

```
┌─────────────────────────────────────────────────────────────────┐
│  SPRINT 1 · CHECKLIST                                           │
├─────────────────────────────────────────────────────────────────┤
│  CORREÇÃO 1: _flush() — guard de re-entrância                   │
├─────────────────────────────────────────────────────────────────┤
│  [ ] S1.01  Adicionar S._flushing = false na declaração de S    │
│  [ ] S1.02  No início de _flush(): se _flushing, return         │
│  [ ] S1.03  Ao entrar na thread de batch: _flushing = true      │
│  [ ] S1.04  Ao sair da thread de batch: _flushing = false       │
│             (DENTRO de pcall para garantir mesmo em erro)       │
│  [ ] S1.05  Teste: chamar _flush() 3x simultâneos, verificar    │
│             que só 1 batch é processado por vez                 │
├─────────────────────────────────────────────────────────────────┤
│  CORREÇÃO 2: Auth._ids() — prioridade de identificadores        │
├─────────────────────────────────────────────────────────────────┤
│  [ ] S1.06  Implementar ordem de prioridade:                    │
│             1° license: (Rockstar — mais estável)               │
│             2° steam:   (segundo mais estável)                  │
│             3° discord: (terceiro)                              │
│             4° fivem:   (opcional)                              │
│             resto: qualquer outro exceto ip:                    │
│  [ ] S1.07  Garantir que IDs duplicados não entram na lista     │
│  [ ] S1.08  Teste: com IDs na ordem inversa, a prioridade       │
│             é respeitada                                        │
├─────────────────────────────────────────────────────────────────┤
│  CORREÇÃO 3: validPlate → normalizePlate                        │
├─────────────────────────────────────────────────────────────────┤
│  [ ] S1.09  Usar vHub.normalizePlate() de utils.lua             │
│  [ ] S1.10  normalizePlate: upper(), trim, validar charset       │
│             A-Z, 0-9, espaço; len 1-10                          │
│  [ ] S1.11  Todos os pontos de entrada de placa normalizam       │
│             antes de usar: onSpawned, onEnter, register, etc.  │
│  [ ] S1.12  Teste: placa "abc 123" normaliza para "ABC 123"     │
├─────────────────────────────────────────────────────────────────┤
│  CORREÇÃO 4: Notify — retry com backoff                         │
├─────────────────────────────────────────────────────────────────┤
│  [ ] S1.13  Notify:send(ch, msg, retries) — retries padrão = 3  │
│  [ ] S1.14  Em caso de falha (code ~= 204 e ~= 200):            │
│             SetTimeout(5000 * (4 - retries), retry)            │
│  [ ] S1.15  Log de warn se falha; log de error se esgota retry  │
│  [ ] S1.16  Canais críticos (ban, security): retries = 5        │
├─────────────────────────────────────────────────────────────────┤
│  CORREÇÃO 5: assertThread() — proteção de funções com Await     │
├─────────────────────────────────────────────────────────────────┤
│  [ ] S1.17  Implementar assertThread() em utils.lua (server)    │
│             → assert(Citizen.GetCurrentThread() ~= nil, ...)    │
│  [ ] S1.18  Adicionar assertThread() nas funções:               │
│             Auth:connect, Auth:_resolveUID, Auth:getCharacters  │
│             Auth:selectCharacter, Veh:register, Veh:byKey       │
│             S:query, S:scalar, S:exec                           │
│  [ ] S1.19  Teste: chamar Auth:connect fora de thread lança     │
│             erro claro com mensagem de diagnóstico              │
├─────────────────────────────────────────────────────────────────┤
│  CORREÇÃO 6: substituir todos os print() por Logger             │
├─────────────────────────────────────────────────────────────────┤
│  [ ] S1.20  Buscar todos os print( no código e substituir       │
│  [ ] S1.21  Nível correto por contexto:                         │
│             Inicialização normal    → Logger:info               │
│             Rate limit bloqueado   → Logger:warn                │
│             Perm fail / SEC        → Logger:warn                │
│             Erros de net event     → Logger:error               │
│             Rollback               → Logger:warn                │
│             FATAL (DB falhou)      → Logger:error               │
│  [ ] S1.22  Grep final: zero ocorrências de print( no projeto   │
│             (exceto dentro de Logger:log que é o único allowed) │
├─────────────────────────────────────────────────────────────────┤
│  CORREÇÃO 7: odômetro — validação por velocidade real           │
├─────────────────────────────────────────────────────────────────┤
│  [ ] S1.23  Calcular max_delta = rpm * max_speed_kmh /          │
│             veh_state_hz / 3600                                 │
│  [ ] S1.24  Substituir math.min(upd.odometer_delta, 0.5) por    │
│             math.min(upd.odometer_delta, max_delta)            │
│  [ ] S1.25  max_speed_kmh vem de vHub.cfg — padrão 350          │
└─────────────────────────────────────────────────────────────────┘
```

### Código canônico — correção de _flush()

```lua
-- Em state.lua — substituir a função _flush existente por:

S._flushing = false

function S:_flush()
  if self._batchN == 0 or not self._ready or self._flushing then return end
  self._flushing = true
  local ops, n = self._batch, self._batchN
  self._batch, self._batchN = {}, 0
  Citizen.CreateThread(function()
    local ok, err = pcall(function()
      self._driver:batch(ops, n)
    end)
    if not ok then
      vHub.Logger:error("state", "Erro no batch flush", {err=err, n=n})
    end
    self._flushing = false
  end)
end
```

### Código canônico — correção de Auth:_ids()

```lua
-- Em auth.lua — substituir _ids por:

function Auth:_ids(src)
  local raw  = GetPlayerIdentifiers(src) or {}
  local prio = {"license:", "steam:", "discord:", "fivem:"}
  local ids, seen = {}, {}

  -- Primeira passagem: identificadores prioritários na ordem definida
  for _, prefix in ipairs(prio) do
    for _, id in ipairs(raw) do
      if not seen[id] and id:sub(1, #prefix) == prefix then
        ids[#ids+1] = id; seen[id] = true
      end
    end
  end

  -- Segunda passagem: demais (exceto ip:)
  for _, id in ipairs(raw) do
    if not seen[id] and not id:find("^ip:") then
      ids[#ids+1] = id; seen[id] = true
    end
  end

  return ids
end
```


---

## SPRINT 2 — ORGANIZAÇÃO: refactor multi-arquivo

**Objetivo**: Separar o monolito em arquivos por responsabilidade, mantendo 100% de compatibilidade.  
**Pré-requisito**: Sprint 1 concluído. Zero regressões.  
**Estratégia**: Extrair um módulo por vez, testar, depois extrair o próximo. Nunca extrair dois ao mesmo tempo.

```
┌─────────────────────────────────────────────────────────────────┐
│  SPRINT 2 · CHECKLIST                                           │
├─────────────────────────────────────────────────────────────────┤
│  PASSO 2.1: Criar fxmanifest.lua com nova ordem de carga        │
├─────────────────────────────────────────────────────────────────┤
│  [ ] S2.01  fxmanifest.lua lista arquivos na ordem canônica     │
│             definida na FASE 1 deste documento                  │
│  [ ] S2.02  Declarar server_exports para TODOS os exports       │
│             públicos (getUser, getUID, hasPerm, etc.)           │
│  [ ] S2.03  Declarar shared_scripts para shared/               │
│  [ ] S2.04  Declarar server_scripts para server/               │
│  [ ] S2.05  Declarar client_scripts para client/               │
├─────────────────────────────────────────────────────────────────┤
│  PASSO 2.2: Extrair server/notify.lua                           │
├─────────────────────────────────────────────────────────────────┤
│  [ ] S2.06  Mover Notify completo (com retry do Sprint 1)       │
│  [ ] S2.07  Notify referencia vHub.cfg e vHub.Logger            │
│             (ambos já disponíveis quando notify.lua carrega)    │
│  [ ] S2.08  Remover Notify do monolito                          │
│  [ ] S2.09  Smoke test: webhook de join funciona                │
├─────────────────────────────────────────────────────────────────┤
│  PASSO 2.3: Extrair server/state.lua                            │
├─────────────────────────────────────────────────────────────────┤
│  [ ] S2.10  Mover S (State) completo com correções do Sprint 1  │
│  [ ] S2.11  State expõe S como vHub.State                       │
│  [ ] S2.12  Mover as funções públicas de API de dados:          │
│             vHub.getUData, vHub.setUData, vHub.getCData, etc.   │
│  [ ] S2.13  Remover State do monolito                           │
│  [ ] S2.14  Smoke test: S:begin() / S:commit() funciona         │
├─────────────────────────────────────────────────────────────────┤
│  PASSO 2.4: Extrair server/kernel.lua                           │
├─────────────────────────────────────────────────────────────────┤
│  [ ] S2.15  Mover K (Kernel) completo                           │
│  [ ] S2.16  Kernel usa vHub.Logger em vez de print              │
│  [ ] S2.17  K:net usa vHub.E.NET_* para os nomes dos eventos    │
│             (mas aceita string direta também para compat)       │
│  [ ] S2.18  Kernel expõe K como vHub.Kernel                     │
│  [ ] S2.19  Remover Kernel do monolito                          │
│  [ ] S2.20  Smoke test: K:net com rate funciona                 │
├─────────────────────────────────────────────────────────────────┤
│  PASSO 2.5: Extrair server/security.lua                         │
├─────────────────────────────────────────────────────────────────┤
│  [ ] S2.21  Mover Sec (Security) completo                       │
│  [ ] S2.22  Sec depende de K (Kernel) e Auth                    │
│             mas Auth ainda não foi extraído — usar              │
│             vHub.Auth que será definido depois (lazy ref)       │
│  [ ] S2.23  Remover Security do monolito                        │
│  [ ] S2.24  Smoke test: _permFail não quebra sem Auth           │
├─────────────────────────────────────────────────────────────────┤
│  PASSO 2.6: Extrair server/auth.lua                             │
├─────────────────────────────────────────────────────────────────┤
│  [ ] S2.25  Mover Auth completo com correções do Sprint 1       │
│             (prioridade de IDs, assertThread)                   │
│  [ ] S2.26  Auth usa vHub.E.EVT_* para TriggerEvent             │
│  [ ] S2.27  Auth usa vHub.E.CLI_* para K:emit                   │
│  [ ] S2.28  Auth expõe como vHub.Auth                           │
│  [ ] S2.29  Remover Auth do monolito                            │
│  [ ] S2.30  Smoke test: connect + disconnect completo           │
├─────────────────────────────────────────────────────────────────┤
│  PASSO 2.7: Extrair server/vehicle.lua                          │
├─────────────────────────────────────────────────────────────────┤
│  [ ] S2.31  Mover Veh completo com correção de normalizePlate   │
│  [ ] S2.32  Veh usa vHub.E para todos os eventos                │
│  [ ] S2.33  Veh expõe como vHub.Vehicle                         │
│  [ ] S2.34  Remover Vehicle do monolito                         │
│  [ ] S2.35  Smoke test: register + onSpawned + onEnter          │
├─────────────────────────────────────────────────────────────────┤
│  PASSO 2.8: Extrair server/sql.lua                              │
├─────────────────────────────────────────────────────────────────┤
│  [ ] S2.36  Mover todos os S:prepare() para sql.lua             │
│  [ ] S2.37  sql.lua é o ÚLTIMO arquivo server a carregar        │
│             (exceto compat e init) pois depende de S:prepare    │
│  [ ] S2.38  Smoke test: queries executam corretamente           │
├─────────────────────────────────────────────────────────────────┤
│  PASSO 2.9: Extrair server/compat.lua                           │
├─────────────────────────────────────────────────────────────────┤
│  [ ] S2.39  Mover vRP shim completo para compat.lua             │
│  [ ] S2.40  compat.lua depende de todos os módulos acima        │
│  [ ] S2.41  Verificar que scripts vRP1 ainda funcionam          │
│  [ ] S2.42  Verificar que scripts vRP2 Extension ainda funcionam│
├─────────────────────────────────────────────────────────────────┤
│  PASSO 2.10: Criar server/init.lua (boot)                       │
├─────────────────────────────────────────────────────────────────┤
│  [ ] S2.43  vHub:init(cfg, db_driver) movido para init.lua      │
│  [ ] S2.44  init.lua usa vHub.E para TODOS os net events        │
│  [ ] S2.45  init.lua usa vHub.E para TODOS os AddEventHandler   │
│  [ ] S2.46  init.lua é o ÚLTIMO arquivo a carregar no servidor  │
│  [ ] S2.47  Remover qualquer resquício do monolito original      │
│  [ ] S2.48  Smoke test: resource inicia sem erros               │
├─────────────────────────────────────────────────────────────────┤
│  VALIDAÇÃO FINAL DO SPRINT 2                                    │
├─────────────────────────────────────────────────────────────────┤
│  [ ] S2.49  grep -r "print(" server/ → zero resultados          │
│  [ ] S2.50  grep -r '"vHub:' server/ → zero resultados          │
│             (todos os strings de evento são via vHub.E.*)       │
│  [ ] S2.51  Conectar 10 jogadores simultâneos — sem erros       │
│  [ ] S2.52  Desconectar todos — dados persistidos corretamente  │
│  [ ] S2.53  Resource restart — sem perda de dados de sessão     │
│             ativa (emergência save funciona)                    │
└─────────────────────────────────────────────────────────────────┘
```

### Código canônico — fxmanifest.lua

```lua
-- fxmanifest.lua
fx_version  'cerulean'
game        'gta5'
lua54       'yes'

author      'vHub Framework'
description 'vHub — Production-grade FiveM RP framework'
version     '2.0.0'

-- Carregado em AMBOS server e client, nesta ordem
shared_scripts {
  'shared/config.lua',
  'shared/events.lua',
  'shared/utils.lua',
  'shared/logger.lua',
}

-- Carregado APENAS no servidor, em ordem de dependência
server_scripts {
  'server/state.lua',
  'server/kernel.lua',
  'server/security.lua',
  'server/notify.lua',
  'server/auth.lua',
  'server/vehicle.lua',
  'server/instance.lua',
  'server/metrics.lua',
  'server/sql.lua',
  'server/compat.lua',
  'server/init.lua',    -- sempre por último
}

-- Carregado APENAS no cliente, em ordem de dependência
client_scripts {
  'client/core.lua',
  'client/vehicle.lua',
  'client/instance.lua',
  'client/hud.lua',
}

-- Exports declarados explicitamente para descoberta por outros resources
server_exports {
  'getVHub',
  'getUser',
  'getUID',
  'hasPerm',
  'grantPerm',
  'getVehicle',
  'transferKey',
  'getVehicleByKey',
  'banPlayer',
  'unbanPlayer',
  'getInstance',
  'setInstance',
}
```

---

## SPRINT 3 — CLIENT-SIDE: camada client completa

**Objetivo**: Criar a camada client estruturada que o servidor espera.  
**Pré-requisito**: Sprint 2 concluído. Todos os eventos CLI_* emitidos corretamente pelo servidor.  
**Regra L-02 aplicada**: Cliente nunca é fonte de verdade. Cliente reporta intenção, servidor valida.  
**Regra L-09 aplicada**: Cliente lê State Bags, nunca escreve.  
**Regra L-03 aplicada**: Zero coordenadas de veículo enviadas ao servidor.

```
┌─────────────────────────────────────────────────────────────────┐
│  SPRINT 3 · CHECKLIST                                           │
├─────────────────────────────────────────────────────────────────┤
│  ARQUIVO: client/core.lua                                       │
├─────────────────────────────────────────────────────────────────┤
│  [ ] S3.01  AddEventHandler "onClientGameTypeStart" →           │
│             TriggerServerEvent(vHub.E.NET_READY)               │
│  [ ] S3.02  AddEventHandler vHub.E.CLI_INIT_DONE →             │
│             armazenar uid local, char_id local, first_spawn     │
│  [ ] S3.03  AddEventHandler vHub.E.CLI_CHAR_SELECTED →         │
│             armazenar char_id local, disparar evento local      │
│  [ ] S3.04  AddEventHandler vHub.E.CLI_CHAR_FAILED →           │
│             notificar jogador com mensagem de erro              │
│  [ ] S3.05  AddEventHandler vHub.E.EVT_PLAYER_DEATH (client) → │
│             TriggerServerEvent(vHub.E.NET_DIED)                 │
│             usando AddEventHandler("gameEventTriggered") →      │
│             filtrar CEventNetworkEntityDamage                   │
│  [ ] S3.06  Expor vHub.localUID() e vHub.localCharId()          │
│             como getters client-side                            │
│  [ ] S3.07  Smoke test: spawn → init done recebido em < 1s     │
├─────────────────────────────────────────────────────────────────┤
│  ARQUIVO: client/vehicle.lua                                    │
├─────────────────────────────────────────────────────────────────┤
│  [ ] S3.08  AddStateBagChangeHandler("vh_fuel") →              │
│             SetVehicleFuelLevel(ent, value)                     │
│  [ ] S3.09  AddStateBagChangeHandler("vh_eng") →               │
│             SetVehicleEngineHealth(ent, value)                  │
│  [ ] S3.10  AddStateBagChangeHandler("vh_body") →              │
│             SetVehicleBodyHealth(ent, value)                    │
│  [ ] S3.11  AddStateBagChangeHandler("vh_tune") →              │
│             aplicar mods via SetVehicleMod em loop              │
│  [ ] S3.12  AddStateBagChangeHandler("vh_on") →                │
│             SetVehicleEngineOn(ent, value, true, false)         │
│  [ ] S3.13  Cada handler valida que entidade existe antes       │
│             de aplicar: DoesEntityExist(ent) and                │
│             IsEntityAVehicle(ent)                               │
│  [ ] S3.14  Loop de report a 4hz (250ms):                       │
│             • Pegar veículo do pedestre: GetVehiclePedIsIn      │
│             • Se sem veículo: Wait(250) e continuar             │
│             • Se motorista (seat == -1):                        │
│               - rpm     = GetVehicleCurrentRpm(veh)            │
│               - eng     = GetVehicleEngineHealth(veh)          │
│               - body    = GetVehicleBodyHealth(veh)            │
│               - on      = GetIsVehicleEngineRunning(veh)       │
│               - speed   = GetEntitySpeed(veh) (m/s)            │
│               - delta   = speed * 0.25 / 1000 (km)            │
│               - plate   = GetVehicleNumberPlateText(veh)       │
│               TriggerServerEvent(NET_V_STATE, plate, upd)      │
│             • Se passageiro: não enviar estado                  │
│  [ ] S3.15  Detecção de enter/leave via                         │
│             AddEventHandler("gameEventTriggered") →            │
│             CEventNetworkPlayerEnteredVehicle /                │
│             CEventNetworkPlayerLeftVehicle                      │
│             → TriggerServerEvent(NET_V_ENTER/LEAVE, plate, netid, seat)│
│  [ ] S3.16  Ao entrar como motorista:                           │
│             aguardar CLI_VEH_STATE_LOAD e aplicar              │
│             estado salvo (fuel, engine, body)                   │
│  [ ] S3.17  Ao detectar spawn de veículo (IsPedInAnyVehicle    │
│             false → true): TriggerServerEvent(NET_V_SPAWNED)   │
│  [ ] S3.18  Ao detectar despawn: NET_V_DESPAWNED               │
│  [ ] S3.19  Smoke test: entrar em veículo → State Bags          │
│             recebidos e aplicados em < 500ms                   │
├─────────────────────────────────────────────────────────────────┤
│  ARQUIVO: client/instance.lua                                   │
├─────────────────────────────────────────────────────────────────┤
│  [ ] S3.20  AddEventHandler "vHub:instanceSet" →               │
│             armazenar bucket local                              │
│  [ ] S3.21  Ao mudar de bucket, disparar evento local           │
│             "vHub:instanceChanged" com o novo id               │
│  [ ] S3.22  Expor vHub.getCurrentInstance() client-side         │
├─────────────────────────────────────────────────────────────────┤
│  ARQUIVO: client/hud.lua (opcional mas recomendado)             │
├─────────────────────────────────────────────────────────────────┤
│  [ ] S3.23  AddStateBagChangeHandler("vh_fuel") (segundo        │
│             handler — o primeiro aplica no veículo)             │
│             → armazenar fuel% local para exibição no HUD       │
│  [ ] S3.24  Loop de HUD a 100ms: exibir fuel, engine health    │
│             usando DrawText ou NUI — usando dados dos bags      │
│             sem nenhum round-trip ao servidor                   │
│  [ ] S3.25  HUD desativa automaticamente se sem veículo         │
└─────────────────────────────────────────────────────────────────┘
```

### Código canônico — client/vehicle.lua (estrutura base)

```lua
-- client/vehicle.lua
-- Responsabilidade: State Bag handlers, report loop, enter/leave detection
-- Regra L-02: Zero dados enviados sem validação local mínima
-- Regra L-03: NUNCA enviar posição. GTA cuida disso.
-- Regra L-09: NUNCA escrever em State Bags

local _currentVehicle = nil
local _currentPlate   = nil
local _isDriver       = false
local _odoAccum       = 0.0

-- ── State Bag handlers (servidor → cliente via bags) ──────────

local function _netidFromBag(bagName)
  local netid = tonumber(bagName:gsub("entity:", ""))
  if not netid then return nil end
  local ent = NetworkGetEntityFromNetworkId(netid)
  return (DoesEntityExist(ent) and IsEntityAVehicle(ent)) and ent or nil
end

AddStateBagChangeHandler("vh_fuel", nil, function(bagName, _, value)
  local ent = _netidFromBag(bagName); if not ent then return end
  SetVehicleFuelLevel(ent, math.max(0, math.min(100, tonumber(value) or 0)))
end)

AddStateBagChangeHandler("vh_eng", nil, function(bagName, _, value)
  local ent = _netidFromBag(bagName); if not ent then return end
  SetVehicleEngineHealth(ent, math.max(0, math.min(1000, tonumber(value) or 1000)))
end)

AddStateBagChangeHandler("vh_body", nil, function(bagName, _, value)
  local ent = _netidFromBag(bagName); if not ent then return end
  SetVehicleBodyHealth(ent, math.max(0, math.min(1000, tonumber(value) or 1000)))
end)

AddStateBagChangeHandler("vh_on", nil, function(bagName, _, value)
  local ent = _netidFromBag(bagName); if not ent then return end
  SetVehicleEngineOn(ent, value == true, true, false)
end)

AddStateBagChangeHandler("vh_tune", nil, function(bagName, _, tuning)
  local ent = _netidFromBag(bagName)
  if not ent or type(tuning) ~= "table" then return end
  for mod_type, mod_index in pairs(tuning) do
    SetVehicleMod(ent, tonumber(mod_type), tonumber(mod_index), false)
  end
end)

-- ── Report loop (client → servidor) ───────────────────────────
-- REGRA: nunca enviar mais do que vHub.cfg.veh_state_hz por segundo
-- REGRA: nunca enviar posição

CreateThread(function()
  local hz = (vHub.cfg or {}).veh_state_hz or 4
  local interval = math.floor(1000 / hz)
  local lastSpeed = 0.0

  while true do
    Wait(interval)
    if not _isDriver or not _currentVehicle or not DoesEntityExist(_currentVehicle) then
      goto continue
    end

    local veh   = _currentVehicle
    local speed = GetEntitySpeed(veh)  -- m/s
    local delta = speed * (interval / 1000) / 1000  -- km por tick

    -- Acumular odômetro localmente — evita flood de números pequenos
    _odoAccum = _odoAccum + delta
    local delta_send = 0.0
    if _odoAccum >= 0.01 then  -- só enviar ao acumular >= 10 metros
      delta_send = _odoAccum
      _odoAccum  = 0.0
    end

    TriggerServerEvent(vHub.E.NET_V_STATE, _currentPlate, {
      rpm            = GetVehicleCurrentRpm(veh),
      engine_health  = GetVehicleEngineHealth(veh),
      body_health    = GetVehicleBodyHealth(veh),
      engine_on      = GetIsVehicleEngineRunning(veh),
      odometer_delta = delta_send,
      -- Sem posição. Nunca. Lei L-03.
    })

    ::continue::
  end
end)

-- ── Enter / Leave detection via gameEventTriggered ────────────

AddEventHandler("gameEventTriggered", function(name, args)
  if name == "CEventNetworkPlayerEnteredVehicle" then
    local ped  = args[1]
    local veh  = args[2]
    if ped ~= PlayerPedId() then return end

    local plate  = GetVehicleNumberPlateText(veh)
    local netid  = NetworkGetNetworkIdFromEntity(veh)
    local seat   = GetPedSeatInVehicle(ped, veh)
    _currentVehicle = veh
    _currentPlate   = plate
    _isDriver       = (seat == -1)
    _odoAccum       = 0.0

    TriggerServerEvent(vHub.E.NET_V_ENTER, plate, netid, seat)

  elseif name == "CEventNetworkPlayerLeftVehicle" then
    local ped = args[1]
    if ped ~= PlayerPedId() then return end

    if _currentPlate then
      local seat = _isDriver and -1 or 0  -- aproximação
      TriggerServerEvent(vHub.E.NET_V_LEAVE, _currentPlate, seat)
    end
    _currentVehicle = nil
    _currentPlate   = nil
    _isDriver       = false
    _odoAccum       = 0.0
  end
end)

-- ── Aplicar estado salvo ao entrar como motorista ─────────────

AddEventHandler(vHub.E.CLI_VEH_STATE_LOAD, function(plate, state)
  if not _currentVehicle or plate ~= _currentPlate then return end
  local veh = _currentVehicle
  if not DoesEntityExist(veh) then return end

  -- Dados vêm dos State Bags via servidor — apenas aplicar
  -- (State Bags já dispararam os handlers acima, mas reforçar)
  if state.fuel          then SetVehicleFuelLevel(veh, state.fuel) end
  if state.engine_health then SetVehicleEngineHealth(veh, state.engine_health) end
  if state.body_health   then SetVehicleBodyHealth(veh, state.body_health) end
  if state.engine_on ~= nil then
    SetVehicleEngineOn(veh, state.engine_on, true, false)
  end
end)
```

---

## SPRINT 4 — SEGURANÇA: hardening de grau militar

**Objetivo**: Adicionar todas as camadas de segurança que o análise identificou.  
**Pré-requisito**: Sprint 3 concluído.  
**Princípio**: Defense in depth — múltiplas camadas independentes. A falha de uma não compromete o sistema.

```
┌─────────────────────────────────────────────────────────────────┐
│  SPRINT 4 · CHECKLIST                                           │
├─────────────────────────────────────────────────────────────────┤
│  SEC-1: IsPlayerAceAllowed — bypass de admin via ACE nativo     │
├─────────────────────────────────────────────────────────────────┤
│  [ ] S4.01  Sec:requireAdmin verifica IsPlayerAceAllowed        │
│             ANTES de verificar VRAM                             │
│             → admin no server.cfg nunca bloqueado por bug de DB │
│  [ ] S4.02  Adicionar instrução em ARCHITECTURE.md:             │
│             "add_ace group.admin vhub.admin allow"              │
│  [ ] S4.03  Smoke test: ACE admin pode fazer reload sem         │
│             entrada no banco                                    │
├─────────────────────────────────────────────────────────────────┤
│  SEC-2: GetInvokingResource — whitelist de exports críticos     │
├─────────────────────────────────────────────────────────────────┤
│  [ ] S4.04  Exports que devem verificar invoker:                │
│             banPlayer, unbanPlayer, transferKey                 │
│             grantPerm, setInstance                              │
│  [ ] S4.05  Implementar Sec:requireTrustedResource() que:       │
│             - obtém GetInvokingResource()                       │
│             - permite se nil (chamada interna)                  │
│             - permite se resource está em cfg.trusted_resources  │
│             - bloqueia e loga SEC warning caso contrário        │
│  [ ] S4.06  Smoke test: resource não listado não consegue banir │
├─────────────────────────────────────────────────────────────────┤
│  SEC-3: GetPlayerPing — anti-exploit de ping                    │
├─────────────────────────────────────────────────────────────────┤
│  [ ] S4.07  Loop periódico a cada cfg.ping_check_interval s     │
│  [ ] S4.08  Para cada sessão ativa: GetPlayerPing(src)          │
│  [ ] S4.09  Se ping > cfg.max_ping: DropPlayer + log warn       │
│             + Notify:send("security", ...)                      │
│  [ ] S4.10  Exemption: jogadores com ACE admin não são kickados │
│  [ ] S4.11  Smoke test: simular ping alto (cfg temporário baixo)│
├─────────────────────────────────────────────────────────────────┤
│  SEC-4: Validação de payload no kernel                          │
├─────────────────────────────────────────────────────────────────┤
│  [ ] S4.12  K:net verifica automaticamente tamanho do payload    │
│             antes de chamar o handler                           │
│  [ ] S4.13  Tamanho estimado via json.encode({...}) + #str       │
│             (aproximação suficiente para anti-abuse)            │
│  [ ] S4.14  Payload > cfg.max_payload: drop silencioso + warn   │
│  [ ] S4.15  Smoke test: enviar payload gigante → bloqueado       │
├─────────────────────────────────────────────────────────────────┤
│  SEC-5: Validação de source em todos os net events              │
├─────────────────────────────────────────────────────────────────┤
│  [ ] S4.16  K:net SEMPRE verifica: src > 0 e src <= 1023        │
│             (FiveM: source 0 = servidor, > 1023 = inválido)     │
│  [ ] S4.17  Verificar GetPlayerName(src) ~= nil antes de        │
│             processar qualquer evento                           │
│  [ ] S4.18  Se inválido: drop silencioso + Logger:warn          │
├─────────────────────────────────────────────────────────────────┤
│  SEC-6: Anti-spam de vSpawned / vEnter com placa inválida       │
├─────────────────────────────────────────────────────────────────┤
│  [ ] S4.19  Se placa falha normalizePlate: drop + Logger:warn    │
│             + incrementar contador de violações por src          │
│  [ ] S4.20  Após 5 placas inválidas em 60s:                     │
│             DropPlayer + Notify:send("security")                │
│  [ ] S4.21  Contador reseta no disconnect                        │
├─────────────────────────────────────────────────────────────────┤
│  SEC-7: VerifyPasswordHash — preparação para auth local         │
├─────────────────────────────────────────────────────────────────┤
│  [ ] S4.22  Adicionar vHub.Auth:hashPassword(plain) →           │
│             usar VerifyPasswordHash (nativo FiveM bcrypt)       │
│  [ ] S4.23  Adicionar vHub.Auth:checkPassword(plain, hash) →    │
│             retorna boolean                                     │
│  [ ] S4.24  Documentar: NUNCA armazenar senha em texto plano    │
│             na VRAM ou no SQL — usar hash sempre                │
├─────────────────────────────────────────────────────────────────┤
│  SEC-8: Rate limits revisados por evento                         │
├─────────────────────────────────────────────────────────────────┤
│  [ ] S4.25  Revisar TODOS os rate limits com tabela abaixo:     │
│                                                                 │
│  NET_READY:      {3, 30000, 300000}  -- 3x/30s, bloqueia 5min  │
│  NET_DIED:       {5, 20000, 60000}   -- 5x/20s, bloqueia 1min  │
│  NET_V_SPAWNED:  {15, 5000, 30000}   -- 15x/5s, bloqueia 30s  │
│  NET_V_DESPAWNED:{15, 5000, 30000}                              │
│  NET_V_ENTER:    {10, 3000, 15000}   -- 10x/3s                  │
│  NET_V_LEAVE:    {10, 3000, 15000}                              │
│  NET_V_STATE:    {8, 1000, 10000}    -- max 8hz, async=false    │
│  NET_SELECT_CHAR:{3, 10000, 60000}   -- 3x/10s                  │
│  NET_RELOAD:     {1, 120000, 600000} -- 1x/2min, bloqueia 10min │
│  NET_V_REFUEL:   {1, 5000, 30000}    -- 1x/5s                   │
│                                                                 │
│  [ ] S4.26  Aplicar os valores acima em init.lua                │
└─────────────────────────────────────────────────────────────────┘
```

### Código canônico — server/security.lua (versão hardened)

```lua
-- server/security.lua
-- Responsabilidade: verificações de segurança transversais
-- Depende de: kernel.lua (K), logger.lua, config.lua
-- NÃO depende de auth.lua diretamente (usa vHub.Auth lazy)

local Sec = {}; Sec.__index = Sec; vHub.Security = Sec

Sec._violations = {}  -- { [src] = {count, reset_at} }

-- ── Admin guard ───────────────────────────────────────────────

function Sec:requireAdmin(src, action)
  -- ACE nativo tem prioridade absoluta (funciona sem DB)
  if IsPlayerAceAllowed(src, "vhub.admin") then return true end
  if IsPlayerAceAllowed(src, "vhub." .. action) then return true end

  -- Fallback: permissão em VRAM
  local uid = vHub.Auth and vHub.Auth:getUID(src)
  if uid and vHub.Kernel:hasPerm(uid, "admin." .. action) then return true end

  self:_permFail(src, "admin." .. action, action)
  return false
end

-- ── Trusted resource guard ────────────────────────────────────

function Sec:requireTrustedResource(action)
  local caller = GetInvokingResource()
  if not caller then return true end  -- chamada interna = sempre OK
  local trusted = (vHub.cfg and vHub.cfg.trusted_resources) or {}
  if trusted[caller] then return true end
  vHub.Logger:warn("security", "Export bloqueado — resource não autorizado", {
    resource = caller, action = action
  })
  vHub.Notify:send("security",
    ("🔒 Export `%s` negado para resource `%s`"):format(action, caller))
  return false
end

-- ── Perm fail ─────────────────────────────────────────────────

function Sec:_permFail(src, event, perm)
  vHub.Logger:warn("security", "Perm negada", {src=src, event=event, perm=perm})
  vHub.Notify:send("security",
    ("🚨 Acesso negado | src:`%d` perm:`%s`"):format(src, tostring(perm)))
end

-- ── Payload size check ────────────────────────────────────────

function Sec:checkPayload(src, event, ...)
  local ok, encoded = pcall(json.encode, {...})
  if ok and #encoded > (vHub.cfg.max_payload or 8192) then
    vHub.Logger:warn("security", "Payload gigante bloqueado", {
      src=src, event=event, size=#encoded
    })
    return false
  end
  return true
end

-- ── Source validation ─────────────────────────────────────────

function Sec:isValidSource(src)
  if type(src) ~= "number" then return false end
  if src <= 0 or src > 1023 then return false end
  if not GetPlayerName(src)  then return false end
  return true
end

-- ── Plate violation tracker ───────────────────────────────────

function Sec:trackPlateViolation(src)
  local now = GetGameTimer()
  local v   = self._violations[src]
  if not v or now > v.reset_at then
    self._violations[src] = {count=1, reset_at=now+60000}
    return false
  end
  v.count = v.count + 1
  if v.count >= 5 then
    vHub.Logger:warn("security", "Muitas placas inválidas — kick", {src=src})
    DropPlayer(src, "Comportamento suspeito detectado.")
    vHub.Notify:send("security",
      ("⛔ Auto-kick por placas inválidas | src:`%d`"):format(src))
    self._violations[src] = nil
    return true  -- já kickado
  end
  return false
end

function Sec:clearViolations(src)
  self._violations[src] = nil
end

-- ── Ping check loop ───────────────────────────────────────────

CreateThread(function()
  while true do
    Wait((vHub.cfg and vHub.cfg.ping_check_interval or 30) * 1000)
    if not vHub.Auth then goto continue end
    for src, _ in pairs(vHub.Auth._sessions) do
      if not IsPlayerAceAllowed(src, "vhub.admin") then
        local ping = GetPlayerPing(src)
        if ping > (vHub.cfg.max_ping or 800) then
          vHub.Logger:warn("security", "Ping alto — kick", {src=src, ping=ping})
          DropPlayer(src, ("Ping muito alto (%dms). Tente novamente."):format(ping))
        end
      end
    end
    ::continue::
  end
end)
```

---

## SPRINT 5 — PERFORMANCE: nativos FiveM máximos

**Objetivo**: Aproveitar todos os nativos FiveM identificados na análise para reduzir overhead,  
eliminar round-trips e melhorar a experiência de 3000+ players simultâneos.  
**Pré-requisito**: Sprint 4 concluído.

```
┌─────────────────────────────────────────────────────────────────┐
│  SPRINT 5 · CHECKLIST                                           │
├─────────────────────────────────────────────────────────────────┤
│  PERF-1: server/instance.lua — Routing Buckets                  │
├─────────────────────────────────────────────────────────────────┤
│  [ ] S5.01  Criar vHub.Instance com API pública:                │
│             Instance:set(src, bucket_id) →                     │
│               SetPlayerRoutingBucket(src, bucket_id)           │
│               K:emit(src, "vHub:instanceSet", bucket_id)       │
│             Instance:get(src) →                                │
│               GetPlayerRoutingBucket(src)                      │
│             Instance:reset(src) →                              │
│               SetPlayerRoutingBucket(src, 0)                   │
│  [ ] S5.02  Ao fazer Auth:disconnect: Instance:reset(src)       │
│             garantir que jogador saiu do bucket privado         │
│  [ ] S5.03  Adicionar export "setInstance" e "getInstance"      │
│  [ ] S5.04  Smoke test: dois jogadores em buckets diferentes    │
│             não se veem no mundo                                │
├─────────────────────────────────────────────────────────────────┤
│  PERF-2: NetworkGetEntityOwner — health check periódico         │
├─────────────────────────────────────────────────────────────────┤
│  [ ] S5.05  Em Veh: criar loop a cada 10s que verifica          │
│             todos os veículos spawned com driver                │
│  [ ] S5.06  Para cada vd com netid e driver:                    │
│             - ent = NetworkGetEntityFromNetworkId(vd.netid)    │
│             - owner = NetworkGetEntityOwner(ent)               │
│             - Se owner != vd.driver:                           │
│               vd.driver = owner                               │
│               Logger:warn("vehicle", "Owner drift corrigido")  │
│  [ ] S5.07  Smoke test: forçar troca de owner, verificar       │
│             que vd.driver sincroniza                           │
├─────────────────────────────────────────────────────────────────┤
│  PERF-3: GetPopulationType — filtrar veículos de NPC            │
├─────────────────────────────────────────────────────────────────┤
│  [ ] S5.08  Em onSpawned: verificar netid antes de registrar    │
│  [ ] S5.09  Client-side: ao detectar spawn de veículo,          │
│             verificar GetVehiclePopulationType(veh)            │
│             • 7 = POPTYPE_MISSION (veículo do jogador) → OK    │
│             • outros = NPC → NÃO enviar vSpawned               │
│  [ ] S5.10  Smoke test: veículo de tráfego não cria VD          │
├─────────────────────────────────────────────────────────────────┤
│  PERF-4: SetEntityDistanceCullingRadius — garagem               │
├─────────────────────────────────────────────────────────────────┤
│  [ ] S5.11  Ao spawnar veículo de garagem:                      │
│             - ent = entidade recém-spawned                     │
│             - SetEntityDistanceCullingRadius(ent, 256.0)       │
│             - Garante que o veículo é visível ao aproximar      │
│  [ ] S5.12  Remover após 2s (veículo já está no mundo)          │
├─────────────────────────────────────────────────────────────────┤
│  PERF-5: Batch SQL otimizações                                   │
├─────────────────────────────────────────────────────────────────┤
│  [ ] S5.13  BATCH_MAX aumentar para 200 (servidor de 3000+)     │
│  [ ] S5.14  BATCH_INT manter em 5000ms (equilíbrio)             │
│  [ ] S5.15  No driver:batch(), envolver em BEGIN/COMMIT          │
│             MySQL para atomicidade real                         │
│  [ ] S5.16  Adicionar métricas de batch:                        │
│             - tamanho médio do batch                           │
│             - frequência de flush forçado (atingiu BATCH_MAX)  │
│             - latência do flush                                 │
├─────────────────────────────────────────────────────────────────┤
│  PERF-6: VRAM GC — limpeza de entidades órfãs                   │
├─────────────────────────────────────────────────────────────────┤
│  [ ] S5.17  Loop a cada 5 minutos: varrer S._mem["vd"]          │
│             - Para cada plate: verificar se está em Veh._veh   │
│             - Se não está: é órfão → remover de S._mem          │
│  [ ] S5.18  Loop a cada 5 minutos: varrer Veh._veh              │
│             - Se vd.spawned mas netid inválido (entidade gone): │
│               chamar onDespawned automaticamente               │
│  [ ] S5.19  Smoke test: criar 100 VDs, deletar metade,          │
│             verificar que GC remove corretamente               │
├─────────────────────────────────────────────────────────────────┤
│  PERF-7: Fuel — consumo server-side mais preciso                 │
├─────────────────────────────────────────────────────────────────┤
│  [ ] S5.20  Consumo baseado em rpm + engine_health:             │
│             consumo = rpm * fuel_rate * (eng/1000)             │
│             (motor danificado consome menos, lógica realista)   │
│  [ ] S5.21  Se fuel <= 5.0: emitir EVT_VEH_FUEL_EMPTY          │
│  [ ] S5.22  Se fuel == 0.0: setar State Bag vh_on=false         │
│             forçar desligar motor via bag (client reage)        │
└─────────────────────────────────────────────────────────────────┘
```

### Código canônico — server/instance.lua

```lua
-- server/instance.lua
-- Responsabilidade: gerenciar instâncias via Routing Buckets
-- Depende de: kernel.lua, auth.lua
-- Nativo-chave: SetPlayerRoutingBucket, GetPlayerRoutingBucket

local Instance = {}; Instance.__index = Instance
vHub.Instance  = Instance

Instance._buckets = {}  -- { [bucket_id] = {players, created_at, data} }

function Instance:set(src, bucket_id)
  assert(type(src) == "number" and src > 0, "src inválido")
  assert(type(bucket_id) == "number" and bucket_id >= 0, "bucket_id inválido")

  local prev = GetPlayerRoutingBucket(src)
  SetPlayerRoutingBucket(src, bucket_id)

  -- Registrar no mapa de buckets
  if bucket_id ~= 0 then
    if not self._buckets[bucket_id] then
      self._buckets[bucket_id] = {players={}, created_at=GetGameTimer(), data={}}
    end
    self._buckets[bucket_id].players[src] = true
  end
  if prev ~= 0 and prev ~= bucket_id and self._buckets[prev] then
    self._buckets[prev].players[src] = nil
    -- Limpar bucket vazio
    if not next(self._buckets[prev].players) then
      self._buckets[prev] = nil
    end
  end

  vHub.Kernel:emit(src, "vHub:instanceSet", bucket_id)
  TriggerEvent("vHub:instanceChanged", src, prev, bucket_id)
end

function Instance:get(src)
  return GetPlayerRoutingBucket(src)
end

function Instance:reset(src)
  self:set(src, 0)
end

function Instance:getBucketData(bucket_id)
  return self._buckets[bucket_id]
end

function Instance:getPlayersInBucket(bucket_id)
  local b = self._buckets[bucket_id]
  if not b then return {} end
  local list = {}
  for src in pairs(b.players) do list[#list+1] = src end
  return list
end
```

---

## SPRINT 6 — OBSERVABILIDADE: métricas, health e diagnóstico

**Objetivo**: Ter visibilidade total do estado interno do servidor em produção.  
**Pré-requisito**: Sprint 5 concluído.

```
┌─────────────────────────────────────────────────────────────────┐
│  SPRINT 6 · CHECKLIST                                           │
├─────────────────────────────────────────────────────────────────┤
│  ARQUIVO: server/metrics.lua                                    │
├─────────────────────────────────────────────────────────────────┤
│  [ ] S6.01  Criar vHub.Metrics com contadores:                  │
│             - net_events_total   (por nome de evento)           │
│             - net_events_blocked (por nome de evento)           │
│             - batch_flushes_total                               │
│             - batch_ops_total                                   │
│             - batch_force_flushes (atingiu BATCH_MAX)           │
│             - db_errors_total                                   │
│             - sessions_peak                                     │
│             - sessions_current                                  │
│             - veh_registered_peak                               │
│  [ ] S6.02  Kernel:net incrementa net_events_total e            │
│             net_events_blocked quando rate bloqueia            │
│  [ ] S6.03  State:_flush incrementa batch_flushes_total         │
│             e batch_ops_total com n                             │
│  [ ] S6.04  Auth:connect incrementa sessions_current e          │
│             atualiza sessions_peak                             │
│  [ ] S6.05  Auth:disconnect decrementa sessions_current         │
├─────────────────────────────────────────────────────────────────┤
│  [ ] S6.06  Criar endpoint de health check via net event:        │
│             K:net("vHub:health", handler, {admin=true})         │
│             → retorna snapshot de métricas para admin           │
│  [ ] S6.07  Health report inclui:                               │
│             - uptime em segundos                                │
│             - sessions_current / sessions_peak                  │
│             - batch queue size atual (_batchN)                  │
│             - db_ready status                                   │
│             - veh count (spawned, registered)                   │
│             - instance buckets ativos                           │
│             - taxa de rate-limit (bloqueados/total últimos 60s) │
│  [ ] S6.08  Adicionar comando de servidor (RCON-friendly):       │
│             RegisterCommand("vhub_health", function(src, args)  │
│               if src ~= 0 then ... end -- só console           │
│               local report = vHub.Metrics:snapshot()           │
│               print(json.encode(report, {indent=2}))           │
│             end)                                                │
├─────────────────────────────────────────────────────────────────┤
│  [ ] S6.09  Auto-webhook de health a cada hora:                 │
│             se cfg.webhooks.health existe:                      │
│             enviar relatório de métricas compacto              │
│  [ ] S6.10  Smoke test: /vhub_health no console retorna JSON    │
│             válido sem erros                                    │
└─────────────────────────────────────────────────────────────────┘
```

### Código canônico — server/metrics.lua

```lua
-- server/metrics.lua
-- Responsabilidade: contadores de observabilidade e health check
-- Depende de: kernel.lua, logger.lua

local Metrics = {}; Metrics.__index = Metrics
vHub.Metrics  = Metrics

Metrics._started  = GetGameTimer()
Metrics._counters = {
  net_events_total       = {},
  net_events_blocked     = {},
  batch_flushes_total    = 0,
  batch_ops_total        = 0,
  batch_force_flushes    = 0,
  db_errors_total        = 0,
  sessions_current       = 0,
  sessions_peak          = 0,
  veh_spawned_current    = 0,
  veh_registered_current = 0,
}

function Metrics:inc(counter, key)
  if key then
    if not self._counters[counter] then self._counters[counter] = {} end
    self._counters[counter][key] = (self._counters[counter][key] or 0) + 1
  else
    self._counters[counter] = (self._counters[counter] or 0) + 1
  end
end

function Metrics:set(counter, value)
  self._counters[counter] = value
end

function Metrics:snapshot()
  local uptime_s = math.floor((GetGameTimer() - self._started) / 1000)
  local batchN   = vHub.State and vHub.State._batchN or 0
  local db_ready = vHub.State and vHub.State._ready or false

  local veh_spawned = 0
  local veh_reg     = 0
  if vHub.Vehicle then
    for _, vd in pairs(vHub.Vehicle._veh) do
      veh_reg = veh_reg + 1
      if vd.spawned then veh_spawned = veh_spawned + 1 end
    end
  end

  return {
    uptime_seconds    = uptime_s,
    db_ready          = db_ready,
    sessions_current  = self._counters.sessions_current,
    sessions_peak     = self._counters.sessions_peak,
    batch_queue_size  = batchN,
    batch_flushes     = self._counters.batch_flushes_total,
    batch_ops         = self._counters.batch_ops_total,
    batch_forced      = self._counters.batch_force_flushes,
    db_errors         = self._counters.db_errors_total,
    veh_spawned       = veh_spawned,
    veh_registered    = veh_reg,
    net_events        = self._counters.net_events_total,
    net_blocked       = self._counters.net_events_blocked,
    instances         = vHub.Instance and vHub.tableSize(vHub.Instance._buckets) or 0,
    timestamp         = os.date("%Y-%m-%d %H:%M:%S"),
  }
end

-- Console command
RegisterCommand("vhub_health", function(src)
  if src ~= 0 then return end  -- apenas console do servidor
  local report = Metrics:snapshot()
  print(json.encode(report, {indent = 2}))
end, true)
```

---

## SPRINT 7 — TESTES E VALIDAÇÃO: smoke test matrix completa

**Objetivo**: Checklist de validação end-to-end antes de declarar S+.  
**Pré-requisito**: Sprints 0–6 concluídos.  
**Regra**: Cada teste deve ser executado manualmente com pelo menos 2 jogadores reais (ou bots).  
**Critério de aprovação**: 100% dos testes passam. Zero falhas silenciosas.

```
┌─────────────────────────────────────────────────────────────────┐
│  SPRINT 7 · MATRIZ DE TESTES                                    │
├─────────────────────────────────────────────────────────────────┤
│  MÓDULO: Fundação (shared/)                                     │
├─────────────────────────────────────────────────────────────────┤
│  [ ] T01  vHub.mergeConfig({}) → todos os defaults presentes    │
│  [ ] T02  vHub.validateConfig(cfg_errado) → retorna erros       │
│  [ ] T03  vHub.E.FOO = "x" → lança erro (imutável)             │
│  [ ] T04  vHub.normalizePlate("abc 1") → "ABC 1"               │
│  [ ] T05  vHub.safeUnpack("lixo") → nil sem panic               │
│  [ ] T06  Logger:debug abaixo do nível → nada impresso          │
│  [ ] T07  Logger:error → imprime com formato correto            │
├─────────────────────────────────────────────────────────────────┤
│  MÓDULO: State (server/state.lua)                               │
├─────────────────────────────────────────────────────────────────┤
│  [ ] T08  S:get em chave inexistente → nil                      │
│  [ ] T09  S:set + S:get → valor correto                         │
│  [ ] T10  S:begin → S:set → S:rollback → valor anterior         │
│  [ ] T11  S:begin → S:set → S:commit → SQL enfileirado          │
│  [ ] T12  _flush() chamado 3x simultâneos → sem double-write    │
│  [ ] T13  Validator retorna false → rollback automático         │
│  [ ] T14  _flush() com _ready=false → no-op, sem erro           │
├─────────────────────────────────────────────────────────────────┤
│  MÓDULO: Kernel (server/kernel.lua)                             │
├─────────────────────────────────────────────────────────────────┤
│  [ ] T15  K:net com rate → 9 eventos em 1s → 10° bloqueado      │
│  [ ] T16  Evento bloqueado: cliente NÃO recebe resposta          │
│  [ ] T17  K:net com perm → sem perm → _permFail + no handler    │
│  [ ] T18  K:net com async=false → sem thread extra              │
│  [ ] T19  K:hasPerm com "admin.*" → match qualquer "admin.X"   │
│  [ ] T20  Rate GC a 2min → entradas expiradas removidas         │
├─────────────────────────────────────────────────────────────────┤
│  MÓDULO: Auth (server/auth.lua)                                 │
├─────────────────────────────────────────────────────────────────┤
│  [ ] T21  Jogador conecta → sessão criada, UID correto          │
│  [ ] T22  Mesmo jogador reconecta → mesmo UID (identifier match)│
│  [ ] T23  Jogador banido tenta conectar → DropPlayer            │
│  [ ] T24  Whitelist ativa, jogador sem wl → DropPlayer          │
│  [ ] T25  Login duplicado → sessão anterior dropada             │
│  [ ] T26  Disconnect → S:_flush() forçado, sessão limpa         │
│  [ ] T27  selectCharacter com cid não-owned → false retornado   │
│  [ ] T28  ban + unban → campo ban.active removido               │
│  [ ] T29  _ids() com license+steam → license primeiro na lista  │
├─────────────────────────────────────────────────────────────────┤
│  MÓDULO: Vehicle (server/vehicle.lua)                           │
├─────────────────────────────────────────────────────────────────┤
│  [ ] T30  register com placa inválida → nil retornado + warn    │
│  [ ] T31  register com placa minúscula → normalizada            │
│  [ ] T32  onSpawned → State Bags setados imediatamente          │
│  [ ] T33  onEnter como driver → NetworkSetEntityOwner chamado   │
│  [ ] T34  onLeave motorista → authority transferida para next   │
│  [ ] T35  onStateUpdate de não-driver → ignorado                │
│  [ ] T36  odometer_delta além do max_speed_kmh → clamped        │
│  [ ] T37  fuel = 0 → EVT_VEH_FUEL_EMPTY emitido                 │
│  [ ] T38  onDespawned → last_pos salvo + _save chamado          │
│  [ ] T39  transferKey → _byKey atualizado, evento emitido       │
├─────────────────────────────────────────────────────────────────┤
│  MÓDULO: Security (server/security.lua)                         │
├─────────────────────────────────────────────────────────────────┤
│  [ ] T40  requireAdmin com ACE → passa sem DB                   │
│  [ ] T41  requireAdmin sem ACE, sem perm → _permFail            │
│  [ ] T42  requireTrustedResource resource não-listado → false   │
│  [ ] T43  requireTrustedResource chamada interna → true         │
│  [ ] T44  5 placas inválidas em 60s → DropPlayer               │
│  [ ] T45  isValidSource(0) → false                              │
│  [ ] T46  isValidSource(1024) → false                           │
│  [ ] T47  Ping > max_ping → DropPlayer (exceto ACE admin)       │
├─────────────────────────────────────────────────────────────────┤
│  MÓDULO: Client (client/)                                       │
├─────────────────────────────────────────────────────────────────┤
│  [ ] T48  Spawn → NET_READY enviado → CLI_INIT_DONE recebido    │
│  [ ] T49  Entrar em veículo → NET_V_ENTER com plate/seat certo  │
│  [ ] T50  Sair de veículo → NET_V_LEAVE enviado                  │
│  [ ] T51  State Bag vh_fuel mudado → SetVehicleFuelLevel aplicado│
│  [ ] T52  Loop de report: sem veículo → zero events enviados    │
│  [ ] T53  Loop de report: passageiro → zero events enviados     │
│  [ ] T54  Loop de report: motorista → events a 4hz              │
│  [ ] T55  Veículo de NPC → não gera NET_V_SPAWNED               │
│  [ ] T56  Position nunca enviada ao servidor (verificar via log)│
├─────────────────────────────────────────────────────────────────┤
│  MÓDULO: Instance (server/instance.lua)                         │
├─────────────────────────────────────────────────────────────────┤
│  [ ] T57  set(src, 5) → GetPlayerRoutingBucket(src) == 5        │
│  [ ] T58  Jogador A no bucket 5, B no bucket 0 → não se veem   │
│  [ ] T59  reset(src) → de volta ao bucket 0                     │
│  [ ] T60  Disconnect → reset automático do bucket               │
├─────────────────────────────────────────────────────────────────┤
│  MÓDULO: Metrics (server/metrics.lua)                           │
├─────────────────────────────────────────────────────────────────┤
│  [ ] T61  /vhub_health no console → JSON válido, sem nil        │
│  [ ] T62  sessions_current correto após connect e disconnect    │
│  [ ] T63  batch_flushes_total incrementa a cada flush           │
│  [ ] T64  net_events_blocked incrementa ao rate-limitar         │
├─────────────────────────────────────────────────────────────────┤
│  COMPATIBILIDADE vRP                                            │
├─────────────────────────────────────────────────────────────────┤
│  [ ] T65  Script vRP1 usando vRP.getUserId → funciona           │
│  [ ] T66  Script vRP1 usando vRP.setUData → persiste corretamente│
│  [ ] T67  Script vRP2 usando registerExtension → eventos bound  │
│  [ ] T68  Proxy.getInterface → retorna vRP_compat               │
│  [ ] T69  Tunnel.getInterface → proxy de emit funciona          │
├─────────────────────────────────────────────────────────────────┤
│  CARGA E STRESS                                                 │
├─────────────────────────────────────────────────────────────────┤
│  [ ] T70  50 jogadores conectando simultâneos → zero deadlocks  │
│  [ ] T71  50 jogadores em veículos → State Bags consistentes    │
│  [ ] T72  Resource restart com jogadores ativos → dados salvos  │
│  [ ] T73  DB desconecta e reconecta → batch acumula e flush OK  │
│  [ ] T74  Memória do servidor após 1h → sem memory leak          │
│           (comparar S._mem size antes e depois de disconnects)  │
└─────────────────────────────────────────────────────────────────┘
```

---

## APÊNDICE A — SQL SCHEMA FINAL COMPLETO

```sql
-- ============================================================
-- vHub Schema v2.0
-- Executar uma única vez no banco de dados
-- ============================================================

-- Usuários base
CREATE TABLE IF NOT EXISTS vh_users (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  created_at DATETIME DEFAULT NOW()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Identificadores (license, steam, discord, etc.)
CREATE TABLE IF NOT EXISTS vh_user_ids (
  identifier VARCHAR(100) NOT NULL,
  user_id    INT          NOT NULL,
  PRIMARY KEY (identifier),
  INDEX idx_user_id (user_id),
  CONSTRAINT fk_uid_users FOREIGN KEY (user_id)
    REFERENCES vh_users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Personagens
CREATE TABLE IF NOT EXISTS vh_characters (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  user_id    INT NOT NULL,
  created_at DATETIME DEFAULT NOW(),
  INDEX idx_char_user (user_id),
  CONSTRAINT fk_char_users FOREIGN KEY (user_id)
    REFERENCES vh_users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Dados de usuário (key-value, msgpack)
CREATE TABLE IF NOT EXISTS vh_user_data (
  user_id INT          NOT NULL,
  dkey    VARCHAR(128) NOT NULL,
  dvalue  MEDIUMBLOB,
  PRIMARY KEY (user_id, dkey),
  CONSTRAINT fk_ud_users FOREIGN KEY (user_id)
    REFERENCES vh_users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Dados de personagem (key-value, msgpack)
CREATE TABLE IF NOT EXISTS vh_char_data (
  char_id INT          NOT NULL,
  dkey    VARCHAR(128) NOT NULL,
  dvalue  MEDIUMBLOB,
  PRIMARY KEY (char_id, dkey),
  CONSTRAINT fk_cd_chars FOREIGN KEY (char_id)
    REFERENCES vh_characters(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Dados globais do servidor (key-value, msgpack)
CREATE TABLE IF NOT EXISTS vh_global_data (
  dkey   VARCHAR(128) NOT NULL,
  dvalue MEDIUMBLOB,
  PRIMARY KEY (dkey)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Veículos
CREATE TABLE IF NOT EXISTS vh_vehicles (
  plate   VARCHAR(10)  NOT NULL,
  key_uid VARCHAR(64)  DEFAULT NULL,
  PRIMARY KEY (plate),
  INDEX idx_key_uid (key_uid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Dados de veículo (key-value, msgpack)
CREATE TABLE IF NOT EXISTS vh_vehicle_data (
  plate  VARCHAR(10)  NOT NULL,
  dkey   VARCHAR(128) NOT NULL,
  dvalue MEDIUMBLOB,
  PRIMARY KEY (plate, dkey),
  CONSTRAINT fk_vd_vehicles FOREIGN KEY (plate)
    REFERENCES vh_vehicles(plate) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Índices adicionais para performance em alta carga
CREATE INDEX IF NOT EXISTS idx_ud_dkey ON vh_user_data(dkey);
CREATE INDEX IF NOT EXISTS idx_cd_dkey ON vh_char_data(dkey);
CREATE INDEX IF NOT EXISTS idx_vd_dkey ON vh_vehicle_data(dkey);
```

---

## APÊNDICE B — fxmanifest.lua FINAL

```lua
-- fxmanifest.lua — versão final após todos os sprints
fx_version  'cerulean'
game        'gta5'
lua54       'yes'

author      'vHub Framework'
description 'vHub — Production-grade S+ FiveM RP framework'
version     '2.0.0'

-- ── Compartilhado (server + client) ──────────────────────────
shared_scripts {
  'shared/config.lua',
  'shared/events.lua',
  'shared/utils.lua',
  'shared/logger.lua',
}

-- ── Servidor ──────────────────────────────────────────────────
server_scripts {
  '@oxmysql/lib/MySQL.lua',     -- ou o driver escolhido
  'server/state.lua',
  'server/kernel.lua',
  'server/security.lua',
  'server/notify.lua',
  'server/auth.lua',
  'server/vehicle.lua',
  'server/instance.lua',
  'server/metrics.lua',
  'server/sql.lua',
  'server/compat.lua',
  'server/init.lua',
}

-- ── Cliente ───────────────────────────────────────────────────
client_scripts {
  'client/core.lua',
  'client/vehicle.lua',
  'client/instance.lua',
  'client/hud.lua',
}

-- ── Exports públicos (visíveis por outros resources) ──────────
server_exports {
  'getVHub',
  'getUser',
  'getUID',
  'hasPerm',
  'grantPerm',
  'revokePerm',
  'getVehicle',
  'transferKey',
  'getVehicleByKey',
  'banPlayer',
  'unbanPlayer',
  'getInstance',
  'setInstance',
  'getMetrics',
}

-- ── Dependências ──────────────────────────────────────────────
dependencies {
  '/server:5558',   -- FiveM server mínimo
  '/onesync',       -- OneSync obrigatório para State Bags
}
```

---

## APÊNDICE C — GLOSSÁRIO DE DECISÕES ARQUITETURAIS

### Por que `NetworkSetEntityOwner` em vez de broadcast?
O GTA 5 network model já replica a posição da entidade para todos os clientes quando há um owner definido. Fazer broadcast manual compete com isso, causando jitter. A decisão é delegar ao engine o que o engine já faz melhor.

### Por que msgpack em vez de JSON para VRAM/SQL?
msgpack é binary, ~30% menor que JSON para dados típicos de RP e ~3x mais rápido de serializar. Para 3000 players com salvamento a cada 60s, isso é relevante.

### Por que REPLACE INTO em vez de INSERT ON DUPLICATE KEY UPDATE?
REPLACE INTO deleta e reinsere — é atômico e simples, ao custo de resetar AUTO_INCREMENT. Para dados de key-value sem IDs sequenciais (nosso caso), é a escolha correta.

### Por que batch SQL com flush de 5s e não imediato?
Com 3000 players e centenas de ações por minuto, um execute por operação causaria milhares de queries/minuto. O batch agrupa todas as operações em uma única transação MySQL, reduzindo I/O ~100x.

### Por que State Bags para veículos e não events?
State Bags são replicados automaticamente pelo FiveM para todos os clientes que têm a entidade em range. Usar events manuais causaria o mesmo problema do broadcast de posição: competição com o engine.

### Por que Routing Buckets em vez de instâncias manuais?
Routing Buckets são implementados no nível da rede do FiveM. Jogadores em buckets diferentes são completamente invisíveis um para o outro sem nenhum código adicional. Implementar isso manualmente exigiria filtrar todos os eventos e broadcasts — impraticável.

### Por que assertThread() em vez de silent fail?
Um Citizen.Await fora de thread causa deadlock silencioso — o código para de funcionar sem nenhuma mensagem de erro. Um assert claro com stack trace poupa horas de debug.

### Por que priorizar license: sobre steam:?
A Rockstar Social Club é a identidade principal no FiveM. O `license:` identifier vem do token de autenticação da Rockstar e é o mais difícil de falsificar. O `steam:` pode estar ausente se o jogador não tiver Steam aberto.

---

## CHECKLIST MASTER — ORDEM ABSOLUTA DE EXECUÇÃO

```
FASE 0  — Lei do Projeto ............ Lida, compreendida, assinada ✓
FASE 1  — Estrutura de Arquivos ...... Árvore criada fisicamente   ✓

Sprint 0 · Fundação shared/
  S0.01–S0.05  config.lua ............. [ ]
  S0.06        smoke test config ....... [ ]
  S0.07–S0.09  events.lua .............. [ ]
  S0.10–S0.16  utils.lua ............... [ ]
  S0.17        smoke test utils ........ [ ]
  S0.18–S0.22  logger.lua .............. [ ]
  S0.23        smoke test logger ........ [ ]
  ► GATE: resource inicia com shared/ sem erros

Sprint 1 · Correções críticas
  S1.01–S1.05  _flush guard ............ [ ]
  S1.06–S1.08  _ids prioridade ......... [ ]
  S1.09–S1.12  normalizePlate .......... [ ]
  S1.13–S1.16  notify retry ............ [ ]
  S1.17–S1.19  assertThread ............ [ ]
  S1.20–S1.22  print→Logger ........... [ ]
  S1.23–S1.25  odômetro fix ............ [ ]
  ► GATE: todos os smoke tests do Sprint 1 passam

Sprint 2 · Organização multi-arquivo
  S2.01–S2.05  fxmanifest .............. [ ]
  S2.06–S2.09  notify.lua .............. [ ]
  S2.10–S2.14  state.lua ............... [ ]
  S2.15–S2.20  kernel.lua .............. [ ]
  S2.21–S2.24  security.lua ............ [ ]
  S2.25–S2.30  auth.lua ................ [ ]
  S2.31–S2.35  vehicle.lua ............. [ ]
  S2.36–S2.38  sql.lua ................. [ ]
  S2.39–S2.42  compat.lua .............. [ ]
  S2.43–S2.48  init.lua ................ [ ]
  S2.49–S2.53  validação final ......... [ ]
  ► GATE: 10 jogadores simultâneos, sem erros, dados persistem

Sprint 3 · Client-side
  S3.01–S3.07  core.lua ................ [ ]
  S3.08–S3.19  vehicle.lua client ....... [ ]
  S3.20–S3.22  instance.lua client ...... [ ]
  S3.23–S3.25  hud.lua ................. [ ]
  ► GATE: ciclo completo connect→spawn→veh→disconnect

Sprint 4 · Segurança hardened
  S4.01–S4.03  ACE admin ............... [ ]
  S4.04–S4.06  invoker whitelist ........ [ ]
  S4.07–S4.11  ping kick ............... [ ]
  S4.12–S4.15  payload guard ........... [ ]
  S4.16–S4.18  source validation ........ [ ]
  S4.19–S4.21  plate violation .......... [ ]
  S4.22–S4.24  password hash ........... [ ]
  S4.25–S4.26  rate limits revisados .... [ ]
  ► GATE: pentest básico — nenhum bypass dos guards

Sprint 5 · Performance nativos
  S5.01–S5.04  instance Routing Bucket .. [ ]
  S5.05–S5.07  entity owner health check . [ ]
  S5.08–S5.10  population type filter ... [ ]
  S5.11–S5.12  culling radius ........... [ ]
  S5.13–S5.16  batch otimizações ........ [ ]
  S5.17–S5.19  VRAM GC ................. [ ]
  S5.20–S5.22  fuel preciso ............. [ ]
  ► GATE: 100 jogadores por 30 min sem leak de memória

Sprint 6 · Observabilidade
  S6.01–S6.05  metrics counters ......... [ ]
  S6.06–S6.08  health endpoint .......... [ ]
  S6.09–S6.10  auto webhook report ....... [ ]
  ► GATE: /vhub_health retorna JSON correto em prod

Sprint 7 · Validação final
  T01–T07    Fundação .................. [ ]
  T08–T14    State ..................... [ ]
  T15–T20    Kernel .................... [ ]
  T21–T29    Auth ...................... [ ]
  T30–T39    Vehicle ................... [ ]
  T40–T47    Security .................. [ ]
  T48–T56    Client .................... [ ]
  T57–T60    Instance .................. [ ]
  T61–T64    Metrics ................... [ ]
  T65–T69    Compat vRP ................ [ ]
  T70–T74    Stress/carga .............. [ ]
  ► GATE FINAL: 100% dos testes passam
                zero regressões nos módulos vRP
                zero print() no código (exceto Logger)
                zero string literal de evento (tudo via vHub.E.*)
                zero posição de veículo enviada pelo cliente
                ════════════════════════════════
                       STATUS: S+ AAA ✓
```

---

*Versão do documento: 1.0.0 — gerado para vHub 2.0.0*  
*Não modificar as Leis do Projeto (FASE 0) sem revisão de toda a arquitetura*