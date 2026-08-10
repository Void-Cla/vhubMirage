// audio.js — backends HTML5/YouTube com master gain único e cleanup explícito

(function () {
  'use strict';

  var sounds = Object.create(null);
  var streamerMode = false;
  var voiceActivity = 0;
  var youtubeOrigin = 'https://www.youtube.com';
  var subscriptions = [
    vhub.listen('nui:wow:audio:play', onPlay),
    vhub.listen('nui:wow:audio:destroy', function (data) { destroyIfExists(data.name); }),
    vhub.listen('nui:wow:audio:pause', onPause),
    vhub.listen('nui:wow:audio:resume', onResume),
    vhub.listen('nui:wow:audio:volume', onVolume),
    vhub.listen('nui:wow:audio:volumes', onVolumes),
    vhub.listen('nui:wow:audio:master', onMaster),
  ];

  window.addEventListener('message', onProviderMessage);
  window.addEventListener('beforeunload', cleanup);

  function clamp(value) {
    value = Number(value);
    if (!Number.isFinite(value)) return 0;
    return Math.max(0, Math.min(1, value));
  }

  function duckStrength(value) {
    value = Number(value);
    return Number.isFinite(value) ? clamp(value) : 0.5;
  }

  function effective(entry) {
    if (streamerMode) return 0;
    return clamp(entry.sourceVolume) *
      (1 - entry.duckStrength * clamp(voiceActivity));
  }

  function youtubeCommand(entry, method, args) {
    if (!entry || !entry.iframe || !entry.iframe.contentWindow) return;
    entry.iframe.contentWindow.postMessage(JSON.stringify({
      event: 'command',
      func: method,
      args: args || [],
      id: entry.iframe.id,
      channel: 'widget',
    }), youtubeOrigin);
  }

  function applyVolume(entry) {
    if (!entry) return;
    var value = effective(entry);
    entry.effectiveVolume = value;

    if (entry.backend === 'audio') {
      entry.handle.muted = streamerMode;
      entry.handle.volume = value;
    } else if (entry.backend === 'youtube' && entry.ready) {
      youtubeCommand(entry, 'setVolume', [Math.round(value * 100)]);
      youtubeCommand(entry,
        streamerMode || value === 0 || !entry.playing || !entry.progressConfirmed
          ? 'mute' : 'unMute');
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
    var sourceDuckStrength = duckStrength(data.duck_strength);
    var youtubeId = parseYouTubeId(data.url);
    if (youtubeId) {
      playYouTube(data.name, youtubeId, sourceVolume, data.loop === true,
        sourceDuckStrength);
    } else {
      playAudio(data.name, data.url, sourceVolume, data.loop === true,
        sourceDuckStrength);
    }
  }

  function playAudio(name, url, sourceVolume, loop, sourceDuckStrength) {
    var audio = new Audio();
    var entry = {
      backend: 'audio', handle: audio, ready: true,
      sourceVolume: sourceVolume, effectiveVolume: 0, loop: loop,
      duckStrength: sourceDuckStrength,
      reportedReady: false,
    };
    sounds[name] = entry;
    audio.loop = loop;
    audio.preload = 'auto';
    applyVolume(entry);
    audio.addEventListener('ended', function () {
      if (!loop) complete(name, entry, 'ended');
    }, { once: true });
    audio.addEventListener('error', function () { complete(name, entry, 'error'); }, { once: true });
    audio.addEventListener('playing', function () { reportReady(name, entry); }, { once: true });
    audio.src = url;
    audio.play().catch(function () { complete(name, entry, 'error'); });
  }

  function playYouTube(name, videoId, sourceVolume, loop, sourceDuckStrength) {
    var iframe = document.createElement('iframe');
    iframe.id = 'ytp-' + safeId(name);
    iframe.width = '200';
    iframe.height = '200';
    iframe.setAttribute('allow', 'autoplay');
    iframe.setAttribute('title', 'Player de áudio');
    iframe.src = youtubeOrigin + '/embed/' + videoId +
      '?enablejsapi=1&autoplay=1&mute=1&controls=0&disablekb=1&fs=0&playsinline=1&rel=0' +
      (loop ? '&loop=1&playlist=' + videoId : '');

    var entry = {
      backend: 'youtube', iframe: iframe, ready: false,
      videoId: videoId,
      sourceVolume: sourceVolume, effectiveVolume: 0, loop: loop,
      duckStrength: sourceDuckStrength,
      desiredPlaying: true, playing: false,
      reportedReady: false, retried: false,
      handshakeTimer: null, readyTimer: null,
      playbackTimer: null, playbackDeadline: null,
      progressTimer: null, progressConfirmed: false,
      lastTime: 0, lastProgressAt: 0,
    };
    sounds[name] = entry;
    entry.readyTimer = window.setTimeout(function () {
      if (sounds[name] === entry && !entry.ready) complete(name, entry, 'error');
    }, 20000);
    document.getElementById('wow-players').appendChild(iframe);

    iframe.addEventListener('load', function () {
      if (sounds[name] !== entry) return;
      var listen = function () {
        if (sounds[name] !== entry || !iframe.contentWindow) return;
        iframe.contentWindow.postMessage(JSON.stringify({
          event: 'listening',
          id: iframe.id,
          channel: 'widget',
        }), youtubeOrigin);
      };
      listen();
      entry.handshakeTimer = window.setInterval(listen, 250);
    }, { once: true });
  }

  function retryYouTube(name, entry) {
    if (sounds[name] !== entry) return;
    if (entry.retried) { complete(name, entry, 'error'); return; }
    entry.retried = true;
    // limpa estado do iframe antigo
    window.clearInterval(entry.handshakeTimer);
    window.clearTimeout(entry.readyTimer);
    clearPlaybackTimers(entry);
    entry.handshakeTimer = null; entry.readyTimer = null;
    entry.ready = false; entry.playing = false;
    entry.progressConfirmed = false;
    if (entry.iframe && entry.iframe.parentNode) {
      entry.iframe.src = 'about:blank';
      entry.iframe.parentNode.removeChild(entry.iframe);
    }
    // recria o iframe
    var videoId = entry.videoId;
    if (!videoId) { complete(name, entry, 'error'); return; }
    var iframe = document.createElement('iframe');
    iframe.id = 'ytp-' + safeId(name);
    iframe.width = '200'; iframe.height = '200';
    iframe.setAttribute('allow', 'autoplay');
    iframe.setAttribute('title', 'Player de áudio');
    iframe.src = youtubeOrigin + '/embed/' + videoId +
      '?enablejsapi=1&autoplay=1&mute=1&controls=0&disablekb=1&fs=0&playsinline=1&rel=0' +
      (entry.loop ? '&loop=1&playlist=' + videoId : '');
    entry.iframe = iframe;
    entry.readyTimer = window.setTimeout(function () {
      if (sounds[name] === entry && !entry.ready) complete(name, entry, 'error');
    }, 20000);
    document.getElementById('wow-players').appendChild(iframe);
    iframe.addEventListener('load', function () {
      if (sounds[name] !== entry) return;
      var listen = function () {
        if (sounds[name] !== entry || !iframe.contentWindow) return;
        iframe.contentWindow.postMessage(JSON.stringify({
          event: 'listening', id: iframe.id, channel: 'widget',
        }), youtubeOrigin);
      };
      listen();
      entry.handshakeTimer = window.setInterval(listen, 250);
    }, { once: true });
  }

  function clearStartTimers(entry) {
    window.clearInterval(entry.playbackTimer);
    window.clearTimeout(entry.playbackDeadline);
    entry.playbackTimer = null;
    entry.playbackDeadline = null;
  }

  function clearPlaybackTimers(entry) {
    clearStartTimers(entry);
    window.clearInterval(entry.progressTimer);
    entry.progressTimer = null;
  }

  function startYouTubePlayback(name, entry) {
    if (sounds[name] !== entry || !entry.ready || !entry.desiredPlaying) return;
    if (entry.playbackTimer || entry.playbackDeadline) {
      youtubeCommand(entry, 'playVideo');
      return;
    }
    clearPlaybackTimers(entry);
    entry.playing = false;
    entry.progressConfirmed = false;
    entry.lastTime = 0;
    entry.lastProgressAt = 0;
    applyVolume(entry);
    youtubeCommand(entry, 'mute');
    youtubeCommand(entry, 'playVideo');
    if (!entry.playbackTimer) {
      entry.playbackTimer = window.setInterval(function () {
        if (sounds[name] === entry && entry.ready && entry.desiredPlaying && !entry.playing) {
          youtubeCommand(entry, 'playVideo');
        }
      }, 1000);
    }
    if (!entry.playbackDeadline) {
      entry.playbackDeadline = window.setTimeout(function () {
        if (sounds[name] === entry && entry.desiredPlaying && !entry.progressConfirmed) {
          complete(name, entry, 'error');
        }
      }, 20000);
    }
  }

  function startProgressWatchdog(name, entry) {
    if (entry.progressTimer) return;
    // loop=true: video nunca termina naturalmente; watchdog so detecta travamento real (30s)
    var stallTimeout = entry.loop ? 30000 : 12000;
    entry.progressTimer = window.setInterval(function () {
      if (sounds[name] !== entry || !entry.desiredPlaying) return;
      youtubeCommand(entry, 'getCurrentTime');
      if (entry.progressConfirmed && Date.now() - entry.lastProgressAt > stallTimeout) {
        complete(name, entry, 'error');
      }
    }, 1000);
  }

  function recordYouTubeProgress(name, entry, info) {
    var currentTime = Number(info && info.currentTime);
    if (!Number.isFinite(currentTime) || currentTime < 0) return;
    var advanced = Math.abs(currentTime - entry.lastTime) >= 0.05;
    entry.lastTime = currentTime;
    if (!advanced) return;
    entry.lastProgressAt = Date.now();
    if (!entry.progressConfirmed) {
      entry.progressConfirmed = true;
      window.clearTimeout(entry.playbackDeadline);
      entry.playbackDeadline = null;
      applyVolume(entry);
      reportReady(name, entry);
    }
  }

  function onProviderMessage(event) {
    if (event.origin !== youtubeOrigin) return;
    var payload = event.data;
    if (typeof payload === 'string') {
      try { payload = JSON.parse(payload); } catch (error) { return; }
    }
    if (!payload || typeof payload.event !== 'string') return;

    Object.keys(sounds).some(function (name) {
      var entry = sounds[name];
      if (entry.backend !== 'youtube' || entry.iframe.contentWindow !== event.source) return false;
      if (payload.event === 'onReady') {
        if (entry.ready) return true;
        window.clearInterval(entry.handshakeTimer);
        window.clearTimeout(entry.readyTimer);
        entry.handshakeTimer = null;
        entry.readyTimer = null;
        entry.ready = true;
        youtubeCommand(entry, 'addEventListener', ['onStateChange']);
        youtubeCommand(entry, 'addEventListener', ['onError']);
        youtubeCommand(entry, 'addEventListener', ['onAutoplayBlocked']);
        startYouTubePlayback(name, entry);
      } else if (payload.event === 'onError') {
        complete(name, entry, 'error');
      } else if (payload.event === 'onAutoplayBlocked') {
        // autoplay bloqueado: recarrega o iframe do zero uma vez antes de desistir
        retryYouTube(name, entry);
      } else if (payload.event === 'onStateChange') {
        var state = Number(payload.info);
        if (state === 1) {
          if (!entry.desiredPlaying) {
            youtubeCommand(entry, 'pauseVideo');
          } else {
            entry.playing = true;
            window.clearInterval(entry.playbackTimer);
            entry.playbackTimer = null;
            startProgressWatchdog(name, entry);
          }
        } else if (state === 0 && !entry.loop) {
          complete(name, entry, 'ended');
        } else if (entry.desiredPlaying && [ -1, 0, 2, 5 ].indexOf(state) >= 0) {
          startYouTubePlayback(name, entry);
        }
      } else if (payload.event === 'infoDelivery') {
        recordYouTubeProgress(name, entry, payload.info);
      }
      return true;
    });
  }

  function onPause(data) {
    var entry = sounds[data.name];
    if (!entry) return;
    if (entry.backend === 'audio') entry.handle.pause();
    else {
      entry.desiredPlaying = false;
      entry.playing = false;
      clearPlaybackTimers(entry);
      if (entry.ready) youtubeCommand(entry, 'pauseVideo');
    }
  }

  function onResume(data) {
    var entry = sounds[data.name];
    if (!entry) return;
    applyVolume(entry);
    if (entry.backend === 'audio') entry.handle.play().catch(function () {
      complete(data.name, entry, 'error');
    });
    else {
      entry.desiredPlaying = true;
      startYouTubePlayback(data.name, entry);
    }
  }

  function onVolume(data) {
    var entry = sounds[data.name];
    if (!entry) return;
    entry.sourceVolume = clamp(data.volume);
    applyVolume(entry);
  }

  function onVolumes(data) {
    var items = data && data.items;
    if (!items || typeof items !== 'object' || Array.isArray(items)) return;
    Object.keys(items).slice(0, 16).forEach(function (name) {
      var entry = sounds[name];
      if (!entry) return;
      entry.sourceVolume = clamp(items[name]);
      applyVolume(entry);
    });
  }

  function reportReady(name, entry) {
    if (sounds[name] !== entry || entry.reportedReady) return;
    entry.reportedReady = true;
    vhub.native.wow.audioLifecycle(name, 'ready');
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
    } else {
      window.clearInterval(entry.handshakeTimer);
      window.clearTimeout(entry.readyTimer);
      clearPlaybackTimers(entry);
      if (entry.iframe && entry.iframe.parentNode) {
        entry.iframe.parentNode.removeChild(entry.iframe);
      }
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
    window.removeEventListener('beforeunload', cleanup);
    subscriptions.forEach(function (unsubscribe) { unsubscribe(); });
    subscriptions = [];
    Object.keys(sounds).forEach(destroyIfExists);
  }
})();
