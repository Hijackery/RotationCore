-- RotationCore_Paladin/Core.lua
-- Priority rotation logic for Paladin specs (3.3.5a compatible)
-- Uses core RunSimulation for CD-aware predictions

local DH = RotationCore
if not DH then return end

if select(2, UnitClass("player")) ~= "PALADIN" then
    return
end

local ns = DH.ns
local class = DH.Class
local state = DH.State

-- ============================================================================
-- RETRIBUTION ROTATION
-- ============================================================================

local retConfig = {
    gcdType = "melee",
    maxRecs = 3,
    cds = {
        crusader_strike = "crusader_strike",
        judgement_of_wisdom = "judgement",
        divine_storm = "divine_storm",
        consecration = "consecration",
        exorcism = "exorcism",
        hammer_of_wrath = "hammer_of_wrath",
        holy_wrath = "holy_wrath",
        avenging_wrath = "avenging_wrath",
        divine_plea = "divine_plea",
    },
    baseCDs = {
        crusader_strike = 4,
        judgement_of_wisdom = 8,
        divine_storm = 10,
        consecration = 8,
        exorcism = 15,
        hammer_of_wrath = 6,
        holy_wrath = 30,
        avenging_wrath = 120,
        divine_plea = 60,
    },
    initState = function(sim, s)
        sim.aow_up = s.buff.art_of_war.up
        sim.aw_up = s.buff.avenging_wrath.up
        sim.has_ds = s.talent.divine_storm.rank > 0
        sim.seal_up = s.buff.seal_of_vengeance.up or s.buff.seal_of_command.up
            or s.buff.seal_of_wisdom.up or s.buff.seal_of_righteousness.up
        sim.is_undead_demon = (UnitCreatureType("target") == "Undead"
            or UnitCreatureType("target") == "Demon")
    end,
    getPriority = function(sim, recs)
        -- Seal upkeep: a missing seal is a large DPS loss. Only acts when no
        -- seal is active, so it never overrides a deliberate choice.
        if not sim.seal_up then
            if DH:IsCleave(sim) or DH:IsMultiTarget(sim) then
                return "seal_of_command"
            end
            return "seal_of_vengeance"
        end

        -- Avenging Wrath
        if sim:ready("avenging_wrath") and not sim.aw_up
            and DH:CanUseCooldown(sim, "avenging_wrath", "use_avenging_wrath") then
            return "avenging_wrath"
        end

        -- Divine Plea (high priority when mana is critical)
        if sim.mana_pct < (DH:GetSetting("mana_threshold_divine_plea") or 40)
            and DH:CanUseCooldown(sim, "divine_plea", "use_divine_plea") then
            return "divine_plea"
        end

        -- target_mode: AOE rotation (Divine Storm / Consecration)
        if DH:IsCleave(sim) then
            if sim.has_ds and sim:ready("divine_storm") then
                return "divine_storm"
            end
            if sim:ready("consecration") and sim.ttd > 4 then
                return "consecration"
            end
            if sim:ready("crusader_strike") then
                return "crusader_strike"
            end
        end

        if DH:IsMultiTarget(sim) then
            if sim.has_ds and sim:ready("divine_storm") then
                return "divine_storm"
            end
            if sim:ready("consecration") and sim.ttd > 4 then
                return "consecration"
            end
        end

        -- Execute: Hammer of Wrath
        if sim.in_execute and sim:ready("hammer_of_wrath") then
            return "hammer_of_wrath"
        end

        -- Exorcism vs Undead/Demon with AoW (100% crit)
        if sim.is_undead_demon and sim.aow_up and sim:ready("exorcism")
            and DH:GetSetting("use_exorcism") then
            return "exorcism"
        end

        -- Core FCFS (wotlk sim APL order: Judge > CS > DS)
        if sim:ready("judgement_of_wisdom") then
            return "judgement_of_wisdom"
        end

        if sim:ready("crusader_strike") then
            return "crusader_strike"
        end

        if sim.has_ds and sim:ready("divine_storm") then
            return "divine_storm"
        end

        -- Consecration
        if sim:ready("consecration") and sim.ttd > 4 then
            return "consecration"
        end

        -- Exorcism vs normal targets with AoW
        if not sim.is_undead_demon and sim.aow_up and sim:ready("exorcism")
            and DH:GetSetting("use_exorcism") then
            return "exorcism"
        end

        -- Holy Wrath (undead/demons only)
        if sim.is_undead_demon and sim:ready("holy_wrath") then
            return "holy_wrath"
        end

        -- Nothing ready — return nearest FCFS ability not already recommended
        local function hasRec(key)
            for _, r in ipairs(recs) do if r.ability == key then return true end end
            return false
        end
        local nearest, nearestCD = nil, 999
        local fcfs = { "judgement_of_wisdom", "crusader_strike" }
        if sim.has_ds then table.insert(fcfs, "divine_storm") end
        table.insert(fcfs, "consecration")
        for _, key in ipairs(fcfs) do
            if not hasRec(key) then
                local cd = sim:remains(key)
                if cd < nearestCD then
                    nearest = key
                    nearestCD = cd
                end
            end
        end
        return nearest
    end,
    onCast = function(sim, key)
        if key == "avenging_wrath" then
            sim.aw_up = true
        elseif key == "exorcism" then
            sim.aow_up = false  -- Consumes AoW proc
        elseif key == "seal_of_vengeance" or key == "seal_of_command" then
            sim.seal_up = true
        end
    end,
}

local function GetRetributionRecommendations(addon)
    return DH:RunSimulation(state, retConfig)
end

-- ============================================================================
-- PROTECTION ROTATION (969 pattern)
-- ============================================================================

local protConfig = {
    gcdType = "melee",
    maxRecs = 3,
    cds = {
        shield_of_righteousness = "shield_of_righteousness",
        hammer_of_the_righteous = "hammer_of_the_righteous",
        consecration = "consecration",
        holy_shield = "holy_shield",
        judgement_of_wisdom = "judgement",
        hammer_of_wrath = "hammer_of_wrath",
        divine_plea = "divine_plea",
        avengers_shield = "avengers_shield",
    },
    baseCDs = {
        shield_of_righteousness = 6,
        hammer_of_the_righteous = 6,
        consecration = 8,
        holy_shield = 8,
        judgement_of_wisdom = 8,
        hammer_of_wrath = 6,
        divine_plea = 60,
        avengers_shield = 30,
    },
    initState = function(sim, s)
        sim.rf_up = s.buff.righteous_fury.up
        sim.has_ds = s.talent.divine_storm.rank > 0
        sim.seal_up = s.buff.seal_of_vengeance.up or s.buff.seal_of_command.up
            or s.buff.seal_of_wisdom.up or s.buff.seal_of_righteousness.up
    end,
    getPriority = function(sim, recs)
        -- Righteous Fury always first
        if not sim.rf_up then
            return "righteous_fury"
        end

        -- Seal upkeep (no seal active -> restore it).
        if not sim.seal_up then
            if DH:IsCleave(sim) or DH:IsMultiTarget(sim) then
                return "seal_of_command"
            end
            return "seal_of_vengeance"
        end

        -- Helper: is ability already recommended?
        local function hasRec(key)
            for _, r in ipairs(recs) do
                if r.ability == key then return true end
            end
            return false
        end

        local sor_cd = sim:remains("shield_of_righteousness")
        local hotr_cd = sim:remains("hammer_of_the_righteous")

        -- target_mode: AOE rotation (Hammer of the Righteous / Consecration)
        if DH:IsCleave(sim) then
            if sim.has_ds and sim:ready("divine_storm") then
                return "divine_storm"
            end
            if hotr_cd <= 0 then
                return "hammer_of_the_righteous"
            end
            if sim:ready("consecration") and sim.ttd > 4 then
                return "consecration"
            end
        end

        if DH:IsMultiTarget(sim) then
            if hotr_cd <= 0 then
                return "hammer_of_the_righteous"
            end
            if sim:ready("consecration") and sim.ttd > 4 then
                return "consecration"
            end
        end

        -- 969 APL: cast a 6s ability only when the OTHER 6s is within 3s.
        -- This naturally produces 6-9-6-9 without forcing it.
        if sor_cd <= 0 and hotr_cd <= 3 then
            return "shield_of_righteousness"
        end
        if hotr_cd <= 0 and sor_cd <= 3 then
            return "hammer_of_the_righteous"
        end

        -- Execute: Hammer of Wrath
        if sim.in_execute and sim:ready("hammer_of_wrath") then
            return "hammer_of_wrath"
        end

        -- Avengers Shield (30s CD, high ranged threat/damage)
        if sim:ready("avengers_shield")
            and DH:CanUseCooldown(sim, "avengers_shield", "use_avengers_shield") then
            return "avengers_shield"
        end

        -- If both 6s on CD but one is very close (350ms), wait for it
        -- rather than wasting a GCD on a 9s ability
        local nearest6s = math.min(sor_cd, hotr_cd)
        if nearest6s > 0 and nearest6s <= 0.35 then
            if sor_cd <= hotr_cd then
                return "shield_of_righteousness"
            else
                return "hammer_of_the_righteous"
            end
        end

        -- Divine Plea (high priority when mana is critical)
        if sim.mana_pct < (DH:GetSetting("mana_threshold_divine_plea") or 40)
            and DH:CanUseCooldown(sim, "divine_plea", "use_divine_plea") then
            return "divine_plea"
        end

        -- 9s abilities in priority order: Cons > HS > JoW
        if sim:ready("consecration") then
            return "consecration"
        end

        if sim:ready("holy_shield") and DH:CanUseCooldown(sim, "holy_shield", "use_holy_shield") then
            return "holy_shield"
        end

        if sim:ready("judgement_of_wisdom") then
            return "judgement_of_wisdom"
        end

        -- Nothing ready — return whichever ability comes off CD soonest
        local nearest, nearestCD = nil, 999
        local all = {
            "shield_of_righteousness", "hammer_of_the_righteous",
            "consecration", "holy_shield", "judgement_of_wisdom",
        }
        if sim.in_execute then table.insert(all, "hammer_of_wrath") end
        for _, key in ipairs(all) do
            if not hasRec(key) then
                local cd = sim:remains(key)
                if cd < nearestCD then
                    nearest = key
                    nearestCD = cd
                end
            end
        end
        return nearest
    end,
    onCast = function(sim, key)
        if key == "righteous_fury" then
            sim.rf_up = true
        elseif key == "seal_of_vengeance" or key == "seal_of_command" then
            sim.seal_up = true
        end
    end,
}

local function GetProtectionRecommendations(addon)
    return DH:RunSimulation(state, protConfig)
end

-- ============================================================================
-- ROTATION MODES
-- ============================================================================

DH:RegisterMode("ret", {
    name = "Retribution (DPS)",
    icon = select(3, GetSpellInfo(35395)) or "Interface\\Icons\\Ability_ThunderClap",
    rotation = function(addon)
        return GetRetributionRecommendations(addon)
    end,
})

DH:RegisterMode("prot_paladin", {
    name = "Protection (Tank)",
    icon = select(3, GetSpellInfo(48827)) or "Interface\\Icons\\Spell_Holy_AvengersShield",
    rotation = function(addon)
        return GetProtectionRecommendations(addon)
    end,
})

-- Post-phase 3: dedicated Holy Paladin DPS list (shockadin-style). Used when
-- the heal-DPS mode is enabled for a Holy Paladin.
local function GetHolyDpsRecommendations(addon)
    local s = addon.State
    local recs = {}
    local function push(key) recs[#recs + 1] = { ability = key, priority = #recs + 1 } end
    local function Ready(key)
        local a = class.abilities[key]
        return DH:SpellReady(a and a.id)
    end
    local function Build()
        -- Seal upkeep (only if the aura is registered/known)
        if s.buff.seal_of_wisdom and not s.buff.seal_of_wisdom.up
            and not (s.buff.seal_of_vengeance and s.buff.seal_of_vengeance.up) then
            push("seal_of_wisdom")
        end
        local hp = s.target and s.target.health and s.target.health.pct or 100
        if Ready("holy_shock") then push("holy_shock") end
        if Ready("exorcism") then push("exorcism") end
        if Ready("consecration") then push("consecration") end
        if Ready("judgement_of_wisdom") then push("judgement_of_wisdom") end
        if hp < 20 and Ready("hammer_of_wrath") then push("hammer_of_wrath") end
        if #recs == 0 then push("exorcism") end
    end
    Build()
    return recs
end

DH:RegisterMode("holy_paladin_dps", {
    name = "Holy (DPS)",
    icon = select(3, GetSpellInfo(48825)) or "Interface\\Icons\\Spell_Holy_SearingLight",
    rotation = function(addon)
        return GetHolyDpsRecommendations(addon)
    end,
})

-- Heal spec: no heal rotation implemented. A safe mode prevents a Holy
-- paladin from being driven by the Retribution rotation; enabling the
-- heal-DPS mode borrows holy_paladin_dps instead.
DH:RegisterSafeMode("holy_paladin", "Holy (Healer)",
    select(3, GetSpellInfo(635)) or "Interface\\Icons\\Spell_Holy_HolyBolt",
    (DH.L and DH.L["safe_mode_holy_paladin"]) or "Healer rotations are not supported (Holy Paladin)")

-- Post-phase 4: PvP priority branch
DH:RegisterPvPSpec({
    interrupt = {},
    control = { "hammer_of_justice", "repentance" },
    burst = { "avenging_wrath", "holy_wrath" },
    survival = {},
    dot = {},
    filler = { "crusader_strike", "judgement_of_wisdom", "exorcism", "consecration" },
})

-- v3.4.0 battle context: defensive-phase recommendation.
DH:RegisterDefensiveAbility("holy_shield")
