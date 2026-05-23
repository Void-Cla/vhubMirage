// nui/js/actions.js — renderiza grids de ações a partir de App.state.actions
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
    heal: 'Curar', healall: 'Curar todos',
    god: 'Invencível', freeze: 'Congelar',
    revive: 'Reviver', reviveall: 'Reviver todos',
    invis: 'Invisível', skin: 'Trocar aparência',
    spec: 'Espectar', kill: 'Matar',
    spawncar: 'Spawnar veículo', delveh: 'Deletar veículo',
    fix: 'Reparar veículo', tuning: 'Aplicar tuning', carcolor: 'Cor RGB',
    weather: 'Clima', time: 'Horário', blackout: 'Apagão',
    clearzone: 'Limpar área', announce: 'Anunciar', staffchat: 'Chat da equipe',
    givemoney: 'Dar dinheiro', setmoney: 'Definir saldo',
    giveitem: 'Dar item', clearinv: 'Limpar inventário',
    addgroup: 'Adicionar grupo', delgroup: 'Remover grupo',
    rg: 'Ver ficha', coords: 'Coordenadas', pon: 'Listar jogadores',
    reports: 'Denúncias',
  };

  App.renderActions = () => {
    document.querySelectorAll('.action-grid').forEach(grid => {
      const cat = grid.dataset.cat;
      grid.innerHTML = '';
      Object.entries(App.state.actions || {}).forEach(([key, a]) => {
        if (a.cat !== cat) return;
        const el = document.createElement('div');
        el.className = 'act-btn' + (a.dangerous ? ' dangerous' : '');
        el.innerHTML = `<span class="nm">${PT_LABEL[key] || key}</span><span class="dc">${a.desc}</span>`;
        el.onclick = () => trigger(key, a);
        grid.appendChild(el);
      });
    });
  };

  async function trigger(key, a) {
    if (!a.fields || a.fields.length === 0) {
      if (a.dangerous) {
        const r = await App.modal({ title: 'Confirmar', text: `Executar: ${a.desc}?` });
        if (!r.ok) return;
      }
      App.post('act', { action: key, fields: {} });
      return;
    }
    const labels = {
      target: 'Alvo (ID)', uid: 'UID', reason: 'Motivo', message: 'Mensagem',
      minutes: 'Minutos', x: 'X', y: 'Y', z: 'Z', h: 'Direção',
      model: 'Modelo', r: 'R (0-255)', g: 'G (0-255)', b: 'B (0-255)',
      wx: 'Clima', hour: 'Hora', minute: 'Minuto',
      amount: 'Valor (R$)', rota: 'Rota (banco/wallet)',
      item: 'Item', qty: 'Quantidade',
      group: 'Grupo', radius: 'Raio (m)', notes: 'Observações',
      id: 'ID da denúncia',
    };
    const types = {
      target: 'number', uid: 'number', minutes: 'number',
      x: 'number', y: 'number', z: 'number', h: 'number',
      r: 'number', g: 'number', b: 'number',
      hour: 'number', minute: 'number',
      amount: 'number', qty: 'number', radius: 'number', id: 'number',
    };
    const html = a.fields.map(f => {
      const lbl = labels[f] || f;
      const tp  = types[f]  || 'text';
      return f === 'message' || f === 'notes'
        ? `<label>${lbl}</label><textarea data-field="${f}" maxlength="500"></textarea>`
        : `<label>${lbl}</label><input data-field="${f}" type="${tp}">`;
    }).join('');
    const res = await App.modal({
      title: a.desc, html,
      okText: a.dangerous ? 'Confirmar ação' : 'Executar',
    });
    if (!res.ok) return;
    App.post('act', { action: key, fields: res.fields });
  }
})();
