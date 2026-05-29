/* ============================================================
   VELOCIMETRO VOID-HUB v3
   Layout 540x250, 3 mostradores compactos + status row
   ============================================================ */

// ---------- DOM ----------
const body         = document.body;
const velocimetro  = document.getElementById('velocimetro');
const speedNeedle  = document.getElementById('speed-needle');
const rpmNeedle    = document.getElementById('rpm-needle');
const fuelNeedle   = document.getElementById('fuel-needle');
const speedPrefix  = document.getElementById('vehicle-speed-prefix');
const speedValue   = document.getElementById('vehicle-speed');
const gearValue    = document.getElementById('vehicle-gear');
const fuelValue    = document.getElementById('vehicle-fuel');
const odoValue     = document.getElementById('vehicle-odometer');

const customRpmBg   = document.getElementById('custom-rpm-bg');
const customSpeedBg = document.getElementById('custom-speed-bg');
const customFuelBg  = document.getElementById('custom-fuel-bg');

const iconTurnLeft  = document.getElementById('status-turn-left');
const iconTurnRight = document.getElementById('status-turn-right');
const iconLock      = document.getElementById('status-lock');
const iconBelt      = document.getElementById('status-belt');
const iconEngine    = document.getElementById('status-engine');

// ---------- CONSTANTES ----------
const LOGO_PADRAO = 'https://raw.githubusercontent.com/Void-Cla/vhub-assets/main/logo.png';
const STORAGE_KEY = 'voidhub:velocimetro:config:v3';

const DEFAULT_CONFIG = {
    urlImagemFuel:       LOGO_PADRAO,
    urlImagemVelocidade: LOGO_PADRAO,
    urlImagemRpm:        LOGO_PADRAO,
    corPonteiroFuel:     '#37e0a1',
    corPonteiroVelocidade: '#ff8c00',
    corPonteiroRpm:      '#ff2a2a'
};

// ---------- INTERPOLADOR ----------
function createPredictPoint({ points, clamp = true }) {
    const pts = points.slice().sort((a, b) => a[0] - b[0]);
    const segments = [];
    for (let i = 0; i < pts.length - 1; i++) {
        const [v1, a1] = pts[i];
        const [v2, a2] = pts[i + 1];
        segments.push([v1, v2, a1, (a2 - a1) / (v2 - v1)]);
    }
    return {
        get(value) {
            for (const s of segments) {
                if (value >= s[0] && value <= s[1]) return s[2] + (value - s[0]) * s[3];
            }
            if (clamp) {
                if (value < segments[0][0]) return segments[0][2];
                const last = segments[segments.length - 1];
                return last[2] + (last[1] - last[0]) * last[3];
            }
            return undefined;
        },
        minValue: pts[0][0],
        maxValue: pts[pts.length - 1][0]
    };
}

const speedGauge = createPredictPoint({ points: [ [0, -135], [400,  135] ] });
const rpmGauge   = createPredictPoint({ points: [ [0, -135], [10,    60] ] });
const fuelGauge  = createPredictPoint({ points: [ [0,  135], [100, -135] ] });

// ---------- TICKS gerados no SVG ----------
function gerarTicks() {
    // FUEL: dial pequeno r=46
    desenharTicksCircular({
        groupId: 'ticks-fuel',
        cx: 72, cy: 100, raio: 40,
        startAngle: -135, endAngle: 135,
        steps: 4,
        majorLen: 5,
        minorLen: 0,
        redAfter: 3,
        labels: [],
        fontSize: 0
    });
    // SPEED: dial grande r=92
    desenharTicksCircular({
        groupId: 'ticks-speed',
        cx: 210, cy: 100, raio: 84,
        startAngle: -135, endAngle: 135,
        steps: 8,
        majorLen: 9, minorLen: 4,
        labels: ['0','50','100','150','200','250','300','350','400'],
        fontSize: 9,
        labelInset: 18
    });
    // RPM: dial médio r=68, 0..10
    desenharTicksCircular({
        groupId: 'ticks-rpm',
        cx: 370, cy: 100, raio: 62,
        startAngle: -135, endAngle: 60,
        steps: 10,
        majorLen: 7, minorLen: 3,
        labels: ['0','1','2','3','4','5','6','7','8','9','10'],
        fontSize: 8,
        labelInset: 14,
        redAfter: 8
    });
}

function desenharTicksCircular({
    groupId, cx, cy, raio,
    startAngle, endAngle,
    steps,
    majorLen = 8, minorLen = 4,
    redAfter = null,
    labels = [], fontSize = 10, labelInset = 16
}) {
    const g = document.getElementById(groupId);
    if (!g) return;
    const SVG_NS = 'http://www.w3.org/2000/svg';
    const span = endAngle - startAngle;

    for (let i = 0; i <= steps; i++) {
        const t = i / steps;
        const ang = startAngle + span * t;
        const rad = (ang - 90) * Math.PI / 180;

        const x1 = cx + Math.cos(rad) * (raio - majorLen);
        const y1 = cy + Math.sin(rad) * (raio - majorLen);
        const x2 = cx + Math.cos(rad) * raio;
        const y2 = cy + Math.sin(rad) * raio;

        const isRed = (redAfter !== null && i >= redAfter);

        const tick = document.createElementNS(SVG_NS, 'line');
        tick.setAttribute('x1', x1.toFixed(1));
        tick.setAttribute('y1', y1.toFixed(1));
        tick.setAttribute('x2', x2.toFixed(1));
        tick.setAttribute('y2', y2.toFixed(1));
        tick.setAttribute('stroke', isRed ? '#ff2a2a' : '#c8c9cd');
        tick.setAttribute('stroke-width', '2');
        tick.setAttribute('stroke-linecap', 'round');
        g.appendChild(tick);

        // Minor ticks
        if (minorLen > 0 && i < steps) {
            for (let k = 1; k < 5; k++) {
                const subT = (i + k / 5) / steps;
                const subAng = startAngle + span * subT;
                const subRad = (subAng - 90) * Math.PI / 180;
                const sx1 = cx + Math.cos(subRad) * (raio - minorLen);
                const sy1 = cy + Math.sin(subRad) * (raio - minorLen);
                const sx2 = cx + Math.cos(subRad) * raio;
                const sy2 = cy + Math.sin(subRad) * raio;
                const sub = document.createElementNS(SVG_NS, 'line');
                sub.setAttribute('x1', sx1.toFixed(1));
                sub.setAttribute('y1', sy1.toFixed(1));
                sub.setAttribute('x2', sx2.toFixed(1));
                sub.setAttribute('y2', sy2.toFixed(1));
                sub.setAttribute('stroke', '#5a5c63');
                sub.setAttribute('stroke-width', '1');
                g.appendChild(sub);
            }
        }

        // Labels
        if (labels[i] && fontSize > 0) {
            const lx = cx + Math.cos(rad) * (raio - labelInset);
            const ly = cy + Math.sin(rad) * (raio - labelInset) + fontSize * 0.35;
            const txt = document.createElementNS(SVG_NS, 'text');
            txt.setAttribute('x', lx.toFixed(1));
            txt.setAttribute('y', ly.toFixed(1));
            txt.setAttribute('text-anchor', 'middle');
            txt.setAttribute('font-family', "'Segoe UI', sans-serif");
            txt.setAttribute('font-size', fontSize);
            txt.setAttribute('font-weight', '700');
            txt.setAttribute('fill', isRed ? '#ff2a2a' : '#c8c9cd');
            txt.textContent = labels[i];
            g.appendChild(txt);
        }
    }
}

// ---------- ESTADO ----------
const fallbackPayload = {
    visible: false, active: false,
    speed_kmh: 0, rpm_percent: 0, fuel_percent: 100,
    gear_label: 'N',
    odometer: 0,
    engine_health: 100,
    locked: false, belt: false,
    turn_left: false, turn_right: false
};
const previewPayload = { ...fallbackPayload, visible: true, active: true };
let estadoAtual = fallbackPayload;
let configAtual = { ...DEFAULT_CONFIG };

function detectarPreviewNavegador() {
    const host = String(window.location.hostname || '').toLowerCase();
    return !host.startsWith('cfx-nui-');
}
const previewMode = detectarPreviewNavegador();
if (previewMode) body.classList.add('preview');

// ---------- UTIL ----------
function clamp(value, min, max) {
    const n = Number(value);
    if (!Number.isFinite(n)) return min;
    return Math.max(min, Math.min(max, n));
}
function splitSpeed(speed) {
    const s = String(Math.round(clamp(speed, 0, 999))).padStart(3, '0');
    return { prefix: s.slice(0, 2), value: s.slice(2) };
}
function normalizarMarcha(v) {
    const label = String(v.gear_label || v.gear || '').trim().toUpperCase();
    if (label === 'R' || label === 'N') return label;
    const g = parseInt(label, 10);
    return Number.isFinite(g) && g > 0 ? String(Math.min(g, 9)) : 'N';
}
function formatarOdometro(km) {
    const n = Math.max(0, Math.floor(Number(km) || 0));
    return String(n).padStart(6, '0');   // 6 dígitos com zeros à esquerda
}
// Renderiza o odômetro como caixinhas de dígito (igual hodômetro real).
// A última casa (unidades) usa estilo "drum" âmbar via classe .tenth.
let ultimoOdoStr = null;
function renderOdometro(km) {
    const s = formatarOdometro(km);
    if (s === ultimoOdoStr) return;   // evita reconstruir DOM à toa
    ultimoOdoStr = s;
    odoValue.innerHTML = '';
    for (let i = 0; i < s.length; i++) {
        const cell = document.createElement('span');
        cell.className = 'odo-digit' + (i === s.length - 1 ? ' tenth' : '');
        cell.textContent = s[i];
        odoValue.appendChild(cell);
    }
}

// ---------- RENDER ----------
function renderVelocimetro(p) {
    const active = Boolean(p.visible && p.active);
    body.classList.toggle('velocimetro-visivel', active);
    body.classList.toggle('velocimetro-oculto', !active);

    const speed = clamp(p.speed_kmh, 0, 999);
    const rpm   = clamp(p.rpm_percent, 0, 100);
    const fuel  = clamp(p.fuel_percent, 0, 100);
    const eng   = clamp(p.engine_health, 0, 100);

    const sp = splitSpeed(speed);
    speedPrefix.textContent = sp.prefix;
    speedValue.textContent  = sp.value;
    gearValue.textContent   = normalizarMarcha(p);
    fuelValue.textContent   = Math.round(fuel);
    renderOdometro(p.odometer);

    speedNeedle.style.transform = `rotate(${speedGauge.get(speed)}deg)`;
    rpmNeedle.style.transform   = `rotate(${rpmGauge.get((rpm / 100) * rpmGauge.maxValue)}deg)`;
    fuelNeedle.style.transform  = `rotate(${fuelGauge.get(fuel)}deg)`;

    // Status icons
    iconTurnLeft.classList.toggle('on',  Boolean(p.turn_left));
    iconTurnRight.classList.toggle('on', Boolean(p.turn_right));

    iconLock.classList.toggle('locked',   Boolean(p.locked));
    iconLock.classList.toggle('unlocked', !p.locked);

    iconBelt.classList.toggle('on',  Boolean(p.belt));
    iconBelt.classList.toggle('off', !p.belt);

    iconEngine.classList.remove('good', 'warn', 'danger');
    if (eng >= 70)       iconEngine.classList.add('good');
    else if (eng >= 35)  iconEngine.classList.add('warn');
    else                 iconEngine.classList.add('danger');
}

function normalizarPayload(data) {
    if (!data || typeof data !== 'object') return fallbackPayload;
    const v = data.vehicle && typeof data.vehicle === 'object' ? data.vehicle : data;
    return {
        visible: data.visible !== false,
        active:  v.active !== false,
        speed_kmh:     v.speed_kmh,
        rpm_percent:   v.rpm_percent,
        fuel_percent:  v.fuel_percent !== undefined ? v.fuel_percent : estadoAtual.fuel_percent,
        gear_label:    normalizarMarcha(v),
        odometer:      v.odometer      !== undefined ? v.odometer      : estadoAtual.odometer,
        engine_health: v.engine_health !== undefined ? v.engine_health : estadoAtual.engine_health,
        locked:        v.locked        !== undefined ? Boolean(v.locked)     : estadoAtual.locked,
        belt:          v.belt          !== undefined ? Boolean(v.belt)       : estadoAtual.belt,
        turn_left:     v.turn_left     !== undefined ? Boolean(v.turn_left)  : estadoAtual.turn_left,
        turn_right:    v.turn_right    !== undefined ? Boolean(v.turn_right) : estadoAtual.turn_right
    };
}
function applyPayload(data) {
    estadoAtual = normalizarPayload(data);
    renderVelocimetro(estadoAtual);
}

// ---------- CUSTOMIZAÇÃO ----------
function aplicarCustomizacao(cfg) {
    if (!cfg) return;
    configAtual = { ...configAtual, ...cfg };

    customFuelBg.style.backgroundImage  = `url('${configAtual.urlImagemFuel}')`;
    customSpeedBg.style.backgroundImage = `url('${configAtual.urlImagemVelocidade}')`;
    customRpmBg.style.backgroundImage   = `url('${configAtual.urlImagemRpm}')`;

    const cf = configAtual.corPonteiroFuel;
    fuelNeedle.style.background = `linear-gradient(180deg, #ffffff, ${cf})`;
    fuelNeedle.style.boxShadow  = `0 4px 10px ${cf}66`;

    const cs = configAtual.corPonteiroVelocidade;
    speedNeedle.style.background = `linear-gradient(180deg, #ffffff, ${cs})`;
    speedNeedle.style.boxShadow  = `0 4px 14px ${cs}66`;

    const cr = configAtual.corPonteiroRpm;
    rpmNeedle.style.background = `linear-gradient(180deg, #ffffff, ${cr})`;
    rpmNeedle.style.boxShadow  = `0 4px 12px ${cr}66`;
}

function carregarConfigSalva() {
    try {
        const raw = localStorage.getItem(STORAGE_KEY);
        if (raw) {
            const saved = JSON.parse(raw);
            aplicarCustomizacao({ ...DEFAULT_CONFIG, ...saved });
            return;
        }
    } catch (_) {}
    aplicarCustomizacao(DEFAULT_CONFIG);
}
function salvarConfig(cfg) {
    try { localStorage.setItem(STORAGE_KEY, JSON.stringify(cfg)); } catch (_) {}
}

// ---------- PAINEL /velo ----------
const painel     = document.getElementById('velo-config');
const inpRpm     = document.getElementById('input-rpm');
const inpSpeed   = document.getElementById('input-speed');
const inpFuel    = document.getElementById('input-fuel');
const colorRpm   = document.getElementById('color-rpm');
const colorSpeed = document.getElementById('color-speed');
const colorFuel  = document.getElementById('color-fuel');
const btnSave    = document.getElementById('config-save');
const btnReset   = document.getElementById('config-reset');
const btnClose   = document.getElementById('config-close');

function abrirPainel() {
    inpRpm.value     = configAtual.urlImagemRpm        === LOGO_PADRAO ? '' : configAtual.urlImagemRpm;
    inpSpeed.value   = configAtual.urlImagemVelocidade === LOGO_PADRAO ? '' : configAtual.urlImagemVelocidade;
    inpFuel.value    = configAtual.urlImagemFuel       === LOGO_PADRAO ? '' : configAtual.urlImagemFuel;
    colorRpm.value   = configAtual.corPonteiroRpm;
    colorSpeed.value = configAtual.corPonteiroVelocidade;
    colorFuel.value  = configAtual.corPonteiroFuel;
    painel.classList.add('open');
    painel.setAttribute('aria-hidden', 'false');
    enviarCallback('focar', { focar: true });
}
function fecharPainel() {
    painel.classList.remove('open');
    painel.setAttribute('aria-hidden', 'true');
    enviarCallback('focar', { focar: false });
}

[colorRpm, colorSpeed, colorFuel].forEach(el => {
    el.addEventListener('input', () => {
        aplicarCustomizacao({
            corPonteiroRpm:        colorRpm.value,
            corPonteiroVelocidade: colorSpeed.value,
            corPonteiroFuel:       colorFuel.value
        });
    });
});

btnSave.addEventListener('click', () => {
    const cfg = {
        urlImagemRpm:        inpRpm.value.trim()   || LOGO_PADRAO,
        urlImagemVelocidade: inpSpeed.value.trim() || LOGO_PADRAO,
        urlImagemFuel:       inpFuel.value.trim()  || LOGO_PADRAO,
        corPonteiroRpm:      colorRpm.value,
        corPonteiroVelocidade: colorSpeed.value,
        corPonteiroFuel:     colorFuel.value
    };
    aplicarCustomizacao(cfg);
    salvarConfig(cfg);
    enviarCallback('salvarConfig', cfg);
    fecharPainel();
});
btnReset.addEventListener('click', () => {
    aplicarCustomizacao(DEFAULT_CONFIG);
    salvarConfig(DEFAULT_CONFIG);
    inpRpm.value = inpSpeed.value = inpFuel.value = '';
    colorRpm.value   = DEFAULT_CONFIG.corPonteiroRpm;
    colorSpeed.value = DEFAULT_CONFIG.corPonteiroVelocidade;
    colorFuel.value  = DEFAULT_CONFIG.corPonteiroFuel;
});
btnClose.addEventListener('click', fecharPainel);
painel.addEventListener('click', (e) => { if (e.target === painel) fecharPainel(); });
document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && painel.classList.contains('open')) fecharPainel(); });

// ---------- /velo  detecção do comando ----------
let buffer = '';
let bufferTimer = null;
document.addEventListener('keydown', (e) => {
    if (e.target && (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA' || e.target.tagName === 'SELECT')) return;
    if (e.key === '/') buffer = '/';
    else if (buffer && /^[a-zA-Z]$/.test(e.key)) {
        buffer += e.key.toLowerCase();
        if (buffer === '/velo') setTimeout(abrirPainel, 50);
    }
    else if (e.key === 'Backspace') buffer = buffer.slice(0, -1);

    clearTimeout(bufferTimer);
    bufferTimer = setTimeout(() => { buffer = ''; }, 2000);
});

// ---------- FiveM bridge ----------
function enviarCallback(nome, data) {
    if (previewMode) return;
    try {
        const res = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'void_velocimetro';
        fetch(`https://${res}/${nome}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data || {})
        }).catch(() => {});
    } catch (_) {}
}

window.addEventListener('message', (event) => {
    const payload = event.data;
    if (!payload || typeof payload !== 'object') return;
    if (payload.type === 'velocimetro:update') {
        applyPayload(payload.data || payload.vehicle || fallbackPayload);
    } else if (payload.type === 'velocimetro:config') {
        const cfg = { ...DEFAULT_CONFIG, ...(payload.data || {}) };
        aplicarCustomizacao(cfg);
        salvarConfig(cfg);
    } else if (payload.type === 'velocimetro:abrirConfig') {
        abrirPainel();
    }
});

// ---------- INIT ----------
gerarTicks();
carregarConfigSalva();
if (previewMode) {
    applyPayload({
        visible: true, active: true,
        speed_kmh: 0, rpm_percent: 0, fuel_percent: 100,
        gear_label: 'N', odometer: 123456, engine_health: 100,
        locked: false, belt: false, turn_left: false, turn_right: false
    });
} else {
    applyPayload(fallbackPayload);
}

// ============================================================
// HUD DE PREVIEW
// ============================================================
const hudSpeed  = document.getElementById('hud-speed');
const hudRpm    = document.getElementById('hud-rpm');
const hudFuel   = document.getElementById('hud-fuel');
const hudEngine = document.getElementById('hud-engine');
const hudGear   = document.getElementById('hud-gear');
const hudOdo    = document.getElementById('hud-odometer');
const hudAuto   = document.getElementById('hud-auto');
const hudSpeedOut  = document.getElementById('hud-speed-out');
const hudRpmOut    = document.getElementById('hud-rpm-out');
const hudFuelOut   = document.getElementById('hud-fuel-out');
const hudEngineOut = document.getElementById('hud-engine-out');

const togState = { locked: false, belt: false, turn_left: false, turn_right: false };
document.querySelectorAll('.preview-hud .tog').forEach(btn => {
    btn.addEventListener('click', () => {
        const key = btn.dataset.toggle;
        togState[key] = !togState[key];
        btn.classList.toggle('on', togState[key]);
        if (!autoSim) aplicarHud();
    });
});

let autoSim = false;
let simT = 0;
let simOdo = 123456;

function aplicarHud() {
    applyPayload({
        visible: true, active: true,
        speed_kmh:    Number(hudSpeed.value),
        rpm_percent:  Number(hudRpm.value),
        fuel_percent: Number(hudFuel.value),
        engine_health: Number(hudEngine.value),
        gear_label:   hudGear.value,
        odometer:     Number(hudOdo.value),
        locked:       togState.locked,
        belt:         togState.belt,
        turn_left:    togState.turn_left,
        turn_right:   togState.turn_right
    });
    hudSpeedOut.textContent  = hudSpeed.value;
    hudRpmOut.textContent    = hudRpm.value;
    hudFuelOut.textContent   = hudFuel.value;
    hudEngineOut.textContent = hudEngine.value;
}

if (hudSpeed) {
    [hudSpeed, hudRpm, hudFuel, hudEngine, hudGear, hudOdo].forEach(el => {
        el.addEventListener('input', () => { if (!autoSim) aplicarHud(); });
    });
    hudAuto.addEventListener('click', () => {
        autoSim = !autoSim;
        hudAuto.classList.toggle('on', autoSim);
        hudAuto.textContent = autoSim ? '■ Parar simulação' : '▶ Simular condução';
    });

    function loop() {
        if (autoSim) {
            simT += 0.012;
            const speed = Math.max(0, (Math.sin(simT) * 0.5 + 0.5) * 280 + Math.sin(simT * 4) * 20);
            const rpm   = Math.max(0, (Math.sin(simT * 1.6 + 0.5) * 0.5 + 0.5) * 90 + Math.sin(simT * 8) * 6);
            const fuel  = 100 - ((simT * 1.2) % 100);
            const eng   = Math.max(0, 100 - ((simT * 0.6) % 110));
            const gear  = ['N','1','2','3','4','5','6'][Math.min(6, Math.floor(speed / 45) + 1)];
            simOdo += speed * 0.003;

            hudSpeed.value  = Math.round(speed);
            hudRpm.value    = Math.round(rpm);
            hudFuel.value   = Math.round(fuel);
            hudEngine.value = Math.round(eng);
            hudGear.value   = gear;
            hudOdo.value    = Math.round(simOdo);
            aplicarHud();
        }
        requestAnimationFrame(loop);
    }
    loop();
}
