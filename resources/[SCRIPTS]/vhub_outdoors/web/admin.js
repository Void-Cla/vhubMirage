(function () {
  'use strict';

  var state = {
    mounted: false,
    open: false,
    pending: false,
    root: null,
    form: null,
    sizes: null,
    url: null,
    error: null,
    submit: null,
    close: null,
    items: null,
    count: null,
    empty: null,
    confirmId: null,
    confirmTimer: null,
    removingId: null,
    removeTimer: null,
  };

  function post(endpoint, payload) {
    return fetch('https://' + GetParentResourceName() + '/' + endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload || {}),
    }).then(function (response) { return response.json(); });
  }

  function errorMessage(code) {
    if (code === 'invalid_size') return 'Escolha um tamanho.';
    if (code === 'invalid_media') {
      return 'Use Discord CDN, Imgur direto ou YouTube, sem sinais ao redor.';
    }
    return 'Não foi possível iniciar o posicionamento.';
  }

  function setPending(value) {
    state.pending = value === true;
    state.submit.disabled = state.pending;
    state.submit.textContent = state.pending ? 'Validando...' : 'Criar e posicionar';
  }

  function clearRemoveState() {
    window.clearTimeout(state.confirmTimer);
    window.clearTimeout(state.removeTimer);
    state.confirmTimer = null;
    state.removeTimer = null;
    state.confirmId = null;
    state.removingId = null;
  }

  function renderItems(items) {
    clearRemoveState();
    state.items.replaceChildren();
    items = Array.isArray(items) ? items : [];
    items.forEach(function (item) {
      if (!item || !Number.isInteger(Number(item.id))) return;
      var row = document.createElement('div');
      var copy = document.createElement('div');
      var name = document.createElement('span');
      var meta = document.createElement('span');
      var remove = document.createElement('button');
      row.className = 'active-row';
      copy.className = 'active-copy';
      name.className = 'active-name';
      meta.className = 'active-meta';
      remove.className = 'remove';
      remove.type = 'button';
      remove.dataset.id = String(item.id);
      remove.textContent = 'Remover';
      name.textContent = '#' + item.id + ' | ' + String(item.title || 'Sem titulo');
      meta.textContent = String(item.size_label || 'personalizado') +
        ' | ' + String(item.media_type || 'midia');
      copy.append(name, meta);
      row.append(copy, remove);
      state.items.appendChild(row);
    });
    var total = state.items.children.length;
    state.count.textContent = String(total);
    state.empty.hidden = total > 0;
  }

  function renderSizes(sizes) {
    state.sizes.replaceChildren();
    (Array.isArray(sizes) ? sizes : []).forEach(function (size) {
      var option = document.createElement('div');
      var input = document.createElement('input');
      var label = document.createElement('label');
      var name = document.createElement('span');
      var measure = document.createElement('span');
      var hint = document.createElement('span');
      option.className = 'size-option';
      input.type = 'radio';
      input.name = 'size';
      input.id = 'size-' + size.id;
      input.value = size.id;
      label.htmlFor = input.id;
      name.className = 'size-name';
      measure.className = 'size-measure';
      hint.className = 'size-hint';
      name.textContent = size.label;
      measure.textContent =
        Number(size.width).toFixed(2) + ' × ' + Number(size.height).toFixed(2) + ' m';
      hint.textContent = size.hint;
      label.append(name, measure, hint);
      option.append(input, label);
      state.sizes.appendChild(option);
    });
  }

  function onShow(data) {
    renderSizes(data.sizes);
    renderItems(data.items);
    state.form.reset();
    state.error.textContent = '';
    setPending(false);
    state.root.hidden = false;
    state.open = true;
    window.setTimeout(function () { state.url.focus(); }, 0);
  }

  function onHide() {
    state.open = false;
    state.root.hidden = true;
    state.form.reset();
    state.error.textContent = '';
    setPending(false);
    renderItems([]);
  }

  function requestClose() {
    if (!state.open) return;
    post('creatorClose', {}).catch(function () {
      state.error.textContent = 'Falha de comunicação com o jogo.';
    });
  }

  function onSubmit(event) {
    event.preventDefault();
    if (!state.open || state.pending) return;
    var selected = state.form.querySelector('input[name="size"]:checked');
    if (!selected) {
      state.error.textContent = 'Escolha um tamanho.';
      return;
    }
    setPending(true);
    post('creatorSubmit', {
      size: selected.value,
      url: state.url.value.trim(),
    }).then(function (response) {
      if (response && response.ok) return;
      state.error.textContent = errorMessage(response && response.err);
      setPending(false);
    }).catch(function () {
      state.error.textContent = 'Falha de comunicação com o jogo.';
      setPending(false);
    });
  }

  function resetRemoveButton() {
    window.clearTimeout(state.confirmTimer);
    var button = state.items.querySelector('.remove.confirming');
    if (button) {
      button.classList.remove('confirming');
      button.textContent = 'Remover';
    }
    state.confirmId = null;
    state.confirmTimer = null;
  }

  function recoverRemove(message) {
    window.clearTimeout(state.removeTimer);
    state.removeTimer = null;
    state.removingId = null;
    var button = state.items.querySelector('.remove:disabled');
    if (button) {
      button.disabled = false;
      button.textContent = 'Remover';
    }
    state.error.textContent = message;
  }

  function onRemove(event) {
    var button = event.target.closest('.remove');
    if (!button || !state.items.contains(button) || state.removingId !== null) return;
    var id = Number(button.dataset.id);
    if (!Number.isInteger(id) || id < 1) return;

    if (state.confirmId !== id) {
      resetRemoveButton();
      state.confirmId = id;
      button.classList.add('confirming');
      button.textContent = 'Confirmar';
      state.confirmTimer = window.setTimeout(resetRemoveButton, 3000);
      return;
    }

    window.clearTimeout(state.confirmTimer);
    state.confirmTimer = null;
    state.confirmId = null;
    state.removingId = id;
    button.disabled = true;
    button.textContent = 'Removendo...';
    state.error.textContent = '';
    state.removeTimer = window.setTimeout(function () {
      recoverRemove('Tempo limite ao remover.');
    }, 10000);
    post('creatorRemove', { id: id }).then(function (response) {
      if (response && response.ok) return;
      recoverRemove('Falha ao solicitar remocao.');
    }).catch(function () {
      recoverRemove('Falha de comunicacao com o jogo.');
    });
  }

  function onKeydown(event) {
    if (state.open && event.key === 'Escape') requestClose();
  }

  function onMessage(event) {
    var message = event.data;
    if (!message || typeof message !== 'object'
        || typeof message.type !== 'string'
        || !message.data || typeof message.data !== 'object') return;
    var data = message.data;
    if (message.type === 'creator:open') onShow(data);
    else if (message.type === 'creator:close') onHide();
    else if (message.type === 'creator:items') {
      renderItems(data.items);
      if (data.ok === false) state.error.textContent = 'Falha ao remover o outdoor.';
      else if (data.ok === true) state.error.textContent = '';
    }
  }

  function onDestroy() {
    if (!state.mounted) return;
    window.removeEventListener('message', onMessage);
    window.removeEventListener('beforeunload', onDestroy);
    document.removeEventListener('keydown', onKeydown);
    state.form.removeEventListener('submit', onSubmit);
    state.close.removeEventListener('click', requestClose);
    state.items.removeEventListener('click', onRemove);
    clearRemoveState();
    state.mounted = false;
  }

  function onMount() {
    state.root = document.getElementById('creator');
    state.form = document.getElementById('creator-form');
    state.sizes = document.getElementById('sizes');
    state.url = document.getElementById('media-url');
    state.error = document.getElementById('error');
    state.submit = document.getElementById('submit');
    state.close = document.getElementById('close');
    state.items = document.getElementById('active-items');
    state.count = document.getElementById('active-count');
    state.empty = document.getElementById('active-empty');
    state.form.addEventListener('submit', onSubmit);
    state.close.addEventListener('click', requestClose);
    state.items.addEventListener('click', onRemove);
    document.addEventListener('keydown', onKeydown);
    window.addEventListener('message', onMessage);
    window.addEventListener('beforeunload', onDestroy);
    state.mounted = true;
  }

  onMount();
})();
