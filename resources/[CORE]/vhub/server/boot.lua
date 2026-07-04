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

  -- ADR #41 (F-022): trust vazio = todo export sensível NEGA (default-deny N0-2).
  -- Avisa no boot com ação concreta em vez de falhar silenciosamente em runtime.
  if not cfg.trusted_resources or next(cfg.trusted_resources) == nil then
    vHub.Logger:warn("boot",
      "trusted_resources VAZIO — exports sensíveis serão NEGADOS. " ..
      'Configure: setr vhub_trusted_resources "vhub_conce,vhub_garage,vhub_custom,' ..
      'vhub_vehcontrol,vhub_nitro,vhub_racha,vhub_admin,vhub_ferinha"')
  end

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
    vHub.Logger:debug("boot", ("ready recebido src=%s"):format(tostring(src)))

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

  -- ── Veículos — REANIMAÇÃO GATED (ADR #37, 2026-07-02 — descongelamento FASE 1) ──
  -- Vetor original (ADR #24): forjar vEnter com netid da VÍTIMA → onEnter concedia
  -- NetworkSetEntityOwner à entidade alheia. O gate abaixo fecha o vetor validando a
  -- alegação contra a RÉPLICA server-side: o servidor só aceita se o ped do src está
  -- fisicamente sentado no assento alegado do veículo cuja placa real bate com a
  -- alegada. Atacante não senta no carro da vítima → rejeitado antes de qualquer efeito.
  -- vSpawned/vDespawned PERMANECEM desarmados na superfície de rede: spawn/despawn é
  -- verdade server-side dos donos (garage/conce) via exports gated (server/exports.lua).

  -- valida a alegação (plate, netid) contra a réplica; retorna entidade + placa normalizada
  -- Colapsa espaços internos ANTES de normalizar — mesma regra do plateKey do client
  -- e da normalizePlate local do server/vehicle.lua (placa nativa vem com padding).
  local function veiculoAlegado(plate, netid)
    if type(plate) ~= "string" or type(netid) ~= "number" then return nil end
    local ent = NetworkGetEntityFromNetworkId(netid)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return nil end
    local bruta   = (GetVehicleNumberPlateText(ent) or ""):gsub("%s+", " ")
    local real    = vHub.Utils.normalizePlate(bruta)
    local alegada = vHub.Utils.normalizePlate(plate:gsub("%s+", " "))
    if not real or not alegada or real ~= alegada then return nil end
    return ent, alegada
  end

  -- true se o ped do src está fisicamente no assento alegado do veículo
  local function pedNoAssento(src, ent, seat)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    return GetPedInVehicleSeat(ent, seat) == ped
  end

  vHub.Kernel:net("vHub:vEnter", function(src, plate, netid, seat)
    seat = tonumber(seat)
    if not seat or seat < -1 or seat > 16 then return end
    local ent, placa = veiculoAlegado(plate, netid)
    if not ent then return end
    if not pedNoAssento(src, ent, seat) then
      vHub.Logger:warn("vehicle",
        ("vEnter rejeitado src=%d placa=%s seat=%d — ped fora do assento alegado"):format(
          src, tostring(placa), seat))
      return
    end
    vHub.Vehicle:onEnter(src, placa, netid, seat)
  end, { rate = { 10, 3000, 10000 } })

  vHub.Kernel:net("vHub:vLeave", function(src, plate, seat)
    local placa = vHub.Utils.normalizePlate(plate)
    if not placa then return end
    local vd = vHub.Vehicle._veh[placa]
    if not vd or vd.occupants[src] == nil then return end  -- só sai quem entrou validado
    vHub.Vehicle:onLeave(src, placa, tonumber(seat) or vd.occupants[src])
  end, { rate = { 10, 3000, 10000 } })

  vHub.Kernel:net("vHub:vState", function(src, plate, patch)
    vHub.Vehicle:onStateUpdate(src, plate, patch)  -- exige vd.driver == src internamente
  end, { rate = { 8, 1000, 5000 }, async = false })

  -- Superfície de rede de spawn segue INERTE (registrada p/ rate-limit + contrato)
  local function _vhDisarmed() end
  vHub.Kernel:net("vHub:vSpawned",   _vhDisarmed, { rate = { 15, 5000, 15000 } })
  vHub.Kernel:net("vHub:vDespawned", _vhDisarmed, { rate = { 15, 5000, 15000 } })

  -- Kill-switch replicado (ADR #37): cliente só emite eventos de veículo quando true.
  -- Desarmar de novo = setar false aqui — o tráfego cliente morre sem restart (F-019).
  GlobalState.vh_core_active = true

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
