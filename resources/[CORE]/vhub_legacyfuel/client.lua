local isNearPump = false
local isFueling = false
local currentFuel = 0.0
local currentFuel2 = 0.0
local currentCost = 0.0

-- shim: o codigo legado usa parseInt (JavaScript). Em Lua = truncar p/ inteiro.
local function parseInt(v) return math.floor(tonumber(v) or 0) end

-- D1 RESOLVIDO: o consumo de combustivel agora e FONTE UNICA do CORE — vd.state.fuel
-- decai por rpm em vhub/server/vehicle.lua:onStateUpdate e replica via State Bag vh_fuel
-- (lido pelo HUD). O loop client ManageFuelUsage foi REMOVIDO para nao competir com o CORE
-- (a competicao causava o /fuel inconsistente). So o registro do decor permanece (a bomba usa).
Citizen.CreateThread(function()
	DecorRegister(Config.FuelDecor, 1)
end)

function FindNearestFuelPump()
	local coords = GetEntityCoords(PlayerPedId())
	local fuelPumps = {}
	local handle,object = FindFirstObject()
	local success

	repeat
		if Config.PumpModels[GetEntityModel(object)] then
			table.insert(fuelPumps,object)
		end

		success,object = FindNextObject(handle,object)
	until not success

	EndFindObject(handle)

	local pumpObject = 0
	local pumpDistance = 1000

	for k,v in pairs(fuelPumps) do
		local dstcheck = GetDistanceBetweenCoords(coords,GetEntityCoords(v))

		if dstcheck < pumpDistance then
			pumpDistance = dstcheck
			pumpObject = v
		end
	end
	return pumpObject,pumpDistance
end

Citizen.CreateThread(function()
	while true do
		Citizen.Wait(250)
		local pumpObject,pumpDistance = FindNearestFuelPump()
		if pumpDistance < 2.5 then
			isNearPump = pumpObject
		else
			isNearPump = false
			Citizen.Wait(math.ceil(pumpDistance*20))
		end
	end
end)

AddEventHandler('fuel:startFuelUpTick',function(pumpObject,ped,vehicle)
	currentFuel = GetVehicleFuelLevel(vehicle)
	currentFuel2 = GetVehicleFuelLevel(vehicle)
	while isFueling do
		Citizen.Wait(1)
		local oldFuel = DecorGetFloat(vehicle,Config.FuelDecor)
		local fuelToAdd = math.random(1,2) / 100.0
		local extraCost = fuelToAdd / 0.1

		if not pumpObject then
			if GetAmmoInPedWeapon(ped,883325847) - fuelToAdd * 100 >= 0 then
				currentFuel = oldFuel + fuelToAdd
				SetPedAmmo(ped,883325847,math.floor(GetAmmoInPedWeapon(ped,883325847) - fuelToAdd * 100))
			else
				isFueling = false
			end
		else
			currentFuel = oldFuel + fuelToAdd
		end

		if currentFuel > 100.0 then
			currentFuel = 100.0
			isFueling = false
		end

		currentCost = currentCost + extraCost

		SetVehicleFuelLevel(vehicle,currentFuel)
		DecorSetFloat(vehicle,Config.FuelDecor,GetVehicleFuelLevel(vehicle))
	end

	if pumpObject then
		TriggerServerEvent('vrp_legacyfuel:pagamento',parseInt(currentCost),false,VehToNet(vehicle),GetVehicleFuelLevel(vehicle),currentFuel2)
	end

	currentCost = 0.0
end)

RegisterNetEvent("vrp_legacyfuel:insuficiente")
AddEventHandler("vrp_legacyfuel:insuficiente",function(index,fuel)
	if NetworkDoesNetworkIdExist(index) then
		local v = NetToVeh(index)
		if DoesEntityExist(v) then
			SetVehicleFuelLevel(v,fuel)
			DecorSetFloat(v,Config.FuelDecor,GetVehicleFuelLevel(v))
		end
	end
end)

RegisterNetEvent("syncfuel")
AddEventHandler("syncfuel",function(index,fuel)
	if NetworkDoesNetworkIdExist(index) then
		local v = NetToVeh(index)
		if DoesEntityExist(v) then
			SetVehicleFuelLevel(v,fuel)
			DecorSetFloat(v,Config.FuelDecor,GetVehicleFuelLevel(v))
		end
	end
end)

RegisterNetEvent("100fuel")
AddEventHandler("100fuel",function(index,vehicle,fuel)
	local vehicle = GetPlayersLastVehicle()
	if vehicle then
		currentFuel = 100.0
		SetVehicleFuelLevel(vehicle,currentFuel)
	end
end)

RegisterNetEvent("90fuel")
AddEventHandler("90fuel",function(index,vehicle,fuel)
	local vehicle = GetPlayersLastVehicle()
	if vehicle then
		currentFuel = 90.0
		SetVehicleFuelLevel(vehicle,currentFuel)
	end
end)

RegisterNetEvent("80fuel")
AddEventHandler("80fuel",function(index,vehicle,fuel)
	local vehicle = GetPlayersLastVehicle()
	if vehicle then
		currentFuel = 80.0
		SetVehicleFuelLevel(vehicle,currentFuel)
	end
end)

RegisterNetEvent("70fuel")
AddEventHandler("70fuel",function(index,vehicle,fuel)
	local vehicle = GetPlayersLastVehicle()
	if vehicle then
		currentFuel = 70.0
		SetVehicleFuelLevel(vehicle,currentFuel)
	end
end)

RegisterNetEvent("60fuel")
AddEventHandler("60fuel",function(index,vehicle,fuel)
	local vehicle = GetPlayersLastVehicle()
	if vehicle then
		currentFuel = 60.0
		SetVehicleFuelLevel(vehicle,currentFuel)
	end
end)

RegisterNetEvent("50fuel")
AddEventHandler("50fuel",function(index,vehicle,fuel)
	local vehicle = GetPlayersLastVehicle()
	if vehicle then
		currentFuel = 50.0
		SetVehicleFuelLevel(vehicle,currentFuel)
	end
end)

RegisterNetEvent("40fuel")
AddEventHandler("40fuel",function(index,vehicle,fuel)
	local vehicle = GetPlayersLastVehicle()
	if vehicle then
		currentFuel = 40.0
		SetVehicleFuelLevel(vehicle,currentFuel)
	end
end)

RegisterNetEvent("20fuel")
AddEventHandler("20fuel",function(index,vehicle,fuel)
	local vehicle = GetPlayersLastVehicle()
	if vehicle then
		currentFuel = 20.0
		SetVehicleFuelLevel(vehicle,currentFuel)
	end
end)

RegisterNetEvent("0fuel")
AddEventHandler("0fuel",function(index,vehicle,fuel)
	local vehicle = GetPlayersLastVehicle()
	if vehicle then
		currentFuel = 0.0
		SetVehicleFuelLevel(vehicle,currentFuel)
	end
end)

RegisterNetEvent('vrp_legacyfuel:galao')
AddEventHandler('vrp_legacyfuel:galao',function()
	GiveWeaponToPed(PlayerPedId(),883325847,4500,false,true)
end)

function Round(num,numDecimalPlaces)
	local mult = 10^(numDecimalPlaces or 0)
	return math.floor(num*mult+0.5) / mult
end

AddEventHandler('fuel:refuelFromPump',function(pumpObject,ped,vehicle)
	TaskTurnPedToFaceEntity(ped,vehicle,5000)
	LoadAnimDict("timetable@gardener@filling_can")
	TaskPlayAnim(ped,"timetable@gardener@filling_can","gar_ig_5_filling_can",2.0,8.0,-1,50,0,0,0,0)
	TriggerEvent('fuel:startFuelUpTick',pumpObject,ped,vehicle)

	while isFueling do
		Citizen.Wait(1)
		for k,v in pairs(Config.DisableKeys) do
			DisableControlAction(0,v)
		end

		local vehicleCoords = GetEntityCoords(vehicle)
		if pumpObject then
			local stringCoords = GetEntityCoords(pumpObject)
			DrawText3Ds(stringCoords.x,stringCoords.y,stringCoords.z + 1.2,"PRESSIONE ~g~E ~w~PARA CANCELAR")
			DrawText3Ds(vehicleCoords.x,vehicleCoords.y,vehicleCoords.z + 0.5,"TANQUE: ~y~"..Round(currentFuel,1).."%")
		else
			DrawText3Ds(vehicleCoords.x,vehicleCoords.y,vehicleCoords.z + 0.5,"PRESSIONE ~g~E ~w~PARA CANCELAR")
			DrawText3Ds(vehicleCoords.x,vehicleCoords.y,vehicleCoords.z + 0.34,"GALÃO: ~b~"..Round(GetAmmoInPedWeapon(ped,883325847) / 4500 * 100,1).."%~w~    TANQUE: ~y~"..Round(currentFuel,1).."%")
		end

		if not IsEntityPlayingAnim(ped,"timetable@gardener@filling_can","gar_ig_5_filling_can",3) then
			TaskPlayAnim(ped,"timetable@gardener@filling_can","gar_ig_5_filling_can",2.0,8.0,-1,50,0,0,0,0)
		end

		if IsControlJustReleased(0,38) or DoesEntityExist(GetPedInVehicleSeat(vehicle,-1)) or (isNearPump and GetEntityHealth(pumpObject) <= 0) then
			isFueling = false
		end
	end

	ClearPedTasks(ped)
	RemoveAnimDict("timetable@gardener@filling_can")
end)

Citizen.CreateThread(function()
	while true do
		Citizen.Wait(1)
		local ped = PlayerPedId()
		if not isFueling and ((isNearPump and GetEntityHealth(isNearPump) > 0) or (GetSelectedPedWeapon(ped) == 883325847 and not isNearPump)) then
			if IsPedInAnyVehicle(ped) and GetPedInVehicleSeat(GetVehiclePedIsIn(ped),-1) == ped then
				local pumpCoords = GetEntityCoords(isNearPump)
				DrawText3Ds(pumpCoords.x,pumpCoords.y,pumpCoords.z + 1.2,"SAIA DO ~y~VEÍCULO ~w~PARA ABASTECER")
			else
				local vehicle = GetPlayersLastVehicle()
				local vehicleCoords = GetEntityCoords(vehicle)
				if DoesEntityExist(vehicle) and GetDistanceBetweenCoords(GetEntityCoords(ped),vehicleCoords) < 2.5 then
					if not DoesEntityExist(GetPedInVehicleSeat(vehicle,-1)) then
						local stringCoords = GetEntityCoords(isNearPump)
						local canFuel = true
						if GetSelectedPedWeapon(ped) == 883325847 then
							stringCoords = vehicleCoords
							if GetAmmoInPedWeapon(ped,883325847) < 100 then
								canFuel = false
							end
						end

						if GetVehicleFuelLevel(vehicle) < 99 and canFuel then
							DrawText3Ds(stringCoords.x,stringCoords.y,stringCoords.z + 1.2,"PRESSIONE ~g~E ~w~PARA ABASTECER")
							if IsControlJustReleased(0,38) then
								isFueling = true
								TriggerEvent('fuel:refuelFromPump',isNearPump,ped,vehicle)
								LoadAnimDict("timetable@gardener@filling_can")
							end
						elseif not canFuel then
							DrawText3Ds(stringCoords.x,stringCoords.y,stringCoords.z + 1.2,"~o~GALÃO VAZIO")
						else
							DrawText3Ds(stringCoords.x,stringCoords.y,stringCoords.z + 1.2,"~g~TANQUE CHEIO")
						end
					end
				elseif isNearPump then
					local stringCoords = GetEntityCoords(isNearPump)
					DrawText3Ds(stringCoords.x,stringCoords.y,stringCoords.z + 1.2,"PRESSIONE ~g~E ~w~PARA COMPRAR UM ~b~GALÃO DE GASOLINA")
					if IsControlJustReleased(0,38) then
						TriggerServerEvent('vrp_legacyfuel:pagamento',parseInt(300),true)
					end
				else
					Citizen.Wait(250)
				end
			end
		else
			Citizen.Wait(250)
		end
	end
end)

function DrawText3Ds(x,y,z,text)
	local onScreen,_x,_y = World3dToScreen2d(x,y,z)

	SetTextFont(4)
	SetTextScale(0.35,0.35)
	SetTextColour(255,255,255,150)
	SetTextEntry("STRING")
	SetTextCentre(1)
	AddTextComponentString(text)
	DrawText(_x,_y)
	local factor = (string.len(text))/370
	DrawRect(_x,_y+0.0125,0.01+factor,0.03,0,0,0,80)
end

function LoadAnimDict(dict)
	if not HasAnimDictLoaded(dict) then
		RequestAnimDict(dict)
		while not HasAnimDictLoaded(dict) do
			Citizen.Wait(10)
		end
	end
end


-- ============================================================
-- COMANDO ADMIN: /fuel
-- ============================================================

-- /fuel <qtd>          → define combustivel do veiculo em que o admin esta (0-100)
-- /fuel <placa> <qtd>  → define combustivel de uma placa especifica
-- A autoridade real e validada server-side (is_admin); aqui so resolvemos o alvo.
RegisterCommand('fuel', function(_, args)
	if #args == 0 then
		TriggerEvent('chat:addMessage', { args = { '^3[Fuel]', 'Uso: /fuel <qtd>  ou  /fuel <placa> <qtd>' } })
		return
	end

	local target, qty

	if #args >= 2 then
		-- /fuel <placa> <qtd>
		target = tostring(args[1]):upper():gsub('^%s+', ''):gsub('%s+$', '')
		qty = tonumber(args[2])
	else
		-- /fuel <qtd> → veiculo atual; envia netid (aplica ao vivo e persiste se registrado)
		qty = tonumber(args[1])
		local veh = GetVehiclePedIsIn(PlayerPedId(), false)
		if not veh or veh == 0 then
			TriggerEvent('chat:addMessage', { args = { '^1[Fuel]', 'Voce nao esta em um veiculo.' } })
			return
		end
		target = VehToNet(veh)
	end

	if not qty then
		TriggerEvent('chat:addMessage', { args = { '^1[Fuel]', 'Quantidade invalida (use 0 a 100).' } })
		return
	end

	TriggerServerEvent('vrp_legacyfuel:setFuel', target, qty)
end, false)

-- Sugestao no chat (apenas dica visual; nao concede permissao alguma)
TriggerEvent('chat:addSuggestion', '/fuel', 'Define o combustivel do veiculo (admin)', {
	{ name = '[placa]', help = 'Opcional. Sem placa = veiculo atual.' },
	{ name = 'qtd',     help = 'Combustivel de 0 a 100.' },
})