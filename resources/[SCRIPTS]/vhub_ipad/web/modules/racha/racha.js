// modules/racha/racha.js — APP EMBUTIDO do racha (FONTE UNICA da UI do racha).
//
// O painel standalone do vhub_racha foi REMOVIDO: esta e a unica casa da UI de
// pistas/lobbies/ranqueado/perfil/ranking/historico/editor. O in-game (totem,
// blip, ready-zone, HUD) continua nativo em Lua no vhub_racha (JS nunca toca GTA5).
//
// COMUNICACAO = RELAY do iPad (vhub.app.channel('racha')):
//   • ch.send(action, data)   → server do racha (export ipadRelay)
//   • ch.on(action, fn)       → push do server (appPush)
//
// Icones = SVG embutido (vhub_ipad nao usa FontAwesome / nenhum CDN — A-10).
// App AUTOCONTIDO: helpers locais; render so em push (sem polling, A-08/L-06).


(() => {
    'use strict';


    // ============================================================
    // HELPERS LOCAIS (formatadores + criacao de elemento)
    // ============================================================

    function fmtTime(ms) {
        ms = Math.max(0, parseInt(ms || 0));
        const m = Math.floor(ms / 60000);
        const s = Math.floor((ms % 60000) / 1000);
        const f = ms % 1000;
        return `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}.${String(f).padStart(3, '0')}`;
    }

    function fmtNum(n)   { return Math.max(0, parseInt(n || 0)).toLocaleString('pt-BR'); }
    function fmtMoney(n) { return 'R$ ' + parseInt(n || 0).toLocaleString('pt-BR'); }

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
    // ICONES — registry SVG embutido (sem FontAwesome / sem CDN)
    // ============================================================

    const ICONS = {
        'road':              '<path d="M4 20 9 4"/><path d="M20 20 15 4"/><path d="M12 5v2M12 11v2M12 17v2"/>',
        'flag':              '<path d="M5 21V4"/><path d="M5 4h12l-2 4 2 4H5"/>',
        'flag-checkered':    '<path d="M5 21V4"/><rect x="5" y="5" width="14" height="9"/><g fill="currentColor" stroke="none"><rect x="5" y="5" width="4.66" height="3"/><rect x="14.34" y="5" width="4.66" height="3"/><rect x="9.67" y="8" width="4.66" height="3"/><rect x="5" y="11" width="4.66" height="3"/><rect x="14.34" y="11" width="4.66" height="3"/></g>',
        'ranking-star':      '<path d="M12 3l2.4 5 5.6.5-4.2 3.7 1.3 5.4L12 17.8 6.9 20.6l1.3-5.4L4 11.5l5.6-.5z"/>',
        'clock-rotate-left': '<path d="M3.5 12a8.5 8.5 0 1 0 2.6-6.1"/><path d="M3 4v4h4"/><path d="M12 8v4l3 2"/>',
        'pen-ruler':         '<path d="M4 20l3.5-1 9-9-2.5-2.5-9 9z"/><path d="M13.5 6.5 16 9"/><path d="M17 7l3-3-2.5-2.5-3 3"/>',
        'xmark':             '<path d="M6 6l12 12M18 6 6 18"/>',
        'magnifying-glass':  '<circle cx="11" cy="11" r="7"/><path d="M21 21l-4.3-4.3"/>',
        'arrows-rotate':     '<path d="M21 12a9 9 0 1 1-2.6-6.4"/><path d="M21 3v5h-5"/>',
        'plus':              '<path d="M12 5v14M5 12h14"/>',
        'car':               '<path d="M3 13l2-5.2A2 2 0 0 1 6.9 6.5h10.2A2 2 0 0 1 19 7.8L21 13"/><path d="M3 13h18v5H3z"/><circle cx="7.5" cy="18" r="1.4"/><circle cx="16.5" cy="18" r="1.4"/>',
        'list':              '<path d="M8 6h13M8 12h13M8 18h13"/><path d="M3.5 6h.01M3.5 12h.01M3.5 18h.01"/>',
        'trash':             '<path d="M3 6h18"/><path d="M8 6V4h8v2"/><path d="M6 6l1 14h10l1-14"/><path d="M10 11v5M14 11v5"/>',
        'floppy-disk':       '<path d="M5 3h11l3 3v15H5z"/><path d="M8 3v5h7V3"/><rect x="8" y="13" width="8" height="5"/>',
        'right-to-bracket':  '<path d="M15 3h4a1 1 0 0 1 1 1v16a1 1 0 0 1-1 1h-4"/><path d="M10 17l5-5-5-5"/><path d="M15 12H3"/>',
        'eye':               '<path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>',
        'map-marker':        '<path d="M12 21s7-6.6 7-12a7 7 0 1 0-14 0c0 5.4 7 12 7 12z"/><circle cx="12" cy="9" r="2.5"/>',
        'users':             '<circle cx="9" cy="8" r="3.4"/><path d="M2.5 20a6.5 6.5 0 0 1 13 0"/><path d="M16 4.8a3.4 3.4 0 0 1 0 6.4"/><path d="M18.5 20a6.5 6.5 0 0 0-3-5.3"/>',
        'lock':              '<rect x="5" y="11" width="14" height="9" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>',
        'bolt':              '<path d="M13 2 4 14h7l-1 8 9-12h-7l1-8z"/>',
        'wind':              '<path d="M3 8h11a3 3 0 1 0-3-3"/><path d="M3 12h15a3 3 0 1 1-3 3"/><path d="M3 16h7a2.5 2.5 0 1 1-2.5 2.5"/>',
        'gauge-high':        '<path d="M3.5 17a9 9 0 1 1 17 0"/><path d="M12 16l4.5-3.5"/><circle cx="12" cy="16" r="1.2"/>',
        'stopwatch':         '<circle cx="12" cy="13.5" r="7.5"/><path d="M12 13.5V9.5"/><path d="M9.5 2.5h5"/><path d="M12 2.5v3"/>',
        'circle-check':        '<circle cx="12" cy="12" r="9"/><path d="M8 12l3 3 5-6"/>',
        'triangle-exclamation':'<path d="M12 3 2 20h20L12 3z"/><path d="M12 9v5"/><path d="M12 17h.01"/>',
        'circle-info':         '<circle cx="12" cy="12" r="9"/><path d="M12 11v5"/><path d="M12 8h.01"/>',
        'user':              '<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>',
        'medal':             '<path d="M8 3h8l-2.5 7h-3z"/><circle cx="12" cy="16" r="5"/><path d="M12 14l1 2 2 .2-1.5 1.4.4 2-1.9-1-1.9 1 .4-2L9.5 16l2-.2z" fill="currentColor" stroke="none"/>',
        'crown':             '<path d="M3 7l4 4 5-6 5 6 4-4-2 12H5z"/>',
        'shield-halved':     '<path d="M12 3l8 3v5c0 5-3.5 8.5-8 10-4.5-1.5-8-5-8-10V6z"/><path d="M12 3v17"/>',
        'chart-simple':      '<path d="M6 20V10M12 20V4M18 20v-7"/>',
    };
    const ICON_STYLE = 'width:1em;height:1em;display:inline-block;vertical-align:-0.125em;flex-shrink:0';

    function svgStr(name, cls) {
        const inner = ICONS[name] || ICONS['circle-info'];
        return '<svg class="vh-icon' + (cls ? ' ' + cls : '') + '" viewBox="0 0 24 24" fill="none"'
             + ' stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"'
             + ' style="' + ICON_STYLE + '" aria-hidden="true">' + inner + '</svg>';
    }
    function icon(name, cls) {
        const box = document.createElement('span');
        box.innerHTML = svgStr(name, cls);   // conteudo constante e controlado: seguro
        return box.firstChild;
    }
    function hydrateIcons(root) {
        (root || document).querySelectorAll('[data-icon]').forEach(node => {
            const name = node.getAttribute('data-icon');
            if (!name) return;
            node.innerHTML = svgStr(name);
            node.removeAttribute('data-icon');
        });
    }


    // ============================================================
    // CONST — labels / estilos
    // ============================================================

    const store = vhub.store('racha');
    const ch    = vhub.app.channel('racha');

    const KIND_LABELS = {
        sprint: 'Sprint', circuit: 'Circuito', drag: 'Drag', drift: 'Drift',
        speedtrap: 'Radar', timeattack: 'Contra-relogio', freerun: 'Free Run',
    };
    const KIND_ICONS = {
        sprint: 'bolt', circuit: 'arrows-rotate', drag: 'flag-checkered', drift: 'wind',
        speedtrap: 'gauge-high', timeattack: 'stopwatch', freerun: 'road',
    };

    // Categoria da pista (temporadas). Cor/label de PRESENTACAO (regra no server).
    const CAT_STYLE = {
        ranqueada:     { label: 'Ranqueada',     color: '#f3c038', icon: 'shield-halved' },
        normal:        { label: 'Normal',        color: '#8fb7e8', icon: 'flag' },
        personalizada: { label: 'Personalizada', color: '#c08bff', icon: 'pen-ruler' },
    };

    // Divisoes do ranqueado (key → cor/icone). Presentacao; faixa de PDL e do server.
    const DIV_STYLE = {
        bronze:   { color: '#cd7f44', icon: 'shield-halved' },
        prata:    { color: '#c2cad6', icon: 'shield-halved' },
        ouro:     { color: '#f3c038', icon: 'medal' },
        platina:  { color: '#58d6cb', icon: 'medal' },
        diamante: { color: '#7db8ff', icon: 'medal' },
        mestre:   { color: '#c08bff', icon: 'crown' },
        lendario: { color: '#ff5d73', icon: 'crown' },
    };
    const ROMAN = ['', 'I', 'II', 'III'];

    const ERR = {
        sem_sessao:               'Sessao nao encontrada.',
        pista_inexistente:        'Pista nao encontrada.',
        lobby_fechado:            'Esse lobby ja foi iniciado.',
        ja_no_lobby:              'Voce ja esta nesse lobby.',
        ja_em_outra_corrida:      'Voce ja esta em outra corrida.',
        lobby_cheio:              'O lobby esta cheio.',
        saldo_insuficiente:       'Saldo insuficiente para a taxa.',
        sem_grid:                 'Sem slots de grade disponiveis.',
        jogadores_insuficientes:  'Jogadores insuficientes para iniciar.',
        nao_e_lobby:              'Nao e mais um lobby aberto.',
        estado_invalido:          'Estado invalido para essa acao.',
        host_left:                'O organizador saiu.',
        fora_da_ready_zone:       'Va ate o ponto de largada para confirmar.',
        fora_do_lobby:            'Voce nao esta nesse lobby.',
        sem_presenca_minima:      'Sem presenca minima confirmada.',
        lobby_expirou:            'Lobby expirou.',
        senha_obrigatoria:        'Pista personalizada exige senha no lobby.',
        senha_incorreta:          'Senha incorreta.',
        modo_invalido_para_pista: 'Modo invalido para essa pista.',
    };
    const errMsg = (raw) => ERR[String(raw || '')] || `Falha: ${raw || 'erro desconhecido'}.`;


    // ============================================================
    // STATE — refs DOM + lifecycle handles
    // ============================================================

    let root    = null;
    let refs    = {};
    let chOffs  = [];
    let clickHandler = null;
    let inputHandler = null;


    // ============================================================
    // HELPERS DOM
    // ============================================================

    function bindRefs(el0) {
        const map = {};
        el0.querySelectorAll('[data-el]').forEach(n => { map[n.getAttribute('data-el')] = n; });
        return map;
    }
    function setText(key, value) { if (refs[key]) refs[key].textContent = value; }
    function show(key) { if (refs[key]) refs[key].classList.remove('hidden'); }
    function hide(key) { if (refs[key]) refs[key].classList.add('hidden'); }

    function categoryBadge(cat) {
        const s = CAT_STYLE[cat] || CAT_STYLE.normal;
        return el('span', { class: 'panel-cat-badge', style: { color: s.color, borderColor: s.color } },
            [icon(s.icon), el('b', {}, s.label)]);
    }

    function divisionBadge(d, big) {
        d = d || {};
        const s = DIV_STYLE[d.key] || { color: '#f3c038', icon: 'shield-halved' };
        const tier = d.tier ? ' ' + (ROMAN[d.tier] || '') : '';
        return el('span', {
            class: 'panel-div-badge' + (big ? ' big' : ''),
            style: { color: s.color, borderColor: s.color },
        }, [icon(s.icon), el('b', {}, (d.label || '—') + tier)]);
    }


    // ============================================================
    // TOAST
    // ============================================================

    function toast(message, kind = 'info') {
        if (!refs['toast-stack']) return;
        const iconName = kind === 'success' ? 'circle-check'
                       : kind === 'error'   ? 'triangle-exclamation'
                       :                      'circle-info';
        const t = el('div', { class: `vh-toast ${kind} panel-toast` }, [icon(iconName), el('span', {}, message)]);
        refs['toast-stack'].appendChild(t);
        setTimeout(() => { t.classList.add('fade-out'); setTimeout(() => t.remove(), 250); }, 3500);
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
        const cat    = data.tracksCat || '';

        let list = data.catalog || [];
        if (kind) list = list.filter(t => t.kind === kind);
        if (cat)  list = list.filter(t => (t.category || 'normal') === cat);
        if (filter) list = list.filter(t =>
            t.label.toLowerCase().includes(filter) ||
            (t.district || '').toLowerCase().includes(filter) ||
            (KIND_LABELS[t.kind] || '').toLowerCase().includes(filter));

        setText('tracks-count', list.length);
        grid.innerHTML = '';
        if (list.length === 0) {
            grid.appendChild(el('div', { class: 'panel-empty' }, [icon('road'), 'Nenhuma pista encontrada.']));
            return;
        }
        for (const t of list) grid.appendChild(trackCard(t));
    }

    function trackCard(t) {
        const card = el('div', { class: 'vh-card panel-track' });

        card.appendChild(el('div', { class: 'panel-track-head' }, [
            icon(KIND_ICONS[t.kind] || 'road'),
            el('div', { class: 'panel-track-title' }, t.label),
            categoryBadge(t.category || 'normal'),
        ]));

        const meta = el('div', { class: 'panel-track-meta' }, [
            el('span', {}, [icon('map-marker'), ' ', el('b', {}, t.district || '—')]),
            el('span', {}, [icon('flag'), ' ', el('b', {}, String(t.cps || 0)), ' CPs']),
            el('span', {}, [icon('users'), ' ', el('b', {}, `${t.min_players}-${t.max_players}`)]),
            el('span', { class: 'vh-chip' + (t.illegal ? ' illegal' : '') }, KIND_LABELS[t.kind] || t.kind),
        ]);
        if (t.laps > 1) meta.appendChild(el('span', {}, [icon('arrows-rotate'), ' ', el('b', {}, String(t.laps)), ' voltas']));
        if (t.alerts_police) meta.appendChild(el('span', { title: 'Alerta policia' }, [icon('triangle-exclamation'), ' Policia']));
        card.appendChild(meta);

        card.appendChild(el('div', { class: 'panel-track-foot' }, [
            el('span', { class: 'panel-track-fee' }, t.default_fee > 0 ? fmtMoney(t.default_fee) : 'Gratis'),
            el('button', { class: 'vh-btn primary', 'data-create': t.id }, [icon('flag-checkered'), 'Criar lobby']),
        ]));
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
        if (refs['lobby-count']) {
            refs['lobby-count'].textContent = lobbies.length;
            refs['lobby-count'].classList.toggle('hidden', lobbies.length === 0);
        }

        list.innerHTML = '';
        if (lobbies.length === 0) {
            list.appendChild(el('div', { class: 'panel-empty' }, [icon('flag'), 'Nenhum lobby aberto. Crie um na aba "Pistas".']));
            return;
        }
        for (const lb of lobbies) list.appendChild(lobbyRow(lb));
    }

    function lobbyRow(lb) {
        const title = el('div', { class: 'panel-lobby-title' }, [
            lb.label || lb.track_id,
            el('span', { class: 'panel-lobby-state ' + lb.state }, lb.state === 'pending' ? 'Confirmando' : 'Aberto'),
            categoryBadge(lb.category || 'normal'),
            lb.has_password ? el('span', { class: 'panel-lobby-lock', title: 'Protegido por senha' }, icon('lock')) : null,
        ]);

        const info = el('div', { class: 'panel-lobby-info' }, [
            title,
            el('div', { class: 'panel-lobby-meta' }, [
                `${KIND_LABELS[lb.kind] || lb.kind} · `,
                el('b', {}, `${lb.players}/${lb.max_players}`), ' inscritos · ',
                el('b', {}, fmtMoney(lb.entry_fee || 0)), ' entrada',
            ]),
        ]);

        return el('div', { class: 'panel-lobby' }, [
            icon(KIND_ICONS[lb.kind] || 'road'),
            info,
            el('button', { class: 'vh-btn primary', 'data-join': lb.id, 'data-pass': lb.has_password ? '1' : '0' },
                [icon('right-to-bracket'), 'Entrar']),
        ]);
    }


    // ============================================================
    // RENDER — Ranking (por modalidade)
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


    // ============================================================
    // RENDER — Historico
    // ============================================================

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
                el('td', {}, categoryBadge(h.category || 'normal')),
                el('td', {}, h.track_id),
                el('td', {}, String(h.players_total || 0)),
                el('td', {}, h.winner_nick || ('char_' + h.winner_char)),
                el('td', {}, h.winner_time_ms > 0 ? fmtTime(h.winner_time_ms) : '—'),
                el('td', {}, fmtMoney(h.pot_total || 0)),
                el('td', {}, el('button', { class: 'vh-btn ghost', 'data-results': h.id }, icon('eye'))),
            ]));
        }
    }


    // ============================================================
    // RENDER — Ranqueado (ladder PDL)
    // ============================================================

    function renderRanqueado(rows) {
        const tbody = refs['ranqueado-tbody'];
        if (!tbody) return;
        tbody.innerHTML = '';
        if (!Array.isArray(rows) || rows.length === 0) {
            tbody.appendChild(el('tr', {}, el('td', { class: 'panel-table-empty', colspan: '7' },
                'Sem pilotos ranqueados ainda. Corra uma ranqueada com 2+ pilotos.')));
            return;
        }
        rows.forEach((r, i) => {
            const cls = i === 0 ? 'gold' : i === 1 ? 'silver' : i === 2 ? 'bronze' : '';
            const wr = r.matches > 0 ? Math.round((r.wins / r.matches) * 100) : 0;
            tbody.appendChild(el('tr', {}, [
                el('td', { class: cls }, '#' + (i + 1)),
                el('td', {}, r.nick || ('char_' + r.char_id)),
                el('td', {}, divisionBadge(r.division)),
                el('td', { class: 'panel-pdl-cell' }, fmtNum(r.pdl || 0)),
                el('td', {}, fmtNum(r.peak_pdl || 0)),
                el('td', {}, `${r.wins || 0} (${wr}%)`),
                el('td', {}, String(r.matches || 0)),
            ]));
        });
    }


    // ============================================================
    // RENDER — Perfil
    // ============================================================

    function profileStatCell(label, value) {
        return el('div', { class: 'panel-profile-stat' }, [
            el('span', { class: 'panel-profile-stat-val' }, value),
            el('span', { class: 'panel-profile-stat-lbl' }, label),
        ]);
    }

    function renderProfile(data) {
        const host = refs['profile-root'];
        if (!host) return;
        data = data || {};

        const rk  = data.ranked || {};
        const div = rk.division || {};
        const wr  = rk.matches > 0 ? Math.round((rk.wins / rk.matches) * 100) : 0;

        let progress;
        if (div.next_min && div.next_min > (div.floor || 0)) {
            const pct = Math.max(0, Math.min(100, Math.round(((rk.pdl - div.floor) / (div.next_min - div.floor)) * 100)));
            progress = el('div', { class: 'panel-profile-progress' }, [
                el('div', { class: 'panel-profile-progress-bar' },
                    el('div', { class: 'panel-profile-progress-fill', style: { width: pct + '%' } })),
                el('span', { class: 'panel-profile-progress-lbl' }, `${fmtNum(rk.pdl)} / ${fmtNum(div.next_min)} PDL`),
            ]);
        } else {
            progress = el('span', { class: 'panel-profile-progress-lbl' }, 'Divisao maxima atingida');
        }

        const head = el('div', { class: 'panel-profile-head vh-card' }, [
            el('div', { class: 'panel-profile-id' }, [
                el('div', { class: 'panel-profile-avatar' }, icon('user')),
                el('div', {}, [
                    el('div', { class: 'panel-profile-nick' }, data.nick || ('char_' + data.char_id)),
                    rk.provisional ? el('span', { class: 'panel-profile-prov' }, 'Em calibracao') : divisionBadge(div, true),
                ]),
            ]),
            el('div', { class: 'panel-profile-stats' }, [
                profileStatCell('PDL', fmtNum(rk.pdl || 0)),
                profileStatCell('Pico', fmtNum(rk.peak_pdl || 0)),
                profileStatCell('Vitorias', String(rk.wins || 0)),
                profileStatCell('Partidas', String(rk.matches || 0)),
                profileStatCell('Aproveit.', wr + '%'),
            ]),
            progress,
        ]);

        const statRows = (data.stats || []).map(s => el('tr', {}, [
            el('td', {}, [icon(KIND_ICONS[s.kind] || 'road'), ' ', KIND_LABELS[s.kind] || s.kind]),
            el('td', {}, String(s.runs || 0)),
            el('td', {}, String(s.wins || 0)),
            el('td', {}, String(s.podiums || 0)),
            el('td', {}, String(s.dnf || 0)),
            el('td', {}, s.best_time_ms > 0 ? fmtTime(s.best_time_ms) : '—'),
            el('td', {}, fmtNum(s.total_drift || 0)),
            el('td', {}, (s.top_speed || 0) + ' km/h'),
        ]));

        const statsCard = el('div', { class: 'panel-profile-section vh-card' }, [
            el('h3', { class: 'panel-profile-h3' }, [icon('chart-simple'), ' Estatisticas por modalidade']),
            statRows.length === 0
                ? el('div', { class: 'panel-empty' }, 'Nenhuma corrida registrada ainda.')
                : el('table', { class: 'panel-table' }, [
                    el('thead', {}, el('tr', {}, [
                        el('th', {}, 'Modalidade'), el('th', {}, 'Corridas'), el('th', {}, 'Vit.'),
                        el('th', {}, 'Podios'), el('th', {}, 'DNF'), el('th', {}, 'Melhor'),
                        el('th', {}, 'Drift'), el('th', {}, 'Top'),
                    ])),
                    el('tbody', {}, statRows),
                ]),
        ]);

        const recRows = (data.records || []).map(r => el('tr', {}, [
            el('td', {}, r.track_id),
            el('td', {}, r.best_time_ms > 0 ? fmtTime(r.best_time_ms) : '—'),
            el('td', {}, fmtNum(r.best_drift || 0)),
            el('td', {}, (r.top_speed || 0) + ' km/h'),
            el('td', {}, String(r.runs || 0)),
            el('td', {}, String(r.wins || 0)),
        ]));

        const recCard = el('div', { class: 'panel-profile-section vh-card' }, [
            el('h3', { class: 'panel-profile-h3' }, [icon('medal'), ' Recordes por pista']),
            recRows.length === 0
                ? el('div', { class: 'panel-empty' }, 'Nenhum recorde registrado.')
                : el('table', { class: 'panel-table' }, [
                    el('thead', {}, el('tr', {}, [
                        el('th', {}, 'Pista'), el('th', {}, 'Melhor tempo'), el('th', {}, 'Drift'),
                        el('th', {}, 'Top'), el('th', {}, 'Corridas'), el('th', {}, 'Vit.'),
                    ])),
                    el('tbody', {}, recRows),
                ]),
        ]);

        // Carreira (agregados cross-kind)
        const c = data.career || {};
        const careerCard = el('div', { class: 'panel-profile-section vh-card' }, [
            el('h3', { class: 'panel-profile-h3' }, [icon('flag-checkered'), ' Carreira']),
            el('div', { class: 'panel-profile-stats' }, [
                profileStatCell('Corridas', fmtNum(c.runs || 0)),
                profileStatCell('Vitorias', fmtNum(c.wins || 0)),
                profileStatCell('Podios', fmtNum(c.podiums || 0)),
                profileStatCell('Aproveit.', (c.winrate || 0) + '%'),
                profileStatCell('Melhor', c.best_time_ms > 0 ? fmtTime(c.best_time_ms) : '—'),
                profileStatCell('Top vel.', (c.top_speed || 0) + ' km/h'),
                profileStatCell('Ganhos', fmtMoney(c.total_payout || 0)),
                profileStatCell('Favorito', KIND_LABELS[data.favorite_kind] || '—'),
            ]),
        ]);

        // Atividade recente
        const recentRows = (data.recent || []).map(h => {
            const when = h.started_unix
                ? new Date(h.started_unix * 1000).toLocaleString('pt-BR',
                    { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' })
                : '—';
            return el('tr', {}, [
                el('td', {}, when),
                el('td', {}, KIND_LABELS[h.kind] || h.kind),
                el('td', {}, categoryBadge(h.category || 'normal')),
                el('td', {}, h.track_id),
                el('td', {}, h.winner_nick || ('char_' + h.winner_char)),
            ]);
        });
        const recentCard = el('div', { class: 'panel-profile-section vh-card' }, [
            el('h3', { class: 'panel-profile-h3' }, [icon('clock-rotate-left'), ' Atividade recente']),
            recentRows.length === 0
                ? el('div', { class: 'panel-empty' }, 'Nenhuma corrida recente.')
                : el('table', { class: 'panel-table' }, [
                    el('thead', {}, el('tr', {}, [
                        el('th', {}, 'Quando'), el('th', {}, 'Tipo'), el('th', {}, 'Categoria'),
                        el('th', {}, 'Pista'), el('th', {}, 'Vencedor'),
                    ])),
                    el('tbody', {}, recentRows),
                ]),
        ]);

        host.innerHTML = '';
        host.appendChild(head);
        host.appendChild(careerCard);
        host.appendChild(statsCard);
        host.appendChild(recCard);
        host.appendChild(recentCard);
    }


    // ============================================================
    // MODAL — criar lobby (category-aware + senha)
    // ============================================================

    function openCreate(trackId) {
        const track = (store.get().catalog || []).find(t => t.id === trackId);
        if (!track) return;
        const cat = track.category || 'normal';
        store.set({ modalTrack: track });

        setText('modal-track', `${track.label} (${track.district || '—'})`);
        setText('modal-kind', KIND_LABELS[track.kind] || track.kind);
        if (refs['modal-cat']) {
            const s = CAT_STYLE[cat] || CAT_STYLE.normal;
            refs['modal-cat'].textContent = s.label;
            refs['modal-cat'].style.color = s.color;
            refs['modal-cat'].style.borderColor = s.color;
        }
        if (refs['modal-mode-comp']) refs['modal-mode-comp'].textContent = (CAT_STYLE[cat] || CAT_STYLE.normal).label;
        if (refs['modal-laps']) { refs['modal-laps'].value = track.laps || 1; refs['modal-laps'].max = 10; }
        if (refs['modal-fee'])  { refs['modal-fee'].value  = track.default_fee || 0; refs['modal-fee'].max = store.get().maxFee || 100000; }
        if (refs['modal-mode']) refs['modal-mode'].value = 'rankeada';
        if (refs['modal-password']) refs['modal-password'].value = '';

        // timeattack/freerun = treino sem fee
        if (track.kind === 'timeattack' || track.kind === 'freerun') {
            if (refs['modal-mode']) refs['modal-mode'].value = 'treino';
            if (refs['modal-fee'])  refs['modal-fee'].value = 0;
        }

        // Senha so aparece em pista personalizada (obrigatoria)
        if (cat === 'personalizada') show('modal-pass-row'); else hide('modal-pass-row');

        show('modal');
    }

    function closeModal() { hide('modal'); }

    function submitCreate() {
        const track = store.get().modalTrack;
        if (!track) return;
        const cat  = track.category || 'normal';
        const mode = refs['modal-mode'] ? refs['modal-mode'].value : 'rankeada';
        const pass = (refs['modal-password'] && refs['modal-password'].value || '').trim();

        if (cat === 'personalizada' && mode !== 'treino' && pass === '') {
            toast('Pista personalizada exige senha no lobby.', 'error');
            return;
        }

        ch.send('create', {
            track_id:  track.id,
            mode:      mode,
            laps:      parseInt(refs['modal-laps'] && refs['modal-laps'].value, 10) || 1,
            entry_fee: parseInt(refs['modal-fee'] && refs['modal-fee'].value, 10) || 0,
            password:  pass,
        });
        closeModal();
    }


    // ============================================================
    // MODAL — entrar com senha
    // ============================================================

    function openJoin(instId) {
        store.set({ joinInst: instId });
        if (refs['join-password']) refs['join-password'].value = '';
        show('join-modal');
    }
    function closeJoin() { hide('join-modal'); }
    function submitJoin() {
        const instId = store.get().joinInst;
        if (!instId) return;
        ch.send('join', { inst_id: instId, password: (refs['join-password'] && refs['join-password'].value || '').trim() });
        closeJoin();
    }


    // ============================================================
    // TABS
    // ============================================================

    function switchTab(name) {
        store.set({ activeTab: name });
        root.querySelectorAll('.panel-tab').forEach(t => t.classList.toggle('active', t.dataset.tab === name));
        root.querySelectorAll('.panel-view').forEach(v => v.classList.toggle('active', v.dataset.view === name));

        if (name === 'ranking') {
            ch.send('ranking', {
                kind: refs['ranking-kind'] ? refs['ranking-kind'].value : 'sprint',
                mode: refs['ranking-mode'] ? refs['ranking-mode'].value : 'wins',
            });
        } else if (name === 'history') {
            ch.send('history', { kind: refs['history-kind'] ? refs['history-kind'].value : '' });
        } else if (name === 'ranqueado') {
            ch.send('ranked', {});
        } else if (name === 'perfil') {
            ch.send('profile', {});   // char_id resolvido server-side (sessao)
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
    // PUSH HANDLERS (server → relay)
    // ============================================================

    function onData(data) {
        data = data || {};
        store.set({
            open: true,
            catalog: data.catalog || [],
            lobbies: data.lobbies || [],
            maxFee:  (data.cfg && data.cfg.max_fee) || 100000,
        });
        setText('brand-tag', (data.cfg && data.cfg.brand_tag) || 'Liga clandestina');

        const tab = store.get().activeTab || 'tracks';
        switchTab(tab);
        renderTracks();
        renderLobbies();
        renderRanking(data.ranking || []);
        renderHistory(data.history || []);
    }

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
        } else {
            const code = typeof r.data === 'string' ? r.data : (r.data && r.data.err) || '';
            toast(errMsg(code), 'error');
        }
    }

    function onRefresh(d) {
        d = d || {};
        if (d.lobbies) { store.set({ lobbies: d.lobbies }); renderLobbies(); }
    }

    function onResults(d) {
        d = d || {};
        const rows = d.results || [];
        if (rows.length === 0) { toast('Sem resultados nessa sessao.', 'info'); return; }
        const lines = rows.map(r => `#${r.placement} ${r.nick} — ${fmtTime(r.total_time_ms)}` + (r.payout > 0 ? ` (${fmtMoney(r.payout)})` : ''));
        toast(lines.join(' · '), 'info');
    }

    function onEditorPhase(d) {
        const phase = (d && d.phase) || 'idle';
        if (phase === 'grid') toast('Fase 1: posicione os carros da grade.', 'info');
        if (phase === 'cps')  toast('Fase 2: dirija marcando checkpoints.', 'info');
        if (phase === 'meta') { toast('Fase 3: preencha os metadados.', 'info'); switchTab('editor'); }
    }


    // ============================================================
    // EVENT DELEGATION
    // ============================================================

    function onClick(ev) {
        const create = ev.target.closest('[data-create]');
        if (create) { openCreate(create.getAttribute('data-create')); return; }

        const join = ev.target.closest('[data-join]');
        if (join) {
            if (join.getAttribute('data-pass') === '1') openJoin(join.getAttribute('data-join'));
            else ch.send('join', { inst_id: join.getAttribute('data-join') });
            return;
        }

        const results = ev.target.closest('[data-results]');
        if (results) { ch.send('results', { history_id: results.getAttribute('data-results') }); return; }

        const tab = ev.target.closest('[data-tab]');
        if (tab) { switchTab(tab.dataset.tab); return; }

        const act = ev.target.closest('[data-action]');
        if (!act) return;
        switch (act.dataset.action) {
            case 'refresh':           ch.send('refresh'); break;
            case 'modal-close':       closeModal(); break;
            case 'modal-create':      submitCreate(); break;
            case 'join-close':        closeJoin(); break;
            case 'join-confirm':      submitJoin(); break;
            case 'refresh-ranking':   switchTab('ranking'); break;
            case 'refresh-history':   switchTab('history'); break;
            case 'refresh-ranqueado': ch.send('ranked', {}); break;
            case 'editor-start':      ch.send('editor_open'); break;
            case 'editor-phase-grid': ch.send('editor_phase', { phase: 'grid' }); break;
            case 'editor-phase-cps':  ch.send('editor_phase', { phase: 'cps' }); break;
            case 'editor-phase-meta': ch.send('editor_phase', { phase: 'meta' }); break;
            case 'editor-discard':    ch.send('editor_discard'); break;
            case 'editor-save':       editorSave(); break;
        }
    }

    function onInput(ev) {
        const key = ev.target.getAttribute('data-el');
        if (key === 'tracks-search')      { store.set({ tracksFilter: ev.target.value }); renderTracks(); }
        if (key === 'tracks-filter-kind') { store.set({ tracksKind: ev.target.value }); renderTracks(); }
        if (key === 'tracks-filter-cat')  { store.set({ tracksCat: ev.target.value }); renderTracks(); }
    }


    // ============================================================
    // LIFECYCLE
    // ============================================================

    vhub.createModule('racha', {

        onInit() {
            chOffs.push(ch.on('data',         onData));
            chOffs.push(ch.on('refresh',      onRefresh));
            chOffs.push(ch.on('result',       onResult));
            chOffs.push(ch.on('ranking',      (d) => renderRanking((d && d.rows) || [])));
            chOffs.push(ch.on('history',      (d) => renderHistory((d && d.rows) || [])));
            chOffs.push(ch.on('ranked',       (d) => renderRanqueado((d && d.rows) || [])));
            chOffs.push(ch.on('profile',      (d) => renderProfile(d || {})));
            chOffs.push(ch.on('results',      onResults));
            chOffs.push(ch.on('editor_phase', onEditorPhase));
        },

        onMount(el0) {
            root = el0;
            hydrateIcons(el0);
            refs = bindRefs(el0);

            clickHandler = onClick;
            inputHandler = onInput;
            root.addEventListener('click', clickHandler);
            root.addEventListener('input', inputHandler);
        },

        onShow() {
            ch.send('open');
            if (store.get().catalog) { renderTracks(); renderLobbies(); }
        },

        onHide() { /* noop — sem timers/RAF */ },

        onDestroy() {
            if (root && clickHandler) root.removeEventListener('click', clickHandler);
            if (root && inputHandler) root.removeEventListener('input', inputHandler);
            for (const off of chOffs) { try { off(); } catch (_) {} }
            chOffs = [];
            root = null; refs = {}; clickHandler = inputHandler = null;
        },

    });

})();
