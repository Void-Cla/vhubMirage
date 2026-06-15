// Bike adapter — engine VeloCore. velo-core preenche speed/gear/needles/visibilidade;
// veloCustomRender cobre o que falta (fuel% + odômetro). Personalização = logo DENTRO dos círculos.
const STORAGE_KEY = 'vhub_velo:bike:config';

// logo nos círculos (containers já são border-radius:50% + overflow:hidden → não vaza)
function aplicarLogo(url) {
    ['custom-fuel-bg', 'custom-speed-bg', 'custom-rpm-bg'].forEach(id => {
        const el = document.getElementById(id);
        if (el) el.style.backgroundImage = url ? `url('${url}')` : 'none';
    });
}

// velo-core chama isto quando recebe velocimetro:config
window.veloOnConfig = function (cfg) {
    if (!cfg) return;
    if (cfg.accent) document.documentElement.style.setProperty('--velo-accent', cfg.accent);
    aplicarLogo(cfg.bgSpeed || cfg.bgFuel || cfg.bgRpm || cfg.bg || '');
};

// velo-core chama isto a cada update: só o que o engine não cobre (fuel% + odômetro simples)
let lastOdo = null;
window.veloCustomRender = function (state) {
    const fuel = document.getElementById('vehicle-fuel');
    if (fuel) fuel.textContent = Math.round(state.fuel_percent || 0);
    const odo = document.getElementById('vehicle-odometer');
    if (odo) {
        const s = String(Math.max(0, Math.floor(Number(state.odometer_km) || 0))).padStart(6, '0');
        if (s !== lastOdo) {
            lastOdo = s; odo.innerHTML = '';
            for (let i = 0; i < s.length; i++) { const sp = document.createElement('span'); sp.className = 'odo-digit'; sp.textContent = s[i]; odo.appendChild(sp); }
        }
    }
};

document.addEventListener('DOMContentLoaded', () => {
    VeloCore.init({ speedPoints: [[0, -135], [300, 135]], rpmPoints: [[0, -135], [8, 60]] });
    try { const r = localStorage.getItem(STORAGE_KEY); if (r) VeloCore.applyConfig(JSON.parse(r)); } catch (e) {}
});
