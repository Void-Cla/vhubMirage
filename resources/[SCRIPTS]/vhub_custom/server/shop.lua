---@diagnostic disable: undefined-global

-- server/shop.lua — catálogo físico da oficina; transação pertence ao vhub_inventory.
local CFG = VHubCustom.cfg

local function registrar(id, loja, produtos)
  return exports.vhub_inventory:registerStore(id, {
    x = loja.x, y = loja.y, z = loja.z, raio = loja.raio, titulo = loja.titulo,
    subtitulo = loja.subtitulo, max_quantidade = loja.max_quantidade, produtos = produtos,
  })
end

local function catalogoPerformance()
  local produtos = {}
  for _, parte in ipairs(VHubCustom.PartsCatalog.PARTS) do
    if type(parte.item) == 'string' and (tonumber(parte.price) or 0) > 0 then
      produtos[#produtos + 1] = { id = parte.id, item = parte.item, preco = math.floor(parte.price), familia = parte.family, descricao = parte.desc }
    end
  end
  return produtos
end

local function catalogoMecanica()
  local produtos = {}
  for _, item in ipairs(CFG.loja_mecanica_itens or {}) do
    produtos[#produtos + 1] = { id = item.id, item = item.id, preco = item.preco, familia = 'mecânica' }
  end
  return produtos
end

local function registrarLojas()
  local lojas = CFG.lojas or {}
  if lojas.performance then registrar('oficina_pecas', lojas.performance, catalogoPerformance()) end
  if lojas.mecanica then registrar('mecanica_suprimentos', lojas.mecanica, catalogoMecanica()) end
end

AddEventHandler('onResourceStart', function(resource)
  if resource == GetCurrentResourceName() then registrarLojas() end
end)

AddEventHandler('onResourceStop', function(resource)
  if resource == GetCurrentResourceName() then exports.vhub_inventory:unregisterStoresByOwner() end
end)
