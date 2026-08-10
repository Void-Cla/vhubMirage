# vhub_spawselector

**Versão:** 2.3.1 | **Owner:** `vhub_spawselector`

Seleciona uma coordenada; somente o `vhub_hss` move/libera o ped e encerra o bucket privado.

## Fluxo

1. HSS mantém pending, ped congelado/invisível e bucket privado.
2. `vhub_login` chama `preparePending(src)` antes de fechar sua NUI.
3. Cliente seleciona um destino, confirma ou retorna aos personagens.
4. Servidor revalida sessão, índice e permissão.
5. `vhub_hss:spawnAt` libera o jogador; a NUI fecha somente após `SPAWNED` físico.

Com o gate ativo, abertura manual exige `getSessionStep(src) == "spawning"`. O export `preparePending` aceita apenas `vhub_login`.

## Configuração

Edite `shared/config.lua`:

```lua
Config.Location[#Config.Location + 1] = {
  Coords = vector4(-277.146, -881.197, 31.546, 351.19),
  Name = "Estacionamento Central",
  Description = "Nascer no estacionamento central.",
  Image = "parking.png",
  Perm = nil,
}
```

Imagens precisam estar em `ui/images` e no `files` do manifesto. `Perm` é validada no servidor por owner UID, ACE e `vhub_groups`.

## Contratos

- Client export `Open()`: solicita abertura; o servidor valida pending e gate.
- Server export `preparePending(src)`: uso exclusivo de `vhub_login`.
- Eventos públicos: `OPEN`, `REQUEST_OPEN`, `REQUEST_SPAWN`, `RESULT` em `shared/events.lua`.

Proibido usar `SetEntityCoords`, `SetPlayerRoutingBucket` ou ressurreição neste resource.
