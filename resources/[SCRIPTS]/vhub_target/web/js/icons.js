// icons.js — mapa local de ícones SVG (A-10: zero CDN; substitui FontAwesome)
// Todos stroke/fill em currentColor → herdam a cor do container (hover dourado).
// Consumidores passam icon: 'car' | 'key' | ... ; strings fa-* são normalizadas.
'use strict';

(function () {

  const S = (path) =>
    `<svg class="option-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${path}</svg>`;

  const ICONS = {
    car:    S('<path d="M3 13l1.5-4.5A2 2 0 0 1 6.4 7h11.2a2 2 0 0 1 1.9 1.5L21 13v5h-2.5v-1.5h-13V18H3v-5z"/><circle cx="7" cy="14.5" r="1" fill="currentColor"/><circle cx="17" cy="14.5" r="1" fill="currentColor"/>'),
    door:   S('<rect x="6" y="3" width="12" height="18" rx="1.5"/><circle cx="15" cy="12" r="1" fill="currentColor"/>'),
    key:    S('<circle cx="8" cy="8" r="4"/><path d="M11 11l9 9M17 17l2-2M14 20l2-2"/>'),
    lock:   S('<rect x="5" y="10" width="14" height="10" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3"/>'),
    hand:   S('<path d="M8 12V5a1.5 1.5 0 0 1 3 0v6M11 11V4a1.5 1.5 0 0 1 3 0v7M14 11V6a1.5 1.5 0 0 1 3 0v7c0 4-2.5 7-6.5 7S5 17 5 14v-3a1.5 1.5 0 0 1 3 0"/>'),
    bag:    S('<path d="M6 8h12l-1 12H7L6 8z"/><path d="M9 8V6a3 3 0 0 1 6 0v2"/>'),
    gear:   S('<circle cx="12" cy="12" r="3"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3M4.9 4.9l2.1 2.1M17 17l2.1 2.1M4.9 19.1L7 17M17 7l2.1-2.1"/>'),
    wrench: S('<path d="M14.7 6.3a4 4 0 0 0-5.3 5.3L4 17l3 3 5.4-5.4a4 4 0 0 0 5.3-5.3L15 12l-3-3 2.7-2.7z"/>'),
    info:   S('<circle cx="12" cy="12" r="9"/><path d="M12 11v5"/><circle cx="12" cy="8" r="0.5" fill="currentColor"/>'),
    warn:   S('<path d="M12 3L2 20h20L12 3z"/><path d="M12 10v4"/><circle cx="12" cy="17" r="0.5" fill="currentColor"/>'),
    cart:   S('<circle cx="9" cy="20" r="1.5"/><circle cx="17" cy="20" r="1.5"/><path d="M3 4h2l2.5 12h10L20 8H6"/>'),
    person: S('<circle cx="12" cy="7" r="3.5"/><path d="M5 21a7 7 0 0 1 14 0"/>'),
    box:    S('<path d="M12 3l8 4.5v9L12 21l-8-4.5v-9L12 3z"/><path d="M12 12l8-4.5M12 12v9M12 12L4 7.5"/>'),
    circle: S('<circle cx="12" cy="12" r="8"/>'),
    globe:  S('<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/>'),
    flask:  S('<path d="M9 3h6M10 3v5l-5 10a2 2 0 0 0 1.8 3h10.4A2 2 0 0 0 19 18L14 8V3"/>'),
    back:   S('<circle cx="12" cy="12" r="9"/><path d="M13.5 8.5L10 12l3.5 3.5"/>'),
    plus:   S('<path d="M12 5v14M5 12h14"/>'),
    minus:  S('<path d="M5 12h14"/>'),
    check:  S('<path d="M4 12.5l5 5L20 6.5"/>'),
    close:  S('<path d="M6 6l12 12M18 6L6 18"/>'),
    star:   S('<path d="M12 3l2.7 5.8 6.3.7-4.7 4.3 1.3 6.2L12 16.9 6.4 20l1.3-6.2L3 9.5l6.3-.7L12 3z"/>'),
    dot:    S('<circle cx="12" cy="12" r="3" fill="currentColor" stroke="none"/>'),
  };

  // aliases fa-* → chave do mapa (compat com consumidores que passam classes FontAwesome)
  const ALIAS = {
    'car-side': 'car', 'car-rear': 'car', 'car-on': 'car',
    'door-open': 'door', 'door-closed': 'door',
    'circle-chevron-left': 'back', 'chevron-left': 'back', 'arrow-left': 'back',
    'male': 'person', 'user': 'person', 'person-walking': 'person',
    'handcuffs': 'lock', 'unlock': 'lock',
    'bong': 'flask', 'flask-vial': 'flask', 'vial': 'flask',
    'cube': 'box', 'boxes-stacked': 'box',
    'screwdriver-wrench': 'wrench', 'screwdriver': 'wrench',
    'circle-info': 'info', 'triangle-exclamation': 'warn',
    'cart-shopping': 'cart', 'basket-shopping': 'cart', 'bag-shopping': 'bag',
    'hand-pointer': 'hand', 'hand-holding': 'hand',
    'xmark': 'close', 'ban': 'close',
    'earth-americas': 'globe',
  };

  // resolve um nome de ícone ('car', 'fa-solid fa-car-side', ...) para o SVG do mapa
  window.vhIcon = function (name) {
    if (!name || typeof name !== 'string') return ICONS.dot;

    // normaliza classes fa: remove prefixos de estilo e 'fa-'
    const key = name
      .replace(/fa-(solid|regular|light|thin|brands|duotone|fw)/g, ' ')
      .replace(/fa-/g, ' ')
      .trim()
      .split(/\s+/)
      .pop() || 'dot';

    return ICONS[key] || ICONS[ALIAS[key]] || ICONS.dot;
  };

})();
