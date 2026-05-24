-- client/countdown.lua — countdown cinematografico 3 / 2 / 1 / GO!
-- Renderiza so durante warmup. Cor escalonada: vermelho → amarelo → verde.
-- Inclui camera shake leve no GO.

local Lang = VHubRachaLang
local L    = VHubRachaLocal

local _shaken = false

local function shake_cam()
  if _shaken then return end
  _shaken = true
  pcall(function()
    -- Native shake leve: pequena vibracao na largada
    ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', 0.35)
  end)
end

CreateThread(function()
  while true do
    local active = VHubRachaLocal.active_race()
    if not active or active.started_ms ~= 0 or active.aborted or active.finished then
      _shaken = false
      Wait(200)
    else
      Wait(0)
      local now = GetGameTimer()
      local remain = (active.starts_at or 0) - now

      if remain <= 0 then
        -- GO!
        shake_cam()
        SetTextFont(7); SetTextScale(0.0, 2.6)
        SetTextColour(80, 230, 80, 245); SetTextOutline(); SetTextDropShadow()
        SetTextEntry('STRING'); AddTextComponentString(Lang.t('race.go'))
        SetTextCentre(true); DrawText(0.5, 0.40)
      else
        local sec = math.ceil(remain / 1000)
        local r, g, b
        if sec >= 4 then       r, g, b = 230, 60, 60       -- vermelho
        elseif sec >= 2 then   r, g, b = 230, 200, 50      -- amarelo
        else                   r, g, b = 80, 230, 80 end   -- verde
        SetTextFont(7); SetTextScale(0.0, 2.4)
        SetTextColour(r, g, b, 245); SetTextOutline(); SetTextDropShadow()
        SetTextEntry('STRING'); AddTextComponentString(tostring(sec))
        SetTextCentre(true); DrawText(0.5, 0.40)
      end
    end
  end
end)
