-- sql/schema.sql — vhub_racha v3 (Liga clandestina)
-- 6 tabelas. Pistas custom criadas pelo editor in-game vivem so no SQL.
-- Pistas do config sao espelhadas em vh_race_tracks no boot (idempotente).

CREATE TABLE IF NOT EXISTS `vh_race_tracks` (
  `id`              VARCHAR(48)      NOT NULL,
  `label`           VARCHAR(80)      NOT NULL DEFAULT '',
  `district`        VARCHAR(60)      NOT NULL DEFAULT '',
  `kind`            VARCHAR(24)      NOT NULL DEFAULT 'sprint',
  `creator_char`    INT UNSIGNED     NOT NULL DEFAULT 0,
  `illegal`         TINYINT UNSIGNED NOT NULL DEFAULT 1,
  `alerts_police`   TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `laps`            INT UNSIGNED     NOT NULL DEFAULT 1,
  `min_players`     INT UNSIGNED     NOT NULL DEFAULT 1,
  `max_players`     INT UNSIGNED     NOT NULL DEFAULT 8,
  `vehicle_class`   VARCHAR(16)      NOT NULL DEFAULT 'car',
  `default_fee`     INT UNSIGNED     NOT NULL DEFAULT 0,
  `limit_seconds`   INT UNSIGNED     NOT NULL DEFAULT 300,
  `start_x`         DOUBLE           NOT NULL DEFAULT 0,
  `start_y`         DOUBLE           NOT NULL DEFAULT 0,
  `start_z`         DOUBLE           NOT NULL DEFAULT 0,
  `start_h`         DOUBLE           NOT NULL DEFAULT 0,
  `source`          ENUM('config','custom') NOT NULL DEFAULT 'config',
  -- Categoria fixa da pista (temporadas): ranqueada conta PDL; normal=casual;
  -- personalizada=editor, lobby SEMPRE com senha. Escritor: upsert_track (#36).
  `category`        ENUM('ranqueada','normal','personalizada') NOT NULL DEFAULT 'normal',
  `enabled`         TINYINT UNSIGNED NOT NULL DEFAULT 1,
  `created_at`      TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`      TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_tracks_kind` (`kind`),
  KEY `idx_tracks_source` (`source`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `vh_race_checkpoints` (
  `track_id`  VARCHAR(48)  NOT NULL,
  `idx`       INT UNSIGNED NOT NULL,
  `x`         DOUBLE       NOT NULL,
  `y`         DOUBLE       NOT NULL,
  `z`         DOUBLE       NOT NULL,
  `radius`    DOUBLE       NOT NULL DEFAULT 11.0,
  `kind`      VARCHAR(16)  NOT NULL DEFAULT 'normal',
  PRIMARY KEY (`track_id`, `idx`),
  CONSTRAINT `fk_cp_track` FOREIGN KEY (`track_id`)
    REFERENCES `vh_race_tracks` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `vh_race_grid` (
  `track_id`  VARCHAR(48)  NOT NULL,
  `slot`      INT UNSIGNED NOT NULL,
  `x`         DOUBLE       NOT NULL,
  `y`         DOUBLE       NOT NULL,
  `z`         DOUBLE       NOT NULL,
  `h`         DOUBLE       NOT NULL DEFAULT 0,
  PRIMARY KEY (`track_id`, `slot`),
  CONSTRAINT `fk_grid_track` FOREIGN KEY (`track_id`)
    REFERENCES `vh_race_tracks` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `vh_race_history` (
  `id`              BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  `track_id`        VARCHAR(48)      NOT NULL,
  `kind`            VARCHAR(24)      NOT NULL DEFAULT 'sprint',
  `mode`            ENUM('rankeada','treino','privada') NOT NULL DEFAULT 'rankeada',
  -- Categoria da pista no momento da corrida (dimensao ORTOGONAL a `mode`;
  -- filtro de temporada = WHERE category='ranqueada' AND mode='rankeada'). #36
  `category`        ENUM('ranqueada','normal','personalizada') NOT NULL DEFAULT 'normal',
  `creator_char`    INT UNSIGNED     NOT NULL DEFAULT 0,
  `players_total`   INT UNSIGNED     NOT NULL DEFAULT 0,
  `winner_char`     INT UNSIGNED     NOT NULL DEFAULT 0,
  `winner_time_ms`  BIGINT UNSIGNED  NOT NULL DEFAULT 0,
  `pot_total`       BIGINT UNSIGNED  NOT NULL DEFAULT 0,
  `started_at`      TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `finished_at`     TIMESTAMP        NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_hist_track` (`track_id`),
  KEY `idx_hist_winner` (`winner_char`),
  KEY `idx_hist_kind` (`kind`),
  KEY `idx_hist_mode` (`mode`),
  KEY `idx_hist_category` (`category`),
  KEY `idx_hist_started` (`started_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `vh_race_results` (
  `history_id`     BIGINT UNSIGNED  NOT NULL,
  `char_id`        INT UNSIGNED     NOT NULL,
  `nick`           VARCHAR(48)      NOT NULL DEFAULT '',
  `placement`      INT UNSIGNED     NOT NULL DEFAULT 0,
  `total_time_ms`  BIGINT UNSIGNED  NOT NULL DEFAULT 0,
  `best_lap_ms`    BIGINT UNSIGNED  NOT NULL DEFAULT 0,
  `drift_score`    INT UNSIGNED     NOT NULL DEFAULT 0,
  `top_speed`      INT UNSIGNED     NOT NULL DEFAULT 0,
  `finished`       TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `payout`         BIGINT UNSIGNED  NOT NULL DEFAULT 0,
  PRIMARY KEY (`history_id`, `char_id`),
  KEY `idx_res_char` (`char_id`),
  KEY `idx_res_placement` (`placement`),
  CONSTRAINT `fk_res_hist` FOREIGN KEY (`history_id`)
    REFERENCES `vh_race_history` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `vh_race_records` (
  `track_id`      VARCHAR(48)      NOT NULL,
  `char_id`       INT UNSIGNED     NOT NULL,
  `best_time_ms`  BIGINT UNSIGNED  NOT NULL DEFAULT 0,
  `best_drift`    INT UNSIGNED     NOT NULL DEFAULT 0,
  `top_speed`     INT UNSIGNED     NOT NULL DEFAULT 0,
  `runs`          INT UNSIGNED     NOT NULL DEFAULT 0,
  `wins`          INT UNSIGNED     NOT NULL DEFAULT 0,
  `updated_at`    TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`track_id`, `char_id`),
  KEY `idx_rec_best` (`track_id`, `best_time_ms`),
  CONSTRAINT `fk_rec_track` FOREIGN KEY (`track_id`)
    REFERENCES `vh_race_tracks` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `fk_rec_char` FOREIGN KEY (`char_id`)
    REFERENCES `vh_characters` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `vh_race_stats` (
  `char_id`        INT UNSIGNED     NOT NULL,
  `kind`           VARCHAR(24)      NOT NULL DEFAULT 'sprint',
  `runs`           INT UNSIGNED     NOT NULL DEFAULT 0,
  `wins`           INT UNSIGNED     NOT NULL DEFAULT 0,
  `podiums`        INT UNSIGNED     NOT NULL DEFAULT 0,
  `dnf`            INT UNSIGNED     NOT NULL DEFAULT 0,
  `total_payout`   BIGINT UNSIGNED  NOT NULL DEFAULT 0,
  `total_drift`    BIGINT UNSIGNED  NOT NULL DEFAULT 0,
  `top_speed`     INT UNSIGNED     NOT NULL DEFAULT 0,
  `best_time_ms`   BIGINT UNSIGNED  NOT NULL DEFAULT 0,
  `updated_at`    TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`char_id`, `kind`),
  CONSTRAINT `fk_stats_char` FOREIGN KEY (`char_id`)
    REFERENCES `vh_characters` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Ranqueado: rating PDL GLOBAL (cross-kind, estilo CS2). 1 linha por personagem.
-- Escritor UNICO = server/ranked.lua (Elo FFA, snapshot-read → UPSERT atomico).
-- `pdl` é INT com sinal: o delta de Elo pode ser negativo; clamp >= MIN_PDL no
-- escritor evita rating abaixo do piso (a coluna nunca recebe valor < 0 na pratica).
CREATE TABLE IF NOT EXISTS `vh_race_ranked` (
  `char_id`        INT UNSIGNED     NOT NULL,
  `pdl`            INT              NOT NULL DEFAULT 1000,
  `peak_pdl`       INT              NOT NULL DEFAULT 1000,
  `matches`        INT UNSIGNED     NOT NULL DEFAULT 0,
  `wins`           INT UNSIGNED     NOT NULL DEFAULT 0,
  `last_match_at`  INT UNSIGNED     NOT NULL DEFAULT 0,
  `updated_at`     TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`char_id`),
  KEY `idx_ranked_pdl` (`pdl`),
  CONSTRAINT `fk_ranked_char` FOREIGN KEY (`char_id`)
    REFERENCES `vh_characters` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
