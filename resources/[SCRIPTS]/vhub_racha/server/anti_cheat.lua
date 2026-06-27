-- server/anti_cheat.lua — validacao server-side de payloads.

VHubRachaAC = {}
local AC = VHubRachaAC
local Cfg = VHubRachaCfg

function AC.validate_checkpoint(inst, src, payload)
  if type(payload) ~= 'table' then return false, 'payload_invalido' end
  local player = inst.players and inst.players[src]
  if not player then return false, 'jogador_fora_instancia' end

  local idx = tonumber(payload.cp_index) or -1
  if idx < 1 then return false, 'cp_index_invalido' end

  local expected = (player.cp_done or 0) + 1
  if idx ~= expected then
    return false, ('cp_fora_de_ordem:%d!=%d'):format(idx, expected)
  end

  local track = VHubRachaState.track(inst.track_id)
  if not track or not track.checkpoints then return false, 'pista_invalida' end
  local cp_total = #track.checkpoints * math.max(1, tonumber(inst.laps) or track.laps or 1)
  if idx > cp_total then return false, 'cp_alem_do_total' end

  local now_ms = GetGameTimer()
  local last_ms = player.last_cp_ms or player.started_ms or now_ms
  if (now_ms - last_ms) < (Cfg.MIN_CHECKPOINT_MS or 400) then
    return false, 'cp_muito_rapido'
  end

  local cp_target = track.checkpoints[((idx - 1) % #track.checkpoints) + 1]
  if not cp_target then return false, 'cp_alvo_inexistente' end

  -- posicao SERVER-SIDE (zero confianca no cliente; mesmo padrao de grid.in_ready_zone).
  -- Se o ped resolve, a checagem de distancia e OBRIGATORIA (fail-closed) — o atacante
  -- nao consegue mais pular a validacao omitindo `pos` no payload. So cai pro best-effort
  -- do payload quando a entidade nao resolve server-side (ped==0; residual aceito #22d-i).
  local ped = GetPlayerPed(src)
  local pos = (ped and ped ~= 0) and GetEntityCoords(ped) or payload.pos

  if pos and pos.x and pos.y then
    local dx, dy = pos.x - cp_target.x, pos.y - cp_target.y
    local d2 = dx * dx + dy * dy
    local max_d = Cfg.CP_MAX_TELEPORT_DIST or 300
    if d2 > (max_d * max_d) then
      return false, ('teleport_suspeito:%.1f'):format(math.sqrt(d2))
    end
  end

  local speed = tonumber(payload.speed) or 0
  if speed > (Cfg.MAX_SPEED_KMH or 400) then
    player.warns = (player.warns or 0) + 1
  end

  return true
end

function AC.cap_drift_score(reported, started_ms, ended_ms)
  local d = math.max(0, math.floor(tonumber(reported) or 0))
  local secs = math.max(1, math.floor(((ended_ms or 0) - (started_ms or 0)) / 1000))
  local cap_per_sec = Cfg.DRIFT.CAP_PER_SEC or 150
  local max_mult = Cfg.DRIFT.COMBO_MULT[#Cfg.DRIFT.COMBO_MULT] or 3.0
  local cap = math.floor(cap_per_sec * secs * max_mult)
  if d > cap then return cap end
  return d
end

function AC.cap_top_speed(reported)
  local s = math.max(0, math.floor(tonumber(reported) or 0))
  local cap = Cfg.MAX_SPEED_KMH or 400
  if s > cap then return cap end
  return s
end
