-- RotationCore_Hunter/Hunter.lua
-- Hunter class module: ability definitions + registration of all Hunter-specific data

local DH = RotationCore
if not DH then return end

-- Only load for Hunters
if select(2, UnitClass("player")) ~= "HUNTER" then
    return
end

local ns = DH.ns
local L = function(s) local t = DH.L; return (t and t[s]) or s end
local class = DH.Class

-- ============================================================================
-- SPELL IDS (max rank for 3.3.5a)
-- ============================================================================

local SPELLS = {
    -- Shots
    STEADY_SHOT = 49052,
    AIMED_SHOT = 49050,
    ARCANE_SHOT = 49045,
    MULTI_SHOT = 49048,
    CHIMERA_SHOT = 53209,
    EXPLOSIVE_SHOT = 60053,
    KILL_SHOT = 61006,
    SILENCING_SHOT = 34490,

    -- DoTs / Traps
    SERPENT_STING = 49001,
    BLACK_ARROW = 63672,
    EXPLOSIVE_TRAP = 49067,

    -- Pet
    KILL_COMMAND = 34026,
    BESTIAL_WRATH = 19574,

    -- Cooldowns
    RAPID_FIRE = 3045,

    -- Aspects
    ASPECT_OF_THE_DRAGONHAWK = 61847,
    ASPECT_OF_THE_VIPER = 34074,
    ASPECT_OF_THE_HAWK = 27044,

    -- Utility
    HUNTERS_MARK = 53338,
    MISDIRECTION = 34477,
    DISENGAGE = 781,
    FEIGN_DEATH = 5384,

    -- PvP
    SCATTER_SHOT = 19503,
    WYVERN_STING = 49011,
    INTIMIDATION = 19577,
    DETERRENCE = 19263,
}

ns.SPELLS = SPELLS

-- ============================================================================
-- ABILITY DEFINITIONS
-- ============================================================================

class.abilities = {
    -- Shots
    steady_shot = {
        id = SPELLS.STEADY_SHOT,
        name = "Steady Shot",
        texture = 236182,
    },
    aimed_shot = {
        id = SPELLS.AIMED_SHOT,
        name = "Aimed Shot",
        texture = 135130,
    },
    arcane_shot = {
        id = SPELLS.ARCANE_SHOT,
        name = "Arcane Shot",
        texture = 132218,
    },
    multi_shot = {
        id = SPELLS.MULTI_SHOT,
        name = "Multi-Shot",
        texture = 132330,
    },
    chimera_shot = {
        id = SPELLS.CHIMERA_SHOT,
        name = "Chimera Shot",
        texture = 236176,
    },
    explosive_shot = {
        id = SPELLS.EXPLOSIVE_SHOT,
        name = "Explosive Shot",
        texture = 236178,
    },
    kill_shot = {
        id = SPELLS.KILL_SHOT,
        name = "Kill Shot",
        texture = 236174,
    },
    silencing_shot = {
        id = SPELLS.SILENCING_SHOT,
        name = "Silencing Shot",
        texture = 236174,
    },

    -- Aspects
    aspect_of_the_viper = {
        id = SPELLS.ASPECT_OF_THE_VIPER,
        name = "Aspect of the Viper",
        texture = 136076,
    },
    aspect_of_the_dragonhawk = {
        id = SPELLS.ASPECT_OF_THE_DRAGONHAWK,
        name = "Aspect of the Dragonhawk",
        texture = 61855,
    },

    -- DoTs / Traps
    serpent_sting = {
        id = SPELLS.SERPENT_STING,
        name = "Serpent Sting",
        texture = 132204,
    },
    black_arrow = {
        id = SPELLS.BLACK_ARROW,
        name = "Black Arrow",
        texture = 136181,
    },
    explosive_trap = {
        id = SPELLS.EXPLOSIVE_TRAP,
        name = "Explosive Trap",
        texture = 135826,
    },

    -- Pet
    kill_command = {
        id = SPELLS.KILL_COMMAND,
        name = "Kill Command",
        texture = 132176,
    },
    bestial_wrath = {
        id = SPELLS.BESTIAL_WRATH,
        name = "Bestial Wrath",
        texture = 132127,
    },

    -- Cooldowns
    rapid_fire = {
        id = SPELLS.RAPID_FIRE,
        name = "Rapid Fire",
        texture = 132208,
    },

    -- Utility
    hunters_mark = {
        id = SPELLS.HUNTERS_MARK,
        name = "Hunter's Mark",
        texture = 132212,
    },

    -- PvP
    scatter_shot = {
        id = SPELLS.SCATTER_SHOT,
        name = "Scatter Shot",
        texture = 132381,
    },
    wyvern_sting = {
        id = SPELLS.WYVERN_STING,
        name = "Wyvern Sting",
        texture = 135125,
    },
    intimidation = {
        id = SPELLS.INTIMIDATION,
        name = "Intimidation",
        texture = 132111,
    },
    deterrence = {
        id = SPELLS.DETERRENCE,
        name = "Deterrence",
        texture = 132369,
    },
}

-- Create name mapping and get textures from GetSpellInfo (3.3.5a compatible)
DH:RegisterAbilityTable()

-- ============================================================================
-- REGISTER HUNTER DATA INTO FRAMEWORK
-- ============================================================================

-- GCD reference spell (Arcane Shot)
DH:RegisterGCDSpell(SPELLS.ARCANE_SHOT)

-- No melee abilities for hunter
DH:RegisterMeleeAbilities({})

-- Buffs to track
DH:RegisterBuffs({
    "aspect_of_the_dragonhawk", "aspect_of_the_viper", "aspect_of_the_hawk",
    "rapid_fire",
    "bestial_wrath",
    "lock_and_load",
    "improved_steady_shot",
    "kill_command",
})

-- Debuffs to track
DH:RegisterDebuffs({
    "serpent_sting",
    "black_arrow",
    "hunters_mark",
    "explosive_trap",
})

-- Cooldowns
DH:RegisterCooldowns({
    steady_shot = 49052,
    aimed_shot = 49050,
    arcane_shot = 49045,
    multi_shot = 49048,
    chimera_shot = 53209,
    explosive_shot = 60053,
    kill_shot = 61006,
    serpent_sting = 49001,
    black_arrow = 63672,
    explosive_trap = 49067,
    kill_command = 34026,
    bestial_wrath = 19574,
    rapid_fire = 3045,
    silencing_shot = 34490,
})

-- Talents
DH:RegisterTalents({
    -- Beast Mastery
    { 1, 1, "improved_aspect_of_the_hawk" },
    { 1, 2, "endurance_training" },
    { 1, 3, "focused_fire" },
    { 1, 4, "improved_aspect_of_the_monkey" },
    { 1, 5, "thick_hide" },
    { 1, 6, "improved_revive_pet" },
    { 1, 7, "pathfinding" },
    { 1, 8, "aspect_mastery" },
    { 1, 9, "unleashed_fury" },
    { 1, 10, "improved_mend_pet" },
    { 1, 11, "ferocity" },
    { 1, 12, "spirit_bond" },
    { 1, 13, "intimidation" },
    { 1, 14, "bestial_discipline" },
    { 1, 15, "animal_handler" },
    { 1, 16, "frenzy" },
    { 1, 17, "ferocious_inspiration" },
    { 1, 18, "bestial_wrath" },
    { 1, 19, "catlike_reflexes" },
    { 1, 20, "invigoration" },
    { 1, 21, "serpents_swiftness" },
    { 1, 22, "longevity" },
    { 1, 23, "the_beast_within" },
    { 1, 24, "cobra_strikes" },
    { 1, 25, "kindred_spirits" },
    { 1, 26, "beast_mastery" },

    -- Marksmanship
    { 2, 1, "improved_concussive_shot" },
    { 2, 2, "focused_aim" },
    { 2, 3, "lethal_shots" },
    { 2, 4, "careful_aim" },
    { 2, 5, "improved_hunters_mark" },
    { 2, 6, "mortal_shots" },
    { 2, 7, "go_for_the_throat" },
    { 2, 8, "improved_arcane_shot" },
    { 2, 9, "aimed_shot" },
    { 2, 10, "rapid_killing" },
    { 2, 11, "improved_stings" },
    { 2, 12, "efficiency" },
    { 2, 13, "concussive_barrage" },
    { 2, 14, "readiness" },
    { 2, 15, "barrage" },
    { 2, 16, "combat_experience" },
    { 2, 17, "ranged_weapon_specialization" },
    { 2, 18, "piercing_shots" },
    { 2, 19, "trueshot_aura" },
    { 2, 20, "improved_barrage" },
    { 2, 21, "master_marksman" },
    { 2, 22, "rapid_recuperation" },
    { 2, 23, "wild_quiver" },
    { 2, 24, "silencing_shot" },
    { 2, 25, "improved_steady_shot" },
    { 2, 26, "marked_for_death" },
    { 2, 27, "chimera_shot" },

    -- Survival
    { 3, 1, "improved_tracking" },
    { 3, 2, "hawk_eye" },
    { 3, 3, "savage_strikes" },
    { 3, 4, "surefooted" },
    { 3, 5, "entrapment" },
    { 3, 6, "trap_mastery" },
    { 3, 7, "survival_instincts" },
    { 3, 8, "survivalist" },
    { 3, 9, "scatter_shot" },
    { 3, 10, "deflection" },
    { 3, 11, "survival_tactics" },
    { 3, 12, "tnt" },
    { 3, 13, "lock_and_load" },
    { 3, 14, "hunter_vs_wild" },
    { 3, 15, "killer_instinct" },
    { 3, 16, "lightning_reflexes" },
    { 3, 17, "resourcefulness" },
    { 3, 18, "expose_weakness" },
    { 3, 19, "wyvern_sting" },
    { 3, 20, "thrill_of_the_hunt" },
    { 3, 21, "master_tactician" },
    { 3, 22, "noxious_stings" },
    { 3, 23, "point_of_no_escape" },
    { 3, 24, "black_arrow" },
    { 3, 25, "sniper_training" },
    { 3, 26, "hunting_party" },
    { 3, 27, "explosive_shot" },
})

-- Glyphs
DH:RegisterGlyphs({
    [57011] = "steady_shot",  -- Glyph of Steady Shot
    [56869] = "aimed_shot",  -- Glyph of Aimed Shot
    [56995] = "arcane_shot",  -- Glyph of Arcane Shot
    [57007] = "multi_shot",  -- Glyph of Multi-Shot
    [64271] = "chimera_shot",  -- Glyph of Chimera Shot
    [64273] = "explosive_shot",  -- Glyph of Explosive Shot
    [64304] = "kill_shot",  -- Glyph of Kill Shot
    [57009] = "serpent_sting",  -- Glyph of Serpent Sting
    [56999] = "bestial_wrath",  -- Glyph of Bestial Wrath
    [57008] = "rapid_fire",  -- Glyph of Rapid Fire
})

-- Buff spell ID -> key mapping
DH:RegisterBuffMap({
    [61847] = "aspect_of_the_dragonhawk",
    [34074] = "aspect_of_the_viper",
    [27044] = "aspect_of_the_hawk",
    [3045] = "rapid_fire",
    [19574] = "bestial_wrath",
    [56453] = "lock_and_load",
    [53220] = "improved_steady_shot",
    [34026] = "kill_command",
})

-- Debuff spell ID -> key mapping (player-applied)
DH:RegisterDebuffMap({
    -- Serpent Sting (all ranks)
    [49001] = "serpent_sting", [49000] = "serpent_sting", [27016] = "serpent_sting",
    [25295] = "serpent_sting", [13555] = "serpent_sting", [13554] = "serpent_sting",
    [13553] = "serpent_sting", [13552] = "serpent_sting", [13551] = "serpent_sting",
    [13550] = "serpent_sting", [13549] = "serpent_sting", [1978] = "serpent_sting",
    -- Black Arrow
    [63672] = "black_arrow",
    -- Hunter's Mark
    [53338] = "hunters_mark",
    -- Explosive Trap
    [49067] = "explosive_trap",
})

-- Debuff name patterns (fallback matching)
DH:RegisterDebuffNamePatterns({
    { "serpent sting", "serpent_sting" },
    { "black arrow", "black_arrow" },
    { "hunter.*mark", "hunters_mark" },
    { "explosive trap", "explosive_trap" },
})

-- External debuff mapping
DH:RegisterExternalDebuffMap({})
DH:RegisterExternalDebuffNamePatterns({})

-- ============================================================================
-- SPEC DETECTION
-- ============================================================================

DH:RegisterSpecDetector(function()
    local bm, mm, sv = 0, 0, 0

    for i = 1, GetNumTalentTabs() do
        local _, _, points = GetTalentTabInfo(i)
        if i == 1 then bm = points
        elseif i == 2 then mm = points
        else sv = points
        end
    end

    if bm > mm and bm > sv then
        return "beast_mastery"
    elseif mm > sv then
        return "marksmanship"
    else
        return "survival"
    end
end)

-- ============================================================================
-- DEFAULT SETTINGS (class-specific)
-- ============================================================================

-- Last-resort basic abilities shown when every recommendation was
-- filtered out as unknown (see DH:FirstKnownFallback).
DH:RegisterFallbackAbilities({
    "steady_shot", "arcane_shot", "serpent_sting",
})

-- Buffs whose rising edge plays the proc sound (see DH:RegisterProcBuff).
DH:RegisterProcBuff("lock_and_load")

DH:RegisterDefaults({
    beast_mastery = {
        enabled = true,
        role = "dps",
        use_bestial_wrath = true,
        use_kill_command = true,
        use_rapid_fire = true,
        aoe_threshold = 4,
        dot_refresh_buffer = 2.0,
    },
    marksmanship = {
        enabled = true,
        role = "dps",
        use_rapid_fire = true,
        use_silencing_shot = true,
        use_aspect_dance = true,
        aoe_threshold = 3,
        dot_refresh_buffer = 2.0,
    },
    survival = {
        enabled = true,
        role = "dps",
        use_rapid_fire = true,
        use_aspect_dance = true,
        use_black_arrow = true,
        aoe_threshold = 3,
        dot_refresh_buffer = 2.0,
    },
    beast_mastery = {
        enabled = true,
        role = "dps",
        use_bestial_wrath = true,
        use_kill_command = true,
        use_rapid_fire = true,
        use_aspect_dance = true,
        aoe_threshold = 4,
        dot_refresh_buffer = 2.0,
    },
})

DH:RegisterCommonDefaults()

-- Major cooldowns: snoozeable if player skips them
DH:RegisterSnoozeable("bestial_wrath", 60)
DH:RegisterSnoozeable("rapid_fire", 60)

-- ============================================================================
-- SLASH COMMANDS (Hunter-specific)
-- ============================================================================

DH:RegisterSlashCommand("hunt", function(cmd)
    local s = DH.State
    DH:UpdateState()
    DH:Print(L("--- Hunter Status ---"))
    DH:Print(L("Mana: ") .. tostring(math.floor(s.mana.pct)) .. "%")
    DH:Print(L("Serpent Sting: ") .. (s.debuff.serpent_sting.up and string.format("%.1fs", s.debuff.serpent_sting.remains) or L("DOWN")))
    DH:Print(L("Black Arrow: ") .. (s.debuff.black_arrow.up and string.format("%.1fs", s.debuff.black_arrow.remains) or L("DOWN")))
    DH:Print(L("Lock and Load: ") .. (s.buff.lock_and_load.up and (tostring(s.buff.lock_and_load.stacks) .. L(" stacks")) or L("no")))
    if DH.db and DH.db.debug then DH:Print(L("TTD: ") .. tostring(s.target.time_to_die) .. "s") end
end, "hunt - Show hunter status")

-- ============================================================================
-- DEBUG FRAME (Hunter-specific)
-- ============================================================================
ns.registered.debugFrameUpdater = DH:MakeDebugFrameUpdater(function(s, rec1, rec2, rec3)
    return {
            string.format(L("Mana: %d%% | GCD: %.2f"), math.floor(s.mana.pct), s.gcd_remains),
            string.format(L("SS: %.1f | BA: %.1f"), s.debuff.serpent_sting.remains, s.debuff.black_arrow.remains),
            string.format(L("LnL: %d | ISS: %s"), s.buff.lock_and_load.stacks or 0, s.buff.improved_steady_shot.up and L("UP") or L("no")),
    }
end)

-- v3.3.0: approximate direct-damage coefficients for the DPS forecast.
-- Observed combat-log averages override these once the spells land.

DH:RegisterSpellDamage({
  steady_shot = { min=260, max=340, coeff=0.20, cast=1.5, ap=true },
  aimed_shot = { min=480, max=570, coeff=0.55, cast=2.5, ap=true },
  arcane_shot = { min=300, max=360, coeff=0.15, ap=true },
  multi_shot = { min=300, max=380, coeff=0.25, ap=true },
  chimera_shot = { min=420, max=500, coeff=0.50, ap=true },
  explosive_shot = { min=400, max=480, coeff=0.25, ap=true },
  kill_shot = { min=550, max=650, coeff=0.60, ap=true },
})
