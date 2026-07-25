---@diagnostic disable: undefined-global, lowercase-global

-- server/migrations.lua — runner forward-only de alterações de schema.
-- Corre sempre no boot (independente de inventory_vnext).
-- Cada migração é idempotente: verificamos information_schema antes de ALTER.

local M = {}; Inventory.Migrations = M

local SQL = nil   -- setado por M.init() antes de runAll()


-- ============================================================
-- HELPERS INTERNOS
-- ============================================================

-- true se a coluna já existe (portável MySQL 5.7+ / MariaDB 10.0+)
local function column_exists(tbl, col, exec, qry)
  local r = qry([[
    SELECT COUNT(*) AS cnt
    FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME   = ?
      AND COLUMN_NAME  = ?
  ]], { tbl, col })
  return r and r[1] and tonumber(r[1].cnt) > 0
end


-- ============================================================
-- CATÁLOGO DE MIGRAÇÕES (ordem crescente, forward-only)
-- ============================================================
-- checksum = string curta; detecta alteração acidental de migração já aplicada.
-- up(exec, qry): executa DDL; retorna true em sucesso, false em falha.

local MIGRATIONS = {

  -- M001: revision + schema_version + checksum + payload em vhub_inv_player
  {
    version  = 1,
    name     = 'player_revision_payload',
    checksum = 'a1b2c3d4e5f6a7b8',
    up = function(exec, qry)
      if not column_exists('vhub_inv_player', 'revision', exec, qry) then
        exec('ALTER TABLE vhub_inv_player ADD COLUMN `revision` BIGINT UNSIGNED NOT NULL DEFAULT 0', {})
      end
      if not column_exists('vhub_inv_player', 'schema_version', exec, qry) then
        exec('ALTER TABLE vhub_inv_player ADD COLUMN `schema_version` SMALLINT UNSIGNED NOT NULL DEFAULT 1', {})
      end
      if not column_exists('vhub_inv_player', 'checksum', exec, qry) then
        exec('ALTER TABLE vhub_inv_player ADD COLUMN `checksum` CHAR(64) NULL', {})
      end
      if not column_exists('vhub_inv_player', 'payload', exec, qry) then
        exec('ALTER TABLE vhub_inv_player ADD COLUMN `payload` BLOB NULL', {})
      end
      return true
    end,
  },

  -- M002: revision + schema_version + payload em vhub_inv_containers
  {
    version  = 2,
    name     = 'container_revision_payload',
    checksum = 'b2c3d4e5f6a7b8c9',
    up = function(exec, qry)
      if not column_exists('vhub_inv_containers', 'revision', exec, qry) then
        exec('ALTER TABLE vhub_inv_containers ADD COLUMN `revision` BIGINT UNSIGNED NOT NULL DEFAULT 0', {})
      end
      if not column_exists('vhub_inv_containers', 'schema_version', exec, qry) then
        exec('ALTER TABLE vhub_inv_containers ADD COLUMN `schema_version` SMALLINT UNSIGNED NOT NULL DEFAULT 1', {})
      end
      if not column_exists('vhub_inv_containers', 'payload', exec, qry) then
        exec('ALTER TABLE vhub_inv_containers ADD COLUMN `payload` BLOB NULL', {})
      end
      return true
    end,
  },

}


-- ============================================================
-- RUNNER
-- ============================================================

-- recebe os wrappers de sql diretamente para evitar acoplamento circular
-- deve ser chamado dentro de Citizen.CreateThread (usa Citizen.Await)
function M.runAll()
  if not SQL then
    SQL = Inventory.SQL
  end

  local exec = SQL.execute
  local qry  = SQL.query

  for _, m in ipairs(MIGRATIONS) do

    -- verifica se já foi aplicada
    local applied = qry(
      'SELECT checksum FROM vhub_inv_schema_migrations WHERE version = ? LIMIT 1',
      { m.version }
    )

    if applied and applied[1] then
      -- detecta alteração acidental de migração já aplicada
      if applied[1].checksum ~= m.checksum then
        Inventory.Utils.quarantine(0, m.name,
          ('migracao %d: checksum diverge (esperado=%s aplicado=%s)'):format(
            m.version, m.checksum, tostring(applied[1].checksum)))
      end
      -- pula (já aplicada)
    else

      -- aplica a migração
      local ok, err = pcall(m.up, exec, qry)
      if not ok or err == false then
        Inventory.Utils.quarantine(0, m.name,
          ('migracao %d falhou: %s'):format(m.version, tostring(err)))
        return false   -- bloqueia boot; Inventory.ready permanece false
      end

      -- registra a migração como aplicada
      exec(
        'INSERT INTO vhub_inv_schema_migrations (version, name, checksum) VALUES (?, ?, ?)',
        { m.version, m.name, m.checksum }
      )
    end

  end

  return true
end
