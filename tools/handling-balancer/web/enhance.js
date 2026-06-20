// enhance.js — camada de UX/visualização sobre o app.js.
// NÃO altera lógica do app.js. Apenas:
//   • intercepta /api/cars para construir o catálogo (sidebar) e os comparativos
//   • mostra um carro por vez (seleção via sidebar)
//   • injeta gráfico de radar (carro × média × melhor do tier) e barra de score 0–1000
'use strict';

(() => {
  const TIERS = ['D', 'C', 'B', 'A', 'S', 'S+'];
  const tierKey = (t) => (t === 'S+' ? 'Sp' : t);
  const PART_LABELS = {
    accel: 'Acel.', launch: 'Largada', grip: 'Curva',
    brake: 'Freio', stability: 'Estab.',
  };
  const PART_KEYS = Object.keys(PART_LABELS);

  let CARS = [];
  let ACTIVE_HANDLING = null;
  let TIER_FILTER = 'all';
  let SEARCH = '';

  // -----------------------------------------------------------------
  // intercepta fetch para capturar a lista de carros sem tocar no app.js
  // -----------------------------------------------------------------
  const origFetch = window.fetch.bind(window);
  window.fetch = async (input, init) => {
    const res = await origFetch(input, init);
    try {
      const url = typeof input === 'string' ? input : input.url;
      if (url && url.includes('/api/cars') && res.ok) {
        res.clone().json().then((data) => {
          CARS = data.cars || [];
          onCarsLoaded();
        }).catch(() => {});
      }
    } catch (_) {}
    return res;
  };

  // -----------------------------------------------------------------
  // MutationObserver: assim que app.js insere um .card em #cars,
  // enriquecemos com score-meter + radar de comparação.
  // -----------------------------------------------------------------
  const carsRoot = document.getElementById('cars');
  const cardObs = new MutationObserver((muts) => {
    for (const m of muts) {
      m.addedNodes.forEach((n) => {
        if (n.nodeType === 1 && n.classList.contains('card')) {
          decorateCard(n);
        }
      });
    }
    syncActiveCard();
  });
  cardObs.observe(carsRoot, { childList: true });

  // -----------------------------------------------------------------
  // SIDEBAR
  // -----------------------------------------------------------------
  const sbList = document.getElementById('sb-list');
  const sbCount = document.getElementById('sb-count');
  const sbSearch = document.getElementById('sb-search-input');
  const sbTiers = document.getElementById('sb-tiers');
  const sbToggle = document.getElementById('btn-sb-toggle');
  const welcome = document.getElementById('welcome');
  const crCurrent = document.getElementById('cr-current');

  sbSearch.addEventListener('input', () => {
    SEARCH = sbSearch.value.trim().toLowerCase();
    renderSidebar();
  });
  sbTiers.addEventListener('click', (e) => {
    const b = e.target.closest('.sb-tier');
    if (!b) return;
    [...sbTiers.children].forEach((x) => x.classList.remove('is-active'));
    b.classList.add('is-active');
    TIER_FILTER = b.dataset.tier;
    renderSidebar();
  });
  sbToggle.addEventListener('click', () => {
    document.body.classList.toggle('sb-open');
  });

  function onCarsLoaded() {
    renderSidebar();
    renderWelcomeStats();
  }

  function filteredCars() {
    return CARS.filter((c) => {
      if (TIER_FILTER !== 'all' && c.calculatedTier !== TIER_FILTER) return false;
      if (!SEARCH) return true;
      const s = SEARCH;
      return (c.handlingNameRaw || '').toLowerCase().includes(s)
          || (c.model || '').toLowerCase().includes(s)
          || (c.carFolder || '').toLowerCase().includes(s);
    });
  }

  function renderSidebar() {
    const list = filteredCars();
    sbCount.textContent = list.length;
    sbList.innerHTML = '';
    if (!list.length) {
      sbList.innerHTML = '<li class="sb-empty">nenhum carro encontrado</li>';
      return;
    }
    // ordena por tier desc, depois por score desc
    list.sort((a, b) => {
      const ti = TIERS.indexOf(b.calculatedTier) - TIERS.indexOf(a.calculatedTier);
      return ti !== 0 ? ti : (b.score || 0) - (a.score || 0);
    });
    for (const car of list) {
      const li = document.createElement('li');
      li.className = 'sb-item';
      li.dataset.handling = car.handlingName;
      if (car.handlingName === ACTIVE_HANDLING) li.classList.add('is-active');
      const tier = car.calculatedTier;
      const pct = Math.max(0, Math.min(100, Math.round((car.score || 0) / 10)));
      li.innerHTML = `
        <span class="sbi-badge tier-badge t-${tierKey(tier)}">${tier}</span>
        <div class="sbi-main">
          <div class="sbi-name" title="${esc(car.handlingNameRaw)}">${esc(car.handlingNameRaw)}</div>
          <div class="sbi-meta">
            <span class="sbi-dt">${esc((car.drivetrain || '').toUpperCase())}</span>
            <span class="sbi-dot">·</span>
            <span class="sbi-score">${car.score || 0}<small>/1000</small></span>
          </div>
          <div class="sbi-bar"><span style="width:${pct}%"></span></div>
        </div>
      `;
      li.addEventListener('click', () => selectCar(car.handlingName));
      sbList.appendChild(li);
    }
  }

  function selectCar(handling) {
    ACTIVE_HANDLING = handling;
    document.body.classList.add('has-selection');
    document.body.classList.remove('sb-open');
    [...sbList.querySelectorAll('.sb-item')].forEach((el) => {
      el.classList.toggle('is-active', el.dataset.handling === handling);
    });
    syncActiveCard();
  }

  function syncActiveCard() {
    const cards = [...carsRoot.querySelectorAll('.card')];
    if (!cards.length) return;
    // se nada selecionado, seleciona o primeiro do catálogo filtrado
    if (!ACTIVE_HANDLING) {
      const first = filteredCars()[0];
      if (first) {
        ACTIVE_HANDLING = first.handlingName;
        document.body.classList.add('has-selection');
        [...sbList.querySelectorAll('.sb-item')].forEach((el) => {
          el.classList.toggle('is-active', el.dataset.handling === ACTIVE_HANDLING);
        });
      }
    }
    let found = false;
    cards.forEach((c) => {
      const active = c.dataset.handling === ACTIVE_HANDLING;
      c.classList.toggle('is-active', active);
      if (active) {
        found = true;
        const car = CARS.find((x) => x.handlingName === ACTIVE_HANDLING);
        if (car) crCurrent.textContent = car.handlingNameRaw;
      }
    });
    if (!found && cards.length) {
      cards[0].classList.add('is-active');
      ACTIVE_HANDLING = cards[0].dataset.handling;
      const car = CARS.find((x) => x.handlingName === ACTIVE_HANDLING);
      if (car) crCurrent.textContent = car.handlingNameRaw;
    }
  }

  // -----------------------------------------------------------------
  // CARD DECORATION (score-meter + radar)
  // -----------------------------------------------------------------
  function decorateCard(card) {
    // espera até CARS estar disponível
    const tryDecorate = () => {
      const car = CARS.find((c) => c.handlingName === card.dataset.handling);
      if (!car) { setTimeout(tryDecorate, 50); return; }
      drawScoreMeter(card, car);
      drawRadar(card, car);
    };
    tryDecorate();
  }

  // -----------------------------------------------------------------
  // SCORE METER 0–1000
  // -----------------------------------------------------------------
  function drawScoreMeter(card, car) {
    const meter = card.querySelector('[data-score-meter]');
    if (!meter) return;
    const cursor = meter.querySelector('[data-sm-cursor]');
    const peersWrap = meter.querySelector('[data-sm-peers]');
    const score = Math.max(0, Math.min(1000, car.score || 0));
    cursor.style.left = (score / 10) + '%';
    cursor.dataset.score = score;
    cursor.setAttribute('title', `${score} / 1000`);
    // marca pontos dos outros carros do mesmo tier
    peersWrap.innerHTML = '';
    const peers = CARS.filter((c) => c.calculatedTier === car.calculatedTier
                                  && c.handlingName !== car.handlingName);
    for (const p of peers) {
      const dot = document.createElement('span');
      dot.className = 'sm-peer';
      dot.style.left = ((p.score || 0) / 10) + '%';
      dot.title = `${esc(p.handlingNameRaw)} · ${p.score}`;
      peersWrap.appendChild(dot);
    }
  }

  // -----------------------------------------------------------------
  // RADAR (SVG) — carro × média × melhor do mesmo tier
  // -----------------------------------------------------------------
  function drawRadar(card, car) {
    const host = card.querySelector('[data-cmp-radar]');
    const hint = card.querySelector('[data-cmp-hint]');
    const peersBox = card.querySelector('[data-cmp-peers]');
    if (!host) return;

    const tierPeers = CARS.filter((c) => c.calculatedTier === car.calculatedTier);
    const others = tierPeers.filter((c) => c.handlingName !== car.handlingName);

    if (hint) {
      hint.textContent = others.length
        ? `vs ${others.length} carro(s) tier ${car.calculatedTier}`
        : `único no tier ${car.calculatedTier}`;
    }

    const self = PART_KEYS.map((k) => clamp01(car.parts?.[k] || 0));
    const avg = PART_KEYS.map((k) => {
      if (!tierPeers.length) return 0;
      return tierPeers.reduce((s, c) => s + (c.parts?.[k] || 0), 0) / tierPeers.length;
    });
    const best = PART_KEYS.map((k) =>
      tierPeers.reduce((m, c) => Math.max(m, c.parts?.[k] || 0), 0));

    const size = 260, cx = size / 2, cy = size / 2, R = 96;
    const N = PART_KEYS.length;
    const ang = (i) => -Math.PI / 2 + (i * 2 * Math.PI) / N;
    const pt = (i, v) => {
      const r = R * v;
      return [cx + r * Math.cos(ang(i)), cy + r * Math.sin(ang(i))];
    };
    const polygon = (arr) => arr.map((v, i) => pt(i, v).join(',')).join(' ');

    // grades concêntricas
    let grid = '';
    for (let g = 1; g <= 4; g++) {
      const f = g / 4;
      const poly = PART_KEYS.map((_, i) => pt(i, f).join(',')).join(' ');
      grid += `<polygon points="${poly}" class="rg-grid" />`;
    }
    // eixos + rótulos
    let axes = '';
    for (let i = 0; i < N; i++) {
      const [x, y] = pt(i, 1);
      axes += `<line x1="${cx}" y1="${cy}" x2="${x}" y2="${y}" class="rg-axis"/>`;
      const [lx, ly] = pt(i, 1.18);
      axes += `<text x="${lx}" y="${ly}" class="rg-label" text-anchor="middle">${PART_LABELS[PART_KEYS[i]]}</text>`;
    }
    // pontos do self
    let selfDots = '';
    self.forEach((v, i) => {
      const [x, y] = pt(i, v);
      selfDots += `<circle cx="${x}" cy="${y}" r="3.5" class="rg-dot is-self"/>`;
    });

    host.innerHTML = `
      <svg viewBox="0 0 ${size} ${size}" class="rg-svg" role="img" aria-label="Radar de comparação">
        <g>${grid}</g>
        <g>${axes}</g>
        <polygon points="${polygon(avg)}"  class="rg-poly is-avg"/>
        <polygon points="${polygon(best)}" class="rg-poly is-best"/>
        <polygon points="${polygon(self)}" class="rg-poly is-self"/>
        ${selfDots}
      </svg>
    `;

    // mini-tabela de peers (top 4 por score)
    peersBox.innerHTML = '';
    if (!others.length) {
      peersBox.innerHTML = `<div class="cmp-empty">Sem outros carros tier ${car.calculatedTier} para comparar.</div>`;
      return;
    }
    const top = [...others].sort((a, b) => (b.score || 0) - (a.score || 0)).slice(0, 5);
    const table = document.createElement('div');
    table.className = 'cmp-peers-list';
    table.innerHTML = `<div class="cpl-head"><span>Outros do tier ${car.calculatedTier}</span><span>score</span></div>` +
      top.map((p) => {
        const delta = (p.score || 0) - (car.score || 0);
        const sign = delta > 0 ? '▲' : delta < 0 ? '▼' : '·';
        const cls = delta > 0 ? 'up' : delta < 0 ? 'down' : 'same';
        return `<div class="cpl-row">
            <span class="cpl-name" title="${esc(p.handlingNameRaw)}">${esc(p.handlingNameRaw)}</span>
            <span class="cpl-score">${p.score || 0}<small class="${cls}"> ${sign} ${Math.abs(delta)}</small></span>
          </div>`;
      }).join('');
    peersBox.appendChild(table);
  }

  // -----------------------------------------------------------------
  // welcome stats (overview de frota)
  // -----------------------------------------------------------------
  function renderWelcomeStats() {
    const host = document.getElementById('welcome-stats');
    if (!host) return;
    const byTier = {};
    for (const t of TIERS) byTier[t] = 0;
    for (const c of CARS) if (byTier[c.calculatedTier] != null) byTier[c.calculatedTier]++;
    host.innerHTML = `
      <div class="ws-total">
        <span class="ws-num">${CARS.length}</span>
        <span class="ws-label">carros na frota</span>
      </div>
      <div class="ws-tiers">
        ${TIERS.map((t) => `
          <div class="ws-tier">
            <span class="tier-badge t-${tierKey(t)}">${t}</span>
            <span class="ws-tier-n">${byTier[t]}</span>
          </div>`).join('')}
      </div>
    `;
  }

  // -----------------------------------------------------------------
  // utils
  // -----------------------------------------------------------------
  function clamp01(v) { return Math.max(0, Math.min(1, v)); }
  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({
      '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
    }[c]));
  }
})();
