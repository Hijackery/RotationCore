-- RotationCore_Shaman/Shaman.lua
-- Shaman class module: ability definitions + registration of all Shaman-specific data

local DH = RotationCore
if not DH then return end

-- Only load for Shamans
if select(2, UnitClass("player")) ~= "SHAMAN" then
    return
end

local ns = DH.ns
local L = function(s) local t = DH.L; return (t and t[s]) or s end
local class = DH.Class

-- ============================================================================
-- SPELL IDS (max rank for 3.3.5a)
-- ============================================================================

local SPELLS = {
    -- Enhancement
    STORMSTRIKE = 17364,
    LAVA_LASH = 60103,
    FERAL_SPIRIT = 51533,
    SHAMANISTIC_RAGE = 30823,

    -- Elemental
    LIGHTNING_BOLT = 49238,
    CHAIN_LIGHTNING = 49271,
    LAVA_BURST = 60043,
    THUNDERSTORM = 51490,
    ELEMENTAL_MASTERY = 16166,

    -- Shared
    FLAME_SHOCK = 49233,
    EARTH_SHOCK = 49231,
    FROST_SHOCK = 49236,
    FIRE_NOVA = 61657,
    WIND_SHEAR = 57994,

    -- Shields
    LIGHTNING_SHIELD = 49281,
    WATER_SHIELD = 57960,

    -- Totems
    MAGMA_TOTEM = 58734,
    SEARING_TOTEM = 3599,
    TOTEM_OF_WRATH = 57722,
    STRENGTH_OF_EARTH = 58643,
    WRATH_OF_AIR = 3738,
    MANA_SPRING = 58774,
    WINDFURY_TOTEM = 8512,

    -- Buffs
    BLOODLUST = 2825,
    HEROISM = 32182,
    NATURES_SWIFTNESS = 16188,
}

ns.SPELLS = SPELLS

-- ============================================================================
-- ABILITY DEFINITIONS
-- ============================================================================

class.abilities = {
    -- Enhancement
    stormstrike = {
        id = SPELLS.STORMSTRIKE,
        name = "Stormstrike",
        texture = 132314,
    },
    lava_lash = {
        id = SPELLS.LAVA_LASH,
        name = "Lava Lash",
        texture = 236289,
    },
    feral_spirit = {
        id = SPELLS.FERAL_SPIRIT,
        name = "Feral Spirit",
        texture = 236868,
    },
    shamanistic_rage = {
        id = SPELLS.SHAMANISTIC_RAGE,
        name = "Shamanistic Rage",
        texture = 136088,
    },

    -- Elemental
    lightning_bolt = {
        id = SPELLS.LIGHTNING_BOLT,
        name = "Lightning Bolt",
        texture = 136048,
    },
    chain_lightning = {
        id = SPELLS.CHAIN_LIGHTNING,
        name = "Chain Lightning",
        texture = 136015,
    },
    lava_burst = {
        id = SPELLS.LAVA_BURST,
        name = "Lava Burst",
        texture = 237582,
    },
    thunderstorm = {
        id = SPELLS.THUNDERSTORM,
        name = "Thunderstorm",
        texture = 237589,
    },
    elemental_mastery = {
        id = SPELLS.ELEMENTAL_MASTERY,
        name = "Elemental Mastery",
        texture = 136115,
    },

    -- Shared
    flame_shock = {
        id = SPELLS.FLAME_SHOCK,
        name = "Flame Shock",
        texture = 135813,
    },
    earth_shock = {
        id = SPELLS.EARTH_SHOCK,
        name = "Earth Shock",
        texture = 136026,
    },
    frost_shock = {
        id = SPELLS.FROST_SHOCK,
        name = "Frost Shock",
        texture = 135849,
    },
    fire_nova = {
        id = SPELLS.FIRE_NOVA,
        name = "Fire Nova",
        texture = 135824,
    },
    wind_shear = {
        id = SPELLS.WIND_SHEAR,
        name = "Wind Shear",
        texture = 136018,
    },

    -- Shields
    lightning_shield = {
        id = SPELLS.LIGHTNING_SHIELD,
        name = "Lightning Shield",
        texture = 136051,
    },
    water_shield = {
        id = SPELLS.WATER_SHIELD,
        name = "Water Shield",
        texture = 132315,
    },

    -- Totems
    magma_totem = {
        id = SPELLS.MAGMA_TOTEM,
        name = "Magma Totem",
        texture = 135826,
    },
    searing_totem = {
        id = SPELLS.SEARING_TOTEM,
        name = "Searing Totem",
        texture = 135825,
    },

    -- Cooldowns
    natures_swiftness = {
        id = SPELLS.NATURES_SWIFTNESS,
        name = "Nature's Swiftness",
        texture = 136076,
    },
}

-- Create name mapping and get textures from GetSpellInfo (3.3.5a compatible)
DH:RegisterAbilityTable()

-- ============================================================================
-- REGISTER SHAMAN DATA INTO FRAMEWORK
-- ============================================================================

-- GCD reference spell (Flame Shock)
DH:RegisterGCDSpell(SPELLS.FLAME_SHOCK)

-- Melee abilities (for UI range overlay)
DH:RegisterMeleeAbilities({
    "stormstrike", "lava_lash", "earth_shock", "frost_shock",
})

-- Buffs to track
DH:RegisterBuffs({
    "lightning_shield", "water_shield",
    "maelstrom_weapon",
    "shamanistic_rage",
    "elemental_mastery",
    "natures_swiftness",
    "clearcasting",  -- Elemental Focus
    "flurry",
    "elemental_devastation",
    "bloodlust", "heroism",
})

-- Debuffs to track
DH:RegisterDebuffs({
    "flame_shock",
    "earth_shock",
    "frost_shock",
    "stormstrike",
})

-- Cooldowns
DH:RegisterCooldowns({
    stormstrike = 17364,
    lava_lash = 60103,
    feral_spirit = 51533,
    shamanistic_rage = 30823,
    flame_shock = 49233,
    earth_shock = 49231,
    frost_shock = 49236,
    fire_nova = 61657,
    lightning_bolt = 49238,
    chain_lightning = 49271,
    lava_burst = 60043,
    thunderstorm = 51490,
    elemental_mastery = 16166,
    natures_swiftness = 16188,
    wind_shear = 57994,
})

-- Mana costs as a fraction of base mana (approximate WotLK 3.3.5a values).
-- Without these the sim never drains mana, so Shamanistic Rage /
-- Thunderstorm never trigger and Elemental mana management is unmodelled.
DH:RegisterManaCosts({
    lightning_bolt = 0.10,
    chain_lightning = 0.19,
    lava_burst = 0.10,
    flame_shock = 0.17,
    earth_shock = 0.18,
    frost_shock = 0.16,
    lightning_shield = 0.10,
    fire_nova = 0.22,
    thunderstorm = 0.0,
    stormstrike = 0.02,
    lava_lash = 0.01,
    healing_wave = 0.12,
    lesser_healing_wave = 0.10,
})

-- Talents
DH:RegisterTalents({
    -- Elemental
    { 1, 1, "convection" },
    { 1, 2, "concussion" },
    { 1, 3, "call_of_flame" },
    { 1, 5, "elemental_warding" },
    { 1, 6, "elemental_devastation" },
    { 1, 7, "reverberation" },
    { 1, 8, "elemental_focus" },
    { 1, 9, "elemental_fury" },
    { 1, 10, "improved_fire_nova" },
    { 1, 11, "eye_of_the_storm" },
    { 1, 13, "elemental_reach" },
    { 1, 14, "call_of_thunder" },
    { 1, 15, "unrelenting_storm" },
    { 1, 16, "elemental_precision" },
    { 1, 17, "lightning_mastery" },
    { 1, 18, "elemental_mastery" },
    { 1, 19, "storm_earth_and_fire" },
    { 1, 20, "booming_echoes" },
    { 1, 21, "elemental_oath" },
    { 1, 22, "lightning_overload" },
    { 1, 23, "totem_of_wrath" },
    { 1, 24, "lava_flows" },
    { 1, 25, "shamanism" },
    { 1, 26, "thunderstorm" },

    -- Enhancement
    { 2, 1, "enhancing_totems" },
    { 2, 2, "earths_grasp" },
    { 2, 3, "ancestral_knowledge" },
    { 2, 4, "guardian_totems" },
    { 2, 5, "thundering_strikes" },
    { 2, 6, "improved_ghost_wolf" },
    { 2, 7, "improved_shields" },
    { 2, 8, "elemental_weapons" },
    { 2, 9, "shamanistic_focus" },
    { 2, 10, "flurry" },
    { 2, 11, "improved_windfury_totem" },
    { 2, 12, "spirit_weapons" },
    { 2, 13, "lava_lash" },
    { 2, 14, "improved_stormstrike" },
    { 2, 15, "mental_dexterity" },
    { 2, 16, "unleashed_rage" },
    { 2, 17, "weapon_mastery" },
    { 2, 18, "dual_wield_specialization" },
    { 2, 19, "dual_wield" },
    { 2, 20, "stormstrike" },
    { 2, 21, "static_shock" },
    { 2, 22, "shamanistic_rage" },
    { 2, 23, "mental_quickness" },
    { 2, 24, "maelstrom_weapon" },
    { 2, 25, "feral_spirit" },

    -- Restoration
    { 3, 3, "improved_healing_wave" },
    { 3, 4, "totemic_focus" },
    { 3, 6, "healing_grace" },
    { 3, 7, "restorative_totems" },
    { 3, 8, "tidal_focus" },
    { 3, 10, "natures_swiftness" },
})

-- Glyphs
DH:RegisterGlyphs({
    [57248] = "stormstrike",  -- Glyph of Stormstrike
    [57249] = "lava_lash",  -- Glyph of Lava Lash
    [64288] = "feral_spirit",  -- Glyph of Feral Spirit
    [57245] = "lightning_bolt",  -- Glyph of Lightning Bolt
    [57239] = "flame_shock",  -- Glyph of Flame Shock
    [57234] = "lava_burst",  -- Glyph of Lava
    [57233] = "chain_lightning",  -- Glyph of Chain Lightning
    [57238] = "fire_nova",  -- Glyph of Fire Nova
    [57237] = "fire_elemental",  -- Glyph of Fire Elemental Totem
    [64262] = "totem_of_wrath",  -- Glyph of Totem of Wrath
})

-- Buff spell ID -> key mapping
DH:RegisterBuffMap({
    [49281] = "lightning_shield",
    [57960] = "water_shield",
    [53817] = "maelstrom_weapon",
    [30823] = "shamanistic_rage",
    [64701] = "elemental_mastery",  -- haste buff from EM
    [16188] = "natures_swiftness",
    [16246] = "clearcasting",       -- Elemental Focus proc
    [16280] = "flurry",
    [30160] = "elemental_devastation",
    [2825] = "bloodlust",
    [32182] = "heroism",
})

-- Debuff spell ID -> key mapping (player-applied)
DH:RegisterDebuffMap({
    -- Flame Shock (all ranks)
    [49233] = "flame_shock", [49232] = "flame_shock", [25457] = "flame_shock",
    [29228] = "flame_shock", [10447] = "flame_shock", [10448] = "flame_shock",
    [8052] = "flame_shock",
    [8053] = "flame_shock", [8050] = "flame_shock",
    -- Earth Shock
    [49231] = "earth_shock", [49230] = "earth_shock", [25454] = "earth_shock",
    -- Frost Shock
    [49236] = "frost_shock", [49235] = "frost_shock", [25464] = "frost_shock",
    -- Stormstrike
    [17364] = "stormstrike",
})

-- Debuff name patterns (fallback matching)
DH:RegisterDebuffNamePatterns({
    { "flame shock", "flame_shock" },
    { "earth shock", "earth_shock" },
    { "frost shock", "frost_shock" },
    { "stormstrike", "stormstrike" },
})

-- External debuff mapping (from other players)
DH:RegisterExternalDebuffMap({})
DH:RegisterExternalDebuffNamePatterns({})

-- ============================================================================
-- SPEC DETECTION
-- ============================================================================

DH:RegisterSpecDetector(function()
    local elemental, enhancement, resto = 0, 0, 0

    for i = 1, GetNumTalentTabs() do
        local _, _, points = GetTalentTabInfo(i)
        if i == 1 then elemental = points
        elseif i == 2 then enhancement = points
        else resto = points
        end
    end

    if enhancement > elemental and enhancement > resto then
        return "enhancement"
    elseif elemental > resto then
        return "elemental"
    else
        return "resto"
    end
end)

-- ============================================================================
-- DEFAULT SETTINGS (class-specific)
-- ============================================================================

-- Last-resort basic abilities shown when every recommendation was
-- filtered out as unknown (see DH:FirstKnownFallback).
DH:RegisterFallbackAbilities({
    "lightning_bolt", "earth_shock", "chain_lightning",
})

-- Buffs whose rising edge plays the proc sound (see DH:RegisterProcBuff).
DH:RegisterProcBuff("clearcasting")
DH:RegisterProcBuff("maelstrom_weapon", { minStacks = 5 })

DH:RegisterDefaults({
    enhancement = {
        enabled = true,
        role = "dps",
        use_feral_spirit = true,
        use_shamanistic_rage = true,
        use_fire_nova = true,
        aoe_threshold = 3,
        dot_refresh_buffer = 2.0,
    },
    elemental = {
        enabled = true,
        role = "dps",
        use_elemental_mastery = true,
        use_thunderstorm = true,
        use_natures_swiftness = true,
        aoe_threshold = 3,
        dot_refresh_buffer = 2.0,
    },
})

DH:RegisterCommonDefaults()

-- Major cooldowns: snoozeable if player skips them
DH:RegisterSnoozeable("feral_spirit", 60)
DH:RegisterSnoozeable("elemental_mastery", 60)

-- ============================================================================
-- SLASH COMMANDS (Shaman-specific)
-- ============================================================================

DH:RegisterSlashCommand("enh", function(cmd)
    local s = DH.State
    DH:UpdateState()
    DH:Print(L("--- Enhancement Status ---"))
    DH:Print(L("Mana: ") .. tostring(math.floor(s.mana.pct)) .. "%")
    DH:Print(L("MW Stacks: ") .. tostring(s.buff.maelstrom_weapon.stacks or 0))
    DH:Print(L("Flame Shock: ") .. (s.debuff.flame_shock.up and string.format("%.1fs", s.debuff.flame_shock.remains) or L("DOWN")))
    DH:Print(L("SS CD: ") .. (s.cooldown.stormstrike.ready and L("READY") or string.format("%.1fs", s.cooldown.stormstrike.remains)))
    DH:Print(L("LL CD: ") .. (s.cooldown.lava_lash.ready and L("READY") or string.format("%.1fs", s.cooldown.lava_lash.remains)))
    if DH.db and DH.db.debug then DH:Print(L("TTD: ") .. tostring(s.target.time_to_die) .. "s") end
end, "enh - Show enhancement status")

DH:RegisterSlashCommand("ele", function(cmd)
    local s = DH.State
    DH:UpdateState()
    DH:Print(L("--- Elemental Status ---"))
    DH:Print(L("Mana: ") .. tostring(math.floor(s.mana.pct)) .. "%")
    DH:Print(L("Flame Shock: ") .. (s.debuff.flame_shock.up and string.format("%.1fs", s.debuff.flame_shock.remains) or L("DOWN")))
    DH:Print(L("LvB CD: ") .. (s.cooldown.lava_burst.ready and L("READY") or string.format("%.1fs", s.cooldown.lava_burst.remains)))
    DH:Print(L("CL CD: ") .. (s.cooldown.chain_lightning.ready and L("READY") or string.format("%.1fs", s.cooldown.chain_lightning.remains)))
    DH:Print(L("EM CD: ") .. (s.cooldown.elemental_mastery.ready and L("READY") or string.format("%.1fs", s.cooldown.elemental_mastery.remains)))
    if DH.db and DH.db.debug then DH:Print(L("TTD: ") .. tostring(s.target.time_to_die) .. "s") end
end, "ele - Show elemental status")

-- ============================================================================
-- DEBUG FRAME (Shaman-specific)
-- ============================================================================
ns.registered.debugFrameUpdater = DH:MakeDebugFrameUpdater(function(s, rec1, rec2, rec3)
    return {
            string.format(L("Mana: %d%% | GCD: %.2f"), math.floor(s.mana.pct), s.gcd_remains),
            string.format(L("MW: %d | FS: %.1f"), s.buff.maelstrom_weapon.stacks or 0, s.debuff.flame_shock.remains),
    }
end)

-- v3.3.0: approximate direct-damage coefficients for the DPS forecast.
-- Observed combat-log averages override these once the spells land.

DH:RegisterSpellDamage({
  lightning_bolt = { min=600, max=740, coeff=0.86, cast=2.5 },
  chain_lightning = { min=750, max=880, coeff=0.81, cast=2.5 },
  lava_burst = { min=950, max=1100, coeff=0.86 },
  stormstrike = { min=500, max=600, coeff=0.65, ap=true },
  lava_lash = { min=400, max=500, coeff=0.50, ap=true },
  flame_shock = { min=380, max=470, coeff=0.55 },
  earth_shock = { min=500, max=600, coeff=0.43 },
  frost_shock = { min=420, max=480, coeff=0.43 },
})
