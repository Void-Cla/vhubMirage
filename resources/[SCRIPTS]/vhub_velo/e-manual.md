# vhub_velo — Manual para criar e instalar HUDs de velocímetro

Este manual descreve o padrão, os contratos NUI e o passo-a-passo para criar/instalar novos HUDs de velocímetro no `vhub_velo`.

Resumo rápido
- Canvas base: SVG 470 x 235 (layout tangente: FUEL 72,100 r=46; SPEED 210,100 r=92; RPM 370,100 r=68)
- Camadas (z-index crescente):
  1. `.custom-bg-container` (logos / fotos por mostrador)
  2. `svg.velo-bg` (moldura, ticks, letras, ícones de status)
  3. `.needle` / `.pivot` (ponteiros e eixos)
  4. `.speedometerOverlay` (leitura digital: %, km/h, marcha, odômetro)
- Engine comum: incluir `/nui/velo-core.js` e chamar `VeloCore.init(opts)` no `DOMContentLoaded`.

IDs e contrato (obrigatórios / recomendados)
- IDs que o engine reconhece (null-safe — pode faltar alguns):
  - `vehicle-speed-prefix` (dois dígitos à esquerda)
  - `vehicle-speed` (último dígito da velocidade)
  - `vehicle-gear` (marchas)
  - `speed-needle`, `rpm-needle`, `fuel-needle` (ponteiros)
  - `vehicle-odometer` (container simples) ou `[data-odo-digit] .odoColumn` (6 colunas rolantes)
  - `status-turn-left`, `status-turn-right`, `status-seatbelt`, `status-lock`, `status-engine`
- Mensagens recebidas pelo iframe (host → HUD):
  - `velocimetro:update` — `{ data: { speed_kmh, rpm_percent, gear_label, fuel_percent, odometer_km, turn_left, turn_right, seatbelt, locked, heading } }`
  - `velocimetro:config` — `{ data: { bgFuel, bgSpeed, bgRpm, accent, ... } }` (config do jogador)
  - `velocimetro:openConfig` — abre o painel /velo; payload inclui `category` e `data` com config atual
- Endpoints do HUD → host (fetch `https://${resource}/<name>`):
  - `velo:saveConfig` — salvar config (ex.: `{ category, bgFuel, bgSpeed, bgRpm, accent }`)
  - `velo:saveHud` — salvar preferência de HUD (via galeria) — já tratado pelo host
  - `velo:closeConfig` — fecha painel e desfoca NUI
  - `focar` — compatibilidade: host aceitará `{ focar = true/false }` (legacy)

Estrutura mínima de um HUD
```
nui/huds/<categoria>/<id>/
  index.html    ← inclui /nui/velo-core.js + markup SVG/DOM (IDs padrão)
  style.css     ← visual e camadas (custom-bg z-index baixo; needle z-index alto)
  assets/...    ← ícones, imagens locais opcionais
```

Passo-a-passo: criar um HUD novo
1. Copie `nui/huds/_template/` para `nui/huds/<categoria>/<seu_hud>/`.
2. Edite `index.html` (somente markup/CSS/pequena lógica), preserve:
   - inclusão de `/nui/velo-core.js` e `VeloCore.init(window.veloOpts || {})` no `DOMContentLoaded`.
   - IDs canônicos (ou mapeie via `window.veloCustomRender`).
3. Ajuste `style.css` para respeitar as camadas:
   - `.custom-bg-container` (z-index baixo) — use `background-image` para logos por mostrador
   - `.velo-bg` (SVG) — ticks e moldura
   - `.needle` / `.pivot` — ponteiros (transform-origin = 50% 100%)
   - `.speedometerOverlay` — leitura digital (z-index mais alto)
4. Se precisar de lógica extra a cada update, defina `window.veloCustomRender = function(state) { ... }` — o engine chama a cada `velocimetro:update`.
5. Se quiser aceitar personalização por slot (bgFuel/bgSpeed/bgRpm), implemente uma função que aplique `payload.data` do `velocimetro:config`.
6. Teste no navegador (preview mode): o engine aplica valores de exemplo fora do FiveM.

Como o engine (`/nui/velo-core.js`) ajuda
- Geração de `gauge` (mapeamento valor → ângulo) via `VeloCore.createGauge` (padrão aplicado com `VeloCore.init`).
- Recebe `velocimetro:update` e aplica needles/texts/estados null-safe.
- Gerencia odômetro (suporta markup rolante com `[data-odo-digit] .odoColumn` e fallback simples `#vehicle-odometer`).
- `VeloCore.applyConfig(obj)` aplica `--velo-bg` e `--velo-accent` e chama `window.veloOnConfig(obj)` se definido (hook para HUD aplicar logos por mostrador).

Persistência e /velo (Galeria)
- Preferência por jogador por categoria armazenada em KVP JSON: `vhub_velo:config:<category>` contendo `{ bgFuel, bgSpeed, bgRpm, accent }`.
- O host fornece a configuração ao HUD via `velocimetro:config` e `velocimetro:openConfig`.
- Ao salvar no HUD, chame `fetch('https://${res}/velo:saveConfig', { method:'POST', body: JSON.stringify({ category, bgFuel, bgSpeed, bgRpm, accent }) })`.

Checklist de QA antes de subir
- [ ] HUD inclui `/nui/velo-core.js` e chama `VeloCore.init()`.
- [ ] IDs padrão estão presentes ou `window.veloCustomRender` cobre as diferenças.
- [ ] Camadas respeitam a ordem: logos → SVG → needles → overlay.
- [ ] Preview (abrir `index.html` no navegador) mostra valores de exemplo.
- [ ] `/velo` abre o painel e salva configuração (verificar KVP via host).

Exemplo mínimo de `index.html` (template já disponível em `nui/huds/_template`).

---

Se quiser, eu já posso:
- criar um HUD de exemplo novo usando o template (por ex. `nui/huds/carro/vrm_moderno`), ou
- validar e ajustar um HUD existente (`vrm_aut`) para o padrão e gerar screenshots de comparação.

Fim do manual.
