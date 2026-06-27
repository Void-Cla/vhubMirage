// ============================================================
// app.js — painel minimalista do player de replay (VRCS)
// Vanilla JS. Sem framework, sem CDN. Toda regra de negocio fica no Lua;
// aqui so UI + roteamento de controles para o cliente.
// ============================================================

const RES = 'vhub_vrcs';

const SPEEDS = [0.5, 1, 2, 4];
let speedIdx = 1;
let seeking  = false;


// ============================================================
// PONTE NUI
// ============================================================

function post(name, data) {
  return fetch(`https://${RES}/${name}`, {
    method:  'POST',
    headers: { 'Content-Type': 'application/json' },
    body:    JSON.stringify(data || {}),
  }).catch(() => {});
}


// ============================================================
// ELEMENTOS
// ============================================================

const app      = document.getElementById('app');
const elList   = document.getElementById('list');
const elPlayer = document.getElementById('player');
const elItems  = document.getElementById('list-items');
const elEmpty  = document.getElementById('list-empty');
const btnPlay  = document.getElementById('btn-play');
const btnSpeed = document.getElementById('btn-speed');
const btnCam   = document.getElementById('btn-cam');
const seek     = document.getElementById('seek');
const tCur     = document.getElementById('t-cur');
const tDur     = document.getElementById('t-dur');
const focusLbl = document.getElementById('focus-label');


// ============================================================
// HELPERS
// ============================================================

function fmt(sec) {
  sec = Math.max(0, Math.floor(sec || 0));
  const m = Math.floor(sec / 60);
  const s = sec % 60;
  return `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
}

function show(view) {
  app.classList.remove('hidden');
  elList.classList.toggle('hidden',   view !== 'list');
  elPlayer.classList.toggle('hidden', view !== 'player');
}

function hideAll() {
  app.classList.add('hidden');
  elList.classList.add('hidden');
  elPlayer.classList.add('hidden');
}


// ============================================================
// LISTA
// ============================================================

function renderList(replays) {
  replays = replays || [];
  elItems.innerHTML = '';
  elEmpty.classList.toggle('hidden', replays.length > 0);

  replays.forEach((r) => {
    // aceita tanto o shape do cache local quanto a linha do DB (servidor)
    const rid   = r.raceId || r.race_id;
    const tName = r.track || r.track_id || '?';
    const n     = r.n != null ? r.n : (r.players_n || 0);
    const dur   = r.dur != null ? r.dur : r.duration_s;
    const ts    = r.at || r.created_at;
    if (!rid) return;

    const li = document.createElement('li');
    li.dataset.raceId = rid;

    const main = document.createElement('div');
    main.className = 'r-main';

    const track = document.createElement('span');
    track.className = 'r-track';
    track.textContent = tName;                   // textContent = anti-XSS

    const meta = document.createElement('span');
    meta.className = 'r-meta';
    const date = ts ? new Date(ts * 1000).toLocaleString() : '';
    meta.textContent = `${r.kind || 'sprint'} • ${n} pilotos • ${fmt(dur)}${date ? ' • ' + date : ''}`;

    main.appendChild(track);
    main.appendChild(meta);

    const play = document.createElement('span');
    play.className = 'r-play';
    play.textContent = '▶';

    li.appendChild(main);
    li.appendChild(play);
    li.addEventListener('click', () => post('play', { raceId: rid }));
    elItems.appendChild(li);
  });
}


// ============================================================
// TICK (estado de reproducao vindo do cliente)
// ============================================================

function onTick(msg) {
  btnPlay.textContent = msg.playing ? '❚❚' : '▶';
  tCur.textContent = fmt(msg.t);
  tDur.textContent = fmt(msg.dur);
  if (!seeking && msg.dur > 0) {
    seek.value = Math.round((msg.t / msg.dur) * 1000);
  }
  focusLbl.textContent = msg.focusLabel || '—';
  if (msg.camMode) btnCam.textContent = `📷 ${msg.camMode}`;

  // sincroniza o rotulo de velocidade quando o cliente dita o valor
  const i = SPEEDS.indexOf(msg.speed);
  if (i >= 0) { speedIdx = i; btnSpeed.textContent = `${SPEEDS[i]}x`; }
}


// ============================================================
// EVENTOS DE UI
// ============================================================

// botoes com data-act (toggle/back/focus/close)
document.querySelectorAll('[data-act]').forEach((btn) => {
  btn.addEventListener('click', () => {
    const act = btn.dataset.act;
    if (act === 'close') { post('close'); return; }
    if (act === 'back')  { post('control', { action: 'back' }); return; }
    if (act === 'focus') { post('control', { action: 'focus', delta: Number(btn.dataset.delta) }); return; }
    if (act === 'toggle'){ post('control', { action: 'toggle' }); return; }
    if (act === 'cam')   { post('control', { action: 'cam' }); return; }
  });
});

// velocidade (cicla SPEEDS)
btnSpeed.addEventListener('click', () => {
  speedIdx = (speedIdx + 1) % SPEEDS.length;
  btnSpeed.textContent = `${SPEEDS[speedIdx]}x`;
  post('control', { action: 'speed', value: SPEEDS[speedIdx] });
});

// timeline (seek)
seek.addEventListener('input',  () => { seeking = true;  post('control', { action: 'seek', value: seek.value / 1000 }); });
seek.addEventListener('change', () => { seeking = false; post('control', { action: 'seek', value: seek.value / 1000 }); });

// ESC fecha
document.addEventListener('keyup', (e) => { if (e.key === 'Escape') post('close'); });


// ============================================================
// MENSAGENS DO CLIENTE
// ============================================================

window.addEventListener('message', (ev) => {
  const msg = ev.data || {};
  switch (msg.type) {
    case 'open':  renderList(msg.replays); show(msg.view || 'list'); break;
    case 'view':  if (msg.replays) renderList(msg.replays); show(msg.view); break;
    case 'tick':  onTick(msg); break;
    case 'close': hideAll(); break;
  }
});
