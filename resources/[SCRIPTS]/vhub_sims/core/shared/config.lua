-- config.lua — limites, modos e orçamento do SIMS
---@diagnostic disable: undefined-global, lowercase-global

VHubSims = VHubSims or {}

VHubSims.cfg = {
  max_payload_bytes = 8192,
  max_outfits = 10,
  shop_radius = 3.0,
  paid_session_ttl_ms = 300000,
  creator_session_ttl_ms = 900000,
  rates = {
    begin = 1000,
    open = 1000,
    checkout = 1500,
    wizard = 1000,
    cancel = 500,
    outfit_list = 1000,
    outfit_save = 1500,
    outfit_rename = 1000,
    outfit_delete = 1000,
    outfit_apply = 1500,
  },
  trusted = {
    needs_creation     = { vhub_login = true },
    begin_creation     = { vhub_login = true },
    cancel_creation    = { vhub_login = true },
    force_resolve_saga = { vhub_admin = true },
  },
}
