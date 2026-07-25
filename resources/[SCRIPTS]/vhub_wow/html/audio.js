// audio.js — backends HTML5/YouTube com master gain único e cleanup explícito

(function () {
  'use strict';

  var sounds = Object.create(null);
  var streamerMode = false;
  var voiceActivity = 0;

  vhub.listen('nui:wow:audio:play', onPlay);
  vhub.listen('nui:wow:audio:destroy', function (data) { destroyIfExists(data.name); });
  vhub.listen('nui:wow:audio:pause', onPause);
  vhub.listen('nui:wow:audio:resume', onResume);
  vhub.listen('nui:wow:audio:volume', onVolume);
  vhub.listen('nui:wow:audio:master', onMaster);

  window.addEventListener('message', onProviderMessage);
  window.addEventListener('beforeunload', cleanup);

  function clamp(value) {
    value = Number(value);
    if (!Number.isFinite(value)) return 0;
    return Math.max(0, Math.min(1, value));
  }

  function effective(sourceVolume) {
    if (streamerMode) return 0;
    return clamp(sourceVolume) * (1 - 0.5 * clamp(voiceActivity));
  }

  function youtubeCommand(entry, method, args) {
    if (!entry || !entry.iframe || !entry.iframe.contentWindow) return;
    entry.iframe.contentWindow.postMessage(JSON.stringify({
      event: 'command', func: method, args: args || [], id: entry.iframe.id,
    }), 'https://www.youtube-nocookie.com');
  }

  function applyVolume(entry) {
    if (!entry) return;
    var value = effective(entry.sourceVolume);
    entry.effectiveVolume = value;

    if (entry.backend === 'audio') {
      entry.handle.muted = streamerMode;
      entry.handle.volume = value;
    } else if (entry.backend === 'youtube' && entry.ready) {
      youtubeCommand(entry, 'setVolume', [Math.round(value * 100)]);
      youtubeCommand(entry, streamerMode || value === 0 ? 'mute' : 'unMute');
    }
  }

  function onMaster(data) {
    if (typeof data.streamer_mode === 'boolean') streamerMode = data.streamer_mode;
    if (Number.isFinite(Number(data.voice_activity))) voiceActivity = clamp(data.voice_activity);
    Object.keys(sounds).forEach(function (name) { applyVolume(sounds[name]); });
  }

  function onPlay(data) {
    if (!data || typeof data.name !== 'string' || typeof data.url !== 'string') return;
    if (typeof data.streamer_mode === 'boolean') streamerMode = data.streamer_mode;
    destroyIfExists(data.name);
    var sourceVolume = clamp(data.volume);
    var youtubeId = parseYouTubeId(data.url);
    if (youtubeId) playYouTube(data.name, youtubeId, sourceVolume, data.loop === true);
    else playAudio(data.name, data.url, sourceVolume, data.loop === true);
  }

  function playAudio(name, url, sourceVolume, loop) {
    var audio = new Audio();
    var entry = {
      backend: 'audio', handle: audio, ready: true,
      sourceVolume: sourceVolume, effectiveVolume: 0, loop: loop,
    };
    sounds[name] = entry;
    audio.loop = loop;
    audio.preload = 'auto';
    applyVolume(entry);
    audio.addEventListener('ended', function () {
      if (!loop) complete(name, entry, 'ended');
    }, { once: true });
    audio.addEventListener('error', function () { complete(name, entry, 'error'); }, { once: true });
    audio.src = url;
    audio.play().catch(function () { complete(name, entry, 'error'); });
  }

  function playYouTube(name, videoId, sourceVolume, loop) {
    var iframe = document.createElement('iframe');
    iframe.id = 'ytp-' + safeId(name);
    iframe.width = '1';
    iframe.height = '1';
    iframe.setAttribute('allow', 'autoplay');
    iframe.setAttribute('title', 'Player de áudio');
    iframe.src = 'https://www.youtube-nocookie.com/embed/' + videoId +
      '?enablejsapi=1&autoplay=0&controls=0&disablekb=1&fs=0&playsinline=1&rel=0' +
      (loop ? '&loop=1&playlist=' + videoId : '');

    var entry = {
      backend: 'youtube', iframe: iframe, ready: false,
      sourceVolume: sourceVolume, effectiveVolume: 0, loop: loop,
    };
    sounds[name] = entry;
    document.getElementById('wow-players').appendChild(iframe);

    iframe.addEventListener('load', function () {
      if (sounds[name] !== entry) return;
      entry.ready = true;
      iframe.contentWindow.postMessage(JSON.stringify({ event: 'listening', id: iframe.id }),
        'https://www.youtube-nocookie.com');
      youtubeCommand(entry, 'addEventListener', ['onStateChange']);
      youtubeCommand(entry, 'addEventListener', ['onError']);
      youtubeCommand(entry, 'mute');
      applyVolume(entry);
      youtubeCommand(entry, 'playVideo');
    }, { once: true });
  }

  function onProviderMessage(event) {
    if (event.origin !== 'https://www.youtube-nocookie.com'
        && event.origin !== 'https://www.youtube.com') return;
    var payload = event.data;
    if (typeof payload === 'string') {
      try { payload = JSON.parse(payload); } catch (error) { return; }
    }
    if (!payload || typeof payload.event !== 'string') return;

    Object.keys(sounds).some(function (name) {
      var entry = sounds[name];
      if (entry.backend !== 'youtube' || entry.iframe.contentWindow !== event.source) return false;
      if (payload.event === 'onError') complete(name, entry, 'error');
      else if (payload.event === 'onStateChange' && Number(payload.info) === 0 && !entry.loop) {
        complete(name, entry, 'ended');
      }
      return true;
    });
  }

  function onPause(data) {
    var entry = sounds[data.name];
    if (!entry) return;
    if (entry.backend === 'audio') entry.handle.pause();
    else if (entry.ready) youtubeCommand(entry, 'pauseVideo');
  }

  function onResume(data) {
    var entry = sounds[data.name];
    if (!entry) return;
    applyVolume(entry);
    if (entry.backend === 'audio') entry.handle.play().catch(function () {
      complete(data.name, entry, 'error');
    });
    else if (entry.ready) youtubeCommand(entry, 'playVideo');
  }

  function onVolume(data) {
    var entry = sounds[data.name];
    if (!entry) return;
    entry.sourceVolume = clamp(data.volume);
    applyVolume(entry);
  }

  function complete(name, entry, status) {
    if (sounds[name] !== entry) return;
    destroyIfExists(name);
    vhub.native.wow.audioLifecycle(name, status);
  }

  function destroyIfExists(name) {
    var entry = sounds[name];
    if (!entry) return;
    delete sounds[name];
    if (entry.backend === 'audio') {
      entry.handle.pause();
      entry.handle.removeAttribute('src');
      entry.handle.load();
    } else if (entry.iframe && entry.iframe.parentNode) {
      entry.iframe.parentNode.removeChild(entry.iframe);
    }
  }

  function safeId(name) {
    return String(name).replace(/[^a-zA-Z0-9_-]/g, '_');
  }

  function parseYouTubeId(url) {
    var host = typeof url === 'string' && (url.match(/^https:\/\/([\w.-]+)\//) || [])[1];
    if (!host || ['youtu.be', 'youtube.com', 'www.youtube.com', 'm.youtube.com',
      'music.youtube.com', 'www.youtube-nocookie.com', 'youtube-nocookie.com'].indexOf(host) < 0) {
      return null;
    }
    var match = url.match(/[?&]v=([\w-]+)/) || url.match(/youtu\.be\/([\w-]+)/) ||
      url.match(/\/shorts\/([\w-]+)/) || url.match(/\/embed\/([\w-]+)/);
    return match && match[1] && match[1].length >= 11 ? match[1].slice(0, 11) : null;
  }

  function cleanup() {
    window.removeEventListener('message', onProviderMessage);
    Object.keys(sounds).forEach(destroyIfExists);
  }
})();
