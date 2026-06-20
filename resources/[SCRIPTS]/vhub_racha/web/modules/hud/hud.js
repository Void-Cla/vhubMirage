// web/modules/hud/hud.js — HUD in-race (L4 — modulo isolado).
//
// Lifecycle completo conforme A-02 + cleanup obrigatorio (A-07).
// Estado puramente local (efemero de UI) — comunica com outros modulos
// SOMENTE via bus.
//
// Eventos escutados (do Lua via core.js dispatcher):
//   nui:hud_show       → mostra HUD, recebe { cps_total, laps_total, mode }
//   nui:hud_hide       → esconde HUD
//   nui:hud_start      → re-sincroniza o cronometro (RACE_START)
//   nui:hud_countdown  → exibe contagem 3..2..1..GO (inicia timer no GO)
//   nui:hud_finish     → exibe card de chegada
//   nui:vhub_racha.telemetry  → atualiza speed/cp/drift/distance
//   nui:vhub_racha.bag_update → sincroniza placement


(() => {
    'use strict';

    const { fmtTime, fmtTimeShort, fmtMoney, fmtDist } = window.vhubUtils;


    // ============================================================
    // STATE — refs DOM + lifecycle handles
    // ============================================================

    let el = null;                  // root element (.mod-hud)
    let refs = {};                  // { timer, pos, lap, cp, ... }

    let raf = null;                 // requestAnimationFrame handle
    let countdownInterval = null;   // setInterval do countdown 3..2..1
    let finishTimer = null;         // setTimeout que esconde o card de chegada
    let busOffs = [];               // funcoes off() acumuladas (A-07)

    let startedAt = 0;              // timestamp local em ms (performance.now)


    // ============================================================
    // QUERY HELPER
    // ============================================================

    function findRefs(root) {
        const out = {};
        root.querySelectorAll('[data-el]').forEach(n => {
            out[n.getAttribute('data-el')] = n;
        });
        return out;
    }


    // ============================================================
    // RAF LOOP — atualiza apenas o #timer (1 textContent / frame)
    // ============================================================

    function tick() {
        if (!startedAt) return;

        // Cronometro in-race: SO MM:SS (sem milissegundos — evita piscar).
        // Os milissegundos so aparecem no resultado final (fmtTime).
        const elapsed = performance.now() - startedAt;
        if (refs.timer) refs.timer.textContent = fmtTimeShort(elapsed);

        raf = requestAnimationFrame(tick);
    }


    function startRaf() {
        if (raf) cancelAnimationFrame(raf);
        raf = requestAnimationFrame(tick);
    }


    function stopRaf() {
        if (raf) { cancelAnimationFrame(raf); raf = null; }
    }


    // ============================================================
    // HANDLERS — chamados pelos eventos do bus
    // ============================================================

    // hud_show — chegou em RACE_PREPARE; mostra HUD com totais
    function onShowMsg(data) {
        if (!el) return;

        data = data || {};

        // Lap chip visivel se ha mais de 1 volta
        if (refs.lapChip) {
            refs.lapChip.classList.toggle('hidden', (data.laps_total || 1) <= 1);
        }
        if (refs.cpChip) refs.cpChip.classList.remove('hidden');

        // Drift chip: visivel SEMPRE em modo drift (mostra a contagem desde 0),
        // escondido nos demais modos.
        if (refs.driftChip) {
            refs.driftChip.classList.toggle('hidden', data.kind !== 'drift');
        }

        el.classList.remove('hidden');
    }


    // hud_hide — esconde tudo, para o RAF e limpa o timer do card final
    function onHideMsg() {
        if (finishTimer) { clearTimeout(finishTimer); finishTimer = null; }
        if (!el) return;

        stopRaf();
        startedAt = 0;
        el.classList.add('hidden');
        if (refs.countdown) refs.countdown.classList.add('hidden');
        if (refs.finish)    refs.finish.classList.add('hidden');
    }


    // hud_countdown — exibe numero do contador
    function onCountdownMsg(data) {
        if (!el || !refs.countdown) return;

        const seconds = (data && data.seconds) || 3;

        refs.countdown.classList.remove('hidden', 'go');
        if (refs.countdownNum) refs.countdownNum.textContent = String(seconds);

        // Animar contagem regressiva via setInterval (1Hz)
        // OBS: limpa anterior se existir
        if (countdownInterval) { clearInterval(countdownInterval); countdownInterval = null; }

        let n = seconds;
        countdownInterval = setInterval(() => {
            n--;
            if (n > 0) {
                if (refs.countdownNum) refs.countdownNum.textContent = String(n);
            } else {
                if (refs.countdownNum) refs.countdownNum.textContent = 'GO';
                refs.countdown.classList.add('go');
                clearInterval(countdownInterval);
                countdownInterval = null;

                // Countdown e SO visual. O cronometro inicia no RACE_START
                // (onStartMsg) — fonte unica, sem corrida entre GO e START.
                setTimeout(() => {
                    if (refs.countdown) refs.countdown.classList.add('hidden');
                }, 800);
            }
        }, 1000);
    }


    // hud_start — RACE_START do servidor: inicia o cronometro (fonte unica).
    // Re-sincroniza se ja rodando e o drift passar de 120ms.
    function onStartMsg(data) {
        const offset = (data && data.elapsed_ms) || 0;
        const target = performance.now() - offset;

        if (!startedAt) {
            startedAt = target;
            startRaf();
        } else if (Math.abs(startedAt - target) > 120) {
            startedAt = target;
        }
    }


    // hud_finish — RACE_FINISH; mostra card final por 5s e some.
    function onFinishMsg(data) {
        if (!el || !refs.finish) return;
        data = data || {};

        stopRaf();

        // So o numero da posicao (o "o" sobrescrito vem do HTML — &ordm;)
        if (refs.finishPos) refs.finishPos.textContent = String(parseInt(data.placement || 1));

        // Resultado mostra o tempo COMPLETO (com milissegundos)
        if (refs.finishTime) refs.finishTime.textContent = fmtTime(data.time_ms || 0);

        if (refs.finishPayout) {
            if ((data.payout || 0) > 0) {
                refs.finishPayout.textContent = fmtMoney(data.payout);
                refs.finishPayout.classList.remove('hidden');
            } else {
                refs.finishPayout.classList.add('hidden');
            }
        }

        refs.finish.classList.remove('hidden');

        // Card fica 5s na tela e e destruido (esconde HUD inteiro)
        if (finishTimer) clearTimeout(finishTimer);
        finishTimer = setTimeout(onHideMsg, 5000);
    }


    // telemetry — cp_index / cp_total / lap / drift / distance (sem velocidade)
    function onTelemetry(data) {
        if (!el || !data) return;

        if (refs.cp && data.cp_index != null && data.cp_total != null) {
            refs.cp.textContent = `${data.cp_index}/${data.cp_total}`;
        }
        if (refs.cpDist && data.distance_m != null) {
            refs.cpDist.textContent = fmtDist(data.distance_m);
        }
        if (refs.lap && data.lap != null && data.laps != null) {
            refs.lap.textContent = `${data.lap}/${data.laps}`;
        }
        // Drift: pts vivos, % bancado e combo
        if (refs.drift != null && data.drift_score != null) {
            refs.drift.textContent = String(Math.floor(data.drift_score));
        }
        if (refs.driftPct != null) {
            const live   = Math.max(1, data.drift_score  || 0);
            const banked = Math.min(live, data.drift_banked || 0);
            const pct    = Math.round((banked / live) * 100);
            refs.driftPct.textContent = pct + '%';
        }
        if (refs.driftCombo != null && data.drift_combo != null) {
            const c = Number(data.drift_combo) || 1;
            refs.driftCombo.textContent = 'x' + c.toFixed(1) + ' COMBO';
            // cor progressiva
            refs.driftCombo.className = 'hud-drift-combo'
                + (c >= 3.0 ? ' combo-4' : c >= 2.0 ? ' combo-3' : c >= 1.5 ? ' combo-2' : '');
        }

        // Re-sync timer se servidor reportou drift > 120ms
        if (startedAt && data.elapsed_ms != null) {
            const localElapsed = performance.now() - startedAt;
            if (Math.abs(localElapsed - data.elapsed_ms) > 120) {
                startedAt = performance.now() - data.elapsed_ms;
            }
        }
    }


    // bag_update — placement (posicao corrente)
    function onBagUpdate(bag) {
        if (!refs.pos) return;
        if (bag && bag.placement && bag.placement > 0) {
            refs.pos.textContent = String(bag.placement);
        } else {
            refs.pos.textContent = '--';
        }
    }


    // ============================================================
    // LIFECYCLE
    // ============================================================

    vhub.createModule('hud', {


        // onInit — registra listeners do bus (A-07: guardar offs)
        onInit() {
            busOffs.push(vhub.bus.listen('nui:hud_show',       onShowMsg));
            busOffs.push(vhub.bus.listen('nui:hud_hide',       onHideMsg));
            busOffs.push(vhub.bus.listen('nui:hud_start',      onStartMsg));
            busOffs.push(vhub.bus.listen('nui:hud_countdown',  onCountdownMsg));
            busOffs.push(vhub.bus.listen('nui:hud_finish',     onFinishMsg));
            busOffs.push(vhub.bus.listen('nui:vhub_racha.telemetry', onTelemetry));
            busOffs.push(vhub.bus.listen('nui:vhub_racha.bag_update', onBagUpdate));
        },


        // onMount — DOM disponivel; bind refs
        onMount(rootEl) {
            el   = rootEl;
            refs = findRefs(el);

            // Aliases convenientes pros data-el com hifen
            refs.countdownNum = el.querySelector('[data-el="countdown-num"]');
            refs.lapChip      = el.querySelector('[data-el="lap-chip"]');
            refs.cpChip       = el.querySelector('[data-el="cp-chip"]');
            refs.driftChip    = el.querySelector('[data-el="drift-chip"]');
            refs.finishPos    = el.querySelector('[data-el="finish-pos"]');
            refs.finishTime   = el.querySelector('[data-el="finish-time"]');
            refs.finishPayout = el.querySelector('[data-el="finish-payout"]');
            refs.cpDist       = el.querySelector('[data-el="cp-dist"]');
            refs.driftPct     = el.querySelector('[data-el="drift-pct"]');
            refs.driftCombo   = el.querySelector('[data-el="drift-combo"]');

            // Comeca escondido (RACE_PREPARE mostra)
            el.classList.add('hidden');
        },


        // onShow — modulo visivel (raro pro hud, pois e mostrado via nui:hud_show)
        onShow() { /* noop — show vem por evento do Lua */ },


        // onHide — pausa RAF (modulo voltara a tela so com novo hud_show)
        onHide() {
            stopRaf();
        },


        // onDestroy — cleanup OBRIGATORIO (A-07)
        onDestroy() {
            // Cancela RAF
            stopRaf();

            // Limpa interval do countdown + timer do card final
            if (countdownInterval) {
                clearInterval(countdownInterval);
                countdownInterval = null;
            }
            if (finishTimer) {
                clearTimeout(finishTimer);
                finishTimer = null;
            }

            // Remove TODOS os listeners do bus
            for (const off of busOffs) {
                try { off(); } catch (_) {}
            }
            busOffs = [];

            // Libera refs (GC)
            el   = null;
            refs = {};
        },


    });

})();
