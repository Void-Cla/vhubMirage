// web/shared/utils.js — utilitarios puros sem side-effects.
//
// Sem fetch, sem DOM mutation. Apenas formatadores e helpers de criacao
// de elemento. Modulos importam via `window.vhubUtils.X`.


(() => {
    'use strict';


    // ============================================================
    // FORMATADORES DE TEMPO
    // ============================================================

    // Milisegundos → "MM:SS.fff" (ex: 87340 → "01:27.340")
    function fmtTime(ms) {
        ms = Math.max(0, parseInt(ms || 0));
        const m = Math.floor(ms / 60000);
        const s = Math.floor((ms % 60000) / 1000);
        const f = ms % 1000;
        return `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}.${String(f).padStart(3, '0')}`;
    }


    // Milisegundos → "MM:SS" (sem milessegundo, para displays mais limpos)
    function fmtTimeShort(ms) {
        ms = Math.max(0, parseInt(ms || 0));
        const m = Math.floor(ms / 60000);
        const s = Math.floor((ms % 60000) / 1000);
        return `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
    }


    // ============================================================
    // FORMATADORES DE NUMEROS
    // ============================================================

    // 1234567 → "1.234.567" (numero com separador de milhar, sem prefixo)
    function fmtNum(n) {
        return Math.max(0, parseInt(n || 0)).toLocaleString('pt-BR');
    }


    // 1234567 → "R$ 1.234.567"
    function fmtMoney(n) {
        n = parseInt(n || 0);
        return 'R$ ' + n.toLocaleString('pt-BR');
    }


    // 123.456 → "123 km/h" (truncado, sem decimal)
    function fmtSpeed(kmh) {
        return Math.max(0, Math.floor(kmh || 0)) + ' km/h';
    }


    // 12500 (metros) → "12.5 km" / 800 → "800 m"
    function fmtDist(m) {
        m = Math.max(0, parseFloat(m || 0));
        if (m >= 1000) return (m / 1000).toFixed(1) + ' km';
        return Math.floor(m) + ' m';
    }


    // ============================================================
    // DOM HELPER
    // ============================================================

    // Cria elemento + atrs + filhos numa unica chamada.
    //   el('div', { class: 'card', 'data-id': 1 }, [el('span', {}, 'Hi')])
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
    // EXPORT
    // ============================================================

    window.vhubUtils = { fmtTime, fmtTimeShort, fmtNum, fmtMoney, fmtSpeed, fmtDist, el };

})();
