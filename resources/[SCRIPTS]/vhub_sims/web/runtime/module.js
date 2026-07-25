// module.js — lifecycle e lazy load de componentes

window.vhub = window.vhub || {};

(() => {
  const registry = new Map();
  const mounted = new Map();
  const templates = new Map();
  const revisions = new Map();

  function revision(name) {
    return revisions.get(name) || 0;
  }

  async function template(path) {
    if (templates.has(path)) return templates.get(path);
    const response = await fetch(path, { cache: 'no-store' });
    if (!response.ok) throw new Error('template_unavailable');
    const html = await response.text();
    templates.set(path, html);
    return html;
  }

  vhub.createModule = (name, spec) => {
    if (registry.has(name)) throw new Error(`Módulo duplicado: ${name}`);
    registry.set(name, spec);
  };

  vhub.mount = async (name, target = '#app') => {
    if (mounted.has(name)) {
      mounted.get(name).spec.onShow();
      return mounted.get(name).root;
    }

    const spec = registry.get(name);
    const host = document.querySelector(target);
    if (!spec || !host) throw new Error(`Módulo inválido: ${name}`);
    const expectedRevision = revision(name);
    const shell = document.createElement('div');
    shell.innerHTML = await template(spec.template);
    if (revision(name) !== expectedRevision) return null;
    const root = shell.firstElementChild;
    if (!root) throw new Error(`Template vazio: ${name}`);
    host.appendChild(root);

    try {
      spec.onInit();
      spec.onMount(root);
      spec.onShow();
      mounted.set(name, { root, spec });
      return root;
    } catch (error) {
      try { spec.onHide(); } catch (_) {}
      try { spec.onDestroy(); } catch (_) {}
      root.remove();
      throw error;
    }
  };

  vhub.unmount = (name) => {
    revisions.set(name, revision(name) + 1);
    const instance = mounted.get(name);
    if (!instance) return;

    let cleanupError = null;
    try {
      instance.spec.onHide();
    } catch (error) {
      cleanupError = error;
    }
    try {
      instance.spec.onDestroy();
    } catch (error) {
      cleanupError = cleanupError || error;
    }
    instance.root.remove();
    mounted.delete(name);
    if (cleanupError) console.error(`Falha no cleanup do módulo ${name}.`, cleanupError);
  };
})();
