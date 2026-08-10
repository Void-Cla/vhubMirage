// services/index.js — única borda NUI do Studio

window.vhubSims = window.vhubSims || {};

(() => {
  let previewTimer = null;
  let pendingPreview = null;

  function sessionPayload(extra = {}) {
    return { session_id: vhubSims.store.get().sessionId, ...extra };
  }

  function flushPreview() {
    previewTimer = null;
    if (!pendingPreview) return;
    const patch = pendingPreview;
    pendingPreview = null;
    vhub.native.post('preview', sessionPayload({ patch }));
  }

  vhubSims.studioService = {
    preview: (patch) => {
      pendingPreview = { ...(pendingPreview || {}), ...(patch || {}) };
      if (!previewTimer) previewTimer = window.setTimeout(flushPreview, 100);
    },
    camera: (view) => vhub.native.post('camera', { view }),
    rotate: (delta) => vhub.native.post('rotate', { delta }),
    orbit: (delta) => vhub.native.post('orbit', delta),
    checkout: () => vhub.native.post('checkout', sessionPayload({
      patch: vhubSims.store.get().patch || {},
    })),
    cancel: () => vhub.native.post('cancel', sessionPayload()),
    outfitList: () => vhub.native.post('outfitList', sessionPayload()),
    outfitSave: (label) => vhub.native.post('outfitSave', sessionPayload({
      label,
      patch: vhubSims.store.get().patch || {},
    })),
    outfitRename: (outfitId, label) => vhub.native.post('outfitRename', sessionPayload({ outfit_id: outfitId, label })),
    outfitDelete: (outfitId) => vhub.native.post('outfitDelete', sessionPayload({ outfit_id: outfitId })),
    outfitApply: (outfitId) => vhub.native.post('outfitApply', sessionPayload({ outfit_id: outfitId })),
    destroy: () => {
      if (previewTimer) window.clearTimeout(previewTimer);
      previewTimer = null;
      pendingPreview = null;
    },
  };
})();
