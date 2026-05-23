-- sql/schema.sql — vhub_money (Fleeca Camell)
-- Persistencia propria. char_id e INT UNSIGNED (casa com vh_characters.id).
-- FK ON DELETE CASCADE: apagar personagem zera contas.
-- Transactions e append-only para auditoria (sem FK pra preservar historico).
--
-- Tabelas:
--   vh_money_accounts      : saldo de carteira + banco por char_id
--   vh_money_transactions  : log auditavel de toda movimentacao

CREATE TABLE IF NOT EXISTS `vh_money_accounts` (
  `char_id`     INT UNSIGNED      NOT NULL,
  `wallet`      BIGINT UNSIGNED   NOT NULL DEFAULT 0,
  `bank`        BIGINT UNSIGNED   NOT NULL DEFAULT 0,
  `total_in`    BIGINT UNSIGNED   NOT NULL DEFAULT 0,
  `total_out`   BIGINT UNSIGNED   NOT NULL DEFAULT 0,
  `created_at`  TIMESTAMP         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`  TIMESTAMP         NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`char_id`),
  CONSTRAINT `fk_money_char` FOREIGN KEY (`char_id`)
    REFERENCES `vh_characters` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `vh_money_transactions` (
  `id`              BIGINT UNSIGNED   NOT NULL AUTO_INCREMENT,
  `actor_char_id`   INT UNSIGNED      NOT NULL,
  `target_char_id`  INT UNSIGNED      NOT NULL,
  `kind`            VARCHAR(24)       NOT NULL DEFAULT 'unknown',
  `amount`          BIGINT UNSIGNED   NOT NULL DEFAULT 0,
  `source_account`  ENUM('wallet','bank','none') NOT NULL DEFAULT 'none',
  `target_account`  ENUM('wallet','bank','none') NOT NULL DEFAULT 'none',
  `balance_wallet`  BIGINT UNSIGNED   NOT NULL DEFAULT 0,
  `balance_bank`    BIGINT UNSIGNED   NOT NULL DEFAULT 0,
  `reason`          VARCHAR(180)      NOT NULL DEFAULT '',
  `created_at`      TIMESTAMP         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_tx_actor` (`actor_char_id`),
  KEY `idx_tx_target` (`target_char_id`),
  KEY `idx_tx_kind` (`kind`),
  KEY `idx_tx_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
