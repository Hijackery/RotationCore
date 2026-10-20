-- RotationCore_Paladin/Paladin.lua
-- Paladin class module: ability definitions + registration

local DH = RotationCore
if not DH then return end

-- Only load for Paladins
if select(2, UnitClass("player")) ~= "PALADIN" then
    return
end

local ns = DH.ns
local L = function(s) local t = DH.L; return (t and t[s]) or s end
local class = DH.Class

-- ============================================================================
-- SPELL IDS (max rank for 3.3.5a)
-- ============================================================================

local SPELLS = {
    -- Retribution
    CRUSADER_STRIKE = 35395,
    DIVINE_STORM = 53385,
    JUDGEMENT_OF_WISDOM = 53408,
    JUDGEMENT_OF_LIGHT = 20271,
    HAMMER_OF_WRATH = 48806,
    EXORCISM = 48801,
    CONSECRATION = 48819,
    AVENGING_WRATH = 31884,
    DIVINE_PLEA = 54428,

    -- Protection
    SHIELD_OF_RIGHTEOUSNESS = 61411,
    HAMMER_OF_THE_RIGHTEOUS = 53595,
    AVENGERS_SHIELD = 48827,
    HOLY_SHIELD = 48952,
    RIGHTEOUS_FURY = 25780,

    -- Holy
    HOLY_SHOCK = 48825,
    HOLY_LIGHT = 48782,

    -- Shared
    HOLY_WRATH = 48817,
    SEAL_OF_VENGEANCE = 31801,
    SEAL_OF_COMMAND = 20375,
    SEAL_OF_RIGHTEOUSNESS = 21084,
    SEAL_OF_WISDOM = 20166,

    -- PvP
    HAMMER_OF_JUSTICE = 10308,
    REPENTANCE = 20066,

    -- Auras
    DEVOTION_AURA = 48942,
    RETRIBUTION_AURA = 54043,

    -- Blessings
    BLESSING_OF_MIGHT = 48934,
    BLESSING_OF_KINGS = 20217,
}

ns.SPELLS = SPELLS

-- ============================================================================
-- ABILITY DEFINITIONS
-- ============================================================================

class.abilities = {
    -- Retribution
    crusader_strike = {
        id = SPELLS.CRUSADER_STRIKE,
        name = "Crusader Strike",
        texture = 135891,
    },
    divine_storm = {
        id = SPELLS.DIVINE_STORM,
        name = "Divine Storm",
        texture = 236250,
    },
    judgement_of_wisdom = {
        id = SPELLS.JUDGEMENT_OF_WISDOM,
        name = "Judgement of Wisdom",
        texture = 236255,
    },
    judgement_of_light = {
        id = SPELLS.JUDGEMENT_OF_LIGHT,
        name = "Judgement of Light",
        texture = 136002,
    },
    hammer_of_wrath = {
        id = SPELLS.HAMMER_OF_WRATH,
        name = "Hammer of Wrath",
        texture = 132326,
    },
    exorcism = {
        id = SPELLS.EXORCISM,
        name = "Exorcism",
        texture = 135903,
    },
    consecration = {
        id = SPELLS.CONSECRATION,
        name = "Consecration",
        texture = 135926,
    },
    avenging_wrath = {
        id = SPELLS.AVENGING_WRATH,
        name = "Avenging Wrath",
        texture = 135875,
    },
    divine_plea = {
        id = SPELLS.DIVINE_PLEA,
        name = "Divine Plea",
        texture = 236171,
    },

    -- Protection
    shield_of_righteousness = {
        id = SPELLS.SHIELD_OF_RIGHTEOUSNESS,
        name = "Shield of Righteousness",
        texture = 236265,
    },
    hammer_of_the_righteous = {
        id = SPELLS.HAMMER_OF_THE_RIGHTEOUS,
        name = "Hammer of the Righteous",
        texture = 236253,
    },
    avengers_shield = {
        id = SPELLS.AVENGERS_SHIELD,
        name = "Avenger's Shield",
        texture = 135874,
    },
    holy_shield = {
        id = SPELLS.HOLY_SHIELD,
        name = "Holy Shield",
        texture = 135880,
    },
    righteous_fury = {
        id = SPELLS.RIGHTEOUS_FURY,
        name = "Righteous Fury",
        texture = 135962,
    },

    -- Shared
    holy_wrath = {
        id = SPELLS.HOLY_WRATH,
        name = "Holy Wrath",
        texture = 135902,
    },
    seal_of_vengeance = {
        id = SPELLS.SEAL_OF_VENGEANCE,
        name = "Seal of Vengeance",
        texture = 236270,
    },
    seal_of_command = {
        id = SPELLS.SEAL_OF_COMMAND,
        name = "Seal of Command",
        texture = 132347,
    },
    seal_of_wisdom = {
        id = SPELLS.SEAL_OF_WISDOM,
        name = "Seal of Wisdom",
        texture = 132347,
    },

    -- Holy
    holy_shock = {
        id = SPELLS.HOLY_SHOCK,
        name = "Holy Shock",
        texture = 135972,
    },
    holy_light = {
        id = SPELLS.HOLY_LIGHT,
        name = "Holy Light",
        texture = 135907,
        heal = true,
    },

    -- PvP
    hammer_of_justice = {
        id = SPELLS.HAMMER_OF_JUSTICE,
        name = "Hammer of Justice",
        texture = 135963,
    },
    repentance = {
        id = SPELLS.REPENTANCE,
        name = "Repentance",
        texture = 135942,
    },
}

-- Create name mapping and get textures from GetSpellInfo
DH:RegisterAbilityTable()

-- ============================================================================
-- REGISTER PALADIN DATA INTO FRAMEWORK
-- ============================================================================

-- GCD reference spell (Crusader Strike)
DH:RegisterGCDSpell(SPELLS.CRUSADER_STRIKE)

-- Melee abilities (for UI range overlay)
DH:RegisterMeleeAbilities({
    "crusader_strike", "divine_storm", "hammer_of_wrath",
    "shield_of_righteousness", "hammer_of_the_righteous",
})

-- Buffs to track
DH:RegisterBuffs({
    "avenging_wrath", "divine_plea", "art_of_war",
    "seal_of_vengeance", "seal_of_command", "seal_of_wisdom", "seal_of_righteousness",
    "righteous_fury", "holy_shield",
    "devotion_aura", "retribution_aura",
    "divine_protection", "divine_shield",
    "blessing_of_might", "blessing_of_kings",
})

-- Debuffs to track
DH:RegisterDebuffs({
    "judgement_of_wisdom", "judgement_of_light",
    "holy_vengeance", -- SoV dot stacks
    "consecration",
    "training_dummy",
})

-- Cooldowns
DH:RegisterCooldowns({
    crusader_strike = SPELLS.CRUSADER_STRIKE,
    divine_storm = SPELLS.DIVINE_STORM,
    judgement = SPELLS.JUDGEMENT_OF_WISDOM,
    judgement_of_wisdom = SPELLS.JUDGEMENT_OF_WISDOM,
    hammer_of_wrath = SPELLS.HAMMER_OF_WRATH,
    exorcism = SPELLS.EXORCISM,
    consecration = SPELLS.CONSECRATION,
    avenging_wrath = SPELLS.AVENGING_WRATH,
    divine_plea = SPELLS.DIVINE_PLEA,
    shield_of_righteousness = SPELLS.SHIELD_OF_RIGHTEOUSNESS,
    hammer_of_the_righteous = SPELLS.HAMMER_OF_THE_RIGHTEOUS,
    avengers_shield = SPELLS.AVENGERS_SHIELD,
    holy_shield = SPELLS.HOLY_SHIELD,
    holy_wrath = SPELLS.HOLY_WRATH,
})

-- Talents
DH:RegisterTalents({
    -- Retribution
    { 3, 4, "crusader_strike" },
    { 3, 8, "sanctified_wrath" },
    { 3, 10, "repentance" },
    { 3, 11, "divine_storm" },
    { 3, 7, "the_art_of_war" },
    { 3, 6, "righteous_vengeance" },
    { 3, 5, "fanaticism" },
    { 3, 3, "improved_judgements" },
    { 3, 2, "heart_of_the_crusader" },
    { 3, 9, "swift_retribution" },

    -- Protection
    { 2, 1, "divinity" },
    { 2, 4, "divine_strength" },
    { 2, 6, "anticipation" },
    { 2, 9, "blessing_of_sanctuary" },
    { 2, 10, "holy_shield_talent" },
    { 2, 11, "ardent_defender" },
    { 2, 12, "redoubt" },
    { 2, 13, "combat_expertise" },
    { 2, 14, "touched_by_the_light" },
    { 2, 15, "avengers_shield" },
    { 2, 16, "guarded_by_the_light" },
    { 2, 17, "shield_of_the_templar" },
    { 2, 18, "judgements_of_the_just" },
    { 2, 19, "hammer_of_the_righteous" },

    -- Holy (relevant ones)
    { 1, 5, "divine_intellect" },
    { 1, 8, "aura_mastery" },
})

-- Glyphs
DH:RegisterGlyphs({
    [57030] = "judgement",  -- Glyph of Judgement
    [57025] = "exorcism",  -- Glyph of Exorcism
    [57024] = "crusader_strike",  -- Glyph of Crusader Strike
    [64308] = "shield_of_righteousness",  -- Glyph of Shield of Righteousness
    [57023] = "consecration",  -- Glyph of Consecration
    [64279] = "divine_storm",  -- Glyph of Divine Storm
    [57021] = "avenging_wrath",  -- Glyph of Avenging Wrath
})

-- Buff spell ID -> key mapping
DH:RegisterBuffMap({
    [31884] = "avenging_wrath",
    [54428] = "divine_plea",
    [59578] = "art_of_war",
    [53489] = "art_of_war",
    [31801] = "seal_of_vengeance",
    [20375] = "seal_of_command",
    [20166] = "seal_of_wisdom",
    [21084] = "seal_of_righteousness",
    [25780] = "righteous_fury",
    [48952] = "holy_shield",
    [498]   = "divine_protection",
    [642]   = "divine_shield",
    [48942] = "devotion_aura",
    [54043] = "retribution_aura",
    [48934] = "blessing_of_might",
    [20217] = "blessing_of_kings",
})

-- Debuff spell ID -> key mapping
DH:RegisterDebuffMap({
    [53408] = "judgement_of_wisdom",
    [20271] = "judgement_of_light",
    [31803] = "holy_vengeance", -- SoV dot
})

DH:RegisterDebuffNamePatterns({
    { "judgement of wisdom", "judgement_of_wisdom" },
    { "judgement of light", "judgement_of_light" },
    { "holy vengeance", "holy_vengeance" },
})

-- ============================================================================
-- SPEC DETECTION
-- ============================================================================

DH:RegisterSpecDetector(function()
    local holy, prot, ret = 0, 0, 0

    for i = 1, GetNumTalentTabs() do
        local _, _, points = GetTalentTabInfo(i)
        if i == 1 then holy = points
        elseif i == 2 then prot = points
        else ret = points
        end
    end

    if ret > prot and ret > holy then
        return "retribution"
    elseif prot > holy then
        return "protection"
    else
        return "holy"
    end
end)

-- ============================================================================
-- DEFAULT SETTINGS
-- ============================================================================

-- Last-resort basic abilities shown when every recommendation was
-- filtered out as unknown (see DH:FirstKnownFallback).
DH:RegisterFallbackAbilities({
    "crusader_strike", "exorcism", "judgement_of_light",
})

-- Buffs whose rising edge plays the proc sound (see DH:RegisterProcBuff).
DH:RegisterProcBuff("art_of_war")

DH:RegisterDefaults({
    ret = {
        enabled = true,
        role = "dps",
        use_avenging_wrath = true,
        use_divine_plea = true,
        use_exorcism = true,
        mana_threshold_divine_plea = 40,
        aoe_threshold = 3,
        dot_refresh_buffer = 2.0,
    },
    prot_paladin = {
        enabled = true,
        role = "tank",
        use_avenging_wrath = true,
        use_divine_plea = true,
        use_holy_shield = true,
        mana_threshold_divine_plea = 40,
        aoe_threshold = 3,
        dot_refresh_buffer = 2.0,
    },
})

DH:RegisterCommonDefaults()

-- Mana costs (% of base mana)
DH:RegisterManaCosts({
    crusader_strike = 0.05,
    judgement_of_wisdom = 0.05,
    divine_storm = 0.12,
    consecration = 0.22,
    exorcism = 0.08,
    holy_wrath = 0.20,
    hammer_of_wrath = 0.12,
    shield_of_righteousness = 0.06,
    hammer_of_the_righteous = 0.06,
    holy_shield = 0.10,
})

-- Major cooldowns: snoozeable if player skips them (60s snooze)
DH:RegisterSnoozeable("avenging_wrath", 60)

-- ============================================================================
-- SLASH COMMANDS
-- ============================================================================

DH:RegisterSlashCommand("ret", function(cmd)
    local s = DH.State
    DH:UpdateState()
    DH:Print(L("--- Ret Status ---"))
    DH:Print(L("Mana: ") .. tostring(s.mana.current) .. L("/") .. tostring(s.mana.max))
    DH:Print(L("Seal: ") .. (s.buff.seal_of_vengeance.up and L("Vengeance") or (s.buff.seal_of_command.up and L("Command") or L("None"))))
    DH:Print(L("AoW: ") .. (s.buff.art_of_war.up and L("|cFF00FF00UP|r") or L("no")))
    DH:Print(L("AW: ") .. (s.buff.avenging_wrath.up and L("|cFFFF0000UP|r") or (s.cooldown.avenging_wrath.ready and L("READY") or string.format(L("CD %.1f"), s.cooldown.avenging_wrath.remains))))
    DH:Print(L("CS CD: ") .. (s.cooldown.crusader_strike.ready and L("READY") or string.format("%.1f", s.cooldown.crusader_strike.remains)))
    DH:Print(L("DS CD: ") .. (s.cooldown.divine_storm.ready and L("READY") or string.format("%.1f", s.cooldown.divine_storm.remains)))
    DH:Print(L("Judge CD: ") .. (s.cooldown.judgement.ready and L("READY") or string.format("%.1f", s.cooldown.judgement.remains)))
    DH:Print(L("HoW CD: ") .. (s.cooldown.hammer_of_wrath.ready and L("READY") or string.format("%.1f", s.cooldown.hammer_of_wrath.remains)))
    if DH.db and DH.db.debug then DH:Print(L("TTD: ") .. tostring(s.target.time_to_die) .. "s") end
end, "ret - Show retribution status")

DH:RegisterSlashCommand("prot", function(cmd)
    local s = DH.State
    DH:UpdateState()
    DH:Print(L("--- Prot Status ---"))
    DH:Print(L("Mana: ") .. tostring(s.mana.current) .. L("/") .. tostring(s.mana.max))
    DH:Print(L("RF: ") .. (s.buff.righteous_fury.up and L("|cFF00FF00UP|r") or L("|cFFFF0000DOWN|r")))
    DH:Print(L("HS: ") .. (s.buff.holy_shield.up and L("|cFF00FF00UP|r") or (s.cooldown.holy_shield.ready and L("READY") or string.format(L("CD %.1f"), s.cooldown.holy_shield.remains))))
    DH:Print(L("SoR CD: ") .. (s.cooldown.shield_of_righteousness.ready and L("READY") or string.format("%.1f", s.cooldown.shield_of_righteousness.remains)))
    DH:Print(L("HotR CD: ") .. (s.cooldown.hammer_of_the_righteous.ready and L("READY") or string.format("%.1f", s.cooldown.hammer_of_the_righteous.remains)))
    DH:Print(L("AS CD: ") .. (s.cooldown.avengers_shield.ready and L("READY") or string.format("%.1f", s.cooldown.avengers_shield.remains)))
end, "prot - Show protection status")

-- ============================================================================
-- DEBUG FRAME
-- ============================================================================
ns.registered.debugFrameUpdater = DH:MakeDebugFrameUpdater(function(s, rec1, rec2, rec3)
        local seal = "None"
        if s.buff.seal_of_vengeance.up then seal = "SoV"
        elseif s.buff.seal_of_command.up then seal = "SoC"
        elseif s.buff.seal_of_righteousness.up then seal = "SoR"
        end
    return {
            string.format(L("Mana: %d/%d | Seal: %s"), s.mana.current, s.mana.max, seal),
            string.format(L("AoW: %s | AW: %s"), s.buff.art_of_war.up and L("|cFF00FF00UP|r") or L("no"), s.buff.avenging_wrath.up and L("|cFFFF0000UP|r") or L("no")),
    }
end)

-- v3.3.0: approximate direct-damage coefficients for the DPS forecast.
-- Observed combat-log averages override these once the spells land.

DH:RegisterSpellDamage({
  crusader_strike = { min=350, max=430, coeff=0.60, ap=true },
  divine_storm = { min=350, max=430, coeff=0.60, ap=true },
  hammer_of_wrath = { min=700, max=890, coeff=0.73 },
  exorcism = { min=500, max=600, coeff=0.60 },
  judgement_of_wisdom = { min=260, max=340, coeff=0.38, ap=true },
  judgement_of_light = { min=260, max=340, coeff=0.38, ap=true },
  shield_of_righteousness = { min=400, max=480, coeff=0.50, ap=true },
  hammer_of_the_righteous = { min=250, max=320, coeff=0.40, ap=true },
  consecration = { min=700, max=800, coeff=0.30 },
  holy_shock = { min=700, max=820, coeff=0.80 },
})
