# vhub_df — Gateway de Pagamento Pix (MercadoPago)

**Versão:** 1.0.0 | **Owner:** vhub_df

Gateway server-authoritative de pagamento Pix via MercadoPago. Emite QR + copia-e-cola, faz polling + webhook e entrega via handlers registrados por prefix. Restart-safe, fail-closed.

---

## O que faz

- Cria cobranças Pix via API MercadoPago (QR + copia-e-cola)
- Polling automático de status + webhook de confirmação
- Sistema de handlers por prefixo: cada domínio registra o seu entregador
- Fila persistente em `vhub_df_orders` — cobranças sobrevivem a restart
- NUI de checkout com countdown e QR code (ou integra UI própria)
- Cancelamento de cobrança pendente

---

## Dependências

```
vhub, oxmysql
```

**Convar obrigatório:**

```cfg
# config/server.cfg
set vhub_df_mp_token "APP_USR-..."    # token MercadoPago
set vhub_df_enabled  "true"
```

---

## Exports disponíveis (server-side, TRUSTED via `vhub_trusted_resources`)

### Status

```lua
-- true se o gateway está pronto para criar cobranças
local ok = exports.vhub_df:isReady()
```

### Registrar handler de entrega

Chame **uma vez no boot** do resource consumidor. O prefixo deve bater com `productKey` da cobrança.

```lua
-- server/init.lua do resource consumidor
exports.vhub_df:registerHandler('coins', function(charId, orderId, meta, done)
  Citizen.CreateThread(function()
    -- creditar moedas...
    local ok = exports.vhub_coinshop:creditCoins(charId, meta.amount)
    if ok then
      done(true, 'credito_ok')
    else
      done(false, 'falha_credito')  -- false = tentar novamente depois
    end
  end)
end)
```

### Criar cobrança

```lua
-- src deve estar online; cb(ok, result) é assíncrono
exports.vhub_df:createPayment(src, {
  amountBRL   = 19.90,
  productKey  = 'coins:100',          -- prefixo 'coins' → handler registrado
  productDesc = '100 Moedas vHub',
  metadata    = { pack = 1, amount = 100 },  -- passado intacto ao handler
  openNui     = true,                 -- false se o consumidor abre a própria UI
}, function(ok, result)
  if ok then
    -- result.txid, result.qrBase64, result.copiaECola, result.expiresAt
  end
end)
```

### Consultas e cancelamento

```lua
-- cobranças pendentes do player (lista)
exports.vhub_df:getPlayerPending(src, function(ok, lista) ... end)

-- status de uma cobrança específica
exports.vhub_df:getOrderStatus(txid, function(ok, status) ... end)

-- cancela cobrança pendente
exports.vhub_df:cancelPayment(src, txid, function(ok, err) ... end)
```

---

## Como criar um novo produto/família

1. No resource consumidor, registre o handler com o prefixo da família:

```lua
exports.vhub_df:registerHandler('meudom', function(charId, orderId, meta, done)
  -- lógica de entrega
  done(true, 'entregue')
end)
```

2. Crie a cobrança com `productKey = 'meudom:produto_especifico'`:

```lua
exports.vhub_df:createPayment(src, {
  amountBRL   = 9.90,
  productKey  = 'meudom:item_premium',
  productDesc = 'Item Premium vHub',
  openNui     = true,
}, cb)
```

O gateway roteia pelo prefixo antes do `:`.

---

## Regras aplicáveis (manual_dev_vhub.md)

| Lei | Aplicação aqui |
|-----|---------------|
| L-01 | Servidor valida entrega; nunca o cliente decide se o pagamento foi aprovado |
| L-07 | Resource consumidor declara ownership do prefixo no Registro de Ownership |
| §3.7 | Exports gated via `vhub_trusted_resources` (default-deny) |
| §4.6 | Rate de criação de cobrança declarado em `CFG.rates` do consumidor |
