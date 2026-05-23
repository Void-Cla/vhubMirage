-- sql/schema.sql — vhub_groups
-- Schema canonico pos Frozen v1.0:
--   char_id e INT UNSIGNED (casa com vh_characters.id)
--   FK ON DELETE CASCADE: apagar personagem purga grupos automaticamente
--   audit log e append-only e nao tem FK estrita (mantem historico mesmo apos delete)
--
-- Tabelas:
--   vh_groups        : grupos atribuidos por char_id (com nivel + expiracao opcional)
--   vh_groups_audit  : log append-only de toda mudanca

CREATE TABLE IF NOT EXISTS `vh_groups` (
  `char_id`     INT UNSIGNED     NOT NULL,
  `group_id`    VARCHAR(48)      NOT NULL,
  `level`       INT UNSIGNED     NOT NULL DEFAULT 1,
  `added_by`    INT UNSIGNED     NOT NULL DEFAULT 0,
  `added_at`    TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `expires_at`  TIMESTAMP        NULL DEFAULT NULL,
  `updated_at`  TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `reason`      VARCHAR(120)     NOT NULL DEFAULT '',
  PRIMARY KEY (`char_id`, `group_id`),
  KEY `idx_groups_group` (`group_id`),
  KEY `idx_groups_expires` (`expires_at`),
  CONSTRAINT `fk_groups_char` FOREIGN KEY (`char_id`)
    REFERENCES `vh_characters` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `vh_groups_audit` (
  `id`              BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  `actor_char_id`   INT UNSIGNED     NOT NULL DEFAULT 0,
  `target_char_id`  INT UNSIGNED     NOT NULL,
  `action`          VARCHAR(32)      NOT NULL,
  `group_id`        VARCHAR(48)      NOT NULL DEFAULT '',
  `level`           INT UNSIGNED     NOT NULL DEFAULT 0,
  `reason`          VARCHAR(180)     NOT NULL DEFAULT '',
  `created_at`      TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_audit_target` (`target_char_id`),
  KEY `idx_audit_actor` (`actor_char_id`),
  KEY `idx_audit_created` (`created_at`),
  KEY `idx_audit_action` (`action`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
