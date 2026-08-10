# vhub_hss — Human State System

**Versão:** 2.2.1 | **Owner:** `vhub_hss`

Owner único do ped associado ao `char_id`: spawn, posição, vida, colete, modelo,
customização, routing buckets e fisiologia. `char_id` continua pertencendo ao CORE.

## Contratos

- Estado persistente: uma linha revisionada; digest validado em todo load.
- Flush terminal: outbox KVP limitado; falha exige ACK SQL síncrono.
- Posição/vida/colete: réplica server-side em 1 Hz; cliente nunca reporta verdade.
- Morte/respawn: transição institucional CORE↔HSS; cliente não conclui respawn.
- Armas: efêmeras por sessão; não persistem.
- Customização: somente por export confiável, sanitizada e com modelo allowlisted.
- APV2: revisão exclusiva, CAS persistido e rollback one-shot auditável.
- Spawn/buckets/monitor funcionam mesmo se SQL/inventário falharem.
- `vhub_routing_bucket`: State Bag server-owned consumida pelo transporte de voz.
- Inventário é integração opcional registrada após o boot.

## Dependências

`vhub`, `oxmysql`.

## Exports de ped

```lua
exports.vhub_hss:spawnAt(src, { x = 0.0, y = 0.0, z = 70.0, heading = 0.0 })
exports.vhub_hss:isPendingSpawn(src)
exports.vhub_hss:teleport(src, x, y, z, heading)
exports.vhub_hss:getPosition(src) -- x, y, z
exports.vhub_hss:setHealth(src, 200)
exports.vhub_hss:setArmour(src, 100)
exports.vhub_hss:revive(src)
exports.vhub_hss:kill(src)
exports.vhub_hss:setPedModel(src, 'mp_m_freemode_01')
exports.vhub_hss:setCustomization(src, custom)
exports.vhub_hss:giveWeapons(src, weapons, clear_before)
exports.vhub_hss:beginActivity(src)
exports.vhub_hss:attachActivityVehicle(src, entity)
exports.vhub_hss:endActivity(src)
exports.vhub_hss:authorizePosition(src, position) -- vhub_racha exato
exports.vhub_hss:beginPendingStage(src, session_id)
exports.vhub_hss:endPendingStage(src, stage_token)
exports.vhub_hss:getCustomization(src)
exports.vhub_hss:getCharacterSummaries(src)
exports.vhub_hss:sanitizeCustomizationPatch(patch)
exports.vhub_hss:commitCustomization(src, patch, expected_revision, operation_id)
exports.vhub_hss:rollbackCustomization(src, rollback_token)
```

Client HSS expõe exclusivamente ao `vhub_sims`: `beginCustomizationPreview`,
`previewCustomization`, `restoreCustomizationPreview`, `setCustomizationCamera`,
`rotateCustomizationPed` e `endCustomizationPreview`.

`setPedModel` preserva skins legadas como override transitório, confirmado pela réplica server-side.

Todos os exports server-side de mutação são default-deny e validam alvo online.

## Export cliente do HUD nativo

```lua
exports.vhub_hss:setNativeHudSuppressed('hud'|'radar', true|false)
```

Gated por resource: `vhub_login` pode suprimir `hud`; `vhub_lspdtool`, `radar`.
Somente o HSS executa `DisplayHud`, `DisplayRadar` e o Scaleform do minimapa.

## Exports fisiológicos

`getState`, `addAdrenaline`, `addStress`, `addPain`, `addBleeding`, `applyItem`,
`useInventoryItem`, `registerItem`, `fullHeal`, `setHandcuffed`, `isHandcuffed`,
`isConscious`, `getAnimBlocks`.

## Eventos

- Server: `vhub_hss:chooseSpawn` — solicita coordenada ao provider.
- Client local: `vhub_hss:spawned` — spawn físico concluído.

Nomes canônicos: `shared/events.lua`.

## Teste persistente

Com `set vhub_test_mode 1`, `vhub_run_tests` cobre retry, flush, reload/digest e outbox.

## Migração

`vhub_player_state` foi REMOVIDO (2026-07-19): a fachada stateless não tinha consumidor
vivo (grep global zero) e os aliases `LEGACY_*` morreram junto. Todo acesso é direto:
`exports.vhub_hss:*`, `vhub_hss:chooseSpawn` e `vhub_hss:spawned`.

## Gate de exclusão da fachada

1. Login, seleção/troca de personagem, spawn escolhido e replay de `vHub:ready`.
2. Morte, correção de autorressurreição, revive HSS/admin e restart em bucket normal/999.
3. Noclip, spectate, jail, grid de corrida, cena VRCS e armas da coinshop.
4. Em ambiente de teste: `set vhub_test_mode 1` + `vhub_run_tests`; validar restart do banco.
5. Resmon com 0/1/128 jogadores: idle `<= 0,02 ms`; p95 `<= 0,10 ms`.

Após aprovação: ADR #71 remove `ensure`, aliases/allowlists legados e a pasta da fachada no
mesmo commit.

---

## Mapa de Integração

| # | Export | Assinatura resumida | Quem consome |
|---|--------|---------------------|--------------|
| 1 | `spawnAt` | `(src, {x,y,z,heading}) → ok` | vhub_spawselector (via chooseSpawn) |
| 2 | `isPendingSpawn` | `(src) → bool` | vhub_login |
| 3 | `teleport` | `(src, x, y, z, heading) → ok` | vhub_admin |
| 4 | `getPosition` | `(src) → x, y, z` | vhub_racha, vhub_vrcs |
| 5 | `setHealth` | `(src, hp) → ok` | vhub_admin, vhub_hss interno |
| 6 | `setArmour` | `(src, arm) → ok` | vhub_admin |
| 7 | `revive` | `(src) → ok` | vhub_admin, vhub_lspdtool |
| 8 | `kill` | `(src) → ok` | vhub_admin |
| 9 | `setPedModel` | `(src, model) → ok` | vhub_sims |
| 10 | `setCustomization` | `(src, custom) → ok` | vhub_sims |
| 11 | `giveWeapons` | `(src, weapons, clear) → ok` | vhub_coinshop |
| 12 | `beginActivity` | `(src) → ok` | vhub_racha |
| 13 | `attachActivityVehicle` | `(src, entity) → ok` | vhub_racha |
| 14 | `endActivity` | `(src) → ok` | vhub_racha |
| 15 | `authorizePosition` | `(src, position) → ok` | vhub_racha |
| 16 | `beginPendingStage` | `(src, session_id) → token` | vhub_racha |
| 17 | `endPendingStage` | `(src, stage_token) → ok` | vhub_racha |
| 18 | `getCustomization` | `(src) → custom` | vhub_sims |
| 19 | `getCharacterSummaries` | `(src) → lista` | vhub_login |
| 20 | `sanitizeCustomizationPatch` | `(patch) → patch_safe` | vhub_sims |
| 21 | `commitCustomization` | `(src, patch, rev, op_id) → ok` | vhub_sims |
| 22 | `rollbackCustomization` | `(src, token) → ok` | vhub_sims |
| 23 | `getState` | `(src) → fisiologia` | vhub_animacao, vhub_lspdtool |
| 24 | `setHandcuffed` | `(src, bool) → ok` | vhub_lspdtool |
| 25 | `isHandcuffed` | `(src) → bool` | vhub_animacao |
| 26 | `isConscious` | `(src) → bool` | vhub_animacao |
| 27 | `getAnimBlocks` | `(src) → blocks` | vhub_animacao |
| 28 | `fullHeal` | `(src) → ok` | vhub_admin |
| 29 | `registerItem` | `(item, handler) → ok` | vhub_hss interno |

## Consome de

| Resource | Exports usados |
|----------|----------------|
| `vhub` (CORE) | `getUser`, `getCharacterId`, `getCData`, `setCData`, `notify` |
| `oxmysql` | Persistência direta do estado do ped |

## Eventos emitidos

| Evento | Direção | Payload resumido |
|--------|---------|-----------------|
| `vhub_hss:chooseSpawn` | server→providers registrados | `{src, char_id}` |
| `vhub_hss:spawned` | server→client (player) | `{coord, char_id}` |
