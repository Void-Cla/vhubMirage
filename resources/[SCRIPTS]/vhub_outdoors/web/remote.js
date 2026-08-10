(function () {
  'use strict';

  var state = {
    open: false,
    pending: null,
    timer: null,
    root: null,
    form: null,
    title: null,
    meta: null,
    url: null,
    volume: null,
    volumeText: null,
    status: null,
    channel: null,
    move: null,
    close: null,
  };

  function post(endpoint, payload) {
    return fetch('https://' + GetParentResourceName() + '/' + endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload || {}),
    }).then(function (response) { return response.json(); });
  }

  function setPending(action) {
    window.clearTimeout(state.timer);
    state.pending = action || null;
    state.channel.disabled = state.pending !== null;
    state.move.disabled = state.pending !== null;
    if (state.pending) {
      state.timer = window.setTimeout(function () {
        setPending(null);
        state.status.textContent = 'Tempo limite da operacao.';
      }, 12000);
    } else {
      state.timer = null;
    }
  }

  function applyItem(item) {
    if (!item || typeof item !== 'object') return;
    state.title.textContent = String(item.title || 'Outdoor');
    state.meta.textContent = '#' + String(item.id) + ' | ' + String(item.size || '');
    state.url.value = String(item.url || '');
    state.volume.value = String(Number(item.volume) || 0);
    state.volumeText.textContent = state.volume.value + '%';
  }

  function show(data) {
    applyItem(data);
    state.status.textContent = '';
    setPending(null);
    state.root.hidden = false;
    state.open = true;
    window.setTimeout(function () { state.url.focus(); }, 0);
  }

  function hide() {
    state.open = false;
    state.root.hidden = true;
    state.form.reset();
    state.status.textContent = '';
    setPending(null);
  }

  function requestClose() {
    if (!state.open) return;
    post('remoteClose', {}).catch(function () {
      state.status.textContent = 'Falha de comunicacao.';
    });
  }

  function onSubmit(event) {
    event.preventDefault();
    if (!state.open || state.pending) return;
    setPending('media');
    state.status.textContent = 'Validando midia...';
    post('remoteSetMedia', { url: state.url.value.trim() }).then(function (response) {
      if (response && response.ok) return;
      setPending(null);
      state.status.textContent = 'URL invalida.';
    }).catch(function () {
      setPending(null);
      state.status.textContent = 'Falha de comunicacao.';
    });
  }

  function onVolumeInput() {
    state.volumeText.textContent = state.volume.value + '%';
  }

  function onVolumeChange() {
    if (!state.open || state.pending) return;
    setPending('volume');
    state.status.textContent = 'Salvando volume...';
    post('remoteSetVolume', { volume: Number(state.volume.value) }).then(function (response) {
      if (response && response.ok) return;
      setPending(null);
      state.status.textContent = 'Volume recusado.';
    }).catch(function () {
      setPending(null);
      state.status.textContent = 'Falha de comunicacao.';
    });
  }

  function onMove() {
    if (!state.open || state.pending) return;
    setPending('move');
    post('remoteMove', {}).catch(function () {
      setPending(null);
      state.status.textContent = 'Falha de comunicacao.';
    });
  }

  function onMessage(event) {
    var message = event.data;
    if (!message || typeof message !== 'object'
        || typeof message.type !== 'string'
        || !message.data || typeof message.data !== 'object') return;
    if (message.type === 'remote:open') show(message.data);
    else if (message.type === 'remote:close') hide();
    else if (message.type === 'remote:update' && state.open) {
      setPending(null);
      if (message.data.ok) {
        applyItem(message.data.item);
        state.status.textContent = message.data.action === 'media'
          ? 'Canal atualizado.'
          : 'Volume atualizado.';
      } else {
        state.status.textContent = message.data.err === 'remote_media_rejected'
          ? 'Arquivo remoto recusado.'
          : 'Operacao recusada.';
      }
    }
  }

  function onKeydown(event) {
    if (state.open && event.key === 'Escape') requestClose();
  }

  function mount() {
    state.root = document.getElementById('remote');
    state.form = document.getElementById('remote-form');
    state.title = document.getElementById('remote-title');
    state.meta = document.getElementById('remote-meta');
    state.url = document.getElementById('remote-url');
    state.volume = document.getElementById('remote-volume');
    state.volumeText = document.getElementById('remote-volume-text');
    state.status = document.getElementById('remote-status');
    state.channel = document.getElementById('remote-channel');
    state.move = document.getElementById('remote-move');
    state.close = document.getElementById('remote-close');
    state.form.addEventListener('submit', onSubmit);
    state.volume.addEventListener('input', onVolumeInput);
    state.volume.addEventListener('change', onVolumeChange);
    state.move.addEventListener('click', onMove);
    state.close.addEventListener('click', requestClose);
    document.addEventListener('keydown', onKeydown);
    window.addEventListener('message', onMessage);
    window.addEventListener('beforeunload', destroy);
  }

  function destroy() {
    window.clearTimeout(state.timer);
    state.form.removeEventListener('submit', onSubmit);
    state.volume.removeEventListener('input', onVolumeInput);
    state.volume.removeEventListener('change', onVolumeChange);
    state.move.removeEventListener('click', onMove);
    state.close.removeEventListener('click', requestClose);
    document.removeEventListener('keydown', onKeydown);
    window.removeEventListener('message', onMessage);
    window.removeEventListener('beforeunload', destroy);
  }

  mount();
})();
