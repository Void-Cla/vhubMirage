# Skill — Resiliência do batch SQL (poison-op + âncora FK)

> Padrão validado na decisão #47 (2026-07-02: flood real em dev com `/spawncar`;
> 2026-07-03: boot limpo). Owner de referência: `resources/[CORE]/vhub/server/state.lua`
> (`_requeueCapped`) + `server/vehicle.lua` (`Veh:register` / `vd.anchored`).

## Quando usar
Qualquer fila de escrita SQL com retry (batch do CORE, filas próprias de resources).
E qualquer escrita em tabela FILHA de FK cuja linha-pai é criada por OUTRO resource.

## O acidente que paga esta skill
Carro de admin (`/spawncar`) não tem linha em `vh_vehicles` (âncora criada pelo conce,
dono da identidade). O autosave tentava `REPLACE INTO vh_vehicle_data` → FK falhava →
a op voltava para a fila → falhava de novo → **para sempre** (flood de log + DB a cada
flush de 3s). Uma única placa órfã degradou o servidor inteiro.

## Defesa em DUAS camadas (as duas, sempre — uma só não basta)

### 1. Cap de retry na fila (defesa genérica — vale p/ QUALQUER falha futura)
```lua
local MAX_OP_RETRIES = 5
-- no re-enfileiramento (exceção do driver OU falha parcial):
op._retries = (op._retries or 0) + 1
if op._retries > MAX_OP_RETRIES then
  Logger:error('state', ('op DESCARTADA após %d tentativas: %s'):format(MAX_OP_RETRIES, op[1]))
else
  fila[#fila+1] = op
end
```
- Descarte LOGA com ERROR (perda de dado é visível, nunca silenciosa).
- Campo `_retries` vive na op da fila (nunca é serializado — só o driver lê `op[1]/op[2]`).
- Preservar a ordem: falhas re-enfileiradas ANTES das pendências novas.

### 2. Não gerar a op envenenada (defesa específica de FK)
No registro da entidade, detectar se a âncora existe (1 SELECT que geralmente já existe
no fluxo) e marcar o registro como **EFÊMERO** quando não existe:
```lua
vd.anchored = (r and #r > 0) and true or false   -- r = SELECT na tabela-pai
-- no save: efêmero vive na VRAM + State Bags, mas NUNCA vai ao SQL
if not vd.anchored then vd.dirty = false; return end
```
- O resource dono da FK-filha **NÃO cria a linha-pai** — o escritor da identidade é outro
  (L-04). Criar "só pra passar a FK" = segundo escritor = a próxima dor de cabeça.
- Débito conhecido: entidade que ganha âncora DEPOIS do registro fica efêmera até
  re-registro. Aceitável para carros de teste; revisar se virar fluxo de produção.

## Regras de ouro
1. Fila com retry SEM cap = incidente esperando gatilho. Cap primeiro, causa depois.
2. FK filha escrita por resource ≠ dono da pai → SEMPRE checar âncora antes de enfileirar.
3. Efêmero ≠ quebrado: a entidade funciona 100% em runtime (VRAM/bags); só não persiste.

## Checklist de runtime
`/spawncar` + dirigir → log mostra `registro EFÊMERO (VRAM-only)` em DEBUG e ZERO erro de
FK. Forçar uma op inválida → exatamente 5 tentativas e 1 ERROR de descarte, fila segue viva.
