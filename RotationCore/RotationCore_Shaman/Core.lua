-- RotationCore_Shaman/Core.lua
-- Priority rotation logic for Shaman specs (3.3.5a compatible)
-- Uses core RunSimulation for CD-aware predictions

local DH = RotationCore
if not DH then
    return
end

if select(2, UnitClass("player")) ~= "SHAMAN" then
    return
end

local ns = DH.ns
local class = DH.Class
local state = DH.State

-- ============================================================================
-- ENHANCEMENT ROTATION
-- ============================================================================

local enhancementConfig = {
    gcdType = "melee",
    maxRecs = 3,
    allowDupes = true,
    cds = {
        stormstrike = "stormstrike",
        lava_lash = "lava_lash",
        feral_spirit = "feral_spirit",
        shamanistic_rage = "shamanistic_rage",
        flame_shock = "flame_shock",
        earth_shock = "earth_shock",
        fire_nova = "fire_nova",
    },
    baseCDs = {
        stormstrike = 8,
        lava_lash = 6,
        feral_spirit = 180,
        shamanistic_rage = 60,
        flame_shock = 6, -- shared shock CD
        earth_shock = 6, -- shared shock CD
        fire_nova = 10,
    },
    auras = {
        { up = "flame_shock_up", remains = "flame_shock_remains" },
        { up = "stormstrike_up", remains = "stormstrike_remains" },
    },
    initState = function(sim, s)
        -- Maelstrom Weapon stacks
        sim.mw_stacks = s.buff.maelstrom_weapon.stacks or 0

        -- DoTs/debuffs
        sim.flame_shock_up = s.debuff.flame_shock.up
        sim.flame_shock_remains = s.debuff.flame_shock.remains
        sim.stormstrike_up = s.debuff.stormstrike.up
        sim.stormstrike_remains = s.debuff.stormstrike.remains

        -- Buffs
        sim.ls_up = s.buff.lightning_shield.up

        -- Talents
        sim.has_stormstrike = s.talent.stormstrike.rank > 0
        sim.has_lava_lash = s.talent.lava_lash.rank > 0
        sim.has_mw = s.talent.maelstrom_weapon.rank > 0
        sim.has_feral_spirit = s.talent.feral_spirit.rank > 0
        sim.has_shamanistic_rage = s.talent.shamanistic_rage.rank > 0
        sim.has_improved_stormstrike = s.talent.improved_stormstrike.rank > 0
        -- Fire Nova is a base trainable ability, not gated behind Improved
        -- Fire Nova (that talent only adds damage/stun). It also requires a
        -- Fire totem to be active, which the sim does not model.
        sim.has_fire_nova = true
    end,
    getPriority = function(sim, recs)
        -- target_mode: AOE rotation (Fire Nova)
        if DH:IsCleave(sim) then
            if sim.has_fire_nova and sim.flame_shock_up and DH:Ready(sim, "fire_nova") then
                return "fire_nova"
            end
            if
                (not sim.flame_shock_up or sim.flame_shock_remains < 2)
                and DH:Ready(sim, "flame_shock")
                and sim.ttd > 6
            then
                return "flame_shock"
            end
        end

        if DH:IsMultiTarget(sim) then
            if sim.has_fire_nova and sim.flame_shock_up and DH:Ready(sim, "fire_nova") then
                return "fire_nova"
            end
            if
                (not sim.flame_shock_up or sim.flame_shock_remains < 2)
                and DH:Ready(sim, "flame_shock")
                and sim.ttd > 6
            then
                return "flame_shock"
            end
        end

        -- Feral Spirit (major CD)
        if sim.has_feral_spirit and DH:CanUseCooldown(sim, "feral_spirit", "use_feral_spirit") then
            return "feral_spirit"
        end

        -- Shamanistic Rage (mana recovery)
        if
            sim.has_shamanistic_rage
            and sim.mana_pct < 30
            and DH:CanUseCooldown(sim, "shamanistic_rage", "use_shamanistic_rage")
        then
            return "shamanistic_rage"
        end

        -- Lightning Shield if not up
        if not sim.ls_up then
            return "lightning_shield"
        end

        -- Maelstrom Weapon 5 stacks: instant Lightning Bolt
        if sim.has_mw and sim.mw_stacks >= 5 then
            return "lightning_bolt"
        end

        -- Stormstrike on CD
        if sim.has_stormstrike and DH:Ready(sim, "stormstrike") then
            return "stormstrike"
        end

        -- Flame Shock: maintain DoT
        if (not sim.flame_shock_up or sim.flame_shock_remains < 2) and DH:Ready(sim, "flame_shock") and sim.ttd > 6 then
            return "flame_shock"
        end

        -- Earth Shock: when Flame Shock is healthy and shock CD is up
        if sim.flame_shock_up and sim.flame_shock_remains > 6 and DH:Ready(sim, "earth_shock") then
            return "earth_shock"
        end

        -- Fire Nova (if near fire totem)
        if sim.has_fire_nova and DH:Ready(sim, "fire_nova") then
            return "fire_nova"
        end

        -- Lava Lash
        if sim.has_lava_lash and DH:Ready(sim, "lava_lash") then
            return "lava_lash"
        end

        -- Nothing ready - wait
        return nil
    end,
    onCast = function(sim, key)
        if DH.SimSpendMana then
            DH:SimSpendMana(sim, key)
        end
        if key == "flame_shock" then
            sim.flame_shock_up = true
            sim.flame_shock_remains = 18
            -- Shared shock CD: put earth shock on CD too
            sim.cd["earth_shock"] = sim.cd["flame_shock"]
        elseif key == "earth_shock" then
            -- Shared shock CD: put flame shock on CD too
            sim.cd["flame_shock"] = sim.cd["earth_shock"]
        elseif key == "stormstrike" then
            sim.stormstrike_up = true
            sim.stormstrike_remains = 12
        elseif key == "lightning_bolt" then
            sim.mw_stacks = 0 -- consume MW stacks
        elseif key == "lightning_shield" then
            sim.ls_up = true
        elseif key == "shamanistic_rage" then
            sim.mana_pct = math.min(100, sim.mana_pct + 30)
        end
    end,
    getWaitTime = function(sim)
        -- Find the nearest CD
        local nearest = 999
        local keys = { "stormstrike", "lava_lash", "flame_shock", "earth_shock", "fire_nova" }
        for _, key in ipairs(keys) do
            local cd = sim.cd[key] or 0
            if cd > 0 and cd < nearest then
                nearest = cd
            end
        end
        if nearest < 999 then
            return nearest
        end
        return sim.gcd
    end,
}

local function GetEnhancementRecommendations(addon)
    return DH:RunSimulation(state, enhancementConfig)
end

-- ============================================================================
-- ELEMENTAL ROTATION
-- ============================================================================

local elementalConfig = {
    gcdType = "spell",
    maxRecs = 3,
    allowDupes = true,
    cds = {
        lava_burst = "lava_burst",
        chain_lightning = "chain_lightning",
        flame_shock = "flame_shock",
        earth_shock = "earth_shock",
        elemental_mastery = "elemental_mastery",
        natures_swiftness = "natures_swiftness",
        thunderstorm = "thunderstorm",
    },
    baseCDs = {
        lava_burst = 8,
        chain_lightning = 6,
        flame_shock = 6,
        earth_shock = 6,
        elemental_mastery = 180,
        natures_swiftness = 180,
        thunderstorm = 45,
    },
    auras = {
        { up = "flame_shock_up", remains = "flame_shock_remains" },
    },
    initState = function(sim, s)
        -- DoTs
        sim.flame_shock_up = s.debuff.flame_shock.up
        sim.flame_shock_remains = s.debuff.flame_shock.remains

        -- Buffs
        sim.clearcasting = s.buff.clearcasting.up
        sim.ls_up = s.buff.lightning_shield.up

        -- Talents
        sim.has_lava_burst = s.talent.lava_flows.rank > 0 or true -- all ele have LvB
        sim.has_em = s.talent.elemental_mastery.rank > 0
        sim.has_ns = s.talent.natures_swiftness.rank > 0
        sim.has_thunderstorm = s.talent.thunderstorm.rank > 0
        sim.has_storm_earth_fire = s.talent.storm_earth_and_fire.rank or 0
    end,
    getPriority = function(sim, recs)
        -- target_mode: AOE rotation (Chain Lightning)
        if DH:IsCleave(sim) then
            if sim.has_fire_nova and sim.flame_shock_up and DH:Ready(sim, "fire_nova") then
                return "fire_nova"
            end
            if DH:Ready(sim, "chain_lightning") then
                return "chain_lightning"
            end
        end

        if DH:IsMultiTarget(sim) then
            if DH:Ready(sim, "chain_lightning") then
                return "chain_lightning"
            end
        end

        -- Elemental Mastery (major CD)
        if
            sim.has_em
            and DH:Ready(sim, "elemental_mastery")
            and DH:CanUseCooldown(sim, "elemental_mastery", "use_elemental_mastery")
        then
            return "elemental_mastery"
        end

        -- Natures Swiftness (instant next spell, mana saver)
        if
            sim.has_ns
            and DH:Ready(sim, "natures_swiftness")
            and DH:CanUseCooldown(sim, "natures_swiftness", "use_natures_swiftness")
        then
            return "natures_swiftness"
        end

        -- Thunderstorm (mana return every 45s)
        if
            sim.has_thunderstorm
            and sim.mana_pct < 30
            and DH:Ready(sim, "thunderstorm")
            and DH:CanUseCooldown(sim, "thunderstorm", "use_thunderstorm")
            and sim.ttd > 10
        then
            return "thunderstorm"
        end

        -- Lightning Shield if not up
        if not sim.ls_up then
            return "lightning_shield"
        end

        -- Flame Shock: must be up for Lava Burst auto-crit
        if (not sim.flame_shock_up or sim.flame_shock_remains < 2) and DH:Ready(sim, "flame_shock") and sim.ttd > 6 then
            return "flame_shock"
        end

        -- Lava Burst on CD (guaranteed crit with Flame Shock up)
        if DH:Ready(sim, "lava_burst") and sim.flame_shock_up then
            return "lava_burst"
        end

        -- Chain Lightning (if off CD, good DPS filler between LvB)
        if DH:Ready(sim, "chain_lightning") then
            return "chain_lightning"
        end

        -- Filler: Lightning Bolt
        return "lightning_bolt"
    end,
    onCast = function(sim, key)
        -- Elemental Focus ("Clearcasting"): next spell is free. Consume the
        -- proc instead of spending mana, then let the spell land.
        if sim.clearcasting then
            sim.clearcasting = false
        elseif DH.SimSpendMana then
            DH:SimSpendMana(sim, key)
        end
        if key == "flame_shock" then
            sim.flame_shock_up = true
            sim.flame_shock_remains = 18
            -- Shared shock CD
            sim.cd["earth_shock"] = sim.cd["flame_shock"]
        elseif key == "earth_shock" then
            sim.cd["flame_shock"] = sim.cd["earth_shock"]
        elseif key == "elemental_mastery" then
            -- Next cast is instant + crit
        elseif key == "lightning_shield" then
            sim.ls_up = true
        end
    end,
    getAdvanceTime = function(sim, action)
        local h = sim.haste or 1
        if action == "lightning_bolt" then
            return math.max(sim.gcd, 2.5 / h)
        end
        if action == "chain_lightning" then
            return math.max(sim.gcd, 2.0 / h)
        end
        if action == "lava_burst" then
            return math.max(sim.gcd, 2.0 / h)
        end
        return sim.gcd -- instants: flame shock, earth shock, EM, LS, thunderstorm
    end,
}

local function GetElementalRecommendations(addon)
    return DH:RunSimulation(state, elementalConfig)
end

-- ============================================================================
-- ROTATION MODES
-- ============================================================================

DH:RegisterMode("enhancement", {
    name = "Enhancement (DPS)",
    icon = select(3, GetSpellInfo(17364)) or "Interface\\Icons\\Ability_Shaman_Stormstrike",
    rotation = function(addon)
        return GetEnhancementRecommendations(addon)
    end,
})

DH:RegisterMode("elemental", {
    name = "Elemental (DPS)",
    icon = select(3, GetSpellInfo(60043)) or "Interface\\Icons\\Spell_Shaman_LavaBurst",
    rotation = function(addon)
        return GetElementalRecommendations(addon)
    end,
})

-- Post-phase 4: PvP priority branch
DH:RegisterPvPSpec({
    interrupt = { "wind_shear" },
    control = { "frost_shock", "fire_nova" },
    burst = { "elemental_mastery", "natures_swiftness", "thunderstorm", "feral_spirit", "shamanistic_rage" },
    survival = { "lightning_shield", "water_shield" },
    dot = { "flame_shock" },
    filler = { "lava_burst", "lightning_bolt", "chain_lightning", "earth_shock" },
})

-- Post-phase 3: dedicated Restoration DPS list (Elemental-style) used when the
-- heal-DPS mode is enabled for a Restoration shaman.
DH:RegisterMode("resto_shaman_dps", {
    name = "Restoration (DPS)",
    icon = select(3, GetSpellInfo(60043)) or "Interface\\Icons\\Spell_Shaman_LavaBurst",
    rotation = function(addon)
        return GetElementalRecommendations(addon)
    end,
})

-- ============================================================================
-- RESTORATION HEAL ROTATION
-- Isolated from the Enhancement/Elemental rotations. It only emits heal and
-- utility recommendations.
-- ============================================================================
local function GetRestoShamanHealRecommendations(addon)
    local ctx = ns.GetHealContext()
    local recs = {}
    local function push(key, target)
        if ns.CanHeal(key, target) then
            ns.PushHeal(recs, key, target)
        end
    end

    local tank = ns.GetTankTarget(ctx)
    local low = ns.GetHealTarget(ctx, { below = 100 })
    local critical = ns.GetHealTarget(ctx, { below = 30 })
    local target = critical or low
    local injured = ns.GetInjuredCount(ctx, 80)

    -- Shield upkeep.
    if not ns.GetAbilityAura("player", "water_shield") then
        push("water_shield", "player")
    end
    if tank then
        local es = ns.GetAbilityAura(tank.unit, "earth_shield")
        if not es or (es.count or 0) < 3 then
            push("earth_shield", tank)
        end
    end

    -- Dispel before healing through avoidable damage.
    local dispelUnit, _, dispelType = ns.FindDispelTarget(ctx, { Curse = true, Disease = true, Poison = true })
    if dispelUnit then
        if dispelType == "Curse" then
            push("cleanse_spirit", dispelUnit)
        elseif dispelType == "Disease" then
            push("cure_disease", dispelUnit)
        elseif dispelType == "Poison" then
            push("cure_poison", dispelUnit)
        end
    end

    -- Emergency instant heal.
    if critical then
        if not ns.GetAbilityAura("player", "natures_swiftness") then
            push("natures_swiftness", critical)
        end
        push("healing_wave", critical)
    end

    -- Riptide on the tank and injured players.
    if tank and not ns.GetAbilityAura(tank.unit, "riptide") then
        push("riptide", tank)
    end
    if low and not ns.GetAbilityAura(low.unit, "riptide") then
        push("riptide", low)
    end

    -- Chain Heal for stacked damage, direct heals otherwise.
    if injured >= 3 then
        push("chain_heal", low or tank)
    end
    if target then
        if target.pct < 55 then
            push("lesser_healing_wave", target)
        else
            push("healing_wave", target)
        end
    end

    -- Sustained raid damage and mana recovery.
    if injured >= 2 then
        push("healing_stream_totem", "player")
    end
    if ctx.manaPct < 30 then
        push("mana_tide_totem", "player")
    end

    return recs
end

DH:RegisterHealMode(
    "resto_shaman",
    "Restoration (Healer)",
    select(3, GetSpellInfo(61295)) or "Interface\\Icons\\Spell_Nature_HealingWay",
    GetRestoShamanHealRecommendations
)
