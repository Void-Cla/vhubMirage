CREATE TABLE IF NOT EXISTS vhub_npcai_memory (
    id         INT UNSIGNED     NOT NULL AUTO_INCREMENT,
    char_id    INT UNSIGNED     NOT NULL,
    npc_id     VARCHAR(48)      NOT NULL,
    mkey       VARCHAR(64)      NOT NULL,
    mval       VARCHAR(255)     NOT NULL,
    weight     SMALLINT         NOT NULL DEFAULT 1,
    updated_at TIMESTAMP        DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_mem (char_id, npc_id, mkey),
    KEY idx_lookup (char_id, npc_id),
    CONSTRAINT fk_npcai_mem_char FOREIGN KEY (char_id)
        REFERENCES vh_characters(id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS vhub_npcai_audit (
    id         INT UNSIGNED     NOT NULL AUTO_INCREMENT,
    char_id    INT UNSIGNED     NOT NULL,
    npc_id     VARCHAR(48)      NOT NULL,
    intent     VARCHAR(64)      NOT NULL DEFAULT 'unknown',
    stage      VARCHAR(16)      NOT NULL DEFAULT 'cache',
    stt_text   TEXT,
    created_at TIMESTAMP        DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_audit_char (char_id),
    KEY idx_audit_npc  (npc_id),
    KEY idx_audit_ts   (created_at)
) ENGINE=InnoDB CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
