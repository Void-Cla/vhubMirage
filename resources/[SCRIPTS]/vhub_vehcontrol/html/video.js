// video.js — telinha "DVD do carro" (mini-player de vídeo flutuante).
//
// Mostra o CLIPE do YouTube que está tocando, em MUTE (o áudio 3D vem do vhub_wow —
// decisão #53: áudio=wow, vídeo=vehcontrol). O iframe usa host nocookie (menos anúncio).
// Só o videoId de 11 chars (validado no servidor) entra no player — nunca string crua.
//
// Ciclo: server manda 'soundVideoAttach{videoId}' → monta YT.Player mute → telinha visível.
// Fechar (X) ou 'soundVideoDetach' → destrói o player (A-07) e esconde a telinha.


// ============================================================
// PRONTIDÃO DA IFRAME API (carrega async — mesmo padrão do vhub_wow)
// ============================================================

var _ytReady = false;
var _ytQueue = [];

window.onYouTubeIframeAPIReady = function () {
  _ytReady = true;
  while (_ytQueue.length) { try { _ytQueue.shift()(); } catch (e) {} }
};


// ============================================================
// ESTADO — 1 player por vez
// ============================================================

var _dvd = {
  player: null,      // instância YT.Player
  videoId: null,     // id atual (11 chars)
  mountId: null,     // id do <div> que a API converte em iframe
};


// ============================================================
// LIFECYCLE
// ============================================================

vhub.ready(function (el) {
  if (el.dvdClose) {
    // fechar pela telinha: para o vídeo (o áudio do carro continua, é do wow)
    el.dvdClose.addEventListener('click', function () {
      onVideoDetach();
      // avisa o Lua que o usuário desligou o vídeo (desmarca o checkbox no painel Som)
      post('soundVideoOff', {});
    });
  }
});


// ============================================================
// ATTACH / DETACH — monta e derruba o iframe do YouTube (mute)
// ============================================================

// mostra a telinha e monta o player do videoId (validado server-side)
function onVideoAttach(videoId, title) {
  var el = vhub.el;
  if (!el.dvd || !el.dvdFrame) return;
  if (!/^[\w-]{11}$/.test(videoId)) return;   // defesa: espelha o server (11 chars)

  // já tocando o mesmo vídeo: só garante visível
  if (_dvd.player && _dvd.videoId === videoId) {
    el.dvd.classList.remove('hidden');
    return;
  }

  destroyPlayer();   // troca de vídeo: derruba o anterior (A-07)

  if (el.dvdTitle) el.dvdTitle.textContent = title || 'DVD do carro';   // textContent anti-XSS
  el.dvd.classList.remove('hidden');

  _dvd.videoId = videoId;

  function build() {
    if (_dvd.videoId !== videoId) return;   // detach chegou antes de montar

    var mount = document.createElement('div');
    _dvd.mountId = 'vc-yt-' + videoId;
    mount.id = _dvd.mountId;
    el.dvdFrame.appendChild(mount);

    _dvd.player = new YT.Player(_dvd.mountId, {
      width: '100%', height: '100%', videoId: videoId,
      host: 'https://www.youtube-nocookie.com',
      playerVars: {
        autoplay: 1, controls: 0, disablekb: 1, fs: 0,
        modestbranding: 1, playsinline: 1, rel: 0, iv_load_policy: 3,
      },
      events: {
        onReady: function (e) {
          if (_dvd.videoId !== videoId) { try { e.target.destroy(); } catch (x) {} return; }
          try { e.target.mute(); } catch (x) {}          // MUTE fixo: áudio vem do wow
          try { e.target.playVideo(); } catch (x) {}
        },
        onError: function () { /* vídeo embargado: silencioso, não trava a UI */ },
      },
    });
  }

  if (_ytReady) build(); else _ytQueue.push(build);
}

// esconde a telinha e destrói o player (áudio do carro segue tocando no wow)
function onVideoDetach() {
  var el = vhub.el;
  destroyPlayer();
  if (el.dvd) el.dvd.classList.add('hidden');
  // mantém o checkbox "Vídeo no carro" do painel Som em sincronia
  if (typeof resetVideoToggle === 'function') resetVideoToggle();
}

// derruba o YT.Player e limpa o container (A-07: cleanup real)
function destroyPlayer() {
  if (_dvd.player) { try { _dvd.player.destroy(); } catch (e) {} }
  _dvd.player = null;
  _dvd.videoId = null;

  // descarta builds pendentes na fila (evita leak se API YT nao carregou ainda)
  _ytQueue.length = 0;

  var el = vhub.el;
  if (el.dvdFrame) el.dvdFrame.innerHTML = '';   // remove o iframe órfão
  _dvd.mountId = null;
}
