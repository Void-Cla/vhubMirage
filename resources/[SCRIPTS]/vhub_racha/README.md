# vhub_racha — Liga Clandestina de Corridas

**Versão:** 3.1.0 | **Owner:** vhub_racha

Sistema de corridas ilegais premium: 7 modos (sprint, circuit, drag, drift, speedtrap, timeattack, freerun), ready-zone com totem cinematográfico nativo, editor visual de pistas, ranking ranqueado (PDL) persistido e anti-cheat em camadas. UI completa vive no iPad (app builtin); in-game só overlays HUD/race.

---

## O que faz

- Lobbies com taxa de inscrição, escrow e premiação (via `vhub_money`)
- 7 modos de corrida com checkpoints, voltas e classes de veículo
- Editor visual de pistas in-game (checkpoints, grid, validação)
- Ranking persistido: vitórias, recordes por pista, ladder ranqueada (PDL)
- Anti-cheat: anti-teleport fail-closed, validação de progressão server-side
- Telemetria para replay via `vhub_vrcs` (hooks sob pcall)
- Totem 3D nativo na ready-zone (client/totem.lua — não é NUI)

---

## Dependências

```
oxmysql, vhub, vhub_money, vhub_identity, vhub_groups
```

Soft-dep: `vhub_vrcs` (replay — corrida funciona sem ele).

---

## Exports disponíveis (server-side)

### Read-only (públicos)

```lua
-- catálogo de pistas: { { id, label, district, kind, laps, min/max_players, ... }, ... }
local pistas = exports.vhub_racha:catalog()

-- lobbies públicos abertos
local lobbies = exports.vhub_racha:lobbies()

-- true se o player está em corrida ativa
local ok = exports.vhub_racha:isInRace(src)

-- true se o racha terminou o boot (handshake com o core)
local ok = exports.vhub_racha:isReady()

-- snapshot de status geral (instâncias, players, fase)
local st = exports.vhub_racha:Status()
```

### Ranking (públicos — alimentam perfil/site)

```lua
-- top N por tipo e modo ('wins'|'races'|'podiums')
local top = exports.vhub_racha:topRanking('sprint', 'wins', 50)

-- histórico recente com filtros { kind=, track=, char_id= }
local hist = exports.vhub_racha:historyRecent({}, 30)

-- resultados de uma corrida específica
local res = exports.vhub_racha:resultsOf(history_id)

-- stats agregadas / recordes / perfil completo de um char
local stats = exports.vhub_racha:statsOfChar(char_id)
local recs  = exports.vhub_racha:recordsOfChar(char_id, 30)
local prof  = exports.vhub_racha:profile(char_id)

-- ladder ranqueada (PDL)
local ladder = exports.vhub_racha:rankedLadder(50)
```

### Mutações (TRUSTED — default-deny via `Cfg.TRUSTED_RESOURCES`)

```lua
-- cria lobby programaticamente (payload = mesmo shape do NUI)
local ok, err = exports.vhub_racha:createLobby(src, payload)

-- cancela lobby/instância (admin)
local ok = exports.vhub_racha:cancelLobby(inst_id, 'admin')

-- deleta pista do catálogo (admin)
local ok = exports.vhub_racha:deleteTrack(track_id)

-- relay do app iPad (chamado APENAS pelo broker vhub_ipad)
exports.vhub_racha:ipadRelay(src, action, data)
```

### Exports client-side

```lua
exports.vhub_racha:isInRace()      -- este player está correndo?
exports.vhub_racha:isInLobby()     -- está em lobby?
exports.vhub_racha:currentKind()   -- modo atual ('sprint', 'drift', ...)
exports.vhub_racha:driftScore()    -- score de drift ao vivo (modo drift)
exports.vhub_racha:isReady()       -- client bootou?
```

---

## Exemplo de integração

```lua
-- HUD externo quer saber se deve se esconder durante corrida:
if exports.vhub_racha:isInRace() then hideMyHud() end

-- Perfil social do site consome o profile completo (JSON-friendly, versionado):
local perfil = exports.vhub_racha:profile(char_id)
```

---

## Integração com vhub_vrcs (replay)

O racha EMPURRA telemetria ao VRCS por 2 hooks sob `pcall` (se o VRCS cair, a corrida não quebra). Só corridas **ranqueadas** são gravadas.

---

## Regras aplicáveis (manual_dev_vhub.md)

| Lei | Aplicação aqui |
|-----|---------------|
| L-01 | Progressão de checkpoint, resultado e premiação validados server-side |
| L-13 | Anti-cheat fail-closed: teleport detectado = DQ, sem confiar no client |
| §3.7 | Mutações default-deny (#32): sem whitelist configurada, ninguém passa |
| R-9 | Nomes de evento centralizados em `shared/events.lua` (VHubRachaE) |
| A-10 | NUI 100% local: ícones SVG inline (`web/shared/icons.js`), sem CDN |
