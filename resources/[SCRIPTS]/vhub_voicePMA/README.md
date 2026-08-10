# vhub_voicePMA

**Versão:** 1.0.0 | **Owner:** `vhub_voicePMA`

Motor de voz Mumble nativo do vHub Mirage. Estado efêmero server-authoritative; zero SQL.

## Recursos

- Proximidade: `Sussurrando` 3 m, `Normal` 8 m, `Gritando` 18 m (`F11`).
- Rádio: `/radio <1-999>`, sair com `/radio sair`, PTT em `Caps Lock`.
- Frequências `900-999`: permissão `policia.radio`.
- Rádio exige item `radio` e fisiologia liberada pelo `vhub_hss`.
- Ligações entram apenas por export server-side confiável.
- Rádio e ligação usam voice targets e submixes Mumble separados.
- Atividade de voz reduz o WOW progressivamente, até 50%.

## Ownership

- `vhub_voicePMA`: proximidade, memberships efêmeros, PTT, targets e submixes.
- `vhub_wow`: playback, volume-base, atenuação musical, ducking e preferência streamer.
- `vhub_hss`: ped, consciência e algemas.

## Exports server-side

Default-deny por `TRUSTED_SERVER_RESOURCES`:

```lua
exports.vhub_voicePMA:setRadioChannel(src, channel)
exports.vhub_voicePMA:leaveRadio(src)
exports.vhub_voicePMA:setCallChannel(src, callId)
exports.vhub_voicePMA:leaveCall(src)
exports.vhub_voicePMA:getVoiceState(src)
exports.vhub_voicePMA:getRadioMembers(channel)
```

## Exports client-side

Mutação default-deny por `TRUSTED_CLIENT_RESOURCES`:

```lua
exports.vhub_voicePMA:setRadioChannel(channel)
exports.vhub_voicePMA:leaveRadio()
exports.vhub_voicePMA:setRadioVolume(0.35)
exports.vhub_voicePMA:setCallVolume(0.60)
exports.vhub_voicePMA:getVoiceState()
```

## Referências

Os quatro projetos usados somente para análise foram arquivados em
`metas/vhub_voicePMA_referencias/`. Nenhum código legado entra no runtime.

---

## Mapa de Integração

| # | Export | Assinatura resumida | Quem consome |
|---|--------|---------------------|--------------|
| 1 | `setRadioChannel` | `(src, channel) → ok` *(server)* | vhub_voicePMA interno |
| 2 | `leaveRadio` | `(src) → ok` *(server)* | vhub_voicePMA interno |
| 3 | `setCallChannel` | `(src, callId) → ok` *(server)* | vhub_voicePMA (ligações) |
| 4 | `leaveCall` | `(src) → ok` *(server)* | vhub_voicePMA interno |
| 5 | `getVoiceState` | `(src) → {channel, inCall, …}` *(server)* | vhub_wow (ducking) |
| 6 | `getRadioMembers` | `(channel) → lista` *(server)* | vhub_admin |
| 7 | `setRadioChannel` | `(channel) → ok` *(client)* | vhub_voicePMA NUI |
| 8 | `leaveRadio` | `() → ok` *(client)* | vhub_voicePMA NUI |
| 9 | `setRadioVolume` | `(vol) → ok` *(client)* | vhub_voicePMA NUI |
| 10 | `setCallVolume` | `(vol) → ok` *(client)* | vhub_voicePMA NUI |
| 11 | `getVoiceState` | `() → state` *(client)* | vhub_wow (ducking client) |

## Consome de

| Resource | Exports usados |
|----------|----------------|
| `vhub` (CORE) | `getUser`, `getCharacterId`, `notify` |
| `vhub_inventory` | `hasItem` (item `radio` para frequências normais) |
| `vhub_groups` | `hasPermissionByChar` (freq 900-999 = policia.radio) |
| `vhub_hss` | `isConscious`, `isHandcuffed` (bloqueio fisiológico) |
| `vhub_wow` | ducking de áudio (voicePMA notifica atividade de voz) |

## Eventos emitidos

| Evento | Direção | Payload resumido |
|--------|---------|-----------------|
| `vhub_voicePMA:channelJoined` | server→client (player) | `{channel}` |
| `vhub_voicePMA:channelLeft` | server→client (player) | `{}` |
| `vhub_voicePMA:voiceActivity` | server→vhub_wow | `{src, active}` |
