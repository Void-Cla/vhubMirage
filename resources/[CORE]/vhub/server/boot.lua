-- server/boot.lua — lifecycle, net events e autosave
-- REGRA CRÍTICA: Auth:connect é chamado UMA única vez por player,
--   dentro do handler de "vHub:ready". playerConnecting não autentica.

local _RES = GetCurrentResourceName()

function vHub:init(cfg, db_driver)
  -- Normaliza log_level: aceita número (GetConvarInt) ou string
  if type(cfg.log_level) == "number" then
    local m = {[0]="DEBUG",[1]="INFO",[2]="WARN",[3]="ERROR"}
    cfg.log_level = m[cfg.log_level] or "INFO"
  end
  vHub.cfg = cfg
  vHub.State:setDriver(db_driver)

  -- ── onResourceStop — flush de emergência (chunked: yield a cada 50) ──
  AddEventHandler("onResourceStop", function(res)
    if res ~= _RES then return end
    vHub.Logger:warn("boot", "Resource encerrando — flush de emergência...")
    local i = 0
    for _, user in pairs(vHub.Auth._sessions) do
      i = i + 1
      vHub.setUData(user.id, "datatable", vHub.Utils.dataCopy(user.data))
      if i % 50 == 0 then Citizen.Wait(0) end
    end
    vHub.Vehicle:saveAll()
    vHub.State:_flush()
    vHub.Logger:warn("boot", "Flush de emergência concluído.")
  end)

  -- ── onResourceStart — replay de sessões para resources que reiniciaram ──
  -- Quando um resource externo reinicia com jogadores online, seus handlers
  -- de vHub:characterLoad/playerSpawn perderam as sessões existentes.
  -- O vHub re-dispara os eventos para popular os _sessions de todos os recursos.
  AddEventHandler("onResourceStart", function(res)
    if res == _RES then return end  -- ignora self
    -- Pequeno delay garante que o resource novo registrou todos os handlers
    SetTimeout(200, function()
      for _, user in pairs(vHub.Auth._sessions) do
        TriggerEvent("vHub:characterLoad", user)
        TriggerEvent("vHub:playerSpawn",   user, false)
      end
    end)
  end)

  -- ── playerDropped ─────────────────────────────────────────────────────
  AddEventHandler("playerDropped", function(reason)
    local src = source
    if src and src > 0 then
      vHub.Auth:disconnect(src, reason)
      -- GC do rate-limit do source: chaves no padrão "src:action"
      local prefix = tostring(src) .. ":"
      local removidos = 0
      for key in pairs(vHub.Kernel._rate) do
        if key:sub(1, #prefix) == prefix then
          vHub.Kernel._rate[key] = nil
          removidos = removidos + 1
        end
      end
      if removidos > 0 and vHub.Logger then
        vHub.Logger:debug("kernel",
          ("GC _rate src=%d — %d chave(s) removida(s)"):format(src, removidos))
      end
    end
  end)

  -- ── playerConnecting — APENAS deferrals, SEM autenticação ─────────────
  -- Autenticação real ocorre somente em vHub:ready abaixo.
  -- Fazer Auth:connect aqui causava double-connect e criação duplicada de user.
  AddEventHandler("playerConnecting", function(_, _, deferrals)
    deferrals.defer()
    Citizen.CreateThread(function()
      Citizen.Wait(0)
      deferrals.done()
    end)
  end)

  -- ── vHub:ready — ÚNICO ponto de autenticação e spawn ──────────────────
  vHub.Kernel:net("vHub:ready", function(src)
    print(('vHub.boot: ready received src=%s'):format(tostring(src)))

    -- Se já tem sessão: é um respawn (morte, reconexão rápida)
    local existing = vHub.Auth:getUser(src)
    if existing then
      existing.spawns = existing.spawns + 1
      -- Pequeno delay antes de emitir spawn para o cliente estar pronto
      SetTimeout(500, function()
        TriggerEvent("vHub:playerSpawn", existing, false)
        vHub.Kernel:emit(src, "vHub:initDone",
          existing.id, existing.char_id, false)
      end)
      return
    end

    -- Primeira conexão: autenticação completa
    local user = vHub.Auth:connect(src)
    if not user then
      -- connect retornou nil = ban/whitelist — player já foi kickado
      return
    end

    user.spawns = 1

    -- uid=1 é o owner permanente do servidor
    if user.id == 1 then
      if not user.data.is_owner then
        user.data.is_owner = true
        vHub.Logger:info("boot", "uid=1 autenticado como owner — is_owner=true")
      end
      Player(src).state:set("vhub_is_admin", true, true)
    end

    -- Garante personagem padrão se não tem nenhum
    if not user.char_id then
      local chars = vHub.Auth:getCharacters(user.id)
      if #chars == 0 then
        -- Cria personagem padrão automaticamente no primeiro acesso
        local new_cid = vHub.Auth:createCharacter(user.id)
        if new_cid then
          user.char_id             = new_cid
          user.data.last_character = new_cid
          vHub.Logger:info("boot",
            ("uid=%d primeiro personagem criado: char_id=%d"):format(
              user.id, new_cid))
          TriggerEvent("vHub:characterLoad", user)
        else
          vHub.Logger:error("boot",
            ("uid=%d falha ao criar personagem padrão"):format(user.id))
        end
      else
        -- Carrega último personagem usado ou o primeiro da lista
        local cid_load = user.data.last_character or tonumber(chars[1].id)
        if cid_load then
          user.char_id = tonumber(cid_load)
          TriggerEvent("vHub:characterLoad", user)
        end
      end
    end

    -- Delay antes do spawn para garantir que o cliente recebeu initDone
    SetTimeout(500, function()
      TriggerEvent("vHub:playerSpawn", user, true)
      vHub.Kernel:emit(src, "vHub:initDone",
        user.id, user.char_id, true)
    end)

  end, { rate = { 5, 15000, 60000 } })

  -- ── vHub:died ─────────────────────────────────────────────────────────
  vHub.Kernel:net("vHub:died", function(src)
    local user = vHub.Auth:getUser(src)
    if user then
      user.data.last_position = nil   -- reseta posição na morte
      user.data.last_health   = nil
      TriggerEvent("vHub:playerDeath", user)
    end
  end, { rate = { 5, 20000, 30000 } })

  -- ── vHub:selectChar ───────────────────────────────────────────────────
  vHub.Kernel:net("vHub:selectChar", function(src, cid)
    local user = vHub.Auth:getUser(src)
    if not user then return end
    if not vHub.Auth:selectCharacter(user, cid) then
      vHub.Kernel:emit(src, "vHub:charSelectFailed", "not_owned")
    end
  end, { rate = { 3, 10000, 30000 } })

  -- vHub:savePos removido — vhub_player_state é o dono da persistência de posição
  -- via evento vhub_player_state:update (resource externo).

  -- ── Veículos — HANDLERS DESARMADOS (N0-3, 2026-06-21, gate arquiteto+segurança) ──
  -- Cadeia física do CORE DORMENTE por design desde a decisão #24 (verdade no
  -- prontuário vhub_vehicle_state do conce; emitters deletados do vhub_vehcontrol).
  -- Sem emissor legítimo, estes handlers eram superfície 100% hostil: um executor
  -- forjava vEnter/vSpawned com o netid da VÍTIMA → onEnter concedia
  -- NetworkSetEntityOwner(entidade_alheia, atacante) = sequestro de posição (grief).
  -- Mantidos REGISTRADOS (rate-limit + contrato de evento) com corpo NO-OP. NUNCA
  -- reanimar onEnter/onLeave/onStateUpdate/onSpawned sem novo gate (regra da #24).
  local function _vhDisarmed() end
  vHub.Kernel:net("vHub:vSpawned",   _vhDisarmed, { rate = { 15, 5000, 15000 } })
  vHub.Kernel:net("vHub:vDespawned", _vhDisarmed, { rate = { 15, 5000, 15000 } })
  vHub.Kernel:net("vHub:vEnter",     _vhDisarmed, { rate = { 10, 3000, 10000 } })
  vHub.Kernel:net("vHub:vLeave",     _vhDisarmed, { rate = { 10, 3000, 10000 } })
  vHub.Kernel:net("vHub:vState",     _vhDisarmed, { rate = { 8, 1000, 5000 }, async = false })

  -- ── Autosave periódico (chunked: cede o tick a cada 50 sessões) ────────
  local function doSave()
    local n_sess = 0
    for _, user in pairs(vHub.Auth._sessions) do
      n_sess = n_sess + 1
      vHub.setUData(user.id, "datatable", vHub.Utils.dataCopy(user.data))
      if n_sess % 50 == 0 then Citizen.Wait(0) end
    end
    vHub.Vehicle:saveAll()
    vHub.State:_flush()
    vHub.Logger:info("boot",
      ("autosave — %d sessão(ões), %d veículo(s)"):format(
        n_sess, vHub.Utils.tableSize(vHub.Vehicle._veh)))
    SetTimeout((vHub.cfg.save_interval or 60) * 1000, doSave)
  end
  SetTimeout((vHub.cfg.save_interval or 60) * 1000, doSave)

  -- ── Ping check ────────────────────────────────────────────────────────
  if vHub.cfg.ping_check_enabled then
    Citizen.CreateThread(function()
      while true do
        Citizen.Wait((vHub.cfg.ping_check_interval or 30) * 1000)
        for src, _ in pairs(vHub.Auth._sessions) do
          local ping = GetPlayerPing(src)
          if ping and ping > (vHub.cfg.max_ping or 800) then
            local msg = ((vHub.cfg.lang or {}).ping_kick or "Ping alto: %dms.")
            DropPlayer(src, msg:format(ping))
          end
        end
      end
    end)
  end

  vHub.Logger:info("boot", "vHub Boot concluído — sistema pronto.")
end
