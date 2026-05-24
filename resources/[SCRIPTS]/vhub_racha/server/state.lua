-- server/state.lua — VRAM da liga (catalogo, instancias, drafts).

VHubRachaState = {
  _catalog   = {},
  _instances = {},
  _by_src    = {},
  _drafts    = {},
  metrics    = { instances_created = 0, instances_started = 0, instances_finished = 0, drafts_saved = 0 },
}
local ST = VHubRachaState

function ST.set_catalog(c) ST._catalog = c or {} end
function ST.catalog()      return ST._catalog end
function ST.track(id)      return ST._catalog[id] end

function ST.put_instance(inst)
  if not inst or not inst.id then return end
  ST._instances[inst.id] = inst
end

function ST.instance(id) return ST._instances[id] end

function ST.remove_instance(id)
  local inst = ST._instances[id]
  if not inst then return end
  for src, _ in pairs(inst.players or {}) do
    if ST._by_src[src] == id then ST._by_src[src] = nil end
  end
  ST._instances[id] = nil
end

function ST.instance_by_src(src)
  local id = ST._by_src[tonumber(src) or 0]
  return id and ST._instances[id] or nil
end

function ST.bind_src(src, id)   ST._by_src[tonumber(src) or 0] = id end
function ST.unbind_src(src)     ST._by_src[tonumber(src) or 0] = nil end

function ST.count_players(inst)
  local n = 0
  if type(inst.players) == 'table' then for _ in pairs(inst.players) do n = n + 1 end end
  return n
end

function ST.public_lobbies()
  local out = {}
  for _, inst in pairs(ST._instances) do
    if inst.state == 'lobby' or inst.state == 'pending' then
      out[#out + 1] = {
        id          = inst.id,
        track_id    = inst.track_id,
        label       = inst.label,
        kind        = inst.kind,
        mode        = inst.mode,
        illegal     = inst.illegal,
        alerts_police = inst.alerts_police,
        creator     = inst.creator_char,
        entry_fee   = inst.entry_fee,
        players     = ST.count_players(inst),
        confirmed   = inst.confirmed_count or 0,
        min_players = inst.min_players,
        max_players = inst.max_players,
        laps        = inst.laps,
        state       = inst.state,
        pending_deadline = inst.pending_deadline or 0,
      }
    end
  end
  return out
end

-- ── Drafts (editor) ────────────────────────────────────────────────────────

function ST.draft_get(char_id) return ST._drafts[char_id] end
function ST.draft_set(char_id, d) ST._drafts[char_id] = d end
function ST.draft_clear(char_id) ST._drafts[char_id] = nil end

function ST.gc_drafts(ttl_ms)
  local now = GetGameTimer()
  for cid, d in pairs(ST._drafts) do
    if d.created_ms and (now - d.created_ms) > ttl_ms then
      ST._drafts[cid] = nil
    end
  end
end

function ST.status_snapshot()
  local n_inst, n_lobby, n_pending, n_racing = 0, 0, 0, 0
  for _, i in pairs(ST._instances) do
    n_inst = n_inst + 1
    if i.state == 'lobby'   then n_lobby   = n_lobby + 1 end
    if i.state == 'pending' then n_pending = n_pending + 1 end
    if i.state == 'racing'  then n_racing  = n_racing + 1 end
  end
  local n_drafts = 0
  for _ in pairs(ST._drafts) do n_drafts = n_drafts + 1 end
  local catalog_size = 0
  for _ in pairs(ST._catalog) do catalog_size = catalog_size + 1 end
  return {
    catalog_size = catalog_size,
    instances    = n_inst,
    lobbies      = n_lobby,
    pending      = n_pending,
    racing       = n_racing,
    drafts       = n_drafts,
    metrics      = ST.metrics,
  }
end
