-- pricing.lua — cálculo único e autoritativo de preço por diff

VHubSimsPricing = VHubSimsPricing or {}

local Pricing = VHubSimsPricing
local AP = VHubSims.APShape
local Catalog = VHubSims.catalog

local tattooPrices = {}
for _, tattoo in ipairs(VHubSims.tattoos) do
  tattooPrices[tattoo.dlc .. ':' .. tattoo.hash] = tattoo.price
end

local function tattooSet(items)
  local output = {}
  for _, tattoo in ipairs(type(items) == 'table' and items or {}) do
    output[tattoo.dlc .. ':' .. tattoo.hash] = tattoo
  end
  return output
end

-- valida se todas as tatuagens pertencem ao catálogo do servidor
function Pricing.validTattoos(items)
  for _, tattoo in ipairs(type(items) == 'table' and items or {}) do
    if not tattooPrices[tattoo.dlc .. ':' .. tattoo.hash] then return false end
  end
  return true
end

-- calcula preço e chaves alteradas sem confiar no total do cliente
function Pricing.calculate(mode, before, after)
  local keys = AP.diff(before, after)
  if mode == 'creator' then return 0, keys end

  local amount = 0
  local prices = Catalog.prices[mode] or {}

  if mode == 'tattoo' then
    local previous = tattooSet(before.tattoos)
    local desired = tattooSet(after.tattoos)
    for key in pairs(desired) do
      if not previous[key] then amount = amount + (tattooPrices[key] or prices.add or 0) end
    end
    for key in pairs(previous) do
      if not desired[key] then amount = amount + (prices.remove or 0) end
    end
    return amount, keys
  end

  for _, key in ipairs(keys) do
    local index = tonumber(key:match('^drawable:(%d+)$'))
    if mode == 'barber' then
      if key == 'drawable:2' then amount = amount + (prices.hair or 0)
      elseif key == 'hair_color' then amount = amount + (prices.hair_color or 0)
      elseif key:match('^overlay:') then amount = amount + (prices.overlay or 0) end
    elseif mode == 'clothes' then
      if index then
        amount = amount + ((prices.drawable or {})[index] or 100)
      else
        index = tonumber(key:match('^prop:(%d+)$'))
        if index then amount = amount + ((prices.prop or {})[index] or 100) end
      end
    elseif mode == 'surgeon' then
      if key == 'heritage' then amount = amount + (prices.heritage or 0)
      elseif key == 'eye_color' then amount = amount + (prices.eye_color or 0)
      elseif key:match('^face:') then amount = amount + (prices.face or 0) end
    end
  end

  return amount, keys
end
