// editor.js — controles APV2 ricos (rosto nomeado, swatches, steppers, presets)

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

  // enquadramento automático da câmera ao trocar de aba (só regiões válidas do HSS)
  const tabCamera = {
    heranca: 'body', rosto: 'head', cabelo: 'head', sobrancelha: 'head',
    barba: 'head', maquiagem: 'head', roupas: 'body', acessorios: 'head',
    tatuagens: 'body', outfits: 'body',
  };

  // metadados dos 13 overlays de cabeça do GTA: rótulo PT-BR, teto de variações e paleta de cor
  // (color: 0 = sem cor · 1 = paleta de cabelo · 2 = paleta de maquiagem — espelha o colourType do HSS)
  const overlayMeta = {
    0:  { label: 'Manchas',            max: 23, color: 0 },
    1:  { label: 'Barba',              max: 28, color: 1 },
    2:  { label: 'Sobrancelhas',       max: 33, color: 1 },
    3:  { label: 'Envelhecimento',     max: 14, color: 0 },
    4:  { label: 'Maquiagem',          max: 74, color: 0 },
    5:  { label: 'Blush',              max: 6,  color: 2 },
    6:  { label: 'Tez',                max: 11, color: 0 },
    7:  { label: 'Danos solares',      max: 10, color: 0 },
    8:  { label: 'Batom',              max: 9,  color: 2 },
    9:  { label: 'Pintas e sardas',    max: 17, color: 0 },
    10: { label: 'Pelos no peito',     max: 16, color: 1 },
    11: { label: 'Manchas no corpo',   max: 11, color: 0 },
    12: { label: 'Imperfeições extra', max: 1,  color: 0 },
  };

  // overlays de pele sem cor, editáveis na aba Rosto (os coloridos vivem em barba/sobrancelha/maquiagem)
  const skinOverlays = [0, 3, 6, 7, 9, 11, 12];

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
  let renamingId = null;
  let onClick = null;
  let onInput = null;
  let onKeydown = null;


  // ============================================================
  // ESTADO — leitura/escrita do patch efêmero
  // ============================================================

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

  function setPatchField(key, field, value) {
    const base = editableTuple(key, valueFor(key, {}));
    base[field] = value;
    if (key.startsWith('drawable:') && base.palette === undefined) base.palette = 0;
    if (key.startsWith('overlay:')) {
      if (base.value === undefined) base.value = 0;
      if (base.c1 === undefined) base.c1 = 0;
      if (base.c2 === undefined) base.c2 = 0;
      if (base.opacity === undefined) base.opacity = 1;
    }
    setPatch(key, base);
  }

  function writeNumeric(key, field, value) {
    if (field) setPatchField(key, field, value);
    else setPatch(key, value);
  }

  function readNumeric(key, field) {
    if (field) return Number(nestedValue(key, field, 0));
    const value = valueFor(key, 0);
    return typeof value === 'number' ? value : Number(value) || 0;
  }

  function clamp(value, min, max) {
    return Math.max(min, Math.min(max, value));
  }


  // ============================================================
  // PALETAS — cor real do jogo quando disponível; HSL como guia de reserva
  // (o ped continua sendo a verdade; os swatches são apenas orientação visual)
  // ============================================================

  function hairHSL(i) {
    if (i <= 3) return `hsl(30, 18%, ${8 + i * 3}%)`;
    if (i <= 11) return `hsl(28, 45%, ${16 + (i - 3) * 4}%)`;
    if (i <= 20) return `hsl(42, 62%, ${44 + (i - 12) * 4}%)`;
    if (i <= 27) return `hsl(210, 6%, ${52 + (i - 21) * 5}%)`;
    return `hsl(${(i * 43) % 360}, 55%, 46%)`;
  }

  function makeupHSL(i) {
    return `hsl(${(i * 37) % 360}, 46%, 48%)`;
  }

  function eyeSwatchColor(i) {
    const hues = [28, 24, 200, 205, 120, 96, 40, 260];
    return `hsl(${hues[i % hues.length]}, 45%, ${34 + (i % 5) * 6}%)`;
  }

  // paleta real injetada pelo cliente (cores nativas do jogo), por tipo
  function palette(kind) {
    return (vhubSims.store.get().palettes || {})[kind] || null;
  }

  function paletteCount(kind, fallback) {
    const pal = palette(kind);
    return (pal && pal.length) || fallback;
  }

  function hairSwatchColor(i) {
    const pal = palette('hair');
    return (pal && pal[i]) || hairHSL(i);
  }

  function makeupSwatchColor(i) {
    const pal = palette('makeup');
    return (pal && pal[i]) || makeupHSL(i);
  }


  // ============================================================
  // BUILDERS — element, slider, stepper, swatches, group, presets
  // ============================================================

  function element(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  }

  // slider contínuo (traços de rosto, mistura, opacidade, modelo)
  function slider(container, label, key, options = {}) {
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
      input.type = 'range';
      input.min = options.min ?? -1;
      input.max = options.max ?? 1;
      input.step = options.step ?? 0.05;
    }
    input.value = options.value ?? 0;
    wrapper.appendChild(input);
    container.appendChild(wrapper);
  }

  // stepper ◀ valor ▶ para índices inteiros (cortes, roupas, herança)
  function stepper(container, label, key, options = {}) {
    const min = options.min ?? 0;
    const max = options.max ?? 100;
    const value = clamp(options.value ?? min, min, max);
    const box = element('div', 'sims-stepper');
    box.appendChild(element('span', 'sims-stepper__label', label));

    const row = element('div', 'sims-stepper__row');
    const meta = { key, field: options.field || '', min, max };

    const dec = element('button', 'sims-stepper__btn', '◀');
    dec.type = 'button';
    dec.dataset.step = '-1';
    Object.assign(dec.dataset, meta);

    const display = element('span', 'sims-stepper__value', String(value));

    const inc = element('button', 'sims-stepper__btn', '▶');
    inc.type = 'button';
    inc.dataset.step = '1';
    Object.assign(inc.dataset, meta);

    row.append(dec, display, inc);
    box.appendChild(row);
    container.appendChild(box);
  }

  // grade de swatches de cor (guia); clique aplica preview
  function swatches(container, key, field, count, colorFn) {
    const grid = element('div', 'sims-swatches');
    const selected = readNumeric(key, field);
    for (let i = 0; i < count; i += 1) {
      const chip = element('button', 'sims-swatch');
      chip.type = 'button';
      chip.dataset.swatch = '1';
      chip.dataset.key = key;
      if (field) chip.dataset.field = field;
      chip.dataset.value = String(i);
      chip.style.background = colorFn(i);
      chip.title = String(i);
      chip.setAttribute('aria-pressed', String(i === selected));
      grid.appendChild(chip);
    }
    container.appendChild(grid);
  }

  // grupo nomeado com título + grade 2-col própria (rosto/herança)
  function group(container, title) {
    const box = element('div', 'sims-group');
    box.appendChild(element('h3', 'sims-group__title', title));
    const grid = element('div', 'sims-group__grid');
    box.appendChild(grid);
    container.appendChild(box);
    return grid;
  }


  // ============================================================
  // RENDER POR ABA
  // ============================================================

  function renderPresets(container) {
    const catalog = vhubSims.store.get().catalog || {};
    const isFemale = valueFor('model', 'mp_m_freemode_01') === 'mp_f_freemode_01';
    const list = (catalog.presets || {})[isFemale ? 'female' : 'male'] || [];
    if (!list.length) return;
    const row = element('div', 'sims-presets');
    list.forEach((preset, index) => {
      const button = element('button', 'sims-preset', preset.label);
      button.type = 'button';
      button.dataset.preset = String(index);
      button.dataset.gender = isFemale ? 'female' : 'male';
      row.appendChild(button);
    });
    container.appendChild(row);
  }

  function renderHeritage(container) {
    if (vhubSims.store.get().mode === 'creator') {
      slider(container, 'Modelo', 'model', {
        select: [
          { value: 'mp_m_freemode_01', label: 'Masculino' },
          { value: 'mp_f_freemode_01', label: 'Feminino' },
        ],
        value: valueFor('model', 'mp_m_freemode_01'),
      });
    }
    renderPresets(container);

    const face = group(container, 'Face (herança)');
    stepper(face, 'Pai', 'heritage', { field: 'shape_first', min: 0, max: 45, value: nestedValue('heritage', 'shape_first', 0) });
    stepper(face, 'Mãe', 'heritage', { field: 'shape_second', min: 0, max: 45, value: nestedValue('heritage', 'shape_second', 0) });
    slider(face, 'Mistura', 'heritage', { field: 'shape_mix', min: 0, max: 1, step: 0.05, value: nestedValue('heritage', 'shape_mix', 0.5) });

    const skin = group(container, 'Pele (herança)');
    stepper(skin, 'Pai', 'heritage', { field: 'skin_first', min: 0, max: 45, value: nestedValue('heritage', 'skin_first', 0) });
    stepper(skin, 'Mãe', 'heritage', { field: 'skin_second', min: 0, max: 45, value: nestedValue('heritage', 'skin_second', 0) });
    slider(skin, 'Mistura', 'heritage', { field: 'skin_mix', min: 0, max: 1, step: 0.05, value: nestedValue('heritage', 'skin_mix', 0.5) });
  }

  function renderFace(container) {
    const groups = (vhubSims.store.get().catalog || {}).face_groups || [];
    if (groups.length) {
      groups.forEach((section) => {
        const grid = group(container, section.title);
        (section.items || []).forEach((item) => {
          slider(grid, item.label, `face:${item.i}`, {
            min: -1, max: 1, step: 0.05, value: valueFor(`face:${item.i}`, 0),
          });
        });
      });
    } else {
      // fallback sem catálogo de grupos: 20 traços simples
      for (let index = 0; index < 20; index += 1) {
        slider(container, `Traço ${index + 1}`, `face:${index}`, {
          min: -1, max: 1, step: 0.05, value: valueFor(`face:${index}`, 0),
        });
      }
    }
    container.appendChild(element('h3', 'sims-group__title studio-wide', 'Cor dos olhos'));
    swatches(container, 'eye_color', null, 32, eyeSwatchColor);

    container.appendChild(element('h3', 'sims-group__title studio-wide', 'Pele e imperfeições'));
    renderOverlay(container, skinOverlays);
  }

  function renderHair(container) {
    const cut = group(container, 'Corte');
    stepper(cut, 'Estilo', 'drawable:2', { field: 'd', min: 0, max: 73, value: nestedValue('drawable:2', 'd', 0) });
    stepper(cut, 'Fade (degradê)', 'drawable:2', { field: 't', min: 0, max: 15, value: nestedValue('drawable:2', 't', 0) });

    const count = paletteCount('hair', 64);
    container.appendChild(element('h3', 'sims-group__title studio-wide', 'Cor principal'));
    swatches(container, 'hair_color', 'c1', count, hairSwatchColor);
    container.appendChild(element('h3', 'sims-group__title studio-wide', 'Reflexo'));
    swatches(container, 'hair_color', 'c2', count, hairSwatchColor);
  }

  // renderiza N overlays de cabeça: valor + opacidade sempre; swatches só quando o overlay tem cor
  function renderOverlay(container, indexes) {
    indexes.forEach((index) => {
      const key = `overlay:${index}`;
      const meta = overlayMeta[index] || { label: `Estilo ${index}`, max: 40, color: 0 };
      const box = group(container, meta.label);
      stepper(box, 'Modelo', key, { field: 'value', min: 0, max: meta.max, value: nestedValue(key, 'value', 0) });
      slider(box, 'Opacidade', key, { field: 'opacity', min: 0, max: 1, step: 0.05, value: nestedValue(key, 'opacity', 1) });
      if (meta.color === 1) {
        swatches(box.parentElement, key, 'c1', paletteCount('hair', 64), hairSwatchColor);
      } else if (meta.color === 2) {
        swatches(box.parentElement, key, 'c1', paletteCount('makeup', 64), makeupSwatchColor);
      }
    });
  }

  function renderClothes(container, props) {
    const map = props
      ? (vhubSims.store.get().catalog.props || {})
      : (vhubSims.store.get().catalog.components || {});
    Object.entries(map).forEach(([rawIndex, label]) => {
      const key = `${props ? 'prop' : 'drawable'}:${rawIndex}`;
      const box = group(container, label);
      stepper(box, 'Peça', key, { field: 'd', min: props ? -1 : 0, max: 400, value: nestedValue(key, 'd', props ? -1 : 0) });
      stepper(box, 'Textura', key, { field: 't', min: 0, max: 100, value: nestedValue(key, 't', 0) });
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

  // linha de outfit em edição de nome (input + salvar/cancelar)
  function outfitRenameRow(outfit) {
    const row = element('div', 'studio-wide mod-studio__outfit mod-studio__outfit--edit');
    const input = document.createElement('input');
    input.className = 'sims-button mod-studio__outfit-input';
    input.value = outfit.label;
    input.maxLength = 48;
    input.dataset.outfitRenameInput = String(outfit.id);
    const save = element('button', 'sims-button sims-button--primary sims-button--sm', 'Salvar');
    save.dataset.action = 'outfit-rename-save';
    const cancel = element('button', 'sims-button sims-button--sm', 'Cancelar');
    cancel.dataset.action = 'outfit-rename-cancel';
    row.append(input, save, cancel);
    return row;
  }

  // linha de outfit padrão (nome + renomear/aplicar/excluir)
  function outfitRow(outfit) {
    const row = element('div', 'studio-wide mod-studio__outfit');
    row.appendChild(element('span', 'mod-studio__outfit-name', outfit.label));
    const rename = element('button', 'sims-button sims-button--sm', 'Renomear');
    rename.dataset.action = 'outfit-rename';
    rename.dataset.outfitId = outfit.id;
    const apply = element('button', 'sims-button sims-button--sm', 'Aplicar');
    apply.dataset.action = 'outfit-apply';
    apply.dataset.outfitId = outfit.id;
    const remove = element('button', 'sims-button sims-button--danger sims-button--sm', 'Excluir');
    remove.dataset.action = 'outfit-delete';
    remove.dataset.outfitId = outfit.id;
    row.append(rename, apply, remove);
    return row;
  }

  function renderOutfits(container) {
    const save = element('div', 'studio-wide mod-studio__outfit');
    const input = document.createElement('input');
    input.className = 'sims-button mod-studio__outfit-input';
    input.placeholder = 'Nome do outfit';
    input.maxLength = 48;
    input.dataset.outfitLabel = 'true';
    const button = element('button', 'sims-button sims-button--primary sims-button--sm', 'Salvar');
    button.dataset.action = 'outfit-save';
    save.append(input, button);
    container.appendChild(save);

    (vhubSims.store.get().outfits || []).forEach((outfit) => {
      container.appendChild(outfit.id === renamingId ? outfitRenameRow(outfit) : outfitRow(outfit));
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
      invalid_label: 'Nome inválido.',
    };
    status.dataset.kind = result && result.ok ? 'success' : 'error';
    status.textContent = result && result.ok
      ? (result.outfit_saved ? 'Outfit salvo.' : 'Operação concluída.')
      : (errors[result && result.err] || 'Não foi possível concluir.');
  }


  // ============================================================
  // HANDLERS
  // ============================================================

  function applyPreset(gender, index) {
    const list = ((vhubSims.store.get().catalog || {}).presets || {})[gender] || [];
    const preset = list[index];
    if (!preset || !preset.patch) return;
    const state = vhubSims.store.get();
    const patch = { ...(state.patch || {}) };
    Object.entries(preset.patch).forEach(([key, value]) => { patch[key] = value; });
    vhubSims.store.set({ patch, result: null });
    vhubSims.studioService.preview(preset.patch);
    renderControls();
  }

  // há alterações no patch efêmero ainda não comitadas?
  function isDirty() {
    return Object.keys(vhubSims.store.get().patch || {}).length > 0;
  }

  function toggleExitModal(show) {
    if (!root) return;
    const modal = root.querySelector('[data-studio-modal]');
    if (modal) modal.hidden = !show;
  }

  // saída pede confirmação só quando há alteração pendente; limpo sai direto
  function requestExit() {
    if (isDirty()) toggleExitModal(true);
    else vhubSims.studioService.cancel();
  }

  // "Salvar" equivale ao Confirmar: modo pago abre o checkout; grátis comita direto
  function commitCurrent() {
    if (vhubSims.store.get().paid) vhub.router.navigate('checkout');
    else vhubSims.studioService.checkout();
  }

  function saveRename() {
    const input = root && root.querySelector('[data-outfit-rename-input]');
    const id = renamingId;
    renamingId = null;
    if (id != null && input) vhubSims.studioService.outfitRename(id, input.value);
    renderControls();
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
      writeNumeric(key, input.dataset.field, Number(input.value));
    } else {
      setPatch(key, input.tagName === 'SELECT' ? input.value : Number(input.value));
    }
    // troca de modelo re-renderiza presets/estado dependente
    if (key === 'model') renderControls();
  }

  function handleClick(event) {
    const target = event.target.closest('button');
    if (!target) return;

    if (target.dataset.step !== undefined) {
      const key = target.dataset.key;
      const field = target.dataset.field || '';
      const min = Number(target.dataset.min);
      const max = Number(target.dataset.max);
      const next = clamp(readNumeric(key, field) + Number(target.dataset.step), min, max);
      writeNumeric(key, field || null, next);
      const valueEl = target.parentElement.querySelector('.sims-stepper__value');
      if (valueEl) valueEl.textContent = String(next);
      return;
    }

    if (target.dataset.swatch !== undefined) {
      const key = target.dataset.key;
      const field = target.dataset.field || '';
      const value = Number(target.dataset.value);
      writeNumeric(key, field || null, value);
      const grid = target.closest('.sims-swatches');
      if (grid) {
        grid.querySelectorAll('.sims-swatch').forEach((chip) => {
          chip.setAttribute('aria-pressed', String(Number(chip.dataset.value) === value));
        });
      }
      return;
    }

    if (target.dataset.preset !== undefined) {
      applyPreset(target.dataset.gender, Number(target.dataset.preset));
      return;
    }

    if (target.dataset.tab) {
      renamingId = null;
      selectedTab = target.dataset.tab;
      renderTabs();
      renderControls();
      const view = tabCamera[selectedTab];
      if (view) { vhubSims.studioService.camera(view); setActiveCamera(view); }
      if (selectedTab === 'outfits') vhubSims.studioService.outfitList();
      return;
    }

    const action = target.dataset.action;
    if      (action === 'cancel')       requestExit();
    else if (action === 'exit-stay')    toggleExitModal(false);
    else if (action === 'exit-discard') { toggleExitModal(false); vhubSims.studioService.cancel(); }
    else if (action === 'exit-save')    { toggleExitModal(false); commitCurrent(); }
    else if (action === 'reset') {
      vhubSims.store.set({ patch: {} });
      vhubSims.studioService.preview(vhubSims.store.get().current || {});
      renderControls();
    } else if (action === 'continue') {
      commitCurrent();
    } else if (action === 'camera-body')  { vhubSims.studioService.camera('body');  setActiveCamera('body');  }
    else if  (action === 'camera-head')  { vhubSims.studioService.camera('head');  setActiveCamera('head');  }
    else if  (action === 'camera-chest') { vhubSims.studioService.camera('chest'); setActiveCamera('chest'); }
    else if  (action === 'camera-legs')  { vhubSims.studioService.camera('legs');  setActiveCamera('legs');  }
    else if  (action === 'camera-feet')  { vhubSims.studioService.camera('feet');  setActiveCamera('feet');  }
    else if  (action === 'rotate-left')  vhubSims.studioService.rotate(-20);
    else if  (action === 'rotate-right') vhubSims.studioService.rotate(20);
    else if (action === 'outfit-save') {
      const input = root.querySelector('[data-outfit-label]');
      vhubSims.studioService.outfitSave(input ? input.value : '');
    } else if (action === 'outfit-apply') {
      vhubSims.studioService.outfitApply(Number(target.dataset.outfitId));
    } else if (action === 'outfit-delete') {
      vhubSims.studioService.outfitDelete(Number(target.dataset.outfitId));
    } else if (action === 'outfit-rename') {
      renamingId = Number(target.dataset.outfitId);
      renderControls();
      const input = root.querySelector('[data-outfit-rename-input]');
      if (input) { input.focus(); input.select(); }
    } else if (action === 'outfit-rename-save') {
      saveRename();
    } else if (action === 'outfit-rename-cancel') {
      renamingId = null;
      renderControls();
    }
  }

  function handleKeydown(event) {
    if (event.target.dataset && event.target.dataset.outfitRenameInput !== undefined) {
      if (event.key === 'Enter') { event.preventDefault(); saveRename(); }
      else if (event.key === 'Escape') {
        event.stopPropagation();   // não deixa o ESC global abrir o modal de saída
        event.preventDefault();
        renamingId = null;
        renderControls();
      }
      return;
    }
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


  // ============================================================
  // INTERFACE PÚBLICA
  // ============================================================

  vhubSims.editor = {
    mount: (elementRoot) => {
      root = elementRoot;
      const state = vhubSims.store.get();
      selectedTab = state.tabs && state.tabs[0];
      activeCamera = 'body';
      renamingId = null;

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
    requestExit,
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
