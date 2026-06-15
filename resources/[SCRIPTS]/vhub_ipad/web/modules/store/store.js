// modules/store/store.js — Loja: lista o catálogo; instala/remove (estado per-char).
// LÊ store('ipad'); emite intenção pelo bus (shell persiste + reconcilia). A-04.

(() => {
  'use strict';

  const ui   = vhub.store('ipad');
  const offs = [];

  vhub.createModule('store', {

    onInit() {
      offs.push(vhub.bus.listen('ipad:opened',            () => this._render()));
      offs.push(vhub.bus.listen('ipad:installed_changed', () => this._render()));
    },

    onMount(el) { this._el = el; this._render(); },
    onShow()    { this._render(); },
    onHide()    {},

    onDestroy() {
      while (offs.length) offs.pop()();   // A-07
    },

    _render() {
      const list = this._el && this._el.querySelector('[data-el="list"]');
      if (!list) return;

      const st        = ui.get();
      const catalog   = st.catalog   || {};
      const installed = st.installed || [];

      const ids = Object.keys(catalog).sort(
        (a, b) => (catalog[a].label || a).localeCompare(catalog[b].label || b)
      );

      list.innerHTML = '';
      if (ids.length === 0) {
        const empty = document.createElement('p');
        empty.className = 'store-empty';
        empty.textContent = 'Nenhum app disponível.';
        list.appendChild(empty);
        return;
      }
      for (const id of ids) {
        list.appendChild(this._card(id, catalog[id], installed.includes(id)));
      }
    },

    _card(id, app, isInstalled) {
      const card = document.createElement('div');
      card.className = 'store-card';

      const icon = document.createElement('img');
      icon.className = 'store-icon';
      icon.loading = 'lazy';
      icon.alt = '';
      icon.src = vhub.icon(app.icon || '');
      icon.onerror = () => { icon.onerror = null; icon.src = vhub.iconFallback; };

      const info = document.createElement('div');
      info.className = 'store-info';
      const name = document.createElement('strong');
      name.textContent = app.label || id;
      const cat = document.createElement('small');
      cat.textContent = app.category || '';
      info.appendChild(name);
      info.appendChild(cat);

      const btn = document.createElement('button');
      btn.className = 'store-btn';
      if (!app.removable) {
        btn.textContent = 'Sistema';
        btn.disabled = true;
        btn.classList.add('is-system');
      } else if (isInstalled) {
        btn.textContent = 'Remover';
        btn.classList.add('is-remove');
        btn.addEventListener('click', () => vhub.bus.emit('ipad:uninstall_app', { id }));
      } else {
        btn.textContent = 'Instalar';
        btn.addEventListener('click', () => vhub.bus.emit('ipad:install_app', { id }));
      }

      card.appendChild(icon);
      card.appendChild(info);
      card.appendChild(btn);
      return card;
    },

  });
})();
