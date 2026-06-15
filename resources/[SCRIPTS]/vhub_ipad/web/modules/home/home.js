// modules/home/home.js — home screen: grade de ícones a partir do catálogo.
// LÊ store('ipad'); navega emitindo 'ipad:open_app'. Não escreve estado (A-04).

(() => {
  'use strict';

  const ui   = vhub.store('ipad');
  const offs = [];

  vhub.createModule('home', {

    onInit() {
      offs.push(vhub.bus.listen('ipad:opened',            () => this._render()));
      offs.push(vhub.bus.listen('ipad:installed_changed', () => this._render()));
    },

    onMount(el) { this._el = el; this._render(); },
    onShow()    { this._render(); },
    onHide()    {},

    onDestroy() {
      while (offs.length) offs.pop()();   // A-07: remove handlers do bus
    },

    // monta a grade: apps de sistema sempre + removíveis instalados (pull do store)
    _render() {
      const grid = this._el && this._el.querySelector('.home-grid');
      if (!grid) return;

      const st        = ui.get();
      const catalog   = st.catalog   || {};
      const installed = st.installed || [];

      const visible = Object.keys(catalog)
        .filter((id) => {
          const a = catalog[id];
          return a && (!a.removable || installed.includes(id));
        })
        .sort((a, b) => {
          const ra = catalog[a].removable ? 1 : 0;
          const rb = catalog[b].removable ? 1 : 0;
          if (ra !== rb) return ra - rb;   // sistema primeiro
          return (catalog[a].label || a).localeCompare(catalog[b].label || b);
        });

      grid.innerHTML = '';
      for (const id of visible) {
        grid.appendChild(this._icon(id, catalog[id]));
      }
    },

    // cria um ícone (DOM seguro; sem innerHTML com label)
    _icon(id, app) {
      const btn = document.createElement('button');
      btn.className = 'home-icon' + (app.available === false ? ' is-off' : '');

      const wrap = document.createElement('span');
      wrap.className = 'home-icon-img';
      const img = document.createElement('img');
      img.loading = 'lazy';
      img.alt = '';
      img.src = vhub.icon(app.icon || '');
      img.onerror = () => { img.onerror = null; img.src = vhub.iconFallback; };
      wrap.appendChild(img);

      const label = document.createElement('span');
      label.className = 'home-icon-label';
      label.textContent = app.label || id;

      btn.appendChild(wrap);
      btn.appendChild(label);
      btn.addEventListener('click', () => {
        if (app.available === false) return;   // dependency offline
        vhub.bus.emit('ipad:open_app', { id });
      });
      return btn;
    },

  });
})();
