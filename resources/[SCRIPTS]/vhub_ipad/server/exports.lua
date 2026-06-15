---@diagnostic disable: undefined-global, lowercase-global

-- server/exports.lua — API pública do vhub_ipad (plataforma de apps).
-- registerApp/unregisterApp: contrato para QUALQUER resource publicar um app.
-- openIpad/closeIpad/isOpen: controle do tablet de fora (item-use, handoff).
-- As funções de sessão (openFor/closeFor/openSet) vivem em server/init.lua.

VHubIpad = VHubIpad or {}


-- ============================================================
-- CONTROLE DE INVOCADOR
-- ============================================================

-- libera local; cross-resource passa se não houver whitelist (ou se estiver nela)
local function _invoker_allowed()
  local trust = VHubIpadCFG.trusted_resources
  if not trust or next(trust) == nil then return true end
  local caller = GetInvokingResource()
  if not caller then return true end
  return trust[caller] == true
end


-- ============================================================
-- PLATAFORMA — registro de apps (contrato para terceiros)
-- ============================================================

-- registra/atualiza um app no catálogo. retorna (true) ou (false, motivo)
exports('registerApp', function(manifest)
  if not _invoker_allowed() then return false, 'invoker_negado' end
  return VHubIpad.Registry:register(manifest)
end)

-- remove um app do catálogo (resource dono parou)
exports('unregisterApp', function(id)
  if not _invoker_allowed() then return false end
  VHubIpad.Registry:unregister(id)
  return true
end)


-- ============================================================
-- CONTROLE DO TABLET (de fora)
-- ============================================================

-- abre o tablet para o jogador (carrega estado per-char + envia catálogo)
exports('openIpad', function(src)
  if not _invoker_allowed() then return false end
  if type(src) ~= 'number' then return false end
  return VHubIpad.openFor(src)
end)

-- fecha o tablet do jogador
exports('closeIpad', function(src)
  if not _invoker_allowed() then return false end
  if type(src) ~= 'number' then return false end
  VHubIpad.closeFor(src)
  return true
end)

-- true se o tablet está aberto para o jogador (melhor-esforço server-side)
exports('isOpen', function(src)
  return VHubIpad.openSet ~= nil and VHubIpad.openSet[src] == true
end)
