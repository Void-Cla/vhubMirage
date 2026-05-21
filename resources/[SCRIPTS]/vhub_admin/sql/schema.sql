-- vhub_admin/sql/schema.sql
-- Auditoria + jail/mute persistente + tickets de jogadores.

-- =============================================================================
-- Log de auditoria (toda  o admin grava aqui)
-- =============================================================================
CREATE TABLE IF NOT EXISTS `vhub_admin_log` (
  `id`         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `actor_id`   INT UNSIGNED    DEFAULT NULL,   -- user_id do admin (NULL = console)
  `actor_name` VARCHAR(64)     DEFAULT NULL,
  `action`     VARCHAR(48)     NOT NULL,
  `target_id`  INT UNSIGNED    DEFAULT NULL,
  `target_src` INT UNSIGNED    DEFAULT NULL,
  `payload`    TEXT            DEFAULT NULL,
  `created_at` BIGINT          NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_actor`   (`actor_id`),
  KEY `idx_target`  (`target_id`),
  KEY `idx_action`  (`action`),
  KEY `idx_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================================
-- Jail (preso por X minutos)
-- =============================================================================
CREATE TABLE IF NOT EXISTS `vhub_admin_jail` (
  `char_id`    INT UNSIGNED    NOT NULL,
  `expires_at` BIGINT          NOT NULL,
  `reason`     VARCHAR(180)    DEFAULT NULL,
  `jailer_id`  INT UNSIGNED    DEFAULT NULL,
  `created_at` BIGINT          NOT NULL,
  PRIMARY KEY (`char_id`),
  KEY `idx_expires` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================================
-- Mute (sem fala em chat por X minutos)
-- =============================================================================
CREATE TABLE IF NOT EXISTS `vhub_admin_mute` (
  `char_id`    INT UNSIGNED    NOT NULL,
  `expires_at` BIGINT          NOT NULL,
  `reason`     VARCHAR(180)    DEFAULT NULL,
  `muter_id`   INT UNSIGNED    DEFAULT NULL,
  `created_at` BIGINT          NOT NULL,
  PRIMARY KEY (`char_id`),
  KEY `idx_expires` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================================
-- Reports (jogador   admin)
-- =============================================================================
CREATE TABLE IF NOT EXISTS `vhub_admin_reports` (
  `id`           INT UNSIGNED   NOT NULL AUTO_INCREMENT,
  `reporter_id`  INT UNSIGNED   NOT NULL,
  `reporter_src` INT UNSIGNED   DEFAULT NULL,
  `message`      VARCHAR(500)   NOT NULL,
  `status`       ENUM('open','claimed','closed') NOT NULL DEFAULT 'open',
  `claimed_by`   INT UNSIGNED   DEFAULT NULL,
  `closed_by`    INT UNSIGNED   DEFAULT NULL,
  `notes`        TEXT           DEFAULT NULL,
  `created_at`   BIGINT         NOT NULL,
  `claimed_at`   BIGINT         DEFAULT NULL,
  `closed_at`    BIGINT         DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_status`   (`status`),
  KEY `idx_reporter` (`reporter_id`),
  KEY `idx_created`  (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
