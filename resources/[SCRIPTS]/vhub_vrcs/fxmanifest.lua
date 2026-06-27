---@diagnostic disable: undefined-global, lowercase-global
fx_version 'cerulean'
game       'gta5'
lua54      'yes'

name        'vhub_vrcs'
author      'vHub Mirage'
version     '1.0.0'
description 'VHUB Race Cinema System — gravador de telemetria autoritativa -> .vhr + fila de render (Fase 1 MVP).'

-- Soft-coupling com vhub_racha: o racha EMPURRA telemetria validada via export
-- (sob pcall do lado de la). vhub_vrcs nao depende do racha em runtime — so do driver.
dependencies {
  'oxmysql',
}

shared_scripts {
  'core/shared/logger.lua',   -- PRIMEIRO: VRCS.Log (unico print autorizado, L-08)
  'config/config.lua',        -- VRCS.Cfg (tunables)
  'core/shared/vhr_schema.lua',
  'core/shared/codec.lua',
}

server_scripts {
  'core/server/queue.lua',    -- VRCS.Db + VRCS.Queue (escritor de vh_vrcs_jobs)
  'core/server/recorder.lua', -- VRCS.Recorder (escritor unico do .vhr + vh_race_replays)
  'server/publisher.lua',     -- VRCS.Publisher (Discord — TESTE Fase 1)
  'server/library.lua',       -- lista + download sob demanda (/replays)
  'bindings/racha.lua',       -- VRCS.Bindings.Racha (regra de negocio + ingest client)
  'server/init.lua',          -- ULTIMO: schema + exports + lifecycle
}

client_scripts {
  'client/recorder.lua',      -- grava o proprio carro durante a corrida (client-driven)
  'client/cache.lua',         -- cache local (KVP) dos replays baixados
  'client/player.lua',        -- engine de playback in-game (ghosts + motorista + cam)
  'client/nui.lua',           -- comando /replays + lista/download + controles
}

-- Painel minimalista do player (web/). Sem CDN externo (A-10); CEF transparente (A-09).
ui_page 'web/index.html'

files {
  'sql/schema.sql',
  'web/index.html',
  'web/style.css',
  'web/app.js',
}
