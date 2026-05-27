# TROUBLESHOOTING - void_mochila_prime

## UI nao abre
- Verifique se o recurso esta `ensure` no `server.cfg`.
- Confirme que o `ui_page` aponta para `nui/index.html`.
- Confira se nao ha erros no F8/console.

## Itens nao aparecem
- Verifique se o banco tem dados em `vrp_inventario_itens`.
- Confira se o item existe em `shared/items.lua`.
- Se usa outros scripts para adicionar itens, use `adicionarItemSeguro` ou sincronize manualmente.

## Marketplace vazio
- O listing exige items na mochila (tabela de inventario).
- Verifique limites em `config.lua` (quantidade, preco, anuncios).

## Bau nao abre
- Certifique-se de estar proximo ao local.
- Verifique permissao em `config.lua` (baus_faccao.permissoes).
- Para veiculo, confirme que `vRPclient.vehList` esta disponivel.

## Drop sem objeto
- `DropSystem` nao encontrado. O item foi removido, mas nao houve spawn visual.

## Erros de SQL
- Execute `database/schema.sql`.
- Garanta que o usuario do MySQL tem permissao para CREATE/ALTER/INSERT.