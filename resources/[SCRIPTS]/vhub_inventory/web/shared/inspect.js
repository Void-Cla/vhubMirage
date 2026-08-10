// shared/inspect.js — helper presentacional de inspeção de item (detalhe rico).
// Não é um createModule(); o módulo dono injeta o container e chama:
//   const off = vhub.inspect.init(el)  — registra listeners; retorna cleanup (A-07)
//   vhub.inspect.show(entry)           — renderiza entry
//   vhub.inspect.hide()                — limpa e oculta
// O dono guarda off() e chama em onDestroy. Só textContent/createElement (anti-XSS).

(function () {

  const WHITELIST = ['plate', 'fuel', 'engine_health', 'body_health', 'odometer_km', 'model'];

  const LABELS = {
    plate: 'Placa', fuel: 'Combustível',
    engine_health: 'Motor', body_health: 'Lataria',
    odometer_km: 'Odômetro', model: 'Modelo',
  };

  function fmt(key, val) {
    if (key === 'fuel')          return Math.round(+val) + '%';
    if (key === 'engine_health') return Math.round(+val / 10) + '%';
    if (key === 'body_health')   return Math.round(+val / 10) + '%';
    if (key === 'odometer_km')   return (+val).toFixed(1) + ' km';
    return '' + val;
  }

  let _el = null, _offKey = null;


  // ============================================================
  // HELPERS DE RENDER
  // ============================================================

  // cria um elemento com classe + texto (createElement -> sem HTML injetado)
  function node(tag, cls, text) {
    const e = document.createElement(tag);
    if (cls)  e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  }

  // linha rótulo/valor da grade de metadados
  function metaRow(label, value) {
    const row = node('div', 'insp-row');
    row.appendChild(node('span', 'insp-lbl', label));
    row.appendChild(node('span', 'insp-val', value));
    return row;
  }


  // ============================================================
  // API
  // ============================================================

  const inspect = {

    // monta o helper no elemento fornecido pelo módulo dono
    init(containerEl) {
      _el = containerEl;
      _el.classList.add('vh-inspector', 'insp-empty');

      const onKey = (e) => {
        if (e.key !== 'Escape') return;
        inspect.hide();
        vhub.emit('inspector:close', {});
      };
      window.addEventListener('keydown', onKey);
      _offKey = onKey;

      return function off() {                       // cleanup para o dono (A-07)
        window.removeEventListener('keydown', onKey);   // fecha sobre o handler LOCAL (robusto)
        _offKey = null;
        if (_el) { _el.innerHTML = ''; _el.classList.add('insp-empty'); }
        _el = null;
      };
    },

    // renderiza entry no painel de detalhe
    show(entry) {
      if (!_el || !entry) return;
      const def = (vhub.util && vhub.util.itemDef(entry.id)) || {};

      _el.innerHTML = '';
      _el.classList.remove('insp-empty');

      // ---- cabeçalho: ícone + nome + legalidade ----
      const head = node('div', 'insp-head');

      const ic = node('div', 'insp-ic');
      head.appendChild(ic);
      if (vhub.util) vhub.util.applyIcon(ic, entry.id);   // SVG local + PNG do repo se carregar

      const htext = node('div', 'insp-htext');
      htext.appendChild(node('div', 'insp-name', def.nome || entry.id));

      const tags = node('div', 'insp-tags');
      const leg = def.legalidade || 'comum';
      const legPill = node('span', 'insp-pill insp-pill--' + leg, vhub.util.legalityLabel(leg));
      tags.appendChild(legPill);
      if (def.categoria) tags.appendChild(node('span', 'insp-pill insp-pill--cat', def.categoria));
      if ((entry.amount || 1) > 1) tags.appendChild(node('span', 'insp-pill insp-pill--qty', 'x' + entry.amount));
      htext.appendChild(tags);
      head.appendChild(htext);
      _el.appendChild(head);

      // ---- grade de propriedades ----
      const grid = node('div', 'insp-meta');

      if (typeof def.peso === 'number') {
        grid.appendChild(metaRow('Peso', vhub.util.fmtWeight(def.peso) + ' kg' +
          ((entry.amount || 1) > 1 ? ' · ' + vhub.util.fmtWeight(def.peso * entry.amount) + ' total' : '')));
      }

      // metadados de instância (whitelist — nunca campos livres do payload)
      const meta = entry.meta || {};
      WHITELIST.forEach((key) => {
        const val = meta[key];
        if (val === undefined || val === null) return;
        grid.appendChild(metaRow(LABELS[key] || key, fmt(key, val)));
      });

      if (grid.children.length > 0) _el.appendChild(grid);

      // ---- selo de restrições (só quando há algo relevante a avisar) ----
      const flags = node('div', 'insp-flags');
      if (def.negociavel === false)    flags.appendChild(node('span', 'insp-flag', 'Não negociável'));
      if (def.perdivel === false)      flags.appendChild(node('span', 'insp-flag', 'Não perde na morte'));
      if (def.permitido_bau === false) flags.appendChild(node('span', 'insp-flag', 'Fora do baú'));
      if (def.serial === true)         flags.appendChild(node('span', 'insp-flag insp-flag--gold', 'Item único'));
      if (flags.children.length > 0) _el.appendChild(flags);
    },

    // oculta o painel sem destruir o helper
    hide() {
      if (!_el) return;
      _el.innerHTML = '';
      _el.classList.add('insp-empty');
    },
  };

  vhub.inspect = inspect;
})();
