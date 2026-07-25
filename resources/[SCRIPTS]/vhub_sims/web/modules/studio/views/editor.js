// editor.js — controles APV2, ícones de aba e estado de câmera

window.vhubSims = window.vhubSims || {};

(() => {
  const labels = {
    heranca: 'Herança', rosto: 'Rosto', cabelo: 'Cabelo', sobrancelha: 'Sobrancelha',
    barba: 'Barba', maquiagem: 'Maquiagem', roupas: 'Roupas', acessorios: 'Acessórios',
    tatuagens: 'Tatuagens', outfits: 'Outfits',
  };

  const modeLabels = {
    creator: 'Criação de Personagem',
    editor: 'Editar Aparência',
    barber: 'Barbearia',
    tattoo: 'Tatuagens',
    clothes: 'Roupas',
    surgeon: 'Cirurgia',
  };

  // ícones SVG inline por categoria (stroke-based, sem CDN)
  const icons = {
    heranca: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><circle cx="7.5" cy="7" r="3.5"/><path d="M3 21c0-3 1.8-5.5 4.5-5.5S12 18 12 21"/><circle cx="17" cy="9.5" r="2.5"/><path d="M14.5 21c0-2.2 1.1-4 2.5-4"/></svg>`,
    rosto: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"><circle cx="12" cy="12" r="9"/><circle cx="9" cy="11" r="1.2" fill="currentColor" stroke="none"/><circle cx="15" cy="11" r="1.2" fill="currentColor" stroke="none"/><path d="M9.5 15.5c.8 1 4.2 1 5 0"/></svg>`,
    cabelo: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"><path d="M5 17C5 10 8 4 12 4s7 6 7 13"/><path d="M9.5 17c0-3.8 1.1-7.5 2.5-7.5S14.5 13.2 14.5 17"/></svg>`,
    sobrancelha: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M3 9.5c2.5-3.5 7-5 10.5-3.5S19.5 9 22 7.5"/><path d="M3 16c2.5-3.5 7-5 10.5-3.5S19.5 15.5 22 14"/></svg>`,
    barba: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"><circle cx="12" cy="8.5" r="5"/><path d="M7 13.5v1.5c0 3.6 2.2 6.5 5 6.5s5-2.9 5-6.5V13.5"/><path d="M10 18.5c0 1.1.4 2 1.5 2M14 18.5c0 1.1-.4 2-1.5 2"/></svg>`,
    maquiagem: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><polygon points="12,2 14.8,9 22.5,9.5 16.8,14.7 18.8,22.5 12,18.3 5.2,22.5 7.2,14.7 1.5,9.5 9.2,9"/></svg>`,
    roupas: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M9 2L3 7l3 3 1.5-1.5V20h9V8.5L18 10l3-3L15 2a3 3 0 01-6 0z"/></svg>`,
    acessorios: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><rect x="5" y="9" width="14" height="12" rx="2"/><path d="M9 9V7a3 3 0 016 0v2"/></svg>`,
    tatuagens: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><polygon points="12,2 15,9 22.5,9.5 17,14.5 18.8,22 12,18.2 5.2,22 7,14.5 1.5,9.5 9,9"/></svg>`,
    outfits: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3a2.5 2.5 0 010 5V3z"/><path d="M12 3a2.5 2.5 0 000 5V3z"/><path d="M4 12l8-4 8 4"/><rect x="5" y="12" width="14" height="9" rx="1.5"/></svg>`,
  };

  let root = null;
  let selectedTab = null;
  let activeCamera = 'body';
  let onClick = null;
  let onInput = null;
  let onKeydown = null;

  function valueFor(key, fallback) {
    const state = vhubSims.store.get();
    return Object.prototype.hasOwnProperty.call(state.patch || {}, key)
      ? state.patch[key]
      : (state.current || {})[key] ?? fallback;
  }

  function setPatch(key, value) {
    const state = vhubSims.store.get();
    const patch = { ...(state.patch || {}), [key]: value };
    vhubSims.store.set({ patch, result: null });
    vhubSims.studioService.preview({ [key]: value });
  }

  function element(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  }

  function field(container, label, key, options = {}) {
    const wrapper = element('label', 'sims-field');
    wrapper.appendChild(element('span', '', label));
    const input = document.createElement(options.select ? 'select' : 'input');
    input.dataset.key = key;
    if (options.field) input.dataset.field = options.field;
    if (options.select) {
      options.select.forEach((item) => {
        const option = document.createElement('option');
        option.value = item.value;
        option.textContent = item.label;
        input.appendChild(option);
      });
    } else {
      input.type = options.type || 'range';
      input.min = options.min ?? -1;
      input.max = options.max ?? 1;
      input.step = options.step ?? 0.05;
    }
    input.value = options.value ?? 0;
    wrapper.appendChild(input);
    container.appendChild(wrapper);
  }

  function nestedValue(key, fieldName, fallback) {
    const value = valueFor(key, {});
    const indexes = key === 'hair_color'
      ? { c1: 0, c2: 1 }
      : key.startsWith('overlay:')
        ? { value: 0, c1: 1, c2: 2, opacity: 3 }
        : { d: 0, t: 1, palette: 2 };
    if (Array.isArray(value) && indexes[fieldName] !== undefined) {
      return value[indexes[fieldName]] ?? fallback;
    }
    return value && value[fieldName] !== undefined ? value[fieldName] : fallback;
  }

  function editableTuple(key, value) {
    if (!Array.isArray(value)) return { ...(value || {}) };
    if (key === 'hair_color') return { c1: value[0], c2: value[1] };
    if (key.startsWith('overlay:')) {
      return { value: value[0], c1: value[1], c2: value[2], opacity: value[3] };
    }
    return { d: value[0], t: value[1], palette: value[2] };
  }

  function renderHeritage(container) {
    const state = vhubSims.store.get();
    if (state.mode === 'creator') {
      field(container, 'Modelo', 'model', {
        select: [
          { value: 'mp_m_freemode_01', label: 'Masculino' },
          { value: 'mp_f_freemode_01', label: 'Feminino' },
        ],
        value: valueFor('model', 'mp_m_freemode_01'),
      });
    }
    ['shape_first', 'shape_second', 'skin_first', 'skin_second'].forEach((name) => {
      field(container, name.replace('_', ' '), 'heritage', {
        field: name, min: 0, max: 45, step: 1, value: nestedValue('heritage', name, 0),
      });
    });
    ['shape_mix', 'skin_mix'].forEach((name) => {
      field(container, name.replace('_', ' '), 'heritage', {
        field: name, min: 0, max: 1, step: 0.05, value: nestedValue('heritage', name, 0.5),
      });
    });
  }

  function renderFace(container) {
    for (let index = 0; index < 20; index += 1) {
      field(container, `Traço ${index + 1}`, `face:${index}`, {
        min: -1, max: 1, step: 0.05, value: valueFor(`face:${index}`, 0),
      });
    }
    field(container, 'Cor dos olhos', 'eye_color', {
      min: 0, max: 31, step: 1, value: valueFor('eye_color', 0),
    });
  }

  function renderHair(container) {
    field(container, 'Corte', 'drawable:2', {
      field: 'd', min: 0, max: 200, step: 1, value: nestedValue('drawable:2', 'd', 0),
    });
    field(container, 'Textura', 'drawable:2', {
      field: 't', min: 0, max: 30, step: 1, value: nestedValue('drawable:2', 't', 0),
    });
    field(container, 'Cor principal', 'hair_color', {
      field: 'c1', min: 0, max: 63, step: 1, value: nestedValue('hair_color', 'c1', 0),
    });
    field(container, 'Reflexo', 'hair_color', {
      field: 'c2', min: 0, max: 63, step: 1, value: nestedValue('hair_color', 'c2', 0),
    });
  }

  function renderOverlay(container, indexes) {
    indexes.forEach((index) => {
      const key = `overlay:${index}`;
      field(container, `Estilo ${index}`, key, {
        field: 'value', min: 0, max: 40, step: 1, value: nestedValue(key, 'value', 0),
      });
      field(container, `Opacidade ${index}`, key, {
        field: 'opacity', min: 0, max: 1, step: 0.05, value: nestedValue(key, 'opacity', 1),
      });
    });
  }

  function renderClothes(container, props) {
    const map = props
      ? (vhubSims.store.get().catalog.props || {})
      : (vhubSims.store.get().catalog.components || {});
    Object.entries(map).forEach(([rawIndex, label]) => {
      const key = `${props ? 'prop' : 'drawable'}:${rawIndex}`;
      field(container, `${label} · peça`, key, {
        field: 'd', min: props ? -1 : 0, max: 400, step: 1, value: nestedValue(key, 'd', props ? -1 : 0),
      });
      field(container, `${label} · textura`, key, {
        field: 't', min: 0, max: 100, step: 1, value: nestedValue(key, 't', 0),
      });
    });
  }

  function tattooKey(tattoo) {
    return `${tattoo.dlc}:${tattoo.hash}`;
  }

  function renderTattoos(container) {
    const selected = new Set((valueFor('tattoos', []) || []).map(tattooKey));
    (vhubSims.store.get().catalog.tattoos || []).forEach((tattoo) => {
      const row = element('label', 'mod-studio__tattoo studio-wide');
      row.appendChild(element('span', '', tattoo.label));
      const input = document.createElement('input');
      input.type = 'checkbox';
      input.dataset.tattoo = tattooKey(tattoo);
      input.checked = selected.has(tattooKey(tattoo));
      row.appendChild(input);
      container.appendChild(row);
    });
  }

  function renderOutfits(container) {
    const save = element('div', 'studio-wide mod-studio__outfit');
    const input = document.createElement('input');
    input.className = 'sims-button';
    input.placeholder = 'Nome do outfit';
    input.dataset.outfitLabel = 'true';
    const button = element('button', 'sims-button sims-button--primary', 'Salvar');
    button.dataset.action = 'outfit-save';
    save.append(input, button);
    container.appendChild(save);

    (vhubSims.store.get().outfits || []).forEach((outfit) => {
      const row = element('div', 'studio-wide mod-studio__outfit');
      row.appendChild(element('span', '', outfit.label));
      const apply = element('button', 'sims-button', 'Aplicar');
      apply.dataset.action = 'outfit-apply';
      apply.dataset.outfitId = outfit.id;
      const remove = element('button', 'sims-button sims-button--danger', 'Excluir');
      remove.dataset.action = 'outfit-delete';
      remove.dataset.outfitId = outfit.id;
      row.append(apply, remove);
      container.appendChild(row);
    });
  }

  function renderControls() {
    const container = root.querySelector('[data-studio-controls]');
    container.setAttribute('aria-labelledby', `studio-tab-${selectedTab}`);
    container.replaceChildren(element('h2', '', labels[selectedTab] || selectedTab));
    if (selectedTab === 'heranca') renderHeritage(container);
    else if (selectedTab === 'rosto') renderFace(container);
    else if (selectedTab === 'cabelo') renderHair(container);
    else if (selectedTab === 'sobrancelha') renderOverlay(container, [2]);
    else if (selectedTab === 'barba') renderOverlay(container, [1, 10]);
    else if (selectedTab === 'maquiagem') renderOverlay(container, [4, 5, 8]);
    else if (selectedTab === 'roupas') renderClothes(container, false);
    else if (selectedTab === 'acessorios') renderClothes(container, true);
    else if (selectedTab === 'tatuagens') renderTattoos(container);
    else if (selectedTab === 'outfits') renderOutfits(container);
  }

  function renderTabs() {
    const nav = root.querySelector('[data-studio-tabs]');
    nav.replaceChildren();
    (vhubSims.store.get().tabs || []).forEach((tab) => {
      const button = element('button', 'mod-studio__tab');
      button.dataset.tab = tab;
      button.id = `studio-tab-${tab}`;
      button.setAttribute('role', 'tab');
      button.setAttribute('aria-controls', 'studio-controls');
      button.setAttribute('aria-selected', String(tab === selectedTab));
      button.setAttribute('aria-label', labels[tab] || tab);
      button.tabIndex = tab === selectedTab ? 0 : -1;

      const iconEl = element('span', 'mod-studio__tab-icon');
      iconEl.innerHTML = icons[tab] || '';
      const labelEl = element('span', 'mod-studio__tab-label', labels[tab] || tab);
      button.append(iconEl, labelEl);
      nav.appendChild(button);
    });
  }

  // atualiza aria-pressed em todos os botões de câmera
  function setActiveCamera(view) {
    activeCamera = view;
    if (!root) return;
    root.querySelectorAll('[data-action^="camera-"]').forEach((btn) => {
      const btnView = btn.dataset.action.replace('camera-', '');
      btn.setAttribute('aria-pressed', String(btnView === activeCamera));
    });
  }

  function setStatus(result) {
    if (!root) return;
    const status = root.querySelector('[data-studio-status]');
    const errors = {
      insufficient: 'Saldo insuficiente.', invalid_patch: 'Alteração inválida.',
      identity_required: 'Conclua sua identidade.', storage: 'Falha de armazenamento.',
      conflict: 'A aparência mudou em outra sessão.', forbidden_piece: 'Peça restrita.',
      dependency: 'Serviço indisponível.', outfit_limit: 'Limite de outfits atingido.',
    };
    status.dataset.kind = result && result.ok ? 'success' : 'error';
    status.textContent = result && result.ok
      ? (result.outfit_saved ? 'Outfit salvo.' : 'Operação concluída.')
      : (errors[result && result.err] || 'Não foi possível concluir.');
  }

  function handleInput(event) {
    const input = event.target;
    if (input.dataset.tattoo) {
      const catalog = vhubSims.store.get().catalog.tattoos || [];
      const selected = new Set((valueFor('tattoos', []) || []).map(tattooKey));
      if (input.checked) selected.add(input.dataset.tattoo); else selected.delete(input.dataset.tattoo);
      setPatch('tattoos', catalog.filter((tattoo) => selected.has(tattooKey(tattoo))));
      return;
    }
    const key = input.dataset.key;
    if (!key) return;
    if (input.dataset.field) {
      const base = editableTuple(key, valueFor(key, {}));
      base[input.dataset.field] = Number(input.value);
      if (key.startsWith('drawable:') && base.palette === undefined) base.palette = 0;
      if (key.startsWith('overlay:')) {
        if (base.value === undefined) base.value = 0;
        if (base.c1 === undefined) base.c1 = 0;
        if (base.c2 === undefined) base.c2 = 0;
        if (base.opacity === undefined) base.opacity = 1;
      }
      setPatch(key, base);
    } else {
      setPatch(key, input.tagName === 'SELECT' ? input.value : Number(input.value));
    }
  }

  function handleClick(event) {
    const target = event.target.closest('button');
    if (!target) return;
    if (target.dataset.tab) {
      selectedTab = target.dataset.tab;
      renderTabs();
      renderControls();
      if (selectedTab === 'outfits') vhubSims.studioService.outfitList();
      return;
    }
    const action = target.dataset.action;
    if      (action === 'cancel')       vhubSims.studioService.cancel();
    else if (action === 'reset') {
      vhubSims.store.set({ patch: {} });
      vhubSims.studioService.preview(vhubSims.store.get().current || {});
      renderControls();
    } else if (action === 'continue') {
      if (vhubSims.store.get().paid) vhub.router.navigate('checkout');
      else vhubSims.studioService.checkout();
    } else if (action === 'camera-body')  { vhubSims.studioService.camera('body');  setActiveCamera('body');  }
    else if  (action === 'camera-head')  { vhubSims.studioService.camera('head');  setActiveCamera('head');  }
    else if  (action === 'camera-chest') { vhubSims.studioService.camera('chest'); setActiveCamera('chest'); }
    else if  (action === 'camera-legs')  { vhubSims.studioService.camera('legs');  setActiveCamera('legs');  }
    else if  (action === 'camera-feet')  { vhubSims.studioService.camera('feet');  setActiveCamera('feet');  }
    else if  (action === 'rotate-left')  vhubSims.studioService.rotate(-15);
    else if  (action === 'rotate-right') vhubSims.studioService.rotate(15);
    else if (action === 'outfit-save') {
      const input = root.querySelector('[data-outfit-label]');
      vhubSims.studioService.outfitSave(input ? input.value : '');
    } else if (action === 'outfit-apply') {
      vhubSims.studioService.outfitApply(Number(target.dataset.outfitId));
    } else if (action === 'outfit-delete') {
      vhubSims.studioService.outfitDelete(Number(target.dataset.outfitId));
    }
  }

  function handleKeydown(event) {
    if (!event.target.matches('[role="tab"]')) return;
    const tabs = vhubSims.store.get().tabs || [];
    const current = tabs.indexOf(selectedTab);
    let next = current;
    if (event.key === 'ArrowDown')  next = (current + 1) % tabs.length;
    else if (event.key === 'ArrowUp') next = (current - 1 + tabs.length) % tabs.length;
    else if (event.key === 'Home')   next = 0;
    else if (event.key === 'End')    next = tabs.length - 1;
    else return;
    event.preventDefault();
    selectedTab = tabs[next];
    renderTabs();
    renderControls();
    root.querySelector(`#studio-tab-${selectedTab}`)?.focus();
  }

  vhubSims.editor = {
    mount: (elementRoot) => {
      root = elementRoot;
      const state = vhubSims.store.get();
      selectedTab = state.tabs && state.tabs[0];
      activeCamera = 'body';

      const titleEl = root.querySelector('[data-studio-title]');
      if (titleEl) titleEl.textContent = state.label || 'SIMS';

      const modeEl = root.querySelector('[data-studio-mode]');
      if (modeEl) modeEl.textContent = modeLabels[state.mode] || '';

      onClick = handleClick;
      onInput = handleInput;
      onKeydown = handleKeydown;
      root.addEventListener('click', onClick);
      root.addEventListener('input', onInput);
      root.addEventListener('keydown', onKeydown);

      renderTabs();
      renderControls();
      setActiveCamera('body');
    },
    result: setStatus,
    outfits: () => { if (selectedTab === 'outfits') renderControls(); },
    destroy: () => {
      if (root && onClick)   root.removeEventListener('click', onClick);
      if (root && onInput)   root.removeEventListener('input', onInput);
      if (root && onKeydown) root.removeEventListener('keydown', onKeydown);
      root = null;
      onClick = null;
      onInput = null;
      onKeydown = null;
    },
  };
})();
