-- vhub_garage/sql/schema.sql
-- Schema centralizado: ve culos, chaves, leil es, p tio, aluguel, IPVA, est tica, log.
-- Convivem com tabelas do core vHub (`vh_vehicles` para key_uid; `vh_char_data` para state f sico via msgpack).
-- vhub_garage = fonte de verdade de NEG CIO (dono, status, IPVA, p tio, leil o, aluguel).
-- core vHub  = fonte de verdade de F SICO (fuel, dano, odometer, tuning, last_pos).

-- =============================================================================
-- Tabela mestre: registro can nico do ve culo (uma linha por placa)
-- =============================================================================
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
  `purchase_at`       BIGINT            DEFAULT NULL,
  `last_seen_at`      BIGINT            DEFAULT NULL,
  `created_at`        BIGINT            NOT NULL,
  `updated_at`        BIGINT            NOT NULL,
  PRIMARY KEY (`plate`),
  KEY `idx_char_id`   (`char_id`),
  KEY `idx_status`    (`status`),
  KEY `idx_vtype`     (`vtype`),
  KEY `idx_rented`    (`rented_until`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================================
-- Chaves compartilhadas / emprestadas / clonadas
-- (a chave-item f sica vive no `vhub_inventory`. Esta tabela trava autoriza  o de uso.)
-- =============================================================================
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

-- =============================================================================
-- Leil es: cabe alho
-- =============================================================================
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

-- =============================================================================
-- Leil es: hist rico de lances
-- =============================================================================
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

-- =============================================================================
-- P tio (impound): hist rico/atual de apreens es
-- =============================================================================
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

-- =============================================================================
-- Estoque opcional da concession ria (admin pode limitar oferta)
-- =============================================================================
CREATE TABLE IF NOT EXISTS `vhub_dealership_stock` (
  `model`         VARCHAR(64)  NOT NULL,
  `qty`           INT          NOT NULL DEFAULT -1,
  `custom_price`  INT UNSIGNED DEFAULT NULL,
  `updated_at`    BIGINT       NOT NULL,
  PRIMARY KEY (`model`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================================
-- Auditoria (a  es relevantes: compra, venda, leil o, p tio, transfer ncia)
-- =============================================================================
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
