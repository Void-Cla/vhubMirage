-- shared/events.lua — registro único de eventos do vhub_admin

VHubAdmin = VHubAdmin or {}
VHubAdmin.E = VHubAdmin.E or {}
local E = VHubAdmin.E

-- Servidor → cliente
E.SETUP             = 'vhub_admin:setup'
E.NOTIFY            = 'vhub_admin:notify'
E.DASHBOARD         = 'vhub_admin:dashboard'
E.PLAYER_LIST       = 'vhub_admin:playerList'
E.PROFILE           = 'vhub_admin:profile'
E.WALL_STATE        = 'vhub_admin:wallState'
E.WALL_SNAPSHOT     = 'vhub_admin:wallSnapshot'
E.REPORT_LIST       = 'vhub_admin:reportList'
E.LOG_LIST          = 'vhub_admin:logList'
E.FLEET_LIST        = 'vhub_admin:fleetList'
E.FLEET_DETAIL      = 'vhub_admin:fleetDetail'
E.REQUEST_WAYPOINT  = 'vhub_admin:requestWaypoint'
E.RESOLVE_WAYPOINT  = 'vhub_admin:resolveWaypoint'
E.TOGGLE_GOD        = 'vhub_admin:toggleGod'
E.TOGGLE_FREEZE     = 'vhub_admin:toggleFreeze'
E.TOGGLE_INVIS      = 'vhub_admin:toggleInvis'
E.TOGGLE_NOCLIP     = 'vhub_admin:toggleNoclip'
E.NOCLIP_LEASE      = 'vhub_admin:noclipLease'
E.TOGGLE_STAMINA    = 'vhub_admin:toggleStamina'
E.TOGGLE_JUMP       = 'vhub_admin:toggleJump'
E.DO_CLEANPED       = 'vhub_admin:doCleanped'
E.DO_CLEARZONE      = 'vhub_admin:doClearzone'
E.DO_SPAWNCAR       = 'vhub_admin:doSpawncar'
E.DO_DELVEH         = 'vhub_admin:doDelveh'
E.DO_FIX            = 'vhub_admin:doFix'
E.DO_BOOST          = 'vhub_admin:doBoost'
E.DO_FLIP           = 'vhub_admin:doFlip'
E.DO_TUNING         = 'vhub_admin:doTuning'
E.DO_CARCOLOR       = 'vhub_admin:doCarcolor'
E.DO_BLACKOUT       = 'vhub_admin:doBlackout'
E.DO_WEATHER        = 'vhub_admin:doWeather'
E.DO_TIME           = 'vhub_admin:doTime'
E.ANNOUNCE          = 'vhub_admin:announce'
E.STAFF_MSG         = 'vhub_admin:staffMsg'
E.SPEC_START        = 'vhub_admin:specStart'
E.SPEC_STOP         = 'vhub_admin:specStop'
E.SPEC_UPDATE       = 'vhub_admin:specUpdate'
E.JAIL_APPLY        = 'vhub_admin:jailApply'
E.JAIL_RELEASE      = 'vhub_admin:jailRelease'

-- Cliente → servidor: consultas
E.OPEN_PANEL        = 'vhub_admin:openPanel'
E.REQ_DASHBOARD     = 'vhub_admin:reqDashboard'
E.REQ_PLAYERS       = 'vhub_admin:reqPlayers'
E.REQ_PROFILE       = 'vhub_admin:reqProfile'
E.REQ_WALL_TOGGLE   = 'vhub_admin:reqWallToggle'
E.REQ_WALL_SNAPSHOT = 'vhub_admin:reqWallSnapshot'
E.REQ_REPORTS       = 'vhub_admin:reqReports'
E.REQ_LOGS          = 'vhub_admin:reqLogs'
E.REQ_FLEET         = 'vhub_admin:reqFleet'
E.REQ_FLEET_DETAIL  = 'vhub_admin:reqFleetDetail'

-- Cliente → servidor: moderação
E.ACT_KICK          = 'vhub_admin:actKick'
E.ACT_BAN           = 'vhub_admin:actBan'
E.ACT_UNBAN         = 'vhub_admin:actUnban'
E.ACT_WARN          = 'vhub_admin:actWarn'
E.ACT_JAIL          = 'vhub_admin:actJail'
E.ACT_UNJAIL        = 'vhub_admin:actUnjail'
E.ACT_MUTE          = 'vhub_admin:actMute'
E.ACT_UNMUTE        = 'vhub_admin:actUnmute'

-- Cliente → servidor: deslocamento e pessoas
E.ACT_TP            = 'vhub_admin:actTp'
E.ACT_TPTOME        = 'vhub_admin:actTptome'
E.ACT_TPGO          = 'vhub_admin:actTpgo'
E.ACT_TPWAYPOINT_BEGIN = 'vhub_admin:actTpWaypointBegin'
E.ACT_TPWAYPOINT    = 'vhub_admin:actTpWaypoint'
E.ACT_TPCDS         = 'vhub_admin:actTpcds'
E.ACT_TPALL         = 'vhub_admin:actTpall'
E.ACT_TPLAST        = 'vhub_admin:actTplast'
E.ACT_TPZ           = 'vhub_admin:actTpz'
E.ACT_HEAL          = 'vhub_admin:actHeal'
E.ACT_HEALALL       = 'vhub_admin:actHealall'
E.ACT_GOD           = 'vhub_admin:actGod'
E.ACT_NOCLIP        = 'vhub_admin:actNoclip'
E.ACT_FREEZE        = 'vhub_admin:actFreeze'
E.ACT_REVIVE        = 'vhub_admin:actRevive'
E.ACT_REVIVEALL     = 'vhub_admin:actReviveall'
E.ACT_INVIS         = 'vhub_admin:actInvis'
E.ACT_KILL          = 'vhub_admin:actKill'
E.ACT_STAMINA       = 'vhub_admin:actStamina'
E.ACT_JUMP          = 'vhub_admin:actJump'
E.ACT_CLEANPED      = 'vhub_admin:actCleanped'
E.ACT_SPEC          = 'vhub_admin:actSpec'
E.ACT_SKIN          = 'vhub_admin:actSkin'

-- Cliente → servidor: veículo (server valida perm → re-dispara DO_ ao cliente)
E.ACT_SPAWNCAR      = 'vhub_admin:actSpawncar'
E.ACT_DELVEH        = 'vhub_admin:actDelveh'
E.ACT_FIX           = 'vhub_admin:actFix'
E.ACT_BOOST         = 'vhub_admin:actBoost'
E.ACT_FLIP          = 'vhub_admin:actFlip'
E.ACT_TUNING        = 'vhub_admin:actTuning'
E.ACT_CARCOLOR      = 'vhub_admin:actCarcolor'

-- Cliente → servidor: frota persistente
E.ACT_FLEET_GIVE       = 'vhub_admin:actFleetGive'
E.ACT_FLEET_TRANSFER   = 'vhub_admin:actFleetTransfer'
E.ACT_FLEET_DELETE     = 'vhub_admin:actFleetDelete'
E.ACT_FLEET_STATUS     = 'vhub_admin:actFleetStatus'
E.ACT_FLEET_IPVA       = 'vhub_admin:actFleetIpva'
E.ACT_FLEET_RELEASE    = 'vhub_admin:actFleetRelease'
E.ACT_FLEET_GRANT_KEY  = 'vhub_admin:actFleetGrantKey'
E.ACT_FLEET_REVOKE_KEY = 'vhub_admin:actFleetRevokeKey'
E.ACT_FLEET_DESPAWN    = 'vhub_admin:actFleetDespawn'
E.ACT_FLEET_PURGE_KEYS = 'vhub_admin:actFleetPurgeKeys'
E.ACT_FLEET_PURGE_LOGS = 'vhub_admin:actFleetPurgeLogs'
E.ACT_FLEET_FINALIZE   = 'vhub_admin:actFleetFinalizeAuctions'

-- Cliente → servidor: mundo, economia e grupos
E.ACT_WEATHER       = 'vhub_admin:actWeather'
E.ACT_TIME          = 'vhub_admin:actTime'
E.ACT_BLACKOUT      = 'vhub_admin:actBlackout'
E.ACT_CLEARZONE     = 'vhub_admin:actClearzone'
E.ACT_WIPE          = 'vhub_admin:actWipe'
E.ACT_ANNOUNCE      = 'vhub_admin:actAnnounce'
E.ACT_STAFFCHAT     = 'vhub_admin:actStaffchat'
E.ACT_GIVEMONEY     = 'vhub_admin:actGivemoney'
E.ACT_SETMONEY      = 'vhub_admin:actSetmoney'
E.ACT_REMOVEMONEY   = 'vhub_admin:actRemovemoney'
E.ACT_GIVEITEM      = 'vhub_admin:actGiveitem'
E.ACT_ADDGROUP      = 'vhub_admin:actAddgroup'
E.ACT_DELGROUP      = 'vhub_admin:actDelgroup'
E.ACT_REPORT_CLAIM  = 'vhub_admin:actReportClaim'
E.ACT_REPORT_CLOSE  = 'vhub_admin:actReportClose'
E.ACT_REPORT        = 'vhub_admin:actReport'

-- Eventos locais do resource
E.CLEANUP_EFFECTS   = 'vhub_admin:cleanupEffects'

-- Mensagens Lua → NUI
VHubAdmin.UI = {
  OPEN         = 'open',
  CLOSE        = 'close',
  DASHBOARD    = 'dashboard',
  PLAYER_LIST  = 'playerList',
  PROFILE      = 'profile',
  OVERLAY_SNAPSHOT = 'overlaySnapshot',
  OVERLAY_UPDATE = 'overlayUpdate',
  OVERLAY_CLEAR  = 'overlayClear',
  REPORT_LIST  = 'reportList',
  LOG_LIST     = 'logList',
  FLEET_LIST   = 'fleetList',
  FLEET_DETAIL = 'fleetDetail',
  TOAST        = 'toast',
  ANNOUNCE     = 'announce',
  STATE_SYNC   = 'stateSync',
  SPEC_HUD     = 'specHud',
}
