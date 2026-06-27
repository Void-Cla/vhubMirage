// web/shared/icons.js — registro ÚNICO de ícones SVG inline (sem CDN, A-10).
//
// Substitui o Font Awesome remoto (kit.fontawesome.com) por SVG local: zero
// execução de JS de terceiro na NUI, offline-safe e mais leve no render.
//
// USO:
//   • Markup estático: <span data-icon="road"></span>  → hidratado por vhubIcons.hydrate(root)
//   • Dinâmico (JS):   vhubIcons.get('road')            → retorna um <svg> pronto
//   • Adicionar ícone = 1 entrada em ICONS (fonte única; escala sem tocar nos módulos).
//
// Estilo: stroke currentColor (herda a cor do contexto — dourado/areia do tema).


(() => {
    'use strict';


    // ============================================================
    // REGISTRO — só o miolo (paths) de cada ícone; o wrapper <svg> é comum
    // ============================================================

    const ICONS = {
        // navegação / ações
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

        // tipos de corrida (KIND_ICONS)
        'bolt':              '<path d="M13 2 4 14h7l-1 8 9-12h-7l1-8z"/>',
        'wind':              '<path d="M3 8h11a3 3 0 1 0-3-3"/><path d="M3 12h15a3 3 0 1 1-3 3"/><path d="M3 16h7a2.5 2.5 0 1 1-2.5 2.5"/>',
        'gauge-high':        '<path d="M3.5 17a9 9 0 1 1 17 0"/><path d="M12 16l4.5-3.5"/><circle cx="12" cy="16" r="1.2"/>',
        'stopwatch':         '<circle cx="12" cy="13.5" r="7.5"/><path d="M12 13.5V9.5"/><path d="M9.5 2.5h5"/><path d="M12 2.5v3"/>',

        // estado / toasts
        'circle-check':        '<circle cx="12" cy="12" r="9"/><path d="M8 12l3 3 5-6"/>',
        'triangle-exclamation':'<path d="M12 3 2 20h20L12 3z"/><path d="M12 9v5"/><path d="M12 17h.01"/>',
        'circle-info':         '<circle cx="12" cy="12" r="9"/><path d="M12 11v5"/><path d="M12 8h.01"/>',

        // perfil / ranqueado (PDL)
        'user':              '<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>',
        'medal':             '<path d="M8 3h8l-2.5 7h-3z"/><circle cx="12" cy="16" r="5"/><path d="M12 14l1 2 2 .2-1.5 1.4.4 2-1.9-1-1.9 1 .4-2L9.5 16l2-.2z" fill="currentColor" stroke="none"/>',
        'crown':             '<path d="M3 7l4 4 5-6 5 6 4-4-2 12H5z"/>',
        'shield-halved':     '<path d="M12 3l8 3v5c0 5-3.5 8.5-8 10-4.5-1.5-8-5-8-10V6z"/><path d="M12 3v17"/>',
        'chart-simple':      '<path d="M6 20V10M12 20V4M18 20v-7"/>',
    };

    const ICON_STYLE = 'width:1em;height:1em;display:inline-block;vertical-align:-0.125em;flex-shrink:0';


    // ============================================================
    // API
    // ============================================================

    // string <svg> de um ícone (conteúdo é CONSTANTE do registro — sem dado de usuário)
    function svg(name, cls) {
        const inner = ICONS[name] || ICONS['circle-info'];
        return '<svg class="vh-icon' + (cls ? ' ' + cls : '') + '" viewBox="0 0 24 24" fill="none"'
             + ' stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"'
             + ' style="' + ICON_STYLE + '" aria-hidden="true">' + inner + '</svg>';
    }

    // elemento <svg> pronto para appendChild (dinâmico, em JS)
    function get(name, cls) {
        const box = document.createElement('span');
        box.innerHTML = svg(name, cls);   // conteúdo constante e controlado: seguro
        return box.firstChild;
    }

    // troca todo [data-icon] do escopo pelo SVG correspondente (markup estático → SVG)
    function hydrate(root) {
        (root || document).querySelectorAll('[data-icon]').forEach(node => {
            const name = node.getAttribute('data-icon');
            if (!name) return;
            node.innerHTML = svg(name, node.getAttribute('data-icon-class') || '');
            node.removeAttribute('data-icon');
        });
    }


    window.vhubIcons = { get, svg, hydrate, has: (n) => !!ICONS[n] };

})();
