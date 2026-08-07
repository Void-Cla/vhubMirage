-- shared/events.lua — fonte única de nomes de eventos do vhub_custom
---@diagnostic disable: undefined-global, lowercase-global

VHubCustom   = VHubCustom or {}
VHubCustom.E = {

  -- autorização física comum (cliente declara intenção; servidor emite lease efêmero)
  SERVICE_AUTH    = 'vhub_custom:server:serviceAuth',
  SERVICE_AUTH_OK = 'vhub_custom:client:serviceAuthOk',

  -- bennys (estética)
  BENNYS_APPLY   = 'vhub_custom:server:bennysApply',    -- cliente → servidor: aplicar cosmético
  BENNYS_CONFIRM = 'vhub_custom:client:bennysConfirm',  -- servidor → cliente: confirmar/rollback

  -- mec (reparo / reboque)
  MEC_REPAIR     = 'vhub_custom:server:mecRepair',      -- cliente → servidor: reparar componente
  MEC_TOW_REQ    = 'vhub_custom:server:mecTowReq',      -- cliente → servidor: solicitar reboque
  MEC_CONFIRM    = 'vhub_custom:client:mecConfirm',     -- servidor → cliente: confirmar/rollback

  -- oficina (tuning)
  OFICINA_TUNE   = 'vhub_custom:server:oficinaTune',    -- cliente → servidor: aplicar stage
  OFICINA_CONFIRM= 'vhub_custom:client:oficinaConfirm', -- servidor → cliente: confirmar/rollback

  -- calibração (redistribuição de pontos livres — decisão #27, motor em vhub_vehcontrol)
  OFICINA_PREVIEW    = 'vhub_custom:server:oficinaPreview',   -- cliente → servidor: prévia de alloc (não persiste)
  OFICINA_PREVIEW_OK = 'vhub_custom:client:oficinaPreviewOk', -- servidor → cliente: ficha hipotética

  OFICINA_RECALIBRATE    = 'vhub_custom:server:oficinaRecalibrate',
  OFICINA_RECALIBRATE_OK = 'vhub_custom:client:oficinaRecalibrateOk',

  -- kit nitro (decisão #29 — oficina cobra; escritor real do estado = vhub_nitro via installKit)
  OFICINA_NITRO_KIT    = 'vhub_custom:server:oficinaNitroKit',   -- cliente → servidor: instalar kit nitro
  OFICINA_NITRO_KIT_OK = 'vhub_custom:client:oficinaNitroKitOk', -- servidor → cliente: resultado (ok, msg)

  -- knobs de handling livre (freio de mão, trava de direção, largada, rigidez) — normalizado 0..1
  -- persiste customization.handling_ext; motor (vhub_vehcontrol) mapeia p/ banda e aplica
  OFICINA_HANDLING    = 'vhub_custom:server:oficinaHandling',   -- cliente → servidor: { key=0..1 }
  OFICINA_HANDLING_OK = 'vhub_custom:client:oficinaHandlingOk', -- servidor → cliente: (ok, msg, knobs)

    -- drift (Freio de Mão Hidráulico — peça instalável, efêmera em runtime; persiste só drift_capable)
  DRIFT_INSTALL   = 'vhub_custom:server:driftInstall',    -- cliente → servidor: instalar peça
  DRIFT_REMOVE    = 'vhub_custom:server:driftRemove',     -- cliente → servidor: remover peça
  DRIFT_CONFIRM   = 'vhub_custom:client:driftConfirm',    -- servidor → cliente: resultado (ok, msg)

  -- estado VISUAL persistido (stance/escapamento) — cliente pede reidratação passando SÓ o netId;
  -- o servidor (server/visual.lua) deriva a placa da entidade e espelha nos bags abaixo
  REQUEST_VISUAL = 'vhub_custom:server:requestVisual',

  -- notificação (servidor → cliente: feedpost nativo)
  NOTIFY         = 'vhub_custom:client:notify',

}

-- nomes canônicos dos State Bags de entidade (equivalente a R9 p/ eventos — fonte única).
-- Escritores: server/visual.lua (hydrate) + server/drift.lua (install/remove).
VHubCustom.BAG = {
  STANCE  = 'vhub_custom:stance',
  EXHAUST = 'vhub_custom:exhaust',
  DRIFT   = 'vhub_custom:drift',   -- bool; true = Freio de Mão Hidráulico instalado
}
