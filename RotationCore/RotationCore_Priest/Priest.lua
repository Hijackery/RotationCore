-- RotationCore_Priest/Priest.lua
-- Priest class module: ability definitions + registration (Shadow DPS only)

local DH = RotationCore
if not DH then return end

if select(2, UnitClass("player")) ~= "PRIEST" then
    return
end

local ns = DH.ns
local L = function(s) local t = DH.L; return (t and t[s]) or s end
local class = DH.Class

-- ============================================================================
-- SPELL IDS (max rank for 3.3.5a)
-- ============================================================================

local SPELLS = {
    -- Shadow
    SHADOW_WORD_PAIN = 48125,
    VAMPIRIC_TOUCH = 48160,
    DEVOURING_PLAGUE = 48300,
    MIND_BLAST = 48127,
    MIND_FLAY = 48156,
    MIND_SEAR = 53023,
    SHADOW_WORD_DEATH = 48158,
    SHADOWFIEND = 34433,
    DISPERSION = 47585,
    SHADOWFORM = 15473,
    VAMPIRIC_EMBRACE = 15286,
    INNER_FOCUS = 14751,

    -- Holy / Discipline DPS
    SMITE = 48123,
    HOLY_FIRE = 48135,
    HOLY_NOVA = 48078,

    -- PvP
    PSYCHIC_SCREAM = 10890,
    SILENCE = 15487,
    FEAR_WARD = 6346,

    -- Shared
    POWER_WORD_SHIELD = 48066,
    FADE = 586,
}

ns.SPELLS = SPELLS

-- ============================================================================
-- ABILITY DEFINITIONS
-- ============================================================================

class.abilities = {
    shadow_word_pain = {
        id = SPELLS.SHADOW_WORD_PAIN,
        name = "Shadow Word: Pain",
        texture = 136207,
    },
    vampiric_touch = {
        id = SPELLS.VAMPIRIC_TOUCH,
        name = "Vampiric Touch",
        texture = 135978,
    },
    devouring_plague = {
        id = SPELLS.DEVOURING_PLAGUE,
        name = "Devouring Plague",
        texture = 136188,
    },
    mind_blast = {
        id = SPELLS.MIND_BLAST,
        name = "Mind Blast",
        texture = 136224,
    },
    mind_flay = {
        id = SPELLS.MIND_FLAY,
        name = "Mind Flay",
        texture = 136208,
    },
    shadow_word_death = {
        id = SPELLS.SHADOW_WORD_DEATH,
        name = "Shadow Word: Death",
        texture = 136149,
    },
    shadowfiend = {
        id = SPELLS.SHADOWFIEND,
        name = "Shadowfiend",
        texture = 136199,
    },
    dispersion = {
        id = SPELLS.DISPERSION,
        name = "Dispersion",
        texture = 237563,
    },
    shadowform = {
        id = SPELLS.SHADOWFORM,
        name = "Shadowform",
        texture = 136200,
    },
    vampiric_embrace = {
        id = SPELLS.VAMPIRIC_EMBRACE,
        name = "Vampiric Embrace",
        texture = 136230,
    },
    inner_focus = {
        id = SPELLS.INNER_FOCUS,
        name = "Inner Focus",
        texture = 135863,
    },
    mind_sear = {
        id = SPELLS.MIND_SEAR,
        name = "Mind Sear",
        texture = 135975,
    },

    -- Holy / Discipline DPS
    smite = {
        id = SPELLS.SMITE,
        name = "Smite",
        texture = 135924,
    },
    holy_fire = {
        id = SPELLS.HOLY_FIRE,
        name = "Holy Fire",
        texture = 135972,
    },
    holy_nova = {
        id = SPELLS.HOLY_NOVA,
        name = "Holy Nova",
        texture = 135922,
    },

    -- PvP
    psychic_scream = {
        id = SPELLS.PSYCHIC_SCREAM,
        name = "Psychic Scream",
        texture = 136184,
    },
    silence = {
        id = SPELLS.SILENCE,
        name = "Silence",
        texture = 136164,
    },
    fear_ward = {
        id = SPELLS.FEAR_WARD,
        name = "Fear Ward",
        texture = 135992,
    },
}

-- Create name mapping and get textures
DH:RegisterAbilityTable()

-- ============================================================================
-- REGISTER PRIEST DATA INTO FRAMEWORK
-- ============================================================================

DH:RegisterGCDSpell(SPELLS.MIND_BLAST)

DH:RegisterMeleeAbilities({})

-- Buffs to track
DH:RegisterBuffs({
    "shadowform",
    "vampiric_embrace",
    "inner_focus",
    "shadow_weaving",
    "improved_spirit_tap",
    "dispersion",
})

-- Debuffs to track
DH:RegisterDebuffs({
    "shadow_word_pain",
    "vampiric_touch",
    "devouring_plague",
    "shadow_weaving_debuff",
    "misery",
})

-- Cooldowns
DH:RegisterCooldowns({
    mind_blast = 48127,
    shadow_word_death = 48158,
    shadowfiend = 34433,
    dispersion = 47585,
    inner_focus = 14751,
})

-- Talents
DH:RegisterTalents({
    -- Discipline
    { 1, 3, "inner_focus" },
    { 1, 5, "improved_power_word_fortitude" },
    { 1, 7, "meditation" },
    { 1, 9, "inner_focus_talent" },
    { 1, 14, "focused_power" },

    -- Holy (minimal for Shadow)
    { 2, 1, "healing_focus" },
    { 2, 3, "improved_renew" },

    -- Shadow
    { 3, 1, "spirit_tap" },
    { 3, 2, "improved_spirit_tap" },
    { 3, 3, "darkness" },
    { 3, 4, "shadow_affinity" },
    { 3, 5, "improved_shadow_word_pain" },
    { 3, 6, "shadow_focus" },
    { 3, 7, "improved_psychic_scream" },
    { 3, 8, "improved_mind_blast" },
    { 3, 9, "mind_flay" },
    { 3, 10, "veiled_shadows" },
    { 3, 11, "shadow_reach" },
    { 3, 12, "shadow_weaving" },
    { 3, 13, "silence" },
    { 3, 14, "vampiric_embrace" },
    { 3, 15, "improved_vampiric_embrace" },
    { 3, 16, "focused_mind" },
    { 3, 17, "mind_melt" },
    { 3, 18, "improved_devouring_plague" },
    { 3, 19, "shadowform" },
    { 3, 20, "shadow_power" },
    { 3, 21, "improved_shadowform" },
    { 3, 22, "misery" },
    { 3, 23, "psychic_horror" },
    { 3, 24, "vampiric_touch" },
    { 3, 25, "pain_and_suffering" },
    { 3, 26, "twisted_faith" },
    { 3, 27, "dispersion" },
})

-- Glyphs
DH:RegisterGlyphs({
    [57192] = "shadow_word_pain",  -- Glyph of Shadow Word: Pain
    [57200] = "mind_flay",  -- Glyph of Mind Flay
    [64280] = "dispersion",  -- Glyph of Dispersion
    [57199] = "shadow_word_death",  -- Glyph of Shadow Word: Death
})

-- Buff spell ID -> key mapping
DH:RegisterBuffMap({
    [15473] = "shadowform",
    [15286] = "vampiric_embrace",
    [14751] = "inner_focus",
    [15258] = "shadow_weaving",
    [59000] = "improved_spirit_tap",
    [47585] = "dispersion",
})

-- Debuff spell ID -> key mapping
DH:RegisterDebuffMap({
    -- Shadow Word: Pain (all ranks)
    [48125] = "shadow_word_pain", [48124] = "shadow_word_pain",
    [25368] = "shadow_word_pain", [25367] = "shadow_word_pain",
    [10894] = "shadow_word_pain", [10893] = "shadow_word_pain",
    [10892] = "shadow_word_pain", [2767] = "shadow_word_pain",
    [992] = "shadow_word_pain", [970] = "shadow_word_pain",
    [594] = "shadow_word_pain", [589] = "shadow_word_pain",
    -- Vampiric Touch
    [48160] = "vampiric_touch", [48159] = "vampiric_touch",
    [34917] = "vampiric_touch", [34916] = "vampiric_touch", [34914] = "vampiric_touch",
    -- Devouring Plague
    [48300] = "devouring_plague", [48299] = "devouring_plague",
    [25467] = "devouring_plague",
})

DH:RegisterDebuffNamePatterns({
    { "shadow word: pain", "shadow_word_pain" },
    { "vampiric touch", "vampiric_touch" },
    { "devouring plague", "devouring_plague" },
})

DH:RegisterExternalDebuffMap({})
DH:RegisterExternalDebuffNamePatterns({})

-- ============================================================================
-- SPEC DETECTION
-- ============================================================================

DH:RegisterSpecDetector(function()
    local disc, holy, shadow = 0, 0, 0

    for i = 1, GetNumTalentTabs() do
        local _, _, points = GetTalentTabInfo(i)
        if i == 1 then disc = points
        elseif i == 2 then holy = points
        else shadow = points
        end
    end

    if shadow > disc and shadow > holy then
        return "shadow"
    elseif disc > holy then
        return "discipline"
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
    "mind_blast", "shadow_word_pain",
})

DH:RegisterDefaults({
    shadow = {
        enabled = true,
        role = "dps",
        use_shadowfiend = true,
        use_dispersion = true,
        use_inner_focus = true,
        mana_threshold_dispersion = 10,
        aoe_threshold = 3,
        dot_refresh_buffer = 2.0,
    },
})

DH:RegisterCommonDefaults()

DH:RegisterSnoozeable("shadowfiend", 60)

-- ============================================================================
-- SLASH COMMANDS
-- ============================================================================

DH:RegisterSlashCommand("sp", function(cmd)
    local s = DH.State
    DH:UpdateState()
    DH:Print(L("--- Shadow Priest Status ---"))
    DH:Print(L("Mana: ") .. tostring(math.floor(s.mana.pct)) .. "%")
    DH:Print(L("SWP: ") .. (s.debuff.shadow_word_pain.up and string.format("%.1fs", s.debuff.shadow_word_pain.remains) or L("DOWN")))
    DH:Print(L("VT: ") .. (s.debuff.vampiric_touch.up and string.format("%.1fs", s.debuff.vampiric_touch.remains) or L("DOWN")))
    DH:Print(L("DP: ") .. (s.debuff.devouring_plague.up and string.format("%.1fs", s.debuff.devouring_plague.remains) or L("DOWN")))
    DH:Print(L("MB CD: ") .. (s.cooldown.mind_blast.ready and L("READY") or string.format("%.1fs", s.cooldown.mind_blast.remains)))
    if DH.db and DH.db.debug then DH:Print(L("TTD: ") .. tostring(s.target.time_to_die) .. "s") end
end, "sp - Show shadow priest status")

-- ============================================================================
-- DEBUG FRAME
-- ============================================================================
ns.registered.debugFrameUpdater = DH:MakeDebugFrameUpdater(function(s, rec1, rec2, rec3)
    return {
            string.format(L("Mana: %d%% | GCD: %.2f"), math.floor(s.mana.pct), s.gcd_remains),
            string.format(L("SWP:%.1f VT:%.1f DP:%.1f"), s.debuff.shadow_word_pain.remains, s.debuff.vampiric_touch.remains, s.debuff.devouring_plague.remains),
            string.format(L("MB: %s | SWD: %s"), s.cooldown.mind_blast.ready and L("RDY") or string.format("%.1f", s.cooldown.mind_blast.remains), s.cooldown.shadow_word_death.ready and L("RDY") or string.format("%.1f", s.cooldown.shadow_word_death.remains)),
    }
end)

-- ============================================================================
-- MIND FLAY CLIP GLOW
-- Glow REC1 icon right after a Mind Flay tick lands to signal optimal clip time.
-- MF has 3 ticks over the channel duration (haste-adjusted).
-- Glow activates in a 0.3s window after each tick completes.
-- Only glows when REC1 is NOT mind_flay (i.e., something higher priority is ready).
-- ============================================================================

ns.registered.glowUpdater = function()
    ns.glowButtons = nil  -- reset each frame

    -- Only relevant when channeling Mind Flay
    local spell, _, _, _, startTime, endTime = UnitChannelInfo("player")
    if not spell or not startTime or not endTime then return end

    -- Check if channeling Mind Flay (match by name since ID may vary)
    local mfName = GetSpellInfo(SPELLS.MIND_FLAY)
    if spell ~= mfName then return end

    -- Only glow if REC1 is something other than Mind Flay (something to clip for)
    local rec1 = ns.recommendations[1]
    if not rec1 or rec1.ability == "mind_flay" then return end

    -- Calculate tick timing
    local now = GetTime()
    local channelStart = startTime / 1000
    local channelEnd = endTime / 1000
    local channelDuration = channelEnd - channelStart
    local tickInterval = channelDuration / 3  -- 3 ticks
    local elapsed = now - channelStart

    -- Check if we're in the clip window (within 0.3s after a tick)
    local currentTick = math.floor(elapsed / tickInterval)
    if currentTick >= 1 then
        local timeSinceTick = elapsed - (currentTick * tickInterval)
        if timeSinceTick >= 0 and timeSinceTick < 0.3 then
            ns.glowButtons = { [1] = true }
        end
    end
end

-- v3.3.0: approximate direct-damage coefficients for the DPS forecast.
-- Observed combat-log averages override these once the spells land.

DH:RegisterSpellDamage({
  mind_blast = { min=800, max=860, coeff=1.03 },
  mind_flay = { min=600, max=660, coeff=0.72, cast=3.0 },
  shadow_word_death = { min=570, max=650, coeff=0.43 },
  smite = { min=560, max=640, coeff=0.71, cast=2.5 },
  holy_fire = { min=600, max=700, coeff=0.57 },
  shadow_word_pain = { min=250, max=320, coeff=0.22 },
  devouring_plague = { min=700, max=850, coeff=0.52 },
  vampiric_touch = { min=750, max=900, coeff=0.53 },
})
