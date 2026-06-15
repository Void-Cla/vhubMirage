---@diagnostic disable: undefined-global

-- server/item_handlers.lua — handlers de uso de itens (integração com vhub_inventory).
-- Quando o jogador usa uma chave de veículo, abre o painel do vehcontrol.

CreateThread(function()
  Wait(500)  -- aguarda o inventário estar pronto (soft-dep)

  local ok, inv = pcall(function() return exports.vhub_inventory end)
  if not ok or not inv then return end

  -- Handler: veh_key — usar a chave de veículo abre o painel do vehcontrol
  inv:registerItemUse('veh_key', function(src, slot, id)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false, 'Jogador offline' end

    -- Lê o inventário para pegar a chave (com meta.plate)
    local ok2, inv_snap = pcall(function() return inv:getInventory(src) end)
    if not ok2 or not inv_snap then return false, 'Erro ao ler inventário' end

    local plate = nil
    if inv_snap.slots and inv_snap.slots[slot] then
      local entry = inv_snap.slots[slot]
      if entry.id == 'veh_key' and entry.meta and entry.meta.plate then
        plate = entry.meta.plate
      end
    end

    if not plate then return false, 'Chave sem placa vinculada' end

    -- Abre o painel do vehcontrol no client
    TriggerClientEvent('vhub_vehcontrol:open_from_key', src, plate)
    return true, 'Painel do veículo aberto'
  end)
end)
