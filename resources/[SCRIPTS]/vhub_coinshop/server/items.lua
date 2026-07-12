-- server/items.lua — catálogo (itens, categorias, ofertas, settings UI) com loaders e admin CRUD

VHubCoin = VHubCoin or {}
local Core = VHubCoin.Core
local Items = {}
VHubCoin.Items = Items


-- ============================================================
-- ÍCONES SVG INLINE — sem CDN (A-10); base64 para não quebrar no SQL
-- ============================================================

VHubCoin.Icons = {
    car    = 'data:image/svg+xml;utf8,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="%23f3b53a" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M5 17h14M5 17a2 2 0 01-2-2v-3l2-4h10l2 4v3a2 2 0 01-2 2M5 17a1.5 1.5 0 100-3 1.5 1.5 0 000 3zm14 0a1.5 1.5 0 100-3 1.5 1.5 0 000 3z"/><path d="M5 10h14"/></svg>',
    box    = 'data:image/svg+xml;utf8,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="%23f3b53a" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M21 8l-9-5-9 5v8l9 5 9-5V8z"/><path d="M3 8l9 5 9-5M12 13v8"/></svg>',
    weapon = 'data:image/svg+xml;utf8,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="%23f3b53a" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="8"/><path d="M12 2v4M12 18v4M2 12h4M18 12h4"/><circle cx="12" cy="12" r="2"/></svg>',
    tools  = 'data:image/svg+xml;utf8,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="%23f3b53a" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M14.7 6.3a1 1 0 000 1.4l1.6 1.6a1 1 0 001.4 0l3-3A6 6 0 0112.7 15L5.4 21.3a2 2 0 01-2.8-2.8L9 11.3A6 6 0 0114.7 6.3z"/></svg>',
    home   = 'data:image/svg+xml;utf8,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="%23d9c19a" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M3 10.5L12 3l9 7.5V20a1 1 0 01-1 1h-4v-5a1 1 0 00-1-1h-2a1 1 0 00-1 1v5H5a1 1 0 01-1-1v-9.5z"/></svg>',
    tutorial = 'data:image/svg+xml;utf8,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="%23d9c19a" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="18" height="18" rx="2"/><path d="M7 8h10M7 12h10M7 16h6"/></svg>',
    redeem = 'data:image/svg+xml;utf8,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="%23d9c19a" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M2 9V6a1 1 0 011-1h18a1 1 0 011 1v3a2 2 0 100 4v3a1 1 0 01-1 1H3a1 1 0 01-1-1v-3a2 2 0 100-4z"/><path d="M9 12l2 2 4-4"/></svg>',
    admin  = 'data:image/svg+xml;utf8,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="%23d9c19a" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2l8 4v6c0 5-3.5 9-8 10-4.5-1-8-5-8-10V6l8-4z"/></svg>',
    coin   = 'data:image/svg+xml;utf8,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="10" fill="%23f3b53a"/><circle cx="12" cy="12" r="8" fill="none" stroke="%23a89572" stroke-width="1"/><text x="12" y="16.5" text-anchor="middle" font-family="Arial,sans-serif" font-weight="bold" font-size="12" fill="%230c0a06">$</text></svg>',
}


-- ============================================================
-- CACHE EM VRAM — lido pela NUI via getInitData
-- ============================================================

Items.list        = {}   -- array de itens (id, name, description, category, tags, price, images, spawnName, itemName, itemCount, weaponName, trending, customCategory)
Items.categories  = {}   -- array de categorias (id, name, icon, type)
Items.deals       = {}   -- array de ofertas ativas (id, name, description, price, image, items[], remainingSeconds)
Items.settings    = {}   -- mapa key→value (UI customization)

local SETTINGS_KEYS = {
    accentColor = true, bgColor = true, textColor = true, errorColor = true,
    cardBorderColor = true, bgImage = true, bgOpacity = true, bgBlur = true,
    cardBgOpacity = true, cardBorderRadius = true, coinIcon = true,
}

-- Decodifica somente tabelas; dado SQL/GData corrompido falha fechado.
local function decodeTable(value)
    if type(value) == 'table' then return value end
    if type(value) ~= 'string' or value == '' then return nil end
    local ok, decoded = pcall(json.decode, value)
    return ok and type(decoded) == 'table' and decoded or nil
end


-- ============================================================
-- LOADERS
-- ============================================================

-- carrega todos os itens do DB para o cache (chamado no boot e após admin CRUD)
function Items.loadAll()
    local rows = SQL.query('SELECT id, name, description, category, tags, price, images, spawn_name, item_name, item_count, weapon_name, trending, custom_category, published FROM vhub_coinshop_items ORDER BY created_at ASC')
    local list = {}
    for _, r in ipairs(rows or {}) do
        list[#list + 1] = {
            id             = r.id,
            name           = r.name,
            description    = r.description or '',
            category       = r.category,
            tags           = decodeTable(r.tags) or {},
            price          = tonumber(r.price) or 0,
            images         = decodeTable(r.images) or {},
            spawnName      = r.spawn_name,
            itemName       = r.item_name,
            itemCount      = tonumber(r.item_count) or 1,
            weaponName     = r.weapon_name,
            trending       = tonumber(r.trending) == 1,
            customCategory = r.custom_category,
            published      = r.published == nil or tonumber(r.published) ~= 0,
        }
    end
    Items.list = list
end

-- carrega categorias (inclui as 4 padrão + custom criadas via admin)
function Items.loadCategories()
    local rows = SQL.query('SELECT id, name, icon, type FROM vhub_coinshop_categories ORDER BY created_at ASC')
    local list = {}
    for _, r in ipairs(rows or {}) do
        list[#list + 1] = { id = r.id, name = r.name, icon = r.icon or '', type = r.type }
    end
    Items.categories = list
end

-- carrega ofertas ativas (não expiradas) com remaining_seconds (TTL SQL)
function Items.loadDeals()
    local rows = SQL.query(
        'SELECT id, name, description, price, image, items, ' ..
        'TIMESTAMPDIFF(SECOND, NOW(), expires_at) AS remaining_seconds ' ..
        'FROM vhub_coinshop_deals WHERE expires_at > NOW() ORDER BY created_at DESC'
    )
    local list = {}
    for _, r in ipairs(rows or {}) do
        local itemIds = decodeTable(r.items) or {}
        local resolved = {}
        for _, itemId in ipairs(itemIds) do
            local found = Items.find(itemId)
            if found then
                resolved[#resolved + 1] = {
                    id = found.id, name = found.name, price = found.price,
                    images = found.images, category = found.category,
                }
            end
        end
        list[#list + 1] = {
            id               = r.id,
            name             = r.name,
            description      = r.description or '',
            price            = tonumber(r.price) or 0,
            image            = r.image or '',
            items            = resolved,
            remainingSeconds = math.max(0, tonumber(r.remaining_seconds) or 0),
        }
    end
    Items.deals = list
end

-- carrega settings de UI do GData (blob JSON); fallback para defaults canônicos vHub
function Items.loadSettings()
    local ok, blob = pcall(function() return exports.vhub:getGData('coinshop_ui_settings') end)
    local parsed = ok and decodeTable(blob) or nil
    local settings = Items.defaultSettings()
    if parsed then
        for key, value in pairs(parsed) do
            if SETTINGS_KEYS[key] and type(value) == 'string' and #value <= 500 then
                settings[key] = value
            end
        end
    end
    Items.settings = settings
end


-- ============================================================
-- DEFAULTS — UI customization (paleta vHub canônica, não lime)
-- ============================================================

function Items.defaultSettings()
    return {
        accentColor      = '#f3b53a',  -- vh-gold (destaque primário)
        bgColor          = '#0c0a06',  -- vh-black (fundo profundo)
        textColor        = '#d9c19a',  -- vh-sand (texto suave)
        errorColor       = '#e8513f',  -- vh-danger
        cardBorderColor  = 'rgba(243,181,58,0.18)',
        bgImage          = '',
        bgOpacity        = '0.50',
        bgBlur           = '3',
        cardBgOpacity    = '0.06',
        cardBorderRadius = '10',
        coinIcon         = VHubCoin.Icons.coin,
    }
end


-- ============================================================
-- HELPERS DE BUSCA
-- ============================================================

-- retorna item por id (cache VRAM; O(n) pequeno, catálogo admin é < 100)
function Items.find(itemId)
    for _, item in ipairs(Items.list) do
        if item.id == itemId then return item end
    end
    return nil
end

-- retorna uma cópia rasa do item; admin recebe a flag de publicação
function Items.publicCopy(item, withAdmin)
    if not item then return nil end
    local out = {
        id             = item.id,
        name           = item.name,
        description    = item.description,
        category       = item.category,
        tags           = item.tags,
        price          = item.price,
        images         = item.images,
        spawnName      = item.spawnName,
        itemName       = item.itemName,
        itemCount      = item.itemCount,
        weaponName     = item.weaponName,
        trending       = item.trending,
        customCategory = item.customCategory,
    }
    if withAdmin then out.published = item.published == true end
    return out
end

-- retorna ofertas cujos itens permanecem publicáveis para jogadores
function Items.publicDeals(withAdmin)
    if withAdmin then return Items.deals end
    local out = {}
    for _, deal in ipairs(Items.deals) do
        local visible = #deal.items > 0
        for _, dealItem in ipairs(deal.items) do
            local item = Items.find(dealItem.id)
            if not item or item.published ~= true then visible = false break end
        end
        if visible then out[#out + 1] = deal end
    end
    return out
end


-- ============================================================
-- ADMIN CRUD — ITENS
-- ============================================================

-- cria item (validação shape → check duplicidade → insert → reload cache)
function Items.adminCreate(src, data)
    if not VHubCoin.isNonEmptyStr(data and data.name) then
        return false, T('item_name_required')
    end
    local category = data.category
    if category ~= 'vehicle' and category ~= 'item' and category ~= 'weapon' and category ~= 'tool' then
        category = 'item'
    end
    local price = VHubCoin.clamp(tonumber(data.price) or 0, 0, 1000000)
    if data.published ~= false and price < 1 then return false, T('item_price_required') end

    local itemId = VHubCoin.isNonEmptyStr(data.id) and data.id
        or (string.lower(data.name:gsub('%s+', '_'):gsub('[^%w_]', '')) .. '_' .. math.random(1000, 9999))

    if SQL.scalar('SELECT id FROM vhub_coinshop_items WHERE id = ?', { itemId }) then
        return false, T('item_id_exists')
    end

    local customCat = VHubCoin.isNonEmptyStr(data.customCategory) and data.customCategory or nil

    SQL.insert(
        'INSERT INTO vhub_coinshop_items ' ..
        '(id, name, description, category, tags, price, images, spawn_name, item_name, item_count, weapon_name, trending, custom_category, published) ' ..
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        {
            itemId, data.name, data.description or '', category,
            json.encode(VHubCoin.isStrArray(data.tags, 50, 20) and data.tags or {}),
            price,
            json.encode(VHubCoin.isStrArray(data.images, 500, 10) and data.images or {}),
            VHubCoin.isNonEmptyStr(data.spawnName) and data.spawnName or nil,
            VHubCoin.isNonEmptyStr(data.itemName) and data.itemName or nil,
            VHubCoin.clamp(tonumber(data.itemCount) or 1, 1, 1000),
            VHubCoin.isNonEmptyStr(data.weaponName) and data.weaponName or nil,
            data.trending and 1 or 0,
            customCat,
            data.published == false and 0 or 1,
        }
    )
    Items.loadAll()
    Items.loadDeals()
    Core.log('item criado por admin', src, itemId)
    return true, T('item_created', data.name)
end

-- edita item existente
function Items.adminEdit(src, data)
    if not VHubCoin.isNonEmptyStr(data and data.id) then return false, T('item_id_required') end
    if not VHubCoin.isNonEmptyStr(data and data.name) then return false, T('item_name_required') end
    if not SQL.scalar('SELECT id FROM vhub_coinshop_items WHERE id = ?', { data.id }) then
        return false, T('item_not_found')
    end
    local category = data.category
    if category ~= 'vehicle' and category ~= 'item' and category ~= 'weapon' and category ~= 'tool' then
        category = 'item'
    end
    local price = VHubCoin.clamp(tonumber(data.price) or 0, 0, 1000000)
    if data.published ~= false and price < 1 then return false, T('item_price_required') end
    local customCat = VHubCoin.isNonEmptyStr(data.customCategory) and data.customCategory or nil

    SQL.execute(
        'UPDATE vhub_coinshop_items SET name=?, description=?, category=?, tags=?, price=?, images=?, ' ..
        'spawn_name=?, item_name=?, item_count=?, weapon_name=?, trending=?, custom_category=?, published=? WHERE id=?',
        {
            data.name, data.description or '', category,
            json.encode(VHubCoin.isStrArray(data.tags, 50, 20) and data.tags or {}),
            price,
            json.encode(VHubCoin.isStrArray(data.images, 500, 10) and data.images or {}),
            VHubCoin.isNonEmptyStr(data.spawnName) and data.spawnName or nil,
            VHubCoin.isNonEmptyStr(data.itemName) and data.itemName or nil,
            VHubCoin.clamp(tonumber(data.itemCount) or 1, 1, 1000),
            VHubCoin.isNonEmptyStr(data.weaponName) and data.weaponName or nil,
            data.trending and 1 or 0,
            customCat, data.published == false and 0 or 1, data.id,
        }
    )
    Items.loadAll()
    Items.loadDeals()
    Core.log('item editado por admin', src, data.id)
    return true, T('item_updated', data.name)
end

-- deleta item
function Items.adminDelete(src, itemId)
    if not VHubCoin.isNonEmptyStr(itemId) then return false, T('item_id_required') end
    SQL.execute('DELETE FROM vhub_coinshop_items WHERE id = ?', { itemId })
    Items.loadAll()
    Items.loadDeals()
    Core.log('item deletado por admin', src, itemId)
    return true, T('item_deleted')
end


-- ============================================================
-- ADMIN CRUD — CATEGORIAS
-- ============================================================

function Items.adminCreateCategory(src, data)
    if not VHubCoin.isNonEmptyStr(data and data.name) then return false, T('category_name_required') end
    local catId = string.lower(data.name:gsub('%s+', '_'):gsub('[^%w_]', ''))
    if catId == '' then catId = 'cat_' .. math.random(1000, 9999) end
    if SQL.scalar('SELECT id FROM vhub_coinshop_categories WHERE id = ?', { catId }) then
        return false, T('category_exists')
    end
    SQL.insert(
        'INSERT INTO vhub_coinshop_categories (id, name, icon) VALUES (?, ?, ?)',
        { catId, data.name, VHubCoin.isNonEmptyStr(data.icon) and data.icon or '' }
    )
    Items.loadCategories()
    return true, T('category_created', data.name)
end

function Items.adminEditCategory(src, data)
    if not VHubCoin.isNonEmptyStr(data and data.id) then return false, T('category_id_required') end
    if not VHubCoin.isNonEmptyStr(data and data.name) then return false, T('category_name_required') end
    if not SQL.scalar('SELECT id FROM vhub_coinshop_categories WHERE id = ?', { data.id }) then
        return false, T('category_not_found')
    end
    SQL.execute(
        'UPDATE vhub_coinshop_categories SET name = ?, icon = ? WHERE id = ?',
        { data.name, VHubCoin.isNonEmptyStr(data.icon) and data.icon or '', data.id }
    )
    Items.loadCategories()
    return true, T('category_updated', data.name)
end

function Items.adminDeleteCategory(src, categoryId)
    if not VHubCoin.isNonEmptyStr(categoryId) then return false, T('category_id_required') end
    SQL.execute('DELETE FROM vhub_coinshop_categories WHERE id = ?', { categoryId })
    -- desvincula itens que apontavam para essa categoria custom
    SQL.execute('UPDATE vhub_coinshop_items SET custom_category = NULL WHERE custom_category = ?', { categoryId })
    Items.loadCategories()
    Items.loadAll()
    return true, T('category_deleted')
end


-- ============================================================
-- ADMIN CRUD — OFERTAS
-- ============================================================

function Items.adminCreateDeal(src, data)
    if not VHubCoin.isNonEmptyStr(data and data.name) then return false, T('deal_name_required') end
    local expiresIn = VHubCoin.isInt(data.expiresIn, 1, 86400 * 30) and tonumber(data.expiresIn) or nil
    if not expiresIn then return false, T('valid_expiry_required') end
    local itemIds = {}
    if type(data.items) == 'table' then
        for _, id in ipairs(data.items) do
            if VHubCoin.isNonEmptyStr(id) then itemIds[#itemIds + 1] = id end
        end
    end
    if #itemIds == 0 or #itemIds > 10 then return false, T('deal_items_limit') end

    local dealId = 'deal_' .. string.lower(data.name:gsub('%s+', '_'):gsub('[^%w_]', '')) .. '_' .. math.random(1000, 9999)
    -- limpa ofertas expiradas antes de inserir (housekeeping)
    SQL.execute('DELETE FROM vhub_coinshop_deals WHERE expires_at <= NOW()')
    SQL.insert(
        'INSERT INTO vhub_coinshop_deals (id, name, description, price, image, items, expires_at) ' ..
        'VALUES (?, ?, ?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL ? SECOND))',
        {
            dealId, data.name, data.description or '',
            VHubCoin.clamp(tonumber(data.price) or 0, 0, 1000000),
            VHubCoin.isNonEmptyStr(data.image) and data.image or '',
            json.encode(itemIds), expiresIn,
        }
    )
    Items.loadDeals()
    return true, T('deal_created', data.name)
end

-- edita oferta existente (#59 — não existia nem no FearX original); campos opcionais
-- mantêm o valor atual; expiresIn (segundos) REDEFINE a expiração a partir de agora
function Items.adminEditDeal(src, data)
    if not VHubCoin.isNonEmptyStr(data and data.id) then return false, T('deal_id_required') end
    local rows = SQL.query('SELECT id, name, description, price, image, items FROM vhub_coinshop_deals WHERE id = ? AND expires_at > NOW()', { data.id })
    if not rows or #rows == 0 then return false, T('deal_not_found') end
    local cur = rows[1]

    local itemIds = nil
    if type(data.items) == 'table' then
        itemIds = {}
        for _, id in ipairs(data.items) do
            if VHubCoin.isNonEmptyStr(id) then itemIds[#itemIds + 1] = id end
        end
        if #itemIds == 0 or #itemIds > 10 then return false, T('deal_items_limit') end
    end

    SQL.execute(
        'UPDATE vhub_coinshop_deals SET name=?, description=?, price=?, image=?, items=? WHERE id=?',
        {
            VHubCoin.isNonEmptyStr(data.name) and data.name or cur.name,
            data.description ~= nil and tostring(data.description) or cur.description,
            data.price ~= nil and VHubCoin.clamp(tonumber(data.price) or 0, 0, 1000000) or cur.price,
            VHubCoin.isNonEmptyStr(data.image) and data.image or (cur.image or ''),
            itemIds and json.encode(itemIds) or cur.items,
            data.id,
        }
    )
    if VHubCoin.isInt(data.expiresIn, 1, 86400 * 30) then
        SQL.execute(
            'UPDATE vhub_coinshop_deals SET expires_at = DATE_ADD(NOW(), INTERVAL ? SECOND) WHERE id = ?',
            { tonumber(data.expiresIn), data.id }
        )
    end
    Items.loadDeals()
    Core.log('oferta editada por admin', src, data.id)
    return true, T('deal_updated')
end

function Items.adminDeleteDeal(src, dealId)
    if not VHubCoin.isNonEmptyStr(dealId) then return false, T('deal_id_required') end
    SQL.execute('DELETE FROM vhub_coinshop_deals WHERE id = ?', { dealId })
    Items.loadDeals()
    return true, T('deal_deleted')
end


-- ============================================================
-- ADMIN — CÓDIGOS DE RESGATE (tabela vhub_coinshop_codes, dona: coinshop)
-- ============================================================

local KEY_CHARSET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'  -- sem 0/O/1/I (legibilidade)

-- gera chave de resgate SERVER-side (24 chars úteis; cliente NUNCA propõe a chave — #59/4.1).
-- math.random do Lua 5.4 é auto-seedado com entropia no boot; unicidade garantida
-- pelo UNIQUE(tbx_id) + retry
local function generateKey()
    local parts = {}
    for p = 1, 4 do
        local seg = {}
        for i = 1, 6 do
            local n = math.random(1, #KEY_CHARSET)
            seg[i] = KEY_CHARSET:sub(n, n)
        end
        parts[p] = table.concat(seg)
    end
    return 'VHC-' .. table.concat(parts, '-')
end

-- cria um código de resgate com `coins` moedas; retorna a chave gerada (mostrada 1x ao admin)
function Items.adminCreateCode(src, coins)
    coins = tonumber(coins)
    if not coins or coins <= 0 or coins > 10000000 then return false, T('invalid_data') end
    coins = math.floor(coins)

    for _ = 1, 5 do
        local key = generateKey()
        if not SQL.scalar('SELECT id FROM vhub_coinshop_codes WHERE tbx_id = ?', { key }) then
            SQL.insert(
                'INSERT INTO vhub_coinshop_codes (tbx_id, coins, status) VALUES (?, ?, ?)',
                { key, coins, 'pending' }
            )
            Core.log('código criado por admin', src, key)
            return true, key
        end
    end
    return false, T('invalid_data')  -- 5 colisões seguidas = impossível na prática
end

-- lista os últimos 20 códigos; chave em claro só nos pending (resgatado é mascarado — #59/4.4)
function Items.adminListCodes()
    local rows = SQL.query(
        'SELECT tbx_id, coins, status, redeemed_by, created_at FROM vhub_coinshop_codes ' ..
        'ORDER BY created_at DESC LIMIT 20'
    )
    local out = {}
    for _, r in ipairs(rows or {}) do
        local key = r.tbx_id
        if r.status ~= 'pending' and type(key) == 'string' and #key > 4 then
            key = '***-' .. key:sub(-4)
        end
        out[#out + 1] = {
            key        = key,
            coins      = tonumber(r.coins) or 0,
            status     = r.status,
            redeemedBy = r.redeemed_by,
            date       = r.created_at,
        }
    end
    return out
end

-- apaga um código AINDA pendente (resgatado é imutável — auditoria; WHERE server-side #59/4.2)
function Items.adminDeleteCode(src, key)
    if not VHubCoin.isNonEmptyStr(key) then return false, T('invalid_data') end
    local affected = SQL.execute(
        "DELETE FROM vhub_coinshop_codes WHERE tbx_id = ? AND status = 'pending'", { key }
    )
    if not affected or affected == 0 then return false, T('order_already_redeemed') end
    Core.log('código pendente apagado por admin', src, key)
    return true, T('code_deleted')
end


-- ============================================================
-- ADMIN — CLEAR ALL
-- ============================================================

-- limpa todos os itens, categorias custom e ofertas (mantém histórico de compras/resgates)
function Items.adminClearAll(src)
    SQL.execute('DELETE FROM vhub_coinshop_items')
    SQL.execute('DELETE FROM vhub_coinshop_categories')
    SQL.execute('DELETE FROM vhub_coinshop_deals')
    Items.loadAll()
    Items.loadCategories()
    Items.loadDeals()
    return true, T('all_cleared')
end


-- ============================================================
-- ADMIN — UI SETTINGS (GData blob JSON)
-- ============================================================

function Items.adminSaveSettings(src, data)
    if type(data) ~= 'table' then return false, T('invalid_data') end
    -- merge conservador: só aceita keys conhecidas e strings (anti-injection)
    local nextSettings = {}
    for key, value in pairs(Items.settings) do nextSettings[key] = value end
    for k, v in pairs(data) do
        if SETTINGS_KEYS[k] and type(v) == 'string' and #v <= 500 then
            nextSettings[k] = v
        end
    end
    local ok, res = pcall(function()
        return exports.vhub:setGData('coinshop_ui_settings', json.encode(nextSettings))
    end)
    if not ok or res == false then return false, T('settings_persistence_failed') end
    Items.settings = nextSettings
    return true, T('settings_saved')
end

function Items.adminResetSettings(src)
    local defaults = Items.defaultSettings()
    local ok, res = pcall(function()
        return exports.vhub:setGData('coinshop_ui_settings', json.encode(defaults))
    end)
    if not ok or res == false then return false, T('settings_persistence_failed') end
    Items.settings = defaults
    return true, T('settings_reset')
end


-- ============================================================
-- ADMIN — ESTATÍSTICAS (para o painel admin)
-- ============================================================

-- retorna { totalPackages, totalSales, coinsSpent24h, activePlayers }
function Items.adminStats()
    local totalSales   = tonumber(SQL.scalar('SELECT COALESCE(SUM(price), 0) FROM vhub_coinshop_purchases')) or 0
    local sales24h     = tonumber(SQL.scalar('SELECT COALESCE(SUM(price), 0) FROM vhub_coinshop_purchases WHERE purchased_at >= DATE_SUB(NOW(), INTERVAL 24 HOUR)')) or 0
    return {
        totalPackages = #Items.list,
        totalSales    = totalSales,
        coinsSpent24h = sales24h,
        activePlayers = #GetPlayers(),
    }
end

-- retorna últimas 10 transações (admin)
function Items.recentTransactions()
    local rows = SQL.query(
        'SELECT char_id, item_id, price, purchased_at FROM vhub_coinshop_purchases ORDER BY purchased_at DESC LIMIT 10'
    )
    local out = {}
    for _, r in ipairs(rows or {}) do
        local item = Items.find(r.item_id)
        out[#out + 1] = {
            charId  = r.char_id, itemId = r.item_id,
            itemName = (item and item.name) or r.item_id,
            price = r.price, date = r.purchased_at,
        }
    end
    return out
end

-- retorna top 5 itens mais vendidos
function Items.topSelling()
    local rows = SQL.query(
        'SELECT item_id, COUNT(*) AS sales FROM vhub_coinshop_purchases GROUP BY item_id ORDER BY sales DESC LIMIT 5'
    )
    local out = {}
    for _, r in ipairs(rows or {}) do
        local item = Items.find(r.item_id)
        out[#out + 1] = {
            itemId = r.item_id,
            name   = (item and item.name) or r.item_id,
            sales  = tonumber(r.sales) or 0,
        }
    end
    return out
end

-- retorna histórico completo (50 últimas) — admin
function Items.purchaseHistory()
    local rows = SQL.query(
        'SELECT char_id, item_id, price, purchased_at FROM vhub_coinshop_purchases ORDER BY purchased_at DESC LIMIT 50'
    )
    local out = {}
    for _, r in ipairs(rows or {}) do
        local item = Items.find(r.item_id)
        out[#out + 1] = {
            charId = r.char_id, itemId = r.item_id,
            itemName = (item and item.name) or r.item_id,
            price = r.price, date = r.purchased_at,
        }
    end
    return out
end


-- ============================================================
-- SEED — catálogo padrão (PT-BR; somente inserido se shop vazio)
-- ============================================================

function VHubCoin.SeedItems()
    -- Veículos de exemplo (descrições PT-BR)
    local vehicles = {
        { 'veh_adder',     'Truffade Adder',      'Hipercarro inspirado na Bugatti Veyron. Velocidade máxima que vai soprar sua mente.',         '["supercarro","rapido","luxo"]',  5000, '["https://raw.githubusercontent.com/MericcaN41/gta5carimages/main/images/adder.png"]',      'adder',      1 },
        { 'veh_zentorno',  'Pegassi Zentorno',    'Engenharia italiana na sua melhor forma. Uma bestialidade inspirada na Lamborghini.',         '["supercarro","corrida","rapido"]', 4500, '["https://raw.githubusercontent.com/MericcaN41/gta5carimages/main/images/zentorno.png"]',   'zentorno',   0 },
        { 'veh_t20',       'Progen T20',          'Obra-prima inspirada na McLaren P1. Leve, potente e absolutamente linda.',                    '["supercarro","corrida","premium"]', 5500, '["https://raw.githubusercontent.com/MericcaN41/gta5carimages/main/images/t20.png"]',         't20',        1 },
        { 'veh_elegy2',    'Annis Elegy RH8',     'Esportivo livre-espírito inspirado na Nissan GT-R. Rápido, confiável e favorito dos fãs.',    '["esportivo","jdm","corrida"]',     1500, '["https://raw.githubusercontent.com/MericcaN41/gta5carimages/main/images/elegy2.png"]',     'elegy2',     0 },
        { 'veh_sultanrs',  'Karin Sultan RS',     'Lenda tuner. Sedã inspirado em rally com sério poder sob o capô.',                            '["esportivo","tuner","jdm"]',       2000, '["https://raw.githubusercontent.com/MericcaN41/gta5carimages/main/images/sultanrs.png"]',   'sultanrs',   0 },
        { 'veh_banshee',   'Bravado Banshee',     'Muscular americano inspirado no Dodge Viper. Poder bruto e estilo clássico.',                '["esportivo","muscle","rapido"]',   1800, '["https://raw.githubusercontent.com/MericcaN41/gta5carimages/main/images/banshee.png"]',    'banshee',    0 },
        { 'veh_comet2',    'Pfister Comet',       'Clássico inspirado no Porsche 911. Equilíbrio perfeito entre velocidade e dirigibilidade.',   '["esportivo","classico","alemao"]', 2200, '["https://raw.githubusercontent.com/MericcaN41/gta5carimages/main/images/comet2.png"]',     'comet2',     0 },
        { 'veh_kuruma2',   'Karin Kuruma Blindada','Vidros à prova de balas e painéis reforçados — o veículo de fuga definitivo.',             '["blindado","a prova de balas","essencial"]', 3500, '["https://raw.githubusercontent.com/MericcaN41/gta5carimages/main/images/kuruma2.png"]', 'kuruma2', 1 },
        { 'veh_deluxo',    'Imponte Deluxo',      'Carro voador inspirado na DeLorean. Sim, ele voa. Modo hover incluído.',                     '["especial","voador","premium"]',  12000, '["https://raw.githubusercontent.com/MericcaN41/gta5carimages/main/images/deluxo.png"]',     'deluxo',     1 },
        { 'veh_vigilante', 'Vigilante',           'O Batmóvel de GTA. Boost de foguete, resistência a explosões e pura intimidação.',           '["especial","militar","foguete"]', 15000, '["https://raw.githubusercontent.com/MericcaN41/gta5carimages/main/images/vigilante.png"]',  'vigilante',  0 },
        { 'veh_bati',      'Pegassi Bati 801',    'Supermoto inspirada na Ducati. Rápida como um raio e manobrável como um sonho.',             '["moto","rapido","corrida"]',       1000, '["https://raw.githubusercontent.com/MericcaN41/gta5carimages/main/images/bati.png"]',       'bati',       0 },
        { 'veh_insurgent', 'HVY Insurgent',       'MRAP militar que pode receber rockets e continuar rodando. Não tema nada.',                  '["militar","blindado","pesado"]',   6000, '["https://raw.githubusercontent.com/MericcaN41/gta5carimages/main/images/insurgent.png"]',  'insurgent',  0 },
    }
    for _, v in ipairs(vehicles) do
        SQL.insert(
            'INSERT IGNORE INTO vhub_coinshop_items (id, name, description, category, tags, price, images, spawn_name, trending) ' ..
            'VALUES (?, ?, ?, "vehicle", ?, ?, ?, ?, ?)',
            { v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8] }
        )
    end

    -- Itens de inventário
    local items = {
        { 'item_repairkit',  'Kit de Reparo de Veículo', 'Conserte seu carro na hora. Sem precisar de mecânico. Tudo para reparos de campo.', '["essencial","veiculo","reparo"]', 350, '["https://raw.githubusercontent.com/McKleans-Scripts/mk-items/main/mechanic/repairkit.png"]', 'repairkit', 3 },
        { 'item_medkit',     'Kit de Primeiros Socorros',  'Kit médico militar. Cura você quando a situação fica difícil.',                  '["essencial","saude","medico"]', 300, '["https://raw.githubusercontent.com/McKleans-Scripts/mk-items/main/medical/firstaid_bandage.png"]', 'medikit', 5 },
        { 'item_bandage',    'Pacote de Bandagens',        'Pacote bulk com 10 bandagens. Tratamento rápido de ferimentos em campo.',         '["essencial","saude","medico"]', 200, '["https://raw.githubusercontent.com/McKleans-Scripts/mk-items/main/medical/bandage.png"]', 'bandage', 10 },
        { 'item_burger',     'Pacote Bleeder Burger',      'Pilha de 10 Bleeder Burgers do Burger Shot. Restaura saúde ao consumir.',         '["comida","saude","bulk"]', 250, '["https://raw.githubusercontent.com/McKleans-Scripts/mk-items/main/food/burgershot/burger-bleeder.png"]', 'burger', 10 },
        { 'item_sprunk',     'Caixa de Sprunk',            'Caixa cheia com 15 latinhas de Sprunk. O refrigerante extremo para gente extrema.', '["bebida","bulk","popular"]', 200, '["https://raw.githubusercontent.com/McKleans-Scripts/mk-items/main/drinks/soda/sprunk.png"]', 'sprunk', 15 },
        { 'item_ecola',      'Pacote eCola',               'Pacote com 10 latinhas de eCola. O sabor delicioso de Los Santos.',              '["bebida","bulk","popular"]', 180, '["https://raw.githubusercontent.com/McKleans-Scripts/mk-items/main/drinks/soda/ecola.png"]', 'ecola', 10 },
        { 'item_tablet',     'Tablet',                     'Tablet high-end. Acesse a dark web e gerencie suas operações.',                  '["tech","utilitario","premium"]', 1200, '["https://raw.githubusercontent.com/McKleans-Scripts/mk-items/main/tech/tablet.png"]', 'tablet', 1 },
        { 'item_drone',      'Drone de Vigilância',        'Drone compacto com câmera para reconhecimento aéreo.',                           '["tech","recon","premium"]', 2000, '["https://raw.githubusercontent.com/McKleans-Scripts/mk-items/main/tech/drone.png"]', 'drone', 1 },
    }
    for _, v in ipairs(items) do
        SQL.insert(
            'INSERT IGNORE INTO vhub_coinshop_items (id, name, description, category, tags, price, images, item_name, item_count, trending) ' ..
            'VALUES (?, ?, ?, "item", ?, ?, ?, ?, ?, ?)',
            { v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8], 0 }
        )
    end

    -- Armas
    local weapons = {
        { 'wep_pistol',         'Pistola de Combate',  'Sidearm 9mm confiável. Compacta, precisa e mortal à curta distância.',  '["pistola","sidearm","basico"]',     500, '["https://raw.githubusercontent.com/aifazi/items-images/main/weapons/pistol/weapon_combatpistol.png"]', 'WEAPON_COMBATPISTOL', 0 },
        { 'wep_pistol50',       'Pistola .50',         'Canhão de mão com impacto devastador. Um tiro basta.',                  '["pistola","potente","premium"]',    800, '["https://raw.githubusercontent.com/aifazi/items-images/main/weapons/pistol/weapon_pistol50.png"]', 'WEAPON_PISTOL50', 0 },
        { 'wep_smg',            'SMG',                 'Submetralhadora compacta para combate próximo. Alta cadência de tiro.', '["smg","automatica","cqb"]',        1200, '["https://raw.githubusercontent.com/aifazi/items-images/main/weapons/weapon_smg.png"]', 'WEAPON_SMG', 0 },
        { 'wep_carbine',        'Rifle Carabina',      'Rifle de assalto padrão. Equilíbrio de precisão, dano e cadência.',     '["rifle","assalto","versatil"]',    2000, '["https://raw.githubusercontent.com/aifazi/items-images/main/weapons/weapon_carbinerifle.png"]', 'WEAPON_CARBINERIFLE', 1 },
        { 'wep_specialcarbine', 'Carabina Especial',   'Rifle de assalto aprimorado, melhor precisão e trilho tático.',         '["rifle","assalto","tatico"]',      2500, '["https://raw.githubusercontent.com/aifazi/items-images/main/weapons/weapon_specialcarbine.png"]', 'WEAPON_SPECIALCARBINE', 0 },
        { 'wep_combatmg',       'Combat MG',           'Metralhadora de fita. Fogo supressivo devastador.',                     '["pesado","mg","supressao"]',       4000, '["https://raw.githubusercontent.com/aifazi/items-images/main/weapons/weapon_combatmg.png"]', 'WEAPON_COMBATMG', 0 },
        { 'wep_minigun',        'Minigun',             'Metralhadora rotativa com cadência insana. Destruição total.',         '["pesado","raro","premium"]',       8000, '["https://raw.githubusercontent.com/aifazi/items-images/main/weapons/weapon_minigun.png"]', 'WEAPON_MINIGUN', 1 },
        { 'wep_sniper',         'Rifle Sniper',        'Sniper de ação por ferrolho para engagements de longa distância.',      '["sniper","longrange","precisao"]', 3000, '["https://raw.githubusercontent.com/aifazi/items-images/main/weapons/sniper/weapon_sniperrifle.png"]', 'WEAPON_SNIPERRIFLE', 0 },
        { 'wep_heavysniper',    'Sniper Pesado',       'Rifle anti-material que atravessa blindados. Poder devastador.',        '["sniper","pesado","premium"]',     5000, '["https://raw.githubusercontent.com/aifazi/items-images/main/weapons/sniper/weapon_heavysniper.png"]', 'WEAPON_HEAVYSNIPER', 0 },
    }
    for _, v in ipairs(weapons) do
        SQL.insert(
            'INSERT IGNORE INTO vhub_coinshop_items (id, name, description, category, tags, price, images, weapon_name, trending) ' ..
            'VALUES (?, ?, ?, "weapon", ?, ?, ?, ?, ?)',
            { v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8] }
        )
    end

    -- Ferramentas
    local tools = {
        { 'tool_binoculars',     'Binóculos',           'Binóculos militares de alto poder. Veja seus alvos a uma distância segura.', '["recon","tatico","utilitario"]',  400, '["https://raw.githubusercontent.com/McKleans-Scripts/mk-items/main/tools/binoculars.png"]', 'binoculars', 1 },
        { 'tool_metaldetector',  'Detector de Metal',   'Encontre tesouros enterrados e valiosos ocultos. Item essencial para caçadores.', '["tesouro","hobby","outdoor"]', 600, '["https://raw.githubusercontent.com/McKleans-Scripts/mk-items/main/tools/metaldetector.png"]', 'metaldetector', 1 },
        { 'tool_safecracker',    'Kit Arrombador de Cofre','Ferramentas profissionais para arrombar cofres. Alto risco, alta recompensa.', '["heist","utilitario","premium"]', 1500, '["https://raw.githubusercontent.com/McKleans-Scripts/mk-items/main/tools/safecracker.png"]', 'safecracker', 1 },
        { 'tool_screwdriver',    'Jogo de Chaves de Fenda','Conjunto completo de chaves de precisão. Essencial para qualquer trabalho.', '["mecanico","reparo","basico"]', 250, '["https://raw.githubusercontent.com/McKleans-Scripts/mk-items/main/tools/screwdriverset_red.png"]', 'screwdriverset', 1 },
        { 'tool_gps',            'Rastreador GPS',      'Dispositivo avançado de rastreamento. Acompanhe veículos em tempo real.',  '["tech","rastreamento","utilitario"]', 800, '["https://raw.githubusercontent.com/McKleans-Scripts/mk-items/main/tech/garmin-gps.png"]', 'gps', 1 },
        { 'tool_handcuffs',      'Algemas',             'Algemas profissionais. Para quem precisa prender alguém temporariamente.',  '["restricao","lei","utilitario"]', 350, '["https://raw.githubusercontent.com/McKleans-Scripts/mk-items/main/police/handcuffs.png"]', 'handcuffs', 1 },
        { 'tool_nightvision',    'Óculos de Visão Noturna','NVG militar para operar em escuridão total. Veja tudo.',                  '["tatico","militar","premium"]', 2000, '["https://raw.githubusercontent.com/McKleans-Scripts/mk-items/main/tech/nightvision.png"]', 'nightvision', 1 },
        { 'tool_bodycam',        'Câmera Corporal',     'Grave tudo que acontece. Evidência perfeita para qualquer situação.',       '["lei","gravacao","utilitario"]', 500, '["https://raw.githubusercontent.com/McKleans-Scripts/mk-items/main/police/bodycam.png"]', 'bodycam', 1 },
    }
    for _, v in ipairs(tools) do
        SQL.insert(
            'INSERT IGNORE INTO vhub_coinshop_items (id, name, description, category, tags, price, images, item_name, item_count, trending) ' ..
            'VALUES (?, ?, ?, "tool", ?, ?, ?, ?, ?, ?)',
            { v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8], 0 }
        )
    end

    Core.log('seed aplicado — veículos/itens/armas/ferramentas padrão inseridos')
end
