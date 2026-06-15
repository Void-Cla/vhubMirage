// web/shared/utils.js — helpers puros do iPad (anexados a window.vhub).
// Carregado APÓS o runtime (core.js já criou window.vhub).

(() => {
  'use strict';

  // CDN preenchida pelo Lua no open (payload.cdn). Default seguro.
  vhub.cdn = 'https://cdn.jsdelivr.net/gh/Void-Cla/vhub-assets@main';

  // monta a URL completa de um ícone a partir do nome do arquivo
  vhub.icon = (filename) => `${vhub.cdn}/${filename}`;

  // hora atual HH:MM
  vhub.clock = () => {
    const d = new Date();
    return String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0');
  };

  // resolve o CSS de background do wallpaper a partir das prefs + enum do server.
  // custom (https) vence; senão o id escolhido; senão o primeiro do enum.
  vhub.wallpaperStyle = (prefs, wallpapers) => {
    if (prefs && typeof prefs.wallpaper_custom === 'string' && prefs.wallpaper_custom) {
      return `url("${prefs.wallpaper_custom}")`;
    }
    const list = wallpapers || [];
    const id   = prefs && prefs.wallpaper_id;
    const w    = list.find((x) => x.id === id) || list[0];
    if (!w) return 'linear-gradient(150deg, #1b2735 0%, #090a0f 70%)';
    return w.type === 'image' ? `url("${w.value}")` : w.value;
  };

  // placeholder SVG inline para ícone que falhar no carregamento (onerror)
  vhub.iconFallback =
    "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='64' height='64'>" +
    "<rect width='64' height='64' rx='14' fill='%23222'/>" +
    "<text x='32' y='40' font-size='28' text-anchor='middle' fill='%23f3b53a'>?</text></svg>";

})();
