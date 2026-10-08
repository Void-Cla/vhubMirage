-- sql/schema.sql — vhub_identity
-- char_id é INT UNSIGNED para casar com vh_characters.id (CORE FROZEN v1.0)
CREATE TABLE IF NOT EXISTS `vh_identity` (
  `char_id`      INT UNSIGNED     NOT NULL,
  `firstname`    VARCHAR(50)      NOT NULL DEFAULT '',
  `lastname`     VARCHAR(50)      NOT NULL DEFAULT '',
  `age`          TINYINT UNSIGNED NOT NULL DEFAULT 25,
  `registration` VARCHAR(20)      NOT NULL DEFAULT '',
  `phone`        VARCHAR(20)      NOT NULL DEFAULT '',
  `role`         ENUM('legal','ilegal','mecanica','hospital','policia','livre') NULL DEFAULT NULL,
  `backstory`    TEXT             NULL DEFAULT NULL,
  PRIMARY KEY (`char_id`),
  UNIQUE KEY `uk_registration` (`registration`),
  UNIQUE KEY `uk_phone` (`phone`),
  CONSTRAINT `fk_identity_char` FOREIGN KEY (`char_id`)
    REFERENCES `vh_characters` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE `vh_identity`
  ADD COLUMN IF NOT EXISTS `role`
    ENUM('legal','ilegal','mecanica','hospital','policia','livre') NULL DEFAULT NULL;
ALTER TABLE `vh_identity`
  ADD COLUMN IF NOT EXISTS `backstory` TEXT NULL DEFAULT NULL;

CREATE TABLE IF NOT EXISTS `vh_identity_operations` (
  `operation_id`   VARCHAR(96)  NOT NULL,
  `char_id`        INT UNSIGNED NOT NULL,
  `digest`         CHAR(64)     NOT NULL,
  `result_identity` JSON        NULL,
  `state`          ENUM('pending', 'committed') NOT NULL DEFAULT 'pending',
  `created_at`     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`operation_id`),
  KEY `idx_identity_operations_char` (`char_id`),
  CONSTRAINT `fk_identity_operations_char` FOREIGN KEY (`char_id`)
    REFERENCES `vh_characters` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
