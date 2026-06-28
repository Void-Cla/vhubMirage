# GOVERNANÇA v2 — Delta de Implantação

> Por que existe cada mudança: a auditoria provou que as leis certas já existiam e foram violadas **citando-as em comentário**. A v2 não adiciona prosa — adiciona **enforcement mecânico** dos padrões exatos que furaram o projeto.

## 1. Mapa de substituição (sobrescrever no repo)

| Arquivo entregue | Destino | O que muda e por quê (evidência) |
|---|---|---|
| `CLAUDE.md` | `/CLAUDE.md` | +L-13..L-18 com **detector declarado por lei**; **Registro de Ownership** (tabela-lei, preenchida com o estado real pós-auditoria); Política de Código Morto; **Orçamentos** numéricos (L-18); **Doutrina de Escala honesta** (teto OneSync 2048; além = multi-instância sobre o KV do CORE — nada de números de marketing); Definition of Done; cap de 20 KB no contexto. L-08 recalibrada para a realidade do codebase (lei morta-letra corrói as vivas) |
| `.claude/AGENTS.md` | idem | Deduplicação (leis vivem só no CLAUDE.md — drift entre os dois era inevitável); formato ÚNICO de veredito; orçamento de tokens por chamada (diff ≤ 400 linhas, índice do contexto, nunca histórico); tabela "padrões históricos × quem detecta" |
| `.claude/settings.json` | idem | **Fecha brecha real**: o deny antigo cobria só `Write` — `Edit`/`MultiEdit` editavam o CORE FROZEN e o `contexto.md` livremente. Hook PostToolUse agora cobre `Write\|Edit\|MultiEdit`. +denies SQL (`vh_vehicle*`, `vhub_vehicles`) |
| `.claude/hooks/post_lua_check.sh` | idem | v2 com **bloqueio** (exit 2): L-13 `set*Data` fora do CORE, L-15 órfão-do-manifest (resolve globs) e módulo-fantasma, `os.exit`/HTTP vendor; **avisos**: L-14 getVHub, L-16 spawn fora do owner (allowlist), L-17 sem replay-guard, L-06 por-bloco (12 linhas), L-10/print. Testado contra 4 fixtures (violador, órfão, fantasma, limpo) |
| `.claude/hooks/guard_sql_danger.sh` | idem | +`DELETE FROM vh_vehicle_data/vhub_vehicles`, `ALTER TABLE vh_`, `DROP COLUMN`, `git clean -f`, `rm -rf resources/.claude` |
| `.claude/agents/vhub_arquiteto.md` | idem | Gate passa a exigir **LINHA_REGISTRO** pronta antes de código; reprova suposição "todos os players neste processo" |
| `.claude/agents/vhub_guardiao_persistencia.md` | **NOVO** | O pior incidente do projeto foi de persistência (bind `@dkey` matou `vh_vehicle_data` desde o freeze + 8 escritores externos) e nenhum agente era dono disso. Checa bind prepared×caller, round-trip, janela de staleness do batch (3 s), FK âncora, merge-sobre-defaults, grep de fechamento |
| `.claude/agents/vhub_guardiao_revisao.md` | idem | Checklist = Definition of Done; **violação agravada** (comentário citando lei violada — caso real "L-04" nos 8 call-sites); aplica o cap/estrutura do contexto |
| `.claude/agents/vhub_guardiao_seguranca.md` | idem | Vetores reais primeiro: claim de entidade sem vínculo placa↔netId (estilo `vEnter`), mutação via `getVHub`, replay em massa, vendor `os.exit`/HTTP. Derruba a desculpa "native nil server-side" (o próprio CORE usa as natives no servidor) |
| `.claude/agents/vhub_guardiao_performance.md` | idem | Orçamentos como contrato; custo/player O(1); `TriggerClientEvent(-1)` p/ estado de entidade → State Bag; `GetPlayers()` p/ domínio exige justificativa |
| `.claude/agents/vhub_guardiao_natives.md` | idem | Seção "Fatos de plataforma" anti-desinformação; reforça L-16 |
| `.claude/agents/vhub_guardiao_contrato.md` | idem | Contratos de commit = única porta de escrita; **protocolo de descontinuação** (grep de emissores+listeners anexado — os eventos mortos do selector teriam sido pegos aqui) |
| `.claude/agents/vhub_guardiao_simplicidade.md` | idem | Poder de bloqueio em L-15; "deletar é entrega"; placeholder/vendor banidos |

**Inalterados (não regenerados de propósito — minimalismo):** `vhub_designer.md`, `vhub_guardiao_designer.md`, `vhub_guardiao_runtime.md`, `settings.local.json`, `.claude/memory/`.

## 2. Tarefa manual obrigatória: reestruturar `contexto.md` (74 KB → ≤ 20 KB)

O arquivo é memória institucional (escritor: `vhub_guardiao_revisao`) — não foi reescrito automaticamente. Procedimento:

```
1. mkdir .claude/contexto_arquivo
2. mover histórico/raciocínios longos → .claude/contexto_arquivo/2026-06.md
3. reescrever contexto.md no esqueleto fixo:
   ## ÍNDICE
   ## Ownership            ← espelho da tabela do CLAUDE.md (link, não cópia)
   ## Contratos congelados ← exports/eventos públicos + contratos de commit
   ## Riscos ativos        ← itens A8 da auditoria (getVHub, vEnter sem vínculo, lifecycle dependente do vehcontrol)
   ## Decisões             ← 1 linha por decisão, com data
   ## Sprints              ← status atual
4. validar: wc -c .claude/contexto.md  ≤ 20480
```

Motivo: 74 KB lidos "sempre primeiro" por todo agente = o maior custo de token recorrente do projeto e diluição de sinal.

## 3. Ordem de ativação

```
[ ] backup: cp -r .claude .claude_backup_v1 && cp CLAUDE.md CLAUDE.md.v1
[ ] sobrescrever os 13 arquivos do mapa acima
[ ] chmod +x .claude/hooks/*.sh
[ ] reestruturar contexto.md (seção 2)
[ ] sessão nova do Claude Code (recarrega settings/hooks)
[ ] smoke do enforcement:
    1. pedir ao agente para gravar um .lua com setVData num script → hook BLOQUEIA citando L-13
    2. pedir um .lua novo sem referenciar no fxmanifest → hook BLOQUEIA L-15
    3. tentar Edit em resources/[CORE]/vhub/server/state.lua → deny do settings
    4. gravar arquivo no template oficial (vHub.X = M ... return M) → passa limpo (exit 0)
[ ] rollback: restaurar .claude_backup_v1 + CLAUDE.md.v1
```

## 4. Interação com o plano técnico (IMPLEMENTACAO.md já entregue)

- A v2 **pressiona na direção certa antes mesmo da IT.2**: qualquer edição nos 8 call-sites legados de `setVData` será bloqueada pelo hook, forçando a migração para `commitVehicleState` (PARTE D) naquele arquivo.
- IT.1 (Spawn) já entregue é o estado que L-16 protege; IT.6 (round-trip) é o teste que `vhub_guardiao_persistencia` passa a exigir.
- Pós-IT.2 com grep de fechamento zerado: promover L-14 de aviso para **bloqueio** (1 linha no hook: mover o ramo `add_warn` do getVHub para `add_issue`) e então remover o export `getVHub` do CORE (A8.1).
