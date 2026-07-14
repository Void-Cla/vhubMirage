// overlay.js - cards administrativos projetados sobre jogadores proximos
(() => {
  const container = document.getElementById('overlay-container');
  const cards = new Map();
  const snapshots = new Map();
  const money = new Intl.NumberFormat('pt-BR');

  function createCard(src) {
    const card = document.createElement('article');
    card.className = 'pov-card';

    const mugshot = document.createElement('img');
    mugshot.className = 'pov-mugshot';
    mugshot.alt = '';

    const content = document.createElement('div');
    content.className = 'pov-content';

    const charName = document.createElement('div');
    charName.className = 'pov-char';

    const ids = document.createElement('div');
    ids.className = 'pov-ids';

    const playerName = document.createElement('div');
    playerName.className = 'pov-player';

    const registration = document.createElement('div');
    registration.className = 'pov-registration';

    const health = document.createElement('div');
    health.className = 'pov-hp';
    const healthFill = document.createElement('div');
    healthFill.className = 'pov-hp-fill';
    health.appendChild(healthFill);

    const balances = document.createElement('div');
    balances.className = 'pov-balances';

    const groups = document.createElement('div');
    groups.className = 'pov-groups';

    content.append(charName, ids, playerName, registration, health, balances, groups);
    card.append(mugshot, content);
    container.appendChild(card);

    const entry = {
      card, mugshot, charName, ids, playerName, registration,
      healthFill, balances, groups, signature: '',
    };
    cards.set(String(src), entry);
    return entry;
  }

  function updateCard(player) {
    const key = String(player.src);
    const info = snapshots.get(key) || {};
    const entry = cards.get(key) || createCard(player.src);
    entry.card.style.left = `${(Number(player.sx) * 100).toFixed(2)}vw`;
    entry.card.style.top = `${(Number(player.sy) * 100).toFixed(2)}vh`;

    const hp = Math.max(0, Math.min(100, Math.round(Number(player.hp) || 0)));
    entry.healthFill.style.width = `${hp}%`;
    entry.healthFill.dataset.level = hp > 60 ? 'ok' : hp > 30 ? 'warn' : 'danger';

    const signature = JSON.stringify([
      info.uid, info.char_id, info.player_name, info.char_name,
      info.registration, info.wallet, info.bank, player.mugshot, info.groups,
    ]);
    if (entry.signature === signature) return;
    entry.signature = signature;

    entry.charName.textContent = info.char_name || 'Sem identidade';
    entry.ids.textContent = `ID ${player.src} · UID ${info.uid || 0} · CHAR ${info.char_id || 0}`;
    entry.playerName.textContent = info.player_name || '?';
    entry.registration.textContent = info.registration ? `RG ${info.registration}` : 'RG indisponível';
    const wallet = money.format(info.wallet || 0);
    const bank = money.format(info.bank || 0);
    entry.balances.textContent = `Carteira R$ ${wallet} · Banco R$ ${bank}`;

    if (player.mugshot) {
      entry.mugshot.src = player.mugshot;
      entry.mugshot.hidden = false;
    } else {
      entry.mugshot.removeAttribute('src');
      entry.mugshot.hidden = true;
    }

    entry.groups.replaceChildren();
    (Array.isArray(info.groups) ? info.groups : []).slice(0, 3).forEach((group) => {
      const tag = document.createElement('span');
      tag.textContent = typeof group === 'object'
        ? `${group.id || '?'} L${group.level || 1}`
        : String(group);
      entry.groups.appendChild(tag);
    });
  }

  function clearCards() {
    cards.forEach((entry) => entry.card.remove());
    cards.clear();
    snapshots.clear();
  }

  function onMessage(event) {
    const message = event.data || {};
    if (message.action === 'overlayClear') return clearCards();
    if (message.action === 'overlaySnapshot') {
      snapshots.clear();
      (Array.isArray(message.data) ? message.data : []).forEach((info) => {
        if (info && info.src) snapshots.set(String(info.src), info);
      });
      return;
    }
    if (message.action !== 'overlayUpdate') return;

    const seen = new Set();
    (Array.isArray(message.data) ? message.data : []).forEach((player) => {
      if (!player || !player.src) return;
      seen.add(String(player.src));
      updateCard(player);
    });
    cards.forEach((entry, src) => {
      if (!seen.has(src)) {
        entry.card.remove();
        cards.delete(src);
      }
    });
  }

  function destroy() {
    window.removeEventListener('message', onMessage);
    window.removeEventListener('unload', destroy);
    clearCards();
  }

  window.addEventListener('message', onMessage);
  window.addEventListener('unload', destroy);
})();
