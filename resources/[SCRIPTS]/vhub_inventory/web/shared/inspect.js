// shared/inspect.js — helper presentacional de inspecao de item.
// Nao e um createModule(); o modulo dono injeta o container e chama:
//   const off = vhub.inspect.init(el)  — registra listeners; retorna cleanup (A-07)
//   vhub.inspect.show(entry)           — renderiza entry
//   vhub.inspect.hide()                — limpa e oculta
// O dono guarda off() e chama em onDestroy.

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

  let _el     = null;
  let _offKey = null;


  // ============================================================
  // API
  // ============================================================

  const inspect = {

    // monta o helper no elemento fornecido pelo modulo dono
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

      // retorna cleanup para o dono chamar em onDestroy (A-07)
      return function off() {
        window.removeEventListener('keydown', _offKey);
        _offKey = null;
        if (_el) { _el.innerHTML = ''; _el.classList.add('insp-empty'); }
        _el = null;
      };
    },

    // renderiza entry no painel — textContent/createElement apenas (sem innerHTML c/ var)
    show(entry) {
      if (!_el || !entry) return;
      const def = (vhub.util && vhub.util.itemDef(entry.id)) || {};

      _el.innerHTML = '';
      _el.classList.remove('insp-empty');

      // icone
      const ic = document.createElement('div');
      ic.className = 'insp-ic';
      ic.style.backgroundImage = 'url(' + ((vhub.util && vhub.util.itemIcon(entry.id)) || '') + ')';
      _el.appendChild(ic);

      // corpo de texto
      const body = document.createElement('div');
      body.className = 'insp-body';
      _el.appendChild(body);

      const nm = document.createElement('div');
      nm.className = 'insp-name';
      nm.textContent = (def.nome) || entry.id;
      body.appendChild(nm);

      if (def.descricao) {
        const dc = document.createElement('div');
        dc.className = 'insp-desc';
        dc.textContent = def.descricao;
        body.appendChild(dc);
      }

      if ((entry.amount || 1) > 1) {
        const qt = document.createElement('div');
        qt.className = 'insp-qty';
        qt.textContent = 'x' + entry.amount;
        body.appendChild(qt);
      }

      // metadata (whitelist — nunca campos livres)
      const meta = entry.meta || {};
      const hasMeta = WHITELIST.some((k) => meta[k] !== undefined && meta[k] !== null);
      if (hasMeta) {
        const md = document.createElement('div');
        md.className = 'insp-meta';
        WHITELIST.forEach((key) => {
          const val = meta[key];
          if (val === undefined || val === null) return;
          const row = document.createElement('div');
          row.className = 'insp-row';
          const lbl = document.createElement('span');
          lbl.className = 'insp-lbl';
          lbl.textContent = LABELS[key] || key;
          const vl = document.createElement('span');
          vl.className = 'insp-val';
          vl.textContent = fmt(key, val);
          row.appendChild(lbl);
          row.appendChild(vl);
          md.appendChild(row);
        });
        if (md.children.length > 0) body.appendChild(md);
      }
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
