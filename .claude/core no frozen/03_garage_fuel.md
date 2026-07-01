# 03 — Análise Profunda: `vhub_garage` + `vhub_legacyfuel`

> **Task ID:** 3 · **Agente:** Garage+Fuel Analyzer
> **Caminhos analisados:**
> - `resources/[SCRIPTS]/vhub_garage/` (GitHub-only, ~28 arquivos)
> - `resources/[CORE]/vhub_legacyfuel/` (4 arquivos)
>
> **Padrão de citação:** todos os nomes de evento, export, função e SQL são copiados literalmente dos arquivos lidos.

---

## 1. Visão Geral

### 1.1 O que cada recurso faz

#### `vhub_garage` (v2.0.0 — *"Garagem centralizada: garage + concessionária + leilão + pátio + aluguel + IPVA + chave. Fonte de verdade dos veículos"*)

É o **orquestrador de negócio do ciclo de vida dos veículos**: dono, posse, status, pátio, leilão, aluguel, IPVA, chave, transferência, reparo. Ele é **dono do NUI** (HTML/JS) e **dono da UX** das 4 views (Garagem, Concessionária, Leilão, Pátio), mas é **fino no domínio** — a maioria das transações é delegada a outros resources (que ele chama de "autoridades únicas"). Em outras palavras, o `vhub_garage` funciona como um **delegator / aggregator**.

Fluxo de donos por feature:

| Feature | Dono real | Papel do `vhub_garage` |
|---|---|---|
| Catálogo (modelos/preços/stats) | `vhub_conce` (`getCatalog`) | Cache read-only em `VHubGarage.catalog` no boot |
| Concessionária (zonas/compra/venda/test-drive) | `vhub_conce` (`buy`/`sellToShop`/`testDrive`) + `vhub_inventory` + `vhub_money` | NUI + delegação |
| Leilão (escrow/cron/bid/finalização) | `vhub_ferinha` (`newAuction`/`bid`/`cancelAuction`/`finalizeExpired`/`listActiveAuctions`) | NUI + montagem de lista |
| Veículo (registro/dono/status/keys/customization) | `vhub_conce` (autoridade de `vhub_vehicles` + `vhub_vehicle_keys` desde a "FASE 1") | Proxy `VHubGarage.SQL:*` → `exports.vhub_conce:*` |
| Prontuário físico (fuel/engine/body/damage/odometer) | `vhub_conce` (`getVehicleState`/`saveVehicleState`/`repairVehicleState`) | Lê p/ spawn, escreve no `store` |
| Pátio (impound) | **Próprio** (`vhub_impound` table + `server/impound.lua`) | Único que escreve em `vhub_impound` |
| IPVA | **Próprio** (coluna `vhub_vehicles.ipva_paid_until` via proxy) + lógica em `server/ipva.lua` | Único que cobra |
| Aluguel | **Próprio** (`server/rental.lua` + `rented_until` em `vhub_vehicles`) | Cron de expiração 1/min |
| Manutenção (reparo pago) | **Próprio** (`server/maintenance.lua`) + `vhub_conce:repairVehicleState` | Calcula custo + aplica |
| Admin (give/delete/transfer/set-status/repair/ipva/impound/stock/keys/spawn/despawn) | **Próprio** (`server/admin.lua`) | Superfície admin p/ `vhub_admin` |
| Logs de auditoria | **Próprio** (`vhub_vehicle_log`) | Único escritor |

#### `vhub_legacyfuel` (sem versão declarada — *"Legacy fuel adapted to vHub (server now uses vHub APIs)"*)

É a adaptação vHub do **Legacy Fuel** clássico da scene FiveM. Faz a **bomba de combustível física** (procura de pump no mundo, animação, taxa por litro, galão como arma `883325847` = jerrycan, persistência do nível de combustível) e o **comando admin `/fuel`**.

**Importante:** o consumo de combustível em si **NÃO** vive aqui — vive no CORE (`vhub/server/vehicle.lua:onStateUpdate` decai por rpm e replica via State Bag `vh_fuel`). O `legacyfuel` só cuida do **abastecimento na bomba** e do **comando admin**. O loop client `ManageFuelUsage` foi explicitamente REMOVIDO (comentário D1 RESOLVIDO em `client.lua`).

### 1.2 Como conversam com CORE/vhub

| Recurso | Mecanismo | Quem chama |
|---|---|---|
| `vhub_garage` → CORE | `AddEventHandler('vHub:characterLoad', ...)` e `'vHub:playerSpawn', ...` (replay-safe) | `server/init.lua:115-122` |
| `vhub_garage` → `vhub_money` | `exports.vhub_money:tryFullPayment` / `tryPayment` / `giveWallet` / `giveBank` | `server/core.lua:55-73` |
| `vhub_garage` → `vhub_inventory` | `hasVehicleKey` / `giveVehicleKey` / `takeVehicleKey` / `getVehicleKeys` | `server/core.lua:75-91` e `server/init.lua:145` |
| `vhub_garage` → `vhub_groups` | `hasPermission(src, perm)` | `server/core.lua:93-97` |
| `vhub_garage` → `vhub_conce` | 16+ exports (autoridade chave/placa/dono/prontuário) | `server/sql.lua` inteiro + vários call-sites |
| `vhub_garage` → `vhub_ferinha` | `listActiveAuctions`/`newAuction`/`bid`/`cancelAuction`/`finalizeExpired`/`getZones`/`getAuctionByPlate` | `server/auction.lua` + `server/init.lua:83` |
| `vhub_garage` → `oxmysql` | `exports['oxmysql']:scalar/execute/query` (Promise) | `server/sql.lua:8-31` |
| `vhub_legacyfuel` → `vhub_money` | `tryPayment(src, amount)` | `server.lua:14` |
| `vhub_legacyfuel` → `vhub_conce` | `saveVehicleState(plate, {fuel}, 'pump')` / `getVehicleState(plate)` | `server.lua:44,87,98` |
| `vhub_legacyfuel` → `vhub` (core) | `getUID(src)` / `hasPerm(uid, 'panel')` | `server.lua:49-53` |
| `vhub_legacyfuel` → cliente | `TriggerClientEvent('vHub:notify', src, ...)` / `syncfuel` / `vrp_legacyfuel:galao` / `vrp_legacyfuel:insuficiente` | `server.lua:71,99,102,148` |

### 1.3 Diferença de papel entre `vhub_garage` e `vhub_conce`

A separação é o coração da "FASE 1/2/4" referenciada em comentários do código:

| Aspecto | `vhub_conce` | `vhub_garage` |
|---|---|---|
| Posição no manifest | Antes do `vhub_garage` (é dependência) | Depois do `vhub_conce` |
| Dono do SQL `vhub_vehicles` / `vhub_vehicle_keys` | **Sim** (escritor único) | Não — só proxy de leitura/escrita |
| Dono do catálogo (modelos/preços/stats) | **Sim** | Não — lê `getCatalog()` em boot |
| Dono das zonas de concessionária | **Sim** (`getZones`) | Não — faz PULL no boot |
| Dono do prontuário físico (`vhub_vehicle_state`) | **Sim** (`saveVehicleState`/`getVehicleState`/`repairVehicleState`) | Não — lê no spawn, escreve via `saveVehicleState` no `store` |
| Dono da transação de compra/test-drive/venda-loja | **Sim** (`buy`/`sellToShop`/`testDrive`) | Não — só delega |
| Dono da NUI | Não | **Sim** (incl. view concessionária) |
| Dono do garage/pátio/leilão/IPVA/aluguel/reparo/admin | Não | **Sim** (parcial: leilão delega p/ `vhub_ferinha`) |
| Quem chama quem | `conce:backfillMirror`, `backfillOwnerKeys`, `backfillVehicleState`, `reconcileVehicleState` são chamados pelo `garage` no boot (porque `conce` sobe antes — `vhub_vehicles` ainda não existe quando `conce` carrega) | — |

A decisão #25 (citada em vários comentários): **config de localização de concessionária mudou para `vhub_conce`** e a do **leilão para `vhub_ferinha`** ("donos de negócio"). O garage agrega ambas via PULL no boot (`exports.vhub_conce:getZones` / `exports.vhub_ferinha:getZones`) e renderiza a engine de presença única (`client/zones.lua`).

---

## 2. SQL Schema (DETALHADO)

Schema: `vhub_garage/sql/schema.sql` — 6 tabelas, charset `utf8mb4_unicode_ci`, engine `InnoDB`. Aplicado no boot via `M:initSchema()` que lê o arquivo via `LoadResourceFile` e executa como batch único.

> **Observação crítica (comentário no topo do schema):** "Convivem com tabelas do core vHub (`vh_vehicles` para key_uid; `vh_char_data` para state físico via msgpack). `vhub_garage` = fonte de verdade de **NEGÓCIO** (dono, status, IPVA, pátio, leilão, aluguel). Core vHub = fonte de verdade de **FÍSICO** (fuel, dano, odometer, tuning, last_pos)."
>
> **Porém** — no código real (pós-FASE 1), o `vhub_garage` **não escreve mais** diretamente nestas tabelas: tudo é proxy para `vhub_conce` (escritor único). O DDL ainda mora no garage por motivos de ordem de boot, mas a leitura/escrita é delegated.

### 2.1 Tabela `vhub_vehicles` (mestre)

```sql
CREATE TABLE IF NOT EXISTS `vhub_vehicles` (
  `plate`             VARCHAR(10)  NOT NULL,
  `model`             VARCHAR(64)  NOT NULL,
  `vtype`             ENUM('car','bike','plane','heli','boat','truck','trailer') NOT NULL DEFAULT 'car',
  `category`          VARCHAR(32)  NOT NULL DEFAULT 'sedan',
  `char_id`           INT UNSIGNED      DEFAULT NULL,
  `status`            ENUM('garage','out','impound','auction','rental','sold') NOT NULL DEFAULT 'garage',
  `customization`     LONGTEXT          DEFAULT NULL,
  `locked`            TINYINT(1)        NOT NULL DEFAULT 0,
  `position`          TEXT              DEFAULT NULL,
  `ipva_paid_until`   BIGINT            DEFAULT NULL,
  `rented_until`      BIGINT            DEFAULT NULL,
  `purchase_price`    INT UNSIGNED      DEFAULT 0,
  `purchase_at`       BIGINT             DEFAULT NULL,
  `last_seen_at`      BIGINT            DEFAULT NULL,
  `created_at`        BIGINT            NOT NULL,
  `updated_at`        BIGINT            NOT NULL,
  PRIMARY KEY (`plate`),
  KEY `idx_char_id`   (`char_id`),
  KEY `idx_status`    (`status`),
  KEY `idx_vtype`     (`vtype`),
  KEY `idx_rented`    (`rented_until`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

- **PK:** `plate` (VARCHAR(10)) — chave natural, placa normalizada
- **FKs lógicas:** `char_id` → `vh_characters.id` (não tem constraint física, mas `adminFindOrphans` valida com subquery `WHERE char_id NOT IN (SELECT id FROM vh_characters)`)
- **6 status possíveis:** `garage`, `out`, `impound`, `auction`, `rental`, `sold`
- **`customization`:** LONGTEXT JSON (legado — pós-PRONTUÁRIO usa `vhub_conce:getVehicleState` no lugar; fallback para DB antigo no spawn)
- **`position`:** TEXT JSON `{x,y,z,h}` (server-authoritative pós-store)
- **`ipva_paid_until` / `rented_until`:** BIGINT Unix timestamp (segundos) — permite `NULL` (sem IPVA/aluguel)
- **Índices:** `idx_char_id`, `idx_status`, `idx_vtype`, `idx_rented` (cobre queries de dono/status/tipo/cron de aluguel)

### 2.2 Tabela `vhub_vehicle_keys` (autorização de chave)

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
  KEY `idx_char_id` (`char_id`),
  KEY `idx_plate`   (`plate`),
  KEY `idx_expires` (`expires_at`),
  CONSTRAINT `fk_keys_plate`
    FOREIGN KEY (`plate`) REFERENCES `vhub_vehicles`(`plate`)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

- **4 kinds de chave:** `owner` (dono real), `shared` (empréstimo), `clone` (cópia paga), `rental` (aluguel)
- **UNIQUE KEY `(plate, char_id, kind)`:** impede duplicar exatamente a mesma outorga
- **FK física `fk_keys_plate` → `vhub_vehicles(plate)` ON DELETE CASCADE:** placa some → chaves somem junto
- **`expires_at`:** `NULL` = permanente; timestamp = expira (cron `purgeExpiredKeys`)
- **Lembrete do comentário no schema:** "a chave-item física vive no `vhub_inventory`. Esta tabela trava autorização de uso." — ou seja, há duas camadas: a item-física (inventário) e a lógica (esta tabela)

### 2.3 Tabela `vhub_auctions` (cabeçalho de leilão)

```sql
CREATE TABLE IF NOT EXISTS `vhub_auctions` (
  `id`             INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  `plate`          VARCHAR(10)   NOT NULL,
  `seller_id`      INT UNSIGNED  NOT NULL,
  `min_bid`        INT UNSIGNED  NOT NULL,
  `buyout`         INT UNSIGNED  DEFAULT NULL,
  `current_bid`    INT UNSIGNED  DEFAULT NULL,
  `current_bidder` INT UNSIGNED  DEFAULT NULL,
  `fee_paid`       INT UNSIGNED  NOT NULL DEFAULT 0,
  `ends_at`        BIGINT        NOT NULL,
  `status`         ENUM('active','sold','cancelled','expired') NOT NULL DEFAULT 'active',
  `created_at`     BIGINT        NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_plate`   (`plate`),
  KEY `idx_status`  (`status`),
  KEY `idx_ends`    (`ends_at`),
  KEY `idx_seller`  (`seller_id`),
  CONSTRAINT `fk_auc_plate`
    FOREIGN KEY (`plate`) REFERENCES `vhub_vehicles`(`plate`)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

- **4 status:** `active`, `sold`, `cancelled`, `expired`
- **`buyout`:** `NULL` = sem compra direta; valor = preço de compra imediata
- **`current_bid`/`current_bidder`:** lance atual (NULL no início)
- **`fee_paid`:** taxa de listagem não-reembolsável (default `CFG.taxa_leilao = 100`)
- **FK física `fk_auc_plate`** CASCADE

> **Nota:** embora a tabela exista no schema do garage, o comentário em `server/sql.lua:104-108` declara que a lógica de leilão migrou para `vhub_ferinha` (FASE 4) e só `getAuctionByPlate` (info admin) fica como proxy. As queries de leitura de leilão admin (`adminListAuctions` em `server/admin.lua:122-132`) ainda usam `SQL.query` direto nesta tabela.

### 2.4 Tabela `vhub_auction_bids` (histórico de lances)

```sql
CREATE TABLE IF NOT EXISTS `vhub_auction_bids` (
  `id`         INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  `auction_id` INT UNSIGNED  NOT NULL,
  `bidder_id`  INT UNSIGNED  NOT NULL,
  `amount`     INT UNSIGNED  NOT NULL,
  `created_at` BIGINT        NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_auc`    (`auction_id`),
  KEY `idx_bidder` (`bidder_id`),
  CONSTRAINT `fk_bid_auc`
    FOREIGN KEY (`auction_id`) REFERENCES `vhub_auctions`(`id`)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

- FK física `fk_bid_auc` → `vhub_auctions(id)` CASCADE — leilão some → lances somem
- Sem queries de escrita direta do `vhub_garage` (escritas são via `vhub_ferinha`); pode haver escritas legacy não removidas — **verificar em `vhub_ferinha`**

### 2.5 Tabela `vhub_impound` (pátio)

```sql
CREATE TABLE IF NOT EXISTS `vhub_impound` (
  `id`            INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  `plate`         VARCHAR(10)   NOT NULL,
  `reason`        VARCHAR(120)  NOT NULL DEFAULT 'apreendido',
  `fee`           INT UNSIGNED  NOT NULL DEFAULT 0,
  `impounded_by`  INT UNSIGNED  DEFAULT NULL,
  `impounded_at`  BIGINT        NOT NULL,
  `released_by`   INT UNSIGNED  DEFAULT NULL,
  `released_at`   BIGINT        DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_plate`   (`plate`),
  KEY `idx_active`  (`released_at`),
  CONSTRAINT `fk_imp_plate`
    FOREIGN KEY (`plate`) REFERENCES `vhub_vehicles`(`plate`)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

- **Histórico + atual:** mesma tabela; `released_at IS NULL` = apreensão ativa
- **`fee`:** calculada em `CFG.patio_taxa + floor(preco * CFG.patio_taxa_porcent)` + extra admin
- **`impounded_by`/`released_by`:** `char_id` do ator (`NULL` se foi por boot-scan ou API externa)
- **Índice `idx_active` em `released_at`:** otimiza `WHERE released_at IS NULL` (lista de pátio)
- **FK física `fk_imp_plate`** CASCADE

### 2.6 Tabela `vhub_dealership_stock` (estoque admin)

```sql
CREATE TABLE IF NOT EXISTS `vhub_dealership_stock` (
  `model`         VARCHAR(64)  NOT NULL,
  `qty`           INT          NOT NULL DEFAULT -1,
  `custom_price`  INT UNSIGNED DEFAULT NULL,
  `updated_at`    BIGINT       NOT NULL,
  PRIMARY KEY (`model`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

- **`qty = -1`:** ilimitado (default)
- **`qty = 0`:** esgotado (a NUI não mostra o modelo)
- **`custom_price`:** `NULL` = usa preço do catálogo; valor = override
- **Sem FK** (model não é placa; é nome de modelo GTA)
- **Único escritor:** `vhub_conce` (proxy desde FASE 1) — `vhub_garage` chama `SQL:stockGet/Set/Decrement` → `exports.vhub_conce:*`

### 2.7 Tabela `vhub_vehicle_log` (auditoria)

```sql
CREATE TABLE IF NOT EXISTS `vhub_vehicle_log` (
  `id`         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `plate`      VARCHAR(10)     NOT NULL,
  `action`     VARCHAR(32)     NOT NULL,
  `actor_id`   INT UNSIGNED    DEFAULT NULL,
  `payload`    TEXT            DEFAULT NULL,
  `created_at` BIGINT          NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_plate`   (`plate`),
  KEY `idx_action`  (`action`),
  KEY `idx_actor`   (`actor_id`),
  KEY `idx_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

- **`plate`:** VARCHAR(10) — também aceita `"STOCK"` e `"SYS"` para logs não-veiculares (`adminSetStock` e `adminPurgeOldLogs` usam essas sentinelas)
- **`action`:** VARCHAR(32) — sem ENUM (valores vistos no código: `spawn`, `store`, `transfer`, `transfer_error`, `lend_key`, `revoke_key`, `clone_key`, `boot_scan`, `impound_put`, `impound_put_api`, `impound_release`, `repair`, `rent_new`, `rent_expired`, `ipva_paid`, `admin_give`, `admin_transfer`, `admin_delete`, `admin_set_status`, `admin_repair`, `admin_ipva`, `admin_release_impound`, `admin_spawn_to`, `admin_despawn`, `admin_grant_key`, `admin_revoke_key`, `admin_set_stock`, `admin_purge_keys`, `admin_purge_logs`, `admin_finalize_auctions`, `force_transfer`)
- **`payload`:** TEXT JSON serializado por `U.jenc`
- **`actor_id`:** `NULL` para boot-scan; caso contrário `char_id`
- **Sem FK** (plates órfãos podem existir após `deleteVehicle` — histórico é preservado)
- **4 índices** cobrem lookup por placa, action, ator, e range temporal (purge)

### 2.8 Tabelas esperadas mas ausentes

A task pede para verificar "rentals, ipva, maintenance_logs". Veredito:

| Esperado | Realidade |
|---|---|
| `rentals` | **NÃO existe como tabela separada.** Aluguel é marcado pela coluna `vhub_vehicles.rented_until` (BIGINT). Cron de expiração em `server/rental.lua:69-89` faz `SELECT plate, char_id FROM vhub_vehicles WHERE rented_until IS NOT NULL AND rented_until <= ?`. |
| `ipva` | **NÃO existe como tabela separada.** IPVA é marcado pela coluna `vhub_vehicles.ipva_paid_until` (BIGINT). Pagamento estende o timestamp em `server/ipva.lua:28-30`. |
| `maintenance_logs` | **NÃO existe como tabela separada.** Reparos são logados na tabela genérica `vhub_vehicle_log` com `action='repair'` (e `admin_repair` para reparo admin). O custo é calculado on-the-fly em `server/maintenance.lua:67-68` lendo o estado físico do prontuário. |

### 2.9 Tabelas externas referenciadas (não-criadas aqui)

- `vh_vehicles` — core (mirror de `vhub_vehicles` para `key_uid` — escritor é `vhub_conce`)
- `vh_vehicle_data` — core (estado físico via msgpack; **não usado diretamente** pelo garage pós-PRONTUÁRIO)
- `vh_characters` — core (referenciado em subquery de `adminFindOrphans`)
- `vh_char_data` — core (state físico legado, mencionado em comentário)

---

## 3. Exports (Server & Client)

> **Sem exports client-side** declarados em `vhub_garage` (a UX é dirigida por eventos). A única exposição pública é via estado global `VHubGarage` (com `VHubGarage.openNui`, `VHubGarage.closeNui`, `VHubGarage.veiculoMaisProximo` em `client/init.lua:65-66` e `client/vehicles.lua:393`) — mas estes são **métodos da tabela global**, não exports registrados.

### 3.1 `vhub_garage` — exports server

Localização: `server/exports.lua` e `server/admin.lua` e `server/impound.lua`.

#### 3.1.1 Públicos (qualquer um chama)

| Export | Assinatura | Descrição |
|---|---|---|
| `getVehicle` | `getVehicle(plate) → row\|nil` | Lê linha de `vhub_vehicles` (via proxy `vhub_conce:getVehicle`). Normaliza placa. |
| `listOwnerVehicles` | `listOwnerVehicles(char_id) → {[row]}` | Lista veículos por dono (`vhub_conce:listByOwner`). |
| `isImpound` | `isImpound(plate) → boolean` | `true` se `status == 'impound'`. |
| `ipvaUntil` | `ipvaUntil(plate) → number` | Devolve `ipva_paid_until` (0 se não existir). |

#### 3.1.2 Sensíveis (exigem invoker confiável: `vhub`, `vhub_inventory`, `vhub_money`, `vhub_identity`, `vhub_groups`, `vhub_player_state`, `vhub_admin`, `vhub_lspdtool`)

| Export | Assinatura | Descrição |
|---|---|---|
| `forceTransfer` | `forceTransfer(plate, new_char_id) → boolean` | Transferência forçada (admin/polícia). Delega `vhub_conce:transferOwner`. Roda em thread própria (não-bloqueante). |
| `forceImpound` | `forceImpound(plate, reason, fee_extra) → boolean` | Apreensão policial via `vhub_lspdtool`. Re-chama `impoundVehicle` em si mesmo. |

#### 3.1.3 Admin (`server/admin.lua` — invoker restrito a `vhub_admin` e `vhub`)

| Export | Assinatura | Descrição |
|---|---|---|
| `adminStats` | `adminStats() → { total, by_status, by_type, active_auctions, active_impound, active_rental }` | Panorama da frota (queries agregadas). |
| `adminListVehicles` | `adminListVehicles({ status?, vtype?, char_id?, search? }, limit, offset) → {[row]}` | Lista com filtros. limit max 500. |
| `adminGetVehicle` | `adminGetVehicle(plate) → { vehicle, keys, impound, auction, logs }` | Detalhe completo de uma placa. |
| `adminListByOwner` | `adminListByOwner(char_id) → {[row]}` | Por dono. |
| `adminListAuctions` | `adminListAuctions(status?) → {[row]}` | Leilões (max 200). |
| `adminListImpound` | `adminListImpound() → {[row]}` | Pátio ativo. |
| `adminListLogs` | `adminListLogs(plate?, limit) → {[row]}` | Logs (max 500). |
| `adminFindOrphans` | `adminFindOrphans() → {[row]}` | Veículos com `char_id NULL` ou inexistente em `vh_characters` (max 500). |
| `adminGiveVehicle` | `adminGiveVehicle(char_id, model, placa_custom?, actor_src?) → plate\|false` | Cria veículo grátis para um char. Dá IPVA inicial + chave-item se online. |
| `adminTransfer` | `adminTransfer(plate, new_char_id, actor_src?) → boolean` | Transferência forçada (tira chave-item antigo, dá novo). |
| `adminDelete` | `adminDelete(plate, actor_src?) → boolean` | Remove veículo + broadcast `DO_DESPAWN(-1)`. |
| `adminSetStatus` | `adminSetStatus(plate, status, actor_src?) → boolean` | Força status. |
| `adminRepair` | `adminRepair(plate, actor_src?) → boolean` | Reparo grátis (`vhub_conce:repairVehicleState` + `DO_REPAIR(-1)`). |
| `adminRenewIpva` | `adminRenewIpva(plate, dias?, actor_src?) → boolean` | Renova IPVA grátis (default `CFG.ipva_dias`). |
| `adminReleaseImpound` | `adminReleaseImpound(plate, actor_src?) → boolean` | Libera do pátio sem custo. |
| `adminCancelAuction` | `adminCancelAuction(auction_id, actor_src?) → boolean` | Cancela leilão (delega `vhub_ferinha:cancelAuction`). |
| `adminSetStock` | `adminSetStock(model, qty, custom_price, actor_src?) → boolean` | Define estoque/preço custom. |
| `adminGrantKey` | `adminGrantKey(plate, char_id, kind?, days?, actor_src?) → boolean` | Concede chave (default `shared`). |
| `adminRevokeKey` | `adminRevokeKey(plate, char_id, actor_src?) → boolean` | Revoga chave + tira item. |
| `adminSpawnTo` | `adminSpawnTo(src, plate, pos?, actor_src?) → boolean` | Spawn de veículo para um src específico em pos arbitrária (admin). |
| `adminDespawn` | `adminDespawn(plate, actor_src?) → boolean` | Despawn global + status `garage`. |
| `adminPurgeExpiredKeys` | `adminPurgeExpiredKeys(actor_src?) → number` | Limpa chaves expiradas (delega `vhub_conce:purgeExpiredKeys`). |
| `adminPurgeOldLogs` | `adminPurgeOldLogs(days?, actor_src?) → number` | Deleta logs com mais de `days` dias (min 7, default 60). |
| `adminFinalizeStaleAuctions` | `adminFinalizeStaleAuctions(actor_src?) → number` | Finaliza leilões expirados (delega `vhub_ferinha:finalizeExpired`). |

#### 3.1.4 Pátio (`server/impound.lua:115-131`)

| Export | Assinatura | Descrição |
|---|---|---|
| `impoundVehicle` | `impoundVehicle(plate, reason, fee_extra) → boolean` | Apreensão programática (sem validação de perm — gate é externo). Atualiza status + insere `vhub_impound` + broadcast `DO_DESPAWN(-1)`. |

### 3.2 `vhub_legacyfuel` — exports

**Nenhum export declarado.** Todo o acesso é via eventos server `vrp_legacyfuel:pagamento` e `vrp_legacyfuel:setFuel` (e os respectivos `RegisterServerEvent`).

### 3.3 `vhub_conce` exports consumidos pelo `vhub_garage` (relevantes)

Os seguintes exports do `vhub_conce` são chamados a partir do `vhub_garage` (proxy em `server/sql.lua` + call-sites diretos):

- `getCatalog()` — cache de catálogo
- `getZones()` — zonas de concessionária (PULL no boot)
- `backfillMirror()` / `backfillOwnerKeys()` / `backfillVehicleState()` / `reconcileVehicleState()` — backfills no boot
- `plateExists` / `getVehicle` / `listByOwner` / `listByStatus` / `createVehicle` / `updateStatus` / `updatePosition` / `updateCustomization` / `updateIpva` / `updateRental` / `deleteVehicle`
- `grantKey` / `revokeKey` / `hasValidKey` / `listKeys` / `listKeysOfChar` / `purgeExpiredKeys`
- `stockGet` / `stockSet` / `stockDecrement`
- `canOperate` (autorização)
- `transferOwner` (transferência atômica de dono)
- `getVehicleState` / `saveVehicleState` / `repairVehicleState` (prontuário)

---

## 4. Eventos (NetEvents, ClientEvents, NUI callbacks)

Centralizados em `shared/events.lua` em `VHubGarage.E` (tabela global).

### 4.1 Servidor → Cliente (`VHubGarage.E.*` — `TriggerClientEvent`)

| Evento | Constante | Payload | Emissor | Ouvinte | Validação |
|---|---|---|---|---|---|
| `vhub_garage:setup` | `E.SETUP` | `{ garagens, concessionarias, leilao, patio, catalog, types }` | `server/init.lua:106,121` | `client/init.lua:24` | `type(setup) == 'table'` |
| `vhub_garage:notify` | `E.NOTIFY` | `string` | `server/core.lua:125` | `client/init.lua:42` | feedpost textual |
| `vhub_garage:openUI` | `E.OPEN_UI` | `{ view, payload }` | `server/init.lua:159,194`; `server/impound.lua:39`; `server/auction.lua:34`; `server/dealership.lua:25` | `client/init.lua:68` | `req.view` truthy |
| `vhub_garage:closeUI` | `E.CLOSE_UI` | (nenhum) | (não usado diretamente em código lido) | `client/init.lua:79` | — |
| `vhub_garage:doSpawn` | `E.DO_SPAWN` | `{ plate, model, vtype, customization, state, locked, surface }`, `pos = { x, y, z, h }` | `server/garage.lua:150`; `server/admin.lua:375` | `client/vehicles.lua:155` | — |
| `vhub_garage:doDespawn` | `E.DO_DESPAWN` | `plate` (string) | `server/garage.lua:230`; `server/impound.lua:77`; `server/rental.lua:82`; `server/admin.lua:246,390` | `client/vehicles.lua:258` | — |
| `vhub_garage:doTestDrive` | `E.DO_TESTDRIVE` | `{ model, spawn, seg, raio }` | `server/dealership.lua:57` | `client/vehicles.lua:283` | — |
| `vhub_garage:spawnOut` | `E.SPAWN_OUT` | `{ [snap, ...] }` (cada `snap` tem `.position`) | (não emitido em código lido — placeholder) | `client/vehicles.lua:160` | `type(list) == 'table'` |
| `vhub_garage:doRepair` | `E.DO_REPAIR` | `plate` | `server/maintenance.lua:79`; `server/admin.lua:272` | `client/vehicles.lua:353` | — |
| `vhub_garage:rescueDone` | `E.RESCUE_DONE` | `plate` | `server/impound.lua:108` | (não há handler client visível — provavelmente UI-only) | — |
| `vhub_garage:updateAuction` | `E.UPDATE_AUCTION` | (broadcast de leilão atualizado) | (não emitido em código lido — placeholder) | — | — |

### 4.2 Cliente → Servidor (`VHubGarage.E.*` — `RegisterNetEvent`)

| Evento | Constante | Payload | Emissor | Handler | Validação de source |
|---|---|---|---|---|---|
| `vhub_garage:reqList` | `E.REQ_LIST` | (nenhum) | `client/init.lua:197`; `client/zones.lua:130` | `server/init.lua:131` | `Core:getCharId(src)` |
| `vhub_garage:reqCatalog` | `E.REQ_CATALOG` | `conc_id` (string) | `client/init.lua:203`; `client/zones.lua:131` | `server/init.lua:166` | `Core:resolveConc(conc_id)` |
| `vhub_garage:reqAuctions` | `E.REQ_AUCTIONS` | (nenhum) | `client/init.lua:209`; `client/zones.lua:132` | `server/auction.lua:15` | (sem gate — lista pública) |
| `vhub_garage:reqImpound` | `E.REQ_IMPOUND` | (nenhum) | `client/init.lua:215`; `client/zones.lua:133` | `server/impound.lua:15` | `Core:getCharId(src)` |
| `vhub_garage:actSpawn` | `E.ACT_SPAWN` | `plate`, `garagem_id` | `client/init.lua:99` | `server/garage.lua:71` | `Core:getCharId` + `Core.hasKeyItem` + `Core:authorized` + proximidade server-side |
| `vhub_garage:actStore` | `E.ACT_STORE` | `plate`, `garagem_id`, `payload` (customization/locked/fuel/health/damage/position) | `client/init.lua:115` | `server/garage.lua:157` | mesma cadeia + validação de entidade por placa no raio da garagem |
| `vhub_garage:actBuy` | `E.ACT_BUY` | `model`, `placa_custom` (string vazia se nenhuma), `conc_id` | `client/init.lua:121` | `server/dealership.lua:17` | delega a `vhub_conce:buy` |
| `vhub_garage:actSellShop` | `E.ACT_SELL_SHOP` | `plate` | `client/init.lua:127` | `server/dealership.lua:37` | delega a `vhub_conce:sellToShop` |
| `vhub_garage:actTestdrive` | `E.ACT_TESTDRIVE` | `model`, `conc_id` | `client/init.lua:132` | `server/dealership.lua:50` | delega a `vhub_conce:testDrive` |
| `vhub_garage:actRent` | `E.ACT_RENT` | `model`, `conc_id`, `horas` | `client/init.lua:137` | `server/rental.lua:15` | `Core:getCharId` + `Core.pay` + tipo aceito pela conc |
| `vhub_garage:actAuctionNew` | `E.ACT_AUCTION_NEW` | `plate`, `min_bid`, `buyout`, `duracao_min` | `client/init.lua:143` | `server/auction.lua:48` | delega a `vhub_ferinha:newAuction` |
| `vhub_garage:actAuctionBid` | `E.ACT_AUCTION_BID` | `auction_id`, `amount` | `client/init.lua:149` | `server/auction.lua:61` | delega a `vhub_ferinha:bid` |
| `vhub_garage:actAuctionCancel` | `E.ACT_AUCTION_CANC` | `auction_id` | (não emitido do client — admin via NUI ou console) | `server/auction.lua:74` | `Core.hasPerm(src, CFG.perms.auction_admin)` |
| `vhub_garage:actImpoundPay` | `E.ACT_IMPOUND_PAY` | `plate` | `client/init.lua:154` | `server/impound.lua:85` | `Core:getCharId` + `v.char_id == cid` + `v.status == 'impound'` + `Core.pay(fee)` |
| `vhub_garage:actImpoundPut` | `E.ACT_IMPOUND_PUT` | `plate`, `reason`, `fee_extra` | (admin via NUI ou comando) | `server/impound.lua:53` | `Core.hasPerm(src, CFG.perms.impound_admin)` |
| `vhub_garage:actIpvaPay` | `E.ACT_IPVA_PAY` | `plate` | `client/init.lua:159` | `server/ipva.lua:12` | `Core:getCharId` + `v.char_id == cid` + `Core.pay` |
| `vhub_garage:actRepair` | `E.ACT_REPAIR` | `plate` | `client/init.lua:164` | `server/maintenance.lua:45` | `Core:authorized` + `Core.pay(custo)` |
| `vhub_garage:actCloneKey` | `E.ACT_CLONE_KEY` | `plate` | `client/init.lua:169` | `server/garage.lua:375` | `v.char_id == cid` + `Core.payWallet(clone_chave_taxa)` |
| `vhub_garage:actLendKey` | `E.ACT_LEND_KEY` | `plate`, `target_src`, `dias` | `client/init.lua:174` | `server/garage.lua:319` | `v.char_id == cid` + `Core.giveKeyItem(target)` |
| `vhub_garage:actRevokeKey` | `E.ACT_REVOKE_KEY` | `plate`, `target_char_id` | `client/init.lua:181` | `server/garage.lua:350` | `v.char_id == cid` |
| `vhub_garage:actTransfer` | `E.ACT_TRANSFER` | `plate`, `target_src`, `valor` | `client/init.lua:188` | `server/garage.lua:238` | lock pessimista por placa + saga com compensação (ver §7) |
| `vhub_garage:reportState` | `E.REPORT_STATE` | `plate`, `payload` (position, locked, customization) | `client/vehicles.lua:379` (a cada 30s) | `server/maintenance.lua:16` | `Core:getCharId` + `Core.hasKeyItem` |

### 4.3 Eventos institucionais do CORE consumidos

| Evento | Lado | Quem ouve (garage) | Ação |
|---|---|---|---|
| `vHub:characterLoad` | servidor → servidor | `server/init.lua:115` | `Core:setSession(src, user)` |
| `vHub:playerSpawn` | servidor → servidor | `server/init.lua:119` | `Core:setSession` + `TriggerClientEvent(E.SETUP, src, buildSetup())` |
| `playerDropped` | servidor | `server/init.lua:124`; `server/garage.lua:31` | `Core:dropSession(src)` + limpeza de locks de transferência órfãos |

### 4.4 NUI callbacks (Lua → JS via `RegisterNUICallback`)

Localização: `client/init.lua:85-192`. Todos devolvem `cb({ ok = true })`.

| Callback | Payload recebido | Ação |
|---|---|---|
| `close` | (nenhum) | `closeNui()` |
| `spawn` | `{ plate }` | `TriggerServerEvent(E.ACT_SPAWN, plate, currentGarageId())` |
| `store` | `{ plate }` | Coleta estado via `'vhub_garage:collectClientState'` e envia `E.ACT_STORE` |
| `buy` | `{ model, plate, conc_id }` | `E.ACT_BUY` (plate é string vazia se não custom) |
| `sellShop` | `{ plate }` | `E.ACT_SELL_SHOP` |
| `testDrive` | `{ model, conc_id }` | `E.ACT_TESTDRIVE` |
| `rent` | `{ model, conc_id, horas }` | `E.ACT_RENT` |
| `auctionNew` | `{ plate, min_bid, buyout, dur_min }` | `E.ACT_AUCTION_NEW` |
| `auctionBid` | `{ id, amount }` | `E.ACT_AUCTION_BID` |
| `impoundPay` | `{ plate }` | `E.ACT_IMPOUND_PAY` |
| `ipvaPay` | `{ plate }` | `E.ACT_IPVA_PAY` |
| `repair` | `{ plate }` | `E.ACT_REPAIR` |
| `cloneKey` | `{ plate }` | `E.ACT_CLONE_KEY` |
| `lendKey` | `{ plate, target_src, dias }` | `E.ACT_LEND_KEY` |
| `revokeKey` | `{ plate, target_char }` | `E.ACT_REVOKE_KEY` |
| `transfer` | `{ plate, target_src, valor }` | `E.ACT_TRANSFER` |

### 4.5 Eventos internos do cliente (`TriggerEvent` — não-net)

| Evento | Quem dispara | Quem ouve |
|---|---|---|
| `vhub_garage:setupReady` | `client/init.lua:35` | `client/zones.lua:54` (cria blips) |
| `vhub_garage:zonaTrocou` | `client/zones.lua:93` | (não há handler visível — placeholder p/ hooks futuros) |
| `vhub_garage:collectClientState` | `client/init.lua:114` (com callback) | `client/vehicles.lua:313` (devolve snapshot por callback param) |

### 4.6 Eventos do `vhub_legacyfuel`

| Evento | Lado | Constante | Payload |
|---|---|---|---|
| `vrp_legacyfuel:pagamento` | client → server | — | `(price, galao, vehicle_netid, fuel, fuel2)` |
| `vrp_legacyfuel:setFuel` | client → server | — | `(target, qty)` onde `target` é netid (number) ou placa (string) |
| `vrp_legacyfuel:galao` | server → client | — | (nenhum) — entrega jerrycan (arma `883325847`) |
| `vrp_legacyfuel:insuficiente` | server → client | — | `(netid, fuel)` — reverte fuel ao valor pré-tentativa |
| `syncfuel` | server → client (-1) | — | `(netid, fuel)` — sync de fuel entre todos |
| `100fuel`/`90fuel`/`80fuel`/`70fuel`/`60fuel`/`50fuel`/`40fuel`/`20fuel`/`0fuel` | server → client | — | `(index, vehicle, fuel)` — **handlers vestigiais** (provavelmente não emitidos; `GetPlayersLastVehicle()` em vez de netid) |
| `fuel:startFuelUpTick` | client local | — | `(pumpObject, ped, vehicle)` — iniciado por `fuel:refuelFromPump` |
| `fuel:refuelFromPump` | client local | — | `(pumpObject, ped, vehicle)` — iniciado por [E] na bomba |
| `vHub:notify` | server → client | (CORE) | `(src, kind, msg)` — usado pelo `legacyfuel` para feedback |

> ⚠️ **Convenção obsoleta:** os eventos `vrp_legacyfuel:*` mantêm o prefixo `vrp_` mesmo no projeto `vhub_*` — é legado do fork original. Há uma inconsistência semântica: o recurso se chama `vhub_legacyfuel` mas os eventos ainda são `vrp_legacyfuel:*`.

---

## 5. Callbacks (lib callback / ox_lib)

**Nenhum callback `lib.callback` ou `ox_lib` é usado** em qualquer um dos dois resources.

O padrão adotado pelo vHub é **eventos + Promise interna** (`promise.new()` + `Citizen.Await`) em exports server-side que precisam retornar valor (ver §3 — `adminStats`, `adminListVehicles`, etc.). No client, o padrão é **RegisterNUICallback** ( FiveM nativo) com callback param.

---

## 6. NUI Bridge

### 6.1 Padrão geral

- **`ui_page`:** `nui/index.html`
- **`files`:** index.html, css/style.css, 6 JS (app, sand, garage, dealership, auction, impound), 2 PNG (bg, logo)
- **Fontes externas:** Google Fonts (Barlow Condensed, Inter) + Font Awesome kit
- **Foco:** `SetNuiFocus(true, true)` ao abrir, `SetNuiFocus(false, false)` ao fechar (em `client/init.lua:51-62`)

### 6.2 Mensagens Lua → JS (`SendNUIMessage`)

Estrutura: `{ action = <string>, data = <payload> }`. Centralizado em `client/init.lua:51-77`.

| `action` (constante `VHubGarage.UI.*`) | Quando | `data` |
|---|---|---|
| `openGarage` | `E.OPEN_UI` com `view == 'openGarage'` | `{ vehicles: [snap], types: ['car',...] }` |
| `openDealership` | idem | `{ conc: { id, label }, catalog: [...], cfg: { taxa_placa, fator_revenda, fator_test, test_seg, fator_aluguel, aluguel_h } }` |
| `openAuction` | idem | `{ auctions: [...], cfg: { fee, dur_min, increment } }` |
| `openImpound` | idem | `{ items: [...], admin: bool, cfg: { taxa_base, taxa_porc } }` |
| `close` | `closeNui()` ou `E.CLOSE_UI` | (nenhum) |
| `refresh` | (não emitido — placeholder) | payload |
| `notify` | `E.OPEN_UI` com `view == 'notify'` | `{ kind, text?, ttl? }` — kind `buy_ok` envia `{ plate, model, total }` |

### 6.3 Mensagens JS → Lua (`fetch POST` + `RegisterNUICallback`)

Padrão do `app.js:10-19`:

```js
App.post = async (callback, data = {}) => {
  const resp = await fetch(`https://vhub_garage/${callback}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data),
  });
  return await resp.json().catch(() => ({}));
};
```

Endpoints (cada um casa com `RegisterNUICallback` em `client/init.lua`):

```
POST https://vhub_garage/close
POST https://vhub_garage/spawn       { plate }
POST https://vhub_garage/store       { plate }
POST https://vhub_garage/buy         { model, plate, conc_id }
POST https://vhub_garage/sellShop    { plate }
POST https://vhub_garage/testDrive   { model, conc_id }
POST https://vhub_garage/rent        { model, conc_id, horas }
POST https://vhub_garage/auctionNew  { plate, min_bid, buyout, dur_min }
POST https://vhub_garage/auctionBid  { id, amount }
POST https://vhub_garage/impoundPay  { plate }
POST https://vhub_garage/ipvaPay     { plate }
POST https://vhub_garage/repair      { plate }
POST https://vhub_garage/cloneKey    { plate }
POST https://vhub_garage/lendKey     { plate, target_src, dias }
POST https://vhub_garage/revokeKey   { plate, target_char }
POST https://vhub_garage/transfer    { plate, target_src, valor }
```

> **Observação:** o nome do resource (`vhub_garage`) está hardcoded em `app.js:5` como `App.resName`. Se o resource for renomeado, a NUI quebra.

### 6.4 Helpers da NUI

| Helper | Definido em | Função |
|---|---|---|
| `App.toast(msg, type, ttl)` | `app.js:24` | Toast flutuante com borda colorida (ok=verde, err=vermelho, info=dourado) |
| `App.modal({title, html, text, okText, cancelText})` → `Promise<{ok, fields}>` | `app.js:41` | Modal universal; `data-field` em inputs vira `fields` |
| `App.show(viewId)` | `app.js:63` | Mostra view + ativa canvas de areia |
| `App.hideAll()` | `app.js:69` | Esconde tudo + para areia |
| `App.imgFor(model)` | `app.js:116` | URL `https://docs.fivem.net/vehicles/${model}.webp` |
| `App.fmtMoney(n)` / `App.fmtDate(ts)` / `App.fmtDur(s)` | `app.js:122-131` | Formatadores pt-BR |
| `window.vhubSand.start()/stop()` | `sand.js` | Canvas com 40 grãos dourados (requestAnimationFrame; idle 0ms quando parado) |

### 6.5 Comandos de cliente

| Comando | Condição | Ação |
|---|---|---|
| `/garagem` | `state.zona.kind == 'garage'` | `E.REQ_LIST` |
| `/concessionaria` | `state.zona.kind == 'dealer'` | `E.REQ_CATALOG, z.id` |
| `/leilao` | `state.zona.kind == 'auction'` | `E.REQ_AUCTIONS` |
| `/patio` | `state.zona.kind == 'impound'` | `E.REQ_IMPOUND` |

> **UX:** o comando só funciona se o player estiver dentro da zona correspondente. A detecção de zona roda a 500ms quando pronto (`client/zones.lua:84-97`). Dentro da zona, frame loop ativo desenha marker + texto `[E] <label>` e ouve `IsControlJustReleased(0, 38)` (tecla E).

---

## 7. Fluxos Principais

### 7.1 Spawn de veículo da garagem (`store → recover` → na verdade `garage → out`)

1. **Cliente** entra na zona `garage` (`client/zones.lua:60-64` → `kind='garage'`).
2. Pressiona **[E]** → `TriggerServerEvent(E.REQ_LIST)` (`client/zones.lua:130`).
3. **Servidor** `E.REQ_LIST` (`server/init.lua:131-164`):
   - `Core:getCharId(src)` gate.
   - Cria thread; faz **self-heal de chaves-item**: para cada veículo em `SQL:listByOwner(cid)` sem chave-item, entrega uma (`Core.giveKeyItem`).
   - Lista **POR CHAVE-ITEM** no inventário: `exports.vhub_inventory:getVehicleKeys(src)` — quem tem a chave vê/opera.
   - Para cada placa, busca `SQL:getVehicle(p)` e monta `Core:vehicleSnapshot(v)` + `role = 'owner'|'key'`.
   - `TriggerClientEvent(E.OPEN_UI, src, { view = 'openGarage', payload = { vehicles, types } })`.
4. **Cliente** `E.OPEN_UI` (`client/init.lua:68`) → `openNui({ action = 'openGarage', data = payload })`.
5. **NUI** `app.js:89-91` → `App.views.garage.render(data)` (`garage.js:166`) → renderiza lista + detalhe com botões **Spawnar / Estacionar / Reparar / Pagar IPVA / Clonar / Emprestar / Transferir / Vender**.
6. Jogador clica **Spawnar** → `App.post('spawn', { plate })` → `RegisterNUICallback('spawn')` (`client/init.lua:95`) → `TriggerServerEvent(E.ACT_SPAWN, plate, currentGarageId())`.
7. **Servidor** `E.ACT_SPAWN` (`server/garage.lua:71-152`):
   - `Core:getCharId(src)`, `U.normalizePlate`, `getGaragem(id)`.
   - **Validações em cadeia:**
     - `SQL:getVehicle(p)` existe
     - `Core.hasKeyItem(src, p)` (chave-item física)
     - `Core:authorized(src, p)` (delega a `vhub_conce:canOperate`)
     - `garagemAceita(g, v.vtype)` (tipo suportado pela garagem)
     - **Proximidade server-side**: `GetEntityCoords(GetPlayerPed(src))` vs `g.coord`, raio `g.raio + 3.0` — anti-cheat (IT.4 / Void-Zero)
     - `v.status` não é `impound` nem `auction`
     - `ipvaOk(v)` (IPVA em dia)
   - **Force-out:** se `v.status == 'out'`, cobra `CFG.taxa_force_out` (R$ 50) via `Core.payWallet`.
   - **Anti-dupe server-side:** itera `GetAllVehicles()`, apaga qualquer entidade com a mesma placa antes de spawnar.
   - `SQL:updateStatus(p, 'out')` + `SQL:updatePosition(p, ...)` + `Core:log(p, 'spawn', cid, {garagem})`.
   - Lê prontuário via `exports.vhub_conce:getVehicleState(p)` (fallback para coluna legada `v.customization` se prontuário não existir).
   - `TriggerClientEvent(E.DO_SPAWN, src, snapshot, pos)`.
8. **Cliente** `E.DO_SPAWN` (`client/vehicles.lua:155-158`) → `spawnVehicle(snap, pos, true)` em thread:
   - Apaga duplicata local + `scanAndDeleteByPlate(snap.plate)`.
   - `loadModel(snap.model)` (RequestModel com timeout 5s).
   - `CreateVehicle(hash, x, y, z+0.5, h, true, false)` — `true` = networked, `false` = não dinâmico.
   - `SetVehicleNumberPlateText(veh, snap.plate)` (identificador único; **DecorSetString foi removido do FiveM**).
   - `placeOnSurface(veh, snap.surface)` — `ground`/`water`/`pad`/`runway`.
   - `SetEntityAsMissionEntity(veh, true, true)` + `SetVehicleHasBeenOwnedByPlayer(veh, true)`.
   - `applyCustomization(veh, snap.customization)` — aplica cores, mods, neons, xenon, etc.
   - `applyPhysicalState(veh, snap.state)` — **CRÍTICO:** `+ 0.0` força subtipo FLOAT em Lua 5.4 (inteiro do msgpack é bit-reinterpretado como float: `1000 → 1.4e-42` = motor/fuel zerados). Aplica `SetVehicleFuelLevel`, `SetVehicleEngineHealth`, `SetVehicleBodyHealth`, quebra portas/janelas/pneus.
   - Trava portas se `snap.locked`.
   - `SetPedIntoVehicle(PlayerPedId(), veh, -1)` (entra como motorista).
   - `state.veiculos[plate] = veh`.

### 7.2 Guardar veículo na garagem (`out → garage`)

1. Jogador entra na zona `garage` com veículo próximo.
2. **[E]** ou clica **Estacionar** no detalhe (se a NUI estiver aberta) ou no botão `#g-store` do header.
3. `App.post('store', { plate })` → `RegisterNUICallback('store')` (`client/init.lua:108`):
   - `currentGarageId()` resolve a garagem da zona atual.
   - `TriggerEvent('vhub_garage:collectClientState', plate, function(s) payload = s end)` — handler em `client/vehicles.lua:313` coleta:
     - `customization = collectCustomization(veh)` (cores, mods 0..49, neons 0..3, xenon, turbo, smoke, livery, custom RGB se flag on)
     - `locked = GetVehicleDoorLockStatus(veh) >= 2`
     - `position = { x, y, z, h }` via `GetEntityCoords(veh, true)`
     - `fuel = GetVehicleFuelLevel(veh)`
     - `engine_health = GetVehicleEngineHealth(veh)`
     - `body_health = GetVehicleBodyHealth(veh)`
     - `damage = { doors=[0..5], windows=[0..7] com bone-check, tyres=[0..7], tyres_rim=[0..7] }` (só se `GetVehicleTyresCanBurst`)
   - Se handle stale, re-resolve via `findByPlate(plate)` (migração de ownership/cull).
   - `TriggerServerEvent(E.ACT_STORE, plate, g, payload or {})`.
4. **Servidor** `E.ACT_STORE` (`server/garage.lua:157-233`):
   - Cadeia de validação igual à do SPAWN (chave-item + autorização + tipo aceito + proximidade do PED).
   - **Proximidade do VEÍCULO (server-authoritative, OneSync):** itera `GetAllVehicles()`, encontra a entidade com a placa, valida `#(GetEntityCoords(ent) - g.coord) <= raio`. Se a placa existe mas fora do raio → mensagem específica; se nem a placa existe → outra mensagem. **Dupla stale/legítimo não veta o legítimo.**
   - **ORDEM IMPORTA:** `SQL:updateStatus(p, 'garage')` **PRIMEIRO** — telemetria pós-store é rejeitada pelo escritor (`vhub_conce:saveVehicleState` só aceita `status='out'`).
   - `Core:log(p, 'store', cid, { garagem })`.
   - Se `payload` é table:
     - `U.sanitizeCustomization(payload.customization)` → whitelist de 13 chaves (`colours, extra_colours, plate_index, wheel_type, window_tint, livery, turbo, smoke, xenon, mods, neons, neon_colour, model`) + cap de 8192 bytes JSON → `SQL:updateCustomization(p, jenc(cust), locked)`.
     - `exports.vhub_conce:saveVehicleState(p, { fuel, engine_health, body_health, damage }, 'store')` (com `finiteNum` clamp em cada campo).
   - **Despawn autoritativo server-side:** `if DoesEntityExist(vent) then DeleteEntity(vent) end` (anti-dupe — o servidor deleta a entidade validada).
   - `TriggerClientEvent(E.DO_DESPAWN, src, p)` (limpa mapa local e restos).
   - `Core.notify(src, 'Veículo ${p} guardado.')`.

### 7.3 Veículo vai para pátio (impound)

Caminhos possíveis:

#### A) Admin/Polícia via NUI ou comando (perm `CFG.perms.impound_admin = 'police.patio'`)
- Dispara `E.ACT_IMPOUND_PUT` com `(plate, reason, fee_extra)`.
- `server/impound.lua:53-80`:
  - `Core.hasPerm(src, 'police.patio')` gate.
  - `SQL:getVehicle(p)`, rejeita se já está `impound`.
  - **Calcula fee:** `CFG.patio_taxa + floor(preco * CFG.patio_taxa_porcent)` + `fee_extra` admin (default: R$ 500 + 5% do preço).
  - `SQL:updateStatus(p, 'impound')` + `SQL:impoundPut(p, reason, fee, char_id_do_admin)` (INSERT em `vhub_impound`).
  - `Core:log(p, 'impound_put', ...)`.
  - `TriggerClientEvent(E.DO_DESPAWN, -1, p)` — broadcast global (despawna em todos os clientes).
  - `Core.notify(src, '${p} enviado ao pátio (R$ ${fee}).')`.

#### B) Via API externa (outro resource, ex.: `vhub_lspdtool`)
- Export `impoundVehicle(plate, reason, fee_extra)` em `server/impound.lua:115-131`.
- **Sem validação de perm** (o gate é responsabilidade do caller) — **PONTO DE ATENÇÃO** (ver §10).
- Mesma lógica de fee/cálculo + log `impound_put_api`.

#### C) Boot-scan (IT.3 / Void-Zero)
- Em `server/init.lua:89-100`: **só roda em BOOT REAL** (`#GetPlayers() == 0`); em restart com players online, NÃO recolhe (seria roubo de carro — entidades ainda existem).
- Para cada `SQL:listByStatus('out')`:
  - Se `CFG.patio_boot_destino == 'garage'` → `SQL:updateStatus(p, 'garage')` (devolução grátis).
  - Senão (`'impound'` default) → `SQL:updateStatus(p, 'impound')` + `SQL:impoundPut(p, 'recolhido (queda do servidor)', CFG.patio_taxa, nil)`.
  - `Core:log(p, 'boot_scan', nil, { destino })`.

### 7.4 Recuperar do pátio (custo, validação)

1. Jogador entra na zona `impound` (`patio_dpdp` em `CFG.patio_local`).
2. **[E]** → `E.REQ_IMPOUND` (`client/zones.lua:133`).
3. `server/impound.lua:15-48`:
   - `Core:getCharId(src)` gate.
   - **Admin** (`Core.hasPerm(src, 'police.patio')`) vê lista completa via `SQL:impoundList()` (JOIN com `vhub_vehicles` para `model/vtype`).
   - **Comum** vê só seus: itera `SQL:listByStatus('impound')`, filtra `v.char_id == cid`, busca `SQL:impoundGetActive(v.plate)` (última apreensão não liberada).
   - `TriggerClientEvent(E.OPEN_UI, src, { view='openImpound', payload={ items, admin, cfg } })`.
4. NUI `impound.js` renderiza cards com **Motivo / Apreendido em / Fee** + botão **Liberar**.
5. Click → `App.modal('Liberar Veículo')` confirmação → `App.post('impoundPay', { plate })` → `E.ACT_IMPOUND_PAY`.
6. `server/impound.lua:85-110`:
   - `Core:getCharId(src)` + `v.char_id == cid` (só dono paga).
   - `v.status == 'impound'` gate.
   - `imp = SQL:impoundGetActive(p)` (a apreensão ativa).
   - `Core.pay(src, imp.fee)` (carteira+banco via `tryFullPayment`); se falhar → notifica e aborta.
   - `SQL:impoundRelease(imp.id, cid)` (UPDATE `released_at = os.time(), released_by = cid`).
   - `SQL:updateStatus(p, 'garage')` (status volta para garage).
   - `Core:log(p, 'impound_release', cid, { id, fee })`.
   - `Core.notify(src, 'Veículo liberado.')`.
   - `TriggerClientEvent(E.RESCUE_DONE, src, p)`.
   - **Atenção:** o veículo vai para `status='garage'` mas NÃO é spawnado — o jogador precisa ir até uma garagem física e fazer o spawn normal.

### 7.5 Leilão de veículos abandonados

> **Nota:** o `vhub_garage` é apenas o frontend NUI + roteador. A lógica de leilão vive no `vhub_ferinha`.

1. Jogador entra na zona `auction` (definida em `vhub_ferinha:getZones()`, puxada no boot).
2. **[E]** → `E.REQ_AUCTIONS` (`client/zones.lua:132`).
3. `server/auction.lua:15-42`:
   - Lista via `exports.vhub_ferinha:listActiveAuctions()`.
   - Para cada leilão, busca `SQL:getVehicle(a.plate)` (proxy conce) e `VHubGarage.catalog[v.model]` para montar `nome` e `preco_ref`.
   - `TriggerClientEvent(E.OPEN_UI, src, { view='openAuction', payload={ auctions, cfg } })`.
4. NUI `auction.js`:
   - Renderiza cards com timer regressivo (atualizado a 1s via `setInterval`), lance atual, input para novo lance (mínimo = `current * (1 + cfg.increment)`), botão **Dar Lance**.
   - Botão **Novo Leilão** no header → modal com `plate, min_bid, buyout, dur_min`.
5. **Criar leilão:** `App.post('auctionNew', { ... })` → `E.ACT_AUCTION_NEW` → `server/auction.lua:48-55` → `exports.vhub_ferinha:newAuction(src, plate, min_bid, buyout, duracao_min)` (delega).
6. **Dar lance:** `App.post('auctionBid', { id, amount })` → `E.ACT_AUCTION_BID` → `exports.vhub_ferinha:bid(src, id, amount)` (delega).
7. **Cancelar (admin):** `E.ACT_AUCTION_CANC` → gate `Core.hasPerm(src, 'admin.garage')` → `exports.vhub_ferinha:cancelAuction(id, cid)`.
8. **Finalização automática:** via cron do `vhub_ferinha` (não no garage). Admin pode forçar via `adminFinalizeStaleAuctions` → `exports.vhub_ferinha:finalizeExpired()`.

### 7.6 Aluguel de veículos

1. Jogador entra na zona `dealer`, abre a NUI concessionária, seleciona modelo, clica **Alugar**.
2. Modal pede `horas` (1-168, default 24).
3. `App.post('rent', { model, conc_id, horas })` → `E.ACT_RENT` (`server/rental.lua:15-63`):
   - `Core:getCharId(src)` gate.
   - `VHubGarage.catalog[model]` precisa existir (cache do conce).
   - `Core:resolveConc(conc_id)` resolve a concessionária.
   - `horas` clamp 1-168 (default `CFG.aluguel_periodo_h = 24`).
   - Valida que o tipo do modelo é aceito pela concessionária (`conc.tipos`).
   - **Cálculo:** `total = floor(entry.preco * CFG.fator_aluguel * (horas / CFG.aluguel_periodo_h))` = 10% do preço por 24h.
   - `Core.pay(src, total)` (carteira+banco); se falhar → notifica.
   - **Placa nova aleatória:** `Core:newPlate(nil)` (formato "LLL DDDD", 60 tentativas; fallback `VH<timestamp%100000>`).
   - **Entrega chave-item:** `Core.giveKeyItem(src, plate)`; se inventário cheio → `Core.refund` + aborta.
   - **Cria veículo:** `SQL:createVehicle({ plate, model, vtype, category, char_id, status='garage' (não 'rental'!), customization, locked=false, purchase_price=0, purchase_at, rented_until=now+horas*3600, last_seen_at })`.
   - **Outorga chave lógica:** `SQL:grantKey(plate, cid, 'rental', cid, rented_until)`.
   - `Core:log(plate, 'rent_new', cid, { model, horas, total })`.
   - `Core.notify(src, 'Aluguel ativo até HH:MM DD/MM. Chave no inventário.')`.
4. **Cron de expiração (1x por minuto):** `server/rental.lua:69-89`:
   - `SELECT plate, char_id FROM vhub_vehicles WHERE rented_until IS NOT NULL AND rented_until <= now`.
   - Para cada: tira chave-item do dono se online, broadcast `DO_DESPAWN(-1, plate)`, `SQL:revokeKey(plate, cid, 'rental')`, `SQL:deleteVehicle(plate)` (prontuário morre junto), log `rent_expired`.

> **PONTO DE ATENÇÃO (ver §10):** o status do aluguel é `'garage'` (não `'rental'`) — o que marca o aluguel é a coluna `rented_until`. A coluna `status` enum **tem** `'rental'` mas o código nunca a usa para veículos alugados. Isso significa que `adminStats` conta `active_rental = SELECT COUNT(*) WHERE status = 'rental'` que **sempre retorna 0** — bug de relatório.

### 7.7 IPVA (cobrança, multa por atraso)

1. **Cálculo:** `valor = max(50, floor((entry.preco or 0) * CFG.ipva_porcentagem))` = 1% do preço, mínimo R$ 50 (`server/ipva.lua:23`).
2. **Bloqueio de spawn:** `ipvaOk(row)` em `server/garage.lua:63-66` — retorna `true` se `ipva_paid_until` é `NULL`/`0`, ou `>= os.time()`. Se vencido, o spawn é bloqueado com mensagem `'IPVA vencido. Quite antes de retirar o veículo.'`.
3. **Pagamento (jogador):**
   - `E.ACT_IPVA_PAY` ← NUI botão "Pagar IPVA" (ou "Renovar IPVA" se em dia).
   - `server/ipva.lua:12-35`:
     - `Core:getCharId` + `v.char_id == cid` gate.
     - `Core.pay(src, valor)`.
     - **Extensão:** `base = max(os.time(), v.ipva_paid_until or 0)` + `CFG.ipva_dias * 86400` (= +15 dias). Permite pagar adiantado.
     - `SQL:updateIpva(p, until_ts)`.
     - `Core:log(p, 'ipva_paid', cid, { valor, until_ts })`.
     - `Core.notify(src, 'IPVA pago. Válido até DD/MM/YYYY.')`.
4. **Inicialização:** veículos comprados recebem `ipva_paid_until = now + ipva_dias * 86400` em `adminGiveVehicle` (e também em `vhub_conce:buy`, presumivelmente).
5. **Multa por atraso:** **NÃO HÁ.** O IPVA vencido apenas bloqueia o spawn. Não há juros, multa, ou cobrança automática — apenas o bloqueio funcional.

### 7.8 Manutenção (degradação, custo)

> **Estado físico** (fuel/engine/body/damage/odometer) vive no **prontuário** (`vhub_vehicle_state`, escritor único = `vhub_conce`). O `vhub_garage` apenas:
> - Lê (`exports.vhub_conce:getVehicleState(p)`) para calcular custo de reparo.
> - Escreve (`exports.vhub_conce:saveVehicleState(p, {...}, 'store')`) no `store`.
> - Aplica reparo trusted (`exports.vhub_conce:repairVehicleState(p)`).

1. **Cálculo de custo** (`server/maintenance.lua:61-71`):
   - Lê `st = exports.vhub_conce:getVehicleState(p)` (fallback `engine=1000, body=1000`).
   - `dmg_eng = max(0, 1000 - st.engine_health)` — pontos de dano de motor.
   - `dmg_body = max(0, 1000 - st.body_health)` — pontos de dano de carroceria.
   - `preco = entry.preco or 0` (do catálogo).
   - `custo = floor(preco * (dmg_eng * CFG.reparo_taxa_engine + dmg_body * CFG.reparo_taxa_body))`.
     - `reparo_taxa_engine = 0.0015` (0,15% do preço por ponto de motor)
     - `reparo_taxa_body = 0.0008` (0,08% do preço por ponto de carroceria)
   - Exemplo: carro de R$ 100.000 com motor em 800 (200 de dano) e body em 700 (300 de dano): custo = 100000 * (200*0.0015 + 300*0.0008) = 100000 * (0.3 + 0.24) = R$ 54.000.
2. **Ação de reparo (jogador):**
   - `E.ACT_REPAIR` ← NUI botão "Reparar" na garagem.
   - `server/maintenance.lua:45-83`:
     - `Core:authorized(src, p)` (chave + dono/autorização).
     - Lê estado, calcula custo.
     - Se `custo <= 0` → "Veículo sem danos a reparar.".
     - `Core.pay(src, custo)`.
     - **Reparo trusted:** `exports.vhub_conce:repairVehicleState(p)` (eleva health + limpa dano no prontuário).
     - `TriggerClientEvent(E.DO_REPAIR, src, p)` — cliente conserta a entidade VIVA.
     - `Core:log(p, 'repair', cid, { custo, dmg_eng, dmg_body })`.
     - `Core.notify(src, 'Veículo reparado. R$ X cobrados.')`.
3. **Cliente `E.DO_REPAIR`** (`client/vehicles.lua:353-367`):
   - Resolve entidade por `state.veiculos[plate]` ou `findByPlate(plate)`.
   - `NetworkRequestControlOfEntity(veh)` com timeout 20 ticks.
   - `SetVehicleFixed(veh)` + `SetVehicleEngineHealth(veh, 1000.0)` + `SetVehicleBodyHealth(veh, 1000.0)` + `SetVehicleDirtLevel(veh, 0.0)`.
4. **Report periódico (não-crítico):** `client/vehicles.lua:372-388` roda a cada `CFG.report_intervalo_s = 30s` e envia `E.REPORT_STATE` para cada veículo em `state.veiculos`:
   - `position`, `locked` (não envia fuel/health — esses fluem pelo CORE via State Bags).
   - `server/maintenance.lua:16-39` valida, atualiza `position` (se `U.validCoords`) e `customization` (se `sanitizeCustomization`).

### 7.9 Abastecimento (legado — `vhub_legacyfuel`)

> **Importante:** o **consumo** de combustível NÃO vive aqui — vive no CORE. Este recurso só faz a bomba e o `/fuel`.

#### A) Bomba física (client `client.lua`)
1. Thread a cada 250ms (`client.lua:48-59`) procura a bomba mais próxima via `FindFirstObject/FindNextObject` em `Config.PumpModels` (7 hashes de modelos GTA). Se distância < 2.5m → `isNearPump = pumpObject`.
2. Thread principal (`client.lua:247-296`):
   - Se `isNearPump` e jogador **no veículo como motorista** → "SAIA DO VEÍCULO PARA ABASTECER".
   - Se fora do veículo e último veículo a < 2.5m:
     - Se arma equipada = jerrycan (`883325847`) → modo galão; se `GetAmmoInPedWeapon < 100` → "GALÃO VAZIO".
     - Se `GetVehicleFuelLevel(vehicle) < 99` → "PRESSIONE E PARA ABASTECER".
     - [E] → `isFueling = true` + `TriggerEvent('fuel:refuelFromPump', pumpObject, ped, vehicle)`.
   - Se `isNearPump` e sem veículo por perto → "PRESSIONE E PARA COMPRAR UM GALÃO DE GASOLINA" → [E] → `TriggerServerEvent('vrp_legacyfuel:pagamento', 300, true)` (galão custa R$ 300 fixo).
3. **`fuel:refuelFromPump`** (`client.lua:212-245`):
   - `TaskTurnPedToFaceEntity(ped, vehicle, 5000)`.
   - Carrega anim `timetable@gardener@filling_can` → `gar_ig_5_filling_can`.
   - `TriggerEvent('fuel:startFuelUpTick', ...)`.
   - Loop com `DisableControlAction` para as 20 keys em `Config.DisableKeys` (inclui 38=E, 23=F, etc.).
   - DrawText3Ds com tanque atual e "PRESSIONE E PARA CANCELAR".
   - Cancela se: [E] liberado, ou alguém entra no banco do motorista, ou bomba destruída.
   - Ao sair: `ClearPedTasks` + `RemoveAnimDict`.
4. **`fuel:startFuelUpTick`** (`client.lua:61-97`):
   - Captura `currentFuel = GetVehicleFuelLevel(vehicle)` e `currentFuel2` (valor inicial).
   - Loop while `isFueling`:
     - `oldFuel = DecorGetFloat(vehicle, Config.FuelDecor)` (decor `FUEL_LEVEL` registrado no boot).
     - `fuelToAdd = math.random(1,2) / 100.0` — 0.01 a 0.02 por tick (randomizado).
     - `extraCost = fuelToAdd / 0.1` — custo em "unidades" (1 ponto % = R$ 10 server-side).
     - Se galão (sem pumpObject): consome munição do jerrycan (`883325847`); se acabar → `isFueling = false`.
     - Se bomba: só soma.
     - Se `currentFuel > 100.0` → `isFueling = false`.
     - `currentCost += extraCost`.
     - `SetVehicleFuelLevel(vehicle, currentFuel)` + `DecorSetFloat(vehicle, FUELDecor, GetVehicleFuelLevel)`.
   - Ao sair, **só se for bomba** (não galão): `TriggerServerEvent('vrp_legacyfuel:pagamento', parseInt(currentCost), false, VehToNet(vehicle), GetVehicleFuelLevel(vehicle), currentFuel2)`.
   - `currentCost = 0.0`.

#### B) Pagamento + persistência (server `server.lua`)
- `vrp_legacyfuel:pagamento` (`server.lua:61-106`):
  - Se `galao=true`: preço clampado 1-100000, `safe_try_payment` (carteira+banco). Se OK → `vrp_legacyfuel:galao` (dá jerrycan) + notify. Se falha → notify negado. **Não persiste** — o abastecimento por galão entra no prontuário via telemetria do vehcontrol em até 15s.
  - Se `galao=false` (bomba):
    - `fuelFinal = finiteNum(fuel, 0, 100)` (clamp + rejeita NaN/±inf).
    - `plate = plateFromNetId(vehicle)` (fail-closed: se entidade não resolver, aborta).
    - **Delta server-side (anti-undercharge):** lê `exports.vhub_conce:getVehicleState(plate).fuel` (prontuário) como `base`; se prontuário não existe (carro de rua), usa `fuel2` (valor inicial reportado pelo client). `delta = max(0, fuelFinal - base)`. `preco = floor(delta * PRICE_PER_PCT + 0.5)` (= R$ 10 por ponto %).
    - `safe_try_payment(src, preco)`:
      - **OK:** se prontuário existe → `persistFuel(plate, fuelFinal)` via `exports.vhub_conce:saveVehicleState(plate, {fuel}, 'pump')`. `TriggerClientEvent('syncfuel', -1, netid, fuelFinal)` (broadcast). Notify sucesso.
      - **Falha:** `TriggerClientEvent('vrp_legacyfuel:insuficiente', src, netid, fuel2)` (reverte fuel ao valor pré-tentativa no client). Notify negado.

#### C) Admin `/fuel` (server `server.lua:113-150` + client `client.lua:329-358`)
- Client `/fuel [placa] <qtd>`:
  - Sem placa: pega `GetVehiclePedIsIn` → envia netid.
  - Com placa: envia placa como string.
  - `TriggerServerEvent('vrp_legacyfuel:setFuel', target, qty)`.
- Server `vrp_legacyfuel:setFuel`:
  - `is_admin(src)` = `uid == 1` OU `vhub:hasPerm(uid, 'panel')`.
  - `qty = finiteNum(qty, 0, 100)`.
  - Se `target` for número: `netid = target`, `plate = plateFromNetId(netid)`.
  - Se `target` for string: `plate = normPlate(target)`, busca entidade em `GetAllVehicles()` pela placa para achar netid.
  - `persistFuel(plate, qty)`.
  - `TriggerClientEvent('syncfuel', -1, netid, qty)` (se netid resolvido).
  - Notify sucesso.

---

## 8. Integração com CORE/vhub

### 8.1 Exports do CORE chamados

| Export | Lado | Quem chama | Quando |
|---|---|---|---|
| `exports.vhub:getUID(src)` | server | `vhub_legacyfuel/server.lua:49` | `is_admin(src)` |
| `exports.vhub:hasPerm(uid, 'panel')` | server | `vhub_legacyfuel/server.lua:52` | `is_admin(src)` |

> **Observação:** o `vhub_garage` **não chama exports do CORE diretamente** — todo o contato com o CORE é via eventos institucionais (`vHub:characterLoad`, `vHub:playerSpawn`, `playerDropped`) e via proxies (`vhub_conce`, `vhub_money`, `vhub_inventory`, `vhub_groups`, `vhub_ferinha`).

### 8.2 State Bags lidas/escritas

**Nenhuma State Bag** é lida ou escrita diretamente por `vhub_garage` ou `vhub_legacyfuel`. A única interação indireta:

- **Cliente `vhub_garage`** lê `GetVehicleFuelLevel(veh)` (nativa, não State Bag direta) ao coletar estado para `store`.
- **Cliente `vhub_legacyfuel`** lê/escreve `DecorSetFloat/DecorGetFloat` (decor `FUEL_LEVEL`) — **NÃO é State Bag**, é Decor (registry local + replicação nativa). O comentário em `client/vehicles.lua:14-16` menciona que `DecorSetString` foi removido do FiveM, mas `DecorSetFloat` ainda funciona.
- **CORE** mantém State Bags `vh_fuel` etc. (mencionado em `legacyfuel/client.lua:12-13` — "replica via State Bag `vh_fuel` lido pelo HUD") mas o `legacyfuel` não registra handler — só o HUD o consome.

### 8.3 Como o garage decide "veículo X está spawnado ou não"

**Decisão 100% baseada em `vhub_vehicles.status`:**

- `status='garage'` → veículo guardado, pode ser spawnado
- `status='out'` → veículo em uso (spawnado em algum lugar do mapa)
- `status='impound'` → apreendido, bloqueado até pagar
- `status='auction'` → em leilão, bloqueado
- `status='rental'` → aluguel (coluna enum existe mas NÃO é usada — ver §7.6)
- `status='sold'` → vendido

A "fonte de verdade" do status é a coluna SQL. **Não há** consulta a State Bags ou a entidades do mundo para decidir — quando o jogador spawna, o status vira `'out'`; quando guarda, vira `'garage'`. Se o servidor cair com veículo `'out'`, no boot-scan ele é recolhido para `'impound'` ou `'garage'` (decisão #25).

A coluna `position` (JSON) é a "última posição conhecida" — atualizada em 3 momentos: no `spawn` (server define posição inicial), no `store` (cliente envia), e no `reportState` (cliente reporta a cada 30s). Não é usada para decidir "spawnado ou não" — apenas para recuperação.

---

## 9. Configuração

### 9.1 `vhub_garage/shared/config.lua` — `VHubGarage.cfg`

| Chave | Default | Descrição |
|---|---|---|
| `taxa_force_out` | `50` | Custo em R$ para retirar veículo que está `'out'` (perdeu/esqueceu) |
| `taxa_placa_custom` | `2000` | Custo adicional ao comprar com placa personalizada |
| `fator_revenda_loja` | `0.60` | Venda para concessionária = 60% do preço |
| `fator_test_drive` | `0.01` | Test drive = 1% do preço |
| `test_drive_segundos` | `180` | Duração do test drive (3 min) |
| `test_drive_raio` | `300.0` | Raio máximo do test drive (m) |
| `fator_aluguel` | `0.10` | Aluguel = 10% do preço por período |
| `aluguel_periodo_h` | `24` | Período padrão de aluguel (h) |
| `taxa_leilao` | `100` | Fee de listagem (não-reembolsável) |
| `leilao_duracao_min` | `60` | Duração padrão de leilão (min) |
| `leilao_incremento` | `0.05` | Mínimo 5% acima do lance atual |
| `ipva_dias` | `15` | IPVA vence a cada 15 dias |
| `ipva_porcentagem` | `0.01` | 1% do preço do veículo |
| `patio_taxa` | `500` | Taxa base de liberação do pátio |
| `patio_taxa_porcent` | `0.05` | + 5% do preço do veículo |
| `patio_boot_scan` | `true` | Recolhe veículos `'out'` órfãos no boot real |
| `patio_boot_destino` | `'impound'` | `'impound'` (cobra taxa) \| `'garage'` (devolve grátis) |
| `reparo_taxa_engine` | `0.0015` | 0,15% do preço por ponto de dano de motor |
| `reparo_taxa_body` | `0.0008` | 0,08% do preço por ponto de dano de carroceria |
| `clone_chave_taxa` | `800` | Custo de clonar chave |
| `emprestar_dias` | `7` | Empréstimo expira em 7 dias (default) |
| `max_veiculos_player` | `25` | **Defesa contra alocador maligno — não enforcei em código visível** (ver §10) |
| `spawn_offset_carro` | `vec3(0.0, 5.0, 0.5)` | Offset de spawn (server-side, mesmo contexto) |
| `spawn_offset_moto` | `vec3(0.0, 3.0, 0.5)` | |
| `spawn_offset_boat` | `vec3(0.0, 8.0, 0.0)` | |
| `spawn_offset_plane` | `vec3(0.0, 25.0, 0.0)` | |
| `spawn_offset_heli` | `vec3(0.0, 0.0, 0.0)` | |
| `raio_guardar` | `5.0` | Raio para guardar veículo |
| `report_intervalo_s` | `30` | Cliente reporta posição/customização a cada 30s |
| `garagens` | (vetor de 6) | ls_centro, sandy, paleto, aero_ls, sandy_aero, marina_ls |
| `patio_local` | `{ id='patio_dpdp', coord=vec3(405.40,-1623.41,29.29), raio=8.0 }` | Pátio único |
| `perms.impound_admin` | `'police.patio'` | Permissão para apreender |
| `perms.auction_admin` | `'admin.garage'` | Permissão para cancelar leilão |
| `perms.stock_admin` | `'admin.garage'` | Permissão para mexer em estoque |

#### `garagens` (cada item)

```lua
{ id='ls_centro', label='Garagem Los Santos',
  coord=vec3(222.5119, -801.9008, 30.6713), h=118.0, raio=8.0,
  tipos={ 'car', 'bike' },
  blip={ sprite=357, color=5, scale=0.75 } }
```

6 garagens: `ls_centro` (car+bike), `sandy` (car+bike+truck), `paleto` (car+bike), `aero_ls` (plane+heli), `sandy_aero` (plane+heli), `marina_ls` (boat).

> **L-19 (cruzamento de fronteira):** `coord` é `vec3` no config; `h` é heading de saída. No setup, `flatZone` transforma `vec3` em `{x,y,z}` primitivos porque `vec3` não sobrevive ao msgpack do evento.

### 9.2 `vhub_legacyfuel/config.lua` — `Config`

| Chave | Default | Descrição |
|---|---|---|
| `Config.FuelDecor` | `"FUEL_LEVEL"` | Nome do Decor registrado para fuel |
| `Config.DisableKeys` | `{0,22,23,24,29,30,31,37,44,56,82,140,166,167,168,170,288,289,311,323}` | 20 controles desabilitados durante fuel |
| `Config.PumpModels` | (7 hashes) | `[-2007231801, 1339433404, 1694452750, 1933174915, -462817101, -469694731, -164877493]` |
| `Config.Classes` | (22 classes) | Multiplicador de consumo por classe (0.0 a 0.4) — **não usado** (consumo migrou para CORE) |
| `Config.FuelUsage` | (11 valores) | Multiplicador de consumo por velocidade — **não usado** |

> **PONTO DE ATENÇÃO:** `Config.Classes` e `Config.FuelUsage` são **vestigiais** — o comentário D1 RESOLVIDO em `client.lua:10-13` declara que o consumo migrou para o CORE. As tabelas continuam no config mas não são referenciadas em código. Limpeza pendente.

### 9.3 `vhub_legacyfuel/server.lua` — constantes hardcoded

| Constante | Valor | Descrição |
|---|---|---|
| `PRICE_PER_PCT` | `10` | R$ por ponto percentual de combustível (1 litro = R$ 10) |

---

## 10. Pontos de Atenção

### 10.1 Possíveis conflitos com `vhub_conce`

Há **sobreposição intencional** que pode causar confusão:

1. **Tabela `vhub_vehicles` escrita por ambos (em teoria):** O schema SQL está no `vhub_garage/sql/schema.sql`, mas **o escritor único é `vhub_conce`** desde a FASE 1. O `vhub_garage` é **apenas proxy** (`server/sql.lua:46-74`). Se um desenvolvedor desavisado adicionar um `INSERT INTO vhub_vehicles` direto no garage, **viola o contrato**. O comentário em `server/sql.lua:47-50` é explícito: *"PROXY -> vhub_conce: escritor único desde a FASE 1. O dado e a verdade vivem no vhub_conce; aqui apenas encaminhamos a chamada para manter os ~16 call-sites do garage inalterados ate a FASE 6."*

2. **Catálogo:** vive no `vhub_conce` (`shared/catalog.lua`); o `vhub_garage` só faz cache read-only via `exports.vhub_conce:getCatalog()` no boot. Mudar preço no garage **não tem efeito**.

3. **Zonas de concessionária:** vivem no `vhub_conce` (`getZones()`). Se uma zona for adicionada ao garage, **não funciona** — o PULL no boot sobrescreve.

4. **Backfills chamados pelo garage:** `backfillMirror`, `backfillOwnerKeys`, `backfillVehicleState`, `reconcileVehicleState` são todos do `vhub_conce`, mas chamados pelo `vhub_garage` no boot (`server/init.lua:67-73`) porque o `vhub_conce` carrega **antes** e `vhub_vehicles` ainda não existe. Se a ordem do manifest for alterada (ex.: `vhub_conce` depois do `vhub_garage`), os backfills quebram silenciosamente (estão em `pcall`).

5. **Decisão #25:** explicitamente移ou concessionária para o `vhub_conce` e leilão para o `vhub_ferinha`. Se um jogador, admin ou script tentar mexer nessas zonas via `vhub_garage`, não há endpoint.

### 10.2 Possíveis violações do `manual_dev_vhub.md`

Verificando contra o manual lido (`manual_dev_vhub.md:1-120`):

| Regra do manual | Status no `vhub_garage` | Status no `vhub_legacyfuel` |
|---|---|---|
| **Compat: none, sem shim vRP** | ✅ Sem shims vRP | ⚠️ **Nomes de eventos ainda `vrp_legacyfuel:*`** (legado do fork) |
| **Ordem fixa de carga** (`sql → core → init → features → exports`) | ✅ Exatamente esta ordem em `fxmanifest.lua:29-42` | N/A (1 arquivo server) |
| **Batch SQL atômico** (`BATCH_MAX=800`) | ⚠️ Não usa batch — queries unitárias via `oxmysql:scalar/execute/query` | N/A (só 2 queries) |
| **Schemas externos com FK ao core DEVEM usar `INT UNSIGNED`** | ✅ `char_id INT UNSIGNED`, `seller_id INT UNSIGNED`, `bidder_id INT UNSIGNED`, `impounded_by INT UNSIGNED`, `actor_id INT UNSIGNED`, `granted_by INT UNSIGNED` — todos UNSIGNED | N/A |
| **Proibido `INSERT/UPDATE/DELETE` em `vh_users`, `vh_characters`, `vh_vehicles`, `vh_*_data`** | ⚠️ **Violação:** `admin.lua` faz `SELECT * FROM vhub_vehicles WHERE char_id NOT IN (SELECT id FROM vh_characters)` (apenas leitura, OK) mas também `SELECT * FROM vhub_auctions`, `SELECT * FROM vhub_impound`, `SELECT * FROM vhub_vehicle_log` diretamente. As queries `INSERT INTO vhub_impound` e `INSERT INTO vhub_vehicle_log` também são diretas (não-proxied), o que é **OK** porque são tabelas do próprio garage. Mas a leitura direta de `vhub_auctions` em `admin.lua:122-132` pode conflitar com `vhub_ferinha` (escritor do leilão). | ✅ Não escreve em tabelas do core |
| **`exports.vhub:commitVehicleState`** (único caminho p/ terceiros persistir físico) | ⚠️ **Possível violação:** o garage chama `exports.vhub_conce:saveVehicleState(p, {...}, 'store')` em `server/garage.lua:217`, não `exports.vhub:commitVehicleState`. Mas o PRONTUÁRIO (vhub_conce) parece ser a via **preferencial** pós-PRONTUÁRIO (comentário em `server.lua:5-8` do legacyfuel: "Sprint PRONTUÁRIO: os pokes na VRAM do CORE foram removidos (exports do FiveM devolvem CÓPIA serializada — mutar vd.state era no-op real). Persistência agora passa pelo escritor único: exports.vhub_conce:saveVehicleState"). Precisa confirmar com o manual se `commitVehicleState` (CORE) e `saveVehicleState` (conce) são equivalentes ou competem. | ⚠️ Mesma questão — chama `vhub_conce:saveVehicleState` |
| **Tabelas SQL com prefixo `vhub_<dom>_*`** | ✅ `vhub_vehicles`, `vhub_vehicle_keys`, `vhub_auctions`, `vhub_auction_bids`, `vhub_impound`, `vhub_dealership_stock`, `vhub_vehicle_log` | N/A (sem tabelas) |
| **State Bag em vez de `TriggerClientEvent(-1)`** | ⚠️ **Violação:** `DO_DESPAWN` é broadcast via `TriggerClientEvent(E.DO_DESPAWN, -1, p)` em `server/impound.lua:77`, `server/rental.lua:82`, `server/admin.lua:246,390`, `server/maintenance.lua:79` (este último só para `src`, OK). O broadcast `-1` para despawn é o padrão adotado, mas tecnicamente viola a regra "Estado de entidade para todos = State Bag, **nunca** `TriggerClientEvent(-1)`." | ⚠️ `TriggerClientEvent('syncfuel', -1, ...)` em `server.lua:99,147` — mesma violação |
| **Replay-safe por padrão (L-17)** | ✅ `server/init.lua:115-122` replay-safe (`characterLoad`/`playerSpawn` setam sessão e re-enviam setup) | N/A |
| **Deletar é entrega (L-15)** | ✅ Todos os arquivos `.lua` do `fxmanifest.lua` existem no disco (verificado via LS); `shared/types.lua` e `shared/utils.lua` estão ambos no manifest | N/A |
| **Anti-fantasma em `shared/events.lua` (tabela global, não return module)** | ✅ `VHubGarage = VHubGarage or {}; VHubGarage.E = VHubGarage.E or {}` | N/A |
| **Falha graciosa (`pcall` nas fronteiras)** | ✅ `pcall` em todos os exports externos (`Core.pay`, `Core.hasKeyItem`, `vhub_conce:*`, `vhub_ferinha:*`); o `safe(callfn)` helper em `core.lua:51-53` padroniza | ✅ `pcall(function() return exports.vhub_money:tryPayment(...) end)` e similares |
| **Saídas em PT-BR** (comentários/logs/NUI) | ✅ Tudo em PT-BR (incluindo notificações no feedpost) | ⚠️ Comentários em PT-BR mas **eventos em prefixo `vrp_`** (não-vhub) |

### 10.3 Áreas não documentadas

1. **`max_veiculos_player = 25`** está no config mas **não é enforcei** em nenhum código visível (busca por `max_veiculos` retorna só o config). A defesa contra "alocador maligno" (player comprando infinitos veículos) **não existe** — o limite está documentado mas não implementado.

2. **Eventos `E.SPAWN_OUT` e `E.UPDATE_AUCTION`** são declarados em `shared/events.lua` mas **não são emitidos** em nenhum código server analisado. Provavelmente são placeholders para funcionalidade futura (re-spawn de veículos que estavam fora; broadcast de leilão atualizado em tempo real).

3. **Evento `E.RESCUE_DONE`** é emitido em `server/impound.lua:108` mas **não há handler client visível**. Provavelmente deveria fechar a NUI de pátio ou dar feedback visual, mas está como no-op.

4. **Evento `E.CLOSE_UI`** é declarado mas **não emitido** — `closeNui()` é chamado diretamente no client via `RegisterNUICallback('close')`. O evento server→client existe mas ninguém dispara.

5. **`Config.Classes` e `Config.FuelUsage`** no `vhub_legacyfuel/config.lua` são vestigiais — o consumo migrou para o CORE. Continuam no config mas não são referenciados.

6. **Eventos `100fuel`, `90fuel`, ..., `0fuel`** no `client.lua` são 9 handlers vestigiais que usam `GetPlayersLastVehicle()` (não netid). Provavelmente herança do fork original; **nenhum server code os emite**.

7. **Status `'rental'` na coluna `vhub_vehicles.status`** é declarado no ENUM mas **nunca escrito** — veículos alugados recebem `status='garage'` e marcação via `rented_until`. Isso causa o `adminStats` reportar `active_rental = 0` sempre.

8. **Status `'sold'`** também é declarado mas **nunca escrito** em código visível — provavelmente seria setado pela `vhub_ferinha` quando um leilão finaliza com venda, mas não há confirmação neste resource.

9. **`forceImpound` em `server/exports.lua:63-66`** chama `exports[GetCurrentResourceName()]:impoundVehicle(...)` — padrão incomum de auto-export. Funciona, mas é frágil (se o resource for renomeado, quebra).

10. **Lock pessimista de transferência** (`TxLock` em `server/garage.lua:18-36`): serializa transfers por placa **dentro do processo**. Se houver múltiplas instâncias do servidor (multi-instance setup mencionado no manual), o lock não protege contra dupe cross-instance. O comentário reconhece: *"process-local (só serializa NESTE processo, igual ao ferinha #19)"*.

11. **Compensação da saga de transferência** (`server/garage.lua:252-313`): a ordem é `pay → transferOwner → giveKeyItem`. Se `giveKeyItem` falha, a compensação é: `giveKeyItem(src)` (volta chave ao vendedor) + `transferOwner(p, cid)` (volta posse) + `refund(target)` + `refund(src, -valor)` (estorna). Há um `if not ok` final que **não faz compensação cega** (porque a fase é desconhecida em caso de erro real) — apenas loga `transfer_error`. **Comportamento correto** segundo o padrão L-09, mas merece teste de carga.

12. **`/fuel` admin do `legacyfuel`** confunde `target` como número (netid) OU string (placa) — se o jogador digitar `/fuel 50 100`, o `50` vira placa (string) e o `100` vira qty, então o parser só aceita 2 args se o primeiro for não-numérico. **Bug sutil:** `/fuel 50` (intent: por 50% no veículo atual) funciona porque `target` vira `VehToNet(veh)` (número grande), mas `/fuel ABC1234 50` também funciona. O caso `/fuel 50 100` é ambíguo (50 parece placa mas é número).

13. **`PRICE_PER_PCT = 10`** no `vhub_legacyfuel/server.lua:9` é **hardcoded**, não está no `Config`. Mudar o preço do combustível requer editar código, não config.

14. **Galão (jerrycan) custa R$ 300 fixo** em `client.lua:286` (`TriggerServerEvent('vrp_legacyfuel:pagamento', parseInt(300), true)`). Não está no `Config`. E o preço do galão **não é persistido como fuel** — só entrega a arma com munição. O fuel só entra no prontuário via telemetria do vehcontrol (até 15s de lag).

15. **Decor `FUEL_LEVEL`** é registrado por `vhub_legacyfuel/client.lua:14-16` mas o consumo real é feito pelo CORE via State Bag `vh_fuel`. Há **dois mecanismos paralelos** de fuel no cliente: o Decor (legado, lido pela bomba) e a State Bag (CORE, lida pelo HUD). Se divergirem, a bomba cobra errado. O `applyPhysicalState` em `client/vehicles.lua:109` chama `SetVehicleFuelLevel(veh, st.fuel + 0.0)` que atualiza **ambos** implícitamente (a native atualiza o Decor registrado), mas só se o Decor estiver registrado primeiro. Ordem de boot importa.

---

## Resumo Executivo

- **`vhub_garage`** é o **orquestrador de UX e negócio** do ciclo de vida de veículos. Tem 4 views NUI (garage/dealer/auction/impound), mas delega a maior parte das transações para `vhub_conce` (catálogo, concessionária, registro, prontuário) e `vhub_ferinha` (leilão). É **dono direto** apenas de: pátio, IPVA, aluguel, reparo, admin de frota, e auditoria (`vhub_vehicle_log`).

- **`vhub_legacyfuel`** é a **bomba de combustível física** + o comando admin `/fuel`. Não controla consumo (que é do CORE). Padrão de integração: client paga/persiste via `vhub_conce:saveVehicleState({fuel}, 'pump')` com preço derivado server-side (delta contra prontuário, anti-undercharge).

- **Convergência crítica:** ambos escrevem no **PRONTUÁRIO** do `vhub_conce` (não no CORE direto). Isto é o pós-PRONTUÁRIO: `commitVehicleState` (CORE) foi substituído por `saveVehicleState` (conce) porque os exports do FiveM devolvem **cópia serializada** — mutar `vd.state` direto era no-op real.

- **5 bugs/pendências identificados:** (1) `active_rental` sempre 0 (status `'rental'` nunca usado); (2) `max_veiculos_player` não enforcei; (3) `Config.Classes`/`Config.FuelUsage` vestigiais; (4) eventos `100fuel`/`0fuel`/etc vestigiais; (5) `E.SPAWN_OUT`/`E.UPDATE_AUCTION`/`E.CLOSE_UI`/`E.RESCUE_DONE` declarados mas sem emitter ou sem handler.

- **2 riscos de segurança:** (1) `impoundVehicle` export não valida permissão (o caller deve gatear — frágil); (2) Lock pessimista de transferência é process-local (não protege multi-instance).

- **3 violações do manual_dev_vhub:** (1) uso de `TriggerClientEvent(-1)` para despawn/syncfuel em vez de State Bag; (2) eventos `vrp_legacyfuel:*` mantêm prefixo não-vhub; (3) leitura direta de `vhub_auctions` em `admin.lua` pode competir com `vhub_ferinha` (escritor do leilão).
