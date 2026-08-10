// bootstrap.js — entrada de mensagens Lua e composição dos módulos

(() => {
  const store = vhub.store('sims');
  let lifecycle = 0;

  async function open(payload) {
    const token = lifecycle + 1;
    lifecycle = token;
    document.body.classList.add('hidden');
    vhub.router.close();
    vhub.unmount('studio');
    store.reset({
      open: true,
      sessionId: payload.session_id,
      mode: payload.mode,
      label: payload.label,
      paid: payload.paid === true,
      tabs: payload.tabs || [],
      current: payload.current || {},
      patch: {},
      prices: payload.prices || {},
      catalog: payload.catalog || {},
      palettes: payload.palettes || {},
      outfits: [],
      wizardDone: false,
      busy: false,
      result: null,
    });
    try {
      const studio = await vhub.mount('studio', '#app');
      if (token !== lifecycle || !studio) return;
      if (payload.mode === 'creator') {
        await vhub.router.navigate('wizard');
        if (token !== lifecycle) return;
      }
      document.body.classList.remove('hidden');
      // página visível: pede ao Lua para reassegurar foco/cursor (SetNuiFocus feito com o body
      // ainda display:none pode não revelar o cursor no CEF). Fire-and-forget.
      vhub.native.post('studioReady');
    } catch (_) {
      if (token !== lifecycle) return;
      close();
      vhub.native.post('cancel');
    }
  }

  function close() {
    lifecycle += 1;
    document.body.classList.add('hidden');
    vhub.router.close();
    vhub.unmount('studio');
    store.reset({ open: false });
  }

  window.addEventListener('message', (event) => {
    const message = event.data || {};
    if (message.type === 'sims:open') {
      open(message.data || {});
    } else if (message.type === 'sims:close') {
      close();
    } else if (message.type === 'sims:result') {
      store.set({ busy: false, result: message.data || {} });
      vhub.emit('sims:result', message.data || {});
    } else if (message.type === 'sims:outfits') {
      store.set({ outfits: (message.data && message.data.items) || [] });
      vhub.emit('sims:outfits', message.data || {});
    }
  });

  document.body.classList.add('hidden');
})();
