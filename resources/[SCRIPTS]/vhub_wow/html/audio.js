// audio.js — player híbrido do vhub_wow.
// Backends por tipo de URL:
//   • 'audio'      → <audio> HTML5 (Jamendo/Discord/.mp3 direto) — offline-safe (A-10)
//   • 'youtube'    → YouTube IFrame Player API (player oficial, sem chave)
//   • 'soundcloud' → SoundCloud Widget API
// YT/SC são exceção consciente à A-10 (exigem o domínio acessível). Só o id/permalink
// validado entra no iframe (nunca string crua) — anti-injeção.

var sounds = {};   // [name] = { backend, handle, ready, volume, loop, ... }


// ============================================================
// PRONTIDÃO DAS APIS DE EMBED (carregam async)
// ============================================================

var ytReady = false;
var ytQueue = [];

// callback global que a IFrame API chama ao carregar
window.onYouTubeIframeAPIReady = function () {
  ytReady = true;
  while (ytQueue.length) { try { ytQueue.shift()(); } catch (e) {} }
};


// ============================================================
// LISTENER — dispatch das mensagens do Lua
// ============================================================

window.addEventListener('message', function (event) {
  var d = event.data;
  if (!d || !d.type) return;

  switch (d.type) {
    case 'play':       onPlay(d); break;
    case 'destroy':    onDestroy(d); break;
    case 'pause':      onPauseMsg(d); break;
    case 'resume':     onResumeMsg(d); break;
    case 'volume':     onVolume(d); break;
    case 'distance':   onDistance(d); break;
    case 'position':   onPosition(d); break;
  }
});


// ============================================================
// PLAY — detecta o backend pela URL e roteia
// ============================================================

function onPlay(d) {
  destroyIfExists(d.name);

  var vol = clampVolume(d.volume);
  var loop = d.loop === true;

  var ytId = parseYouTubeId(d.url);
  if (ytId) { return playYouTube(d.name, ytId, vol, loop); }

  if (isSoundCloud(d.url)) { return playSoundCloud(d.name, d.url, vol, loop); }

  playAudio(d.name, d.url, vol, loop, d);
}

// backend 'audio' — arquivo direto via <audio> (anti-XSS: src por propriedade DOM)
function playAudio(name, url, vol, loop, d) {
  var audio = new Audio();
  audio.src = url;
  audio.loop = loop;
  audio.volume = vol;

  sounds[name] = {
    backend: 'audio', handle: audio, ready: true, volume: vol, loop: loop,
    distance: (d && d.distance) || 10.0, dynamic: (d && d.dynamic) === true,
  };

  audio.play().catch(function () {});
}

// backend 'youtube' — IFrame Player API (só o id de 11 chars entra)
function playYouTube(name, videoId, vol, loop) {
  var entry = { backend: 'youtube', handle: null, ready: false, volume: vol, loop: loop };
  sounds[name] = entry;

  function build() {
    if (sounds[name] !== entry) return;   // destruído antes de montar

    var div = document.createElement('div');
    div.id = 'ytp-' + safeId(name);
    document.getElementById('wow-players').appendChild(div);

    var pv = { autoplay: 1, controls: 0, disablekb: 1, fs: 0, modestbranding: 1, playsinline: 1 };
    if (loop) { pv.loop = 1; pv.playlist = videoId; }   // loop de 1 vídeo exige playlist=id

    entry.handle = new YT.Player(div.id, {
      width: '1', height: '1', videoId: videoId, playerVars: pv,
      events: {
        onReady: function (e) {
          if (sounds[name] !== entry) { try { e.target.destroy(); } catch (x) {} return; }
          entry.ready = true;
          try { e.target.setVolume(Math.round(entry.volume * 100)); } catch (x) {}
          try { e.target.playVideo(); } catch (x) {}
        },
        onError: function () { /* vídeo bloqueado/embargado: silencioso, não trava a UI */ },
      },
    });
  }

  if (ytReady) build(); else ytQueue.push(build);
}

// backend 'soundcloud' — Widget API (permalink host-validado, URL-encoded)
function playSoundCloud(name, url, vol, loop) {
  var iframe = document.createElement('iframe');
  iframe.id = 'scp-' + safeId(name);
  iframe.width = '1'; iframe.height = '1';
  iframe.setAttribute('frameborder', 'no');
  iframe.setAttribute('allow', 'autoplay');
  iframe.src = 'https://w.soundcloud.com/player/?url=' + encodeURIComponent(url) +
    '&auto_play=true&visual=false&hide_related=true&show_comments=false&show_user=false&download=false&sharing=false&buying=false';
  document.getElementById('wow-players').appendChild(iframe);

  var entry = { backend: 'soundcloud', handle: null, ready: false, volume: vol, loop: loop, iframe: iframe };
  sounds[name] = entry;

  (function bind() {
    if (typeof SC === 'undefined' || !SC.Widget) { setTimeout(bind, 200); return; }
    if (sounds[name] !== entry) return;

    var widget = SC.Widget(iframe);
    entry.handle = widget;
    widget.bind(SC.Widget.Events.READY, function () {
      if (sounds[name] !== entry) return;
      entry.ready = true;
      try { widget.setVolume(Math.round(entry.volume * 100)); } catch (x) {}
      if (entry.loop) {
        widget.bind(SC.Widget.Events.FINISH, function () { try { widget.seekTo(0); widget.play(); } catch (x) {} });
      }
      try { widget.play(); } catch (x) {}
    });
  })();
}


// ============================================================
// CONTROLES — despacham pelo backend
// ============================================================

function onDestroy(d) {
  destroyIfExists(d.name);
}

function onPauseMsg(d) {
  var s = sounds[d.name];
  if (!s) return;
  if (s.backend === 'audio') { s.handle.pause(); }
  else if (s.backend === 'youtube')    { if (s.handle && s.ready) try { s.handle.pauseVideo(); } catch (e) {} }
  else if (s.backend === 'soundcloud') { if (s.handle) try { s.handle.pause(); } catch (e) {} }
}

function onResumeMsg(d) {
  var s = sounds[d.name];
  if (!s) return;
  if (s.backend === 'audio') { s.handle.play().catch(function () {}); }
  else if (s.backend === 'youtube')    { if (s.handle && s.ready) try { s.handle.playVideo(); } catch (e) {} }
  else if (s.backend === 'soundcloud') { if (s.handle) try { s.handle.play(); } catch (e) {} }
}

function onVolume(d) {
  var s = sounds[d.name];
  if (!s) return;
  var v = clampVolume(d.volume);
  s.volume = v;   // guardado p/ aplicar no onReady caso o player ainda não esteja pronto
  if (s.backend === 'audio') { s.handle.volume = v; }
  else if (s.backend === 'youtube')    { if (s.handle && s.ready) try { s.handle.setVolume(Math.round(v * 100)); } catch (e) {} }
  else if (s.backend === 'soundcloud') { if (s.handle && s.ready) try { s.handle.setVolume(Math.round(v * 100)); } catch (e) {} }
}

function onDistance(d) {
  var s = sounds[d.name];
  if (s && s.backend === 'audio') s.distance = d.distance;
}

// posição 3D só faz sentido p/ <audio> (e ainda é andaime — sem atenuação real).
// YT/SC tocam 2D no CEF (só o motorista ouve) — ignoram.
function onPosition(d) {
  var s = sounds[d.name];
  if (s && s.backend === 'audio') s.lastPos = { x: d.x, y: d.y, z: d.z };
}


// ============================================================
// HELPERS
// ============================================================

// derruba o backend correto e remove o player do DOM (A-07: cleanup)
function destroyIfExists(name) {
  var s = sounds[name];
  if (!s) return;
  delete sounds[name];   // marca destruído ANTES (evita onReady tardio reativar)

  if (s.backend === 'audio') {
    s.handle.pause();
    s.handle.src = '';
  } else if (s.backend === 'youtube') {
    if (s.handle) { try { s.handle.destroy(); } catch (e) {} }
    removeEl('ytp-' + safeId(name));
  } else if (s.backend === 'soundcloud') {
    if (s.iframe && s.iframe.parentNode) s.iframe.parentNode.removeChild(s.iframe);
  }
}

function removeEl(id) {
  var el = document.getElementById(id);
  if (el && el.parentNode) el.parentNode.removeChild(el);
}

// id de DOM seguro a partir do nome do som
function safeId(name) {
  return String(name).replace(/[^a-zA-Z0-9_-]/g, '_');
}

function clampVolume(v) {
  v = Number(v);
  if (isNaN(v)) return 0.5;
  return Math.max(0, Math.min(1, v));
}


// ============================================================
// DETECÇÃO DE URL — espelha a validação server-side (config.lua)
// ============================================================

// extrai o id de 11 chars de uma URL do YouTube (ou null)
function parseYouTubeId(url) {
  if (typeof url !== 'string') return null;
  var host = (url.match(/^https:\/\/([\w.-]+)\//) || [])[1];
  if (!host) return null;
  if (['youtu.be', 'youtube.com', 'www.youtube.com', 'm.youtube.com', 'music.youtube.com'].indexOf(host) === -1) {
    return null;
  }
  var m = url.match(/[?&]v=([\w-]+)/) || url.match(/youtu\.be\/([\w-]+)/) ||
          url.match(/\/shorts\/([\w-]+)/) || url.match(/\/embed\/([\w-]+)/);
  if (m && m[1] && m[1].length >= 11) return m[1].slice(0, 11);
  return null;
}

// true se for permalink do SoundCloud
function isSoundCloud(url) {
  if (typeof url !== 'string') return false;
  var parts = url.match(/^https:\/\/([\w.-]+)(\/.*)$/);
  if (!parts) return false;
  var host = parts[1], path = parts[2];
  if (['soundcloud.com', 'www.soundcloud.com', 'm.soundcloud.com'].indexOf(host) === -1) return false;
  return /^\/[\w-]+\/[\w-]+/.test(path);
}
