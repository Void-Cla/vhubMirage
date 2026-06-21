// script.js — runtime do toast vHub (render seguro via textContent, ícones unicode, zero CDN)


// ============================================================
// TIPOS (ícone unicode + rótulo PT-BR)
// ============================================================

const TYPES = {
    success: { icon: '✓', label: 'Sucesso' }, // ✓
    error:   { icon: '✕', label: 'Erro' },    // ✕
    warning: { icon: '!',      label: 'Aviso' },
    info:    { icon: 'i',      label: 'Info' },
};

const HIDE_MS = 280; // casa com a animação vhOut do CSS


// ============================================================
// NOTIFIER
// ============================================================

class VHubNotify {
    constructor() {
        this.container = document.getElementById('notification-container');
        this.items = [];
        this.max = 5;
    }

    // exibe um toast já normalizado pelo cliente Lua ({ type, title, msg, duration })
    show(opts) {
        const type = TYPES[opts.type] ? opts.type : 'info';
        const duration = Number(opts.duration) > 0 ? Number(opts.duration) : 5000;

        this.playSound();

        if (this.items.length >= this.max) this.removeOldest();

        const node = this.build(type, opts.title, opts.msg, duration);
        this.container.appendChild(node);
        this.items.push(node);

        node._timer = setTimeout(() => this.remove(node), duration);
        return node;
    }

    // constrói o card via DOM API — texto SEMPRE por textContent (sem XSS)
    build(type, title, msg, duration) {
        const meta = TYPES[type];

        const card = document.createElement('div');
        card.className = `notification notification--${type}`;

        const header = document.createElement('div');
        header.className = 'notification__header';

        const icon = document.createElement('span');
        icon.className = 'notification__icon';
        icon.textContent = meta.icon;

        const badge = document.createElement('span');
        badge.className = 'notification__type';
        badge.textContent = meta.label;

        const titleEl = document.createElement('span');
        titleEl.className = 'notification__title';
        titleEl.textContent = title || meta.label;

        header.append(icon, badge, titleEl);

        const body = document.createElement('div');
        body.className = 'notification__message';
        body.textContent = msg || '';

        const progWrap = document.createElement('div');
        progWrap.className = 'progress-container';

        const prog = document.createElement('div');
        prog.className = 'progress-bar';
        prog.style.animationDuration = `${duration}ms`;
        progWrap.appendChild(prog);

        card.append(header, body, progWrap);
        return card;
    }

    // remove um toast com animação de saída e limpa o timer
    remove(node) {
        if (!node || !node.parentNode) return;
        if (node._timer) { clearTimeout(node._timer); node._timer = null; }

        node.classList.add('is-hiding');
        setTimeout(() => {
            if (node.parentNode) node.parentNode.removeChild(node);
            const i = this.items.indexOf(node);
            if (i > -1) this.items.splice(i, 1);
        }, HIDE_MS);
    }

    // descarta o toast mais antigo quando o limite é atingido
    removeOldest() {
        if (this.items.length) this.remove(this.items[0]);
    }

    // toca o som de notificação (falha silenciosa quando bloqueado)
    playSound() {
        try {
            const audio = new Audio('sound.wav');
            audio.volume = 0.5;
            audio.play().catch(() => {});
        } catch (e) { /* sem áudio: ignora */ }
    }
}


// ============================================================
// BOOT
// ============================================================

const notifier = new VHubNotify();

window.addEventListener('message', (event) => {
    const d = event.data;
    if (!d || d.action !== 'notify') return;
    notifier.show(d.data || {});
});
