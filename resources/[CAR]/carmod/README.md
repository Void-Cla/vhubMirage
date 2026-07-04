# carmod

Resource ÚNICO para veículos add-on, com streaming **dinâmico** (glob).
Adicionar carro = soltar a pasta + 1 linha no catálogo. **Não edite o `fxmanifest.lua`.**

## Adicionar um carro novo (3 passos)

1. **Solte a pasta do carro** em `resources/[SCRIPTS]/carmod/<nome>/`.
   O `fxmanifest` pega os metas e os modelos **sozinho** (glob `**`). Aceita os dois layouts:
   - `carmod/<nome>/stream/...` + `carmod/<nome>/common/*.meta`  ← solta a pasta do mod como veio
   - `carmod/stream/<nome>/...` + `carmod/<nome>/common/*.meta`  ← layout atual (skyline/supra)

   Metas reconhecidos (em `common/`, `data/` ou na raiz da pasta): `vehicles.meta`,
   `handling.meta`, `carcols.meta`, `carvariations.meta`, `vehiclelayouts.meta` (opcional).
   `dlctext.meta` é ignorado (não é preciso para add-on).

2. **Aponte no catálogo** `resources/[SCRIPTS]/vhub_conce/shared/catalog.lua`:
   a chave = `<modelName>` do `vehicles.meta` **em minúsculo**. Ex.:
   ```lua
   skyline = { nome='Nissan Skyline R34', preco=380000, tipo='car', categoria='sport',
               stats={vel=88,acel=86,freio=76,dir=84}, tags={'mod'} },
   ```

3. **Reinicie:** `restart carmod` e `restart vhub_conce` (catálogo). Pronto — está à venda.

> O `atualizar_manifest.ps1` ficou **obsoleto** (o glob substitui). Pode apagar.

## Áudio do motor

- O som vem do `<audioNameHash>` no `vehicles.meta`. Hoje skyline=`ELEGY2`, supra=`JESTER3`
  (carros de fábrica) → o motor **já tem som** assim que os metas carregam.
- Para mudar o timbre sem áudio custom: troque o `<audioNameHash>` por outro carro base
  (ex.: `SULTAN`, `KURUMA`, `BANSHEE`, `COMET`, `ZR380`).
- **Os `.wav` da pasta `audio/` NÃO funcionam sozinhos** — são fonte crua. Áudio custom real
  exige um pacote FiveM compilado (`.awc` + `.dat151.rel`/`.dat54.rel`), que é outro fluxo
  (ferramentas tipo CodeWalker). Pode apagar a pasta `audio/` se não for compilar.

## Regras

- `config/resources.cfg` usa apenas `ensure carmod`. **Nunca** `ensure` por carro.
- Não coloque carros dentro de outro resource (ex.: `vhub_conce/`): qualquer pasta `stream/`
  vira streaming daquele resource → **modelo duplicado** = carro não carrega.
- `vhub_conce` é dono do catálogo/preço; `carmod` só faz o streaming dos arquivos.
