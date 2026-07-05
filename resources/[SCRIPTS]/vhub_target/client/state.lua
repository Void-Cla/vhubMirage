-- client/state.lua — estado do targeting (ativo / foco NUI / desabilitado / travado)
---@diagnostic disable: undefined-global, lowercase-global

VHubTarget = VHubTarget or {}

local state = {}
VHubTarget.state = state

local isActive  = false
local nuiFocus  = false
local disabled  = false
local locked    = false   -- consumidor sinaliza "em progresso" (substituto do lib.progressActive)

-- retorna se o targeting está ativo (olho aberto)
function state.isActive()
  return isActive
end

-- ativa/desativa o targeting; mostrar a NUI é efeito colateral do ativar
function state.setActive(value)
  isActive = value
  if value then
    SendNuiMessage('{"event": "visible", "state": true}')
  end
end

-- retorna se a NUI está com foco de mouse
function state.isNuiFocused()
  return nuiFocus
end

-- aplica/remove foco NUI mantendo input do jogo (cursor centralizado ao focar)
function state.setNuiFocus(value, cursor)
  if value then SetCursorLocation(0.5, 0.5) end

  nuiFocus = value
  SetNuiFocus(value, cursor or false)
  SetNuiFocusKeepInput(value)
end

-- retorna se o targeting foi desabilitado por um consumidor (export disableTargeting)
function state.isDisabled()
  return disabled
end

-- desabilita/reabilita o targeting
function state.setDisabled(value)
  disabled = value
end

-- retorna se um consumidor travou o targeting (barra de progresso etc.)
function state.isLocked()
  return locked
end

-- trava/destrava o targeting (export setLocked)
function state.setLocked(value)
  locked = value == true
end
