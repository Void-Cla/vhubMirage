---@diagnostic disable: undefined-global, lowercase-global

-- config/inventory.lua — catalogo de itens (tags) + ajustes do sistema.
--
-- REGRA: aqui ficam apenas DADOS (visual + tags). A FUNCAO DE USO de cada item
-- vive no script dono do dominio (ex: agua -> vhub_survival registra o handler
-- via exports.vhub_inventory:registerItemUse). O inventory e dispatcher, nao monolito.

Inventory = {}

-- Mutadores cross-resource: default-deny; leitura permanece pública.
Inventory.TrustedResources = {
  ['vhub'] = true,
  ['vhub_admin'] = true,
  ['vhub_coinshop'] = true,
  ['vhub_conce'] = true,
  ['vhub_custom'] = true,
  ['vhub_ferinha'] = true,
  ['vhub_garage'] = true,
  ['vhub_hss'] = true,
  ['vhub_ipad'] = true,
  ['vhub_legacyfuel'] = true,
  ['vhub_nitro'] = true,
  ['vhub_survival'] = true,
  ['vhub_vehcontrol'] = true,
}


-- ============================================================
-- AJUSTES GERAIS
-- ============================================================

-- Mochila do jogador (slots + teto de peso). Peso e SEMPRE derivado, nunca salvo.
-- Abertura: tecla unificada 'I' (client/containers.lua) — baú perto > porta-malas > mochila.
Inventory.Backpack = {
  slots      = 10,        -- numero de slots da mochila
  max_weight = 50.0,      -- kg
}

-- Morte: por padrao NAO perde itens (preserva o cliente). Drop-no-chao na morte
-- entra no SPRINT-INV-3 (precisa do modulo de drops). `perdivel` controla o que cai.
Inventory.Death = {
  lose_on_death = false,
}

-- Hotbar: 5 atalhos (vincula item arrastando-o p/ a barra). Teclas configuraveis
-- (o jogador tambem pode remapear nas teclas do FiveM). Usar item sem abrir a mochila.
Inventory.Hotbar = {
  slots = 5,
  keys  = { '1', '2', '3', '4', '5' },
}

-- Porta-malas: capacidade base x multiplicador por TIPO do registro do vhub_garage.
-- NAO usar GetVehicleClass server-side (ambiguo) — capacidade vem do garage (L-04).
Inventory.Trunk = {
  base_capacity  = 40.0,
  range          = 2.5,    -- distancia maxima do veiculo (server-side)
  size           = 5,     -- slots do porta-malas
  require_access = true,   -- exige chave do veiculo OU ser dono (preserva economia)
  vtype_mult = {
    car = 1.0, bike = 0.2, truck = 2.5, trailer = 3.0, boat = 0.8, heli = 0.6, plane = 1.5,
  },
}

-- Baus fixos (static) e de faccao. Operador estende. Coords + capacidade(kg) + slots.
Inventory.Chests = {

  -- abertos por proximidade + tecla [E]; permissao opcional (vhub_groups)
  static = {
    ['guarda_volumes'] = {
      label = 'Guarda-Volumes', coords = { x = -360.0432, y = -144.5569, z = 38.2476 },
      range = 2.0, capacity = 50.0, size = 10,
    },
  },

  -- exigem permissao de grupo (vhub_groups) obrigatoria
  faction = {
    -- ['policia'] = { label='Deposito PM', coords={x=441.7,y=-981.0,z=30.7}, range=2.5,
    --                 capacity=1000.0, size=120, permission='policia.deposito' },
  },
}

-- Seguranca e anti-dupe (server-side).
Inventory.Security = {
  action_cooldown_ms = 250,    -- cooldown por jogador por acao (anti double-action)
  p2p_range          = 2.0,    -- distancia maxima para envio P2P (metros)
  pickup_range       = 2.5,    -- distancia maxima para pegar drop
  antidupe_window_ms = 1000,   -- janela de deteccao de flood
  antidupe_max       = 8,      -- acoes na janela antes de reagir
  antidupe_action    = 'log',  -- log | kick | ban
}

-- Persistencia (write-through). Debounce evita query por acao; flush triplo evita perda.
Inventory.Save = {
  debounce_ms = 3000,          -- salva apos 3s sem nova mutacao
}

-- Comandos de TESTE/DEV.
-- /item publico so existe com give_command habilitado E convar dev explicita.
-- Em producao, mantenha false; /item exige dono (uid 1) ou ACE 'vhub.item'.
Inventory.Dev = {
  give_command = false,
}

-- Drops no chao (SPRINT-INV-3 — valores ja definidos para nao mexer depois).
Inventory.Drops = {
  ttl_player_s     = 900,      -- 15 min
  ttl_script_s     = 1800,     -- 30 min
  spawn_budget     = 3,        -- CreateObject por frame da thread fria
  max_per_zone     = 200,      -- cap por celula de 100m2 (anti-spike)
  default_model    = 'prop_paper_bag_01',
}

-- Icones: resolvidos automaticamente por chave de item.
-- URL base: https://raw.githubusercontent.com/Void-Cla/vhub-assets/main/<id>.png
-- Fallback visual (letra inicial do nome) exibido automaticamente quando o PNG nao existe.
Inventory.Assets = {}


-- ============================================================
-- CATALOGO DE ITENS (tags declarativas)
-- ============================================================
-- Campos:
--   nome        string  — rotulo PT-BR
--   peso        number  — kg por unidade (entra no calculo de capacidade)
--   stack       bool    — empilha no mesmo slot?
--   max         int     — teto da pilha (so para stack=true)
--   legalidade  string  — 'legal' | 'ilegal' | 'comum'
--   negociavel  bool    — pode P2P / mercado?
--   perdivel    bool    — pode dropar / cai na morte?
--   permitido_bau bool  — pode ir para bau?
--   serial      bool    — gera serial unico server-side (anti-dupe de itens valiosos)
--   categoria   string  — agrupamento visual na NUI
-- icon e implicito = a propria chave do item (CDN/<chave>.png).

Inventory.Items = {

  -- CONSUMIVEIS ------------------------------------------------
  ['agua'] = {
    nome = 'Água', peso = 0.20, stack = true, max = 50,
    legalidade = 'comum', negociavel = true, perdivel = true,
    permitido_bau = true, categoria = 'consumivel', consume_policy = 'on_applied',
  },
  ['sandwich'] = {
    nome = 'Sanduíche', peso = 0.30, stack = true, max = 50,
    legalidade = 'comum', negociavel = true, perdivel = true,
    permitido_bau = true, categoria = 'consumivel', consume_policy = 'on_applied',
  },
  ['bandage'] = {
    nome = 'Bandagem', peso = 0.10, stack = true, max = 20,
    legalidade = 'legal', negociavel = true, perdivel = true,
    permitido_bau = true, categoria = 'medico', consume_policy = 'on_applied',
  },
  ['medkit'] = {
    nome = 'Kit Médico', peso = 1.50, stack = true, max = 5,
    legalidade = 'legal', negociavel = true, perdivel = true,
    permitido_bau = true, categoria = 'medico', consume_policy = 'on_applied',
  },

  -- FERRAMENTAS ------------------------------------------------
  ['repairkit'] = {
    nome = 'Kit de Reparo', peso = 1.00, stack = true, max = 5,
    legalidade = 'legal', negociavel = true, perdivel = true,
    permitido_bau = true, categoria = 'ferramenta', consume_policy = 'never',
  },
  ['caixadeferramentas'] = {
    nome = 'Caixa de Ferramentas', peso = 2.00, stack = true, max = 10,
    legalidade = 'legal', negociavel = true, perdivel = true,
    permitido_bau = true, categoria = 'ferramenta', consume_policy = 'never',
  },
  ['nitro'] = {
    nome = 'Garrafa de Nitro', peso = 1.50, stack = true, max = 10,
    legalidade = 'legal', negociavel = true, perdivel = true,
    permitido_bau = true, categoria = 'ferramenta', consume_policy = 'never',
  },
  ['fuel_can'] = {
    nome = 'Galão de Combustível', peso = 5.00, stack = false, serial = true,
    legalidade = 'legal', negociavel = true, perdivel = true,
    permitido_bau = true, categoria = 'ferramenta', consume_policy = 'never',
  },
  ['lockpick'] = {
    nome = 'Lockpick', peso = 0.10, stack = false,
    legalidade = 'ilegal', negociavel = true, perdivel = true,
    permitido_bau = true, serial = true, categoria = 'ferramenta', consume_policy = 'never',
  },

  -- DOCUMENTOS / CHAVES (nao perdiveis, nao negociaveis) -------
  ['rg'] = {
    nome = 'Carteira de Identidade', peso = 0.05, stack = false,
    legalidade = 'legal', negociavel = false, perdivel = false,
    permitido_bau = false, categoria = 'documento', consume_policy = 'never',
  },
  ['veh_key'] = {
    nome = 'Chave de Veículo', peso = 0.05, stack = false,
    legalidade = 'legal', negociavel = false, perdivel = false,
    permitido_bau = false, serial = true, categoria = 'chave', consume_policy = 'never',
    -- meta = { plate = 'ABC1234' } definido pelo emissor (vhub_garage)
  },

  -- ELETRONICOS ------------------------------------------------
  -- handler de uso registrado por vhub_ipad (registerItemUse 'ipad'): abre o
  -- tablet e NAO consome (return false). icon implicito = ipad.png no CDN.
  ['ipad'] = {
    nome = 'iPad', peso = 0.30, stack = false,
    legalidade = 'legal', negociavel = true, perdivel = false,
    permitido_bau = true, serial = true, categoria = 'eletronico', consume_policy = 'never',
  },
  ['radio'] = {
    nome = 'Rádio Comunicador', peso = 0.45, stack = false,
    legalidade = 'legal', negociavel = true, perdivel = true,
    permitido_bau = true, serial = true, categoria = 'eletronico', consume_policy = 'never',
  },
}


-- ============================================================
-- CUTOVER F2+ (monotônico, default-off)
-- ============================================================

-- Gate para features de F2+ (schema novo, CAS, protocol v2).
-- Habilitar somente após F1 validado e rollback testado:
--   setr inventory_vnext 1   ← no server.cfg/server-vnext.cfg
-- Nunca ativar em produção sem o rito de migração completo (plan2.md §15).
Inventory.VNext = {
  enabled = GetConvar('inventory_vnext', '0') == '1',
}
