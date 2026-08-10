// shared/utils.js — helpers puros de NUI: ícones, formatação, DOM.
// ÍCONE = base SVG LOCAL garantida (data URI: nunca quebra/fica preto offline)
// + camada opcional do repo do dono (vhub-assets/<id>.png) que sobe quando carrega.
// Sem DEPENDÊNCIA dura de CDN (offline degrada para o SVG) — espírito de A-10 honrado.

(function () {

  // base dos assets curados do dono (padrão: <id>.png; override por def.icon)
  const CDN_BASE = 'https://raw.githubusercontent.com/Void-Cla/vhub-assets/main/';

  // ============================================================
  // REGISTRO DE ÍCONES (SVG stroke, 24x24) — mora aqui, sem asset externo
  // ============================================================

  // desenho interno de cada ícone (path/shape); a moldura <svg> é montada em svgURI()
  const GLYPH = {

    // categorias (fallback quando não há ícone específico do item)
    'cat:consumivel': '<path d="M9 3h6M10 3v3l-2 3v9a2 2 0 0 0 2 2h4a2 2 0 0 0 2-2V9l-2-3V3"/><path d="M8 13h8"/>',
    'cat:medico':     '<rect x="3" y="7" width="18" height="13" rx="2"/><path d="M8 7V5a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/><path d="M12 11v6M9 14h6"/>',
    'cat:ferramenta': '<path d="M15 5.5a3.8 3.8 0 0 0-5 5L4 16.5 7.5 20l6-6a3.8 3.8 0 0 0 5-5l-2.6 2.6-2.4-2.4L16 5.5z"/>',
    'cat:documento':  '<rect x="3" y="5" width="18" height="14" rx="2"/><circle cx="8.5" cy="11" r="2"/><path d="M13 9h5M13 13h5M5.6 15.4c.6-1.5 4.3-1.5 4.9 0"/>',
    'cat:chave':      '<circle cx="8" cy="8" r="4"/><path d="M11 11l8 8M15 15l2-2M17.5 17.5l2-2"/>',
    'cat:eletronico': '<rect x="6" y="3" width="12" height="18" rx="2.4"/><path d="M10.5 18h3"/>',
    'cat:outros':     '<path d="M12 3 3 8v8l9 5 9-5V8l-9-5z"/><path d="M3 8l9 5 9-5M12 13v8"/>',

    // itens específicos do catálogo atual
    'agua':      '<path d="M9 3h6M10 3v3l-2 3v9a2 2 0 0 0 2 2h4a2 2 0 0 0 2-2V9l-2-3V3"/><path d="M8 13h8"/>',
    'sandwich':  '<path d="M4 12c0-3 3.6-5 8-5s8 2 8 5H4z"/><path d="M4 12h16M5.5 15h13a2 2 0 0 1-2 2H7.5a2 2 0 0 1-2-2z"/>',
    'bandage':   '<rect x="3.5" y="8.5" width="17" height="7" rx="3.5" transform="rotate(-45 12 12)"/><path d="M10.4 10.4l3.2 3.2M12.6 8.2l3.2 3.2M8.2 12.6l3.2 3.2"/>',
    'medkit':    '<rect x="3" y="7" width="18" height="13" rx="2"/><path d="M8 7V5a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/><path d="M12 11v6M9 14h6"/>',
    'repairkit': '<rect x="3" y="9" width="18" height="10" rx="2"/><path d="M8 9V6.5A2.5 2.5 0 0 1 10.5 4h3A2.5 2.5 0 0 1 16 6.5V9M3 13h18"/>',
    'caixadeferramentas': '<rect x="3" y="9" width="18" height="10" rx="2"/><path d="M8 9V6.5A2.5 2.5 0 0 1 10.5 4h3A2.5 2.5 0 0 1 16 6.5V9M3 13h18"/>',
    'nitro':     '<path d="M12 3c2.4 3 4 4.4 4 7.8A4 4 0 0 1 8 11c0-1.8.9-3 2-4 .4 1 1 1.6 2 1.6 0-2 0-3.6 0-5.6z"/><path d="M10 20h4"/>',
    'fuel_can':  '<path d="M5 8h9v11H5z"/><path d="M14 10.5h2.5L19 13v6h-5M8 5h3v3H8z"/>',
    'lockpick':  '<path d="M4 20l6.5-6.5M9.5 12.5l3-3 3.5 3.5-3 3z"/><circle cx="18" cy="6" r="2"/><path d="M14 8l2.4 2.4"/>',
    'rg':        '<rect x="3" y="5" width="18" height="14" rx="2"/><circle cx="8.5" cy="11" r="2"/><path d="M13 9h5M13 13h5M5.6 15.4c.6-1.5 4.3-1.5 4.9 0"/>',
    'veh_key':   '<circle cx="7" cy="12" r="4"/><path d="M11 12h9M17 12v3M20 12v2.5"/><path d="M5.4 12h1.4"/>',
    'ipad':      '<rect x="4" y="3" width="16" height="18" rx="2.4"/><path d="M10.5 18h3"/>',
    'radio':     '<rect x="7" y="8" width="9" height="13" rx="1.6"/><path d="M16 5l2.5-1M13.5 6.5V4M9.5 12h4M9.5 15h4"/>',
  };


  // ============================================================
  // HELPERS DE ÍCONE
  // ============================================================

  // monta um data URI SVG (auto-contido, sem rede) com o traço no tom dourado
  function svgURI(inner, stroke) {
    const svg =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" ' +
      'stroke="' + stroke + '" stroke-width="1.55" stroke-linecap="round" stroke-linejoin="round">' +
      inner + '</svg>';
    return 'data:image/svg+xml,' + encodeURIComponent(svg);
  }


  vhub.util = {

    // ----------------------------------------------------------
    // FORMATAÇÃO
    // ----------------------------------------------------------

    // peso em kg com 1 casa
    fmtWeight(n) {
      return (Number(n) || 0).toFixed(1);
    },

    // cor da barra de peso por percentual (verde -> dourado -> laranja -> vermelho)
    weightColor(pct) {
      if (pct >= 100) return 'var(--vh-danger)';
      if (pct >= 85)  return 'linear-gradient(90deg, #e0a85a, #e0785a)';
      if (pct >= 60)  return 'linear-gradient(90deg, var(--vh-gold), var(--vh-sand))';
      return 'linear-gradient(90deg, #7fce8a, #b9e2a0)';
    },

    // rótulo curto da legalidade (PT-BR)
    legalityLabel(leg) {
      return leg === 'ilegal' ? 'Ilegal' : (leg === 'legal' ? 'Legal' : 'Comum');
    },

    // cor de acento por legalidade (discreta — só o realce do slot, não o ícone)
    legalityColor(leg) {
      if (leg === 'ilegal') return 'var(--vh-leg-ilegal)';
      if (leg === 'legal')  return 'var(--vh-leg-legal)';
      return 'var(--vh-leg-comum)';
    },


    // ----------------------------------------------------------
    // ÍCONES (locais)
    // ----------------------------------------------------------

    // data URI do ícone LOCAL (base garantida): específico > categoria > caixa. Traço dourado.
    itemIcon(id) {
      const def   = vhub.util.itemDef(id) || {};
      const glyph = GLYPH[id] || GLYPH['cat:' + (def.categoria || 'outros')] || GLYPH['cat:outros'];
      return svgURI(glyph, '#ffd573');   // dourado claro canônico (legível sobre slot escuro)
    },

    // URL do PNG curado do dono (repo vhub-assets). Nome = def.icon || id.
    itemIconRemote(id) {
      const def = vhub.util.itemDef(id) || {};
      return CDN_BASE + (def.icon || id) + '.png';
    },

    // pinta o ícone num elemento .ic: SVG local IMEDIATO + sobe p/ o PNG do repo se ele carregar.
    // Falha de rede é silenciosa: o SVG permanece (nunca quebra, nunca fica preto).
    applyIcon(el, id) {
      if (!el) return;
      el.style.backgroundImage = 'url("' + vhub.util.itemIcon(id) + '")';   // base local garantida
      const url = vhub.util.itemIconRemote(id);
      const probe = new Image();
      probe.onload = function () {
        if (el.isConnected) el.style.backgroundImage = 'url("' + url + '")'; // upgrade só se ainda no DOM
      };
      probe.src = url;                                                        // onerror -> ignora, mantém SVG
    },


    // ----------------------------------------------------------
    // CATÁLOGO (recebido no handshake nui_ready)
    // ----------------------------------------------------------

    // rótulo do item
    itemName(id) {
      const c = vhub.config && vhub.config.catalog && vhub.config.catalog[id];
      return (c && c.nome) || id;
    },

    // definição completa do item (tags declarativas) ou null
    itemDef(id) {
      return (vhub.config && vhub.config.catalog && vhub.config.catalog[id]) || null;
    },


    // ----------------------------------------------------------
    // DOM
    // ----------------------------------------------------------

    // cria elemento com classe e atributos
    el(tag, cls, attrs) {
      const e = document.createElement(tag);
      if (cls) e.className = cls;
      if (attrs) for (const k in attrs) e.setAttribute(k, attrs[k]);
      return e;
    },

    // preenche uma célula `.slot` com ícone local, quantidade, acento de legalidade,
    // placa e tooltip. Compartilhado por mochila e baú (DRY). `entry` = { id, amount, meta }.
    fillSlot(cell, entry) {
      cell.dataset.filled = '1';
      const def = vhub.util.itemDef(entry.id) || {};

      // acento de legalidade (barra fina no topo do slot — realce discreto)
      cell.style.setProperty('--slot-accent', vhub.util.legalityColor(def.legalidade));

      // ícone: SVG local garantido + PNG do repo do dono se carregar
      const ic = vhub.util.el('div', 'ic');
      cell.appendChild(ic);
      vhub.util.applyIcon(ic, entry.id);

      // quantidade (só quando > 1)
      if ((entry.amount || 1) > 1) {
        const qt = vhub.util.el('div', 'qt'); qt.textContent = entry.amount; cell.appendChild(qt);
      }

      // placa (chave de veículo)
      if (entry.meta && entry.meta.plate) {
        const pl = vhub.util.el('div', 'pl'); pl.textContent = entry.meta.plate; cell.appendChild(pl);
      }

      // tooltip nativo enxuto (o inspector cobre o detalhe rico)
      const nm = def.nome || entry.id;
      cell.title = nm + (entry.meta && entry.meta.plate ? ' • ' + entry.meta.plate : '');
    },
  };
})();
