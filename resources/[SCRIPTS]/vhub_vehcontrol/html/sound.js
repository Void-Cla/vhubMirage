// sound.js — aside TOPO-CENTRO (Som)
// Fontes: "Buscar" (Jamendo via vhub_wow), "Rádio" (top-semana aleatório) e "URL"
// (arquivo direto). Tudo passa pelo Lua → servidor valida e dispara via vhub_wow (#34).


vhub.ready(function (el) {
  attachSoundUI();
  updateSourceLabel(_sound.source);
  setPlaying(false);
});


// ============================================================
// ESTADO LOCAL — sem persistência; verdade de playback é server-side
// ============================================================

var _sound = {
  playing: false,
  source:  'search',
  volume:  55,
};

var _searchTimer = null;   // debounce da digitação na busca
var _searchTO    = null;   // timeout de segurança (evita "Buscando…" infinito)


// ============================================================
// LIFECYCLE / BIND
// ============================================================

function attachSoundUI() {
  var el = vhub.el;

  // Play / Pause — comportamento depende da fonte ativa
  el.soundPlay.addEventListener('click', function () {
    if (_sound.source === 'url')        togglePlayUrl();
    else if (_sound.source === 'radio') togglePlayRadio();
    else                                togglePlaySearch();
  });

  // Prev / Next
  el.soundPrev.addEventListener('click', function () { pulseBtn(el.soundPrev); });
  el.soundNext.addEventListener('click', function () {
    if (_sound.source === 'radio') playRadio();   // próxima faixa aleatória
    else pulseBtn(el.soundNext);
  });

  // Fonte (Rádio / Buscar / URL)
  document.querySelectorAll('.vc-sound-tab').forEach(function (tab) {
    tab.addEventListener('click', function () {
      document.querySelectorAll('.vc-sound-tab').forEach(function (t) {
        t.classList.remove('is-active');
      });
      tab.classList.add('is-active');

      // troca de fonte com som tocando: para o stream anterior
      if (_sound.playing) { post('soundStop', {}); setPlaying(false); }

      _sound.source = tab.dataset.source;
      el.soundSearchRow.classList.toggle('hidden', _sound.source !== 'search');
      el.soundUrlRow.classList.toggle('hidden', _sound.source !== 'url');
      updateSourceLabel(_sound.source);
    });
  });

  // Busca: Enter dispara já; digitação dispara com debounce (controla chamadas)
  el.soundSearchInput.addEventListener('keydown', function (e) {
    if (e.key === 'Enter') { clearTimeout(_searchTimer); doSearch(); }
  });
  el.soundSearchInput.addEventListener('input', function () {
    clearTimeout(_searchTimer);
    _searchTimer = setTimeout(doSearch, 450);
  });

  // Volume
  el.soundVolume.addEventListener('input', function () {
    _sound.volume = Number(el.soundVolume.value);
    el.soundVolumeVal.textContent = _sound.volume + '%';
    if (_sound.playing) post('soundVolume', { volume: _sound.volume / 100 });
  });
}


// ============================================================
// BUSCA (Jamendo) — pesquisa, render da lista, play do resultado
// ============================================================

function doSearch() {
  var q = vhub.el.soundSearchInput.value.trim();
  if (q.length < 2) { renderEmpty('Digite ao menos 2 letras.'); return; }

  renderEmpty('Buscando…');
  post('soundSearch', { query: q });

  // se nada voltar em 8s, sai do estado "Buscando…" (ex.: vhub_wow fora do ar)
  clearTimeout(_searchTO);
  _searchTO = setTimeout(function () {
    renderEmpty('Sem resposta. Tente de novo.');
  }, 8000);
}

// recebe a lista do servidor (via core.js → onSoundResults)
function onSoundResults(items) {
  clearTimeout(_searchTO);
  if (!items || !items.length) { renderEmpty('Nada encontrado.'); return; }
  renderResults(items);
}

function renderEmpty(msg) {
  var box = vhub.el.soundResults;
  box.innerHTML = '';
  var li = document.createElement('li');
  li.className = 'vc-sound-results-empty';
  li.textContent = msg;                       // textContent: anti-XSS
  box.appendChild(li);
}

function renderResults(items) {
  var box = vhub.el.soundResults;
  box.innerHTML = '';

  items.forEach(function (it) {
    var li = document.createElement('li');
    li.className = 'vc-sound-result';

    var t = document.createElement('strong');
    t.textContent = it.title || 'Faixa';      // dados da API → textContent (nunca innerHTML)
    var a = document.createElement('span');
    a.textContent = it.artist || '—';

    li.appendChild(t);
    li.appendChild(a);
    li.addEventListener('click', function () { playTrack(it, li); });
    box.appendChild(li);
  });
}

// toca a faixa escolhida: header local + manda o servidor disparar (que revalida a URL)
function playTrack(it, li) {
  if (!it || !it.url) return;

  document.querySelectorAll('.vc-sound-result.is-playing').forEach(function (n) {
    n.classList.remove('is-playing');
  });
  if (li) li.classList.add('is-playing');

  setTrackMeta(it.title, it.artist);
  post('soundPlay', { url: it.url, volume: _sound.volume / 100 });
  setPlaying(true);
}

function togglePlaySearch() {
  if (_sound.playing) { post('soundStop', {}); setPlaying(false); return; }
  pulseBtn(vhub.el.soundSearchInput);   // sem faixa ativa: escolha um resultado
}


// ============================================================
// RÁDIO (top-semana aleatório) — o servidor escolhe a faixa
// ============================================================

function togglePlayRadio() {
  if (_sound.playing) { post('soundStop', {}); setPlaying(false); return; }
  playRadio();
}

function playRadio() {
  post('soundRadio', { volume: _sound.volume / 100 });
  setPlaying(true);   // confirmação real chega em onSoundNow / onSoundRejected
}

// servidor informa a faixa que entrou no ar (rádio)
function onSoundNow(title, artist) {
  setTrackMeta(title, artist);
  if (!_sound.playing) setPlaying(true);
}


// ============================================================
// URL (arquivo direto) — play/stop real via Lua → vhub_wow
// ============================================================

function togglePlayUrl() {
  var el = vhub.el;
  if (_sound.playing) { post('soundStop', {}); setPlaying(false); return; }

  var url = el.soundUrlInput.value.trim();
  if (!url) { pulseBtn(el.soundUrlInput); return; }

  setTrackMeta('Tocando agora', 'Stream remoto');
  post('soundPlay', { url: url, volume: _sound.volume / 100 });
  setPlaying(true);
}

function onSoundRejected() {
  setPlaying(false);
  var el = vhub.el;
  var target = _sound.source === 'url'    ? el.soundUrlInput
             : _sound.source === 'search' ? el.soundSearchInput
             :                              el.soundPlay;
  pulseBtn(target);
}


// ============================================================
// HEADER / VISUAL
// ============================================================

function setTrackMeta(title, artist) {
  vhub.el.soundTitle.textContent  = title  || 'Nenhuma faixa';
  vhub.el.soundArtist.textContent = artist || '— · —';
}

function setPlaying(on) {
  var el = vhub.el;
  _sound.playing = on;

  // alterna ícone do botão play (svg interno)
  el.soundPlay.innerHTML = on
    ? '<svg viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">' +
      '<rect x="5" y="3" width="4" height="14" rx="1"/>' +
      '<rect x="11" y="3" width="4" height="14" rx="1"/>' +
      '</svg>'
    : '<svg viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">' +
      '<path d="M5 3v14l12-7L5 3z"/>' +
      '</svg>';

  // visualizador: pausa/anima as barrinhas
  el.soundViz.classList.toggle('is-paused', !on);

  if (!on) {
    setTrackMeta(null, null);
    document.querySelectorAll('.vc-sound-result.is-playing').forEach(function (n) {
      n.classList.remove('is-playing');
    });
  }
}

function updateSourceLabel(source) {
  var label = vhub.el.soundSource.querySelector('span');
  if (!label) return;
  if (source === 'radio')       label.textContent = 'Rádio FM';
  else if (source === 'search') label.textContent = 'Buscar';
  else                          label.textContent = 'Link';
}


// micro feedback de press (botões e inputs)
function pulseBtn(btn) {
  btn.style.transform = 'scale(0.88)';
  setTimeout(function () { btn.style.transform = ''; }, 110);
}
