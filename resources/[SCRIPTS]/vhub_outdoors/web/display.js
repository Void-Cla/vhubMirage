// display.js - lifecycle da midia validada do outdoor

var discordHosts = {
  'cdn.discordapp.com': true,
  'media.discordapp.net': true,
};
var imgurHosts = { 'i.imgur.com': true };
var imageExtensions = { png: true, jpg: true, jpeg: true, webp: true, gif: true };
var videoExtensions = { mp4: true, webm: true };
var maxMediaPixels = 8388608;
var maxMediaSide = 4096;
var maxVideoSeconds = 1800;
var youtubeOrigin = 'https://www.youtube.com';

function validDimensions(width, height) {
  return Number.isFinite(width) && Number.isFinite(height)
    && width >= 1 && height >= 1
    && width <= maxMediaSide && height <= maxMediaSide
    && width * height <= maxMediaPixels;
}

function mediaType(source) {
  try {
    var url = new URL(source);
    var discord = discordHosts[url.hostname]
      && /^\/attachments\/\d+\/\d+\//.test(url.pathname);
    var imgur = imgurHosts[url.hostname] === true
      && /^\/[\w-]+\.[a-z0-9]+$/i.test(url.pathname);
    if (url.protocol !== 'https:' || (!discord && !imgur)) {
      return null;
    }
    var match = url.pathname.toLowerCase().match(/\.([a-z0-9]+)$/);
    if (!match) return null;
    if (imageExtensions[match[1]]) return 'image';
    if (discord && videoExtensions[match[1]]) return 'video';
  } catch (error) {
    return null;
  }
  return null;
}

var display = {
  root: null,
  viewport: null,
  current: null,
  id: null,
  type: null,
  source: '',
  targetAspect: 16 / 9,
  canvasAspect: 16 / 9,
  ready: false,
  providerReady: false,
  playing: false,
  youtubeReloads: 0,
  handshakeTimer: null,
  readyTimer: null,
  playbackTimer: null,
  playbackDeadline: null,
  progressTimer: null,
  progressConfirmed: false,
  lastTime: 0,
  lastProgressAt: 0,
  failureReported: false,
  mediaTimer: null,

  onInit: function () {
    var params = new URLSearchParams(window.location.search);
    var id = Number(params.get('id'));
    if (Number.isInteger(id) && id >= 1) this.id = id;
    this.type = params.get('type');
    this.source = params.get('source') || '';
    var aspect = Number(params.get('aspect'));
    if (Number.isFinite(aspect) && aspect >= 0.25 && aspect <= 8) {
      this.targetAspect = aspect;
    }
  },

  reportFailure: function (stage) {
    if (this.failureReported || !this.id || typeof stage !== 'string') return;
    this.failureReported = true;
    fetch('https://' + GetParentResourceName() + '/displayFailure', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id: this.id, stage: stage }),
    }).catch(function () {});
  },

  onMount: function () {
    this.root = document.getElementById('outdoor');
    if (!this.root) return;
    this.viewport = document.createElement('div');
    this.viewport.className = 'media-viewport';
    this.viewport.style.width = (this.targetAspect / this.canvasAspect * 100) + '%';
    this.viewport.style.transform = 'translateX(-50%) scaleX('
      + (this.canvasAspect / this.targetAspect) + ')';
    this.root.appendChild(this.viewport);
    if (this.type === 'image') this.mountImage();
    else if (this.type === 'video') this.mountVideo();
    else if (this.type === 'youtube') this.mountYouTube();
  },

  onShow: function () {
    if (this.ready && this.current && this.current.tagName === 'VIDEO') {
      this.current.play().catch(function () {});
    }
  },

  onHide: function () {
    if (this.current && this.current.tagName === 'VIDEO') this.current.pause();
  },

  onDestroy: function () {
    window.removeEventListener('beforeunload', handleUnload);
    window.removeEventListener('message', handleProviderMessage);
    window.clearInterval(this.handshakeTimer);
    window.clearTimeout(this.readyTimer);
    window.clearInterval(this.playbackTimer);
    window.clearTimeout(this.playbackDeadline);
    window.clearInterval(this.progressTimer);
    window.clearTimeout(this.mediaTimer);
    this.handshakeTimer = null;
    this.readyTimer = null;
    this.playbackTimer = null;
    this.playbackDeadline = null;
    this.progressTimer = null;
    this.mediaTimer = null;
    this.ready = false;
    this.providerReady = false;
    this.playing = false;
    if (this.current) {
      if (this.current.tagName === 'VIDEO') {
        this.current.pause();
        this.current.removeAttribute('src');
        this.current.load();
      } else if (this.current.tagName === 'IFRAME') {
        this.current.src = 'about:blank';
      }
      this.current.remove();
      this.current = null;
    }
    if (this.viewport) this.viewport.remove();
    this.viewport = null;
    this.root = null;
  },

  mountImage: function () {
    if (mediaType(this.source) !== 'image') return;
    var image = document.createElement('img');
    image.alt = '';
    image.decoding = 'async';
    image.referrerPolicy = 'no-referrer';
    image.addEventListener('load', function () {
      window.clearTimeout(display.mediaTimer);
      display.mediaTimer = null;
      if (display.current !== image
          || validDimensions(image.naturalWidth, image.naturalHeight)) {
        if (display.current === image) display.ready = true;
        return;
      }
      image.removeAttribute('src');
      image.remove();
      display.current = null;
      display.reportFailure('image_invalid');
    }, { once: true });
    image.addEventListener('error', function () {
      window.clearTimeout(display.mediaTimer);
      display.mediaTimer = null;
      if (display.current !== image) return;
      display.current = null;
      image.remove();
      display.reportFailure('image_error');
    }, { once: true });
    image.src = this.source;
    this.current = image;
    this.viewport.appendChild(image);
    this.mediaTimer = window.setTimeout(function () {
      if (display.current === image && !display.ready) {
        display.reportFailure('image_timeout');
      }
    }, 10000);
  },

  mountVideo: function () {
    if (mediaType(this.source) !== 'video') return;
    var video = document.createElement('video');
    video.autoplay = true;
    video.loop = true;
    video.muted = true;
    video.playsInline = true;
    video.preload = 'auto';
    video.referrerPolicy = 'no-referrer';
    video.addEventListener('playing', function () {
      if (display.current !== video) return;
      display.playing = true;
    });
    video.addEventListener('pause', function () {
      if (display.current === video) display.playing = false;
    });
    video.addEventListener('loadedmetadata', function () {
      window.clearTimeout(display.mediaTimer);
      display.mediaTimer = null;
      if (display.current !== video) return;
      var duration = video.duration;
      var validDuration = Number.isFinite(duration)
        && duration > 0 && duration <= maxVideoSeconds;
      if (!validDimensions(video.videoWidth, video.videoHeight) || !validDuration) {
        video.removeAttribute('src');
        video.load();
        video.remove();
        display.current = null;
        display.reportFailure('video_invalid');
        return;
      }
      display.startVideoWatchdog(video);
    }, { once: true });
    video.addEventListener('error', function () {
      window.clearTimeout(display.mediaTimer);
      display.mediaTimer = null;
      if (display.current !== video) return;
      display.ready = false;
      display.playing = false;
      display.reportFailure('video_error');
    });
    video.src = this.source;
    this.current = video;
    this.viewport.appendChild(video);
    this.mediaTimer = window.setTimeout(function () {
      if (display.current === video && !display.ready) {
        display.reportFailure('video_timeout');
      }
    }, 10000);
  },

  startVideoWatchdog: function (video) {
    var lastTime = video.currentTime;
    var lastAdvanceAt = Date.now();
    var reloads = 0;
    window.clearInterval(this.playbackTimer);
    var verify = function () {
      if (display.current !== video) return;
      if (video.paused) video.play().catch(function () {});
      if (Number.isFinite(video.currentTime)
          && lastTime >= 0 && Math.abs(video.currentTime - lastTime) >= 0.02) {
        lastAdvanceAt = Date.now();
        display.ready = true;
        display.playing = true;
      }
      lastTime = Number.isFinite(video.currentTime) ? video.currentTime : lastTime;
      if (Date.now() - lastAdvanceAt >= 3000) {
        if (reloads < 2) {
          reloads += 1;
          lastTime = -1;
          lastAdvanceAt = Date.now();
          display.ready = false;
          display.playing = false;
          video.load();
          video.play().catch(function () {});
        } else {
          window.clearInterval(display.playbackTimer);
          display.playbackTimer = null;
          display.ready = false;
          display.playing = false;
          video.pause();
          video.removeAttribute('src');
          video.load();
          console.error('[vhub_outdoors] video direto sem progresso apos retries.');
          display.reportFailure('video_stalled');
        }
      }
    };
    verify();
    this.playbackTimer = window.setInterval(verify, 1000);
  },

  mountYouTube: function () {
    if (!/^[A-Za-z0-9_-]{11}$/.test(this.source)) return;
    var frame = document.createElement('iframe');
    frame.id = 'youtube-outdoor';
    frame.title = 'Video do outdoor';
    frame.allow = 'autoplay; encrypted-media';
    frame.referrerPolicy = 'strict-origin-when-cross-origin';
    var videoAspect = 16 / 9;
    if (this.targetAspect >= videoAspect) {
      frame.style.width = '100%';
      frame.style.height = (this.targetAspect / videoAspect * 100) + '%';
    } else {
      frame.style.width = (videoAspect / this.targetAspect * 100) + '%';
      frame.style.height = '100%';
    }
    frame.src = youtubeOrigin + '/embed/' + this.source
      + '?enablejsapi=1&autoplay=1&mute=1&controls=0&disablekb=1&fs=0&playsinline=1'
      + '&rel=0&loop=1&playlist=' + this.source;
    frame.addEventListener('load', function () {
      if (display.current !== frame) return;
      display.startYouTubeHandshake(frame);
    }, { once: true });
    this.current = frame;
    this.readyTimer = window.setTimeout(function () {
      if (display.current === frame && !display.providerReady) {
        display.retryYouTube(frame);
      }
    }, 10000);
    this.viewport.appendChild(frame);
  },

  sendYouTube: function (method, args) {
    if (!this.current || this.current.tagName !== 'IFRAME'
        || !this.current.contentWindow) return;
    this.current.contentWindow.postMessage(JSON.stringify({
      event: 'command',
      func: method,
      args: args || [],
      id: this.current.id,
      channel: 'widget',
    }), youtubeOrigin);
  },

  startYouTubeHandshake: function (frame) {
    var listen = function () {
      if (display.current !== frame || !frame.contentWindow) return;
      frame.contentWindow.postMessage(JSON.stringify({
        event: 'listening',
        id: frame.id,
        channel: 'widget',
      }), youtubeOrigin);
    };
    listen();
    this.handshakeTimer = window.setInterval(listen, 250);
  },

  clearStartTimers: function () {
    window.clearInterval(this.playbackTimer);
    window.clearTimeout(this.playbackDeadline);
    this.playbackTimer = null;
    this.playbackDeadline = null;
  },

  clearPlaybackTimers: function () {
    this.clearStartTimers();
    window.clearInterval(this.progressTimer);
    this.progressTimer = null;
  },

  startYouTubePlayback: function (frame) {
    if (this.current !== frame || !this.providerReady) return;
    if (this.playbackTimer || this.playbackDeadline) {
      this.sendYouTube('playVideo');
      return;
    }
    this.clearPlaybackTimers();
    this.playing = false;
    this.ready = false;
    this.progressConfirmed = false;
    this.lastTime = 0;
    this.lastProgressAt = 0;
    this.sendYouTube('mute');
    this.sendYouTube('playVideo');
    if (!this.playbackTimer) {
      this.playbackTimer = window.setInterval(function () {
        if (display.current === frame && display.providerReady && !display.playing) {
          display.sendYouTube('playVideo');
        }
      }, 1000);
    }
    if (!this.playbackDeadline) {
      this.playbackDeadline = window.setTimeout(function () {
        if (display.current === frame && !display.progressConfirmed) {
          display.retryYouTube(frame);
        }
      }, 10000);
    }
  },

  startProgressWatchdog: function (frame) {
    if (this.progressTimer) return;
    this.progressTimer = window.setInterval(function () {
      if (display.current !== frame || !display.providerReady) return;
      display.sendYouTube('getCurrentTime');
      if (display.progressConfirmed && Date.now() - display.lastProgressAt > 3000) {
        display.retryYouTube(frame);
      }
    }, 1000);
  },

  recordYouTubeProgress: function (frame, info) {
    if (this.current !== frame) return;
    var currentTime = Number(info && info.currentTime);
    if (!Number.isFinite(currentTime) || currentTime < 0) return;
    var advanced = Math.abs(currentTime - this.lastTime) >= 0.05;
    this.lastTime = currentTime;
    if (!advanced) return;
    this.lastProgressAt = Date.now();
    if (!this.progressConfirmed) {
      this.progressConfirmed = true;
      this.ready = true;
      window.clearTimeout(this.playbackDeadline);
      this.playbackDeadline = null;
    }
  },

  retryYouTube: function (frame) {
    if (this.current !== frame) return;
    window.clearInterval(this.handshakeTimer);
    window.clearTimeout(this.readyTimer);
    this.clearPlaybackTimers();
    this.handshakeTimer = null;
    this.readyTimer = null;
    this.ready = false;
    this.providerReady = false;
    this.playing = false;
    frame.src = 'about:blank';
    frame.remove();
    this.current = null;
    if (this.youtubeReloads >= 1) {
      console.error('[vhub_outdoors] YouTube sem progresso apos retry.');
      this.reportFailure('youtube_stalled');
      return;
    }
    this.youtubeReloads += 1;
    this.mountYouTube();
  },
};

function handleProviderMessage(event) {
  if (event.origin !== youtubeOrigin || !display.current
      || display.current.tagName !== 'IFRAME'
      || display.current.contentWindow !== event.source) return;
  var payload = event.data;
  if (typeof payload === 'string') {
    try { payload = JSON.parse(payload); } catch (error) { return; }
  }
  if (!payload || typeof payload.event !== 'string') return;
  if (payload.event === 'onReady') {
    if (display.providerReady) return;
    window.clearInterval(display.handshakeTimer);
    window.clearTimeout(display.readyTimer);
    display.handshakeTimer = null;
    display.readyTimer = null;
    display.providerReady = true;
    display.sendYouTube('addEventListener', ['onStateChange']);
    display.sendYouTube('addEventListener', ['onError']);
    display.sendYouTube('addEventListener', ['onAutoplayBlocked']);
    display.sendYouTube('mute');
    display.startYouTubePlayback(display.current);
  } else if (payload.event === 'onError' || payload.event === 'onAutoplayBlocked') {
    display.retryYouTube(display.current);
  } else if (payload.event === 'onStateChange') {
    var state = Number(payload.info);
    if (state === 1) {
      display.playing = true;
      window.clearInterval(display.playbackTimer);
      display.playbackTimer = null;
      display.startProgressWatchdog(display.current);
    } else if ([ -1, 0, 2, 5 ].indexOf(state) >= 0) {
      display.startYouTubePlayback(display.current);
    }
  } else if (payload.event === 'infoDelivery') {
    display.recordYouTubeProgress(display.current, payload.info);
  }
}

function handleUnload() {
  display.onHide();
  display.onDestroy();
}

display.onInit();
window.addEventListener('message', handleProviderMessage);
display.onMount();
display.onShow();
window.addEventListener('beforeunload', handleUnload);
