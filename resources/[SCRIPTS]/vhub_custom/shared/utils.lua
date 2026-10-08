-- shared/utils.lua — helpers puros do vhub_custom
---@diagnostic disable: undefined-global, lowercase-global

VHubCustom   = VHubCustom or {}
VHubCustom.U = {}

local U = VHubCustom.U

U.pneus = { 0, 1, 2, 3, 4, 5, 6, 7, 45, 47 }

function U.indicesDano(valor, maximo, pneus)
  local lista, vistos = {}, {}
  if type(valor) ~= 'table' then return lista end
  local quantidade = 0
  for _, indice in pairs(valor) do
    quantidade = quantidade + 1
    if quantidade > 16 then return {} end
    if type(indice) == 'number' and indice == math.floor(indice) and indice >= 0
        and (indice <= maximo or (pneus and (indice == 45 or indice == 47))) and not vistos[indice] then
      vistos[indice] = true
      lista[#lista + 1] = indice
    end
  end
  table.sort(lista)
  return lista
end

function U.danoFisico(valor)
  valor = type(valor) == 'table' and valor or {}
  return { doors = U.indicesDano(valor.doors, 5), windows = U.indicesDano(valor.windows, 7),
    tyres = U.indicesDano(valor.tyres, 7, true), tyres_rim = U.indicesDano(valor.tyres_rim, 7, true) }
end

function U.contarPneus(dano)
  local vistos, quantidade = {}, 0
  for _, lista in ipairs({ dano.tyres or {}, dano.tyres_rim or {} }) do
    for _, indice in ipairs(lista) do
      if not vistos[indice] then vistos[indice] = true; quantidade = quantidade + 1 end
    end
  end
  return quantidade
end

-- Orçamento canônico. Lataria inclui portas/vidros, sem reparar motor ou pneus.
function U.reparo(estado, componente, precos)
  local dano = U.danoFisico(estado.damage)
  if componente == 'tyre' then
    local quantidade = U.contarPneus(dano)
    return { damage = { doors = dano.doors, windows = dano.windows, tyres = {}, tyres_rim = {} } },
      quantidade * precos.pneu, quantidade == 0
  end
  if componente ~= 'engine' and componente ~= 'body' then return nil end
  local chave = componente .. '_health'
  local saude = U.clamp(estado[chave], componente == 'engine' and -4000 or 0, 1000)
  if not saude then return nil end
  local pontos = math.max(0, 1000 - saude)
  local unidades = pontos >= 50 and math.ceil(pontos / 100) or 0
  if componente == 'body' then
    -- Deformação não possui snapshot persistível; serviço estrutural tem tarifa mínima explícita.
    unidades = math.max(unidades, 1)
    return { body_health = 1000.0, damage = { doors = {}, windows = {},
      tyres = dano.tyres, tyres_rim = dano.tyres_rim } }, unidades * precos.lataria_parcial, unidades == 0
  end
  return { engine_health = 1000.0 }, unidades * precos.motor_parcial, unidades == 0
end


-- ============================================================
-- NORMALIZAÇÃO
-- ============================================================

-- normaliza placa (upper + colapso de espaços internos + trim de bordas)
-- compatível com conce U.normalizePlate (mesmo algoritmo — evita divergência de chave)
function U.normalizePlate(plate)
  if type(plate) ~= 'string' then return nil end
  local p = plate:upper():gsub('%s+', ' '):match('^%s*(.-)%s*$')
  if not p or #p < 2 or #p > 8 then return nil end
  if not p:match('^[A-Z0-9][A-Z0-9 ]*[A-Z0-9]$') then return nil end
  return p
end

-- número finito no intervalo [lo, hi], ou nil
function U.clamp(v, lo, hi)
  if type(v) ~= 'number' or v ~= v or math.abs(v) == math.huge then return nil end
  return math.max(lo, math.min(hi, v))
end

-- inteiro finito no intervalo [lo, hi], ou nil
function U.integer(v, lo, hi)
  local n = tonumber(v)
  if not n or n ~= n or math.abs(n) == math.huge or n ~= math.floor(n) then return nil end
  if n < lo or n > hi then return nil end
  return math.floor(n)
end


-- ============================================================
-- VALIDAÇÃO DE PAYLOAD
-- ============================================================

-- retorna true se o payload é tabela não-vazia com tamanho plausível
function U.validPayload(p)
  return type(p) == 'table' and next(p) ~= nil
end

-- sanitiza tabela de mods {[idx]=level} → só indices integer 0..49
-- levels válidos: -1 (stock) até maxLvl (default 5 p/ stages de performance;
-- bennys passa 60 pois kits cosméticos têm MUITAS opções no GTA — limitar a 5
-- escondia opções reais do carro). filtra via whitelist opcional (set de índices).
function U.sanitizeMods(raw, whitelist, maxLvl)
  if type(raw) ~= 'table' then return nil end
  maxLvl = tonumber(maxLvl) or 5
  local out, n = {}, 0
  for k, v in pairs(raw) do
    local idx = tonumber(k)
    local lvl = tonumber(v)
    if idx and lvl and idx == math.floor(idx) and idx >= 0 and idx <= 49
       and lvl == math.floor(lvl) and lvl >= -1 and lvl <= maxLvl then
      if not whitelist or whitelist[idx] then
        out[idx] = lvl
        n = n + 1
        if n > 50 then return nil end  -- payload acima do plausível = hostil
      end
    end
  end
  return next(out) ~= nil and out or nil
end
