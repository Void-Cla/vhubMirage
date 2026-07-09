-- server/init.lua — bootstrap do vhub_coinshop: schema idempotente, seed, handlers institucionais replay-safe

VHubCoin = VHubCoin or {}
local Core = VHubCoin.Core


-- ============================================================
-- REGISTRO DE OWNERSHIP (L-04, L-13) — declarado no código (single source of truth)
-- ============================================================

-- [Domínio]      | [Escritor único]         | [Leitores]            | [Persistência]                  | [Contrato de escrita]
-- ----------------------------------------------------------------------------------------------------------------------------
-- Moedas (coin)  | vhub_coinshop (aqui)     | cliente via NUI       | CData key 'coinshop_coins'     | exports.vhub:setCData/getCData (batch do core)
-- Itens shop     | vhub_coinshop (aqui)     | cliente via NUI       | tabela vhub_coinshop_items     | SQL own (server/sql.lua) — admin CRUD via callback
-- Categorias     | vhub_coinshop (aqui)     | cliente via NUI       | tabela vhub_coinshop_categories| SQL own
-- Ofertas        | vhub_coinshop (aqui)     | cliente via NUI       | tabela vhub_coinshop_deals     | SQL own — expira por TTL SQL
-- Códigos Tebex  | vhub_coinshop (aqui)     | —                     | tabela vhub_coinshop_codes     | SQL own — status pending/redeemed (idempotente)
-- Resgates       | vhub_coinshop (aqui)     | —                     | tabela vhub_coinshop_redeems   | SQL own — audit only
-- Compras        | vhub_coinshop (aqui)     | admin via NUI         | tabela vhub_coinshop_purchases | SQL own — audit only
-- Settings UI    | vhub_coinshop (aqui)     | cliente via NUI       | GData key 'coinshop_ui_settings' | exports.vhub:setGData/getGData (blob JSON)
-- Discord avatar | vhub_coinshop (aqui)     | cliente via NUI       | cache VRAM efêmero (discordCache) | fetch HTTP opcional (pcall)


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
            expires_at   TIMESTAMP    NOT NULL,
            created_at   TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
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
end


-- ============================================================
-- SEED INICIAL — categorias padrão + pacotes de exemplo (apenas na 1ª carga)
-- ============================================================

-- insere categorias e itens padrão se o catálogo estiver vazio (idempotente via INSERT IGNORE)
local function seedDefaults()
    local count = SQL.scalar('SELECT COUNT(*) FROM vhub_coinshop_categories') or 0
    if tonumber(count) > 0 then return end

    -- categorias canônicas (ícones SVG inline para não depender de CDN — A-10)
    SQL.execute(
        "INSERT IGNORE INTO vhub_coinshop_categories (id, name, icon, type) VALUES " ..
        "('vehicles','Veículos',?,'vehicle')," ..
        "('items','Itens',?,'item')," ..
        "('weapons','Armas',?,'weapon')," ..
        "('tools','Ferramentas',?,'tool')",
        { VHubCoin.Icons.car, VHubCoin.Icons.box, VHubCoin.Icons.weapon, VHubCoin.Icons.tools }
    )

    -- itens padrão (somente PT-BR nas descrições)
    VHubCoin.SeedItems()
end


-- ============================================================
-- HANDLERS INSTITUCIONAIS — replay-guard L-17
-- ============================================================

-- carrega sessão do domínio quando o personagem entra (replay-safe)
AddEventHandler('vHub:characterLoad', function(user)
    if not user or not user.source or not user.char_id then return end
    Core.sessions[user.source] = {
        char_id    = user.char_id,
        identifier = user.identifier,
    }
    -- pré-aquece o cache de moedas (CData; VRAM-first)
    VHubCoin.Coins.get(user.char_id)
end)

-- reage ao spawn UMA vez por spawn real (core re-dispara em onResourceStart — L-17)
AddEventHandler('vHub:playerSpawn', function(user, first)
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
    Core.sessions[src]    = nil
    Core._seenSpawn[src]  = nil
    Core.clearRatesFor(src)
    VHubCoin.TestDrive.onPlayerDropped(src)
    VHubCoin.Discord.onPlayerDropped(src)
end)


-- ============================================================
-- BOOT
-- ============================================================

-- quando o MySQL está pronto, aplica schema + seed + carrega caches
MySQL.ready(function()
    applySchema()
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

-- ao parar o resource, libera routing buckets de test-drive ativos
AddEventHandler('onResourceStop', function(stopping)
    if stopping ~= GetCurrentResourceName() then return end
    VHubCoin.TestDrive.resetAll()
end)
