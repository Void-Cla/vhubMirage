-- client/state.lua — estado local da corrida + State Bag listener.

VHubRachaLocal = {
  open_nui   = false,
  open_editor = false,
  bag        = {},          -- snapshot da state bag local (vhub_racha)
  -- Lobby pending state
  pending    = nil,         -- { inst_id, ready_zone, pending_deadline, mode, track_label }
  confirmed  = false,
  -- Race active (preenchido em race.lua)
  active     = nil,
  -- Blips para os proximos checkpoints (client-side)
  _cp_blips  = {},
  -- Editor draft (recebido do server)
  editor_draft = nil,
}
local L = VHubRachaLocal

-- ── State Bag listener ─────────────────────────────────────────────────────

AddStateBagChangeHandler('vhub_racha',
  ('player:%d'):format(GetPlayerServerId(PlayerId())),
  function(_bag, _key, value)
    if type(value) == 'table' then
      L.bag = value
      L.confirmed = value.confirmed == true
    else
      L.bag = {}
      L.confirmed = false
    end
    TriggerEvent('vhub_racha:local:bag_update', L.bag)
  end)

-- Toast global do core (vhub_notify) — FONTE UNICA de notificacao do racha.
-- Substitui os feeds nativos (BeginTextCommandThefeedPost). A barra de rota/tempo
-- da ready-zone (lobby.lua) NAO passa por aqui — e UI in-game persistente, nao toast.
function VHubRachaLocal.notify(msg, kind)
  local ok = pcall(function()
    exports.vhub_notify:notify({ type = kind or 'info', msg = tostring(msg or '') })
  end)
  if not ok then   -- fallback se o vhub_notify nao estiver de pe
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(tostring(msg or ''))
    EndTextCommandThefeedPostTicker(false, true)
  end
end

function VHubRachaLocal.active_race()  return L.active end
function VHubRachaLocal.set_active(a)  L.active = a end
function VHubRachaLocal.clear_active() L.active = nil end

function VHubRachaLocal.set_pending(p)
  L.pending = p
  L.confirmed = false
end
function VHubRachaLocal.clear_pending()
  L.pending = nil
  L.confirmed = false
end

-- ── API local (outros resources podem checar) ─────────────────────────────

exports('isInRace',     function() return L.active ~= nil and L.bag.state == 'racing' end)
exports('isInLobby',    function() return L.pending ~= nil end)
exports('currentKind',  function() return L.bag and L.bag.kind or nil end)
exports('driftScore',   function() return L.bag and L.bag.drift_score or 0 end)
exports('isReady',      function() return VHubRachaBoot and VHubRachaBoot.READY == true end)
