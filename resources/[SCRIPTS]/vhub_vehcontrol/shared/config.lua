---@diagnostic disable: undefined-global, lowercase-global

-- shared/config.lua — ajustes do controle de veiculo (carregado client + server).

Config = {}

-- Teclas (tokens VALIDOS do FiveM; remapeaveis em Configuracoes > Atribuicao de teclas)
Config.keys = {
  lock        = 'L',      -- TOQUE: trança/destranca | SEGURAR: abre o painel
  signalLeft  = 'LEFT',   -- seta esq: pisca esquerdo (esq+dir juntas = pisca-alerta)
  signalRight = 'RIGHT',  -- seta dir: pisca direito
  windowUp    = 'UP',     -- seta cima: sobe a janela do seu assento
  windowDown  = 'DOWN',   -- seta baixo: abaixa a janela do seu assento
}
Config.command      = 'vehcontrol'  -- comando de chat p/ abrir o painel ('' = desliga)
Config.skillDebug   = false         -- DEBUG engine de skill no chat (F-051: true poluía produção)
Config.holdToOpenMs = 1000          -- tempo segurando a tecla de trava p/ abrir o painel
Config.distance     = 2.0           -- distancia p/ controlar veiculo proximo a pe (metros)

-- NUI ---------------------------------------------------------
Config.viewWindows = true       -- exibe os botoes de janela na NUI

-- Indice do pisca por lado (troque left<->right se aparecer espelhado no seu jogo)
Config.indicator = { left = 1, right = 0 }

-- Notificacao (ligue seu sistema aqui; padrao = feed nativo do GTA). So roda no client.
function Config.notify(msg)
  BeginTextCommandThefeedPost('STRING')
  AddTextComponentSubstringPlayerName(msg)
  EndTextCommandThefeedPostTicker(false, true)
end

-- Autoridade --------------------------------------------------
-- Trava e motor exigem chave do veiculo (vhub_inventory) OU ser dono (vhub_garage).
-- Portas/janelas/luzes/banco/camera sao locais (cosmeticos) e nao precisam de chave.
Config.requireKey = true

-- Mapeamento nome-da-NUI -> indice nativo GTA (NAO alterar — casa com o html)
Config.doorIndex   = { lfdoor = 0, rfdoor = 1, lrdoor = 2, rrdoor = 3, hood = 4, trunk = 5 }
Config.windowIndex = { lfdoor = 0, rfdoor = 1, lrdoor = 2, rrdoor = 3 }


-- ============================================================
-- ENGINE DE SKILL — manifestacao fisica (F5 / decisao #28)
-- ============================================================
-- O SERVIDOR calcula sheet.hnd (tier_rules.handlingFromAlloc) a partir do alloc;
-- o CLIENTE (client/handling.lua) APLICA so no carro que dirige, RE-CLAMPADO, e
-- RESTAURA o handling base ao sair (override do GTA e model-wide no cliente).
-- hnd NUNCA e persistido (e derivado do alloc; dono = conce). RECALIBRAR o "feel"
-- do jogo = editar SO as faixas abaixo (min->max por eixo). Seguro ligar/desligar.

Config.skillApplyHandling = false  -- DESLIGADO (dono 2026-08-05): motor de handling em runtime causava instabilidade; física volta ao .meta. Reativar só com o motor de peças (itens) validado in-game.
Config.skillBruteTest     = false -- F-052: true desligava o anti-P2W (alloc 0..100% por eixo) em produção
Config.skillGripMinRatio  = 0.85   -- fTractionCurveMin = grip * isto (mantem Min < Max)

-- ADR #85 F2.5-C: baseline JUSTO p/ carro sem p1 explícito (nativo). true = deriva p1 default dos
-- `stats` autorados no catálogo (vel/acel/freio/dir → classe D..S+ do balancer, base_alloc balanceado,
-- mass = massBase do tier). Assim nativo e mod entram no MESMO sistema de classes (anti-P2W). p1
-- EXPLÍCITO (balancer/.meta selado) SEMPRE vence. Kill-switch: false volta ao fail-closed (sem skill
-- em carro sem p1). Muda invariante "sem p1 = sem skill" → gate vhub_arquiteto PENDENTE (2026-08-09).
Config.defaultBaselineFromStats = true

-- ============================================================
-- CAMADA A per-entidade (ADR #82 FASE 2) — sub-flag da física, SEGURA (não model-wide)
-- ============================================================
-- Aplica SÓ potência+velocidade máxima derivadas das peças, via natives per-ENTIDADE
-- (SetVehicleCheatPowerIncrease/ModifyVehicleTopSpeed — confirmadas seguras pelo gate de
-- natives). NÃO toca CHandlingData (isso é Camada B model-wide = ADR #83, applyModelWide).
-- Dois carros do mesmo modelo podem ter potências diferentes (objetivo da FASE 2).
-- DEFAULT false: ligar só após smoke in-game (peça muda aceleração/topo; nitro soma sobre a base).
Config.applyPerEntity = false
Config.applyModelWide = false  -- Camada B (peso/grip/freio/susp) — GATED por ADR #83, NÃO ativar aqui

-- eixo -> { field do CHandlingData, valor no alloc MINIMO do eixo, valor no MAXIMO }.
-- valor aplicado = lerp(min, max, fracao normalizada do eixo na sua faixa). min>max = inverso.
-- REMOVER um eixo daqui = esse eixo NAO vira fisica (fica o do .meta) -> modelo hibrido.
Config.skillHandling = {
  potencia  = { field = 'fInitialDriveForce', min = 0.14, max = 0.46 },
  grip      = { field = 'fTractionCurveMax',  min = 1.55, max = 2.95 },
  frenagem  = { field = 'fBrakeForce',        min = 0.55, max = 1.65 },
  aero      = { field = 'fInitialDragCoeff',  min = 6.0,  max = 18.0 },
  suspensao = { field = 'fAntiRollBarForce',  min = 0.05, max = 1.50 },
}

-- ============================================================
-- OVERLAY DE HANDLING (tuning livre) — decisão do dono 2026-08-04
-- ============================================================
-- Campos DISJUNTOS dos 5 eixos acima (nunca colidem). NÃO são derivados do alloc: vêm de
-- customization.handling_ext (knobs absolutos). O motor (client/handling.lua) aplica DEPOIS
-- dos 5 eixos, cada um re-clampado à sua banda (valor absoluto). Ausência no customization =
-- campo NÃO tocado (base do .meta preservada). Mass/bias FORA (identidade/física crítica).
-- NB: STANCE saiu daqui (2026-08-06) — altura/rebaixamento é 100% de vhub_custom
-- (client/stance.lua, per-entidade via State Bag). SetVehicleHandlingFloat(fSuspensionRaise)
-- era model-wide e instável. Ver [[handling-engine-blueprint]] (linha de stance REVOGADA).
Config.skillHandlingExt = {
  handbrake  = { field = 'fHandBrakeForce',            min = 0.50,  max = 3.00 },
  steering   = { field = 'fSteeringLock',              min = 28.0,  max = 50.0 },
  low_speed  = { field = 'fLowSpeedTractionLossMult',  min = 0.20,  max = 3.00 },
  susp_force = { field = 'fSuspensionForce',           min = 2.00,  max = 6.00 },
}
