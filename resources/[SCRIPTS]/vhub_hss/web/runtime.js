// runtime.js — lifecycle mínimo e determinístico da NUI HSS

'use strict';

(() => {
    const modules = new Map();

    function getModule(name) {
        return modules.get(name) || null;
    }

    function createModule(name, spec) {
        if (typeof name !== 'string' || name === '' || !spec || modules.has(name)) {
            throw new Error('[vhub_hss] módulo NUI inválido ou duplicado');
        }

        for (const hook of ['onInit', 'onMount', 'onShow', 'onHide', 'onDestroy']) {
            if (typeof spec[hook] !== 'function') {
                throw new Error(`[vhub_hss] lifecycle incompleto: ${hook}`);
            }
        }

        modules.set(name, { spec, initialized: false, mounted: false, visible: false });
    }

    function mount(name) {
        const module = getModule(name);
        if (!module) return false;

        if (!module.initialized) {
            module.spec.onInit();
            module.initialized = true;
        }
        if (!module.mounted) {
            module.spec.onMount();
            module.mounted = true;
        }
        return true;
    }

    function show(name) {
        const module = getModule(name);
        if (!module || !mount(name)) return false;
        if (!module.visible) {
            module.spec.onShow();
            module.visible = true;
        }
        return true;
    }

    function hide(name) {
        const module = getModule(name);
        if (!module || !module.mounted || !module.visible) return false;
        module.spec.onHide();
        module.visible = false;
        return true;
    }

    function unmount(name) {
        const module = getModule(name);
        if (!module) return false;
        hide(name);
        if (module.mounted) module.spec.onDestroy();
        modules.delete(name);
        return true;
    }

    window.vhub = Object.freeze({
        createModule,
        mount,
        show,
        hide,
        unmount,
        isVisible: (name) => getModule(name)?.visible === true,
    });

    window.addEventListener('beforeunload', () => {
        for (const name of [...modules.keys()]) unmount(name);
    }, { once: true });
})();
