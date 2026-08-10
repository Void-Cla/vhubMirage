CREATE TABLE IF NOT EXISTS `vhub_outdoors_items` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `operation_id` VARCHAR(96) NOT NULL,
  `title` VARCHAR(80) NOT NULL,
  `media_type` ENUM('image', 'video', 'youtube') NOT NULL,
  `media_url` VARCHAR(768) NOT NULL,
  `youtube_id` CHAR(11) DEFAULT NULL,
  `size` ENUM('small', 'medium', 'large') DEFAULT NULL,
  `volume` DECIMAL(4,3) NOT NULL DEFAULT 0.450,
  `controller_char_id` INT UNSIGNED DEFAULT NULL,
  `controller_key` CHAR(32) DEFAULT NULL,
  `top_left_x` DOUBLE NOT NULL,
  `top_left_y` DOUBLE NOT NULL,
  `top_left_z` DOUBLE NOT NULL,
  `bottom_right_x` DOUBLE NOT NULL,
  `bottom_right_y` DOUBLE NOT NULL,
  `bottom_right_z` DOUBLE NOT NULL,
  `created_by` INT UNSIGNED NOT NULL,
  `created_by_name` VARCHAR(64) NOT NULL,
  `active` TINYINT UNSIGNED NOT NULL DEFAULT 1,
  `deleted_by` INT UNSIGNED DEFAULT NULL,
  `delete_reason` VARCHAR(120) DEFAULT NULL,
  `deleted_at` DATETIME DEFAULT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_vhub_outdoors_operation` (`operation_id`),
  KEY `idx_vhub_outdoors_active` (`active`, `id`),
  KEY `idx_vhub_outdoors_controller` (`controller_char_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `vhub_outdoors_audit` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `operation_id` VARCHAR(96) NOT NULL,
  `outdoor_id` INT UNSIGNED NOT NULL,
  `action` ENUM('create', 'update', 'delete') NOT NULL,
  `actor_id` INT UNSIGNED NOT NULL,
  `actor_name` VARCHAR(64) NOT NULL,
  `reason` VARCHAR(120) NOT NULL,
  `before_state` JSON DEFAULT NULL,
  `after_state` JSON NOT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_vhub_outdoors_audit_operation` (`operation_id`),
  KEY `idx_vhub_outdoors_audit_item` (`outdoor_id`, `id`),
  CONSTRAINT `fk_vhub_outdoors_audit_item`
    FOREIGN KEY (`outdoor_id`) REFERENCES `vhub_outdoors_items` (`id`)
    ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `vhub_outdoors_remote_grants` (
  `operation_id` VARCHAR(96) NOT NULL,
  `outdoor_id` INT UNSIGNED NOT NULL,
  `char_id` INT UNSIGNED NOT NULL,
  `access_key` CHAR(32) NOT NULL,
  `status` ENUM('pending', 'activating', 'active', 'revoked', 'cancelled')
    NOT NULL DEFAULT 'pending',
  `active_outdoor_id` INT UNSIGNED GENERATED ALWAYS AS (
    CASE WHEN `status` = 'active' THEN `outdoor_id` ELSE NULL END
  ) STORED,
  `created_by` INT UNSIGNED NOT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`operation_id`),
  UNIQUE KEY `uq_vhub_outdoors_remote_key` (`access_key`),
  UNIQUE KEY `uq_vhub_outdoors_remote_active` (`active_outdoor_id`),
  KEY `idx_vhub_outdoors_remote_item` (`outdoor_id`, `status`),
  CONSTRAINT `fk_vhub_outdoors_remote_item`
    FOREIGN KEY (`outdoor_id`) REFERENCES `vhub_outdoors_items` (`id`)
    ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
