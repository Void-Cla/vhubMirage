-- vhub_inventory/sql/schema.sql
-- Idempotente (CREATE TABLE IF NOT EXISTS). Aplicado em onResourceStart.
-- FK INT UNSIGNED para vh_characters.id (decisao #17).
-- Colunas revision/payload adicionadas via server/migrations.lua (forward-only).


-- ============================================================
-- MOCHILA — 1 linha por personagem; slots serializados em JSON
-- ============================================================

CREATE TABLE IF NOT EXISTS `vhub_inv_player` (
  `char_id`    INT UNSIGNED NOT NULL,
  `data`       LONGTEXT     NOT NULL,                  -- JSON { slots = { [i]={id,amount,meta} } }
  `updated_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`char_id`),
  CONSTRAINT `fk_inv_player_char` FOREIGN KEY (`char_id`)
    REFERENCES `vh_characters` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ============================================================
-- BAUS — fixos / faccao / porta-malas (container_id hierarquico)
-- ============================================================

CREATE TABLE IF NOT EXISTS `vhub_inv_containers` (
  `container_id` VARCHAR(80)   NOT NULL,               -- static:<nome> | trunk:<placa> | faction:<grupo>
  `kind`         VARCHAR(20)   NOT NULL,
  `owner`        INT UNSIGNED  NULL,                   -- char_id dono (NULL p/ faccao/estatico)
  `data`         LONGTEXT      NOT NULL,               -- JSON { slots = {...} }
  `capacity`     DECIMAL(10,2) NOT NULL DEFAULT 100,
  `updated_at`   DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`container_id`),
  KEY `idx_owner` (`owner`),
  CONSTRAINT `fk_inv_owner_char` FOREIGN KEY (`owner`)
    REFERENCES `vh_characters` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ============================================================
-- MIGRAÇÕES — rastreamento de alterações forward-only (F2)
-- ============================================================

CREATE TABLE IF NOT EXISTS `vhub_inv_schema_migrations` (
  `version`    SMALLINT UNSIGNED NOT NULL,
  `name`       VARCHAR(120)      NOT NULL,
  `checksum`   CHAR(16)          NOT NULL,
  `applied_at` DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`version`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ============================================================
-- OPS — idempotência CAS por (actor, session, request, action)
-- ============================================================

CREATE TABLE IF NOT EXISTS `vhub_inv_ops` (
  `op_id`               CHAR(26)     NOT NULL,
  `actor`               INT UNSIGNED NOT NULL,
  `session_id`          CHAR(26)     NOT NULL,
  `request_id`          VARCHAR(64)  NOT NULL,
  `action`              VARCHAR(40)  NOT NULL,
  `payload_fingerprint` CHAR(32)     NOT NULL,
  `result`              TINYINT(1)   NOT NULL,
  `expires_at`          DATETIME     NOT NULL,
  `created_at`          DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`op_id`),
  UNIQUE KEY `uq_dedup` (`actor`, `session_id`, `request_id`, `action`),
  KEY `idx_expires` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ============================================================
-- SERIAIS — índice de unicidade (estado canônico no aggregate)
-- ============================================================

CREATE TABLE IF NOT EXISTS `vhub_inv_serials` (
  `serial`     CHAR(26)      NOT NULL,
  `item_id`    VARCHAR(40)   NOT NULL,
  `owner_ref`  VARCHAR(100)  NOT NULL,               -- "player:<char_id>" | "container:<id>"
  `revision`   BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `created_at` DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`serial`),
  KEY `idx_owner` (`owner_ref`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ============================================================
-- DROPS — itens no chão, bucket-scoped, CAS pickup
-- ============================================================

CREATE TABLE IF NOT EXISTS `vhub_inv_drops` (
  `drop_id`    CHAR(26)      NOT NULL,
  `payload`    BLOB          NOT NULL,               -- JSON {id, amount, meta}; cap 60 KB
  `bucket`     SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  `x`          FLOAT         NOT NULL,
  `y`          FLOAT         NOT NULL,
  `z`          FLOAT         NOT NULL,
  `status`     ENUM('available','claimed','expired') NOT NULL DEFAULT 'available',
  `revision`   BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `expires_at` DATETIME      NOT NULL,
  `created_at` DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`drop_id`),
  KEY `idx_bucket_status` (`bucket`, `status`, `expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
