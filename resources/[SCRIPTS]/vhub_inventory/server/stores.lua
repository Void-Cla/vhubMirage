---@diagnostic disable: undefined-global, lowercase-global

-- server/stores.lua — compra física genérica; catálogo externo, transação do inventário.
local M = {}; Inventory.Stores = M
local Bag, U, E = Inventory.Bag, Inventory.Utils, VHubInvE
local lojas, sessoes, operacoes = {}, {}, {}

local function copiaProduto(produto)
  if type(produto) ~= 'table' or type(produto.id) ~= 'string' or type(produto.item) ~= 'string' then return nil end
  local preco = tonumber(produto.preco)
  if not preco or preco % 1 ~= 0 or preco < 1 or preco > 100000000 then return nil end
  if not U.itemDef(produto.item) then return nil end
  return { id = produto.id, item = produto.item, preco = preco, familia = tostring(produto.familia or 'itens'):sub(1, 32), descricao = tostring(produto.descricao or ''):sub(1, 240) }
end

local function lojaPerto(src, loja)
  local ped = GetPlayerPed(src)
  if not ped or ped == 0 then return false end
  local ok, pos = pcall(GetEntityCoords, ped)
  if not ok or not pos then return false end
  local dx, dy, dz = pos.x - loja.x, pos.y - loja.y, pos.z - loja.z
  return dx * dx + dy * dy + dz * dz <= (loja.raio + 1.0) ^ 2
end

local function token(src)
  return ('%x:%x:%x'):format(src, os.time(), GetGameTimer() & 0xffffffff)
end

function M.register(id, definition, owner)
  if type(id) ~= 'string' or not id:match('^[%a][%w_]+$') or type(definition) ~= 'table' or type(owner) ~= 'string' then return false end
  local x, y, z, raio = tonumber(definition.x), tonumber(definition.y), tonumber(definition.z), tonumber(definition.raio)
  if not x or not y or not z or not raio or raio < 1 or raio > 15 then return false end
  local produtos = {}
  for _, raw in ipairs(definition.produtos or {}) do
    local produto = copiaProduto(raw)
    if not produto or produtos[produto.id] then return false end
    produtos[produto.id] = produto
  end
  if not next(produtos) then return false end
  lojas[id] = { owner = owner, x = x, y = y, z = z, raio = raio,
    titulo = tostring(definition.titulo or 'LOJA'):sub(1, 64), subtitulo = tostring(definition.subtitulo or ''):sub(1, 120),
    max_quantidade = math.min(20, math.max(1, math.floor(tonumber(definition.max_quantidade) or 5))), produtos = produtos }
  return true
end

function M.unregisterOwner(owner)
  for id, loja in pairs(lojas) do if loja.owner == owner then lojas[id] = nil end end
end

function M.open(src, id)
  local loja = lojas[id]
  if not loja or not lojaPerto(src, loja) then return end
  local itens = {}
  for _, produto in pairs(loja.produtos) do
    local def = U.itemDef(produto.item)
    itens[#itens + 1] = { id = produto.id, item = produto.item, nome = def.nome, descricao = produto.descricao ~= '' and produto.descricao or def.descricao,
      familia = produto.familia, peso = def.peso, preco = produto.preco }
  end
  table.sort(itens, function(a, b) return a.nome < b.nome end)
  local sessao = { token = token(src), loja = id, expires = GetGameTimer() + 60000 }
  sessoes[src] = sessao
  TriggerClientEvent(E.STORE_OPEN, src, { token = sessao.token, titulo = loja.titulo, subtitulo = loja.subtitulo, itens = itens, max_quantidade = loja.max_quantidade })
end

function M.buy(src, sessionToken, productId, amount, requestId)
  local function resposta(ok, mensagem)
    TriggerClientEvent(E.STORE_RESULT, src, { ok = ok == true, mensagem = mensagem })
  end
  local sessao = sessoes[src]
  if type(sessionToken) ~= 'string' or not sessao or sessao.token ~= sessionToken or GetGameTimer() > sessao.expires then return resposta(false, 'Sessão inválida.') end
  local loja = lojas[sessao.loja]
  if not loja or not lojaPerto(src, loja) then return resposta(false, 'Você se afastou da loja.') end
  if type(requestId) ~= 'string' or not requestId:match('^[%w_-]+$') or #requestId > 32 then return resposta(false, 'Pedido inválido.') end
  amount = U.validQty(tonumber(amount), loja.max_quantidade)
  local produto = type(productId) == 'string' and loja.produtos[productId] or nil
  if not amount or not produto then return resposta(false, 'Item indisponível.') end
  local user = exports.vhub:getUser(src)
  local charId = user and user.char_id
  if not charId then return resposta(false, 'Personagem indisponível.') end
  local valor = produto.preco * amount
  local assinatura = GetHashKey(('%s:%s:%d:%d'):format(sessao.loja, produto.id, amount, valor)) & 0xffffffff
  local operationId = ('vi:st:%d:%s:%08x'):format(charId, requestId, assinatura)
  if operacoes[operationId] then return resposta(true, 'Pedido já processado.') end
  local ok, pagamento = pcall(function() return exports.vhub_money:commitPayment(src, valor, operationId, 'inventory.store:' .. sessao.loja) end)
  if not ok or type(pagamento) ~= 'table' or pagamento.ok ~= true then return resposta(false, type(pagamento) == 'table' and pagamento.err == 'insufficient' and 'Saldo insuficiente.' or 'Falha ao cobrar.') end
  if pagamento.replayed then return resposta(true, 'Pedido já processado.') end
  if not Bag.give(src, produto.item, amount) then
    pcall(function() exports.vhub_money:refundPayment(operationId) end)
    return resposta(false, 'Mochila sem espaço. Valor estornado.')
  end
  operacoes[operationId] = GetGameTimer() + 300000
  resposta(true, ('%dx %s entregue.'):format(amount, U.itemDef(produto.item).nome))
end

AddEventHandler('playerDropped', function() sessoes[source] = nil end)
CreateThread(function()
  while true do
    Wait(60000)
    local now = GetGameTimer()
    for id, expires in pairs(operacoes) do if now > expires then operacoes[id] = nil end end
  end
end)
