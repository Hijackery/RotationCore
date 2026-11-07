std = "lua51"
max_line_length = false
unused = false
redefined = false

globals = {
    "RotationCore", "DH", "ns", "mock", "TEST_SUMMARY", "UIParent",
    "ChatFontNormal", "StaticPopupDialogs", "BOOKTYPE_SPELL", "RAID_CLASS_COLORS",
    "CreateFrame", "GetTime", "time", "date", "UnitClass", "UnitRace", "UnitName",
    "UnitCastingInfo", "UnitChannelInfo", "UnitLevel", "UnitCreatureType",
    "GetSpellBookItemInfo", "GetSpellBookItemName", "GetSpellLink",
    "GetCursorPosition", "GameTooltip", "UISpecialFrames", "ReloadUI", "PlaySoundFile",
    "GetRealmName", "GetLocale", "UnitExists", "UnitIsDeadOrGhost",
    "UnitIsConnected", "UnitCanAssist", "UnitIsFriend", "UnitCanAttack",
    "UnitIsUnit", "UnitHealth", "UnitHealthMax", "UnitPower", "UnitPowerMax",
    "UnitAffectingCombat", "UnitGroupRolesAssigned", "UnitAura", "UnitGUID",
    "IsInRaid", "IsInGroup", "GetNumPartyMembers", "GetNumRaidMembers",
    "GetRaidRosterInfo", "IsSpellKnown", "GetSpellInfo", "GetSpellCooldown",
    "IsSpellInRange", "UnitInRange", "InCombatLockdown", "IsInInstance",
    "GetBattlefieldStatus", "GetShapeshiftForm", "GetNumSpellTabs",
    "GetSpellTabInfo", "IsAddOnLoaded", "LoadAddOn", "StaticPopup_Show",
    "SetText", "Show", "Hide", "Print",
}

ignore = {
    "611", -- whitespace-only line
    "612", -- trailing whitespace
    "613", -- trailing whitespace in string
    "614", -- trailing whitespace in comment
    "621", -- inconsistent indentation
    "622", -- inconsistent indentation in string
    "631", -- line too long
    "632", -- mixed tabs and spaces
}
