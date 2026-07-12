-- ╔════════════════════════════════════════════════════════════════╗
-- ║ vHub Mirage — CORE v2.0 (DESCONGELAMENTO — FASE 2 fuel)       ║
-- ║ Freeze v1.0: 2026-05-22 → descongelado sob gate em 2026-07-02 ║
-- ║ Toda alteração segue GATED: arquiteto + revisão + ADR + bump.  ║
-- ║ ADRs desta fase: #37..#50, #61, #65 (WORKLOG_CORE_V2.md)       ║
-- ╚════════════════════════════════════════════════════════════════╝
-- fxmanifest.lua — vHub Mirage
-- Ordem de carga garantida pelo runtime FiveM:
--   shared_scripts → server_scripts → client_scripts
fx_version 'cerulean'
game      'gta5'
lua54     'yes'

name        'vhub'
author      'vHub Mirage'
version     '2.0.0-alpha.3'
description 'Core autoritativo vHub Mirage — VRAM-first, thread-safe (v2 FASE 2: fuel autoritativo).'

dependency 'oxmysql'

-- ── Compartilhado (server + client) ──────────────────────────────────────
-- Rodam primeiro — criam vHub global com Logger, Utils, E, mergeConfig
shared_scripts {
  'shared/config.lua',   -- [1] cria vHub = {} e define mergeConfig
  'shared/events.lua',   -- [2] vHub.E (constantes de eventos)
  'shared/utils.lua',    -- [3] vHub.Utils (helpers puros)
  'shared/logger.lua',   -- [4] vHub.Logger (único ponto de log)
}

-- ── Servidor ──────────────────────────────────────────────────────────────
-- bootstrap.lua carrega base.lua → server/init.lua → todos os módulos server/
-- spawn.lua é carregado pelo server/init.lua (via loadmod) — NÃO aqui,
-- para garantir que só roda após vHub estar completamente inicializado.
server_scripts {
  'bootstrap.lua',
}

-- ── Cliente ───────────────────────────────────────────────────────────────
client_scripts {
  'client/bootstrap.lua',       -- ready único, initDone, charSelected, State Bags
  'client/vehicle.lua',         -- report de veículo 4Hz
  -- spawn é responsabilidade de vhub_player_state (resource externo)
}
