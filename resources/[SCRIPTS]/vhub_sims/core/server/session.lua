-- session.lua — máquina de estados autoritativa das sessões SIMS

VHubSimsSession = VHubSimsSession or {}

local Session = VHubSimsSession
local sessions = {}
local results = {}


-- retorna snapshot da sessão ativa
function Session.get(src)
  return sessions[src]
end

-- abre uma sessão exclusiva para o jogador
function Session.start(src, spec)
  if sessions[src] then
    if sessions[src].request_id == spec.request_id then return sessions[src], true end
    return nil, false
  end

  local now = GetGameTimer()
  local ttl = spec.mode == 'creator' and VHubSims.cfg.creator_session_ttl_ms
    or VHubSims.cfg.paid_session_ttl_ms
  spec.state = 'studio'
  spec.started_at = now
  spec.expires_at = now + ttl
  sessions[src] = spec
  results[src] = nil
  return spec, false
end

-- informa se a capability efÃªmera venceu
function Session.expired(session)
  return type(session) ~= 'table' or GetGameTimer() >= (tonumber(session.expires_at) or 0)
end

-- valida vínculo e estado da sessão
function Session.require(src, sessionId, expected)
  local session = sessions[src]
  if not session or type(sessionId) ~= 'string' or session.session_id ~= sessionId then
    return nil, 'invalid_session'
  end
  if expected and session.state ~= expected then return nil, 'invalid_state' end
  return session
end

-- trava a sessão para commit único
function Session.beginCommit(src, sessionId, digest)
  local session, err = Session.require(src, sessionId)
  if not session then
    local cached = results[src]
    if cached and cached.session_id == sessionId and cached.digest == digest then
      return nil, nil, cached.result
    end
    return nil, err
  end
  if session.state == 'committing' then
    if session.commit_digest == digest then return nil, 'busy' end
    return nil, 'conflict'
  end
  if session.state ~= 'studio' then return nil, 'invalid_state' end

  session.state = 'committing'
  session.commit_digest = digest
  return session
end

-- devolve a sessão ao estúdio após falha recuperável
function Session.retry(src)
  local session = sessions[src]
  if session and session.state == 'committing' then session.state = 'studio' end
end

-- conclui e memoriza o último resultado idempotente
function Session.finish(src, result)
  local session = sessions[src]
  if not session then return end
  results[src] = {
    session_id = session.session_id,
    digest = session.commit_digest,
    result = result,
  }
  sessions[src] = nil
end

-- cancela e remove a sessão ativa
function Session.cancel(src, sessionId)
  local session, err = Session.require(src, sessionId, 'studio')
  if not session then return nil, err end
  sessions[src] = nil
  results[src] = nil
  return session
end

-- remove todo estado efêmero do jogador
function Session.cleanup(src)
  local session = sessions[src]
  sessions[src] = nil
  results[src] = nil
  return session
end

-- percorre sessões ativas somente para cleanup de resource
function Session.each(callback)
  local snapshot = {}
  for src, session in pairs(sessions) do snapshot[#snapshot + 1] = { src = src, session = session } end
  for _, entry in ipairs(snapshot) do callback(entry.src, entry.session) end
end
