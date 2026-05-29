-- server/editor.lua — editor visual de pistas.
-- Fluxo (3 fases):
--   1) NUI envia 'open' → cria draft (sem CPs/grid)
--   2) Cliente entra na fase GRID → /racha_addgrid ou buzina captura posicao
--   3) Cliente entra na fase CPS → /racha_addcp captura posicao do veiculo
--   4) NUI envia 'save' com metadados → persiste pista 'custom' no SQL

VHubRachaEditor = {}
local ED = VHubRachaEditor
local Cfg = VHubRachaCfg
local U   = VHubRachaUtils
local ST  = VHubRachaState
local SQL = VHubRachaSQL
local E   = VHubRachaE

local function ms() return GetGameTimer() end


-- ============================================================
-- HELPER — sessao do player (fonte unica: VHubRachaSessions)
-- ============================================================

-- Retorna user da sessao ativa. Zero retry, zero Wait.
-- Substitui o user_of() antigo (retry de 2s + acesso a _sessions privado).
local function user_of(src)
  return VHubRachaSessions and VHubRachaSessions.get(src) or nil
end

function ED.is_allowed(src)
  src = tonumber(src) or 0
  if src <= 0 then return true end
  if IsPlayerAceAllowed(src, Cfg.ADMIN_ACE) then return true end
  local user = user_of(src)
  if user and user.char_id == (Cfg.OWNER_CHAR_ID or 1) then return true end
  local has = false
  pcall(function()
    has = exports.vhub_groups:hasPermission(src, Cfg.EDITOR_PERMISSION) == true
  end)
  return has
end

local function get_pos_h(src)
  local ped = GetPlayerPed(src)
  local veh = GetVehiclePedIsIn(ped, false)
  local x, y, z, h
  if veh and veh ~= 0 then
    local c = GetEntityCoords(veh)
    x, y, z = c.x, c.y, c.z
    h = GetEntityHeading(veh)
  else
    local c = GetEntityCoords(ped)
    x, y, z = c.x, c.y, c.z
    h = GetEntityHeading(ped)
  end
  return x, y, z, h
end

local function char_of(src)
  local user = user_of(src); return user and user.char_id or nil
end

local function push_draft(src, draft)
  TriggerClientEvent(E.EDITOR_DRAFT, src, draft)
end

-- ── Lifecycle ──────────────────────────────────────────────────────────────

function ED.open(src)
  if not ED.is_allowed(src) then
    TriggerClientEvent(E.NOTIFY, src, VHubRachaLang.t('editor.no_permission'), 'error')
    return false
  end
  local char_id = char_of(src); if not char_id then return false end

  local draft = ST.draft_get(char_id) or {
    char_id       = char_id,
    src_creator   = src,
    id            = nil,
    label         = nil,
    kind          = 'sprint',
    illegal       = true,
    alerts_police = false,
    laps          = 1,
    vehicle_class = 'car',
    default_fee   = 1000,
    limit_seconds = 300,
    start         = nil,
    grid          = {},
    checkpoints   = {},
    phase         = 'grid',
    created_ms    = ms(),
  }
  ST.draft_set(char_id, draft)
  TriggerClientEvent(E.EDITOR_OPENED, src, draft)
  return true
end

function ED.set_phase(src, phase)
  local char_id = char_of(src); if not char_id then return end
  local draft = ST.draft_get(char_id); if not draft then return end
  if phase == 'grid' or phase == 'cps' or phase == 'meta' or phase == 'idle' then
    draft.phase = phase
    push_draft(src, draft)
    TriggerClientEvent(E.EDITOR_PHASE, src, { phase = phase })
  end
end

function ED.discard(src)
  local char_id = char_of(src); if not char_id then return end
  ST.draft_clear(char_id)
  TriggerClientEvent(E.NOTIFY, src, VHubRachaLang.t('editor.discarded'), 'info')
end

function ED.add_grid(src)
  local char_id = char_of(src); if not char_id then return end
  local draft = ST.draft_get(char_id); if not draft then return end
  if #draft.grid >= (Cfg.EDITOR_MAX_GRID or 12) then
    TriggerClientEvent(E.NOTIFY, src, VHubRachaLang.t('editor.max_grid'), 'error')
    return
  end
  local x, y, z, h = get_pos_h(src)
  local entry = {
    x = math.floor(x * 100) / 100,
    y = math.floor(y * 100) / 100,
    z = math.floor(z * 100) / 100,
    h = math.floor(h * 10) / 10,
  }
  draft.grid[#draft.grid + 1] = entry
  if not draft.start then
    draft.start = { x = entry.x, y = entry.y, z = entry.z, h = entry.h }
  end
  push_draft(src, draft)
  TriggerClientEvent(E.NOTIFY, src,
    VHubRachaLang.t('editor.grid_saved', { #draft.grid }), 'success')
end

function ED.add_cp(src)
  local char_id = char_of(src); if not char_id then return end
  local draft = ST.draft_get(char_id); if not draft then return end
  if #draft.checkpoints >= (Cfg.EDITOR_MAX_CPS or 80) then
    TriggerClientEvent(E.NOTIFY, src, VHubRachaLang.t('editor.max_cps'), 'error')
    return
  end
  local x, y, z = get_pos_h(src)
  draft.checkpoints[#draft.checkpoints + 1] = {
    x = math.floor(x * 100) / 100,
    y = math.floor(y * 100) / 100,
    z = math.floor(z * 100) / 100,
    radius = 11.0,
    kind   = 'normal',
  }
  push_draft(src, draft)
  TriggerClientEvent(E.NOTIFY, src,
    VHubRachaLang.t('editor.cp_saved', { #draft.checkpoints }), 'success')
end

function ED.undo(src)
  local char_id = char_of(src); if not char_id then return end
  local draft = ST.draft_get(char_id); if not draft then return end
  if #draft.checkpoints == 0 then return end
  draft.checkpoints[#draft.checkpoints] = nil
  push_draft(src, draft)
  TriggerClientEvent(E.NOTIFY, src,
    VHubRachaLang.t('editor.undo', { #draft.checkpoints }), 'info')
end

-- Salva com payload { id, label, kind, illegal, alerts_police, laps, fee, limit, class }
function ED.save(src, meta)
  local char_id = char_of(src); if not char_id then return false, 'sem_char' end
  local draft = ST.draft_get(char_id); if not draft then return false, 'sem_draft' end

  meta = type(meta) == 'table' and meta or {}
  local id    = U.sanitize_id(meta.id or '')
  local label = U.sanitize_label(meta.label or '')
  if id == '' then
    TriggerClientEvent(E.NOTIFY, src, VHubRachaLang.t('editor.id_invalid'), 'error')
    return false, 'id_invalido'
  end
  if #draft.grid == 0 then
    TriggerClientEvent(E.NOTIFY, src, VHubRachaLang.t('editor.need_grid'), 'error')
    return false, 'sem_grid'
  end
  if #draft.checkpoints == 0 and draft.kind ~= 'freerun' then
    TriggerClientEvent(E.NOTIFY, src, VHubRachaLang.t('editor.need_cps'), 'error')
    return false, 'sem_cps'
  end

  local existing = ST.track(id)
  if existing and existing.source ~= 'custom' then
    TriggerClientEvent(E.NOTIFY, src, VHubRachaLang.t('editor.id_conflict'), 'error')
    return false, 'id_do_config'
  end
  if existing and existing.creator_char ~= 0
     and existing.creator_char ~= char_id then
    TriggerClientEvent(E.NOTIFY, src, VHubRachaLang.t('editor.id_taken'), 'error')
    return false, 'id_de_outro'
  end

  -- Aplica metadados ao draft
  draft.kind          = (VHubRachaKind[ (meta.kind or 'sprint'):upper() ] or meta.kind) or 'sprint'
  draft.laps          = U.clamp_int(meta.laps or draft.laps, 1, 10)
  draft.illegal       = meta.illegal == true or meta.illegal == 1
  draft.alerts_police = meta.alerts_police == true or meta.alerts_police == 1
  draft.vehicle_class = U.sanitize_id(meta.vehicle_class or 'car')
  draft.default_fee   = U.clamp_int(meta.default_fee or 1000, 0, Cfg.MAX_ENTRY_FEE or 100000)
  draft.limit_seconds = U.clamp_int(meta.limit_seconds or 300, 0, 7200)

  local track = {
    id            = id,
    label         = label ~= '' and label or id,
    district      = U.sanitize_label(meta.district or 'Custom'),
    kind          = draft.kind,
    creator_char  = char_id,
    illegal       = draft.illegal,
    alerts_police = draft.alerts_police,
    laps          = draft.laps,
    min_players   = U.clamp_int(meta.min_players or 1, 1, math.max(1, #draft.grid)),
    max_players   = U.clamp_int(meta.max_players or #draft.grid, 1, #draft.grid),
    vehicle_class = draft.vehicle_class,
    default_fee   = draft.default_fee,
    limit_seconds = draft.limit_seconds,
    start         = draft.start,
    source        = 'custom',
  }
  SQL.upsert_track(track)
  SQL.set_checkpoints(id, draft.checkpoints)
  SQL.set_grid(id, draft.grid)

  track.grid        = draft.grid
  track.checkpoints = draft.checkpoints
  ST._catalog[id]   = track

  ST.metrics.drafts_saved = ST.metrics.drafts_saved + 1
  ST.draft_clear(char_id)

  -- Informa o cliente para limpar o draft/overlay local imediatamente
  pcall(function() TriggerClientEvent(E.EDITOR_DRAFT, src, {}) end)

  TriggerClientEvent(E.NOTIFY, src,
    VHubRachaLang.t('editor.saved', { track.label, #track.checkpoints, #track.grid }), 'success')
  return true, { id = id }
end

function ED.snapshot(src)
  local char_id = char_of(src); if not char_id then return nil end
  return ST.draft_get(char_id)
end
