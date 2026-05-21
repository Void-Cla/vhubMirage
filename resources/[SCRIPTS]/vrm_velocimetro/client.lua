local INTERVALO_ATIVO_MS = 80
local INTERVALO_INATIVO_MS = 350
local METROS_POR_SEGUNDO_PARA_KMH = 3.6

local ultimo_estado = {
    ativo = nil,
    velocidade = -1,
    rpm = -1,
    marcha = ''
}

local function limitar(valor, minimo, maximo)
    valor = tonumber(valor) or minimo
    if valor < minimo then
        return minimo
    end
    if valor > maximo then
        return maximo
    end
    return valor
end

local function arredondar(valor)
    return math.floor((tonumber(valor) or 0) + 0.5)
end

-- Direcao local separa re de neutro quando a native retorna marcha zero.
local function eixo_veiculo(veiculo)
    if type(GetEntitySpeedVector) ~= 'function' then
        return 0.0
    end

    local vetor = GetEntitySpeedVector(veiculo, true)
    if type(vetor) == 'vector3' or type(vetor) == 'table' then
        return tonumber(vetor.y or vetor[2]) or 0.0
    end
    return 0.0
end

-- Marcha visual deve expor somente numero real, N ou R.
local function ler_marcha(veiculo)
    local marcha = tonumber(GetVehicleCurrentGear(veiculo)) or 0
    if marcha > 0 then
        return ('%d'):format(limitar(arredondar(marcha), 1, 9))
    end
    return eixo_veiculo(veiculo) < -0.35 and 'R' or 'N'
end

local function enviar_velocimetro(ativo, velocidade, rpm, marcha)
    velocidade = limitar(arredondar(velocidade), 0, 999)
    rpm = limitar(arredondar(rpm), 0, 100)
    marcha = ativo and tostring(marcha or 'N') or 'N'

    if ultimo_estado.ativo == ativo
        and ultimo_estado.velocidade == velocidade
        and ultimo_estado.rpm == rpm
        and ultimo_estado.marcha == marcha then
        return
    end

    ultimo_estado.ativo = ativo
    ultimo_estado.velocidade = velocidade
    ultimo_estado.rpm = rpm
    ultimo_estado.marcha = marcha

    SendNUIMessage({
        type = 'velocimetro:update',
        data = {
            visible = ativo,
            active = ativo,
            speed_kmh = velocidade,
            rpm_percent = rpm,
            gear_label = marcha
        }
    })
end

local function ler_telemetria_veiculo()
    local ped = PlayerPedId()
    if ped == 0 or not DoesEntityExist(ped) or not IsPedInAnyVehicle(ped, false) then
        return false, 0, 0, 'N'
    end

    local veiculo = GetVehiclePedIsIn(ped, false)
    if veiculo == 0 or not DoesEntityExist(veiculo) then
        return false, 0, 0, 'N'
    end

    local velocidade = (GetEntitySpeed(veiculo) or 0.0) * METROS_POR_SEGUNDO_PARA_KMH
    local rpm = (GetVehicleCurrentRpm(veiculo) or 0.0) * 100.0
    local marcha = ler_marcha(veiculo)

    return true, velocidade, rpm, marcha
end

CreateThread(function()
    while true do
        local ativo, velocidade, rpm, marcha = ler_telemetria_veiculo()
        enviar_velocimetro(ativo, velocidade, rpm, marcha)
        Wait(ativo and INTERVALO_ATIVO_MS or INTERVALO_INATIVO_MS)
    end
end)

AddEventHandler('onClientResourceStop', function(resource_name)
    if resource_name ~= GetCurrentResourceName() then
        return
    end

    SendNUIMessage({
        type = 'velocimetro:update',
        data = {
            visible = false,
            active = false,
            speed_kmh = 0,
            rpm_percent = 0,
            gear_label = 'N'
        }
    })
end)
