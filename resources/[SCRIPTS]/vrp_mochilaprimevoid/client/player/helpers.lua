VOIDP = VOIDP or {}

function VOIDP.getPlayers()
    local players = {}
    for _, player in ipairs(GetActivePlayers()) do
        if NetworkIsPlayerActive(player) then
            players[#players + 1] = player
        end
    end
    return players
end

function VOIDP.getClosestPlayer(radius)
    local players = VOIDP.getPlayers()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local closestDistance = -1
    local closestPlayer = -1

    for _, player in ipairs(players) do
        local target = GetPlayerPed(player)
        if target ~= ped then
            local targetCoords = GetEntityCoords(target)
            local distance = #(targetCoords - coords)
            if closestDistance == -1 or distance < closestDistance then
                closestDistance = distance
                closestPlayer = player
            end
        end
    end

    if closestDistance ~= -1 and closestDistance <= radius then
        return closestPlayer
    end
    return nil
end

function VOIDP.drawText3d(x, y, z, text)
    local onScreen, _x, _y = World3dToScreen2d(x, y, z)
    if not onScreen then return end
    SetTextFont(4)
    SetTextScale(0.40, 0.40)
    SetTextColour(255, 255, 255, 200)
    SetTextEntry('STRING')
    SetTextCentre(1)
    AddTextComponentString(text)
    DrawText(_x, _y)
    local factor = (string.len(text)) / 300
    DrawRect(_x, _y + 0.0125, 0.01 + factor, 0.03, 0, 0, 0, 80)
end

function VOIDP.drawTxts(x, y, width, height, scale, text, r, g, b, a)
    SetTextFont(4)
    SetTextScale(scale, scale)
    SetTextColour(r, g, b, a)
    SetTextOutline()
    SetTextEntry('STRING')
    AddTextComponentString(text)
    DrawText(x, y)
end

function VOIDP.getMinimapAnchor()
    local safezone = GetSafeZoneSize()
    local safezone_x = 1.0 / 20.0
    local safezone_y = 1.0 / 20.0
    local aspect_ratio = GetAspectRatio(0)
    local res_x, res_y = GetActiveScreenResolution()
    local xscale = 1.0 / res_x
    local yscale = 1.0 / res_y

    local Minimap = {}
    Minimap.width = xscale * (res_x / (4 * aspect_ratio))
    Minimap.height = yscale * (res_y / 5.674)
    Minimap.left_x = xscale * (res_x * (safezone_x * ((math.abs(safezone - 1.0)) * 10)))
    Minimap.bottom_y = 1.0 - yscale * (res_y * (safezone_y * ((math.abs(safezone - 1.0)) * 10)))
    Minimap.right_x = Minimap.left_x + Minimap.width
    Minimap.top_y = Minimap.bottom_y - Minimap.height
    Minimap.x = Minimap.left_x
    Minimap.y = Minimap.top_y
    Minimap.xunit = xscale
    Minimap.yunit = yscale

    return Minimap
end

return VOIDP
