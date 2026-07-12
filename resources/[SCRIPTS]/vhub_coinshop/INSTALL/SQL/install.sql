-- vhub_coinshop — instalação limpa para phpMyAdmin, DBeaver e mysql CLI.
-- Pré-requisito: tabelas vh_characters do CORE já existem.

CREATE TABLE IF NOT EXISTS `vhub_coinshop_items` (
    `id` VARCHAR(50) NOT NULL,
    `name` VARCHAR(100) NOT NULL,
    `description` VARCHAR(255) DEFAULT '',
    `category` ENUM('vehicle','item','weapon','tool') NOT NULL DEFAULT 'item',
    `tags` TEXT,
    `price` INT NOT NULL DEFAULT 0,
    `images` TEXT,
    `spawn_name` VARCHAR(50) DEFAULT NULL,
    `item_name` VARCHAR(50) DEFAULT NULL,
    `item_count` INT DEFAULT 1,
    `weapon_name` VARCHAR(50) DEFAULT NULL,
    `trending` TINYINT(1) DEFAULT 0,
    `custom_category` VARCHAR(50) DEFAULT NULL,
    `published` TINYINT(1) NOT NULL DEFAULT 1,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `vhub_coinshop_categories` (
    `id` VARCHAR(50) NOT NULL,
    `name` VARCHAR(100) NOT NULL,
    `icon` VARCHAR(500) DEFAULT '',
    `type` VARCHAR(20) DEFAULT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `vhub_coinshop_purchases` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `char_id` INT UNSIGNED NOT NULL,
    `item_id` VARCHAR(50) NOT NULL,
    `price` INT NOT NULL,
    `purchased_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_char` (`char_id`),
    CONSTRAINT `fk_coinshop_purchases_char`
      FOREIGN KEY (`char_id`) REFERENCES `vh_characters`(`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `vhub_coinshop_deals` (
    `id` VARCHAR(50) NOT NULL,
    `name` VARCHAR(100) NOT NULL,
    `description` VARCHAR(255) DEFAULT '',
    `price` INT NOT NULL DEFAULT 0,
    `image` VARCHAR(500) DEFAULT '',
    `items` TEXT,
    `expires_at` DATETIME NOT NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `vhub_coinshop_codes` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `tbx_id` VARCHAR(100) NOT NULL,
    `coins` INT NOT NULL DEFAULT 0,
    `status` ENUM('pending','redeemed') NOT NULL DEFAULT 'pending',
    `redeemed_by` INT UNSIGNED DEFAULT NULL,
    `redeemed_at` TIMESTAMP NULL DEFAULT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_tbx_id` (`tbx_id`),
    KEY `idx_status` (`status`),
    CONSTRAINT `fk_coinshop_codes_redeemer`
      FOREIGN KEY (`redeemed_by`) REFERENCES `vh_characters`(`id`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `vhub_coinshop_redeems` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `char_id` INT UNSIGNED NOT NULL,
    `redeem_key` VARCHAR(100) NOT NULL,
    `coins_added` INT NOT NULL DEFAULT 0,
    `redeemed_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_redeem_key` (`redeem_key`),
    KEY `idx_char` (`char_id`),
    CONSTRAINT `fk_coinshop_redeems_char`
      FOREIGN KEY (`char_id`) REFERENCES `vh_characters`(`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `vhub_coinshop_pix_tx` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `txid` VARCHAR(64) NOT NULL,
    `char_id` INT UNSIGNED NOT NULL,
    `src` INT NOT NULL,
    `package_id` VARCHAR(50) NOT NULL,
    `coins` INT NOT NULL DEFAULT 0,
    `amount_brl` DECIMAL(10,2) NOT NULL,
    `status` ENUM('pending','paid','expired') NOT NULL DEFAULT 'pending',
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `expires_at` DATETIME NOT NULL,
    `paid_at` DATETIME NULL DEFAULT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_txid` (`txid`),
    KEY `idx_char` (`char_id`),
    KEY `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT IGNORE INTO `vhub_coinshop_categories` (`id`, `name`, `icon`, `type`) VALUES
('vehicles', 'Veículos', '', 'vehicle'),
('items', 'Itens', '', 'item'),
('weapons', 'Armas', '', 'weapon'),
('tools', 'Ferramentas', '', 'tool');
