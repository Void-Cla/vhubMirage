// IDs do HTML: nao renomear sem alterar index.html.
const body = document.body;
const velocimetro = document.getElementById('velocimetro');
const speedNeedle = document.getElementById('speed-needle');
const rpmNeedle = document.getElementById('rpm-needle');
const speedPrefix = document.getElementById('vehicle-speed-prefix');
const speedValue = document.getElementById('vehicle-speed');
const gearValue = document.getElementById('vehicle-gear');

// Interpolador dos mostradores: pontos [valor, angulo] definem a escala.
function createPredictPoint({ points, clamp = true }) {
    const pts = points.slice().sort((a, b) => a[0] - b[0]);
    const segments = [];
    for (let i = 0; i < pts.length - 1; i++) {
        const [v1, a1] = pts[i];
        const [v2, a2] = pts[i + 1];
        segments.push([v1, v2, a1, (a2 - a1) / (v2 - v1)]);
    }

    let lastIndex = 0;

    function get(value) {
        let s = segments[lastIndex];
        if (value >= s[0] && value <= s[1]) {
            return s[2] + (value - s[0]) * s[3];
        }

        let low = 0;
        let high = segments.length - 1;
        while (low <= high) {
            const mid = (low + high) >> 1;
            s = segments[mid];
            if (value < s[0]) {
                high = mid - 1;
            } else if (value > s[1]) {
                low = mid + 1;
            } else {
                lastIndex = mid;
                return s[2] + (value - s[0]) * s[3];
            }
        }

        if (clamp) {
            if (value <= segments[0][0]) {
                return segments[0][2];
            }
            const last = segments[segments.length - 1];
            if (value >= last[1]) {
                return last[2] + (last[1] - last[0]) * last[3];
            }
        }

        return undefined;
    }

    const first = pts[0];
    const last = pts[pts.length - 1];
    return {
        get,
        minValue: first[0],
        maxValue: last[0],
        minAngle: first[1],
        maxAngle: last[1]
    };
}
// Escala mapeada direto na geometria do SVG: A0=-135°, A1=+135° para 0..400 km/h.
const speedGauge = createPredictPoint({ points: [
    [0,   -135],
    [400,  135]
]});

// Escala mapeada direto na geometria do SVG: A0=-135°, A1=+60° para 0..8 (x1000).
// mapearAgulhaRpm converte rpm_percent 0-100 para 0-10 antes de consultar aqui.
const rpmGauge = createPredictPoint({ points: [
    [0,  -135],
    [10,   60]
]});

// Estado seguro: NUI inicia oculta ate receber dado valido.
const fallbackPayload = {
    visible: false,
    active: false,
    speed_kmh: 0,
    rpm_percent: 0,
    gear_label: 'N'
};

// Preview local: usado ao abrir o HTML fora do FiveM.
const previewPayload = {
    visible: true,
    active: true,
    speed_kmh: 128,
    rpm_percent: 67,
    gear_label: '4'
};

let estadoAtual = fallbackPayload;
let previewMode = detectarPreviewNavegador();

// Detecta navegador comum para calibrar visual sem FXServer.
function detectarPreviewNavegador() {
    const params = new URLSearchParams(window.location.search);
    const query = (params.get('preview') || params.get('modo') || '').toLowerCase();
    const hash = String(window.location.hash || '').replace(/^#/, '').toLowerCase();
    const candidate = query || hash;
    if (candidate === 'veiculo' || candidate === 'carro' || candidate === 'velocimetro') {
        return true;
    }

    const hostname = String(window.location.hostname || '').toLowerCase();
    return !hostname.startsWith('cfx-nui-');
}

// Normaliza entrada hostil e evita NaN quebrando CSS rotate().
function clamp(value, min, max) {
    const parsed = Number(value);
    if (!Number.isFinite(parsed)) {
        return min;
    }
    return Math.max(min, Math.min(max, parsed));
}

// Mantem tres digitos no visor, separando prefixo apagado.
function splitSpeed(speed) {
    const normalized = String(Math.round(clamp(speed, 0, 999))).padStart(3, '0');
    return {
        prefix: normalized.slice(0, 2),
        value: normalized.slice(2)
    };
}

// Normaliza marcha para renderizar apenas N, R ou um digito.
function normalizarMarcha(vehicle) {
    const label = String(vehicle.gear_label || vehicle.gear || '').trim().toUpperCase();
    if (label === 'R' || label === 'N') {
        return label;
    }
    const gear = Number.parseInt(label, 10);
    return Number.isFinite(gear) && gear > 0 ? String(Math.min(gear, 9)) : 'N';
}

// Converte km/h em angulo CSS conforme speedGauge.
function mapearAgulhaVelocidade(speed) {
    return speedGauge.get(clamp(speed, speedGauge.minValue, speedGauge.maxValue));
}

// Converte RPM percentual do client em escala 0..10.
function mapearAgulhaRpm(rpm) {
    const scaled = (Number(rpm) / 100) * rpmGauge.maxValue;
    return rpmGauge.get(clamp(scaled, rpmGauge.minValue, rpmGauge.maxValue));
}

// Aceita payload direto ou aninhado em vehicle sem confiar no formato.
function normalizarPayload(data) {
    if (!data || typeof data !== 'object') {
        return fallbackPayload;
    }

    const vehicle = data.vehicle && typeof data.vehicle === 'object' ? data.vehicle : data;
    return {
        visible: data.visible !== false,
        active: vehicle.active !== false,
        speed_kmh: vehicle.speed_kmh,
        rpm_percent: vehicle.rpm_percent,
        gear_label: normalizarMarcha(vehicle)
    };
}

// Render unico: aplica visibilidade, texto e rotacao dos ponteiros.
function renderVelocimetro(payload) {
    const active = Boolean(payload.visible && payload.active);
    body.classList.toggle('velocimetro-visivel', active);
    body.classList.toggle('velocimetro-oculto', !active);
    velocimetro.classList.toggle('active', active);

    const speed = clamp(payload.speed_kmh, 0, 999);
    const rpm = clamp(payload.rpm_percent, 0, 100);
    const split = splitSpeed(speed);

    speedPrefix.textContent = split.prefix;
    speedValue.textContent = split.value;
    if (gearValue) {
        gearValue.textContent = normalizarMarcha(payload);
    }
    speedNeedle.style.transform = `rotate(${mapearAgulhaVelocidade(speed)}deg)`;
    rpmNeedle.style.transform = `rotate(${mapearAgulhaRpm(rpm)}deg)`;
}

// Guarda ultimo payload para recalibrar apos load/resize.
function applyPayload(data) {
    estadoAtual = normalizarPayload(data);
    renderVelocimetro(estadoAtual);
}

// Calibracao fina dos ponteiros para o velo.png atual.
function calibrarAgulhas() {
    speedNeedle.style.transformOrigin = '50% 88%';
    speedNeedle.style.left = '309px';
    speedNeedle.style.bottom = '106px';
    rpmNeedle.style.transformOrigin = '50% 88%';
    rpmNeedle.style.left = '152px';
    rpmNeedle.style.bottom = '92px';
    renderVelocimetro(estadoAtual);
}

// Contrato NUI: client.lua deve enviar type velocimetro:update.
window.addEventListener('message', (event) => {
    const payload = event.data;
    if (!payload || typeof payload !== 'object') {
        return;
    }

    if (payload.type === 'velocimetro:update') {
        applyPayload(payload.data || payload.vehicle || fallbackPayload);
    }
});

// Reaplica coordenadas quando CEF recalcula layout.
window.addEventListener('load', calibrarAgulhas);
window.addEventListener('resize', calibrarAgulhas);

if (previewMode) {
    applyPayload(previewPayload);
} else {
    applyPayload(fallbackPayload);
}
