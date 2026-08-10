-- shared/compat.lua — RESOLVEDOR PURO de compatibilidade de peças (ADR #85 F2.5-A).
--
-- Função pura, ZERO I/O (sem SQL/native/export/State Bag) — mesmo contrato de parts_catalog/tier_rules:
-- recebe dados, devolve status. É o JUÍZO ÚNICO de install/remove; o server (core.lua) delega aqui e
-- reusa no payload de auth (init.lua) — a NUI nunca é autoridade. `class_budget`/stageCap NÃO bloqueiam
-- mais (viram `hint`); o gate REAL é compatibilidade: família/conflito/dependência/item/já-instalada.
--
-- ENTRADAS:
--   part      def da peça (parts_catalog) — usa .id/.gta_mod/.replaces/.conflicts/.requires/.item
--   curParts  customization.parts persistido = { [id] = truthy|false } (LEITURA-ONLY)
--   cap       teto de stage do chassi (Core.stageCap) — usado SÓ p/ hint, NUNCA p/ barrar
--   hasItem   function(itemId) -> bool  (posse no inventário; nil = não checa)
--
-- SAÍDA: { state, hint?, replaces? }
--   state     ok | already_installed | conflict | requires_missing | missing_item
--   hint      aviso não-bloqueante (stage acima do ideal da classe) ou nil
--   replaces  ids INSTALADOS que esta peça troca (p/ NUI "substitui X") ou nil
---@diagnostic disable: undefined-global, lowercase-global

VHubCustom = VHubCustom or {}
local Compat = {}
VHubCustom.Compat = Compat


-- ============================================================
-- RESOLUÇÃO (pura, determinística — mesma entrada → mesmo status)
-- ============================================================

-- resolve o status de UMA peça contra o estado atual do veículo
function Compat.resolve(part, curParts, cap, hasItem)
  if type(part) ~= 'table' then return { state = 'conflict' } end

  -- set de peças INSTALADAS (slot truthy; [id]=false = removido, não conta — merge esparso)
  local installed = {}
  if type(curParts) == 'table' then
    for id, v in pairs(curParts) do
      if v ~= nil and v ~= false then installed[id] = true end
    end
  end

  -- hint do DNA/classe: stageCap rebaixado a dica (nunca barra — ADR #85 D1)
  local hint
  local gtaMod = type(part.gta_mod) == 'table' and part.gta_mod or nil
  if gtaMod and (tonumber(gtaMod.stage) or 0) > (tonumber(cap) or 0) then
    hint = 'Acima do ideal para a classe deste veículo.'
  end

  -- peças que ESTA troca e já estão instaladas (substituição válida ≠ conflito)
  local replaces
  if type(part.replaces) == 'table' then
    for _, rid in ipairs(part.replaces) do
      if installed[rid] then replaces = replaces or {}; replaces[#replaces + 1] = rid end
    end
  end

  local function status(state) return { state = state, hint = hint, replaces = replaces } end

  if part.id and installed[part.id] then return status('already_installed') end

  -- conflito: qualquer peça conflitante instalada — checado contra o SET COMPLETO (cond. 1 da ADR #85)
  if type(part.conflicts) == 'table' then
    for _, cid in ipairs(part.conflicts) do
      if installed[cid] then return status('conflict') end
    end
  end

  -- dependência: qualquer requisito ausente do set instalado
  if type(part.requires) == 'table' then
    for _, rid in ipairs(part.requires) do
      if not installed[rid] then return status('requires_missing') end
    end
  end

  -- item de inventário exigido pela peça (a tomada real é do handler)
  if type(part.item) == 'string' and hasItem and not hasItem(part.item) then
    return status('missing_item')
  end

  return status('ok')
end


return Compat
