// velo-dials.js — builder DECLARATIVO de face de velocímetro a partir de um "dial spec".
// SEM estado de jogo (L-04): só desenha SVG + posiciona peças. SEM listener/RAF (cleanup dispensado, A-07).
// Consumido por HUDs: <script src="/nui/velo-core.js"> + <script src="/nui/velo-dials.js"> + <script src="spec.js">.
//
// CONTRATO PÚBLICO: VeloDials.build(spec[, mount]) → { speedPoints, rpmPoints, fuelPoints, anchors }
//   - Monta a face (bezel/ticks/números/redzone), os slots CDN (cover+clip estilo iPad), os ponteiros
//     ancorados nos CENTROS dos dials (fim do drift em px) e as leituras digitais — TUDO a partir do spec.
//   - Deriva as curvas de gauge do MESMO spec (uma fonte por dial): o HUD passa o retorno a VeloCore.init().
//
// SPEC canônico (ver e-manual.md / spec.js dos HUDs):
//   { canvas:[w,h], layout:'tri',
//     dials:{ speed|rpm|fuel: { c:[x,y], r, range:[min,max], arc:[a0,a1], ticks, minor, redAfter|redBefore, label } },
//     needles:{ speed|rpm|fuel:{ len, w, color? } },
//     backgrounds:[ 'fuel','speed','rpm' ],
//     readouts:{ speedDigital, gear, fuelPercent, odometer, nitro },
//     status:[ 'turnLeft','lock','seatbelt','engine','turnRight' ] }   // 'engine' = LED de saúde do motor
//
// IDs DOM emitidos = os canônicos do velo-core (null-safe): vehicle-speed-prefix/vehicle-speed,
// vehicle-gear, vehicle-fuel, speed-needle/rpm-needle/fuel-needle, [data-odo-digit] .odoColumn,
// status-turn-left/right, status-seatbelt, status-lock, engine-health-dot, nitro-arc-fill, nitro-value.

(function () {
    'use strict';

    const NS = 'http://www.w3.org/2000/svg';
    const EPS = 1e-6;


    // ============================================================
    // HELPERS DE GEOMETRIA
    // ============================================================

    // ponto polar num dial: ângulo em graus, 0° = topo, negativo = horário-esquerda (igual ao rotate do ponteiro)
    function polar(cx, cy, r, deg) {
        const rad = deg * Math.PI / 180;
        return { x: cx + r * Math.sin(rad), y: cy - r * Math.cos(rad) };
    }

    // valor → ângulo dentro do arco do dial (linear)
    function angleOf(d, value) {
        const [lo, hi] = d.range, [a0, a1] = d.arc;
        const t = (hi - lo) === 0 ? 0 : (value - lo) / (hi - lo);
        return a0 + (a1 - a0) * t;
    }

    // um valor cai na redzone? (redAfter = alto demais; redBefore = baixo demais, ex.: combustível)
    function isRed(d, value) {
        if (typeof d.redAfter === 'number')  return value >= d.redAfter - EPS;
        if (typeof d.redBefore === 'number') return value <= d.redBefore + EPS;
        return false;
    }

    function el(tag, attrs, parent) {
        const e = document.createElementNS(NS, tag);
        if (attrs) for (const k in attrs) e.setAttribute(k, attrs[k]);
        if (parent) parent.appendChild(e);
        return e;
    }
    function div(cls, parent) {
        const e = document.createElement('div');
        if (cls) e.className = cls;
        if (parent) parent.appendChild(e);
        return e;
    }
    // posiciona (px, sistema do canvas) um elemento absoluto pelo seu centro
    function place(node, x, y) { node.style.left = x + 'px'; node.style.top = y + 'px'; }


    // ============================================================
    // FACE SVG — bezel + fundo escuro por dial (camada z1, sob a imagem CDN)
    // ============================================================

    function buildFace(spec, shell) {
        const svg = el('svg', { class: 'vf-face', viewBox: `0 0 ${spec.canvas[0]} ${spec.canvas[1]}`,
                                preserveAspectRatio: 'xMidYMid meet' }, shell);
        const seen = {};
        for (const key in spec.dials) {
            const d = spec.dials[key], [cx, cy] = d.c, ck = cx + ',' + cy + ',' + d.r;
            if (seen[ck]) { seen[ck]++; continue; }   // dials que dividem o mesmo círculo = 1 face
            seen[ck] = 1;
            // cores via CLASSE (não atributo): CEF não resolve var() em atributo de apresentação SVG
            el('circle', { class: 'vf-ring', cx, cy, r: d.r, 'stroke-width': 2 }, svg);
            el('circle', { class: 'vf-ring-in', cx, cy, r: d.r - 6, 'stroke-width': 1 }, svg);
        }
        // divisor horizontal onde 2+ dials dividem o círculo (mostrador partido metade/metade)
        for (const key in spec.dials) {
            const d = spec.dials[key], [cx, cy] = d.c, ck = cx + ',' + cy + ',' + d.r;
            if (seen[ck] >= 2) {
                el('line', { class: 'vf-div', x1: (cx - d.r + 4).toFixed(1), y1: cy, x2: (cx + d.r - 4).toFixed(1), y2: cy, 'stroke-width': 1.5 }, svg);
                seen[ck] = 0;   // um divisor por círculo
            }
        }
    }


    // ============================================================
    // TICKS + NÚMEROS + REDZONE — camada z3 (SOBRE a imagem CDN, sempre legível)
    // ============================================================

    function buildTicks(spec, shell) {
        const svg = el('svg', { class: 'vf-ticks', viewBox: `0 0 ${spec.canvas[0]} ${spec.canvas[1]}`,
                                preserveAspectRatio: 'xMidYMid meet' }, shell);

        for (const key in spec.dials) {
            const d = spec.dials[key], [cx, cy] = d.c, [a0, a1] = d.arc, [lo, hi] = d.range;
            const steps = d.ticks || 6, minor = d.minor || 0, span = a1 - a0;
            const majorLen = Math.max(6, d.r * 0.12), minorLen = majorLen * 0.5, labelInset = majorLen + 10;
            const showLabel = d.r >= 55;   // dial pequeno (fuel) não recebe número, só ticks

            for (let i = 0; i <= steps; i++) {
                const t = i / steps, ang = a0 + span * t, val = lo + (hi - lo) * t, red = isRed(d, val);
                const pi = polar(cx, cy, d.r - majorLen, ang), po = polar(cx, cy, d.r, ang);
                el('line', { class: red ? 'vf-tk-red' : 'vf-tk', x1: pi.x.toFixed(1), y1: pi.y.toFixed(1),
                             x2: po.x.toFixed(1), y2: po.y.toFixed(1), 'stroke-width': 2, 'stroke-linecap': 'round' }, svg);

                if (minor && i < steps) {
                    for (let k = 1; k < minor; k++) {
                        const st = (i + k / minor) / steps, sa = a0 + span * st;
                        const s1 = polar(cx, cy, d.r - minorLen, sa), s2 = polar(cx, cy, d.r, sa);
                        el('line', { class: 'vf-tk-min', x1: s1.x.toFixed(1), y1: s1.y.toFixed(1),
                                     x2: s2.x.toFixed(1), y2: s2.y.toFixed(1), 'stroke-width': 1 }, svg);
                    }
                }

                if (showLabel) {
                    const lp = polar(cx, cy, d.r - labelInset, ang), num = Math.round(val);
                    const tx = el('text', { class: red ? 'vf-num-red' : 'vf-num', x: lp.x.toFixed(1), y: (lp.y + 3.5).toFixed(1),
                                            'text-anchor': 'middle', 'font-family': "'Segoe UI', sans-serif",
                                            'font-size': d.r >= 80 ? 9 : 8, 'font-weight': 700 }, svg);
                    tx.textContent = String(num);
                }
            }

            // arco de redzone colado no aro
            const rEdge = d.r - 1;
            if (typeof d.redAfter === 'number' || typeof d.redBefore === 'number') {
                const from = typeof d.redAfter === 'number' ? angleOf(d, d.redAfter) : a0;
                const to   = typeof d.redAfter === 'number' ? a1 : angleOf(d, d.redBefore);
                const s = polar(cx, cy, rEdge, from), e = polar(cx, cy, rEdge, to);
                const large = Math.abs(to - from) > 180 ? 1 : 0;
                el('path', { class: 'vf-rz', d: `M ${s.x.toFixed(1)} ${s.y.toFixed(1)} A ${rEdge} ${rEdge} 0 ${large} 1 ${e.x.toFixed(1)} ${e.y.toFixed(1)}`,
                             fill: 'none', 'stroke-width': 2.5, 'stroke-linecap': 'round', opacity: 0.9 }, svg);
            }

            // rótulo do dial (opcional) DENTRO da face, na área vazia inferior — nunca vaza a margem
            if (d.label) {
                const tx = el('text', { class: 'vf-lbl', x: cx, y: cy + d.r * 0.56, 'text-anchor': 'middle',
                                        'font-family': "'Segoe UI', sans-serif", 'font-size': d.r >= 55 ? 7.5 : 6.5,
                                        'font-weight': 700, 'letter-spacing': 1 }, svg);
                tx.textContent = d.label;
            }
        }
    }


    // ============================================================
    // SLOTS CDN — imagem central por dial (cover + overflow:hidden, técnica do iPad: preenche sem vazar)
    // ============================================================

    function buildBackgrounds(spec, shell) {
        (spec.backgrounds || []).forEach(function (key) {
            const d = spec.dials[key]; if (!d) return;
            const dia = (d.r - 6) * 2 * 0.86;   // preenche o miolo do dial, dentro dos ticks
            const slot = div('vf-cdn', shell);
            slot.id = 'custom-' + key + '-bg';
            slot.style.width = slot.style.height = dia.toFixed(1) + 'px';
            place(slot, d.c[0] - dia / 2, d.c[1] - dia / 2);
            // dirigido pelas CSS vars que o velo-core.applyConfig() já seta (--velo-bg-speed/fuel/rpm)
            slot.style.backgroundImage = 'var(--velo-bg-' + key + ', none)';
        });
    }


    // ============================================================
    // PONTEIROS + PIVÔS — ancorados no centro do dial (uma fonte de geometria com os ticks)
    // ============================================================

    function buildNeedles(spec, shell) {
        const map = { speed: 'speed-needle', rpm: 'rpm-needle', fuel: 'fuel-needle', nitro: 'nitro-needle' };
        for (const key in map) {
            const d = spec.dials[key]; if (!d) continue;
            const n = (spec.needles && spec.needles[key]) || {};
            const len = n.len || d.r * 0.85, w = n.w || 3, [cx, cy] = d.c;
            const color = n.color || 'var(--vf-accent)';

            const needle = div('needle ' + map[key], shell);
            needle.id = map[key];
            needle.style.width = w + 'px';
            needle.style.height = len + 'px';
            needle.style.left = (cx - w / 2) + 'px';
            needle.style.top = (cy - len) + 'px';
            needle.style.background = 'linear-gradient(180deg, #fff4cf, ' + color + ')';
            needle.style.boxShadow = '0 3px 10px rgba(0,0,0,.4)';

            const pr = key === 'speed' ? 8 : (key === 'rpm' ? 6 : (key === 'nitro' ? 3 : 4));
            const pivot = div('pivot', shell);
            pivot.style.width = pivot.style.height = (pr * 2) + 'px';
            place(pivot, cx - pr, cy - pr);
        }
    }


    // ============================================================
    // ODÔMETRO — 6 dígitos rolantes (velo-core anima [data-odo-digit] .odoColumn, passo 11px)
    // ============================================================

    function buildOdometer(parent) {
        const odo = div('vf-odo', parent);
        for (let i = 0; i < 6; i++) {
            const cell = div('odoDigit', odo);
            cell.setAttribute('data-odo-digit', '');
            const col = div('odoColumn', cell);
            for (let n = 0; n <= 9; n++) { const s = document.createElement('span'); s.textContent = n; col.appendChild(s); }
        }
        return odo;
    }


    // ============================================================
    // ÍCONES DE STATUS — setas/lock/cinto (velo-core seta data-status) + LED de motor (engine-health-dot)
    // ============================================================

    const ICON = {
        turnLeft:  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M14 6l-7 6 7 6"/><path d="M19 6l-7 6 7 6" opacity="0.55"/></svg>',
        turnRight: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M10 6l7 6-7 6"/><path d="M5 6l7 6-7 6" opacity="0.55"/></svg>',
        lock:      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3" class="vf-shackle"/><circle cx="12" cy="16" r="1.4" fill="currentColor" stroke="none"/></svg>',
        seatbelt:  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 3v8a6 6 0 0 0 6 6 6 6 0 0 0 6-6V3"/><path d="M6 3l12 14"/><circle cx="12" cy="20" r="1.4" fill="currentColor" stroke="none"/></svg>',
    };
    const STATUS_ID = { turnLeft: 'status-turn-left', turnRight: 'status-turn-right', lock: 'status-lock', seatbelt: 'status-seatbelt' };

    function buildStatus(spec, parent) {
        const row = div('vf-status', parent);
        (spec.status || []).forEach(function (kind) {
            if (kind === 'engine') {
                // saúde do motor = LED tricolor (velo-core seta data-health ok/warn/crit)
                const led = div('vf-eng-led', row);
                led.id = 'engine-health-dot';
                led.setAttribute('data-health', 'ok');
                return;
            }
            const icon = ICON[kind]; if (!icon) return;
            const cell = div('vf-stat vf-' + kind, row);
            cell.id = STATUS_ID[kind];
            cell.setAttribute('data-status', 'off');
            cell.innerHTML = icon;
        });
        return row;
    }


    // ============================================================
    // NITRO — dial PADRÃO com ponteiro (spec.dials.nitro desenha face/ticks/nitro-needle);
    //         aqui só o rótulo "NITRO" + a leitura % (nitro-value), ancorados no dial.
    // ============================================================

    function buildNitroReadout(spec, ov) {
        const d = spec.dials.nitro; if (!d) return;
        const [cx, cy] = d.c;
        // leitura na METADE de baixo (cor azul distingue do fuel verde na metade de cima)
        const val = div('vf-nitro-val', ov); val.id = 'nitro-value';
        place(val, cx, cy + d.r * 0.5); val.textContent = '0%';
    }


    // ============================================================
    // OVERLAY DIGITAL — leituras ancoradas nos centros dos dials (z6)
    // ============================================================

    function buildOverlay(spec, shell) {
        const ov = div('vf-overlay', shell);
        const R = spec.readouts || {};
        const speed = spec.dials.speed, rpm = spec.dials.rpm, fuel = spec.dials.fuel;

        // velocidade digital (prefixo apagado + valor) + unidade + odômetro, empilhados no centro do speed
        if (R.speedDigital && speed) {
            const block = div('vf-speed', ov);
            place(block, speed.c[0], speed.c[1] - 6);
            block.innerHTML =
                '<h1 class="vf-speed-num"><span class="vf-dim" id="vehicle-speed-prefix">00</span><span id="vehicle-speed">0</span></h1>' +
                '<div class="vf-unit">KM/H</div>';
            if (R.odometer) buildOdometer(block);
        } else if (R.odometer && speed) {
            const block = div('vf-speed', ov);
            place(block, speed.c[0], speed.c[1] + 18);
            buildOdometer(block);
        }

        // marcha no centro do RPM
        if (R.gear && rpm) {
            const g = div('vf-gear', ov);
            place(g, rpm.c[0], rpm.c[1] + rpm.r * 0.34);
            g.innerHTML = '<strong id="vehicle-gear">N</strong>';
        }

        // % de combustível na METADE de cima do dial partido (verde)
        if (R.fuelPercent && fuel) {
            const f = div('vf-fuel', ov);
            place(f, fuel.c[0], fuel.c[1] - fuel.r * 0.5);
            f.innerHTML = '<span id="vehicle-fuel">100</span><i>%</i>';
        }

        // nitro: ponteiro vive no dial padrão (spec.dials.nitro); aqui só rótulo + leitura %
        if (R.nitro && spec.dials.nitro) buildNitroReadout(spec, ov);

        // tira de status centralizada sob o speed
        if (spec.status && spec.status.length) {
            const row = buildStatus(spec, ov);
            place(row, speed.c[0], speed.c[1] + speed.r * 0.66);
        }
    }


    // ============================================================
    // CSS BASE — estrutural + tokens Mirage (areia/dourado). Escopo local em #velo-root (A-11).
    // ============================================================

    function injectBaseCss() {
        if (document.getElementById('velo-dials-base')) return;
        const css = `
html,body{ margin:0; padding:0; width:100%; height:100%; overflow:hidden; background:transparent !important; }
#velo-root,#velo-root *{ box-sizing:border-box; }
#velo-root{
  --vf-accent:var(--velo-accent,#d8b863); --vf-face:#08080c; --vf-bezel:#26282e;
  --vf-tick:#c8c9cd; --vf-tick-minor:#5a5c63; --vf-red:#ff2a2a; --vf-text:#f4ead0;
  --vf-ok:#22dd6a; --vf-warn:#ffaa00; --vf-nitro:#00b4ff; --vf-cdn-op:.85;
  position:absolute; right:2px; bottom:2px;
  transform-origin:bottom right; transform:translateY(16px) scale(calc(var(--velo-zoom,1) * var(--vf-rzoom,1)));
  opacity:0; transition:opacity .3s ease, transform .3s ease;
  pointer-events:none; user-select:none; font-family:'Segoe UI',Tahoma,sans-serif; color:var(--vf-text);
}
#velo-root.velo-active{ opacity:1; transform:translateY(0) scale(calc(var(--velo-zoom,1) * var(--vf-rzoom,1))); }
@media (max-width:1366px){ #velo-root{ --vf-rzoom:.9; } }
@media (max-width:1100px){ #velo-root{ --vf-rzoom:.8; } }
#velo-root .speedometerShell{ position:relative; filter:drop-shadow(0 14px 26px rgba(0,0,0,.5)); }
#velo-root .vf-face,#velo-root .vf-ticks{ position:absolute; inset:0; width:100%; height:100%; pointer-events:none; }
#velo-root .vf-face{ z-index:1; } #velo-root .vf-ticks{ z-index:3; }
/* cores do SVG por CLASSE (CEF não resolve var() em atributo de apresentação) */
#velo-root .vf-ring{ fill:var(--vf-face); stroke:var(--vf-bezel); }
#velo-root .vf-ring-in{ fill:none; stroke:#15161a; }
#velo-root .vf-div{ stroke:var(--vf-bezel); opacity:.7; }
#velo-root .vf-tk{ stroke:var(--vf-tick); } #velo-root .vf-tk-red{ stroke:var(--vf-red); }
#velo-root .vf-tk-min{ stroke:var(--vf-tick-minor); }
#velo-root .vf-num{ fill:var(--vf-tick); } #velo-root .vf-num-red{ fill:var(--vf-red); }
#velo-root .vf-rz{ stroke:var(--vf-red); } #velo-root .vf-lbl{ fill:var(--vf-tick-minor); }
#velo-root #nitro-arc-fill{ stroke:var(--vf-nitro); }
/* imagem preenche o dial (cover + overflow:hidden = técnica do iPad, não vaza do círculo) */
#velo-root .vf-cdn{ position:absolute; border-radius:50%; overflow:hidden; background-size:cover;
  background-position:center; background-repeat:no-repeat; opacity:var(--vf-cdn-op); z-index:2;
  pointer-events:none; }
#velo-root .vf-cdn::after{ content:''; position:absolute; inset:0; border-radius:50%;
  background:radial-gradient(circle at 50% 35%, rgba(0,0,0,0) 42%, rgba(0,0,0,.5) 100%); }
#velo-root .needle{ position:absolute; z-index:4; border-radius:3px; pointer-events:none;
  will-change:transform; transition:transform .12s linear; transform-origin:50% 100%; transform:rotate(-135deg); }
#velo-root .pivot{ position:absolute; z-index:5; border-radius:50%; pointer-events:none;
  background:radial-gradient(circle at 35% 30%,#5a5d66,#16171b 65%,#0a0a0d); border:1px solid #2a2c33;
  box-shadow:0 2px 6px rgba(0,0,0,.6); }
#velo-root .vf-overlay{ position:absolute; inset:0; z-index:6; pointer-events:none; }

#velo-root .vf-speed{ position:absolute; transform:translate(-50%,-50%); text-align:center; width:150px; }
#velo-root .vf-speed-num{ font-size:34px; font-weight:800; line-height:.86; letter-spacing:1px; color:#fff;
  text-shadow:0 0 10px var(--vf-accent), 0 2px 6px rgba(0,0,0,.6); display:inline-flex; align-items:flex-end; }
#velo-root .vf-dim{ color:rgba(255,255,255,.20); text-shadow:none; }
#velo-root .vf-unit{ margin-top:1px; font-size:9px; font-weight:700; letter-spacing:3px; color:var(--vf-accent);
  text-shadow:0 0 6px rgba(0,0,0,.5); }
#velo-root .vf-gear{ position:absolute; transform:translate(-50%,-50%); }
#velo-root .vf-gear strong{ font-size:15px; font-weight:800; letter-spacing:1px; color:#fff;
  text-shadow:0 0 8px var(--vf-accent); }
#velo-root .vf-fuel{ position:absolute; transform:translate(-50%,-50%); font-size:12px; font-weight:800; color:#fff;
  text-shadow:0 0 6px rgba(0,0,0,.6); }
#velo-root .vf-fuel i{ font-style:normal; font-size:8px; color:var(--vf-accent); margin-left:1px; }

#velo-root .vf-odo{ margin:7px auto 0; display:flex; justify-content:center; gap:2px; }
#velo-root .odoDigit{ width:9px; height:11px; overflow:hidden; border-radius:2px; background:rgba(0,0,0,.5); }
#velo-root .odoColumn{ display:flex; flex-direction:column; will-change:transform;
  transition:transform .45s cubic-bezier(.22,.61,.36,1); }
#velo-root .odoColumn span{ height:11px; line-height:11px; text-align:center; font:700 9px 'Consolas',monospace;
  color:var(--vf-accent); }

#velo-root .vf-status{ position:absolute; transform:translate(-50%,-50%); display:flex; align-items:center; gap:9px; }
#velo-root .vf-stat{ width:15px; height:15px; color:rgba(255,255,255,.14);
  filter:drop-shadow(0 1px 2px rgba(0,0,0,.6)); transition:color .18s ease, filter .18s ease; }
#velo-root .vf-stat svg{ width:100%; height:100%; display:block; }
#velo-root .vf-turnLeft[data-status="on"],#velo-root .vf-turnRight[data-status="on"]{
  color:#ffb02e; filter:drop-shadow(0 0 5px rgba(255,176,46,.85)); animation:vfBlink .55s steps(1,end) infinite; }
#velo-root .vf-seatbelt[data-status="on"],#velo-root .vf-lock[data-status="on"]{
  color:var(--vf-ok); filter:drop-shadow(0 0 5px rgba(34,221,106,.7)); }
#velo-root .vf-seatbelt[data-status="off"],#velo-root .vf-lock[data-status="off"]{
  color:var(--vf-red); filter:drop-shadow(0 0 5px rgba(255,59,59,.5)); }
#velo-root .vf-lock[data-status="off"] .vf-shackle{ transform:translateY(-1.5px) rotate(-12deg); transform-origin:16px 11px; }
@keyframes vfBlink{ 50%{ opacity:.15; } }

#velo-root .vf-eng-led{ width:10px; height:10px; border-radius:50%; background:#333; }
#velo-root .vf-eng-led[data-health="ok"]{ background:var(--vf-ok); box-shadow:0 0 6px rgba(34,221,106,.75); }
#velo-root .vf-eng-led[data-health="warn"]{ background:var(--vf-warn); box-shadow:0 0 6px rgba(255,170,0,.75); }
#velo-root .vf-eng-led[data-health="crit"]{ background:var(--vf-red); box-shadow:0 0 8px rgba(255,42,42,.85); animation:vfCrit 1s ease-in-out infinite; }
@keyframes vfCrit{ 50%{ box-shadow:0 0 16px rgba(255,42,42,1); } }

#velo-root .vf-nitro-val{ position:absolute; transform:translate(-50%,-50%); font:700 8px 'Consolas',monospace;
  color:var(--vf-nitro); text-shadow:0 0 5px rgba(0,180,255,.55); }
`;
        const style = document.createElement('style');
        style.id = 'velo-dials-base';
        style.textContent = css;
        document.head.appendChild(style);
    }


    // ============================================================
    // BUILD — monta a face inteira e devolve as curvas de gauge + âncoras
    // ============================================================

    // deriva pontos [valor, ângulo] do dial p/ o gauge do velo-core (mesma verdade dos ticks desenhados)
    function pointsOf(d) { return d ? [[d.range[0], d.arc[0]], [d.range[1], d.arc[1]]] : null; }

    function build(spec, mount) {
        if (!spec || !spec.dials) throw new Error('VeloDials.build: spec inválido');
        injectBaseCss();

        const root = mount || document.getElementById('velo-root') || div('', document.body);
        root.id = 'velo-root';
        root.classList.add('velo-face');
        root.style.width = spec.canvas[0] + 'px';
        root.innerHTML = '';   // re-entrante: rebuild limpo (hot-reload de HUD não empilha shells)

        const shell = div('speedometerShell', root);
        shell.style.width = spec.canvas[0] + 'px';
        shell.style.height = spec.canvas[1] + 'px';

        buildFace(spec, shell);          // z1
        buildBackgrounds(spec, shell);   // z2 (imagem CDN)
        buildTicks(spec, shell);         // z3
        buildNeedles(spec, shell);       // z4/z5
        buildOverlay(spec, shell);       // z6

        // âncoras (centros/raios) — expostas para debug/calibração externa
        const anchors = {};
        for (const k in spec.dials) anchors[k] = { c: spec.dials[k].c.slice(), r: spec.dials[k].r };

        return {
            speedPoints: pointsOf(spec.dials.speed),
            rpmPoints:   pointsOf(spec.dials.rpm),
            fuelPoints:  pointsOf(spec.dials.fuel),
            nitroPoints: pointsOf(spec.dials.nitro),
            anchors,
        };
    }

    window.VeloDials = { build };
})();
