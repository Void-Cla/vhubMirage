# Skill — Reconciliação de plano/prompt externo com a arquitetura real

> Padrão validado em 2026-07-03 (veredito `vhub_arquiteto`). Aplicado aos docs
> `PLANO_IMPLEMENTACAO_VEICULOS.md` e `PROMPT_VHUBMIRAGE_CORE_AAA.md`.

## Quando usar
Um documento de planejamento/prompt entrou no repo (importado de fora — "Manus AI",
prompt genérico de IA, rascunho de terceiro) e diverge da arquitetura real do vHub:
SQL errado, tabela inexistente, ownership trocado, leis citadas com número/semântica
errada, paths com typo, cláusula de autonomia sem gates.

## Regra de ouro
**Não reescreva o doc externo para "salvá-lo".** Se a intenção legítima já vive — melhor
articulada — num doc canônico (`CLAUDE.md`, `frozen_core_2.md`, `WORKLOG_CORE_V2.md`,
`AGENTS.md`, skills), reescrever cria **2ª fonte de verdade em nível meta** (viola L-04/R4
no plano de planejamento). Arquive com nota `SUPERSEDED` apontando para a fonte canônica.

## Árvore de decisão (por doc)
1. **É o doc canônico / reconciliado com o código?** (referências com localização real,
   ADRs numeradas, doc-drift registrado) → **MANTER**. Só ajuste de consistência
   (numeração, cross-ref). Nunca reescrever auditoria — perde rastreabilidade.
2. **A intenção já existe canônica em outro doc?** → **SUPERSEDED com nota** apontando
   para lá. Preserva pedigree ("de onde veio a ideia") sem duplicar verdade.
3. **A intenção é legítima e NÃO existe em lugar nenhum?** → aí sim reconciliar/reescrever,
   mas com placement/ownership corretos e passando pelos gates (arquiteto + guardiões).
4. **Não tem valor histórico nem intenção aproveitável?** → deletar (L-15, "deletar é
   entrega"). Só depois de confirmar que nada canônico depende dele.

## Anatomia do bloco SUPERSEDED
```
# SUPERSEDED — <data>
> <por que arquivado, 1 linha> Não usar como fonte operacional; pedigree histórico.

## Por que foi arquivado (drift confirmado contra o código)
- <cada divergência com a lei/regra que viola: L-04, R10, P4, ...>

## Onde a intenção legítima continua viva
- <doc canônico §seção> (numeração final: confirmar no WORKLOG)
```

## Checklist de drift comum (FiveM/vHub)
- `MySQL.Async.*` no exemplo → projeto usa `exports.oxmysql`.
- Tabela/coluna citada não existe → cruzar com `sql.lua`/`vstate.lua` reais.
- Verdade veicular fora de `vhub_vehicle_state` (conce) → doutrina da placa; derivado
  nunca persiste.
- Módulo novo em resource errado → checar escritor único (L-04/R4) antes do placement.
- `print()` colorido, `onResourceStart → SELECT` full-table → viola R10/P4.
- "Autonomia sem pedir permissão para nada" → o modelo real é **autonomia COM gates**
  (CLAUDE.md 2026-06-27): arquiteto + guardiões + condições de parada obrigatória.

## Governança
Housekeeping puramente documental (sem código Lua/JS tocado) **não precisa** de
segurança/natives/performance/runtime/designer — só `vhub_arquiteto` (veredito de
ownership/placement) + `vhub_guardiao_revisao` (gate final + `contexto.md`). Invocar
guardiões que não tocam o risco = queima de tokens.
