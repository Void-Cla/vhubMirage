-- sql/schema.sql — vhub_vrcs (idempotente, aplicado em onResourceStart).
-- PKs/FKs canonicos: char_id = INT UNSIGNED (decisao #17). Sem FK (replays
-- sobrevivem a delecao de char/track; .vhr e artefato derivado).

CREATE TABLE IF NOT EXISTS vh_race_replays (
    race_id     VARCHAR(36)  NOT NULL,
    track_id    VARCHAR(64)  NOT NULL DEFAULT '',
    kind        VARCHAR(24)  NOT NULL DEFAULT 'sprint',
    category    VARCHAR(24)  NOT NULL DEFAULT 'normal',
    winner_char INT UNSIGNED NOT NULL DEFAULT 0,
    duration_s  INT UNSIGNED NOT NULL DEFAULT 0,
    players_n   INT UNSIGNED NOT NULL DEFAULT 0,
    size_bytes  INT UNSIGNED NOT NULL DEFAULT 0,
    vhr_path    VARCHAR(255) NOT NULL,
    created_at  INT UNSIGNED NOT NULL,
    PRIMARY KEY (race_id),
    KEY idx_replays_created (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS vh_vrcs_jobs (
    race_id    VARCHAR(36)  NOT NULL,
    vhr_path   VARCHAR(255) NOT NULL,
    status     ENUM('pending','claimed','done','failed') NOT NULL DEFAULT 'pending',
    attempts   INT UNSIGNED NOT NULL DEFAULT 0,
    claimed_by VARCHAR(64)  NOT NULL DEFAULT '',
    created_at INT UNSIGNED NOT NULL,
    updated_at INT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (race_id),
    KEY idx_jobs_status (status, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
