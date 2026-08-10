# vhub_wow — Motor de Áudio/Vídeo

**Versão:** 2.1.0 | **Owner:** vhub_wow

Motor de áudio standalone (porta mínima do xsound, decisão #34): player YouTube, busca InnerTube/APIv3 e rádio com playlist curada. Consumidor principal: rádio do `vhub_vehcontrol`. Áudio = vhub_wow; vídeo (telinha) = responsabilidade do consumidor de UI (decisão #53).

---

## O que faz

- Playback 2D e 3D de YouTube e URLs diretas de áudio permitidas
- Busca de música: InnerTube (primária, sem chave) + YouTube API v3 (fallback via convar `wow_youtube_key`)
- Rádio: faixa aleatória das mais tocadas (cache curado)
- Controles: pause, resume, volume, distância
- Ducking progressivo pela atividade do `vhub_voicePMA` (máximo de 50%)
- Modo streamer local persistente: silêncio total do WOW, sem afetar voz
- Rate-limit por resource chamador + whitelist default-deny

## Migração 2.1.0

Os exports `Play`, `PlayAtEntity` e `PlayAtCoords` aceitam `duckStrength` opcional no
último argumento. O padrão permanece `0.5`; `1.0` silencia totalmente a fonte quando a
atividade de voz chega a 100%. O valor fica isolado por som e não altera o modo streamer.

## Migração 2.0.3

- Protocolo YouTube usa `channel=widget`, iframe 200x200 e autoplay inicialmente mudo.
- Somente `PLAYING` com avanço de `currentTime` libera volume; stall reporta erro ao consumidor.
- Lifecycle `ready` zera backoff acumulado. Volumes espaciais seguem em lote unico por ciclo.
- Volumes espaciais usam lote unico; entidade fora do escopo apenas recebe volume zero.

## Migração 2.0.2

- Player YouTube aguarda `onReady`; comandos enviados no `load` foram removidos.
- Handshake possui retry de 250 ms e timeout explícito de 10 s.

## Migração 2.0.1

- `vhub_outdoors` pode usar somente `PlayAtCoords`, `SetVolume` e `Destroy`.
- Rate-limit combina deduplicacao por som, burst global por caller/jogador e memoria limitada.
- Cada cliente aceita no maximo 16 sons simultaneos.
- Erros do player retornam por evento server-side rate-limited para retry do consumidor.

## Migração 1.x para 2.0

- Permalink `soundcloud.com` foi removido; use URL direta HTTPS de CDN permitida.
- Exports filtram targets offline/duplicados, limitam 128 destinos e podem retornar
  `false` quando nenhum destinatário for aceito ou o rate-limit bloquear a chamada.
- Scripts remotos de player foram removidos; YouTube usa iframe direto.

---

## Dependências

```
vhub
```

Integração opcional: `vhub_voicePMA`. O WOW pede atividade somente enquanto há som ativo.

## Modo streamer

- `/wow`: abre preferências.
- `/streamermode`: alterna diretamente.
- O painel Som do `vhub_vehcontrol` expõe a mesma preferência.
- KVP local: `vhub_wow_streamer_mode`.
- O ganho zero é aplicado antes do primeiro play em HTML Audio e YouTube.

---

## Exports disponíveis (server-side, TRUSTED default-deny)

Whitelist em `WOW_Config.TrustedResources` e ACL por export em
`WOW_Config.TrustedActions` — sem ambas, **ninguém passa** (N0-2). `targets` é sempre
uma lista de server ids.

### Playback

```lua
-- som 2D (sem posição) nos targets
exports.vhub_wow:Play({src}, 'radio_carro_12', url, 0.5, false)  -- (targets, soundName, url, volume, loop)

-- som 3D ancorado a entidade de rede (client resolve a posição localmente)
exports.vhub_wow:PlayAtEntity({src}, 'radio_carro_12', url, 0.5, netId, 20.0, true)

-- som 3D preso a COORDENADA fixa (TV da cidade/palco/boteco — export-first, decisão #35)
exports.vhub_wow:PlayAtCoords(
  {src}, 'palco_rap', url, 0.8, { x=0, y=0, z=0 }, 30.0, true, 0.9
)

-- destrói som ativo nos targets
exports.vhub_wow:Destroy({src}, 'radio_carro_12')
```

### Controles

```lua
exports.vhub_wow:Pause(targets, soundName)
exports.vhub_wow:Resume(targets, soundName)
exports.vhub_wow:SetVolume(targets, soundName, 0.7)
exports.vhub_wow:SetDistance(targets, soundName, 25.0)   -- clamp em MaxDistance
```

### Busca e rádio

Callbacks Lua **não cruzam** exports de forma confiável — a busca é assíncrona via evento client; o rádio é leitura síncrona do cache.

```lua
-- inicia busca; resultado chega no CLIENT do player via evento 'vhub_wow:searchResults' (query, items)
exports.vhub_wow:RequestSearch(playerSrc, 'nome da música')

-- 1 faixa aleatória das mais tocadas (síncrono, do cache) ou nil se frio
local track = exports.vhub_wow:GetRadioTrack()
```

---

## Como autorizar seu resource

```lua
-- shared/config.lua
WOW_Config.TrustedResources = {
  'vhub_vehcontrol',
  'vhub_outdoors',
  'meu_resource',   -- adicione o seu aqui (com ownership registrado)
}

WOW_Config.TrustedActions = {
  vhub_vehcontrol = { ['*'] = true },
  vhub_outdoors = { play_coords = true, destroy = true },
  meu_resource = { play = true, destroy = true },
}
```

---

## Exemplo de integração (rádio de estabelecimento)

```lua
-- Palco/boteco: toca música para todos os players próximos
local perto = getPlayersNearby(coord, 30.0)  -- sua lógica de proximidade
local track = exports.vhub_wow:GetRadioTrack()
if track then
  exports.vhub_wow:PlayAtCoords(perto, 'boteco_01', track.url, 0.8,
    { x = coord.x, y = coord.y, z = coord.z }, 30.0, false)
end
```

---

## Convars

```cfg
# fallback de busca (opcional — InnerTube funciona sem chave)
set wow_youtube_key "AIza..."
```

---

## Áudio espacial

Atenuação local por distância roda a cada 150 ms somente enquanto existe som posicional ativo.
O volume efetivo preserva separadamente volume-base, fator espacial e ducking de voz.

---

## Regras aplicáveis (manual_dev_vhub.md)

| Lei | Aplicação aqui |
|-----|---------------|
| §3.7 | Default-deny total (N0-2): sem whitelist configurada, nenhum caller passa |
| §4.6 | Rate-limit por resource chamador (janela mínima entre disparos) |
| L-19 | Coordenadas cruzam o export como flat `{x,y,z}` |
| L-08 | Sem leak de estado: `_opAt` indexado por resource (conjunto finito) |

---

## Mapa de Integração

| # | Export | Assinatura resumida | Quem consome |
|---|--------|---------------------|--------------|
| 1 | `Play` | `(targets, soundName, url, vol, loop, duckStrength?) → ok` | vhub_vehcontrol (rádio) |
| 2 | `PlayAtEntity` | `(targets, soundName, url, vol, netId, dist, loop, duckStrength?) → ok` | vhub_vehcontrol (rádio 3D) |
| 3 | `PlayAtCoords` | `(targets, soundName, url, vol, coord, dist, loop, duckStrength?) → ok` | vhub_outdoors |
| 4 | `Destroy` | `(targets, soundName) → ok` | vhub_vehcontrol |
| 5 | `Pause` | `(targets, soundName) → ok` | vhub_vehcontrol |
| 6 | `Resume` | `(targets, soundName) → ok` | vhub_vehcontrol |
| 7 | `SetVolume` | `(targets, soundName, vol) → ok` | vhub_vehcontrol, vhub_outdoors |
| 8 | `SetDistance` | `(targets, soundName, dist) → ok` | vhub_vehcontrol |
| 9 | `RequestSearch` | `(playerSrc, query) → void` | vhub_vehcontrol (busca de música) |
| 10 | `GetRadioTrack` | `() → track\|nil` | vhub_vehcontrol (rádio aleatório) |

## Consome de

| Resource | Exports usados |
|----------|----------------|
| `vhub` (CORE) | `getUser`, `notify` |
| `vhub_voicePMA` | `getVoiceState` (ducking de voz) — soft-dep |

## Eventos emitidos

| Evento | Direção | Payload resumido |
|--------|---------|-----------------|
| `vhub_wow:searchResults` | server→client (player) | `{query, items[]}` |
| `vhub_wow:play` | server→client (targets) | `{soundName, url, vol, loop}` |
| `vhub_wow:destroy` | server→client (targets) | `{soundName}` |
| `vhub_wow:server:audioLifecycle` | server interno | `{src, soundName, status}` |
