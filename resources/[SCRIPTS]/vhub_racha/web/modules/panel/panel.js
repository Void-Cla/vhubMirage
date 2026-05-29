// web/modules/panel/panel.js — menu principal /racha (L4 — modulo isolado).
//
// Consolida shell + 5 views (tracks/lobbies/ranking/history/editor) + modal.
// Decisao de simplicidade: tabs sao views internas (acopladas ao shell, sem
// reuso externo) — nao micro-modulos. Owner do slice store('panel').
//
// Eventos escutados (Lua → core.js dispatcher → bus 'nui:*'):
//   nui:open      abre painel com { catalog, lobbies, ranking, history, cfg }
//   nui:close     fecha painel
//   nui:refresh   atualiza lista de lobbies
//   nui:result    feedback de create/join/leave { ok, kind, data }
//   nui:ranking   dados de ranking
//   nui:history   dados de historico
//   nui:results   resultados de uma corrida historica
//   nui:race_finish  toast de fim de corrida
//   nui:editor_phase / editor_open / editor_draft / editor_close
//
// L-D8 / A-01: NUI nao decide. Toda acao chama vhub.post(endpoint) → Lua valida.


(() => {
    'use strict';

    const { fmtTime, fmtMoney, fmtNum, el } = window.vhubUtils;
    const store = vhub.store('panel');


    // ============================================================
    // CONST — labels e icones por tipo de corrida
    // ============================================================

    const KIND_LABELS = {
        sprint: 'Sprint', circuit: 'Circuito', drag: 'Drag', drift: 'Drift',
        speedtrap: 'Radar', timeattack: 'Contra-relogio', freerun: 'Free Run',
    };
    const KIND_ICONS = {
        sprint: 'fa-solid fa-bolt', circuit: 'fa-solid fa-arrows-rotate',
        drag: 'fa-solid fa-flag-checkered', drift: 'fa-solid fa-wind',
        speedtrap: 'fa-solid fa-gauge-high', timeattack: 'fa-solid fa-stopwatch',
        freerun: 'fa-solid fa-road',
    };

    // Mapeamento de erros do servidor → PT-BR amigavel
    const ERR = {
        sem_sessao:              'Sessao nao encontrada.',
        pista_inexistente:       'Pista nao encontrada.',
        lobby_fechado:           'Esse lobby ja foi iniciado.',
        ja_no_lobby:             'Voce ja esta nesse lobby.',
        ja_em_outra_corrida:     'Voce ja esta em outra corrida.',
        lobby_cheio:             'O lobby esta cheio.',
        saldo_insuficiente:      'Saldo insuficiente para a taxa.',
        sem_grid:                'Sem slots de grade disponiveis.',
        jogadores_insuficientes: 'Jogadores insuficientes para iniciar.',
        nao_e_lobby:             'Nao e mais um lobby aberto.',
        estado_invalido:         'Estado invalido para essa acao.',
        host_left:               'O organizador saiu.',
        fora_da_ready_zone:      'Va ate o ponto de largada para confirmar.',
        fora_do_lobby:           'Voce nao esta nesse lobby.',
        sem_presenca_minima:     'Sem presenca minima confirmada.',
        lobby_expirou:           'Lobby expirou.',
    };
    const errMsg = (raw) => ERR[String(raw || '')] || `Falha: ${raw || 'erro desconhecido'}.`;


    // ============================================================
    // STATE — refs DOM + lifecycle handles
    // ============================================================

    let root    = null;     // module root (.mod-panel)
    let refs    = {};        // map data-el → node
    let busOffs = [];        // off() acumulados (A-07)

    let clickHandler = null; // delegacao de clique (removida no destroy)
    let inputHandler = null;
    let keyHandler   = null;


    // ============================================================
    // HELPERS DOM
    // ============================================================

    function bindRefs(el0) {
        const map = {};
        el0.querySelectorAll('[data-el]').forEach(n => {
            map[n.getAttribute('data-el')] = n;
        });
        return map;
    }

    function setText(key, value) {
        if (refs[key]) refs[key].textContent = value;
    }

    function show(key) { if (refs[key]) refs[key].classList.remove('hidden'); }
    function hide(key) { if (refs[key]) refs[key].classList.add('hidden'); }


    // ============================================================
    // TOAST
    // ============================================================

    function toast(message, kind = 'info') {
        if (!refs['toast-stack']) return;

        const icon = kind === 'success' ? 'fa-circle-check'
                   : kind === 'error'   ? 'fa-triangle-exclamation'
                   :                      'fa-circle-info';

        const t = el('div', { class: `vh-toast ${kind} panel-toast` }, [
            el('i', { class: 'fa-solid ' + icon }),
            el('span', {}, message),
        ]);
        refs['toast-stack'].appendChild(t);

        setTimeout(() => {
            t.classList.add('fade-out');
            setTimeout(() => t.remove(), 250);
        }, 3500);
    }


    // ============================================================
    // RENDER — Pistas
    // ============================================================

    function renderTracks() {
        const grid = refs['tracks-grid'];
        if (!grid) return;

        const data   = store.get();
        const filter = (data.tracksFilter || '').trim().toLowerCase();
        const kind   = data.tracksKind || '';

        let list = data.catalog || [];
        if (kind)   list = list.filter(t => t.kind === kind);
        if (filter) list = list.filter(t =>
            t.label.toLowerCase().includes(filter) ||
            (t.district || '').toLowerCase().includes(filter) ||
            (KIND_LABELS[t.kind] || '').toLowerCase().includes(filter));

        setText('tracks-count', list.length);
        grid.innerHTML = '';

        if (list.length === 0) {
            grid.appendChild(el('div', { class: 'panel-empty' }, [
                el('i', { class: 'fa-solid fa-road' }),
                'Nenhuma pista encontrada.',
            ]));
            return;
        }

        for (const t of list) grid.appendChild(trackCard(t));
    }


    function trackCard(t) {
        const card = el('div', { class: 'vh-card panel-track' });

        const head = el('div', { class: 'panel-track-head' }, [
            el('i', { class: KIND_ICONS[t.kind] || 'fa-solid fa-road' }),
            el('div', { class: 'panel-track-title' }, t.label),
            el('span', { class: 'vh-chip' + (t.illegal ? ' illegal' : '') },
                KIND_LABELS[t.kind] || t.kind),
        ]);
        card.appendChild(head);

        const meta = el('div', { class: 'panel-track-meta' }, [
            el('span', {}, [el('i', { class: 'fa-solid fa-map-marker' }), ' ', el('b', {}, t.district || '—')]),
            el('span', {}, [el('i', { class: 'fa-solid fa-flag' }), ' ', el('b', {}, String(t.cps || 0)), ' CPs']),
            el('span', {}, [el('i', { class: 'fa-solid fa-users' }), ' ', el('b', {}, `${t.min_players}-${t.max_players}`)]),
        ]);
        if (t.laps > 1) {
            meta.appendChild(el('span', {}, [el('i', { class: 'fa-solid fa-arrows-rotate' }), ' ', el('b', {}, String(t.laps)), ' voltas']));
        }
        if (t.alerts_police) {
            meta.appendChild(el('span', { title: 'Alerta policia' }, [el('i', { class: 'fa-solid fa-triangle-exclamation' }), ' Policia']));
        }
        card.appendChild(meta);

        const foot = el('div', { class: 'panel-track-foot' }, [
            el('span', { class: 'panel-track-fee' }, t.default_fee > 0 ? fmtMoney(t.default_fee) : 'Gratis'),
            el('button', { class: 'vh-btn primary', 'data-create': t.id },
                [el('i', { class: 'fa-solid fa-flag-checkered' }), 'Criar lobby']),
        ]);
        card.appendChild(foot);

        return card;
    }


    // ============================================================
    // RENDER — Lobbies
    // ============================================================

    function renderLobbies() {
        const list = refs['lobbies-list'];
        if (!list) return;

        const lobbies = store.get().lobbies || [];
        setText('lobby-count-2', lobbies.length);

        // Badge no tab
        if (refs['lobby-count']) {
            refs['lobby-count'].textContent = lobbies.length;
            refs['lobby-count'].classList.toggle('hidden', lobbies.length === 0);
        }

        list.innerHTML = '';
        if (lobbies.length === 0) {
            list.appendChild(el('div', { class: 'panel-empty' }, [
                el('i', { class: 'fa-solid fa-flag' }),
                'Nenhum lobby aberto. Crie um na aba "Pistas".',
            ]));
            return;
        }

        for (const lb of lobbies) list.appendChild(lobbyRow(lb));
    }


    function lobbyRow(lb) {
        const info = el('div', { class: 'panel-lobby-info' }, [
            el('div', { class: 'panel-lobby-title' }, [
                lb.label || lb.track_id,
                el('span', { class: 'panel-lobby-state ' + lb.state },
                    lb.state === 'pending' ? 'Confirmando' : 'Aberto'),
                lb.mode === 'treino' ? el('span', { class: 'panel-lobby-mode' }, 'TREINO') : null,
            ]),
            el('div', { class: 'panel-lobby-meta' }, [
                `${KIND_LABELS[lb.kind] || lb.kind} · `,
                el('b', {}, `${lb.players}/${lb.max_players}`), ' inscritos · ',
                el('b', {}, fmtMoney(lb.entry_fee || 0)), ' entrada',
            ]),
        ]);

        return el('div', { class: 'panel-lobby' }, [
            el('i', { class: KIND_ICONS[lb.kind] || 'fa-solid fa-road' }),
            info,
            el('button', { class: 'vh-btn primary', 'data-join': lb.id },
                [el('i', { class: 'fa-solid fa-right-to-bracket' }), 'Entrar']),
        ]);
    }


    // ============================================================
    // RENDER — Ranking + Historico
    // ============================================================

    function renderRanking(rows) {
        const tbody = refs['ranking-tbody'];
        if (!tbody) return;

        tbody.innerHTML = '';
        if (!Array.isArray(rows) || rows.length === 0) {
            tbody.appendChild(el('tr', {}, el('td', { class: 'panel-table-empty', colspan: '8' },
                'Sem dados ainda. Quando houver corridas, o ranking aparece aqui.')));
            return;
        }

        rows.forEach((r, i) => {
            const cls = i === 0 ? 'gold' : i === 1 ? 'silver' : i === 2 ? 'bronze' : '';
            tbody.appendChild(el('tr', {}, [
                el('td', { class: cls }, '#' + (i + 1)),
                el('td', {}, r.nick || ('char_' + r.char_id)),
                el('td', {}, String(r.wins || 0)),
                el('td', {}, String(r.podiums || 0)),
                el('td', {}, String(r.dnf || 0)),
                el('td', {}, r.best_time_ms > 0 ? fmtTime(r.best_time_ms) : '—'),
                el('td', {}, fmtNum(r.total_drift || 0)),
                el('td', {}, (r.top_speed || 0) + ' km/h'),
            ]));
        });
    }


    function renderHistory(rows) {
        const tbody = refs['history-tbody'];
        if (!tbody) return;

        tbody.innerHTML = '';
        if (!Array.isArray(rows) || rows.length === 0) {
            tbody.appendChild(el('tr', {}, el('td', { class: 'panel-table-empty', colspan: '9' },
                'Nenhuma corrida registrada ainda.')));
            return;
        }

        for (const h of rows) {
            const when = h.started_unix
                ? new Date(h.started_unix * 1000).toLocaleString('pt-BR',
                    { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' })
                : '—';
            tbody.appendChild(el('tr', {}, [
                el('td', {}, when),
                el('td', {}, KIND_LABELS[h.kind] || h.kind),
                el('td', {}, h.mode === 'treino' ? 'Treino' : 'Rankeada'),
                el('td', {}, h.track_id),
                el('td', {}, String(h.players_total || 0)),
                el('td', {}, h.winner_nick || ('char_' + h.winner_char)),
                el('td', {}, h.winner_time_ms > 0 ? fmtTime(h.winner_time_ms) : '—'),
                el('td', {}, fmtMoney(h.pot_total || 0)),
                el('td', {}, el('button', { class: 'vh-btn ghost', 'data-results': h.id },
                    el('i', { class: 'fa-solid fa-eye' }))),
            ]));
        }
    }


    // ============================================================
    // MODAL — criar lobby
    // ============================================================

    function openCreate(trackId) {
        const track = (store.get().catalog || []).find(t => t.id === trackId);
        if (!track) return;

        store.set({ modalTrack: track });

        setText('modal-track', `${track.label} (${track.district || '—'})`);
        setText('modal-kind', KIND_LABELS[track.kind] || track.kind);
        if (refs['modal-laps']) { refs['modal-laps'].value = track.laps || 1; refs['modal-laps'].max = 10; }
        if (refs['modal-fee'])  { refs['modal-fee'].value  = track.default_fee || 0; refs['modal-fee'].max = store.get().maxFee || 100000; }
        if (refs['modal-mode']) refs['modal-mode'].value = 'rankeada';

        // timeattack/freerun forcam treino sem fee
        if (track.kind === 'timeattack' || track.kind === 'freerun') {
            if (refs['modal-mode']) refs['modal-mode'].value = 'treino';
            if (refs['modal-fee'])  refs['modal-fee'].value = 0;
        }

        show('modal');
    }

    function closeModal() { hide('modal'); }

    function submitCreate() {
        const track = store.get().modalTrack;
        if (!track) return;

        vhub.post('create', {
            track_id:  track.id,
            mode:      refs['modal-mode'] ? refs['modal-mode'].value : 'rankeada',
            laps:      parseInt(refs['modal-laps'] && refs['modal-laps'].value, 10) || 1,
            entry_fee: parseInt(refs['modal-fee'] && refs['modal-fee'].value, 10) || 0,
        });
        closeModal();
    }


    // ============================================================
    // TABS
    // ============================================================

    function switchTab(name) {
        store.set({ activeTab: name });

        root.querySelectorAll('.panel-tab').forEach(t =>
            t.classList.toggle('active', t.dataset.tab === name));
        root.querySelectorAll('.panel-view').forEach(v =>
            v.classList.toggle('active', v.dataset.view === name));

        if (name === 'ranking') {
            vhub.post('ranking', {
                kind: refs['ranking-kind'] ? refs['ranking-kind'].value : 'sprint',
                mode: refs['ranking-mode'] ? refs['ranking-mode'].value : 'wins',
            });
        } else if (name === 'history') {
            vhub.post('history', {
                kind: refs['history-kind'] ? refs['history-kind'].value : '',
            });
        }
    }


    // ============================================================
    // EDITOR
    // ============================================================

    function editorSave() {
        const id = (refs['meta-id'] && refs['meta-id'].value || '').trim();
        if (!id) { toast('Informe um ID para a pista.', 'error'); return; }

        vhub.post('editor_save', {
            id,
            label:         (refs['meta-label'] && refs['meta-label'].value || '').trim(),
            district:      (refs['meta-district'] && refs['meta-district'].value || '').trim() || 'Custom',
            kind:          refs['meta-kind'] ? refs['meta-kind'].value : 'sprint',
            laps:          parseInt(refs['meta-laps'] && refs['meta-laps'].value, 10) || 1,
            default_fee:   parseInt(refs['meta-fee'] && refs['meta-fee'].value, 10) || 0,
            limit_seconds: parseInt(refs['meta-limit'] && refs['meta-limit'].value, 10) || 300,
            illegal:       refs['meta-illegal'] ? refs['meta-illegal'].checked : false,
            alerts_police: refs['meta-police'] ? refs['meta-police'].checked : false,
        });
    }


    // ============================================================
    // OPEN / CLOSE
    // ============================================================

    function onOpen(data) {
        data = data || {};
        store.set({
            open:    true,
            catalog: data.catalog || [],
            lobbies: data.lobbies || [],
            maxFee:  (data.cfg && data.cfg.max_fee) || 100000,
        });

        setText('brand-tag', (data.cfg && data.cfg.brand_tag) || 'Liga clandestina');

        show('shell');
        const bg = root.querySelector('#vhub-bg');
        if (bg) bg.classList.remove('hidden');

        switchTab('tracks');
        renderTracks();
        renderLobbies();
        renderRanking(data.ranking || []);
        renderHistory(data.history || []);

        vhub.sand && vhub.sand.start();
    }


    function onClose() {
        store.set({ open: false });
        hide('shell');
        hide('modal');
        const bg = root.querySelector('#vhub-bg');
        if (bg) bg.classList.add('hidden');
        vhub.sand && vhub.sand.stop();
    }


    // ============================================================
    // RESULT / REFRESH / RANKING / HISTORY
    // ============================================================

    function onResult(r) {
        r = r || {};
        if (r.ok) {
            const k = r.kind || '';
            if      (k === 'create') toast('Lobby criado. Va ao ponto de largada e confirme presenca.', 'success');
            else if (k === 'join')   toast('Voce entrou no lobby. Va ao ponto de largada.', 'success');
            else if (k === 'leave')  toast('Voce saiu do lobby.', 'info');
            else                     toast('Operacao concluida.', 'success');

            vhub.post('refresh_lobbies', {});
            if (k === 'join') switchTab('lobbies');
            if (k === 'create' || k === 'join') setTimeout(() => vhub.post('close', {}), 350);
        } else {
            const code = typeof r.data === 'string' ? r.data : (r.data && r.data.err) || '';
            toast(errMsg(code), 'error');
        }
    }

    function onRefresh(d) {
        d = d || {};
        if (d.lobbies) { store.set({ lobbies: d.lobbies }); renderLobbies(); }
    }

    function onRaceFinish(d) {
        d = d || {};
        toast(`Voce terminou em #${d.placement || '?'} — ${fmtMoney(d.payout || 0)}`,
              d.placement === 1 ? 'success' : 'info');
    }

    // Resultados de uma corrida historica (botao "olho" no historico)
    function onResults(d) {
        d = d || {};
        const rows = d.results || [];
        if (rows.length === 0) { toast('Sem resultados nessa sessao.', 'info'); return; }

        const lines = rows.map(r =>
            `#${r.placement} ${r.nick} — ${fmtTime(r.total_time_ms)}` +
            (r.payout > 0 ? ` (${fmtMoney(r.payout)})` : ''));
        toast(lines.join(' · '), 'info');
    }


    // ============================================================
    // EVENT DELEGATION (bind no root, removido no destroy)
    // ============================================================

    function onClick(ev) {
        const create = ev.target.closest('[data-create]');
        if (create) { openCreate(create.getAttribute('data-create')); return; }

        const join = ev.target.closest('[data-join]');
        if (join) { vhub.post('join', { inst_id: join.getAttribute('data-join') }); return; }

        const results = ev.target.closest('[data-results]');
        if (results) { vhub.post('results', { history_id: results.getAttribute('data-results') }); return; }

        const tab = ev.target.closest('[data-tab]');
        if (tab) { switchTab(tab.dataset.tab); return; }

        const act = ev.target.closest('[data-action]');
        if (!act) return;

        switch (act.dataset.action) {
            case 'close':            vhub.post('close', {}); break;
            case 'refresh':          vhub.post('refresh_lobbies', {}); break;
            case 'modal-close':      closeModal(); break;
            case 'modal-create':     submitCreate(); break;
            case 'refresh-ranking':  switchTab('ranking'); break;
            case 'refresh-history':  switchTab('history'); break;
            case 'editor-start':     vhub.post('editor_open', {}); break;
            case 'editor-phase-grid':vhub.post('editor_phase', { phase: 'grid' }); break;
            case 'editor-phase-cps': vhub.post('editor_phase', { phase: 'cps' }); break;
            case 'editor-phase-meta':vhub.post('editor_phase', { phase: 'meta' }); break;
            case 'editor-discard':   vhub.post('editor_discard', {}); break;
            case 'editor-save':      editorSave(); break;
        }
    }

    function onInput(ev) {
        const key = ev.target.getAttribute('data-el');
        if (key === 'tracks-search')      { store.set({ tracksFilter: ev.target.value }); renderTracks(); }
        if (key === 'tracks-filter-kind') { store.set({ tracksKind: ev.target.value }); renderTracks(); }
    }

    function onKey(ev) {
        if (!store.get().open) return;
        if (ev.key === 'Escape') {
            if (refs['modal'] && !refs['modal'].classList.contains('hidden')) { closeModal(); return; }
            vhub.post('close', {});
        }
    }


    // ============================================================
    // LIFECYCLE
    // ============================================================

    vhub.createModule('panel', {


        onInit() {
            busOffs.push(vhub.bus.listen('nui:open',        onOpen));
            busOffs.push(vhub.bus.listen('nui:close',       onClose));
            busOffs.push(vhub.bus.listen('nui:refresh',     onRefresh));
            busOffs.push(vhub.bus.listen('nui:result',      onResult));
            busOffs.push(vhub.bus.listen('nui:ranking',     (d) => renderRanking((d && d.data) || [])));
            busOffs.push(vhub.bus.listen('nui:history',     (d) => renderHistory(d || [])));
            busOffs.push(vhub.bus.listen('nui:results',     onResults));
            busOffs.push(vhub.bus.listen('nui:race_finish', onRaceFinish));
            busOffs.push(vhub.bus.listen('nui:editor_phase', (d) => {
                const phase = (d && d.phase) || 'idle';
                if (phase === 'grid') toast('Fase 1: posicione os carros da grade.', 'info');
                if (phase === 'cps')  toast('Fase 2: dirija marcando checkpoints.', 'info');
                if (phase === 'meta') { toast('Fase 3: preencha os metadados.', 'info'); switchTab('editor'); }
            }));
        },


        onMount(el0) {
            root = el0;
            refs = bindRefs(el0);

            // Wrapper sempre visivel (overlay persistente). A visibilidade real
            // e controlada internamente por shell/bg/modal (.hidden proprio).
            // Sem isso, o wrapper #mod-panel ficaria display:none e esconderia tudo.
            root.classList.remove('hidden');

            clickHandler = onClick;
            inputHandler = onInput;
            keyHandler   = onKey;

            root.addEventListener('click', clickHandler);
            root.addEventListener('input', inputHandler);
            document.addEventListener('keydown', keyHandler);
        },


        onShow() { /* abertura vem via nui:open */ },
        onHide() { /* noop */ },


        onDestroy() {
            // Remove delegacoes (A-07)
            if (root && clickHandler) root.removeEventListener('click', clickHandler);
            if (root && inputHandler) root.removeEventListener('input', inputHandler);
            if (keyHandler) document.removeEventListener('keydown', keyHandler);

            // Remove listeners do bus
            for (const off of busOffs) { try { off(); } catch (_) {} }
            busOffs = [];

            root = null;
            refs = {};
            clickHandler = inputHandler = keyHandler = null;
        },


    });

})();
