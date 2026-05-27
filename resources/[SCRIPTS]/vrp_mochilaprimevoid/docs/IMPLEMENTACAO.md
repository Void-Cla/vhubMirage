# IMPLEMENTACAO - void_mochila_prime

## 1) Banco de dados
- Execute `database/schema.sql` no seu MySQL.
- Confirme que as tabelas `vrp_inventario_*` e `vrp_lojas_*` foram criadas.

## 2) Recurso FiveM
- Coloque a pasta `void_mochila_prime` dentro de `resources/`.
- Adicione no `server.cfg`:
  - `ensure void_mochila_prime`

## 3) Configuracao
- Ajuste `config.lua`:
  - Teclas (mochila, bau veiculo, lojas)
  - Capacidades e limites
  - Baus de faccao (locais + permissoes)
  - Marketplace (limites e comando)
  - Lojas (tipos e lojas padrao)
- Detalhes completos em `docs/GUIA_CONFIG.md`.

## 4) Dependencias
- vRP (Proxy/Tunnel)
- vrp_garages (se usar abertura de porta-malas)
- DropSystem (opcional para drop visual)

## 5) Uso
- Tecla `I` abre mochila (configuravel).
- Tecla `K` abre bau de veiculo (configuravel).
- Tecla `E` abre bau de faccao quando perto.
- Comando `/market` abre marketplace.

## 6) Integracao
- Evento server: `void_mochila_prime:itemUsed`
  - Recebe: `user_id, itemName, tipo, quantidade`
  - Use para acionar efeitos de itens especificos.

## 7) Validacao
- A recuperacao automatica roda no spawn (se habilitada).
- Para auditoria, verifique `vrp_inventario_auditoria`.
- Testes manuais em `docs/TESTES.md`.
- Comandos de console:
  - `inventario_teste <user_id> [item]`
  - `inventario_relatorio <user_id> <limite>`
