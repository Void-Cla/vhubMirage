# [mapas]

Categoria de mapas. **Cada mapa é um resource próprio** (com seu `fxmanifest.lua`) —
é o padrão FiveM (igual aos exemplos em `exemplos de base/big/resources/[mapas]`).

## Adicionar um mapa (2 passos)

1. **Solte a pasta do mapa** aqui: `resources/[mapas]/<nome>/`
   - Se o mod **já vem com `fxmanifest.lua`** (a maioria): solte como veio, não mexe em nada.
   - Se o mod **não tem `fxmanifest.lua`** (OpenIV `.rpf` / replace solto): extraia os
     arquivos do jogo pra `<nome>/stream/` e crie um `fxmanifest.lua` mínimo:
     ```lua
     fx_version 'cerulean'
     game 'gta5'
     this_is_a_map 'yes'
     ```
2. **Adicione no `config/resources.cfg`** (seção Mapas): `ensure <nome>` e dê `restart`.

## Por que cada mapa é um resource (e não um pacote único tipo carmod)

Cada mapa traz `data_file` específicos (colisão `COLLISION_FILE`, archetypes `.ytyp`,
proxies de interior). Esses ficam no `fxmanifest.lua` do autor — juntar tudo num resource
genérico quebra colisão/interior. Por isso mapa = 1 resource cada (≠ carros, que compartilham
o mesmo formato de meta e cabem num pacote só).

## Avisos comuns no console (e como resolver)

- `could not find client_script client.lua` → o manifest declara um script que não existe.
  Mapa não tem script: **apague a linha** `client_script '...'` do manifest.
- `could not find file meta/gtxd.meta` (ou `.meta` qualquer) → `data_file`/`file` apontando
  pra arquivo que não veio. Se o arquivo não existe na pasta, **apague essas duas linhas**.
- `DLC_ITYP_REQUEST` apontando pra `.ytyp` errado (ex.: `schoolmoe.ytyp` num mapa que tem
  `dep_xxx.ytyp`) → **corrija o caminho** para o `.ytyp` que existe em `stream/`. Se não
  corrigir, os props/MLO do mapa não carregam.
- `Asset X.ytd uses NN MiB of physical memory. Oversized assets WILL lead to streaming
  issues` → textura **grande demais** (acima de ~16 MiB). Abra o `.ytd` no **OpenIV** ou
  **CodeWalker**, reduza a resolução das texturas (ex.: 4096→2048) e salve. É o único jeito
  (não dá pra resolver no manifest) e é importante: textura gigante derruba carregamento.
- `__resource.lua` (manifest legado) + `fxmanifest.lua` juntos → o FiveM usa o `fxmanifest.lua`.
  Deixe **só o `fxmanifest.lua`** (apague o `__resource.lua`) pra evitar confusão.

## Mapas atuais

- `blodline` — chop shop sc1 (Hayes Autos). Resource com fxmanifest do autor (tem `COLLISION_FILE`).
- `conce1`  — retextura da loja do Simeon (replace puro de textura/modelo; sem `.ymap`/`.ytyp`).
- `depzitamadasptlnd` — mapa com props/MLO (`.ytyp`). Manifest corrigido (apontava `.ytyp` errado +
  `client.lua`/`gtxd.meta` inexistentes). ⚠️ tem 1 textura de 96 MiB — downscale recomendado (OpenIV).
