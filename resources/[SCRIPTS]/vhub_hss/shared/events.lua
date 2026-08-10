-- shared/events.lua — contratos de evento do vHub HSS (R9)

VHubHSS = VHubHSS or {}

VHubHSS.E = {
    STATE_INIT = 'vhub_hss:stateInit',
    STATE_HIDE = 'vhub_hss:stateHide',
    REQUEST_INIT = 'vhub_hss:requestInit',
    ITEM_EFFECT = 'vhub_hss:itemEffect',

    CRITICAL = 'vhub_hss:critical',
    STATE_CHANGED = 'vhub_hss:stateChanged',

    CHARACTER_LOAD = 'vHub:characterLoad',
    PLAYER_SPAWN = 'vHub:playerSpawn',
    PLAYER_DEATH = 'vHub:playerDeath',
    NOTIFY = 'vHub:notify',
    ENTITY_DAMAGED = 'entityDamaged',
    HANDCUFF_SET = 'vhub_hss:handcuffSet',

    PED_APPLY = 'vhub_hss:pedApply',
    PED_RELEASE = 'vhub_hss:pedRelease',
    PED_GIVE_WEAPONS = 'vhub_hss:pedGiveWeapons',
    PED_SET_ARMOUR = 'vhub_hss:pedSetArmour',
    PED_SET_HEALTH = 'vhub_hss:pedSetHealth',
    PED_SET_MODEL = 'vhub_hss:pedSetModel',
    PED_REVIVE = 'vhub_hss:pedRevive',
    PED_KILL = 'vhub_hss:pedKill',
    PED_SET_CUSTOMIZATION = 'vhub_hss:pedSetCustomization',
    PED_TELEPORT = 'vhub_hss:pedTeleport',
    CUSTOMIZATION_STAGE_BEGIN = 'vhub_hss:customizationStageBegin',
    CUSTOMIZATION_STAGE_END = 'vhub_hss:customizationStageEnd',
    SPAWN_CHOOSE = 'vhub_hss:chooseSpawn',
    SPAWNED      = 'vhub_hss:spawned',

    REQUEST_CROUCH = 'vhub_hss:requestCrouch',
    SET_CROUCH     = 'vhub_hss:setCrouch',

    AFK_HEARTBEAT  = 'vhub_hss:afkHeartbeat',
}
