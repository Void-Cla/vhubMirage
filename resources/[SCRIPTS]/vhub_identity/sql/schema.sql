-- sql/schema.sql — vhub_identity
-- char_id é INT UNSIGNED para casar com vh_characters.id (CORE FROZEN v1.0)
CREATE TABLE IF NOT EXISTS `vh_identity` (
  `char_id`      INT UNSIGNED     NOT NULL,
  `firstname`    VARCHAR(50)      NOT NULL DEFAULT '',
  `lastname`     VARCHAR(50)      NOT NULL DEFAULT '',
  `age`          TINYINT UNSIGNED NOT NULL DEFAULT 25,
  `registration` VARCHAR(20)      NOT NULL DEFAULT '',
  `phone`        VARCHAR(20)      NOT NULL DEFAULT '',
  PRIMARY KEY (`char_id`),
  UNIQUE KEY `uk_registration` (`registration`),
  UNIQUE KEY `uk_phone` (`phone`),
  CONSTRAINT `fk_identity_char` FOREIGN KEY (`char_id`)
    REFERENCES `vh_characters` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
