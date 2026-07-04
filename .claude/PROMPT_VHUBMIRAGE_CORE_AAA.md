# SUPERSEDED — 2026-07-03

> Este prompt foi um **rascunho externo** de engenharia. O conteúdo válido já migrou para as
> fontes canônicas do projeto. Não usar como fonte operacional — mantido só como pedigree.

## Onde o conteúdo válido vive agora

- `CLAUDE.md` → leis **L-01..L-19**, componentização **A-01..A-10**, Orçamentos, Fase Atual,
  camadas L1..L4 (kernel/HAL/runtime/componente), autonomia-com-gates.
- `.claude/plano_core_v2/frozen_core_2.md` → regras de ouro **R1..R15**, performance **P1..P6**,
  arquitetura **A1..A5**, auditoria **F-001..F-079**. Cobre VRAM/MS, anti-limbo veicular,
  single-pilot-channel, lazy-load.
- `.claude/plano_core_v2/WORKLOG_CORE_V2.md` → ADRs **#37..#50** aplicadas (próximo livre #51).
- `.claude/AGENTS.md` → protocolo dos agentes, gates, formato de veredito, economia de tokens.

## Divergências resolvidas contra a arquitetura real

- **Autonomia é COM gates de agente**, não sem eles. O modelo real (CLAUDE.md 2026-06-27) é
  *"Autonomia ≠ pular governança — continue rodando os gates (arquiteto + guardiões + revisão) e
  as condições de parada obrigatória"*. Este prompt propunha autonomia irrevogável sem gates —
  não reconciliável, filosofia diferente.
- **Numeração de leis** segue a fonte única do `CLAUDE.md` (o prompt citava L-09/L-18/L-19 com
  semântica trocada).
- **Paths corrigidos:** o prompt usava `vhubMirage.claude/plano_core_v2/...` (sem barra); o
  correto é `.claude/plano_core_v2/...`.
- **Referências ao `PLANO_IMPLEMENTACAO_VEICULOS.md`** estão SUPERSEDED (ver aquele arquivo).
- **Handle "Fable5":** no WORKLOG real é o executor de um sprint específico, não um papel de
  arquiteto-chefe irrevogável. Governança real = sistema multi-agente do `CLAUDE.md`.

Arquivo mantido apenas como pedigree histórico — a operação segue pelas fontes canônicas acima.
