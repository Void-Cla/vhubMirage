---@diagnostic disable: undefined-global, lowercase-global

-- server/registry.lua — catálogo AUTORITATIVO de apps (escritor único).
-- Apps (builtin e de terceiros) entram SÓ por register(); o cliente nunca inventa app.
-- A verdade de "quais apps existem" vive aqui (L-01/L-04). O "instalado" vive no State.

VHubIpad = VHubIpad or {}

local M   = {}; VHubIpad.Registry = M
local CFG = VHubIpadCFG

local _apps    = {}   -- id → manifest validado
local _version = 0    -- catalog_version (bump a cada mudança → invalida cache da NUI)


-- ============================================================
-- ESCRITA (único ponto — via export registerApp / builtins no boot)
-- ============================================================

-- registra/atualiza um app; retorna (true) ou (false, motivo). Idempotente.
function M:register(manifest)
  local ok, err = VHubIpadManifest.validate(manifest)
  if not ok then return false, err end

  if (manifest.manifest_level or 1) > CFG.API_LEVEL then
    return false, 'manifest_level_acima_do_suportado'
  end

  _apps[manifest.id] = manifest
  _version = _version + 1
  return true
end

-- remove um app do catálogo (resource parou)
function M:unregister(id)
  if _apps[id] then
    _apps[id] = nil
    _version  = _version + 1
  end
end

function M:has(id)        return _apps[id] ~= nil end
function M:isRemovable(id) local m = _apps[id]; return m ~= nil and m.removable == true end
function M:version()      return _version end

-- descritor de relay do app embutido (server-only; NUNCA vai no snapshot da NUI)
function M:getRelay(id)   local m = _apps[id]; return m and m.relay or nil end

-- ACL: o jogador pode usar/abrir este app? (permissão server-side, igual ao snapshot)
function M:permittedFor(src, id)
  local m = _apps[id]; if not m then return false end
  if not m.permission then return true end
  local user = exports.vhub:getUser(src)
  return user ~= nil and exports.vhub:hasPerm(user, m.permission) == true
end


-- ============================================================
-- LEITURA — snapshot filtrado por jogador (verdade server)
-- ============================================================

-- resolve URLs do manifest: local → relativo ao iPad; remote → cfx-nui-<resource>
local function resolveEntry(m)
  local ui = m.ui
  if ui.source == 'remote' then
    local base = ('https://cfx-nui-%s/'):format(ui.resource)
    return { html = base .. ui.html, css = base .. ui.css, js = base .. ui.js }
  end
  return { html = ui.html, css = ui.css, js = ui.js }
end

-- monta o catálogo visível/abrível para `src` (permissão + dependency + URLs).
-- Retorna (apps_map, catalog_version).
function M:snapshotFor(src)
  local user = exports.vhub:getUser(src)
  local out  = {}

  for id, m in pairs(_apps) do
    -- gating de permissão (server-authoritative; app sem permission é público)
    local permitted = true
    if m.permission then
      permitted = user ~= nil and exports.vhub:hasPerm(user, m.permission) == true
    end

    if permitted then
      out[id] = {
        id         = id,
        label      = m.label,
        icon       = m.icon,
        category   = m.category,
        removable  = m.removable == true,
        api_version= m.version,
        available  = (not m.dependency) or (GetResourceState(m.dependency) == 'started'),
        mount_kind = m.ui.source or 'local',
        entry      = resolveEntry(m),
      }
    end
  end

  return out, _version
end


-- ============================================================
-- BOOT — registra os apps builtin pelo MESMO caminho (dogfooding)
-- ============================================================

function M:registerBuiltins()
  for _, manifest in ipairs(CFG.BUILTIN_APPS) do
    local ok, err = self:register(manifest)
    if not ok then
      IpadLog(('builtin "%s" rejeitado: %s'):format(tostring(manifest.id), tostring(err)))
    end
  end
end
