---@diagnostic disable: undefined-global, lowercase-global

-- client/countdown.lua — camera shake nativo no GO da largada.
--
-- A contagem visual (3/2/1/GO) e feita pela NUI (web/modules/hud). Aqui mora
-- apenas o efeito nativo que a NUI nao consegue fazer: um tremor leve de
-- camera no instante da largada (RACE_START).


local E = VHubRachaE


RegisterNetEvent(E.RACE_START, function()
  pcall(function()
    ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', 0.35)
  end)
end)
