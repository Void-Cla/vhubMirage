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
Config.skillDebug   = true          -- DEBUG engine de skill: diagnostica resolução de ficha no chat (DESLIGAR após validar)
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

Config.skillApplyHandling = true   -- liga a fisica derivada (false = so numeros, .meta intacto)
Config.skillBruteTest     = true  -- TESTE: libera alloc 0..100% por eixo (builds extremas). Producao = false
Config.skillGripMinRatio  = 0.85   -- fTractionCurveMin = grip * isto (mantem Min < Max)

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
