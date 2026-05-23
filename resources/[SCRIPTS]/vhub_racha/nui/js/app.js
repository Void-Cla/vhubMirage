// nui/js/app.js - painel e HUD do vhub_racha.
(() => {
  const $ = (q) => document.querySelector(q);
  const $$ = (q) => Array.from(document.querySelectorAll(q));
  const res = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'vhub_racha';

  const state = {
    tracks: [],
    lobbies: [],
    selected: null,
    selectedData: null,
    general: [],
    myHistory: [],
    profile: null,
    tab: 'track',
    countdownTimer: null,
    toastTimer: null,
  };

  async function post(name, data) {
    try {
      const r = await fetch(`https://${res}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data || {}),
      });
      return await r.json().catch(() => ({}));
    } catch (_) {
      return {};
    }
  }

  function esc(v) {
    return String(v ?? '').replace(/[&<>"']/g, (c) => ({
      '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
    }[c]));
  }

  function money(v) {
    const n = Math.max(0, Math.floor(Number(v) || 0));
    return `R$ ${n.toString().replace(/\B(?=(\d{3})+(?!\d))/g, '.')}`;
  }

  function time(ms) {
    if (ms === null || ms === undefined || Number(ms) < 0) return '--:--.---';
    const n = Math.max(0, Math.floor(Number(ms) || 0));
    const m = Math.floor(n / 60000);
    const s = Math.floor((n % 60000) / 1000);
    const x = n % 1000;
    return `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}.${String(x).padStart(3, '0')}`;
  }

  function toast(msg, kind) {
    const el = $('#toast');
    el.textContent = String(msg || '');
    el.className = `toast ${kind || ''}`;
    clearTimeout(state.toastTimer);
    state.toastTimer = setTimeout(() => el.classList.add('hidden'), 3200);
  }

  function selectedTrack() {
    return state.tracks.find((t) => t.id === state.selected) || state.tracks[0] || null;
  }

  function selectedLobby() {
    return state.lobbies.find((l) => l.track_id === state.selected) || null;
  }

  function renderTracks() {
    $('#tracks').innerHTML = state.tracks.map((t) => `
      <button class="track ${t.id === state.selected ? 'active' : ''}" data-track="${esc(t.id)}">
        <i class="fa-solid ${t.kind === 'moto' ? 'fa-motorcycle' : 'fa-flag-checkered'}"></i>
        <span><strong>${esc(t.label)}</strong><span>${esc(t.district)} - ${esc(t.kind)}</span></span>
      </button>
    `).join('');
  }

  function renderMain() {
    const t = selectedTrack();
    if (!t) return;
    $('#track-title').textContent = t.label;
    $('#track-sub').textContent = `${t.district} - ${t.kind}`;
    $('#entry-fee').value = t.default_fee || 0;
    $('#laps').value = t.laps || 1;
    $('#metrics').innerHTML = `
      <div class="metric"><strong>${t.checkpoints.length}</strong><span>Checkpoints</span></div>
      <div class="metric"><strong>${t.laps}</strong><span>Voltas padrao</span></div>
      <div class="metric"><strong>${t.max_players}</strong><span>Grid maximo</span></div>
      <div class="metric"><strong>${Math.floor(t.limit_seconds / 60)}m</strong><span>Tempo limite</span></div>
    `;
    renderLobby();
    renderBoard();
  }

  function renderLobby() {
    const lobby = selectedLobby();
    const box = $('#lobby');
    if (!lobby) {
      box.innerHTML = `<div class="empty">Nenhum lobby ativo nessa pista.</div>`;
      return;
    }
    const rows = (lobby.standings || []).map((p, i) => `
      <div class="row">
        <span class="pos">${p.position || p.live_position || i + 1}</span>
        <span><strong>${esc(p.nickname)}</strong><span>${esc(p.status)} - volta ${p.lap || 1}</span></span>
        <span class="time">${p.duration_ms ? time(p.duration_ms) : `${p.progress || 0} cp`}</span>
      </div>
    `).join('');
    box.innerHTML = `
      <div class="lobby-head">
        <div>
          <strong>${esc(lobby.organizer_nickname)}</strong>
          <span>${esc(lobby.state)} - ${lobby.participant_count}/${lobby.max_players} - ${money(lobby.prize_pool)}</span>
        </div>
        <div class="lobby-actions">
          <button class="btn primary" id="join"><i class="fa-solid fa-right-to-bracket"></i> Entrar</button>
          <button class="btn ghost" id="start"><i class="fa-solid fa-play"></i> Largar</button>
          <button class="btn ghost" id="leave"><i class="fa-solid fa-person-running"></i> Sair</button>
          <button class="btn danger" id="cancel"><i class="fa-solid fa-ban"></i> Cancelar</button>
        </div>
      </div>
      ${rows || '<div class="empty">Sem pilotos.</div>'}
    `;
  }

  function boardRows(rows, mode) {
    if (!rows || rows.length === 0) return '<div class="empty">Sem registros.</div>';
    return rows.map((r, i) => {
      const title = r.nickname || r.track_id || `Corrida ${r.run_id || ''}`;
      const sub = mode === 'general'
        ? `${r.wins || 0} vitorias - ${r.podiums || 0} podios - ${r.finishes || 0} fins`
        : `${r.status || 'recorde'} ${r.payout ? '- ' + money(r.payout) : ''}`;
      const val = r.best_ms || r.duration_ms;
      return `
        <div class="row">
          <span class="pos">${r.position || i + 1}</span>
          <span><strong>${esc(title)}</strong><span>${esc(sub)}</span></span>
          <span class="time">${val ? time(val) : (r.score || '--')}</span>
        </div>
      `;
    }).join('');
  }

  function renderBoard() {
    $$('.tab').forEach((b) => b.classList.toggle('active', b.dataset.tab === state.tab));
    const selected = state.selectedData || {};
    let rows = selected.ranking || [];
    let mode = 'track';
    if (state.tab === 'general') { rows = state.general || []; mode = 'general'; }
    if (state.tab === 'history') { rows = selected.history || state.myHistory || []; mode = 'history'; }
    $('#board').innerHTML = boardRows(rows, mode);
  }

  function renderAll() {
    renderTracks();
    renderMain();
  }

  function applyOpen(data) {
    state.tracks = data.tracks || [];
    state.lobbies = data.lobbies || [];
    state.selected = data.selected_track_id || (state.tracks[0] && state.tracks[0].id);
    state.selectedData = data.selected || {};
    state.general = data.general || [];
    state.myHistory = data.my_history || [];
    state.profile = data.profile || null;
    $('#brand-name').textContent = (data.brand && data.brand.name) || 'Mirage Racha';
    $('#brand-tag').textContent = (data.brand && data.brand.tag) || 'Liga clandestina';
    $('#nickname').value = state.profile && state.profile.nickname || '';
    $('#vhub-bg').classList.remove('hidden');
    $('#panel').classList.remove('hidden');
    if (window.vhubSand) window.vhubSand.start();
    renderAll();
  }

  function closePanel(send) {
    $('#panel').classList.add('hidden');
    $('#vhub-bg').classList.add('hidden');
    if (window.vhubSand) window.vhubSand.stop();
    if (send !== false) post('close');
  }

  function updateLobby(lobby) {
    if (!lobby) return;
    const idx = state.lobbies.findIndex((l) => l.track_id === lobby.track_id);
    if (idx >= 0) state.lobbies[idx] = lobby;
    else state.lobbies.push(lobby);
    renderLobby();
  }

  function raceHud(data) {
    if (!data || !data.track) return;
    const hud = $('#race-hud');
    const standings = data.standings || [];
    const selfRef = data.self || {};
    const self = standings.find((p) => (
      (selfRef.char_id && Number(p.char_id) === Number(selfRef.char_id)) ||
      (selfRef.src && Number(p.src) === Number(selfRef.src))
    )) || standings[0] || {};
    $('#hud-track').textContent = data.track.label || 'Racha';
    $('#hud-time').textContent = time(data.elapsed_ms || 0);
    $('#hud-cp').textContent = `${data.next_checkpoint || 1}/${(data.track.checkpoints || []).length}`;
    $('#hud-lap').textContent = `Volta ${data.lap || 1}/${data.laps || 1}`;
    $('#hud-pos').textContent = self.live_position || '--';
    $('#hud-total').textContent = `/${standings.length || '--'}`;
    hud.classList.remove('hidden');
  }

  function startCountdown(data) {
    const box = $('#countdown');
    const num = $('#count-num');
    $('#count-track').textContent = data.track || 'Racha';
    let left = Math.ceil((Number(data.ms) || 7000) / 1000);
    clearInterval(state.countdownTimer);
    num.textContent = left;
    box.classList.remove('hidden');
    state.countdownTimer = setInterval(() => {
      left -= 1;
      num.textContent = left > 0 ? left : 'VAI';
      if (left < 0) {
        clearInterval(state.countdownTimer);
        box.classList.add('hidden');
      }
    }, 1000);
  }

  function finish(data) {
    $('#finish-pos').textContent = data.position ? `${data.position}o lugar` : String(data.status || 'DNF').toUpperCase();
    $('#finish-time').textContent = data.duration_ms ? time(data.duration_ms) : '--:--.---';
    $('#finish-pay').textContent = data.payout ? money(data.payout) : 'R$ 0';
    $('#finish').classList.remove('hidden');
    setTimeout(() => $('#finish').classList.add('hidden'), 6500);
    $('#race-hud').classList.add('hidden');
  }

  window.addEventListener('message', (ev) => {
    const msg = ev.data || {};
    if (msg.action === 'open') applyOpen(msg.data || {});
    if (msg.action === 'close') closePanel(false);
    if (msg.action === 'refresh' && msg.data && msg.data.lobby) updateLobby(msg.data.lobby);
    if (msg.action === 'result' && msg.data) {
      if (msg.data.ok) {
        if (msg.data.data && msg.data.data.track_id) updateLobby(msg.data.data);
        toast('Operacao executada.', 'ok');
      } else {
        toast(msg.data.err || 'Operacao negada.', 'error');
      }
    }
    if (msg.action === 'toast') toast(msg.data && msg.data.msg, msg.data && msg.data.kind);
    if (msg.action === 'countdown') startCountdown(msg.data || {});
    if (msg.action === 'raceStart' || msg.action === 'raceHud') raceHud(msg.data || {});
    if (msg.action === 'raceEnd') $('#race-hud').classList.add('hidden');
    if (msg.action === 'finish') finish(msg.data || {});
    if (msg.action === 'abort') {
      toast((msg.data && msg.data.reason) || 'Corrida encerrada.', 'warn');
      $('#race-hud').classList.add('hidden');
    }
  });

  document.addEventListener('click', (ev) => {
    const close = ev.target.closest('[data-close]');
    if (close) return closePanel();

    const trackBtn = ev.target.closest('[data-track]');
    if (trackBtn) {
      state.selected = trackBtn.dataset.track;
      post('refresh', { track_id: state.selected });
      renderAll();
      return;
    }

    const tab = ev.target.closest('[data-tab]');
    if (tab) {
      state.tab = tab.dataset.tab;
      renderBoard();
      return;
    }

    const track = selectedTrack();
    if (!track) return;
    if (ev.target.closest('#route')) post('route', { track_id: track.id });
    if (ev.target.closest('#save-nick')) post('setNick', { nickname: $('#nickname').value, track_id: track.id });
    if (ev.target.closest('#create')) post('create', {
      track_id: track.id,
      entry_fee: Number($('#entry-fee').value) || 0,
      laps: Number($('#laps').value) || 1,
      ranked: $('#ranked').checked,
    });
    if (ev.target.closest('#join')) post('join', { track_id: track.id });
    if (ev.target.closest('#start')) post('start', { track_id: track.id });
    if (ev.target.closest('#leave')) post('leave', { track_id: track.id });
    if (ev.target.closest('#cancel')) post('cancel', { track_id: track.id });
  });

  document.addEventListener('keydown', (ev) => {
    if (ev.key === 'Escape') closePanel();
  });
})();
