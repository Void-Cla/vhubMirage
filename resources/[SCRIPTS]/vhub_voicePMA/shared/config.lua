-- shared/config.lua — limites e politicas do motor de voz

VHubVoicePMA = VHubVoicePMA or {}

VHubVoicePMA.Cfg = {
  DEFAULT_MODE = 2,
  MODES = {
    [1] = { label = 'Sussurrando', distance = 3.0, duck = 0.55 },
    [2] = { label = 'Normal', distance = 8.0, duck = 0.80 },
    [3] = { label = 'Gritando', distance = 18.0, duck = 1.00 },
  },

  DEFAULT_RADIO_VOLUME = 0.35,
  DEFAULT_CALL_VOLUME = 0.60,
  RADIO_DUCK = 0.90,
  CALL_DUCK = 0.80,

  RADIO = {
    MIN_CHANNEL = 1,
    MAX_CHANNEL = 999,
    MAX_MEMBERS = 128,
    ITEM = 'radio',
    REQUIRE_ITEM = true,
    REVALIDATE_MS = 5000,
    PERMISSION_RANGES = {
      { min = 900, max = 999, permission = 'policia.radio' },
    },
  },

  CALL = {
    MIN_CHANNEL = 1,
    MAX_CHANNEL = 2147483647,
    MAX_MEMBERS = 64,
    REVALIDATE_MS = 5000,
  },

  RATE_MS = {
    sync = 1000,
    mode = 300,
    radio = 500,
    call = 250,
    radio_talk = 80,
    call_talk = 80,
    proximity_talk = 80,
  },

  CLIENT = {
    MODE_KEY = 'F11',
    RADIO_KEY = 'CAPITAL',
    TALK_INTERVAL_MS = 125,
    DUCK_INTERVAL_MS = 200,
    DUCK_DELTA = 0.02,
  },

  TRUSTED_SERVER_RESOURCES = {
    ['vhub_admin'] = true,
    ['vhub_ipad'] = true,
  },

  TRUSTED_CLIENT_RESOURCES = {
    ['vhub_ipad'] = true,
  },
}
