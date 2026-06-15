# vhub_velo — Sistema de Velocímetro Modular (PLANO MELHORADO)

> Resolve o conflito do rascunho original (que integrava o velocímetro DENTRO do `vhub_vehcontrol`).
> **Decisão do arquiteto (2026-06-04): SEPARAR.** `vhub_velo` é o dono ÚNICO do HUD de display do
> veículo; `vhub_vehcontrol` cede o velocímetro e volta a ser só CONTROLE + sync de persistência.

## Princípios (ownership / L-04)
- **vhub_velo = PURO CONSUMIDOR de display.** Lê bags `vh_fuel`/`vh_odo` (CORE escreve), `vhub_seatbelt`
  (vehcontrol escreve) e natives efêmeros (speed/rpm/gear/heading/indicadores/trava). **NUNCA escreve**
  bag, nem `setVData`, nem persiste odômetro. O odômetro de exibição integra local com o bag como PISO.
- **CORE** segue escritor único do físico (`vh_vehicle_data`, bags). **vehcontrol** segue dono do
  controle + da cadeia `vEnter/vLeave` (decisão #21 — a que faz odo/fuel persistir). Intocados.
- **Preferência de HUD = KVP client-side** (`GetResourceKvpString`/`SetResourceKvp`): dado de UI por
  jogador, não-crítico, sem server. (Remove o `server/main.lua` fantasma do manifest.)

## Arquitetura (engine PORTADA, não reescrita)
O engine superior já existe e funciona: `vhub_vehcontrol/html/script-velocimetro.js` (binary-search
O(log n), odômetro RAF que PARA quando inativo, normalize null-safe, preview `cfx-nui-`). Ele é
**portado** para `nui/velo-core.js`; o `core.js` linear atual (97 LOC, inferior) é descartado.

```
vhub_velo/
  shared/config.lua          ← VehicleCategories(classe→cat) + Huds + DefaultHuds  [PATHS CORRIGIDOS]
  client/main.lua            ← L2: telemetria (bags+natives+dedup+heading) + categoria→loadHud
                                + /velo (galeria) + NUICallback velo:saveHud (KVP) + reset no leave + L-06 guard
  nui/
    index.html               ← L3 host: 1 iframe #hud-frame (pointer-events:none) + painel /velo (IIFE, sem onclick inline)
    velo-core.js             ← L3 engine portado (incluído por TODA HUD via /nui/velo-core.js root-relative)
    huds/<cat>/<id>/index.html ← L4: cada HUD = IDs padrão + CSS próprio + inclui velo-core.js (isolado por iframe)
  fxmanifest.lua             ← SEM server_scripts; files com glob das HUDs
```

### Contrato NUI (Lua → CEF)
| type | payload | nota |
|------|---------|------|
| `velocimetro:loadHud` | `{ path, category, hudId, huds }` | host troca `iframe.src`; popula galeria |
| `velocimetro:toggle`  | `{ visible }` | host mostra/esconde o iframe |
| `velocimetro:update`  | `{ data:{ speed_kmh, rpm_percent, gear_label, fuel_percent, odometer_km, turn_left, turn_right, seatbelt, locked, heading } }` | host repassa ao iframe; velo-core renderiza |
| `velocimetro:openConfig` | `{ category, huds }` | host abre a galeria (SetNuiFocus só aqui) |

NUICallback `velo:saveHud {category,hudId}` → `SetResourceKvp('vhub_velo:'..cat, hudId)` (valida tipos).

### IDs DOM padrão (uma HUD usa os que precisar; velo-core é null-safe)
`vehicle-speed-prefix`+`vehicle-speed` · `vehicle-gear` · `speed-needle` · `rpm-needle` · `fuel-needle` ·
`[data-odo-digit] .odoColumn` · `status-turn-left/right` · `status-seatbelt` · `status-lock` ·
`heading-deg`/`heading-card` (aero, via `veloCustomRender`).

## Fases (gated)
- **VELO-1 (foundation):** corrigir `shared/config.lua` (paths reais), `fxmanifest.lua` (tirar server fantasma),
  reescrever `client/main.lua` (telemetria por bag + dedup + heading + KVP + L-06). Gates: simplicidade, contrato, runtime.
- **VELO-2 (engine+HUDs):** portar `velo-core.js`, reescrever `nui/index.html` (host limpo), padronizar HUDs
  (vrm_classic/moto/aero) com IDs padrão. Gates: runtime, designer, natives.
- **VELO-3 (remover do vehcontrol):** SÓ após VELO-2 **validado em runtime** (senão fica sem velocímetro nenhum).
  Remove de `vhub_vehcontrol`: `client/velocimetro.lua`, `html/script-velocimetro.js`, `html/style-velocimetro.css`,
  `html/dashboard_fivem.svg`, o `<main id="velocimetro">` do `html/index.html` e as refs no manifest. Gate: revisao.

## Riscos / paradas
- 2 velocímetros simultâneos na transição (vehcontrol + velo) — aceitável (ambos passivos); resolver na VELO-3.
- `heading` muda todo frame em aero → dedup com threshold `floor(h/2+0.5)*2` (senão spamma a 80ms parado).
- iframe: manter `pointer-events:none`; SetNuiFocus só no painel /velo.
- **PARAR** se o velo escrever qualquer bag/`setVData` (2ª fonte) ou se animação rodar com NUI fechada (idle>0).
