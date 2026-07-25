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
}

