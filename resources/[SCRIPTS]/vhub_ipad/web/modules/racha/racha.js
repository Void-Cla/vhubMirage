// modules/racha/racha.js — APP EMBUTIDO do racha (painel COMPLETO no iPad).
//
// Porte fiel de vhub_racha/web/modules/panel/panel.js: shell + 5 views
// (tracks/lobbies/ranking/history/editor) + modal de criar lobby + toasts.
//
// COMUNICACAO = RELAY do iPad (vhub.app.channel('racha')):
//   • ch.send(action, data)   substitui CADA vhub.post(action, data)
//   • ch.on(action, fn)       substitui CADA vhub.bus.listen('nui:action', fn)
//
// O app roda DENTRO da NUI unica do iPad. A navbar do iPad (◀ ⌂ ×) fecha — o
// app NAO tem botao de fechar nem ESC. Apos create/join, o SERVER do racha fecha
// o iPad (o JS so envia a acao). SEM setInterval/RAF/polling: render so em push.
//
// App AUTOCONTIDO: helpers (el/fmtTime/fmtMoney/fmtNum) sao locais (o iPad nao
// expoe window.vhubUtils). FontAwesome injetado uma vez no onMount.


(() => {
    'use strict';


    // ============================================================
    // HELPERS LOCAIS — copia de vhub_racha/web/shared/utils.js
    // ============================================================

    // Milisegundos → "MM:SS.fff" (ex: 87340 → "01:27.340")
    function fmtTime(ms) {
        ms = Math.max(0, parseInt(ms || 0));
        const m = Math.floor(ms / 60000);
        const s = Math.floor((ms % 60000) / 1000);
        const f = ms % 1000;
        return `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}.${String(f).padStart(3, '0')}`;
    }

    // 1234567 → "1.234.567"
    function fmtNum(n) {
        return Math.max(0, parseInt(n || 0)).toLocaleString('pt-BR');
    }

    // 1234567 → "R$ 1.234.567"
    function fmtMoney(n) {
        n = parseInt(n || 0);
        return 'R$ ' + n.toLocaleString('pt-BR');
    }

    // Cria elemento + atrs + filhos numa unica chamada.
    function el(tag, attrs, children) {
        const node = document.createElement(tag);

        if (attrs && typeof attrs === 'object') {
            for (const k in attrs) {
                if (k === 'class')      node.className = attrs[k];
                else if (k === 'style') Object.assign(node.style, attrs[k]);
                else                    node.setAttribute(k, attrs[k]);
            }
        }

        if (children) {
            const arr = Array.isArray(children) ? children : [children];
            for (const c of arr) {
                if (c == null) continue;
                node.appendChild(typeof c === 'string' ? document.createTextNode(c) : c);
            }
        }

        return node;
    }


    // ============================================================
    // FONTAWESOME — injeta uma vez (mesma URL do index.html do racha)
    // ============================================================

    const FA_ID  = 'vhub-fa-kit';
    const FA_URL = 'https://kit.fontawesome.com/095ee9bcd2.js';

    function ensureFontAwesome() {
        if (document.getElementById(FA_ID)) return;
        const s = document.createElement('script');
        s.id = FA_ID;
        s.src = FA_URL;
        s.crossOrigin = 'anonymous';
        document.head.appendChild(s);
    }


    // ============================================================
    // STATE — relay channel + slice de estado do app
    // ============================================================

    const store = vhub.store('racha');
    const ch    = vhub.app.channel('racha');


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

    let root    = null;     // module root (.mod-racha)
    let refs    = {};        // map data-el → node
    let chOffs  = [];        // off() do relay acumulados (A-07)

    let clickHandler = null; // delegacao de clique (removida no destroy)
    let inputHandler = null;


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

        ch.send('create', {
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
            ch.send('ranking', {
                kind: refs['ranking-kind'] ? refs['ranking-kind'].value : 'sprint',
                mode: refs['ranking-mode'] ? refs['ranking-mode'].value : 'wins',
            });
        } else if (name === 'history') {
            ch.send('history', {
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

        ch.send('editor_save', {
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
    // DATA — estado completo do painel (primeiro push apos 'open')
    // ============================================================

    function onData(data) {
        data = data || {};
        store.set({
            open:    true,
            catalog: data.catalog || [],
            lobbies: data.lobbies || [],
            maxFee:  (data.cfg && data.cfg.max_fee) || 100000,
        });

        setText('brand-tag', (data.cfg && data.cfg.brand_tag) || 'Liga clandestina');

        // mantem a aba atual (default tracks); re-renderiza tudo
        const tab = store.get().activeTab || 'tracks';
        switchTab(tab);
        renderTracks();
        renderLobbies();
        renderRanking(data.ranking || []);
        renderHistory(data.history || []);
    }


    // ============================================================
    // RESULT / REFRESH / RANKING / HISTORY / RESULTS
    // ============================================================

    function onResult(r) {
        r = r || {};
        if (r.ok) {
            const k = r.kind || '';
            if      (k === 'create') toast('Lobby criado. Va ao ponto de largada e confirme presenca.', 'success');
            else if (k === 'join')   toast('Voce entrou no lobby. Va ao ponto de largada.', 'success');
            else if (k === 'leave')  toast('Voce saiu do lobby.', 'info');
            else                     toast('Operacao concluida.', 'success');

            ch.send('refresh');
            if (k === 'join') switchTab('lobbies');
            // create/join: o SERVER do racha fecha o iPad. O app NAO fecha pelo JS.
        } else {
            const code = typeof r.data === 'string' ? r.data : (r.data && r.data.err) || '';
            toast(errMsg(code), 'error');
        }
    }

    function onRefresh(d) {
        d = d || {};
        if (d.lobbies) { store.set({ lobbies: d.lobbies }); renderLobbies(); }
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

    function onEditorPhase(d) {
        const phase = (d && d.phase) || 'idle';
        if (phase === 'grid') toast('Fase 1: posicione os carros da grade.', 'info');
        if (phase === 'cps')  toast('Fase 2: dirija marcando checkpoints.', 'info');
        if (phase === 'meta') { toast('Fase 3: preencha os metadados.', 'info'); switchTab('editor'); }
    }


    // ============================================================
    // EVENT DELEGATION (bind no root, removido no destroy)
    // ============================================================

    function onClick(ev) {
        const create = ev.target.closest('[data-create]');
        if (create) { openCreate(create.getAttribute('data-create')); return; }

        const join = ev.target.closest('[data-join]');
        if (join) { ch.send('join', { inst_id: join.getAttribute('data-join') }); return; }

        const results = ev.target.closest('[data-results]');
        if (results) { ch.send('results', { history_id: results.getAttribute('data-results') }); return; }

        const tab = ev.target.closest('[data-tab]');
        if (tab) { switchTab(tab.dataset.tab); return; }

        const act = ev.target.closest('[data-action]');
        if (!act) return;

        switch (act.dataset.action) {
            case 'refresh':          ch.send('refresh'); break;
            case 'modal-close':      closeModal(); break;
            case 'modal-create':     submitCreate(); break;
            case 'refresh-ranking':  switchTab('ranking'); break;
            case 'refresh-history':  switchTab('history'); break;
            case 'editor-start':     ch.send('editor_open'); break;
            case 'editor-phase-grid':ch.send('editor_phase', { phase: 'grid' }); break;
            case 'editor-phase-cps': ch.send('editor_phase', { phase: 'cps' }); break;
            case 'editor-phase-meta':ch.send('editor_phase', { phase: 'meta' }); break;
            case 'editor-discard':   ch.send('editor_discard'); break;
            case 'editor-save':      editorSave(); break;
        }
    }

    function onInput(ev) {
        const key = ev.target.getAttribute('data-el');
        if (key === 'tracks-search')      { store.set({ tracksFilter: ev.target.value }); renderTracks(); }
        if (key === 'tracks-filter-kind') { store.set({ tracksKind: ev.target.value }); renderTracks(); }
    }


    // ============================================================
    // LIFECYCLE
    // ============================================================

    vhub.createModule('racha', {


        onInit() {
            // Push do server (via relay do iPad). off() chamados no onDestroy (A-07).
            chOffs.push(ch.on('data',         onData));
            chOffs.push(ch.on('refresh',      onRefresh));
            chOffs.push(ch.on('result',       onResult));
            chOffs.push(ch.on('ranking',      (d) => renderRanking((d && d.rows) || [])));
            chOffs.push(ch.on('history',      (d) => renderHistory((d && d.rows) || [])));
            chOffs.push(ch.on('results',      onResults));
            chOffs.push(ch.on('editor_phase', onEditorPhase));
        },


        onMount(el0) {
            root = el0;
            refs = bindRefs(el0);

            ensureFontAwesome();

            clickHandler = onClick;
            inputHandler = onInput;

            root.addEventListener('click', clickHandler);
            root.addEventListener('input', inputHandler);
        },


        onShow() {
            // Pede o estado completo; render chega no push 'data'.
            ch.send('open');
            if (store.get().catalog) {
                // mostra o cache enquanto o fresh nao chega
                renderTracks();
                renderLobbies();
            }
        },


        onHide() { /* noop — sem timers/RAF para pausar */ },


        onDestroy() {
            // Remove delegacoes (A-07)
            if (root && clickHandler) root.removeEventListener('click', clickHandler);
            if (root && inputHandler) root.removeEventListener('input', inputHandler);

            // Remove listeners do relay
            for (const off of chOffs) { try { off(); } catch (_) {} }
            chOffs = [];

            root = null;
            refs = {};
            clickHandler = inputHandler = null;
        },


    });

})();
