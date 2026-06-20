# vHub Handling Balancer

Pipeline **offline** de balanceamento de `handling.meta` de veículos mod (add-on) do vHub Mirage.

Padroniza, de forma **determinística e auditável**, o núcleo de performance de cada carro para
o padrão do seu Tier (D → S+), preservando toda a identidade do veículo. Roda **fora do servidor**
(pré-deploy / gate de CI) — o FXServer apenas lê os `.meta` já balanceados no boot, com **zero**
impacto em `resmon` (alinhado a L-05/L-06).

> **Especificação completa:** [`script.md`](./script.md) (Handling Balancer v2.0) e
> [`../../resources/[CAR]/carskill.md`](../../resources/[CAR]/carskill.md) (P1 Skill v2.2).
> Este README é o **guia operacional**; as duas specs são a fonte de design.

---

## O que esta Fase 1 entrega

- **Interface web** (`node balance.js serve`) intuitiva e explicativa — decisões na mão do
  humano, execução automática. Ver [Interface web](#interface-web-recomendada).
- **Renomear o veículo** em TODOS os arquivos do mod (metas + assets `.yft/.ytd`) — mods vêm
  com nomes aleatórios; o app troca o nome de spawn com segurança (preview + backup).
- **Decisão de tier**: o app **calcula** o tier pela física atual; você indica o **desejado**;
  a **média** (ou sua escolha) define o final — sem perder o balanceamento.
- **Reescrita CIRÚRGICA** dos `.meta`: troca apenas o `value="..."` dos **8 campos de performance**
  (NÚCLEO-8), deixando o resto do arquivo **byte-a-byte idêntico**. Sem `xml2js`, sem round-trip de XML.
- **Backup automático** antes de qualquer escrita, **selo sha256** com detecção de drift, e um
  **`catalog-patch.json`** pronto para mesclar no catálogo do `vhub_conce` na Fase 2.
- **Zero dependência de runtime** (só `fs`/`path`/`crypto`/`http` nativos do Node).

---

## Interface web (recomendada)

```bash
cd tools/handling-balancer
node balance.js serve          # ou: npm run serve  (porta 7920 por padrão; --port para mudar)
```

Abra **http://127.0.0.1:7920** no navegador. Tudo é local (127.0.0.1), offline, sem dependências.

Cada carro vira um **card** com três blocos de decisão:

1. **Renomear** — esses mods vêm com nomes aleatórios (`a80`, etc.). Digite o novo nome,
   clique em *Pré-visualizar* (mostra cada arquivo e cada linha que muda + quantos assets
   serão renomeados) e confirme. O app troca o token do modelo em **todos os `.meta`**
   (modelName, txdName, handlingId, gameName, handlingName, refs de modkit/layout/driveby) e
   **renomeia os arquivos** `.yft/.ytd`. Backup automático antes de tocar qualquer arquivo.

2. **Análise** — o app **calcula** o tier natural do carro pela física atual (score 0–1000),
   com barras explicativas por dimensão (aceleração, largada, curva, frenagem, estabilidade)
   e power-to-weight. É o "tier que o carro É hoje".

3. **Decisão de tier** — você vê *Calculado* vs. *Desejado* (dropdown) e escolhe como decidir:
   - **Calculado**: usa o que o app estimou.
   - **Média** (padrão): meio-termo entre calculado e desejado — **nunca** teleporta um carro
     fraco para o topo; mantém o balanceamento.
   - **Meu desejado**: usa exatamente o tier que você quer.
   A **prévia do balanceamento** (8 campos, antes → depois) atualiza ao vivo. *Aplicar* grava
   com backup + selo + `catalog-patch.json`, persistindo o tier escolhido em `registry.json`.

> A UI é apenas um editor amigável do `registry.json` + um disparador do `apply`. CLI e UI
> compartilham a mesma fonte de verdade — o que você decide na tela vale para a linha de comando.

### Áudio de veículos com som próprio

Alguns mods vêm com **som customizado** (arquivos `.awc` + `.dat151.rel`/`.dat54.rel`). Esse áudio
tem uma **identidade separada do modelo**: o nome com que o som foi *compilado* (ex.: `ta488f154`),
gravado no **binário** e no `<audioNameHash>`. Renomear só os arquivos na mão **quebra o som** —
foi o que aconteceu com o FERRARIF8 (arquivos viraram `FERRARIF8_*`, mas o binário, o `fxmanifest`
e o `audioNameHash` continuavam `ta488f154` → o FiveM não achava os bancos de som).

O card de cada carro com som próprio mostra um painel **Áudio**:
- **✓ OK** — a identidade do áudio está consistente.
- **⚠ precisa de conserto** — lista o que está fora do lugar e oferece **Consertar áudio**: o app
  descobre o nome **verdadeiro** do som (lendo o banco referenciado no `.dat54` binário) e
  **alinha** os nomes dos arquivos `.awc/.rel` + o `fxmanifest` + o `audioNameHash` a esse nome.
  Backup automático; nenhum byte do binário é alterado.

> **Limite honesto:** o nome interno do som está *baked* no binário (hash joaat). O app faz o som
> **voltar a tocar** alinhando tudo ao nome real — mas **não** troca esse nome interno por um
> bonito (ex.: deixar o áudio com o nome do carro). Isso exigiria **recompilar** o áudio
> (CodeWalker/Sollumz), fora do escopo desta ferramenta. O nome interno é invisível em jogo.
>
> Por isso o **rename do modelo** (acima) **nunca** toca os arquivos de áudio — modelo e áudio são
> identidades distintas. O rename só mexe em `.yft/.ytd` (visual/modelo).

### NÚCLEO-8 — os únicos campos que o pipeline escreve

```
fInitialDriveForce       fInitialDragCoeff       fInitialDriveMaxFlatVel   fDriveInertia
fBrakeForce              fTractionCurveMax       fTractionCurveMin         fAntiRollBarForce
```

**NUNCA tocado** (identidade pura — decisão do dono 2026-06-15): lataria/dano
(`fCollisionDamageMult`, `fDeformationDamageMult`, `fWeaponDamageMult`, `fEngineDamageMult`,
`strDamageFlags`), suspensão, `vecCentreOfMassOffset`, `vecInertiaMultiplier`, drivetrain
(`fDriveBiasFront`), marchas, flags, `SubHandlingData`, e todo conteúdo visual (`carcols.meta`,
`carvariations.meta`, `.yft`, `.ytd`, `vehicles.meta`). O `.meta` é a única coisa lida/escrita,
e dentro dele só os 8 campos acima.

> O `script.md` v2.0 §5.3 (injeção de anti-capotamento / 11 campos) está **SUPERADO** pelo
> NÚCLEO-8 do `carskill.md` v2.2 — não reintroduzir os campos extras.

---

## Pré-requisitos

- Node.js ≥ 18 (testado em v24). Nenhuma dependência npm para os comandos da Fase 1.

---

## Uso

```bash
cd tools/handling-balancer

node balance.js serve     # sobe a interface web em http://127.0.0.1:7920 (--port para mudar).
node balance.js scan      # lista handlingNames REAIS, tier, órfãos e duplicatas. NÃO grava.
node balance.js plan      # diff campo-a-campo por carro + preview do catalog-patch. NÃO grava.
node balance.js apply     # backup + reescrita cirúrgica + seal + catalog-patch + build-report.
node balance.js verify    # confere meta == seal (sha256). Exit ≠ 0 em drift. (usado no CI)
node balance.js seal      # re-sela os hashes atuais (após edição manual APROVADA).
node balance.js restore   # restaura do backup mais recente (ou --backup <id>).
```

Ou via npm scripts: `npm run scan | plan | apply | verify | seal | restore`.

### Flags

| Flag | Efeito |
|------|--------|
| `--dry-run` | No `apply`, calcula tudo mas **não grava** (igual ao `plan`). |
| `--only <A80,SKYLINE>` | Processa só os handlingNames listados. |
| `--tier <D..S+>` | Processa só os carros de um tier. |
| `--json` | Saída machine-readable (para CI). |
| `--backup <id>` | No `restore`, escolhe um backup específico (default: o mais recente). |
| `--no-backup --force` | No `apply`, pula o backup (proibido sem `--force`). |

### Exit codes

| Código | Significado |
|--------|-------------|
| `0` | OK |
| `1` | Drift / divergência de selo (`verify`) |
| `2` | Erro de config (mensagem PT-BR aponta o arquivo/campo) |
| `3` | Erro de I/O (arquivo em uso, backup inexistente, etc.) |

---

## Fluxo recomendado

```
1. Coloque o carro mod na árvore de recursos (resources/[SCRIPTS]/carmod/<nome>/...).
2. node balance.js scan            → veja o handlingName REAL do carro.
3. Classifique-o em config/registry.json  (handlingName UPPERCASE → tier_base/tier_max).
4. node balance.js plan            → confira o diff campo-a-campo. Nada é gravado.
5. node balance.js apply           → grava (com backup) + gera selo + catalog-patch + report.
6. node balance.js verify          → confirma que tudo bate com o selo (também roda no CI).
7. Commit. Na Fase 2, mescle out/catalog-patch.json no catálogo do vhub_conce (gate do conce).
```

---

## Configuração (`config/`)

Toda a "inteligência" mora em config versionada — `balance.js` é só o motor.

| Arquivo | Responsabilidade |
|---------|------------------|
| `tiers.json` | A Matriz-Ouro: valores-alvo por tier + `budget` de pontos da Fase 2 + carro nativo de referência. |
| `registry.json` | `handlingName` (UPPERCASE) → `{ tier_base, tier_max }`. Carro fora daqui = **ignorado** + reportado. |
| `overrides.json` | Afinação fina por carro (sobrescreve campos do tier sem sair da banda). |
| `archetypes.json` | Regra `fDriveBiasFront` + `fMass` → arquétipo (`rwd_heavy`…) + `grip_modifier`. |
| `scan-paths.json` | Raízes do glob (`resources/[SCRIPTS]/carmod` etc.), exclusões e nomes de arquivo. |

### `overrides.json` — exemplo

```jsonc
{
  "vehicles": {
    "SUPRA": {
      "fBrakeForce": 0.92,             // este S específico freia um pouco melhor
      "fTractionCurveMin": 2.55,       // sem sair do tier
      "base_alloc": { "potencia":180, "grip":160, "frenagem":160, "aero":160, "suspensao":140 }
    }
  }
}
```

> **Invariante travada:** se `base_alloc` for definido, a **soma deve ser exatamente igual ao
> `budget` do `tier_base`** (D=500, C=600, B=700, A=800, S=900, S+=1000). Caso contrário, o
> comando falha com **exit 2** — isso impede emitir um `catalog-patch` que a Fase 2 rejeitaria.

---

## Artefatos gerados

| Caminho | Versionado? | O que é |
|---------|-------------|---------|
| `.seal/seal.json` | **commitar** | Hash sha256 selado por arquivo. Fonte viva que o `verify` recomputa. |
| `out/catalog-patch.json` | gitignore | Proposta do bloco `p1` por veículo, para mesclar no catálogo na Fase 2. |
| `build-report.json` | gitignore | Relatório por carro (tier, campos alterados antes→depois, warnings, mapa key↔handling_name). |
| `.backups/<timestamp>/` | gitignore | Cópia byte-a-byte dos `.meta` antes de cada `apply`. |

### Contrato do `catalog-patch.json` (ponte para a Fase 2)

```jsonc
{
  "a80": {                              // KEY = modelName minúsculo (casa com a entrada do catalog.lua)
    "handling_name": "a80",             // handlingName REAL do .meta (âncora ao arquivo)
    "tier_base": "A",
    "tier_max": "S",
    "archetype": "rwd_heavy",
    "grip_modifier": 0.92,
    "base_alloc": { "potencia":160, "grip":160, "frenagem":160, "aero":160, "suspensao":160 },
    "drive_bias": 0.0,                  // preservado do .meta (fDriveBiasFront)
    "susp_raise": 0.0,                  // preservado (fSuspensionRaise)
    "mass": 1750.0,                     // preservado (fMass)
    "inertia_z": 1.8,                   // preservado (vecInertiaMultiplier z)
    "low_speed_loss": 1.2,              // preservado (fLowSpeedTractionLossMult)
    "seal": "sha256:..."               // CÓPIA de auditoria do hash do apply (verify só lê seal.json)
  }
}
```

Duas convenções de chave coexistem **de propósito**: o `seal.json` chaveia por `handlingName` real
(integridade do arquivo); o `catalog-patch` chaveia por modelName minúsculo (merge no catálogo,
casa com `catalog[norm(model)]` em runtime, `norm == string.lower`).

---

## Selo + detecção de drift (CI)

O `verify` recomputa o sha256 de cada `.meta` classificado e compara com `.seal/seal.json`.
Qualquer divergência (edição manual, merge errado, carro pirata colado na pasta) → **exit 1**
com o nome do carro. Use num gate de CI / pre-commit:

```bash
node balance.js verify --json   # exit 1 falha o PR se um .meta divergir do tier selado
```

> **Limite honesto:** o selo bloqueia edição **na fonte (repo/deploy)**. Não impede um trainer
> client-side — isso é trabalho do anti-cheat server-side do vHub (defesa complementar).

---

## Arquitetura (separação por responsabilidade)

```
balance.js              entrypoint: parse de args + dispatch + mapeamento de exit code
serve.js                atalho para subir a interface web
lib/
  io.js                 leitura/escrita preservando bytes, glob, backup/restore
  meta.js               split em blocos <Item CHandlingData> + substituição cirúrgica de value=
  util.js               helpers puros (norm, f6, clamp)
  config.js             carrega + VALIDA toda a config (falha cedo, exit 2)
  tiers.js              resolveTargets + ordem/score→tier + reconcile (calc x desejado x média)
  profiler.js           fingerprint + score determinístico + tier CALCULADO (read-only)
  carmod.js             descoberta do mod completo (model token, metas irmãos, assets .yft/.ytd)
  rename.js             rename cirúrgico do token em todos os metas + renomeia assets (preview+backup)
  audio.js              diagnóstico + conserto de áudio custom (.awc/.rel/audioNameHash/fxmanifest)
  seal.js               sha256, read/write seal.json, comparação de drift
  catalogEmitter.js     monta o bloco p1 + grava out/catalog-patch.json
  registryStore.js      persiste decisões de tier no registry.json (fonte única CLI+UI)
  report.js             log PT-BR, render de diff, build-report.json
  engine.js             pipeline compartilhado scan → processar (sem escrita)
  server.js             servidor HTTP local + API JSON da interface web
commands/
  scan.js plan.js apply.js verify.js seal.js restore.js serve.js
config/                 tiers / registry / overrides / archetypes / scan-paths
web/                    index.html · style.css · app.js (interface humana, vanilla JS)
```

**Decisão física-chave:** drive force **NÃO** escala por massa. No GTA5, aceleração ≈
`10 × fInitialDriveForce` e a massa cancela em `a = F/m` (carskill.md §1.5). O alvo de drive force
é o valor do tier (ajustável por override), apenas clampado à banda do tier.

---

## Ownership e lifecycle (L-07)

- **Dono:** equipe de veículos / física.
- **Lifecycle:** roda **pré-deploy** (local + gate de CI). **Nunca** em runtime do servidor.
- **Placement:** `tools/handling-balancer/` (junto dos outros tools de manutenção), **não**
  `[TOOLS]/vhub_testrunner/` (runner Lua server-side) nem um resource FiveM.
- **Não toca** o CORE FROZEN, nenhum resource Lua, nenhum schema SQL. O `catalog-patch.json` é um
  artefato inerte mesclado manualmente na Fase 2 (sob gate do `vhub_conce`).

---

## Roadmap

| Fase | Entrega | Status |
|------|---------|--------|
| **F1 (esta)** | CLI (`scan`/`plan`/`apply`/`verify`/`seal`/`restore`) + selo + catalog-patch + **interface web** (rename em todos os arquivos, tier calculado x desejado x média, prévia ao vivo) | ✅ |
| F2 | Extensão `catalog.p1` no `vhub_conce` (gate do conce); garage exibe `tier_base` | ⏳ |
| Futuro | IA Gemini assistente (nomear arquétipo), leitura de `vehicles.meta` para upgrades/Stage 3 | ⏳ adiado |
```
