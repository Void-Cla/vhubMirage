# Skill — Relay de app do iPad zero-trust (`ipadRelay`)

> Padrão VALIDADO em 3 consumidores: `vhub_racha`, `vhub_lspdtool`, `vhub_coinshop` (#58).
> Aprovado por: vhub_arquiteto + vhub_guardiao_seguranca (gate #58, 2026-07-09).
> Receita completa da plataforma: `resources/[SCRIPTS]/vhub_ipad/manual.md`.

## Quando aplicar

Todo resource que vira app do iPad implementa UM export `ipadRelay(src, action, data)`.
O broker do iPad injeta `src` server-side (não-forjável); o cliente só nomeia `action`+`data`.

## Esqueleto canônico (server/ipad_relay.lua)

```lua
local APP_ID = '<id-do-manifest>'

-- push de volta ao app (owner-binding do broker; pcall na fronteira — R7)
local function push(src, action, data)
    pcall(function() return exports.vhub_ipad:appPush(src, APP_ID, action, data) end)
end

-- string sã do payload: tostring + trim + cap
local function str(v, cap)
    if type(v) ~= 'string' and type(v) ~= 'number' then return nil end
    local s = tostring(v):gsub('^%s+', ''):gsub('%s+$', '')
    if s == '' then return nil end
    return s:sub(1, cap or 64)
end

local actions = {}   -- WHITELIST FECHADA: só chaves declaradas aqui existem

actions.open = function(src, char_id, data) ... end   -- cada ação: rate + validação própria

exports('ipadRelay', function(src, action, data)
    if type(src) ~= 'number' or not GetPlayerName(src) then return false end
    if type(action) ~= 'string' or not actions[action] then return false end
    data = (type(data) == 'table') and data or {}

    CreateThread(function()                     -- REGRA 1: yield NUNCA cruza o export (corrotina abandonada)
        local ok, err = pcall(function()
            local char_id = Core.getCharId(src) -- REGRA 2: identidade SÓ do server (nunca payload)
            if not char_id then return push(src, 'denied', { reason = 'sem_char' }) end
            actions[action](src, char_id, data)
        end)
        if not ok then Core.logErr('ipadRelay ' .. action .. ' estourou: ' .. tostring(err)) end
    end)

    return true   -- resposta imediata; resultado volta por appPush
end)
```

## Invariantes (o que os gates cobram)

1. **Whitelist fechada de ações** — `actions[action]` inexistente = `return false` (sem else genérico).
2. **Rate-limit POR AÇÃO** com valores declarados na shared config (`cfg.rates`), O(1) por `(src, chave)`.
3. **char_id/uid derivados server-side** (`getUser(src)`); `data.char_id` do cliente é LIXO.
4. **Sanitização de todo `data`**: `str()` com cap; número → `tonumber`+clamp. O cap do broker é anti-DoS, não validação de domínio.
5. **Domínio reusado, nunca duplicado**: as ações chamam as MESMAS funções do domínio que a NUI fullscreen (ex.: `Purch.buyItem`) — zero 2ª fonte de verdade (L-04).
6. **Efetor client via evento dedicado** (R9): se a ação precisa do client (ex.: test-drive), o server REVALIDA tudo (item/categoria/estado) e dispara `TriggerClientEvent(E.X, src, <args server-derived>)`. Payload do client jamais escolhe modelo/coord.
7. **Push protocol**: server só envia `data` DEPOIS de receber `open` (a engine garante `onInit < onMount < onShow`, e `open` sai no `onShow` — push espontâneo antes disso quebra refs do fragmento).
8. **Erro nunca silencioso**: pcall do thread loga `logErr` E devolve `result {ok=false}` ao app.

## Colon-call de exports (causa-raiz do #58 — NUNCA repetir)

O wrapper de export do FiveM é `function(self, ...)`. **Dot-call come o 1º argumento**:
`pcall(exports.vhub.getUser, src)` chama `getUser()` com src=nil — falha silenciosa.
SEMPRE: `pcall(function() return exports.vhub:getUser(src) end)`.
Indexar export inexistente (`exports.res.fn`) LANÇA erro, não retorna nil — o truthy-check é inócuo.
