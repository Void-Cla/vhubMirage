-- sql/schema.sql - vhub_racha
-- Perfis/recordes usam FK CASCADE; runs/results preservam historico.

CREATE TABLE IF NOT EXISTS `vh_racha_profiles` (
  `char_id`     INT UNSIGNED NOT NULL,
  `nickname`    VARCHAR(24)  NOT NULL,
  `created_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`char_id`),
  UNIQUE KEY `uk_racha_nickname` (`nickname`),
  CONSTRAINT `fk_racha_profile_char` FOREIGN KEY (`char_id`)
    REFERENCES `vh_characters` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `vh_racha_runs` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `track_id` VARCHAR(48) NOT NULL,
  `state` ENUM('open','countdown','running','finished','cancelled','expired') NOT NULL DEFAULT 'open',
  `organizer_char_id` INT UNSIGNED NOT NULL,
  `entry_fee` BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `prize_pool` BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `laps` TINYINT UNSIGNED NOT NULL DEFAULT 1,
  `ranked` TINYINT(1) NOT NULL DEFAULT 1,
  `participant_count` SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  `started_at` DATETIME NULL DEFAULT NULL,
  `finished_at` DATETIME NULL DEFAULT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_racha_runs_track` (`track_id`, `created_at`),
  KEY `idx_racha_runs_state` (`state`),
  KEY `idx_racha_runs_organizer` (`organizer_char_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `vh_racha_results` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `run_id` BIGINT UNSIGNED NOT NULL,
  `track_id` VARCHAR(48) NOT NULL,
  `char_id` INT UNSIGNED NOT NULL,
  `nickname` VARCHAR(24) NOT NULL DEFAULT '',
  `vehicle_plate` VARCHAR(12) NOT NULL DEFAULT '',
  `vehicle_model` VARCHAR(32) NOT NULL DEFAULT '',
  `position` SMALLINT UNSIGNED DEFAULT NULL,
  `duration_ms` INT UNSIGNED DEFAULT NULL,
  `checkpoints` SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  `status` ENUM('finished','dnf','left','timeout','cancelled') NOT NULL,
  `payout` BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_racha_result_run_char` (`run_id`, `char_id`),
  KEY `idx_racha_results_track_time` (`track_id`, `status`, `duration_ms`),
  KEY `idx_racha_results_char` (`char_id`, `created_at`),
  CONSTRAINT `fk_racha_result_run` FOREIGN KEY (`run_id`)
    REFERENCES `vh_racha_runs` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `vh_racha_records` (
  `track_id` VARCHAR(48) NOT NULL,
  `char_id` INT UNSIGNED NOT NULL,
  `nickname` VARCHAR(24) NOT NULL DEFAULT '',
  `best_ms` INT UNSIGNED DEFAULT NULL,
  `best_run_id` BIGINT UNSIGNED DEFAULT NULL,
  `wins` INT UNSIGNED NOT NULL DEFAULT 0,
  `podiums` INT UNSIGNED NOT NULL DEFAULT 0,
  `finishes` INT UNSIGNED NOT NULL DEFAULT 0,
  `dnfs` INT UNSIGNED NOT NULL DEFAULT 0,
  `total_ms` BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`track_id`, `char_id`),
  KEY `idx_racha_records_char` (`char_id`),
  KEY `idx_racha_records_track_best` (`track_id`, `best_ms`),
  KEY `idx_racha_records_general` (`wins`, `podiums`, `finishes`, `best_ms`),
  CONSTRAINT `fk_racha_record_char` FOREIGN KEY (`char_id`)
    REFERENCES `vh_characters` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
