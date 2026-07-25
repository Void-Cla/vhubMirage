// form.js — coleta local da identidade sem decidir validade crítica

window.vhubSims = window.vhubSims || {};

(() => {
  let form = null;
  let submitHandler = null;

  vhubSims.wizardForm = {
    mount(root) {
      form = root.querySelector('[data-wizard-form]');
      submitHandler = (event) => {
        event.preventDefault();
        const data = new FormData(form);
        const identity = {
          firstname: String(data.get('firstname') || ''),
          lastname: String(data.get('lastname') || ''),
          age: Number(data.get('age')),
        };
        vhubSims.store.set({ busy: true });
        vhubSims.wizardService.submit(identity);
      };
      form.addEventListener('submit', submitHandler);
    },
    result(result) {
      if (!form) return;
      const status = form.querySelector('[data-wizard-status]');
      if (result && result.wizard && result.ok) {
        vhubSims.store.set({ wizardDone: true, busy: false });
        vhub.emit(vhubSims.events.WIZARD_ACCEPTED);
        return;
      }
      if (result && !result.ok) {
        status.dataset.kind = 'error';
        status.textContent = result.err === 'invalid_identity'
          ? 'Nome, sobrenome ou idade inválidos.'
          : 'Não foi possível validar sua identidade.';
        vhubSims.store.set({ busy: false });
      }
    },
    destroy() {
      if (form && submitHandler) form.removeEventListener('submit', submitHandler);
      form = null;
      submitHandler = null;
    },
  };
})();
