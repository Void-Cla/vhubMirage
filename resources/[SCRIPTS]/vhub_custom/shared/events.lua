-- shared/events.lua — fonte única de nomes de eventos do vhub_custom
---@diagnostic disable: undefined-global, lowercase-global

VHubCustom   = VHubCustom or {}
VHubCustom.E = {

  -- bennys (estética)
  BENNYS_APPLY   = 'vhub_custom:server:bennysApply',    -- cliente → servidor: aplicar cosmético
  BENNYS_CONFIRM = 'vhub_custom:client:bennysConfirm',  -- servidor → cliente: confirmar/rollback
  BENNYS_OPEN    = 'vhub_custom:client:bennysOpen',     -- servidor → cliente: abrir menu

  -- mec (reparo / reboque)
  MEC_REPAIR     = 'vhub_custom:server:mecRepair',      -- cliente → servidor: reparar componente
  MEC_TOW_REQ    = 'vhub_custom:server:mecTowReq',      -- cliente → servidor: solicitar reboque
  MEC_TOW_DO     = 'vhub_custom:client:mecTowDo',       -- servidor → cliente: executar attach/move
  MEC_CONFIRM    = 'vhub_custom:client:mecConfirm',     -- servidor → cliente: confirmar/rollback

  -- oficina (tuning)
  OFICINA_TUNE   = 'vhub_custom:server:oficinaTune',    -- cliente → servidor: aplicar stage
  OFICINA_CONFIRM= 'vhub_custom:client:oficinaConfirm', -- servidor → cliente: confirmar/rollback
  OFICINA_OPEN   = 'vhub_custom:client:oficinaOpen',    -- servidor → cliente: abrir menu
  OFICINA_AUTH   = 'vhub_custom:server:oficinaAuth',    -- cliente → servidor: pré-checagem de acesso
  OFICINA_AUTH_OK= 'vhub_custom:client:oficinaAuthOk',  -- servidor → cliente: pode abrir

  -- calibração (redistribuição de pontos livres — decisão #27, motor em vhub_vehcontrol)
  OFICINA_PREVIEW    = 'vhub_custom:server:oficinaPreview',   -- cliente → servidor: prévia de alloc (não persiste)
  OFICINA_PREVIEW_OK = 'vhub_custom:client:oficinaPreviewOk', -- servidor → cliente: ficha hipotética

  -- kit nitro (decisão #29 — oficina cobra; escritor real do estado = vhub_nitro via installKit)
  OFICINA_NITRO_KIT    = 'vhub_custom:server:oficinaNitroKit',   -- cliente → servidor: instalar kit nitro
  OFICINA_NITRO_KIT_OK = 'vhub_custom:client:oficinaNitroKitOk', -- servidor → cliente: resultado (ok, msg)

  -- catálogo (bootstrap único por spawn — client recebe cópia read-only do conce)
  REQ_CATALOG    = 'vhub_custom:server:reqCatalog',     -- cliente → servidor: pede catálogo
  CATALOG        = 'vhub_custom:client:catalog',        -- servidor → cliente: catálogo recebido

  -- dados de veículo por placa (lookup autoritativo via prontuário → catálogo)
  REQ_VEH_DATA   = 'vhub_custom:server:reqVehData',    -- cliente → servidor: pede dados por placa
  VEH_DATA       = 'vhub_custom:client:vehData',       -- servidor → cliente: dados recebidos

  -- zonas (shared)
  ZONE_ENTER     = 'vhub_custom:client:zoneEnter',      -- servidor → cliente: entrou na zona
  ZONE_LEAVE     = 'vhub_custom:client:zoneLeave',      -- servidor → cliente: saiu da zona

  -- notificação (servidor → cliente: feedpost nativo)
  NOTIFY         = 'vhub_custom:client:notify',

}
