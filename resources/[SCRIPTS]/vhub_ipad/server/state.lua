---@diagnostic disable: undefined-global, lowercase-global

-- server/state.lua — estado do tablet POR PERSONAGEM em VRAM (escritor único).
-- Cache de online apenas (load em characterLoad, flush+free em playerDropped).
-- Verdade autoritativa do "instalado" e das preferências do personagem (L-01/L-04).
-- O catálogo de apps DISPONÍVEIS NÃO mora aqui — é do registry. Aqui só a escolha do char.

VHubIpad = VHubIpad or {}

local M     = {}; VHubIpad.State = M
local SQL   = VHubIpad.SQL
local CFG   = VHubIpadCFG

local _sess = {}            -- [src] = { char_id, installed={id,...}, prefs={}, dirty, saving, scheduled }
local DEBOUNCE_MS = 3000    -- janela de coalescência de escrita


-- ============================================================
-- HELPERS
-- ============================================================

-- cópia rasa de array de strings
local function copyList(t)
  local out = {}
  if t then for i = 1, #t do out[i] = t[i] end end
  return out
end

-- índice de um id na lista (0 se ausente)
local function indexOf(list, id)
  for i = 1, #list do if list[i] == id then return i end end
  return 0
end

-- agenda flush debounced (coalescência) — sem polling, um timer por janela
local function scheduleFlush(src)
  local s = _sess[src]; if not s or s.scheduled then return end
  s.scheduled = true
  SetTimeout(DEBOUNCE_MS, function()
    local cur = _sess[src]
    if not cur then return end
    cur.scheduled = false
    M.flush(src)
  end)
end


-- ============================================================
-- LIFECYCLE
-- ============================================================

-- carrega o estado do personagem (flush do char anterior no mesmo src, se trocou)
function M.load(src, char_id)
  local prev = _sess[src]
  if prev and prev.char_id ~= char_id and prev.dirty then
    SQL:saveState(prev.char_id, prev.installed, prev.prefs)
  end

  local installed, prefs = SQL:loadState(char_id)

  _sess[src] = {
    char_id   = char_id,
    installed = installed or copyList(CFG.DEFAULT_INSTALLED),
    prefs     = prefs or { zoom = CFG.DEFAULTS.zoom, wallpaper_id = CFG.DEFAULTS.wallpaper_id },
    dirty     = false,
    saving    = false,
    scheduled = false,
  }
end

-- snapshot consistente das prefs (evita salvar tabela mutando durante o Await)
local function copyPrefs(p)
  return { zoom = p.zoom, wallpaper_id = p.wallpaper_id, wallpaper_custom = p.wallpaper_custom }
end

-- grava se sujo (write-through). dirty é limpo ANTES do save async; mutação
-- durante o save re-marca dirty e reagenda — nenhuma escrita se perde.
function M.flush(src)
  local s = _sess[src]
  if not s or not s.dirty or s.saving then return end

  s.saving = true
  s.dirty  = false
  local cid       = s.char_id
  local installed = copyList(s.installed)
  local prefs     = copyPrefs(s.prefs)

  CreateThread(function()
    SQL:saveState(cid, installed, prefs)
    s.saving = false
    if s.dirty then scheduleFlush(src) end   -- houve mutação durante o save
  end)
end

-- flush final + libera a sessão
function M.unload(src)
  local s = _sess[src]
  if not s then return end
  if s.dirty then SQL:saveState(s.char_id, s.installed, s.prefs) end
  _sess[src] = nil
end

-- flush de todos (onResourceStop)
function M.flushAll()
  for _, s in pairs(_sess) do
    if s.dirty then SQL:saveState(s.char_id, s.installed, s.prefs) end
  end
end


-- ============================================================
-- LEITURA
-- ============================================================

function M.charId(src)       local s = _sess[src]; return s and s.char_id end
function M.installedList(src) local s = _sess[src]; return s and copyList(s.installed) or {} end
function M.isInstalled(src, id) local s = _sess[src]; return s ~= nil and indexOf(s.installed, id) > 0 end

-- cópia das preferências (com defaults preenchidos)
function M.prefs(src)
  local s = _sess[src]
  local p = s and s.prefs or {}
  return {
    zoom             = p.zoom             or CFG.DEFAULTS.zoom,
    wallpaper_id     = p.wallpaper_id     or CFG.DEFAULTS.wallpaper_id,
    wallpaper_custom = p.wallpaper_custom or nil,
  }
end


-- ============================================================
-- MUTAÇÃO (validada pelo init handler antes de chegar aqui)
-- ============================================================

-- instala um app removível; true se mudou
function M.install(src, id)
  local s = _sess[src]; if not s then return false end
  if indexOf(s.installed, id) > 0 then return false end
  s.installed[#s.installed + 1] = id
  s.dirty = true; scheduleFlush(src)
  return true
end

-- remove um app removível; true se mudou
function M.uninstall(src, id)
  local s = _sess[src]; if not s then return false end
  local i = indexOf(s.installed, id)
  if i == 0 then return false end
  table.remove(s.installed, i)
  s.dirty = true; scheduleFlush(src)
  return true
end

-- grava uma preferência (zoom number | wallpaper_id string | wallpaper_custom string)
function M.setPref(src, key, value)
  local s = _sess[src]; if not s then return false end
  s.prefs[key] = value
  s.dirty = true; scheduleFlush(src)
  return true
end
