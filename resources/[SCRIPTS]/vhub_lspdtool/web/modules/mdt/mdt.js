// mdt.js — MDT / Central de Despacho (FASE C). Módulo INTERATIVO registrado no dispatcher.
// Renderiza BOLOs + scans com DOM SEGURO (textContent, nunca innerHTML de dado do servidor → sem XSS).
// `fetch` só para AÇÃO do usuário (fechar / criar / remover) — nunca em hot path (A-06). Cleanup A-07.

(function () {
    'use strict';

    const root    = document.getElementById('mdt');
    const elBolos = root.querySelector('.js-bolos');
    const elScans = root.querySelector('.js-scans');
    const elCount = root.querySelector('.js-bolo-count');
    const elForm  = root.querySelector('.js-bolo-form');
    const elPlate = root.querySelector('.js-bolo-plate');
    const elReas  = root.querySelector('.js-bolo-reason');
    const elLevel = root.querySelector('.js-bolo-level');

    const RES = 'vhub_lspdtool';

    // envia uma ação ao Lua (callback NUI). Só em ação do usuário.
    function post(cb, data) {
        fetch('https://' + RES + '/' + cb, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data || {}),
        }).catch(function () {});
    }

    // cria elemento com classe + texto (seguro contra XSS — textContent)
    function ce(tag, cls, text) {
        const el = document.createElement(tag);
        if (cls) el.className = cls;
        if (text != null) el.textContent = text;
        return el;
    }

    function fmtTime(ts) {
        if (!ts) return '';
        const d = new Date(typeof ts === 'string' ? ts.replace(' ', 'T') : ts);
        if (isNaN(d.getTime())) return String(ts).slice(11, 16);
        return ('0' + d.getHours()).slice(-2) + ':' + ('0' + d.getMinutes()).slice(-2);
    }


    // ========================================================
    // RENDER
    // ========================================================

    function renderBolos(bolos, levels, canManage) {
        elBolos.textContent = '';
        elCount.textContent = bolos.length;
        if (!bolos.length) elBolos.appendChild(ce('div', 'mdt-empty', 'Nenhum BOLO ativo.'));

        bolos.forEach(function (b) {
            const row = ce('div', 'mdt-row');
            row.appendChild(ce('span', 'plate', b.plate));
            row.appendChild(ce('span', 'reason', b.reason || ''));
            row.appendChild(ce('span', 'lvl', (levels && levels[b.level]) || ('N' + (b.level || 1))));
            if (canManage) {
                const del = ce('button', 'mdt-row__del', '✕');
                del.dataset.plate = b.plate;
                row.appendChild(del);
            }
            elBolos.appendChild(row);
        });
    }

    function renderScans(scans) {
        elScans.textContent = '';
        if (!scans.length) elScans.appendChild(ce('div', 'mdt-empty', 'Nenhum scan recente.'));

        scans.forEach(function (s) {
            const row = ce('div', 'mdt-row');
            row.appendChild(ce('span', 'plate', s.plate));
            if (s.flagged) row.appendChild(ce('span', 'flag', 'BOLO'));
            row.appendChild(ce('span', 'meta', s.src_kind === 'air' ? 'aéreo' : 'solo'));
            row.appendChild(ce('span', 'meta', fmtTime(s.created_at)));
            elScans.appendChild(row);
        });
    }

    function render(data) {
        const canManage = !!data.canManage;
        elForm.hidden = !canManage;
        renderBolos(data.bolos || [], data.levels || {}, canManage);
        renderScans(data.scans || []);
    }


    // ========================================================
    // LISTENERS (adicionados 1×; removidos no onDestroy — A-07)
    // ========================================================

    function onClick(e) {
        const close = e.target.closest('[data-act="close"]');
        if (close) { post('mdtClose'); return; }
        const del = e.target.closest('.mdt-row__del');
        if (del && del.dataset.plate) post('mdtDelBolo', { plate: del.dataset.plate });
    }

    function onSubmit(e) {
        e.preventDefault();
        const plate = (elPlate.value || '').trim().toUpperCase();
        if (!plate) return;
        post('mdtAddBolo', { plate: plate, reason: elReas.value || '', level: parseInt(elLevel.value, 10) || 1 });
        elPlate.value = '';
        elReas.value = '';
    }

    function onKey(e) { if (e.key === 'Escape') post('mdtClose'); }

    root.addEventListener('click', onClick);
    elForm.addEventListener('submit', onSubmit);
    document.addEventListener('keydown', onKey);


    // ========================================================
    // MENSAGENS (Lua → CEF)
    // ========================================================

    function onMessage(type, m) {
        switch (type) {
            case 'mdt:open':
                render(m.data || {});
                root.classList.add('is-open');
                root.setAttribute('aria-hidden', 'false');
                break;

            case 'mdt:close':
                root.classList.remove('is-open');
                root.setAttribute('aria-hidden', 'true');
                break;

            case 'mdt:data':
                render(m.data || {});
                break;
        }
    }

    window.LSPD.register('mdt', {
        onMessage: onMessage,
        onDestroy: function () {
            root.removeEventListener('click', onClick);
            elForm.removeEventListener('submit', onSubmit);
            document.removeEventListener('keydown', onKey);
        },
    });
})();
