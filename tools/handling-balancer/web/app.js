// app.js — lógica da interface do Handling Balancer (vanilla JS, sem framework)
//
// Fluxo: carrega /api/cars -> renderiza um card por carro -> usuário decide tier (calculado x
// desejado x média) e vê a prévia do balanceamento ao vivo -> aplica. Rename tem preview próprio.

'use strict';

// ============================================================
// CONSTANTES / RÓTULOS PT-BR
// ============================================================

const TIER_ORDER = ['D', 'C', 'B', 'A', 'S', 'S+'];
const tierClass = (t) => 't-' + (t === 'S+' ? 'Sp' : t);

// rótulos amigáveis das 5 dimensões do score
const PART_LABELS = {
  accel: 'Aceleração', launch: 'Largada (tração)', grip: 'Curva (grip)',
  brake: 'Frenagem', stability: 'Estabilidade',
};

// rótulos amigáveis dos 8 campos do NÚCLEO-8
const FIELD_LABELS = {
  fInitialDriveForce: 'Força motriz (potência)',
  fInitialDragCoeff: 'Arrasto / aero',
  fInitialDriveMaxFlatVel: 'Teto de velocidade',
  fDriveInertia: 'Inércia de aceleração',
  fBrakeForce: 'Força de frenagem',
  fTractionCurveMax: 'Grip máximo',
  fTractionCurveMin: 'Grip mínimo',
  fAntiRollBarForce: 'Barra estabilizadora',
};


// ============================================================
// API
// ============================================================

async function api(method, url, body) {
  const opts = { method, headers: { 'Content-Type': 'application/json' } };
  if (body) opts.body = JSON.stringify(body);
  const res = await fetch(url, opts);
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || `HTTP ${res.status}`);
  return data;
}


// ============================================================
// RECONCILIAÇÃO DE TIER (mesma regra do servidor — local p/ resposta instantânea)
// ============================================================

const tierIndex = (t) => TIER_ORDER.indexOf(t);
function reconcile(calc, desired, mode) {
  const ci = tierIndex(calc), di = tierIndex(desired);
  let fi;
  if (mode === 'calculado' || di < 0) fi = ci;
  else if (mode === 'desejado') fi = di;
  else fi = Math.round((ci + di) / 2);
  fi = Math.max(0, Math.min(TIER_ORDER.length - 1, fi));
  return TIER_ORDER[fi];
}


// ============================================================
// RENDER
// ============================================================

const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

function setBadge(el, tier) {
  el.textContent = tier;
  el.className = 'tier-badge ' + el.className.replace(/t-\w+/g, '').replace(/\s+/g, ' ').trim();
  el.classList.add(tierClass(tier));
}

// estado por card (tier escolhido) para o apply
const cardState = new Map();

function renderCar(car, tiersOrder) {
  const tpl = $('#tpl-car').content.cloneNode(true);
  const card = $('.card', tpl);
  card.dataset.handling = car.handlingName;
  card.classList.add(tierClass(car.calculatedTier));

  // identidade
  $('.car-name', card).textContent = car.handlingNameRaw;
  $('.chip-model', card).textContent = 'modelo: ' + car.model;
  $('.chip-dt', card).textContent = car.drivetrain.toUpperCase();
  $('.chip-folder', card).textContent = 'pasta: ' + car.carFolder;

  // análise
  setBadge($('.tier-badge-calc', card), car.calculatedTier);
  setBadge($('.tier-badge-calc2', card), car.calculatedTier);
  $('.score', card).textContent = `score ${car.score} / 1000`;
  $('.pwr', card).textContent = car.powerToWeight != null
    ? `power-to-weight ${car.powerToWeight.toFixed(3)}` : '';
  renderBars($('.bars', card), car.parts);
  $('.notes', card).textContent = (car.notes || []).join(' · ');

  // decisão de tier
  const select = $('.desired-select', card);
  for (const t of tiersOrder) {
    const opt = document.createElement('option');
    opt.value = t; opt.textContent = 'Tier ' + t;
    select.appendChild(opt);
  }
  // desejado default = registry, senão o calculado
  select.value = (car.registry && car.registry.tier_base) || car.calculatedTier;

  const state = { handling: car.handlingName, calc: car.calculatedTier, mode: 'media' };
  cardState.set(card, state);

  const recompute = () => {
    const desired = select.value;
    const final = reconcile(car.calculatedTier, desired, state.mode);
    state.final = final;
    setBadge($('.tier-badge-final', card), final);
    loadPreview(card, car.handlingName, final);
  };

  select.addEventListener('change', recompute);
  $$('.mode-btn', card).forEach((b) => b.addEventListener('click', () => {
    $$('.mode-btn', card).forEach((x) => x.classList.remove('is-active'));
    b.classList.add('is-active');
    state.mode = b.dataset.mode;
    recompute();
  }));

  // rename
  wireRename(card, car);

  // áudio custom
  renderAudio(card, car);

  // aplicar
  $('.btn-apply', card).addEventListener('click', () => applyBalance(card, car));

  $('#cars').appendChild(tpl);

  // primeira prévia
  recompute();
}

function renderBars(root, parts) {
  root.innerHTML = '';
  for (const [key, label] of Object.entries(PART_LABELS)) {
    const v = parts[key] || 0;
    const row = document.createElement('div');
    row.className = 'bar-row';
    row.innerHTML =
      `<span class="bn">${label}</span>` +
      `<span class="bar-track"><span class="bar-fill" style="width:${Math.round(v * 100)}%"></span></span>` +
      `<span class="bar-val">${v.toFixed(2)}</span>`;
    root.appendChild(row);
  }
}

// prévia do balanceamento (8 campos) para o tier escolhido
async function loadPreview(card, handling, tier) {
  $('.preview-tier', card).textContent = 'tier ' + tier;
  const body = $('.diff-body', card);
  body.innerHTML = '<tr><td colspan="4" class="fname">calculando…</td></tr>';
  try {
    const data = await api('POST', '/api/preview', { handlingName: handling, tier });
    body.innerHTML = '';
    for (const f of data.fields) {
      const tr = document.createElement('tr');
      const from = f.from == null ? '—' : (+f.from).toFixed(3).replace(/\.?0+$/, '');
      const to = (+f.to).toFixed(3).replace(/\.?0+$/, '');
      if (f.missing) tr.className = 'same';
      else if (!f.changed) tr.className = 'same';
      else if (f.from != null && f.to > f.from) tr.className = 'up';
      else if (f.from != null && f.to < f.from) tr.className = 'down';
      tr.innerHTML =
        `<td class="fname">${FIELD_LABELS[f.field] || f.field}${f.missing ? ' <em>(ausente)</em>' : ''}</td>` +
        `<td class="v-from">${from}</td><td class="arrow">→</td><td class="v-to">${to}</td>`;
      body.appendChild(tr);
    }
    const warn = $('.preview-warn', card);
    warn.textContent = data.clampInfo
      ? `Atenção: força motriz fora da banda do tier — limitada de ${data.clampInfo.raw.toFixed(3)} para ${data.clampInfo.clamped.toFixed(3)}.`
      : '';
  } catch (e) {
    body.innerHTML = `<tr><td colspan="4" class="fname">erro: ${e.message}</td></tr>`;
  }
}


// ============================================================
// RENAME
// ============================================================

function wireRename(card, car) {
  const panel = $('.rename-panel', card);
  const input = $('.rename-input', card);
  const btnPreview = $('.btn-rename-preview', card);
  const btnApply = $('.btn-rename-apply', card);
  const result = $('.rename-result', card);

  $('.btn-rename', card).addEventListener('click', () => {
    panel.hidden = !panel.hidden;
    if (!panel.hidden && !input.value) input.value = car.model;
  });

  btnPreview.addEventListener('click', async () => {
    result.innerHTML = 'gerando prévia…';
    btnApply.disabled = true;
    try {
      const p = await api('POST', '/api/rename',
        { handlingName: car.handlingName, newName: input.value, execute: false });
      result.innerHTML = renderRenamePreview(p);
      btnApply.disabled = !p.valid;
      btnApply.dataset.ready = p.valid ? '1' : '';
    } catch (e) {
      result.innerHTML = `<div class="rn-warn">erro: ${e.message}</div>`;
    }
  });

  btnApply.addEventListener('click', async () => {
    if (!confirm(`Renomear "${car.model}" para "${input.value}" em todos os arquivos? ` +
                 `Um backup será criado automaticamente.`)) return;
    result.innerHTML = 'renomeando…';
    try {
      const r = await api('POST', '/api/rename',
        { handlingName: car.handlingName, newName: input.value, execute: true });
      toast(`Renomeado para "${r.newName}" (${r.metasWritten.length} metas, ${r.assetsRenamed.length} assets). ` +
            `Backup: ${r.backupId}.`, 'ok');
      result.innerHTML = `<div class="rn-sum">Pronto. ${r.note}</div>`;
      setTimeout(reload, 900);
    } catch (e) {
      result.innerHTML = `<div class="rn-warn">erro: ${e.message}</div>`;
    }
  });
}

function renderRenamePreview(p) {
  let html = '';
  if (p.warnings && p.warnings.length) {
    html += p.warnings.map((w) => `<div class="rn-warn">⚠ ${w}</div>`).join('');
  }
  for (const mc of p.metaChanges) {
    html += `<div class="rn-file">${mc.file} — ${mc.count} ocorrência(s)</div>`;
    for (const l of mc.lines.slice(0, 4)) {
      html += `<div class="rn-line">L${l.n}: ${esc(l.before)} → <b>${esc(l.after)}</b></div>`;
    }
    if (mc.lines.length > 4) html += `<div class="rn-line">… +${mc.lines.length - 4} linha(s)</div>`;
  }
  html += `<div class="rn-sum">Assets a renomear: <b>${p.assetRenames.length}</b> arquivo(s). ` +
          `handlingName: ${p.oldName} → <b>${p.newHandlingName}</b></div>`;
  return html;
}


// ============================================================
// ÁUDIO CUSTOM (detecção + conserto)
// ============================================================

function renderAudio(card, car) {
  const au = car.audio || {};
  const panel = $('.audio', card);
  const statusEl = $('.audio-status', card);
  const body = $('.audio-body', card);
  const actions = $('.audio-actions', card);

  if (!au.custom) {
    // som nativo: mostra discreto só se houver hash
    if (au.audioNameHash) {
      panel.hidden = false;
      statusEl.textContent = 'som nativo';
      statusEl.className = 'audio-status native';
      body.innerHTML = `Usa o som nativo do GTA (<span class="a-name">${esc(au.audioNameHash)}</span>). Nada a fazer.`;
    }
    return;
  }

  panel.hidden = false;
  if (au.status === 'ok') {
    statusEl.textContent = '✓ OK';
    statusEl.className = 'audio-status ok';
    body.innerHTML = `Som próprio consistente (nome interno: <span class="a-name">${esc(au.canonical)}</span>).`;
    return;
  }

  // quebrado
  statusEl.textContent = '⚠ precisa de conserto';
  statusEl.className = 'audio-status broken';
  body.innerHTML =
    `Este carro tem som próprio com nome interno <span class="a-name">${esc(au.canonical || '?')}</span>, ` +
    `mas os arquivos foram renomeados e não batem mais. Por isso o som não toca.` +
    au.problems.map((p) => `<div class="a-prob">• ${esc(p)}</div>`).join('') +
    `<div class="a-note">O conserto alinha os nomes dos arquivos + fxmanifest ao nome real do ` +
    `áudio (do binário). Não recompila nada; o nome interno do som não muda (é invisível em jogo).</div>`;
  actions.hidden = false;

  const btnPreview = $('.btn-audio-preview', card);
  const btnFix = $('.btn-audio-fix', card);
  const result = $('.audio-result', card);

  btnPreview.addEventListener('click', async () => {
    result.innerHTML = 'gerando prévia…'; btnFix.disabled = true;
    try {
      const p = await api('POST', '/api/audio-fix', { handlingName: car.handlingName, execute: false });
      if (!p.applicable) { result.innerHTML = `<div class="a-note">${esc(p.reason)}</div>`; return; }
      let html = `<div class="ar-ok">Alvo: <b>${esc(p.canonical)}</b></div>`;
      for (const r of p.fileRenames) html += `<div class="ar-line">${esc(r.from)} → <b>${esc(r.to)}</b></div>`;
      if (p.manifestEdits.length) html += `<div class="ar-line">fxmanifest: ${p.manifestEdits[0].lines.length} linha(s) ajustada(s)</div>`;
      if (p.hashEdit) html += `<div class="ar-line">audioNameHash: ${esc(p.hashEdit.from)} → <b>${esc(p.hashEdit.to)}</b></div>`;
      result.innerHTML = html;
      btnFix.disabled = false;
    } catch (e) { result.innerHTML = `<div class="a-prob">erro: ${esc(e.message)}</div>`; }
  });

  btnFix.addEventListener('click', async () => {
    if (!confirm(`Consertar o áudio de "${car.handlingNameRaw}"? Backup automático será criado.`)) return;
    result.innerHTML = 'consertando…';
    try {
      const r = await api('POST', '/api/audio-fix', { handlingName: car.handlingName, execute: true });
      toast(`Áudio consertado (${r.renamed.length} arquivo(s) alinhados a "${r.canonical}"). Backup: ${r.backupId}.`, 'ok');
      result.innerHTML = `<div class="ar-ok">✓ pronto — o som deve tocar agora.</div>`;
      setTimeout(reload, 900);
    } catch (e) { result.innerHTML = `<div class="a-prob">erro: ${esc(e.message)}</div>`; }
  });
}


// ============================================================
// APLICAR BALANCEAMENTO
// ============================================================

async function applyBalance(card, car) {
  const state = cardState.get(card);
  const final = state.final;
  const out = $('.apply-result', card);
  if (!confirm(`Aplicar tier ${final} em "${car.handlingNameRaw}"? ` +
               `Backup automático + selo serão gerados.`)) return;
  out.textContent = 'aplicando…'; out.className = 'apply-result';
  try {
    const r = await api('POST', '/api/apply',
      { handlingName: car.handlingName, tierBase: final, tierMax: null });
    if (r.ok) {
      out.textContent = `✓ tier ${final} aplicado e selado.`;
      out.className = 'apply-result ok';
      toast(`"${car.handlingNameRaw}" balanceado para tier ${final}.`, 'ok');
    } else {
      out.textContent = `falhou (exit ${r.exitCode})`;
      out.className = 'apply-result err';
    }
  } catch (e) {
    out.textContent = 'erro: ' + e.message;
    out.className = 'apply-result err';
  }
}


// ============================================================
// BOOT
// ============================================================

async function reload() {
  const status = $('#status');
  $('#cars').innerHTML = '';
  cardState.clear();
  status.textContent = 'carregando carros…';
  try {
    const data = await api('GET', '/api/cars');
    status.textContent = data.cars.length
      ? `${data.cars.length} carro(s) encontrado(s).`
      : 'nenhum carro encontrado nos scan-paths (config/scan-paths.json).';
    for (const car of data.cars) renderCar(car, data.tiers || TIER_ORDER);
  } catch (e) {
    status.textContent = 'erro ao carregar: ' + e.message;
  }
}

let toastTimer = null;
function toast(msg, kind) {
  const el = $('#toast');
  el.textContent = msg;
  el.className = 'toast ' + (kind || '');
  el.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { el.hidden = true; }, 4200);
}

function esc(s) {
  return String(s).replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));
}

$('#btn-reload').addEventListener('click', reload);
reload();
