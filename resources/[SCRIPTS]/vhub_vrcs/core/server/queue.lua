---@diagnostic disable: undefined-global, lowercase-global

-- core/server/queue.lua — fila FIFO de render (escritor unico de vh_vrcs_jobs)
--                       + wrapper oxmysql compartilhado (VRCS.Db).
--
-- O renderer (FASE 2, instancia isolada) consome esta fila por CLAIM ATOMICO.
-- Aqui, no servidor principal, so ENFILEIRAMOS — nenhum render acontece.

VRCS = VRCS or {}


-- ============================================================
-- DB — wrapper oxmysql (resource externo usa exports.oxmysql direto, decisao #8)
-- ============================================================

local Db = {}; VRCS.Db = Db

-- execucao fire-and-forget (nao bloqueia a thread que fecha a corrida)
function Db.execute(query, params)
    exports.oxmysql:execute(query, params or {}, function() end)
end

-- query com callback (usada pelo renderer na FASE 2)
function Db.query(query, params, cb)
    exports.oxmysql:query(query, params or {}, cb or function() end)
end


-- ============================================================
-- QUEUE
-- ============================================================

local Q = {}; VRCS.Queue = Q

-- enfileira um job de render para o replay recem-fechado (idempotente por race_id)
function Q.enqueue(race_id, vhr_path)
    local now = os.time()
    Db.execute([[
        INSERT INTO vh_vrcs_jobs (race_id, vhr_path, status, created_at, updated_at)
        VALUES (?, ?, 'pending', ?, ?)
        ON DUPLICATE KEY UPDATE
            vhr_path = VALUES(vhr_path), status = 'pending', updated_at = VALUES(updated_at)
    ]], { race_id, vhr_path, now, now })
end

-- claim ATOMICO de 1 job pending (FASE 2 — renderer). Marca como 'claimed' para
-- um worker; o UPDATE...WHERE status='pending' LIMIT 1 garante exclusao mutua (L-12).
function Q.claim(worker)
    Db.execute([[
        UPDATE vh_vrcs_jobs
           SET status = 'claimed', claimed_by = ?, attempts = attempts + 1, updated_at = ?
         WHERE status = 'pending'
         ORDER BY created_at
         LIMIT 1
    ]], { tostring(worker or 'renderer'), os.time() })
end

-- marca o desfecho de um job (FASE 2 — renderer)
function Q.mark(race_id, status)
    if status ~= 'done' and status ~= 'failed' and status ~= 'pending' then return end
    Db.execute([[
        UPDATE vh_vrcs_jobs SET status = ?, updated_at = ? WHERE race_id = ?
    ]], { status, os.time(), race_id })
end
