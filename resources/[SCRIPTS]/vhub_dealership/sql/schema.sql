-- vhub_dealership/sql/schema.sql
-- Placa → char_id para garantir unicidade global (jogadores online e offline).
-- Estado do veículo fica em user.data.vehicles[plate] (salvo pelo autosave do vHub).

CREATE TABLE IF NOT EXISTS `vhub_plates` (
  `plate`   VARCHAR(8)    NOT NULL,
  `char_id` INT UNSIGNED  NOT NULL,
  PRIMARY KEY (`plate`),
  INDEX `idx_char_id` (`char_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
