-- shared/events.lua — contratos de evento do vhub_voicePMA (R9)

VHubVoicePMA = VHubVoicePMA or {}

VHubVoicePMA.E = {
  SYNC_REQUEST = 'vhub_voicePMA:syncRequest',
  SYNC = 'vhub_voicePMA:sync',
  MODE_REQUEST = 'vhub_voicePMA:modeRequest',
  MODE_CHANGED = 'vhub_voicePMA:modeChanged',
  PROXIMITY_TALK_REQUEST = 'vhub_voicePMA:proximityTalkRequest',
  RADIO_REQUEST = 'vhub_voicePMA:radioRequest',
  RADIO_SYNC = 'vhub_voicePMA:radioSync',
  RADIO_MEMBER = 'vhub_voicePMA:radioMember',
  RADIO_TALK_REQUEST = 'vhub_voicePMA:radioTalkRequest',
  RADIO_TALK = 'vhub_voicePMA:radioTalk',
  RADIO_ACTIVE = 'vhub_voicePMA:radioActive',
  CALL_SYNC = 'vhub_voicePMA:callSync',
  CALL_MEMBER = 'vhub_voicePMA:callMember',
  CALL_TALK_REQUEST = 'vhub_voicePMA:callTalkRequest',
  CALL_TALK = 'vhub_voicePMA:callTalk',
  NOTIFY = 'vHub:notify',
  CHARACTER_LOAD = 'vHub:characterLoad',
}
