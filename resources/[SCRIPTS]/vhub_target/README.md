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
