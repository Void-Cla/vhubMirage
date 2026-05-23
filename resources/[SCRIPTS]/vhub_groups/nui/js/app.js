// nui/js/app.js — vhub_groups
// L-D8: NUI nao decide regra. Toda mutacao e relay para o servidor via callback.
// Estado local apenas para render — refletir snapshots do servidor.

(() => {
  // ─── Estado ────────────────────────────────────────────────────────────────

  const state = {
    open: false,
    catalog: [],            // [{ id, label, type, color, icon, levels, max_level }]
    players: [],            // [{ src, char_id, owner, name, groups: [{id,level,...}] }]
    catalogById: {},        // index por id (lazy)
    owner_char_id: 1,
    activeTab: 'players',
    filterPlayers: '',
    filterCatalog: '',
    modal: { target: null, group: null, level: 1, days: 0, reason: '' },
  };

  // ─── Util ──────────────────────────────────────────────────────────────────

  const $  = (sel) => document.querySelector(sel);
  const $$ = (sel) => document.querySelectorAll(sel);
  const el = (tag, attrs, ...children) => {
    const e = document.createElement(tag);
    if (attrs) for (const [k, v] of Object.entries(attrs)) {
      if (k === 'class') e.className = v;
      else if (k === 'html') e.innerHTML = v;
      else if (k.startsWith('on') && typeof v === 'function') e.addEventListener(k.slice(2), v);
      else if (k.startsWith('data-')) e.setAttribute(k, v);
      else e[k] = v;
    }
    for (const c of children) {
      if (c == null) continue;
      e.appendChild(typeof c === 'string' ? document.createTextNode(c) : c);
    }
    return e;
  };

  const escape = (s) => String(s == null ? '' : s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

  const fmtDate = (unix) => {
    if (!unix) return '—';
    const d = new Date(unix * 1000);
    return d.toLocaleString('pt-BR', {
      day: '2-digit', month: '2-digit', year: 'numeric',
      hour: '2-digit', minute: '2-digit',
    });
  };

  const fmtDateRel = (unix) => {
    if (!unix) return '—';
    const diff = Math.floor(Date.now() / 1000) - unix;
    if (diff < 60)        return `${diff}s atrás`;
    if (diff < 3600)      return `${Math.floor(diff / 60)}min atrás`;
    if (diff < 86400)     return `${Math.floor(diff / 3600)}h atrás`;
    return fmtDate(unix);
  };

  const POST = (cb, data) =>
    fetch(`https://${GetParentResourceName ? GetParentResourceName() : 'vhub_groups'}/${cb}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data || {}),
    }).then((r) => r.json().catch(() => ({}))).catch(() => ({}));

  function toast(message, kind = 'info') {
    const t = el('div', { class: `vh-toast ${kind}` }, message);
    $('#toast-stack').appendChild(t);
    setTimeout(() => {
      t.classList.add('fade-out');
      setTimeout(() => t.remove(), 250);
    }, 3500);
  }

  // ─── Index do catalog ──────────────────────────────────────────────────────

  function reindexCatalog() {
    state.catalogById = {};
    for (const g of state.catalog) state.catalogById[g.id] = g;
  }

  // ─── Render: Jogadores ─────────────────────────────────────────────────────

  function renderPlayers() {
    const grid = $('#players-grid');
    const filter = (state.filterPlayers || '').trim().toLowerCase();
    let list = state.players;
    if (filter) {
      list = list.filter((p) =>
        String(p.name).toLowerCase().includes(filter) ||
        String(p.src).includes(filter) ||
        String(p.char_id).includes(filter)
      );
    }
    $('#players-count').textContent = list.length;
    $('#hdr-online').textContent = state.players.length;
    grid.innerHTML = '';

    if (list.length === 0) {
      grid.appendChild(el('div', { class: 'vh-empty' },
        el('i', { class: 'fa-solid fa-users-slash' }),
        'Nenhum jogador online corresponde ao filtro.'
      ));
      return;
    }

    for (const p of list) {
      grid.appendChild(renderPlayerCard(p));
    }
  }

  function renderPlayerCard(p) {
    const card = el('div', { class: 'vh-card vh-player' + (p.owner ? ' is-owner' : '') });

    const head = el('div', { class: 'vh-player-head' });
    head.appendChild(el('div', null,
      el('div', { class: 'vh-player-name' },
        p.owner ? el('i', { class: 'fa-solid fa-crown crown' }) : null,
        p.name
      ),
      el('div', { class: 'vh-player-meta' },
        'ID ', el('b', null, String(p.src)),
        ' · char_id ', el('b', null, String(p.char_id))
      )
    ));
    head.appendChild(el('button', {
      class: 'vh-btn primary small',
      onclick: () => openModalAdd(p),
    }, el('i', { class: 'fa-solid fa-plus' }), 'Adicionar'));

    card.appendChild(head);

    const groups = el('div', { class: 'vh-player-groups' });
    if (!p.groups || p.groups.length === 0) {
      groups.appendChild(el('span', { class: 'vh-player-empty' }, 'Sem grupos atribuídos.'));
    } else {
      for (const g of p.groups) {
        groups.appendChild(renderGroupChip(p, g));
      }
    }
    card.appendChild(groups);

    return card;
  }

  function renderGroupChip(player, g) {
    const def  = state.catalogById[g.id] || {};
    const color = def.color || '#d9c19a';
    const icon  = def.icon  || 'fa-solid fa-user';

    const chip = el('div', { class: 'vh-group-chip' });
    chip.style.borderColor = color + '55';
    chip.appendChild(el('i', { class: icon }));
    chip.appendChild(document.createTextNode(g.label || g.id));
    chip.appendChild(el('span', { class: 'lvl' }, 'N' + g.level));

    if (g.expires_at_unix) {
      const exp = el('span', { class: 'vh-player-meta', title: 'Expira em ' + fmtDate(g.expires_at_unix) },
        el('i', { class: 'fa-solid fa-hourglass' }));
      chip.appendChild(exp);
    }

    chip.appendChild(el('button', {
      class: 'x',
      title: 'Editar nível',
      onclick: () => openModalEdit(player, g),
    }, el('i', { class: 'fa-solid fa-pen' })));
    chip.appendChild(el('button', {
      class: 'x',
      title: 'Remover grupo',
      onclick: () => confirmRemove(player, g),
    }, el('i', { class: 'fa-solid fa-trash' })));
    return chip;
  }

  // ─── Render: Catalogo ──────────────────────────────────────────────────────

  function renderCatalog() {
    const grid = $('#catalog-grid');
    const filter = (state.filterCatalog || '').trim().toLowerCase();
    let list = state.catalog;
    if (filter) {
      list = list.filter((g) =>
        g.id.toLowerCase().includes(filter) ||
        String(g.label).toLowerCase().includes(filter) ||
        String(g.type).toLowerCase().includes(filter)
      );
    }
    $('#catalog-count').textContent = list.length;
    grid.innerHTML = '';

    if (list.length === 0) {
      grid.appendChild(el('div', { class: 'vh-empty' },
        el('i', { class: 'fa-solid fa-folder-open' }),
        'Nenhum grupo no catálogo corresponde ao filtro.'
      ));
      return;
    }

    for (const g of list) grid.appendChild(renderCatalogCard(g));
  }

  function renderCatalogCard(g) {
    const card = el('div', { class: 'vh-card vh-cat' });

    const head = el('div', { class: 'vh-cat-head' });
    const icon = el('div', { class: 'vh-cat-icon' }, el('i', { class: g.icon || 'fa-solid fa-user' }));
    icon.style.color = g.color || 'var(--vh-gold)';
    head.appendChild(icon);
    head.appendChild(el('div', null,
      el('div', { class: 'vh-cat-title' }, g.label),
      el('span', { class: 'vh-cat-type' }, g.type || 'system')
    ));
    head.appendChild(el('div', { class: 'vh-cat-id' }, g.id));
    card.appendChild(head);

    const levels = el('div', { class: 'vh-cat-levels' });
    for (const l of g.levels || []) {
      const row = el('div', { class: 'vh-cat-level' });
      row.appendChild(el('span', { class: 'vh-cat-level-num' }, 'N' + l.level));
      const body = el('div', { class: 'vh-cat-level-body' });
      body.appendChild(el('strong', null, l.label));
      if (l.permissions && l.permissions.length) {
        body.appendChild(el('span', { class: 'vh-cat-level-perms' }, l.permissions.join(' · ')));
      }
      row.appendChild(body);
      levels.appendChild(row);
    }
    card.appendChild(levels);

    return card;
  }

  // ─── Render: Auditoria ─────────────────────────────────────────────────────

  function renderAudit(rows) {
    const tbody = $('#audit-tbody');
    tbody.innerHTML = '';
    if (!Array.isArray(rows) || rows.length === 0) {
      const tr = el('tr', null,
        el('td', { class: 'vh-table-empty', colspan: 7 }, 'Nenhum registro encontrado.'));
      tbody.appendChild(tr);
      return;
    }
    for (const r of rows) {
      tbody.appendChild(el('tr', null,
        el('td', { class: 'when',   title: fmtDate(r.created_unix) }, fmtDateRel(r.created_unix)),
        el('td', { class: 'action' }, r.action || ''),
        el('td', { class: 'actor'  }, String(r.actor_char_id || 0)),
        el('td', { class: 'target' }, String(r.target_char_id || 0)),
        el('td', { class: 'group'  }, r.group_id || ''),
        el('td', { class: 'level'  }, r.level > 0 ? String(r.level) : '—'),
        el('td', { class: 'reason', title: r.reason || '' }, r.reason || '')
      ));
    }
  }

  // ─── Render: Sistema ───────────────────────────────────────────────────────

  function renderSystem(data) {
    if (!data) return;
    $('#sys-sql').textContent     = data.sql_ready ? 'ONLINE' : 'OFFLINE';
    $('#sys-core').textContent    = data.core_ready ? 'PRONTO' : 'CARREGANDO';
    $('#sys-entries').textContent = data.cache?.entries || 0;
    $('#sys-hits').textContent    = data.cache?.metrics?.hits || 0;
    $('#sys-misses').textContent  = data.cache?.metrics?.misses || 0;
    $('#sys-invals').textContent  = data.cache?.metrics?.invalidations || 0;
    $('#sys-owner').textContent   = '#' + (data.owner_char_id || 1);
    $('#sys-cron').textContent    = ((data.expire_interval_ms || 0) / 1000) + 's';
  }

  // ─── Modal ────────────────────────────────────────────────────────────────

  function fillGroupSelect() {
    const sel = $('#modal-group');
    sel.innerHTML = '';
    for (const g of state.catalog) {
      const opt = el('option', { value: g.id }, `${g.label}  [${g.type}]`);
      sel.appendChild(opt);
    }
  }

  function fillLevelSelect(group_id) {
    const sel = $('#modal-level');
    sel.innerHTML = '';
    const def = state.catalogById[group_id];
    if (!def) return;
    for (const l of def.levels || []) {
      const opt = el('option', { value: l.level }, `N${l.level} — ${l.label}`);
      sel.appendChild(opt);
    }
  }

  function openModalAdd(player) {
    state.modal = { target: player, group: null, level: 1, days: 0, reason: '', editing: null };
    $('#modal-title').textContent = 'Adicionar grupo';
    $('#modal-target').textContent =
      `${player.name} · ID ${player.src} · char_id ${player.char_id}`;
    fillGroupSelect();
    const first = state.catalog[0];
    if (first) {
      $('#modal-group').value = first.id;
      fillLevelSelect(first.id);
    }
    $('#modal-days').value = '';
    $('#modal-reason').value = '';
    $('#modal-edit').classList.remove('hidden');
  }

  function openModalEdit(player, group) {
    state.modal = {
      target: player,
      group: group.id,
      level: group.level,
      days: 0,
      reason: '',
      editing: group,
    };
    $('#modal-title').textContent = `Editar nível — ${group.label || group.id}`;
    $('#modal-target').textContent =
      `${player.name} · ID ${player.src} · char_id ${player.char_id}`;
    fillGroupSelect();
    $('#modal-group').value = group.id;
    $('#modal-group').disabled = true;
    fillLevelSelect(group.id);
    $('#modal-level').value = group.level;
    $('#modal-days').value = '';
    $('#modal-reason').value = '';
    $('#modal-edit').classList.remove('hidden');
  }

  function closeModal() {
    $('#modal-edit').classList.add('hidden');
    $('#modal-group').disabled = false;
  }

  function confirmRemove(player, group) {
    if (!confirm(`Remover grupo "${group.label || group.id}" de ${player.name}?`)) return;
    POST('remove_group', {
      target_char_id: player.char_id,
      group_id: group.id,
      reason: 'panel_remove',
    });
  }

  function saveModal() {
    const m = state.modal;
    if (!m.target) return;
    const group_id = $('#modal-group').value;
    const level    = parseInt($('#modal-level').value, 10) || 1;
    const days     = parseInt($('#modal-days').value, 10) || 0;
    const reason   = $('#modal-reason').value || 'panel_edit';

    if (m.editing) {
      POST('set_level', {
        target_char_id: m.target.char_id,
        group_id,
        level,
        reason,
      });
    } else {
      POST('add_group', {
        target_char_id: m.target.char_id,
        group_id,
        level,
        expires_days: days,
        reason,
      });
    }
    closeModal();
  }

  // ─── Tabs ──────────────────────────────────────────────────────────────────

  function switchTab(name) {
    state.activeTab = name;
    $$('.vh-tab').forEach((t) => t.classList.toggle('active', t.dataset.tab === name));
    $$('.vh-tabpanel').forEach((p) => p.classList.toggle('active', p.dataset.tabpanel === name));
    if (name === 'audit')  POST('audit',  {});
    if (name === 'system') POST('status', {});
  }

  // ─── Mensagens do server ───────────────────────────────────────────────────

  window.addEventListener('message', (e) => {
    const msg = e.data || {};
    switch (msg.action) {
      case 'open': {
        state.open = true;
        const data = msg.data || {};
        state.catalog        = data.catalog || [];
        state.players        = data.players || [];
        state.owner_char_id  = data.owner_char_id || 1;
        reindexCatalog();
        $('#vhub-bg').classList.remove('hidden');
        $('#panel').classList.remove('hidden');
        switchTab('players');
        renderPlayers();
        renderCatalog();
        window.vhubSand && window.vhubSand.start();
        break;
      }
      case 'close': {
        state.open = false;
        $('#panel').classList.add('hidden');
        $('#vhub-bg').classList.add('hidden');
        $('#modal-edit').classList.add('hidden');
        window.vhubSand && window.vhubSand.stop();
        break;
      }
      case 'players': {
        state.players = msg.data || [];
        renderPlayers();
        break;
      }
      case 'result': {
        const r = msg.data || {};
        if (r.ok) {
          toast(`Ação concluída (${r.action}).`, 'success');
        } else {
          toast(`Falha: ${r.err || 'erro desconhecido'}.`, 'error');
        }
        break;
      }
      case 'audit': {
        renderAudit(msg.data || []);
        break;
      }
      case 'status': {
        renderSystem(msg.data || {});
        break;
      }
    }
  });

  // ─── Bindings ──────────────────────────────────────────────────────────────

  document.addEventListener('click', (ev) => {
    const t = ev.target.closest('[data-action], [data-tab]');
    if (!t) return;
    if (t.dataset.tab) { switchTab(t.dataset.tab); return; }
    const action = t.dataset.action;
    if (action === 'close')         POST('close', {});
    if (action === 'refresh')       POST('refresh_players', {});
    if (action === 'modal-close')   closeModal();
    if (action === 'modal-save')    saveModal();
    if (action === 'audit-search')  doAuditSearch();
  });

  document.addEventListener('keydown', (ev) => {
    if (!state.open) return;
    if (ev.key === 'Escape') POST('close', {});
  });

  // Filtros
  document.addEventListener('input', (ev) => {
    if (ev.target.id === 'players-search') {
      state.filterPlayers = ev.target.value;
      renderPlayers();
    } else if (ev.target.id === 'catalog-search') {
      state.filterCatalog = ev.target.value;
      renderCatalog();
    }
  });

  // Mudanca de grupo no modal → repovoa niveis
  document.addEventListener('change', (ev) => {
    if (ev.target.id === 'modal-group') fillLevelSelect(ev.target.value);
  });

  function doAuditSearch() {
    const filters = {};
    const t = parseInt($('#audit-target').value, 10);
    const a = $('#audit-action').value.trim();
    const g = $('#audit-group').value.trim();
    if (t > 0) filters.target_char_id = t;
    if (a)     filters.action = a;
    if (g)     filters.group_id = g;
    POST('audit', filters);
  }
})();
