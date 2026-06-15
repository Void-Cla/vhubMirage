---@diagnostic disable: undefined-global, lowercase-global

-- shared/manifest_schema.lua — validador PURO do manifest de app (sem estado).
-- Usado pelo registry server antes de aceitar qualquer registerApp (inclusive builtins).


VHubIpadManifest = VHubIpadManifest or {}

local ID_PATTERN = '^[a-z0-9_]+$'


-- valida um manifest de app; retorna (true) ou (false, motivo_em_pt_br_curto)
function VHubIpadManifest.validate(m)
  if type(m) ~= 'table' then return false, 'manifest_nao_e_tabela' end

  if type(m.id) ~= 'string' or not m.id:match(ID_PATTERN) then
    return false, 'id_invalido (use [a-z0-9_])'
  end
  if type(m.version) ~= 'string' or m.version == '' then
    return false, 'version_obrigatoria'
  end
  if type(m.label) ~= 'string' or m.label == '' then
    return false, 'label_obrigatorio'
  end

  local ui = m.ui
  if type(ui) ~= 'table' then return false, 'ui_obrigatorio' end

  local source = ui.source or 'local'
  if source ~= 'local' and source ~= 'remote' then
    return false, 'ui_source_invalido (local|remote)'
  end
  if source == 'remote' and (type(ui.resource) ~= 'string' or ui.resource == '') then
    return false, 'ui_resource_obrigatorio_para_remote'
  end

  for _, key in ipairs({ 'html', 'css', 'js' }) do
    if type(ui[key]) ~= 'string' or ui[key] == '' then
      return false, 'ui_' .. key .. '_obrigatorio'
    end
  end

  -- relay (OPCIONAL): app EMBUTIDO. Server roteia AppRelay→este export. Server-only.
  if m.relay ~= nil then
    local r = m.relay
    if type(r) ~= 'table'
       or type(r.resource) ~= 'string' or r.resource == ''
       or type(r.export) ~= 'string' or r.export == '' then
      return false, 'relay_invalido (resource+export string)'
    end
  end

  return true
end
