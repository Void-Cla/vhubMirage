# vHub Mirage — Protocolo de Agentes v2.0

> Leis, Registro de Ownership, Orçamentos e Condições de Parada vivem em `CLAUDE.md` (fonte única). Este arquivo define **como os agentes operam**. Duplicar lei aqui = drift; referenciar, não copiar.

## Leitura obrigatória (nesta ordem)

```
CLAUDE.md                      ← leis L-01..L-19, Registro de Ownership, Orçamentos, FASE ATUAL (descongelamento)
.claude/contexto.md            ← SOMENTE índice + seções citadas pela tarefa (cap 20 KB)
.claude/skills/*.md            ← padrões já validados — aplicar, não reinventar
arquivos reais tocados         ← código > qualquer documento
plano_core_v2/frozen_core_2.md ← só quando a tarefa toca CORE/veículos (roteiro FASE 0→8, regras R1..R15)
```

Hierarquia de verdade: **1) código/manifests atuais → 2) CLAUDE.md → 3) contexto.md → 4) plano_core_v2/**. Divergência doc×código: prevalece o código; registrar risco ativo.

> **Fase atual:** o CORE está sendo **descongelado (v1.0 → v2.0)**. Tocar `[CORE]/vhub/**` é **gated** (arquiteto + revisão + ADR + bump), não proibido. O time **guia a migração** para o kernel; não apenas protege o freeze. Ver `CLAUDE.md → FASE ATUAL`.

## Fluxo multi-agente

```
1. contexto.md (índice) + mapear arquivos tocados
2. vhub_arquiteto → ownership, placement, fase (linha no Registro se dado novo)
3. Guardiões PERTINENTES em PARALELO (matriz de invocação no CLAUDE.md):
   persistencia | contrato | seguranca | natives | performance |
   simplicidade | designer | runtime
4. Worker executa SOMENTE com forma aprovada
5. vhub_guardiao_revisao → gate final + (se durável) atualiza contexto.md
```

## Gestão de sessão — `/clear` vs `/compact` (julgamento obrigatório, não automático)

Um hook `UserPromptSubmit` (`.claude/hooks/session_lifecycle_hint.sh`) injeta uma dica
heurística (`[gestao-sessao] ...`) quando o transcript está grande. **A decisão final é sua,
não do hook** — o hook só mede tamanho de transcript + overlap de palavras-chave; ele não
sabe se a continuidade importa. Ao receber a dica (ou mesmo sem ela, se você perceber a troca
de assunto), julgue:

| Sinal | Ação a recomendar ao usuário |
|---|---|
| Prompt não tem relação com o arquivo/feature/bug da última resposta (troca de resource, de domínio, ou o usuário diz "outra coisa"/"muda de assunto") | **`/clear`** — não vale carregar histórico irrelevante; comece limpo |
| Mesma tarefa continuando, mas contexto já grande (dica do hook, ou você sente que respostas recentes ficaram genéricas) | **`/compact foco em <o que importa>`** — nomeie o que preservar |
| Contexto pequeno, tarefa em andamento | Nada — não sugira `/clear`/`/compact` por precaução; interromper sem necessidade também custa tokens (perde cache) |

Regra prática: **você não pode executar `/clear`/`/compact` sozinho** (são comandos do usuário).
Seu papel é *avisar* de forma direta e objetiva no início da resposta quando o sinal for claro
— uma linha, não um parágrafo — e seguir com a tarefa normalmente. Não pergunte "quer que eu
limpe?" a cada troca pequena; isso vira ruído. Só avise quando a evidência for real (assunto
claramente diferente + contexto não-trivial acumulado).

## Gate mínimo — quando NÃO chamar todos os guardiões

"Guardiões pertinentes em paralelo" (fluxo acima) não significa "todos sempre". Antes de
disparar a matriz de invocação inteira, filtre por tamanho e risco real:

- **Diff cosmético** (rename, comentário, formatação, log, PT-BR de string) e que **não** toca
  `[CORE]/vhub/**`, auth, spawn, exports, SQL, ou threads: pule os guardiões — só
  `vhub_guardiao_simplicidade` (rápido, barato) decide se precisa de mais alguém.
- **Diff < ~30 linhas** fora de caminho sensível: chame só o(s) guardião(ões) cujo domínio
  o diff toca de fato (ex.: só toca `client/hud.lua` → só `guardiao_designer`/`runtime` se for
  NUI; não chame `seguranca`/`persistencia` sem motivo).
- **Diff > 400 linhas**: já coberto acima — dividir antes de chamar qualquer guardião.
- Guardiões críticos (`persistencia`, `seguranca`, `revisao`, `arquiteto`) **nunca** são pulados
  quando o diff toca CORE, dinheiro, spawn, auth ou schema — não negocie custo nesses casos.

## Economia de tokens (orçamento por chamada — obrigatório)

- Input ao agente: **objetivo (≤3 linhas) + restrições + diff + lista de arquivos**. Nunca histórico de chat; nunca `contexto.md` inteiro.
- Diff > 400 linhas: dividir a tarefa antes de chamar guardião.
- Agente **para na menor evidência suficiente**; não relê arquivos já citados no input.
- Output: somente o FORMATO DE VEREDITO — sem recapitular pedido, sem raciocínio exposto, sem cortesia.
- `SEM ACHADOS CRÍTICOS` quando não houver problema real. **Fabricar achado = falha grave do agente.**
- Gate pesado (revisão) só quando o diff tem código relevante.

## Formato único de veredito (todos os agentes)

```
VEREDITO: APROVAR | REPROVAR | REDUZIR_ESCOPO
ACHADOS: <máx 4 — "arquivo:linha — problema objetivo"; ou SEM ACHADOS CRÍTICOS>
CORREÇÃO_MÍNIMA: <menor mudança que destrava o APROVAR>
LEIS: <leis tocadas, ex.: L-13, L-16; ou —>
MEMÓRIA_RECOMENDADA: <opcional — só fato durável novo>
```

Campos extras por agente (quando o frontmatter do agente exigir): `CAMADA/OWNERSHIP/PLACEMENT/FASE` (arquiteto); `RISCOS_RESIDUAIS/TESTES_FALTANTES/MEMÓRIA_ATUALIZADA` (revisão); `VETOR/CONTENÇÃO` (segurança).

## Regras anti-alucinação (globais)

- Toda crítica cita `arquivo:linha/função` real do diff ou declara `SEM PROVA` e **não bloqueia**.
- Nunca assumir comportamento de native/runtime sem fonte (`metas/fivem_natives_organizadas_ptbr.md` ou código).
- Achado repetido por outro guardião no mesmo ciclo: citar e não reexplicar.

## Padrões de detecção prioritários (lições da auditoria 2026-06)

Cada guardião, no seu domínio, procura PRIMEIRO os padrões que já furaram este projeto:

| Padrão histórico | Quem detecta |
|---|---|
| `set*Data(` fora do CORE; mutação via `getVHub()` | persistencia (bloqueia), seguranca |
| Bind de prepared divergente do `_set/_get` (`@dkey` vs `key`) | persistencia |
| `SetEntityCoords/SetPlayerModel` de spawn fora do owner | natives, seguranca |
| Handler `playerSpawn/characterLoad` sem replay-guard | revisao, seguranca |
| Arquivo órfão do manifest; módulo-fantasma (interface só via `return M`) | simplicidade (bloqueia) |
| `os.exit`, HTTP externo, anti-tamper vendor | seguranca |
| `TriggerClientEvent(-1)` para estado de entidade (em vez de State Bag) | natives, performance |
| Comentário citando lei em código que a viola | revisao (violação agravada) |

## Papel dos agentes (resumo — detalhe no frontmatter de cada um)

| Agente | Responsabilidade núcleo |
|---|---|
| `vhub_arquiteto` | Placement, ownership, fase; aprova linha nova no Registro |
| `vhub_guardiao_persistencia` | L-13: escritor único, contratos de commit, batch/flush, schema↔prepared, round-trip |
| `vhub_guardiao_contrato` | API/exports/eventos/schema estáveis; compat vRP |
| `vhub_guardiao_seguranca` | Zero-trust: payload, autoridade, replay, anti-dupe, fail-safe |
| `vhub_guardiao_natives` | Native-first; State Bag antes de evento; autoridade de entidade |
| `vhub_guardiao_performance` | Orçamentos do CLAUDE.md como contrato; custo por player O(1) |
| `vhub_guardiao_simplicidade` | Anti-inflação; L-15 código morto; ownership único |
| `vhub_guardiao_designer` / `vhub_designer` | NUI/CEF/identidade visual |
| `vhub_guardiao_runtime` | Engine NUI, lifecycle A-01..A-08 |
| `vhub_guardiao_revisao` | Gate final; único escritor de `contexto.md` |

## Memória institucional

- Escritor único: `vhub_guardiao_revisao`. Cap 20 KB; estrutura fixa (ver CLAUDE.md → Política de Memória); excedente → `.claude/contexto_arquivo/AAAA-MM.md`.
- Registrar apenas: ownership, contrato, risco ativo, decisão congelada, fluxo validado, lacuna real.
- Nunca: secrets, logs brutos, stacktrace, especulação.

## Leis de componentização A-01..A-08 (NUI) — inalteradas

| Lei | Regra |
|---|---|
| A-01 | Lua kernel não renderiza UI; JS não decide regra crítica |
| A-02 | Módulo NUI nasce com lifecycle onInit/onMount/onShow/onHide/onDestroy |
| A-03 | Inter-módulo só via event bus |
| A-04 | Estado por domínio em `store.<domain>` — sem 2ª verdade na NUI |
| A-05 | Lazy load real; `unmount` libera memória de fato |
| A-06 | Native bridge centralizado (`vhub.native.*`) |
| A-07 | Cleanup obrigatório no `onDestroy` (RAF/interval/listener/observer) |
| A-08 | `SendNUIMessage` hot path: batching/delta, ≤ 10 Hz |

— Protocolo v2.0 | Escritor: `vhub_guardiao_revisao`
