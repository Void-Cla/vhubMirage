# vhub_target

Interação por mira ("targeting") do vHub Mirage — o jogador segura a tecla (padrão `LMENU`),
um olho aparece no centro da tela e opções contextuais surgem ao mirar entidades/zonas.

Conversão vHub do **ox_target 1.18.1**: sem ox_lib, sem frameworks externos, sem CDN.
A **API de exports é contract-compatible com ox_target 1.18.x** (mesmos nomes/assinaturas) —
não é fork com tracking de upstream; é compatibilidade de contrato para consumidores.

## Ownership

- **Dono**: UI de targeting + registro **efêmero client-side** de opções por resource.
- **Sem persistência**: cada consumidor re-registra suas opções no boot; `onClientResourceStop` limpa.
- **Servidor** valida: `toggleEntityDoor` (tipo veículo + porta 0..5 + alcance 5 m + rate) e
  `setEntityHasOptions` (netid vivo + rate + cap). Zero verdade crítica aqui.

## Zonas: target × negócio

- `vhub_target` zonas = **interação por mira** (mostrar opção ao olhar+aproximar) — UX client.
- Zonas de **negócio** (entrar na oficina, trigger server-side) = padrão do domínio dono
  (ex.: `vhub_custom/client/zones.lua`). Não misturar.

## API (exports client)

```lua
exports.vhub_target:addBoxZone({ coords = vec3(...), size = vec3(2,2,2), rotation = 45, options = {...} })
exports.vhub_target:addSphereZone({ coords = vec3(...), radius = 2.0, options = {...} })
exports.vhub_target:addPolyZone({ points = { vec3(...), ... }, thickness = 4, options = {...} })
exports.vhub_target:removeZone(id)            -- id numérico ou nome
exports.vhub_target:zoneExists(id)

exports.vhub_target:addGlobalPed(options)     -- e Vehicle / Object / Player / Option
exports.vhub_target:addModel(models, options)
exports.vhub_target:addEntity(netIds, options)
exports.vhub_target:addLocalEntity(handles, options)
-- remove* correspondentes; homônimos do mesmo resource são substituídos

exports.vhub_target:disableTargeting(bool)    -- desliga o olho por completo
exports.vhub_target:setLocked(bool)           -- trava durante progresso (substitui lib.progressActive)
exports.vhub_target:isActive()
```

Shape de `option`: `{ name, label, icon?, distance?, groups?, items?, bones?, offset?,
canInteract?, onSelect?, event?, serverEvent?, export?, command?, openMenu?, menuName? }`.

- `icon`: chave do mapa local (`car`, `key`, `lock`, `gear`, `wrench`, `bag`, `cart`, `person`,
  `box`, `circle`, `globe`, `flask`, `info`, `warn`, `hand`, `door`, `plus`, `minus`, `check`,
  `close`, `star`, `back`) — classes `fa-*` são normalizadas por alias.
- `groups`: filtro UX via `vhub_groups:getGroupsLocal` (client). **Verdade é server-side.**
- `items`: filtro **UX-only permissivo** — `vhub_inventory` não expõe contagem client-side.
  **O consumidor DEVE validar o item no handler server-side** (`hasItem`/`getItemAmount`).

## Config

`shared/config.lua` → `VHubTarget.cfg`: `hotkey`, `toggleHotkey`, `leftClick`, `debug`,
`drawSprite`, `defaults` (portas de veículo built-in), `maxZones`, `rates`.

---

## Mapa de Integração

| # | Export | Assinatura resumida | Quem consome |
|---|--------|---------------------|--------------|
| 1 | `addBoxZone` | `(id, coords, size, opts) → ok` *(client)* | vhub_money, vhub_sims |
| 2 | `addSphereZone` | `(id, coord, radius, opts) → ok` *(client)* | vhub_conce, vhub_ferinha |
| 3 | `addPolyZone` | `(id, pontos, opts) → ok` *(client)* | vhub_sims |
| 4 | `addModel` | `(model, opts) → ok` *(client)* | vhub_money (ATM), vhub_cadeira |
| 5 | `addEntity` | `(entity, opts) → ok` *(client)* | vhub_cadeira |
| 6 | `addGlobalPed` | `(ped_hash, opts) → ok` *(client)* | vhub_sims (NPC de loja) |
| 7 | `removeZone` | `(id) → ok` *(client)* | vhub_money, vhub_sims, vhub_cadeira |
| 8 | `zoneExists` | `(id) → bool` *(client)* | vhub_target interno |
| 9 | `disableTargeting` | `(bool) → ok` *(client)* | vhub_racha (durante corrida) |
| 10 | `setLocked` | `(bool) → ok` *(client)* | vhub_hss (ped inconsciente) |
| 11 | `isActive` | `() → bool` *(client)* | vhub_target NUI |

## Consome de

| Resource | Exports usados |
|----------|----------------|
| `vhub` (CORE) | `getUser`, `getCharacterId` |

## Eventos emitidos

| Evento | Direção | Payload resumido |
|--------|---------|-----------------|
| `vhub_target:zoneEntered` | client local | `{zoneId, entity?}` |
| `vhub_target:zoneLeft` | client local | `{zoneId}` |
| `vhub_target:optionSelected` | client local | `{zoneId, option}` |
