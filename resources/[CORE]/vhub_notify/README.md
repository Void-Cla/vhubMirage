# vHub Notify — toast global

Front-end **único e global** de notificação (toast) do vHub Mirage.
Identidade visual Mirage (Liquid Glass + Areia + Dourado), 100% offline (sem CDN), PT-BR.

> Canal canônico: o evento **`vHub:notify`**. Qualquer resource notifica o jogador
> por esse evento (ou pelos exports de açúcar abaixo). Não use `SendNUIMessage`
> direto na `ui_page` deste resource a partir de fora.

---

## Tipos

| Tipo (PT-BR) | Alias (EN) | Cor          |
|--------------|------------|--------------|
| `sucesso`    | `success`  | Verde        |
| `erro`       | `error`    | Vermelho     |
| `negado`     | `error`    | Vermelho     |
| `aviso`      | `warning`  | Dourado/Âmbar|
| `info`       | `info`     | Areia        |

Tipo desconhecido cai em `info`. `msg`/`title` são truncados; `duration` é
limitado entre **1000 e 10000 ms** (padrão 5000).

---

## Servidor → jogador

### Forma simples — `(type, msg)`

```lua
TriggerClientEvent('vHub:notify', source, 'sucesso', 'Veículo guardado.')
TriggerClientEvent('vHub:notify', source, 'erro', 'Saldo insuficiente.')
```

### Forma rica — tabela `{ type, title, msg, duration }`

```lua
TriggerClientEvent('vHub:notify', source, {
    type     = 'aviso',
    title    = 'Concessionária',
    msg      = 'IPVA vence em 2 dias.',
    duration = 7000,
})
```

### Export de açúcar (servidor)

```lua
exports.vhub_notify:notify(source, {
    type  = 'sucesso',
    title = 'vHub Roleplay',
    msg   = 'Compra concluída.',
})

-- alias de compatibilidade
exports.vhub_notify:sendAlert(source, { type = 'info', msg = 'Bem-vindo.' })
```

---

## Cliente (local)

```lua
exports.vhub_notify:notify({
    type  = 'info',
    title = 'Dica',
    msg   = 'Pressione E para interagir.',
})

-- ou dispare o evento local
TriggerEvent('vHub:notify', 'sucesso', 'Pronto!')
```

---

## Contrato resumido

- **Evento:** `vHub:notify` — `(type, msg)` **ou** `({ type, title|titulo, msg, duration|tempo })`
- **Export servidor:** `exports.vhub_notify:notify(source, data)` (+ alias `sendAlert`)
- **Export cliente:** `exports.vhub_notify:notify(data)` (+ alias `sendAlert`)

Toda normalização (mapa de tipo PT-BR→EN, coerção/truncamento de texto, clamp de
duração, rate-limit) acontece no cliente antes de chegar ao NUI; o NUI renderiza
texto exclusivamente via `textContent` (sem injeção de HTML).
