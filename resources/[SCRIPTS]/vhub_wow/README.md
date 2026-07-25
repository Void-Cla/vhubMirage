# vhub_wow — Motor de Áudio/Vídeo

**Versão:** 2.0.0 | **Owner:** vhub_wow

Motor de áudio standalone (porta mínima do xsound, decisão #34): player YouTube nocookie, busca InnerTube/APIv3 e rádio com playlist curada. Consumidor principal: rádio do `vhub_vehcontrol`. Áudio = vhub_wow; vídeo (telinha) = responsabilidade do consumidor de UI (decisão #53).

---

## O que faz

- Playback 2D e 3D de YouTube e URLs diretas de áudio permitidas
- Busca de música: InnerTube (primária, sem chave) + YouTube API v3 (fallback via convar `wow_youtube_key`)
- Rádio: faixa aleatória das mais tocadas (cache curado)
- Controles: pause, resume, volume, distância
- Ducking progressivo pela atividade do `vhub_voicePMA` (máximo de 50%)
- Modo streamer local persistente: silêncio total do WOW, sem afetar voz
- Rate-limit por resource chamador + whitelist default-deny

## Migração 1.x para 2.0

- Permalink `soundcloud.com` foi removido; use URL direta HTTPS de CDN permitida.
- Exports filtram targets offline/duplicados, limitam 128 destinos e podem retornar
  `false` quando nenhum destinatário for aceito ou o rate-limit bloquear a chamada.
- Scripts remotos de player foram removidos; YouTube usa iframe `youtube-nocookie` direto.

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

Whitelist em `WOW_Config.TrustedResources` — sem entrada, **ninguém passa** (N0-2). `targets` é sempre uma lista de server ids.

### Playback

```lua
-- som 2D (sem posição) nos targets
exports.vhub_wow:Play({src}, 'radio_carro_12', url, 0.5, false)  -- (targets, soundName, url, volume, loop)

-- som 3D ancorado a entidade de rede (client resolve a posição localmente)
exports.vhub_wow:PlayAtEntity({src}, 'radio_carro_12', url, 0.5, netId, 20.0, true)

-- som 3D preso a COORDENADA fixa (TV da cidade/palco/boteco — export-first, decisão #35)
exports.vhub_wow:PlayAtCoords({src}, 'palco_rap', url, 0.8, { x=0, y=0, z=0 }, 30.0, true)

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
  'meu_resource',   -- adicione o seu aqui (com ownership registrado)
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
