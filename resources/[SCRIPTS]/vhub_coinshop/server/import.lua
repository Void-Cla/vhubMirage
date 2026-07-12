-- server/import.lua — importação administrativa de snapshots externos para rascunhos locais

VHubCoin = VHubCoin or {}
local Core  = VHubCoin.Core
local Items = VHubCoin.Items
local M = {}
VHubCoin.Import = M


-- ============================================================
-- CONTRATO DAS FONTES — snapshots read-only; nunca globals de outro resource
-- ============================================================

local INV_CATEGORY = {
    consumivel = 'item',
    medico     = 'item',
    ferramenta = 'tool',
    arma       = 'weapon',
    eletronico = 'item',
    material   = 'item',
}


-- ============================================================
-- SANITIZAÇÃO E COLETA
-- ============================================================

local function cleanString(value, cap)
    if type(value) ~= 'string' and type(value) ~= 'number' then return nil end
    local text = tostring(value):gsub('^%s+', ''):gsub('%s+$', '')
    if text == '' then return nil end
    return text:sub(1, cap or 100)
end

local function importId(prefix, raw)
    local value = cleanString(raw, 80)
    if not value then return nil end
    value = value:lower():gsub('[^%w_]+', '_'):gsub('_+', '_'):gsub('^_+', ''):gsub('_+$', '')
    if value == '' then return nil end
    return (prefix .. value):sub(1, 50)
end

local function requestedSources(data)
    local raw = type(data) == 'table' and data.sources or {}
    return { inventory = raw.inventory == true, conce = raw.conce == true }
end

local function collectInventory()
    local out = {}
    local ok, rows = pcall(function() return exports.vhub_inventory:getCatalogSnapshot() end)
    if not ok or type(rows) ~= 'table' then return out, 'Inventário indisponível.' end

    for _, def in ipairs(rows) do
        local rawId = type(def) == 'table' and cleanString(def.id, 80) or nil
        local category = type(def) == 'table' and INV_CATEGORY[tostring(def.category or ''):lower()] or nil
        local id = rawId and category and importId('inv_', rawId) or nil
        local name = type(def) == 'table' and cleanString(def.name, 100) or nil
        if id and name then
            out[#out + 1] = {
                id = id, name = name, category = category, itemName = rawId,
                itemCount = 1, source = 'inventory', rawId = rawId,
            }
        end
    end
    return out
end

local function collectConce()
    local out = {}
    local ok, rows = pcall(function() return exports.vhub_conce:getCatalogSnapshot() end)
    if not ok or type(rows) ~= 'table' then return out, 'Concessionária indisponível.' end

    for _, def in ipairs(rows) do
        local model = type(def) == 'table' and cleanString(def.model, 80) or nil
        local id = model and importId('veh_', model) or nil
        local name = type(def) == 'table' and cleanString(def.name, 100) or nil
        if id and name then
            out[#out + 1] = {
                id = id, name = name, category = 'vehicle', spawnName = model,
                itemCount = 1, source = 'conce', rawId = model,
            }
        end
    end
    return out
end

local function collect(data)
    local sources = requestedSources(data)
    if not sources.inventory and not sources.conce then
        return nil, 'Selecione ao menos uma fonte.'
    end

    local all, errors = {}, {}
    if sources.inventory then
        local rows, reason = collectInventory()
        for _, row in ipairs(rows) do all[#all + 1] = row end
        if reason then errors[#errors + 1] = reason end
    end
    if sources.conce then
        local rows, reason = collectConce()
        for _, row in ipairs(rows) do all[#all + 1] = row end
        if reason then errors[#errors + 1] = reason end
    end

    if #all == 0 and #errors > 0 then return nil, table.concat(errors, ' ') end

    table.sort(all, function(a, b) return a.id < b.id end)
    local limit = math.max(1, math.min(1000, tonumber(VHubCoin.cfg.import.maxItems) or 500))
    local truncated = #all > limit
    while #all > limit do all[#all] = nil end
    return all, nil, { truncated = truncated, warnings = errors }
end

local function markExisting(items)
    local exists = {}
    local rows = SQL.query('SELECT id FROM vhub_coinshop_items') or {}
    for _, row in ipairs(rows) do exists[row.id] = true end
    for _, item in ipairs(items) do item.exists = exists[item.id] == true end
end


-- ============================================================
-- ESCRITA — lote idempotente; importação sempre nasce como rascunho
-- ============================================================

local function insertBatch(batch)
    local values, args = {}, {}
    for _, item in ipairs(batch) do
        values[#values + 1] = "(?, ?, '', ?, '[]', 0, '[]', ?, ?, ?, NULL, 0, NULL, 0)"
        args[#args + 1] = item.id
        args[#args + 1] = item.name
        args[#args + 1] = item.category
        args[#args + 1] = item.spawnName or nil
        args[#args + 1] = item.itemName or nil
        args[#args + 1] = item.itemCount or 1
    end
    if #values == 0 then return 0 end

    local affected = SQL.execute(
        'INSERT IGNORE INTO vhub_coinshop_items ' ..
        '(id, name, description, category, tags, price, images, spawn_name, item_name, item_count, weapon_name, trending, custom_category, published) VALUES ' ..
        table.concat(values, ', '),
        args
    )
    return math.max(0, tonumber(affected) or 0)
end

local function adminItems()
    local out = {}
    for _, item in ipairs(Items.list) do out[#out + 1] = Items.publicCopy(item, true) end
    return out
end


-- ============================================================
-- API DO DOMÍNIO — chamada somente pelo dispatcher admin
-- ============================================================

-- pré-visualiza snapshots externos sem mutar o catálogo
function M.preview(_src, data)
    local items, reason, meta = collect(data)
    if not items then return false, reason end
    markExisting(items)
    return true, {
        preview = items,
        total = #items,
        truncated = meta.truncated == true,
        warnings = meta.warnings,
    }
end

-- importa snapshots externos como rascunhos não publicáveis até edição explícita
function M.run(src, data)
    local items, reason, meta = collect(data)
    if not items then return false, reason end

    local inserted = 0
    local size = math.max(1, math.min(100, tonumber(VHubCoin.cfg.import.batchSize) or 100))
    for first = 1, #items, size do
        local batch, last = {}, math.min(first + size - 1, #items)
        for index = first, last do batch[#batch + 1] = items[index] end
        inserted = inserted + insertBatch(batch)
    end

    Items.loadAll()
    Items.loadCategories()
    Items.loadDeals()

    Core.log(('importação: src=%d inseriu %d rascunho(s)'):format(src, inserted))
    VHubCoin.Webhooks.fire('admin', 'Importação CoinShop', nil, {
        { name = 'Admin', value = Core.getPlayerName(src) .. ' (ID: ' .. tostring(src) .. ')', inline = true },
        { name = 'Rascunhos criados', value = tostring(inserted), inline = true },
    })

    return true, {
        inserted = inserted,
        total = #items,
        truncated = meta.truncated == true,
        items = adminItems(),
        message = ('%d rascunho(s) importado(s). Defina preço e publique no Catálogo.'):format(inserted),
    }
end


return M
