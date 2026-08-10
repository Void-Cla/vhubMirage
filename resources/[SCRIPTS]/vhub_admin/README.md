# vhub_admin — Painel de Administração

**Versão:** 3.1.0 | **Owner:** vhub_admin

Painel de moderação completo: kick/ban/mute/jail, teleporte, controle de jogadores, veículos, mundo, economia, modo espectador, relatórios e logs de auditoria. NUI integrada com design Liquid Glass.

---

## O que faz

- Dashboard em tempo real: lista de players, stats do servidor
- Moderação: kick, ban, unban, mute, jail persistentes (sobrevivem a restart)
- Economia: dar/setar/remover dinheiro (wallet/bank), dar itens, adicionar/remover grupos
- Teleporte: ir/trazer player, coordenadas, waypoint, blips
- Veículos: spawnar, reparar, deletar, flip, wipe, boost
- Mundo: mudar tempo/clima, limpar veículos
- Espectador: modo spec em qualquer player
- Relatórios: players enviam `/report`; admins veem e respondem no painel
- Auditoria: todas as ações logadas com actor/alvo/payload/timestamp

---

## Dependências

```
vhub, vhub_hss, vhub_inventory, vhub_money, vhub_identity, vhub_groups, vhub_garage, oxmysql
```

---

## Exports disponíveis (server-side, TRUSTED)

```lua
-- true se o player tem permissão de abrir o painel admin
local ok = exports.vhub_admin:isAdmin(src)

-- lista players admins conectados: { { src, name }, ... }
local lista = exports.vhub_admin:listAdmins()

-- registra ação externa no log de auditoria do admin
-- payload deve ser tabela plana com dados relevantes à ação
exports.vhub_admin:log(actorSrc, 'meudom:acao', targetSrc, { plate = 'ABC1234' })

-- true se o char_id está preso (jail ativo)
local ok = exports.vhub_admin:isJailed(char_id)

-- true se o char_id está mutado
local ok = exports.vhub_admin:isMuted(char_id)
```

---

## Comandos de console (rcon/server)

```bash
# Banir por user_id
vhub_ban <user_id> <motivo>

# Desbanir por user_id
vhub_unban <user_id>
```

---

## Como integrar ações no painel (ACTIONS data-driven)

O painel usa `shared/actions.lua` como lista data-driven. Para adicionar uma nova ação ao menu admin:

```lua
-- shared/actions.lua
VHubAdmin.ACTIONS[#VHubAdmin.ACTIONS + 1] = {
  id         = 'meudom_acao',
  label      = 'Minha Ação',
  section    = 'economy',         -- economy | teleport | moderation | vehicle | world
  perm       = 'meudom.acao',     -- permissão necessária (vhub_groups)
  event      = 'vhub_admin:ACT_MEUDOM_ACAO',
  params     = { 'target', 'value' },
}
```

---

## Como registrar log de ação externa

Qualquer resource TRUSTED pode registrar ações no histórico de auditoria:

```lua
-- Formato: actorSrc = server id do admin (nil = console), targetSrc = alvo (pode ser nil)
exports.vhub_admin:log(actorSrc, 'lspd:prender', targetSrc, {
  plate  = 'ABC1234',
  motivo = 'excesso de velocidade',
})
```

---

## Permissões necessárias (via vhub_groups)

| Permissão | O que libera |
|-----------|-------------|
| `panel`   | Abrir o painel |
| `economy` | Dar/setar dinheiro, itens, grupos |
| `givemoney` | Dar dinheiro |
| `setmoney` | Setar saldo |
| `giveitem` | Dar item |
| `addgroup` | Adicionar grupo |
| `delgroup` | Remover grupo |
| `moderation` | Kick, ban, mute, jail |
| `vehicle` | Spawnar, reparar, flipar veículos |
| `world` | Mudar tempo/clima |
| `spectator` | Modo espectador |

---

## Regras aplicáveis (manual_dev_vhub.md)

| Lei | Aplicação aqui |
|-----|---------------|
| L-01 | Toda moderação e economia validada server-side; NUI só exibe |
| L-04 | Dinheiro gerenciado por `vhub_money`; grupos por `vhub_groups`; admin delega |
| §3.7 | Exports gated — apenas resources TRUSTED da lista interna |
| §4.6 | Rate de ações moderadas declarado em `CFG.limits` |
| L-12 | Logs de auditoria em SQL atômico (`server/sql.lua`) |

---

## Mapa de Integração

| # | Export | Assinatura resumida | Quem consome |
|---|--------|---------------------|--------------|
| 1 | `isAdmin` | `(src) → bool` | vhub_lspdtool, vhub_coinshop |
| 2 | `listAdmins` | `() → [{src, name}]` | vhub_admin NUI |
| 3 | `log` | `(actorSrc, action, targetSrc, payload) → ok` | vhub_lspdtool, vhub_garage, vhub_ferinha |
| 4 | `isJailed` | `(char_id) → bool` | vhub_login, vhub_spawselector |
| 5 | `isMuted` | `(char_id) → bool` | vhub_voicePMA |

## Consome de

| Resource | Exports usados |
|----------|----------------|
| `vhub` (CORE) | `getUser`, `getCharacterId`, `isAdmin`, `banPlayer`, `notify` |
| `oxmysql` | Logs de auditoria, jail/mute persistentes |
| `vhub_hss` | `teleport`, `revive`, `kill`, `setHealth`, `setArmour`, `fullHeal`, `giveWeapons` |
| `vhub_inventory` | `giveItem`, `getInventory` |
| `vhub_money` | `giveWallet`, `giveBank`, `setWallet`, `setBank`, `getBalance` |
| `vhub_identity` | `getIdentity` |
| `vhub_groups` | `hasPermission`, `addGroup`, `removeGroup`, `getCatalog` |
| `vhub_garage` | `adminSpawnVehicle`, `storeVehicle`, `retrieveVehicle` |

## Eventos emitidos

| Evento | Direção | Payload resumido |
|--------|---------|-----------------|
| `vhub_admin:actionLog` | server interno + webhook Discord | `{actor, action, target, payload, ts}` |
| `vhub_admin:banned` | server→client (target) | `{motivo, expires}` |
