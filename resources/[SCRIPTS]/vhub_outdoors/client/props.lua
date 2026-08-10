-- client/props.lua - ciclo de vida e alinhamento dos props locais

local CFG = VHubOutdoors.cfg
local M = {}
VHubOutdoors.Props = M

local function coordenada(raw)
  local kind = type(raw)
  if kind ~= 'table' and kind ~= 'vector3' and kind ~= 'vector4' then return nil end
  local x = VHubOutdoors.finite(raw.x)
  local y = VHubOutdoors.finite(raw.y)
  local z = VHubOutdoors.finite(raw.z)
  if not x or not y or not z then return nil end
  return { x = x, y = y, z = z }
end

local function configuracao(preset)
  local prop = type(preset) == 'table' and preset.prop or nil
  local tela = type(prop) == 'table' and prop.tela or nil
  if type(prop) ~= 'table' or type(prop.modelo) ~= 'string'
      or type(tela) ~= 'table'
      or (prop.frente ~= -1.0 and prop.frente ~= 1.0) then
    return nil
  end
  return prop, tela
end

function M.centroDaTela(ancora, preset, normal)
  local centro = coordenada(ancora)
  local prop, tela = configuracao(preset)
  if not centro or not prop then return nil end
  if preset.modo == 'chao' then
    normal = coordenada(normal)
    if not normal then return nil end
    local centro_x = (tela.min_x + tela.max_x) * 0.5
    local centro_y = tela.y
    local frente_x = normal.x * prop.frente
    local frente_y = normal.y * prop.frente
    local direita_x = frente_y
    local direita_y = -frente_x
    centro.x = centro.x + direita_x * centro_x + frente_x * centro_y
    centro.y = centro.y + direita_y * centro_x + frente_y * centro_y
    centro.z = centro.z
      + (tela.min_z + tela.max_z) * 0.5
      - (prop.solo_z or 0.0)
  end
  return centro
end

function M.aplicarDeslocamento(centro, normal)
  centro = coordenada(centro)
  normal = coordenada(normal)
  if not centro or not normal then return nil end
  return {
    x = centro.x + normal.x * CFG.limits.surface_offset,
    y = centro.y + normal.y * CFG.limits.surface_offset,
    z = centro.z,
  }
end

function M.normalDaGeometria(item)
  local esquerda = coordenada(item and item.top_left)
  local direita = coordenada(item and item.bottom_right)
  if not esquerda or not direita then return nil end
  local dx = direita.x - esquerda.x
  local dy = direita.y - esquerda.y
  local largura = math.sqrt(dx * dx + dy * dy)
  if largura < 0.001 then return nil end
  return { x = dy / largura, y = -dx / largura, z = 0.0 }
end

function M.carregarModelo(preset)
  local prop = configuracao(preset)
  if not prop then return nil end
  local hash = GetHashKey(prop.modelo)
  if not IsModelInCdimage(hash) or not IsModelValid(hash) then return nil end

  RequestModel(hash)
  local limite = GetGameTimer() + CFG.renderer.model_timeout_ms
  while not HasModelLoaded(hash) and GetGameTimer() < limite do Wait(0) end
  if not HasModelLoaded(hash) then
    SetModelAsNoLongerNeeded(hash)
    return nil
  end
  return hash
end

function M.superficie(entidade, preset, normal)
  local prop, tela = configuracao(preset)
  normal = coordenada(normal)
  if not prop or not normal
      or not entidade or entidade == 0 or not DoesEntityExist(entidade) then
    return nil
  end

  local y = tela.y
  local offset = VHubOutdoors.finite(tela.offset)
    or CFG.renderer.prop_surface_offset
  local esquerda_x = prop.frente < 0.0 and tela.min_x or tela.max_x
  local direita_x = prop.frente < 0.0 and tela.max_x or tela.min_x
  local function vertice(x, z)
    local ponto = GetOffsetFromEntityInWorldCoords(entidade, x, y, z)
    return {
      x = ponto.x + normal.x * offset,
      y = ponto.y + normal.y * offset,
      z = ponto.z + normal.z * offset,
    }
  end
  return {
    top_left = vertice(esquerda_x, tela.max_z),
    top_right = vertice(direita_x, tela.max_z),
    bottom_left = vertice(esquerda_x, tela.min_z),
    bottom_right = vertice(direita_x, tela.min_z),
  }
end

function M.alinhar(entidade, preset, centro, normal)
  centro = coordenada(centro)
  normal = coordenada(normal)
  local prop, tela = configuracao(preset)
  if not centro or not normal or not prop
      or not entidade or entidade == 0 or not DoesEntityExist(entidade) then
    return nil
  end

  local heading = math.deg(math.atan(
    -normal.x * prop.frente,
    normal.y * prop.frente
  )) % 360.0
  SetEntityHeading(entidade, heading)
  SetEntityCoordsNoOffset(entidade, centro.x, centro.y, centro.z, false, false, false)

  local tela_centro = GetOffsetFromEntityInWorldCoords(
    entidade,
    (tela.min_x + tela.max_x) * 0.5,
    tela.y,
    (tela.min_z + tela.max_z) * 0.5
  )
  local origem = GetEntityCoords(entidade)
  SetEntityCoordsNoOffset(
    entidade,
    origem.x + centro.x - tela_centro.x,
    origem.y + centro.y - tela_centro.y,
    origem.z + centro.z - tela_centro.z,
    false, false, false
  )
  return M.superficie(entidade, preset, normal)
end

function M.criar(preset, hash, centro, normal, alpha)
  centro = coordenada(centro)
  normal = coordenada(normal)
  if not hash or not centro or not normal or not HasModelLoaded(hash) then return nil end
  local entidade = CreateObjectNoOffset(
    hash, centro.x, centro.y, centro.z, false, false, false
  )
  if not entidade or entidade == 0 or not DoesEntityExist(entidade) then
    SetModelAsNoLongerNeeded(hash)
    return nil
  end

  SetEntityAsMissionEntity(entidade, true, true)
  SetEntityCollision(entidade, false, false)
  SetEntityInvincible(entidade, true)
  local visual = type(preset.visual) == 'table' and preset.visual or nil
  local lod_distance = visual and VHubOutdoors.finite(visual.unload_distance) or nil
  if lod_distance then SetEntityLodDist(entidade, math.floor(lod_distance + 0.5)) end
  FreezeEntityPosition(entidade, true)
  if alpha then SetEntityAlpha(entidade, alpha, false) end

  local superficie = M.alinhar(entidade, preset, centro, normal)
  SetModelAsNoLongerNeeded(hash)
  if superficie then return entidade, superficie end
  DeleteObject(entidade)
  return nil
end

function M.remover(entidade)
  if entidade and entidade ~= 0 and DoesEntityExist(entidade) then
    SetEntityAsMissionEntity(entidade, true, true)
    DeleteObject(entidade)
  end
end
