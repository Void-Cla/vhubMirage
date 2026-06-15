---@diagnostic disable: undefined-global
-- server.lua — vhub_legacyfuel: pagamento de bomba + persistência via PRONTUÁRIO (vhub_conce)
--
-- Sprint PRONTUÁRIO: os pokes na VRAM do CORE foram removidos (exports do FiveM
-- devolvem CÓPIA serializada — mutar vd.state era no-op real). Persistência agora
-- passa pelo escritor único: exports.vhub_conce:saveVehicleState(plate, {fuel}, 'pump').
-- Preço derivado SERVER-SIDE do delta vs combustível persistido (anti undercharge).

local PRICE_PER_PCT = 10   -- R$ por ponto percentual (espelha extraCost = litros/0.1 do client)

-- cobra do jogador (carteira+banco) via vhub_money; false se sem saldo
local function safe_try_payment(src, amount)
	if type(amount) ~= 'number' or amount <= 0 then return false end
	local ok, res = pcall(function() return exports.vhub_money:tryPayment(src, amount) end)
	return ok and res
end

-- normaliza placa (espelha o normalizePlate do CORE; GTA devolve padding bilateral)
local function normPlate(p)
	local s = tostring(p or ''):upper():gsub('%s+', ' ')
	return s:match('^%s*(.-)%s*$') or ''
end

-- número finito clampado, ou nil (rejeita NaN/±inf — payload hostil)
local function finiteNum(v, lo, hi)
	if type(v) ~= 'number' or v ~= v or math.abs(v) == math.huge then return nil end
	if lo and v < lo then v = lo end
	if hi and v > hi then v = hi end
	return v
end

-- resolve netid → placa via entidade no servidor (FAIL-CLOSED: sem entidade, nada)
local function plateFromNetId(netid)
	netid = tonumber(netid)
	if not netid or netid <= 0 then return nil end
	local ent = NetworkGetEntityFromNetworkId(netid)
	if not ent or ent == 0 then return nil end
	local p = normPlate(GetVehicleNumberPlateText(ent) or '')
	return (#p >= 2) and p or nil
end

-- persiste o combustível no prontuário (só placa registrada; falha silenciosa p/ carro de rua)
local function persistFuel(plate, fuel)
	pcall(function() exports.vhub_conce:saveVehicleState(plate, { fuel = fuel }, 'pump') end)
end

-- admin? (uid 1 ou permissão de painel)
local function is_admin(src)
	local ok, uid = pcall(function() return exports.vhub:getUID(src) end)
	if not ok or not uid then return false end
	if uid == 1 then return true end
	local ok2, has = pcall(function() return exports.vhub:hasPerm(uid, 'panel') end)
	return ok2 and has == true
end


-- ============================================================
-- BOMBA — pagamento + persistência (preço derivado server-side)
-- ============================================================

RegisterServerEvent('vrp_legacyfuel:pagamento')
AddEventHandler('vrp_legacyfuel:pagamento', function(price, galao, vehicle, fuel, fuel2)
	local src = source
	Citizen.CreateThread(function()
		-- galão: preço do item, sem persistência (o abastecimento pelo galão entra
		-- no prontuário pelo snapshot de telemetria do vehcontrol em até 15s)
		if galao then
			local preco = finiteNum(price, 1, 100000)
			if preco and safe_try_payment(src, math.floor(preco)) then
				TriggerClientEvent('vrp_legacyfuel:galao', src)
				pcall(function() TriggerClientEvent('vHub:notify', src, 'sucesso', 'Pagou $' .. math.floor(preco) .. ' pelo Galão.') end)
			else
				pcall(function() TriggerClientEvent('vHub:notify', src, 'negado', 'Dinheiro insuficiente.') end)
			end
			return
		end

		-- bomba: entidade PRECISA resolver (fail-closed antes de cobrar — L-01)
		local fuelFinal = finiteNum(fuel, 0.0, 100.0)
		if not fuelFinal then return end
		local plate = plateFromNetId(vehicle)
		if not plate then return end

		-- delta server-side: contra o persistido (placa registrada) ou contra o
		-- fuel inicial reportado (carro de rua — só money sink, sem persistência)
		local base
		local ok, st = pcall(function() return exports.vhub_conce:getVehicleState(plate) end)
		if ok and type(st) == 'table' then
			base = st.fuel
		else
			base = finiteNum(fuel2, 0.0, 100.0) or fuelFinal
		end
		local delta = math.max(0.0, fuelFinal - base)
		local preco = math.floor(delta * PRICE_PER_PCT + 0.5)
		if preco <= 0 then return end

		if safe_try_payment(src, preco) then
			if ok and type(st) == 'table' then persistFuel(plate, fuelFinal) end
			TriggerClientEvent('syncfuel', -1, tonumber(vehicle), fuelFinal)
			pcall(function() TriggerClientEvent('vHub:notify', src, 'sucesso', 'Pagou $' .. preco .. ' em combustível.') end)
		else
			TriggerClientEvent('vrp_legacyfuel:insuficiente', src, tonumber(vehicle), finiteNum(fuel2, 0.0, 100.0) or 0.0)
			pcall(function() TriggerClientEvent('vHub:notify', src, 'negado', 'Dinheiro insuficiente.') end)
		end
	end)
end)


-- ============================================================
-- ADMIN — /fuel por placa ou netid
-- ============================================================

RegisterServerEvent('vrp_legacyfuel:setFuel')
AddEventHandler('vrp_legacyfuel:setFuel', function(target, qty)
	local src = source
	if not is_admin(src) then
		pcall(function() TriggerClientEvent('vHub:notify', src, 'erro', 'Sem permissao para usar /fuel.') end)
		return
	end
	qty = finiteNum(tonumber(qty), 0, 100)
	if not qty then
		pcall(function() TriggerClientEvent('vHub:notify', src, 'erro', 'Quantidade inválida.') end)
		return
	end

	Citizen.CreateThread(function()
		local plate, netid
		if type(target) == 'number' then
			netid = tonumber(target)
			plate = plateFromNetId(netid)
		else
			plate = normPlate(target)
			-- acha a entidade viva pela placa (OneSync) p/ aplicar ao vivo
			for _, ent in ipairs(GetAllVehicles()) do
				if normPlate(GetVehicleNumberPlateText(ent) or '') == plate then
					netid = NetworkGetNetworkIdFromEntity(ent)
					break
				end
			end
		end
		if not plate or plate == '' then
			pcall(function() TriggerClientEvent('vHub:notify', src, 'erro', 'Veículo não encontrado.') end)
			return
		end

		persistFuel(plate, qty)
		if netid then TriggerClientEvent('syncfuel', -1, netid, qty) end
		pcall(function() TriggerClientEvent('vHub:notify', src, 'sucesso', 'Combustível definido para ' .. qty .. '% (' .. plate .. ')') end)
	end)
end)
