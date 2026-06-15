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
}

-- Contrato de UI: o leilão usa a NUI do vhub_garage (dono da apresentação),
-- então ferinha emite os mesmos eventos de cliente do garage.
VHubFerinha.GARAGE_UI = {
  UPDATE_AUCTION = 'vhub_garage:updateAuction',
}
