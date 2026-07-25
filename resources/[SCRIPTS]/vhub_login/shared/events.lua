-- shared/events.lua — contratos de eventos do gate de login (R9)

VHubLogin = VHubLogin or {}

VHubLogin.E = {
  OPEN = "vhub_login:open",
  AUTH_OK = "vhub_login:authOK",
  AUTH_FAIL = "vhub_login:authFail",
  RECOVERY_DONE = "vhub_login:recoveryDone",
  CHAR_OK = "vhub_login:charOK",
  CHAR_FAIL = "vhub_login:charFail",
  PROCEED_SPAWN = "vhub_login:proceedSpawn",
  CREATION_HANDOFF = "vhub_login:creationHandoff",
  CREATION_RETURN = "vhub_login:creationReturn",
  CREATION_DONE = VHubSims.E.CREATION_DONE,
  CREATION_CANCELLED = VHubSims.E.CREATION_CANCELLED,

  TRY_LOGIN = "vhub_login:tryLogin",
  TRY_REGISTER = "vhub_login:tryRegister", -- legado depreciado em 0.2.0
  TRY_REGISTER_V2 = "vhub_login:tryRegisterV2",
  TRY_RECOVERY = "vhub_login:tryRecovery",
  PICK_CHAR = "vhub_login:pickChar",
  REQUEST_CREATE = "vhub_login:requestCreate",

  SELECTOR_OPEN = VHubSpawnSelector.E.OPEN,
  SELECTOR_REQUEST_OPEN = VHubSpawnSelector.E.REQUEST_OPEN,
}
