# vHub Handling Balancer — Análise Profunda (Task 7)

> **Posição no ecossistema:** Ferramenta Node.js **offline** (CLI + web UI local) que normaliza
> `handling.meta` de veículos add-on por tier (D→S+). Roda **pré-deploy** + **gate de CI**,
> nunca em runtime do FXServer. Gera o `catalog-patch.json` que a Fase 2 mesclará no catálogo do
> `vhub_conce`, alimentando o runtime do `vhub_vehcontrol`.
>
> **Versão analisada:** v1.0.0 (`package.json`) — spec `script.md` v2.0.0; **entrega Fase 1 completa**
> (CLI 7 comandos + web UI + selo sha256 + catalog-patch).
>
> **Localização:** `/home/z/my-project/workspace/SCRIPTS/handling-balancer/`
> (em produção viveria em `tools/handling-balancer/`, segundo README — `REPO_ROOT` resolvido como `../../..`).
>
> **Zero dependências externas**: só `fs` / `path` / `crypto` / `http` nativos. Sem `xml2js`, sem `npm install`.

---

## 1. Visão Geral

### 1.1 O que é

O **handling-balancer** é um pipeline **determinístico e auditável** de balanceamento de `handling.meta`
para o vHub Mirage. Padrões de performance por tier (D→S+) são aplicados como **substituição cirúrgica**
dos 8 campos do **NÚCLEO-8** (decisão do dono 2026-06-15, conforme `carskill.md` v2.2 §3.4 balde B),
preservando todo o resto do arquivo byte-a-byte.

**NÚCLEO-8** (única coisa que o pipeline escreve):
```
fInitialDriveForce       fInitialDragCoeff       fInitialDriveMaxFlatVel   fDriveInertia
fBrakeForce              fTractionCurveMax       fTractionCurveMin         fAntiRollBarForce
```

**NUNCA tocado** (identidade pura): lataria/dano (`fCollisionDamageMult`, `fDeformationDamageMult`,
`fWeaponDamageMult`, `fEngineDamageMult`, `strDamageFlags`), suspensão, `vecCentreOfMassOffset`,
`vecInertiaMultiplier`, drivetrain (`fDriveBiasFront`), marchas (`nInitialDriveGears`), flags,
`SubHandlingData`, todo conteúdo visual (`carcols.meta`, `carvariations.meta`, `.yft`, `.ytd`,
`vehicles.meta`).

> **Divergência spec × código:** o `script.md` §5.3 descreve injeção de anti-capotamento (11 campos,
> incluindo `vecCentreOfMassOffset.z`, `fTractionBiasFront`, `fRollCentreHeight*`,
> `fSuspensionReboundDamp`). O README declara explicitamente que isto está **SUPERADO** pelo
> NÚCLEO-8 do `carskill.md` v2.2. A implementação segue o NÚCLEO-8 (8 campos apenas).

### 1.2 Papel no ecossistema vHub

| Camada | Quem | Quando | Como conversa com o balancer |
|--------|------|--------|------------------------------|
| **Build-time** | handling-balancer (este) | pré-deploy + CI | gera `.meta` balanceados + `catalog-patch.json` |
| **Runtime catálogo** | vhub_conce (Fase 2) | boot do servidor | consome `catalog-patch.json` (merge manual em `catalog.lua`) |
| **Runtime ficha** | vhub_vehcontrol | on-read veículo | lê tier_base/tier_max + base_alloc + grip_modifier do catálogo |
| **Runtime física** | vhub_vehcontrol `client/handling.lua` | F5 on enter vehicle | aplica SetVehicleHandlingFloat por eixo dentro do budget |

O balancer **NÃO toca** no CORE FROZEN, em nenhum resource Lua, em nenhum schema SQL. O `catalog-patch.json`
é um artefato inerte mesclado manualmente na Fase 2 sob gate do `vhub_conce`.

### 1.3 Pipeline

```
scan → plan → apply → seal (pos-edicao manual) → verify (CI) → serve (UI)
                                                    ↓
                                            catalog-patch.json → vhub_conce (Fase 2)
```

Cada etapa:
- **scan** — descobre `handling.meta`, lista `handlingName`s reais, órfãos e duplicatas (read-only)
- **plan** — diff campo-a-campo + preview do `catalog-patch.json` (read-only)
- **apply** — backup + reescrita cirúrgica + selo sha256 + catalog-patch + build-report (único que escreve `.meta`)
- **verify** — recomputa sha256 e compara com `.seal/seal.json` (exit 1 em drift; gate de CI)
- **seal** — re-sela hashes atuais (após edição manual APROVADA)
- **restore** — restaura do backup mais recente (rede de segurança)
- **serve** — sobe web UI em `127.0.0.1:7920`

### 1.4 Conversa com vhub_vehcontrol

O `catalogEmitter.js` monta o bloco `p1` por veículo (12 campos: `handling_name`, `tier_base`, `tier_max`,
`archetype`, `grip_modifier`, `base_alloc{5 eixos}`, `drive_bias`, `susp_raise`, `mass`, `inertia_z`,
`low_speed_loss`, `seal`). Este bloco será mesclado em `vhub_conce/shared/catalog.lua` na Fase 2.
Em runtime, `vhub_vehcontrol` lê esse catálogo para derivar:
- `tier_base`/`tier_max` → clamp do tier exibido na ficha
- `base_alloc` → âncora do budget de pontos do skill (D=500..S+=1000, soma exata)
- `grip_modifier` → ajuste de afinidade por arquétipo
- `archetype` → exibição + regra de jogada (rwd_heavy, awd_light, etc.)

---

## 2. CLI Commands

Entrypoint: `balance.js` (linha 1-128). Parse de args simples, dispatch por tabela `COMMANDS`, mapeamento
de exit codes (0 ok · 1 drift · 2 config · 3 I/O).

### 2.1 `scan`

```js
// commands/scan.js:12
function run(args, cfg) {
  const inv = engine.inventory(cfg);
  const { entries, orphans, duplicates } = engine.process(cfg, inv);
  // ...
  return 0;
}
```

- **Args**: `--json`
- **O que faz**: varre `scan-paths.json` → descobre `handling.meta` → fatia em blocos
  `<Item type="CHandlingData">` → casa com `registry.json` por `handlingName` normalizado
  (UPPERCASE+trim). Lista: carros classificados (com tier_base→tier_max), órfãos (sem tier no registry),
  duplicatas (mesmo `handlingName` em vários arquivos), totais.
- **Saída**: terminal PT-BR (3 seções: CARROS CLASSIFICADOS / ÓRFÃOS / DUPLICATAS / TOTAL) ou JSON.
- **Exemplo (README)**:
  ```bash
  node balance.js scan   # lista handlingNames REAIS, tier, órfãos e duplicatas. NÃO grava.
  ```

### 2.2 `plan`

```js
// commands/plan.js:14
function run(args, cfg) {
  const inv = engine.inventory(cfg);
  const filter = buildFilter(args);
  const { entries, orphans } = engine.process(cfg, inv, filter);
  // ... renderDiff para cada entry + preview do bloco p1
}
```

- **Args**: `--only A80,SKYLINE` (filtra por handlingName) · `--tier A` (filtra por tier_base) · `--json`
- **O que faz**: calcula o diff dos 8 campos NÚCLEO-8 antes→depois por carro, **sem gravar**. Renderiza
  a prévia do bloco `p1` que iria no `catalog-patch.json` (usando hash atual como selo provisório).
- **Saída**: diff legível (campo, valor atual → alvo, warnings) + summary (carros com alteração,
  ignorados, com avisos) + preview JSON do bloco `p1`.
- **Exemplo**:
  ```bash
  node balance.js plan --only SUPRA,SKYLINER34   # diff dos dois carros, sem gravar
  ```

### 2.3 `apply`

```js
// commands/apply.js:29
function run(args, cfg) {
  const inv = engine.inventory(cfg);
  const filter = buildFilter(args);
  const { entries } = engine.process(cfg, inv, filter);
  // 1. groupByFile
  // 2. backup (io.backup) — sem --no-backup --force, falha
  // 3. rebuild cirúrgico por arquivo
  // 4. hash UMA vez por arquivo (seal + patch usam MESMO valor)
  // 5. seal.write(sealMap) + emitter.writePatch(patchByKey) + report.writeBuildReport()
}
```

- **Args**: `--dry-run` (igual ao plan) · `--only` · `--tier` · `--no-backup --force` (pula backup, exige force)
- **O que faz** (fluxo de 5 passos):
  1. Processa (calcula mudanças, sem gravar)
  2. Backup automático de todo `.meta` que vai mudar (`.backups/<timestamp>/`)
  3. Reescrita cirúrgica (`meta.splitBlocks` + troca só `value="..."` dos 8 campos) — grava só se mudou
  4. Hash sha256 calculado UMA vez por arquivo (selo e patch usam o MESMO valor)
  5. Artefatos: `.seal/seal.json` + `out/catalog-patch.json` + `build-report.json`
- **Idempotente**: rodar 2x não muda nada na 2ª vez (alvos são absolutos do tier).
- **Saída**: log PT-BR com backup criado, arquivos gravados, selo atualizado, catalog-patch emitido,
  build-report gravado + summary.
- **Exemplo**:
  ```bash
  node balance.js apply --only SUPRA   # aplica só a SUPRA, com backup + selo + patch
  ```

### 2.4 `verify`

```js
// commands/verify.js:15
function run(args, cfg) {
  const inv = engine.inventory(cfg);
  const { entries } = engine.process(cfg, inv);
  const sealMap = seal.read();
  const checkable = entries.filter((e) => !e.skipped).map((e) => ({ name, file, content }));
  const result = seal.diff(checkable, sealMap);
  // exit 0 if result.ok; exit 1 otherwise
}
```

- **Args**: `--json`
- **O que faz**: recomputa sha256 de cada `.meta` classificado e compara com `.seal/seal.json`.
  Reporta 3 categorias de problema: `drift` (hash diferente), `unsealed` (carro classificado mas nunca selado),
  `missing` (selo órfão — carro sumiu do scan).
- **Saída**: lista de problemas + totalizadores, exit 1 se qualquer problema.
- **Uso no CI** (README): `node balance.js verify --json` — PR que mexe num `handling.meta` sem passar
  pelo pipeline **não mergeia**.

### 2.5 `seal`

```js
// commands/seal.js:14
function run(args, cfg) {
  const inv = engine.inventory(cfg);
  const { entries } = engine.process(cfg, inv);
  const sealMap = {};
  for (const e of entries) {
    if (e.skipped) continue;
    sealMap[e.name] = { tier: e.tier, sha256: seal.hashContent(e.content), file: e.file };
  }
  seal.write(sealMap);
}
```

- **O que faz**: re-sela os hashes do estado atual. Uso: após uma edição manual APROVADA (decisão consciente
  do dono fora do NÚCLEO-8), registra o novo hash como estado válido. Depois disso o `verify` volta a passar.
  **Não reescreve `.meta`** — só atualiza `.seal/seal.json`.

### 2.6 `restore`

```js
// commands/restore.js:18
function run(args) {
  const backups = io.listBackups();
  const id = args.backup || backups[0];   // mais recente
  // ... valida, io.restoreBackup(id) (copia byte-a-byte)
}
```

- **Args**: `--backup <id>` (default: backup mais recente)
- **O que faz**: desfaz um `apply` restaurando os `.meta` exatamente como estavam (copia byte-a-byte
  do `.backups/<id>/`). **Não mexe no selo** — após restaurar, rode `seal` ou `apply` para realinhar
  `.seal/seal.json` com os arquivos restaurados.

### 2.7 `serve`

```js
// commands/serve.js:10
function run(args) {
  const port = args.port ? parseInt(args.port, 10) : 7920;
  server.start(port);
  return { keepAlive: true };   // sinaliza ao entrypoint não chamar process.exit
}
```

- **Args**: `--port <n>` (default: 7920)
- **O que faz**: sobe o servidor HTTP local (bind `127.0.0.1`) que serve a web UI + a API JSON.
- **Exemplo**:
  ```bash
  node balance.js serve --port 8000
  ```

### 2.8 Exit codes (comum a todos)

| Código | Significado |
|--------|-------------|
| `0` | OK |
| `1` | Drift / divergência de selo (`verify`) |
| `2` | Erro de config (`ConfigError` — mensagem PT-BR aponta arquivo/campo) |
| `3` | Erro de I/O (`IoError` — arquivo em uso, backup inexistente, etc.) |

---

## 3. Architecture (lib/*.js)

### 3.1 `engine.js` — motor de balancing (compartilhado scan→processar, sem escrita)

**Funções exportadas**:

```js
function inventory(cfg) → { files: [{ file, abs, content, blocks: [{ handlingName, raw, block }] }],
                            names: { UPPER: [{ file }] } }   // p/ detectar duplicatas
function process(cfg, inv, filter?) → { entries: [...], orphans: [...], duplicates: [...] }
```

**Pipeline interno** (`processBlock` em engine.js:80):
1. Lê `handlingName` cru do bloco (preserva a caixa real para relatório)
2. Casa com `cfg.registry[handlingName]`; sem tier → órfão
3. Lê `fMass`; se inválida (`<=0` ou não-numérico) → `skipped: 'massa-invalida'`
4. `warnIfMassOutOfBand`: se `mass / tiers[tier].massBase` < 0.5 ou > 2.0 → WARN
5. `tiers.resolveTargets(handlingName, cfg)` → 8 alvos + clampInfo (se drive force foi clampado)
6. Para cada campo do NÚCLEO-8: `meta.readValue` (atual) + `meta.setValue` (alvo) → diff `changes[]`
7. `entry.newBlock` = bloco recomposto (pronto para gravação, se `apply` decidir)
8. Warnings: campo ausente no `.meta` (`missing: true`, não injeta), clampInfo, massa fora da banda

**Edge cases tratados**:
- Massa inválida → skip com motivo
- Massa fora da banda (2x ou metade da base do tier) → warn
- Campo-alvo ausente no bloco → warn + `missing: true` (não cria campo novo; ordem do `.meta` importa)
- handlingName ausente → órfão com motivo "sem handlingName"
- Duplicatas (mesmo handlingName em vários arquivos) → lista separada

### 3.2 `io.js` — I/O de arquivos (preserva bytes)

**Constantes**:
- `REPO_ROOT = path.resolve(__dirname, '..', '..', '..')` — assume `tools/handling-balancer/`
- `TOOL_ROOT = path.resolve(__dirname, '..')` — onde vivem `config/`, `out/`, `.seal/`, `.backups/`

**Primitivas**:
```js
readText(absPath)                  // fs.readFileSync(utf8) — preserva BOM, EOL
writeText(absPath, content)        // mkdirSync(recursive) + writeFileSync(utf8)
readJson(absPath)                  // JSON.parse com erro apontando arquivo
writeJson(absPath, obj)            // JSON.stringify(null, 2) + '\n' (indentado, trailing newline)
exists(absPath)                    // fs.existsSync

discover(roots, matchFiles, exclude) → [absPaths]   // glob recursivo case-sensitive por filename
backup(absPaths) → backupId                         // .backups/<YYYYMMDD-HHMMSS>/<rel-path>
listBackups() → [ids]                               // ordenado reverse (mais recente primeiro)
restoreBackup(id) → [restoredAbsPaths]              // copia byte-a-byte de volta ao REPO_ROOT
rel(absPath) → string                               // path relativo ao REPO_ROOT com barras normais
stamp() → "YYYYMMDD-HHMMSS"
```

**Regra de ouro** (script.md §6): NUNCA reserializar o arquivo. Lemos como texto, alteramos só as
substrings-alvo em `meta.js`, gravamos de volta o MESMO texto com apenas essas substrings trocadas.
Sem normalizar BOM, line-endings ou trailing newline.

### 3.3 `meta.js` — parser de handling.meta (substituição cirúrgica)

**Por que não `xml2js`**: o `xml2js` Parser→Builder **reescreve o arquivo inteiro** (reordena atributos,
destrói `<Item type="NULL"/>`, remove comentários, muda formatação). Os 3 `.meta` reais do repo provam
que isso é obrigatório: formatações divergentes (`value="0"`, `value="180.094"`, `value="1.20000"`,
indentação com TAB), sem trailing newline.

**Funções exportadas**:
```js
splitBlocks(content) → [{ text, isHandling }]
// Fatiamento depth-aware: <Item type="CHandlingData"> de TOPO, ignorando <Item> aninhados em SubHandlingData.
// findMatchingClose conta aninhamento (<Item ...> vs </Item> vs <Item .../> self-closing).

readHandlingName(block) → "UPPER" | null
readValue(block, field) → number | NaN     // match <field value="..."/> (parseFloat)
readAttr(block, tag, attr) → number | NaN  // ex.: z de vecInertiaMultiplier
setValue(block, field, num) → { block, changed, missing }
// Regex: /(<field\s+value=")([^"]*)("\s*\/>)/
// Se já está no alvo → changed=false, missing=false (diff limpo)
// Se campo ausente → changed=false, missing=true (não injeta)
// Caso contrário → block.replace(re, `$1${f6(num)}$3`), changed=true
```

`f6(num) = Number(n).toFixed(6)` — padrão da engine GTA5 (6 casas decimais).

### 3.4 `tiers.js` — cálculo de tiers (regras PURAS, sem I/O)

**Decisão física-chave** (carskill.md §1.5): drive force **NÃO** escala por massa. Aceleração ≈
`10 × fInitialDriveForce`; massa cancela em `a = F/m`. Escalar driveForce por massa super-recompensa
carros pesados — foi o bug da v1.0. Por isso o alvo de drive force é o valor do **TIER direto**
(ajustável por override), apenas clampado à banda do tier.

**Funções exportadas**:
```js
resolveTargets(handlingName, cfg, tierKey?) → { targets: {8 campos}, tier, clampInfo }
// tier base do registry → override por campo → clamp drive force a ±15% do tier.drive
// gripMin nunca pode superar gripMax (sanidade física)

FIELDS = ['fInitialDriveForce', 'fInitialDragCoeff', 'fInitialDriveMaxFlatVel', 'fDriveInertia',
          'fBrakeForce', 'fTractionCurveMax', 'fTractionCurveMin', 'fAntiRollBarForce']

ORDER = ['D', 'C', 'B', 'A', 'S', 'S+']

SCORE_BANDS = [
  { tier: 'D',  min: 0,   max: 199 },
  { tier: 'C',  min: 200, max: 399 },
  { tier: 'B',  min: 400, max: 599 },
  { tier: 'A',  min: 600, max: 749 },
  { tier: 'S',  min: 750, max: 899 },
  { tier: 'S+', min: 900, max: 1000 },
]

tierIndex(tier) → 0..5 | -1
scoreToTier(score) → 'D'..'S+'
reconcileTier(calculated, desired, mode) → { final, calcIndex, desiredIndex, finalIndex, mode }
// mode: 'calculado' | 'media' (default) | 'desejado'
// média = Math.round((ci + di) / 2) — NUNCA teleporta um carro fraco para o topo
```

**Algoritmo `resolveTargets`** (tiers.js:33):
```js
const driveRaw = ov.fInitialDriveForce ?? tier.drive;
const drive    = clamp(driveRaw, tier.drive * 0.85, tier.drive * 1.15);   // ±15% da banda

const targets = {
  fInitialDriveForce:      drive,
  fInitialDragCoeff:       ov.fInitialDragCoeff       ?? tier.drag,
  fInitialDriveMaxFlatVel: ov.fInitialDriveMaxFlatVel ?? tier.maxVel,
  fDriveInertia:           ov.fDriveInertia           ?? tier.driveInertia,
  fBrakeForce:             ov.fBrakeForce             ?? tier.brakeForce,
  fTractionCurveMax:       ov.fTractionCurveMax       ?? tier.gripMax,
  fTractionCurveMin:       ov.fTractionCurveMin       ?? tier.gripMin,
  fAntiRollBarForce:       ov.fAntiRollBarForce       ?? tier.antiRollBar,
};
if (targets.fTractionCurveMin > targets.fTractionCurveMax) {
  targets.fTractionCurveMin = targets.fTractionCurveMax;
}
```

### 3.5 `seal.js` — sistema de selo (anti-tampering)

**Algoritmo**: `sha256` do conteúdo UTF-8 do `.meta`, prefixado `'sha256:'` (deixa o algoritmo explícito
no JSON).

```js
hashContent(content) → 'sha256:<64hex>'
hashFile(absPath) → 'sha256:<64hex>'
read() → { UPPER: { tier, sha256, file } }   // lê .seal/seal.json; remove _doc
write(sealMap) → void                         // ordenado por handlingName p/ diff git estável
diff(entries, sealMap) → { ok, drift: [], missing: [], unsealed: [] }
```

**Caminho**: `.seal/seal.json` (commitado).

**Comparação de drift** (seal.js:64):
- Para cada entry: se não tem no selo → `unsealed` (carro classificado mas nunca selado)
- Se hash difere → `drift: { name, file, expected, got }`
- Para cada chave no selo não vista no scan → `missing` (selo órfão — carro sumiu)

> **Limite honesto** (README §"Selo + detecção de drift"): o selo bloqueia edição **na fonte (repo/deploy)**.
> Não impede um trainer client-side — isso é trabalho do anti-cheat server-side do vHub (defesa complementar).

### 3.6 `registryStore.js` — persistência do registry.json

```js
read() → { _doc, vehicles: { UPPER: { tier_base, tier_max } } }
write(reg) → void
setTier(handlingName, tierBase, tierMax) → entry
migrateKey(oldName, newName) → void   // usado pelo rename (UI)
remove(handlingName) → void
```

Caminho: `config/registry.json`. A UI é um editor amigável deste arquivo (fonte única de verdade CLI+UI).

### 3.7 `carmod.js` — descoberta do MOD completo (além do handling.meta)

**Por que existe**: o `handling.meta` sozinho não basta para renomear — o "nome aleatório" do mod (o
`modelName`, nome de spawn) vive em `vehicles.meta` e dá nome aos arquivos `.yft/.ytd`. Este módulo liga
cada bloco de handling ao seu `InitData` em `vehicles.meta` e descobre os metas irmãos + os assets de stream.

**Funções exportadas**:
```js
discoverAll(cfg) → [car]                    // um por bloco <Item CHandlingData>
buildCar(handlingAbs, handlingNameRaw, block, cfg) → car
splitInitDataItems(content) → [items]       // fatia <InitDatas> em itens de TOPO (depth-aware)
assetMatchesToken(basename, token) → bool
```

**Objeto `car` retornado por `buildCar`** (carmod.js:60):
```js
{
  handlingName,                   // normalizado UPPER — chave registry/seal
  handlingNameRaw: "...",
  handlingFile: "rel/path/handling.meta",
  handlingAbs: "/abs/...",
  block,                          // texto do bloco <Item CHandlingData>
  carFolder, carRootAbs,
  dataDir, dataDirAbs,
  metaFiles: { handling, vehicles, carcols, carvariations, vehiclelayouts, contentunlocks, dlctext },
  metaFilesAbs: { ... },          // mesmos paths absolutos
  model: "a80",                   // token de rename = modelName (fallback = handlingName)
  txd: "a80",
  vehicleInfo: { modelName, txdName, handlingId, gameName },
  streamDir, streamDirAbs,
  assets: [{ name, rel, abs }],   // só .yft/.ytd do MODELO (áudio é à parte)
  registry: { tier_base, tier_max } | null,
}
```

**Convenção da árvore**:
- `carmod/<pasta>/common/handling.meta` (dados)
- `carmod/stream/<pasta>/<model>*.yft` (assets nomeados pelo MODELO, não pela pasta)
- A pasta (ex.: "supra") pode diferir do modelo (ex.: "a80") — o token de rename é o MODELO.

**Filtro de assets** (carmod.js:184): `MODEL_ASSET_RE = /\.(yft|ytd)$/i`. Áudio (`.awc`, `.rel`) é
identidade SEPARADA (ver `audio.js`) e **NUNCA** entra no rename do modelo.

### 3.8 `audio.js` — diagnóstico e conserto de áudio custom

**Contexto**: carros com som próprio têm uma IDENTIDADE DE ÁUDIO separada do modelo. Ex.: o FERRARIF8
tem `modelName "ferrarif8"` mas o áudio é `"ta488f154"` (nome com que o som foi compilado). Essa
identidade vive em: `<audioNameHash>` no `vehicles.meta`, dentro dos `.dat151.rel`/`.dat54.rel` binários,
nos nomes dos `.awc`/`.rel`, e nas linhas `data_file`/`files` do `fxmanifest.lua`.

**Por que existe**: o FERRARIF8 teve arquivos renomeados para `FERRARIF8_*`, mas o binário, o `fxmanifest`
e o `audioNameHash` continuavam `ta488f154` → o FiveM não achava os bancos de som. Este módulo alinha tudo
ao nome verdadeiro (que está baked no binário).

**Funções exportadas**:
```js
detect(car) → { custom, status, audioNameHash, canonical, files, fxmanifest, manifestRefs, problems }
previewFix(car) → { applicable, info, canonical, fileRenames, manifestEdits, hashEdit, wrongTokens }
executeFix(car, opts) → { changed, canonical, backupId, renamed, manifestFixed, hashFixed }
```

**Algoritmo do `canonical`** (audio.js:46): lê o banco referenciado no `.dat54` BINÁRIO (busca ASCII
`DLC_<token>...` via `bankTokenFromDat`). Fallback = `audioNameHash` do vehicles.meta.

> **Limite honesto** (README): o nome interno do som está baked no binário (hash joaat). O app faz o som
> **voltar a tocar** alinhando tudo ao nome real — mas **não** troca esse nome interno por um bonito.
> Isso exigiria recompilar o áudio (CodeWalker/Sollumz), fora do escopo.

### 3.9 `catalogEmitter.js` — emite catálogo para vhub_vehcontrol (via vhub_conce Fase 2)

**Ponte Fase 1 → Fase 2**. Gera `out/catalog-patch.json` (ARTEFATO INERTE — mesclagem manual na Fase 2).

**Convenções de chave** (travadas pelo guardião de contrato):
- **Key do patch** = `handlingName` em LOWERCASE (casa 1:1 com a key do catálogo do conce, que é o
  `modelName` minúsculo; runtime usa `catalog[norm(model)]` com `norm == string.lower`).
- **`handling_name`** (dentro do bloco) = `handlingName` REAL do `.meta` (âncora ao arquivo físico).

**Funções exportadas**:
```js
buildEntry(handlingNameRaw, block, cfg, seal) → p1Block
writePatch(entriesByKey) → PATCH_PATH   // chaves ordenadas p/ diff estável
balancedAlloc(budget) → { potencia, grip, frenagem, aero, suspensao }   // soma == budget
deriveArchetype(driveBias, mass, rule) → "rwd_heavy" | "awd_light" | ...
AXES = ['potencia', 'grip', 'frenagem', 'aero', 'suspensao']
PATCH_PATH = '<TOOL_ROOT>/out/catalog-patch.json'
```

**`balancedAlloc`** (catalogEmitter.js:34): distribui o budget igualmente entre os 5 eixos; sobra inteira
vai para `potencia`. Garante por construção `soma(base_alloc) == budget` (trava do contrato F1→F2).

**`deriveArchetype`** (catalogEmitter.js:49):
```js
const heavy = mass >= (r.massThreshold ?? 1500);   // 1500 default
if (driveBias <= 0.2) drive = 'rwd';
else if (driveBias <= 0.8) drive = 'awd';
else drive = 'fwd';
return `${drive}_${heavy ? 'heavy' : 'light'}`;
```

**`buildEntry`** monta o bloco `p1` com 12 campos (carskill.md §4.1 espelhado EXATAMENTE):
```js
{
  handling_name: "f8t",                    // real (NÃO uppercased)
  tier_base: "S",
  tier_max: "S+",
  archetype: "rwd_heavy",
  grip_modifier: 0.92,                     // archMod (config) ou override
  base_alloc: { potencia:180, grip:180, frenagem:180, aero:180, suspensao:180 },  // soma=budget
  drive_bias: 0,                           // preservado do .meta (fDriveBiasFront)
  susp_raise: -0.015,                      // preservado (fSuspensionRaise)
  mass: 1600,                              // preservado (fMass)
  inertia_z: 1.6,                          // preservado (vecInertiaMultiplier z)
  low_speed_loss: 1,                       // preservado (fLowSpeedTractionLossMult)
  seal: "sha256:...",                      // CÓPIA de auditoria do hash do apply
}
```

### 3.10 `config.js` — carregamento + validação de config (falha cedo, falha claro)

```js
class ConfigError extends Error { constructor(msg) { super(msg); this.exitCode = 2; } }

load() → { tiers, registry, overrides, archetypes, archetypeRule, scanPaths }
```

**Validadores**:
- `validateTiers`: cada tier precisa de 10 campos numéricos (`drive`, `drag`, `maxVel`, `driveInertia`,
  `gripMax`, `gripMin`, `brakeForce`, `antiRollBar`, `budget`, `massBase`); `gripMin <= gripMax`
- `validateRegistry`: todo `tier_base` e `tier_max` precisa existir em `tiers.json`; `tier_max` não pode
  ser abaixo de `tier_base` (compara índices na ordem de inserção do JSON)
- `validateOverrides`: toda chave precisa existir no registry; campos limitados a `OVERRIDE_PERF`
  (8 campos NÚCLEO-8) ∪ `OVERRIDE_IDENTITY` (`archetype`, `grip_modifier`, `base_alloc`); se
  `base_alloc` presente, soma deve ser exatamente igual ao `budget` do `tier_base`
- `validateScanPaths`: `roots` e `matchFiles` não-vazios

**Normalização** (`normalizeKeys`): re-chaveia por `norm(k)` (UPPER+trim); ignora chaves começadas com
`_` (documentação).

### 3.11 `profiler.js` — fingerprint + score + tier CALCULADO (read-only)

Lê valores ATUAIS do `.meta` e estima em que tier o carro naturalmente cai. Cruza RELAÇÕES (não soma
campos isolados) conforme `carskill.md §3.6`:
`accel(0.30) · launch(0.10) · grip(0.30) · brake(0.15) · estabilidade(0.15)`

**`analyze(block, tiersMap)`** (profiler.js:35) retorna:
```js
{
  fingerprint: { mass, driveForce, driveBias, gripMax, gripMin, brakeForce, drag, maxVel,
                 driveInertia, antiRoll, suspForce, inertiaZ, gears },
  drivetrain: 'rwd' | 'awd' | 'fwd',
  parts: { accel: 0..1, launch: 0..1, grip: 0..1, brake: 0..1, stability: 0..1 },
  score: 0..1000,
  calculatedTier: 'D'..'S+',
  powerToWeight: number | null,   // driveForce / (mass/1000)
  notes: [...],
}
```

**Algoritmo**:
```js
// dimensões normalizadas 0..1 dentro da banda D..S+
const accel = band(f.driveForce, D.drive, SP.drive);
const grip  = band(f.gripMax,    D.gripMax, SP.gripMax);
const brake = band(f.brakeForce, D.brakeForce, SP.brakeForce);

// largada: torque sem grip patina; AWD agarra, RWD sofre
const dtFactor = drivetrain === 'awd' ? 1.0 : drivetrain === 'rwd' ? 0.85 : 0.92;
const launch = clamp((grip / Math.max(accel, 0.01)) * dtFactor, 0, 1);

// estabilidade: antiRoll (banda) + suspensão (peso real entra aqui, não em accel)
const stability = clamp(
  0.6 * band(f.antiRoll, D.antiRollBar, SP.antiRollBar) +
  0.4 * clamp((f.suspForce || 0) / 3.0, 0, 1), 0, 1);

const score = Math.round(
  (accel * 0.30 + launch * 0.10 + grip * 0.30 + brake * 0.15 + stability * 0.15) * 1000);

// anti-absurdo: power-to-weight baixo derruba tier A+ em 1 nível
if (pwr < 0.12 && tierIndex(calculatedTier) >= tierIndex('A')) {
  calculatedTier = ORDER[max(0, tierIndex(calculatedTier) - 1)];
  notes.push(`power-to-weight baixo (${pwr.toFixed(3)}) — tier reduzido 1 nível (anti-absurdo)`);
}
```

`classifyDrivetrain(driveBias)`: `≤0.2 = rwd`, `≤0.8 = awd`, `>0.8 = fwd` (default awd se NaN).

### 3.12 `report.js` — saída PT-BR + diff + build-report.json

```js
log = { info, ok, warn, erro, head }   // prefixos PT-BR: "   ", "[ ok ]", "[aviso]", "[erro]", "=== ... ==="
renderDiff(entry)                       // terminal: campo, antes → depois, warnings, skip
renderSummary(verb, entries)            // resumo: classificados, gravados/alterados, ignorados, com avisos
writeBuildReport(entries, { backupId }) → REPORT_PATH   // build-report.json
REPORT_PATH = '<TOOL_ROOT>/build-report.json'
```

**Schema do `build-report.json`** (report.js:76):
```js
{
  generatedAt: "ISO timestamp",
  backupId: "...",
  summary: { classified, written, skipped },
  keyMap: [{ catalog_key: "f8t", handling_name: "f8t" }],   // ponte humana Fase 2
  vehicles: [{
    name, handling_name, tier, file, skipped, written,
    changes: [{ field, from, to, changed, missing }],
    warnings: [...],
  }],
}
```

### 3.13 `rename.js` — renomeia veículo em TODOS os arquivos do mod

Troca o token do modelo em todos os `.meta` da pasta de dados (`modelName`, `txdName`, `handlingId`,
`gameName`, `handlingName`, refs de modkit/layout/driveby) E renomeia os assets `.yft/.ytd` nomeados
pelo modelo.

**Características**:
- **CIRÚRGICO**: só o token muda no conteúdo (resto byte-a-byte) — replace no conteúdo inteiro
- **PREVIEW-FIRST**: `preview()` mostra cada arquivo/ocorrência e cada asset antes de aplicar
- **BACKUP-SEMPRE**: `execute()` faz backup de tudo antes de tocar
- **VALIDADO**: confere que o token é seguro e que sobra um asset principal `<novo>.yft`
- **Case-insensitive, case-PRESERVADO**: `applyCase` detecta UPPER/LOWER/mixed e preserva
- **Delimitador não-`\b`**: pega "a80" em `STD_a80_FRONT` e `a80_modkit`, mas NÃO em "a800" nem "xa80"

**Validação do novo nome** (`NAME_RE`): `/^[A-Za-z][A-Za-z0-9_]{0,23}$/` — letras/dígitos/underscore,
1..24 chars, começando por letra.

**Funções exportadas**:
```js
preview(car, newNameRaw, existingModels) → { handlingName, oldName, newName, newHandlingName,
                                             metaChanges, assetRenames, warnings, valid }
execute(car, newNameRaw, opts) → { changed, newName, newHandlingName, backupId,
                                    metasWritten, assetsRenamed }
validateName(newName) → string | throws RenameError
replaceToken(content, token, newName) → string   // case-insensitive, case-preservado
class RenameError extends Error
```

### 3.14 `server.js` — servidor HTTP local + API JSON (web UI)

Servidor `http` nativo, bind `127.0.0.1` (offline, sem auth, sem rede externa). Cada request carrega
config fresca (cheap para dezenas de carros) — mudanças no `registry.json` refletem na hora.

**Endpoints**:
| Método+Path | Descrição |
|-------------|-----------|
| `GET /` | Serve `web/index.html` |
| `GET /style.css`, `/app.js`, `/enhance.js` | Estáticos (com anti path-traversal: tudo precisa ficar dentro de `web/`) |
| `GET /api/cars` | Lista de carros (perfil, score, tier calc/registry, assets, áudio) + `tiers: ORDER` |
| `POST /api/preview` | Diff dos 8 campos + bloco p1 p/ um tier escolhido (sem gravar) |
| `POST /api/reconcile` | Calculado × desejado × média (sem tocar nada) |
| `POST /api/rename` | Preview (`execute=false`) ou aplica (`execute=true`) o rename |
| `POST /api/audio-fix` | Preview ou aplica o conserto de áudio |
| `POST /api/apply` | Persiste tier no registry + aplica o balanceamento desse carro |

**`POST /api/apply`** detalhado (server.js:164):
1. `validTier(body.tierBase)` — exit 400 se inválido
2. `registryStore.setTier(handlingName, tierBase, tierMax)` — persiste decisão no registry (fonte única)
3. `config.load()` — recarrega config com o tier novo
4. `applyCmd.run({ only: norm(handlingName) }, freshCfg)` — aplica só este carro
5. Retorna `{ ok, exitCode, report: build-report.json, patch: catalog-patch.json }`

**`carView(car, cfg)`** (server.js:42) — monta a visão completa de um carro para a UI:
```js
{
  audio: { custom, status, canonical, audioNameHash, problems, files },
  handlingName, handlingNameRaw, model, carFolder, dataDir, handlingFile,
  drivetrain, score, calculatedTier, parts, powerToWeight, notes, fingerprint,
  registry: { tier_base, tier_max } | null,
  currentTier: registryTier || calculatedTier,
  metaFiles: [...], assetsCount, streamDir,
}
```

### 3.15 `util.js` — utils puros

```js
norm(s)  = String(s).trim().toUpperCase()      // normalização de handlingName
f6(n)    = Number(n).toFixed(6)                // formato da engine GTA5
clamp(n, lo, hi) = Math.min(hi, Math.max(lo, n))
isNum(n) = typeof n === 'number' && Number.isFinite(n)
r0(n)    = Math.round(n)                        // arredondamento p/ base_alloc
```

---

## 4. Configuração JSON (valores reais)

### 4.1 `config/tiers.json` — a Matriz-Ouro

```jsonc
{
  "_doc": "Matriz-Ouro por tier (seed). Valores de REFERENCIA, a validar em pista (script.md §12). ...",
  "_campos": {
    "drive": "fInitialDriveForce alvo (coeficiente da engine, NAO Newtons)",
    "drag": "fInitialDragCoeff alvo (paredao de vento contra upgrades)",
    "maxVel": "fInitialDriveMaxFlatVel alvo (teto do drive force base)",
    "driveInertia": "fDriveInertia alvo (resposta de aceleracao)",
    "gripMax": "fTractionCurveMax alvo",
    "gripMin": "fTractionCurveMin alvo",
    "brakeForce": "fBrakeForce alvo (modelo proprio, NAO escala com potencia)",
    "antiRollBar": "fAntiRollBarForce alvo (estabilidade base)",
    "budget": "orcamento de pontos da Fase 2 por tier"
  },
  "tiers": {
    "D":  { "reference": "blista",   "massBase": 1100, "drive": 0.140, "drag": 11.5, "maxVel": 125, "driveInertia": 1.00, "gripMax": 2.05, "gripMin": 1.90, "brakeForce": 0.70, "antiRollBar": 0.55, "budget": 500 },
    "C":  { "reference": "kuruma",   "massBase": 1400, "drive": 0.180, "drag": 10.5, "maxVel": 130, "driveInertia": 1.00, "gripMax": 2.15, "gripMin": 2.00, "brakeForce": 0.80, "antiRollBar": 0.60, "budget": 600 },
    "B":  { "reference": "elegy",    "massBase": 1500, "drive": 0.220, "drag": 10.0, "maxVel": 132, "driveInertia": 1.10, "gripMax": 2.30, "gripMin": 2.15, "brakeForce": 0.90, "antiRollBar": 0.65, "budget": 700 },
    "A":  { "reference": "banshee",  "massBase": 1400, "drive": 0.260, "drag":  9.5, "maxVel": 135, "driveInertia": 1.20, "gripMax": 2.45, "gripMin": 2.30, "brakeForce": 1.00, "antiRollBar": 0.70, "budget": 800 },
    "S":  { "reference": "zentorno", "massBase": 1500, "drive": 0.310, "drag":  9.2, "maxVel": 138, "driveInertia": 1.30, "gripMax": 2.65, "gripMin": 2.50, "brakeForce": 1.10, "antiRollBar": 0.75, "budget": 900 },
    "S+": { "reference": "krieger",  "massBase": 1500, "drive": 0.350, "drag":  9.0, "maxVel": 140, "driveInertia": 1.40, "gripMax": 2.80, "gripMin": 2.65, "brakeForce": 1.20, "antiRollBar": 0.80, "budget": 1000 }
  }
}
```

**Observações**:
- `budget` cresce de 500 (D) a 1000 (S+) em passos de 100 — casa com `BUDGET` do `vhub_vehcontrol/shared/tier_rules.lua`
- Carros de referência nativos GTA5 (Blista, Kuruma, Elegy, Banshee, Zentorno, Krieger) servem de baseline
- `maxVel` (125..140) é o ceiling do drive force base — NÃO é top speed real (script.md §2)
- `drive` (0.140..0.350) é o coeficiente da engine; aceleração ≈ `10 × drive` (carskill.md §1.5)
- Spec `script.md` §4 descreve campos adicionais (`gears`, `brakeBiasFront`, `tractionBiasFront`, `comZ`)
  que **NÃO estão** no `tiers.json` real — foram removidos na adoção do NÚCLEO-8

### 4.2 `config/registry.json` — classificação por handlingName

```jsonc
{
  "_doc": "handlingName (normalizado UPPERCASE+trim) -> classificacao de tier. ...",
  "vehicles": {
    "NISSAN370Z":   { "tier_base": "A",  "tier_max": "S"  },
    "TOYOTASUPRA":  { "tier_base": "S",  "tier_max": "S+" },
    "SKYLINER34":   { "tier_base": "S",  "tier_max": "S+" },
    "FERRARIF8":    { "tier_base": "A",  "tier_max": "S"  },
    "FUSCA68":      { "tier_base": "C",  "tier_max": "B"  },
    "BMWE46GTR":    { "tier_base": "S+", "tier_max": "S+" },
    "M3E46":        { "tier_base": "A",  "tier_max": "S"  },
    "F8T":          { "tier_base": "S",  "tier_max": "S+" }
  }
}
```

8 veículos registrados. `tier_max` sempre ≥ `tier_base` (validado por `config.js:validateRegistry`).
Carro fora daqui = **ignorado** + reportado por `scan` (nunca tocado silenciosamente).

### 4.3 `config/overrides.json` — afinação fina por carro

```jsonc
{
  "_doc": "Afinacao fina por carro (opcional). ...",
  "vehicles": {}
}
```

**Vazio** no estado atual — nenhum override aplicado. Schema permitido:
- Performance (NÚCLEO-8): `fInitialDriveForce`, `fInitialDragCoeff`, `fInitialDriveMaxFlatVel`, `fBrakeForce`,
  `fTractionCurveMax`, `fTractionCurveMin`, `fAntiRollBarForce`, `fDriveInertia`
- Identidade (não escritos no `.meta`): `archetype`, `grip_modifier`, `base_alloc`
- Se `base_alloc` presente: 5 chaves (`potencia`, `grip`, `frenagem`, `aero`, `suspensao`) numéricas,
  soma **EXATA** = `budget` do `tier_base` (exit 2 se não bater)

Exemplo do README:
```jsonc
{
  "vehicles": {
    "SUPRA": {
      "fBrakeForce": 0.92,
      "fTractionCurveMin": 2.55,
      "base_alloc": { "potencia":180, "grip":160, "frenagem":160, "aero":160, "suspensao":140 }
    }
  }
}
```

### 4.4 `config/archetypes.json` — arquétipos + regra de derivação

```jsonc
{
  "_doc": "Arquetipo derivado por regra de fDriveBiasFront (0=RWD, ~0.5=AWD, 1=FWD) + fMass (leve/pesado). ...",
  "_regra": {
    "driveBias": { "rwd_max": 0.2, "awd_max": 0.8 },
    "massThreshold": 1500
  },
  "archetypes": {
    "rwd_light": { "grip_modifier": 1.05, "note": "agil, sai de traseira facil" },
    "rwd_heavy": { "grip_modifier": 0.92, "note": "instavel em curva rapida" },
    "fwd_light": { "grip_modifier": 1.02, "note": "subesterçante no limite" },
    "fwd_heavy": { "grip_modifier": 0.95, "note": "dificil de rotar traseiro" },
    "awd_light": { "grip_modifier": 1.08, "note": "equilibrado, versatil" },
    "awd_heavy": { "grip_modifier": 1.00, "note": "estavel, acelera bem" }
  }
}
```

6 arquétipos possíveis (3 drivetrains × 2 classes de peso). Regra pura, sem IA. `grip_modifier`
varia de 0.92 (rwd_heavy, instável) a 1.08 (awd_light, equilibrado) — afina a afinidade do carro
no catálogo sem mexer no `.meta`.

### 4.5 `config/scan-paths.json` — onde varrer

```jsonc
{
  "_doc": "Onde o pipeline varre handling.meta. roots sao relativos a RAIZ DO REPO ...",
  "roots": [
    "resources/[SCRIPTS]/carmod",
    "resources/[CAR]/carmod"
  ],
  "exclude": [ "backup", "_archive", "node_modules", ".backups" ],
  "matchFiles": [ "handling.meta" ]
}
```

Dois roots (um real, um placeholder vazio). Apenas `handling.meta` é matcheado — `vehicles.meta`,
`carcols.meta` e `carvariations.meta` são lidos pelo `carmod.js` a partir da pasta de dados do carro,
não pelo glob. `exclude` filtra por nome de diretório (não glob pattern).

---

## 5. Algoritmo de Balanceamento

### 5.1 Cálculo de alvos por tier (NÚCLEO-8)

```
PARA CADA bloco <Item CHandlingData>:
  1. handlingName = norm(<handlingName> do bloco)
  2. reg = registry[handlingName]; se null → órfão (skip)
  3. mass = parseFloat(<fMass value="..."/>)
     - se mass inválida → skip 'massa-invalida'
     - se mass/massBase < 0.5 ou > 2.0 → WARN 'massa fora da banda'
  4. tier = tiers[reg.tier_base]
  5. ov = overrides[handlingName] || {}
  6. PARA CADA campo F do NÚCLEO-8:
     - alvo = ov[F] ?? tier[mapa(F)]
       (driveRaw = ov.fInitialDriveForce ?? tier.drive)
       (drive    = clamp(driveRaw, tier.drive*0.85, tier.drive*1.15))   # ±15%
       (se driveRaw != drive → clampInfo warning)
     - from = readValue(bloco, F)
     - se from === alvo → changed=false, missing=false
     - se campo ausente → changed=false, missing=true (WARN, não injeta)
     - senão → substitui value="..." por f6(alvo), changed=true
  7. se gripMin > gripMax → gripMin = gripMax (sanidade)
  8. newBlock = bloco recomposto com os 8 valores (se aplicável)
```

### 5.2 Mapeamento campo→tier

| Campo .meta | Campo tiers.json | Observação |
|-------------|------------------|------------|
| `fInitialDriveForce` | `drive` | clampado ±15% (anti-P2W) |
| `fInitialDragCoeff` | `drag` | paredão contra upgrades |
| `fInitialDriveMaxFlatVel` | `maxVel` | ceiling do drive force base |
| `fDriveInertia` | `driveInertia` | resposta de aceleração |
| `fBrakeForce` | `brakeForce` | modelo próprio, NÃO escala com potência |
| `fTractionCurveMax` | `gripMax` | aderência pico |
| `fTractionCurveMin` | `gripMin` | aderência derrapando |
| `fAntiRollBarForce` | `antiRollBar` | estabilidade base |

### 5.3 Classificação em archetype

Regra pura (sem IA), em `catalogEmitter.deriveArchetype`:
```js
drive = (driveBias <= 0.2) ? 'rwd' : (driveBias <= 0.8) ? 'awd' : 'fwd'
heavy = mass >= 1500
archetype = `${drive}_${heavy ? 'heavy' : 'light'}`
```

Override possível: `overrides[handlingName].archetype = "..."` (bypassa a regra).

### 5.4 Classificação em tier CALCULADO (profiler.js)

Score 0..1000 = `Σ (dimensão × peso) × 1000`:
```
score = round(
  accel×0.30 + launch×0.10 + grip×0.30 + brake×0.15 + stability×0.15
) × 1000
```

Cada dimensão normalizada 0..1 na banda D..S+ (piso/teto da Matriz-Ouro). `fMass` **NÃO** entra em
`accel` (a=F/m cancela — §1.5); entra em `power-to-weight` (clamp anti-absurdo) e na `estabilidade`
(via suspensão/antiRoll).

**Anti-absurdo**: se `powerToWeight < 0.12` E `tierIndex(calculatedTier) >= tierIndex('A')` →
reduz 1 nível (carro muito pesado com pouca força não merece tier alto mesmo com números altos).

**Faixas de tier por score** (SCORE_BANDS):
- D: 0–199 · C: 200–399 · B: 400–599 · A: 600–749 · S: 750–899 · S+: 900–1000

### 5.5 Reconciliação calc × desejado × média

```js
// tiers.js:107
function reconcileTier(calculated, desired, mode) {
  const ci = tierIndex(calculated);
  const di = tierIndex(desired);
  const m = mode || 'media';
  let fi;
  if (m === 'calculado' || di < 0) fi = ci;
  else if (m === 'desejado')       fi = di;
  else                             fi = Math.round((ci + di) / 2);  // média
  fi = Math.max(0, Math.min(ORDER.length - 1, fi));
  return { final: ORDER[fi], calcIndex: ci, desiredIndex: di, finalIndex: fi, mode: m };
}
```

**Default seguro = `'media'`** — nunca teleporta um carro fraco para o topo; fica no meio do caminho,
mantendo o balanceamento.

### 5.6 Geração do patch (apply)

```
1. processar (calcula newBlock + changes por carro)
2. groupByFile (um arquivo pode ter N carros)
3. backup de TODOS os arquivos que vão mudar (.backups/<timestamp>/)
4. PARA CADA arquivo:
   a. rebuild() = splitBlocks + troca só blocos processados por newBlock
   b. writeText (só se mudou — idempotente)
   c. hash sha256 do arquivo final UMA vez
   d. PARA CADA entry do arquivo:
      - sealMap[name] = { tier, sha256, file }
      - patchByKey[name.toLowerCase()] = buildEntry(...)
5. seal.write(sealMap)
6. emitter.writePatch(patchByKey)
7. report.writeBuildReport(entries, { backupId })
```

### 5.7 Campos de handling.meta modificados

**Apenas 8** (NÚCLEO-8), conforme `tiers.FIELDS`:
```
fInitialDriveForce, fInitialDragCoeff, fInitialDriveMaxFlatVel, fDriveInertia,
fBrakeForce, fTractionCurveMax, fTractionCurveMin, fAntiRollBarForce
```

Substituição via regex escopada ao bloco: `(<field\s+value=")([^"]*)("\s*/>)`. Apenas o grupo 2
(valor) é trocado por `f6(num)` (6 casas decimais). Indentação, comentários, atributos adjacentes,
`<Item type="NULL"/>` e `SubHandlingData` — tudo preservado byte-a-byte.

---

## 6. Seal System (Anti-Tampering)

### 6.1 Como seal.js gera o selo

```js
// seal.js:24
function hashContent(content) {
  return 'sha256:' + crypto.createHash('sha256').update(content, 'utf8').digest('hex');
}
```

- **Algoritmo**: SHA-256 (Node `crypto` nativo)
- **Encoding**: UTF-8 do conteúdo completo do `.meta` (incluindo BOM, EOL, trailing newline — preservados)
- **Formato no JSON**: `'sha256:<64-hex-chars>'` (prefixo explícito deixa o algoritmo visível)
- **Caminho**: `.seal/seal.json` (commitado no repo)

### 6.2 Schema do `.seal/seal.json`

```jsonc
{
  "_doc": "Selo de integridade gerado por `apply`/`seal`. Chave = handlingName real do .meta. ...",
  "F8T":         { "tier": "S",  "sha256": "sha256:c65806cc...", "file": "resources/[SCRIPTS]/carmod/f8t/common/handling.meta" },
  "TOYOTASUPRA": { "tier": "S",  "sha256": "sha256:a17b...",     "file": "..." }
}
```

Ordenado por `handlingName` (sort alfabético) para diff git estável. `_doc` é adicionado por `seal.write`
e removido por `seal.read`.

### 6.3 Sealed vs unsealed

- **Sealed**: carro classificado no `registry.json` E com entrada no `.seal/seal.json` (após `apply` ou `seal`)
- **Unsealed**: carro classificado no registry mas SEM entrada no selo → reportado por `verify` como `unsealed`
- **Drift**: carro com selo mas hash atual difere do selado → `verify` reporta `drift`
- **Missing (selo órfão)**: carro no selo que sumiu do scan → `verify` reporta `missing`

### 6.4 Como `verify` valida

```js
// verify.js:15 + seal.diff
function diff(entries, sealMap) {
  for (const e of entries) {
    if (!sealMap[e.name]) result.unsealed.push(e.name);     // classificado, nunca selado
    else if (hashContent(e.content) !== sealed.sha256)
      result.drift.push({ name, file, expected, got });      // editado fora do pipeline
  }
  for (const name of Object.keys(sealMap)) {
    if (!seen.has(name)) result.missing.push(name);          // selo órfão
  }
  return result;  // result.ok = (drift + unsealed + missing) === 0
}
```

Exit codes: `0` se `result.ok`; `1` se qualquer problema.

### 6.5 Como `restore` reverte

```js
// io.js:126
function restoreBackup(id) {
  // walk .backups/<id>/ — para cada arquivo, copia byte-a-byte de volta ao REPO_ROOT
  // retorna [restoredAbsPaths]
}
```

Restaura os `.meta` exatamente como estavam antes do `apply`. **Não mexe no selo** — após restaurar,
rode `seal` (re-sela hashes atuais) ou `apply` (re-aplica + re-sela) para realinhar.

### 6.6 Como `seal` re-sela

Para uso após uma edição manual APROVADA (fora do NÚCLEO-8, por decisão consciente do dono). Recomputa
o hash atual e grava como novo estado válido. **Não reescreve `.meta`** — só atualiza `.seal/seal.json`.

> **Limite honesto do selo**: bloqueia edição **na fonte (repo/deploy)**. Não impede um trainer
> client-side — isso é trabalho do anti-cheat server-side do vHub (defesa complementar, camada 3 do §8
> do script.md).

---

## 7. Web UI (serve.js + web/)

### 7.1 Como o servidor web funciona

- **Bind**: `127.0.0.1` apenas (offline, sem rede externa, sem auth)
- **Porta**: 7920 default (`--port <n>` para mudar)
- **Sem dependências externas**: `http` nativo do Node
- **Config fresca por request**: cada handler chama `config.load()` (cheap p/ dezenas de carros) —
  mudanças no `registry.json` refletem na hora
- **Anti path-traversal**: `serveStatic` checa `abs.startsWith(WEB_DIR)` (tudo precisa ficar dentro de `web/`)

### 7.2 Arquivos da web UI

| Arquivo | Tamanho | Papel |
|---------|---------|-------|
| `web/index.html` | 282 linhas | Estrutura HTML + template `<article class="card">` para cada carro |
| `web/app.js` | 392 linhas | Lógica principal (vanilla JS, sem framework) |
| `web/enhance.js` | 342 linhas | Camada de UX (sidebar, radar SVG, score-meter, peers) |
| `web/style.css` | 893 linhas | Tema dark premium (Inter/JetBrains Mono/Space Grotesk, paleta gold) |

### 7.3 Estrutura da UI

**Layout**: sidebar (catálogo) + main (detalhe do carro selecionado).

**Sidebar** (`<aside class="sidebar">`):
- Brand "vHub Handling Balancer"
- Busca (carro, modelo, pasta)
- Filtro por tier (Todos, D, C, B, A, S, S+)
- Lista de carros (ordenada por tier desc, depois por score desc) com badge tier, drivetrain, score/1000, barra
- Botão "Recarregar catálogo"

**Card de carro** (`<template id="tpl-car">`):
1. **Identidade**: nome, chips (modelo, drivetrain, pasta), botão "Renomear"
2. **Painel de rename**: input + "Pré-visualizar mudanças" + "Renomear em todos os arquivos"
3. **Áudio custom**: status (✓ OK / ⚠ precisa de conserto / som nativo), problemas, "Consertar áudio"
4. **Análise de performance**: tier calculado, score 0..1000 com zonas por tier, power-to-weight, 5 barras
   (Aceleração, Largada, Curva, Frenagem, Estabilidade), notas
5. **Comparativo de tier** (radar SVG): carro × média × melhor do mesmo tier + tabela de peers (top 5)
6. **Decisão de tier**: Calculado (badge) · Desejado (select D..S+) · Modo (Calculado/Média/Meu desejado) · Final (badge)
7. **Prévia do balanceamento** (tabela): Campo · Atual → Alvo (8 linhas NÚCLEO-8) + warning de clamp
8. **Ação**: "Aplicar balanceamento (Final)"

### 7.4 Operações disponíveis na UI

- **Listar carros**: `GET /api/cars` → monta catálogo na sidebar
- **Preview balanceamento**: `POST /api/preview` → tabela antes→depois dos 8 campos
- **Reconcile**: `POST /api/reconcile` → modo calculado/desejado/média → tier final
- **Rename**: `POST /api/rename` (execute=false → preview; execute=true → aplica + migra registry)
- **Audio fix**: `POST /api/audio-fix` (execute=false → preview; execute=true → conserta)
- **Apply**: `POST /api/apply` → persiste tier no registry + aplica balanceamento + gera build-report

### 7.5 API endpoints do server.js

| Método+Path | Body | Resposta |
|-------------|------|----------|
| `GET /api/cars` | — | `{ cars: [carView], tiers: ORDER }` |
| `POST /api/preview` | `{ handlingName, tier }` | `{ tier, fields: [{field, from, to, changed, missing}], p1, clampInfo }` |
| `POST /api/reconcile` | `{ handlingName, desired, mode }` | `{ final, calcIndex, desiredIndex, finalIndex, mode }` |
| `POST /api/rename` | `{ handlingName, newName, execute }` | preview ou `{ ok, newName, newHandlingName, backupId, metasWritten, assetsRenamed, note }` |
| `POST /api/audio-fix` | `{ handlingName, execute }` | preview ou `{ ok, canonical, backupId, renamed, manifestFixed, hashFixed }` |
| `POST /api/apply` | `{ handlingName, tierBase, tierMax }` | `{ ok, exitCode, report, patch }` |

### 7.6 Detalhes técnicos da UI

- **`app.js`**: vanilla JS, sem framework. Estado por card em `Map`. `reconcile()` local (mesma regra do
  servidor) para resposta instantânea. Toast para feedback. `esc()` anti-XSS para conteúdo dinâmico.
- **`enhance.js`**: IIFE que **não altera** `app.js`. Intercepta `window.fetch` para capturar `/api/cars`
  sem tocar no app original. `MutationObserver` decora cards inseridos com `score-meter` (cursor 0..1000
  + dots dos peers) e `radar` SVG (5 eixos: Acel., Largada, Curva, Freio, Estab.). Ordenação da sidebar
  por tier desc + score desc.
- **`style.css`**: dark premium, paleta gold (`--gold: #f5d77a`), tier palette (D=cinza, C=cyan, B=verde,
  A=âmbar, S=vermelho, S+=gold), fontes Inter/JetBrains Mono/Space Grotesk. Background com orbs + grid
  overlay ornamental.

---

## 8. Catalog Emitter

### 8.1 Como `catalogEmitter.js` gera o catálogo

`buildEntry(handlingNameRaw, block, cfg, seal)` (catalogEmitter.js:69):

1. `name = handlingNameRaw.trim().toUpperCase()` — chave do registry/overrides/seal
2. `reg = cfg.registry[name]`; `ov = cfg.overrides[name] || {}`
3. Lê campos PRESERVADOS direto do `.meta`:
   - `driveBias = meta.readValue(block, 'fDriveBiasFront')`
   - `suspRaise = meta.readValue(block, 'fSuspensionRaise')`
   - `mass = meta.readValue(block, 'fMass')`
   - `inertiaZ = meta.readAttr(block, 'vecInertiaMultiplier', 'z')`
   - `lowSpeedLoss = meta.readValue(block, 'fLowSpeedTractionLossMult')`
4. `archetype = ov.archetype || deriveArchetype(driveBias, mass, cfg.archetypeRule)`
5. `archMod = (cfg.archetypes[archetype] || {}).grip_modifier ?? 1.0`
6. `budget = cfg.tiers[reg.tier_base].budget`
7. Monta o bloco `p1` com 12 campos (ver §3.9)

### 8.2 Formato do catálogo emitido

Exemplo real (`out/catalog-patch.json` atual):
```json
{
  "_doc": "Proposta de extensao do catalogo do conce (bloco p1 por veiculo). ARTEFATO INERTE: mesclar MANUALMENTE em vhub_conce/shared/catalog.lua na Fase 2 (gate do conce). key = modelName minusculo (casa com a entrada existente). NAO commitado (gerado por `apply`; veja `plan` para preview).",
  "f8t": {
    "handling_name": "f8t",
    "tier_base": "S",
    "tier_max": "S+",
    "archetype": "rwd_heavy",
    "grip_modifier": 0.92,
    "base_alloc": { "potencia": 180, "grip": 180, "frenagem": 180, "aero": 180, "suspensao": 180 },
    "drive_bias": 0,
    "susp_raise": -0.015,
    "mass": 1600,
    "inertia_z": 1.6,
    "low_speed_loss": 1,
    "seal": "sha256:c65806cc6e8a382bd931fa29274e3265b0b078c02eb20c3594c4f53524fb30fa"
  }
}
```

**Duas convenções de chave coexistem de propósito**:
- `.seal/seal.json` chaveia por `handlingName` real (UPPERCASE) — integridade do arquivo
- `catalog-patch.json` chaveia por `modelName` minúsculo — merge no catálogo (casa com
  `catalog[norm(model)]` em runtime, `norm == string.lower`)

### 8.3 Como vhub_vehcontrol consome (via vhub_conce Fase 2)

1. **Fase 1** (este tool): gera `out/catalog-patch.json` com o bloco `p1` por veículo
2. **Fase 2** (vhub_conce, ⏳ pendente): dev mescla MANUALMENTE o bloco `p1` em `vhub_conce/shared/catalog.lua`
   sob gate do conce (catálogo é autoridade do conce, decisão #25 do PLANO.md)
3. **Runtime**: `vhub_vehcontrol` lê o catálogo do conce via exports para derivar:
   - `tier_base`/`tier_max` → clamp do tier exibido na ficha
   - `base_alloc` (5 eixos) → âncora do budget do skill (`BUDGET[tier_base] + partsBonus`, soma exata)
   - `grip_modifier` → ajuste de afinidade por arquétipo
   - `archetype` → exibição + regra de jogada
   - `drive_bias`, `susp_raise`, `mass`, `inertia_z`, `low_speed_loss` → parâmetros físicos para o
     `client/handling.lua` (F5 física) aplicar `SetVehicleHandlingFloat` por eixo

### 8.4 Onde o catálogo é gravado

`out/catalog-patch.json` (caminho: `<TOOL_ROOT>/out/catalog-patch.json`). Gitignore (não commitado);
gerado por `apply`, preview por `plan`.

---

## 9. Integração com vHub

### 9.1 Como handling-balancer se encaixa no ecossistema

```
[BUILD-TIME]                              [RUNTIME]
handling-balancer (este tool)             ┌──────────────────────────────┐
  │                                       │ FXServer boot                │
  ├─ scan/plan/apply/seal/verify          │  ├─ vhub_conce (catálogo)    │
  ├─ gera .meta balanceados + selados     │  │    └─ catalog.lua (mescla)│
  ├─ gera catalog-patch.json (artefato)   │  │       ↑                   │
  │                                       │  │    Fase 2 (manual)        │
  ▼                                       │  ├─ vhub_vehcontrol (ficha)  │
commit + deploy                           │  │    ├─ tier clamping       │
  │                                       │  │    ├─ skill budget        │
  ▼                                       │  │    └─ F5 física (HAL)     │
CI: verify --json (gate de PR)            │  └─ vhub_nitro, vhub_garage  │
                                          └──────────────────────────────┘
```

### 9.2 Quem chama quem

- **Dev** chama `node balance.js serve` localmente → web UI para classificar/renomear/balancear
- **Dev** chama `node balance.js scan`/`plan`/`apply` via CLI (ou `npm run scan|plan|apply`)
- **CI** chama `node balance.js verify --json` em cada PR (gate de merge)
- **Dev** mescla `out/catalog-patch.json` MANUALMENTE em `vhub_conce/shared/catalog.lua` (Fase 2)
- **FXServer boot** lê os `.meta` balanceados nativamente (C++ da engine) — zero Lua, zero `resmon`

### 9.3 Quando rodar scan/apply (build time vs runtime)

| Operação | Quando | Quem |
|----------|--------|------|
| `scan` | Adicionar novo DLC/mod | Dev local |
| `plan` | Antes de `apply` (sanidade) | Dev local |
| `apply` | Após classificar no registry | Dev local (UI ou CLI) |
| `verify` | Cada PR / pre-commit hook | CI |
| `seal` | Após edição manual APROVADA | Dev (raro) |
| `restore` | Desfazer `apply` errado | Dev (raro) |
| `serve` | Edição visual / classificação | Dev local |

**NUNCA em runtime do FXServer** — o servidor apenas lê os `.meta` no boot (alinhado a L-05/L-06 do
manual_dev_vhub.md: zero loop, zero thread Lua, zero impacto em `resmon`).

### 9.4 Catálogo gerado é lido por vhub_vehcontrol? vhub_conce?

- **vhub_conce**: lê o catálogo (autoridade — decisão #25). Na Fase 2, o `catalog-patch.json` será
  mesclado em `vhub_conce/shared/catalog.lua`. O conce é o gate: ninguém além do conce escreve no catálogo.
- **vhub_vehcontrol**: lê o catálogo DO CONCE via exports read-only (`getVehicleSheet`, `getCatalog`)
  para derivar tier, budget, afinidade. Não lê o `catalog-patch.json` diretamente — só indiretamente
  após o merge no conce.

---

## 10. Fluxos Principais

### 10.1 Adicionar novo veículo DLC

```
1. Coloque o carro mod na árvore: resources/[SCRIPTS]/carmod/<pasta>/...
   - common/handling.meta, common/vehicles.meta, common/carvariations.meta
   - stream/<pasta>/<model>*.yft/.ytd
2. node balance.js scan
   → veja o handlingName REAL do carro (ex.: "SKYLINER34")
   → confirme que não é órfão nem duplicata
3. (Opcional) node balance.js serve → renomeie o modelo se vier com nome aleatório ("a80" → "supra")
   - Preview mostra cada arquivo/linha que muda + assets a renomear
   - Backup automático; renomeia .meta + .yft/.ytd (NUNCA áudio)
4. Classifique em config/registry.json:
   "SKYLINER34": { "tier_base": "S", "tier_max": "S+" }
   (ou via UI: selecione tier desejado, modo média, apply)
```

### 10.2 Rodar scan em todos os handling.meta

```bash
node balance.js scan
# ou
npm run scan
```
Saída (terminal PT-BR):
```
=== CARROS CLASSIFICADOS ===
   NISSAN370Z       tier A -> S   resources/[SCRIPTS]/carmod/370z/common/handling.meta
   ...
=== ÓRFÃOS (sem tier no registry — IGNORADOS, nunca tocados) ===
   (nenhum)
=== DUPLICATAS (mesmo handlingName em vários arquivos — registro ambíguo) ===
   (nenhuma)
=== TOTAL ===
   arquivos varridos    : 8
   carros classificados : 8
   órfãos               : 0
   duplicatas           : 0
```

### 10.3 Gerar plan (relatório de desbalanceamento)

```bash
node balance.js plan
# ou filtrado:
node balance.js plan --only SUPRA,SKYLINER34 --json
```
Saída por carro: `[tier S] (file)` + diff dos 8 campos (`~ fInitialDriveForce 0.280000 → 0.310000`)
+ warnings + summary. Em seguida, preview do bloco `p1` que iria no catalog-patch.

### 10.4 Aplicar patches (apply)

```bash
node balance.js apply
# ou só um carro:
node balance.js apply --only SUPRA
# ou dry-run (igual ao plan):
node balance.js apply --dry-run
```
Saída: backup criado + arquivos gravados + selo atualizado + catalog-patch emitido + build-report gravado.

### 10.5 Selar (seal)

```bash
node balance.js seal
```
Uso: após uma edição manual APROVADA (fora do NÚCLEO-8). Re-sela os hashes atuais sem reescrever `.meta`.

### 10.6 Verificar integridade (verify)

```bash
node balance.js verify --json   # CI gate
```
Exit 0 se tudo OK; exit 1 se qualquer drift/unsealed/missing. Em CI, PR que mexe num `handling.meta`
sem passar pelo pipeline **não mergeia**.

### 10.7 Servir web UI para ajustes finos

```bash
node balance.js serve --port 7920
# ou
npm run serve
```
Abre `http://127.0.0.1:7920`. Operações na UI: classificar tier (calc × desejado × média), preview
balanceamento, aplicar (com backup + selo), renomear modelo, consertar áudio custom, comparar com peers
do mesmo tier (radar).

### 10.8 Emitir catálogo para vhub_vehcontrol

Automático no `apply` (passo 6 do §5.6): `emitter.writePatch(patchByKey)` grava `out/catalog-patch.json`
com o bloco `p1` por veículo. **Mesclagem manual na Fase 2** sob gate do `vhub_conce`.

### 10.9 Restaurar backup (restore)

```bash
node balance.js restore                # mais recente
node balance.js restore --backup 20260615-120000   # específico
```
Restaura `.meta` byte-a-byte. Após restaurar, rode `seal` ou `apply` para realinhar o selo.

---

## 11. Handling.meta Schema

### 11.1 Campos LIDOS pelo balancer

| Campo | Tipo | Uso no balancer |
|-------|------|-----------------|
| `<handlingName>` | string | Chave do registry/seal/overrides (normalizado UPPER+trim) |
| `fMass` | float (kg) | Validado (>0); lido para `warnIfMassOutOfBand`, `deriveArchetype`, `buildEntry.mass`, `profiler.powerToWeight` |
| `fInitialDriveForce` | float | **MODIFICADO** (alvo = tier.drive, clampado ±15%) |
| `fInitialDragCoeff` | float | **MODIFICADO** (alvo = tier.drag) |
| `fInitialDriveMaxFlatVel` | float | **MODIFICADO** (alvo = tier.maxVel) |
| `fDriveInertia` | float | **MODIFICADO** (alvo = tier.driveInertia) |
| `fBrakeForce` | float | **MODIFICADO** (alvo = tier.brakeForce) |
| `fTractionCurveMax` | float | **MODIFICADO** (alvo = tier.gripMax) |
| `fTractionCurveMin` | float | **MODIFICADO** (alvo = tier.gripMin; clampado a gripMax se >) |
| `fAntiRollBarForce` | float | **MODIFICADO** (alvo = tier.antiRollBar) |
| `fDriveBiasFront` | float (0..1) | LIDO (preservado); usado em `deriveArchetype` + `buildEntry.drive_bias` + `profiler.classifyDrivetrain` |
| `fSuspensionRaise` | float | LIDO (preservado); emitido em `buildEntry.susp_raise` |
| `vecInertiaMultiplier z` | float (attr) | LIDO (preservado); emitido em `buildEntry.inertia_z` |
| `fLowSpeedTractionLossMult` | float | LIDO (preservado); emitido em `buildEntry.low_speed_loss` |
| `fSuspensionForce` | float | LIDO por `profiler.analyze` para `stability` (0.4 × clamp(susp/3.0)) |
| `nInitialDriveGears` | int | LIDO por `profiler.analyze` (fingerprint, não usado no score) |

### 11.2 Campos NUNCA tocados (identidade)

- Lataria/dano: `fCollisionDamageMult`, `fDeformationDamageMult`, `fWeaponDamageMult`, `fEngineDamageMult`, `strDamageFlags`
- Suspensão: `fSuspensionForce`, `fSuspensionHeave`, `fSuspensionBiasFront`, `fSuspensionReboundDamp`, etc.
- `vecCentreOfMassOffset` (x/y/z)
- `vecInertiaMultiplier` (x/y) — só `z` é lido para o patch, nunca modificado
- Drivetrain: `fDriveBiasFront` (preservado)
- Marchas: `nInitialDriveGears` (preservado — spec script.md §5.2 descrevia normalização, REMOVIDO no NÚCLEO-8)
- `fSteeringLock`, `fSeatOffset*`, `AIHandling`, `strModelFlags`, `strHandlingFlags`
- `nMonetaryValue`, `fPetrolTankVolume`
- `SubHandlingData` (intocado — `<Item type="NULL"/>` e sub-handlings nem enxergados pela regex)
- Todo conteúdo visual (`carcols.meta`, `carvariations.meta`, `.yft`, `.ytd`, `vehicles.meta`)

### 11.3 Exemplo real (tmp/hbtest/carmod/zz/common/handling.meta)

```xml
<CHandlingDataMgr><HandlingData>
<Item type="CHandlingData">
  <handlingName>ZZTEST</handlingName>
  <fMass value="1500.000000" />
  <fInitialDriveForce value="0.300000" />
</Item>
</HandlingData></CHandlingDataMgr>
```

Exemplo mínimo (carro de teste). Apenas `fMass` e `fInitialDriveForce` presentes — os outros 6 campos
do NÚCLEO-8 estão AUSENTES, gerariam `missing: true` (WARN, não injeta).

**`vehicles.meta`** correspondente:
```xml
<InitDatas><Item>
  <modelName>zztest</modelName>
  <txdName>zztest</txdName>
  <handlingId>zztest</handlingId>
  <gameName>zztest</gameName>
  <Item>STD_zztest_FRONT</Item>
</Item></InitDatas>
```

**`carvariations.meta`** correspondente:
```xml
<modelName>zztest</modelName>
<Item>1_zztest_modkit</Item>
```

### 11.4 Range/impacto dos campos modificados (Matriz-Ouro)

| Campo | D | S+ | Impacto no balanceamento |
|-------|---|----|--------------------------|
| `fInitialDriveForce` | 0.140 | 0.350 | Aceleração (a ≈ 10×drive); clampado ±15% do tier |
| `fInitialDragCoeff` | 11.5 | 9.0 | Paredão contra upgrades (maior = mais arrasto) |
| `fInitialDriveMaxFlatVel` | 125 | 140 | Ceiling do drive force base (NÃO top speed) |
| `fDriveInertia` | 1.00 | 1.40 | Resposta de aceleração (RPM sobe mais rápido) |
| `fBrakeForce` | 0.70 | 1.20 | Frenagem (modelo próprio, não escala com potência) |
| `fTractionCurveMax` | 2.05 | 2.80 | Grip pico (curva limpa) |
| `fTractionCurveMin` | 1.90 | 2.65 | Grip derrapando (never > gripMax) |
| `fAntiRollBarForce` | 0.55 | 0.80 | Estabilidade base (anti-roll) |

---

## 12. Pontos de Atenção

### 12.1 Possíveis problemas no algoritmo

1. **Override só clamp em `fInitialDriveForce`**: os outros 7 campos do NÚCLEO-8 aceitam override
   SEM clamp de sanidade. Um `fTractionCurveMax: 5.0` em um tier D seria aceito (apenas `gripMin > gripMax`
   é rejeitado). Possível "tier S+ disfarçado de D" se o override for malicioso. O README menciona
   "Override NUNCA ultrapassa os clamps absolutos do tier" mas o código só aplica clamp ao drive force.

2. **`tierOrder` usa ordem de inserção do JSON**: `config.tierOrder(tiers)` retorna `Object.keys(tiers)`.
   Se o `tiers.json` for reordenado (ex.: S+ antes de D), `validateRegistry` (que compara
   `order.indexOf(max) < order.indexOf(base)`) quebraria. Frágil — depende de o JSON manter ordem D..S+.

3. **`profiler.analyze` não tem proteção contra `f.suspForce` NaN**: `clamp((f.suspForce || 0) / 3.0, 0, 1)`
   usa `|| 0` que cobre `NaN`? Não — `NaN || 0` retorna `0` (porque `NaN` é falsy), então OK. Mas
   `0 / 3.0 = 0` reduz a estabilidade artificialmente para carros sem `fSuspensionForce`. Raro.

4. **`bumpTier` (server.js:275) define tier_max = base+1**: quando a UI aplica sem especificar tier_max,
   ela assume `base + 1` (ex.: tier_base=A → tier_max=S). Isto pode não refletir a intenção do dev
   para carros cujo teto de upgrade deva ser o próprio tier_base (ex.: BMWE46GTR é S+/S+ no registry).

5. **Rename não atualiza `.seal/seal.json`**: após `rename.execute`, o `handlingName` muda no `.meta`,
   mas o selo antigo continua apontando para o nome velho. A UI avisa "rode o balanceamento de novo
   (apply) para re-selar o `.meta` com o novo nome", mas se o dev esquecer, `verify` falha com
   `unsealed` (novo nome) + `missing` (nome velho).

6. **`audio.executeFix` exige arquivo `.dat54.rel` legível**: se o binário estiver corrompido ou
   ausente, `bankTokenFromDat` retorna `null` e o conserto é abortado ("nome real do áudio
   indeterminável; conserto manual"). Sem fallback para heuristic.

7. **`deriveArchetype` threshold fixo em 1500kg**: hardcoded em `archetypes.json _regra.massThreshold`.
   Carro de exatamente 1500kg (elegy, zentorno, krieger — todos `massBase: 1500`) cai em `heavy`.
   Threshold de 1499 seria `light`. Sensível a 1 kg de diferença.

### 12.2 Edge cases

- **Veículo muito pesado** (ex.: caminhão 4000kg): `warnIfMassOutOfBand` dispara se `mass/massBase > 2.0`
  (ex.: 4000/1500 = 2.67 → WARN "massa muito fora da banda do tier"). Mas o carro ainda é processado —
  o `fInitialDriveForce` alvo NÃO escala por massa (correção do bug v1.0), então o carro fica lento
  mas com mesma força que um leve do mesmo tier. Pode ser insuficiente.

- **Veículo muito leve** (ex.: 500kg): `warnIfMassOutOfBand` se `mass/massBase < 0.5`. Mesmo problema —
  drive force não escala, então o carro leve acelera igual ao pesado do tier. Mas o `profiler.analyze`
  tem anti-absurdo: `powerToWeight = driveForce / (mass/1000)` — se `< 0.12` E tier ≥ A, reduz 1 nível.
  Para carro leve, o P2W seria ALTO (denominador pequeno), então não aciona. Anti-absurdo só pega
  pesados fracos.

- **Massa inválida** (`fMass` ausente, 0, NaN, negativo): `engine.processBlock` retorna
  `skipped: 'massa-invalida'` — não processa. Correto.

- **`handlingName` duplicado entre arquivos**: reportado por `scan` como `duplicates`. O `process`
  ainda processa ambos (não bloqueia), mas o `seal` fica ambíguo (chave = handlingName, sem arquivo).
  Risco: dois carros com mesmo handlingName sobrescrevem a entrada do selo.

- **Campo-alvo ausente no bloco**: `meta.setValue` retorna `missing: true`, o engine adiciona WARN
  "campo ausente no .meta: <field> (não injetado)". Não cria campo novo (ordem do `.meta` importa
  para o parse nativo). Correto, mas o carro fica com campos desbalanceados.

- **Arquivo com `SubHandlingData` e `<Item type="NULL"/>`**: `meta.splitBlocks` é depth-aware
  (`findMatchingClose` conta aninhamento, self-closing não conta). Não enxerga sub-handlings.
  Correto.

### 12.3 Compatibilidade com DLCs futuros

- **Estrutura `<Item type="CHandlingData">`**: regex `/^<Item\s+type="CHandlingData"\s*>/` é rígida.
  Se um DLC futuro usar `<Item type='CHandlingData'>` (aspas simples) ou `<Item type="CHandlingData" >`
  (espaço extra), o split falha silenciosamente (resto vira prefixo). Tolerante a whitespace entre
  atributos seria mais robusto.

- **Novos campos de handling**: se a Rockstar adicionar campos novos ao schema (ex.: `fDownforceModifier`
  em `CCarHandlingData` sub-handling), o balancer simplesmente não os vê (regex escopada ao bloco de
  topo). Sem quebra, mas também sem balanceamento desses campos.

- **`vehicles.meta` multi-carro**: `carmod.resolveVehicleInfo` casa pelo `handlingId`. Se o
  `vehicles.meta` não tiver `<handlingId>` (caso raro), fallback para o primeiro `<Item>`. Pode
  ligar o handling errado ao modelo errado em mods mal estruturados.

### 12.4 Segurança do selo

- **SHA-256 é forte**: sem colisões práticas conhecidas. Hash determinístico do conteúdo UTF-8.
- **Limite honesto** (declarado no README): o selo bloqueia edição **na fonte (repo/deploy)**. Não
  impede trainer client-side. Defesa complementar: anti-cheat server-side do vHub (validação de
  posição/velocidade).
- **`.seal/seal.json` é commitado**: se um atacante comprometer o repo, pode reescrever o selo junto.
  Mitigação: code review do PR + CI gate (mas o CI também roda no repo comprometido...).
- **Hash do catalog-patch é CÓPIA de auditoria**: o `verify` só lê `seal.json` (linha 7 do verify.js:
  "O seal.json e a UNICA fonte que o verify le"). Se alguém adulterar o `catalog-patch.json` após o
  apply, o `verify` não detecta — apenas o `seal.json` é autoritativo.
- **`seal` re-sela sem auditoria**: qualquer dev com acesso ao repo pode rodar `node balance.js seal`
  após editar um `.meta` à mão, e o `verify` volta a passar. O README diz "use isto apenas após uma
  edição manual APROVADA" — mas é uma convenção social, não técnica. O `build-report.json` é a trilha
  de auditoria (mas também gitignore).

---

## 13. Comparação com sss.txt

### 13.1 O que o sss.txt descreve

O `sss.txt` (391 linhas) é um documento de **filosofia de balanceamento** com 3 partes:

1. **Categoria "Heavy-Sport / GT"** (sweet spot 1450–1750kg): punição por erro de piloto. Carros
   muito leves (<1150kg) agem como "bolas de pinberry"; muito pesados (>1950kg) sofrem de
   subesterço crônico. Sweet spot: `fMass 1450–1750`, `fInitialDriveForce 0.300–0.350`,
   `fDriveInertia` reduzido (ex.: 1.0 → 0.85), `fBrakeForce 0.85–1.10`, `fBrakeBiasFront 0.55`,
   `fTractionCurveMax/Min` altos.

2. **Categoria "Equilibrada" (All-Rounder)**: AWD com viés traseiro (`fDriveBiasFront 0.30–0.40`),
   `fMass 1300–1450`, `fTractionCurveMax ~2.2` (menor que Esportivo), `fTractionCurveMin ~1.8`
   (gap pequeno = previsível), `fDragMult` alto (8.5–9.0) para perder do Muscle em reta longa.

3. **Arquitetura de validação server-side** (Lua + oxmysql): 3 camadas — Domínio (regras por categoria),
   Validação (lógica pura), Integração+Boot (SQL fetchAll + UPDATE dinâmico com clamping). Self-healing:
   corrige automaticamente valores fora da banda no boot.

### 13.2 O handling-balancer implementa essa filosofia?

**Parcialmente.** Pontos de convergência e divergência:

#### Convergências

| Aspecto | sss.txt | handling-balancer |
|---------|---------|-------------------|
| Pré-processamento vs runtime | (não explicita, mas arquitetura Lua é server-side boot) | **OFFLINE pré-deploy** (alinhado a L-05/L-06; corrige o modelo runtime do sss.txt) |
| Tiers/categorias | 4 categorias (balanced, muscle, sport, drift) | 6 tiers (D..S+) com massBase 1100–1500kg |
| fDriveInertia reduzido p/ punir retomada | "1.0 → 0.85" | tiers.json: D=1.00, S+=1.40 (CRESCENTE, não decrescente) |
| fBrakeForce elevado p/ pesados | "0.85–1.10" | tiers.json: D=0.70, S+=1.20 (crescente com tier) |
| fTractionCurveMax alto p/ pesados grudar | "alto" | tiers.json: D=2.05, S+=2.80 (crescente) |
| Clamp de sanidade | "evaluateAndClamp" em Lua | `clamp(driveRaw, tier.drive*0.85, tier.drive*1.15)` em tiers.js |
| Validação tipo-defensiva | `type(value) ~= 'number'` → min seguro | `isNum(n) = typeof n === 'number' && Number.isFinite(n)` |
| Detecção de anomalia com log em cascata | `print("-> anomalia")` | `report.log.warn/erro` PT-BR com warnings por carro |

#### Divergências

1. **Massa NÃO escala drive force (decisão contrária ao sss.txt)**: o sss.txt descreve carros
   pesados precisando de `fInitialDriveForce 0.300–0.350` para "empurrar o peso". O `tiers.js`
   (comentário linhas 17–24) declara explicitamente: "Escalar driveForce por massa super-recompensa
   carros pesados — foi o bug da v2 do balancer. Por isso o alvo de drive force é o valor do TIER
   direto." **Decisão técnica documentada que diverge do sss.txt**, justificada pela física
   `a = F/m` (massa cancela). O sss.txt trata massa como variável de "punição" (carro pesado
   sofre na retomada); o balancer trata massa como identidade preservada (NÚCLEO-8 não inclui fMass).

2. **Categorias (4) vs tiers (6)**: sss.txt propõe 4 categorias semânticas (balanced/muscle/sport/drift).
   O balancer usa 6 tiers de performance (D..S+) sem distinção semântica de "estilo" (muscle vs sport).
   O `archetype` (rwd_heavy, awd_light, etc.) captura parte dessa semântica mas só em 2 dimensões
   (drivetrain + peso), não em "estilo de pilotagem" (drift vs circuito).

3. **Self-healing automático (sss.txt) vs blocking (balancer)**: o sss.txt propõe UPDATE dinâmico
   no boot para corrigir valores fora da banda. O balancer **NÃO** auto-corrigi em runtime — ele
   rebalanceia OFFLINE e bloqueia drift via CI (`verify` exit 1). Decisão arquitetural mais segura
   (sem SQL em runtime, alinhado a L-04 "uma fonte de verdade") mas menos reativa a dados corrompidos
   no banco.

4. **`fDriveInertia` decrescente (sss.txt) vs crescente (balancer)**: o sss.txt propõe REDUZIR
   `fDriveInertia` em carros pesados (1.0 → 0.85) para "marchas demorarem mais para encher" (punição
   na retomada). O balancer faz o CONTRÁRIO: `driveInertia` CRESCE com o tier (D=1.00, S+=1.40),
   dando aos tiers altos resposta de aceleração MAIS rápida. **Divergência de design clara**: o
   sss.txt quer punir o erro; o balancer quer recompensar o tier alto.

5. **`fDragMult` (sss.txt) vs `fInitialDragCoeff` (balancer)**: o sss.txt menciona `fDragMult 8.5–9.0`
   para a categoria Equilibrada perder do Muscle em reta. O balancer usa `fInitialDragCoeff` (11.5 D
   → 9.0 S+) — campo diferente mas conceito similar (paredão de arrasto). Crescente com tier (D freia
   mais cedo), o que é o oposto de "Muscle tem menos arrasto" — mas o Muscle seria tier S/S+ com
   drag 9.2, e o Equilibrado tier B/C com drag 10.0–10.5, então a relação se mantém indiretamente.

6. **`fBrakeBiasFront` e `fTractionBiasFront`**: o sss.txt menciona `fBrakeBiasFront 0.55` para
   carros pesados. A spec `script.md` §4 descrevia `brakeBiasFront` e `tractionBiasFront` por tier.
   **O NÚCLEO-8 NÃO inclui esses campos** — foram removidos na adoção do carskill.md v2.2. Divergência
   entre spec original (script.md §5.3) e implementação final.

### 13.3 Conclusão da comparação

O `handling-balancer` **não implementa** a filosofia do `sss.txt` literalmente, mas **a supera em
clareza arquitetural**:
- Move a validação de runtime (Lua + SQL) para build-time (Node + `.meta`) — alinhado a L-04/L-05/L-06
- Substitui 4 categorias semânticas por 6 tiers de performance + 6 arquétipos derivados (drivetrain×peso)
- Adota a decisão física `a = F/m` (massa cancela) em vez de escalar drive force por massa
- Adiciona camadas ausentes no sss.txt: selo sha256 + CI gate + backup + cirurgia byte-a-byte + web UI

**Divergências principais**:
1. `fDriveInertia` crescente (balancer) vs decrescente para pesados (sss.txt) — design oposto
2. Massa preservada (balancer) vs massa como variável de punição (sss.txt) — abstração diferente
3. Self-healing SQL bloqueado (balancer) vs auto-fix no boot (sss.txt) — defesa em camadas vs reatividade
4. Sem `fBrakeBiasFront`/`fTractionBiasFront` no NÚCLEO-8 (removidos vs spec original)

O `sss.txt` parece ser o documento **conceitual original** que motivou o `script.md` v1.0 → v2.0 →
(superado pelo `carskill.md` v2.2). A implementação atual reflete a **evolução** do pensamento,
não a cópia fiel.

---

## Apêndice A — Árvore de arquivos

```
handling-balancer/
├── package.json              # v1.0.0, commonjs, bin=vhub-balance, scripts npm
├── README.md                 # guia operacional (Fase 1)
├── script.md                 # spec v2.0.0 (518 linhas, parcialmente SUPERADO)
├── balance.js                # entrypoint: parse args + dispatch + exit codes
├── serve.js                  # atalho para `node balance.js serve`
├── commands/
│   ├── scan.js               # lista handlingNames reais, tier, órfãos, duplicatas (read-only)
│   ├── plan.js               # diff campo-a-campo + preview catalog-patch (read-only)
│   ├── apply.js              # backup + cirúrgico + selo + patch + build-report (ÚNICO que escreve)
│   ├── verify.js             # confere meta == selo; exit 1 em drift (CI gate)
│   ├── seal.js               # re-sela hashes atuais (pós-edição manual aprovada)
│   ├── restore.js            # restaura do backup mais recente
│   └── serve.js              # sobe web UI (sinaliza keepAlive)
├── lib/
│   ├── engine.js             # pipeline compartilhado scan→processar (sem escrita)
│   ├── io.js                 # I/O preserva bytes + glob + backup/restore
│   ├── meta.js               # parser cirúrgico (splitBlocks depth-aware + setValue regex)
│   ├── tiers.js              # resolveTargets + scoreToTier + reconcileTier (regras PURAS)
│   ├── seal.js               # sha256 + read/write seal.json + diff (drift detection)
│   ├── registryStore.js      # persiste decisões de tier no registry.json (UI ↔ CLI)
│   ├── carmod.js             # descoberta do mod completo (model token + metas irmãos + assets)
│   ├── audio.js              # diagnóstico + conserto de áudio custom (.awc/.rel/audioNameHash)
│   ├── catalogEmitter.js     # monta bloco p1 + grava out/catalog-patch.json
│   ├── config.js             # carrega + VALIDA config (ConfigError → exit 2)
│   ├── profiler.js           # fingerprint + score 0-1000 + tier calculado (read-only)
│   ├── report.js             # log PT-BR + renderDiff + build-report.json
│   ├── rename.js             # rename cirúrgico em todos os metas + assets (preview+backup)
│   ├── server.js             # servidor HTTP local + API JSON (web UI)
│   └── util.js               # norm/f6/clamp/isNum/r0 (helpers puros)
├── config/
│   ├── tiers.json            # Matriz-Ouro (6 tiers D..S+, 10 campos cada)
│   ├── registry.json         # 8 veículos classificados
│   ├── overrides.json        # vazio (schema pronto)
│   ├── archetypes.json       # 6 arquétipos + regra de derivação
│   └── scan-paths.json       # roots + exclude + matchFiles
├── web/
│   ├── index.html            # estrutura + template de card
│   ├── app.js                # lógica principal (vanilla JS)
│   ├── enhance.js            # UX: sidebar + radar + score-meter (IIFE não-toca app.js)
│   └── style.css             # dark premium (893 linhas)
├── out/
│   └── catalog-patch.json    # artefato gerado por apply (gitignore)
├── tmp/hbtest/carmod/zz/     # fixture de teste (carro ZZTEST)
│   ├── common/
│   │   ├── handling.meta     # 2 campos só (fMass + fInitialDriveForce)
│   │   ├── vehicles.meta     # InitDatas com 1 item
│   │   └── carvariations.meta
│   └── stream/zz/
│       ├── zztest.yft, zztest_hi.yft, zztest_spoil_1.yft, zztest.ytd
└── (gerados, gitignore)
    ├── .seal/seal.json       # hash selado por arquivo (commitado!)
    ├── .backups/<timestamp>/ # cópia byte-a-byte antes de cada apply
    └── build-report.json     # relatório por carro (tier, campos alterados, warnings)
```

---

## Apêndice B — Tabela de exit codes

| Código | Significado | Quando |
|--------|-------------|--------|
| `0` | OK | Sucesso em qualquer comando |
| `1` | Drift / divergência de selo | `verify` encontrou drift/unsealed/missing |
| `2` | Erro de config | `ConfigError` — tiers/registry/overrides/scan-paths inválido |
| `3` | Erro de I/O | `IoError` — arquivo em uso, backup inexistente, falha de escrita |

---

## Apêndice C — Referências cruzadas

- **`carskill.md` v2.2** (referenciado pelo README): spec do P1 Skill — define BUDGET (D=500..S+=1000),
  5 eixos (potencia/grip/frenagem/aero/suspensao), NÚCLEO-8, **§3.4 balde B** (autoridade do dono
  2026-06-15), **§1.5** (a ≈ 10 × fInitialDriveForce; massa cancela em a=F/m).
- **`vhub_vehcontrol/shared/tier_rules.lua`**: BUDGET D=500..S+=1000 (casa com `tiers.json.budget`),
  ALLOC_RANGE anti-P2W, PART_POINTS híbrido. Lê o catálogo do conce (que incluirá o bloco `p1` do
  catalog-patch na Fase 2).
- **`vhub_conce/shared/catalog.lua`** (Fase 2 ⏳): alvo da mesclagem manual do `catalog-patch.json`.
  Key = `modelName` minúsculo (casa com a convenção do patch).
- **`manual_dev_vhub.md`**: L-04 (uma fonte de verdade — balancer é build-time, não cria 2ª fonte
  em runtime), L-05/L-06 (zero impacto em resmon — `.meta` lido nativamente no boot), L-07 (lifecycle
  pré-deploy + CI), L-08 (identificadores EN, mensagens PT-BR).
- **`PLANO_IMPLEMENTACAO_VEICULOS.md`**: decisão #25 (conce é autoridade do catálogo — gate do merge
  do catalog-patch na Fase 2).

---

**Fim do documento** — `/home/z/my-project/workspace/analysis/07_handling_balancer.md`
