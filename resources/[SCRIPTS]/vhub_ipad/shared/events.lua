---@diagnostic disable: undefined-global, lowercase-global

-- shared/events.lua — fonte ÚNICA de nomes de eventos de rede (GLOBAL, sem return).
-- Nomes de NUI callback (vhub.post / RegisterNUICallback) são strings locais,
-- documentadas em client/init.lua e shell.js.

VHubIpadE = {

  -- cliente → servidor (intenção; servidor é autoritativo)
  REQUEST_OPEN = 'vhub_ipad:sv:requestOpen',  -- pedir para abrir (carrega estado per-char)
  INSTALL      = 'vhub_ipad:sv:install',       -- instalar app removível
  UNINSTALL    = 'vhub_ipad:sv:uninstall',     -- remover app removível
  SET_PREF     = 'vhub_ipad:sv:setPref',       -- salvar preferência (zoom/wallpaper)
  APP_RELAY    = 'vhub_ipad:sv:appRelay',      -- app embutido → server do resource dono (broker)

  -- servidor → cliente
  OPEN         = 'vhub_ipad:cl:open',          -- abrir com payload completo (catálogo+estado)
  STATE        = 'vhub_ipad:cl:state',         -- estado per-char atualizado (pós-mutação)
  FORCE_CLOSE  = 'vhub_ipad:cl:forceClose',    -- fechar de fora (export closeIpad / handoff)
  APP_PUSH     = 'vhub_ipad:cl:appPush',       -- server do resource dono → app embutido (broker)

}
