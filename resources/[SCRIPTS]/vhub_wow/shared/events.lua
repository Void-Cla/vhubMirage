-- shared/events.lua — contratos de evento do vhub_wow (R9)

VHubWOW = VHubWOW or {}

VHubWOW.E = {
  PLAY = 'vhub_wow:play',
  PLAY_AT_ENTITY = 'vhub_wow:playAtEntity',
  PLAY_AT_COORDS = 'vhub_wow:playAt',
  DESTROY = 'vhub_wow:destroy',
  PAUSE = 'vhub_wow:pause',
  RESUME = 'vhub_wow:resume',
  SET_VOLUME = 'vhub_wow:setVolume',
  SET_DISTANCE = 'vhub_wow:setDistance',
  SEARCH_RESULTS = 'vhub_wow:searchResults',
  AUDIO_LIFECYCLE_LOCAL = 'vhub_wow:audioLifecycle',
  AUDIO_LIFECYCLE_REPORT = 'vhub_wow:server:audioLifecycleReport',
  AUDIO_LIFECYCLE_SERVER = 'vhub_wow:server:audioLifecycle',
}
