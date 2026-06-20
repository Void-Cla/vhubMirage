---@diagnostic disable: undefined-global, lowercase-global

-- config/inventory.lua — catalogo de itens (tags) + ajustes do sistema.
--
-- REGRA: aqui ficam apenas DADOS (visual + tags). A FUNCAO DE USO de cada item
-- vive no script dono do dominio (ex: agua -> vhub_survival registra o handler
-- via exports.vhub_inventory:registerItemUse). O inventory e dispatcher, nao monolito.

Inventory = {}


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
  container_lock_ms  = 300,    -- mutex por container (acesso concorrente)
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
-- give_command = true  -> QUALQUER jogador pode usar /item (so para testar!).
-- DESLIGUE (false) em PRODUCAO; com false, /item exige dono (uid 1) ou ACE 'vhub.item'.
Inventory.Dev = {
  give_command = true,
}

-- Drops no chao (SPRINT-INV-3 — valores ja definidos para nao mexer depois).
Inventory.Drops = {
  ttl_player_s     = 900,      -- 15 min
  ttl_script_s     = 1800,     -- 30 min
  spawn_budget     = 3,        -- CreateObject por frame da thread fria
  max_per_zone     = 200,      -- cap por celula de 100m2 (anti-spike)
  default_model    = 'prop_paper_bag_01',
}

-- Base do CDN de icones (jsDelivr/GitHub). A NUI resolve <id>.png a partir daqui;
-- a config NUNCA guarda URL completa por item, apenas o identificador (a chave do item).
Inventory.CDN = 'https://cdn.jsdelivr.net/gh/Void-Cla/vhub-assets@main'


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
    permitido_bau = true, categoria = 'consumivel',
  },
  ['sandwich'] = {
    nome = 'Sanduíche', peso = 0.30, stack = true, max = 50,
    legalidade = 'comum', negociavel = true, perdivel = true,
    permitido_bau = true, categoria = 'consumivel',
  },
  ['bandage'] = {
    nome = 'Bandagem', peso = 0.10, stack = true, max = 20,
    legalidade = 'legal', negociavel = true, perdivel = true,
    permitido_bau = true, categoria = 'medico',
  },
  ['medkit'] = {
    nome = 'Kit Médico', peso = 1.50, stack = true, max = 5,
    legalidade = 'legal', negociavel = true, perdivel = true,
    permitido_bau = true, categoria = 'medico',
  },

  -- FERRAMENTAS ------------------------------------------------
  ['repairkit'] = {
    nome = 'Kit de Reparo', peso = 1.00, stack = true, max = 5,
    legalidade = 'legal', negociavel = true, perdivel = true,
    permitido_bau = true, categoria = 'ferramenta',
  },
  ['caixadeferramentas'] = {
    nome = 'Caixa de Ferramentas', peso = 2.00, stack = true, max = 10,
    legalidade = 'legal', negociavel = true, perdivel = true,
    permitido_bau = true, categoria = 'ferramenta',
  },
  ['nitro'] = {
    nome = 'Garrafa de Nitro', peso = 1.50, stack = true, max = 10,
    legalidade = 'legal', negociavel = true, perdivel = true,
    permitido_bau = true, categoria = 'ferramenta',
  },
  ['lockpick'] = {
    nome = 'Lockpick', peso = 0.10, stack = false,
    legalidade = 'ilegal', negociavel = true, perdivel = true,
    permitido_bau = true, serial = true, categoria = 'ferramenta',
  },

  -- DOCUMENTOS / CHAVES (nao perdiveis, nao negociaveis) -------
  ['rg'] = {
    nome = 'Carteira de Identidade', peso = 0.05, stack = false,
    legalidade = 'legal', negociavel = false, perdivel = false,
    permitido_bau = false, categoria = 'documento',
  },
  ['veh_key'] = {
    nome = 'Chave de Veículo', peso = 0.05, stack = false,
    legalidade = 'legal', negociavel = false, perdivel = false,
    permitido_bau = false, serial = true, categoria = 'chave',
    -- meta = { plate = 'ABC1234' } definido pelo emissor (vhub_garage)
  },

  -- ELETRONICOS ------------------------------------------------
  -- handler de uso registrado por vhub_ipad (registerItemUse 'ipad'): abre o
  -- tablet e NAO consome (return false). icon implicito = ipad.png no CDN.
  ['ipad'] = {
    nome = 'iPad', peso = 0.30, stack = false,
    legalidade = 'legal', negociavel = true, perdivel = false,
    permitido_bau = true, serial = true, categoria = 'eletronico',
  },
}
