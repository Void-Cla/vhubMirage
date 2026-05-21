# vhub_oxmysql — Driver de Banco de Dados do vHub Mirage

Adapter entre `vHub.State` e o `oxmysql` upstream.  
Responsável por toda a persistência do vHub com segurança e performance para 3.000–6.000 jogadores.

## Ordem obrigatória no server.cfg

```
ensure oxmysql
ensure vhub
ensure vhub_oxmysql
```

O driver se registra automaticamente quando ambos (`vhub` e `vhub_oxmysql`) estiverem iniciados.

## String de conexão (oxmysql)

```
set mysql_connection_string "mysql://usuario:senha@localhost/banco?multipleStatements=true&connectionLimit=20&waitForConnections=true&queueLimit=200"
```

Parâmetros importantes:
- `multipleStatements=true` — obrigatório para queries com `;SELECT LAST_INSERT_ID()`
- `connectionLimit` — número de conexões simultâneas ao MySQL (recomendado: 15–25)
- `waitForConnections=true` — aguarda conexão livre ao invés de rejeitar
- `queueLimit` — limite de espera interno do mysql2

## Arquitetura interna

```
vHub.State:_flush()
    │
    ▼
Driver:batch(ops, n)              ← todas as ops em 1 transação MySQL
    │
    ├── circuit breaker check     ← abre se > 20 falhas em 10s
    ├── retry 1..4 com backoff    ← 80ms → 160ms → 320ms → 640ms
    └── oxmysql:transaction()     ← 1 round-trip TCP para N ops


vHub.State:query(name, params)
    │
    ▼
Driver:query()
    │
    ├── _enqueue(op)              ← fila circular (max 4.000 ops)
    └── worker pool (12 threads)  ← processa FIFO em paralelo
          └── _exec_op()
                ├── circuit breaker check
                ├── retry 1..4 com backoff exponencial
                ├── timeout guard (8s por query)
                └── oxmysql:[query|scalar|execute|insert]()
```

## Modos de query suportados

| mode      | oxmysql call       | retorno                        |
|-----------|--------------------|--------------------------------|
| `query`   | `:query()`         | `table` de linhas              |
| `scalar`  | `:scalar()`        | valor único da 1ª coluna       |
| `execute` | `:update()`        | `number` de linhas afetadas    |
| `insert`  | `:insert()`        | `number` insertId              |

## Circuit breaker

| Estado     | Comportamento                             |
|------------|-------------------------------------------|
| `closed`   | Normal — todas as queries passam          |
| `open`     | Banco instável — queries rejeitadas por 15s |
| `half_open`| Testando — 1 query de prova passa         |

Abre ao detectar 20 falhas em 10 segundos. Fecha automaticamente ao confirmar sucesso em half_open.

## Métricas via export

```lua
-- Em qualquer resource server-side:
local m = exports["vhub_oxmysql"]:getDriverMetrics()
-- {
--   pool_size=12, workers_busy=3, queue_length=0, queue_peak=47,
--   queries_ok=120453, queries_fail=2, timeouts=0, retries=5,
--   batches_ok=8932, batches_fail=0, cb_state="closed", cb_trips=0
-- }
```

## Diagnóstico de problemas

**"Circuit breaker ABERTO"** → MySQL está sobrecarregado ou caiu. Verifique `mysql_connection_string`, `connectionLimit` e o status do MySQL.

**"Fila saturada"** → Mais operações chegando do que o pool consegue processar. Aumente `POOL_SIZE` ou reduza `save_interval` no cfg do vHub.

**"Query não registrada"** → `server/sql.lua` não carregou antes da query ser chamada. Verifique a ordem no `fxmanifest.lua`.

**Batch falhou após N tentativas** → Falha persistente no MySQL. Os dados estão seguros na VRAM do vHub — o batch será reenfileirado automaticamente pelo `vHub.State`.
