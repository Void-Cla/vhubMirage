-- server/init.lua — bootstrap do vhub_coinshop: schema idempotente, seed, handlers institucionais replay-safe

VHubCoin = VHubCoin or {}
local Core = VHubCoin.Core


-- ============================================================
-- REGISTRO DE OWNERSHIP (L-04, L-13) — declarado no código (single source of truth)
-- ============================================================

-- [Domínio]      | [Escritor único]         | [Leitores]            | [Persistência]                  | [Contrato de escrita]
-- ----------------------------------------------------------------------------------------------------------------------------
-- Moedas (coin)  | vhub_coinshop (aqui)     | cliente via NUI       | CData key 'coinshop_coins'      | exports.vhub:setCData/getCData (batch do core)
-- Itens shop     | vhub_coinshop (aqui)     | cliente via NUI       | tabela vhub_coinshop_items      | SQL own (server/sql.lua) — admin CRUD via callback
-- Categorias     | vhub_coinshop (aqui)     | cliente via NUI       | tabela vhub_coinshop_categories | SQL own
-- Ofertas        | vhub_coinshop (aqui)     | cliente via NUI       | tabela vhub_coinshop_deals      | SQL own — expira por TTL SQL
-- Códigos Tebex  | vhub_coinshop (aqui)     | —                     | tabela vhub_coinshop_codes      | SQL own — status pending/redeemed (idempotente)
-- Resgates       | vhub_coinshop (aqui)     | —                     | tabela vhub_coinshop_redeems    | SQL own — audit only
-- Compras        | vhub_coinshop (aqui)     | admin via NUI         | tabela vhub_coinshop_purchases  | SQL own — audit only
-- Pix TX         | vhub_coinshop (pix_mp)   | —                     | tabela vhub_coinshop_pix_tx     | SQL own — ciclo pending→paid/expired; crédito via webhook MP
-- Settings UI    | vhub_coinshop (aqui)     | cliente via NUI       | GData key 'coinshop_ui_settings'| exports.vhub:setGData/getGData (blob JSON)
-- Discord avatar | vhub_coinshop (aqui)     | cliente via NUI       | cache VRAM efêmero (discordCache)| fetch HTTP opcional (pcall)


-- ============================================================
-- SCHEMA BOOTSTRAP — idempotente, InnoDB, utf8mb4_unicode_ci (§3.6)
-- ============================================================

-- aplica schema próprio (tabelas vhub_coinshop_*); FK ao core é INT UNSIGNED CASCADE
local function applySchema()
    -- Itens do shop (catálogo admin)
    SQL.execute([[
        CREATE TABLE IF NOT EXISTS vhub_coinshop_items (
            id               VARCHAR(50)  NOT NULL,
            name             VARCHAR(100) NOT NULL,
            description      VARCHAR(255) DEFAULT '',
            category         ENUM('vehicle','item','weapon','tool') NOT NULL DEFAULT 'item',
            tags             TEXT,
            price            INT          NOT NULL DEFAULT 0,
            images           TEXT,
            spawn_name       VARCHAR(50)  DEFAULT NULL,
            item_name        VARCHAR(50)  DEFAULT NULL,
            item_count       INT          DEFAULT 1,
            weapon_name      VARCHAR(50)  DEFAULT NULL,
            trending         TINYINT(1)   DEFAULT 0,
            custom_category  VARCHAR(50)  DEFAULT NULL,
            published        TINYINT(1)   NOT NULL DEFAULT 1,
            created_at       TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])

    -- Categorias custom (abas de navegação)
    SQL.execute([[
        CREATE TABLE IF NOT EXISTS vhub_coinshop_categories (
            id          VARCHAR(50)  NOT NULL,
            name        VARCHAR(100) NOT NULL,
            icon        VARCHAR(500) DEFAULT '',
            type        VARCHAR(20)  DEFAULT NULL,
            created_at  TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])

    -- Compras (audit) — FK ao core (vh_characters.id INT UNSIGNED CASCADE)
    SQL.execute([[
        CREATE TABLE IF NOT EXISTS vhub_coinshop_purchases (
            id            INT UNSIGNED NOT NULL AUTO_INCREMENT,
            char_id       INT UNSIGNED NOT NULL,
            item_id       VARCHAR(50)  NOT NULL,
            price         INT          NOT NULL,
            purchased_at  TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            KEY idx_char (char_id),
            CONSTRAINT fk_coinshop_purchases_char
                FOREIGN KEY (char_id) REFERENCES vh_characters(id)
                ON DELETE CASCADE ON UPDATE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])

    -- Ofertas promocionais (TTL por expires_at)
    SQL.execute([[
        CREATE TABLE IF NOT EXISTS vhub_coinshop_deals (
            id           VARCHAR(50)  NOT NULL,
            name         VARCHAR(100) NOT NULL,
            description  VARCHAR(255) DEFAULT '',
            price        INT          NOT NULL DEFAULT 0,
            image        VARCHAR(500) DEFAULT '',
            items        TEXT,
            expires_at   DATETIME     NOT NULL,
            created_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])

    -- Códigos Tebex (resgate) — idempotente por tbx_id UNIQUE
    SQL.execute([[
        CREATE TABLE IF NOT EXISTS vhub_coinshop_codes (
            id           INT UNSIGNED NOT NULL AUTO_INCREMENT,
            tbx_id       VARCHAR(100) NOT NULL,
            coins        INT          NOT NULL DEFAULT 0,
            status       ENUM('pending','redeemed') NOT NULL DEFAULT 'pending',
            redeemed_by  INT UNSIGNED DEFAULT NULL,
            redeemed_at  TIMESTAMP    NULL DEFAULT NULL,
            created_at   TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            UNIQUE KEY uk_tbx_id (tbx_id),
            KEY idx_status (status),
            CONSTRAINT fk_coinshop_codes_redeemer
                FOREIGN KEY (redeemed_by) REFERENCES vh_characters(id)
                ON DELETE SET NULL ON UPDATE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])

    -- Resgates (audit)
    SQL.execute([[
        CREATE TABLE IF NOT EXISTS vhub_coinshop_redeems (
            id            INT UNSIGNED NOT NULL AUTO_INCREMENT,
            char_id       INT UNSIGNED NOT NULL,
            redeem_key    VARCHAR(100) NOT NULL,
            coins_added   INT          NOT NULL DEFAULT 0,
            redeemed_at   TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            UNIQUE KEY uk_redeem_key (redeem_key),
            KEY idx_char (char_id),
            CONSTRAINT fk_coinshop_redeems_char
                FOREIGN KEY (char_id) REFERENCES vh_characters(id)
                ON DELETE CASCADE ON UPDATE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])

    -- Transações Pix MercadoPago (#60): ciclo de vida pending → paid/expired
    -- txid = id do pagamento MP; src é efêmero (jogador pode relog antes da confirmação)
    SQL.execute([[
        CREATE TABLE IF NOT EXISTS vhub_coinshop_pix_tx (
            id          INT UNSIGNED  NOT NULL AUTO_INCREMENT,
            txid        VARCHAR(64)   NOT NULL,
            char_id     INT UNSIGNED  NOT NULL,
            src         INT           NOT NULL,
            package_id  VARCHAR(50)   NOT NULL,
            coins       INT           NOT NULL DEFAULT 0,
            amount_brl  DECIMAL(10,2) NOT NULL,
            status      ENUM('pending','paid','expired') NOT NULL DEFAULT 'pending',
            created_at  DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
            expires_at  DATETIME      NOT NULL,
            paid_at     DATETIME      NULL DEFAULT NULL,
            PRIMARY KEY (id),
            UNIQUE KEY uk_txid (txid),
            KEY idx_char (char_id),
            KEY idx_status (status)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])
end


-- ============================================================
-- MIGRAÇÕES — upgrades idempotentes de schemas já existentes
-- ============================================================

local function columnType(tableName, columnName)
    local rows = SQL.query(
        'SELECT DATA_TYPE AS data_type FROM information_schema.COLUMNS ' ..
        'WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ? LIMIT 1',
        { tableName, columnName }
    )
    local row = rows and rows[1]
    return row and tostring(row.data_type or ''):lower() or nil
end

local function migrateSchema()
    if not columnType('vhub_coinshop_items', 'published') then
        SQL.execute(
            'ALTER TABLE vhub_coinshop_items ADD COLUMN published TINYINT(1) NOT NULL DEFAULT 1 AFTER custom_category'
        )
    end
    SQL.execute('UPDATE vhub_coinshop_items SET published = 1 WHERE published IS NULL')

    local dealExpires = columnType('vhub_coinshop_deals', 'expires_at')
    local dealCreated = columnType('vhub_coinshop_deals', 'created_at')
    if dealExpires ~= 'datetime' or dealCreated ~= 'datetime' then
        SQL.execute(
            'ALTER TABLE vhub_coinshop_deals MODIFY COLUMN expires_at DATETIME NOT NULL, ' ..
            'MODIFY COLUMN created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP'
        )
    end

    local pixCreated = columnType('vhub_coinshop_pix_tx', 'created_at')
    local pixExpires = columnType('vhub_coinshop_pix_tx', 'expires_at')
    local pixPaid = columnType('vhub_coinshop_pix_tx', 'paid_at')
    if pixCreated ~= 'datetime' or pixExpires ~= 'datetime' or pixPaid ~= 'datetime' then
        SQL.execute(
            'ALTER TABLE vhub_coinshop_pix_tx MODIFY COLUMN created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, ' ..
            'MODIFY COLUMN expires_at DATETIME NOT NULL, MODIFY COLUMN paid_at DATETIME NULL DEFAULT NULL'
        )
    end
end


-- ============================================================
-- SEED INICIAL — categorias padrão + pacotes de exemplo (apenas na 1ª carga)
-- ============================================================

-- insere categorias e itens padrão se o catálogo estiver vazio (idempotente via INSERT IGNORE)
local function seedDefaults()
    -- categorias canônicas (ícones SVG inline para não depender de CDN — A-10)
    SQL.execute(
        "INSERT IGNORE INTO vhub_coinshop_categories (id, name, icon, type) VALUES " ..
        "('vehicles','Veículos',?,'vehicle')," ..
        "('items','Itens',?,'item')," ..
        "('weapons','Armas',?,'weapon')," ..
        "('tools','Ferramentas',?,'tool')",
        { VHubCoin.Icons.car, VHubCoin.Icons.box, VHubCoin.Icons.weapon, VHubCoin.Icons.tools }
    )

    -- itens padrão (somente PT-BR nas descrições); categorias podem existir do schema manual
    local count = SQL.scalar('SELECT COUNT(*) FROM vhub_coinshop_items') or 0
    if tonumber(count) == 0 then VHubCoin.SeedItems() end
end


-- ============================================================
-- HANDLERS INSTITUCIONAIS — replay-guard L-17
-- ============================================================

-- carrega sessão do domínio quando o personagem entra (replay-safe)
AddEventHandler('vHub:characterLoad', function(user)
    if not user or not user.source or not user.char_id then return end
    local previous = Core.sessions[user.source]
    if previous and previous.char_id ~= user.char_id then
        VHubCoin.Coins.evict(previous.char_id)
    end
    Core.sessions[user.source] = {
        char_id    = user.char_id,
        identifier = user.identifier,
    }
    -- pré-aquece o cache de moedas (CData; VRAM-first)
    VHubCoin.Coins.get(user.char_id)
end)

-- reage ao spawn UMA vez por spawn real (core re-dispara em onResourceStart — L-17)
AddEventHandler('vHub:playerSpawn', function(user, _)
    if not user or not user.source then return end
    local spawns = tonumber(user.spawns) or 0
    if Core._seenSpawn[user.source] == spawns then return end -- replay → no-op
    Core._seenSpawn[user.source] = spawns

    -- garante que a sessão existe (caso characterLoad não tenha disparado ainda)
    if not Core.sessions[user.source] and user.char_id then
        Core.sessions[user.source] = { char_id = user.char_id, identifier = user.identifier }
    end
end)

-- limpa tudo de um jogador que saiu (sem leak por src — §5 antipadrões)
AddEventHandler('playerDropped', function()
    local src = source
    VHubCoin.Coins.onPlayerDropped(src)
    Core.sessions[src]    = nil
    Core._seenSpawn[src]  = nil
    Core.clearRatesFor(src)
    VHubCoin.Discord.onPlayerDropped(src)
end)


-- ============================================================
-- BOOT
-- ============================================================

-- quando o MySQL está pronto, aplica schema + seed + carrega caches
MySQL.ready(function()
    applySchema()
    migrateSchema()
    seedDefaults()
    VHubCoin.Items.loadAll()
    VHubCoin.Items.loadCategories()
    VHubCoin.Items.loadDeals()
    VHubCoin.Items.loadSettings()
    Core.log('bootstrap concluído — schema, seed, caches prontos')
end)

-- replay-guard extra: ao reiniciar este resource, recarrega caches (sem re-aplicar schema)
AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    Citizen.Wait(500) -- aguarda MySQL.ready se ainda não disparou
    if MySQL and MySQL.ready then
        pcall(function()
            VHubCoin.Items.loadAll()
            VHubCoin.Items.loadCategories()
            VHubCoin.Items.loadDeals()
            VHubCoin.Items.loadSettings()
        end)
    end
end)

AddEventHandler('onResourceStop', function(stopping)
    if stopping ~= GetCurrentResourceName() then return end
end)
