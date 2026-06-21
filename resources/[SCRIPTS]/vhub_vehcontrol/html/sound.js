// sound.js — aside TOPO-CENTRO (Som)
// PLACEHOLDER VISUAL — não envia callback para o Lua. Apenas comportamento
// local (play/pause/seleção de fonte/volume) para a UX já existir. Quando
// o resource vhub_sound entrar, basta trocar os listeners por post('...').


vhub.ready(function (el) {
  attachSoundUI();
  // estado inicial: pausado (visualizador parado, ícone Play)
  setPlaying(false);
});


// ============================================================
// ESTADO LOCAL — sem persistência, sem comunicação com Lua
// ============================================================

var _sound = {
  playing: false,
  source:  'radio',
  volume:  55,
};


function attachSoundUI() {
  var el = vhub.el;

  // Play / Pause
  el.soundPlay.addEventListener('click', function () {
    setPlaying(!_sound.playing);
  });

  // Prev / Next (placeholder — feedback visual apenas)
  el.soundPrev.addEventListener('click', function () { pulseBtn(el.soundPrev); });
  el.soundNext.addEventListener('click', function () { pulseBtn(el.soundNext); });

  // Fonte (Rádio / MP3 / URL)
  document.querySelectorAll('.vc-sound-tab').forEach(function (tab) {
    tab.addEventListener('click', function () {
      document.querySelectorAll('.vc-sound-tab').forEach(function (t) {
        t.classList.remove('is-active');
      });
      tab.classList.add('is-active');
      _sound.source = tab.dataset.source;
      updateSourceLabel(_sound.source);
    });
  });

  // Volume
  el.soundVolume.addEventListener('input', function () {
    _sound.volume = Number(el.soundVolume.value);
    el.soundVolumeVal.textContent = _sound.volume + '%';
  });
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

  // título placeholder
  if (on) {
    el.soundTitle.textContent = 'Tocando agora';
    el.soundArtist.textContent = sourceArtist(_sound.source);
  } else {
    el.soundTitle.textContent = 'Nenhuma faixa';
    el.soundArtist.textContent = '— · —';
  }
}


function updateSourceLabel(source) {
  var label = vhub.el.soundSource.querySelector('span');
  if (!label) return;
  if (source === 'radio') label.textContent = 'Rádio FM';
  else if (source === 'mp3') label.textContent = 'MP3 Local';
  else label.textContent = 'Stream URL';

  if (_sound.playing) vhub.el.soundArtist.textContent = sourceArtist(source);
}


function sourceArtist(source) {
  if (source === 'radio') return 'Rádio FM · 100.0';
  if (source === 'mp3')   return 'Biblioteca local';
  return 'Stream remoto';
}


// micro feedback de press p/ prev/next (sem ação real)
function pulseBtn(btn) {
  btn.style.transform = 'scale(0.88)';
  setTimeout(function () { btn.style.transform = ''; }, 110);
}
