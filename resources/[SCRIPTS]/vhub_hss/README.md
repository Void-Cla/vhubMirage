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

Todos os exports de mutação são server-side, default-deny e validam alvo online.

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
