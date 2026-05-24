// nui/js/app.js — vhub_racha v5 (Mirage Racha)
// L-D8: NUI nao decide. Relay puro de intencao para o servidor.
//
// v5: HUD cinematografico (CP grande, velocimetro suave, countdown com aneis,
//     timer com compensacao de latencia, leaderboard polido, finish glow).
//
// IMPORTANTE: As chamadas POST() e os 'action' existentes NAO foram alterados.
// Mensagens novas do HUD continuam OPCIONAIS — se o cliente Lua nao usar, nada quebra.
//
// ── Mensagens NOVAS aceitas pelo NUI (cliente Lua envia via SendNUIMessage) ──
//   { action: 'hud_show',     data: { laps_total, cps_total, players_total, me_id, best_ms? } }
//   { action: 'hud_countdown',data: { seconds: 3 }   -> roda 3,2,1,GO local + dispara cronometro
//   { action: 'hud_start',    data: { server_now_ms?, elapsed_ms? } -> compensa latencia
//   { action: 'hud_cp',       data: { i, n, dist, heading_deg?, lap?, lap_total? } }
//   { action: 'hud_speed',    data: { kmh } }
//   { action: 'hud_drift',    data: { score } }   -> score 0 esconde
//   { action: 'hud_lap',      data: { lap, lap_total, best_ms? } -> flash "VOLTA N"
//   { action: 'hud_flash',    data: { text, kind? } }
//   { action: 'hud_leader',   data: { rows: [{id, name, gap_ms|gap_m|status}], me_id? }
//   { action: 'hud_finish',   data: { placement, time_ms, payout } }
//   { action: 'hud_hide',     data: {} }
//
// ── Mensagens existentes (PRESERVADAS) ──
//   open, close, refresh, result, ranking, history, results, race_finish,
//   editor_open, editor_draft, editor_phase, editor_close.

(() => {
  const state = {
    open: false,
    catalog: [],
    lobbies: [],
    cfg: { brand_name: 'Mirage Racha', brand_tag: 'Liga clandestina', max_fee: 100000 },
    activeTab: 'tracks',
    tracksFilter: '',
    tracksKind: '',
    modal: { track: null, laps: 1, fee: 1000, mode: 'rankeada' },
    editor: { open: false, draft: null },

    // HUD
    hud: {
      open: false,
      running: false,
      startedAt: 0,       // performance.now() ajustado para GO real
      bestMs: 0,
      lap: 1, lapTotal: 1,
      cpI: 1, cpN: 1,
      meId: null,
      rafId: null,
      lastSpeed: 0,
      smoothSpeed: 0,
      lastHeading: 0,
    },
  };

  const $  = (s) => document.querySelector(s);
  const $$ = (s) => document.querySelectorAll(s);
  const el = (tag, attrs, ...children) => {
    const e = document.createElement(tag);
    if (attrs) for (const [k, v] of Object.entries(attrs)) {
      if (k === 'class') e.className = v;
      else if (k === 'html') e.innerHTML = v;
      else if (k.startsWith('on') && typeof v === 'function') e.addEventListener(k.slice(2), v);
      else if (k.startsWith('data-') || k === 'colspan' || k === 'title' || k === 'value') e.setAttribute(k, v);
      else e[k] = v;
    }
    for (const c of children) {
      if (c == null) continue;
      e.appendChild(typeof c === 'string' ? document.createTextNode(c) : c);
    }
    return e;
  };

  const clamp = (n, lo, hi) => Math.max(lo, Math.min(hi, n));
  const fmtNum = (n) => {
    const v = Math.max(0, Math.floor(Number(n) || 0));
    return v.toString().replace(/\B(?=(\d{3})+(?!\d))/g, '.');
  };
  const fmtMoney = (n) => 'R$ ' + fmtNum(n);
  const fmtTime = (ms) => {
    const n = Math.max(0, Math.floor(Number(ms) || 0));
    const mm = Math.floor(n / 60000);
    const ss = Math.floor((n % 60000) / 1000);
    const mmm = n % 1000;
    return `${String(mm).padStart(2, '0')}:${String(ss).padStart(2, '0')}.${String(mmm).padStart(3, '0')}`;
  };
  const fmtGapMs = (ms) => {
    const n = Math.floor(Math.abs(Number(ms) || 0));
    if (n === 0) return '—';
    const ss = Math.floor(n / 1000);
    const mmm = n % 1000;
    return (ms < 0 ? '-' : '+') + ss + '.' + String(mmm).padStart(3, '0');
  };
  const fmtDate = (unix) => {
    if (!unix) return '—';
    const d = new Date(unix * 1000);
    return d.toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' });
  };

  const KIND_LABELS = {
    sprint: 'Sprint', circuit: 'Circuito', drag: 'Drag', drift: 'Drift',
    speedtrap: 'Radar', timeattack: 'Contra-relógio', freerun: 'Free Run',
  };
  const KIND_ICONS = {
    sprint: 'fa-solid fa-bolt', circuit: 'fa-solid fa-arrows-rotate',
    drag: 'fa-solid fa-flag-checkered', drift: 'fa-solid fa-wind',
    speedtrap: 'fa-solid fa-gauge-high', timeattack: 'fa-solid fa-stopwatch',
    freerun: 'fa-solid fa-road',
  };

  const POST = (cb, data) =>
    fetch(`https://${typeof GetParentResourceName === 'function'
      ? GetParentResourceName() : 'vhub_racha'}/${cb}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data || {}),
    }).then((r) => r.json().catch(() => ({}))).catch(() => ({}));

  function toast(message, kind = 'info') {
    const icon = kind === 'success' ? 'fa-circle-check'
               : kind === 'error'   ? 'fa-triangle-exclamation'
               :                      'fa-circle-info';
    const t = el('div', { class: `vh-toast ${kind}` },
      el('i', { class: 'fa-solid ' + icon }),
      el('span', null, message));
    $('#toast-stack').appendChild(t);
    setTimeout(() => {
      t.classList.add('fade-out');
      setTimeout(() => t.remove(), 250);
    }, 3500);
  }

  // ─── Mapeamento de erros (PT-BR) ────────────────────────────────────────
  const ERR = {
    sem_sessao:             'Sessão não encontrada.',
    pista_inexistente:      'Pista não encontrada.',
    lobby_fechado:          'Esse lobby já foi iniciado.',
    ja_no_lobby:            'Você já está nesse lobby.',
    ja_em_outra_corrida:    'Você já está em outra corrida.',
    lobby_cheio:            'O lobby está cheio.',
    saldo_insuficiente:     'Saldo insuficiente para a taxa.',
    sem_grid:               'Sem slots de grade disponíveis.',
    jogadores_insuficientes:'Jogadores insuficientes para iniciar.',
    nao_e_lobby:            'Não é mais um lobby aberto.',
    estado_invalido:        'Estado inválido para essa ação.',
    forbidden:              'Operação não permitida.',
    host_left:              'O organizador saiu.',
    fora_da_ready_zone:     'Vá até o ponto de largada para confirmar.',
    fora_do_lobby:          'Você não está nesse lobby.',
    sem_presenca_minima:    'Sem presença mínima confirmada.',
    lobby_expirou:          'Lobby expirou.',
  };
  const errMsg = (raw) => ERR[String(raw || '')] || `Falha: ${raw || 'erro desconhecido'}.`;

  // ─── Render: Pistas ─────────────────────────────────────────────────────
  function renderTracks() {
    const grid = $('#tracks-grid');
    const filter = (state.tracksFilter || '').trim().toLowerCase();
    const kind = state.tracksKind || '';
    let list = state.catalog;
    if (kind) list = list.filter((t) => t.kind === kind);
    if (filter) {
      list = list.filter((t) =>
        t.label.toLowerCase().includes(filter) ||
        (t.district || '').toLowerCase().includes(filter) ||
        (KIND_LABELS[t.kind] || '').toLowerCase().includes(filter));
    }
    $('#tracks-count').textContent = list.length;
    grid.innerHTML = '';
    if (list.length === 0) {
      grid.appendChild(el('div', { class: 'vh-empty' },
        el('i', { class: 'fa-solid fa-road' }),
        'Nenhuma pista encontrada.'));
      return;
    }
    for (const t of list) grid.appendChild(renderTrackCard(t));
  }

  function renderTrackCard(t) {
    const card = el('div', { class: 'vh-card vh-track' });
    const head = el('div', { class: 'vh-track-head' });
    head.appendChild(el('i', { class: (KIND_ICONS[t.kind] || 'fa-solid fa-road') }));
    head.appendChild(el('div', { class: 'vh-track-title' }, t.label));
    head.appendChild(el('span',
      { class: 'vh-kind-badge' + (t.illegal ? ' illegal' : '') },
      KIND_LABELS[t.kind] || t.kind));
    card.appendChild(head);

    const meta = el('div', { class: 'vh-track-meta' });
    meta.appendChild(el('span', null,
      el('i', { class: 'fa-solid fa-map-marker' }), ' ',
      el('b', null, t.district || '—')));
    meta.appendChild(el('span', null,
      el('i', { class: 'fa-solid fa-flag' }), ' ',
      el('b', null, String(t.cps || 0)), ' CPs'));
    meta.appendChild(el('span', null,
      el('i', { class: 'fa-solid fa-users' }), ' ',
      el('b', null, `${t.min_players}-${t.max_players}`)));
    if (t.laps > 1) {
      meta.appendChild(el('span', null,
        el('i', { class: 'fa-solid fa-arrows-rotate' }), ' ',
        el('b', null, String(t.laps)), ' voltas'));
    }
    if (t.alerts_police) {
      meta.appendChild(el('span', { title: 'Alerta polícia' },
        el('i', { class: 'fa-solid fa-triangle-exclamation' }), ' ',
        el('b', null, 'Polícia')));
    }
    if (t.source === 'custom') {
      meta.appendChild(el('span', { title: 'Pista customizada' },
        el('i', { class: 'fa-solid fa-hammer' }), ' ',
        el('b', null, 'Custom')));
    }
    card.appendChild(meta);

    const foot = el('div', { class: 'vh-track-foot' });
    foot.appendChild(el('span', { class: 'vh-track-fee' },
      t.default_fee > 0 ? fmtMoney(t.default_fee) : 'Grátis'));
    foot.appendChild(el('button', {
      class: 'vh-btn primary small',
      onclick: () => openCreate(t),
    }, el('i', { class: 'fa-solid fa-flag-checkered' }), 'Criar lobby'));
    card.appendChild(foot);
    return card;
  }

  // ─── Render: Lobbies ────────────────────────────────────────────────────
  function renderLobbies() {
    const list = $('#lobbies-list');
    $('#lobby-count').textContent = state.lobbies.length;
    list.innerHTML = '';
    if (state.lobbies.length === 0) {
      list.appendChild(el('div', { class: 'vh-empty' },
        el('i', { class: 'fa-solid fa-flag' }),
        'Nenhum lobby aberto. Crie um na aba "Pistas".'));
      return;
    }
    for (const lb of state.lobbies) list.appendChild(renderLobbyRow(lb));
  }

  function renderLobbyRow(lb) {
    const row = el('div', { class: 'vh-lobby' });
    row.appendChild(el('i', { class: KIND_ICONS[lb.kind] || 'fa-solid fa-road' }));
    const info = el('div', { class: 'vh-lobby-info' });

    const title = el('div', { class: 'vh-lobby-title' }, lb.label || lb.track_id);
    title.appendChild(el('span', { class: 'vh-lobby-state ' + lb.state },
      lb.state === 'pending' ? 'Confirmando' : 'Aberto'));
    if (lb.mode === 'treino') {
      title.appendChild(el('span', { class: 'vh-lobby-mode' }, 'TREINO'));
    }
    info.appendChild(title);

    const meta = el('div', { class: 'vh-lobby-meta' });
    meta.appendChild(el('span', null,
      KIND_LABELS[lb.kind] || lb.kind, ' · ',
      el('b', null, `${lb.players}/${lb.max_players}`), ' inscritos',
      lb.state === 'pending'
        ? el('span', null, ' · ', el('b', null, String(lb.confirmed || 0)), ' confirmados')
        : null, ' · ',
      el('b', null, fmtMoney(lb.entry_fee || 0)), ' entrada'));
    info.appendChild(meta);
    row.appendChild(info);

    const actions = el('div', { class: 'vh-lobby-actions' });
    actions.appendChild(el('button', {
      class: 'vh-btn primary small',
      onclick: () => POST('join', { inst_id: lb.id }),
    }, el('i', { class: 'fa-solid fa-right-to-bracket' }), 'Entrar'));
    row.appendChild(actions);
    return row;
  }

  // ─── Render: Ranking + Histórico ───────────────────────────────────────
  function renderRanking(rows) {
    const tbody = $('#ranking-tbody');
    tbody.innerHTML = '';
    if (!Array.isArray(rows) || rows.length === 0) {
      tbody.appendChild(el('tr', null,
        el('td', { class: 'vh-table-empty', colspan: 8 },
          'Sem dados ainda. Quando houver corridas, o ranking aparece aqui.')));
      return;
    }
    rows.forEach((r, i) => {
      const placeClass = i === 0 ? 'gold' : i === 1 ? 'silver' : i === 2 ? 'bronze' : '';
      tbody.appendChild(el('tr', null,
        el('td', { class: placeClass }, '#' + (i + 1)),
        el('td', null, r.nick || ('char_' + r.char_id)),
        el('td', null, String(r.wins || 0)),
        el('td', null, String(r.podiums || 0)),
        el('td', null, String(r.dnf || 0)),
        el('td', null, r.best_time_ms > 0 ? fmtTime(r.best_time_ms) : '—'),
        el('td', null, fmtNum(r.total_drift || 0)),
        el('td', null, (r.top_speed || 0) + ' km/h')));
    });
  }

  function renderHistory(rows) {
    const tbody = $('#history-tbody');
    tbody.innerHTML = '';
    if (!Array.isArray(rows) || rows.length === 0) {
      tbody.appendChild(el('tr', null,
        el('td', { class: 'vh-table-empty', colspan: 9 }, 'Nenhuma corrida registrada ainda.')));
      return;
    }
    for (const h of rows) {
      tbody.appendChild(el('tr', null,
        el('td', { class: 'when', title: fmtDate(h.started_unix) }, fmtDate(h.started_unix)),
        el('td', null, KIND_LABELS[h.kind] || h.kind),
        el('td', null, h.mode === 'treino' ? 'Treino' : 'Rankeada'),
        el('td', null, h.track_id),
        el('td', null, String(h.players_total || 0)),
        el('td', null, h.winner_nick || ('char_' + h.winner_char)),
        el('td', null, h.winner_time_ms > 0 ? fmtTime(h.winner_time_ms) : '—'),
        el('td', null, fmtMoney(h.pot_total || 0)),
        el('td', null, el('button', {
          class: 'vh-btn ghost small',
          onclick: () => POST('results', { history_id: h.id }),
        }, el('i', { class: 'fa-solid fa-eye' })))));
    }
  }

  // ─── Modal criar lobby ──────────────────────────────────────────────────
  function openCreate(track) {
    state.modal = {
      track, mode: 'rankeada',
      laps: track.laps || 1, fee: track.default_fee || 0,
    };
    $('#modal-track').textContent = track.label + ' (' + (track.district || '—') + ')';
    $('#modal-kind').textContent  = KIND_LABELS[track.kind] || track.kind;
    $('#modal-laps').value = track.laps || 1;
    $('#modal-laps').max   = 10;
    $('#modal-fee').value  = track.default_fee || 0;
    $('#modal-fee').max    = state.cfg.max_fee || 100000;
    $('#modal-mode').value = 'rankeada';
    if (track.kind === 'timeattack' || track.kind === 'freerun') {
      $('#modal-mode').value = 'treino';
      $('#modal-fee').value = 0;
    }
    $('#modal-create').classList.remove('hidden');
  }
  function closeModal() { $('#modal-create').classList.add('hidden'); }
  function submitCreate() {
    const m = state.modal;
    if (!m.track) return;
    POST('create', {
      track_id: m.track.id,
      mode: $('#modal-mode').value,
      laps: parseInt($('#modal-laps').value, 10) || 1,
      entry_fee: parseInt($('#modal-fee').value, 10) || 0,
    });
    closeModal();
  }

  // ─── Tabs ───────────────────────────────────────────────────────────────
  function switchTab(name) {
    state.activeTab = name;
    $$('.vh-tab').forEach((t) => t.classList.toggle('active', t.dataset.tab === name));
    $$('.vh-tabpanel').forEach((p) => p.classList.toggle('active', p.dataset.tabpanel === name));
    if (name === 'ranking') {
      POST('ranking', { kind: $('#ranking-kind').value || 'sprint',
                        mode: $('#ranking-mode').value || 'wins' });
    } else if (name === 'history') {
      POST('history', { kind: $('#history-kind').value || '',
                        mode: $('#history-mode').value || '' });
    }
  }

  // ─── Editor (NUI envia relays ao server) ────────────────────────────────
  function editorStart() { POST('editor_open', {}); }
  function editorSave() {
    const payload = {
      id:            ($('#meta-id').value || '').trim(),
      label:         ($('#meta-label').value || '').trim(),
      district:      ($('#meta-district').value || '').trim() || 'Custom',
      kind:          $('#meta-kind').value || 'sprint',
      laps:          parseInt($('#meta-laps').value, 10) || 1,
      default_fee:   parseInt($('#meta-fee').value, 10) || 0,
      limit_seconds: parseInt($('#meta-limit').value, 10) || 300,
      illegal:       $('#meta-illegal').checked === true,
      alerts_police: $('#meta-police').checked === true,
    };
    if (!payload.id) { toast('Informe um ID para a pista.', 'error'); return; }
    POST('editor_save', payload);
  }

  // ════════════════════════════════════════════════════════════════════════
  // HUD DE CORRIDA
  // ════════════════════════════════════════════════════════════════════════

  function hudShow(data) {
    const d = data || {};
    state.hud.open = true;
    state.hud.running = false;
    state.hud.bestMs = Number(d.best_ms) || 0;
    state.hud.lap = 1;
    state.hud.lapTotal = Number(d.laps_total) || 1;
    state.hud.cpI = 1;
    state.hud.cpN = Number(d.cps_total) || 1;
    state.hud.meId = d.me_id || null;
    state.hud.lastSpeed = 0;
    state.hud.smoothSpeed = 0;

    $('#hud').classList.remove('hidden');
    $('#hud-finish').classList.add('hidden');
    $('#hud-flash').classList.add('hidden');
    $('#hud-drift').classList.add('hidden');
    $('#hud-cp').classList.remove('near');

    $('#hud-pos').textContent = '1';
    $('#hud-pos-total').textContent = d.players_total ? '/' + d.players_total : '';
    $('#hud-lap').textContent = state.hud.lap;
    $('#hud-lap-total').textContent = '/' + state.hud.lapTotal;
    $('#hud-cp-i').textContent = state.hud.cpI;
    $('#hud-cp-n').textContent = '/' + state.hud.cpN;
    $('#hud-cp-dist').textContent = '0';
    $('#hud-time').textContent = '00:00.000';
    if (state.hud.bestMs > 0) {
      $('#hud-best').textContent = 'Melhor ' + fmtTime(state.hud.bestMs);
      $('#hud-best').classList.remove('hidden');
    } else {
      $('#hud-best').classList.add('hidden');
    }
    $('#hud-speed').textContent = '0';
    setSpeedArc(0);
    $('#hud-leader').innerHTML = '';

    // partículas em modo "boost" durante a corrida
    if (window.vhubSand && window.vhubSand.boost) window.vhubSand.boost(true);
  }

  function hudHide() {
    state.hud.open = false;
    state.hud.running = false;
    if (state.hud.rafId) cancelAnimationFrame(state.hud.rafId);
    state.hud.rafId = null;
    $('#hud').classList.add('hidden');
    $('#hud-countdown').classList.add('hidden');
    if (window.vhubSand && window.vhubSand.boost) window.vhubSand.boost(false);
  }

  // Countdown local — chamado pelo Lua quando o grid esta preso.
  // Ao bater GO, dispara hudStart() imediatamente. Sem latencia de rede.
  function hudCountdown(data) {
    const secs = clamp(parseInt((data && data.seconds) || 3, 10), 1, 5);
    const cd = $('#hud-countdown');
    const num = $('#hud-count-num');
    cd.classList.remove('hidden', 'go');
    let i = secs;
    num.textContent = String(i);
    // re-trigger animation
    num.style.animation = 'none'; void num.offsetWidth; num.style.animation = '';
    const tick = () => {
      i -= 1;
      if (i > 0) {
        num.textContent = String(i);
        num.style.animation = 'none'; void num.offsetWidth; num.style.animation = '';
        setTimeout(tick, 1000);
      } else {
        cd.classList.add('go');
        num.textContent = 'GO';
        num.style.animation = 'none'; void num.offsetWidth; num.style.animation = '';
        // dispara cronometro local IMEDIATAMENTE (sem espera)
        hudStart();
        setTimeout(() => cd.classList.add('hidden'), 900);
      }
    };
    setTimeout(tick, 1000);
  }

  // hudStart com compensacao de latencia.
  // Aceita opcional { elapsed_ms } para compensar atraso entre GO real e a chegada do evento,
  // ou { server_now_ms, started_at_ms } se o Lua quiser passar dois timestamps.
  function hudStart(data) {
    if (state.hud.running) return;
    state.hud.running = true;
    const now = performance.now();
    let offset = 0;
    if (data && typeof data === 'object') {
      if (typeof data.elapsed_ms === 'number' && data.elapsed_ms > 0) {
        offset = data.elapsed_ms;
      } else if (typeof data.server_now_ms === 'number' && typeof data.started_at_ms === 'number') {
        offset = Math.max(0, data.server_now_ms - data.started_at_ms);
      }
    }
    state.hud.startedAt = now - offset;
    if (state.hud.rafId) cancelAnimationFrame(state.hud.rafId);
    const tick = () => {
      if (!state.hud.running) return;
      const ms = performance.now() - state.hud.startedAt;
      $('#hud-time').textContent = fmtTime(ms);
      // suavizacao do velocimetro (interpolacao para evitar "tremidas")
      const cur = state.hud.smoothSpeed;
      const tgt = state.hud.lastSpeed;
      if (cur !== tgt) {
        const diff = tgt - cur;
        const step = diff * 0.18; // easing
        state.hud.smoothSpeed = Math.abs(diff) < 0.5 ? tgt : cur + step;
        setSpeedArc(state.hud.smoothSpeed);
      }
      state.hud.rafId = requestAnimationFrame(tick);
    };
    state.hud.rafId = requestAnimationFrame(tick);
  }

  function hudStop() {
    state.hud.running = false;
    if (state.hud.rafId) cancelAnimationFrame(state.hud.rafId);
    state.hud.rafId = null;
  }

  function hudUpdateCP(data) {
    const d = data || {};
    const i = Number(d.i || 1);
    const n = Number(d.n || state.hud.cpN || 1);
    state.hud.cpI = i; state.hud.cpN = n;
    $('#hud-cp-i').textContent = i;
    $('#hud-cp-n').textContent = '/' + n;
    const dist = Math.max(0, Math.floor(Number(d.dist) || 0));
    $('#hud-cp-dist').textContent = dist >= 1000 ? (dist / 1000).toFixed(1) + 'k' : String(dist);
    $('#hud-cp').classList.toggle('near', dist > 0 && dist < 60);

    if (typeof d.heading_deg === 'number') {
      // a seta interna esta em rotate(-45deg) no CSS base. Adicionamos o heading relativo.
      const arr = document.querySelector('#hud-cp .vh-cp-arrow i');
      if (arr) arr.style.transform = `rotate(${-45 + d.heading_deg}deg)`;
      state.hud.lastHeading = d.heading_deg;
    }
    if (typeof d.lap === 'number') {
      state.hud.lap = d.lap;
      $('#hud-lap').textContent = d.lap;
    }
    if (typeof d.lap_total === 'number') {
      state.hud.lapTotal = d.lap_total;
      $('#hud-lap-total').textContent = '/' + d.lap_total;
    }
  }

  function setSpeedArc(kmh) {
    // arco vai de 0..360 km/h => stroke-dashoffset 326.7..0
    const max = 360;
    const v = clamp(Number(kmh) || 0, 0, max);
    const off = 326.7 * (1 - v / max);
    const arc = $('#hud-speed-arc');
    if (!arc) return;
    arc.setAttribute('stroke-dashoffset', off.toFixed(1));
    arc.classList.toggle('fast',   v >= 180 && v < 280);
    arc.classList.toggle('danger', v >= 280);
  }

  function hudUpdateSpeed(data) {
    const k = Math.max(0, Math.floor(Number((data && data.kmh) || 0)));
    state.hud.lastSpeed = k;
    $('#hud-speed').textContent = k;
    // Se nao estiver rodando (timer parado), atualiza arco direto.
    if (!state.hud.running) {
      state.hud.smoothSpeed = k;
      setSpeedArc(k);
    }
  }

  function hudUpdateDrift(data) {
    const s = Math.max(0, Math.floor(Number((data && data.score) || 0)));
    const wrap = $('#hud-drift');
    if (s <= 0) { wrap.classList.add('hidden'); return; }
    wrap.classList.remove('hidden');
    $('#hud-drift-val').textContent = fmtNum(s);
  }

  function hudFlash(text) {
    const fl = $('#hud-flash');
    $('#hud-flash-text').textContent = String(text || '').toUpperCase();
    fl.classList.remove('hidden');
    fl.style.animation = 'none'; void fl.offsetWidth; fl.style.animation = '';
    clearTimeout(hudFlash._t);
    hudFlash._t = setTimeout(() => fl.classList.add('hidden'), 1800);
  }

  function hudLap(data) {
    const d = data || {};
    if (typeof d.lap === 'number') {
      state.hud.lap = d.lap;
      $('#hud-lap').textContent = d.lap;
    }
    if (typeof d.lap_total === 'number') {
      state.hud.lapTotal = d.lap_total;
      $('#hud-lap-total').textContent = '/' + d.lap_total;
    }
    if (d.best_ms && d.best_ms > 0) {
      state.hud.bestMs = d.best_ms;
      $('#hud-best').textContent = 'Melhor ' + fmtTime(d.best_ms);
      $('#hud-best').classList.remove('hidden');
    }
    hudFlash('Volta ' + (d.lap || state.hud.lap));
  }

  function hudLeader(data) {
    const rows = (data && Array.isArray(data.rows)) ? data.rows : [];
    const meId = (data && data.me_id) || state.hud.meId;
    const ol = $('#hud-leader');
    ol.innerHTML = '';
    if (rows.length === 0) return;

    let myPos = null;
    rows.slice(0, 6).forEach((r, idx) => {
      const li = el('li', { class: (meId != null && String(r.id) === String(meId)) ? 'me' : '' },
        el('span', { class: 'pl-rank' }, String(idx + 1)),
        el('span', { class: 'pl-name' }, r.name || ('Piloto ' + (idx + 1))),
        el('span', { class: 'pl-gap' },
          r.status ? r.status
          : typeof r.gap_ms === 'number' ? (idx === 0 ? '—' : fmtGapMs(r.gap_ms))
          : typeof r.gap_m === 'number'  ? (idx === 0 ? '—' : '+' + Math.max(0, Math.floor(r.gap_m)) + 'm')
          : '—')
      );
      ol.appendChild(li);
      if (meId != null && String(r.id) === String(meId)) myPos = idx + 1;
    });

    if (myPos != null) {
      $('#hud-pos').textContent = myPos;
      $('#hud-pos-total').textContent = '/' + rows.length;
    } else if (rows.length) {
      $('#hud-pos-total').textContent = '/' + rows.length;
    }
  }

  function hudFinish(data) {
    const d = data || {};
    hudStop();
    $('#hud-finish-tag').textContent = '#' + (d.placement || '?');
    $('#hud-finish-time').textContent = d.time_ms > 0 ? fmtTime(d.time_ms) : ($('#hud-time').textContent);
    $('#hud-finish-payout').textContent = fmtMoney(d.payout || 0);
    $('#hud-finish').classList.remove('hidden');
  }

  // ─── Mensagens do server ────────────────────────────────────────────────
  window.addEventListener('message', (e) => {
    const msg = e.data || {};
    switch (msg.action) {
      case 'open': {
        state.open = true;
        const d = msg.data || {};
        state.catalog = d.catalog || [];
        state.lobbies = d.lobbies || [];
        Object.assign(state.cfg, d.cfg || {});
        $('#brand-tag').textContent = state.cfg.brand_tag || 'Liga clandestina';
        $('#vhub-bg').classList.remove('hidden');
        $('#panel').classList.remove('hidden');
        switchTab('tracks');
        renderTracks();
        renderLobbies();
        renderRanking(d.ranking || []);
        renderHistory(d.history || []);
        window.vhubSand && window.vhubSand.start();
        break;
      }
      case 'close': {
        state.open = false;
        $('#panel').classList.add('hidden');
        $('#vhub-bg').classList.add('hidden');
        $('#modal-create').classList.add('hidden');
        if (!state.hud.open) window.vhubSand && window.vhubSand.stop();
        break;
      }
      case 'refresh': {
        const d = msg.data || {};
        if (d.lobbies) { state.lobbies = d.lobbies; renderLobbies(); }
        break;
      }
      case 'result': {
        const r = msg.data || {};
        if (r.ok) {
          const k = r.kind || '';
          if      (k === 'create') toast('Lobby criado. Vá ao ponto de largada e confirme presença.', 'success');
          else if (k === 'join')   toast('Você entrou no lobby. Vá ao ponto de largada.', 'success');
          else if (k === 'leave')  toast('Você saiu do lobby.', 'info');
          else                     toast('Operação concluída.', 'success');
          POST('refresh_lobbies', {});
          if (k === 'join') switchTab('lobbies');
        } else {
          const errCode = typeof r.data === 'string' ? r.data
            : (r.data && r.data.err) || '';
          toast(errMsg(errCode), 'error');
        }
        break;
      }
      case 'ranking': { renderRanking((msg.data || {}).data || []); break; }
      case 'history': { renderHistory(msg.data || []); break; }
      case 'results': {
        const d = msg.data || {};
        const rs = d.results || [];
        if (rs.length === 0) { toast('Sem resultados nessa sessão.', 'info'); return; }
        const lines = rs.map((r) =>
          `#${r.placement} ${r.nick} — ${fmtTime(r.total_time_ms)}` +
          (r.payout > 0 ? ` (${fmtMoney(r.payout)})` : ''));
        toast(lines.join(' · '), 'info');
        break;
      }
      case 'race_finish': {
        const d = msg.data || {};
        toast(`Você terminou em #${d.placement || '?'} — ${fmtMoney(d.payout || 0)}`,
              d.placement === 1 ? 'success' : 'info');
        if (state.hud.open) hudFinish(d);
        break;
      }

      // ── HUD ─────────────────────────────────────────────────────────
      case 'hud_show':      hudShow(msg.data); break;
      case 'hud_hide':      hudHide(); break;
      case 'hud_countdown': hudCountdown(msg.data); break;
      case 'hud_start':     hudStart(msg.data); break;
      case 'hud_stop':      hudStop(); break;
      case 'hud_cp':        hudUpdateCP(msg.data); break;
      case 'hud_speed':     hudUpdateSpeed(msg.data); break;
      case 'hud_drift':     hudUpdateDrift(msg.data); break;
      case 'hud_lap':       hudLap(msg.data); break;
      case 'hud_flash':     hudFlash((msg.data && msg.data.text) || ''); break;
      case 'hud_leader':    hudLeader(msg.data); break;
      case 'hud_finish':    hudFinish(msg.data); break;

      // Editor relays
      case 'editor_open':   state.editor.open = true;  state.editor.draft = msg.data || {}; break;
      case 'editor_draft':  state.editor.draft = msg.data || {}; break;
      case 'editor_phase': {
        const phase = (msg.data && msg.data.phase) || 'idle';
        if (phase === 'grid') toast('Fase 1: posicione os carros da grade.', 'info');
        if (phase === 'cps')  toast('Fase 2: dirija marcando checkpoints.', 'info');
        if (phase === 'meta') { toast('Fase 3: preencha os metadados da pista.', 'info'); switchTab('editor'); }
        break;
      }
      case 'editor_close':  state.editor.open = false; state.editor.draft = null; break;
    }
  });

  // ─── Bindings ───────────────────────────────────────────────────────────
  document.addEventListener('click', (ev) => {
    const t = ev.target.closest('[data-action], [data-tab]');
    if (!t) return;
    if (t.dataset.tab) { switchTab(t.dataset.tab); return; }
    const a = t.dataset.action;
    if (a === 'close')             POST('close', {});
    if (a === 'refresh')           POST('refresh_lobbies', {});
    if (a === 'modal-close')       closeModal();
    if (a === 'modal-create')      submitCreate();
    if (a === 'refresh-ranking') {
      POST('ranking', { kind: $('#ranking-kind').value || 'sprint',
                        mode: $('#ranking-mode').value || 'wins' });
    }
    if (a === 'refresh-history') {
      POST('history', { kind: $('#history-kind').value || '',
                        mode: $('#history-mode').value || '' });
    }
    if (a === 'editor-start')      editorStart();
    if (a === 'editor-phase-grid') POST('editor_phase', { phase: 'grid' });
    if (a === 'editor-phase-cps')  POST('editor_phase', { phase: 'cps' });
    if (a === 'editor-phase-meta') POST('editor_phase', { phase: 'meta' });
    if (a === 'editor-discard')    POST('editor_discard', {});
    if (a === 'editor-save')       editorSave();
  });

  document.addEventListener('keydown', (ev) => {
    if (!state.open) return;
    if (ev.key === 'Escape') {
      if (!$('#modal-create').classList.contains('hidden')) { closeModal(); return; }
      POST('close', {});
    }
  });

  document.addEventListener('input', (ev) => {
    if (ev.target.id === 'tracks-search')      { state.tracksFilter = ev.target.value; renderTracks(); }
    if (ev.target.id === 'tracks-filter-kind') { state.tracksKind   = ev.target.value; renderTracks(); }
  });
})();
