// spec.js — vrm_classic (renascido): o DIAL SPEC do velocímetro de carro padrão vHub.
// "O SVG" agora é ISTO. Uma fonte por dial: mudar um número aqui move JUNTOS os ticks
// desenhados, a matemática do ponteiro e a redzone — nunca mais discordam.
//
// Corrigido nesta reconstrução: RPM vai a 10 (redzone em 8) e velocímetro a 300 (era 400).
// Trocar teto/redzone = editar UM número abaixo (não a arte, não o CSS).

window.veloSpec = {
    canvas: [470, 235],
    layout: 'tri',                                  // fuel | speed | rpm tangentes (72+46+92=210+92+68=370)

    // ============================================================
    // DIALS — c:[centro] · r:raio · range:[min,max] · arc:[ang0,ang1] (0°=topo)
    //         ticks:majores · minor:subdivisões · redAfter/redBefore:início da redzone (valor)
    // ============================================================
    dials: {
        // FUEL + NITRO dividem UM círculo (metade/metade): mesma c/r, arcos complementares.
        // fuel = semicírculo de CIMA · nitro = semicírculo de BAIXO. O motor desenha 1 face + o divisor.
        fuel:  { c: [72, 100],  r: 46, range: [0, 100], arc: [-90, 90],  ticks: 4,  minor: 0, redBefore: 20 },
        nitro: { c: [72, 100],  r: 46, range: [0, 100], arc: [90, 270],  ticks: 4,  minor: 0 },
        speed: { c: [210, 100], r: 92, range: [0, 300], arc: [-135, 135], ticks: 6,  minor: 5, redAfter: 250 },
        rpm:   { c: [370, 100], r: 68, range: [0, 10],  arc: [-135, 60],  ticks: 10, minor: 0, redAfter: 8 },
    },

    // ============================================================
    // NEEDLES — len:comprimento · w:espessura · color? (omitir = puxa --velo-accent do jogador)
    // ============================================================
    needles: {
        fuel:  { len: 30, w: 2.5, color: '#37e0a1' },
        nitro: { len: 30, w: 2.5, color: '#00b4ff' },
        speed: { len: 78, w: 4 },
        rpm:   { len: 54, w: 3,   color: '#ff2a2a' },
    },

    // slots de fundo por link (CDN): imagem preenche o dial (cover + clip, estilo iPad), não vaza
    backgrounds: ['fuel', 'speed', 'rpm'],

    // peças acopláveis: presente = monta · ausente = não aparece
    readouts: { speedDigital: true, gear: true, fuelPercent: true, odometer: true, nitro: true },

    // tira compacta sob o velocímetro (setas com lado já corrigido no velo-core; engine = LED tricolor)
    status: ['turnLeft', 'lock', 'seatbelt', 'engine', 'turnRight'],
};
