-- vhub_inventory/sql/schema.sql
-- Idempotente (CREATE IF NOT EXISTS). Aplicado em onResourceStart.
-- FK INT UNSIGNED para vh_characters.id (decisao #17). Drops NAO tem tabela (efemeros).


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
