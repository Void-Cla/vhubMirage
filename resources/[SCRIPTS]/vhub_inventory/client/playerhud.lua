---@diagnostic disable: undefined-global, lowercase-global

-- client/playerhud.lua — Player Info HUD (ID do personagem, telefone, nome).
--
-- HUD e DISPLAY nao-critico: o cliente monta. Mas o ID e SEMPRE o id do PERSONAGEM
-- (char_id) — o cliente nao conhece isso sozinho, entao o servidor envia (VHubInvE.HUD).
-- Um user_id pode ter 5 char_id; a troca de char re-dispara characterLoad -> novo HUD.
-- Nome/telefone vem do evento publico do dono (vhub_identity:load).

local _charId = nil
local _name   = nil
local _phone  = nil


-- ============================================================
-- PUSH
-- ============================================================

-- envia os campos atuais do HUD para a NUI
local function pushHud()
  SendNUIMessage({
    action = 'hud',
    hud = { id = _charId, name = _name, phone = _phone },
  })
end


-- ============================================================
-- FONTES
-- ============================================================

-- id do PERSONAGEM (vem do servidor — fonte unica por char_id)
RegisterNetEvent(VHubInvE.HUD)
AddEventHandler(VHubInvE.HUD, function(d)
  if type(d) == 'table' and d.charId ~= nil then _charId = d.charId; pushHud() end
end)

-- nome/telefone do dono da identidade
RegisterNetEvent('vhub_identity:load')
AddEventHandler('vhub_identity:load', function(identity)
  if type(identity) ~= 'table' then return end
  local fn = identity.firstname or ''
  local ln = identity.lastname or ''
  _name  = (fn .. ' ' .. ln):gsub('^%s+', ''):gsub('%s+$', '')
  _phone = identity.phone
  pushHud()
end)


-- ============================================================
-- REFRESH (NUI pronta -> pede char_id + identidade)
-- ============================================================

AddEventHandler('vhub_inventory:hud_refresh', function()
  TriggerServerEvent(VHubInvE.HUD_REQ)        -- responde via VHubInvE.HUD
  TriggerServerEvent('vhub_identity:get')     -- responde via vhub_identity:load
  pushHud()
end)
