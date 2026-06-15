# vhub_velo — Velocímetro Modular (HUD de display do veículo)

Engine universal + HUDs isolados por iframe, escolhíveis e **personalizáveis** por categoria.
**vhub_velo é PURO CONSUMIDOR**: lê bags (`vh_fuel`/`vh_odo`/`vhub_seatbelt`) + natives e exibe.
Nunca escreve verdade (sem 2ª fonte). O controle do veículo e a persistência vivem no `vhub_vehcontrol`/CORE.
**Há apenas UM velocímetro na tela** — o que o jogador escolheu por categoria (carro/moto/aero).

## Como funciona
1. **`client/main.lua`** lê a telemetria (com dedup), detecta a categoria do veículo, envia
   `velocimetro:update` à NUI e aplica a personalização salva (`velocimetro:config`). Preferências por
   jogador via **KVP** (sem server): `vhub_velo:<cat>` (HUD), `vhub_velo:bg:<cat>` (fundo), `vhub_velo:accent:<cat>` (cor).
2. **`nui/index.html` + `velo-controller.js`** = host: carrega o HUD escolhido num **iframe isolado**,
   repassa telemetria/config e gerencia a galeria `/velo` (trocar HUD + personalizar).
3. **`nui/velo-core.js`** = engine universal (gauges binary-search, odômetro RAF que para quando inativo,
   render null-safe, `applyConfig` p/ fundo+cor). HUDs bespoke (moto/aero) tratam o contrato por conta própria.

## Contrato NUI (todo HUD escuta isto)
- `velocimetro:update` — `e.data.data` = `speed_kmh, rpm_percent, gear_label, fuel_percent, odometer_km,
  turn_left, turn_right, seatbelt, locked, heading` (+ `visible`/`active`).
- `velocimetro:config` — `e.data.data` = `{ bg, accent }` (personalização do jogador). velo-core aplica como
  CSS vars `--velo-bg` (url do fundo) e `--velo-accent` (cor). O HUD opta usando `var(--velo-bg)`/`var(--velo-accent)`.

## Personalização (`/velo`)
No veículo, `/velo` abre a galeria: trocar o HUD da categoria + **colar um link de imagem para o fundo**
(PNG/JPG/WEBP/GIF via http(s)) + escolher a **cor de destaque**. É por jogador (KVP), só você vê.
A URL é validada no client (`^https?://` + extensão de imagem) antes de salvar.

## Criar um HUD novo — LINHA DE PRODUÇÃO (2 passos, zero Lua)
1. **Copie `nui/huds/_template/`** → `nui/huds/<categoria>/<seu_nome>/`. Edite só o CSS/markup.
   O template já traz: raiz `#velo-root`, todos os IDs padrão, fundo `var(--velo-bg)`, cor `var(--velo-accent)`,
   `veloCustomRender` opcional, e o `VeloCore.init()`. O glob do fxmanifest cobre a pasta nova.
   - **IDs padrão** (use os que quiser — velo-core ignora os ausentes): `vehicle-speed-prefix`+`vehicle-speed`,
     `vehicle-gear`, `speed-needle`, `rpm-needle`, `fuel-needle`, `[data-odo-digit] .odoColumn` (6×),
     `status-turn-left/right`, `status-seatbelt`, `status-lock`.
   - **Curvas de ponteiro** (opcional): `window.veloOpts = { speedPoints:[[0,-135],[400,135]], fuelPoints:[...] }`.
2. **Registre 1 linha** em `shared/config.lua` → `Config.Huds["<categoria>"]`:
   ```lua
   { id = "meu_hud", name = "Meu HUD", path = "huds/carro/meu_hud/index.html" },
   ```
   (O `_template` NÃO é registrado — por isso não aparece na galeria.)

## Comando
- `/velo` (no veículo): galeria para trocar o HUD da categoria atual + personalizar fundo/cor (persiste por KVP).
