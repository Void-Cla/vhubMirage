// velo-core.js — engine UNIVERSAL do velocímetro vHub. Incluído por TODA HUD via /nui/velo-core.js.
// Gauges com binary-search O(log n), odômetro RAF que PARA quando inativo (idle ~0),
// normalize null-safe, nitro arc, saúde do motor, preview fora do FiveM.
// Cada HUD usa só os IDs padrão que tiver; calibração via VeloCore.init(opts).

(function () {
    'use strict';

    // ---- gauge: pontos [valor, ângulo] → ângulo via binary search + cache lastIndex ----
    function createGauge(points, clamp) {
        clamp = clamp !== false;
        const pts = points.slice().sort((a, b) => a[0] - b[0]);
        const seg = [];
        for (let i = 0; i < pts.length - 1; i++) {
            const [v1, a1] = pts[i], [v2, a2] = pts[i + 1];
            seg.push([v1, v2, a1, (a2 - a1) / (v2 - v1)]);
        }
        let li = 0;
        function get(value) {
            let s = seg[li];
            if (s && value >= s[0] && value <= s[1]) return s[2] + (value - s[0]) * s[3];
            let lo = 0, hi = seg.length - 1;
            while (lo <= hi) {
                const m = (lo + hi) >> 1; s = seg[m];
                if (value < s[0]) hi = m - 1;
                else if (value > s[1]) lo = m + 1;
                else { li = m; return s[2] + (value - s[0]) * s[3]; }
            }
            if (clamp && seg.length) {
                if (value <= seg[0][0]) return seg[0][2];
                const L = seg[seg.length - 1];
                if (value >= L[1]) return L[2] + (L[1] - L[0]) * L[3];
            }
            return seg[0] ? seg[0][2] : 0;
        }
        return { get, min: pts[0][0], max: pts[pts.length - 1][0] };
    }

    // arco do gauge de nitro: r=35, sweep=240° → 2π×35×(240/360) ≈ 146.6
    const NITRO_ARC = 146.6;

    const fallback = {
        visible: false, active: false, speed_kmh: 0, rpm_percent: 0, gear_label: 'N',
        fuel_percent: 0, odometer_km: null, turn_left: false, turn_right: false,
        seatbelt: false, locked: false, heading: 0,
        nitro_percent: 0, engine_health: 100,
    };
    let state = fallback, gauges = {};
    const ODO_H = 11;

    // ---- DOM helpers null-safe ----
    const $        = id        => document.getElementById(id);
    const setText  = (id, v)   => { const e = $(id); if (e) e.textContent = v; };
    const setRot   = (id, deg) => { const e = $(id); if (e) e.style.transform = `rotate(${deg}deg)`; };
    const setStatus = (id, on) => { const e = $(id); if (e) e.dataset.status = on ? 'on' : 'off'; };
    const setSVG   = (id, a, v) => { const e = $(id); if (e) e.setAttribute(a, v); };
    const clampn   = (v, a, b) => { const n = Number(v); return Number.isFinite(n) ? Math.max(a, Math.min(b, n)) : a; };

    function gearOf(d) {
        const l = String(d.gear_label || d.gear || '').trim().toUpperCase();
        if (l === 'R' || l === 'N') return l;
        const g = parseInt(l, 10);
        return Number.isFinite(g) && g > 0 ? String(Math.min(g, 9)) : 'N';
    }
    function splitSpeed(sp) {
        const s = String(Math.round(clampn(sp, 0, 999))).padStart(3, '0');
        return [s.slice(0, 2), s.slice(2)];
    }

    function normalize(d) {
        if (!d || typeof d !== 'object') return fallback;
        const v = (d.vehicle && typeof d.vehicle === 'object') ? d.vehicle : d;
        return {
            visible: d.visible !== false, active: v.active !== false,
            speed_kmh: v.speed_kmh, rpm_percent: v.rpm_percent, gear_label: gearOf(v),
            fuel_percent: v.fuel_percent, odometer_km: v.odometer_km,
            turn_left:  Boolean(v.turn_left  ?? v.indicator_left),
            turn_right: Boolean(v.turn_right ?? v.indicator_right),
            seatbelt: Boolean(v.seatbelt), locked: Boolean(v.locked), heading: Number(v.heading) || 0,
            nitro_percent:  clampn(v.nitro_percent  ?? 0,   0, 100),
            engine_health:  clampn(v.engine_health  ?? 100, 0, 100),
        };
    }


    // ---- odômetro 6 dígitos rolantes (RAF gated: para quando inativo) ----
    let odoKm = 0, lastTick = null, raf = null, lastD = [-1, -1, -1, -1, -1, -1];
    const odoCols = [];
    function renderOdo() {
        const t = Math.floor(clampn(odoKm, 0, 999999)), s = String(t).padStart(6, '0');
        for (let i = 0; i < odoCols.length; i++) {
            const d = Number(s[i]);
            if (d !== lastD[i]) { lastD[i] = d; odoCols[i].style.transform = `translateY(${-d * ODO_H}px)`; }
        }
    }
    function tick(now) {
        if (lastTick == null) lastTick = now;
        const dt = (now - lastTick) / 1000; lastTick = now;
        const a = Number(state.odometer_km), tgt = (Number.isFinite(a) && a >= 0) ? a : 0;
        odoKm += (tgt - odoKm) * Math.min(1, dt * 4);
        renderOdo();
        raf = state.active ? requestAnimationFrame(tick) : null;
    }
    function ensureOdo() { if (raf == null && state.active) { lastTick = null; raf = requestAnimationFrame(tick); } }


    // ---- render (null-safe) ----
    function render() {
        const active = Boolean(state.visible && state.active);
        document.body.classList.toggle('velo-active', active);
        const vroot = $('velo-root'); if (vroot) vroot.classList.toggle('velo-active', active);

        const sp   = clampn(state.speed_kmh, 0, 999);
        const rpm  = clampn(state.rpm_percent, 0, 100);
        const fuel = clampn(state.fuel_percent ?? 0, 0, 100);
        const [pre, val] = splitSpeed(sp);
        setText('vehicle-speed-prefix', pre); setText('vehicle-speed', val);
        setText('speed-value', Math.round(sp));
        setText('vehicle-gear', state.gear_label); setText('gear-value', state.gear_label);
        setText('vehicle-fuel', Math.round(fuel));

        if (gauges.speed) setRot('speed-needle', gauges.speed.get(sp));
        if (gauges.rpm)   setRot('rpm-needle',   gauges.rpm.get(rpm / 10));
        if (gauges.fuel)  setRot('fuel-needle',  gauges.fuel.get(fuel));

        // setas: o main.lua envia a leitura CRUA do nativo (lados trocados) — a correção de lado
        // é CONTRATO desta camada (ver comentário em ler_indicadores). NÃO "consertar" removendo.
        setStatus('status-turn-left',  active && state.turn_right);
        setStatus('status-turn-right', active && state.turn_left);
        setStatus('status-seatbelt',   state.seatbelt);
        setStatus('status-lock',       state.locked);

        // saúde do motor: LED tricolor via data-health (ok/warn/crit)
        const ehEl = $('engine-health-dot');
        if (ehEl) {
            const eh = state.engine_health;
            ehEl.dataset.health = eh > 75 ? 'ok' : eh > 25 ? 'warn' : 'crit';
        }

        // nitro arc: stroke-dashoffset 146.6 (vazio) → 0 (cheio)
        const nitro = state.nitro_percent;
        setSVG('nitro-arc-fill', 'stroke-dashoffset', (NITRO_ARC * (1 - nitro / 100)).toFixed(1));
        setText('nitro-value', Math.round(nitro) + '%');

        if (typeof window.veloCustomRender === 'function') window.veloCustomRender(state);
    }

    function apply(d) { state = normalize(d); render(); ensureOdo(); }


    // ---- personalização: fundos por mostrador + cor de destaque + zoom ----
    function applyConfig(c) {
        c = c || {};
        const root = document.documentElement.style;
        function setBg(prop, url) {
            if (typeof url === 'string')
                root.setProperty(prop, url ? 'url("' + url + '")' : 'none');
        }
        setBg('--velo-bg-speed', c.bgSpeed);
        setBg('--velo-bg-fuel',  c.bgFuel);
        setBg('--velo-bg-rpm',   c.bgRpm);
        // legado: c.bg aplica a todos os três mostradores simultaneamente
        if (typeof c.bg === 'string') {
            setBg('--velo-bg-speed', c.bg); setBg('--velo-bg-fuel', c.bg);
            setBg('--velo-bg-rpm',   c.bg); setBg('--velo-bg',      c.bg);
        }
        if (typeof c.accent === 'string' && c.accent) root.setProperty('--velo-accent', c.accent);
        if (typeof c.zoom   === 'number') root.setProperty('--velo-zoom', String(c.zoom));
        try { if (typeof window.veloOnConfig === 'function') window.veloOnConfig(c); } catch (_) {}
    }


    function init(opts) {
        opts = opts || window.veloOpts || {};
        gauges.speed = createGauge(opts.speedPoints || [[0, -135], [400, 135]]);
        gauges.rpm   = opts.rpmPoints ? createGauge(opts.rpmPoints)
                       : ($('rpm-needle') ? createGauge([[0, -135], [10, 60]]) : null);
        gauges.fuel  = opts.fuelPoints ? createGauge(opts.fuelPoints)
                       : ($('fuel-needle') ? createGauge([[0, -120], [50, -25], [100, 70]]) : null);
        document.querySelectorAll('[data-odo-digit] .odoColumn').forEach(c => odoCols.push(c));

        window.addEventListener('message', e => {
            const m = e.data; if (!m) return;
            if (m.type === 'velocimetro:update') apply(m.data || m.vehicle || fallback);
            else if (m.type === 'velocimetro:config') applyConfig(m.data || m);
        });

        // preview fora do FiveM (calibrar HUD no navegador)
        const fivem = String(location.hostname || '').startsWith('cfx-nui-');
        apply(fivem ? fallback : {
            visible: true, active: true, speed_kmh: 128, rpm_percent: 67,
            gear_label: '4', fuel_percent: 60, locked: true, heading: 90,
            nitro_percent: 65, engine_health: 88,
        });
        renderOdo();
    }

    window.VeloCore = { init, apply, applyConfig, createGauge };
})();
