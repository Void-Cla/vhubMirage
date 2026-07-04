# 04 — Análise Profunda: `vhub_conce` + `vhub_custom`

> **Task ID:** 4 · **Agent:** Conce+Custom Analyzer · **Escopo:** 11 arquivos do `vhub_conce` + 26 arquivos do `vhub_custom` + 4 arquivos de checagem cruzada (vhub_garage/dealership.lua, vhub_garage/sql/schema.sql, vhub_vehcontrol/server/exports.lua, vhub_vehcontrol/server/skill.lua, manual_dev_vhub.md).
>
> **Comparação ZIP × GitHub:** `diff -rq` de `workspace/SCRIPTS/vhub_conce/` vs `workspace/vhubMirage/resources/[SCRIPTS]/vhub_conce/` e idem `vhub_custom/` → **zero diferenças**. ZIP e GitHub são idênticos byte-a-byte. Tudo abaixo descreve o estado atual único.

---

## 1. Visão Geral

### 1.1 `vhub_conce` — Autoridade de identidade e concessão

`fxmanifest.lua` declara a responsabilidade ÚNICA: "identidade do veículo — relação CHAVE↔PLACA↔DONO, concessionária (compra/test-drive/estoque/placa única), emissão/clone/empréstimo/revogação de chave, cron 24h e status/IPVA. Não renderiza, não guarda físico (CORE) nem dinheiro (vhub_money)."

| Papel | Dono | Observação |
|---|---|---|
| Identidade canônica do veículo (model/vtype/category/preço) | `shared/catalog.lua` (`VHubConce.catalog`) | 33 entradas (carros, motos, vans, barcos, aviões, helis); 7 delas têm bloco `p1` (engine de skill). |
| Placa única | `Core:newPlate()` + `SQL:plateExists()` | Aleatória `LLL DDDD` (60 tentativas) ou custom (taxa `taxa_placa_custom`). |
| Chave-mãe (owner) + clones/shared/rental | `vhub_vehicles` + `vhub_vehicle_keys` | `transferOwnerTx` atômico em 1 transação SQL (L-12). |
| Estado físico por placa (PRONTUÁRIO) | `vhub_vehicle_state` | DDL própria no `vstate.lua:ensureSchema()` — **sem FK**, substituto do CASCADE. |
| Espelho `vh_vehicles` (CORE) | `INSERT IGNORE` em `SQL:createVehicle` e `backfillMirror()` | Pré-requisito da FK de `vh_vehicle_data` (cadeia legada inerte). |
| Concessionária (transações) | `VHubConce.buy/sellToShop/testDrive` | `dealership.lua` orquestra catálogo+estoque+placa+money+chave+registro. |
| Cron 24h (posse temporária) | `Core:returnExpiredHoldings()` | Thread horária (`cron_interval_ms = 3600*1000`); revoga + tira chave-item + volta p/ garagem. |
| Zonas da concessionária | `cfg.concessionarias` (5 lojas) | Dono da config de localização desde decisão #25. |

**Dependências declaradas:** `vhub`, `vhub_inventory`, `vhub_money`, `oxmysql`.

### 1.2 `vhub_custom` — Consumidor do PRONTUÁRIO (3 domínios)

`PLANO.md` (v1.0.0) declara: *"peça ao dono, nunca escreva no que não é seu."* O `vhub_custom` é **CONSUMIDOR** do PRONTUÁRIO (`vhub_vehicle_state`, dono = `vhub_conce`). Ele **não ganha ownership de nenhum dado existente**.

UM resource, três sub-domínios, todos os arquivos no `fxmanifest.lua` (L-15):

| Domínio | Server | Client | Web | Responsabilidade | `source` no `saveVehicleState` |
|---|---|---|---|---|---|
| **bennys** (estética pura) | `server/bennys.lua` | `client/bennys.lua` + `client/camera.lua` | `web/bennys.js` + `web/bennys.css` + parte de `web/index.html`/`style.css` | Cor primária/secundária/perolada/roda, neon, fumaça, xenon, window_tint, livery, plate_index, wheel_type, mods visuais (0-10, 20, 22-49). **Rejeita** performance (11,12,13,15,16,18). | `'cosmetic'` |
| **mec** (reparo + reboque) | `server/mec.lua` | `client/mec.lua` | `web/mec.js` + `web/mec.css` | Reparo PARCIAL (pneu/motor/lataria) — produto distinto; reboque de veículo preso/atolado (domínio NOVO, persiste posição via `conce:updatePosition`). | `'repair'` |
| **oficina** (performance/tuning) | `server/oficina.lua` | `client/oficina.lua` | `web/oficina.js` + parte de `style.css` | Stages nativos (11 motor, 12 freio, 13 câmbio, 15 suspensão, 16 blindagem, 18 turbo) dentro de cap por classe GTA; calibração 5-eixos (delega persistência ao `vhub_vehcontrol`); instalação de kit nitro (cobra, mas quem escreve o estado é o `vhub_nitro`). | `'tune'` |

**Dependências declaradas:** `vhub_conce`, `vhub_money`. Não declara `vhub_vehcontrol` nem `vhub_nitro` — degradação graciosa por `pcall`/`GetResourceState`.

### 1.3 Concessionária no `vhub_conce` vs concessionária no `vhub_garage`

Existem **dois** `server/dealership.lua` no ecossistema:

| Resource | Arquivo | Papel |
|---|---|---|
| `vhub_conce/server/dealership.lua` (140 linhas) | `VHubConce.buy(src, model, placa_custom, conc)`, `VHubConce.sellToShop(src, plate)`, `VHubConce.testDrive(src, model, conc)` | **Autoridade da transação**: catálogo + estoque + placa única + money + chave-item + registro. Retorna `{ ok, msg, plate?, total? }`. |
| `vhub_garage/server/dealership.lua` (63 linhas) | `RegisterNetEvent(E.ACT_BUY/ACT_SELL_SHOP/ACT_TESTDRIVE)` | **Delegator fino**: resolve a concessionária (`Core:resolveConc(conc_id)`), chama `exports.vhub_conce:buy/sellToShop/testDrive`, fala com a NUI via `OPEN_UI`. |

**Não há conflito de dono**: o garage é apenas o ponto de entrada do NUI/evento de rede; o conce é quem executa. Decisão #25 do `PLANO.md` garante que a config de localização (zonas) também mora no conce, e o garage faz `PULL` no boot via `exports.vhub_conce:getZones` (ver `§8.3`).

### 1.4 Diferença entre bennys / mec / oficina

| Critério | bennys (estética) | mec (reparo+reboque) | oficina (tuning) |
|---|---|---|---|
| Toca em `customization.mods`? | Sim (índices 0-10, 20, 22-49) | Não | Sim (índices 11, 12, 13, 15, 16) + campo `turbo` |
| Toca em `customization.colours/neons/xenon/...`? | Sim (todas as chaves cosméticas) | Não | Não |
| Toca em `engine_health`/`body_health`? | Não | Sim (somente eleva via `source='repair'`) | Não |
| Toca em `damage`? | Não | Sim (limpa pneus/portas/etc. via `source='repair'`) | Não |
| Toca em `customization.handling` (alloc 5-eixos)? | Não | Não | Não diretamente — delega via `vhub_vehcontrol:recalibrate` (source=`'handling'` escrito pelo vehcontrol) |
| Toca em `customization.nitro`? | Não | Não | Não diretamente — delega via `exports.vhub_nitro:installKit` |
| Custo server-side? | Sim (`CFG.prices.cor_*`, `neon`, `xenon`, ...) | Sim (`pneu`, `motor_parcial`, `lataria_parcial`) | Sim (`engine_stage[1..3]`, ..., `turbo`) + R$ 5.000 kit nitro + R$ 2.500 calibração (em `vhub_vehcontrol`) |
| Persistência direta? | `exports.vhub_conce:saveVehicleState(p, {customization=patch}, 'cosmetic')` | `saveVehicleState(p, patch, 'repair')` | `saveVehicleState(p, {customization={mods=..., turbo=...}}, 'tune')` |
| Câmera orbital? | Sim (`client/camera.lua` — `Cam.start/orbit/zoom/focus`) | Não (card HUD compacto) | Não (3 colunas: nav / cards de stage / ficha) |
| Cap por tier? | Não (sem tiers cosméticos) | Não | Sim — `stage_cap_by_class[classe_gta]` (0..3); fallback `stage_cap_default=1` |

---

## 2. SQL Schema (DETAILED)

### 2.1 Tabelas **criadas** pelo `vhub_conce`

#### `vhub_vehicle_state` (PRONTUÁRIO) — criada em `server/vstate.lua:ensureSchema()` no boot do conce

```sql
CREATE TABLE IF NOT EXISTS vhub_vehicle_state (
  plate         VARCHAR(12)  NOT NULL PRIMARY KEY,
  fuel          FLOAT        NOT NULL DEFAULT 100,
  engine_health FLOAT        NOT NULL DEFAULT 1000,
  body_health   FLOAT        NOT NULL DEFAULT 1000,
  odometer_km   DOUBLE       NOT NULL DEFAULT 0,
  customization MEDIUMTEXT   NULL,
  damage        TEXT         NULL,
  damage_log    MEDIUMTEXT   NULL,
  updated_at    INT          NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
```

**Sem FK** (substituída por guarda `reconcileOrphans()` que deleta órfãos pós-DDL do garage). Collation é auditada no boot — se estiver `general_ci` (instalações antigas), converte para `utf8mb4_unicode_ci` em 1x (`ALTER TABLE ... CONVERT TO CHARACTER SET`).

| Coluna | Tipo | Semântica |
|---|---|---|
| `plate` | `VARCHAR(12) PK` | Placa normalizada (upper, trim, 2-8 chars) |
| `fuel` | `FLOAT DEFAULT 100` | 0.0..100.0 — monotônico não-crescente em `telemetry`; `repair`/`store`/`pump` podem elevar |
| `engine_health` | `FLOAT DEFAULT 1000` | -4000..1000 (GTA range) |
| `body_health` | `FLOAT DEFAULT 1000` | 0..1000 |
| `odometer_km` | `DOUBLE DEFAULT 0` | Acumulador; `odometer_add` (delta 0..2 km) somado por snapshot |
| `customization` | `MEDIUMTEXT` | JSON ≤ 8 KB; chaves whitelisted em `CUST_KEYS` |
| `damage` | `TEXT` | JSON ≤ 2 KB; `{doors, windows, tyres, tyres_rim}` |
| `damage_log` | `MEDIUMTEXT` | JSON ≤ 16 KB; append-only FIFO cap 30 entradas |
| `updated_at` | `INT DEFAULT 0` | Unix timestamp |

**Defaults = estado de fábrica** (correto p/ veículo novo). Fontes de telemetria enviam snapshot COMPLETO — row-miss nunca ressuscita default em veículo usado.

### 2.2 Tabelas **usadas** (DDL mora no `vhub_garage/sql/schema.sql` até a "FASE 6")

O comentário em `server/sql.lua:5` é explícito: *"O schema (DDL) ainda é aplicado pelo vhub_garage até a FASE 6; aqui é só DML."*

#### `vhub_vehicles` (mestre — uma linha por placa)

```sql
CREATE TABLE IF NOT EXISTS `vhub_vehicles` (
  `plate`             VARCHAR(10)  NOT NULL,
  `model`             VARCHAR(64)  NOT NULL,
  `vtype`             ENUM('car','bike','plane','heli','boat','truck','trailer') NOT NULL DEFAULT 'car',
  `category`          VARCHAR(32)  NOT NULL DEFAULT 'sedan',
  `char_id`           INT UNSIGNED      DEFAULT NULL,
  `status`            ENUM('garage','out','impound','auction','rental','sold') NOT NULL DEFAULT 'garage',
  `customization`     LONGTEXT          DEFAULT NULL,   -- DEPRECATED pós-PRONTUÁRIO; vstate.lua nunca lê
  `locked`            TINYINT(1)        NOT NULL DEFAULT 0,
  `position`          TEXT              DEFAULT NULL,
  `ipva_paid_until`   BIGINT            DEFAULT NULL,
  `rented_until`      BIGINT            DEFAULT NULL,
  `purchase_price`    INT UNSIGNED      DEFAULT 0,
  `purchase_at`       BIGINT            DEFAULT NULL,
  `last_seen_at`      BIGINT            DEFAULT NULL,
  `created_at`        BIGINT            NOT NULL,
  `updated_at`        BIGINT            NOT NULL,
  PRIMARY KEY (`plate`),
  KEY `idx_char_id` (`char_id`), KEY `idx_status` (`status`),
  KEY `idx_vtype` (`vtype`),    KEY `idx_rented` (`rented_until`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

#### `vhub_vehicle_keys` (autorização lógica)

```sql
CREATE TABLE IF NOT EXISTS `vhub_vehicle_keys` (
  `id`         INT UNSIGNED    NOT NULL AUTO_INCREMENT,
  `plate`      VARCHAR(10)     NOT NULL,
  `char_id`    INT UNSIGNED    NOT NULL,
  `kind`       ENUM('owner','shared','clone','rental') NOT NULL DEFAULT 'shared',
  `granted_by` INT UNSIGNED    DEFAULT NULL,
  `expires_at` BIGINT          DEFAULT NULL,
  `created_at` BIGINT          NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_plate_char_kind` (`plate`, `char_id`, `kind`),
  KEY `idx_char_id` (`char_id`), KEY `idx_plate` (`plate`), KEY `idx_expires` (`expires_at`),
  CONSTRAINT `fk_keys_plate` FOREIGN KEY (`plate`) REFERENCES `vhub_vehicles`(`plate`)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

#### `vhub_dealership_stock`

```sql
CREATE TABLE IF NOT EXISTS `vhub_dealership_stock` (
  `model`         VARCHAR(64)  NOT NULL,
  `qty`           INT          NOT NULL DEFAULT -1,   -- -1 = ilimitado
  `custom_price`  INT UNSIGNED DEFAULT NULL,
  `updated_at`    BIGINT       NOT NULL,
  PRIMARY KEY (`model`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

#### `vhub_vehicle_log` (auditoria append-only)

```sql
CREATE TABLE IF NOT EXISTS `vhub_vehicle_log` (
  `id`         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `plate`      VARCHAR(10)     NOT NULL,
  `action`     VARCHAR(32)     NOT NULL,
  `actor_id`   INT UNSIGNED    DEFAULT NULL,
  `payload`    TEXT            DEFAULT NULL,
  `created_at` BIGINT          NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_plate` (`plate`), KEY `idx_action` (`action`),
  KEY `idx_actor` (`actor_id`), KEY `idx_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

### 2.3 Espelho `vh_vehicles` (CORE FROZEN — apenas `plate` PK)

`SQL:createVehicle` e `SQL:backfillMirror` fazem `INSERT IGNORE INTO vh_vehicles (plate) VALUES (?)` — pré-requisito da FK de `vh_vehicle_data` no CORE. A cadeia física legada do CORE é **inerte** desde o sprint PRONTUÁRIO; o conce mantém o espelho só por compatibilidade.

### 2.4 Tabelas que o `vhub_custom` toca

**Zero SQL direto**. Todo acesso é via `exports.vhub_conce:*` (TRUSTED). As tabelas subjacentes acessadas pelo conce em nome do custom são:

| Tabela | Caminho |
|---|---|
| `vhub_vehicle_state` | `saveVehicleState` (UPSERT com merge de customization), `getVehicleState` (SELECT) |
| `vhub_vehicles` | âncora fail-closed em `saveVehicleState` (SELECT status); `getVehicle` (para reboque checar `status=='out'`); `updatePosition` (UPDATE) |
| `vhub_vehicle_log` | Apenas indiretamente — o conce não loga por padrão em `saveVehicleState`; o custom tem `Core.log()` próprio (print, não SQL) |

---

## 3. Exports (Server & Client)

### 3.1 `vhub_conce` — exports server (todos com gate `_invoker_allowed`)

Lista TRUSTED explícita em `server/exports.lua:10-22`:
```
vhub, vhub_garage, vhub_ferinha, vhub_admin, vhub_inventory, vhub_vehcontrol,
vhub_legacyfuel, vhub_testrunner, vhub_custom, vhub_nitro, vhub_vrcs
```

| Export | Assinatura | Descrição | Quem chama |
|---|---|---|---|
| `canOperate(src, plate)` | `(int, str) → bool` | Pode operar a placa? (chave-item + dono OU `hasValidKey`) | `vhub_custom` (todos os 3 domínios), `vhub_vehcontrol` |
| `isOwner(src, plate)` | `(int, str) → bool` | É dono real? | garage, ferinha |
| `transferOwner(plate, new_cid)` | `(str, int) → bool` | Troca dono atômica (char_id + chave 'owner') | ferinha, garage |
| `plateExists(plate)` | `(str) → bool` | Existe linha em `vhub_vehicles`? | internos |
| `getVehicle(plate)` | `(str) → row\|nil` | Linha de `vhub_vehicles` | `vhub_custom` (mec reboque), `vhub_vehcontrol` (`p1ByPlate`) |
| `listByOwner(char_id)` | `(int) → row[]` | Veículos do char_id | garage |
| `listByStatus(status)` | `(str) → row[]` | Veículos no status | garage |
| `createVehicle(row)` | `(table) → bool` | Cria registro de negócio + espelho `vh_vehicles` + `VState:seed` | garage (em nome do conce? — na verdade o conce é quem chama em `dealership.lua`) |
| `updateStatus(plate, status)` | `(str, str) → exec` | Atualiza status | garage |
| `updatePosition(plate, posJson)` | `(str, str) → exec` | Atualiza posição (JSON string) | `vhub_custom` (mec reboque, via `mecTowDone`) |
| `updateCustomization(plate, cj, locked)` | `(str, str, bool) → bool` | **DEPRECATED** — só atualiza `locked`; customization vai ao VState | legado |
| `updateIpva(plate, until_ts)` | `(str, int) → exec` | IPVA | garage/ipva |
| `updateRental(plate, until_ts)` | `(str, int) → exec` | Aluguel | garage/rental |
| `deleteVehicle(plate)` | `(str) → exec` | Deleta prontuário + espelho + negócio | garage |
| `grantKey(plate, cid, kind, by, exp)` | `(str, int, str, int, int?) → exec` | Concede chave lógica | garage |
| `revokeKey(plate, cid, kind?)` | `(str, int, str?) → exec` | Revoga (kind=nil revoga tudo não-owner) | garage |
| `hasValidKey(plate, cid)` | `(str, int) → bool` | Tem chave não-expirada? | internos |
| `listKeys(plate)` | `(str) → row[]` | Lista chaves da placa | admin |
| `listKeysOfChar(char_id)` | `(int) → row[]` | Lista chaves do char | garage |
| `purgeExpiredKeys()` | `() → exec` | Limpa chaves vencidas | cron |
| `backfillMirror()` | `() → exec` | `INSERT IGNORE` espelho vh_vehicles | garage pós-DDL |
| `backfillOwnerKeys()` | `() → exec` | Garante 'owner' para todo dono | garage pós-DDL |
| **`getVehicleState(plate)`** | `(str) → table\|nil` | **PRONTUÁRIO** — estado físico (fuel/health/odômetro/customization/damage/damage_log). NUNCA nil para placa registrada (devolve factory se nunca persistiu). | `vhub_custom` (todos), `vhub_vehcontrol`, `vhub_nitro`, `vhub_vrcs` |
| **`saveVehicleState(plate, patch, source)`** | `(str, table, str) → bool` | Aplica patch parcial validado/clampado/sanitizado. `source` ∈ {`telemetry`,`store`,`pump`,`seed`,`repair`,`cosmetic`,`tune`,`handling`,`nitro`,`system`}. | `vhub_custom` (`cosmetic`/`tune`/`repair`), `vhub_vehcontrol` (`handling`), `vhub_nitro` (`nitro`), `vhub_legacyfuel` (`pump`), `vhub_vehcontrol` telemetria (`telemetry`) |
| `repairVehicleState(plate)` | `(str) → bool` | Reparo TRUSTED — único caminho que ELEVA health + limpa damage (`source='repair'`) | garage (`maintenance.lua`), `vhub_custom` (mec reparo PARCIAL chama `saveVehicleState` direto, NÃO `repairVehicleState`) |
| `getVehicleDossier(plate)` | `(str) → table\|nil` | Dossiê (identidade + físico) p/ metadata da chave-item e admin | inventory, admin |
| `backfillVehicleState()` | `() → bool` | Backfill 1x da customization legada | garage pós-DDL |
| `reconcileVehicleState()` | `() → bool` | Remove órfãos (`plate NOT IN vhub_vehicles`) | garage pós-DDL |
| `stockGet(model)` | `(str) → row\|nil` | Estoque | `dealership.lua` |
| `stockSet(model, qty, price)` | `(str, int, int?) → exec` | Define estoque | admin |
| `stockDecrement(model)` | `(str) → exec` | Decrementa se `qty > 0` | `dealership.lua` |
| `getCatalog()` | `() → table` | Catálogo canônico (`VHubConce.catalog`) | `vhub_garage` (cache no boot), `vhub_custom` (`buildCatalogIndex`), `vhub_vehcontrol` (`buildIndex`) |
| `buy(src, model, placa, conc)` | `(int, str, str?, table) → {ok, msg, plate?, model?, total?}` | Compra veículo | garage `dealership.lua` |
| `sellToShop(src, plate)` | `(int, str) → {ok, msg, valor?}` | Vende para a loja (60% do preço) | garage `dealership.lua` |
| `testDrive(src, model, conc)` | `(int, str, table) → {ok, msg?, model?, spawn?, seg?, raio?}` | Autoriza+cobra test drive | garage `dealership.lua` |
| `getZones()` | `() → table[]` | Zonas achatadas (`{id,label,x,y,z,raio,tipos,blip,test_spawn={x,y,z,h}}`) | garage (PULL no boot) |

**Cliente**: `vhub_conce` não tem scripts de cliente (fxmanifest.lua só declara `shared_scripts` + `server_scripts`).

### 3.2 `vhub_custom` — exports

**Zero exports server.** O `PLANO.md` previa um `server/exports.lua` com API read-only mínima (getTier preview), mas **este arquivo não existe** no `fxmanifest.lua` nem no disco. Toda comunicação é via `RegisterNetEvent` + `TriggerServerEvent`/`TriggerClientEvent`.

**Cliente**: nenhum `exports()` registrado. Tudo via globais `VHubCustom.*` (`openBennys`, `openMec`, `openOficina`, `applyCosmetic`, `previewTune`, `Cam.*`, `notify`, etc.).

### 3.3 Telemetria — não há export dedicado

O `vhub_conce` não expõe `applyMod`/`removeMod`/`applyUpgrade`. Toda customização (cosmética, tuning, repair) entra pelo **único** canal `saveVehicleState(plate, patch, source)`. O `source` é a chave de governança:

| `source` | Gates aplicados pelo VState | Writers |
|---|---|---|
| `telemetry` | Rejeitado se `status ~= 'out'` (anti race store×telemetry L-13); `engine_health`/`body_health` MONOTÔNICO não-crescente (anti repair-hack); append em `damage_log` se delta ≥ 150 pts | `vhub_vehcontrol` (telemetria física) |
| `store` | Caminho trusted — pode elevar health, escreve tudo | garage (STORE ao guardar) |
| `pump` | Trusted — combustível | `vhub_legacyfuel` |
| `seed` | Apenas cria linha de fábrica com customization inicial | `SQL:createVehicle` → `VState:seed` |
| `repair` | Trusted — ELEVA health, limpa damage, append em `damage_log` | garage (`maintenance.lua`), `vhub_custom` (mec parcial via `saveVehicleState` direto, NÃO `repairVehicleState`) |
| `cosmetic` | Isola patch a `customization` apenas (não toca health/fuel) | `vhub_custom` (bennys) |
| `tune` | Idem `cosmetic` | `vhub_custom` (oficina) |
| `handling` | Idem — `customization.handling` = alloc 5-eixos do engine de skill | `vhub_vehcontrol` (`recalibrate`) |
| `nitro` | Idem — `customization.nitro = {kit, qty}` | `vhub_nitro` |
| `system` | Default — sem gates especiais | interno |

---

## 4. Eventos (NetEvents, ClientEvents)

### 4.1 `vhub_conce` — `shared/events.lua` (`VHubConce.E`)

| Constante | String | Lado | Emissor → Ouvinte | Payload |
|---|---|---|---|---|
| `SETUP` | `vhub_conce:setup` | — | (reservado) | — |
| `NOTIFY` | `vhub_conce:notify` | S→C | conce → client | `(msg, type)` |
| `REQ_CATALOG` | `vhub_conce:reqCatalog` | C→S | client → conce | — |
| `OPEN_UI` | `vhub_conce:openUI` | S→C | conce → client | `{view, payload}` |
| `ACT_BUY` | `vhub_conce:buy` | C→S | client → conce | `(model, placa_custom, conc_id)` |
| `ACT_TESTDRIVE` | `vhub_conce:testDrive` | C→S | client → conce | `(model, conc_id)` |
| **`VEHICLE_COMMITTED`** | `vHub:vehicleCommitted` | S→S (local) | VState (após `save`) → consumers | `{plate=str, source=str, changed={customization=bool, health=bool, fuel=bool}}` |

**⚠ Atenção:** `VEHICLE_COMMITTED` está **reservado** em `events.lua:21` mas **NÃO é emitido em nenhum lugar do vstate.lua ou sql.lua**. O `PLANO.md` (item E, §5.3, §10) prevê a implementação do emissor "para a F2". Hoje, consumidores como `vhub_vehcontrol` precisam pollar `getVehicleState` em vez de reagir — **gap documentado**.

### 4.2 `vhub_conce` — eventos institucionais consumidos (não-reservados)

Em `server/init.lua`:
- `vHub:characterLoad` → `Core:setSession(user.source, user)`
- `vHub:playerSpawn` → `Core:setSession(user.source, user)`
- `playerDropped` → `Core:dropSession(source)`
- `onResourceStart` / `onResourceStop` → lifecycle (`_running`, DDL, backfill, cron)

Em `server/core.lua` (cron de posse temporária):
- `TriggerClientEvent('vhub_garage:doDespawn', -1, k.plate)` — **literal hardcoded** quando o cron devolve veículo à garagem. Não está em `events.lua` do conce nem do garage; acoplamento implícito conce→garage.

### 4.3 `vhub_custom` — `shared/events.lua` (`VHubCustom.E`)

| Constante | String | Lado | Emissor → Ouvinte | Payload | Validação |
|---|---|---|---|---|---|
| `BENNYS_APPLY` | `vhub_custom:server:bennysApply` | C→S | client → `server/bennys.lua` | `(plate, payload)` | rate + canOperate + MOD_SPLIT + custo + persist |
| `BENNYS_CONFIRM` | `vhub_custom:client:bennysConfirm` | S→C | `server/bennys.lua` → client | `(plate, ok, custPatch?)` | rollback se `ok=false` |
| `BENNYS_OPEN` | `vhub_custom:client:bennysOpen` | S→C | (reservado) | — | — |
| `MEC_REPAIR` | `vhub_custom:server:mecRepair` | C→S | client → `server/mec.lua` | `(plate, repair_type)` | rate + canOperate + estado real |
| `MEC_TOW_REQ` | `vhub_custom:server:mecTowReq` | C→S | client → `server/mec.lua` | `(plate, net_id)` | rate + canOperate + status='out' + netId→ent→placa |
| `MEC_TOW_DO` | `vhub_custom:client:mecTowDo` | S→C | `server/mec.lua` → client | `(plate, net_id)` | client pede controle, reposiciona, confirma |
| `MEC_CONFIRM` | `vhub_custom:client:mecConfirm` | S→C | `server/mec.lua` → client | `(plate, ok, repair_type)` | animação + aplicação visual |
| `OFICINA_TUNE` | `vhub_custom:server:oficinaTune` | C→S | client → `server/oficina.lua` | `(plate, proposed_mods, veh_class)` | 9-passos (rate/sessão/placa/canOperate/cap/sanitiza/custo/save/confirm) |
| `OFICINA_CONFIRM` | `vhub_custom:client:oficinaConfirm` | S→C | `server/oficina.lua` → client | `(plate, ok, confirmedMods?)` | aplica stages ou rollback |
| `OFICINA_OPEN` | `vhub_custom:client:oficinaOpen` | S→C | (reservado) | — | — |
| `OFICINA_AUTH` | `vhub_custom:server:oficinaAuth` | C→S | client → `server/oficina.lua` | `(plate)` | pré-cheacagem + canOperate + devolve ficha |
| `OFICINA_AUTH_OK` | `vhub_custom:client:oficinaAuthOk` | S→C | `server/oficina.lua` → client | `(plate, ok, err_msg?, sheet?)` | abre NUI só se `ok=true` |
| `OFICINA_PREVIEW` | `vhub_custom:server:oficinaPreview` | C→S | client → `server/oficina.lua` | `(plate, draftAlloc)` | canOperate + pcall `vhub_vehcontrol:getVehicleSheetPreview` |
| `OFICINA_PREVIEW_OK` | `vhub_custom:client:oficinaPreviewOk` | S→C | `server/oficina.lua` → client | `(sheet?)` | exibe ficha hipotética na NUI |
| `OFICINA_NITRO_KIT` | `vhub_custom:server:oficinaNitroKit` | C→S | client → `server/oficina.lua` | `(plate)` | rate + canOperate + checa `vhub_nitro:getNitro` + cobra + `vhub_nitro:installKit` |
| `OFICINA_NITRO_KIT_OK` | `vhub_custom:client:oficinaNitroKitOk` | S→C | `server/oficina.lua` → client | `(ok, msg)` | notifica |
| `REQ_CATALOG` | `vhub_custom:server:reqCatalog` | C→S | client → `server/init.lua` | — | `buildCatalogIndex` |
| `CATALOG` | `vhub_custom:client:catalog` | S→C | `server/init.lua` → client | `(indexed)` | cacheia `VHubCustom.catalog` |
| `REQ_VEH_DATA` | `vhub_custom:server:reqVehData` | C→S | client → `server/init.lua` | `(plate)` | prontuário → catálogo |
| `VEH_DATA` | `vhub_custom:client:vehData` | S→C | `server/init.lua` → client | `(plate, data?)` | fallback de catálogo |
| `ZONE_ENTER` / `ZONE_LEAVE` | `vhub_custom:client:zoneEnter` / `zoneLeave` | S→C | (reservado — zones.lua é client-only) | — | — |
| `NOTIFY` | `vhub_custom:client:notify` | S→C | `Core.notify` → client | `(msg, kind)` | feedpost nativo colorido |

### 4.4 `vhub_custom` — literais hardcoded (NÃO em `events.lua`)

| String | Onde | Justificativa |
|---|---|---|
| `'vhub_custom:server:mecTowDone'` | `server/mec.lua:175` + `client/mec.lua:152,161,181` | Anti-spoof round-trip do reboque. **Violação L-19** (fonte única de nomes de eventos). |
| `'vhub_vehcontrol:recalibrate'` | `client/oficina.lua:239` | Delegação da calibração ao `vhub_vehcontrol` (recurso externo). |
| `'vhub_vehcontrol:recalDone'` | `client/oficina.lua:295` | Resposta do vehcontrol — NUI permanece aberta. |

---

## 5. Callbacks (lib callback / ox_lib)

**Nenhum callback `lib.callback` ou `ox_lib` é usado** em qualquer dos dois resources. Toda a comunicação NUI↔Lua é via `RegisterNUICallback` + `fetch('https://vhub_custom/...')`; toda Lua↔Lua é via `RegisterNetEvent`/`TriggerServerEvent`/`TriggerClientEvent`.

`vhub_custom` `RegisterNUICallback`s (17 callbacks):

| Callback | Arquivo | Payload de entrada | Retorno cb |
|---|---|---|---|
| `bennys:fechar` | `client/bennys.lua:331` | — | `'ok'` |
| `bennys:preview` | `client/bennys.lua:337` | patch cosmético | `'ok'` |
| `bennys:orbit` | `client/bennys.lua:346` | `{dx, dy}` | `'ok'` |
| `bennys:zoom` | `client/bennys.lua:352` | `{delta}` | `'ok'` |
| `bennys:focus` | `client/bennys.lua:358` | `{part?, kitIdx?}` | `'ok'` |
| `bennys:rescanWheels` | `client/bennys.lua:367` | `{wheel_type}` | `{count}` |
| `bennys:aplicar` | `client/bennys.lua:378` | `{plate, payload}` | `{ok}` |
| `mec:fechar` | `client/mec.lua:78` | — | `'ok'` |
| `mec:repair` | `client/mec.lua:84` | `{plate, repair_type}` | `{ok}` |
| `mec:tow` | `client/mec.lua:98` | — | `{ok}` |
| `oficina:fechar` | `client/oficina.lua:192` | — | `'ok'` |
| `oficina:aplicarTuning` | `client/oficina.lua:198` | `{plate, mods}` | `{ok}` |
| `oficina:recalibrar` | `client/oficina.lua:235` | `{plate, alloc}` | `'ok'` |
| `oficina:previewCalibrar` | `client/oficina.lua:245` | `{plate, alloc}` | `'ok'` |
| `oficina:instalarKitNitro` | `client/oficina.lua:255` | `{plate}` | `'ok'` |

---

## 6. NUI Bridge

Estrutura: UM `ui_page 'web/index.html'` carregando 3 JS (oficina.js, bennys.js, mec.js) + 3 CSS (style.css, bennys.css, mec.css). Cada JS é IIFE isolada, compartilhando o `window` mas não o estado.

### 6.1 Bennys — Lua → NUI

`SendNUIMessage({action='openBennys', data={...}})` dispara `openBennys()` no `bennys.js:480`.

```lua
data = {
  plate, nome, categoria,
  prices    = priceDict(CFG.prices),   -- {cor_primaria:500, cor_secundaria:500, ...}
  avail     = enumerateAvailable(veh), -- {kits={[idx]=count}, liveryCount, wheelMods}
  kit_types = KIT_TYPES,               -- [{idx,name,part}] 16 entradas
  current   = snapshotToCurrent(_snapshot), -- estado real anti-fantasma
}
```

Outros: `action='fecharBennys'` (fecha overlay).

### 6.2 Bennys — NUI → Lua (via `fetch('https://vhub_custom/<cb>')`)

| Endpoint | Body | Efeito |
|---|---|---|
| `bennys:preview` | `{...patch}` | Preview efêmero no veículo vivo |
| `bennys:aplicar` | `{plate, payload}` | `TriggerServerEvent(BENNYS_APPLY)` |
| `bennys:orbit` | `{dx, dy}` | `Cam.orbit` |
| `bennys:zoom` | `{delta}` | `Cam.zoom` |
| `bennys:focus` | `{part?, kitIdx?}` | `Cam.focus` |
| `bennys:rescanWheels` | `{wheel_type}` | `SetVehicleWheelType` + `GetNumVehicleMods(23)` |
| `bennys:fechar` | `{}` | `closeBennys(false)` |

### 6.3 Oficina — Lua → NUI

`action='openOficina'` com:
```lua
data = {
  plate, nome, categoria, classe_gta, stage_cap,
  sheet  = vehSheet(plate),  -- FICHA REAL do vhub_vehcontrol (tier/score/budget/alloc/ranges)
  stages = {_snap_perf indexado por string},  -- stages atuais (0=stock..3)
  prices = {engine_stage:{...}, brakes_stage:{...}, transmission_stage:{...},
            suspension_stage:{...}, armor_stage:{...}, turbo:12000},
}
```

Outros: `fecharOficina`, `recalibrarResultado {ok, data}` (ficha nova), `previewCalibrarResultado {data}`, `nitroKitResultado {ok}`.

### 6.4 Oficina — NUI → Lua

| Endpoint | Body | Efeito |
|---|---|---|
| `oficina:aplicarTuning` | `{plate, mods}` | `OFICINA_TUNE` |
| `oficina:recalibrar` | `{plate, alloc}` | `vhub_vehcontrol:recalibrate` (origin='oficina') |
| `oficina:previewCalibrar` | `{plate, alloc}` | `OFICINA_PREVIEW` (debounced 120ms no JS) |
| `oficina:instalarKitNitro` | `{plate}` | `OFICINA_NITRO_KIT` |
| `oficina:fechar` | `{}` | `closeOficina(false)` |

### 6.5 Mec — Lua → NUI

`action='openMec'` com `{plate, nome}`. `action='fecharMec'` fecha.

### 6.6 Mec — NUI → Lua

| Endpoint | Body | Efeito |
|---|---|---|
| `mec:repair` | `{plate, repair_type}` | `MEC_REPAIR` |
| `mec:tow` | `{}` | `MEC_TOW_REQ` (client resolve netId) |
| `mec:fechar` | `{}` | `closeMec()` |

---

## 7. Fluxos Principais

### 7.1 Comprar veículo novo na concessionária

Caminho completo (NUI do garage → conce → garage):

1. Jogador entra na zona da concessionária (zonas do garage, via PULL de `getZones` no boot).
2. NUI do garage abre catálogo (`vhub_garage/nui/js/dealership.js`).
3. Jogador seleciona modelo + digita placa custom (opcional) + clica "Comprar".
4. `TriggerServerEvent(VHubGarage.E.ACT_BUY, model, placa_custom, conc_id)`.
5. `vhub_garage/server/dealership.lua:18` — `Core:resolveConc(conc_id)` resolve a config da loja.
6. `exports.vhub_conce:buy(src, model, placa_custom, conc)` → `VHubConce.buy` em `vhub_conce/server/dealership.lua:18`:
   - `Core:getCharId(src)` — resolve cid server-side (sessão própria).
   - `VHubConce.catalog[model]` — entrada do catálogo. Rejeita se modelo inválido.
   - Valida `conc.tipos` contém `entry.tipo`.
   - `SQL:ownedCount(cid) >= CFG.max_veiculos_player` (25) → rejeita.
   - `SQL:stockGet(model)` — se `qty == 0`, rejeita; `custom_price` se definido.
   - `Core:newPlate(placa_custom)` — placa única (60 tentativas aleatórias ou custom validada; rejeita colisão).
   - `total = preco + (placa_custom ? taxa_placa_custom : 0)`.
   - `Core.pay(src, total)` → `exports.vhub_money:tryFullPayment(src, valor)` — falha = aborta.
   - `Core.giveKeyItem(src, plate)` → `exports.vhub_inventory:giveVehicleKey(src, plate)` — falha = estorna.
   - `SQL:createVehicle({...})` — INSERT em `vhub_vehicles` + `INSERT IGNORE` em `vh_vehicles` (espelho) + `VHubConce.VState:seed(plate, custJson)` (cria linha de fábrica no PRONTUÁRIO com `customization = {"model": model}`).
   - `SQL:grantKey(plate, cid, 'owner', cid, nil)` — chave-mãe imutável.
   - `SQL:stockDecrement(model)` se estoque existia.
   - `Core:log(plate, 'buy', cid, {model, preco, total})` — auditoria em `vhub_vehicle_log`.
   - Retorna `{ok=true, plate, model, total, msg}`.
7. `vhub_garage/server/dealership.lua:23` — notifica e abre `OPEN_UI` com `{kind='buy_ok', plate, model, total}`.

**Rollback parcial**: se `createVehicle` falha, `takeKeyItem` + `refund` são chamados.

### 7.2 Vender veículo para a concessionária (trade-in)

1. NUI do garage → `TriggerServerEvent(VHubGarage.E.ACT_SELL_SHOP, plate)`.
2. `vhub_garage/server/dealership.lua:38` → `exports.vhub_conce:sellToShop(src, plate)`.
3. `VHubConce.sellToShop` em `dealership.lua:88`:
   - `Core:getCharId(src)` + `U.normalizePlate(plate)`.
   - `SQL:getVehicle(p)` — checa `v.char_id == cid` (é dono), `v.status == 'garage'`, `Core.hasKeyItem(src, p)`.
   - `preco = v.purchase_price or entry.preco`; `valor = floor(preco * 0.60)` (`fator_revenda_loja`).
   - `Core.takeKeyItem(src, p)`.
   - `SQL:deleteVehicle(p)` — chama `VState:delete(p)` + `DELETE FROM vh_vehicles` + `DELETE FROM vhub_vehicles`.
   - `Core.refund(src, valor)` → `vhub_money:giveWallet`.
   - `Core:log(p, 'sell_shop', cid, {valor})`.
   - Retorna `{ok=true, valor, msg}`.

**Atenção**: O comment em `dealership.lua:103` diz que o bloco antigo gravava uma CÓPIA stale do CORE (no-op real) — atualmente nada é persistido antes do `deleteVehicle`, porque o físico morre junto no `VState:delete`.

### 7.3 Catálogo de veículos (`catalog.lua`)

`VHubConce.catalog` é uma tabela Lua **estática** no `shared/catalog.lua` com 33 entradas. Cada entrada:

```lua
sultan = {
  nome='Sultan', preco=18000, tipo='car', categoria='sedan',
  stats={vel=70,acel=72,freio=66,dir=74},
  -- campos opcionais:
  tags={'premium'},                  -- lista de tags
  p1 = {                             -- bloco do ENGINE DE SKILL (decisão #27)
    handling_name='toyotasupra',
    tier_base='S', tier_max='S+',
    base_alloc={potencia=180, grip=180, frenagem=180, aero=180, suspensao=180},
    -- opcionais (afinidade):
    archetype='rwd_heavy', grip_modifier=0.92, drive_bias=0.0,
    susp_raise=-0.015, mass=1600, inertia_z=1.6, low_speed_loss=1.0,
    seal='sha256:...',               -- hash do .meta selado
  },
}
```

7 entradas têm `p1` (TOYOTASUPRA, SKYLINER34, NISSAN370Z, f8t, FUSCA68, m3e46, ...) — estas suportam o engine de skill do `vhub_vehcontrol`. As demais 26 (incluindo todos os barcos/aviões/helis) **não suportam skill** (fail-closed; UI degrada para apenas stages nativos).

BUDGET por tier (do comentário `catalog.lua:12` e confirmado em `vhub_vehcontrol/shared/tier_rules.lua:25`): **D=500, C=600, B=700, A=800, S=900, S+=1000**.

**Carregamento**: o catálogo é lido em runtime via `exports.vhub_conce:getCatalog()`:
- `vhub_garage` faz cache no boot (`VHubGarage.catalog`) para exibição read-only.
- `vhub_custom` em `server/init.lua:18-39` (`buildCatalogIndex`) constrói índice por `lower(spawnName)` E `lower(displayName)` — útil para mods onde `GetDisplayNameFromVehicleModel` ≠ spawn name.
- `vhub_vehcontrol` em `server/exports.lua:20-37` (`buildIndex`) faz o mesmo (estratégia idêntica, cópia independente por design).

### 7.4 Modificação no bennys (câmera, mods, performance, paint)

1. Cliente entra na zona `bennys_ls` (-211.4, -1323.7, 30.3) → `zones.lua:88` detecta `domain='bennys'`.
2. Pressiona [E] dentro do `raio_interact` (3.5m) com veículo próximo (`GetClosestVehicle` raio 8.0).
3. `VHubCustom.openBennys()` em `client/bennys.lua:259`:
   - `_snapshot = snapshotVeh(veh)` — captura mods, colours, extra_colours, neons (0..3), neon_colour, tyre_smoke_color, custom_primary/secondary (RGB), window_tint, wheel_type, livery, plate_index, smoke, xenon, xenon_color.
   - `Cam.start(veh)` — câmera orbital ativa (thread de render a 0 ms com interpolação suave).
   - `SendNUIMessage({action='openBennys', data={plate, nome, categoria, prices, avail, kit_types, current}})`.
   - `avail = enumerateAvailable(veh)` — anti-fantasma: `GetNumVehicleMods(veh, k.idx)` para cada kit; só o que existe é renderizado na NUI.
4. Jogador interage na NUI (`bennys.js`):
   - Escolhe categoria (pintura/neon/rodas/kits/visual) → `post('bennys:focus', {part})` → `Cam.focus(part)` reposiciona alvo + raio.
   - Arrasta picker HSV → `_pending.custom_primary = [r,g,b]` → `post('bennys:preview', _pending)` → `VHubCustom.applyCosmetic(veh, patch)` aplica nativos no veículo vivo (preview efêmero).
   - Arrasta palco central → `bennys:orbit {dx,dy}` → `Cam.orbit` (throttled por RAF).
   - Scroll no palco → `bennys:zoom {delta}` → `Cam.zoom`.
   - Troca tipo de roda → `bennys:rescanWheels {wheel_type}` → re-enumera opções.
5. Jogador clica "APLICAR & PAGAR" → `bennys:aplicar {plate, payload}` → `TriggerServerEvent(BENNYS_APPLY, plate, payload)`.
6. `server/bennys.lua:129` em `Citizen.CreateThread`:
   - `Core.rateOK(src, 'bennys_apply')` — 5/30s.
   - `Core.getCharId(src)`.
   - `U.normalizePlate(plate)` + `U.validPayload(payload)`.
   - `Core.canOperate(src, p)` — **OBRIGATÓRIO** antes de tudo.
   - `buildCosmeticPatch(payload)` — monta patch só com chaves cosméticas; rejeita mods em `performance_mods` (defesa dupla).
   - `calcCost(payload)` — soma preços server-side (`cor_primaria + cor_secundaria + cor_perolado + cor_roda + ...`).
   - `Core.pay(src, custo)` — `vhub_money:tryFullPayment`.
   - `Core.saveVehicleState(p, {customization=custPatch}, 'cosmetic')` → `VState:save` (merge por chave; `mods` merge por índice).
   - `TriggerClientEvent(BENNYS_CONFIRM, src, p, true, custPatch)`.
7. `client/bennys.lua:307` — `applyCosmetic(veh, custPatch)` aplica definitivo + `closeBennys(true)` + `Cam.stop()`.

**Rollback**: Se `ok=false` ou o jogador cancelar, `applyCosmetic(veh, _snapshot)` restaura o estado anterior.

### 7.5 Reparo na oficina (mec — reparo PARCIAL)

Produto **distinto** do reparo total do garage (`maintenance.lua`). O mec repara um componente de cada vez (pneu OU motor OU lataria); o garage repara tudo.

1. Jogador entra na zona `mec_ls` (136.0, -1082.0, 29.1) → `domain='mec'`.
2. [E] → `VHubCustom.openMec()` → NUI `openMec {plate, nome}`.
3. Jogador clica Pneus/Motor/Lataria → `mec:repair {plate, repair_type}` → `MEC_REPAIR`.
4. `server/mec.lua:32` em thread:
   - rate + sessão + `canOperate` + `getVehicleState` (lê estado REAL do prontuário).
   - **`'tyre'`**: `patch.damage = {doors=dmg.doors, windows=dmg.windows, tyres={}, tyres_rim={}}` — limpa só pneus. Custo = `max(1, n_tyres) * prices.pneu`.
   - **`'engine'`**: `patch.engine_health = 1000.0`. Custo = `ceil(dmg_pts/100) * prices.motor_parcial` (R$ 800/100pts). Se `dmg_pts < 50`, aborta ("Motor sem danos relevantes.").
   - **`'body'`**: `patch.body_health = 1000.0`. Custo = `ceil(dmg_pts/100) * prices.lataria_parcial` (R$ 500/100pts).
   - `Core.pay(src, custo)` + `Core.saveVehicleState(p, patch, 'repair')` (source='repair' permite ELEVAR health e reescrever damage).
   - `TriggerClientEvent(MEC_CONFIRM, src, p, true, repair_type)`.
5. `client/mec.lua:117`:
   - `playRepairAnim()` — `veh@repair`/`fixing_a_player` por 3s.
   - Aplica visual: `SetVehicleTyreFixed` (0..5) / `SetVehicleEngineHealth(1000)` / `SetVehicleBodyHealth(1000)`.

### 7.6 Serviço de reboque (mec — tow)

Domínio NOVO sem dono anterior (`PLANO.md §6.2`). Move entidade + persiste posição via `conce:updatePosition`.

1. Jogador clica "SOLICITAR REBOQUE" → `mec:tow {}` → `MEC_TOW_REQ {plate, net_id}` (client resolve `NetworkGetNetworkIdFromEntity`).
2. `server/mec.lua:121` em thread:
   - rate (2/120s) + sessão + `canOperate` + `getVehicle(p).status == 'out'` (não guardado/apreendido).
   - **Anti-dupe**: `NetworkGetEntityFromNetworkId(nid)` → `GetVehicleNumberPlateText(ent)` → compara com `p` normalizado. Inconsistência = bloqueia + loga `mec_tow_ANTI_DUPE`.
   - `SetNetworkIdCanMigrate(nid, false)` — trava ownership durante a operação.
   - `_pending_tow[src] = {plate=p, net_id=nid}` — registra pendência (anti-spoof no `mecTowDone`).
   - `TriggerClientEvent(MEC_TOW_DO, src, p, nid)`.
3. `client/mec.lua:144` em thread:
   - `NetworkGetEntityFromNetId(nid)` → `NetworkRequestControlOfEntity(ent)` com timeout 5s.
   - `SetEntityCoords(ent, pPos.x+5, pPos.y, gz+0.5)` + `SetEntityHeading(ent, GetEntityHeading(PlayerPedId()))`.
   - `Citizen.Wait(200)` estabiliza física.
   - `TriggerServerEvent('vhub_custom:server:mecTowDone', plate, net_id, {x,y,z,h})`.
4. `server/mec.lua:175` em thread:
   - Valida `_pending_tow[src]` (plate + net_id batem).
   - `SetNetworkIdCanMigrate(nid, true)` — reabilita.
   - Monta JSON `{"x":..,"y":..,"z":..,"h":..}` → `exports.vhub_conce:updatePosition(p, posJson)`.
   - Notifica + loga `mec_tow_done`.

**playerDropped**: limpa `_pending_tow[src]` e reabilita migração se o player cair durante o reboque.

### 7.7 Modificação na oficina (tuning + calibração + nitro)

#### 7.7.1 Tuning de stages nativos

1. Zona `oficina_ls` (-360, -135, 38.5) → `domain='oficina'`.
2. [E] → `VHubCustom.openOficina()` em `client/oficina.lua:124`:
   - `_snap_perf = snapshotPerf(veh)` — stages 0..3 por índice 11/12/13/15/16 + toggle 18.
   - `TriggerServerEvent(OFICINA_AUTH, plate)`.
3. `server/oficina.lua:63` — `OFICINA_AUTH`:
   - `Core.getCharId(src)` + `U.normalizePlate(plate)` + `Core.canOperate(src, p)`.
   - `TriggerClientEvent(OFICINA_AUTH_OK, src, p, true, nil, vehSheet(p))` — **ficha real** do `vhub_vehcontrol` via `pcall(exports.vhub_vehcontrol:getVehicleSheet, p)`.
4. `client/oficina.lua:137` — `OFICINA_AUTH_OK`:
   - Lookup no catálogo local (caminho quente) ou fallback `REQ_VEH_DATA` (servidor resolve prontuário → catálogo).
   - `dispatchOpenOficina(veh, plate, catEntry, sheet)` → `SendNUIMessage({action='openOficina', data})`.
5. Jogador seleciona stages (0-3) por componente. JS calcula custo (só UPGRADE é cobrado; downgrade é grátis).
6. "APLICAR TUNING" → `oficina:aplicarTuning {plate, mods}` → preview imediato (`VHubCustom.previewTune`) + `OFICINA_TUNE {plate, mods, veh_class}`.
7. `server/oficina.lua:150` em thread (9 passos):
   - rate + sessão + `U.normalizePlate` + `canOperate` + `clamp(veh_class, 0, 20)`.
   - `cap = stage_cap_by_class[cls] or stage_cap_default`. Se 0, aborta.
   - `clean = U.sanitizeMods(proposed, CFG.performance_mods)` — aceita SÓ 11/12/13/15/16/18.
   - Valida `lvl > cap` → clampa silenciosamente + notifica "Stage máximo... Ajustado: ...".
   - Lê estado atual; `curStage(idx)` = `gta_level + 1` (turbo: `cur_turbo and 1 or 0`).
   - Custo = Σ `calcModCost(idx, lvl)` só para `lvl > curStage(idx)`.
   - `Core.pay(src, custo)`.
   - **Converte STAGE → convenção da garagem** antes de persistir: `gta_mods[idx] = stage - 1` (stock vira -1); `turbo` vira campo booleano separado (NUNCA em `mods`).
   - `Core.saveVehicleState(p, {customization={mods=gta_mods, turbo=...}}, 'tune')`.
   - `TriggerClientEvent(OFICINA_CONFIRM, src, p, true, clean)`.
8. `client/oficina.lua:268` — aplica stages confirmados ou rollback.

#### 7.7.2 Calibração 5-eixos (decisão #27)

A oficina **não persiste** o alloc — delega ao `vhub_vehcontrol` (que escreve via `source='handling'`):

1. Jogador clica "Calibrar" → `entrarCalibragem()` no JS → sliders substituem barras.
2. Arraste → `onSliderDrag` redistribui pontos entre 5 eixos (potencia/grip/frenagem/aero/suspensão) mantendo `Σ == budget`.
3. `requestPreview()` (debounced 120ms) → `oficina:previewCalibrar {plate, alloc}` → `OFICINA_PREVIEW` → `pcall(exports.vhub_vehcontrol:getVehicleSheetPreview, p, draftAlloc)` → `OFICINA_PREVIEW_OK {sheet?}` → `previewCalibrarResultado {data:sheet}` exibe "ATUAL vs CALIBRADO".
4. "Salvar (R$ 2.500)" → `oficina:recalibrar {plate, alloc}` → `TriggerServerEvent('vhub_vehcontrol:recalibrate', plate, alloc, 'oficina')`.
5. `vhub_vehcontrol/server/skill.lua:69`:
   - `canOperate(src, p)` + `p1ByPlate(p)` (carro sem p1 aborta).
   - `TR.budgetOf(base, cust.mods, cust.turbo)` + `TR.validateAlloc(alloc, budget)` (anti-P2W ranges).
   - `origin='oficina'` → `payMoney(src, OFICINA_PRICE=2500)` (vs `origin='toolbox'` consome item).
   - `exports.vhub_conce:saveVehicleState(p, {customization={handling=alloc}}, 'handling')`.
   - `TriggerClientEvent(RECAL_DONE, src, ok, msg, 'success', sheet_nova)`.
6. `client/oficina.lua:295` — `recalibrarResultado {ok, data}` atualiza a ficha na NUI (que permanece aberta).

#### 7.7.3 Kit nitro (decisão #29)

A oficina **cobra**; o `vhub_nitro` **escreve** o estado na placa (`customization.nitro = {kit, qty}`):

1. "⛽ KIT NITRO (R$ 5.000)" → `oficina:instalarKitNitro {plate}` → `OFICINA_NITRO_KIT`.
2. `server/oficina.lua:114`:
   - rate + sessão + `canOperate` + `exports.vhub_nitro:getNitro(p)` — se já tem kit, aborta.
   - `Core.pay(src, 5000)`.
   - `pcall(exports.vhub_nitro:installKit, src, p)` — vhub_nitro é o ÚNICO escritor.
   - Falha → `exports.vhub_money:giveBank(src, 5000, 'estorno_kit_nitro')`.
   - `OFICINA_NITRO_KIT_OK {ok, msg}`.

### 7.8 Persistência das mods (salvar no banco)

Tudo passa pelo `VState:save(plate, patch, source)` em `vhub_conce/server/vstate.lua:272`:

1. `U.normalizePlate(plate)` — anti-ghost-row #23.
2. `status = SELECT status FROM vhub_vehicles WHERE plate = ?` — âncora fail-closed (sem linha = return false).
3. `source == 'telemetry' and status ~= 'out'` → return false (anti race L-13).
4. `source in {'cosmetic','tune','handling','nitro'}` → `patch = {customization = patch.customization}` (isola — não toca health/fuel).
5. `cur = self:get(p)` — estado persistido (cache VRAM hit usual).
6. Por coluna: `finiteNum` (rejeita NaN/Inf ANTES do clamp) + clamp + `setcol`.
7. **Telemetria**: `eng = math.min(eng, cur.engine_health)` (monotônico não-crescente — anti repair-hack).
8. **Odômetro**: `odometer_add` (delta 0..2 km) somado em coluna (`odometer_km = odometer_km + VALUES(odometer_km)`).
9. **Customization**: `mergeCust(cur.customization, patch.customization)` — merge raso no topo, EXCETO `mods` que é merge POR ÍNDICE (preserva slots não tocados pelo patch). `sanitizeCustJson` (whitelist 16 chaves, cap 8 KB).
10. **Damage**: `sanitizeDamageJson` (cap 2 KB; `{}` explícito = limpa).
11. **damage_log**: append em queda brusca ≥ 150 pts (telemetria) ou em `repair`; FIFO cap 30; cap 16 KB.
12. UPSERT: `INSERT INTO vhub_vehicle_state (plate, ...) VALUES (...) ON DUPLICATE KEY UPDATE ...`.
13. `_cache[p] = nil` — invalidação no write (read-through repõe).

### 7.9 Validação de tier (vhub_custom consulta vhub_vehcontrol?)

**Sim**, mas só no `openOficina`:

- `server/oficina.lua:51-54` — `vehSheet(plate)` chama `pcall(exports.vhub_vehcontrol:getVehicleSheet, plate)`.
- O resultado (tier/score/budget/alloc/ranges) viaja no `OFICINA_AUTH_OK` como 5º argumento.
- O client repassa para a NUI em `data.sheet`.
- A NUI usa `sheet.tier` para o badge, `sheet.score` para o cursor na barra 0-1000, `sheet.budget` para os limites dos sliders, `sheet.ranges[axis]` para min/max por eixo.
- Se `vhub_vehcontrol` não estiver rodando, `sheet = nil` — a oficina ainda funciona (somente stages nativos, sem calibração 5-eixos). **Degradation graciosa** via `pcall`.

---

## 8. Integração com CORE/vhub

### 8.1 Exports do CORE chamados

| Resource | Export do CORE | Onde | Para quê |
|---|---|---|---|
| `vhub_conce` | — | — | **NÃO chama `exports.vhub:commitVehicleState/getVehicleState`**. Substituiu o CORE físico pelo PRONTUÁRIO próprio. Mantém só o espelho `vh_vehicles` (FK chain). |
| `vhub_custom` | — | — | Não fala com o CORE diretamente. Tudo via `vhub_conce` + `vhub_money` + `vhub_vehcontrol` + `vhub_nitro`. |

O `vhub_conce/server/exports.lua:97-99` comenta explicitamente: *"difere do homônimo legado `exports.vhub:getVehicleState` (CORE, nil sem VRAM — cadeia inerte pós-PRONTUÁRIO). Consumidores novos usam ESTE."* Ou seja, o `getVehicleState` do conce é o **novo canonical**, e o do CORE é **legado inerte**.

### 8.2 State Bags

Nenhum `AddStateBagChangeHandler` ou `Entity(veh).state.*` é usado em qualquer dos dois resources. O `vhub_conce` é server-only (sem client). O `vhub_custom` lê State Bags do CORE? **Não** — lê tudo via `exports.vhub_conce:getVehicleState`. 

O `vhub_vehcontrol` (vizinho) é quem escreve State Bags (`vhub_p1`, `vhub_p1_hnd`) — mas isso é fora do escopo deste par.

### 8.3 `vstate.lua` — como funciona

O **PRONTUÁRIO** (`vhub_vehicle_state`) é a **caixa-preta do vhub_conce**, mas bem documentada:

| Mecanismo | Implementação |
|---|---|
| **Cache VRAM** | `_cache = {}` global em `vstate.lua:130`. Read-through: `get(p)` lê do cache se presente; senão SELECT + decodifica + cacheia. Invalidation no write (`_cache[p] = nil`) e no delete (`evict`). |
| **GC** | Nenhum. Comment: *"Dispensa GC enquanto o conce for o escritor único (gate performance)."* Se veículos forem criados sem delete, o cache cresce indefinidamente — mas `evict` é chamado em `deleteVehicle`. |
| **DDL própria** | `ensureSchema()` no boot do conce, com `pcall` (DB nova pode não ter tabelas ainda). |
| **Collation audit** | Verifica `information_schema.TABLES.TABLE_COLLATION`; se ≠ `utf8mb4_unicode_ci`, faz `ALTER TABLE ... CONVERT TO`. |
| **Backfill** | `backfillCustomization()` — migrado de `vhub_vehicles.customization` (deprecated) → `vhub_vehicle_state.customization`. Idempotente; disparado pelo garage pós-DDL. |
| **Reconcile** | `reconcileOrphans()` — `DELETE FROM vhub_vehicle_state WHERE plate NOT IN (SELECT plate FROM vhub_vehicles)`. Substitui FK CASCADE. **NUNCA roda no boot do conce** (precisa que `vhub_vehicles` exista e esteja populada — gate persistência). |
| **âncora fail-closed** | Toda escrita começa com `SELECT status FROM vhub_vehicles WHERE plate = ?`. Sem linha = return false. Placa de rua/test-drive NUNCA persiste. |
| **Merge de customization** | `mergeCust(base, patch)` — raso no topo, exceto `mods` que é merge por índice. Preserva patches parciais (bennys toca slots cosméticos, oficina toca slots performance — disjuntos). |
| **Cap de payload** | `customization` ≤ 8 KB, `damage` ≤ 2 KB, `damage_log` ≤ 16 KB. Acima = descarta (hostil). |
| **Whitelist de customization** | `CUST_KEYS = {colours, extra_colours, plate_index, wheel_type, window_tint, livery, turbo, smoke, xenon, mods, neons, neon_colour, model, handling, nitro, custom_primary, custom_secondary, tyre_smoke_color, xenon_color}` — 19 chaves. |
| **Escrita IMEDIATA** | Sem buffer. `se(sql, vals)` direto em cada `save`. Comment: *"nada pendente em stop/drop"* (gate persistência). |

---

## 9. Integração Cross-Resource

### 9.1 `vhub_custom` ↔ `vhub_vehcontrol`

| Direção | Mecanismo | Quando |
|---|---|---|
| custom → vehcontrol | `exports.vhub_vehcontrol:getVehicleSheet(plate)` | `OFICINA_AUTH` (envia ficha real junto da autorização) |
| custom → vehcontrol | `exports.vhub_vehcontrol:getVehicleSheetPreview(plate, draftAlloc)` | `OFICINA_PREVIEW` (prévia não-persistente) |
| custom → vehcontrol | `TriggerServerEvent('vhub_vehcontrol:recalibrate', plate, alloc, 'oficina')` | `oficina:recalibrar` NUI callback |
| vehcontrol → custom | `TriggerClientEvent('vhub_vehcontrol:recalDone', src, ok, msg, kind, sheet)` | Após persistir alloc (origin='oficina' cobra R$ 2.500) |

**Tier limits**: a oficina NÃO consulta `tier_base`/`tier_max` do catálogo para limitar stages nativos. Usa `stage_cap_by_class[classe_gta]` (estático, definido em `CFG`). O tier do carskill só aparece na UI (`sheet.tier`) e limita a calibração 5-eixos (validada pelo vehcontrol em `TR.validateAlloc`).

### 9.2 `vhub_custom` ↔ `vhub_nitro`

| Direção | Mecanismo | Quando |
|---|---|---|
| custom → nitro | `exports.vhub_nitro:getNitro(p)` | `OFICINA_NITRO_KIT` (checa se já tem kit) |
| custom → nitro | `exports.vhub_nitro:installKit(src, p)` | `OFICINA_NITRO_KIT` (instala; nitro escreve `customization.nitro` via `conce:saveVehicleState` source='nitro') |

### 9.3 `vhub_custom` ↔ `vhub_money`

| Direção | Mecanismo |
|---|---|
| custom → money | `exports.vhub_money:tryFullPayment(src, amount)` (carteira → banco) |
| custom → money | `exports.vhub_money:giveBank(src, 5000, 'estorno_kit_nitro')` (estorno) |

### 9.4 `vhub_conce` ↔ `vhub_inventory`

| Direção | Mecanismo |
|---|---|
| conce → inventory | `exports.vhub_inventory:hasVehicleKey(src, plate)` |
| conce → inventory | `exports.vhub_inventory:giveVehicleKey(src, plate)` |
| conce → inventory | `exports.vhub_inventory:takeVehicleKey(src, plate)` |

### 9.5 `vhub_conce` ↔ `vhub_money`

| Direção | Mecanismo |
|---|---|
| conce → money | `exports.vhub_money:tryFullPayment(src, valor)` (compra) |
| conce → money | `exports.vhub_money:tryPayment(src, valor)` (test drive — só carteira) |
| conce → money | `exports.vhub_money:giveWallet(src, valor)` (estorno/refund) |

### 9.6 `vhub_conce` ↔ `vhub_garage`

| Direção | Mecanismo | Quando |
|---|---|---|
| garage → conce | `exports.vhub_conce:getZones()` | Boot do garage (PULL da config de localização, decisão #25) |
| garage → conce | `exports.vhub_conce:getCatalog()` | Boot do garage (cache read-only p/ exibição) |
| garage → conce | `exports.vhub_conce:buy/sellToShop/testDrive` | `dealership.lua` (delegator) |
| garage → conce | `exports.vhub_conce:backfillMirror/backfillOwnerKeys/backfillVehicleState/reconcileVehicleState` | Boot do garage pós-DDL |
| conce → garage | `TriggerClientEvent('vhub_garage:doDespawn', -1, k.plate)` | Cron 24h devolve veículo à garagem (returnExpiredHoldings) |

### 9.7 `vhub_custom` ↔ `handling-balancer`

**Não há integração direta**. O `handling-balancer` gera `out/catalog-patch.json` que é **mesclado à mão** em `vhub_conce/shared/catalog.lua` (bloco `p1` com `seal` hash do .meta). Não é runtime.

### 9.8 `vhub_conce` ↔ `vhub_vehcontrol` (telemetria)

O `vhub_vehcontrol` está no TRUSTED e envia telemetria física via `exports.vhub_conce:saveVehicleState(plate, patch, 'telemetry')`. O vstate aplica gates: `status == 'out'` obrigatório + `health` monotônico não-crescente.

---

## 10. Configuração

### 10.1 `vhub_conce` — `shared/config.lua` (`VHubConce.cfg`)

| Chave | Default | Descrição |
|---|---|---|
| `key_kinds` | `{owner=true, clone=true, shared=true, rental=true}` | Vocabulário de tipos de chave (espelha ENUM do DB) |
| `max_veiculos_player` | `25` | Limite de veículos por jogador (anti-allocador maligno) |
| `ipva_dias` | `7` | Validade do IPVA |
| `taxa_placa_custom` | `10000` | Custo extra ao comprar com placa personalizada |
| `fator_revenda_loja` | `0.60` | Fração do preço paga na venda para a loja |
| `fator_test_drive` | `0.00` | Custo do test drive = 0% do preço (grátis) |
| `test_drive_segundos` | `9999` | Duração do test drive (~2h47min — praticamente infinito) |
| `test_drive_raio` | `900.0` | Raio máximo do test drive (m) |
| `cron_interval_ms` | `3600000` | Varredura horária do cron 24h |
| `temp_hold_ttl_s` | `86400` | Chave sem `expires` devolve em 24h |
| `concessionarias` | 5 entradas | `pdm`, `sandy_dealer`, `paleto_dealer`, `aero_dealer`, `marina_dealer` — cada uma com `id, label, coord(vec3), raio, tipos, blip{sprite,color,scale}, test_spawn(vec4)` |

### 10.2 `vhub_custom` — `shared/config.lua` (`VHubCustom.cfg`)

| Chave | Default | Descrição |
|---|---|---|
| `debug` | `false` | Notificações de diagnóstico no caminho de tuning/estética |
| `performance_mods` | `{[11],[12],[13],[15],[16],[18]=true}` | Índices de performance — rejeitados no bennys, aceitos só na oficina |
| `cosmetic_mods` | 41 índices (0-10, 20, 22-49) | Whitelist cosmética para o bennys |
| `rates.bennys_apply` | `{max=5, window=30000}` | 5 aplicações/30s |
| `rates.mec_repair` | `{max=3, window=60000}` | 3 reparos/60s |
| `rates.mec_tow` | `{max=2, window=120000}` | 2 reboques/120s |
| `rates.oficina_tune` | `{max=5, window=60000}` | 5 tunings/60s |
| `prices.cor_primaria` | `500` | — |
| `prices.cor_secundaria` | `500` | — |
| `prices.cor_perolado` | `800` | — |
| `prices.cor_roda` | `400` | — |
| `prices.cor_custom` | `1500` | Pintura RGB exata |
| `prices.neon` | `1200` | — |
| `prices.neon_cor` | `600` | — |
| `prices.fumaca` | `800` | — |
| `prices.fumaca_cor` | `500` | — |
| `prices.xenon` | `1500` | — |
| `prices.tint` | `300` | — |
| `prices.livery` | `2000` | — |
| `prices.plate_index` | `200` | — |
| `prices.wheel_type` | `600` | — |
| `prices.mod_cosmetic` | `400` | — |
| `prices.pneu` | `300` | Reparo de pneu (por pneu) |
| `prices.motor_parcial` | `800` | Por 100pts de dano |
| `prices.lataria_parcial` | `500` | Por 100pts de dano |
| `prices.engine_stage` | `{[1]=3000, [2]=8000, [3]=18000}` | — |
| `prices.brakes_stage` | `{[1]=2000, [2]=5000, [3]=12000}` | — |
| `prices.transmission_stage` | `{[1]=2500, [2]=6000, [3]=14000}` | — |
| `prices.suspension_stage` | `{[1]=1800, [2]=4500, [3]=10000}` | — |
| `prices.armor_stage` | `{[1]=1500, [2]=4000, [3]=9000}` | — |
| `prices.turbo` | `12000` | — |
| `stage_cap_by_class` | 21 entradas (0-20) | Cap por classe GTA. Ex.: `[0]=1, [3]=2, [6]=2, [7]=3 (super), [11]=0 (van), [12]=0 (bike)` |
| `stage_cap_default` | `1` | Fallback |
| `zones` | 3 entradas | `bennys_ls`, `mec_ls`, `oficina_ls` — `{id, label, domain, x, y, z, raio_check=40, raio_interact=3.5, blip}` |

**Hardcoded em código (NÃO em config):**
- `NITRO_KIT_PRICE = 5000` em `server/oficina.lua:112`.
- `OFICINA_PRICE = 2500` em `vhub_vehcontrol/server/skill.lua` (não no custom, mas consumido pelo custom).
- `MARKER_COLOR = {r=220, g=180, b=90, a=100}` em `client/zones.lua:9`.
- `PROMPT_KEY = 38` (E) em `client/zones.lua:10`.
- Limites de câmera: `PITCH_MIN/MAX=-18/72`, `RAD_MIN/MAX=1.8/7.5`, `SMOOTH=0.16` em `client/camera.lua:37-39`.

---

## 11. Pontos de Atenção

### 11.1 Conflito entre `vhub_conce/dealership.lua` e `vhub_garage/dealership.lua`

**Não é conflito — é delegação por design.** O garage é o **ponto de entrada da NUI** (`ACT_BUY/ACT_SELL_SHOP/ACT_TESTDRIVE` events); o conce é a **autoridade da transação** (`buy/sellToShop/testDrive` exports). A separação é declarada no `fxmanifest.lua` do conce ("responsabilidade única: identidade do veículo... concessionária") e no comment do garage (`server/dealership.lua:1`: "DELEGATOR fino: a concessionaria mora no vhub_conce (FASE 2)").

**Risco**: se alguém adicionar lógica de transação no `garage/dealership.lua` sem saber que o conce é o dono, vira 2ª fonte. Hoje o garage só resolve conc + chama export + fala com NUI — limpo.

### 11.2 Possíveis violações do `manual_dev_vhub.md`

| Lei | Veredito | Detalhe |
|---|---|---|
| **L-04** (um dono por dado) | ✅ | `vhub_vehicle_state` tem dono único = `vhub_conce/VState`. `vhub_custom` nunca escreve direto em SQL. |
| **L-13** (`setVData` fora do core) | ✅ | O conce substituiu o `commitVehicleState` do CORE pelo próprio `saveVehicleState` — documentado no `manual_dev_vhub.md:198-205` ("Consumidores novos usam ESTE"). O CORE físico é declarado "inerte pós-PRONTUÁRIO". |
| **L-14** (não mutar `vd.state`) | ✅ | Nenhum `getVHub()`/`getVehicle()` do CORE é chamado. |
| **L-15** (todo .lua no fxmanifest) | ✅ | Confirmado: 11 arquivos no fxmanifest do conce = 11 no disco; 14 .lua + 7 web no fxmanifest do custom = 21 no disco (todos presentes). |
| **L-17** (replay-safe) | ⚠ Parcial | `vhub_custom/server/core.lua:23` registra `vHub:characterLoad` mas **não tem replay-guard** (sem `_seen[src]` nesse handler). O `server/init.lua:43` tem replay-guard para `vHub:playerSpawn`, mas o do core não. Em restart do conce com players online, a sessão pode ser perdida se `characterLoad` não for re-disparado. |
| **L-18** (orçamentos) | ✅ | Threads frias (1 Hz) + quente (dorme 500ms fora de zona). NUI fechada = 0.00 ms (sem loops). |
| **L-19** (vec3 local; primitivos em evento/export) | ⚠ Parcial | `vhub_conce/getZones` achata vec3/vec4 → `{x,y,z[,h]}` ✅. Mas `vhub_custom` tem 4 literais hardcoded (`vhub_custom:server:mecTowDone`, `vhub_vehcontrol:recalibrate`, `vhub_vehcontrol:recalDone`, `vhub_garage:doDespawn` no conce) que **não estão em `shared/events.lua`** — violação do "fonte única de nomes de eventos". |
| **L-08** (PT-BR) | ✅ | Comentários, logs, NUI em PT-BR. Identificadores em inglês (`canOperate`, `saveVehicleState`, etc.). |
| **L-10** (comentário PT-BR por função pública) | ✅ | Cabeçalhos explicativos em todos os arquivos. |
| **L-09** (1 responsabilidade por arquivo) | ✅ | `bennys.lua`/`mec.lua`/`oficina.lua` isolados. |

### 11.3 `vstate.lua` — caixa preta?

**Não é mais caixa preta** — o cabeçalho `server/vstate.lua:1-18` documenta tudo:

- Substitui `vh_vehicle_data` (CORE, inerte).
- 1 linha por placa, colunas explícitas legíveis (sem blob binário).
- Defaults = estado de fábrica.
- Gates por `source` (telemetria/store/pump/seed/repair/cosmetic/tune/handling/nitro/system).
- Placa SEMPRE normalizada (anti ghost-row #23).
- Âncora fail-closed (sem `vhub_vehicles` = nada escrito).
- NaN/Inf rejeitados antes do clamp.
- Escrita IMEDIATA (sem buffer).

**Riscos remanescentes:**
1. **Cache `_cache` sem GC**: se veículos forem criados sem `deleteVehicle`, o cache cresce. Em servidores longos com muitas compras, pode vazar memória. Mitigação: `evict()` é chamado em `deleteVehicle`, mas não há expiração por LRU.
2. **`vHub:vehicleCommitted` não emitido**: o evento está reservado mas `vstate.lua:save` não faz `TriggerEvent`. Consumers como `vhub_vehcontrol` precisam pollar `getVehicleState` em vez de reagir. Gap documentado ("Implementação do emissor pode ficar para a F2").
3. **`reconcileOrphans()` nunca roda no boot do conce**: depende do garage disparar pós-DDL. Se o garage não sobrer, órfãos se acumulam.
4. **Backfill de collation em todo boot**: `ensureSchema` faz `SELECT TABLE_COLLATION FROM information_schema` + `ALTER TABLE` se divergente. Em DB muito grande, o `ALTER` pode ser custoso. Comentário diz "checagem barata evita rebuild a cada boot" mas o `ALTER` em si não é barato em MEDIUMTEXT grande.

### 11.4 Outros pontos

- **`updateCustomization(plate, cj, locked)` é DEPRECATED** (`sql.lua:164-175`): só atualiza `locked`; `customization` é redirecionado ao `VState:save` com `source='store'`. A coluna `vhub_vehicles.customization` (LONGTEXT) **nunca mais é lida nem escrita** — resíduo histórico. Deveria ser migrada para `NULL` default + drop em FASE 6.
- **`test_drive_segundos = 9999`**: ~2h47min. Praticamente infinito. O `fator_test_drive = 0.00` torna gratuito. Isso é um possível ponto de abuso (player fica em test drive indefinidamente com carro spawnado).
- **`max_veiculos_player = 25`**: alto para um servidor de roleplay. O comment diz "defesa contra alocador maligno".
- **Hardcoded `'vhub_garage:doDespawn'` em `vhub_conce/server/core.lua:162`**: o conce aciona um evento client do garage diretamente. Se o garage não estiver rodando, o evento é silenciosamente descartado. Acoplamento implícito.
- **`vhub_custom/server/init.lua:18` `buildCatalogIndex`** constrói índice lowercase de spawn name + display name. O `vhub_vehcontrol/server/exports.lua:20` faz o mesmo (cópia independente por design — "zero mapa paralelo entre resources"). Se o catálogo mudar, ambos precisam re-cache — mas nenhum invalida explicitamente. Possível desync em hot-reload.
- **`vhub_custom` não tem `server/exports.lua`** apesar de o `PLANO.md §2` prever. A "API pública read-only (getTier preview, etc.)" não foi implementada. Hoje tudo é via eventos de rede — não há como outro resource chamar `vhub_custom` sincronamente.
- **`vhub_custom/client/zones.lua:81` usa `GetClosestVehicle(pPos.x, pPos.y, pPos.z, 8.0, 0, 70)`**: o `0` é o model hash (qualquer modelo) e `70` é a flag de bits (carros+motocicletas+...). Pode pegar veículo errado em zona densa. Não há validação de "veículo mais próximo é do player".
- **NUI sem timeout de inatividade**: comentário explícito em `bennys.js:8`, `mec.js:114`, `oficina.js:557` — "fecha só por ação explícita ou resposta do servidor". Bom para UX, mas se o servidor cair e o client não receber `CONFIRM`, a NUI fica presa até o jogador clicar Cancelar/ESC.
- **Câmera orbital desabilita ações do jogador**: `client/camera.lua:77-81` chama `DisablePlayerFiring` + `DisableControlAction` para Attack/Aim/Detonate/Attack2. Defesa caso o foco do CEF caia por 1 frame.

---

## 12. Resumo Executivo

O par `vhub_conce` + `vhub_custom` forma o **núcleo de identidade e modificação de veículos** do vHub:

- **`vhub_conce`** é a **autoridade** (server-only, 11 arquivos, 0 deps de cliente). Mantém `vhub_vehicles`/`vhub_vehicle_keys`/`vhub_dealership_stock`/`vhub_vehicle_log` (DDL do garage) + **cria e dona** `vhub_vehicle_state` (PRONTUÁRIO, DDL própria). Espelha `vh_vehicles` no CORE para a FK chain legada. Substitui o `commitVehicleState` do CORE por `saveVehicleState` com gates por `source`. Orquestra compra/venda/test-drive delegando ao `vhub_money`/`vhub_inventory`. Cron 24h devolve posse temporária.

- **`vhub_custom`** é o **consumidor** (1 resource, 3 domínios, 26 arquivos). NUNCA escreve em SQL direto — tudo via `exports.vhub_conce:saveVehicleState(plate, patch, source)`. bennys = cosmético (`source='cosmetic'`, rejeita performance); oficina = stages nativos + calibração (delegada ao `vhub_vehcontrol`) + nitro (delegado ao `vhub_nitro`) (`source='tune'`); mec = reparo parcial (`source='repair'`) + reboque (persiste posição via `conce:updatePosition`). Câmera orbital L2 HAL para o bennys. NUI Liquid Glass com 3 JS IIFE isolados.

- **Integração com carskill**: o `vhub_vehcontrol` é a fonte única de tier/score/afinidade derivados. A oficina consulta `getVehicleSheet`/`getVehicleSheetPreview` (read-only) e delega calibração via evento `vhub_vehcontrol:recalibrate` (origin='oficina' cobra R$ 2.500). O alloc é persistido pelo vehcontrol em `customization.handling` (source='handling').

- **Gaps documentados**: `vHub:vehicleCommitted` reservado mas não emitido (F2); `vhub_vehicles.customization` deprecated mas não droppada (FASE 6); 4 literais de evento hardcoded (violação L-19); cache VRAM sem GC.

- **ZIP = GitHub**: `diff -rq` zero diferenças para ambos os resources.
