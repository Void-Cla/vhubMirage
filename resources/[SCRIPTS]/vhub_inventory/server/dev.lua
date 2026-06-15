---@diagnostic disable: undefined-global, lowercase-global

-- server/dev.lua — comandos de TESTE. Isolado para ser facil de remover/desligar.
-- /item <id> <quantidade> adiciona um item do catalogo a propria mochila.

local Backpack = Inventory.Bag
local Cat      = Inventory.Catalog


-- ============================================================
-- AVISO DE BOOT — impossivel esquecer /item aberto em producao
-- ============================================================

AddEventHandler('onResourceStart', function(res)
  if res ~= GetCurrentResourceName() then return end
  if Inventory.Dev and Inventory.Dev.give_command then
    print('^3[vhub_inventory] AVISO: /item esta ABERTO a TODOS os jogadores '
      .. '(Inventory.Dev.give_command = true). DESLIGUE em producao!^0')
  end
end)


-- ============================================================
-- PERMISSAO
-- ============================================================

-- pode usar /item? (dev livre via config OU dono uid 1 OU ACE 'vhub.item')
local function canGive(src)
  if Inventory.Dev and Inventory.Dev.give_command then return true end
  local ok, uid = pcall(function() return exports.vhub:getUID(src) end)
  if ok and uid == 1 then return true end
  return IsPlayerAceAllowed(src, 'vhub.item')
end

-- atalho de mensagem no chat
local function msg(src, color, text)
  TriggerClientEvent('chat:addMessage', src, { args = { color .. 'Inventário', text } })
end


-- ============================================================
-- /item <id> <quantidade>
-- ============================================================

RegisterCommand('item', function(src, args)
  if src == 0 then return end                       -- console nao tem mochila
  if not canGive(src) then return msg(src, '^1', 'Sem permissão para /item.') end

  local id  = args[1]
  local qty = math.floor(tonumber(args[2]) or 1)
  if not id then          return msg(src, '^3', 'Uso: /item <id> <quantidade>') end
  if qty < 1 then         return msg(src, '^1', 'Quantidade inválida.') end
  if not Cat.exists(id) then return msg(src, '^1', ('Item inexistente: %s'):format(id)) end

  local ok, err = Backpack.give(src, id, qty)
  if ok then
    msg(src, '^2', ('+%dx %s'):format(qty, Cat.def(id).nome))
  else
    msg(src, '^1', ('Falha: %s'):format(err or '?'))   -- ex: weight (peso excedido), full (cheio)
  end
end, false)
