-- shared/events.lua — nomes canônicos dos eventos do Fuel v2

VHubFuel = VHubFuel or {}
VHubFuel.E = {
  START = 'vhub_fuel:server:start',
  STOP = 'vhub_fuel:server:stop',
  BUY_CAN = 'vhub_fuel:server:buyCan',
  ADMIN_SET = 'vhub_fuel:server:adminSet',
  STARTED = 'vhub_fuel:client:started',
  PROGRESS = 'vhub_fuel:client:progress',
  ENDED = 'vhub_fuel:client:ended',
}
