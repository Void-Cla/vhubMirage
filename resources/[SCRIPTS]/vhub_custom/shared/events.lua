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

  -- peça de inventário → desempenho (FASE 3 ADR #81 → ADR #82 F2.1: por part_id do catálogo)
  -- cliente envia (leaseId, requestId, partId); servidor valida no catálogo, cobra, toma item (se
  -- houver) e grava customization.parts (fonte única) + projeção mods/turbo/drift_capable ('tune')
  OFICINA_INSTALL_PART    = 'vhub_custom:server:oficinaInstallPart',   -- cliente → servidor: instalar peça
  OFICINA_INSTALL_PART_OK = 'vhub_custom:client:oficinaInstallPartOk', -- servidor → cliente: (ok, msg)

  -- remover PEÇA de engenharia (ADR #85 F2.5-A — remoção como primeira classe). cliente envia
  -- (leaseId, requestId, partId); servidor reverte customization.parts[id]=false + projeção
  -- mods/turbo/drift_capable NA MESMA transação (L-13). Custo 0; sem devolução de item na F2.5-A.
  OFICINA_REMOVE_PART    = 'vhub_custom:server:oficinaRemovePart',   -- cliente → servidor: remover peça
  OFICINA_REMOVE_PART_OK = 'vhub_custom:client:oficinaRemovePartOk', -- servidor → cliente: (ok, msg, fresh)

  -- engine bay (ADR #82 F2.2) — LEITURA contextual do compartimento do motor (imersão capô).
  -- cliente envia (zoneId, plate, netId); servidor GATEIA por Core.validateVehicle (mesmo gate
  -- físico do serviço) e devolve resumo READ-ONLY da engenharia (eng/parts). Não confia no cliente.
  ENGINE_BAY_INSPECT    = 'vhub_custom:server:engineBayInspect',   -- cliente → servidor: inspecionar motor
  ENGINE_BAY_INSPECT_OK = 'vhub_custom:client:engineBayInspectOk', -- servidor → cliente: (ok, resumo)

  -- (OFICINA_HANDLING/OFICINA_HANDLING_OK REMOVIDOS — ADR #82: gravavam handling_ext, campo zumbi
  --  fora de CUST_KEYS que nunca persistiu. Handling físico migra p/ peças na Camada B, ADR #83.)

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
