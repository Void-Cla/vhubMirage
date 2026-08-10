# Baseline de veículos NATIVOS (ADR #85 F2.5-C)

> Como dar a um carro **nativo** do GTA o mesmo `p1` (DNA de engenharia) que os mods recebem —
> **sem fabricar números** e **sem criar um segundo balanceador**.

## O que já está resolvido (não precisa de C para funcionar)

A **ADR #85 F2.5-A** desacoplou instalação de peça do `p1`: o gate agora é **compatibilidade**
(`Core.resolvePartStatus`/`VHubCustom.Compat`), não o `stageCap`/`class_budget`. Consequência direta:

> **Um carro nativo já instala e remove qualquer peça compatível hoje**, mesmo sem `p1`.
> O `stageCap` virou apenas `hint`. A instalabilidade não depende de `p1`.

## Baseline DEFAULT por stats (IMPLEMENTADO — F2.5-C runtime)

Além da instalabilidade, **todo carro do catálogo agora ganha ficha derivada** (score/tier/`sheet.eng`/
`sheet.mass`) mesmo sem `p1` explícito: `Config.defaultBaselineFromStats = true` (vhub_vehcontrol)
faz `TR.defaultP1(entry)` computar um baseline JUSTO a partir dos `stats` autorados no catálogo
(vel/acel/freio/dir → classe D..S+, `base_alloc` balanceado, `mass` = massBase do tier). Assim nativo
e mod entram no MESMO sistema de classes — anti-P2W, sem inventar número (usa o desempenho autorado).

> O **`p1` explícito (balancer/.meta selado) SEMPRE vence** o default. Este bloco (`native.md`) é o
> caminho de **precisão**: gerar `p1` real dos nativos que você quer cravar, em vez de confiar no
> default por stats. Kill-switch: `defaultBaselineFromStats=false` volta ao fail-closed.

## Por que não dá para gerar `p1` de nativo offline hoje

O `handling-balancer` lê `handling.meta` do disco e **já emite tudo que um baseline precisa**
(`base_alloc`, `mass` de `fMass`, `archetype`, `drive_bias`, etc. — ver `lib/catalogEmitter.js`).
O problema é **a fonte**: o `handling.meta` dos veículos **nativos** vive no **base game**
(`update.rpf/common/data/handling.meta`), **não no repositório**. Sem esse dado, gerar `base_alloc`
ou `mass` para um nativo seria **inventar número** — proibido (prompt §10/§34). Então C precisa de
uma das duas fontes REAIS abaixo.

## Pipeline honesto (escolha uma fonte de dados)

### Opção A — `handling.meta` nativo (offline, recomendado)

1. Obtenha o `handling.meta` nativo do GTA (dado público; **não** commitar no repo — asset do jogo).
2. Aponte o `scan-paths.json` para ele (ou copie os blocos `<Item CHandlingData>` dos modelos desejados
   para um `.meta` de trabalho).
3. Classifique cada modelo nativo em `config/registry.json` (`handlingName` UPPERCASE → `tier_base`/`tier_max`).
   Essa é a decisão HUMANA de tier (o balancer calcula um sugerido; você confirma).
4. `node balance.js plan --only <MODELOS>` → confira; `node balance.js apply` → gera `out/catalog-patch.json`.
5. Cole o bloco `p1` de cada nativo no `resources/[SCRIPTS]/vhub_conce/shared/catalog.lua` (dono do `p1`).

### Opção B — captura in-game (quando o `.meta` nativo não estiver à mão)

Um comando de dev (a construir, sob gate do `vhub_arquiteto` — é um módulo novo com ownership L-07)
spawna cada modelo, lê o handling REAL via natives client-side (`GetVehicleHandlingFloat('fMass')`,
`fDriveBiasFront`, etc.) e escreve um dump no MESMO formato do bloco `p1`. O humano revisa e cola no
`catalog.lua`. **Não** roda em runtime de produção; é ferramenta de dev. Dado é REAL (lido do jogo),
nunca inventado.

## Forma do `p1` que o nativo precisa (idêntica à do mod)

```lua
NATIVE_MODEL = { nome='...', tipo='car', categoria='...', ...,
  p1 = { handling_name='<handlingId nativo>', class_budget='<D..S+>', tier_max='<D..S+>',
         mass=<fMass real>, base_alloc={ potencia=…, grip=…, frenagem=…, aero=…, suspensao=… } } },
```

- `mass` alimenta `sheet.mass` (ADR #85 F2.5-B) — peso derivado na oficina.
- `base_alloc` deve **somar exatamente** o `budget` do `class_budget` (D=500…S+=1000) — o
  `catalogEmitter` já garante isso (`balancedAlloc`), e o `tier_rules` rejeita soma divergente.
- `class_budget` é o nome canônico (ADR #82); o balancer ainda emite `tier_base` como **shim R15**
  (`VHubVeh.budgetKey` aceita ambos) — ao colar, prefira `class_budget` para casar com o catálogo atual.

## Limite honesto (registrado)

Com `defaultBaselineFromStats=true`, nativos NÃO ficam mais sem ficha — ganham baseline por stats.
Esse default é JUSTO mas **coarse**: deriva da nota de desempenho autorada (0..100), não do handling
físico real. Para precisão fina (afinidade por drivetrain, massa real, curva de tração), use a
Opção A/B acima para gerar `p1` explícito — que **vence** o default. Nenhum número é inventado:
o default vem dos `stats` autorados; o `p1` explícito vem do `.meta`/captura real.
