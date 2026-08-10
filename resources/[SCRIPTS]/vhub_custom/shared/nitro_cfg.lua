---@diagnostic disable: undefined-global, lowercase-global

-- shared/nitro_cfg.lua — configuração do nitro (FASE 2 ADR #81).
-- Calibrar o "feel" do nitro = editar SÓ este arquivo.
-- Estado do nitro mora na PLACA (customization.nitro = {kit,qty,enabled,level}) via conce.

VHubCustom          = VHubCustom or {}
VHubCustom.NitroCfg = {
  item         = 'nitro',
  chargePerUse = 100,

  durationSec   = 30,
  topSpeedBoost = 1.0,
  torqueBoost   = 2.0,
  exhaustFire   = true,
  fireSize      = 2.0,

  LEVELS = {
    [1]  = { powerMult = 1.00, consumeMult = 0.50 },
    [2]  = { powerMult = 1.11, consumeMult = 0.67 },
    [3]  = { powerMult = 1.22, consumeMult = 0.83 },
    [4]  = { powerMult = 1.33, consumeMult = 1.00 },
    [5]  = { powerMult = 1.44, consumeMult = 1.22 },
    [6]  = { powerMult = 1.56, consumeMult = 1.50 },
    [7]  = { powerMult = 1.67, consumeMult = 1.83 },
    [8]  = { powerMult = 1.78, consumeMult = 2.25 },
    [9]  = { powerMult = 1.89, consumeMult = 2.75 },
    [10] = { powerMult = 2.00, consumeMult = 3.50 },
  },

  blacklist = { ['kuruma'] = true },
}
