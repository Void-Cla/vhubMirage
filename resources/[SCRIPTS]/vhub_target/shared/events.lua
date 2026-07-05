-- shared/events.lua — nomes de evento do vhub_target (R9: constantes únicas, sem string solta)
-- Tabela GLOBAL sem return (anti-fantasma, manual §1).
---@diagnostic disable: undefined-global, lowercase-global

VHubTarget = VHubTarget or {}

VHubTarget.E = {
  SET_ENTITY_HAS_OPTIONS = 'vhub_target:setEntityHasOptions',  -- client→server: entidade netid ganhou opções
  TOGGLE_ENTITY_DOOR     = 'vhub_target:toggleEntityDoor',     -- client→server→owner: abrir/fechar porta
  DEBUG                  = 'vhub_target:debug',                -- client local: imprime dados da opção (dev)
}
