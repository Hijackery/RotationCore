-- RotationCore_Druid/Core.lua
-- Priority rotation logic for Druid specs (3.3.5a compatible)

local DH = RotationCore
if not DH then return end

-- Only load for Druids
if select(2, UnitClass("player")) ~= "DRUID" then
    return
end

local ns = DH.ns
local class = DH.Class
local state = DH.State

-- ============================================================================
-- FERAL CAT ROTATION (WotLK 3.3.5a)
-- Based on the definitive WotLK feral guide with advanced tactics:
-- - SR/Rip desync logic (clip SR up to 10 sec early)
-- - Bearweaving (shift to bear when energy-starved)
-- - Lacerateweaving (maintain 5-stack Lacerate for max DPS)
-- ============================================================================

-- Simulated state for prediction (copy of real state values)
local sim = {}
local modeBearweave = false  -- Set by rotation mode before calling recommendations
-- Furor 5/5 grants 10 Rage on shifting into Bear and a flat +25 max Energy
-- (already reflected in energy_max). It does NOT add Energy when shifting
-- into Cat, so no cat-shift energy constant is needed.

-- Reset simulated state from real state
local function ResetSimState(s)
    -- Resources via framework
    DH:SimInitEnergy(sim, s)
    DH:SimInitRage(sim, s)
    DH:SimInitGCD(sim, s, "melee")  -- Feral uses melee haste
    DH:SimInitTarget(sim, s)

    -- CanUseCooldown / ResolveTargetMode prerequisites
    sim.active_enemies = s.active_enemies or 1
    sim.baseCDs = {
        tigers_fury = 30,
        berserk = 180,
        faerie_fire_feral = 6,
        mangle_bear = 6,
    }

    sim.cp = s.combo_points.current
    sim.berserk = s.buff.berserk.up
    sim.clearcasting = s.buff.clearcasting.up
    sim.tf_ready = s.cooldown.tigers_fury.ready
    sim.tf_cd_remains = s.cooldown.tigers_fury.remains
    sim.sr_up = s.buff.savage_roar.up
    sim.sr_remains = s.buff.savage_roar.remains
    sim.rip_up = s.debuff.rip.up
    sim.rip_remains = s.debuff.rip.remains
    sim.rake_up = s.debuff.rake.up
    sim.rake_remains = s.debuff.rake.remains
    sim.mangle_up = s.debuff.mangle.up
    sim.mangle_remains = s.debuff.mangle.remains
    sim.bleed_debuff_up = s.debuff.bleed_debuff.up  -- External Mangle/Trauma
    sim.has_mangle_talent = s.talent.mangle.rank > 0
    sim.has_berserk_talent = s.talent.berserk.rank > 0
    sim.has_ooc_talent = s.talent.omen_of_clarity.rank > 0
    sim.has_ooc_glyph = s.glyph.omen_of_clarity and s.glyph.omen_of_clarity.enabled
    sim.has_furor = s.talent.furor.rank >= 5
    sim.berserk_ready = s.cooldown.berserk.ready and not DH:IsSnoozed("berserk")
    sim.berserk_remains = s.buff.berserk.remains or 0
    sim.ff_ready = s.cooldown.faerie_fire_feral.ready
    sim.ff_cd_remains = s.cooldown.faerie_fire_feral.remains

    -- Bear form state
    sim.in_bear = s.bear_form
    sim.in_cat = s.cat_form
    sim.mangle_bear_ready = s.cooldown.mangle_bear.ready
    sim.mangle_bear_cd_remains = s.cooldown.mangle_bear.remains
    sim.lacerate_up = s.debuff.lacerate.up
    sim.lacerate_stacks = s.debuff.lacerate.stacks or 0
    sim.lacerate_remains = s.debuff.lacerate.remains

    -- CD helpers (used by DH:CanUseCooldown)
    sim.cd = {}
    sim.cd.tigers_fury = s.cooldown.tigers_fury.remains
    sim.cd.berserk = s.cooldown.berserk.remains
    sim.cd.faerie_fire_feral = s.cooldown.faerie_fire_feral.remains
    sim.cd.mangle_bear = s.cooldown.mangle_bear.remains
    sim.ready = function(self, key)
        return (self.cd[key] or 0) <= 0
    end
    sim.remains = function(self, key)
        return self.cd[key] or 0
    end
end

-- ============================================================================
-- SR/RIP DESYNC LOGIC
-- If Rip will expire shortly after SR, clip SR early to build 5 CP for Rip
-- ============================================================================

local function ShouldClipSRForDesync()
    if not sim.sr_up or not sim.rip_up then
        return false
    end

    local time_to_build_5cp = 5.0
    local conflict_window = sim.sr_remains + time_to_build_5cp + 2

    if sim.rip_remains < conflict_window and sim.rip_remains > sim.sr_remains then
        if sim.sr_remains <= 10 then
            return true
        end
    end

    return false
end

-- ============================================================================
-- BEARWEAVING LOGIC
-- Shift to bear when energy-starved to deal damage while regenerating
-- ============================================================================

local function ShouldBearweave()
    if not sim.has_furor then
        return false
    end

    if sim.energy >= 40 then
        return false
    end

    if sim.clearcasting then
        return false
    end

    if sim.rip_up and sim.rip_remains < 4.5 then
        return false
    end

    if sim.berserk then
        return false
    end

    if sim.sr_up and sim.sr_remains < 4 then
        return false
    end

    return true
end

local function ShouldExitBear()
    if sim.energy > 70 then
        return true
    end

    if sim.rip_up and sim.rip_remains < 3 then
        return true
    end

    if sim.clearcasting then
        return true
    end

    if sim.sr_up and sim.sr_remains < 3 then
        return true
    end

    return false
end

-- Get next bear ability (Lacerateweave - maintains 5-stack Lacerate)
local function GetNextBearAbility()
    local has_rage = sim.rage >= 13 or sim.clearcasting
    local lacerate_emergency = sim.lacerate_up and sim.lacerate_remains < 3
    local lacerate_needs_stack = not sim.lacerate_up or sim.lacerate_stacks < 5
    local lacerate_needs_refresh = sim.lacerate_up and sim.lacerate_remains < 9

    -- Priority 1: Emergency Lacerate refresh
    if has_rage and lacerate_emergency then
        return "lacerate"
    end

    -- Priority 2: Exit if > 70 energy or Rip < 3 sec
    if sim.energy > 70 or (sim.rip_up and sim.rip_remains < 3) then
        return "cat_form"
    end

    -- Priority 3: Build Lacerate stacks to 5
    if has_rage and lacerate_needs_stack then
        return "lacerate"
    end

    -- Priority 4: Refresh Lacerate if < 9 sec
    if has_rage and lacerate_needs_refresh then
        return "lacerate"
    end

    -- Priority 5: Lacerate is healthy (5 stacks, 9+ sec) - exit to cat
    if sim.lacerate_up and sim.lacerate_stacks == 5 and sim.lacerate_remains >= 9 then
        return "cat_form"
    end

    -- Priority 7: Low rage - exit to cat
    if sim.rage < 13 then
        return "cat_form"
    end

    -- Priority 8: Still have rage, keep stacking/refreshing Lacerate
    return "lacerate"
end

local function GetNextBearweaveAbility()
    return GetNextBearAbility()
end

-- ============================================================================
-- CAT ROTATION
-- ============================================================================

local function GetNextCatAbility()
    -- target_mode AOE: Swipe (Cat) when enough enemies, keep SR up
    if DH:IsMultiTarget(sim) then
        if (not sim.sr_up or sim.sr_remains < 3) and sim.cp >= 1 and sim.energy >= 25 then
            return "savage_roar"
        end
        local swipe_cost = sim.berserk and 25 or 50
        if sim.energy >= swipe_cost then
            return "swipe_cat"
        end
    end

    local shred_cost = sim.berserk and 21 or 42
    local mangle_cost = sim.berserk and 17 or 35
    local rake_cost = sim.berserk and 17 or 35
    local rip_cost = sim.berserk and 15 or 30
    local sr_cost = sim.berserk and 12 or 25

    local rake_needs_refresh = not sim.rake_up or sim.rake_remains < 3
    local rip_needs_refresh = not sim.rip_up or sim.rip_remains < 2
    local sr_needs_refresh = not sim.sr_up or sim.sr_remains < 3
    local mangle_needs_refresh = not sim.bleed_debuff_up and (not sim.mangle_up or sim.mangle_remains < 3)

    local sr_desync_clip = ShouldClipSRForDesync()

    local bite_cost = sim.berserk and 17 or 35
    local min_bite_rip_remains = 10
    local min_bite_sr_remains = 8

    local bite_at_end = sim.cp == 5 and (sim.ttd < 10 or (sim.rip_up and sim.ttd - sim.rip_remains < 10))

    local bite_before_rip = sim.cp == 5 and sim.rip_up and sim.sr_up
        and sim.rip_remains >= min_bite_rip_remains
        and sim.sr_remains >= min_bite_sr_remains

    local can_bite = (bite_at_end or bite_before_rip)
        and not sim.clearcasting
        and not sim.berserk
        and sim.energy >= bite_cost
        and sim.energy < 67

    -- Priority 1: Tiger's Fury when < 40 Energy
    if sim.energy < 40 and DH:CanUseCooldown(sim, "tigers_fury", "use_tigers_fury") and not sim.berserk then
        return "tigers_fury"
    end

    -- Priority 2: Berserk when TF on CD for 15+ sec
    if sim.has_berserk_talent
        and DH:CanUseCooldown(sim, "berserk", "use_berserk")
        and not sim.tf_ready and sim.tf_cd_remains >= 15 then
        return "berserk"
    end

    -- Priority 3: Savage Roar
    if (sr_needs_refresh or sr_desync_clip) and sim.cp >= 1 and sim.energy >= sr_cost then
        return "savage_roar"
    end

    -- Priority 4: Mangle when debuff needs refresh
    if sim.has_mangle_talent and mangle_needs_refresh and sim.energy >= mangle_cost then
        return "mangle_cat"
    end

    -- Priority 5: Rip at 5 CP when needs refresh
    if sim.cp == 5 and rip_needs_refresh and sim.ttd >= 10 and sim.energy >= rip_cost and not bite_at_end then
        return "rip"
    end

    -- Priority 5b: Ferocious Bite at 5 CP when safe or end of fight
    if can_bite then
        return "ferocious_bite"
    end

    -- Priority 6: Rake when needs refresh
    if rake_needs_refresh and sim.ttd > 9 and sim.energy >= rake_cost then
        return "rake"
    end

    -- Priority 7: Clearcasting proc -> Shred
    if sim.clearcasting then
        return "shred"
    end

    -- Priority 8: Faerie Fire (Feral) for OoC procs
    if sim.ff_ready and not sim.berserk and sim.energy < 90 then
        return "faerie_fire_feral"
    end

    -- Priority 9: Shred
    if sim.energy >= shred_cost then
        return "shred"
    end

    -- Priority 10: Bearweave if conditions met
    if modeBearweave and ShouldBearweave() then
        return "dire_bear_form"
    end

    -- Not enough energy - wait
    return nil
end

-- ============================================================================
-- SIMULATION
-- ============================================================================

local function SimulateTime(seconds)
    if seconds <= 0 then return end

    -- Energy regen via framework
    DH:SimTickEnergy(sim, seconds)

    if sim.sr_remains > 0 then
        sim.sr_remains = sim.sr_remains - seconds
        if sim.sr_remains <= 0 then
            sim.sr_up = false
            sim.sr_remains = 0
        end
    end

    if sim.rip_remains > 0 then
        sim.rip_remains = sim.rip_remains - seconds
        if sim.rip_remains <= 0 then
            sim.rip_up = false
            sim.rip_remains = 0
        end
    end

    if sim.rake_remains > 0 then
        sim.rake_remains = sim.rake_remains - seconds
        if sim.rake_remains <= 0 then
            sim.rake_up = false
            sim.rake_remains = 0
        end
    end

    if sim.mangle_remains > 0 then
        sim.mangle_remains = sim.mangle_remains - seconds
        if sim.mangle_remains <= 0 then
            sim.mangle_up = false
            sim.mangle_remains = 0
        end
    end

    -- Cooldown tick-downs via framework
    DH:SimTickCD(sim, "tf_cd_remains", "tf_ready", seconds)
    DH:SimTickCD(sim, "ff_cd_remains", "ff_ready", seconds)
    DH:SimTickCD(sim, "mangle_bear_cd_remains", "mangle_bear_ready", seconds)

    -- Mirror CD ticks onto sim.cd for the ready/remains helpers
    if sim.cd then
        for key, remains in pairs(sim.cd) do
            sim.cd[key] = math.max(0, remains - seconds)
        end
        if not sim.berserk_ready then
            sim.cd.berserk = sim.cd.berserk or 0
        end
    end

    if sim.lacerate_remains > 0 then
        sim.lacerate_remains = sim.lacerate_remains - seconds
        if sim.lacerate_remains <= 0 then
            sim.lacerate_up = false
            sim.lacerate_stacks = 0
            sim.lacerate_remains = 0
        end
    end

    if sim.gcd_remains > 0 then
        sim.gcd_remains = sim.gcd_remains - seconds
        if sim.gcd_remains < 0 then sim.gcd_remains = 0 end
    end

    if sim.berserk and sim.berserk_remains then
        sim.berserk_remains = sim.berserk_remains - seconds
        if sim.berserk_remains <= 0 then
            sim.berserk = false
            sim.berserk_remains = 0
        end
    end
end

local function SimulateAbility(action)
    local shred_cost = sim.berserk and 21 or 42
    local mangle_cost = sim.berserk and 17 or 35
    local rake_cost = sim.berserk and 17 or 35
    local rip_cost = sim.berserk and 15 or 30
    local sr_cost = sim.berserk and 12 or 25

    if action == "tigers_fury" then
        sim.energy = math.min(sim.energy_max, sim.energy + 60)
        sim.tf_ready = false
        sim.tf_cd_remains = 30
        sim.cd.tigers_fury = 30

    elseif action == "berserk" then
        sim.berserk = true
        sim.berserk_ready = false
        sim.cd.berserk = 180

    elseif action == "savage_roar" then
        sim.energy = sim.energy - sr_cost
        sim.sr_up = true
        sim.sr_remains = 14 + (sim.cp * 5)
        sim.cp = 0

    elseif action == "mangle_cat" then
        sim.energy = sim.energy - mangle_cost
        sim.mangle_up = true
        sim.mangle_remains = 60
        sim.cp = math.min(5, sim.cp + 1)
        if sim.clearcasting then sim.clearcasting = false end

    elseif action == "shred" then
        if not sim.clearcasting then
            sim.energy = sim.energy - shred_cost
        end
        sim.cp = math.min(5, sim.cp + 1)
        sim.clearcasting = false

    elseif action == "rake" then
        sim.energy = sim.energy - rake_cost
        sim.rake_up = true
        sim.rake_remains = 9
        sim.cp = math.min(5, sim.cp + 1)
        if sim.clearcasting then sim.clearcasting = false end

    elseif action == "rip" then
        sim.energy = sim.energy - rip_cost
        sim.rip_up = true
        sim.rip_remains = 12 + (sim.cp * 2)
        sim.cp = 0

    elseif action == "faerie_fire_feral" then
        sim.ff_ready = false
        sim.ff_cd_remains = 6

    elseif action == "ferocious_bite" then
        local bite_cost = sim.berserk and 17 or 35
        local extra_energy = math.min(30, sim.energy - bite_cost)
        sim.energy = sim.energy - bite_cost - extra_energy
        sim.cp = 0
        if sim.clearcasting then sim.clearcasting = false end

    elseif action == "swipe_cat" then
        local swipe_cost = sim.berserk and 25 or 50
        if not sim.clearcasting then
            sim.energy = sim.energy - swipe_cost
        end
        sim.clearcasting = false

    -- Form shifts
    elseif action == "dire_bear_form" then
        sim.in_bear = true
        sim.in_cat = false
        if sim.has_furor then
            sim.rage = 10
        end

    elseif action == "cat_form" then
        sim.in_cat = true
        sim.in_bear = false
        -- Furor does not grant Energy on shifting into Cat (flat max Energy
        -- is already part of energy_max); only the Bear-shift Rage above.

    -- Bear abilities
    elseif action == "mangle_bear" then
        sim.rage = sim.rage - 15
        sim.mangle_up = true
        sim.mangle_remains = 60
        sim.mangle_bear_ready = false
        sim.mangle_bear_cd_remains = 6
        if sim.clearcasting then sim.clearcasting = false end

    elseif action == "lacerate" then
        if not sim.clearcasting then
            sim.rage = sim.rage - 13
        end
        sim.lacerate_up = true
        sim.lacerate_stacks = math.min(5, sim.lacerate_stacks + 1)
        sim.lacerate_remains = 15
        sim.clearcasting = false

    elseif action == "maul" then
        sim.rage = sim.rage - 15
        if sim.clearcasting then sim.clearcasting = false end
    end

    -- Advance by one GCD (haste-adjusted via framework)
    SimulateTime(sim.gcd)
end

-- ============================================================================
-- FERAL CAT RECOMMENDATIONS
-- ============================================================================

local function GetFeralCatRecommendations(addon)
    local recommendations = {}
    local s = state

    if not s.target.exists or not s.target.canAttack then
        return recommendations
    end

    local function addRec(key)
        local ability = class.abilities[key]
        if ability then
            table.insert(recommendations, {
                ability = key,
                texture = ability.texture,
                name = ability.name,
            })
        end
        return #recommendations >= 3
    end

    ResetSimState(s)

    if sim.gcd_remains > 0 then
        SimulateTime(sim.gcd_remains)
    end

    for i = 1, 3 do
        local action

        if sim.in_bear then
            action = GetNextBearweaveAbility()
        else
            action = GetNextCatAbility()
        end

        if action then
            addRec(action)
            SimulateAbility(action)
        else
            if sim.in_bear then
                -- Wait at least one GCD in bear
                SimulateTime(sim.gcd)
            else
                local rake_cost = sim.berserk and 17 or 35
                local mangle_cost = sim.berserk and 17 or 35
                local sr_cost = sim.berserk and 12 or 25
                local rip_cost = sim.berserk and 15 or 30
                local shred_cost = sim.berserk and 21 or 42

                local needed_energy = shred_cost
                local rake_needs_refresh = not sim.rake_up or sim.rake_remains < 3
                local mangle_needs_refresh = not sim.bleed_debuff_up and (not sim.mangle_up or sim.mangle_remains < 3)
                local sr_needs_refresh = not sim.sr_up or sim.sr_remains < 3
                local rip_needs_refresh = not sim.rip_up or sim.rip_remains < 2

                if sr_needs_refresh and sim.cp >= 1 then needed_energy = math.min(needed_energy, sr_cost) end
                if mangle_needs_refresh and sim.has_mangle_talent then needed_energy = math.min(needed_energy, mangle_cost) end
                if rake_needs_refresh then needed_energy = math.min(needed_energy, rake_cost) end
                if rip_needs_refresh and sim.cp == 5 then needed_energy = math.min(needed_energy, rip_cost) end

                local time_to_energy = math.max(0, (needed_energy - sim.energy) / sim.energy_regen)
                -- Wait at least one GCD
                SimulateTime(math.max(time_to_energy + 0.1, sim.gcd))

                action = GetNextCatAbility()
                if action then
                    addRec(action)
                    SimulateAbility(action)
                else
                    SimulateTime(sim.gcd)
                end
            end
        end
    end

    return recommendations
end

-- ============================================================================
-- FERAL BEAR ROTATION
-- ============================================================================

local function GetFeralBearRecommendations(addon)
    local recommendations = {}
    local s = state
    local settings = addon.db.feral_bear

    if not s.target.exists or not s.target.canAttack then
        return recommendations
    end

    local rage = s.rage.current
    local lacerate_up = s.debuff.lacerate.up
    local lacerate_stack = s.debuff.lacerate.stacks or 0
    local lacerate_remains = s.debuff.lacerate.remains
    local mangle_ready = s.cooldown.mangle_bear.ready
    local ttd = s.target.time_to_die

    local function addRec(key)
        local ability = class.abilities[key]
        if ability then
            table.insert(recommendations, {
                ability = key,
                texture = ability.texture,
                name = ability.name,
            })
        end
    end

    -- target_mode AOE: swipe spam, keep Lacerate stacks for threat
    if DH:IsMultiTarget({ active_enemies = s.active_enemies or 1, ttd = ttd }) then
        if not lacerate_up or lacerate_stack < 5 or lacerate_remains < 3 then
            addRec("lacerate")
            if #recommendations >= 4 then return recommendations end
        elseif rage >= 20 then
            addRec("swipe_bear")
            if #recommendations >= 4 then return recommendations end
        end
        if mangle_ready then
            addRec("mangle_bear")
        end
        return recommendations
    end

    -- 1. Faerie Fire for OoC procs
    if s.glyph.omen_of_clarity and s.glyph.omen_of_clarity.enabled and not s.buff.clearcasting.up and s.cooldown.faerie_fire_feral.ready then
        addRec("faerie_fire_feral")
        if #recommendations >= 4 then return recommendations end
    end

    -- 2. Berserk
    if settings.use_berserk and s.talent.berserk.rank > 0 and s.cooldown.berserk.ready and not DH:IsSnoozed("berserk") then
        addRec("berserk")
        if #recommendations >= 4 then return recommendations end
    end

    -- 2b. Survival Instincts when low (tank CD)
    if settings.use_survival_instincts and s.cooldown.survival_instincts.ready and not DH:IsSnoozed("survival_instincts")
        and (s.target.health and s.target.health.pct or (s.health and s.health.pct) or 100) < 35 then
        addRec("survival_instincts")
        if #recommendations >= 4 then return recommendations end
    end

    -- 2c. Barkskin on damage intake (tank CD)
    if settings.use_barkskin and s.cooldown.barkskin.ready and not DH:IsSnoozed("barkskin")
        and (s.target.health and s.target.health.pct or (s.health and s.health.pct) or 100) < 60 then
        addRec("barkskin")
        if #recommendations >= 4 then return recommendations end
    end

    -- 3. Emergency Lacerate
    if lacerate_up and lacerate_remains < 4.5 then
        addRec("lacerate")
        if #recommendations >= 4 then return recommendations end
    end

    -- 4. Mangle
    if s.talent.mangle.rank > 0 and mangle_ready then
        addRec("mangle_bear")
        if #recommendations >= 4 then return recommendations end
    end

    -- 5. Faerie Fire for debuff
    if s.cooldown.faerie_fire_feral.ready and not s.debuff.faerie_fire_feral.up then
        addRec("faerie_fire_feral")
        if #recommendations >= 4 then return recommendations end
    end

    -- 6. Build Lacerate stacks
    if not lacerate_up or lacerate_stack < 5 or lacerate_remains < 8 then
        addRec("lacerate")
        if #recommendations >= 4 then return recommendations end
    end

    -- 7. Swipe as rage dump / filler
    if rage > 30 then
        addRec("swipe_bear")
        if #recommendations >= 4 then return recommendations end
    end

    -- Filler
    if #recommendations < 4 then
        addRec("lacerate")
    end

    return recommendations
end

-- ============================================================================
-- BALANCE (MOONKIN) ROTATION
-- ============================================================================

-- ============================================================================
-- BALANCE SIMULATION
-- Same approach as cat: copy state, get next ability, simulate, repeat for 3
-- ============================================================================

local bsim = {}  -- Balance simulated state

-- Reset balance sim from real state
local function ResetBalanceSim(s)
    local now = s.now

    -- GCD + haste via framework (spell haste for Balance)
    DH:SimInitGCD(bsim, s, "spell")
    DH:SimInitTarget(bsim, s)

    -- CanUseCooldown / ResolveTargetMode prerequisites
    bsim.active_enemies = s.active_enemies or 1
    bsim.baseCDs = {
        force_of_nature = 180,
        starfall = 90,
    }
    bsim.cd = {
        force_of_nature = s.cooldown.force_of_nature.remains,
        starfall = s.cooldown.starfall.remains,
    }
    bsim.ready = function(self, key)
        return (self.cd[key] or 0) <= 0
    end
    bsim.remains = function(self, key)
        return self.cd[key] or 0
    end

    -- Haste-adjusted cast times
    bsim.wrath_cast = DH:SimCastTime(bsim, 1.5)     -- 1.5s base with 5/5 Starlight Wrath
    bsim.starfire_cast = DH:SimCastTime(bsim, 3.0)   -- 3.0s base with talents

    -- DoT durations (haste adds ticks in WotLK but doesn't change duration)
    bsim.moonfire_duration = s.talent.natures_splendor and s.talent.natures_splendor.rank > 0 and 15 or 12
    bsim.is_duration = s.talent.natures_splendor and s.talent.natures_splendor.rank > 0 and 14 or 12

    -- Eclipse state
    bsim.lunar_up = s.buff.eclipse_lunar.up
    bsim.lunar_remains = s.buff.eclipse_lunar.remains
    bsim.solar_up = s.buff.eclipse_solar.up
    bsim.solar_remains = s.buff.eclipse_solar.remains

    -- ICD tracking
    bsim.lunar_icd_ready = s.buff.eclipse_lunar.last_applied == 0
        or (now - s.buff.eclipse_lunar.last_applied) >= 30
    bsim.lunar_icd_remains = 0
    if not bsim.lunar_icd_ready and s.buff.eclipse_lunar.last_applied > 0 then
        bsim.lunar_icd_remains = 30 - (now - s.buff.eclipse_lunar.last_applied)
    end

    -- DoT tracking
    bsim.moonfire_remains = s.debuff.moonfire.remains
    bsim.is_remains = s.debuff.insect_swarm.remains
    bsim.ff_up = s.debuff.faerie_fire.up

    -- Cooldowns
    bsim.fon_ready = s.cooldown.force_of_nature.ready and not DH:IsSnoozed("force_of_nature")
    bsim.fon_cd = s.cooldown.force_of_nature.remains
    bsim.starfall_ready = s.cooldown.starfall.ready and not DH:IsSnoozed("starfall")
    bsim.starfall_cd = s.cooldown.starfall.remains

    -- Talents
    bsim.has_fon = s.talent.force_of_nature.rank > 0
    bsim.has_starfall = s.talent.starfall.rank > 0
    bsim.has_is = s.talent.insect_swarm.rank > 0
    bsim.has_imp_ff = s.talent.improved_faerie_fire.rank > 0
end

-- Simulate time passing for balance
local function SimulateBalanceTime(seconds)
    if seconds <= 0 then return end

    -- Tick down Eclipse buffs
    if bsim.lunar_remains > 0 then
        bsim.lunar_remains = bsim.lunar_remains - seconds
        if bsim.lunar_remains <= 0 then
            bsim.lunar_up = false
            bsim.lunar_remains = 0
            -- Lunar Eclipse just ended — ICD is now active (30s from when it proc'd)
            -- Since it just fell off, most of the ICD has already elapsed
            -- but we can't proc it again immediately
            bsim.lunar_icd_ready = false
            bsim.lunar_icd_remains = 15  -- ~15s left on ICD after 15s Eclipse
        end
    end
    if bsim.solar_remains > 0 then
        bsim.solar_remains = bsim.solar_remains - seconds
        if bsim.solar_remains <= 0 then
            bsim.solar_up = false
            bsim.solar_remains = 0
        end
    end

    -- Tick down ICD
    if bsim.lunar_icd_remains > 0 then
        bsim.lunar_icd_remains = bsim.lunar_icd_remains - seconds
        if bsim.lunar_icd_remains <= 0 then
            bsim.lunar_icd_ready = true
            bsim.lunar_icd_remains = 0
        end
    end

    -- Tick down DoTs
    if bsim.moonfire_remains > 0 then
        bsim.moonfire_remains = bsim.moonfire_remains - seconds
        if bsim.moonfire_remains < 0 then bsim.moonfire_remains = 0 end
    end
    if bsim.is_remains > 0 then
        bsim.is_remains = bsim.is_remains - seconds
        if bsim.is_remains < 0 then bsim.is_remains = 0 end
    end

    -- Tick down cooldowns via framework
    DH:SimTickCD(bsim, "fon_cd", "fon_ready", seconds)
    DH:SimTickCD(bsim, "starfall_cd", "starfall_ready", seconds)

    -- Mirror CD ticks onto bsim.cd for ready/remains helpers
    if bsim.cd then
        for key, remains in pairs(bsim.cd) do
            bsim.cd[key] = math.max(0, remains - seconds)
        end
    end

    -- Tick down GCD
    if bsim.gcd_remains > 0 then
        bsim.gcd_remains = bsim.gcd_remains - seconds
        if bsim.gcd_remains < 0 then bsim.gcd_remains = 0 end
    end
end

-- Simulate casting a balance ability
local function SimulateBalanceAbility(action)
    if action == "moonfire" then
        bsim.moonfire_remains = bsim.moonfire_duration
        SimulateBalanceTime(bsim.gcd)

    elseif action == "insect_swarm" then
        bsim.is_remains = bsim.is_duration
        SimulateBalanceTime(bsim.gcd)

    elseif action == "starfire" then
        SimulateBalanceTime(bsim.starfire_cast)

    elseif action == "wrath" then
        SimulateBalanceTime(bsim.wrath_cast)

    elseif action == "force_of_nature" then
        bsim.fon_ready = false
        bsim.fon_cd = 180
        bsim.cd.force_of_nature = 180
        SimulateBalanceTime(bsim.gcd)

    elseif action == "starfall" then
        bsim.starfall_ready = false
        bsim.starfall_cd = 90
        bsim.cd.starfall = 90
        SimulateBalanceTime(bsim.gcd)

    elseif action == "faerie_fire" then
        bsim.ff_up = true
        SimulateBalanceTime(bsim.gcd)

    elseif action == "hurricane" then
        -- Channeled filler for AOE
        SimulateBalanceTime(bsim.gcd)
    end
end

-- Get the next balance ability based on simulated state
local function GetNextBalanceAbility()
    -- target_mode AOE: Hurricane with DoTs/Starfall upkeep
    if DH:IsMultiTarget(bsim) then
        if bsim.has_starfall and DH:CanUseCooldown(bsim, "starfall", "use_starfall") then
            return "starfall"
        end
        return "hurricane"
    end

    local eclipseActive = bsim.lunar_up or bsim.solar_up

    -- Determine spam spell based on eclipse / ICD state
    local spamSpell
    if bsim.lunar_up then
        spamSpell = "starfire"
    elseif bsim.solar_up then
        spamSpell = "wrath"
    elseif not bsim.lunar_icd_ready then
        spamSpell = "starfire"   -- Fish for Solar
    else
        spamSpell = "wrath"      -- Fish for Lunar
    end

    -- During Eclipse: only interrupt for Moonfire refresh
    -- Use small buffer so it shows the GCD before it actually expires
    if eclipseActive then
        if bsim.moonfire_remains < 1 and bsim.ttd > 6 then
            return "moonfire"
        end
        return spamSpell
    end

    -- Outside Eclipse priority:

    -- 1. Force of Nature
    if bsim.has_fon and DH:CanUseCooldown(bsim, "force_of_nature", "use_force_of_nature") and bsim.ttd > 20 then
        return "force_of_nature"
    end

    -- 2. Starfall
    if bsim.has_starfall and DH:CanUseCooldown(bsim, "starfall", "use_starfall") then
        return "starfall"
    end

    -- 3. Faerie Fire
    if bsim.has_imp_ff and not bsim.ff_up then
        return "faerie_fire"
    end

    -- 4. Moonfire (reapply when about to fall off — 1s buffer for anticipation)
    if bsim.moonfire_remains < 1 and bsim.ttd > 6 then
        return "moonfire"
    end

    -- 5. Insect Swarm (reapply when about to fall off)
    if bsim.has_is and bsim.is_remains < 1 and bsim.ttd > 6 then
        return "insect_swarm"
    end

    -- 6. Primary nuke (fishing)
    return spamSpell
end

-- Main balance recommendation function with simulation
local function GetBalanceRecommendations(addon)
    local recommendations = {}
    local s = state

    if not s.target.exists or not s.target.canAttack then
        return recommendations
    end

    local function addRec(key)
        local ability = class.abilities[key]
        if ability then
            table.insert(recommendations, {
                ability = key,
                texture = ability.texture,
                name = ability.name,
            })
        end
        return #recommendations >= 3
    end

    -- Initialize sim from real state
    ResetBalanceSim(s)

    -- Account for current GCD
    if bsim.gcd_remains > 0 then
        SimulateBalanceTime(bsim.gcd_remains)
    end

    -- Simulate 3 GCDs ahead
    for i = 1, 3 do
        local action = GetNextBalanceAbility()
        if action then
            addRec(action)
            SimulateBalanceAbility(action)
        end
    end

    return recommendations
end

-- ============================================================================
-- ROTATION MODES
-- Each mode is a self-contained rotation that handles form-awareness
-- ============================================================================

-- Cat (DPS): Pure cat rotation, shift to cat if not in cat form
local function CatModeRotation(addon)
    modeBearweave = false
    local form = GetShapeshiftForm()
    if form == 3 then
        return GetFeralCatRecommendations(addon)
    else
        local ability = class.abilities.cat_form
        return { { ability = "cat_form", texture = ability and ability.texture or select(3, GetSpellInfo(768)) } }
    end
end

-- Cat + Bearweave (DPS): Cat rotation with bearweaving, handles bear form
local function CatBearweaveModeRotation(addon)
    modeBearweave = true
    local form = GetShapeshiftForm()
    if form == 3 or form == 1 then
        return GetFeralCatRecommendations(addon)
    else
        local ability = class.abilities.cat_form
        return { { ability = "cat_form", texture = ability and ability.texture or select(3, GetSpellInfo(768)) } }
    end
end

-- Bear (Tank): Pure bear rotation, shift to bear if not in bear form
local function BearModeRotation(addon)
    local form = GetShapeshiftForm()
    if form == 1 then
        return GetFeralBearRecommendations(addon)
    else
        local ability = class.abilities.dire_bear_form
        return { { ability = "dire_bear_form", texture = ability and ability.texture or select(3, GetSpellInfo(9634)) } }
    end
end

-- Boomkin (DPS): Balance rotation, shift to moonkin if not in moonkin form
local function BoomkinModeRotation(addon)
    local form = GetShapeshiftForm()
    -- Form slot 5 is shared by Moonkin Form and Tree of Life (Restoration).
    -- Require the Moonkin Form buff so a Tree of Life druid is not driven by
    -- the Balance rotation.
    if form == 5 and state.buff.moonkin_form and state.buff.moonkin_form.up then
        return GetBalanceRecommendations(addon)
    else
        local ability = class.abilities.moonkin_form
        return { { ability = "moonkin_form", texture = ability and ability.texture or select(3, GetSpellInfo(24858)) } }
    end
end

-- Register the 4 rotation modes with icons for the dropdown
DH:RegisterMode("feral_cat", {
    name = "Cat (DPS)",
    icon = select(3, GetSpellInfo(768)) or "Interface\\Icons\\Ability_Druid_CatForm",
    rotation = CatModeRotation,
})

DH:RegisterMode("feral_cat_bearweave", {
    name = "Cat + Bearweave (DPS)",
    icon = select(3, GetSpellInfo(768)) or "Interface\\Icons\\Ability_Druid_CatForm",
    rotation = CatBearweaveModeRotation,
})

DH:RegisterMode("feral_bear", {
    name = "Bear (Tank)",
    icon = select(3, GetSpellInfo(9634)) or "Interface\\Icons\\Ability_Racial_BearForm",
    rotation = BearModeRotation,
})

DH:RegisterMode("balance", {
    name = "Boomkin (DPS)",
    icon = select(3, GetSpellInfo(24858)) or "Interface\\Icons\\Spell_Nature_ForceOfNature",
    rotation = BoomkinModeRotation,
})

-- Post-phase 4: PvP priority branch
DH:RegisterPvPSpec({
    interrupt = { "bash" },
    control = { "cyclone", "entangling_roots", "typhoon" },
    burst = { "berserk", "force_of_nature", "starfall" },
    survival = { "barkskin", "survival_instincts" },
    dot = { "rake", "rip", "moonfire", "insect_swarm" },
    filler = { "mangle_cat", "shred", "wrath", "starfire" },
})

-- Post-phase 3: dedicated Restoration DPS list (Boomkin-style) used when the
-- heal-DPS mode is enabled for a Restoration druid.
DH:RegisterMode("resto_druid_dps", {
    name = "Restoration (DPS)",
    icon = select(3, GetSpellInfo(24858)) or "Interface\\Icons\\Spell_Nature_ForceOfNature",
    rotation = BoomkinModeRotation,
})

-- Heal spec: no heal rotation implemented. A safe mode prevents a Restoration
-- druid from being driven by the Feral Cat rotation; enabling the heal-DPS
-- mode borrows resto_druid_dps instead.
DH:RegisterSafeMode("resto_druid", "Restoration (Healer)",
    select(3, GetSpellInfo(18562)) or "Interface\\Icons\\Spell_Nature_HealingTouch",
    (DH.L and DH.L["safe_mode_resto_druid"]) or "Healer rotations are not supported (Restoration Druid)")

-- v3.4.0 battle context: defensive-phase recommendation.
DH:RegisterDefensiveAbility("barkskin")
