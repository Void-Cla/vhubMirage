// web/app_ipad/lspd.js — app EMBUTIDO da Central LSPD (painel policial no iPad).
//
// Porte fiel do painel LSPD com identidade visual vHub. Roda DENTRO da NUI unica
// do iPad, carregado REMOTO de cfx-nui-vhub_lspdtool. A navbar do iPad (◀ ⌂ ×)
// fecha — o app NAO tem botao de fechar nem ESC.
//
// COMUNICACAO = RELAY do iPad (vhub.app.channel('lspd')):
//   • ch.send(action, data)   → ipadRelay(src, action, data) no server do LSPD
//   • ch.on(action, fn)        → push appPush(src, 'lspd', action, data)
//
// O JS so ENVIA acao e RENDERIZA push (A-01): quem valida perm/login/regra
// critica e o SERVER do vhub_lspdtool. SEM setInterval/RAF/polling: render so
// em push. SEM innerHTML com dado do servidor (textContent/el → anti-XSS).
//
// App AUTOCONTIDO: helpers (el) sao locais (o iPad nao expoe window.vhubUtils).
// FontAwesome injetado uma vez no onMount (mesma URL do racha).


(() => {
    'use strict';


    // ============================================================
    // HELPERS LOCAIS — autocontidos (sem window.vhubUtils no remoto)
    // ============================================================

    // Cria elemento + atrs + filhos numa unica chamada. Texto vira textNode
    // (anti-XSS: nunca interpreta dado do servidor como HTML).
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
    // FONTAWESOME — injeta uma vez (mesma URL do racha)
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
    // STATE — relay channel + slice de estado isolado do app
    // ============================================================

    const ch    = vhub.app.channel('lspd');
    const store = vhub.store('lspd');


    // ============================================================
    // CONST — mapa de erros do servidor → PT-BR amigavel
    // ============================================================

    const ERR = {
        id_incorreto:           'ID de personagem incorreto',
        senha_incorreta:        'Senha incorreta',
        char_nao_carregado:     'Personagem nao carregado',
        sem_acesso:             'Acesso restrito (nao e policial)',
        sem_permissao:          'Sem permissao para esta acao',
        placa_invalida:         'Placa invalida',
        veiculo_nao_registrado: 'Veiculo nao registrado',
        ja_apreendido:          'Veiculo ja esta no patio',
        patio_indisponivel:     'Patio indisponivel',
        falha_apreensao:        'Falha ao apreender',
        sem_alvo:               'Nenhum alvo no alcance',
        aguarde:                'Aguarde um instante',
        senha_tamanho:          'Senha deve ter 3 a 32 caracteres',
        char_invalido:          'ID invalido',
        existe:                 'Ja existe',
        limite:                 'Limite atingido',
    };

    // Traduz code do servidor; fallback explicito quando desconhecido.
    function errMsg(code) {
        const raw = String(code || '');
        return ERR[raw] || ('Falha: ' + (raw || 'erro desconhecido'));
    }


    // ============================================================
    // STATE — refs DOM + lifecycle handles
    // ============================================================

    let root = null;     // module root (.mod-lspd)
    let refs = {};        // map data-el → node
    let chOffs = [];      // off() do relay acumulados (A-07)

    let clickHandler = null;  // delegacao de clique (removida no destroy)


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

    // Le valor de um input por data-el (string trim).
    function val(key) {
        return refs[key] ? String(refs[key].value || '').trim() : '';
    }

    // Le valor numerico de um input por data-el (NaN-safe).
    function num(key) {
        return parseInt(refs[key] && refs[key].value, 10);
    }

    // Limpa um input por data-el.
    function clear(key) { if (refs[key]) refs[key].value = ''; }


    // ============================================================
    // TOAST
    // ============================================================

    function toast(message, kind = 'info') {
        if (!refs['toast-stack']) return;

        const icon = kind === 'success' ? 'fa-circle-check'
                   : kind === 'error'   ? 'fa-triangle-exclamation'
                   :                      'fa-circle-info';

        const t = el('div', { class: 'lspd-toast ' + kind }, [
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
    // MAQUINA DE ESTADO — alterna entre as 4 telas
    // ============================================================

    // Mostra UMA das telas (login | changepass | console | denied).
    function setView(view) {
        store.set({ view });

        const map = {
            login:      'view-login',
            changepass: 'view-changepass',
            console:    'view-console',
            denied:     'view-denied',
        };

        for (const k in map) {
            if (k === view) show(map[k]);
            else            hide(map[k]);
        }
    }


    // ============================================================
    // TABS — navegacao interna do console
    // ============================================================

    function switchTab(name) {
        store.set({ tab: name });

        if (!root) return;
        root.querySelectorAll('.lspd-tab').forEach(t =>
            t.classList.toggle('active', t.dataset.tab === name));
        root.querySelectorAll('.lspd-tabview').forEach(v =>
            v.classList.toggle('active', v.dataset.tabview === name));
    }


    // ============================================================
    // RENDER — console completo (primeiro push apos 'open')
    // ============================================================

    function renderConsole() {
        const data    = store.get();
        const officer = data.officer || {};
        const manage  = !!officer.can_manage;

        setText('officer-name', officer.name || '—');

        // forms de criar/remover so aparecem para quem pode gerenciar
        refs['bolo-form']   && refs['bolo-form'].classList.toggle('hidden', !manage);
        refs['wanted-form'] && refs['wanted-form'].classList.toggle('hidden', !manage);

        const bolos  = data.bolos  || [];
        const wanted = data.wanted || [];

        setText('stat-bolos', bolos.length);
        setText('stat-wanted', wanted.length);

        renderScans(data.scans || []);
        renderBolos(bolos, manage, (data.levels && data.levels.bolo) || {});
        renderWanted(wanted, manage, (data.levels && data.levels.wanted) || {});
    }


    // Tabela de leituras recentes (placa / tipo solo|aereo / flag BOLO / hora).
    function renderScans(rows) {
        const tbody = refs['scans-tbody'];
        if (!tbody) return;

        tbody.innerHTML = '';

        if (!Array.isArray(rows) || rows.length === 0) {
            tbody.appendChild(el('tr', {}, el('td', { class: 'lspd-table-empty', colspan: '4' },
                'Nenhuma leitura recente.')));
            return;
        }

        for (const s of rows) {
            const kind = s.src_kind === 'air' ? 'Aereo' : 'Solo';

            const flag = s.flagged
                ? el('span', { class: 'lspd-flag on' }, [el('i', { class: 'fa-solid fa-bullhorn' }), ' BOLO'])
                : el('span', { class: 'lspd-flag off' }, '—');

            tbody.appendChild(el('tr', {}, [
                el('td', {}, s.plate || '—'),
                el('td', {}, kind),
                el('td', {}, flag),
                el('td', {}, fmtTime(s.created_at)),
            ]));
        }
    }


    // Lista de BOLOs (placa / motivo / nivel). Botao remover so se can_manage.
    function renderBolos(rows, manage, levels) {
        const list = refs['bolos-list'];
        if (!list) return;

        list.innerHTML = '';

        if (!Array.isArray(rows) || rows.length === 0) {
            list.appendChild(emptyState('fa-car-burst', 'Nenhum BOLO ativo.'));
            return;
        }

        for (const b of rows) list.appendChild(boloRow(b, manage, levels));
    }


    function boloRow(b, manage, levels) {
        const lvl = parseInt(b.level, 10) || 1;

        const info = el('div', { class: 'lspd-row-info' }, [
            el('div', { class: 'lspd-row-title' }, [
                b.plate || '—',
                levelBadge(lvl, levels),
            ]),
            el('div', { class: 'lspd-row-meta' }, b.reason || 'Sem motivo'),
        ]);

        const children = [el('i', { class: 'fa-solid fa-car-burst' }), info];

        if (manage) {
            children.push(el('button', { class: 'vh-btn danger', 'data-bolo-del': b.plate || '' },
                [el('i', { class: 'fa-solid fa-trash' })]));
        }

        return el('div', { class: 'lspd-row' }, children);
    }


    // Lista de procurados (nome / char_id / motivo / nivel). Remover so se can_manage.
    function renderWanted(rows, manage, levels) {
        const list = refs['wanted-list'];
        if (!list) return;

        list.innerHTML = '';

        if (!Array.isArray(rows) || rows.length === 0) {
            list.appendChild(emptyState('fa-user-secret', 'Nenhum procurado.'));
            return;
        }

        for (const w of rows) list.appendChild(wantedRow(w, manage, levels));
    }


    function wantedRow(w, manage, levels) {
        const lvl = parseInt(w.level, 10) || 1;
        const cid = parseInt(w.char_id, 10) || 0;

        const info = el('div', { class: 'lspd-row-info' }, [
            el('div', { class: 'lspd-row-title' }, [
                w.name || ('char_' + cid),
                levelBadge(lvl, levels),
            ]),
            el('div', { class: 'lspd-row-meta' },
                'ID ' + cid + ' · ' + (w.reason || 'Sem motivo')),
        ]);

        const children = [el('i', { class: 'fa-solid fa-user-secret' }), info];

        if (manage) {
            children.push(el('button', { class: 'vh-btn danger', 'data-wanted-del': String(cid) },
                [el('i', { class: 'fa-solid fa-trash' })]));
        }

        return el('div', { class: 'lspd-row' }, children);
    }


    // ============================================================
    // RENDER — helpers de componente
    // ============================================================

    // Badge de nivel; o rotulo vem de levels[lvl] (do server), com fallback.
    function levelBadge(lvl, levels) {
        const label = (levels && levels[lvl] != null) ? String(levels[lvl]) : ('Nivel ' + lvl);
        const cls   = lvl >= 3 ? 'lspd-level lv3' : lvl === 2 ? 'lspd-level lv2' : 'lspd-level';
        return el('span', { class: cls }, label);
    }

    function emptyState(icon, text) {
        return el('div', { class: 'lspd-empty' }, [
            el('i', { class: 'fa-solid ' + icon }),
            text,
        ]);
    }

    // Unix segundos OU string → "DD/MM HH:MM"; valor invalido vira "—".
    function fmtTime(ts) {
        if (!ts) return '—';
        let d;
        if (typeof ts === 'number') d = new Date(ts * 1000);
        else                        d = new Date(ts);
        if (isNaN(d.getTime())) return String(ts);
        return d.toLocaleString('pt-BR',
            { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' });
    }


    // ============================================================
    // ACOES — envio ao server (so envia; server valida — A-01)
    // ============================================================

    function doLogin() {
        const charId = num('login-charid');
        const pass   = val('login-pass');

        if (!charId || charId < 1) { toast(errMsg('char_invalido'), 'error'); return; }
        if (!pass)                 { toast('Informe a senha.', 'error'); return; }

        ch.send('login', { char_id: charId, password: pass });
    }


    function doChangePass() {
        const p1 = val('cp-pass');
        const p2 = val('cp-pass2');

        if (p1.length < 3 || p1.length > 32) { toast(errMsg('senha_tamanho'), 'error'); return; }
        if (p1 !== p2)                       { toast('As senhas nao conferem.', 'error'); return; }

        ch.send('change_password', { password: p1 });
    }


    function doBoloAdd() {
        const plate  = val('bolo-plate').toUpperCase();
        const reason = val('bolo-reason');
        const level  = num('bolo-level') || 1;

        if (!plate)  { toast(errMsg('placa_invalida'), 'error'); return; }
        if (!reason) { toast('Informe o motivo.', 'error'); return; }

        ch.send('bolo_add', { plate, reason, level });
    }


    function doWantedAdd() {
        const charId = num('wanted-charid');
        const name   = val('wanted-name');
        const reason = val('wanted-reason');
        const level  = num('wanted-level') || 1;

        if (!charId || charId < 1) { toast(errMsg('char_invalido'), 'error'); return; }
        if (!name)                 { toast('Informe o nome.', 'error'); return; }
        if (!reason)               { toast('Informe o motivo.', 'error'); return; }

        ch.send('wanted_add', { char_id: charId, name, reason, level });
    }


    function doSeize() {
        const plate = val('seize-plate').toUpperCase();
        if (!plate) { toast(errMsg('placa_invalida'), 'error'); return; }

        ch.send('seize', { plate });
    }


    // ============================================================
    // PUSH HANDLERS — registrados no onInit (A-07)
    // ============================================================

    // denied → tela de acesso restrito (nao e policial).
    function onDenied() {
        setView('denied');
    }

    // login_required → tela de login.
    function onLoginRequired() {
        setView('login');
    }

    // login_result → ok+must_change vai p/ trocar senha; ok aguarda 'data'; erro toast.
    function onLoginResult(d) {
        d = d || {};
        if (d.ok) {
            if (d.must_change) {
                setView('changepass');
                toast('Defina uma nova senha para continuar.', 'info');
            }
            // ok: aguarda o push 'data' do server para abrir o console.
        } else {
            toast(errMsg(d.err), 'error');
        }
    }

    // pass_changed → ok toast + aguarda 'data'; erro toast.
    function onPassChanged(d) {
        d = d || {};
        if (d.ok) {
            toast('Senha alterada com sucesso.', 'success');
            // aguarda 'data' do server para abrir o console.
        } else {
            toast(errMsg(d.err), 'error');
        }
    }

    // data → estado completo do console; renderiza e mostra a tela.
    function onData(d) {
        d = d || {};
        store.set({
            officer: d.officer || {},
            bolos:   d.bolos   || [],
            wanted:  d.wanted  || [],
            scans:   d.scans   || [],
            levels:  d.levels  || {},
        });

        setView('console');
        switchTab(store.get().tab || 'home');
        renderConsole();
    }

    // action_result → toast de sucesso/erro por tipo de acao.
    function onActionResult(d) {
        d = d || {};

        if (!d.ok) { toast(errMsg(d.err), 'error'); return; }

        const kind  = d.kind || '';
        const name  = d.name  || '';
        const plate = d.plate || '';

        let msg;
        switch (kind) {
            case 'bolo_add':   msg = 'BOLO emitido' + (plate ? ' para ' + plate : '') + '.'; break;
            case 'bolo_del':   msg = 'BOLO removido' + (plate ? ' de ' + plate : '') + '.'; break;
            case 'wanted_add': msg = 'Procurado adicionado' + (name ? ': ' + name : '') + '.'; break;
            case 'wanted_del': msg = 'Procurado removido' + (name ? ': ' + name : '') + '.'; break;
            case 'arrest':     msg = 'Suspeito preso' + (name ? ': ' + name : '') + '.'; break;
            case 'release':    msg = 'Suspeito solto' + (name ? ': ' + name : '') + '.'; break;
            case 'seize':      msg = 'Veiculo apreendido' + (plate ? ': ' + plate : '') + '.'; break;
            default:           msg = 'Operacao concluida.';
        }
        toast(msg, 'success');
    }


    // ============================================================
    // EVENT DELEGATION (bind no root, removido no destroy)
    // ============================================================

    function onClick(ev) {
        // remover BOLO (data-bolo-del = placa)
        const boloDel = ev.target.closest('[data-bolo-del]');
        if (boloDel) {
            ch.send('bolo_del', { plate: boloDel.getAttribute('data-bolo-del') });
            return;
        }

        // remover procurado (data-wanted-del = char_id)
        const wantedDel = ev.target.closest('[data-wanted-del]');
        if (wantedDel) {
            ch.send('wanted_del', { char_id: parseInt(wantedDel.getAttribute('data-wanted-del'), 10) || 0 });
            return;
        }

        // troca de aba do console
        const tab = ev.target.closest('[data-tab]');
        if (tab) { switchTab(tab.dataset.tab); return; }

        // acoes nomeadas
        const act = ev.target.closest('[data-action]');
        if (!act) return;

        switch (act.dataset.action) {
            case 'login':            doLogin(); break;
            case 'changepass-save':  doChangePass(); break;
            case 'open-changepass':  setView('changepass'); break;
            case 'logout':           ch.send('logout'); setView('login'); break;
            case 'bolo-add':         doBoloAdd(); break;
            case 'wanted-add':       doWantedAdd(); break;
            case 'arrest':           ch.send('arrest'); break;
            case 'release':          ch.send('release'); break;
            case 'seize':            doSeize(); break;
        }
    }


    // ============================================================
    // LIFECYCLE (A-02)
    // ============================================================

    vhub.createModule('lspd', {


        onInit() {
            // Push do server (via relay do iPad). off() chamados no onDestroy (A-07).
            chOffs.push(ch.on('denied',         onDenied));
            chOffs.push(ch.on('login_required', onLoginRequired));
            chOffs.push(ch.on('login_result',   onLoginResult));
            chOffs.push(ch.on('pass_changed',   onPassChanged));
            chOffs.push(ch.on('data',           onData));
            chOffs.push(ch.on('action_result',  onActionResult));
        },


        onMount(el0) {
            root = el0;
            refs = bindRefs(el0);

            ensureFontAwesome();

            // estado inicial neutro ate o server responder
            setView('login');

            clickHandler = onClick;
            root.addEventListener('click', clickHandler);
        },


        onShow() {
            // Pede o estado ao server; a tela correta chega no push.
            ch.send('open');
        },


        onHide() { /* noop — sem timers/RAF para pausar */ },


        onDestroy() {
            // Remove delegacao (A-07)
            if (root && clickHandler) root.removeEventListener('click', clickHandler);

            // Remove listeners do relay
            for (const off of chOffs) { try { off(); } catch (_) {} }
            chOffs = [];

            root = null;
            refs = {};
            clickHandler = null;
        },


    });

})();
