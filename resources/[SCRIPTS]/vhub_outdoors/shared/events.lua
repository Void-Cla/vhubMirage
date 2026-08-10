-- shared/events.lua - registro unico dos eventos de rede

VHubOutdoors = VHubOutdoors or {}

VHubOutdoors.E = {
  OPEN_CREATE_UI = 'vhub_outdoors:client:openCreateUi',
  REQUEST_PLACEMENT = 'vhub_outdoors:server:requestPlacement',
  BEGIN_PLACEMENT = 'vhub_outdoors:client:beginPlacement',
  SUBMIT_PLACEMENT = 'vhub_outdoors:server:submitPlacement',
  REQUEST_REMOVE = 'vhub_outdoors:server:requestRemove',
  UPDATE_ADMIN = 'vhub_outdoors:client:updateAdmin',
  OPEN_REMOTE_UI = 'vhub_outdoors:client:openRemoteUi',
  UPDATE_REMOTE_UI = 'vhub_outdoors:client:updateRemoteUi',
  REMOTE_SET_MEDIA = 'vhub_outdoors:server:remoteSetMedia',
  REMOTE_SET_VOLUME = 'vhub_outdoors:server:remoteSetVolume',
  REMOTE_REQUEST_MOVE = 'vhub_outdoors:server:remoteRequestMove',
  BEGIN_REMOTE_MOVE = 'vhub_outdoors:client:beginRemoteMove',
  SUBMIT_REMOTE_MOVE = 'vhub_outdoors:server:submitRemoteMove',
}
