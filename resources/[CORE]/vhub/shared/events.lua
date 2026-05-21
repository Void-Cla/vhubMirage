-- shared/events.lua — Constantes de eventos (vHub.E.*)
-- Depende de: shared/config.lua (garante que vHub existe)

vHub = vHub or {}

local _E = {
  -- Net events cliente → servidor
  NET_READY        = "vHub:ready",
  NET_DIED         = "vHub:died",
  NET_V_SPAWNED    = "vHub:vSpawned",
  NET_V_DESPAWNED  = "vHub:vDespawned",
  NET_V_ENTER      = "vHub:vEnter",
  NET_V_LEAVE      = "vHub:vLeave",
  NET_V_STATE      = "vHub:vState",
  NET_SELECT_CHAR  = "vHub:selectChar",
  NET_SAVE_POS     = "vHub:savePos",

  -- Eventos server-side (TriggerEvent local)
  EVT_PLAYER_JOIN   = "vHub:playerJoin",
  EVT_PLAYER_LEAVE  = "vHub:playerLeave",
  EVT_PLAYER_SPAWN  = "vHub:playerSpawn",
  EVT_PLAYER_DEATH  = "vHub:playerDeath",
  EVT_CHAR_LOAD     = "vHub:characterLoad",

  -- Eventos cliente-bound (servidor → cliente)
  CLI_INIT_DONE    = "vHub:initDone",
  CLI_CHAR_SEL     = "vHub:charSelected",
  CLI_CHAR_FAIL    = "vHub:charSelectFailed",
  CLI_DO_SPAWN     = "vHub:doSpawn",
}

-- Metatable read-only para evitar escrita acidental
vHub.E = setmetatable({}, {
  __index    = _E,
  __newindex = function(_, k)
    error("[vHub][EVENTS] Constante somente-leitura: " .. tostring(k), 2)
  end,
})
