# vhub_money — Fleeca Camell (Carteira, Banco e Transferências)

**Versão:** 2.1.1 | **Owner:** vhub_money

Economia monetária server-authoritative. Fonte única de verdade para carteira e banco de cada personagem. Integra ATMs, transferências P2P e auditoria completa de transações.

---

## O que faz

- Mantém `carteira` (dinheiro físico) e `banco` por `char_id`
- Valida e processa pagamentos, saques, depósitos e transferências
- Registra toda transação em log auditável
- Integra com `vhub_target` para menus de ATM/banco
- Expõe saldo local (client-side) via exports client

---

## Dependências

```
oxmysql, vhub, vhub_target
```

---

## Exports disponíveis

### Leitura (servidor — pública)

```lua
-- saldo da carteira (número)
local carteira = exports.vhub_money:getWallet(src)

-- saldo do banco (número)
local banco = exports.vhub_money:getBank(src)

-- retorna wallet, bank, total
local w, b, total = exports.vhub_money:getBalance(src)

-- true se o player é owner financeiro
local ok = exports.vhub_money:isOwner(src)

-- histórico de transações (server id ou char_id, limite padrão 50)
local rows = exports.vhub_money:getTransactions(src, 30)
```

### Leitura (client — local ao script client)

```lua
local carteira = exports.vhub_money:getWalletLocal()
local banco    = exports.vhub_money:getBankLocal()
local w, b, t  = exports.vhub_money:getBalanceLocal()
```

### Pagamentos — try* (público, server-side)

Todos retornam `ok, err`. `dry=true` simula sem efeito.

```lua
-- debita da carteira
local ok, err = exports.vhub_money:tryPayment(src, 500, false)

-- debita do banco
local ok, err = exports.vhub_money:tryWithdraw(src, 500, false)

-- deposita no banco
local ok, err = exports.vhub_money:tryDeposit(src, 500, false)

-- debita carteira + banco (tenta carteira primeiro, depois banco)
local ok, err = exports.vhub_money:tryFullPayment(src, 500, false)
```

### Mutações (TRUSTED — requer whitelist)

```lua
-- adiciona à carteira (razão obrigatória para auditoria)
local ok, err = exports.vhub_money:giveWallet(src, 100, 'salario_turno')

-- adiciona ao banco
local ok, err = exports.vhub_money:giveBank(src, 100, 'recompensa_missao')

-- credita banco por char_id — funciona OFFLINE (payout/reembolso de leilão)
local ok, err = exports.vhub_money:giveBankChar(char_id, 500, 'reembolso_leilao')

-- sobrescreve saldo (cuidado — sem delta, use giveWallet para soma)
local ok, err = exports.vhub_money:setWallet(src, 0, 'reset_admin')
local ok, err = exports.vhub_money:setBank(src, 0, 'reset_admin')

-- transferência validada P2P (src → target_raw; target_raw pode ser src ou char_id)
local ok, err = exports.vhub_money:tryTransfer(actor_src, target_raw, valor, 'motivo')

-- dar dinheiro de player para player (sem validação de débito próprio)
local ok, err = exports.vhub_money:tryGive(actor_src, target_src, valor, 'motivo')

-- ATM: saque e depósito (wrapper com taxas e cooldown configurado)
local ok, err = exports.vhub_money:atmWithdraw(src, valor)
local ok, err = exports.vhub_money:atmDeposit(src, valor)
```

---

## Padrão de uso em outro resource

```lua
-- server/<feature>.lua — cobrar jogador pelo serviço

AddEventHandler('vhub_meudom:server:PagarServico', function(payload)
  local src = source
  if not Core.rate(src, 'pagar', 2000) then return end
  Citizen.CreateThread(function()
    local ok, err = exports.vhub_money:tryPayment(src, 150, false)
    if not ok then
      exports.vhub:notify(src, 'Sem saldo: ' .. tostring(err))
      return
    end
    -- ... lógica de entrega
  end)
end)
```

---

## Regras aplicáveis (manual_dev_vhub.md)

| Lei | Aplicação aqui |
|-----|---------------|
| L-04 / L-13 | Dinheiro é verdade exclusiva do `vhub_money`; nunca use `setCData('banco', ...)` de fora |
| L-01 | Servidor valida e processa; cliente nunca calcula saldo |
| §3.3 | `banco` é chave KV do domínio money; scripts terceiros não escrevem nessa chave |
| §4.6 | Todo evento de cobrança deve ter rate declarado em `CFG.rates` |
