# vHub Mirage — Framework FiveM GTARP

Framework server-authoritative para FiveM escrito em Lua 5.4.
**Core FROZEN v1.0 — selado em 2026-05-22. Próxima revisão: 2027-05-22.**

> resmon medido: **0.02ms** (alvo < 0.05ms idle, < 0.20ms sob carga).

---

## O que é

vHub Mirage é um framework FiveM GTARP completo, construído do zero, sem dependência de legado vRP.
O objetivo é entregar uma base estável, previsível e extensível para servidores de médio/grande porte.

Decisões arquiteturais centrais:

- **Servidor é a única fonte de verdade** — cliente trata UI, física e estado efêmero
- **VRAM-first** — toda leitura vai à memória primeiro; SQL é backup, não runtime
- **Batch SQL atômico** — writes agrupados em transações de até 800 ops a cada 3s
- **Compat: none** — shim vRP (`_G.vRP`, `_G.Proxy`, `_G.Tunnel`) removido definitivamente em Frozen v1.0

---

## Estrutura do repositório

```
vhubMirage/
├── config/
│   └── resources.cfg          # Ordem de ensure obrigatória
├── resources/
│   ├── [CORE]/
│   │   ├── vhub/              # Core principal (FROZEN v1.0)
│   │   ├── oxmysql/           # Driver MySQL upstream (não alterar)
│   │   └── vhub_oxmysql/      # Adaptador vHub ↔ oxmysql
│   ├── [SCRIPTS]/
│   │   ├── vhub_groups/       # Permissões e grupos
│   │   ├── vhub_identity/     # Nome, registro, telefone
│   │   ├── vhub_money/        # Carteira e banco
│   │   ├── vhub_survival/     # Fome e sede
│   │   ├── vhub_player_state/ # Spawn, posição, armas, customização
│   │   ├── vhub_inventory/    # Itens, peso, baús, chaves de veículo
│   │   ├── vhub_garage/       # Garagem, concessionária, leilão, aluguel,
│   │   │                      #   impound, IPVA, reparo, clone/transferência
│   │   └── vhub_admin/        # Kick, ban, tp, noclip, give — painel NUI
│   └── [TOOLS]/
│       └── vhub_testrunner/   # Runner de testes server-side
├── tools/
│   ├── limpardadossql.ps1
│   └── fix_vhub_db.ps1
├── metas/
│   ├── manual_dev_vhub.md     # Referência de desenvolvimento (ativa)
│   └── fivem_natives_organizadas_ptbr.md
├── CLAUDE.md                  # Leis e instruções para Claude Code
├── FROZEN_EXEC_LOG.md         # Log de execução do Frozen Plan v1.0
└── README.md
```

---

## Core vHub — arquitetura interna

```
resources/[CORE]/vhub/
├── fxmanifest.lua
├── base.lua                   # Carrega server/init.lua via load()
├── bootstrap.lua              # Driver oxmysql + exports API/Status/Health
├── shared/
│   ├── config.lua             # Cria vHub = {}, mergeConfig, validateConfig
│   ├── events.lua             # vHub.E.* read-only
│   ├── utils.lua              # Helpers puros (formatNumber, dataCopy, clamp...)
│   └── logger.lua             # Único ponto de log — vHub.Logger
├── server/
│   ├── init.lua               # OOP helper, assertThread, loadmod, ordem de carga
│   ├── kernel.lua             # Event bus, rate limit, permissões, K:export
│   ├── state.lua              # VRAM-first, TX com rollback, batch SQL, get/setData
│   ├── sql.lua                # Todos os S:prepare() — único lugar de SQL declarado
│   ├── notify.lua             # Webhooks Discord com retry
│   ├── auth.lua               # Identidade, sessão, personagem, ban
│   ├── vehicle.lua            # Registro, State Bags, odômetro, autoridade de entidade
│   ├── security.lua           # Payload check, ACE, invoker whitelist
│   ├── boot.lua               # vHub:init(), net events, autosave, lifecycle
│   └── exports.lua            # Cross-resource exports com _invoker_allowed()
├── client/
│   ├── bootstrap.lua          # Ready único, initDone, charSelected, State Bags locais
│   └── vehicle.lua            # Report de estado 4Hz adaptativo
└── sql/
    └── schema.sql             # Schema idempotente, aplicado a cada boot
```

### Ordem de carga (server/init.lua — imutável)

```
kernel → state → sql → notify → auth → vehicle → security → boot → exports
```

---

## Persistência VRAM-first

```
Leitura:   VRAM hit → retorna direto (sem DB)
           VRAM miss → query DB → armazena em VRAM → retorna

Escrita:   atualiza VRAM → enfileira no batch → invalida VRAM*
           (*hot keys: ban.active, whitelist, permissions ficam em VRAM)

Flush:     automático a cada 3s OU ao atingir 800 ops
           emergencial em onResourceStop (chunked, yield a cada 50)
```

Transações com rollback:

```lua
local tx = vHub.State:begin()
vHub.setUData(uid, "saldo", novo_saldo, tx)
local ok, err = vHub.State:commit(tx)   -- rollback automático se validator falhar
if not ok then ... end
```

---

## Entidades e APIs públicas

### Dados KV

```lua
-- Requer Citizen.CreateThread no chamador
vHub.getUData(user_id, "key")           → value
vHub.setUData(user_id, "key", value, tx?)
vHub.getCData(char_id, "key")           → value
vHub.setCData(char_id, "key", value, tx?)
vHub.getVData(plate,   "key")           → value
vHub.setVData(plate,   "key", value, tx?)
vHub.getGData("key")                    → value
vHub.setGData("key", value, tx?)
```

### Exports cross-resource

| Export | Proteção | Descrição |
|--------|----------|-----------|
| `exports.vhub:getVHub()` | pública | Namespace `vHub` completo |
| `exports.vhub:getUser(src)` | pública | Objeto `User` da sessão |
| `exports.vhub:getUID(src)` | pública | `user_id` do source |
| `exports.vhub:hasPerm(uid, perm)` | pública | Verifica permissão |
| `exports.vhub:grantPerm(uid, perm)` | `_invoker_allowed()` | Concede permissão |
| `exports.vhub:getVehicle(plate)` | pública | `VehicleData` da placa |
| `exports.vhub:transferKey(plate, key)` | `_invoker_allowed()` | Transfere chave de veículo |
| `exports.vhub:banPlayer(uid, r, by)` | `_invoker_allowed()` | Bane por uid |
| `exports.vhub:unbanPlayer(uid)` | `_invoker_allowed()` | Remove ban |
| `exports.vhub:Status()` | pública | Snapshot do runtime |

`_invoker_allowed()` verifica `vHub.cfg.trusted_resources`. Se a lista estiver vazia, todos os resources são aceitos.

### Eventos server-side (TriggerEvent local)

| Evento | Payload | Disparado em |
|--------|---------|--------------|
| `vHub:playerJoin` | `user` | Auth:connect concluído |
| `vHub:playerLeave` | `user, reason` | Auth:disconnect |
| `vHub:playerSpawn` | `user, first_spawn` | Após initDone |
| `vHub:playerDeath` | `user` | Cliente envia vHub:died |
| `vHub:characterLoad` | `user` | Seleção/criação de personagem |
| `vHub:vehicleLoaded` | `vd` | Veh:register |
| `vHub:vehicleSpawned` | `vd` | Cliente envia vHub:vSpawned |
| `vHub:vehicleDespawned` | `vd` | Cliente envia vHub:vDespawned |
| `vHub:vehicleEnter` | `vd, src, seat` | Cliente envia vHub:vEnter |
| `vHub:vehicleLeave` | `vd, src, seat` | Cliente envia vHub:vLeave |
| `vHub:vehicleKeyTransferred` | `vd, new_key` | Veh:transferKey |
| `vHub:vehicleFuelEmpty` | `vd, src` | Combustível chegou a zero |

### State Bags de veículo (Entity.state — servidor escreve, cliente lê)

| Bag | Tipo | Delta mínimo para write |
|-----|------|------------------------|
| `vh_fuel` | number (0–100) | 0.5 L |
| `vh_eng` | number (0–1000) | 5.0 HP |
| `vh_body` | number (0–1000) | 5.0 HP |
| `vh_odo` | number (km) | 0.05 km |
| `vh_tune` | table | sempre |
| `vh_on` | boolean | sempre |

---

## Segurança

- **Payload size check** em todo `K:net` (padrão: 8192 bytes)
- **Rate limit O(1) sliding window** em todos os net events (ex: `vHub:vState` — 8 por 1s; `vHub:ready` — 5 por 15s)
- **Silent block** — cliente nunca sabe que foi bloqueado por rate limit
- **Permission guard** — `K:net` com `opts.perm` verifica antes do handler
- **`_invoker_allowed()`** em exports sensíveis — whitelist por resource
- **`vHub.E` read-only** — metatable protege constantes de eventos contra escrita
- **Type-safe ban** — `ban.reason` e `ban.by` são sempre strings
- **Guard `src <= 0`** — rejeita eventos do servidor ou sources inválidos
- **Guard de double-connect** — `Auth._sessions` impede sessão duplicada

---

## Performance

| Métrica | Alvo | Medido |
|---------|------|--------|
| Resmon server idle | < 0.05 ms | **0.02 ms** ✅ |
| Resmon server tick (100 sessões) | < 0.20 ms | — (T1–T5 pendem runtime) |
| Resmon client idle | < 0.10 ms | — |
| Stall autosave (200 sessões) | < 5 ms | — |
| LOC core | ≤ 2.556 | **2.432** ✅ |

**Estratégias ativas:**
- Batch SQL: até 800 ops por transação (flush a cada 3s)
- VRAM-first elimina a maioria das queries de leitura
- `uidByIdsIn(n)`: login de N identifiers em 1 round-trip (era N round-trips)
- Adaptive vehicle report: 0.5Hz parado → 1Hz idle → 4Hz dirigindo
- State Bag delta thresholds: ≥ 8× menos writes/s
- GC `_byNet` a cada 5min; GC `_rate` em playerDropped

---

## Schema SQL

8 tabelas, schema idempotente aplicado a cada boot em `bootstrap.lua`:

| Tabela | PK | Descrição |
|--------|----|-----------|
| `vh_users` | `id INT UNSIGNED` | Conta do jogador (entidade-pai) |
| `vh_user_ids` | `identifier VARCHAR(64)` | Identifiers FiveM mapeados ao user_id |
| `vh_characters` | `id INT UNSIGNED` | Personagens por usuário |
| `vh_user_data` | `(user_id, dkey)` | KV de usuário — msgpack BLOB |
| `vh_char_data` | `(char_id, dkey)` | KV de personagem — msgpack BLOB |
| `vh_global_data` | `dkey` | KV global do servidor — msgpack BLOB |
| `vh_vehicles` | `plate VARCHAR(10)` | Registro físico de veículo |
| `vh_vehicle_data` | `(plate, dkey)` | KV de veículo — msgpack BLOB |

Todas as tabelas dependentes têm FK com `ON DELETE CASCADE ON UPDATE CASCADE`.

> **Schemas externos com FK ao core DEVEM usar `INT UNSIGNED`** para `user_id` e `char_id`.
> Tipo divergente (`INT` signed) causa `errno 150`.

---

## Como criar um novo módulo

Todo novo recurso vai em `resources/[SCRIPTS]/vhub_*`. Nunca em `[CORE]/vhub`.

```lua
-- meu_script/server/init.lua
local M = {}

AddEventHandler("vHub:characterLoad", function(user)
  -- user.id    = user_id
  -- user.char_id = char_id
  -- user.source  = source FiveM
end)

AddEventHandler("vHub:playerLeave", function(user)
  -- cleanup
end)
```

Regras do `manual_dev_vhub.md`:
- Schema próprio via `LoadResourceFile('sql/schema.sql')` em `onResourceStart`
- FK ao core: `INT UNSIGNED` obrigatório
- SQL via `exports.oxmysql:*` diretamente (não via `vHub.State`)
- Colunas de valor: `BLOB` + msgpack ou tipo nativo SQL conforme o dado

---

## Requisitos

| Dependência | Versão mínima | Notas |
|-------------|--------------|-------|
| FiveM / txAdmin | artifact recente | `lua54 yes` obrigatório |
| oxmysql | 2.x | `multipleStatements=true` na connection string |
| MariaDB / MySQL | 10.3 + / 8.0+ | InnoDB, utf8mb4 |

```
# config/resources.cfg — ordem obrigatória
ensure spawnmanager
ensure oxmysql
ensure vhub
ensure vhub_groups
ensure vhub_identity
ensure vhub_money
ensure vhub_survival
ensure vhub_player_state
ensure vhub_inventory
ensure vhub_garage
ensure vhub_admin
```

---

## Desenvolvimento assistido por IA (Claude Code)

O projeto usa Claude Code com agentes especializados em `.claude/agents/`:

| Agente | Quando invocar |
|--------|----------------|
| `vhub_arquiteto` | Novo módulo, mudança estrutural, dúvida de ownership |
| `vhub_guardiao_seguranca` | Auth, ban, payload, spawn, permissão |
| `vhub_guardiao_performance` | Thread, loop, batch SQL, flush, serialização |
| `vhub_guardiao_contrato` | API pública, exports, schema, eventos |
| `vhub_guardiao_revisao` | Gate final antes de qualquer commit relevante |

Instruções completas em `CLAUDE.md` e `.claude/contexto.md`.

---

## Estado de congelamento

```
╔═════════════════════════════════════════════════════════╗
║ vHub Mirage — CORE FROZEN v1.0                          ║
║ Data      : 2026-05-22                                  ║
║ Revisão   : 2027-05-22                                  ║
║ Compat vRP: none                                        ║
║ LOC core  : 2.432 (de 2.813 — -381 líquido)            ║
║ Resmon    : 0.02ms idle (alvo: < 0.05ms)               ║
╚═════════════════════════════════════════════════════════╝
```

Qualquer alteração em `resources/[CORE]/vhub/**` exige:
1. Justificativa por escrito (incidente, requisito legal, bug crítico)
2. Aprovação de `vhub_arquiteto` + `vhub_guardiao_revisao`
3. Bump de versão para `core-frozen-v2.0`
