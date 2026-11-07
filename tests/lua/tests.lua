-- Behavior tests. Loaded after mock.lua, RotationCore.lua, Heal.lua and the
-- selected class files. Results are exposed as TEST_SUMMARY.

local DH = RotationCore
local ns = DH.ns

TEST_SUMMARY = { passed = 0, failed = 0, results = {} }

local function check(name, condition, detail)
    if condition then
        TEST_SUMMARY.passed = TEST_SUMMARY.passed + 1
        TEST_SUMMARY.results[#TEST_SUMMARY.results + 1] = "PASS " .. name
        return
    end
    TEST_SUMMARY.failed = TEST_SUMMARY.failed + 1
    TEST_SUMMARY.results[#TEST_SUMMARY.results + 1] = "FAIL " .. name .. (detail and (" - " .. tostring(detail)) or "")
end

local function reset()
    mock.group = false
    mock.party = {}
    mock.raid = {}
    mock.roles = {}
    mock.health = { player = 100 }
    mock.healthMax = { player = 100 }
    mock.power = { player = 100 }
    mock.enemies = {}
    mock.known = {}
    mock.cooldowns = {}
    mock.auras = {}
    mock.target = false
    mock.inInstance = false
    mock.instanceType = "none"
    mock.combat = false
    DH.db = {
        mode = "feral_cat",
        common = {
            target_mode = "single",
            aoe_threshold = 4,
            cleave_threshold = 2,
            heal_dps_mode = "auto",
            activity_profile = "raid",
            timeline_auto_phase = false,
        },
    }
end

local function injuredParty(count, hp)
    mock.group = true
    mock.party = {}
    for i = 1, count do
        local unit = "party" .. i
        mock.party[i] = unit
        mock.health[unit] = hp or 40
        mock.healthMax[unit] = 100
        mock.roles[unit] = (i == 1) and "TANK" or "NONE"
    end
end

local function findMode(key)
    for _, mode in ipairs(ns.registered.modes or {}) do
        if mode.key == key then
            return mode
        end
    end
    return nil
end

local function recsFor(key)
    local mode = findMode(key)
    if not mode or not mode.rotation then
        return {}
    end
    return mode.rotation(DH) or {}
end

local function hasAbility(recs, key)
    for _, rec in ipairs(recs) do
        if rec.ability == key then
            return true
        end
    end
    return false
end

local function anyAbility(recs, keys)
    for _, key in ipairs(keys) do
        if hasAbility(recs, key) then
            return true
        end
    end
    return false
end

local function noDps(recs, keys)
    return not anyAbility(recs, keys)
end

local function healSpecTests(spec)
    if not findMode(spec.mode) then
        return
    end
    reset()
    injuredParty(1, 40)
    local recs = recsFor(spec.mode)
    check(spec.name .. ": emits a heal", anyAbility(recs, spec.heals), "no expected heal in recommendations")
    check(spec.name .. ": does not emit DPS", noDps(recs, spec.dps), "DPS ability leaked into a heal rotation")

    reset()
    injuredParty(1, 40)
    local noTargetRecs = recsFor(spec.mode)
    check(spec.name .. ": works without an enemy target", #noTargetRecs > 0, "heal rotation returned nothing")

    if spec.aoe then
        reset()
        injuredParty(3, 50)
        local aoeRecs = recsFor(spec.mode)
        check(
            spec.name .. ": uses AoE heal on stacked damage",
            anyAbility(aoeRecs, spec.aoe),
            "no AoE heal recommended"
        )
    end

    if spec.mana then
        reset()
        injuredParty(1, 40)
        mock.power.player = 10
        local lowManaRecs = recsFor(spec.mode)
        check(
            spec.name .. ": uses a mana tool at low mana",
            anyAbility(lowManaRecs, spec.mana),
            "no mana recovery ability recommended"
        )
    end

    if spec.dispel and spec.dispelAura then
        reset()
        injuredParty(1, 40)
        mock.auras.party1 = { { name = "Test " .. spec.dispelAura, debuffType = spec.dispelAura } }
        local dispelRecs = recsFor(spec.mode)
        check(
            spec.name .. ": dispels " .. spec.dispelAura,
            anyAbility(dispelRecs, spec.dispel),
            "no dispel recommended"
        )
    end
end

local SPECS = {
    {
        mode = "resto_druid",
        name = "Resto Druid",
        heals = { "lifebloom", "rejuvenation", "regrowth", "healing_touch", "nourish" },
        dps = { "wrath", "starfire", "mangle_cat" },
        aoe = { "wild_growth" },
        mana = { "innervate" },
        dispel = { "remove_curse" },
        dispelAura = "Curse",
    },
    {
        mode = "holy_paladin",
        name = "Holy Paladin",
        heals = { "holy_light", "flash_of_light", "holy_shock", "beacon_of_light" },
        dps = { "crusader_strike", "judgement_of_wisdom" },
        mana = { "divine_illumination" },
        dispel = { "cleanse" },
        dispelAura = "Magic",
    },
    {
        mode = "resto_shaman",
        name = "Resto Shaman",
        heals = { "earth_shield", "riptide", "healing_wave", "lesser_healing_wave" },
        dps = { "lightning_bolt", "lava_burst", "stormstrike" },
        aoe = { "chain_heal" },
        mana = { "mana_tide_totem" },
        dispel = { "cleanse_spirit" },
        dispelAura = "Curse",
    },
    {
        mode = "discipline",
        name = "Discipline Priest",
        heals = { "power_word_shield", "prayer_of_mending", "penance", "renew", "greater_heal" },
        dps = { "smite", "mind_blast", "holy_fire" },
        mana = { "hymn_of_hope" },
        dispel = { "dispel_magic" },
        dispelAura = "Magic",
    },
    {
        mode = "holy_priest",
        name = "Holy Priest",
        heals = { "power_word_shield", "renew", "prayer_of_mending", "flash_heal", "greater_heal" },
        dps = { "smite", "mind_blast", "holy_fire" },
        aoe = { "circle_of_healing" },
        mana = { "hymn_of_hope" },
        dispel = { "dispel_magic" },
        dispelAura = "Magic",
    },
}

for _, spec in ipairs(SPECS) do
    healSpecTests(spec)
end

-- Unknown spell: a critical tank must not get an unlearned Lay on Hands.
if findMode("holy_paladin") then
    reset()
    injuredParty(1, 10)
    mock.known[ns.SPELLS.LAY_ON_HANDS] = false
    local recs = recsFor("holy_paladin")
    check(
        "Unknown spell: unlearned Lay on Hands is filtered",
        not hasAbility(recs, "lay_on_hands"),
        "unlearned ability was recommended"
    )
end

-- Target mode resolution: single / cleave / AoE / explicit AoE.
reset()
DH.db.common.target_mode = "auto"
check("Target mode auto: 1 enemy is single", DH:ResolveTargetMode({ active_enemies = 1 }) == "single")
check("Target mode auto: 2 enemies is cleave", DH:ResolveTargetMode({ active_enemies = 2 }) == "cleave")
check("Target mode auto: 4 enemies is AoE", DH:ResolveTargetMode({ active_enemies = 4 }) == "aoe")
DH.db.common.target_mode = "aoe"
check("Target mode explicit AoE stays AoE", DH:ResolveTargetMode({ active_enemies = 1 }) == "aoe")

-- Heal mode resolution must prefer the heal mode over the DPS borrow.
if findMode("resto_druid") then
    check("MatchModeKey: resto resolves to the heal mode", DH:MatchModeKey("resto") == "resto_druid")
end
if findMode("holy_paladin") then
    check("MatchModeKey: holy resolves to the heal mode", DH:MatchModeKey("holy") == "holy_paladin")
end
if findMode("discipline") then
    check("MatchModeKey: discipline resolves to the heal mode", DH:MatchModeKey("discipline") == "discipline")
    check("MatchModeKey: holy resolves to the priest heal mode", DH:MatchModeKey("holy") == "holy_priest")
end

-- Heal-DPS borrow: grouped healers never borrow, solo they do.
if findMode("resto_druid") then
    reset()
    injuredParty(1, 40)
    check("Heal-DPS borrow: disabled in a group", DH:GetHealDpsMode(findMode("resto_druid")) == nil)
    reset()
    mock.group = false
    mock.party = {}
    local dps = DH:GetHealDpsMode(findMode("resto_druid"))
    check("Heal-DPS borrow: enabled solo", dps and dps.key == "resto_druid_dps")
end

-- Talent/spell cache invalidation.
do
    reset()
    local id = 12345
    mock.known[id] = false
    DH:InvalidateKnownSpells()
    check("Known-spell cache: unknown spell is filtered", DH:IsSpellKnownId(id) == false)
    mock.known[id] = true
    check("Known-spell cache: stays cached until invalidated", DH:IsSpellKnownId(id) == false)
    DH:InvalidateKnownSpells()
    check("Known-spell cache: rebuild after talent change", DH:IsSpellKnownId(id) == true)
end
