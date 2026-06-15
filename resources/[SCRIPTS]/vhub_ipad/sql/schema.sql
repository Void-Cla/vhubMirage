-- vhub_ipad — estado do tablet POR PERSONAGEM (char_id).
-- Aplicado idempotente no onResourceStart (server/sql.lua:initSchema).
-- char_id = INT UNSIGNED (PK canônica do core, decisão #17). Sem FK (resource externo).
--
-- installed = JSON array de ids de apps REMOVÍVEIS que o personagem instalou.
-- prefs     = JSON { zoom, wallpaper_id, wallpaper_custom? } — preferência de UI.

CREATE TABLE IF NOT EXISTS `vhub_ipad_state` (
  `char_id`    INT UNSIGNED NOT NULL,
  `installed`  TEXT         NULL,
  `prefs`      TEXT         NULL,
  `updated_at` INT          NULL,
  PRIMARY KEY (`char_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
