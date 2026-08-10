# vhub_velo — Manual: criar um velocímetro novo em 3 passos

> **A face do velocímetro agora é um SPEC, não uma arte pixel-a-pixel.** Você escreve um objeto
> `veloSpec` (os números do painel) e o motor `velo-dials.js` desenha tudo: moldura, ticks, números,
> redzone, ponteiros ancorados nos centros, slots de fundo por link (CDN) e as leituras digitais.
> O `velo-core.js` cuida da telemetria/gauge/odômetro/visibilidade. Você compartilha os dois motores
> e só entrega o **spec**.

---

## Passo a passo (0 Lua, ~5 min)

1. **Copie** `nui/huds/carro/vrm_classic/` → `nui/huds/<categoria>/<seu_id>/`.
2. **Edite `spec.js`** — mude os números (teto, redzone, dials, quais peças). É o único arquivo obrigatório.
3. **Registre 1 linha** em `shared/config.lua` → `Config.Huds["<categoria>"]` (id, name, path).
   (Opcional: `style.css` só se quiser trocar cores; sem ele, usa os defaults Mirage.)

Pronto. O `index.html` é fixo (3 scripts + init) e não precisa ser tocado:

```html
<script src="/nui/velo-core.js"></script>
<script src="/nui/velo-dials.js"></script>
<script src="spec.js"></script>
<script>
document.addEventListener('DOMContentLoaded', function () {
    VeloCore.init(VeloDials.build(window.veloSpec));   // desenha a face + liga a telemetria (mesma verdade)
});
</script>
```

---

## O SPEC (referência anotada)

```js
window.veloSpec = {
    canvas: [470, 235],                 // viewBox do painel (w,h). Ponteiros e leituras vivem nesse sistema.
    layout: 'tri',                      // 'tri' = fuel|speed|rpm tangentes (único layout na Fase 1)

    // -- DIALS: uma FONTE por dial. Estes números movem JUNTOS ticks + ponteiro + redzone. --
    //    DIAL PARTIDO (metade/metade): dois dials com a MESMA c/r e arcos complementares dividem UM
    //    círculo — o motor desenha 1 face + um divisor. Aqui fuel=cima [-90,90], nitro=baixo [90,270].
    dials: {
        //        centro     raio  escala        arco(0°=topo)   ticks minor  redzone
        fuel:  { c:[72,100],  r:46, range:[0,100], arc:[-90,90],   ticks:4,  minor:0, redBefore:20 },
        nitro: { c:[72,100],  r:46, range:[0,100], arc:[90,270],   ticks:4,  minor:0 },
        speed: { c:[210,100], r:92, range:[0,300], arc:[-135,135], ticks:6,  minor:5, redAfter:250 },
        rpm:   { c:[370,100], r:68, range:[0,10],  arc:[-135,60],  ticks:10, minor:0, redAfter:8 },
    },

    // -- PONTEIROS: len=comprimento, w=espessura, color?(omitir = usa --velo-accent do jogador) --
    needles: {
        fuel:  { len:30, w:2.5, color:'#37e0a1' },
        nitro: { len:30, w:2.5, color:'#00b4ff' },
        speed: { len:78, w:4 },
        rpm:   { len:54, w:3,   color:'#ff2a2a' },
    },

    backgrounds: ['fuel','speed','rpm'],   // dials que aceitam imagem por link (cover+clip, preenche sem vazar)

    readouts: { speedDigital:true, gear:true, fuelPercent:true, odometer:true, nitro:true },  // peças acopláveis

    status: ['turnLeft','lock','seatbelt','engine','turnRight'],   // 'engine' = LED de saúde do motor
};
```

**Campos:**
- `range` — mínimo/máximo do dial (a unidade real: km/h, RPM×1000, %). **Trocar o teto = mudar 1 número aqui.**
- `arc` — ângulos em graus, `0°` = topo, negativo = esquerda. Sweep típico: `[-135,135]` (270°).
- **Dial partido (metade/metade):** dê a **mesma `c` e `r`** a dois dials com arcos complementares
  (ex.: `[-90,90]` cima + `[90,270]` baixo) → o motor desenha **uma face + um divisor** e cada metade
  recebe seu ponteiro. É como fuel+nitro moram num só mostrador.
- `ticks` — quantos números/majores. `minor` — subdivisões finas entre eles (0 = nenhuma).
- `redAfter` — redzone a partir desse valor (alto: velocidade/RPM). `redBefore` — abaixo (baixo: combustível).
- `label` (opcional) — texto renderizado **DENTRO** da face (área inferior vazia), nunca fora da margem. Omita
  para o visual limpo (o flagship não usa: RPM/velocidade são autoexplicativos).
- `readouts`/`status` — presente = aparece, ausente = não monta. Nada de código pra ligar/desligar peça.
- **Posição na tela:** o painel fica no **canto inferior direito** (`#velo-root` no `velo-dials`, `right/bottom:8px`).
  Só o `aero` (bússola) fica no topo. Ajuste fino de posição de peça = mudar o `c:[x,y]` no spec.

---

## Contrato (o que o motor garante)

- **CDN por dial:** o jogador cola um link em `/velo`; a imagem preenche o miolo do dial (técnica do iPad:
  `cover` + `overflow:hidden` + círculo). Dirigido pelas CSS vars `--velo-bg-{speed,fuel,rpm}` (o velo-core seta).
- **Cor de destaque:** `--velo-accent` do jogador entra em todo ponteiro/realce sem `color` próprio (`--vf-accent`).
- **Tokens de tema** (todos com default Mirage, sobrescreva em `style.css` dentro de `#velo-root`):
  `--vf-accent · --vf-face · --vf-bezel · --vf-tick · --vf-tick-minor · --vf-red · --vf-nitro · --vf-cdn-op`.
- **IDs canônicos** emitidos pelo motor (o velo-core preenche null-safe): `vehicle-speed-prefix`/`vehicle-speed`,
  `vehicle-gear`, `vehicle-fuel`, `speed-needle`/`rpm-needle`/`fuel-needle`, `[data-odo-digit] .odoColumn`,
  `status-turn-left/right`, `status-seatbelt`, `status-lock`, `engine-health-dot`, `nitro-arc-fill`, `nitro-value`.

### ⚠️ Regra de ouro do SVG no CEF
Cor de elemento SVG **sempre por CLASSE CSS**, nunca por atributo `stroke="var(...)"`/`fill="var(...)"` — o CEF do
FiveM **não resolve `var()` em atributo de apresentação** (ticks/números saem pretos). O `velo-dials` já faz certo;
se você desenhar SVG extra num `veloCustomRender`, use classe + regra CSS.

---

## 🎯 Prompt perfeito (gerar um spec novo com IA)

Cole isto e preencha os `<...>`:

> Gere um `window.veloSpec` para o motor **VeloDials** do `vhub_velo` (layout `'tri'`, canvas `[470,235]`,
> dials tangentes `fuel(72,100 r46) · speed(210,100 r92) · rpm(370,100 r68)`).
> Requisitos deste velocímetro:
> - Velocidade: **0 a `<TETO_KMH>`**, redzone a partir de **`<REDZONE_KMH>`**, `<N>` números, subdivisões finas.
> - RPM: **0 a `<TETO_RPM>`** (×1000), redzone a partir de **`<REDZONE_RPM>`**.
> - Combustível: 0–100, redzone abaixo de **`<FUEL_BAIXO>`**.
> - Cor de destaque padrão: **`<HEX>`** (mas deixe o ponteiro de velocidade SEM `color` p/ herdar `--velo-accent`).
> - Peças: **`<liste: velocidade digital, marcha, %fuel, odômetro, nitro, setas, lock, cinto, LED de motor>`**.
> - Fundos por link nos dials: **`<quais>`**.
> Saída: só o objeto `window.veloSpec` comentado em PT-BR. Não escreva HTML/CSS/Lua — o motor cuida do resto.
> **Regra:** nenhuma cor de SVG por atributo (CEF não resolve `var()` em atributo — o motor já usa classe).

O motor deriva as curvas do gauge do próprio spec, então **os números que você pede são exatamente o que
aparece** — ticks, ponteiro e redzone não podem discordar.

---

## Checklist de QA antes de subir

- [ ] `spec.js` define `window.veloSpec` com `canvas`, `dials`, e as peças desejadas.
- [ ] `index.html` inclui `velo-core.js` + `velo-dials.js` + `spec.js` e chama `VeloCore.init(VeloDials.build(window.veloSpec))`.
- [ ] Registrado em `shared/config.lua` (`Config.Huds` + opcional `Config.DefaultHuds`).
- [ ] Preview no navegador (abra `index.html` — fora do FiveM o velo-core mostra valores de exemplo).
- [ ] `/velo` no jogo troca o HUD e aceita link de imagem (preenche o dial, não vaza).
- [ ] Nenhuma cor de SVG por atributo `var()` (regra do CEF acima).

---

## O que fica de fora (por enquanto)
- `layout:'mono'` (moto) e `'digital'` (bike) — Fase 3 (o motor ganha esses ramos + migração de `moto`/`bike`).
- `vrm_aut` ainda é a via ANTIGA (SVG inline + painel próprio), marcado LEGADO no `script.js` — migra na Fase 3.
- `aero` (bússola de heli/avião/barco) é bespoke por design e permanece como está.
