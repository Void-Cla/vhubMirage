-- server/mec.lua — domínio de reparo e reboque
-- reparo parcial (pneu/motor/lataria) + reboque (entidade + status via conce)
-- DELEGA reparo total ao caminho do garage (sem duplicar fórmula)
---@diagnostic disable: undefined-global

local Core = VHubCustom.Core
local CFG  = VHubCustom.cfg
local U    = VHubCustom.U
local E    = VHubCustom.E

-- reboque pendente por src: garante que mecTowDone só é aceito após TOW_REQ autorizado
local _pending_tow = {}   -- [src] = { plate, net_id }

-- limpa pendência e reabilita migração se o player desconectar durante um reboque
AddEventHandler('playerDropped', function()
  local src = source
  local p = _pending_tow[src]
  if p then
    SetNetworkIdCanMigrate(p.net_id, true)
    _pending_tow[src] = nil
  end
end)


-- ============================================================
-- REPARO PARCIAL
-- ============================================================

-- types aceitos: 'tyre' | 'engine' | 'body'
local REPAIR_TYPES = { tyre = true, engine = true, body = true }

RegisterNetEvent(E.MEC_REPAIR)
AddEventHandler(E.MEC_REPAIR, function(plate, repair_type)
  local src = source
  Citizen.CreateThread(function()
    -- 1. rate
    if not Core.rateOK(src, 'mec_repair') then
      Core.notify(src, 'Aguarde antes de solicitar outro reparo.', 'error'); return
    end

    -- 2. sessão
    local cid = Core.getCharId(src)
    if not cid then return end

    -- 3. validação básica
    local p = U.normalizePlate(plate)
    if not p or not REPAIR_TYPES[repair_type] then return end

    -- 4. autorização (ANTES de ler estado — L-01/segurança)
    if not Core.canOperate(src, p) then
      Core.notify(src, 'Sem autorização para este veículo.', 'error'); return
    end

    -- 5. lê estado real do prontuário
    local st = Core.getVehicleState(p)
    if not st then
      Core.notify(src, 'Veículo não encontrado no sistema.', 'error'); return
    end

    local prices = CFG.prices
    local patch  = {}
    local custo  = 0

    if repair_type == 'tyre' then
      -- reparo de pneu: zera dano de pneus no prontuário
      local dmg = type(st.damage) == 'table' and st.damage or {}
      patch.damage = {
        doors     = dmg.doors,
        windows   = dmg.windows,
        tyres     = {},        -- limpa pneus
        tyres_rim = {},        -- limpa aros
      }
      local n_tyres = (dmg.tyres and #dmg.tyres or 0)
                    + (dmg.tyres_rim and #dmg.tyres_rim or 0)
      custo = math.max(1, n_tyres) * prices.pneu

    elseif repair_type == 'engine' then
      -- reparo de motor: restaura engine_health para 1000 (source='repair' eleva)
      local dmg_pts = math.max(0, 1000 - (st.engine_health or 1000))
      if dmg_pts < 50 then
        Core.notify(src, 'Motor sem danos relevantes.', 'info'); return
      end
      custo = math.ceil(dmg_pts / 100) * prices.motor_parcial
      patch.engine_health = 1000.0

    elseif repair_type == 'body' then
      -- reparo de lataria: restaura body_health para 1000
      local dmg_pts = math.max(0, 1000 - (st.body_health or 1000))
      if dmg_pts < 50 then
        Core.notify(src, 'Lataria sem danos relevantes.', 'info'); return
      end
      custo = math.ceil(dmg_pts / 100) * prices.lataria_parcial
      patch.body_health = 1000.0
    end

    if custo > 0 and not Core.pay(src, custo) then
      Core.notify(src, ('Saldo insuficiente. Reparo: R$ %d.'):format(custo), 'error')
      TriggerClientEvent(E.MEC_CONFIRM, src, p, false, repair_type)
      return
    end

    -- source='repair': pode elevar health + reescrever damage (contrato do vstate)
    local ok = Core.saveVehicleState(p, patch, 'repair')
    if not ok then
      Core.notify(src, 'Erro ao salvar reparo. Tente novamente.', 'error')
      TriggerClientEvent(E.MEC_CONFIRM, src, p, false, repair_type)
      return
    end

    Core.log(p, 'mec_repair_'..repair_type, cid, { custo = custo })
    TriggerClientEvent(E.MEC_CONFIRM, src, p, true, repair_type)
    Core.notify(src, ('Reparo de %s concluído! R$ %d cobrados.'):format(repair_type, custo), 'success')
  end)
end)


-- ============================================================
-- REBOQUE (recuperação de posição)
-- ============================================================

RegisterNetEvent(E.MEC_TOW_REQ)
AddEventHandler(E.MEC_TOW_REQ, function(plate, net_id)
  local src = source
  Citizen.CreateThread(function()
    -- 1. rate
    if not Core.rateOK(src, 'mec_tow') then
      Core.notify(src, 'Aguarde antes de solicitar outro reboque.', 'error'); return
    end

    -- 2. sessão
    local cid = Core.getCharId(src)
    if not cid then return end

    -- 3. placa
    local p = U.normalizePlate(plate)
    if not p then return end

    -- 4. autorização
    if not Core.canOperate(src, p) then
      Core.notify(src, 'Sem autorização para este veículo.', 'error'); return
    end

    -- 5. valida que o veículo está 'out' (não guardado/apreendido)
    local veh_row
    pcall(function() veh_row = exports.vhub_conce:getVehicle(p) end)
    if not veh_row or veh_row.status ~= 'out' then
      Core.notify(src, 'Veículo não está disponível para reboque.', 'error'); return
    end

    -- 6. valida netId → entidade → placa (anti-dupe: servidor resolve, nunca confia no cliente)
    local nid = tonumber(net_id)
    if not nid then return end
    local ent = NetworkGetEntityFromNetworkId(nid)
    if not ent or ent == 0 then
      Core.notify(src, 'Veículo não encontrado na rede.', 'error'); return
    end
    local plate_ent = GetVehicleNumberPlateText(ent)
    if U.normalizePlate(plate_ent) ~= p then
      Core.notify(src, 'Veículo inconsistente. Ação bloqueada.', 'error')
      Core.log(p, 'mec_tow_ANTI_DUPE', cid, { net_id = nid, plate_ent = tostring(plate_ent) })
      return
    end

    -- 7. trava migração de ownership durante a operação
    SetNetworkIdCanMigrate(nid, false)

    -- 8. registra reboque pendente e autoriza o cliente a reposicionar
    _pending_tow[src] = { plate = p, net_id = nid }
    TriggerClientEvent(E.MEC_TOW_DO, src, p, nid)
    Core.log(p, 'mec_tow_authorized', cid, { net_id = nid })
  end)
end)

-- recebe confirmação do cliente após reposicionamento e salva posição
RegisterNetEvent('vhub_custom:server:mecTowDone')
AddEventHandler('vhub_custom:server:mecTowDone', function(plate, net_id, pos)
  local src = source
  Citizen.CreateThread(function()
    local p  = U.normalizePlate(plate)
    local nid = tonumber(net_id)
    if not p or not nid then return end

    -- valida sessão de reboque pendente (anti-spoof: só aceita se TOW_REQ foi autorizado)
    local pending = _pending_tow[src]
    if not pending or pending.plate ~= p or pending.net_id ~= nid then
      Core.log(p, 'mec_tow_SPOOF_BLOCKED', Core.getCharId(src) or '?', { net_id = nid }); return
    end
    _pending_tow[src] = nil

    -- reabilita migração após operação
    SetNetworkIdCanMigrate(nid, true)

    -- persiste posição via conce (escritor de posição)
    if type(pos) == 'table' and tonumber(pos.x) and tonumber(pos.y) and tonumber(pos.z) then
      pcall(function()
        local posJson = ('{"x":%.2f,"y":%.2f,"z":%.2f,"h":%.2f}'):format(
          pos.x, pos.y, pos.z, tonumber(pos.h) or 0.0)
        exports.vhub_conce:updatePosition(p, posJson)
      end)
    end

    Core.notify(src, 'Veículo reposicionado com sucesso.', 'success')
    Core.log(p, 'mec_tow_done', Core.getCharId(src) or '?', {})
  end)
end)
