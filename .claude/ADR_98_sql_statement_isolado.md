# ADR #98 — Scripts SQL sem `multipleStatements`

Data: 2026-10-04

## Decisão

Cada schema local é separado por `vhub/shared/sql_script.lua` e executado sequencialmente.
O parser respeita strings, identificadores e comentários, limita 4 MiB/512 instruções e
interrompe na primeira falha. `multipleStatements` deixa de ser requisito do driver.

## Motivo

`multipleStatements=true` amplia o impacto de uma injeção SQL: um único payload pode anexar
novas instruções. Os schemas são arquivos locais confiáveis; queries de domínio continuam
parametrizadas e limitadas a uma instrução por chamada.

## Rollback

Reverter esta ADR, os imports `@vhub/shared/sql_script.lua`, os aplicadores e restaurar
explicitamente `multipleStatements=true` apenas durante o rollback.
