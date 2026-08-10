-- events.lua — contratos públicos do seletor de spawn

VHubSpawnSelector = VHubSpawnSelector or {}

VHubSpawnSelector.E = {
  OPEN = 'vhub_spawselector:client:Open',
  REQUEST_OPEN = 'vhub_spawselector:server:RequestOpen',
  REQUEST_SPAWN = 'vhub_spawselector:server:RequestSpawn',
  REQUEST_BACK = 'vhub_spawselector:server:RequestBack',
  RESULT = 'vhub_spawselector:client:Result',
  BACK = 'vhub_spawselector:client:Back',
  COMPLETE = 'vhub_spawselector:client:Complete',
}
