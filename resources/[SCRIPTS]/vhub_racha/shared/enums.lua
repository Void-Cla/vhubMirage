-- shared/enums.lua — constantes do dominio (read-only).

VHubRachaE = {
  -- Eventos client/server
  NUI_OPEN          = 'vhub_racha:nui:open',
  NUI_OPENED        = 'vhub_racha:nui:opened',
  NUI_REFRESH       = 'vhub_racha:nui:refresh',
  NUI_RESULT        = 'vhub_racha:nui:result',
  NUI_RANKING       = 'vhub_racha:nui:ranking',
  NUI_RANKING_DATA  = 'vhub_racha:nui:ranking_data',
  NUI_HISTORY       = 'vhub_racha:nui:history',
  NUI_HISTORY_DATA  = 'vhub_racha:nui:history_data',
  NUI_RESULTS       = 'vhub_racha:nui:results',
  NUI_RESULTS_DATA  = 'vhub_racha:nui:results_data',

  LOBBY_CREATE      = 'vhub_racha:lobby:create',
  LOBBY_JOIN        = 'vhub_racha:lobby:join',
  LOBBY_LEAVE       = 'vhub_racha:lobby:leave',
  LOBBY_CANCEL      = 'vhub_racha:lobby:cancel',
  LOBBY_PENDING     = 'vhub_racha:lobby:pending',     -- server → client: jogador em estado pendente
  LOBBY_CONFIRM     = 'vhub_racha:lobby:confirm',     -- client → server: confirma presenca (estando na ready zone)
  LOBBY_CONFIRMED   = 'vhub_racha:lobby:confirmed',   -- server → client: confirmou
  LOBBY_FORCE_START = 'vhub_racha:lobby:force_start', -- criador forca start (apenas confirmados)

  RACE_PREPARE      = 'vhub_racha:race:prepare',
  RACE_START        = 'vhub_racha:race:start',
  RACE_CHECKPOINT   = 'vhub_racha:race:checkpoint',
  RACE_TICK         = 'vhub_racha:race:tick',
  RACE_FINISH       = 'vhub_racha:race:finish',
  RACE_ABORT        = 'vhub_racha:race:abort',
  RACE_POLICE       = 'vhub_racha:race:police_alert',

  NOTIFY            = 'vhub_racha:notify',

  -- Editor visual
  EDITOR_OPEN       = 'vhub_racha:editor:open',
  EDITOR_OPENED     = 'vhub_racha:editor:opened',
  EDITOR_PHASE      = 'vhub_racha:editor:phase',
  EDITOR_ADD_GRID   = 'vhub_racha:editor:add_grid',
  EDITOR_ADD_CP     = 'vhub_racha:editor:add_cp',
  EDITOR_UNDO       = 'vhub_racha:editor:undo',
  EDITOR_NEXT       = 'vhub_racha:editor:next',
  EDITOR_SAVE       = 'vhub_racha:editor:save',
  EDITOR_DISCARD    = 'vhub_racha:editor:discard',
  EDITOR_DRAFT      = 'vhub_racha:editor:draft',   -- server → client: snapshot do draft
}

-- Estado da instancia
VHubRachaInstState = {
  LOBBY     = 'lobby',     -- aguardando jogadores entrarem
  PENDING   = 'pending',   -- jogadores no lobby, aguardando confirmacao na ready-zone
  WARMUP    = 'warmup',    -- countdown na grid
  RACING    = 'racing',
  FINISHED  = 'finished',
  CLOSED    = 'closed',
}

-- Modos competitivos
VHubRachaMode = {
  RANKED   = 'rankeada',
  TRAINING = 'treino',
  PRIVATE  = 'privada',
}

-- Kinds suportados (cada um tem um modo client em client/modes/<kind>.lua)
VHubRachaKind = {
  SPRINT     = 'sprint',
  CIRCUIT    = 'circuit',
  DRAG       = 'drag',
  DRIFT      = 'drift',
  SPEEDTRAP  = 'speedtrap',
  TIMEATTACK = 'timeattack',
  FREERUN    = 'freerun',
}

-- Fases do editor visual
VHubRachaEditorPhase = {
  IDLE  = 'idle',
  GRID  = 'grid',     -- posicionando slots de largada
  CPS   = 'cps',      -- adicionando checkpoints
  META  = 'meta',     -- preenchendo metadados (NUI)
  DONE  = 'done',
}

-- Classes de veiculo (Native GTA V GetVehicleClass)
VHubRachaVClass = {
  car   = { [0]=1,[1]=1,[2]=1,[3]=1,[4]=1,[5]=1,[6]=1,[7]=1,[12]=1,[18]=1,[20]=1 },
  bike  = { [8]=1 },
  off   = { [9]=1,[10]=1 },
  truck = { [10]=1,[11]=1,[17]=1 },
  any   = nil,
}
