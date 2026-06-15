---@diagnostic disable: undefined-global, lowercase-global

-- ipad.lua — ponte do LSPD com a plataforma vhub_ipad (App SDK relay).
-- Registra o app "Central LSPD" no catálogo do iPad e roteia TODAS as ações do painel
-- embutido por um único export `ipadRelay`. Verdade crítica (quem é policial, login,
-- BOLO/procurado/prisão) é SEMPRE decidida aqui (L-01); o iPad só transporta (L-04).
--
-- Regras de ouro do receptor de relay:
--   1. corpo em CreateThread — o yield de Citizen.Await NÃO pode cruzar a fronteira C
--      do export (senão a corrotina é abandonada e o appPush de volta nunca dispara).
--   2. zero-trust — valida src + permissão (vhub_groups) + login ANTES de qualquer ação.

local cfg = VHubLspd.cfg

local Accounts = VHubLspd.Accounts
local Bolo     = VHubLspd.Bolo
local Wanted   = VHubLspd.Wanted
local Arrest   = VHubLspd.Arrest

local APP = cfg.ipad.appId

local _authed  = {}  -- [src] = true  (sessão TOTALMENTE logada; limpa no playerDropped)
local _pending = {}  -- [src] = true  (logou mas DEVE trocar a senha antes de agir)
local _cd      = {}  -- [src] = ms    (cooldown de ação mutadora)
local _lcd     = {}  -- [src] = ms    (throttle de tentativa de login → anti-brute/DB-DoS)

local function Log(level, fmt, ...) if VHubLspd.Log then VHubLspd.Log(level, fmt, ...) end end


-- ============================================================
-- HELPERS
-- ============================================================

-- empurra um push ao app do jogador (broker do iPad faz owner-binding)
local function push(src, action, data)
    exports.vhub_ipad:appPush(src, APP, action, data)
end

-- autoridade do domínio (vhub_groups) — NÃO o gate de permissão do manifest
local function isPolice(src)  return VHubLspd.hasPerm(src, cfg.police.permScan)       end
local function canManage(src) return VHubLspd.hasPerm(src, cfg.police.permManageBolo) end

-- cooldown anti-flood por src nas ações mutadoras; true se a ação pode prosseguir
local function cooldownOk(src)
    local now = GetGameTimer()
    if _cd[src] and (now - _cd[src]) < cfg.ipad.actionCdMs then return false end
    _cd[src] = now
    return true
end

-- throttle de tentativa de login (anti-brute-force / anti-DB-DoS); true se pode tentar
local function loginThrottleOk(src)
    local now = GetGameTimer()
    if _lcd[src] and (now - _lcd[src]) < 800 then return false end
    _lcd[src] = now
    return true
end

-- scans recentes (somente leitura; chamado dentro de thread → Await ok)
local function queryScans(limit)
    local p = promise.new()
    exports.oxmysql:query(
        'SELECT plate, flagged, src_kind, created_at FROM vhub_lspd_scans ORDER BY id DESC LIMIT ?',
        { tonumber(limit) or 20 },
        function(rows) p:resolve(rows or {}) end
    )
    return Citizen.Await(p)
end

-- monta o snapshot do painel (dashboard + BOLOs + procurados + scans + rótulos)
local function buildData(src)
    return {
        officer = {
            char_id    = VHubLspd.getCharId(src),
            name       = GetPlayerName(src),
            can_manage = canManage(src),
        },
        bolos  = Bolo   and Bolo.list()   or {},
        wanted = Wanted and Wanted.list() or {},
        scans  = queryScans(cfg.ipad.scanLimit),
        levels = { bolo = cfg.bolo.levels, wanted = cfg.wanted.levels },
    }
end


-- ============================================================
-- AUTENTICAÇÃO (login por char_id + senha)
-- ============================================================

-- valida o login; em sucesso marca a sessão e envia o dashboard (ou pede troca de senha)
local function doLogin(src, data)
    local own = VHubLspd.getCharId(src)
    if not own then push(src, 'login_result', { ok = false, err = 'char_nao_carregado' }); return end

    if tonumber(data.char_id) ~= own then
        push(src, 'login_result', { ok = false, err = 'id_incorreto' }); return
    end

    local status = Accounts.verify(own, tostring(data.password or ''))
    if status == 'bad' then
        push(src, 'login_result', { ok = false, err = 'senha_incorreta' }); return
    end

    if status == 'must_change' then
        -- senha padrão: NÃO concede sessão; só libera a troca de senha (must_change real)
        _pending[src] = true
        _authed[src]  = nil
        push(src, 'login_result', { ok = true, must_change = true })
        return
    end

    _authed[src]  = true
    _pending[src] = nil
    push(src, 'login_result', { ok = true, must_change = false })
    push(src, 'data', buildData(src))
end

-- troca a senha do policial logado/pendente; SÓ aqui a sessão pendente vira autenticada
local function doChangePass(src, data)
    local own = VHubLspd.getCharId(src)
    local ok, err = Accounts.setPassword(own, tostring(data.password or ''))
    push(src, 'pass_changed', { ok = ok == true, err = err })
    if ok then
        _authed[src]  = true
        _pending[src] = nil
        push(src, 'data', buildData(src))
    end
end


-- ============================================================
-- AÇÕES MUTADORAS (BOLO / procurado / prisão / apreensão)
-- ============================================================

-- cria um BOLO de placa (requer permManageBolo)
local function doBoloAdd(src, data)
    if not canManage(src) then push(src, 'action_result', { ok = false, err = 'sem_permissao' }); return end

    local plate = VHubLspd.normalizePlate(data.plate)
    if not plate then push(src, 'action_result', { ok = false, err = 'placa_invalida' }); return end

    local reason = tostring(data.reason or ''):gsub('[%c]', ''):sub(1, cfg.bolo.reasonMaxLen)
    if reason == '' then reason = 'Sem motivo informado' end
    local level = tonumber(data.level)
    if level then level = math.max(1, math.min(#cfg.bolo.levels, math.floor(level))) end

    local ok, err = Bolo.create(VHubLspd.getUid(src), plate, reason, level)
    push(src, 'action_result', { ok = ok == true, kind = 'bolo_add', err = err })
    push(src, 'data', buildData(src))
end

-- remove um BOLO de placa (requer permManageBolo)
local function doBoloDel(src, data)
    if not canManage(src) then push(src, 'action_result', { ok = false, err = 'sem_permissao' }); return end
    local plate = VHubLspd.normalizePlate(data.plate)
    if not plate then push(src, 'action_result', { ok = false, err = 'placa_invalida' }); return end
    local ok = Bolo.remove(plate)
    push(src, 'action_result', { ok = ok == true, kind = 'bolo_del' })
    push(src, 'data', buildData(src))
end

-- cria um mandado de procurado (requer permManageBolo)
local function doWantedAdd(src, data)
    if not canManage(src) then push(src, 'action_result', { ok = false, err = 'sem_permissao' }); return end
    local ok, err = Wanted.create(VHubLspd.getUid(src), data.char_id, data.name, data.reason, data.level)
    push(src, 'action_result', { ok = ok == true, kind = 'wanted_add', err = err })
    push(src, 'data', buildData(src))
end

-- remove um mandado de procurado (requer permManageBolo)
local function doWantedDel(src, data)
    if not canManage(src) then push(src, 'action_result', { ok = false, err = 'sem_permissao' }); return end
    local ok = Wanted.remove(data.char_id)
    push(src, 'action_result', { ok = ok == true, kind = 'wanted_del' })
    push(src, 'data', buildData(src))
end

-- prende o jogador mais próximo (server acha o alvo)
local function doArrest(src)
    local ok, info = Arrest.arrestNearest(src)
    push(src, 'action_result', ok and { ok = true,  kind = 'arrest',  name = info.name }
                                  or  { ok = false, kind = 'arrest',  err  = info })
end

-- solta o detido mais próximo
local function doRelease(src)
    local ok, info = Arrest.releaseNearest(src)
    push(src, 'action_result', ok and { ok = true,  kind = 'release', name = info.name }
                                  or  { ok = false, kind = 'release', err  = info })
end

-- apreende um veículo por placa (reusa o pátio do vhub_garage)
local function doSeize(src, data)
    local ok, info = Arrest.seize(src, data.plate)
    push(src, 'action_result', ok and { ok = true,  kind = 'seize', plate = info.plate }
                                  or  { ok = false, kind = 'seize', err   = info })
end


-- ============================================================
-- DISPATCHER DO RELAY
-- ============================================================

local MUTATORS = {
    bolo_add   = doBoloAdd,
    bolo_del   = doBoloDel,
    wanted_add = doWantedAdd,
    wanted_del = doWantedDel,
    arrest     = function(src) doArrest(src) end,
    release    = function(src) doRelease(src) end,
    seize      = doSeize,
}

-- roteia uma ação do app (já dentro de thread + pcall)
local function handle(src, action, data)
    -- toda ação exige policial (autoridade server-side; o iPad é broker opaco)
    if not isPolice(src) then push(src, 'denied', { reason = 'sem_acesso' }); return end

    if action == 'open' then
        Accounts.ensure(VHubLspd.getCharId(src))   -- 1º acesso = senha padrão '123'
        if _authed[src] then push(src, 'data', buildData(src))
        elseif _pending[src] then push(src, 'login_result', { ok = true, must_change = true })
        else push(src, 'login_required', {}) end
        return
    elseif action == 'login' then
        if not loginThrottleOk(src) then
            push(src, 'login_result', { ok = false, err = 'aguarde' }); return
        end
        doLogin(src, data); return
    end

    -- troca de senha: permitida para sessão pendente (must_change) OU já autenticada
    if action == 'change_password' then
        if not (_authed[src] or _pending[src]) then push(src, 'login_required', {}); return end
        doChangePass(src, data); return
    end

    -- daqui em diante exige sessão TOTALMENTE autenticada (pendente NÃO age)
    if not _authed[src] then push(src, 'login_required', {}); return end

    if action == 'refresh'    then push(src, 'data', buildData(src)); return
    elseif action == 'logout' then _authed[src] = nil; _pending[src] = nil; push(src, 'login_required', {}); return
    end

    -- ações mutadoras: cooldown anti-flood
    local fn = MUTATORS[action]
    if not fn then return end
    if not cooldownOk(src) then push(src, 'action_result', { ok = false, err = 'aguarde' }); return end
    fn(src, data)
end


-- relay do app EMBUTIDO do LSPD (broker vhub_ipad). Responde sempre por appPush.
exports('ipadRelay', function(src, action, data)
    if type(src) ~= 'number' or not GetPlayerName(src) then return false end
    if type(action) ~= 'string' then return false end
    data = (type(data) == 'table') and data or {}

    CreateThread(function()                                   -- ← regra de ouro 1
        local ok, err = pcall(function() handle(src, action, data) end)
        if not ok then Log('error', 'ipadRelay(%s): %s', action, tostring(err)) end
    end)

    return true   -- responde imediato; o resultado volta por appPush
end)


-- NOTA: o app 'lspd' é REGISTRADO no catálogo do iPad como builtin (caminho provado)
-- em vhub_ipad/shared/config.lua → BUILTIN_APPS (ui.source='remote', resource=este,
-- relay→este ipadRelay, dependency='vhub_lspdtool'). A UI e o relay vivem AQUI; só o
-- registro mora no iPad. A disponibilidade segue o estado deste resource (dependency).


-- ============================================================
-- CLEANUP
-- ============================================================

AddEventHandler('playerDropped', function()
    _authed[source]  = nil
    _pending[source] = nil
    _cd[source]      = nil
    _lcd[source]     = nil
end)
