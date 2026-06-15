// modules/settings/settings.js — zoom + wallpaper. Emite 'ipad:set_pref' (shell persiste).
// LÊ store('ipad'); não escreve estado direto (A-04).

(() => {
  'use strict';

  const ui = vhub.store('ipad');

  vhub.createModule('settings', {

    onMount(el) {
      this._el      = el;
      this._zoom    = el.querySelector('[data-el="zoom"]');
      this._zoomVal = el.querySelector('[data-el="zoom-val"]');
      this._walls   = el.querySelector('[data-el="walls"]');
      this._url     = el.querySelector('[data-el="url"]');

      this._zoom.addEventListener('input', () => {
        const z = +this._zoom.value;
        this._zoomVal.textContent = z + '%';
        vhub.bus.emit('ipad:set_pref', { zoom: z });
      });

      el.querySelector('[data-el="apply-url"]').addEventListener('click', () => {
        const u = (this._url.value || '').trim();
        vhub.bus.emit('ipad:set_pref', { wallpaper_custom: u });
        this._sync();
      });

      el.querySelector('[data-el="reset"]').addEventListener('click', () => {
        vhub.bus.emit('ipad:set_pref', { zoom: 60, wallpaper_id: 'default', wallpaper_custom: '' });
        this._sync();
      });

      this._sync();
    },

    onShow()    { this._sync(); },
    onHide()    {},
    onDestroy() {},   // sem listeners de bus persistentes

    // reflete o estado atual (pull do store) nos controles
    _sync() {
      const prefs = ui.get().prefs || {};
      const z = typeof prefs.zoom === 'number' ? prefs.zoom : 60;
      if (this._zoom)    this._zoom.value = z;
      if (this._zoomVal) this._zoomVal.textContent = z + '%';
      if (this._url)     this._url.value = prefs.wallpaper_custom || '';
      this._renderWalls(prefs);
    },

    // galeria de wallpapers (enum do server); destaca o selecionado
    _renderWalls(prefs) {
      if (!this._walls) return;
      const list = ui.get().wallpapers || [];
      const sel  = prefs.wallpaper_custom ? null : (prefs.wallpaper_id || 'default');

      this._walls.innerHTML = '';
      for (const w of list) {
        const b = document.createElement('button');
        b.className = 'settings-wall' + (w.id === sel ? ' is-sel' : '');
        b.title = w.label || w.id;
        b.style.background = w.type === 'image' ? `center/cover url("${w.value}")` : w.value;
        b.addEventListener('click', () => {
          if (this._url) this._url.value = '';
          vhub.bus.emit('ipad:set_pref', { wallpaper_id: w.id, wallpaper_custom: '' });
          this._renderWalls({ wallpaper_id: w.id });
        });
        this._walls.appendChild(b);
      }
    },

  });
})();
