// app.js — lifecycle do módulo Studio + captura de órbita da câmera (drag/scroll)

(() => {
  let root = null;
  let offs = [];
  let keyHandler = null;


  // ============================================================
  // ÓRBITA — captura de mouse coalescida (~20 Hz) → services.orbit
  // ============================================================

  const orbit = {
    dragging: false,
    lastX: 0,
    lastY: 0,
    acc: { dyaw: 0, dpitch: 0, dzoom: 0 },
    raf: null,
    lastSend: 0,
  };

  function orbitReset() {
    orbit.acc.dyaw = 0;
    orbit.acc.dpitch = 0;
    orbit.acc.dzoom = 0;
  }

  function orbitFlush() {
    orbit.raf = null;
    const now = performance.now();
    if (now - orbit.lastSend < 50) { orbitSchedule(); return; }   // teto ~20 Hz (A-08/L-18)
    if (orbit.acc.dyaw || orbit.acc.dpitch || orbit.acc.dzoom) {
      vhubSims.studioService.orbit({ ...orbit.acc });
      orbitReset();
      orbit.lastSend = now;
    }
  }

  function orbitSchedule() {
    if (orbit.raf === null) orbit.raf = requestAnimationFrame(orbitFlush);
  }

  function inStage(target) {
    return target && target.closest && target.closest('[data-orbit-zone]');
  }

  function onMouseDown(event) {
    if (event.button !== 0 || !inStage(event.target)) return;
    orbit.dragging = true;
    orbit.lastX = event.clientX;
    orbit.lastY = event.clientY;
    if (root) { const z = root.querySelector('[data-orbit-zone]'); if (z) z.classList.add('is-grabbing'); }
  }

  function onMouseMove(event) {
    if (!orbit.dragging) return;
    orbit.acc.dyaw += (event.clientX - orbit.lastX) * 0.35;    // px → graus
    orbit.acc.dpitch += (event.clientY - orbit.lastY) * 0.22;
    orbit.lastX = event.clientX;
    orbit.lastY = event.clientY;
    orbitSchedule();
  }

  function onMouseUp() {
    orbit.dragging = false;
    if (root) { const z = root.querySelector('[data-orbit-zone]'); if (z) z.classList.remove('is-grabbing'); }
  }

  function onWheel(event) {
    if (!inStage(event.target)) return;
    event.preventDefault();
    orbit.acc.dzoom += event.deltaY < 0 ? 0.14 : -0.14;        // scroll cima = aproxima
    orbitSchedule();
  }


  // ============================================================
  // MÓDULO
  // ============================================================

  vhub.createModule('studio', {
    template: '../modules/studio/index.html',

    onInit() {
      offs = [
        vhub.listen(vhubSims.events.RESULT, (result) => vhubSims.editor.result(result)),
        vhub.listen(vhubSims.events.OUTFITS, () => vhubSims.editor.outfits()),
      ];
      keyHandler = (event) => {
        if (event.key === 'Escape') vhubSims.editor.requestExit();
      };
      document.addEventListener('keydown', keyHandler);
    },

    onMount(element) {
      root = element;
      vhubSims.editor.mount(root);
      document.addEventListener('mousedown', onMouseDown);
      document.addEventListener('mousemove', onMouseMove);
      document.addEventListener('mouseup', onMouseUp);
      document.addEventListener('wheel', onWheel, { passive: false });
    },

    onShow() {
      if (root) root.hidden = false;
    },

    onHide() {
      if (root) root.hidden = true;
    },

    onDestroy() {
      document.removeEventListener('mousedown', onMouseDown);
      document.removeEventListener('mousemove', onMouseMove);
      document.removeEventListener('mouseup', onMouseUp);
      document.removeEventListener('wheel', onWheel);
      if (orbit.raf !== null) { cancelAnimationFrame(orbit.raf); orbit.raf = null; }
      orbit.dragging = false;
      orbitReset();

      vhubSims.editor.destroy();
      vhubSims.studioService.destroy();
      offs.forEach((off) => off());
      offs = [];
      if (keyHandler) document.removeEventListener('keydown', keyHandler);
      keyHandler = null;
      root = null;
    },
  });
})();
