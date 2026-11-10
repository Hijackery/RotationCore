-- Simulation.lua
-- Simulation framework. Split out of RotationCore.lua.

local DH = RotationCore
if not DH then
    return
end

local ns = DH.ns

-- ============================================================================
-- SIMULATION FRAMEWORK
-- Core simulation utilities used by all class rotation modules.
-- All sim functions operate on a sim table (not real state).
-- ============================================================================

-- ---- Registered Data ----
ns.manaCosts = {} -- { [abilityKey] = costAsPctOfBaseMana }

-- ---- Registration ----

-- Register mana costs for abilities (as % of base mana, e.g. 0.05 = 5%)
function DH:RegisterManaCosts(costs)
    for key, cost in pairs(costs) do
        ns.manaCosts[key] = cost
    end
end

-- ---- GCD / Haste ----

-- Initialize GCD in a sim table from state (haste-adjusted)
-- resourceType: "melee" or "spell" (determines which haste to use)
function DH:SimInitGCD(simState, s, resourceType)
    local hasteBonus
    if resourceType == "spell" then
        hasteBonus = (s.stat.spell_haste or 1) -- Already a multiplier
    else
        hasteBonus = 1 + (s.stat.haste or 0) / 100 -- Melee haste rating %
    end
    simState.haste = hasteBonus
    simState.gcd = math.max(1.0, 1.5 / hasteBonus)
    simState.gcd_remains = s.gcd_remains or 0
end

-- Get a haste-adjusted cast time
function DH:SimCastTime(simState, baseCastTime)
    local haste = simState.haste or 1
    return baseCastTime / haste
end

-- ---- Mana ----

-- Initialize mana fields in a sim table from state
function DH:SimInitMana(simState, s)
    simState.mana = s.mana.current
    simState.mana_max = s.mana.max
    simState.mana_pct = s.mana.pct
    simState.replenishment_remains = 0
    simState.mp5 = 0
end

local function UpdateManaPct(simState)
    simState.mana_pct = simState.mana_max > 0 and (simState.mana / simState.mana_max * 100) or 0
end

-- Spend mana for an ability (by key or override %)
function DH:SimSpendMana(simState, abilityKey, overrideCost)
    local cost_pct = overrideCost or ns.manaCosts[abilityKey]
    if not cost_pct then
        return
    end
    simState.mana = math.max(0, simState.mana - simState.mana_max * cost_pct)
    UpdateManaPct(simState)
end

-- Gain flat mana
function DH:SimGainMana(simState, amount)
    simState.mana = math.min(simState.mana_max, simState.mana + amount)
    UpdateManaPct(simState)
end

-- Tick mana regen over time (Replenishment + MP5)
function DH:SimTickMana(simState, seconds)
    if simState.replenishment_remains and simState.replenishment_remains > 0 then
        simState.replenishment_remains = simState.replenishment_remains - seconds
        if simState.replenishment_remains < 0 then
            simState.replenishment_remains = 0
        end
        DH:SimGainMana(simState, simState.mana_max * 0.002 * seconds)
    end
    if simState.mp5 and simState.mp5 > 0 then
        DH:SimGainMana(simState, simState.mp5 / 5 * seconds)
    end
end

-- ---- Energy ----

-- Initialize energy fields in a sim table from state
function DH:SimInitEnergy(simState, s)
    simState.energy = s.energy.current
    simState.energy_max = s.energy.max or 100
    simState.energy_regen = 10 -- Base 10 energy/sec
end

-- Tick energy regen over time
function DH:SimTickEnergy(simState, seconds)
    simState.energy = math.min(simState.energy_max, simState.energy + simState.energy_regen * seconds)
end

-- ---- Rage ----

-- Initialize rage fields in a sim table from state
function DH:SimInitRage(simState, s)
    simState.rage = s.rage.current
    simState.rage_max = s.rage.max or 100
end

-- ---- Cooldown Tracking ----

-- Tick down a cooldown field in sim, returns new ready state
function DH:SimTickCD(simState, cdField, readyField, seconds)
    if simState[cdField] > 0 then
        simState[cdField] = simState[cdField] - seconds
        if simState[cdField] <= 0 then
            simState[readyField] = true
            simState[cdField] = 0
        end
    end
end

-- ---- Wait / Advance Time ----

-- Calculate how long to wait until the next action is available.
-- Takes a list of CD remaining values and the sim's GCD.
-- Returns the wait time (at least one GCD, so close CDs both resolve).
-- Usage: local wait = DH:SimWaitTime(sim, {sim.cs_cd, sim.judge_cd, sim.ds_cd})
function DH:SimWaitTime(simState, cdList)
    local shortest = 999
    for _, cd in ipairs(cdList) do
        if cd > 0 and cd < shortest then
            shortest = cd
        end
    end
    return shortest
end

-- ---- Target ----

-- Initialize target fields in a sim table from state
function DH:SimInitTarget(simState, s)
    simState.ttd = s.target.time_to_die
    simState.target_pct = s.target.health.pct
    simState.target_health = s.target.health.current
    simState.in_execute = s.target.health.pct < 20
    simState.target_exists = s.target.exists
    simState.active_enemies = s.active_enemies
end

-- ============================================================================
-- CORE SIMULATION RUNNER
-- Generic sim loop for all class rotations. Handles CD tracking, resource
-- management, aura duration ticking, and recommendation building.
--
-- Config:
--   gcdType       "melee" or "spell" (haste type for GCD calculation)
--   maxRecs       Number of recommendations to produce (default 3)
--   allowDupes    If true, same ability can appear in multiple recs (e.g., Wrath spam)
--   cds           { abilityKey = "stateCooldownKey", ... }
--   baseCDs       { abilityKey = seconds, ... }
--   resources     { { field="energy", max="energy_max", regen=10 }, ... }
--   auras         { { up="sr_up", remains="sr_remains" [, stacks="sr_stacks", clearStacks=true] }, ... }
--   initState     function(sim, s) - copy class-specific state from real state
--   getPriority   function(sim, recs) - return ability key (even if on CD) or nil
--   onCast        function(sim, key) - apply ability effects to sim state
--   getAdvanceTime function(sim, key) - return cast/channel time (default: sim.gcd)
-- ============================================================================

-- Internal: advance sim time by `seconds` — ticks CDs, resources, auras
local function AdvanceSimTime(DH, sim, config, seconds)
    if seconds <= 0 then
        return
    end

    -- Tick all CDs
    for k, v in pairs(sim.cd) do
        sim.cd[k] = math.max(0, v - seconds)
    end

    -- Tick resources (energy regen, etc.)
    if config.resources then
        for _, res in ipairs(config.resources) do
            if res.regen and res.regen > 0 then
                local cur = sim[res.field] or 0
                local cap = 999999
                if res.max and sim[res.max] then
                    cap = sim[res.max]
                end
                sim[res.field] = math.min(cap, cur + res.regen * seconds)
            end
        end
    end

    -- Tick aura durations
    if config.auras then
        for _, aura in ipairs(config.auras) do
            local rem = sim[aura.remains]
            if rem and rem > 0 then
                rem = rem - seconds
                if rem <= 0 then
                    sim[aura.up] = false
                    sim[aura.remains] = 0
                    if aura.stacks and aura.clearStacks then
                        sim[aura.stacks] = 0
                    end
                else
                    sim[aura.remains] = rem
                end
            end
        end
    end

    -- Tick mana
    DH:SimTickMana(sim, seconds)

    -- Class-specific tick
    if config.tickTime then
        config.tickTime(sim, seconds)
    end

    -- Unlearned abilities stay unavailable: a long time jump resets every
    -- cooldown to zero, but blocked ones must not come back.
    if sim._blocked then
        for key in pairs(sim._blocked) do
            sim.cd[key] = 9999
        end
    end
end

-- Shared sim methods. Keeping them on a metatable avoids allocating two
-- closures on every simulation call; class initState may still override them
-- with plain fields on the sim table (raw fields shadow the metatable).
local simMT = {
    ready = function(self, key)
        return (self.cd[key] or 0) <= 0
    end,
    remains = function(self, key)
        return self.cd[key] or 0
    end,
}

-- Older class modules paired with a newer core could receive a plain table
-- without the shared methods and crash on sim:ready / sim:remains. Attach
-- them before any class code runs.
local function EnsureSimMethods(sim)
    if type(sim) ~= "table" then
        return
    end
    if type(sim.ready) ~= "function" then
        sim.ready = simMT.ready
    end
    if type(sim.remains) ~= "function" then
        sim.remains = simMT.remains
    end
end

-- Ask the class rotation for the next action, skipping abilities the player
-- has not learned yet (wrong level, talents not taken, ...). The class keeps
-- returning the same unlearned action until we mark it unavailable, so block
-- it inside the sim and ask again.
local function PickKnownAction(self, sim, config, recommendations)
    EnsureSimMethods(sim)
    -- cooldown_order "burst" (part 3.3): queue every ready major cooldown
    -- (base CD >= 30s) before falling back to the normal rotation
    if self:GetSetting("cooldown_order") == "burst" and sim.baseCDs then
        for key, base in pairs(sim.baseCDs) do
            if base >= 30 and not sim._blocked[key] and self:CanUseCooldown(sim, key, "use_" .. key) then
                return key
            end
        end
    end

    local action = config.getPriority(sim, recommendations)
    for _ = 1, 30 do
        if not action then
            return nil
        end
        if sim._blocked[action] then
            return nil
        end
        if self:IsAbilityKnown(action) then
            return action
        end

        sim._blocked[action] = true
        sim.cd[action] = 9999
        action = config.getPriority(sim, recommendations)
    end
    return nil
end

function DH:RunSimulation(s, config)
    local recommendations = {}
    local maxRecs = config.maxRecs or 3
    -- The icon window can show up to 10 icons; let the simulation produce
    -- enough recommendations to fill it (never more than the slot count).
    local windowIcons = self.GetSpellFrameIconCount and self:GetSpellFrameIconCount()
        or (self.db and self.db.display and self.db.display.spellframe_icons)
    if windowIcons and windowIcons > maxRecs then
        maxRecs = math.min(windowIcons, 10)
    end
    local allowDupes = config.allowDupes or false

    if not s.target.exists or not s.target.canAttack then
        return recommendations
    end

    -- Build sim state (ready/remains come from simMT)
    local sim = setmetatable({}, simMT)
    self:SimInitGCD(sim, s, config.gcdType or "melee")
    self:SimInitMana(sim, s)
    self:SimInitTarget(sim, s)
    -- Enemy count for AOE / target_mode ("auto") decisions (part 4/5)
    sim.active_enemies = s.active_enemies or 1
    -- Build key (Improvement 2): class rotations may branch on this. Cached by
    -- State:GetBuild() so this is cheap even inside the sim loop.
    sim.build = (self.State and self.State.GetBuild) and self.State:GetBuild() or nil
    -- Expose the raid-buffs toggle so class rotations can adjust expectations
    -- (setting previously declared but unread).
    sim.raid_buffs = (self.GetSetting and self:GetSetting("raid_buffs")) ~= false
    -- v3.4.0: battle context + group buffs exposed to every class rotation.
    if self.GetBattlePhase then
        sim.battle_phase = self:GetBattlePhase()
    else
        sim.battle_phase = nil
    end
    if self.GetGroupBuffs then
        sim.group_buffs = self:GetGroupBuffs()
    end

    -- How many icons are actually useful? Stop once the estimated damage of
    -- the queued casts covers the target's HP. For AoE/cleave, use the whole
    -- pack's HP so the row stays useful instead of collapsing to one icon.
    local adaptive = (self.GetSetting and self:GetSetting("adaptive_queue")) ~= false
    local queueBudget = 0
    if adaptive then
        queueBudget = tonumber(s.target.health.current) or 0
        local targetMode = self.ResolveTargetMode and self:ResolveTargetMode(sim) or "single"
        if targetMode ~= "single" and queueBudget > 0 then
            queueBudget = queueBudget * math.max(1, sim.active_enemies or 1)
        end
    end
    local queueDamage = 0
    local queueFinished = false

    -- Initialize resources from state
    if config.resources then
        for _, res in ipairs(config.resources) do
            if res.initFrom then
                sim[res.field] = res.initFrom(s)
                if res.max and res.initMaxFrom then
                    sim[res.max] = res.initMaxFrom(s)
                end
            end
        end
    end

    -- Initialize CD tracking: sim.cd[key] = remaining seconds
    sim.cd = {}
    sim._blocked = {}
    sim._queued = {}
    -- Base cooldown durations (hold-at-end gate in CanUseCooldown)
    sim.baseCDs = config.baseCDs
    -- Expose the active mode's cooldown map so the Cooldowns display (phase 2.1)
    -- and the interrupt list can read it without touching every class module.
    ns.lastCdConfig = ns.lastCdConfig or {}
    ns.lastCdConfig.cds = config.cds
    ns.lastCdConfig.baseCDs = config.baseCDs
    if config.cds then
        for simKey, stateKey in pairs(config.cds) do
            local cd = s.cooldown[stateKey]
            sim.cd[simKey] = cd and cd.remains or 0
        end
    end

    -- Let class copy its own state (buffs, procs, auras, etc.)
    if config.initState then
        config.initState(sim, s)
    end

    -- Account for current GCD or in-progress cast (whichever is longer)
    local castRemains = s.cast_remains or 0
    local waitRemains = math.max(sim.gcd_remains, castRemains)
    if waitRemains > 0 then
        AdvanceSimTime(self, sim, config, waitRemains)
        sim.gcd_remains = 0
    end

    -- Sim loop
    local iters = 0
    while #recommendations < maxRecs and iters < 12 do
        iters = iters + 1

        local action = PickKnownAction(self, sim, config, recommendations)

        if not action then
            -- Nothing to cast right now. If class provides getWaitTime,
            -- advance time and loop back to try again (energy regen, etc.)
            if config.getWaitTime then
                local wait = config.getWaitTime(sim)
                if wait and wait > 0 then
                    AdvanceSimTime(self, sim, config, wait)
                end
            else
                break
            end
        end

        -- If we got an action (either directly or after waiting), process it
        if action then
            -- If the ability is on CD, advance time until it's ready
            local cdRemaining = sim.cd[action] or 0
            if cdRemaining > 0 then
                AdvanceSimTime(self, sim, config, cdRemaining)
            end

            -- Add to recommendations. Duplicates are never queued unless the
            -- class explicitly marks the ability as spam-able (a filler you
            -- really do press back-to-back) AND the mode allows duplicates.
            -- This stops e.g. "frostbolt > frostbolt > frostbolt".
            local ability = self.Class.abilities[action]
            local isSpam = ability and ability.spam == true
            local baseCD = config.baseCDs and config.baseCDs[action]
            -- Fill the visible queue with the real next casts. Abilities that
            -- are on a cooldown or are true executors stay distinct; a plain
            -- no-cooldown filler (Frostbolt / Shadow Bolt / Slam) may repeat.
            local repeatable = allowDupes
                and ability ~= nil
                and ability.id ~= nil
                and ability.execute ~= true
                and not (type(baseCD) == "number" and baseCD > 0)
            local dominated = false
            if (not repeatable) and ((not allowDupes) or not isSpam) then
                for _, rec in ipairs(recommendations) do
                    if rec.ability == action then
                        dominated = true
                        break
                    end
                end
            end
            if not dominated then
                if ability then
                    local execute = self.IsExecutorActive and self:IsExecutorActive(sim, action) or false
                    table.insert(recommendations, {
                        ability = action,
                        texture = ability.texture,
                        name = ability.name,
                        execute = execute or nil,
                    })
                    sim._queued[action] = true
                    if adaptive and self.EstimateAbilityDamage then
                        local damage = self:EstimateAbilityDamage(action)
                        if damage and damage > 0 then
                            queueDamage = queueDamage + damage
                        end
                    end
                end
                if adaptive and queueBudget > 0 and queueDamage >= queueBudget and #recommendations > 0 then
                    queueFinished = true
                end
            end

            if queueFinished then
                break
            end

            -- Set the ability's CD in sim
            if sim.cd[action] ~= nil and config.baseCDs and config.baseCDs[action] then
                sim.cd[action] = config.baseCDs[action]
            end

            -- Class-specific cast effects
            if config.onCast then
                config.onCast(sim, action)
            end

            -- Advance time by GCD or custom cast time
            local advanceTime = sim.gcd
            if config.getAdvanceTime then
                advanceTime = config.getAdvanceTime(sim, action)
            end
            AdvanceSimTime(self, sim, config, advanceTime)
        end
    end

    -- The rotation ran out of distinct actions before the configured icon
    -- count. Keep the window useful by repeating the last plain filler (no
    -- cooldown, not a finisher); cooldown abilities and executors stay single.
    while (not queueFinished) and #recommendations < maxRecs do
        local last = recommendations[#recommendations]
        if not last then
            break
        end
        local ability = self.Class.abilities[last.ability]
        local baseCD = config.baseCDs and config.baseCDs[last.ability]
        if not ability or not ability.id or ability.execute == true or (type(baseCD) == "number" and baseCD > 0) then
            break
        end
        table.insert(recommendations, {
            ability = last.ability,
            texture = ability.texture,
            name = ability.name,
            execute = last.execute,
        })
        if adaptive and self.EstimateAbilityDamage then
            local damage = self:EstimateAbilityDamage(last.ability)
            if damage and damage > 0 then
                queueDamage = queueDamage + damage
                if queueBudget > 0 and queueDamage >= queueBudget then
                    break
                end
            end
        end
    end

    -- Low-level fallback: registered spell damage is only valid at 80, and
    -- observed combat-log samples may not exist yet. Use the target's HP
    -- percentage so the row still shortens instead of always maxing out.
    if adaptive and queueDamage <= 0 and queueBudget > 0 then
        local targetMode = self.ResolveTargetMode and self:ResolveTargetMode(sim) or "single"
        local pct = tonumber(s.target.health.pct) or 100
        if targetMode == "single" and pct < 100 and #recommendations > 0 then
            local desired = math.max(1, math.ceil(maxRecs * pct / 100))
            while #recommendations > desired do
                table.remove(recommendations)
            end
        end
    end

    -- v3.4.0 battle context: in a defensive phase push the registered
    -- class defensive first when it is off cooldown.
    if
        sim.battle_phase == "defensive"
        and ns.defensiveKey
        and self.IsAbilityKnown
        and self:IsAbilityKnown(ns.defensiveKey)
    then
        local present = false
        for _, rec in ipairs(recommendations) do
            if rec.ability == ns.defensiveKey then
                present = true
                break
            end
        end
        if not present and sim.cd[ns.defensiveKey] ~= nil and sim.cd[ns.defensiveKey] <= 0 then
            table.insert(recommendations, 1, { ability = ns.defensiveKey })
        end
    end

    return recommendations
end
