-- RotationCore_Rogue/Rogue.lua
-- Rogue class module: ability definitions + registration

local DH = RotationCore
if not DH then return end

if select(2, UnitClass("player")) ~= "ROGUE" then
    return
end

local ns = DH.ns
local L = function(s) local t = DH.L; return (t and t[s]) or s end
local class = DH.Class

-- ============================================================================
-- SPELL IDS (max rank for 3.3.5a)
-- ============================================================================

local SPELLS = {
    -- Builders
    MUTILATE = 48666,
    SINISTER_STRIKE = 48638,
    BACKSTAB = 48657,
    HEMORRHAGE = 48660,
    AMBUSH = 48691,
    GARROTE = 48676,
    FAN_OF_KNIVES = 51723,

    -- Finishers
    EVISCERATE = 48668,
    ENVENOM = 57993,
    SLICE_AND_DICE = 6774,
    RUPTURE = 48672,
    EXPOSE_ARMOR = 8647,
    KIDNEY_SHOT = 8643,

    -- Cooldowns
    COLD_BLOOD = 14177,
    ADRENALINE_RUSH = 13750,
    BLADE_FLURRY = 13877,
    KILLING_SPREE = 51690,
    SHADOW_DANCE = 51713,
    SHADOWSTEP = 36554,
    VANISH = 26889,
    PREMEDITATION = 14183,
    PREPARATION = 14185,
    HUNGER_FOR_BLOOD = 51662,

    -- Utility
    TRICKS_OF_THE_TRADE = 57934,
    FEINT = 48659,
    CLOAK_OF_SHADOWS = 31224,
    EVASION = 26669,
    SPRINT = 11305,

    -- PvP
    KICK = 1766,
    KIDNEY_SHOT = 8643,
    BLIND = 2094,
    SAP = 51724,
}

ns.SPELLS = SPELLS

-- ============================================================================
-- ABILITY DEFINITIONS
-- ============================================================================

class.abilities = {
    -- Builders
    mutilate = {
        id = SPELLS.MUTILATE,
        name = "Mutilate",
        texture = 236270,
    },
    sinister_strike = {
        id = SPELLS.SINISTER_STRIKE,
        name = "Sinister Strike",
        texture = 136189,
    },
    backstab = {
        id = SPELLS.BACKSTAB,
        name = "Backstab",
        texture = 132090,
    },
    hemorrhage = {
        id = SPELLS.HEMORRHAGE,
        name = "Hemorrhage",
        texture = 136168,
    },
    ambush = {
        id = SPELLS.AMBUSH,
        name = "Ambush",
        texture = 132282,
    },
    garrote = {
        id = SPELLS.GARROTE,
        name = "Garrote",
        texture = 132297,
    },
    fan_of_knives = {
        id = SPELLS.FAN_OF_KNIVES,
        name = "Fan of Knives",
        texture = 236273,
    },

    -- Finishers
    eviscerate = {
        id = SPELLS.EVISCERATE,
        name = "Eviscerate",
        texture = 132292,
    },
    envenom = {
        id = SPELLS.ENVENOM,
        name = "Envenom",
        texture = 132287,
    },
    slice_and_dice = {
        id = SPELLS.SLICE_AND_DICE,
        name = "Slice and Dice",
        texture = 132306,
    },
    rupture = {
        id = SPELLS.RUPTURE,
        name = "Rupture",
        texture = 132302,
    },
    expose_armor = {
        id = SPELLS.EXPOSE_ARMOR,
        name = "Expose Armor",
        texture = 132354,
    },

    -- Cooldowns
    cold_blood = {
        id = SPELLS.COLD_BLOOD,
        name = "Cold Blood",
        texture = 135988,
    },
    adrenaline_rush = {
        id = SPELLS.ADRENALINE_RUSH,
        name = "Adrenaline Rush",
        texture = 136206,
    },
    blade_flurry = {
        id = SPELLS.BLADE_FLURRY,
        name = "Blade Flurry",
        texture = 132350,
    },
    killing_spree = {
        id = SPELLS.KILLING_SPREE,
        name = "Killing Spree",
        texture = 236277,
    },
    shadow_dance = {
        id = SPELLS.SHADOW_DANCE,
        name = "Shadow Dance",
        texture = 236279,
    },
    shadowstep = {
        id = SPELLS.SHADOWSTEP,
        name = "Shadowstep",
        texture = 132303,
    },
    preparation = {
        id = SPELLS.PREPARATION,
        name = "Preparation",
        texture = 136151,
    },
    hunger_for_blood = {
        id = SPELLS.HUNGER_FOR_BLOOD,
        name = "Hunger for Blood",
        texture = 236276,
    },
    vanish = {
        id = SPELLS.VANISH,
        name = "Vanish",
        texture = 132331,
    },
    tricks_of_the_trade = {
        id = SPELLS.TRICKS_OF_THE_TRADE,
        name = "Tricks of the Trade",
        texture = 236283,
    },

    -- PvP
    kick = {
        id = SPELLS.KICK,
        name = "Kick",
        texture = 132219,
    },
    kidney_shot = {
        id = SPELLS.KIDNEY_SHOT,
        name = "Kidney Shot",
        texture = 132298,
    },
    blind = {
        id = SPELLS.BLIND,
        name = "Blind",
        texture = 136175,
    },
    sap = {
        id = SPELLS.SAP,
        name = "Sap",
        texture = 132310,
    },
}

-- Create name mapping and get textures
DH:RegisterAbilityTable()

-- ============================================================================
-- REGISTER ROGUE DATA INTO FRAMEWORK
-- ============================================================================

DH:RegisterGCDSpell(SPELLS.SINISTER_STRIKE)

DH:RegisterMeleeAbilities({
    "mutilate", "sinister_strike", "backstab", "hemorrhage",
    "eviscerate", "envenom", "slice_and_dice", "rupture",
    "expose_armor", "fan_of_knives", "garrote", "ambush",
})

-- Buffs to track
DH:RegisterBuffs({
    "slice_and_dice",
    "hunger_for_blood",
    "envenom",
    "blade_flurry",
    "adrenaline_rush",
    "killing_spree",
    "shadow_dance",
    "shadowstep",
    "cold_blood",
    "master_of_subtlety",
    "overkill",
})

-- Debuffs to track
DH:RegisterDebuffs({
    "rupture",
    "garrote",
    "deadly_poison",
    "wound_poison",
    "expose_armor",
    "hemorrhage",
})

-- Cooldowns
DH:RegisterCooldowns({
    mutilate = 48666,
    sinister_strike = 48638,
    backstab = 48657,
    hemorrhage = 48660,
    eviscerate = 48668,
    envenom = 57993,
    slice_and_dice = 6774,
    rupture = 48672,
    cold_blood = 14177,
    adrenaline_rush = 13750,
    blade_flurry = 13877,
    killing_spree = 51690,
    shadow_dance = 51713,
    shadowstep = 36554,
    vanish = 26889,
    hunger_for_blood = 51662,
    preparation = 14185,
    tricks_of_the_trade = 57934,
    fan_of_knives = 51723,
})

-- Talents
DH:RegisterTalents({
    -- Assassination
    { 1, 1, "improved_eviscerate" },
    { 1, 2, "remorseless_attacks" },
    { 1, 3, "malice" },
    { 1, 4, "ruthlessness" },
    { 1, 5, "blood_spatter" },
    { 1, 6, "puncturing_wounds" },
    { 1, 7, "vigor" },
    { 1, 8, "improved_expose_armor" },
    { 1, 9, "lethality" },
    { 1, 10, "vile_poisons" },
    { 1, 11, "improved_poisons" },
    { 1, 12, "fleet_footed" },
    { 1, 13, "cold_blood" },
    { 1, 14, "improved_kidney_shot" },
    { 1, 15, "quick_recovery" },
    { 1, 16, "seal_fate" },
    { 1, 17, "murder" },
    { 1, 18, "deadly_brew" },
    { 1, 19, "overkill" },
    { 1, 20, "deadened_nerves" },
    { 1, 21, "focused_attacks" },
    { 1, 22, "find_weakness" },
    { 1, 23, "master_poisoner" },
    { 1, 24, "mutilate" },
    { 1, 25, "turn_the_tables" },
    { 1, 26, "cut_to_the_chase" },
    { 1, 27, "hunger_for_blood" },

    -- Combat
    { 2, 1, "improved_sinister_strike" },
    { 2, 2, "dual_wield_specialization" },
    { 2, 3, "improved_slice_and_dice" },
    { 2, 4, "deflection" },
    { 2, 5, "precision" },
    { 2, 6, "endurance" },
    { 2, 7, "riposte" },
    { 2, 8, "close_quarters_combat" },
    { 2, 9, "improved_kick" },
    { 2, 10, "improved_sprint" },
    { 2, 11, "lightning_reflexes" },
    { 2, 12, "aggression" },
    { 2, 13, "mace_specialization" },
    { 2, 14, "blade_flurry" },
    { 2, 15, "hack_and_slash" },
    { 2, 16, "weapon_expertise" },
    { 2, 17, "blade_twisting" },
    { 2, 18, "vitality" },
    { 2, 19, "adrenaline_rush" },
    { 2, 20, "nerves_of_steel" },
    { 2, 21, "throwing_specialization" },
    { 2, 22, "combat_potency" },
    { 2, 23, "unfair_advantage" },
    { 2, 24, "surprise_attacks" },
    { 2, 25, "savage_combat" },
    { 2, 26, "prey_on_the_weak" },
    { 2, 27, "killing_spree" },

    -- Subtlety
    { 3, 1, "relentless_strikes" },
    { 3, 2, "master_of_deception" },
    { 3, 3, "opportunity" },
    { 3, 4, "sleight_of_hand" },
    { 3, 5, "dirty_tricks" },
    { 3, 6, "camouflage" },
    { 3, 7, "elusiveness" },
    { 3, 8, "ghostly_strike" },
    { 3, 9, "serrated_blades" },
    { 3, 10, "setup" },
    { 3, 11, "initiative" },
    { 3, 12, "improved_ambush" },
    { 3, 13, "hemorrhage" },
    { 3, 14, "master_of_subtlety" },
    { 3, 15, "deadliness" },
    { 3, 16, "enveloping_shadows" },
    { 3, 17, "premeditation" },
    { 3, 18, "cheat_death" },
    { 3, 19, "sinister_calling" },
    { 3, 20, "waylay" },
    { 3, 21, "honor_among_thieves" },
    { 3, 22, "shadowstep" },
    { 3, 23, "filthy_tricks" },
    { 3, 24, "slaughter_from_the_shadows" },
    { 3, 25, "shadow_dance" },
})

-- Glyphs
DH:RegisterGlyphs({
    [64260] = "mutilate",  -- Glyph of Mutilate
    [57131] = "sinister_strike",  -- Glyph of Sinister Strike
    [57114] = "backstab",  -- Glyph of Backstab
    [57132] = "slice_and_dice",  -- Glyph of Slice and Dice
    [57120] = "eviscerate",  -- Glyph of Eviscerate
    [57128] = "rupture",  -- Glyph of Rupture
    [64285] = "killing_spree",  -- Glyph of Killing Spree
    [57112] = "adrenaline_rush",  -- Glyph of Adrenaline Rush
    [64284] = "hunger_for_blood",  -- Glyph of Hunger for Blood
    [64310] = "tricks_of_the_trade",  -- Glyph of Tricks of the Trade
    [57126] = "hemorrhage",  -- Glyph of Hemorrhage
})

-- Buff spell ID -> key mapping
DH:RegisterBuffMap({
    [6774] = "slice_and_dice",
    [51662] = "hunger_for_blood",
    [57993] = "envenom",
    [13877] = "blade_flurry",
    [13750] = "adrenaline_rush",
    [51690] = "killing_spree",
    [51713] = "shadow_dance",
    [36554] = "shadowstep",
    [14177] = "cold_blood",
    [31665] = "master_of_subtlety",
    [58427] = "overkill",
})

-- Debuff spell ID -> key mapping
DH:RegisterDebuffMap({
    -- Rupture (all ranks)
    [48672] = "rupture", [48671] = "rupture", [26867] = "rupture",
    [11275] = "rupture", [11274] = "rupture", [8640] = "rupture", [8639] = "rupture", [1943] = "rupture",
    -- Garrote
    [48676] = "garrote", [48675] = "garrote", [26884] = "garrote",
    -- Deadly Poison
    [57970] = "deadly_poison", [57969] = "deadly_poison",
    -- Wound Poison
    [57975] = "wound_poison", [57974] = "wound_poison",
    -- Expose Armor
    [8647] = "expose_armor",
    -- Hemorrhage
    [48660] = "hemorrhage",
})

DH:RegisterDebuffNamePatterns({
    { "rupture", "rupture" },
    { "garrote", "garrote" },
    { "deadly poison", "deadly_poison" },
    { "wound poison", "wound_poison" },
    { "expose armor", "expose_armor" },
    { "hemorrhage", "hemorrhage" },
})

DH:RegisterExternalDebuffMap({})
DH:RegisterExternalDebuffNamePatterns({})

-- ============================================================================
-- SPEC DETECTION
-- ============================================================================

DH:RegisterSpecDetector(function()
    local assassination, combat, subtlety = 0, 0, 0

    for i = 1, GetNumTalentTabs() do
        local _, _, points = GetTalentTabInfo(i)
        if i == 1 then assassination = points
        elseif i == 2 then combat = points
        else subtlety = points
        end
    end

    if assassination > combat and assassination > subtlety then
        return "assassination"
    elseif combat > subtlety then
        return "combat"
    else
        return "subtlety"
    end
end)

-- ============================================================================
-- DEFAULT SETTINGS
-- ============================================================================

-- Last-resort basic abilities shown when every recommendation was
-- filtered out as unknown (see DH:FirstKnownFallback).
DH:RegisterFallbackAbilities({
    "sinister_strike", "backstab", "mutilate", "hemorrhage",
})

DH:RegisterDefaults({
    assassination = {
        enabled = true,
        role = "dps",
        use_cold_blood = true,
        use_hunger_for_blood = true,
        use_vanish = true,
        aoe_threshold = 3,
        dot_refresh_buffer = 2.0,
    },
    combat = {
        enabled = true,
        role = "dps",
        use_killing_spree = true,
        use_adrenaline_rush = true,
        use_blade_flurry = true,
        aoe_threshold = 3,
        dot_refresh_buffer = 2.0,
    },
    subtlety = {
        enabled = true,
        role = "dps",
        use_shadow_dance = true,
        use_preparation = true,
        use_shadowstep = true,
        aoe_threshold = 3,
        dot_refresh_buffer = 2.0,
    },
})

DH:RegisterCommonDefaults()

DH:RegisterSnoozeable("killing_spree", 60)
DH:RegisterSnoozeable("adrenaline_rush", 60)
DH:RegisterSnoozeable("shadow_dance", 60)

-- ============================================================================
-- SLASH COMMANDS
-- ============================================================================

DH:RegisterSlashCommand("rog", function(cmd)
    local s = DH.State
    DH:UpdateState()
    DH:Print(L("--- Rogue Status ---"))
    DH:Print(L("Energy: ") .. tostring(s.energy.current) .. L(" | CP: ") .. tostring(s.combo_points.current))
    DH:Print(L("SnD: ") .. (s.buff.slice_and_dice.up and string.format("%.1fs", s.buff.slice_and_dice.remains) or L("DOWN")))
    DH:Print(L("Rupture: ") .. (s.debuff.rupture.up and string.format("%.1fs", s.debuff.rupture.remains) or L("DOWN")))
    DH:Print(L("HfB: ") .. (s.buff.hunger_for_blood.up and string.format("%.1fs", s.buff.hunger_for_blood.remains) or L("DOWN")))
    if DH.db and DH.db.debug then DH:Print(L("TTD: ") .. tostring(s.target.time_to_die) .. "s") end
end, "rog - Show rogue status")

-- ============================================================================
-- DEBUG FRAME
-- ============================================================================
ns.registered.debugFrameUpdater = DH:MakeDebugFrameUpdater(function(s, rec1, rec2, rec3)
    return {
            string.format(L("E: %d | CP: %d | GCD: %.2f"), s.energy.current, s.combo_points.current, s.gcd_remains),
            string.format(L("SnD:%.1f Rup:%.1f HfB:%.1f"), s.buff.slice_and_dice.remains, s.debuff.rupture.remains, s.buff.hunger_for_blood.remains),
    }
end)

-- v3.3.0: approximate direct-damage coefficients for the DPS forecast.
-- Observed combat-log averages override these once the spells land.

DH:RegisterSpellDamage({
  mutilate = { min=500, max=600, coeff=0.65, ap=true },
  sinister_strike = { min=300, max=400, coeff=0.45, ap=true },
  backstab = { min=450, max=550, coeff=0.63, ap=true },
  hemorrhage = { min=250, max=330, coeff=0.40, ap=true },
  ambush = { min=600, max=720, coeff=0.85, ap=true },
  eviscerate = { min=600, max=900, coeff=0.45, ap=true },
  envenom = { min=500, max=700, coeff=0.40, ap=true },
  fan_of_knives = { min=300, max=380, coeff=0.30, ap=true },
})
