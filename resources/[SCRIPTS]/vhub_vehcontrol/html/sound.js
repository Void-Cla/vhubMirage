// sound.js — controle de áudio delegado ao servidor e ao vhub_wow

(function () {
  'use strict';

  var state = vhub.store('sound');
  var busOffs = [];
  var domOffs = [];
  var searchTimer = null;
  var searchTimeout = null;
  var volumeTimer = null;
  var refreshTimer = null;
  var pulseTimer = null;
  var pulseTarget = null;
  var volumeSent = -1;
  var generation = 0;
  var active = false;

  if (state.playing === undefined) state.playing = false;
  if (!state.source) state.source = 'search';
  if (state.volume === undefined) state.volume = 55;
  if (state.video === undefined) state.video = false;
  if (state.streamer === undefined) state.streamer = false;
  state.results = state.results || [];


  // ============================================================
  // RENDER
  // ============================================================

  function setTrackMeta(title, artist) {
    state.title = title || '';
    state.artist = artist || '';
    vhub.el.soundTitle.textContent = title || 'Nenhuma faixa';
    vhub.el.soundArtist.textContent = artist || '— · —';
  }

  function resetVideoToggle() {
    state.video = false;
    vhub.el.soundVideo.setAttribute('aria-pressed', 'false');
    vhub.el.soundVideo.classList.remove('is-on');
  }

  function setPlaying(on) {
    var el = vhub.el;
    state.playing = on === true;
    if (!state.playing) {
      clearTimeout(volumeTimer);
      volumeTimer = null;
      volumeSent = -1;
      if (state.video) resetVideoToggle();
      vhub.emit('video:detach');
    }

    el.soundPlay.innerHTML = state.playing
      ? '<svg viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">' +
        '<rect x="5" y="3" width="4" height="14" rx="1"/>' +
        '<rect x="11" y="3" width="4" height="14" rx="1"/></svg>'
      : '<svg viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">' +
        '<path d="M5 3v14l12-7L5 3z"/></svg>';
    el.soundViz.classList.toggle('is-paused', !state.playing);

    if (!state.playing) {
      setTrackMeta(null, null);
      document.querySelectorAll('.vc-sound-result.is-playing').forEach(function (node) {
        node.classList.remove('is-playing');
      });
    }
  }

  function updateSourceLabel() {
    var label = vhub.el.soundSource.querySelector('span');
    if (!label) return;
    if (state.source === 'radio') label.textContent = 'Rádio FM';
    else if (state.source === 'search') label.textContent = 'Buscar';
    else label.textContent = 'Link';
  }

  function renderSource() {
    document.querySelectorAll('.vc-sound-tab').forEach(function (tab) {
      tab.classList.toggle('is-active', tab.dataset.source === state.source);
    });
    vhub.el.soundSearchRow.classList.toggle('hidden', state.source !== 'search');
    vhub.el.soundUrlRow.classList.toggle('hidden', state.source !== 'url');
    updateSourceLabel();
  }

  function renderStreamer(activeValue) {
    state.streamer = activeValue === true;
    vhub.el.soundStreamer.checked = state.streamer;
    vhub.el.soundStreamer.disabled = false;
    vhub.el.soundStreamer.setAttribute('aria-checked', state.streamer ? 'true' : 'false');
  }

  function renderEmpty(message) {
    var box = vhub.el.soundResults;
    box.replaceChildren();
    var item = document.createElement('li');
    item.className = 'vc-sound-results-empty';
    item.textContent = message;
    box.appendChild(item);
  }

  function renderResults(items) {
    state.results = Array.isArray(items) ? items : [];
    var box = vhub.el.soundResults;
    box.replaceChildren();

    state.results.forEach(function (item, index) {
      var row = document.createElement('li');
      var title = document.createElement('strong');
      var artist = document.createElement('span');
      row.className = 'vc-sound-result';
      row.dataset.index = String(index);
      title.textContent = item.title || 'Faixa';
      artist.textContent = item.artist || '—';
      row.appendChild(title);
      row.appendChild(artist);
      box.appendChild(row);
    });
  }


  // ============================================================
  // AÇÕES
  // ============================================================

  function pulse(button) {
    if (!button) return;
    if (pulseTarget) pulseTarget.style.transform = '';
    clearTimeout(pulseTimer);
    pulseTarget = button;
    button.style.transform = 'scale(0.88)';
    pulseTimer = setTimeout(function () {
      button.style.transform = '';
      pulseTarget = null;
      pulseTimer = null;
    }, 110);
  }

  function refreshVideoIfOn() {
    if (!state.video) return;
    clearTimeout(refreshTimer);
    refreshTimer = setTimeout(function () {
      refreshTimer = null;
      if (active && state.video) vhub.native.sound.video(true);
    }, 250);
  }

  function playTrack(item, row) {
    if (!item || !item.url) return;
    document.querySelectorAll('.vc-sound-result.is-playing').forEach(function (node) {
      node.classList.remove('is-playing');
    });
    if (row) row.classList.add('is-playing');
    setTrackMeta(item.title, item.artist);
    vhub.native.sound.play({
      url: item.url,
      volume: state.volume / 100,
      title: item.title || '',
    });
    setPlaying(true);
    refreshVideoIfOn();
  }

  function doSearch() {
    var query = vhub.el.soundSearchInput.value.trim();
    if (query.length < 2) {
      renderEmpty('Digite ao menos 2 letras.');
      return;
    }
    renderEmpty('Buscando…');
    vhub.native.sound.search(query);
    clearTimeout(searchTimeout);
    searchTimeout = setTimeout(function () {
      searchTimeout = null;
      if (active) renderEmpty('Sem resposta. Tente de novo.');
    }, 8000);
  }

  function stopPlayback() {
    vhub.native.sound.stop();
    setPlaying(false);
  }

  function togglePlay() {
    if (state.playing) {
      stopPlayback();
      return;
    }
    if (state.source === 'radio') {
      vhub.native.sound.radio(state.volume / 100);
      setPlaying(true);
      refreshVideoIfOn();
      return;
    }
    if (state.source === 'url') {
      var url = vhub.el.soundUrlInput.value.trim();
      if (!url) {
        pulse(vhub.el.soundUrlInput);
        return;
      }
      setTrackMeta('Tocando agora', 'Stream remoto');
      vhub.native.sound.play({
        url: url,
        volume: state.volume / 100,
        title: 'Link do carro',
      });
      setPlaying(true);
      refreshVideoIfOn();
      return;
    }
    pulse(vhub.el.soundSearchInput);
  }

  function syncStreamer() {
    var token = generation;
    vhub.native.sound.getStreamer().then(function (response) {
      return response ? response.json() : null;
    }).then(function (payload) {
      if (active && token === generation && payload && payload.ok === true && payload.data) {
        renderStreamer(payload.data.active === true);
      }
    }).catch(function () {});
  }

  function requestStreamer() {
    var requested = vhub.el.soundStreamer.checked === true;
    var token = generation;
    vhub.el.soundStreamer.disabled = true;
    vhub.native.sound.setStreamer(requested).then(function (response) {
      return response ? response.json() : null;
    }).then(function (payload) {
      if (!active || token !== generation) return;
      if (payload && payload.ok === true && payload.data) {
        renderStreamer(payload.data.active === true);
      } else {
        renderStreamer(!requested);
      }
    }).catch(function () {
      if (active && token === generation) renderStreamer(!requested);
    });
  }


  // ============================================================
  // LIFECYCLE
  // ============================================================

  vhub.createModule('sound', {
    root: '.vc-aside-sound',
    onInit: function () {
      busOffs.push(vhub.listen('sound:rejected', function () {
        setPlaying(false);
        var target = state.source === 'url' ? vhub.el.soundUrlInput
          : state.source === 'search' ? vhub.el.soundSearchInput : vhub.el.soundPlay;
        pulse(target);
      }));
      busOffs.push(vhub.listen('sound:results', function (payload) {
        clearTimeout(searchTimeout);
        searchTimeout = null;
        if (payload.items && payload.items.length) renderResults(payload.items);
        else renderEmpty('Nada encontrado.');
      }));
      busOffs.push(vhub.listen('sound:now', function (payload) {
        setTrackMeta(payload.title || '', payload.artist || '');
        if (!state.playing) setPlaying(true);
      }));
      busOffs.push(vhub.listen('sound:ended', function () { setPlaying(false); }));
      busOffs.push(vhub.listen('sound:streamer', function (payload) {
        renderStreamer(payload.active === true);
      }));
      busOffs.push(vhub.listen('sound:videoState', function (payload) {
        if (payload.enabled !== true) resetVideoToggle();
      }));
    },
    onMount: function () {
      var el = vhub.el;
      active = true;
      generation++;
      domOffs.push(vhub.bind(el.soundPlay, 'click', togglePlay));
      domOffs.push(vhub.bind(el.soundPrev, 'click', function () { pulse(el.soundPrev); }));
      domOffs.push(vhub.bind(el.soundNext, 'click', function () {
        if (state.source === 'radio') {
          vhub.native.sound.radio(state.volume / 100);
          setPlaying(true);
          refreshVideoIfOn();
        } else {
          pulse(el.soundNext);
        }
      }));
      document.querySelectorAll('.vc-sound-tab').forEach(function (tab) {
        domOffs.push(vhub.bind(tab, 'click', function () {
          if (state.playing) stopPlayback();
          state.source = tab.dataset.source;
          renderSource();
        }));
      });
      domOffs.push(vhub.bind(el.soundSearchInput, 'keydown', function (event) {
        if (event.key !== 'Enter') return;
        clearTimeout(searchTimer);
        doSearch();
      }));
      domOffs.push(vhub.bind(el.soundSearchInput, 'input', function () {
        clearTimeout(searchTimer);
        searchTimer = setTimeout(doSearch, 450);
      }));
      domOffs.push(vhub.bind(el.soundVolume, 'input', function () {
        state.volume = Number(el.soundVolume.value);
        el.soundVolumeVal.textContent = state.volume + '%';
        clearTimeout(volumeTimer);
        if (!state.playing) return;
        volumeTimer = setTimeout(function () {
          var value = state.volume / 100;
          if (active && state.playing && Math.abs(value - volumeSent) >= 0.01) {
            volumeSent = value;
            vhub.native.sound.volume(value);
          }
        }, 100);
      }));
      domOffs.push(vhub.bind(el.soundVideo, 'click', function () {
        state.video = !state.video;
        el.soundVideo.setAttribute('aria-pressed', state.video ? 'true' : 'false');
        el.soundVideo.classList.toggle('is-on', state.video);
        vhub.native.sound.video(state.video);
      }));
      domOffs.push(vhub.bind(el.soundStreamer, 'change', requestStreamer));
      domOffs.push(vhub.bind(el.soundResults, 'click', function (event) {
        var row = event.target.closest('.vc-sound-result');
        if (!row || !el.soundResults.contains(row)) return;
        playTrack(state.results[Number(row.dataset.index)], row);
      }));
    },
    onShow: function () {
      vhub.el.soundVolume.value = state.volume;
      vhub.el.soundVolumeVal.textContent = state.volume + '%';
      renderSource();
      renderStreamer(state.streamer);
      setPlaying(state.playing);
      if (state.playing) setTrackMeta(state.title, state.artist);
      syncStreamer();
    },
    onHide: function () { vhub.el.soundViz.classList.add('is-paused'); },
    onDestroy: function () {
      active = false;
      generation++;
      [searchTimer, searchTimeout, volumeTimer, refreshTimer, pulseTimer].forEach(clearTimeout);
      searchTimer = null;
      searchTimeout = null;
      volumeTimer = null;
      refreshTimer = null;
      pulseTimer = null;
      if (pulseTarget) pulseTarget.style.transform = '';
      pulseTarget = null;
      volumeSent = -1;
      vhub.el.soundStreamer.disabled = false;
      while (domOffs.length) domOffs.pop()();
      while (busOffs.length) busOffs.pop()();
    },
  });
})();
