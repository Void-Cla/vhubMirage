-- client/focus.lua — coordenador central de foco NUI (owner único de SetNuiFocus)
---@diagnostic disable: undefined-global

-- PROBLEMA QUE RESOLVE: ~25 resources chamavam SetNuiFocus/SetNuiFocusKeepInput de forma
-- independente, um sobrepondo o outro no mesmo tick (o pior ofensor era o loop por-frame do
-- vhub_target, que fazia SetNuiFocus(false,false) ao perder o alvo e derrubava o cursor de
-- qualquer menu recém-aberto). Sem coordenação, "ninguém sabia quem estava por cima".
--
-- SOLUÇÃO: este módulo é o ÚNICO chamador de SetNuiFocus/SetNuiFocusKeepInput no projeto (L2/HAL,
-- A-06). Resources PEDEM foco (acquireNuiFocus) e DEVOLVEM (releaseNuiFocus); um stack ordenado por
-- prioridade decide quem está no topo. Assim ninguém sobrepõe ninguém — a prioridade arbitra, não a
-- ordem de chamada. Estado 100% client-side efêmero (sem 2ª fonte de verdade, L-04).


-- ============================================================
-- ESTADO (stack de foco)
-- ============================================================

-- Cada entrada: { owner=string, priority=number, cursor=bool, keepInput=bool, seq=number }
local _stack = {}
local _seq = 0
local _applied = nil          -- snapshot do que está aplicado nas natives (anti-reaplicação redundante)

-- Owners autorizados a mexer no foco (default-deny). Export-first: já lista os consumidores
-- previstos mesmo antes de todos migrarem. GetInvokingResource() é a fonte de verdade do caller.
local ALLOWED = {
    vhub_hss = true,          -- o próprio (fluxo de spawn/criação interno)
    vhub_sims = true,         -- criador de personagem
    vhub_login = true,        -- gate de entrada
    vhub_spawselector = true, -- seleção de spawn
    vhub_target = true,       -- eye-target (ex-ofensor nº1)
    vhub_admin = true,
    vhub_ipad = true,
    vhub_inventory = true,
    vhub_coinshop = true,
    vhub_df = true,
    vhub_money = true,
    vhub_garage = true,
    vhub_custom = true,
    vhub_groups = true,
    vhub_outdoors = true,
    vhub_lspdtool = true,
    vhub_vrcs = true,
    vhub_velo = true,
    vhub_wow = true,
}


-- ============================================================
-- GUARDS
-- ============================================================

local function caller_ok()
    local caller = GetInvokingResource()
    -- chamada interna do próprio HSS (sem invoking resource) também é permitida
    if caller == nil or caller == '' then return true end
    return ALLOWED[caller] == true
end

local function valid_owner(owner)
    return type(owner) == 'string' and #owner >= 1 and #owner <= 48
        and owner:match('^[a-zA-Z0-9:_%-]+$') ~= nil
end


-- ============================================================
-- APLICAÇÃO (único ponto que toca as natives de foco)
-- ============================================================

-- Reaplica o topo do stack nas natives. Único lugar do projeto que chama SetNuiFocus*.
local function apply_top()
    local top = _stack[#_stack]
    local want_focus = top ~= nil
    local want_cursor = top ~= nil and top.cursor == true
    local want_keep = top ~= nil and top.keepInput == true

    -- evita reaplicação redundante (o loop por-frame de consumidores não deve spammar a native)
    if _applied
        and _applied.focus == want_focus
        and _applied.cursor == want_cursor
        and _applied.keep == want_keep then
        return
    end

    if want_focus then
        SetNuiFocus(true, want_cursor)
        SetNuiFocusKeepInput(want_keep)
    else
        SetNuiFocus(false, false)
        SetNuiFocusKeepInput(false)
    end
    _applied = { focus = want_focus, cursor = want_cursor, keep = want_keep }
end

local function index_of(owner)
    for i = 1, #_stack do
        if _stack[i].owner == owner then return i end
    end
    return nil
end


-- ============================================================
-- API PÚBLICA (exports gated) + acesso interno
-- ============================================================

-- Adquire foco para 'owner'. opts = { cursor=bool (default true), keepInput=bool, priority=number }.
-- Idempotente: readquirir o mesmo owner ATUALIZA sua entrada e a reordena. Retorna true se aplicado.
local function acquire(owner, opts)
    if not valid_owner(owner) then return false end
    opts = type(opts) == 'table' and opts or {}
    local priority = tonumber(opts.priority) or 10
    local cursor = opts.cursor ~= false          -- default: mostra cursor
    local keepInput = opts.keepInput == true

    local existing = index_of(owner)
    if existing then table.remove(_stack, existing) end

    _seq = _seq + 1
    local entry = {
        owner = owner,
        priority = priority,
        cursor = cursor,
        keepInput = keepInput,
        seq = _seq,
    }
    -- insere mantendo ordem por (priority asc, seq asc): topo = maior prioridade, desempate = mais recente
    local pos = #_stack + 1
    for i = 1, #_stack do
        if _stack[i].priority > priority then pos = i; break end
    end
    table.insert(_stack, pos, entry)
    apply_top()
    return true
end

-- Devolve o foco de 'owner'. Release de owner ausente = no-op seguro. Reaplica o novo topo.
local function release(owner)
    if not valid_owner(owner) then return false end
    local idx = index_of(owner)
    if not idx then return true end   -- no-op: já não estava no stack
    table.remove(_stack, idx)
    apply_top()
    return true
end

-- Limpa TODO o stack e solta o foco (reset defensivo, ex.: onResourceStop de um dono).
local function clear()
    _stack = {}
    apply_top()
end

exports('acquireNuiFocus', function(owner, opts)
    if not caller_ok() then return false end
    return acquire(owner, opts)
end)

exports('releaseNuiFocus', function(owner)
    if not caller_ok() then return false end
    return release(owner)
end)

-- Leitura aberta: há algum owner com foco ativo agora? (para consumidores que só querem checar)
exports('hasNuiFocus', function()
    return #_stack > 0
end)


-- ============================================================
-- ACESSO INTERNO (outros módulos client do HSS, sem export)
-- ============================================================

-- Fachada global para os módulos internos do HSS (customization/native_bridge) usarem sem export.
VHubHSS_Focus = {
    acquire = acquire,
    release = release,
    clear = clear,
}


-- ============================================================
-- CLEANUP
-- ============================================================

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    clear()
end)
