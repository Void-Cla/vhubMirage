# vhub_coinshop — Loja de Moedas

**Versão:** 2.4.2 | **Owner:** vhub_coinshop

Loja de moedas, itens, veículos e ofertas server-authoritative. Moedas virtuais (coins) compradas via Pix (`vhub_df`) ou creditadas por admin. UI de jogador no iPad (app remoto); painel admin via `/coinshop`. Integra com inventário, concessionária e vhub_df para checkout.

---

## O que faz

- Catálogo de itens: veículos, itens, armas, ofertas com TTL (countdown)
- Compra com moedas: débito atômico + entrega server-side + reembolso em falha
- Checkout Pix via `vhub_df` (QR + copia-e-cola, polling + webhook) — pacotes 1/10/100
- Resgate de códigos promocionais (idempotente, anti-double-redeem)
- Painel admin: stats, transações, top-selling, CRUD de itens/categorias/ofertas
- Webhooks Discord para auditoria (purchases, redeems, admin actions)

> Test-drive foi **removido** na v2.4.0. A UI de jogador migrou para o iPad (app remoto
> `web/app_ipad/`); a NUI própria `nui/` não existe mais.

---

## Dependências

```
vhub, oxmysql, vhub_groups, vhub_inventory, vhub_conce, vhub_df
```

---

## Comandos

| Comando | Descrição |
|---------|-----------|
| `/coinshop` | Abre o painel administrativo (permissão `coinshop.admin`) |
| `/givecoins <id> <qtd>` | Admin dá moedas a jogador online |
| `/setcoins <id> <qtd>` | Admin define saldo absoluto |
| `/coinshop_addcode <order> <coins>` | Cria código de resgate (console) |

Jogador comum abre a loja pelo **iPad** (app CoinShop no catálogo).

---

## Exports disponíveis (server-side)

```lua
-- saldo de moedas do char_id (VRAM-first, key coinshop_coins via CData)
local coins = exports.vhub_coinshop:getCoins(char_id)

-- credita moedas ao char_id (delivery Pix/admin/promo); retorna true/false
local ok = exports.vhub_coinshop:creditCoins(char_id, 500)

-- lista itens do catálogo ativo (para UI externa)
local itens = exports.vhub_coinshop:getItems()

-- lista ofertas (deals) ativas
local deals = exports.vhub_coinshop:getDeals()

-- cria código de resgate com valor em moedas
local code = exports.vhub_coinshop:createRedeemCode(200)

-- relay opaco do app do iPad (chamado APENAS pelo broker vhub_ipad)
exports.vhub_coinshop:ipadRelay(src, action, data)
```

---

## Fluxo de compra com Pix

```
1. Player abre a CoinShop no iPad → escolhe pacote de moedas
2. coinshop chama vhub_df:createPayment (productKey='coins:<pack>')
3. vhub_df abre NUI de checkout com QR + copia-e-cola + countdown
4. Pix pago → vhub_df confirma → chama handler registrado no prefixo 'coins'
5. Handler (server/pix_df.lua) credita moedas + webhook Discord
```

O provider legado `mercadopago` direto (`server/pix_mp.lua`) permanece como dono do catálogo de pacotes; o provider padrão é `vhub_df`.

---

## Contratos do core usados

| Contrato | Uso |
|----------|-----|
| `exports.vhub:getUser(src)` | Identidade do jogador (char_id) |
| `exports.vhub:getCData/setCData` | Moedas (key `coinshop_coins`) — via trust do core |
| `exports.vhub_groups:hasPermission` | Permissão admin (`coinshop.admin`) |
| `exports.vhub_inventory:giveItem` | Entrega de itens |
| `exports.vhub_conce:createVehicle` | Registro de veículo comprado (retirado na garagem) |
| evento `vHub:notify` | Notificações |

---

## Regras aplicáveis (manual_dev_vhub.md)

| Lei | Aplicação aqui |
|-----|---------------|
| L-01 | Entrega de itens/moedas 100% server-side; UI só apresenta |
| L-04 | Moedas = dado do coinshop (escritor único via CData `coinshop_coins`) |
| §3.7 | Exports gated default-deny; `ipadRelay` aceita só o broker vhub_ipad |
| A-10 | Assets do app remoto do iPad declarados em `files{}` (servidos via `cfx-nui-vhub_coinshop`) |
| L-12 | Débito/reembolso de compra em transação atômica |
