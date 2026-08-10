---@diagnostic disable: undefined-global, param-type-mismatch
-- sql.lua — wrappers SQL do vhub_npcai (server-only, L-12)

VHubNpcAI     = VHubNpcAI or {}
VHubNpcAI.sql = {}
local S       = VHubNpcAI.sql


-- ============================================================
-- HELPERS DE QUERY (oxmysql via exports)
-- ============================================================

-- executa SELECT e retorna resultado síncrono
function S.query(sql, params)
    return exports.oxmysql:executeSync(sql, params or {})
end

-- executa INSERT/UPDATE/DELETE e retorna número de linhas afetadas
function S.exec(sql, params)
    return exports.oxmysql:executeSync(sql, params or {})
end

-- executa INSERT e retorna o insertId
function S.insert(sql, params)
    return exports.oxmysql:insertSync(sql, params or {})
end

-- escalar: retorna primeira coluna da primeira linha (ou nil)
function S.scalar(sql, params)
    local rows = S.query(sql, params)
    if rows and rows[1] then
        for _, v in pairs(rows[1]) do return v end
    end
    return nil
end


-- ============================================================
-- SCHEMA BOOTSTRAP
-- ============================================================

-- aplica o schema SQL em init — idempotente (IF NOT EXISTS)
function S.applySchema()
    local ok, err = pcall(function()
        exports.oxmysql:executeSync([[
            CREATE TABLE IF NOT EXISTS vhub_npcai_memory (
                id         INT UNSIGNED  NOT NULL AUTO_INCREMENT,
                char_id    INT UNSIGNED  NOT NULL,
                npc_id     VARCHAR(48)   NOT NULL,
                mkey       VARCHAR(64)   NOT NULL,
                mval       VARCHAR(255)  NOT NULL,
                weight     SMALLINT      NOT NULL DEFAULT 1,
                updated_at TIMESTAMP     DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (id),
                UNIQUE KEY uq_mem (char_id, npc_id, mkey),
                KEY idx_lookup (char_id, npc_id),
                CONSTRAINT fk_npcai_mem_char FOREIGN KEY (char_id)
                    REFERENCES vh_characters(id) ON DELETE CASCADE ON UPDATE CASCADE
            ) ENGINE=InnoDB CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        ]], {})

        exports.oxmysql:executeSync([[
            CREATE TABLE IF NOT EXISTS vhub_npcai_audit (
                id         INT UNSIGNED  NOT NULL AUTO_INCREMENT,
                char_id    INT UNSIGNED  NOT NULL,
                npc_id     VARCHAR(48)   NOT NULL,
                intent     VARCHAR(64)   NOT NULL DEFAULT 'unknown',
                stage      VARCHAR(16)   NOT NULL DEFAULT 'cache',
                stt_text   TEXT,
                created_at TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (id),
                KEY idx_audit_char (char_id),
                KEY idx_audit_npc  (npc_id),
                KEY idx_audit_ts   (created_at)
            ) ENGINE=InnoDB CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        ]], {})
    end)
    if not ok then
        VHubNpcAI.Log.error('schema apply falhou: ' .. tostring(err))
    end
end


-- ============================================================
-- MEMÓRIA POR (char_id × npc_id)
-- ============================================================

-- carrega todas as chaves de memória de um par char×npc
function S.loadMemory(charId, npcId)
    local rows = S.query(
        'SELECT mkey, mval, weight FROM vhub_npcai_memory WHERE char_id=? AND npc_id=?',
        { charId, npcId }
    )
    local mem = {}
    if rows then
        for _, r in ipairs(rows) do
            mem[r.mkey] = { val = r.mval, weight = r.weight }
        end
    end
    return mem
end

-- persiste uma chave de memória (upsert — L-13 escritor único)
function S.upsertMemory(charId, npcId, mkey, mval, weight)
    S.exec([[
        INSERT INTO vhub_npcai_memory (char_id, npc_id, mkey, mval, weight)
        VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE mval=VALUES(mval), weight=VALUES(weight), updated_at=CURRENT_TIMESTAMP
    ]], { charId, npcId, mkey, mval, weight or 1 })
end

-- apaga toda memória de um personagem (wipe)
function S.wipeCharMemory(charId)
    S.exec('DELETE FROM vhub_npcai_memory WHERE char_id=?', { charId })
end

-- apaga memória de um par char×npc
function S.wipeNpcMemory(charId, npcId)
    S.exec('DELETE FROM vhub_npcai_memory WHERE char_id=? AND npc_id=?', { charId, npcId })
end


-- ============================================================
-- AUDITORIA
-- ============================================================

-- insere linha de auditoria (não bloqueia — insert assíncrono)
function S.audit(charId, npcId, intent, stage, sttText)
    exports.oxmysql:insert(
        'INSERT INTO vhub_npcai_audit (char_id, npc_id, intent, stage, stt_text) VALUES (?,?,?,?,?)',
        { charId, npcId, intent or 'unknown', stage or 'cache', sttText or '' }
    )
end
