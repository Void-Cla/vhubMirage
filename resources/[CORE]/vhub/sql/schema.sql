-- ╔════════════════════════════════════════════════════════════════════╗
-- ║ vHub Mirage — Schema do CORE (CORE FROZEN v1.0 — 2026-05-22)       ║
-- ║                                                                    ║
-- ║ Engine     : InnoDB                                                ║
-- ║ Charset    : utf8mb4 (suporte completo a Unicode/emoji)            ║
-- ║ Collation  : utf8mb4_unicode_ci                                    ║
-- ║ Aplicação  : automática a cada boot via bootstrap.lua:307          ║
-- ║              (todas as statements são CREATE TABLE IF NOT EXISTS)  ║
-- ║                                                                    ║
-- ║ Pré-requisito do oxmysql:                                          ║
-- ║   multipleStatements=true na connection string (decisão #3)        ║
-- ║                                                                    ║
-- ║ Migração de banco pré-freeze (MEDIUMBLOB → BLOB):                  ║
-- ║   CREATE TABLE IF NOT EXISTS NÃO altera tipo de coluna existente.  ║
-- ║   Se seu banco já tem tabelas com MEDIUMBLOB e quiser otimizar     ║
-- ║   (BLOB usa buffer InnoDB menor), rode UMA VEZ manualmente:        ║
-- ║                                                                    ║
-- ║     ALTER TABLE vh_user_data    MODIFY COLUMN dvalue BLOB;         ║
-- ║     ALTER TABLE vh_char_data    MODIFY COLUMN dvalue BLOB;         ║
-- ║     ALTER TABLE vh_global_data  MODIFY COLUMN dvalue BLOB;         ║
-- ║     ALTER TABLE vh_vehicle_data MODIFY COLUMN dvalue BLOB;         ║
-- ║                                                                    ║
-- ║   ⚠️  ANTES verificar tamanhos com:                                ║
-- ║     SELECT MAX(LENGTH(dvalue)) FROM vh_user_data;                  ║
-- ║   Se > 65000 → manter MEDIUMBLOB naquela tabela.                   ║
-- ╚════════════════════════════════════════════════════════════════════╝


-- ════════════════════════════════════════════════════════════════════
-- vh_users — Um registro por jogador (entidade-pai de identifiers,
--   personagens e dados KV de usuário).
--   `id` é alocado server-side por `vHub._next_user_id` para evitar
--   race condition; AUTO_INCREMENT permanece como fallback.
-- ════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS vh_users (
  id          INT UNSIGNED NOT NULL AUTO_INCREMENT
              COMMENT 'PK alocada server-side ou AUTO_INCREMENT',
  created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
              COMMENT 'Data da primeira conexão do jogador',
  updated_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
              ON UPDATE CURRENT_TIMESTAMP
              COMMENT 'Última modificação na linha (observabilidade)',
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='vHub — usuários (entidade-pai)';


-- ════════════════════════════════════════════════════════════════════
-- vh_user_ids — N identifiers por jogador (steam:, license:, license2:,
--   fivem:, discord:, ip:, live:). PK no identifier garante 1-para-1
--   identifier → user_id.
--   FK ON DELETE CASCADE: apagar `vh_users` remove todos os identifiers.
-- ════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS vh_user_ids (
  identifier  VARCHAR(64)  NOT NULL
              COMMENT 'license:abc..., steam:1100..., discord:..., etc.',
  user_id     INT UNSIGNED NOT NULL,
  created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (identifier),
  KEY idx_vh_user_ids_user_id (user_id),
  CONSTRAINT fk_vh_user_ids_user
    FOREIGN KEY (user_id) REFERENCES vh_users(id)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='vHub — identifiers FiveM mapeados ao user_id';


-- ════════════════════════════════════════════════════════════════════
-- vh_characters — Múltiplos personagens por jogador. `id` é alocado
--   server-side por `vHub._next_char_id`.
--   FK ON DELETE CASCADE: apagar `vh_users` remove personagens.
-- ════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS vh_characters (
  id          INT UNSIGNED NOT NULL AUTO_INCREMENT
              COMMENT 'PK alocada server-side ou AUTO_INCREMENT',
  user_id     INT UNSIGNED NOT NULL,
  created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
              ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_vh_characters_user_id (user_id),
  CONSTRAINT fk_vh_characters_user
    FOREIGN KEY (user_id) REFERENCES vh_users(id)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='vHub — personagens por usuário';


-- ════════════════════════════════════════════════════════════════════
-- vh_user_data — KV por jogador. `dvalue` é msgpack binário.
--   Pós-freeze v1.0: BLOB (64 KB) basta para 99% dos casos
--   (datatable típico < 4 KB).
--   FK ON DELETE CASCADE: dados seguem o usuário.
-- ════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS vh_user_data (
  user_id     INT UNSIGNED NOT NULL,
  dkey        VARCHAR(64)  NOT NULL
              COMMENT 'Chave lógica (ex: datatable, permissions, last_login)',
  dvalue      BLOB
              COMMENT 'msgpack binário (até 64 KB pós-freeze v1.0)',
  updated_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
              ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, dkey),
  CONSTRAINT fk_vh_user_data_user
    FOREIGN KEY (user_id) REFERENCES vh_users(id)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='vHub — KV de jogador (msgpack)';


-- ════════════════════════════════════════════════════════════════════
-- vh_char_data — KV por personagem (inventário lógico, dinheiro,
--   posição, skills, identidade etc.). msgpack binário.
--   FK ON DELETE CASCADE: dados seguem o personagem.
-- ════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS vh_char_data (
  char_id     INT UNSIGNED NOT NULL,
  dkey        VARCHAR(64)  NOT NULL
              COMMENT 'Chave lógica (ex: inventory, money, position)',
  dvalue      BLOB
              COMMENT 'msgpack binário (até 64 KB pós-freeze v1.0)',
  updated_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
              ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (char_id, dkey),
  CONSTRAINT fk_vh_char_data_char
    FOREIGN KEY (char_id) REFERENCES vh_characters(id)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='vHub — KV de personagem (msgpack)';


-- ════════════════════════════════════════════════════════════════════
-- vh_global_data — KV global servidor-wide (config dinâmica, estado
--   da economia, contadores). msgpack binário.
--   Sem FK: dados independentes de qualquer entidade.
-- ════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS vh_global_data (
  dkey        VARCHAR(64)  NOT NULL
              COMMENT 'Chave lógica global (ex: server_economy, day_count)',
  dvalue      BLOB
              COMMENT 'msgpack binário (até 64 KB pós-freeze v1.0)',
  updated_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
              ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (dkey)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='vHub — KV global do servidor (msgpack)';


-- ════════════════════════════════════════════════════════════════════
-- vh_vehicles — Registro físico de veículo: placa (PK GTA — máx 10
--   chars) + chave de propriedade (UID livre — pode ser uuid, hash de
--   item de inventário, etc.).
--   Negócio (owner, status, IPVA, leilão) fica em `vhub_garage`.
--   Sem FK em key_uid: a chave pode apontar para uma entidade externa
--   gerenciada por outro resource.
-- ════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS vh_vehicles (
  plate       VARCHAR(10)  NOT NULL
              COMMENT 'Placa GTA — máx 10 chars, charset [A-Z0-9 ]',
  key_uid     VARCHAR(64)  DEFAULT NULL
              COMMENT 'UID livre da chave (NULL = servidor/leilão)',
  created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
              ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (plate),
  KEY idx_vh_vehicles_key_uid (key_uid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='vHub — registro físico de veículo (placa + chave)';


-- ════════════════════════════════════════════════════════════════════
-- vh_vehicle_data — KV por placa: estado físico (fuel, engine_health,
--   body_health, odometer, tuning, last_pos, damage, engine_on).
--   msgpack binário.
--   FK ON DELETE CASCADE: dados seguem o veículo.
-- ════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS vh_vehicle_data (
  plate       VARCHAR(10)  NOT NULL,
  dkey        VARCHAR(64)  NOT NULL
              COMMENT 'Chave lógica (ex: state, tuning, damage)',
  dvalue      BLOB
              COMMENT 'msgpack binário (até 64 KB pós-freeze v1.0)',
  updated_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
              ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (plate, dkey),
  CONSTRAINT fk_vh_vehicle_data_vehicle
    FOREIGN KEY (plate) REFERENCES vh_vehicles(plate)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='vHub — KV físico de veículo (msgpack)';
