-- shared/config.lua — namespace + configuração estática do vhub_ferinha
---@diagnostic disable: undefined-global, lowercase-global

VHubFerinha     = VHubFerinha or {}
VHubFerinha.cfg = {

  -- ============================================================
  -- LEILÃO (migrado de vhub_garage/auction — FASE 4)
  -- ============================================================
  auction_fee          = 100,    -- taxa de listagem (não-reembolsável)
  auction_dur_default  = 60,     -- duração padrão (minutos)
  auction_dur_min      = 5,      -- mínimo (minutos)
  auction_dur_max      = 1440,   -- máximo (minutos)
  auction_increment    = 0.05,   -- lance mínimo = +5% sobre o atual

  -- ============================================================
  -- ZONA DA CASA DE LEILÕES (decisão #25 — dono da config de localização)
  -- L-19: `coord` = vec3 (blip/zona, sem heading). O garage faz PULL no boot
  -- (exports.vhub_ferinha:getZones) e renderiza a engine de presença única;
  -- vec NÃO cruza fronteira → getZones devolve flat {x,y,z}.
  -- ============================================================
  leilao_local = {
    id    = 'auction_house',
    label = 'Casa de Leilões',
    coord = vec3(-45.61, -1693.55, 29.62), raio = 6.0,
    blip  = { sprite = 431, color = 46, scale = 0.85 },
  },
}

-- Contrato de UI: o leilão usa a NUI do vhub_garage (dono da apresentação),
-- então ferinha emite os mesmos eventos de cliente do garage.
VHubFerinha.GARAGE_UI = {
  UPDATE_AUCTION = 'vhub_garage:updateAuction',
}
