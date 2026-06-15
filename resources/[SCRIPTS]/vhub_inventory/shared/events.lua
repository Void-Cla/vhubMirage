---@diagnostic disable: undefined-global, lowercase-global

-- shared/events.lua — fonte UNICA de nomes de evento de rede (VHubInvE.*).
-- Mudar o valor de um nome aqui muda em todo o resource. Nunca duplicar string solta.

VHubInvE = {

  -- servidor -> cliente
  OPEN           = 'vhub_inventory:open',        -- snapshot completo ao abrir
  CLOSE          = 'vhub_inventory:close',
  DELTA          = 'vhub_inventory:delta',       -- diff de slots (mochila/baú)
  ROLLBACK       = 'vhub_inventory:rollback',    -- estado autoritativo dos slots tocados
  NOTIFY         = 'vhub_inventory:notify',      -- mensagem PT-BR efemera
  CONTAINER_OPEN  = 'vhub_inventory:container_open',   -- abre baú (snapshot baú + mochila)
  CONTAINER_DELTA = 'vhub_inventory:container_delta',  -- diff de slots do baú (a todos viewers)
  CONTAINER_CLOSE = 'vhub_inventory:container_close',  -- força fechar baú
  DROP_ADD       = 'vhub_inventory:drop_add',
  DROP_DEL       = 'vhub_inventory:drop_del',
  HUD            = 'vhub_inventory:hud',         -- { charId } -> Player Info HUD
  HOTBAR         = 'vhub_inventory:hotbar',      -- binds da hotbar (lista {slot,id})

  -- cliente -> servidor (INTENCAO — nunca verdade)
  USE            = 'vhub_inventory:use',         -- usar item do slot
  MOVE           = 'vhub_inventory:move',        -- mover/split/merge dentro da mochila
  DROP           = 'vhub_inventory:drop',        -- jogar no chao
  PICKUP         = 'vhub_inventory:pickup',      -- pegar do chao
  P2P            = 'vhub_inventory:p2p',         -- enviar para jogador proximo
  STORE          = 'vhub_inventory:store',       -- mochila -> baú
  RETRIEVE       = 'vhub_inventory:retrieve',    -- baú -> mochila
  OPEN_CONTAINER = 'vhub_inventory:open_container',  -- pede abrir baú { kind, name|group|netId }
  CLOSE_CONTAINER= 'vhub_inventory:close_container', -- avisa que fechou o baú
  REQUEST_SYNC   = 'vhub_inventory:request_sync',-- cliente pede snapshot
  HUD_REQ        = 'vhub_inventory:hud_req',     -- cliente pede o char_id do HUD
  SET_BIND       = 'vhub_inventory:set_bind',    -- vincula item a um slot da hotbar
  USE_HOTBAR     = 'vhub_inventory:use_hotbar',  -- usa item do slot da hotbar
}
