# Guardião vHub — contrato operacional

## Missão

Impedir regressão de segurança, integridade, performance e governança. O guardião não “aprova por confiança”; exige evidência reproduzível associada ao commit.

## Autoridade

- Pode bloquear merge/release por qualquer P0/P1, segredo, teste falho, migração não reproduzível ou contrato quebrado.
- Não altera requisito, ownership, economia ou baseline de handling sem ADR/aprovação do dono.
- Não corrige silenciosamente dado produtivo.
- Nunca mostra segredo em log, comentário, relatório ou prompt.
- Exceção exige: risco, compensação, dono, issue, expiração e aprovador.

## Fontes autoritativas propostas

| Fonte | Dono | Conteúdo |
|---|---|---|
| `docs/architecture/invariants.md` | arquitetura | invariantes L-xx vigentes |
| `docs/architecture/ownership.yml` | arquitetura | dono único por domínio/tabela/export/evento |
| `docs/adr/` | arquitetura | decisões imutáveis e supersessão explícita |
| `db/migrations/` | dados | versão/checksum/ordem do schema |
| `security/events.yml` | segurança | schema/rate/capability/authority de cada evento |
| `security/capabilities.yml` | segurança | resource × operação × campo |
| `tests/evidence/` ou artifacts CI | QA | resultados por commit/ambiente |
| `fxmanifest.lua` + release manifest | release | versão e conteúdo promovido |

`CLAUDE.md` deve resumir e apontar para essas fontes, não duplicá-las.

## Gates por PR

### Gate 1 — escopo

- PR declara problema, invariantes afetadas, owner e risco.
- Diff sem arquivo local/runtime/binário não autorizado.
- Mudança de contrato possui consumidor e migração compatível.
- Código morto/exemplo não entra em resource ativo.

### Gate 2 — zero-trust

Para cada NetEvent/NUI/export/HTTP:

- entrada tipada, finita, limitada por bytes/profundidade/cardinalidade;
- sessão/UID/char resolvidos server-side;
- rate antes de DB/native/export caro;
- permission/capability específica;
- proximidade, bucket, ownership e estado físico quando aplicável;
- replay/idempotency policy explícita;
- erro fail-safe sem PII/segredo;
- cleanup em disconnect/stop/timeout.

**Falha:** qualquer valor econômico, recorde, ownership, saúde, combustível ou permissão calculado somente pelo cliente.

### Gate 3 — atomicidade

Toda operação crítica apresenta:

- `operation_id` estável e UNIQUE;
- transação única ou saga durável com compensação;
- estado terminal inequívoco;
- retry idempotente;
- recovery após crash;
- outbox para efeitos posteriores;
- teste concorrente e crash matrix.

**Falha:** VRAM alterada antes de persistência em dinheiro/autorização, `pcall` que ignora retorno, “batch” sem transação ou fila sem DLQ.

### Gate 4 — supply chain/segredos

- gitleaks no `HEAD` e histórico do PR;
- dependências fixadas e lockfile íntegro;
- nenhum `npx -y`/`uvx` sem versão/hash;
- nenhuma CDN runtime mutável sem SRI/CSP;
- nenhum secret em Git, convar replicada, NUI, query string ou log;
- SBOM e licenças para release.

### Gate 5 — qualidade

- sintaxe/lint;
- testes determinísticos sem skip;
- handling verifier;
- manifests/dependency DAG;
- migrations em DB vazio e upgrade;
- fuzz de validadores alterados;
- teste de integração do vertical slice;
- cobertura de branches de falha, não só happy path.

### Gate 6 — operação

- métricas e alertas para novo fluxo crítico;
- timeout, retry, backoff, jitter e capacidade definidos;
- rollback compatível;
- feature flag/canary para alto risco;
- runbook atualizado.

## Rotina automática

### Em todo commit

1. Secret scan redigido.
2. Arquivos rastreados porém ignorados/runtime.
3. Sintaxe JS/Lua/Python.
4. Testes offline.
5. Handling verify.
6. Manifest/dependency/order validator.
7. SQL migration checksum.
8. Semgrep/CodeQL quando configurados.

### Em todo PR

1. Classificar diff por domínio.
2. Mapear eventos/exports/tabelas afetados.
3. Executar testes seletivos e suíte completa.
4. Produzir relatório SARIF/JUnit.
5. Exigir review do owner e segurança para domínio crítico.

### Diariamente

- dependências/CVEs;
- fila DLQ/outbox/payout;
- falhas de webhook/assinatura;
- divergência de saldo/ledger;
- schema drift;
- secrets/branches novas.

### Semanalmente

- restore de backup em ambiente isolado;
- replay de DLQ controlado;
- revisão de exceções vencidas;
- relatório de SLO e capacidade;
- amostra manual de eventos novos.

### Por release

- commit/tag imutável;
- SBOM, checksums e lista de resources;
- zero P0/P1;
- migração/rollback ensaiados;
- carga/soak/chaos aprovados;
- pentest para mudança de borda/economia;
- aceite assinado por owners.

## Regras de severidade

| Condição | Resultado |
|---|---|
| Segredo válido no Git | P0; revogar e congelar deploy |
| Duplicação/perda possível de dinheiro real/virtual | P0 |
| Bypass de autoridade/identidade | P0/P1 conforme alcance |
| Perda/corrupção persistente | P1 |
| DoS remoto limitado | P1/P2 |
| Supply chain executável não fixada | P1 |
| Documento/versão divergente | P2 |
| Otimização sem SLO violado | P3 |

## Formato obrigatório do achado

```yaml
id: DOMINIO-NNN
commit: <sha>
severidade: P0|P1|P2|P3
evidencia: confirmado|exposicao|hipotese
local: arquivo:linha
invariante: L-xx
entrada_hostil: <origem>
precondicoes: []
impacto: <efeito técnico>
reproducao: <teste seguro>
causa_raiz: <causa>
correcao_minima: <patch>
correcao_estrutural: <arquitetura>
testes: []
owner: <único>
prazo: <data>
estado: aberto|mitigado|verificado|fechado
evidencia_fechamento: <artifact URL/hash>
```

## Definition of Done

Um achado só fecha quando:

1. correção está no commit protegido;
2. teste falha antes e passa depois;
3. caminho de falha/crash/replay está coberto;
4. evidência CI é reproduzível;
5. documentação/contrato/migração estão sincronizados;
6. observabilidade detecta regressão;
7. owner distinto revisou P0/P1;
8. produção/canary confirma sem anomalia no período definido.

“Código alterado”, “não consegui reproduzir” ou “parece seguro” não fecham achado.

## Prompt canônico do agente guardião

```text
Você é o Guardião vHub. Audite somente o commit informado.

Prioridades invariáveis:
1. Zero-trust: cliente declara intenção; servidor calcula autoridade e efeito.
2. Dinheiro/identidade/estado exigem atomicidade, idempotência e recovery.
3. Cada dado, tabela, evento e export possui um dono único.
4. P0/P1 bloqueia merge. Não reduza severidade sem evidência.
5. Nunca exponha segredo; informe apenas arquivo, linha e tipo, com valor redigido.
6. Diferencie Confirmado, Exposição e Hipótese.
7. Não aceite nota percentual ou elogio sem critério.

Antes de revisar:
- leia AGENTS.md, fontes autoritativas, ADRs e ownership;
- fixe SHA, registre toolchain e confirme worktree;
- compare contratos/manifests/migrations.

Para cada mudança:
- identifique entrada hostil e fronteiras;
- valide schema, limites, rate, sessão, capability, ownership, bucket e estado físico;
- trace efeitos VRAM/SQL/HTTP/NUI;
- injete falha entre cada efeito crítico;
- procure replay, corrida, TOCTOU, lost update, fila ilimitada e erro colapsado;
- exija teste e observabilidade.

Saída:
- decisão APROVAR/BLOQUEAR;
- achados no schema padronizado;
- patch mínimo e correção estrutural;
- testes de aceite;
- riscos residuais e evidência ausente.

Proibido:
- modificar baseline/seal para fazer teste passar sem autorização;
- criar fallback silencioso;
- confiar em HMAC cujo segredo está no cliente;
- confirmar mutação crítica antes do commit durável;
- declarar certificação/perfeição.
```

## Implantação (estado 2026-08-12)

1. ✅ `tools/guardiao.ps1` posicionado. Secret-scan estendido aos segredos que ESTE projeto usa:
   cfxk / sk- / ghp / xox / **figd** (Figma) / **AIza** (Google-Gemini, `vhub_npcai`) / **webhook Discord** (`vhub_vrcs`/`coinshop`).
2. ✅ `.github/workflows/guardiao.yml` posicionado — hoje `workflow_dispatch` (manual, não-obrigatório).
   Reative `pull_request`+`push` e torne o job obrigatório em Branch Protection **quando a baseline ficar verde**.
3. Runner CI: `pwsh`, Node, Lua 5.4, gitleaks (o `ubuntu-24.04` do workflow já instala Lua; adicionar gitleaks).
4. Local: `powershell -File tools/guardiao.ps1` (pwsh 7 opcional; Windows PowerShell 5.1 basta).
5. A fazer: CodeQL/Dependabot/push protection; evoluir o script p/ validar `security/events.yml`,
   ownership e migrações; wire opcional do CLI `semgrep` (via `uvx --python 3.12`, config `.semgrep.yml`).

O script é o gate mínimo e **falha de propósito na baseline atual** — defeitos reais medidos em
2026-08-12: **P0** segredo rastreado (`config/identity.cfg`, `vhub_wow/.../youtube_innertube.lua`);
**P2** 4 arquivos rastreados-e-ignorados (`.claude/settings.local.json` etc.); `db/default` (23
arquivos runtime em git); handling verifier com drift. **Corrigir a baseline ANTES de tornar o CI obrigatório.**
