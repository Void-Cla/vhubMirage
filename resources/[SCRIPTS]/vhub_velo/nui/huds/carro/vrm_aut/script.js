/* Adapter HUD — vrm_aut: usa o engine compartilhado VeloCore e
   aplica personalizações por mostrador. Mantém o painel /velo
   (galeria) e persiste via NUI callbacks padronizados. */

const painel = document.getElementById('velo-config');
const inpRpm = document.getElementById('input-rpm');
const inpSpeed = document.getElementById('input-speed');
const inpFuel = document.getElementById('input-fuel');
const colorRpm = document.getElementById('color-rpm');
const colorSpeed = document.getElementById('color-speed');
const colorFuel = document.getElementById('color-fuel');
const btnSave = document.getElementById('config-save');
const btnReset = document.getElementById('config-reset');
const btnClose = document.getElementById('config-close');

const customRpmBg = document.getElementById('custom-rpm-bg');
const customSpeedBg = document.getElementById('custom-speed-bg');
const customFuelBg = document.getElementById('custom-fuel-bg');

const LOGO_PADRAO = 'https://raw.githubusercontent.com/Void-Cla/vhub-assets/main/logo.png';
const STORAGE_KEY = 'voidhub:velocimetro:config:v3';

const DEFAULT_CONFIG = {
    urlImagemFuel: LOGO_PADRAO,
    urlImagemVelocidade: LOGO_PADRAO,
    urlImagemRpm: LOGO_PADRAO,
    corPonteiroFuel: '#37e0a1',
    corPonteiroVelocidade: '#ff8c00',
    corPonteiroRpm: '#ff2a2a'
};

let configAtual = { ...DEFAULT_CONFIG };
let currentCategory = null;

function previewMode() { return !String(location.hostname || '').startsWith('cfx-nui-'); }

function enviarCallback(nome, data) {
    if (previewMode()) return;
    try {
        const res = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'vhub_velo';
        fetch(`https://${res}/${nome}`, { method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(data || {}) }).catch(() => {});
    } catch (_) {}
}

function normalizeIncomingConfig(d) {
    if (!d || typeof d !== 'object') return null;
    return {
        urlImagemFuel: d.bgFuel || d.urlImagemFuel || d.bg || '',
        urlImagemVelocidade: d.bgSpeed || d.urlImagemVelocidade || d.bg || '',
        urlImagemRpm: d.bgRpm || d.urlImagemRpm || '',
        corPonteiroFuel: d.corPonteiroFuel || d.colorFuel || '#37e0a1',
        corPonteiroVelocidade: d.corPonteiroVelocidade || d.colorSpeed || '#ff8c00',
        corPonteiroRpm: d.corPonteiroRpm || d.colorRpm || '#ff2a2a',
        accent: d.accent || ''
    };
}

function aplicarCustomizacao(cfg) {
    if (!cfg) return;
    configAtual = { ...configAtual, ...cfg };
    customFuelBg.style.backgroundImage = configAtual.urlImagemFuel ? `url('${configAtual.urlImagemFuel}')` : 'none';
    customSpeedBg.style.backgroundImage = configAtual.urlImagemVelocidade ? `url('${configAtual.urlImagemVelocidade}')` : 'none';
    customRpmBg.style.backgroundImage = configAtual.urlImagemRpm ? `url('${configAtual.urlImagemRpm}')` : 'none';
    document.documentElement.style.setProperty('--velo-accent', configAtual.corPonteiroVelocidade || '#ff8c00');
}

function carregarConfigSalva() {
    try {
        const raw = localStorage.getItem(STORAGE_KEY);
        if (raw) {
            const saved = JSON.parse(raw);
            aplicarCustomizacao({ ...DEFAULT_CONFIG, ...saved });
            if (window.VeloCore && VeloCore.applyConfig) VeloCore.applyConfig({ bg: '', accent: saved.corPonteiroVelocidade || '', bgFuel: saved.urlImagemFuel, bgSpeed: saved.urlImagemVelocidade, bgRpm: saved.urlImagemRpm });
            return;
        }
    } catch (_) {}
    aplicarCustomizacao(DEFAULT_CONFIG);
}

function gerarTicks() {
    desenharTicksCircular({ groupId: 'ticks-fuel', cx: 72, cy: 100, raio: 40, startAngle: -135, endAngle: 135, steps: 4, majorLen: 5, minorLen: 0, redAfter: 3, labels: [], fontSize: 0 });
    desenharTicksCircular({ groupId: 'ticks-speed', cx: 210, cy: 100, raio: 84, startAngle: -135, endAngle: 135, steps: 8, majorLen: 9, minorLen: 4, labels: ['0','50','100','150','200','250','300','350','400'], fontSize: 9, labelInset: 18 });
    desenharTicksCircular({ groupId: 'ticks-rpm', cx: 370, cy: 100, raio: 62, startAngle: -135, endAngle: 60, steps: 10, majorLen: 7, minorLen: 3, labels: ['0','1','2','3','4','5','6','7','8','9','10'], fontSize: 8, labelInset: 14, redAfter: 8 });
}

function desenharTicksCircular({ groupId, cx, cy, raio, startAngle, endAngle, steps, majorLen = 8, minorLen = 4, redAfter = null, labels = [], fontSize = 10, labelInset = 16 }) {
    const g = document.getElementById(groupId); if (!g) return; const SVG_NS = 'http://www.w3.org/2000/svg'; const span = endAngle - startAngle;
    for (let i = 0; i <= steps; i++) {
        const t = i / steps; const ang = startAngle + span * t; const rad = (ang - 90) * Math.PI / 180;
        const x1 = cx + Math.cos(rad) * (raio - majorLen); const y1 = cy + Math.sin(rad) * (raio - majorLen);
        const x2 = cx + Math.cos(rad) * raio; const y2 = cy + Math.sin(rad) * raio; const isRed = (redAfter !== null && i >= redAfter);
        const tick = document.createElementNS(SVG_NS, 'line'); tick.setAttribute('x1', x1.toFixed(1)); tick.setAttribute('y1', y1.toFixed(1)); tick.setAttribute('x2', x2.toFixed(1)); tick.setAttribute('y2', y2.toFixed(1)); tick.setAttribute('stroke', isRed ? '#ff2a2a' : '#c8c9cd'); tick.setAttribute('stroke-width', '2'); tick.setAttribute('stroke-linecap', 'round'); g.appendChild(tick);
        if (minorLen > 0 && i < steps) {
            for (let k = 1; k < 5; k++) {
                const subT = (i + k / 5) / steps; const subAng = startAngle + span * subT; const subRad = (subAng - 90) * Math.PI / 180; const sx1 = cx + Math.cos(subRad) * (raio - minorLen); const sy1 = cy + Math.sin(subRad) * (raio - minorLen); const sx2 = cx + Math.cos(subRad) * raio; const sy2 = cy + Math.sin(subRad) * raio; const sub = document.createElementNS(SVG_NS, 'line'); sub.setAttribute('x1', sx1.toFixed(1)); sub.setAttribute('y1', sy1.toFixed(1)); sub.setAttribute('x2', sx2.toFixed(1)); sub.setAttribute('y2', sy2.toFixed(1)); sub.setAttribute('stroke', '#5a5c63'); sub.setAttribute('stroke-width', '1'); g.appendChild(sub);
            }
        }
        if (labels[i] && fontSize > 0) {
            const lx = cx + Math.cos(rad) * (raio - labelInset); const ly = cy + Math.sin(rad) * (raio - labelInset) + fontSize * 0.35; const txt = document.createElementNS(SVG_NS, 'text'); txt.setAttribute('x', lx.toFixed(1)); txt.setAttribute('y', ly.toFixed(1)); txt.setAttribute('text-anchor', 'middle'); txt.setAttribute('font-family', "'Segoe UI', sans-serif"); txt.setAttribute('font-size', fontSize); txt.setAttribute('font-weight', '700'); txt.setAttribute('fill', isRed ? '#ff2a2a' : '#c8c9cd'); txt.textContent = labels[i]; g.appendChild(txt);
        }
    }
}

// VeloCore chama this hook quando applyConfig é recebido pelo engine
window.veloOnConfig = function (c) { const n = normalizeIncomingConfig(c); if (n) aplicarCustomizacao(n); };

function abrirPainel(category, cfg) {
    currentCategory = category || currentCategory;
    inpRpm.value = cfg && cfg.urlImagemRpm && cfg.urlImagemRpm !== LOGO_PADRAO ? cfg.urlImagemRpm : '';
    inpSpeed.value = cfg && cfg.urlImagemVelocidade && cfg.urlImagemVelocidade !== LOGO_PADRAO ? cfg.urlImagemVelocidade : '';
    inpFuel.value = cfg && cfg.urlImagemFuel && cfg.urlImagemFuel !== LOGO_PADRAO ? cfg.urlImagemFuel : '';
    colorRpm.value = cfg ? (cfg.corPonteiroRpm || DEFAULT_CONFIG.corPonteiroRpm) : DEFAULT_CONFIG.corPonteiroRpm;
    colorSpeed.value = cfg ? (cfg.corPonteiroVelocidade || DEFAULT_CONFIG.corPonteiroVelocidade) : DEFAULT_CONFIG.corPonteiroVelocidade;
    colorFuel.value = cfg ? (cfg.corPonteiroFuel || DEFAULT_CONFIG.corPonteiroFuel) : DEFAULT_CONFIG.corPonteiroFuel;
    painel.classList.add('open'); painel.setAttribute('aria-hidden', 'false');
}

function fecharPainel() { painel.classList.remove('open'); painel.setAttribute('aria-hidden', 'true'); enviarCallback('velo:closeConfig', {}); }

btnClose.addEventListener('click', fecharPainel);
btnReset.addEventListener('click', () => { aplicarCustomizacao(DEFAULT_CONFIG); try { localStorage.setItem(STORAGE_KEY, JSON.stringify(DEFAULT_CONFIG)); } catch (_) {} if (window.VeloCore && VeloCore.applyConfig) VeloCore.applyConfig({ bg: '', accent: DEFAULT_CONFIG.corPonteiroVelocidade }); });

btnSave.addEventListener('click', () => {
    const cfg = { urlImagemRpm: inpRpm.value.trim() || LOGO_PADRAO, urlImagemVelocidade: inpSpeed.value.trim() || LOGO_PADRAO, urlImagemFuel: inpFuel.value.trim() || LOGO_PADRAO, corPonteiroRpm: colorRpm.value, corPonteiroVelocidade: colorSpeed.value, corPonteiroFuel: colorFuel.value };
    aplicarCustomizacao(cfg);
    try { localStorage.setItem(STORAGE_KEY, JSON.stringify(cfg)); } catch (_) {}
    if (currentCategory) enviarCallback('velo:saveConfig', { category: currentCategory, bgFuel: cfg.urlImagemFuel, bgSpeed: cfg.urlImagemVelocidade, bgRpm: cfg.urlImagemRpm, accent: cfg.corPonteiroVelocidade });
    fecharPainel();
});

window.addEventListener('message', (event) => {
    const payload = event.data; if (!payload || typeof payload !== 'object') return;
    if (payload.type === 'velocimetro:openConfig' || payload.type === 'velocimetro:abrirConfig') { currentCategory = payload.category || currentCategory; const cfg = normalizeIncomingConfig(payload.data || payload || {}); abrirPainel(currentCategory, cfg); }
    else if (payload.type === 'velocimetro:config') { const cfg = normalizeIncomingConfig(payload.data || payload || {}); aplicarCustomizacao(cfg); try { localStorage.setItem(STORAGE_KEY, JSON.stringify(cfg)); } catch (_) {} }
});

document.addEventListener('DOMContentLoaded', () => { if (window.VeloCore && typeof VeloCore.init === 'function') VeloCore.init({ speedPoints: [[0, -135], [400, 135]], rpmPoints: [[0, -135], [10, 60]], fuelPoints: [[0, 135], [100, -135]] }); gerarTicks(); carregarConfigSalva(); });

