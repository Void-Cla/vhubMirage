---@diagnostic disable: undefined-global, lowercase-global

-- cfg/config.lua — nitro (vHub). Calibrar o "feel" do nitro = editar SÓ este arquivo.
-- Estado do nitro mora na PLACA (customization.nitro = {kit,qty,enabled,level}), via conce.
-- O NÍVEL (1..10) é escolhido na FICHA do veículo (vhub_vehcontrol) e calibra o trade-off
-- durabilidade↔velocidade. Aqui ficam só os ajustes; a verdade é a placa (decisão #30).

NitroCfg = {
  -- item da mochila (a "garrafa" de carga); recarrega pela FICHA (botão Abastecer)
  item         = 'nitro',
  chargePerUse = 100,    -- quanto de carga (0..100) cada garrafa aplica

  -- kit nitro = peça instalada na OFICINA (vhub_custom) — pré-requisito p/ ligar/calibrar/usar.
  -- O PREÇO do kit mora na oficina (vendedora): vhub_custom/server/oficina.lua NITRO_KIT_PRICE.

  -- efeito base (multiplicado pelo nível — ver LEVELS abaixo)
  durationSec   = 30,    -- duração de uma carga cheia (100) NO NÍVEL 1 (o nível só muda a TAXA)
  topSpeedBoost = 1.0,  -- ModifyVehicleTopSpeed BASE (×powerMult do nível)
  torqueBoost   = 2.0,   -- SetVehicleCheatPowerIncrease BASE (×powerMult do nível)
  exhaustFire   = true,  -- fogo no escapamento (mantido)
  fireSize      = 2.0,   -- escala do fogo

  -- ============================================================
  -- NÍVEIS (1..10) — trade-off durabilidade ↔ velocidade
  -- ============================================================
  -- powerMult   = quanto do boost base é aplicado (topspeed/torque). Nível 10 = DOBRO (2.0).
  -- consumeMult = quanto a carga drena por segundo, relativo ao base (durationSec).
  --   nível 1  (durabilidade): ganho PEQUENO, consumo PEQUENO → carga rende muito tempo.
  --   nível 10 (velocidade)  : ganho GRANDE (2x), consumo GRANDE → carga acaba rápido.
  -- Sobe ~10% em 10% entre o piso e o teto. Calibrar livremente sem tocar código de boost.
  LEVELS = {
    [1]  = { powerMult = 1.00, consumeMult = 0.50 },   -- durabilidade máxima
    [2]  = { powerMult = 1.11, consumeMult = 0.67 },
    [3]  = { powerMult = 1.22, consumeMult = 0.83 },
    [4]  = { powerMult = 1.33, consumeMult = 1.00 },
    [5]  = { powerMult = 1.44, consumeMult = 1.22 },
    [6]  = { powerMult = 1.56, consumeMult = 1.50 },
    [7]  = { powerMult = 1.67, consumeMult = 1.83 },
    [8]  = { powerMult = 1.78, consumeMult = 2.25 },
    [9]  = { powerMult = 1.89, consumeMult = 2.75 },
    [10] = { powerMult = 2.00, consumeMult = 3.50 },   -- velocidade máxima (dobro de potência)
  },

  -- modelos que não aceitam nitro (por spawn name)
  blacklist = { ['kuruma'] = true },
}
