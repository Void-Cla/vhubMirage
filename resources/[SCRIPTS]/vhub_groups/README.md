# vhub_groups — Grupos, Níveis e Permissões

**Versão:** 2.0.0 | **Owner:** vhub_groups

Sistema de grupos hierárquicos por personagem. VRAM-first: carrega no `characterLoad` e mantém cache hot enquanto o player está online. Suporta expiração de grupo e auditoria completa de mutações.

---

## O que faz

- Define grupos (`policia`, `admin`, `mecanico`, etc.) com níveis numéricos (1–100)
- Mapeia permissões a grupos via `shared/definitions.lua` e `shared/permissions.lua`
- Expõe API pública gated para leitura e mutação de grupos
- Emite `vhub_groups:changed` quando o grupo de um jogador é alterado

---

## Dependências

```
vhub, oxmysql
```

---

## Exports disponíveis

### Leitura (pública — qualquer resource pode chamar)

```lua
-- verifica se o jogador está em um grupo (opcional: nível mínimo)
local ok = exports.vhub_groups:hasGroup(src, 'policia', 2)

-- verifica se o jogador tem uma permissão específica
local ok = exports.vhub_groups:hasPermission(src, 'police.arrest')

-- retorna todos os grupos do jogador: { [group_id] = { level, expires_at, ... } }
local grupos = exports.vhub_groups:getGroups(src)

-- retorna o nível do jogador em um grupo, ou nil
local level = exports.vhub_groups:getGroupLevel(src, 'policia')

-- lista srcs de players online em um grupo (opcional: nível mínimo)
local srcs = exports.vhub_groups:getUsersByGroup('policia', 1)

-- lista srcs de players online com uma permissão
local srcs = exports.vhub_groups:getUsersByPermission('police.arrest')

-- true se o player é o owner da conta (uid == 1)
local ok = exports.vhub_groups:isOwner(src)

-- retorna o catálogo de grupos definidos
local catalog = exports.vhub_groups:getCatalog()

-- versões por char_id (funciona offline + online)
local ok  = exports.vhub_groups:hasPermissionByChar(char_id, 'police.arrest')
local grp = exports.vhub_groups:getGroupsByChar(char_id)

-- exports client-side (local ao script client)
local ok = exports.vhub_groups:hasGroupLocal('policia')
local gs = exports.vhub_groups:getGroupsLocal()
```

### Mutações (TRUSTED — requer `_invoker_allowed`)

```lua
-- adiciona grupo; expires_days=nil = permanente
local ok, err = exports.vhub_groups:addGroup(src, 'policia', 3, 30, 'promoção')
local ok, err = exports.vhub_groups:addGroupByChar(char_id, 'policia', 3, nil, 'admin grant')

-- remove grupo
local ok, err = exports.vhub_groups:removeGroup(src, 'policia', 'demitido')
local ok, err = exports.vhub_groups:removeGroupByChar(char_id, 'policia', 'admin remove')

-- muda nível sem recriar o registro
local ok, err = exports.vhub_groups:setGroupLevel(src, 'policia', 5, 'promoção interna')
local ok, err = exports.vhub_groups:setLevelByChar(char_id, 'policia', 5, 'promoção interna')

-- auditoria (TRUSTED)
local rows = exports.vhub_groups:getAuditLog({ group_id = 'policia' }, 50)
```

---

## Como verificar permissão no seu resource (padrão `Core.hasPerm`)

Copie este snippet em `server/core.lua` do seu resource:

```lua
-- verifica permissão: owner > ACE > grupos (padrão canônico §3.4 do manual)
function Core.hasPerm(src, perm)
  local uid = exports.vhub:getUID(src)
  if uid == 1 then return true end
  if IsPlayerAceAllowed(src, 'vhub.' .. perm) then return true end
  return exports.vhub_groups:hasPermission(src, perm) == true
end
```

---

## Como definir grupos e permissões

Edite `shared/definitions.lua` para criar grupos e `shared/permissions.lua` para mapear permissões → grupos. **Não crie grupos fora desses arquivos.**

---

## Evento emitido

```lua
-- disparado no servidor quando grupo de um player muda
AddEventHandler('vhub_groups:changed', function(src) ... end)
```

Use para invalidar cache em outros resources:

```lua
local _cache = {}
AddEventHandler('vhub_groups:changed', function(src) _cache[src] = nil end)
AddEventHandler('playerDropped',       function()    _cache[source] = nil end)
```

---

## Regras aplicáveis (manual_dev_vhub.md)

| Lei | Aplicação aqui |
|-----|---------------|
| L-04 / L-13 | Grupos são verdade do `vhub_groups`; nunca escreva grupo de outro resource diretamente |
| L-17 | Handler `vHub:characterLoad` tem replay-guard interno |
| §3.4 | Use o padrão `Core.hasPerm` (owner > ACE > grupo) em todo resource |
| §4.3 | Cache de export com invalidação por `vhub_groups:changed` + `playerDropped` |

---

## Mapa de Integração

| # | Export | Assinatura resumida | Quem consome |
|---|--------|---------------------|--------------|
| 1 | `hasGroup` | `(src, group) → bool` | vhub_garage, vhub_inventory, vhub_spawselector |
| 2 | `hasPermission` | `(src, perm) → bool` | vhub_garage, vhub_inventory, vhub_coinshop, vhub_admin, vhub_lspdtool |
| 3 | `getGroups` | `(src) → lista` | vhub_admin |
| 4 | `getGroupLevel` | `(src, group) → level` | vhub_lspdtool |
| 5 | `getUsersByGroup` | `(group) → lista` | vhub_admin, vhub_lspdtool |
| 6 | `getUsersByPermission` | `(perm) → lista` | vhub_admin |
| 7 | `isOwner` | `(src, group) → bool` | vhub_groups interno |
| 8 | `getCatalog` | `() → catalogo` | vhub_admin |
| 9 | `addGroup` | `(src, group, level?) → ok` | vhub_admin |
| 10 | `removeGroup` | `(src, group) → ok` | vhub_admin |
| 11 | `setGroupLevel` | `(src, group, level) → ok` | vhub_admin |
| 12 | `hasPermissionByChar` | `(char_id, perm) → bool` | vhub_voicePMA (freq policial) |
| 13 | `getGroupsByChar` | `(char_id) → lista` | vhub_lspdtool |
| 14 | `hasGroupLocal` | `(group) → bool` *(client)* | vhub_spawselector NUI |
| 15 | `getGroupsLocal` | `() → lista` *(client)* | vhub_spawselector NUI |

## Consome de

| Resource | Exports usados |
|----------|----------------|
| `vhub` (CORE) | `getUser`, `getCharacterId`, `getCData`, `setCData` |
| `oxmysql` | Persistência de grupos (`vh_groups`) |

## Eventos emitidos

| Evento | Direção | Payload resumido |
|--------|---------|-----------------|
| `vhub_groups:changed` | server→client (player) | `{src, groups}` |
