-- shops.lua — abertura de vitrines com raio revalidado pelo servidor
---@diagnostic disable: undefined-global

local Core = VHubSimsCore
local Session = VHubSimsSession
local Creation = VHubSimsCreation
local E = VHubSims.E

VHubSimsShops = VHubSimsShops or {}
local Shops = VHubSimsShops
local shops = {}
for _, shop in ipairs(VHubSims.shops) do shops[shop.id] = shop end

local function near(src, shop)
  local position = Core.getPosition(src)
  if not position then return false end
  local dx = position.x - shop.coords.x
  local dy = position.y - shop.coords.y
  local dz = position.z - shop.coords.z
  local radius = tonumber(shop.radius) or VHubSims.cfg.shop_radius
  return (dx * dx + dy * dy + dz * dz) <= radius * radius
end

local function conscious(src)
  local ok, result = Core.call('vhub_hss', 'isConscious', src)
  return ok and (result == true or (type(result) == 'table' and result.ok == true
    and result.conscious == true))
end

-- revalida loja, modo, raio e consciÃªncia no instante da mutaÃ§Ã£o
function Shops.validate(src, shopId, mode)
  local shop = type(shopId) == 'string' and shops[shopId] or nil
  return shop ~= nil and shop.mode == mode and near(src, shop) and conscious(src)
end

-- processa intenção de abertura somente após revalidar domínio físico
local function openRequest(src, payload)
  if type(payload) ~= 'table' or type(payload.shop_id) ~= 'string'
    or #payload.shop_id > 32 or not Core.rate(src, 'open') then
    return
  end

  local user = Core.getUser(src)
  if not user or Session.get(src) then return end
  local shop = shops[payload.shop_id]
  if not shop or not Shops.validate(src, payload.shop_id, shop.mode) then return end

  local result = Creation.openPaidStudio(src, shop.mode, shop.id)
  if not result.ok then Core.notify(src, 'erro', 'Não foi possível abrir o atendimento.') end
end

RegisterNetEvent(E.SRV_OPEN_REQUEST, function(payload)
  openRequest(source, payload)
end)
