-- sql/schema.sql — ledger durável da saga do vhub_custom

CREATE TABLE IF NOT EXISTS `vh_custom_operations` (
  `operation_id`    VARCHAR(64)      NOT NULL,
  `request_key`     VARCHAR(55)      NOT NULL,
  `source_id`       INT UNSIGNED     NOT NULL,
  `char_id`         INT UNSIGNED     NOT NULL,
  `plate`           VARCHAR(8)       NOT NULL,
  `model_hash`      BIGINT UNSIGNED  NOT NULL,
  `domain`          ENUM('bennys','mec','oficina') NOT NULL,
  `action`          VARCHAR(24)      NOT NULL,
  `semantic_digest` CHAR(64)         NOT NULL,
  `amount`          BIGINT UNSIGNED  NOT NULL DEFAULT 0,
  `payload_json`    TEXT             NOT NULL,
  `before_json`     TEXT             NOT NULL,
  `after_json`      TEXT             NOT NULL,
  `state`           ENUM('prepared','charged','applied','refunded') NOT NULL DEFAULT 'prepared',
  `claim_token`     VARCHAR(32)      NULL,
  `claim_until`     TIMESTAMP        NULL,
  `created_at`      TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`      TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`operation_id`),
  UNIQUE KEY `uq_custom_request` (`char_id`, `request_key`),
  KEY `idx_custom_recovery` (`state`, `updated_at`),
  CONSTRAINT `fk_custom_operation_char` FOREIGN KEY (`char_id`)
    REFERENCES `vh_characters` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `vh_custom_operation_guards` (
  `plate`         VARCHAR(8)  NOT NULL,
  `operation_id`  VARCHAR(64) NOT NULL,
  `updated_at`    TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`plate`),
  UNIQUE KEY `uq_custom_guard_operation` (`operation_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
