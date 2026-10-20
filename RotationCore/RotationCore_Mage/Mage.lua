-- RotationCore_Mage/Mage.lua
-- Mage class module: ability definitions + registration

local DH = RotationCore
if not DH then return end

if select(2, UnitClass("player")) ~= "MAGE" then
    return
end

local ns = DH.ns
local L = function(s) local t = DH.L; return (t and t[s]) or s end
local class = DH.Class

-- ============================================================================
-- SPELL IDS (max rank for 3.3.5a)
-- ============================================================================

local SPELLS = {
    -- Arcane
    ARCANE_BLAST = 42897,
    ARCANE_MISSILES = 42846,
    ARCANE_BARRAGE = 44781,
    ARCANE_EXPLOSION = 42921,
    ARCANE_POWER = 12042,
    PRESENCE_OF_MIND = 12043,

    -- Fire
    FIREBALL = 42833,
    PYROBLAST = 42891,
    SCORCH = 42859,
    LIVING_BOMB = 55360,
    COMBUSTION = 11129,
    FROSTFIRE_BOLT = 47610,

    -- Frost
    FROSTBOLT = 42842,
    ICE_LANCE = 42914,
    DEEP_FREEZE = 44572,

    -- Shared
    MIRROR_IMAGE = 55342,
    EVOCATION = 12051,
    ICY_VEINS = 12472,
    COLD_SNAP = 11958,
    MANA_GEM = 42985,

    -- AOE (part 4) - max rank for 3.3.5a
    BLIZZARD = 42938,
    CONE_OF_COLD = 42931,
    FLAMESTRIKE = 42926,
    BLAST_WAVE = 42945,

    -- PvP
    COUNTERSPELL = 2139,
    POLYMORPH = 118,
    FROST_NOVA = 122,
    ICE_BLOCK = 45438,
    BLINK = 1953,
}

ns.SPELLS = SPELLS

-- ============================================================================
-- ABILITY DEFINITIONS
-- ============================================================================

class.abilities = {
    -- Arcane
    arcane_blast = {
        id = SPELLS.ARCANE_BLAST,
        name = "Arcane Blast",
        texture = 135735,
    },
    arcane_missiles = {
        id = SPELLS.ARCANE_MISSILES,
        name = "Arcane Missiles",
        texture = 136096,
    },
    arcane_barrage = {
        id = SPELLS.ARCANE_BARRAGE,
        name = "Arcane Barrage",
        texture = 236205,
    },
    arcane_power = {
        id = SPELLS.ARCANE_POWER,
        name = "Arcane Power",
        texture = 136048,
    },
    presence_of_mind = {
        id = SPELLS.PRESENCE_OF_MIND,
        name = "Presence of Mind",
        texture = 136031,
    },

    -- Fire
    fireball = {
        id = SPELLS.FIREBALL,
        name = "Fireball",
        texture = 135812,
    },
    pyroblast = {
        id = SPELLS.PYROBLAST,
        name = "Pyroblast",
        texture = 135808,
    },
    scorch = {
        id = SPELLS.SCORCH,
        name = "Scorch",
        texture = 135827,
    },
    living_bomb = {
        id = SPELLS.LIVING_BOMB,
        name = "Living Bomb",
        texture = 236220,
    },
    combustion = {
        id = SPELLS.COMBUSTION,
        name = "Combustion",
        texture = 135824,
    },
    frostfire_bolt = {
        id = SPELLS.FROSTFIRE_BOLT,
        name = "Frostfire Bolt",
        texture = 236218,
    },

    -- Frost
    frostbolt = {
        id = SPELLS.FROSTBOLT,
        name = "Frostbolt",
        texture = 135846,
    },
    ice_lance = {
        id = SPELLS.ICE_LANCE,
        name = "Ice Lance",
        texture = 135844,
    },
    deep_freeze = {
        id = SPELLS.DEEP_FREEZE,
        name = "Deep Freeze",
        texture = 236209,
    },

    -- AOE (part 4)
    arcane_explosion = {
        id = SPELLS.ARCANE_EXPLOSION,
        name = "Arcane Explosion",
        texture = 136020,
    },
    blizzard = {
        id = SPELLS.BLIZZARD,
        name = "Blizzard",
        texture = 135865,
    },
    cone_of_cold = {
        id = SPELLS.CONE_OF_COLD,
        name = "Cone of Cold",
        texture = 135852,
    },
    flamestrike = {
        id = SPELLS.FLAMESTRIKE,
        name = "Flamestrike",
        texture = 135826,
    },
    blast_wave = {
        id = SPELLS.BLAST_WAVE,
        name = "Blast Wave",
        texture = 135903,
    },

    -- Shared
    mirror_image = {
        id = SPELLS.MIRROR_IMAGE,
        name = "Mirror Image",
        texture = 135994,
    },
    evocation = {
        id = SPELLS.EVOCATION,
        name = "Evocation",
        texture = 136075,
    },
    icy_veins = {
        id = SPELLS.ICY_VEINS,
        name = "Icy Veins",
        texture = 135838,
    },
    cold_snap = {
        id = SPELLS.COLD_SNAP,
        name = "Cold Snap",
    },

    -- PvP
    counterspell = {
        id = SPELLS.COUNTERSPELL,
        name = "Counterspell",
        texture = 135856,
    },
    polymorph = {
        id = SPELLS.POLYMORPH,
        name = "Polymorph",
        texture = 136071,
    },
    frost_nova = {
        id = SPELLS.FROST_NOVA,
        name = "Frost Nova",
        texture = 135848,
    },
    ice_block = {
        id = SPELLS.ICE_BLOCK,
        name = "Ice Block",
        texture = 135841,
    },
    blink = {
        id = SPELLS.BLINK,
        name = "Blink",
        texture = 135736,
    },
}

-- Create name mapping and get textures
DH:RegisterAbilityTable()

-- ============================================================================
-- REGISTER MAGE DATA INTO FRAMEWORK
-- ============================================================================

DH:RegisterGCDSpell(SPELLS.FROSTBOLT)

DH:RegisterMeleeAbilities({})

-- Buffs to track
DH:RegisterBuffs({
    "arcane_blast_aura",
    "missile_barrage",
    "hot_streak",
    "fingers_of_frost",
    "brain_freeze",
    "clearcasting",
    "arcane_power",
    "icy_veins",
    "combustion",
    "presence_of_mind",
    "mirror_image",
})

-- Debuffs to track
DH:RegisterDebuffs({
    "living_bomb",
    "improved_scorch",
    "winters_chill",
    "ignite",
    "frostbolt_debuff",
})

-- Cooldowns
DH:RegisterCooldowns({
    arcane_blast = 42897,
    arcane_missiles = 42846,
    arcane_barrage = 44781,
    arcane_power = 12042,
    presence_of_mind = 12043,
    fireball = 42833,
    pyroblast = 42891,
    scorch = 42859,
    living_bomb = 55360,
    combustion = 11129,
    blast_wave = 11113,
    cone_of_cold = 120,
    frostbolt = 42842,
    ice_lance = 42914,
    deep_freeze = 44572,
    mirror_image = 55342,
    evocation = 12051,
    icy_veins = 12472,
    cold_snap = 11958,
})

-- Talents
DH:RegisterTalents({
    -- Arcane
    { 1, 1, "arcane_subtlety" },
    { 1, 2, "arcane_focus" },
    { 1, 3, "arcane_stability" },
    { 1, 4, "arcane_fortitude" },
    { 1, 5, "magic_absorption" },
    { 1, 6, "arcane_concentration" },
    { 1, 7, "magic_attunement" },
    { 1, 8, "spell_impact" },
    { 1, 9, "student_of_the_mind" },
    { 1, 10, "focus_magic" },
    { 1, 11, "arcane_shielding" },
    { 1, 12, "improved_counterspell" },
    { 1, 13, "arcane_meditation" },
    { 1, 14, "torment_the_weak" },
    { 1, 15, "improved_blink" },
    { 1, 16, "presence_of_mind" },
    { 1, 17, "arcane_mind" },
    { 1, 18, "prismatic_cloak" },
    { 1, 19, "arcane_instability" },
    { 1, 20, "arcane_potency" },
    { 1, 21, "arcane_empowerment" },
    { 1, 22, "arcane_power" },
    { 1, 23, "incanters_absorption" },
    { 1, 24, "arcane_flows" },
    { 1, 25, "mind_mastery" },
    { 1, 26, "missile_barrage" },
    { 1, 27, "netherwind_presence" },
    { 1, 28, "spell_power" },
    { 1, 29, "arcane_barrage" },

    -- Fire
    { 2, 1, "improved_fire_blast" },
    { 2, 2, "incineration" },
    { 2, 3, "improved_fireball" },
    { 2, 4, "ignite" },
    { 2, 5, "burning_determination" },
    { 2, 6, "world_in_flames" },
    { 2, 7, "flame_throwing" },
    { 2, 8, "impact" },
    { 2, 9, "pyroblast" },
    { 2, 10, "burning_soul" },
    { 2, 11, "improved_scorch" },
    { 2, 12, "molten_shields" },
    { 2, 13, "master_of_elements" },
    { 2, 14, "playing_with_fire" },
    { 2, 15, "critical_mass" },
    { 2, 16, "blast_wave" },
    { 2, 17, "blazing_speed" },
    { 2, 18, "fire_power" },
    { 2, 19, "pyromaniac" },
    { 2, 20, "combustion" },
    { 2, 21, "molten_fury" },
    { 2, 22, "fiery_payback" },
    { 2, 23, "empowered_fire" },
    { 2, 24, "firestarter" },
    { 2, 25, "dragons_breath" },
    { 2, 26, "hot_streak" },
    { 2, 27, "burnout" },
    { 2, 28, "living_bomb" },

    -- Frost
    { 3, 1, "frostbite" },
    { 3, 2, "improved_frostbolt" },
    { 3, 3, "ice_floes" },
    { 3, 4, "ice_shards" },
    { 3, 5, "frost_warding" },
    { 3, 6, "precision" },
    { 3, 7, "permafrost" },
    { 3, 8, "piercing_ice" },
    { 3, 9, "icy_veins" },
    { 3, 10, "improved_blizzard" },
    { 3, 11, "arctic_reach" },
    { 3, 12, "frost_channeling" },
    { 3, 13, "shatter" },
    { 3, 14, "cold_snap" },
    { 3, 15, "improved_cone_of_cold" },
    { 3, 16, "cold_as_ice" },
    { 3, 17, "winters_chill" },
    { 3, 18, "arctic_winds" },
    { 3, 19, "empowered_frostbolt" },
    { 3, 20, "fingers_of_frost" },
    { 3, 21, "brain_freeze" },
    { 3, 22, "summon_water_elemental" },
    { 3, 23, "enduring_winter" },
    { 3, 24, "chilled_to_the_bone" },
    { 3, 25, "deep_freeze" },
})

-- Glyphs
DH:RegisterGlyphs({
    [56991] = "arcane_blast",  -- Glyph of Arcane Blast
    [56971] = "arcane_missiles",  -- Glyph of Arcane Missiles
    [64276] = "arcane_barrage",  -- Glyph of Arcane Barrage
    [56975] = "fireball",  -- Glyph of Fireball
    [56982] = "scorch",  -- Glyph of Scorch
    [64275] = "living_bomb",  -- Glyph of Living Bomb
    [56977] = "frostbolt",  -- Glyph of Frostbolt
    [56980] = "ice_lance",  -- Glyph of Ice Lance
    [64314] = "mirror_image",  -- Glyph of Mirror Image
    [56974] = "evocation",  -- Glyph of Evocation
    [56981] = "icy_veins",  -- Glyph of Icy Veins
    [61677] = "frostfire_bolt",  -- Glyph of Frostfire
})

-- Buff spell ID -> key mapping
DH:RegisterBuffMap({
    [36032] = "arcane_blast_aura",
    [44401] = "missile_barrage",
    [44448] = "hot_streak",
    [48108] = "hot_streak",
    [44545] = "fingers_of_frost",
    [44549] = "brain_freeze",
    [12536] = "clearcasting",
    [12042] = "arcane_power",
    [12472] = "icy_veins",
    [11129] = "combustion",
    [28682] = "combustion",
    [12043] = "presence_of_mind",
    [55342] = "mirror_image",
})

-- Debuff spell ID -> key mapping
DH:RegisterDebuffMap({
    [55360] = "living_bomb",
    [12873] = "improved_scorch",
    [12654] = "ignite",
})

DH:RegisterDebuffNamePatterns({
    { "living bomb", "living_bomb" },
    { "improved scorch", "improved_scorch" },
    { "ignite", "ignite" },
    { "winter.*chill", "winters_chill" },
})

DH:RegisterExternalDebuffMap({})
DH:RegisterExternalDebuffNamePatterns({})

-- ============================================================================
-- SPEC DETECTION
-- ============================================================================

DH:RegisterSpecDetector(function()
    local arcane, fire, frost = 0, 0, 0

    for i = 1, GetNumTalentTabs() do
        local _, _, points = GetTalentTabInfo(i)
        if i == 1 then arcane = points
        elseif i == 2 then fire = points
        else frost = points
        end
    end

    if arcane > fire and arcane > frost then
        return "arcane"
    elseif fire > frost then
        return "fire"
    else
        return "frost"
    end
end)

-- ============================================================================
-- BUILD DETECTION (Improvement 2)
-- ============================================================================
-- Only Mage has meaningful sub-builds; the other nine classes use their spec
-- directly. A fire mage is split into:
--   * "ttw" - Frostfire Bolt paired with the Torment the Weak arcane talent
--   * "ffb" - Frostfire Bolt build without Torment the Weak
--   * nil   - plain Fireball fire build (falls back to the "fire" spec key)
DH:RegisterBuildDetector(function(spec, st, mode)
    if spec ~= "fire" and spec ~= "arcane" and spec ~= "frost" then
        return nil
    end

    local function trank(key)
        local t = st and st.talent and st.talent[key]
        return (t and t.rank) or 0
    end
    local function genabled(key)
        local g = st and st.glyph and st.glyph[key]
        return g and g.enabled
    end

    local useGlyphs = (mode == "talents_glyphs" or mode == "talents_glyphs_stats")

    -- Improvement 7: arcane / frost sub-builds are keyed off their core glyph.
    -- "arcane_blast" / "frostbolt" are informational build keys; the spec's
    -- rotation already handles them, so selecting them changes no behaviour.
    if spec == "arcane" then
        if useGlyphs and genabled("arcane_blast") then
            return "arcane_blast", "glyphs"
        end
        return nil
    end
    if spec == "frost" then
        if useGlyphs and genabled("frostbolt") then
            return "frostbolt", "glyphs"
        end
        return nil
    end

    -- Fire: Frostfire Bolt paired with the Torment the Weak arcane talent.
    local hasTTW = trank("torment_the_weak") > 0
    local hasFFB = false
    if useGlyphs then
        hasFFB = genabled("frostfire_bolt")
            or (DH.IsSpellKnownId and DH:IsSpellKnownId(SPELLS.FROSTFIRE_BOLT))
    end

    if hasTTW and (hasFFB or mode == "talents") then
        return "ttw", "talents"
    elseif hasFFB then
        return "ffb", "glyphs"
    end
    return nil
end)

-- ============================================================================
-- DEFAULT SETTINGS
-- ============================================================================

-- Last-resort basic abilities shown when every recommendation was
-- filtered out as unknown (see DH:FirstKnownFallback).
DH:RegisterFallbackAbilities({
    "frostbolt", "fireball", "scorch", "arcane_blast", "fire_blast",
})

-- Buffs whose rising edge plays the proc sound (see DH:RegisterProcBuff).
DH:RegisterProcBuff("missile_barrage")
DH:RegisterProcBuff("hot_streak")
DH:RegisterProcBuff("fingers_of_frost")
DH:RegisterProcBuff("brain_freeze")
DH:RegisterProcBuff("clearcasting")

DH:RegisterDefaults({
    arcane = {
        enabled = true,
        role = "dps",
        use_icy_veins = true,
        use_arcane_power = true,
        use_mirror_image = true,
        use_presence_of_mind = true,
        use_evocation = true,
        aoe_threshold = 3,
        dot_refresh_buffer = 2.0,
        mana_threshold_evocation = 15,
    },
    fire = {
        enabled = true,
        role = "dps",
        use_icy_veins = true,
        use_mirror_image = true,
        use_combustion = true,
        use_evocation = true,
        aoe_threshold = 3,
        dot_refresh_buffer = 2.0,
        mana_threshold_evocation = 15,
    },
    frost_mage = {
        enabled = true,
        role = "dps",
        use_icy_veins = true,
        use_cold_snap = true,
        use_mirror_image = true,
        use_evocation = true,
        aoe_threshold = 3,
        dot_refresh_buffer = 2.0,
        mana_threshold_evocation = 15,
    },
})

DH:RegisterCommonDefaults()

DH:RegisterSnoozeable("mirror_image", 60)
DH:RegisterSnoozeable("arcane_power", 60)
DH:RegisterSnoozeable("icy_veins", 60)
DH:RegisterSnoozeable("combustion", 60)

-- ============================================================================
-- ARCANE BLAST STACK TRACKING (combat log based)
-- The AB stack aura is not visible via UnitBuff in 3.3.5a, so we track
-- it manually: increment on AB cast, reset on AM/ABarrage cast or timeout.
-- ============================================================================

ns.ab_stacks = 0
ns.ab_last_cast = 0
local AB_STACK_DURATION = 8  -- stacks expire after 8s without refresh

DH:RegisterCombatLogHandler(function(subevent, sourceGUID, destGUID, spellId, spellName, ...)
    if sourceGUID ~= UnitGUID("player") then return end

    if subevent == "SPELL_CAST_SUCCESS" then
        if spellId == SPELLS.ARCANE_BLAST then
            ns.ab_stacks = math.min(4, ns.ab_stacks + 1)
            ns.ab_last_cast = GetTime()
        elseif spellId == SPELLS.ARCANE_MISSILES or spellId == SPELLS.ARCANE_BARRAGE then
            ns.ab_stacks = 0
            ns.ab_last_cast = 0
        end
    end
end)

-- Hook into state update to expire stacks after 8s
local origUpdateBuffs = DH.State.UpdateBuffs
function DH.State:UpdateBuffs()
    origUpdateBuffs(self)

    -- Expire AB stacks if 8s since last AB cast
    if ns.ab_stacks > 0 and ns.ab_last_cast > 0 then
        if GetTime() - ns.ab_last_cast > AB_STACK_DURATION then
            ns.ab_stacks = 0
            ns.ab_last_cast = 0
        end
    end

    -- Write tracked stacks into the buff table so Core.lua can read them
    self.buff.arcane_blast_aura.count = ns.ab_stacks
    if ns.ab_stacks > 0 then
        self.buff.arcane_blast_aura.expires = ns.ab_last_cast + AB_STACK_DURATION
    else
        self.buff.arcane_blast_aura.expires = 0
    end
end

-- ============================================================================
-- SLASH COMMANDS
-- ============================================================================

DH:RegisterSlashCommand("mage", function(cmd)
    local s = DH.State
    DH:UpdateState()
    DH:Print(L("--- Mage Status ---"))
    DH:Print(L("Mana: ") .. tostring(math.floor(s.mana.pct)) .. "%")
    DH:Print(L("AB Stacks: ") .. tostring(s.buff.arcane_blast_aura.stacks or 0))
    DH:Print(L("Hot Streak: ") .. (s.buff.hot_streak.up and L("UP") or L("no")))
    DH:Print(L("Missile Barrage: ") .. (s.buff.missile_barrage.up and L("UP") or L("no")))
    DH:Print(L("FoF: ") .. tostring(s.buff.fingers_of_frost.stacks or 0) .. L(" | BF: ") .. (s.buff.brain_freeze.up and L("UP") or L("no")))
    if DH.db and DH.db.debug then DH:Print(L("TTD: ") .. tostring(s.target.time_to_die) .. "s") end
end, "mage - Show mage status")

-- ============================================================================
-- DEBUG FRAME
-- ============================================================================
ns.registered.debugFrameUpdater = DH:MakeDebugFrameUpdater(function(s, rec1, rec2, rec3)
    return {
            string.format(L("Mana: %d%% | GCD: %.2f"), math.floor(s.mana.pct), s.gcd_remains),
            string.format(L("AB:%d HS:%s MB:%s FoF:%d BF:%s"),
                s.buff.arcane_blast_aura.stacks or 0,
                s.buff.hot_streak.up and L("Y") or L("N"),
                s.buff.missile_barrage.up and L("Y") or L("N"),
                s.buff.fingers_of_frost.stacks or 0,
                s.buff.brain_freeze.up and L("Y") or L("N")),
    }
end)

-- v3.3.0: approximate direct-damage coefficients for the DPS forecast.
-- Observed combat-log averages override these once the spells land.

DH:RegisterSpellDamage({
  arcane_blast = { min=580, max=670, coeff=0.71, cast=2.5 },
  fireball = { min=590, max=760, coeff=1.15, cast=3.0 },
  frostbolt = { min=560, max=700, coeff=0.86, cast=2.5 },
  frostfire_bolt = { min=650, max=830, coeff=0.96, cast=3.0 },
  ice_lance = { min=280, max=370, coeff=0.33 },
  scorch = { min=300, max=390, coeff=0.43, cast=1.5 },
  pyroblast = { min=870, max=1020, coeff=1.26, cast=3.0 },
  arcane_missiles = { min=430, max=520, coeff=0.53, cast=2.0 },
  arcane_barrage = { min=750, max=860, coeff=0.81 },
  deep_freeze = { min=580, max=680, coeff=0.71 },
  blizzard = { min=800, max=900, coeff=0.76, cast=3.0 },
  cone_of_cold = { min=380, max=450, coeff=0.36 },
  flamestrike = { min=700, max=830, coeff=0.67, cast=2.0 },
})
