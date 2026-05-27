# TESTES - void_mochila_prime

## Transacoes basicas
1. Use o comando `inventario_teste <user_id> [item]` no console do servidor.
2. Verifique se o item foi adicionado e removido sem erros.
3. Consulte `vrp_inventario_transacoes` para status `completa`.

## Falhas controladas
- Tente comprar no marketplace sem saldo e verifique `status = falhada`.
- Tente listar item bloqueado e valide que a NUI rejeita.
- Tente dropar item bloqueado e verifique notificacao.

## Recuperacao
- Force uma transacao pendente e verifique auto-recovery no spawn.

## Auditoria
- Execute `inventario_relatorio <user_id> 20` no console para listar logs.