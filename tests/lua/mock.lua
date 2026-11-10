-- Minimal WoW 3.3.5a API mock for the Lua behavior tests.
-- Individual tests mutate the `mock` table directly.

mock = {
    class = "Druid",
    classTag = "DRUID",
    level = 80,
    spellbook = {},
    spellNames = {},
    group = false,
    party = {},
    raid = {},
    roles = {},
    health = {},
    healthMax = {},
    power = {},
    enemies = {},
    known = {},
    cooldowns = {},
    auras = {},
    target = false,
    inInstance = false,
    instanceType = "none",
    combat = false,
}

local clock = 100

function GetTime()
    clock = clock + 0.001
    return clock
end

function time()
    return 1700000000 + math.floor(clock)
end

function UnitClass(unit)
    if unit == "player" then
        return mock.class, mock.classTag, 11
    end
    return nil
end

function UnitRace()
    return "Human", "Human", 1
end

function UnitName(unit)
    if unit == "player" then
        return "Tester"
    end
    return unit
end

function GetRealmName()
    return "TestRealm"
end

function GetLocale()
    return "enUS"
end

function UnitExists(unit)
    if unit == "target" then
        return mock.target
    end
    if unit == "player" then
        return true
    end
    return mock.health[unit] ~= nil
end

function UnitIsDeadOrGhost()
    return false
end

function UnitIsConnected()
    return true
end

function UnitCanAssist()
    return true
end

function UnitIsFriend()
    return true
end

function UnitCanAttack(_, unit)
    return mock.enemies[unit] == true
end

function UnitIsUnit(a, b)
    return a == b
end

function UnitLevel(unit)
    if unit == "player" then
        return mock.level or 80
    end
    return 0
end

function UnitHealth(unit)
    return mock.health[unit] or 100
end

function UnitHealthMax(unit)
    return mock.healthMax[unit] or 100
end

function UnitPower(unit)
    return mock.power[unit] or 100
end

function UnitPowerMax()
    return 100
end

function UnitAffectingCombat()
    return mock.combat
end

function UnitGroupRolesAssigned(unit)
    return mock.roles[unit] or "NONE"
end

function UnitAura(unit, index)
    local list = mock.auras[unit]
    local aura = list and list[index]
    if not aura then
        return nil
    end
    return aura.name,
        aura.rank or "",
        aura.icon or 134400,
        aura.count or 0,
        aura.debuffType,
        aura.duration,
        aura.expirationTime,
        aura.source
end

function UnitGUID(unit)
    return "GUID-" .. tostring(unit)
end

function IsInRaid()
    return #mock.raid > 0
end

function IsInGroup()
    return mock.group or #mock.raid > 0 or #mock.party > 0
end

function GetNumPartyMembers()
    return #mock.party
end

function GetNumRaidMembers()
    return #mock.raid
end

function GetRaidRosterInfo(index)
    local unit = mock.raid[index]
    if not unit then
        return nil
    end
    return UnitName(unit), 0, 1, "", "", "", false
end

function IsSpellKnown(id)
    return mock.known[id] ~= false
end

function GetSpellInfo(id)
    return mock.spellNames[id] or ("Spell " .. tostring(id)), nil, 134400
end

function GetSpellCooldown(id)
    local cd = mock.cooldowns[id]
    if not cd then
        return 0, 0
    end
    return cd[1], cd[2]
end

function IsSpellInRange()
    return 1
end

function CheckInteractDistance()
    return true
end

function UnitInRange()
    return true, true
end

function InCombatLockdown()
    return mock.combat
end

function IsInInstance()
    return mock.inInstance, mock.instanceType
end

function GetBattlefieldStatus()
    return "none"
end

function GetShapeshiftForm()
    return 0
end

function GetNumSpellTabs()
    return #mock.spellbook > 0 and 1 or 0
end

function GetSpellTabInfo(tab)
    if tab ~= 1 or #mock.spellbook == 0 then
        return nil
    end
    return "General", "", 0, #mock.spellbook
end

function GetSpellBookItemName(index)
    local entry = mock.spellbook[index]
    return entry and entry.name or nil
end

function GetSpellBookItemInfo(index)
    local entry = mock.spellbook[index]
    if not entry then
        return nil
    end
    return "SPELL", entry.id
end

function IsAddOnLoaded()
    return false
end

function LoadAddOn()
    return false, "DISABLED"
end

-- Widgets are inert. Tests never drive the UI; they call rotations directly.
local function Widget()
    local w = {}
    w.GetFrameLevel = function()
        return 0
    end
    w.GetCenter = function()
        return 0, 0
    end
    w.GetScale = function()
        return 1
    end
    w.GetWidth = function()
        return 100
    end
    w.GetHeight = function()
        return 30
    end
    w.GetAlpha = function()
        return 1
    end
    w.IsShown = function()
        return false
    end
    w.GetVerticalScroll = function()
        return 0
    end
    w.GetVerticalScrollRange = function()
        return 0
    end
    w.GetStringWidth = function()
        return 10
    end
    w.GetFont = function()
        return "Font", 12
    end
    setmetatable(w, {
        __index = function(t, key)
            local fn = function(self)
                return self
            end
            rawset(t, key, fn)
            return fn
        end,
    })
    return w
end

function CreateFrame()
    return Widget()
end

UIParent = Widget()
ChatFontNormal = Widget()
StaticPopupDialogs = {}
UISpecialFrames = {}
BOOKTYPE_SPELL = "spell"
RAID_CLASS_COLORS = {}

-- Unknown globals become harmless functions. This keeps the addon files
-- loadable without maintaining a full WoW API catalogue.
setmetatable(_G, {
    __index = function(t, key)
        local fn = function()
            return nil
        end
        rawset(t, key, fn)
        return fn
    end,
})
