-- vhub_garage/sql/schema.sql
-- A garagem usa as tabelas do vHub core: vh_vehicles e vh_char_data.
-- Não requer tabelas extras — o estado do veículo fica em:
--   vh_char_data WHERE char_id = @cid AND dkey = "veh_state|<plate>"
-- Este arquivo documenta as queries utilizadas.

-- Tabela usada: vh_vehicles (criada pelo vHub core)
-- CREATE TABLE IF NOT EXISTS `vh_vehicles` (
--   `plate`   VARCHAR(10) NOT NULL,
--   `key_uid` INT UNSIGNED DEFAULT NULL,
--   PRIMARY KEY (`plate`)
-- );

-- Tabela usada: vh_char_data (criada pelo vHub core)
-- Os dados de estado ficam em:
--   dkey  = "veh_state|ABC1234"
--   dvalue = msgpack({ customization, condition, fuel, locked, out, position, rotation })

-- Não há necessidade de migrations para a garagem.
-- Compatível com o schema do vHub core (sql/schema.sql).
