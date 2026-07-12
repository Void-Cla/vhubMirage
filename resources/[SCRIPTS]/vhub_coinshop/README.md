# vhub_coinshop — Loja de Moedas vHub Mirage

> Recurso FiveM GTARP para o framework **vHub Mirage** (Lua 5.4, server-authoritative).
> Convertido do FearX-Coinshop para o padrão vHub: alta performance, paleta areia/dourado, PT-BR único.

## Identidade

- **Framework:** vHub Mirage (exports.vhub:*)
- **Paleta:** Liquid Glass + Areia + Dourado (sem lime, sem Tailwind, sem CDN)
- **Idioma:** PT-BR único (locale embutido em `shared/utils.lua`)
- **Performance:** Custo por player O(1); idle 0.00ms; NUI fechada 0.00ms
- **Segurança:** Server-authoritative, exports gated, replay-safe, rate-limited

## Estrutura

```
vhub_coinshop/
├── shared/              # config, events, utils (locale PT-BR)
├── server/              # 11 módulos: sql, core, init, coins, items, purchases,
│                        #            discord, webhooks, testdrive, commands, exports
├── client/              # 3 módulos: init, nui, testdrive
├── nui/                 # Liquid Glass: index.html + css/style.css + js/app.js
├── sql/                 # schema.sql (idempotente, FK INT UNSIGNED CASCADE)
└── INSTALL/             # guia + SQL de instalação/drop
```

## Instalação rápida

1. Copie para `resources/[SCRIPTS]/vhub_coinshop/`
2. Aplique `INSTALL/SQL/install.sql` no MySQL
3. Adicione `ensure vhub_coinshop` ao `server.cfg`
4. Configure admins via ACE: `add_ace vhub.coinshop.admin allow`

Leia `INSTALL/INSTALL GUIDE.txt` para detalhes completos.

## Comandos

| Comando                          | Descrição                              |
| -------------------------------- | -------------------------------------- |
| `/coinshop`                      | Abre o painel administrativo autorizado |
| `/givecoins <id> <qtd>`          | Admin dá moedas a jogador online       |
| `/setcoins <id> <qtd>`           | Admin define saldo absoluto            |
| `/coinshop_addcode <order> <coins>` | Cria código Tebex (console/agent)   |

## Funcionalidades (100% preservadas)

- Catálogo de itens: veículos, itens, armas, ferramentas
- Veículos comprados são registrados e retirados pela garagem canônica
- Categorias padrão + categorias custom (admin)
- Ofertas promocionais com TTL (countdown em tempo real)
- Compra de itens/ofertas com débito atômico + reembolso em falha
- Resgate de códigos Tebex (idempotente, anti-double-redeem)
- Test-drive server-side (veículo, timeout e cleanup autoritativos em bucket exclusivo)
- Painel admin: stats, transações recentes, top-selling, players online
- CRUD admin: itens, categorias, ofertas
- Give/Set coins (admin)
- Customização de UI (cores, opacidade, blur, ícone da moeda)
- Webhooks Discord para auditoria (purchases, redeems, admin actions)
- Avatar Discord opcional (requer bot token)

## Contratos do core usados

| Contrato                                  | Uso                                  |
| ----------------------------------------- | ------------------------------------ |
| `exports.vhub:getUser(src)`               | Identidade do jogador (char_id)      |
| `exports.vhub:getCData/setCData(char,k,v)`| Moedas (key `coinshop_coins`)        |
| `exports.vhub:getGData/setGData(k,v)`     | Settings UI (key `coinshop_ui_settings`) |
| evento `vHub:notify`                      | Notificações amigáveis               |
| `exports.vhub_groups:hasPermission(src,p)`| Permissão admin                      |
| `exports.vhub_inventory:giveItem`             | Entrega de itens                  |
| `exports.vhub_player_state:giveWeapons`       | Entrega de armas de sessão        |
| `exports.vhub_conce:grantVehicle(src, model)`| Registro de veículo comprado        |
| `exports.vhub_player_state:begin/attach/endActivity` | Bucket exclusivo do test-drive |
| `exports.vhub_player_state:teleport(...)` | Teleport do test-drive (owner do ped)|

## Leis vHub honradas

L-01..L-19 (server-authoritative, single-writer, replay-safe, vector types, budgets)
A-01..A-10 (separação de camada, lifecycle, eventbus, lazy load, native bridge, cleanup, delta sync, transparent CEF, assets declarados)

— vHub Mirage • 2026
