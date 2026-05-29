// web/modules/race/race.js — overlay de ready-zone (L4 — modulo isolado).
//
// Sem regra de negocio (A-01): apenas exibe o que o Lua projeta. O totem 3D
// e 100% nativo (client/totem.lua) — nao ha versao NUI dele. Aqui mora APENAS
// a UI de confirmacao de presenca (ready-zone): card de instrucao + ancora.
//
// Eventos escutados (Lua → core.js dispatcher → bus 'nui:*'):
//   nui:vhub_racha.lobby.pending      → mostra ready-zone
//   nui:vhub_racha.lobby.confirmed    → marca confirmado
//   nui:vhub_racha.readyzone.project  → atualiza dist/countdown/ancora
//   nui:vhub_racha.readyzone.clear    → esconde ready-zone
//   nui:hud_hide                      → esconde (fim/inicio de corrida)


(() => {
    'use strict';

    const clamp = (n, lo, hi) => Math.max(lo, Math.min(hi, n));


    // ============================================================
    // STATE
    // ============================================================

    let root = null;
    let refs = {};
    let busOffs = [];

    let rzActive    = false;
    let rzConfirmed = false;


    // ============================================================
    // HELPERS
    // ============================================================

    function bindRefs(el0) {
        const map = {};
        el0.querySelectorAll('[data-el]').forEach(n => {
            map[n.getAttribute('data-el')] = n;
        });
        return map;
    }

    function distLabel(d) {
        d = Math.max(0, Number(d) || 0);
        if (d >= 1000) return (d / 1000).toFixed(1) + ' km';
        return Math.floor(d) + ' m';
    }


    // ============================================================
    // READY ZONE
    // ============================================================

    function showReadyZone(data) {
        if (!refs.readyzone) return;
        data = data || {};

        rzActive    = true;
        rzConfirmed = false;

        if (refs['rz-track']) {
            refs['rz-track'].textContent = String(data.track_label || 'CORRIDA').toUpperCase();
        }
        if (refs['rz-hud'])    refs['rz-hud'].classList.remove('confirmed');
        if (refs['rz-ok'])     refs['rz-ok'].classList.add('hidden');
        if (refs['rz-action']) refs['rz-action'].style.display = '';

        refs.readyzone.classList.remove('hidden');
        refs.readyzone.removeAttribute('aria-hidden');
    }


    function hideReadyZone() {
        rzActive = false;
        if (refs.readyzone) {
            refs.readyzone.classList.add('hidden');
            refs.readyzone.setAttribute('aria-hidden', 'true');
        }
        if (refs['rz-anchor']) refs['rz-anchor'].classList.add('hidden');
    }


    function markConfirmed() {
        rzConfirmed = true;
        if (refs['rz-hud']) refs['rz-hud'].classList.add('confirmed');
        if (refs['rz-ok'])  refs['rz-ok'].classList.remove('hidden');
        if (refs['rz-action']) refs['rz-action'].style.display = 'none';
    }


    function projectReadyZone(p) {
        if (!rzActive || !p) return;

        // Distancia
        if (refs['rz-dist']) {
            refs['rz-dist'].textContent = p.dist_label || distLabel(p.dist);
        }

        // Countdown
        if (refs['rz-countdown']) {
            if (p.remaining_ms > 0) {
                const s  = Math.ceil(p.remaining_ms / 1000);
                const mm = Math.floor(s / 60);
                const ss = s % 60;
                refs['rz-countdown'].textContent =
                    `${String(mm).padStart(2, '0')}:${String(ss).padStart(2, '0')} restante`;
                refs['rz-countdown'].classList.toggle('urgent', s <= 30);
            } else {
                refs['rz-countdown'].textContent = '';
            }
        }

        // Confirmado (idempotente)
        if (p.confirmed && !rzConfirmed) markConfirmed();

        // Ancora 3D projetada
        const anchor = refs['rz-anchor'];
        if (anchor) {
            const x = Number(p.x), y = Number(p.y);
            if (p.visible && Number.isFinite(x) && Number.isFinite(y)) {
                anchor.style.left = clamp(x * 100, 5, 95) + 'vw';
                anchor.style.top  = clamp(y * 100, 5, 95) + 'vh';
                anchor.classList.remove('hidden');
                if (refs['rz-anchor-label']) {
                    refs['rz-anchor-label'].textContent =
                        String(p.track_label || 'LARGADA').toUpperCase();
                }
            } else {
                anchor.classList.add('hidden');
            }
        }
    }


    // ============================================================
    // LIFECYCLE
    // ============================================================

    vhub.createModule('race', {


        onInit() {
            busOffs.push(vhub.bus.listen('nui:vhub_racha.lobby.pending',     showReadyZone));
            busOffs.push(vhub.bus.listen('nui:vhub_racha.lobby.confirmed',   markConfirmed));
            busOffs.push(vhub.bus.listen('nui:vhub_racha.readyzone.project', projectReadyZone));
            busOffs.push(vhub.bus.listen('nui:vhub_racha.readyzone.clear',   hideReadyZone));
            busOffs.push(vhub.bus.listen('nui:hud_hide',                     hideReadyZone));
        },


        onMount(el0) {
            root = el0;
            refs = bindRefs(el0);

            // Wrapper sempre visivel (overlay persistente, pointer-events:none).
            // Visibilidade real e por elemento interno (.hidden da ready-zone).
            root.classList.remove('hidden');
        },


        onShow() { /* aparece via eventos do Lua */ },
        onHide() { hideReadyZone(); },


        onDestroy() {
            for (const off of busOffs) { try { off(); } catch (_) {} }
            busOffs = [];
            root = null;
            refs = {};
            rzActive = false;
            rzConfirmed = false;
        },


    });

})();
