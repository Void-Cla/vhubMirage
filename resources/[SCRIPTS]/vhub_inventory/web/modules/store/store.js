// modules/store/store.js — vitrine reutilizável; catálogo e resultado vêm do servidor.
(function () {
  let root, dados, ocupado = false, sequencia = 0;
  function dinheiro(valor) { return 'R$ ' + Number(valor || 0).toLocaleString('pt-BR'); }
  function fechar() { vhub.post('store_close', {}); vhub.unmount('store'); }
  function renderizar() {
    const lista = Array.isArray(dados && dados.itens) ? dados.itens : [];
    root.querySelector('.st-title').textContent = dados.titulo || 'LOJA';
    root.querySelector('.st-subtitle').textContent = dados.subtitulo || '';
    const itens = root.querySelector('.st-items'); itens.replaceChildren();
    for (const item of lista) {
      if (!item || typeof item.id !== 'string' || typeof item.item !== 'string') continue;
      const card = document.createElement('article'); card.className = 'st-item';
      const icone = document.createElement('div'); icone.className = 'st-icon'; vhub.util.applyIcon(icone, item.item);
      const texto = document.createElement('div'); texto.className = 'st-texto';
      const familia = document.createElement('small'); familia.textContent = String(item.familia || 'itens').toUpperCase();
      const nome = document.createElement('strong'); nome.textContent = String(item.nome || item.item);
      const desc = document.createElement('p'); desc.textContent = String(item.descricao || 'Item técnico.');
      texto.append(familia, nome, desc);
      const rodape = document.createElement('footer');
      const preco = document.createElement('span'); preco.textContent = dinheiro(item.preco);
      const qtd = document.createElement('select');
      const max = Math.max(1, Math.min(20, Number(dados.max_quantidade) || 1));
      for (let n = 1; n <= max; n++) { const op = document.createElement('option'); op.value = n; op.textContent = n + 'x'; qtd.appendChild(op); }
      const comprar = document.createElement('button'); comprar.type = 'button'; comprar.disabled = ocupado; comprar.textContent = ocupado ? 'AGUARDE' : 'COMPRAR';
      comprar.addEventListener('click', () => {
        if (ocupado) return;
        ocupado = true; renderizar();
        const request = 'l' + Date.now().toString(36) + '_' + (++sequencia).toString(36);
        vhub.post('store_buy', { token: dados.token, item: item.id, amount: Number(qtd.value), request_id: request });
      });
      rodape.append(preco, qtd, comprar); card.append(icone, texto, rodape); itens.appendChild(card);
    }
  }
  vhub.createModule('store', {
    onInit() {
      vhub.listen('nui:store_open', (mensagem) => { dados = mensagem.data || {}; ocupado = false; if (!vhub.isMounted('store')) vhub.mount('store'); else renderizar(); });
      vhub.listen('nui:store_result', (mensagem) => { ocupado = false; if (!root) return; root.querySelector('.st-notice').textContent = (mensagem.data && mensagem.data.mensagem) || 'Operação concluída.'; root.querySelector('.st-notice').classList.toggle('st-error', !(mensagem.data && mensagem.data.ok)); renderizar(); });
    },
    onMount() {
      root = document.createElement('section'); root.className = 'mod-store';
      root.innerHTML = '<div class="st-card"><header><div><small>vHub // ESTOQUE</small><strong class="st-title"></strong><p class="st-subtitle"></p></div><button class="st-close" type="button">×</button></header><div class="st-notice"></div><div class="st-items"></div></div>';
      document.body.appendChild(root); root.querySelector('.st-close').addEventListener('click', fechar); renderizar();
    },
    onDestroy() { if (root) root.remove(); root = null; dados = null; ocupado = false; },
  });
})();
