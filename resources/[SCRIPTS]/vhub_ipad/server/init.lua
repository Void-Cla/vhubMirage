---@diagnostic disable: undefined-global, lowercase-global

-- server/init.lua — sessão do tablet (open/close), net events (mutação validada)
-- e registro do item 'ipad'. O servidor é autoritativo: o cliente só sinaliza intenção.

VHubIpad = VHubIpad or {}

local State    = VHubIpad.State
local Registry = VHubIpad.Registry
local CFG      = VHubIpadCFG
local E        = VHubIpadE

VHubIpad.openSet = VHubIpad.openSet or {}   -- [src] = true enquanto o tablet está aberto


-- ============================================================
-- RATE LIMIT (anti-spam por jogador)
-- ============================================================

local _last = {}

-- true se a ação pode rodar agora; arma o cooldown
local function rate(src, key, ms)
  local now = GetGameTimer()
  local k = src .. ':' .. key
  if (now - (_last[k] or 0)) < ms then return false end
  _last[k] = now
  return true
end


-- ============================================================
-- WALLPAPER — enum válido server-side
-- ============================================================

local _wpSet = {}
for _, w in ipairs(CFG.WALLPAPERS) do _wpSet[w.id] = true end

-- valida URL custom: só https, com teto de tamanho (anti-injeção/abuso)
local function validCustomWallpaper(url)
  if type(url) ~= 'string' then return false end
  if #url > 512 then return false end
  return url:match('^https://') ~= nil
end


-- ============================================================
-- OPEN / CLOSE (sessão)
-- ============================================================

-- monta o payload completo enviado à NUI no open (verdade server)
local function buildOpenPayload(src)
  local apps, version = Registry:snapshotFor(src)
  return {
    api_level       = CFG.API_LEVEL,
    catalog_version = version,
    cdn             = CFG.CDN,
    apps            = apps,
    installed       = State.installedList(src),
    prefs           = State.prefs(src),
    wallpapers      = CFG.WALLPAPERS,
  }
end

-- abre o tablet para o jogador (envia catálogo + estado per-char)
function VHubIpad.openFor(src)
  VHubIpad.openSet[src] = true
  TriggerClientEvent(E.OPEN, src, buildOpenPayload(src))
  return true
end

-- fecha o tablet do jogador (força close na NUI)
function VHubIpad.closeFor(src)
  VHubIpad.openSet[src] = nil
  TriggerClientEvent(E.FORCE_CLOSE, src)
end


-- ============================================================
-- NET EVENTS — INTENÇÃO (cliente nunca decide verdade)
-- ============================================================

-- cliente pede para abrir (comando/keymap)
RegisterNetEvent(E.REQUEST_OPEN)
AddEventHandler(E.REQUEST_OPEN, function()
  local src = source
  if not rate(src, 'use_ipad', CFG.rates.use_ipad) then return end
  VHubIpad.openFor(src)
end)

-- cliente avisa que fechou (limpa flag server-side; sem custo)
RegisterNetEvent('vhub_ipad:sv:closed')
AddEventHandler('vhub_ipad:sv:closed', function()
  VHubIpad.openSet[source] = nil
end)

-- instalar app removível
RegisterNetEvent(E.INSTALL)
AddEventHandler(E.INSTALL, function(id)
  local src = source
  if type(id) ~= 'string' then return end
  if not rate(src, 'mutate', CFG.rates.mutate) then return end

  -- só apps que EXISTEM no catálogo e são removíveis (L-01)
  if not Registry:has(id) or not Registry:isRemovable(id) then return end

  if State.install(src, id) then
    TriggerClientEvent(E.STATE, src, { installed = State.installedList(src) })
  end
end)

-- remover app removível
RegisterNetEvent(E.UNINSTALL)
AddEventHandler(E.UNINSTALL, function(id)
  local src = source
  if type(id) ~= 'string' then return end
  if not rate(src, 'mutate', CFG.rates.mutate) then return end

  if not Registry:isRemovable(id) then return end   -- nunca desinstala app de sistema

  if State.uninstall(src, id) then
    TriggerClientEvent(E.STATE, src, { installed = State.installedList(src) })
  end
end)

-- salvar preferência de UI (zoom / wallpaper) — validada server-side
RegisterNetEvent(E.SET_PREF)
AddEventHandler(E.SET_PREF, function(p)
  local src = source
  if type(p) ~= 'table' then return end
  if not rate(src, 'mutate', CFG.rates.mutate) then return end

  if type(p.zoom) == 'number' then
    local z = math.max(30, math.min(100, math.floor(p.zoom)))
    State.setPref(src, 'zoom', z)
  end

  if type(p.wallpaper_id) == 'string' and _wpSet[p.wallpaper_id] then
    State.setPref(src, 'wallpaper_id', p.wallpaper_id)
  end

  if p.wallpaper_custom ~= nil then
    if p.wallpaper_custom == '' then
      State.setPref(src, 'wallpaper_custom', nil)
    elseif validCustomWallpaper(p.wallpaper_custom) then
      State.setPref(src, 'wallpaper_custom', p.wallpaper_custom)
    end
  end
end)


-- ============================================================
-- ITEM 'ipad' (soft-dep do vhub_inventory)
-- ============================================================

-- handler de uso do item: abre o tablet. Durável (return false = NÃO consome).
local function onUseIpad(src, _slot, _meta)
  IpadLog(("item 'ipad' usado por src=%s"):format(tostring(src)))
  if not rate(src, 'use_ipad', CFG.rates.use_ipad) then return false end
  VHubIpad.openFor(src)
  return false
end

-- (re)registra o handler no inventory. Idempotente; retorna true se registrou.
local function tryRegisterItem()
  if GetResourceState('vhub_inventory') ~= 'started' then return false end
  local ok, ret = pcall(function()
    return exports.vhub_inventory:registerItemUse('ipad', onUseIpad)
  end)
  if ok and ret then
    IpadLog("item 'ipad' registrado no vhub_inventory")
    return true
  end
  IpadLog(("registerItemUse falhou (ok=%s ret=%s)"):format(tostring(ok), tostring(ret)))
  return false
end

-- boot: retry bounded (robusto à ordem de boot; padrão vehcontrol)
CreateThread(function()
  for _ = 1, 40 do   -- ~20s de janela
    if tryRegisterItem() then return end
    Wait(500)
  end
  IpadLog("DESISTIU de registrar 'ipad' (vhub_inventory indisponível)")
end)

-- caminho ROBUSTO (sem funcref): o inventory emite este evento server-local no uso do
-- item. Funciona mesmo se o funcref do registerItemUse não atravessar o export.
-- O rate('use_ipad') dedupe caso o handler funcref TAMBÉM dispare (abre só 1x).
AddEventHandler('vhub_inventory:server:itemUsed', function(src, id, _slot, _meta)
  if id ~= 'ipad' then return end
  IpadLog(("item 'ipad' usado (evento) por src=%s"):format(tostring(src)))
  if not rate(src, 'use_ipad', CFG.rates.use_ipad) then return end
  VHubIpad.openFor(src)
end)

-- inventory REINICIOU → o _handlers dele foi zerado: precisamos re-registrar
-- (senão usar o item para de funcionar em silêncio até reiniciar o ipad).
AddEventHandler('onResourceStart', function(res)
  if res == 'vhub_inventory' then
    CreateThread(function() Wait(500); tryRegisterItem() end)
  end
end)


-- ============================================================
-- CLEANUP
-- ============================================================

AddEventHandler('playerDropped', function()
  local src = source
  VHubIpad.openSet[src] = nil
  local p = src .. ':'
  for k in pairs(_last) do if k:sub(1, #p) == p then _last[k] = nil end end
end)
