# vhub_garage — Garagem Centralizada

**Versão:** 2.2.1 | **Owner:** vhub_garage

Garagem server-authoritative: spawn/guarda de veículos persistentes, pátio de apreensão, aluguel, IPVA e integração com concessionária e leilão. Consome o prontuário do `vhub_conce` e o contrato de spawn do CORE.

## Persistência na rua

- Entidade criada por `CreateVehicleServerSetter` e retida com `SetEntityOrphanMode(2)`. OneSync continua fazendo streaming/culling; fora do alcance não há simulação por um cliente. Não aumenta raio de streaming nem cria keepalive por jogador.
- Cliente somente inicializa a entidade recebida por netId, com controle e colisão carregados; confirma/reafirma motorista e retenta o assentamento por até 2 s. Modelo permanece carregado até finalizar. ACK vincula source/token/netId e fase diagnóstica allowlist (nunca autoridade). Timeout servidor de 25 s cobre gates cumulativos; réplica tem tolerância de 5 s. Não assume mission ownership do servidor nem relaxa filtro de controle.
- Falha mostra etapa (`cliente_solo`, `cliente_controle`, `replica_owner` etc.), registra diagnóstico e não confirma status/débito. Exceção nativa aparece no F8 com a fase. Cleanup exato entidade/modelo/netId retenta por 1 s; resíduo permanece privado/cancelado, rejeita ACK tardio e exige remoção confirmada no próximo pedido antes de recriar.
- Retirada/guarda serializadas por placa. Sessão, motorista, owner, bucket, modelo e netId são corroborados após Await. `conce:confirmarRetirada` faz CAS de status+posição por identidade persistida; compensação exige a posição exata da operação. Taxa de recuperação mantém carteira e valor anteriores, cobrada após gates; `tryPayment` legado é cache sem Await, não saga durável.
- Uma coleta global a cada `persist_intervalo_s` (mínimo/padrão 30 s), uma lista SQL de `out`, O(veículos rastreados), yield por 50. Salva apenas deslocamento >1 m ou giro >5°. Baseline só avança após sucesso; lista vazia/falha não descarta referências vivas. Posição canônica continua em `vhub_conce`; health/fuel não são sobrescritos.
- Restart somente do resource reanexa entidades vivas e não recolhe carros, inclusive sem jogadores. No primeiro boot do FXServer, os `out` sem entidade seguem `patio_boot_destino='impound'`: journal idempotente antes da mudança de status, com retry convergente. Sentinel efêmero só é marcado ao concluir. Não respawna carros do boot antigo nas ruas.
- Veículo vivo não é apagado por force-out; o jogador deve buscá-lo. Exclusões deliberadas (guardar, polícia/admin, venda) continuam permitidas. KeepEntity não bloqueia solicitação de delete de clientes; exclusão externa/maliciosa requer investigação, não ressuscitação automática.

Validação offline: `lua tools/test_garage_persistencia.lua`. Natives/SQL simulados não substituem FiveM/DB real. Reiniciar conjuntamente `vhub_conce`, `vhub_garage` e `vhub_custom` em teste; sem migração SQL nova. Guardião e suites sintáticas/offline aprovados; gate em jogo ainda pendente.

Smoke obrigatório: retirar/guardar carro, moto, barco e aeronave; afastar-se >500 m e retornar; desconectar o último jogador e reconectar; restart somente da garagem vazia/ocupada; restart FXServer → pátio/liberação; posição/giro e custom/health preservados; duplicata, bucket/sessão alterados durante SQL, timeout ACK, falha SQL; bindings NULL e affectedRows no MySQL/MariaDB real. Não promover sem esse gate.

---

## O que faz

- Spawn e guarda de veículos do player com validação de chave/owner/status/proximidade
- Pátio de apreensão com taxa configurável e resgate
- Aluguel de veículos por tempo com bloqueio automático
- IPVA: exibe validade e impede uso em inadimplência
- Integra com `vhub_ferinha` para delegação de leilão
- Expõe API admin completa para painel vhub_admin

---

## Dependências

```
vhub, vhub_conce, vhub_ferinha, vhub_inventory, vhub_money, vhub_identity, vhub_groups, oxmysql
```

---

## Exports disponíveis (server-side)

### Consulta pública

```lua
-- dados completos do veículo (via conce)
local veh = exports.vhub_garage:getVehicle('ABC1234')

-- lista veículos de um char_id
local lista = exports.vhub_garage:listOwnerVehicles(char_id)

-- true se a placa está no pátio
local ok = exports.vhub_garage:isImpound('ABC1234')

-- timestamp unix de vencimento do IPVA (ou nil)
local ts = exports.vhub_garage:ipvaUntil('ABC1234')
```

### Ações de gestão

```lua
-- transfere veículo sem passar por UI (admin/missão)
local ok = exports.vhub_garage:forceTransfer('ABC1234', new_char_id)

-- apreende veículo no pátio com razão e taxa extra opcional
local ok = exports.vhub_garage:forceImpound('ABC1234', 'policial_blitz', 500)
```

### API Admin (TRUSTED)

```lua
exports.vhub_garage:adminStats()
exports.vhub_garage:adminListVehicles(filter, limit, offset)
exports.vhub_garage:adminGetVehicle('ABC1234')
exports.vhub_garage:adminListByOwner(char_id)
exports.vhub_garage:adminListAuctions(status)
exports.vhub_garage:adminListImpound()
exports.vhub_garage:adminListLogs('ABC1234', 50)
exports.vhub_garage:adminFindOrphans()

-- dar veículo a um char_id (placa_custom = nil para gerar automático)
exports.vhub_garage:adminGiveVehicle(char_id, 'sultan', nil, actor_src)

-- transferir dono
exports.vhub_garage:adminTransfer('ABC1234', new_char_id, actor_src)

-- deletar veículo
exports.vhub_garage:adminDelete('ABC1234', actor_src)

-- alterar status manualmente
exports.vhub_garage:adminSetStatus('ABC1234', 'parked', actor_src)

-- reparar via export (usa commitVehicleState no CORE)
exports.vhub_garage:adminRepair('ABC1234', actor_src)

-- renovar IPVA por N dias
exports.vhub_garage:adminRenewIpva('ABC1234', 30, actor_src)

-- liberar do pátio
exports.vhub_garage:adminReleaseImpound('ABC1234', actor_src)

-- cancelar leilão
exports.vhub_garage:adminCancelAuction(auction_id, actor_src)

-- estoque de concessionária
exports.vhub_garage:adminSetStock('sultan', 5, 120000, actor_src)

-- chaves
exports.vhub_garage:adminGrantKey('ABC1234', char_id, 'full', 30, actor_src)
exports.vhub_garage:adminRevokeKey('ABC1234', char_id, actor_src)

-- spawn/despawn admin
exports.vhub_garage:adminSpawnTo(src, 'ABC1234', { x=0,y=0,z=0,h=0 }, actor_src)
exports.vhub_garage:adminDespawn('ABC1234', actor_src)

-- manutenção
exports.vhub_garage:adminPurgeExpiredKeys(actor_src)
exports.vhub_garage:adminPurgeOldLogs(30, actor_src)
exports.vhub_garage:adminFinalizeStaleAuctions(actor_src)
```

---

## Ciclo de vida do veículo (§3.2 do manual)

```
COMPRA (conce) → SPAWN (garage valida chave+status) → USO (core acumula estado)
→ GUARDAR (garage store) → PÁTIO (impound/admin) → RECUPERAÇÃO
```

A garagem **nunca** escreve estado físico diretamente — usa `commitVehicleState` do CORE para reparos e sync.

---

## Regras aplicáveis (manual_dev_vhub.md)

| Lei | Aplicação aqui |
|-----|---------------|
| L-04 | Dono do veículo = conce; garage consome via `conce:isOwner`/`conce:canOperate` |
| L-13 | Estado físico escrito via `commitVehicleState` (CORE); nunca `setVData` |
| §3.2 | Ciclo completo documentado: compra→spawn→store→pátio |
| §3.8 | Despawn de entidade usa padrão `TaskLeaveVehicle` + `NetworkRequestControlOfEntity` + `DeleteEntity` |

---

## Mapa de Integração

| # | Export | Assinatura resumida | Quem consome |
|---|--------|---------------------|--------------|
| 1 | `openGarage` | `(src) → ok` | vhub_ipad (app), vhub_admin |
| 2 | `storeVehicle` | `(src, plate) → ok` | vhub_admin, vhub_lspdtool (via forceImpound) |
| 3 | `retrieveVehicle` | `(src, plate, coord) → netid` | vhub_admin |
| 4 | `getPlayerVehicles` | `(src) → lista` | vhub_admin |
| 5 | `forceImpound` | `(plate, actor) → ok` | vhub_lspdtool |
| 6 | `adminSpawnVehicle` | `(src, model) → netid` | vhub_admin |
| 7 | `updateStatus` | `(plate, status) → ok` | vhub_ferinha (após leilão) |

## Consome de

| Resource | Exports usados |
|----------|----------------|
| `vhub` (CORE) | `getUser`, `getCharacterId`, `notify` |
| `vhub_conce` | `getPlayerVehicles`, `spawnVehicle`, `despawnVehicle`, `saveVehicleState`, `loadVehicleState`, `forceImpound`, `givePhysicalKey`, `takePhysicalKey`, `getZones`, `resolveConc` |
| `vhub_ferinha` | `listActiveAuctions`, `getZones` (boot) |
| `vhub_inventory` | `hasVehicleKey`, `giveVehicleKey`, `takeVehicleKey` |
| `vhub_money` | `tryPayment` (taxa de retirada) |
| `vhub_identity` | `getIdentity` (opcional, prontuário) |
| `vhub_groups` | `hasPermission` (ações admin) |

## Eventos emitidos

| Evento | Direção | Payload resumido |
|--------|---------|-----------------|
| `vhub_garage:vehicleStored` | server→client (player) | `{plate}` |
| `vhub_garage:vehicleRetrieved` | server→client (player) | `{plate, netid}` |
