# Skill — Criar HUD de velocímetro por dial-spec (VeloDials)

> Padrão validado na Fase 1 do plano de padronização de velocímetros (2026-07-26). Motor de
> referência: `resources/[SCRIPTS]/vhub_velo/nui/velo-dials.js`. Flagship de referência:
> `nui/huds/carro/vrm_classic/` (spec.js + index.html thin + style.css de tema). Gates:
> `vhub_arquiteto` APROVOU o design; runtime/designer/simplicidade/contrato revisaram.

## Quando usar
Criar ou padronizar QUALQUER velocímetro de carro/moto do `vhub_velo`. **Não** para o `aero`
(bússola bespoke) nem para o `vrm_aut` (via legada, migra na Fase 3). A face NÃO é arte
pixel-a-pixel: é um `window.veloSpec` que o motor desenha.

## O padrão (por que existe)
O problema morto: face em SVG estático (`dashboard_fivem.svg`) com ticks/números/redzone
cravados no arquivo + ponteiros posicionados em **px na mão** → desalinham (setas/lock) e os
números ficam presos na arte (RPM parava em 8, teto 400). O `vrm_aut` já desenhava a face
proceduralmente, mas duplicado no próprio `script.js` + painel de config próprio.

**Solução:** `VeloDials.build(spec) → { speedPoints, rpmPoints, fuelPoints, anchors }`. O spec é a
**fonte única por dial**: o mesmo `range`/`arc` gera os ticks desenhados, a matemática do ponteiro
e a redzone — não podem discordar. Trocar teto/redzone = 1 número. Ponteiros ancorados no
CENTRO do dial (sem drift em px). Peças (nitro/odômetro/status/etc.) acopláveis por flag.

## Receita
1. Copie `nui/huds/carro/vrm_classic/` para `nui/huds/<cat>/<id>/`.
2. Edite só `spec.js` (os números). `index.html` é fixo: `VeloCore.init(VeloDials.build(window.veloSpec))`.
3. Registre 1 linha em `shared/config.lua` (`Config.Huds`).
4. `style.css` só se for trocar cor (tokens `--vf-*` em `#velo-root`); sem ele, defaults Mirage.

## Verdades de plataforma (pagas em revisão — não redescobrir)
- **CEF NÃO resolve `var()` em ATRIBUTO de apresentação SVG** (`stroke="var(--x)"`/`fill="var(--x)"`
  via setAttribute) → o elemento renderiza PRETO. Cor de SVG **sempre por CLASSE CSS**
  (`.vf-tk{stroke:var(--vf-tick)}`). Inline `element.style` e CSS resolvem var(); atributo não.
  Vale para qualquer SVG que você desenhar num `veloCustomRender`. Ver [[fivem-native-gotchas]].
- **CDN "preenche como o iPad"** = `background-size:cover` + `overflow:hidden` + `border-radius:50%`
  num layer full-bleed, dirigido por CSS var (`--velo-bg-<dial>`). NÃO usar `contain` (vira
  marca d'água) nem `mix-blend-mode:screen` (lava a foto). O motor já entrega isso via `backgrounds`.
- **Saúde do motor** = LED (`engine-health-dot`), ligado por `'engine'` no array `status`. NÃO existe
  `readouts.engineHealth` (era drift; foi removido). O velo-core seta `data-health` ok/warn/crit.
- **Nitro = dial PADRÃO com ponteiro** (`spec.dials.nitro` + `needles.nitro`), compacto, NÃO um arco/pod.
  O velo-core rotaciona `nitro-needle` (gauge derivado de `nitroPoints`). Sem redzone (é carga, não perigo).
- **Posição do painel** = canto inferior direito (`#velo-root` no velo-dials, `right/bottom:8px`); só o `aero`
  fica no topo (bespoke). Posição de peça dentro do painel = `c:[x,y]` do dial no spec.
- **`build()` é puro e re-entrante** (`root.innerHTML=''`); o preview fora do FiveM é do velo-core
  (`location.hostname` começa com `cfx-nui-`), NÃO do velo-dials. Não duplicar detecção de preview.
- **Ponteiro sem `color` no spec** herda `--velo-accent` (personalização do jogador). Com `color`
  fixo, ignora a personalização — use fixo só quando a cor for identidade do dial (ex.: RPM vermelho).

## Anti-padrões (REPROVAR)
- Reintroduzir arte SVG estática com número cravado (volta o drift + números presos na arte).
- Posicionar ponteiro/leitura em px na mão contra a face (o motor ancora no centro do dial).
- Segunda UI de config no HUD (o `/velo` da galeria é a única) — foi o pecado do `vrm_aut`.
- Cor de SVG por atributo `var()` (regra do CEF acima).

Ver [[vhub-velo-dials-engine]] e o manual `resources/[SCRIPTS]/vhub_velo/e-manual.md`.
