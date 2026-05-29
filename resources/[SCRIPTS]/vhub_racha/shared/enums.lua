-- shared/enums.lua — enums de estado do dominio (read-only).
--
-- Apenas valores constantes de estado/categoria. Para eventos de rede, ver
-- shared/events.lua. Para configuracao, ver shared/config.lua. Separacao
-- intencional — cada arquivo tem um proposito unico.


-- ============================================================
-- INST STATE — ciclo de vida da instancia de corrida
-- ============================================================

VHubRachaInstState = {
    LOBBY    = 'lobby',     -- lobby aberto, aguardando jogadores entrarem
    PENDING  = 'pending',   -- jogadores no lobby, aguardando confirmar presenca na ready-zone
    WARMUP   = 'warmup',    -- countdown na grid (3..2..1..GO)
    RACING   = 'racing',    -- corrida em andamento
    FINISHED = 'finished',  -- todos cruzaram a chegada (ou grace expirou)
    CLOSED   = 'closed',    -- premiou e liberou — instancia descartada
}


-- ============================================================
-- MODE — modalidade competitiva
-- ============================================================

VHubRachaMode = {
    RANKED   = 'rankeada',  -- com fee + recompensa + ranking
    TRAINING = 'treino',    -- sem fee, sem recompensa, solo (ainda passa por totem)
    PRIVATE  = 'privada',   -- lobby fechado por convite
}


-- ============================================================
-- KIND — tipo de corrida (cada kind tem client/modes/<kind>.lua)
-- ============================================================

VHubRachaKind = {
    SPRINT     = 'sprint',
    CIRCUIT    = 'circuit',
    DRAG       = 'drag',
    DRIFT      = 'drift',
    SPEEDTRAP  = 'speedtrap',
    TIMEATTACK = 'timeattack',
    FREERUN    = 'freerun',
}


-- ============================================================
-- EDITOR PHASE — passos do editor visual de pistas
-- ============================================================

VHubRachaEditorPhase = {
    IDLE = 'idle',
    GRID = 'grid',  -- posicionando slots de largada
    CPS  = 'cps',   -- adicionando checkpoints
    META = 'meta',  -- preenchendo metadados (NUI)
    DONE = 'done',
}


-- ============================================================
-- VEHICLE CLASS — bitmap de classes GTA V aceitas por categoria
-- (consultado por GetVehicleClass() native)
-- ============================================================

VHubRachaVClass = {
    car   = { [0]=1, [1]=1, [2]=1, [3]=1, [4]=1, [5]=1, [6]=1, [7]=1, [12]=1, [18]=1, [20]=1 },
    bike  = { [8]=1 },
    off   = { [9]=1, [10]=1 },
    truck = { [10]=1, [11]=1, [17]=1 },
    any   = nil,
}
