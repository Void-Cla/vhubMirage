-- sql/schema.sql — vhub_hss (Human State System)
-- Estado fisiológico persistido por char_id.
-- FK ON DELETE CASCADE: apagar personagem limpa o estado HSS.
-- Campos voláteis NÃO persistidos: adrenaline (TTL 5min), heart_rate (derivado).

CREATE TABLE IF NOT EXISTS `vhub_hss_state` (
  `char_id`       INT UNSIGNED    NOT NULL,
  `food`          DOUBLE          NOT NULL DEFAULT 1.0,
  `water`         DOUBLE          NOT NULL DEFAULT 1.0,
  `energy`        DOUBLE          NOT NULL DEFAULT 1.0,
  `stress`        DOUBLE          NOT NULL DEFAULT 0.0,
  `blood`         DOUBLE          NOT NULL DEFAULT 1.0,
  `bleeding`      TINYINT         NOT NULL DEFAULT 0,
  `pain`          DOUBLE          NOT NULL DEFAULT 0.0,
  `body_temp`     DOUBLE          NOT NULL DEFAULT 37.0,
  `consciousness` VARCHAR(16)     NOT NULL DEFAULT 'awake',
  `diseases`      JSON                     DEFAULT NULL,
  `injuries`      JSON                     DEFAULT NULL,
  `ped_state`     JSON                     DEFAULT NULL,
  `customization_revision` BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `revision`      BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `digest`        CHAR(64)                 DEFAULT NULL,
  `updated_at`    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`char_id`),
  CONSTRAINT `fk_hss_char` FOREIGN KEY (`char_id`)
    REFERENCES `vh_characters` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE `vhub_hss_state`
  ADD COLUMN IF NOT EXISTS `customization_revision` BIGINT UNSIGNED NOT NULL DEFAULT 0
  AFTER `ped_state`;

CREATE TABLE IF NOT EXISTS `vhub_hss_customization_ops` (
  `operation_id`        VARCHAR(96)     NOT NULL,
  `char_id`             INT UNSIGNED    NOT NULL,
  `digest`              CHAR(64)        NOT NULL,
  `before_customization` JSON           NOT NULL,
  `after_customization`  JSON           NOT NULL,
  `before_revision`     BIGINT UNSIGNED NOT NULL,
  `after_revision`      BIGINT UNSIGNED NOT NULL,
  `rollback_token`      VARCHAR(100)    NOT NULL,
  `rollback_revision`   BIGINT UNSIGNED NULL,
  `state`               ENUM('pending', 'committed', 'rolled_back') NOT NULL DEFAULT 'pending',
  `created_at`          DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`          DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`operation_id`),
  UNIQUE KEY `uk_hss_customization_rollback` (`rollback_token`),
  KEY `idx_hss_customization_char` (`char_id`),
  CONSTRAINT `fk_hss_customization_char` FOREIGN KEY (`char_id`)
    REFERENCES `vh_characters` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `vhub_hss_schema_migrations` (
  `version`    INT UNSIGNED NOT NULL,
  `applied_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`version`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
