// app.js — NUI do vhub_df (Pix MercadoPago)
//
// A NUI é burra por lei (A-01): mostra QR, copia código, exibe status.
// Toda verdade (status/entrega) vem do servidor; aqui só render + timers com cleanup.


// ============================================================
// STATE
// ============================================================

const state = {
    open:      false,
    txid:      null,
    expiresAt: 0,        // unix seconds
    timerId:   null,     // countdown 1s
    pollId:    null,     // checkStatus 5s
    closing:   false,
};

const $ = (id) => document.getElementById(id);

const RES = (typeof GetParentResourceName === 'function')
    ? GetParentResourceName() : 'vhub_df';

// envia callback para o client Lua (fire-and-forget)
function post(name, data) {
    fetch(`https://${RES}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data || {}),
    }).catch(() => {});
}


// ============================================================
// TIMERS — sempre limpos ao fechar (A-07)
// ============================================================

function stopTimers() {
    if (state.timerId) { clearInterval(state.timerId); state.timerId = null; }
    if (state.pollId)  { clearInterval(state.pollId);  state.pollId  = null; }
}

function startTimers() {
    stopTimers();

    // countdown de expiração (1 Hz, só enquanto aberto)
    state.timerId = setInterval(renderCountdown, 1000);
    renderCountdown();

    // re-consulta o status local no servidor (rate do servidor = 3s; 5s aqui)
    state.pollId = setInterval(() => {
        if (state.txid) post('checkStatus', { txid: state.txid });
    }, 5000);
}

function renderCountdown() {
    const left = Math.max(0, state.expiresAt - Math.floor(Date.now() / 1000));
    const mm = String(Math.floor(left / 60)).padStart(2, '0');
    const ss = String(left % 60).padStart(2, '0');

    const el = $('df-timer');
    el.textContent = `Expira em ${mm}:${ss}`;
    el.classList.toggle('urgent', left > 0 && left < 120);

    if (left === 0 && state.open && !state.closing) {
        setStatus('Cobrança expirada.', 'err');
        finishSoon();
    }
}


// ============================================================
// RENDER
// ============================================================

function fmtBRL(n) {
    return (Number(n) || 0).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
}

function setStatus(text, kind) {
    $('df-status-text').textContent = text;
    const dot = $('df-dot');
    dot.classList.remove('ok', 'err');
    if (kind) dot.classList.add(kind);
}

function showOverlay(ok, text) {
    const ov = $('df-overlay');
    ov.classList.remove('hidden');
    ov.classList.toggle('err', !ok);
    $('df-overlay-ico').textContent = ok ? '✓' : '✕';
    $('df-overlay-txt').textContent = text;
}

// encerra a tela após um respiro (sucesso/erro/expiração)
function finishSoon() {
    if (state.closing) return;
    state.closing = true;
    stopTimers();
    setTimeout(() => post('close'), 3500);
}


// ============================================================
// AÇÕES DO SERVIDOR (window message)
// ============================================================

const actions = {

    open(p) {
        state.open      = true;
        state.closing   = false;
        state.txid      = p.txid || null;
        state.expiresAt = Number(p.expiresAt) || 0;

        $('df-amount').textContent = fmtBRL(p.amountBRL);
        $('df-qr').src   = p.qrBase64 ? `data:image/png;base64,${p.qrBase64}` : '';
        $('df-code').value = p.copiaECola || '';

        $('df-overlay').classList.add('hidden');
        $('df-copy-btn').classList.remove('copied');
        $('df-copy-btn').textContent = 'Copiar';
        setStatus('Aguardando pagamento…', null);

        $('df-root').classList.remove('hidden');
        startTimers();
    },

    // status local re-consultado ({ txid, status })
    update(p) {
        if (!state.open || p.txid !== state.txid) return;
        if (p.status === 'pending') return;

        if (p.status === 'approved') {
            // aprovado no banco; a confirmação visual final vem no 'result'
            setStatus('Pagamento aprovado — entregando…', 'ok');
            return;
        }

        const msg = {
            expired:   'Cobrança expirada.',
            cancelled: 'Cobrança cancelada.',
            rejected:  'Pagamento recusado.',
        }[p.status] || 'Cobrança encerrada.';

        setStatus(msg, 'err');
        showOverlay(false, msg);
        finishSoon();
    },

    // desfecho final empurrado pelo servidor (entrega feita)
    result(p) {
        if (!state.open) return;
        if (p.ok) {
            setStatus('Pagamento confirmado!', 'ok');
            showOverlay(true, 'Pagamento aprovado!');
        } else {
            setStatus('Falha na entrega — contate um administrador.', 'err');
            showOverlay(false, 'Falha na entrega');
        }
        finishSoon();
    },

    close() {
        state.open = false;
        state.txid = null;
        stopTimers();
        $('df-root').classList.add('hidden');
    },
};

window.addEventListener('message', (e) => {
    const { action, payload } = e.data || {};
    if (actions[action]) actions[action](payload || {});
});


// ============================================================
// HANDLERS DE UI
// ============================================================

$('df-close').addEventListener('click', () => post('close'));

$('df-cancel').addEventListener('click', () => {
    if (state.txid && !state.closing) post('cancel', { txid: state.txid });
});

$('df-copy-btn').addEventListener('click', () => {
    const input = $('df-code');
    if (!input.value) return;

    input.select();
    input.setSelectionRange(0, input.value.length);

    let ok = false;
    try { ok = document.execCommand('copy'); } catch (_) { /* CEF antigo */ }
    if (!ok && navigator.clipboard) {
        navigator.clipboard.writeText(input.value).catch(() => {});
        ok = true;
    }

    if (ok) {
        const btn = $('df-copy-btn');
        btn.classList.add('copied');
        btn.textContent = 'Copiado!';
        setTimeout(() => {
            btn.classList.remove('copied');
            btn.textContent = 'Copiar';
        }, 1800);
    }
    window.getSelection().removeAllRanges();
});

window.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && state.open) post('close');
});
