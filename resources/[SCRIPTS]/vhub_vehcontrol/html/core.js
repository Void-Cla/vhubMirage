// core.js — runtime mínimo da NUI do controle veicular

(function (global) {
  'use strict';

  var vhub = global.vhub = global.vhub || {};
  var modules = Object.create(null);
  var mounted = Object.create(null);
  var stores = Object.create(null);
  var listeners = Object.create(null);
  var pendingMounts = [];
  var domReady = false;
  var resourceUrl = null;

  vhub.el = {};


  // ============================================================
  // RUNTIME
  // ============================================================

  // Registra um módulo com lifecycle determinístico.
  vhub.createModule = function (name, spec) {
    if (typeof name !== 'string' || !name || !spec || modules[name]) return false;
    modules[name] = spec;
    return true;
  };

  function restoreModuleRoot(name, spec) {
    if (!spec.root || document.querySelector(spec.root)) return true;

    var anchor = document.getElementById('vhub-anchor-' + name);
    if (!anchor || !anchor.parentNode || !spec.rootMarkup) return false;

    var template = document.createElement('template');
    template.innerHTML = spec.rootMarkup.trim();
    var root = template.content.firstElementChild;
    if (!root) return false;

    anchor.parentNode.insertBefore(root, anchor.nextSibling);
    cacheDom();
    return true;
  }

  function releaseDomReferences(root) {
    Object.keys(vhub.el).forEach(function (key) {
      var reference = vhub.el[key];
      if (reference === root || (reference && root.contains(reference))) delete vhub.el[key];
    });
  }

  function removeModuleRoot(name, spec) {
    if (!spec.root) return;

    var root = document.querySelector(spec.root);
    if (!root || !root.parentNode) return;

    var anchorId = 'vhub-anchor-' + name;
    var anchor = document.getElementById(anchorId);
    if (!anchor) {
      anchor = document.createElement('template');
      anchor.id = anchorId;
      root.parentNode.insertBefore(anchor, root);
    }

    spec.rootMarkup = root.outerHTML;
    releaseDomReferences(root);
    root.remove();
  }

  // Monta um módulo registrado quando o DOM estiver pronto.
  vhub.mount = function (name) {
    if (!domReady) {
      if (pendingMounts.indexOf(name) === -1) pendingMounts.push(name);
      return false;
    }

    var spec = modules[name];
    if (!spec || mounted[name]) return false;
    if (!restoreModuleRoot(name, spec)) return false;

    if (typeof spec.onInit === 'function') spec.onInit();
    mounted[name] = true;
    if (typeof spec.onMount === 'function') spec.onMount();
    if (typeof spec.onShow === 'function') spec.onShow();
    return true;
  };

  // Desmonta um módulo e executa todo o cleanup declarado.
  vhub.unmount = function (name) {
    var pendingIndex = pendingMounts.indexOf(name);
    if (pendingIndex !== -1) pendingMounts.splice(pendingIndex, 1);

    var spec = modules[name];
    if (!spec || !mounted[name]) return false;

    try {
      if (typeof spec.onHide === 'function') spec.onHide();
    } catch (error) {
      console.error('[vhub] onHide falhou:', error);
    }
    try {
      if (typeof spec.onDestroy === 'function') spec.onDestroy();
    } catch (error) {
      console.error('[vhub] onDestroy falhou:', error);
    }
    removeModuleRoot(name, spec);
    delete mounted[name];
    return true;
  };

  // Publica um evento interno sem acoplamento direto entre módulos.
  vhub.emit = function (eventName, payload) {
    var handlers = listeners[eventName];
    if (!handlers) return;
    handlers.slice().forEach(function (handler) {
      try { handler(payload); } catch (error) { console.error('[vhub] evento falhou:', error); }
    });
  };

  // Registra um listener interno e retorna seu destrutor idempotente.
  vhub.listen = function (eventName, handler) {
    if (typeof handler !== 'function') return function () {};
    var handlers = listeners[eventName] = listeners[eventName] || [];
    handlers.push(handler);
    var active = true;

    return function () {
      if (!active) return;
      active = false;
      var index = handlers.indexOf(handler);
      if (index !== -1) handlers.splice(index, 1);
      if (handlers.length === 0) delete listeners[eventName];
    };
  };

  // Retorna a fatia única de estado do domínio informado.
  vhub.store = function (domain) {
    if (!stores[domain]) stores[domain] = {};
    return stores[domain];
  };

  // Registra um listener DOM e retorna seu destrutor.
  vhub.bind = function (target, eventName, handler, options) {
    if (!target || typeof target.addEventListener !== 'function') return function () {};
    target.addEventListener(eventName, handler, options);
    return function () { target.removeEventListener(eventName, handler, options); };
  };


  // ============================================================
  // NATIVE BRIDGE
  // ============================================================

  function request(endpoint, payload) {
    if (!resourceUrl) resourceUrl = 'https://' + GetParentResourceName() + '/';
    return fetch(resourceUrl + endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload || {}),
    }).catch(function () { return null; });
  }

  vhub.native = {
    ui: {
      exit: function () { return request('exit'); },
    },
    vehicle: {
      emergency: function () { return request('emergency'); },
      engine: function () { return request('engine'); },
      lock: function () { return request('lock'); },
      lights: function () { return request('lights'); },
      light: function () { return request('light'); },
      seat: function () { return request('seat'); },
      door: function (door) { return request('door', { door: door }); },
      window: function (windowName) { return request('window', { window: windowName }); },
    },
    sheet: {
      recalibrate: function (alloc) { return request('recalibrate', { alloc: alloc }); },
    },
    nitro: {
      toggle: function (on) { return request('nitroToggle', { on: on }); },
      level: function (level) { return request('nitroLevel', { level: level }); },
      charge: function () { return request('nitroCharge'); },
    },
    sound: {
      stop: function () { return request('soundStop'); },
      search: function (query) { return request('soundSearch', { query: query }); },
      volume: function (volume) { return request('soundVolume', { volume: volume }); },
      video: function (show) { return request('soundVideo', { show: show }); },
      videoOff: function () { return request('soundVideoOff'); },
      play: function (data) { return request('soundPlay', data); },
      radio: function (volume) { return request('soundRadio', { volume: volume }); },
      setStreamer: function (active) { return request('soundStreamer', { active: active }); },
      getStreamer: function () { return request('soundStreamerGet'); },
    },
  };


  // ============================================================
  // DOM
  // ============================================================

  function cacheDom() {
    var el = vhub.el;
    el.panel = document.getElementById('vc-panel');
    el.btnClose = document.getElementById('btn-close');
    el.btnEmergency = document.getElementById('btn-emergency');
    el.btnEngine = document.getElementById('btn-engine');
    el.btnLock = document.getElementById('btn-lock');
    el.btnLights = document.getElementById('btn-lights');
    el.btnLight = document.getElementById('btn-light');
    el.fuelBar = document.getElementById('fuel-bar');
    el.fuelPct = document.getElementById('fuel-pct');
    el.fichaEmpty = document.getElementById('ficha-empty');
    el.fichaBody = document.getElementById('ficha-body');
    el.fichaTier = document.getElementById('ficha-tier');
    el.fichaScore = document.getElementById('ficha-score');
    el.fichaTierB = document.getElementById('ficha-tierbase');
    el.fichaTierM = document.getElementById('ficha-tiermax');
    el.fichaUsed = document.getElementById('ficha-used');
    el.fichaBudget = document.getElementById('ficha-budget');
    el.fichaBudgetRow = document.querySelector('.vc-ficha-budget');
    el.fichaBudgetLbl = document.getElementById('ficha-budget-label');
    el.fichaAlloc = document.getElementById('ficha-alloc');
    el.fichaAffin = document.getElementById('ficha-affinity');
    el.fichaAffinWrap = document.getElementById('ficha-affinity-wrap');
    el.btnFichaEdit = document.getElementById('btn-ficha-edit');
    el.fichaEditFtr = document.getElementById('ficha-editftr');
    el.btnFichaSave = document.getElementById('btn-ficha-save');
    el.btnFichaCancel = document.getElementById('btn-ficha-cancel');
    el.nitroWrap = document.getElementById('ficha-nitro-wrap');
    el.nitroNoKit = document.getElementById('nitro-nokit');
    el.nitroBody = document.getElementById('nitro-body');
    el.nitroToggle = document.getElementById('nitro-toggle');
    el.nitroToggleLbl = document.getElementById('nitro-toggle-lbl');
    el.nitroQty = document.getElementById('nitro-qty');
    el.nitroLevel = document.getElementById('nitro-level');
    el.nitroLevelVal = document.getElementById('nitro-level-val');
    el.nitroCharge = document.getElementById('nitro-charge');
    el.soundTitle = document.getElementById('sound-title');
    el.soundArtist = document.getElementById('sound-artist');
    el.soundSource = document.getElementById('sound-source');
    el.soundViz = document.getElementById('sound-viz');
    el.soundPlay = document.getElementById('sound-play');
    el.soundPrev = document.getElementById('sound-prev');
    el.soundNext = document.getElementById('sound-next');
    el.soundVolume = document.getElementById('sound-volume');
    el.soundVolumeVal = document.getElementById('sound-volume-val');
    el.soundUrlRow = document.getElementById('sound-url-row');
    el.soundUrlInput = document.getElementById('sound-url-input');
    el.soundSearchRow = document.getElementById('sound-search-row');
    el.soundSearchInput = document.getElementById('sound-search-input');
    el.soundResults = document.getElementById('sound-results');
    el.soundVideo = document.getElementById('sound-video');
    el.soundStreamer = document.getElementById('sound-streamer');
    el.dvd = document.getElementById('vc-dvd');
    el.dvdFrame = document.getElementById('vc-dvd-frame');
    el.dvdTitle = document.getElementById('vc-dvd-title');
    el.dvdClose = document.getElementById('vc-dvd-close');
  }

  function bootDom() {
    cacheDom();
    domReady = true;
    pendingMounts.splice(0).forEach(vhub.mount);
  }


  // ============================================================
  // SHELL
  // ============================================================

  var shellOffs = [];
  var dragOffs = [];
  var uiState = vhub.store('ui');

  function drain(offs) {
    while (offs.length) offs.pop()();
  }

  function switchTab(name) {
    document.querySelectorAll('.vc-tab').forEach(function (tab) {
      tab.classList.toggle('is-active', tab.dataset.tab === name);
    });
  }

  function showPanel(editTab) {
    vhub.el.panel.classList.remove('hidden');
    switchTab(editTab ? 'ficha' : 'controls');
  }

  function hidePanel() {
    if (vhub.el.panel) vhub.el.panel.classList.add('hidden');
  }

  function wireDrag(root, handle) {
    var dragging = false;
    var startX = 0;
    var startY = 0;
    var origX = 0;
    var origY = 0;

    dragOffs.push(vhub.bind(handle, 'mousedown', function (event) {
      if (event.target.closest('button') || event.button !== 0) return;
      var rect = root.getBoundingClientRect();
      root.style.left = rect.left + 'px';
      root.style.top = rect.top + 'px';
      root.style.right = 'auto';
      root.style.bottom = 'auto';
      root.style.transform = 'none';
      origX = rect.left;
      origY = rect.top;
      startX = event.clientX;
      startY = event.clientY;
      dragging = true;
      root.classList.add('is-dragging');
      event.preventDefault();
    }));

    dragOffs.push(vhub.bind(document, 'mousemove', function (event) {
      if (!dragging) return;
      var maxX = global.innerWidth - root.offsetWidth - 4;
      var maxY = global.innerHeight - root.offsetHeight - 4;
      root.style.left = Math.max(4, Math.min(maxX, origX + event.clientX - startX)) + 'px';
      root.style.top = Math.max(4, Math.min(maxY, origY + event.clientY - startY)) + 'px';
    }));

    dragOffs.push(vhub.bind(document, 'mouseup', function () {
      if (!dragging) return;
      dragging = false;
      root.classList.remove('is-dragging');
    }));
  }

  function attachDrag() {
    document.querySelectorAll('[data-drag-root]').forEach(function (root) {
      var handle = root.querySelector('[data-drag-handle]');
      if (handle) wireDrag(root, handle);
    });
  }

  vhub.createModule('shell', {
    onInit: function () {
      shellOffs.push(vhub.listen('ui:status', function (payload) {
        if (payload.status) showPanel(payload.editTab === true);
      }));
    },
    onMount: function () {
      shellOffs.push(vhub.bind(document, 'keydown', function (event) {
        if (event.key === 'Escape') vhub.native.ui.exit();
      }));
      shellOffs.push(vhub.bind(vhub.el.btnClose, 'click', vhub.native.ui.exit));
      document.querySelectorAll('.vc-tab').forEach(function (tab) {
        shellOffs.push(vhub.bind(tab, 'click', function () { switchTab(tab.dataset.tab); }));
      });
      attachDrag();
    },
    onShow: function () { showPanel(uiState.editTab === true); },
    onHide: hidePanel,
    onDestroy: function () {
      drain(dragOffs);
      drain(shellOffs);
      document.querySelectorAll('.is-dragging').forEach(function (node) {
        node.classList.remove('is-dragging');
      });
    },
  });


  // ============================================================
  // MENSAGENS NUI
  // ============================================================

  var moduleNames = ['controls', 'ficha', 'sound', 'video', 'shell'];

  function mountAll() {
    moduleNames.forEach(vhub.mount);
  }

  function unmountAll() {
    moduleNames.slice().reverse().forEach(vhub.unmount);
  }

  function dispatchMessage(event) {
    var message = event.data;
    if (!message || typeof message.type !== 'string') return;
    var data = message.data || {};

    if (message.type === 'ui') {
      uiState.status = data.status === true;
      uiState.editTab = data.edit_tab === true;
      if (uiState.status) mountAll();
      vhub.emit('ui:status', { status: uiState.status, editTab: uiState.editTab });
      if (!uiState.status) unmountAll();
      return;
    }

    var soundState = vhub.store('sound');
    var sheetState = vhub.store('sheet');
    if (message.type === 'soundNow') {
      soundState.playing = true;
      soundState.title = data.title || '';
      soundState.artist = data.artist || '';
    } else if (message.type === 'soundEnded' || message.type === 'soundRejected') {
      soundState.playing = false;
      soundState.video = false;
    } else if (message.type === 'soundStreamer') {
      soundState.streamer = data.active === true;
    } else if (message.type === 'soundVideoDetach') {
      soundState.video = false;
    } else if (message.type === 'sheet') {
      sheetState.sheet = data.sheet || null;
    } else if (message.type === 'recalDone' && data.ok === true && data.sheet) {
      sheetState.sheet = data.sheet;
    } else if (message.type === 'nitroDone' && sheetState.sheet && data.nitro) {
      sheetState.sheet.nitro = data.nitro;
    }

    var eventMap = {
      updateFuel: 'vehicle:fuel',
      emergency: 'vehicle:emergency',
      sheet: 'sheet:update',
      recalDone: 'sheet:recalDone',
      nitroDone: 'sheet:nitroDone',
      soundRejected: 'sound:rejected',
      soundResults: 'sound:results',
      soundNow: 'sound:now',
      soundEnded: 'sound:ended',
      soundVideoAttach: 'video:attach',
      soundVideoDetach: 'video:detach',
      soundStreamer: 'sound:streamer',
    };

    if (eventMap[message.type]) vhub.emit(eventMap[message.type], data);
  }

  global.addEventListener('message', dispatchMessage);
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', bootDom, { once: true });
  } else {
    bootDom();
  }
})(window);
