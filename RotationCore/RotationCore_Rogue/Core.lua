-- RotationCore_Rogue/Core.lua
-- Priority rotation logic for Rogue specs (3.3.5a compatible)
-- Uses core RunSimulation with energy/CP tracking

local DH = RotationCore
if not DH then return end

if select(2, UnitClass("player")) ~= "ROGUE" then
    return
end

local ns = DH.ns
local class = DH.Class
local state = DH.State

-- ============================================================================
-- ASSASSINATION (MUTILATE) ROTATION
-- ============================================================================

local assConfig = {
    gcdType = "melee",
    maxRecs = 3,
    allowDupes = true,
    cds = {
        cold_blood = "cold_blood",
        hunger_for_blood = "hunger_for_blood",
        vanish = "vanish",
    },
    baseCDs = {
        cold_blood = 180,
        hunger_for_blood = 30,
        vanish = 180,
    },
    resources = {
        {
            field = "energy",
            max = "energy_max",
            regen = 10,  -- base energy regen
            initFrom = function(s) return s.energy.current end,
            initMaxFrom = function(s) return s.energy.max end,
        },
    },
    auras = {
        { up = "snd_up", remains = "snd_remains" },
        { up = "rupture_up", remains = "rupture_remains" },
        { up = "hfb_up", remains = "hfb_remains" },
        { up = "envenom_up", remains = "envenom_remains" },
    },
    initState = function(sim, s)
        sim.cp = s.combo_points.current

        -- Buffs
        sim.snd_up = s.buff.slice_and_dice.up
        sim.snd_remains = s.buff.slice_and_dice.remains
        sim.hfb_up = s.buff.hunger_for_blood.up
        sim.hfb_remains = s.buff.hunger_for_blood.remains
        sim.envenom_up = s.buff.envenom.up
        sim.envenom_remains = s.buff.envenom.remains

        -- Debuffs
        sim.rupture_up = s.debuff.rupture.up
        sim.rupture_remains = s.debuff.rupture.remains

        -- Talents
        sim.has_mutilate = s.talent.mutilate.rank > 0
        sim.has_hfb = s.talent.hunger_for_blood.rank > 0
        sim.has_cut_to_chase = s.talent.cut_to_the_chase.rank > 0
        sim.has_overkill = s.talent.overkill.rank > 0

        -- Energy costs
        sim.muti_cost = (s.glyph.mutilate and s.glyph.mutilate.enabled) and 55 or 60
    end,
    getPriority = function(sim, recs)
        -- target_mode: AOE rotation (Fan of Knives)
        if DH:IsCleave(sim) and sim.active_enemies >= 2 then
            if (not sim.snd_up or sim.snd_remains < 2) and sim.cp >= 1 and sim.energy >= 25 then
                return "slice_and_dice"
            end
            if sim.cp >= 4 and sim.energy >= 25 then
                return "eviscerate"
            end
            if sim.energy >= 35 then
                return "fan_of_knives"
            end
            return nil
        end

        if DH:IsMultiTarget(sim) and sim.active_enemies >= 2 then
            if sim.energy >= 35 then
                return "fan_of_knives"
            end
            return nil
        end

        -- Slice and Dice: maintain (highest priority)
        if (not sim.snd_up or sim.snd_remains < 2) and sim.cp >= 1 and sim.energy >= 25 then
            return "slice_and_dice"
        end

        -- Hunger for Blood: maintain (requires a bleed on the target, which
        -- is what unlocks its damage bonus -- not Deadly Poison)
        if sim.has_hfb and (not sim.hfb_up or sim.hfb_remains < 2) and sim.energy >= 15 and sim.rupture_up
            and DH:CanUseCooldown(sim, "hunger_for_blood", "use_hunger_for_blood") then
            return "hunger_for_blood"
        end

        -- Cold Blood right before the damage finisher so its guaranteed crit
        -- is not wasted on a maintenance finisher (Slice and Dice).
        if sim.cp >= 4 and sim.energy >= 35 and (not sim.envenom_up or sim.energy >= 85)
            and sim:ready("cold_blood")
            and DH:CanUseCooldown(sim, "cold_blood", "use_cold_blood") then
            return "cold_blood"
        end

        -- Envenom at 4-5 CP (when no envenom buff or energy pooled high)
        if sim.cp >= 4 and sim.energy >= 35 and (not sim.envenom_up or sim.energy >= 85) then
            return "envenom"
        end

        -- Rupture at 4-5 CP if not up (used in rupture-mutilate variant)
        if sim.cp >= 4 and not sim.rupture_up and sim.energy >= 25 and sim.ttd > 12 then
            return "rupture"
        end

        -- Vanish (stealth opener for extra CP)
        if sim.cp == 0 and sim:ready("vanish")
            and DH:CanUseCooldown(sim, "vanish", "use_vanish") and sim.energy >= 55 then
            return "vanish"
        end

        -- Mutilate (builder, generates 2 CP)
        if sim.has_mutilate and sim.cp <= 3 and sim.energy >= sim.muti_cost then
            return "mutilate"
        end

        return nil
    end,
    onCast = function(sim, key)
        if key == "mutilate" then
            sim.energy = sim.energy - sim.muti_cost
            sim.cp = math.min(5, sim.cp + 2)
        elseif key == "fan_of_knives" then
            sim.energy = sim.energy - 35
        elseif key == "cold_blood" then
            sim.cd["cold_blood"] = 180
        elseif key == "slice_and_dice" then
            sim.energy = sim.energy - 25
            sim.snd_up = true
            sim.snd_remains = 6 + (sim.cp * 3)  -- 6s base + 3s per CP
            sim.cp = 0
        elseif key == "envenom" then
            sim.energy = sim.energy - 35
            sim.envenom_up = true
            sim.envenom_remains = sim.cp  -- 1s per CP
            -- Cut to the Chase refreshes SnD
            if sim.has_cut_to_chase and sim.snd_up then
                sim.snd_remains = 6 + (5 * 3)  -- refreshes to max (5 CP value)
            end
            sim.cp = 0
        elseif key == "rupture" then
            sim.energy = sim.energy - 25
            sim.rupture_up = true
            sim.rupture_remains = 6 + (sim.cp * 2)
            sim.cp = 0
        elseif key == "hunger_for_blood" then
            sim.energy = sim.energy - 15
            sim.hfb_up = true
            sim.hfb_remains = 60
        elseif key == "vanish" then
            sim.cd["vanish"] = 180
        end
    end,
    getWaitTime = function(sim)
        -- Wait for energy to afford next ability
        local needed = sim.muti_cost
        if sim.cp >= 4 then needed = 35 end  -- envenom cost
        if not sim.snd_up or sim.snd_remains < 2 then needed = 25 end
        local wait = math.max(0, (needed - sim.energy) / 10)
        return math.max(wait, sim.gcd)
    end,
}

local function GetAssassinationRecommendations(addon)
    return DH:RunSimulation(state, assConfig)
end

-- ============================================================================
-- COMBAT (SINISTER STRIKE) ROTATION
-- ============================================================================

local combatConfig = {
    gcdType = "melee",
    maxRecs = 3,
    allowDupes = true,
    resources = {
        {
            field = "energy",
            max = "energy_max",
            regen = 10,
            initFrom = function(s) return s.energy.current end,
            initMaxFrom = function(s) return s.energy.max end,
        },
    },
    cds = {
        adrenaline_rush = "adrenaline_rush",
        killing_spree = "killing_spree",
        blade_flurry = "blade_flurry",
    },
    baseCDs = {
        adrenaline_rush = 180,
        killing_spree = 120,
        blade_flurry = 120,
    },
    auras = {
        { up = "snd_up", remains = "snd_remains" },
        { up = "rupture_up", remains = "rupture_remains" },
    },
    initState = function(sim, s)
        sim.cp = s.combo_points.current

        -- Buffs
        sim.snd_up = s.buff.slice_and_dice.up
        sim.snd_remains = s.buff.slice_and_dice.remains
        sim.ar_up = s.buff.adrenaline_rush.up

        -- Debuffs
        sim.rupture_up = s.debuff.rupture.up
        sim.rupture_remains = s.debuff.rupture.remains

        -- Talents
        sim.has_killing_spree = s.talent.killing_spree.rank > 0
        sim.has_ar = s.talent.adrenaline_rush.rank > 0
        sim.has_bf = s.talent.blade_flurry.rank > 0

        -- Energy cost (improved sinister strike reduces cost)
        local iss_rank = s.talent.improved_sinister_strike.rank or 0
        sim.ss_cost = 45 - (iss_rank * 3)  -- 45/42/40

        -- Glyph of Killing Spree
        sim.ks_cd = (s.glyph.killing_spree and s.glyph.killing_spree.enabled) and 75 or 120
    end,
    getPriority = function(sim, recs)
        -- target_mode: AOE rotation (Blade Flurry / Fan of Knives)
        if DH:IsCleave(sim) and sim.active_enemies >= 2 then
            if (not sim.snd_up or sim.snd_remains < 2) and sim.cp >= 1 and sim.energy >= 25 then
                return "slice_and_dice"
            end
            if sim.cp >= 4 and sim.energy >= 25 then
                return "eviscerate"
            end
            if sim.energy >= 35 then
                return "fan_of_knives"
            end
            return nil
        end

        if DH:IsMultiTarget(sim) and sim.active_enemies >= 2 then
            if sim.has_bf and DH:CanUseCooldown(sim, "blade_flurry", "use_blade_flurry") then
                return "blade_flurry"
            end
            if sim.energy >= 35 then
                return "fan_of_knives"
            end
            return nil
        end

        -- Slice and Dice: maintain (highest priority)
        if (not sim.snd_up or sim.snd_remains < 2) and sim.cp >= 1 and sim.energy >= 25 then
            return "slice_and_dice"
        end

        -- Rupture at 5 CP when SnD is healthy
        if sim.cp == 5 and not sim.rupture_up and sim.snd_up and sim.snd_remains > 4 and sim.energy >= 25 and sim.ttd > 10 then
            return "rupture"
        end

        -- Eviscerate at 4-5 CP when SnD healthy and Rupture healthy
        if sim.cp >= 4 and sim.snd_up and sim.snd_remains > 4 and sim.energy >= 35 then
            if sim.rupture_up and sim.rupture_remains > 6 then
                return "eviscerate"
            end
            -- Eviscerate if target dying soon
            if sim.ttd < 10 then
                return "eviscerate"
            end
        end

        -- Killing Spree (low energy, dump)
        if sim.has_killing_spree and sim.energy < 35
            and DH:CanUseCooldown(sim, "killing_spree", "use_killing_spree") then
            return "killing_spree"
        end

        -- Adrenaline Rush
        if sim.has_ar and sim.energy < 35
            and DH:CanUseCooldown(sim, "adrenaline_rush", "use_adrenaline_rush") then
            return "adrenaline_rush"
        end

        -- Sinister Strike (builder)
        if sim.energy >= sim.ss_cost then
            return "sinister_strike"
        end

        return nil
    end,
    onCast = function(sim, key)
        if key == "sinister_strike" then
            sim.energy = sim.energy - sim.ss_cost
            sim.cp = math.min(5, sim.cp + 1)
        elseif key == "fan_of_knives" then
            sim.energy = sim.energy - 35
        elseif key == "slice_and_dice" then
            sim.energy = sim.energy - 25
            sim.snd_up = true
            sim.snd_remains = 6 + (sim.cp * 3)
            sim.cp = 0
        elseif key == "rupture" then
            sim.energy = sim.energy - 25
            sim.rupture_up = true
            sim.rupture_remains = 6 + (sim.cp * 2)
            sim.cp = 0
        elseif key == "eviscerate" then
            sim.energy = sim.energy - 35
            sim.cp = 0
        elseif key == "killing_spree" then
            sim.cd["killing_spree"] = sim.ks_cd
        elseif key == "adrenaline_rush" then
            sim.ar_up = true
        end
    end,
    getWaitTime = function(sim)
        local needed = sim.ss_cost
        if DH:IsMultiTarget(sim) then needed = 35 end
        if sim.cp >= 4 then needed = 25 end
        if not sim.snd_up or sim.snd_remains < 2 then needed = 25 end
        local wait = math.max(0, (needed - sim.energy) / 10)
        return math.max(wait, sim.gcd)
    end,
}

local function GetCombatRecommendations(addon)
    return DH:RunSimulation(state, combatConfig)
end

-- ============================================================================
-- SUBTLETY (HEMORRHAGE/BACKSTAB) ROTATION
-- ============================================================================

local subConfig = {
    gcdType = "melee",
    maxRecs = 3,
    allowDupes = true,
    resources = {
        {
            field = "energy",
            max = "energy_max",
            regen = 10,
            initFrom = function(s) return s.energy.current end,
            initMaxFrom = function(s) return s.energy.max end,
        },
    },
    cds = {
        shadow_dance = "shadow_dance",
        shadowstep = "shadowstep",
        vanish = "vanish",
        preparation = "preparation",
    },
    baseCDs = {
        shadow_dance = 60,
        shadowstep = 30,
        vanish = 180,
        preparation = 480,
    },
    auras = {
        { up = "snd_up", remains = "snd_remains" },
        { up = "rupture_up", remains = "rupture_remains" },
    },
    initState = function(sim, s)
        sim.cp = s.combo_points.current

        -- Buffs
        sim.snd_up = s.buff.slice_and_dice.up
        sim.snd_remains = s.buff.slice_and_dice.remains
        sim.shadow_dance_up = s.buff.shadow_dance.up

        -- Debuffs
        sim.rupture_up = s.debuff.rupture.up
        sim.rupture_remains = s.debuff.rupture.remains
        sim.hemo_up = s.debuff.hemorrhage.up

        -- Talents
        sim.has_shadow_dance = s.talent.shadow_dance.rank > 0
        sim.has_hemorrhage = s.talent.hemorrhage.rank > 0
        sim.has_shadowstep = s.talent.shadowstep.rank > 0

        -- Hemo cost
        sim.hemo_cost = 35
    end,
    getPriority = function(sim, recs)
        -- target_mode: AOE rotation (Fan of Knives)
        if DH:IsCleave(sim) and sim.active_enemies >= 2 then
            if (not sim.snd_up or sim.snd_remains < 2) and sim.cp >= 1 and sim.energy >= 25 then
                return "slice_and_dice"
            end
            if sim.cp >= 4 and sim.energy >= 25 then
                return "eviscerate"
            end
            if sim.energy >= 35 then
                return "fan_of_knives"
            end
            return nil
        end

        if DH:IsMultiTarget(sim) and sim.active_enemies >= 2 then
            if sim.energy >= 35 then
                return "fan_of_knives"
            end
            return nil
        end

        -- Slice and Dice: maintain
        if (not sim.snd_up or sim.snd_remains < 2) and sim.cp >= 1 and sim.energy >= 25 then
            return "slice_and_dice"
        end

        -- Shadow Dance (major CD, enables stealth abilities)
        if sim.has_shadow_dance and sim.snd_up
            and DH:CanUseCooldown(sim, "shadow_dance", "use_shadow_dance") then
            return "shadow_dance"
        end

        -- Preparation (resets Shadowstep + Vanish CDs while SnD up)
        if sim.snd_up and sim:ready("preparation")
            and DH:CanUseCooldown(sim, "preparation", "use_preparation") then
            return "preparation"
        end

        -- During Shadow Dance: Ambush (best stealth ability)
        if sim.shadow_dance_up and sim.energy >= 60 then
            return "ambush"
        end

        -- Rupture at 5 CP
        if sim.cp == 5 and not sim.rupture_up and sim.snd_up and sim.snd_remains > 4 and sim.energy >= 25 and sim.ttd > 10 then
            return "rupture"
        end

        -- Eviscerate at 4-5 CP when SnD/Rupture healthy
        if sim.cp >= 4 and sim.snd_up and sim.snd_remains > 4 and sim.energy >= 35 then
            if (sim.rupture_up and sim.rupture_remains > 6) or sim.ttd < 10 then
                return "eviscerate"
            end
        end

        -- Hemorrhage (builder, applies debuff)
        if sim.has_hemorrhage and sim.energy >= sim.hemo_cost then
            return "hemorrhage"
        end

        -- Backstab (if no Hemorrhage talent, requires behind target)
        if not sim.has_hemorrhage and sim.energy >= 60 then
            return "backstab"
        end

        -- Shadowstep (positioning CD, low energy window)
        if sim.has_shadowstep and sim.energy < 25
            and DH:CanUseCooldown(sim, "shadowstep", "use_shadowstep") then
            return "shadowstep"
        end

        return nil
    end,
    onCast = function(sim, key)
        if key == "hemorrhage" then
            sim.energy = sim.energy - sim.hemo_cost
            sim.cp = math.min(5, sim.cp + 1)
            sim.hemo_up = true
        elseif key == "fan_of_knives" then
            sim.energy = sim.energy - 35
        elseif key == "backstab" then
            sim.energy = sim.energy - 60
            sim.cp = math.min(5, sim.cp + 1)
        elseif key == "ambush" then
            sim.energy = sim.energy - 60
            sim.cp = math.min(5, sim.cp + 2)
        elseif key == "slice_and_dice" then
            sim.energy = sim.energy - 25
            sim.snd_up = true
            sim.snd_remains = 6 + (sim.cp * 3)
            sim.cp = 0
        elseif key == "rupture" then
            sim.energy = sim.energy - 25
            sim.rupture_up = true
            sim.rupture_remains = 6 + (sim.cp * 2)
            sim.cp = 0
        elseif key == "eviscerate" then
            sim.energy = sim.energy - 35
            sim.cp = 0
        elseif key == "shadow_dance" then
            sim.shadow_dance_up = true
        elseif key == "shadowstep" then
            sim.cd["shadowstep"] = 30
        elseif key == "vanish" then
            sim.cd["vanish"] = 180
        elseif key == "preparation" then
            -- Resets Shadowstep + Vanish CDs
            sim.cd["shadowstep"] = 0
            sim.cd["vanish"] = 0
        end
    end,
    getWaitTime = function(sim)
        local needed = sim.hemo_cost
        if DH:IsMultiTarget(sim) then needed = 35 end
        if sim.cp >= 4 then needed = 25 end
        if not sim.snd_up or sim.snd_remains < 2 then needed = 25 end
        local wait = math.max(0, (needed - sim.energy) / 10)
        return math.max(wait, sim.gcd)
    end,
}

local function GetSubtletyRecommendations(addon)
    return DH:RunSimulation(state, subConfig)
end

-- ============================================================================
-- ROTATION MODES
-- ============================================================================

DH:RegisterMode("assassination", {
    name = "Assassination (DPS)",
    icon = select(3, GetSpellInfo(48666)) or "Interface\\Icons\\Ability_Rogue_ShadowStrikes",
    rotation = function(addon)
        return GetAssassinationRecommendations(addon)
    end,
})

DH:RegisterMode("combat", {
    name = "Combat (DPS)",
    icon = select(3, GetSpellInfo(48638)) or "Interface\\Icons\\Spell_Shadow_RitualOfSacrifice",
    rotation = function(addon)
        return GetCombatRecommendations(addon)
    end,
})

DH:RegisterPvPSpec({
    interrupt = { "kick" },
    control = { "kidney_shot", "blind", "sap" },
    burst = { "cold_blood", "adrenaline_rush", "blade_flurry", "killing_spree", "shadow_dance" },
    survival = { "evasion", "cloak_of_shadows", "vanish" },
    dot = { "garrote", "rupture", "hemorrhage" },
    filler = { "mutilate", "sinister_strike", "eviscerate" },
})

DH:RegisterMode("subtlety", {
    name = "Subtlety (DPS)",
    icon = select(3, GetSpellInfo(51713)) or "Interface\\Icons\\Ability_Rogue_ShadowDance",
    rotation = function(addon)
        return GetSubtletyRecommendations(addon)
    end,
})

-- v3.4.0 battle context: defensive-phase recommendation.
DH:RegisterDefensiveAbility("vanish")
