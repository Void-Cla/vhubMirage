# vHub Mirage — Protocolo de Agentes v2.0

> Leis, Registro de Ownership, Orçamentos e Condições de Parada vivem em `CLAUDE.md` (fonte única). Este arquivo define **como os agentes operam**. Duplicar lei aqui = drift; referenciar, não copiar.

## Leitura obrigatória (nesta ordem)

```
CLAUDE.md                      ← leis L-01..L-12 + estendidas (L-19 vec3/vec4), Registro de Ownership, orçamentos
.claude/contexto.md            ← SOMENTE índice + seções citadas pela tarefa (cap 20 KB)
arquivos reais tocados         ← código > qualquer documento
```

Hierarquia de verdade: **1) código/manifests atuais → 2) CLAUDE.md → 3) contexto.md → 4) metas/**. Divergência doc×código: prevalece o código; registrar risco ativo.

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
