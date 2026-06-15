-- schema.sql — tabelas do LSPD Tool (auditoria de scans + BOLOs)
-- FK ao core usa INT UNSIGNED (decisão #17 do contexto). Idempotente.


-- ============================================================
-- vhub_lspd_scans — auditoria de leituras de placa
-- ============================================================

CREATE TABLE IF NOT EXISTS `vhub_lspd_scans` (
  `id`          INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  `scanner_uid` INT UNSIGNED  NULL,
  `plate`       VARCHAR(8)    NOT NULL,
  `flagged`     TINYINT(1)    NOT NULL DEFAULT 0,
  `src_kind`    VARCHAR(8)    NOT NULL DEFAULT 'ground',
  `pos_x`       FLOAT         NOT NULL DEFAULT 0,
  `pos_y`       FLOAT         NOT NULL DEFAULT 0,
  `pos_z`       FLOAT         NOT NULL DEFAULT 0,
  `created_at`  DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_plate`   (`plate`),
  KEY `idx_created` (`created_at`),
  CONSTRAINT `fk_lspd_scan_user` FOREIGN KEY (`scanner_uid`)
    REFERENCES `vh_users` (`id`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ============================================================
-- vhub_lspd_bolos — alertas de procura (BOLO) por placa
-- ============================================================

CREATE TABLE IF NOT EXISTS `vhub_lspd_bolos` (
  `id`             INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  `plate`          VARCHAR(8)    NOT NULL,
  `reason`         VARCHAR(160)  NOT NULL DEFAULT '',
  `level`          TINYINT       NOT NULL DEFAULT 1,
  `created_by_uid` INT UNSIGNED  NULL,
  `active`         TINYINT(1)    NOT NULL DEFAULT 1,
  `created_at`     DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`     DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_active_plate` (`active`, `plate`),
  CONSTRAINT `fk_lspd_bolo_user` FOREIGN KEY (`created_by_uid`)
    REFERENCES `vh_users` (`id`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ============================================================
-- vhub_lspd_accounts — credencial de acesso ao app LSPD do iPad
-- ============================================================
-- Login = char_id do policial. Senha guardada como HASH (SHA-256 hex) + salt
-- por linha (hashing feito pelo MySQL via SHA2 — sem lib de cripto em Lua).
-- must_change=1 força a troca no primeiro acesso (senha padrão '123').

CREATE TABLE IF NOT EXISTS `vhub_lspd_accounts` (
  `char_id`     INT UNSIGNED  NOT NULL,
  `pass_hash`   CHAR(64)      NOT NULL,
  `salt`        CHAR(32)      NOT NULL,
  `must_change` TINYINT(1)    NOT NULL DEFAULT 1,
  `created_at`  DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`  DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`char_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ============================================================
-- vhub_lspd_wanted — pessoas procuradas (mandado) por char_id
-- ============================================================
-- Distinto do BOLO (que é por PLACA). Aqui o alvo é um PERSONAGEM. Alerta às
-- unidades quando o procurado é avistado/identificado. Fonte de verdade própria.

CREATE TABLE IF NOT EXISTS `vhub_lspd_wanted` (
  `id`             INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  `target_char_id` INT UNSIGNED  NOT NULL,
  `target_name`    VARCHAR(64)   NOT NULL DEFAULT '',
  `reason`         VARCHAR(160)  NOT NULL DEFAULT '',
  `level`          TINYINT       NOT NULL DEFAULT 1,
  `created_by_uid` INT UNSIGNED  NULL,
  `active`         TINYINT(1)    NOT NULL DEFAULT 1,
  `created_at`     DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`     DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_active_target` (`active`, `target_char_id`),
  CONSTRAINT `fk_lspd_wanted_user` FOREIGN KEY (`created_by_uid`)
    REFERENCES `vh_users` (`id`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
