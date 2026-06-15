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
