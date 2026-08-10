-- catalog.lua — modos, abas e preços autoritativos do SIMS

VHubSims.catalog = {
  modes = {
    creator = {
      label = 'Criação de personagem',
      paid = false,
      tabs = { 'heranca', 'rosto', 'cabelo', 'maquiagem', 'roupas' },
    },
    barber = {
      label = 'Barbearia',
      paid = true,
      tabs = { 'cabelo', 'sobrancelha', 'barba', 'maquiagem' },
    },
    tattoo = {
      label = 'Estúdio de tatuagem',
      paid = true,
      tabs = { 'tatuagens' },
    },
    clothes = {
      label = 'Loja de roupas',
      paid = true,
      tabs = { 'roupas', 'acessorios', 'outfits' },
    },
    surgeon = {
      label = 'Cirurgião plástico',
      paid = true,
      tabs = { 'heranca', 'rosto' },
    },
  },
  prices = {
    barber = {
      hair = 180,
      hair_color = 90,
      overlay = 120,
    },
    tattoo = {
      add = 350,
      remove = 180,
    },
    clothes = {
      drawable = {
        [0] = 80, [1] = 120, [2] = 180, [3] = 90,
        [4] = 220, [5] = 150, [6] = 240, [7] = 130,
        [8] = 100, [9] = 350, [10] = 100, [11] = 280,
      },
      prop = {
        [0] = 160, [1] = 140, [2] = 110, [6] = 190, [7] = 170,
      },
    },
    surgeon = {
      heritage = 1800,
      face = 240,
      eye_color = 300,
    },
  },
  component_labels = {
    [0] = 'Rosto', [1] = 'Máscara', [2] = 'Cabelo', [3] = 'Torso',
    [4] = 'Calça', [5] = 'Bolsa', [6] = 'Calçado', [7] = 'Acessório',
    [8] = 'Camisa', [9] = 'Colete', [10] = 'Decalque', [11] = 'Jaqueta',
  },
  prop_labels = {
    [0] = 'Chapéu', [1] = 'Óculos', [2] = 'Orelha',
    [6] = 'Relógio', [7] = 'Pulseira',
  },
  -- rosto: 20 traços do SetPedFaceFeature agrupados e NOMEADOS em PT-BR (mapa canônico GTA)
  face_groups = {
    { title = 'Nariz', items = {
      { i = 0, label = 'Largura' }, { i = 1, label = 'Altura da ponta' },
      { i = 2, label = 'Comprimento' }, { i = 3, label = 'Altura do osso' },
      { i = 4, label = 'Ponta' }, { i = 5, label = 'Desvio do osso' },
    } },
    { title = 'Sobrancelhas', items = {
      { i = 6, label = 'Altura' }, { i = 7, label = 'Profundidade' },
    } },
    { title = 'Bochecha', items = {
      { i = 8, label = 'Altura do osso' }, { i = 9, label = 'Largura do osso' },
      { i = 10, label = 'Largura' },
    } },
    { title = 'Olhos e boca', items = {
      { i = 11, label = 'Abertura dos olhos' }, { i = 12, label = 'Espessura dos lábios' },
    } },
    { title = 'Mandíbula', items = {
      { i = 13, label = 'Largura' }, { i = 14, label = 'Tamanho' },
    } },
    { title = 'Queixo', items = {
      { i = 15, label = 'Altura' }, { i = 16, label = 'Comprimento' },
      { i = 17, label = 'Tamanho' }, { i = 18, label = 'Furo' },
    } },
    { title = 'Pescoço', items = {
      { i = 19, label = 'Espessura' },
    } },
  },
  -- presets de partida por gênero (patch APV2 parcial aplicado em 1 clique; herança real)
  presets = {
    male = {
      { label = 'Equilibrado', patch = {
        heritage = { shape_first = 0, shape_second = 0, skin_first = 0, skin_second = 0, shape_mix = 0.5, skin_mix = 0.5 },
      } },
      { label = 'Anguloso', patch = {
        heritage = { shape_first = 4, shape_second = 21, skin_first = 4, skin_second = 21, shape_mix = 0.35, skin_mix = 0.45 },
      } },
      { label = 'Robusto', patch = {
        heritage = { shape_first = 14, shape_second = 33, skin_first = 14, skin_second = 33, shape_mix = 0.6, skin_mix = 0.5 },
      } },
    },
    female = {
      { label = 'Equilibrada', patch = {
        heritage = { shape_first = 1, shape_second = 1, skin_first = 1, skin_second = 1, shape_mix = 0.5, skin_mix = 0.5 },
      } },
      { label = 'Suave', patch = {
        heritage = { shape_first = 5, shape_second = 22, skin_first = 5, skin_second = 22, shape_mix = 0.45, skin_mix = 0.5 },
      } },
      { label = 'Marcante', patch = {
        heritage = { shape_first = 9, shape_second = 26, skin_first = 9, skin_second = 26, shape_mix = 0.55, skin_mix = 0.5 },
      } },
    },
  },
}

