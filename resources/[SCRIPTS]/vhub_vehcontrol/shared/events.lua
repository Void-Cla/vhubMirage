-- shared/events.lua — nomes de eventos do engine de skill (anti-fantasma L-15)
--
-- Os eventos de CONTROLE legados (lock/engine/state) seguem com o prefixo 'vhub_vehcontrol:'
-- direto em server/client main.lua (código estável, não refatorado). Aqui ficam SÓ os eventos
-- novos do engine de skill, centralizados para evitar literais soltos.
---@diagnostic disable: undefined-global, lowercase-global

VHubVeh   = VHubVeh or {}
VHubVeh.E = {

  -- skill / redistribuição de pontos
  REQ_SHEET    = 'vhub_vehcontrol:reqSheet',     -- cliente → servidor: pede ficha derivada por placa
  SHEET        = 'vhub_vehcontrol:sheet',        -- servidor → cliente: ficha (flat, primitivos)
  RECALIBRATE  = 'vhub_vehcontrol:recalibrate',  -- cliente → servidor: aplicar alloc redistribuído
  RECAL_DONE   = 'vhub_vehcontrol:recalDone',    -- servidor → cliente: resultado (ok, msg, kind, ficha nova)
  OPEN_EDIT    = 'vhub_vehcontrol:openEdit',     -- servidor → cliente: abre painel já em modo edição (item)

  -- chave-item já dispara este (item_handlers.lua) — referenciado aqui para inventário único
  OPEN_FROM_KEY = 'vhub_vehcontrol:open_from_key',

  -- nitro na FICHA (decisão #30) — cliente → servidor; o servidor DELEGA aos exports do
  -- vhub_nitro (setEnabled/setLevel/chargeFromItem), que é o escritor único da placa.
  NITRO_TOGGLE = 'vhub_vehcontrol:nitroToggle',   -- (plate, on)   liga/desliga
  NITRO_LEVEL  = 'vhub_vehcontrol:nitroLevel',    -- (plate, level) ajusta nível 1..10
  NITRO_CHARGE = 'vhub_vehcontrol:nitroCharge',   -- (plate)        abastece (consome 1 garrafa)
  NITRO_DONE   = 'vhub_vehcontrol:nitroDone',     -- servidor → cliente: (ok, msg, nitro novo)

  -- física derivada (F5, decisão #28) — eventos CLIENT-INTERNOS: main.lua emite,
  -- client/handling.lua escuta (gatilho event-driven, sem polling novo — L-06)
  BECAME_DRIVER = 'vhub_vehcontrol:becameDriver',  -- (veh, plate) virei motorista desta placa
  LEFT_VEHICLE  = 'vhub_vehcontrol:leftVehicle',   -- (veh) saí do banco do motorista (restaura base)
}
