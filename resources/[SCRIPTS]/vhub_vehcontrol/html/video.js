// video.js — telinha YouTube muda; áudio pertence ao vhub_wow

(function () {
  'use strict';

  var state = vhub.store('video');
  var busOffs = [];
  var domOffs = [];

  state.iframe = null;
  state.videoId = null;


  // ============================================================
  // PLAYER
  // ============================================================

  function destroyPlayer() {
    if (state.iframe && state.iframe.parentNode) {
      state.iframe.parentNode.removeChild(state.iframe);
    }
    state.iframe = null;
    state.videoId = null;
    if (vhub.el.dvdFrame) vhub.el.dvdFrame.replaceChildren();
  }

  function detachVideo() {
    destroyPlayer();
    vhub.el.dvd.classList.add('hidden');
    vhub.emit('sound:videoState', { enabled: false });
  }

  function attachVideo(payload) {
    var videoId = payload.video_id || '';
    if (!/^[\w-]{11}$/.test(videoId)) return;
    if (state.iframe && state.videoId === videoId) {
      vhub.el.dvd.classList.remove('hidden');
      return;
    }

    destroyPlayer();
    var iframe = document.createElement('iframe');
    iframe.width = '100%';
    iframe.height = '100%';
    iframe.setAttribute('allow', 'autoplay; encrypted-media');
    iframe.setAttribute('title', 'Vídeo do carro');
    iframe.setAttribute('referrerpolicy', 'strict-origin-when-cross-origin');
    iframe.src = 'https://www.youtube-nocookie.com/embed/' + videoId +
      '?autoplay=1&mute=1&controls=0&disablekb=1&fs=0&playsinline=1&rel=0';

    state.iframe = iframe;
    state.videoId = videoId;
    vhub.el.dvdTitle.textContent = payload.title || 'DVD do carro';
    vhub.el.dvdFrame.appendChild(iframe);
    vhub.el.dvd.classList.remove('hidden');
    vhub.emit('sound:videoState', { enabled: true });
  }


  // ============================================================
  // LIFECYCLE
  // ============================================================

  vhub.createModule('video', {
    root: '#vc-dvd',
    onInit: function () {
      busOffs.push(vhub.listen('video:attach', attachVideo));
      busOffs.push(vhub.listen('video:detach', detachVideo));
    },
    onMount: function () {
      domOffs.push(vhub.bind(vhub.el.dvdClose, 'click', function () {
        detachVideo();
        vhub.native.sound.videoOff();
      }));
      domOffs.push(vhub.bind(window, 'beforeunload', destroyPlayer));
    },
    onShow: function () {},
    onHide: detachVideo,
    onDestroy: function () {
      destroyPlayer();
      while (domOffs.length) domOffs.pop()();
      while (busOffs.length) busOffs.pop()();
    },
  });
})();
