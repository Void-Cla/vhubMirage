// actions.js — grade de ações por categoria + modal tipado com seletores
// Seletores no lugar de texto livre: alvo, zona, clima, item, grupo, veículo,
// skin, rota, hora/minuto, cor. Texto livre só onde é semânticamente livre.
(() => {
  const App = window.vhubAdmin;

  // Rótulo visual da ação em PT-BR (sobrepõe a chave inglesa de actions.lua)
  const PT_LABEL = {
    kick: 'Expulsar', ban: 'Banir', unban: 'Desbanir',
    whitelist: 'Aprovar na lista', unwl: 'Remover da lista',
    warn: 'Avisar', jail: 'Prender', unjail: 'Soltar',
    mute: 'Silenciar', unmute: 'Liberar fala',
    tp: 'Ir até o jogador', tptome: 'Trazer jogador', tpgo: 'Ir ao marcador',
    tpcds: 'Ir a coordenadas', tpall: 'Trazer todos', tplast: 'Voltar à posição',
    tpz: 'Ir a local nomeado',
    heal: 'Curar', healall: 'Curar todos',
    god: 'Invencível', freeze: 'Congelar',
    revive: 'Reviver', reviveall: 'Reviver todos',
    invis: 'Invisível', skin: 'Trocar aparência',
    spec: 'Espectar', kill: 'Matar',
    stamina: 'Stamina infinita', jump: 'Super pulo', cleanped: 'Limpar personagem',
    spawncar: 'Spawnar veículo', delveh: 'Deletar veículo',
    fix: 'Reparar veículo', tuning: 'Aplicar tuning', carcolor: 'Cor do veículo',
    boost: 'Boost de motor', flip: 'Desvirar veículo',
    weather: 'Clima', time: 'Horário', blackout: 'Apagão',
    clearzone: 'Limpar área', announce: 'Anunciar', staffchat: 'Chat da equipe',
    wipeveh: 'Wipe veículos', wipeped: 'Wipe NPCs', wipeobj: 'Wipe objetos',
    givemoney: 'Dar dinheiro', setmoney: 'Definir saldo', removemoney: 'Remover dinheiro',
    giveitem: 'Dar item', clearinv: 'Limpar inventário',
    addgroup: 'Adicionar grupo', delgroup: 'Remover grupo',
    rg: 'Ver ficha', coords: 'Coordenadas', pon: 'Listar jogadores',
    reports: 'Denúncias',
  };

  // ============================================================
  // SPECS DE CAMPO — decide o controle certo para cada campo
  // ============================================================

  const playersOpts = () =>
    (App.state.players || []).map(p => ({
      value: p.src, label: `[${p.src}] ${p.name}`,
    }));

  const pick = (kind) => (App.state.pickers?.[kind]) || [];

  // spec do campo por nome (contextual à ação p/ campos ambíguos como model)
  function fieldSpec(fname, actionKey) {
    switch (fname) {
      case 'target':
        return { k: 'target', label: 'Alvo', type: 'player', options: playersOpts() };
      case 'uid':
        return { k: 'uid', label: 'UID do usuário', type: 'number', min: 1 };
      case 'reason':
        return { k: 'reason', label: 'Motivo', type: 'text', maxlen: 180, placeholder: 'motivo da ação' };
      case 'message':
        return { k: 'message', label: 'Mensagem', type: 'textarea', max: 220 };
      case 'minutes': {
        const max = actionKey === 'mute' ? 1440 : 4320;
        return { k: 'minutes', label: `Minutos (5–${max})`, type: 'number', min: 5, max, value: 10 };
      }
      case 'zone':
        return { k: 'zone', label: 'Local', type: 'select', options: App.state.zones || [] };
      case 'weather':
        return { k: 'weather', label: 'Clima', type: 'select', options: App.state.weathers || [] };
      case 'model':
        if (actionKey === 'skin') {
          return { k: 'model', label: 'Modelo de ped', type: 'select', custom: true,
                   options: (App.state.skins || []).map(s => ({ value: s, label: s })),
                   placeholder: 'nome do modelo (ex.: a_m_y_skater_01)' };
        }
        return { k: 'model', label: 'Veículo', type: 'select', custom: true,
                 options: pick('vehicles'),
                 placeholder: 'spawn name (ex.: adder)' };
      case 'item':
        return { k: 'item', label: 'Item', type: 'select', options: pick('items'),
                 placeholder: 'id do item' };
      case 'group':
        return { k: 'group', label: 'Grupo', type: 'select', options: pick('groups'),
                 placeholder: 'id do grupo' };
      case 'rota':
        return { k: 'rota', label: 'Rota', type: 'select', blank: false,
                 options: App.state.routes || [] };
      case 'amount':
        return { k: 'amount', label: 'Valor (R$)', type: 'number', min: 1 };
      case 'qty':
        return { k: 'qty', label: 'Quantidade', type: 'number', min: 1, value: 1 };
      case 'level':
        return { k: 'level', label: 'Nível', type: 'number', min: 1, max: 99, value: 1 };
      case 'days':
        return { k: 'days', label: 'Dias (0 = permanente)', type: 'number', min: 0, max: 3650, value: 0 };
      case 'on':
        return { k: 'on', label: 'Ativar', type: 'checkbox', value: true };
      case 'plate':
        return { k: 'plate', label: 'Placa', type: 'text', maxlen: 8 };
      case 'status':
        return { k: 'status', label: 'Status', type: 'select', options: App.state.statuses || [] };
      case 'hour':
        return { k: 'hour', label: 'Hora', type: 'select', blank: false,
                 options: Array.from({ length: 24 }, (_, i) => ({ value: i, label: String(i).padStart(2, '0') + ':—' })) };
      case 'minute':
        return { k: 'minute', label: 'Minuto', type: 'select', blank: false,
                 options: [0, 15, 30, 45].map(m => ({ value: m, label: String(m).padStart(2, '0') })) };
      case 'color':
        return { k: 'color', label: 'Cor', type: 'color' };
      case 'radius':
        return { k: 'radius', label: 'Raio (m)', type: 'number', min: 50, max: 3000, value: 200 };
      case 'x': return { k: 'x', label: 'X', type: 'number' };
      case 'y': return { k: 'y', label: 'Y', type: 'number' };
      case 'z': return { k: 'z', label: 'Z', type: 'number' };
      case 'h': return { k: 'h', label: 'Direção (0–360, opcional)', type: 'number', min: 0, max: 360 };
      case 'id':    return { k: 'id', label: 'ID da denúncia', type: 'number', min: 1 };
      case 'notes': return { k: 'notes', label: 'Observações', type: 'textarea', max: 220 };
      default:
        return { k: fname, label: fname, type: 'text' };
    }
  }

  // ============================================================
  // DISPARO DA AÇÃO (modal tipado + confirmação de perigo)
  // ============================================================

  async function trigger(key, a) {
    const label = PT_LABEL[key] || key;

    if (!a.fields || a.fields.length === 0) {
      if (a.dangerous) {
        const r = await App.modal({ title: label, text: `Executar: ${a.desc}?`, okText: 'Confirmar ação' });
        if (!r.ok) return;
      }
      App.post('act', { action: key, fields: {} });
      return;
    }

    const specs = a.fields.map(f => fieldSpec(f, key));
    const res = await App.modal({
      title: label,
      text: a.dangerous ? a.desc + ' — esta ação é sensível.' : undefined,
      fields: specs,
      okText: a.dangerous ? 'Confirmar ação' : 'Executar',
    });
    if (!res.ok) return;
    App.post('act', { action: key, fields: res.fields });
  }
  App.triggerAction = trigger;

  // ============================================================
  // RENDER DA GRADE (categoria ativa do topbar + filtro de busca)
  // ============================================================

  const $grid = document.getElementById('action-grid');
  let _query = '';

  function renderGrid() {
    const cat = (App.state.section === 'actions' && App.state.sub) || 'moderation';
    const q = _query.toLowerCase();
    $grid.textContent = '';
    let count = 0;
    Object.entries(App.state.actions || {}).forEach(([key, a]) => {
      if (a.cat !== cat) return;
      const nm = PT_LABEL[key] || key;
      if (q && !nm.toLowerCase().includes(q) && !(a.desc || '').toLowerCase().includes(q)) return;
      const el = App.el('div', 'act-btn' + (a.dangerous ? ' dangerous' : ''));
      el.appendChild(App.el('span', 'nm', nm));
      el.appendChild(App.el('span', 'dc', a.desc));
      el.onclick = () => trigger(key, a);
      $grid.appendChild(el);
      count++;
    });
    if (!count) $grid.appendChild(App.el('div', 'empty-row', 'Nenhuma ação nesta categoria.'));
  }

  App.sectionHooks.actions = () => { _query = ''; renderGrid(); };
  App.searchHooks.actions  = (q) => { _query = q; renderGrid(); };
})();
