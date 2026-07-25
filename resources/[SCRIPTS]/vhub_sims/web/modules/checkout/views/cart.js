// cart.js — estimativa cosmética; servidor permanece autoritativo

window.vhubSims = window.vhubSims || {};

(() => {
  let root = null;
  let clickHandler = null;

  function estimate(state) {
    const patch = state.patch || {};
    const prices = state.prices || {};
    let total = 0;
    Object.keys(patch).forEach((key) => {
      if (state.mode === 'barber') {
        if (key === 'drawable:2') total += prices.hair || 0;
        else if (key === 'hair_color') total += prices.hair_color || 0;
        else if (key.startsWith('overlay:')) total += prices.overlay || 0;
      } else if (state.mode === 'clothes') {
        const [kind, rawIndex] = key.split(':');
        total += Number((prices[kind] || {})[rawIndex] || 0);
      } else if (state.mode === 'surgeon') {
        if (key === 'heritage') total += prices.heritage || 0;
        else if (key === 'eye_color') total += prices.eye_color || 0;
        else if (key.startsWith('face:')) total += prices.face || 0;
      }
    });
    if (state.mode === 'tattoo' && patch.tattoos) {
      const before = new Set(((state.current || {}).tattoos || []).map((item) => `${item.dlc}:${item.hash}`));
      const after = new Set(patch.tattoos.map((item) => `${item.dlc}:${item.hash}`));
      after.forEach((key) => { if (!before.has(key)) total += prices.add || 0; });
      before.forEach((key) => { if (!after.has(key)) total += prices.remove || 0; });
    }
    return total;
  }

  function render() {
    const state = vhubSims.store.get();
    const items = root.querySelector('[data-checkout-items]');
    items.replaceChildren();
    const keys = Object.keys(state.patch || {});
    if (keys.length === 0) {
      const empty = document.createElement('p');
      empty.textContent = 'Nenhuma alteração selecionada.';
      items.appendChild(empty);
    } else {
      keys.forEach((key) => {
        const row = document.createElement('div');
        row.className = 'mod-checkout__item';
        const label = document.createElement('span');
        label.textContent = key.replace(':', ' · ');
        const mark = document.createElement('strong');
        mark.textContent = 'Alterado';
        row.append(label, mark);
        items.appendChild(row);
      });
    }
    root.querySelector('[data-checkout-total]').textContent = `R$ ${estimate(state)}`;
  }

  vhubSims.cart = {
    mount(element) {
      root = element;
      clickHandler = (event) => {
        const button = event.target.closest('button');
        if (!button) return;
        if (button.dataset.action === 'back') vhub.router.close();
        if (button.dataset.action === 'confirm') {
          vhubSims.store.set({ busy: true });
          vhubSims.checkoutService.confirm();
        }
      };
      root.addEventListener('click', clickHandler);
      render();
    },
    result(result) {
      if (!root || !result || result.ok) return;
      const status = root.querySelector('[data-checkout-status]');
      const errors = {
        insufficient: 'Saldo insuficiente.', conflict: 'A aparência mudou. Reabra o atendimento.',
        invalid_patch: 'Alteração inválida.', refunded: 'Pagamento estornado com segurança.',
        manual_reconcile: 'Operação bloqueada para reconciliação.',
      };
      status.dataset.kind = 'error';
      status.textContent = errors[result.err] || 'Não foi possível concluir.';
    },
    destroy() {
      if (root && clickHandler) root.removeEventListener('click', clickHandler);
      root = null;
      clickHandler = null;
    },
  };
})();
