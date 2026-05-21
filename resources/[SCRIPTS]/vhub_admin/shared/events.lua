-- shared/events.lua  constantes de eventos
VHubAdmin   = VHubAdmin or {}
VHubAdmin.E = VHubAdmin.E or {}
local E     = VHubAdmin.E

-- Servidor   cliente
E.SETUP            = 'vhub_admin:setup'
E.NOTIFY           = 'vhub_admin:notify'
E.OPEN_UI          = 'vhub_admin:openUI'
E.CLOSE_UI         = 'vhub_admin:closeUI'
E.PLAYER_LIST      = 'vhub_admin:playerList'
E.REPORT_LIST      = 'vhub_admin:reportList'
E.LOG_LIST         = 'vhub_admin:logList'
E.RG_INFO          = 'vhub_admin:rgInfo'
E.DO_TP            = 'vhub_admin:doTp'
E.DO_HEAL          = 'vhub_admin:doHeal'
E.DO_REVIVE        = 'vhub_admin:doRevive'
E.TOGGLE_GOD       = 'vhub_admin:toggleGod'
E.TOGGLE_FREEZE    = 'vhub_admin:toggleFreeze'
E.TOGGLE_INVIS     = 'vhub_admin:toggleInvis'
E.TOGGLE_NOCLIP    = 'vhub_admin:toggleNoclip'
E.DO_SPAWNCAR      = 'vhub_admin:doSpawncar'
E.DO_DELVEH        = 'vhub_admin:doDelveh'
E.DO_FIX           = 'vhub_admin:doFix'
E.DO_TUNING        = 'vhub_admin:doTuning'
E.DO_CARCOLOR      = 'vhub_admin:doCarcolor'
E.DO_SKIN          = 'vhub_admin:doSkin'
E.DO_CLEARZONE     = 'vhub_admin:doClearzone'
E.DO_BLACKOUT      = 'vhub_admin:doBlackout'
E.DO_WEATHER       = 'vhub_admin:doWeather'
E.DO_TIME          = 'vhub_admin:doTime'
E.ANNOUNCE         = 'vhub_admin:announce'
E.STAFF_MSG        = 'vhub_admin:staffMsg'
E.SPEC_START       = 'vhub_admin:specStart'
E.SPEC_STOP        = 'vhub_admin:specStop'
E.SPEC_UPDATE      = 'vhub_admin:specUpdate'
E.JAIL_APPLY       = 'vhub_admin:jailApply'
E.JAIL_RELEASE     = 'vhub_admin:jailRelease'
E.IS_ADMIN         = 'vhub_admin:isAdmin'

-- Cliente   servidor
E.OPEN_PANEL       = 'vhub_admin:openPanel'
E.REQ_PLAYERS      = 'vhub_admin:reqPlayers'
E.REQ_REPORTS      = 'vhub_admin:reqReports'
E.REQ_LOGS         = 'vhub_admin:reqLogs'
E.REQ_RG           = 'vhub_admin:reqRG'
-- moderation
E.ACT_KICK         = 'vhub_admin:actKick'
E.ACT_BAN          = 'vhub_admin:actBan'
E.ACT_UNBAN        = 'vhub_admin:actUnban'
E.ACT_WL           = 'vhub_admin:actWhitelist'
E.ACT_UNWL         = 'vhub_admin:actUnwhitelist'
E.ACT_WARN         = 'vhub_admin:actWarn'
E.ACT_JAIL         = 'vhub_admin:actJail'
E.ACT_UNJAIL       = 'vhub_admin:actUnjail'
E.ACT_MUTE         = 'vhub_admin:actMute'
E.ACT_UNMUTE       = 'vhub_admin:actUnmute'
-- teleport
E.ACT_TP           = 'vhub_admin:actTp'
E.ACT_TPTOME       = 'vhub_admin:actTptome'
E.ACT_TPGO         = 'vhub_admin:actTpgo'
E.ACT_TPCDS        = 'vhub_admin:actTpcds'
E.ACT_TPALL        = 'vhub_admin:actTpall'
E.ACT_TPLAST       = 'vhub_admin:actTplast'
-- player
E.ACT_HEAL         = 'vhub_admin:actHeal'
E.ACT_HEALALL      = 'vhub_admin:actHealall'
E.ACT_GOD          = 'vhub_admin:actGod'
E.ACT_FREEZE       = 'vhub_admin:actFreeze'
E.ACT_REVIVE       = 'vhub_admin:actRevive'
E.ACT_REVIVEALL    = 'vhub_admin:actReviveall'
E.ACT_INVIS        = 'vhub_admin:actInvis'
E.ACT_SKIN         = 'vhub_admin:actSkin'
E.ACT_KILL         = 'vhub_admin:actKill'
-- vehicle
E.ACT_SPAWNCAR     = 'vhub_admin:actSpawncar'
E.ACT_DELVEH       = 'vhub_admin:actDelveh'
E.ACT_FIX          = 'vhub_admin:actFix'
E.ACT_TUNING       = 'vhub_admin:actTuning'
E.ACT_CARCOLOR     = 'vhub_admin:actCarcolor'
-- world
E.ACT_WEATHER      = 'vhub_admin:actWeather'
E.ACT_TIME         = 'vhub_admin:actTime'
E.ACT_BLACKOUT     = 'vhub_admin:actBlackout'
E.ACT_CLEARZONE    = 'vhub_admin:actClearzone'
E.ACT_ANNOUNCE     = 'vhub_admin:actAnnounce'
E.ACT_STAFFCHAT    = 'vhub_admin:actStaffchat'
-- spec
E.ACT_SPEC         = 'vhub_admin:actSpec'
-- reports
E.ACT_REPORT       = 'vhub_admin:actReport'
E.ACT_REPORT_CLAIM = 'vhub_admin:actReportClaim'
E.ACT_REPORT_CLOSE = 'vhub_admin:actReportClose'
-- money/inventory/groups (delegam aos resources)
E.ACT_GIVEMONEY    = 'vhub_admin:actGivemoney'
E.ACT_SETMONEY     = 'vhub_admin:actSetmoney'
E.ACT_GIVEITEM     = 'vhub_admin:actGiveitem'
E.ACT_CLEARINV     = 'vhub_admin:actClearinv'
E.ACT_ADDGROUP     = 'vhub_admin:actAddgroup'
E.ACT_DELGROUP     = 'vhub_admin:actDelgroup'

-- NUI postMessage actions
VHubAdmin.UI = {
  OPEN          = 'open',
  CLOSE         = 'close',
  PLAYER_LIST   = 'playerList',
  REPORT_LIST   = 'reportList',
  LOG_LIST      = 'logList',
  RG_INFO       = 'rgInfo',
  TOAST         = 'toast',
  ANNOUNCE      = 'announce',
  STATE_SYNC    = 'stateSync',
  SPEC_HUD      = 'specHud',
}
