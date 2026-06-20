-- client/init.lua — estado local, catálogo e callbacks NUI do vhub_custom
---@diagnostic disable: undefined-global

VHubCustom         = VHubCustom or {}
VHubCustom.running = true    -- flag de lifecycle para as threads
VHubCustom.near    = nil     -- zona próxima atual {id, domain, label, ...}
VHubCustom.inMenu  = false   -- menu de algum domínio aberto
VHubCustom.catalog = {}      -- catálogo indexado por hash (tostring(model_hash))

local E = VHubCustom.E

-- pré-calcula vec3 das zonas (L-19: vec3 é LOCAL; nunca cruza evento/export/NUI)
for _, z in ipairs(VHubCustom.cfg.zones) do
  z._vec = vec3(z.x, z.y, z.z)
end

-- solicita catálogo ao servidor assim que o resource inicia
AddEventHandler('onResourceStart', function(res)
  if res ~= GetCurrentResourceName() then return end
  TriggerServerEvent(E.REQ_CATALOG)
end)

-- armazena catálogo recebido do servidor (hash → {nome, stats, categoria})
RegisterNetEvent(E.CATALOG)
AddEventHandler(E.CATALOG, function(catalog)
  VHubCustom.catalog = type(catalog) == 'table' and catalog or {}
end)


-- ============================================================
-- NOTIFICAÇÃO (feedpost nativo — mesmo caminho confiável do garage)
-- ============================================================

-- mostra notificação textual nativa; cor por tipo (error/success/warning/info)
RegisterNetEvent(E.NOTIFY)
AddEventHandler(E.NOTIFY, function(msg, kind)
  local prefix = ({
    error   = '~r~',   -- vermelho
    success = '~g~',   -- verde
    warning = '~y~',   -- amarelo
    info    = '~w~',   -- branco
  })[kind] or '~w~'
  BeginTextCommandThefeedPost('STRING')
  AddTextComponentSubstringPlayerName(prefix .. tostring(msg or ''))
  EndTextCommandThefeedPostTicker(false, true)
end)

-- helper local: notificação client-side direta (sem round-trip ao servidor)
function VHubCustom.notify(msg, kind)
  TriggerEvent(E.NOTIFY, msg, kind)
end

-- cleanup ao parar o resource
AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  VHubCustom.running = false
  if VHubCustom.inMenu then
    SetNuiFocus(false, false)
    VHubCustom.inMenu = false
  end
end)
