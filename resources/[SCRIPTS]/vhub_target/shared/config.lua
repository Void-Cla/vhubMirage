-- shared/config.lua — configuração e textos do vhub_target (targeting por mira)
-- Tabela GLOBAL sem return (anti-fantasma, manual §1).
---@diagnostic disable: undefined-global, lowercase-global

VHubTarget = VHubTarget or {}

VHubTarget.cfg = {
  hotkey        = 'LMENU',  -- tecla padrão do olho (jogador remapeia em Configurações > Teclas)
  toggleHotkey  = false,    -- true = pressionar alterna; false = segurar
  leftClick     = true,     -- true = seleciona com botão esquerdo; false = direito
  debug         = false,    -- zonas/opções de teste + marker do raycast (dev only)
  drawSprite    = 24,       -- máx. de sprites de zona por frame (SetDrawOrigin tem cap de 32); 0 = off
  defaults      = true,     -- opções built-in de portas de veículo
  maxZones      = 200,      -- cap defensivo de zonas registradas (warn one-shot acima disso)

  -- intervalos mínimos (ms) por evento cliente→servidor (manual §4.6)
  rates = {
    set_entity_options = 200,
    toggle_door        = 300,
  },
}

-- textos exibidos ao jogador (PT-BR, L-08)
VHubTarget.lang = {
  toggle_targeting            = 'Alternar mira de interação',
  go_back                     = 'Voltar',
  toggle_front_driver_door    = 'Abrir a porta dianteira do motorista',
  toggle_front_passenger_door = 'Abrir a porta dianteira do passageiro',
  toggle_rear_driver_door     = 'Abrir a porta traseira do motorista',
  toggle_rear_passenger_door  = 'Abrir a porta traseira do passageiro',
  toggle_hood                 = 'Abrir o capô',
  toggle_trunk                = 'Abrir o porta-malas',
  debug_box                   = '(Debug) Caixa',
  debug_sphere                = '(Debug) Esfera',
  debug_police_car            = '(Debug) Carro de polícia',
  debug_ped                   = '(Debug) Ped',
  debug_vehicle               = '(Debug) Veículo',
  debug_object                = '(Debug) Objeto',
  debug_global                = '(Debug) Global',
}
