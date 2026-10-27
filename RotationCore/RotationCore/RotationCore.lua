-- RotationCore.lua
-- Rotation helper framework for WotLK 3.3.5a
-- Class modules register their data via the registration API

-- Create addon namespace
RotationCore = {}
local DH = RotationCore

DH.Version = "1.0.2"

-- Namespace for internal data
local ns = {}
DH.ns = ns

-- Localization helper: Locale.lua fills DH.L after this file loads, so look it
-- up lazily on every call (missing keys return the English source string).
local function L(s)
    local tbl = DH.L
    if tbl and type(s) == "string" then return tbl[s] end
    return s
end

ns.debug = {}
ns.inCombat = false

-- Aura tracking cache
ns.auras = {
    target = { buff = {}, debuff = {} },
    player = { buff = {}, debuff = {} }
}

-- Player class (detected at load time)
DH.playerClass = select(2, UnitClass("player"))
DH.playerRace = select(2, UnitRace("player"))

local CLASS_COLORS = {
    MAGE = { 0.25, 0.78, 0.92 }, WARLOCK = { 0.53, 0.53, 0.93 },
    PRIEST = { 1.00, 1.00, 1.00 }, ROGUE = { 1.00, 0.96, 0.41 },
    WARRIOR = { 0.78, 0.61, 0.43 }, DEATHKNIGHT = { 0.77, 0.12, 0.23 },
    SHAMAN = { 0.00, 0.44, 0.87 }, HUNTER = { 0.67, 0.83, 0.45 },
    DRUID = { 1.00, 0.49, 0.04 }, PALADIN = { 0.96, 0.55, 0.73 },
}
function DH:GetClassColor()
    local rc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[self.playerClass]
    if rc then return rc.r, rc.g, rc.b end
    local c = CLASS_COLORS[self.playerClass]
    if c then return c[1], c[2], c[3] end
    return 1, 0.82, 0
end

-- Class data structure
DH.Class = {
    file = DH.playerClass,
    resources = {},
    talents = {},
    glyphs = {},
    auras = {},
    abilities = {},
    abilityByName = {},
    meleeAbilities = {},  -- Keys of abilities that are melee range
    range = 5,
    settings = {},
}

-- State will be initialized in State.lua
DH.State = {}

-- Recommendation queue
ns.queue = {}
ns.recommendations = {}

-- ============================================================================
-- ERROR LOG (written to its own SavedVariables file: RotationCoreErrors.lua)
-- seterrorhandler catches every Lua error. The last few are kept (duplicates
-- collapsed) so the player can send the file without digging in the normal DB.
-- ============================================================================

ns.MAX_ERRORS = 200
ns.errorLog = {}

function ns.AddError(msg)
    local log = ns.errorLog
    if not log then
        log = {}
        ns.errorLog = log
    end
    msg = tostring(msg)
    local last = log[#log]
    if type(last) == "table" and last.msg == msg then
        last.count = (last.count or 1) + 1
        return
    end
    ns.lastErrorTime = GetTime()
    ns.lastErrorMsg = msg
    log[#log + 1] = { msg = msg, count = 1 }
    while #log > ns.MAX_ERRORS do
        table.remove(log, 1)
    end
end

-- Chain to the previous handler so the default red error box still appears.
do
    local prev = geterrorhandler and geterrorhandler()
    if seterrorhandler then
        seterrorhandler(function(msg)
            ns.AddError(msg)
            if prev then prev(msg) end
        end)
    end
end

-- Recommendation stability: prevent flickering by keeping recommendations
-- stable for at least one GCD. If the new recommendations differ from the
-- previous ones, only update if enough time has passed.
ns.lastRecTime = 0
ns.lastRecAbilities = {}

-- UI elements
ns.UI = {
    MainFrame = nil,
    Buttons = {}
}

-- ============================================================================
-- COOLDOWN SNOOZE SYSTEM
-- When the addon recommends a major cooldown but the player uses a different
-- ability instead, the CD recommendation is snoozed for a duration. If the
-- player manually uses the CD, the snooze clears immediately.
-- ============================================================================

ns.snooze = {}          -- { [abilityKey] = expireTime }
ns.lastRecommended = nil -- The first recommended ability key from last update

-- Check if an ability is currently snoozed
function DH:IsSnoozed(key)
    local expires = ns.snooze[key]
    if expires and GetTime() < expires then
        return true
    end
    ns.snooze[key] = nil
    return false
end

-- Snooze an ability for a duration (default 60s)
function DH:Snooze(key, duration)
    ns.snooze[key] = GetTime() + (duration or 60)
end

-- Clear snooze for an ability (player used it)
function DH:ClearSnooze(key)
    ns.snooze[key] = nil
end

-- Register an ability as snoozeable with a duration
-- When recommended but skipped, it won't be recommended again for `duration` seconds
ns.snoozeable = {}
function DH:RegisterSnoozeable(key, duration)
    ns.snoozeable[key] = duration or 60
end

-- ============================================================================
-- SIMULATION FRAMEWORK
-- Core simulation utilities used by all class rotation modules.
-- All sim functions operate on a sim table (not real state).
-- ============================================================================

-- ---- Registered Data ----
ns.manaCosts = {}       -- { [abilityKey] = costAsPctOfBaseMana }

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
        hasteBonus = (s.stat.spell_haste or 1)  -- Already a multiplier
    else
        hasteBonus = 1 + (s.stat.haste or 0) / 100  -- Melee haste rating %
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
    if not cost_pct then return end
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
        if simState.replenishment_remains < 0 then simState.replenishment_remains = 0 end
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
    simState.energy_regen = 10  -- Base 10 energy/sec
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
    if seconds <= 0 then return end

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
                if res.max and sim[res.max] then cap = sim[res.max] end
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

-- Ask the class rotation for the next action, skipping abilities the player
-- has not learned yet (wrong level, talents not taken, ...). The class keeps
-- returning the same unlearned action until we mark it unavailable, so block
-- it inside the sim and ask again.
local function PickKnownAction(self, sim, config, recommendations)
    -- cooldown_order "burst" (part 3.3): queue every ready major cooldown
    -- (base CD >= 30s) before falling back to the normal rotation
    if self:GetSetting("cooldown_order") == "burst" and sim.baseCDs then
        for key, base in pairs(sim.baseCDs) do
            if base >= 30 and not sim._blocked[key]
               and self:CanUseCooldown(sim, key, "use_" .. key) then
                return key
            end
        end
    end

    local action = config.getPriority(sim, recommendations)
    for _ = 1, 30 do
        if not action then return nil end
        if sim._blocked[action] then return nil end
        if self:IsAbilityKnown(action) then return action end

        sim._blocked[action] = true
        sim.cd[action] = 9999
        action = config.getPriority(sim, recommendations)
    end
    return nil
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

function DH:RunSimulation(s, config)
    local recommendations = {}
    local maxRecs = config.maxRecs or 3
    -- The icon window can show up to 10 icons; let the simulation produce
    -- enough recommendations to fill it (never more than the slot count).
    local windowIcons = self.db and self.db.display and self.db.display.spellframe_icons
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
    sim.build = (self.State and self.State.GetBuild)
        and self.State:GetBuild() or nil
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
            local dominated = false
            if (not allowDupes) or (not isSpam) then
                for _, rec in ipairs(recommendations) do
                    if rec.ability == action then
                        dominated = true
                        break
                    end
                end
            end
            if not dominated then
                if ability then
                    table.insert(recommendations, {
                        ability = action,
                        texture = ability.texture,
                        name = ability.name,
                    })
                end
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

    -- v3.4.0 battle context: in a defensive phase push the registered
    -- class defensive first when it is off cooldown.
    if sim.battle_phase == "defensive" and ns.defensiveKey
        and self.IsAbilityKnown and self:IsAbilityKnown(ns.defensiveKey) then
        local present = false
        for _, rec in ipairs(recommendations) do
            if rec.ability == ns.defensiveKey then
                present = true
                break
            end
        end
        if not present and sim.cd[ns.defensiveKey] ~= nil
            and sim.cd[ns.defensiveKey] <= 0 then
            table.insert(recommendations, 1, { ability = ns.defensiveKey })
        end
    end

    return recommendations
end

-- ============================================================================
-- REGISTRATION API
-- Class modules use these to register their data into the framework.
-- ============================================================================

-- Registered class data (populated by class modules)
ns.registered = {
    buffs = {},           -- List of buff keys to track
    debuffs = {},         -- List of debuff keys to track
    cooldowns = {},       -- { key = spellId } for cooldown tracking
    talents = {},         -- { { tab, index, key }, ... }
    glyphs = {},          -- { [glyphSpellId] = key, ... }
    buffMap = {},         -- { [spellId] = buffKey, ... }
    debuffMap = {},       -- { [spellId] = debuffKey, ... }
    externalDebuffMap = {},  -- { [spellId] = debuffKey, ... }
    debuffNamePatterns = {},  -- { { pattern, key }, ... } for name-based fallback
    externalDebuffNamePatterns = {},  -- same for external debuffs
    buffNamePatterns = {},  -- { { pattern, key }, ... } for name-based buff fallback
    combatLogHandlers = {},  -- Functions called on COMBAT_LOG_EVENT_UNFILTERED
    formHandlers = {},    -- { formId = { update = fn, spec = fn }, ... }
    specDetector = nil,   -- Function that returns current spec string
    buildDetector = nil,  -- Function (spec, state, mode) -> buildKey, source
    modes = {},           -- Rotation modes for minimap dropdown
    gcdSpellId = nil,     -- Spell ID used to check GCD
    defaults = {},        -- Class-specific default settings
    fallbackAbilities = {},  -- Last-resort ability keys per class (class-registered)
    procBuffs = {},       -- { [buffKey] = { minStacks = n } } proc-sound triggers
    spellSchool = nil,    -- Spell school for GetSpellBonusDamage (nil = Nature)
}

-- Register buff keys to track
function DH:RegisterBuffs(buffs)
    for _, buff in ipairs(buffs) do
        table.insert(ns.registered.buffs, buff)
    end
end

-- Register debuff keys to track
function DH:RegisterDebuffs(debuffs)
    for _, debuff in ipairs(debuffs) do
        table.insert(ns.registered.debuffs, debuff)
    end
end

-- Register cooldowns: { key = spellId, ... }
function DH:RegisterCooldowns(cooldowns)
    for key, spellId in pairs(cooldowns) do
        ns.registered.cooldowns[key] = spellId
    end
end

-- Register talents.
-- Entries may use the legacy { tab, index, key } row-major ordinal form or
-- the preferred { tab=, tier=, column=, key= } coordinate form (resolved at
-- runtime against the real tree, so it survives index quirks). State.lua
-- handles both via a (tier,column)->ordinal lookup built at talent update.
function DH:RegisterTalents(talents)
    for _, data in ipairs(talents) do
        table.insert(ns.registered.talents, data)
    end
end

-- Register glyphs: { [referenceGlyphSpellId] = key, ... }
-- The spell id is only used to derive the glyph's localized name; the socketed
-- glyph is then matched by name (see State.lua UpdateGlyphs).
function DH:RegisterGlyphs(glyphs)
    for spellId, key in pairs(glyphs) do
        ns.registered.glyphs[spellId] = key
    end
end

-- Register last-resort basic abilities (class keys) used when every
-- recommendation was filtered out as unknown. Class modules call this so the
-- core no longer hardcodes any class's ability keys.
function DH:RegisterFallbackAbilities(list)
    for _, key in ipairs(list) do
        table.insert(ns.registered.fallbackAbilities, key)
    end
end

-- Register a buff whose rising edge plays the proc sound.
-- opts (optional): { minStacks = n } requires that many stacks before it
-- counts as a proc (e.g. Maelstrom Weapon at 5). Class modules call this so
-- the core no longer hardcodes which class buffs are "procs".
function DH:RegisterProcBuff(key, opts)
    ns.registered.procBuffs[key] = opts or {}
end

-- Register the spell school used by GetSpellBonusDamage (e.g. 4 = Nature,
-- 3 = Fire, 16 = Frost). Defaults to Nature when no class registers one.
function DH:RegisterSpellSchool(schoolId)
    ns.registered.spellSchool = schoolId
end

-- Register buff spell ID mapping: { [spellId] = buffKey, ... }
function DH:RegisterBuffMap(map)
    for spellId, key in pairs(map) do
        ns.registered.buffMap[spellId] = key
    end
end

-- Register debuff spell ID mapping: { [spellId] = debuffKey, ... }
function DH:RegisterDebuffMap(map)
    for spellId, key in pairs(map) do
        ns.registered.debuffMap[spellId] = key
    end
end

-- Register external debuff mapping (from other players)
function DH:RegisterExternalDebuffMap(map)
    for spellId, key in pairs(map) do
        ns.registered.externalDebuffMap[spellId] = key
    end
end

-- Register debuff name patterns for fallback matching
function DH:RegisterDebuffNamePatterns(patterns)
    for _, data in ipairs(patterns) do
        table.insert(ns.registered.debuffNamePatterns, data)
    end
end

-- Register buff name patterns for fallback matching
function DH:RegisterBuffNamePatterns(patterns)
    for _, data in ipairs(patterns) do
        table.insert(ns.registered.buffNamePatterns, data)
    end
end

-- Register external debuff name patterns
function DH:RegisterExternalDebuffNamePatterns(patterns)
    for _, data in ipairs(patterns) do
        table.insert(ns.registered.externalDebuffNamePatterns, data)
    end
end

-- Register combat log handler function
function DH:RegisterCombatLogHandler(fn)
    if type(fn) ~= "function" then return end
    table.insert(ns.registered.combatLogHandlers, fn)
end

-- Register spec detector function
function DH:RegisterSpecDetector(fn)
    ns.registered.specDetector = fn
end

-- Register a fallback spec detector (used when the primary detector
-- returns nil/unknown). LibClassicSpecs hooks in here so the class
-- module detectors (registered later via RegisterSpecDetector) win.
function DH:RegisterSpecDetectorFallback(fn)
    ns.registered.specDetectorFallback = fn
end

-- Register a build detector (Improvement 2). fn(spec, state, mode) returns a
-- build key plus a source tag ("talents"/"glyphs"/"stats") or nil to fall back
-- to the spec. Only invoked lazily by State:GetBuildInfo().
function DH:RegisterBuildDetector(fn)
    ns.registered.buildDetector = fn
end

-- Return the cached build descriptor (or nil before State exists).
function DH:GetBuildInfo()
    if self.State and self.State.GetBuildInfo then
        return self.State:GetBuildInfo()
    end
    return nil
end

-- Convenience: just the build key.
function DH:GetBuild()
    local info = self:GetBuildInfo()
    return info and info.key or nil
end

-- Register a rotation mode for the minimap dropdown
-- key: unique string, data: { name, icon, rotation = fn(addon) }
function DH:RegisterMode(key, data)
    ns.registered.modes = ns.registered.modes or {}
    data.key = key
    table.insert(ns.registered.modes, data)
end

-- Register a "safe" mode for specs whose rotation is not implemented (e.g.
-- healers). It recommends nothing and prints an informative message when it
-- becomes active, instead of silently running the wrong DPS rotation.
function DH:RegisterSafeMode(key, name, icon, message)
    return self:RegisterMode(key, {
        name = name,
        icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark",
        safe = true,
        message = message or "Rotations for this spec are not supported",
        rotation = function() return {} end,
    })
end

-- Post-phase 4: register a class PvP priority branch.
-- fn(addon, state, ctx) -> recs. ctx = { burst = bool, burstThreshold = n }.
-- Consulted instead of the PvE rotation while pvp_mode_enabled is true.
function DH:RegisterPvPRotation(fn)
    ns.registered.pvpRotation = fn
end

-- Register a declarative PvP priority spec:
--   { interrupt={...}, control={...}, burst={...}, survival={...},
--     dot={...}, filler={...} }
-- Builds the recommendation list as:
--   interrupt (target casting) -> control -> burst (target hp <= threshold)
--   -> survival -> dot (missing) -> filler.
function DH:RegisterPvPSpec(spec)
    ns.registered.pvpSpec = spec
    self:RegisterPvPRotation(function(addon, state, ctx)
        return self:BuildPvPRecommendations(addon, state, ctx)
    end)
end

function DH:BuildPvPRecommendations(addon, state, ctx)
    local spec = ns.registered.pvpSpec
    local recs = {}
    if not spec then return recs end
    local abilities = addon.Class and addon.Class.abilities or {}
    local function Ready(key)
        local a = abilities[key]
        if not a then return false end
        return DH:SpellReady(a.id)
    end
    local function add(list)
        for _, key in ipairs(list or {}) do
            if abilities[key] and Ready(key) then
                recs[#recs + 1] = { ability = key, priority = #recs + 1 }
            end
        end
    end
    local casting = state and state.target and state.target.casting
    if casting then add(spec.interrupt) end
    add(spec.control)
    if ctx and ctx.burst then add(spec.burst) end
    add(spec.survival)
    if not casting then add(spec.interrupt) end
    for _, key in ipairs(spec.dot or {}) do
        local d = state and state.debuff and state.debuff[key]
        if abilities[key] and not (d and d.up) and Ready(key) then
            recs[#recs + 1] = { ability = key, priority = #recs + 1 }
        end
    end
    add(spec.filler)
    return recs
end

-- Register GCD reference spell
function DH:RegisterGCDSpell(spellId)
    ns.registered.gcdSpellId = spellId
end

-- Register abilities that are melee range (for UI range overlay)
function DH:RegisterMeleeAbilities(keys)
    for _, key in ipairs(keys) do
        DH.Class.meleeAbilities[key] = true
    end
end

-- Register class-specific default settings (merged into defaults)
function DH:RegisterDefaults(classDefaults)
    -- Merge instead of replace: Config.lua injects its own defaults into the
    -- same table and class modules may load after that (LoadOnDemand).
    for k, v in pairs(classDefaults) do
        ns.registered.defaults[k] = v
    end
end

-- ============================================================================
-- M29: shared class-module factories
-- These remove the repeated boilerplate that every RotationCore_<Class> module
-- carried inline (ability-table finalisation, the `common` defaults block, the
-- status slash command and the live-debug frame updater). Behaviour is
-- byte-for-byte identical to the old inline code; only the location moved.
-- ============================================================================

-- Tag every ability with its key, index it by name and resolve its texture
-- from the spell id. This exact loop was duplicated in all ten class modules.
function DH:RegisterAbilityTable()
    local abilities = DH.Class and DH.Class.abilities
    if not abilities or not DH.Class.abilityByName then return end
    for key, ability in pairs(abilities) do
        ability.key = key
        DH.Class.abilityByName[ability.name] = ability
        if ability.id then
            local name, rank, icon = GetSpellInfo(ability.id)
            if icon then
                ability.texture = icon
            end
        end
    end
end

-- Settings stored under the `common` key are identical for every class bar a
-- handful of extras. Classes call RegisterCommonDefaults(extras); extras win
-- over the base values and the merged table is registered as usual.
ns.COMMON_DEFAULTS = {
    dummy_ttd = 300,
    menu_mode = "simple",
    auto_cooldowns = true,
    cooldown_order = "priority",
    target_mode = "single",
    activity_profile = "raid",
    ttd_raid = 300, ttd_dungeon = 60, ttd_solo = 15, ttd_pvp = 30,
    hold_cd_at_end = true,
    cd_hold_ttd = 30,
    use_glyphs = true,
    raid_buffs = true,
    display_count = 3,
    sound_procs = false,
    sound_procs_file = "Sound\\Interface\\AlarmClockWarning3.wav",
    proc_flash = false,
    proc_flash_speed = 3.0,
    log_decisions = false,
    log_max_lines = 1000,
    icon_size = 36,
    icon_gap = 4,
    icon_columns = 3,
    glow_style = "pulse",
    guide_marker = false,   -- bobbing chevron above the next ability button
    glow_frequency = 1.0,   -- pulse speed multiplier (1 = style default)
    glow_lines = 1,         -- concentric border rings (1 = classic single ring)
    glow_thickness = 1.5,   -- border size multiplier
    spellframe_font = "default",
    spellframe_font_size = 0,  -- 0 = keep the client default size
    spellFrame_pos_per_spec = false,
}

function DH:RegisterCommonDefaults(extra)
    local merged = {}
    for k, v in pairs(ns.COMMON_DEFAULTS) do merged[k] = v end
    if type(extra) == "table" then
        for k, v in pairs(extra) do merged[k] = v end
    end
    ns.registered.defaults.common = merged
end

-- Build the live-debug frame updater from a class `buildLines(s, rec1, rec2,
-- rec3)` callback returning the class-specific middle lines. The factory owns
-- the header, the three recommendation slots and the frame text/show calls.
function DH:MakeDebugFrameUpdater(buildLines)
    return function()
        if not ns.DebugFrame then return end
        local s = DH.State
        local rec1 = ns.recommendations[1] and ns.recommendations[1].ability or "none"
        local rec2 = ns.recommendations[2] and ns.recommendations[2].ability or "none"
        local rec3 = ns.recommendations[3] and ns.recommendations[3].ability or "none"
        local lines = { "|cFFFFFF00=== Live Debug ===|r" }
        if buildLines then
            local mid = buildLines(s, rec1, rec2, rec3)
            if type(mid) == "table" then
                for i = 1, #mid do lines[#lines + 1] = mid[i] end
            end
        end
        lines[#lines + 1] = string.format("|cFFFFFF00Rec: %s > %s > %s|r", rec1, rec2, rec3)
        ns.DebugFrame.text:SetText(table.concat(lines, "\n"))
        ns.DebugFrame:Show()
    end
end

-- Register form update handler
function DH:RegisterFormHandler(formId, handler)
    ns.registered.formHandlers[formId] = handler
end

-- v3.4.0: the class defensive that the battle-context gate recommends first
-- during a "defensive" phase (Improvement 1). Optional; without it the gate
-- stays inactive.
function DH:RegisterDefensiveAbility(key)
    ns.defensiveKey = key
end

-- ============================================================================
-- LEARNED ABILITIES (level / talent filtering)
-- The rotation must only offer abilities the player has actually learned.
-- A level 20 mage has no Frostbolt rank he never trained, no talent abilities
-- he has no points for, so those can never be recommended.
--
-- IsSpellKnown(spellID) exists in 3.3.5a. The result is cached and the cache
-- is dropped whenever the spell book, talents or level change.
-- ============================================================================

ns.knownSpells = nil  -- { [spellId] = bool }, nil = needs a rebuild
ns.knownByName = nil  -- { [localized name] = known spell id }, nil = rebuild

-- Drop the cache (spell book / talents / level changed)
function DH:InvalidateKnownSpells()
    ns.knownSpells = {}
    ns.knownByName = nil
    ns.resolvedId = {}
    ns._gcdSpellResolved = nil
    ns.knownSpellsVersion = (ns.knownSpellsVersion or 0) + 1
end

-- Scan the spell book for the spells the player has actually learned and map
-- every spell name to its current-rank id.
--
-- Abilities are registered with their MAX-rank ids (Frostbolt 42842, ...).
-- A character who has not trained the max rank has IsSpellKnown(42842) == false,
-- so without this map every ranked ability would be filtered out as "unknown"
-- and the queue would fall back to single-rank cooldowns only. 3.3.5a has no
-- "known by name" API, so the spell book is the only source of truth.
local function BuildKnownByName()
    -- Guard every spell book call: private 3.3.5a servers do not all ship the
    -- same helpers (GetSpellBookItemInfo is missing on some). Wrap the whole
    -- scan so a missing/broken API can never abort the rotation.
    local ok, map = pcall(function()
        local out = {}
        if type(GetNumSpellTabs) ~= "function" or type(GetSpellTabInfo) ~= "function" then
            return out
        end
        local bookType = BOOKTYPE_SPELL or "spell"
        for tab = 1, (tonumber(GetNumSpellTabs()) or 0) do
            local _, _, offset, numSpells = GetSpellTabInfo(tab)
            if offset and numSpells then
                for i = offset + 1, offset + numSpells do
                    local name, id
                    if type(GetSpellBookItemName) == "function" then
                        name = GetSpellBookItemName(i, bookType)
                    end
                    if type(GetSpellBookItemInfo) == "function" then
                        local _, spellId = GetSpellBookItemInfo(i, bookType)
                        if type(spellId) == "number" then id = spellId end
                    end
                    if not id and type(GetSpellLink) == "function" then
                        local link = GetSpellLink(i, bookType)
                        if type(link) == "string" then
                            local lid = tonumber(link:match("spell:(%d+)"))
                            local lname = link:match("%[(.-)%]")
                            if not name then name = lname end
                            -- trust the link id only when it agrees with the name
                            if lid and (not lname or not name or name == lname) then
                                id = lid
                            end
                        end
                    end
                    if name and name ~= "" then
                        out[name] = id or true  -- id preferred, name alone is enough
                    end
                end
            end
        end
        return out
    end)
    if ok and type(map) == "table" then return map end
    return {}
end

-- Is a single spell id known to the player?
function DH:IsSpellKnownId(spellId)
    if not spellId then return true end
    if not IsSpellKnown then return true end  -- old client: never filter

    local cache = ns.knownSpells
    if not cache then
        cache = {}
        ns.knownSpells = cache
    end

    local known = cache[spellId]
    if known == nil then
        known = IsSpellKnown(spellId) and true or false
        if not known and GetSpellInfo then
            -- Registered id is a higher rank than the player currently knows
            -- (or no rank at all): accept it if any rank of the same spell is
            -- in the spell book.
            local name = GetSpellInfo(spellId)
            if name then
                if not ns.knownByName then
                    ns.knownByName = BuildKnownByName()
                end
                if ns.knownByName[name] then known = true end
            end
        end
        cache[spellId] = known
    end
    return known
end

-- The spell id the player actually knows for this ability's spell name: the
-- registered id when it is the known rank, otherwise the known rank's id.
-- Used for cooldown / GCD tracking (GetSpellCooldown is rank-specific).
function DH:ResolveKnownSpellId(spellId)
    if not spellId then return nil end
    if not IsSpellKnown then return spellId end
    if IsSpellKnown(spellId) then return spellId end
    -- Memoize: this runs for every registered cooldown on every state tick.
    if not ns.resolvedId then ns.resolvedId = {} end
    local cached = ns.resolvedId[spellId]
    if cached then return cached end
    local resolved = spellId
    if GetSpellInfo then
        local name = GetSpellInfo(spellId)
        if name then
            if not ns.knownByName then
                ns.knownByName = BuildKnownByName()
            end
            local knownId = ns.knownByName[name]
            if type(knownId) == "number" then resolved = knownId end
        end
    end
    ns.resolvedId[spellId] = resolved
    return resolved
end

-- Is an ability key (from DH.Class.abilities) learned?
-- Abilities without a spell id (auto attack, shoot, ...) are always allowed.
function DH:IsAbilityKnown(key)
    local ability = self.Class and self.Class.abilities and self.Class.abilities[key]
    if not ability or not ability.id then return true end
    return self:IsSpellKnownId(ability.id)
end

-- Drop unlearned abilities from a recommendation list
function DH:FilterKnown(recs)
    if not recs then return {} end
    local out = {}
    for i = 1, #recs do
        if self:IsAbilityKnown(recs[i].ability) then
            out[#out + 1] = recs[i]
        end
    end
    return out
end

-- First known basic ability from the class-registered fallback list (nil if
-- nothing fits). Called by UpdateRecommendations when FilterKnown emptied the
-- queue. The list is populated by class modules via RegisterFallbackAbilities.
function DH:FirstKnownFallback()
    local abilities = self.Class and self.Class.abilities
    if not abilities then return nil end
    for _, key in ipairs(ns.registered.fallbackAbilities) do
        if abilities[key] and self:IsAbilityKnown(key) then
            return key
        end
    end
    return nil
end

-- ============================================================================
-- SHARED SETTINGS API
-- Settings live either in the active spec table (db[mode.key]) or in the
-- shared db.common table. Missing fields return nil - callers use
-- `or <default>` so old profiles keep working (part 9 of the spec).
-- ============================================================================

-- Phase 3.3: are per-specialization setting overrides active?
function DH:IsSpecProfilesEnabled()
    return (self.db and self.db.common and self.db.common.spec_profiles_enabled == true) or false
end

-- Are the draggable windows locked? Single source of truth: frames_locked.
-- Default: movable (no /rc move needed).
function DH:WindowsLocked()
    return (self.GetSetting and self:GetSetting("frames_locked")) == true
end

function DH:GetSetting(key)
    if not self.db or key == nil then return nil end
    local mode = self.GetActiveMode and self:GetActiveMode()
    local mt = mode and self.db[mode.key]
    if type(mt) == "table" and mt[key] ~= nil then
        return mt[key]
    end
    -- Per-spec override wins over the shared common table
    if self:IsSpecProfilesEnabled() then
        local spec = self.GetActiveSpec and self:GetActiveSpec() or nil
        local profs = self.db.spec_profiles
        local sp = (spec and type(profs) == "table") and profs[spec] or nil
        if type(sp) == "table" and sp[key] ~= nil then
            return sp[key]
        end
    end
    if type(self.db.common) == "table" and self.db.common[key] ~= nil then
        return self.db.common[key]
    end
    return nil
end

local function SetSettingRaw(self, key, value)
    if not self.db or key == nil then return false end
    -- Bump a version token so UI caches (e.g. the glow animation) can refresh
    -- lazily instead of reading settings every frame.
    ns.glowCacheVersion = (ns.glowCacheVersion or 0) + 1
    -- The toggle itself always lives in the shared table
    if key == "spec_profiles_enabled" then
        if type(self.db.common) ~= "table" then self.db.common = {} end
        self.db.common[key] = value
        return true
    end

    local mode = self.GetActiveMode and self:GetActiveMode()
    local mt = mode and self.db[mode.key]
    if type(mt) == "table" and mt[key] ~= nil then
        mt[key] = value
        return true
    end
    -- Target the active spec's override table when enabled
    if self:IsSpecProfilesEnabled() then
        local spec = self.GetActiveSpec and self:GetActiveSpec() or nil
        if spec and spec ~= "" and spec ~= "unknown" then
            if type(self.db.spec_profiles) ~= "table" then self.db.spec_profiles = {} end
            local sp = self.db.spec_profiles[spec]
            if type(sp) ~= "table" then sp = {}; self.db.spec_profiles[spec] = sp end
            sp[key] = value
            return true
        end
    end
    if type(self.db.common) ~= "table" then self.db.common = {} end
    self.db.common[key] = value
    return true
end

-- Public setter: mirrors SetSettingRaw and re-evaluates the update scheduler
-- when a scheduling-related setting changes.
function DH:SetSetting(key, value)
    local ok = SetSettingRaw(self, key, value)
    if ok and (key == "update_mode" or key == "poll_frequency") and self.SyncUpdateLoop then
        self:SyncUpdateLoop()
    end
    return ok
end

-- Shared UI palette (part 10). Every window reads its colors from here so the
-- whole addon switches together when the theme setting changes.
function DH:GetUITheme()
    local name = (self.GetSetting and self:GetSetting("theme")) or "class"
    -- 1) Explicit skin wins (ui_skin), keeping the optional skin feature.
    local skin = self.GetUISkin and self:GetUISkin()
    if skin and skin.theme and skin.name ~= "default" then
        local t = skin.theme
        return {
            backdrop = t.backdrop,
            border = t.border,
            title = t.title,
            accent = t.accent or { 1, 0.82, 0 },
            text = t.text or { 0.92, 0.92, 0.92 },
            bg = skin.bg or ns.DEFAULT_BG,
            edge = skin.edge or ns.DEFAULT_EDGE,
            edgeSize = skin.edgeSize or 16,
            tile = skin.tile ~= false,
            tileSize = skin.tileSize or 16,
            insets = skin.insets or { left = 4, right = 4, top = 4, bottom = 4 },
        }
    end
    -- 2) Otherwise use the window style resolved by the active UI shell.
    local style, shell
    if self.GetUIStyle then
        style, shell = self:GetUIStyle()
    else
        style = nil
        shell = "blizzard"
    end
    local t = (style and style.theme) or { backdrop = { 0.10, 0.10, 0.10, 0.88 }, border = { 0.85, 0.70, 0.45, 0.95 }, title = { 1, 0.90, 0.55 } }
    if shell == "elvui" and ns.SHELL_THEMES and ns.SHELL_THEMES.elvui then
        t = ns.SHELL_THEMES.elvui
    elseif shell == "bartender4" or shell == "dominos" then
        t = { backdrop = { 0.10, 0.10, 0.10, 0.88 }, border = { 0.85, 0.70, 0.45, 0.95 }, title = { 1, 0.90, 0.55 } }
    end
    -- 3) The legacy "theme" setting (dark/light/class/contrast) tints the window.
    local light = (name == "light")
    local function tinted(rgb)
        return {
            backdrop = { 0.06, 0.06, 0.07, 0.92 },
            border = { rgb[1], rgb[2], rgb[3], 1 },
            title = { rgb[1], rgb[2], rgb[3] },
            accent = { rgb[1], rgb[2], rgb[3] },
            text = { 0.92, 0.92, 0.92 },
        }
    end
    if name == "class" then
        local cr, cg, cb = self:GetClassColor()
        t = tinted({ cr, cg, cb })
    elseif name == "custom" then
        local c = (self.GetSetting and self:GetSetting("theme_custom_color")) or { 1, 0.82, 0 }
        t = tinted({ c[1] or 1, c[2] or 0.82, c[3] or 0 })
    elseif name == "contrast" then
        t = {
            backdrop = { 0, 0, 0, 0.96 },
            border = { 1, 1, 1, 1 },
            title = { 1, 1, 1 },
            accent = { 1, 0.85, 0.2 },
            text = { 1, 1, 1 },
        }
    elseif light then
        t = {
            backdrop = { 0.86, 0.84, 0.78, 0.97 },
            border = { 0.42, 0.35, 0.20, 0.95 },
            title = { 0.32, 0.24, 0.05 },
            accent = { 0.62, 0.42, 0.02 },
            text = { 0.12, 0.12, 0.12 },
        }
    end
    -- The light theme paints its own solid plate (WHITE8X8) so the light tint
    -- reads correctly instead of muddling the dark stone texture.
    local bg = (light and "Interface\\Buttons\\WHITE8X8") or (skin and skin.bg) or ns.DEFAULT_BG
    local edge = (light and "Interface\\Tooltips\\UI-Tooltip-Border") or (skin and skin.edge) or ns.DEFAULT_EDGE
    return {
        backdrop = t.backdrop,
        border = t.border,
        title = t.title,
        accent = t.accent or { 1, 0.82, 0 },
        text = t.text or { 0.92, 0.92, 0.92 },
        bg = bg,
        edge = edge,
        edgeSize = (light and 8) or (skin and skin.edgeSize) or 16,
        tile = light or (not skin) or skin.tile ~= false,
        tileSize = (skin and skin.tileSize) or 16,
        insets = (light and { left = 2, right = 2, top = 2, bottom = 2 }) or (skin and skin.insets) or { left = 4, right = 4, top = 4, bottom = 4 },
        light = light,
    }
end

-- Central gate for every major cooldown recommended from getPriority.
-- Missing settings return nil and block (the defaults are merged into the
-- profile via MergeDefaults, so this only bites unregistered keys).
function DH:CanUseCooldown(sim, spellKey, settingKey)
    if type(sim) ~= "table" or type(sim.ready) ~= "function" then return false end
    -- phase-3 #1: a "simple" adaptive rotation keeps long cooldowns out of the
    -- recommendation queue.
    if self.GetRotationComplexity and self:GetRotationComplexity() == "simple" then
        local base = sim.baseCDs and sim.baseCDs[spellKey]
        if type(base) == "number" and base >= 60 then return false end
    end
    if settingKey and not self:GetSetting(settingKey) then return false end
    if not self:GetSetting("auto_cooldowns") then return false end
    -- cooldown_order "manual": cooldowns stay out of the recommendation queue
    if self:GetSetting("cooldown_order") == "manual" then return false end
    if not self:IsAbilityKnown(spellKey) then return false end
    if not sim:ready(spellKey) then return false end
    if sim.gcd_remains and sim.gcd_remains > 0.05 then return false end
    if sim.cast_remains and sim.cast_remains > 0.05 then return false end
    if self:IsSnoozed(spellKey) then return false end
    -- Не жать длинный кулдаун в конце боя (part 3.1 / 5.4)
    if self:GetSetting("hold_cd_at_end")
       and sim.ttd and sim.ttd < (self:GetSetting("cd_hold_ttd") or 30) then
        local base = sim.baseCDs and sim.baseCDs[spellKey]
        if base and base > 60 then return false end
    end
    return true
end

-- Time-to-die estimate for the active activity profile (raid/dungeon/solo/pvp)
function DH:GetTTD()
    if not self.db then return 300 end
    local profile = self:GetSetting("activity_profile") or "raid"
    return self:GetSetting("ttd_" .. profile) or 300
end

-- Resolve target_mode against the sim's enemy count.
-- "single" / "cleave" / "aoe" are returned verbatim; "auto" picks single for
-- one enemy, the 2-3 target cleave band, or aoe at/above aoe_threshold.
-- ("auto_cleave" is accepted as a legacy alias for the same 3-way split.)
function DH:ResolveTargetMode(sim)
    local mode = self:GetSetting("target_mode") or "single"
    -- Improvement 5: optional phase-driven override (phase 2 -> aoe, 3 -> single)
    if self.GetSetting and self:GetSetting("timeline_auto_phase") and ns.GetPhaseTargetMode then
        local pm = ns.GetPhaseTargetMode()
        if pm then mode = pm end
    end
    local count = (type(sim) == "table" and sim.active_enemies)
        or (self.State and self.State.active_enemies) or 1
    if mode == "auto" or mode == "auto_cleave" then
        local aoeThreshold = self:GetSetting("aoe_threshold") or 4
        if count >= aoeThreshold then return "aoe" end
        local cleaveThreshold = self:GetSetting("cleave_threshold") or 2
        if count >= cleaveThreshold then return "cleave" end
        return "single"
    end
    return mode
end

-- True when the resolved mode is any multi-target mode (cleave or aoe).
-- Class rotations use this so a cleave simply reuses their multi-target list.
function DH:IsMultiTarget(sim)
    if not self.ResolveTargetMode then return false end
    local m = self:ResolveTargetMode(sim)
    return m == "aoe" or m == "cleave"
end

-- True when the resolved mode is specifically the 2-3 target cleave band.
function DH:IsCleave(sim)
    if not self.ResolveTargetMode then return false end
    return self:ResolveTargetMode(sim) == "cleave"
end

-- Explain why there is nothing to recommend right now (Phase 1.2).
-- Returns nil when a recommendation is expected (so the caller keeps the
-- normal UI), otherwise a short human-readable reason. Strings go through
-- DH.L so RU clients get a translation (phase 2.4 collects the keys).
function DH:GetIdleReason()
    local tbl = self.L
    local function T(s)
        if tbl then return tbl[s] end
        return s
    end

    if not self.db then return T("Settings not loaded") end
    if not self.db.enabled then return T("Addon disabled") end
    if self.db.paused then
        -- paused_text=false suppresses the "Paused" label (window just hides).
        if self:GetSetting("paused_text") == false then return nil end
        return T("Paused")
    end

    -- A cast/channel in progress: the next press may be blocked
    if UnitCastingInfo and UnitCastingInfo("player") then
        return T("Casting")
    end
    if UnitChannelInfo and UnitChannelInfo("player") then
        return T("Channeling")
    end

    local st = self.State
    if st and st.gcd_remains and st.gcd_remains > 0.05 then
        return T("Global cooldown")
    end

    if not UnitExists("target") then
        return T("No target")
    end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("target") then
        return T("Target is dead")
    end
    if st and st.target and st.target.canAttack == false then
        return T("Target is not attackable")
    end
    if st and st.target and st.target.exists and st.target.inRange == false
       and not (self.Class and next(self.Class.meleeAbilities or {})) then
        return T("Target out of range")
    end

    local level = UnitLevel("player") or 0
    if level > 0 and level < 10 then
        return T("Level too low")
    end

    if st and st.mana and st.mana.max > 0 and st.mana.pct < 1 then
        return T("No mana")
    end

    return T("No recommendation")
end

-- Self-test: reports what the rotation would do right now without touching
-- keybinds or the action bars. /rc test rotation
function DH:RunRotationSelfTest()
    if self.UpdateState then self:UpdateState() end
    if self.UpdateRecommendations then self:UpdateRecommendations() end
    local recs = ns.recommendations or {}
    self:Print(L("--- Rotation self-test ---"))
    self:Print(L("Spec: ") .. tostring(self:GetActiveSpec())
        .. L(", build: ") .. (self.db.auto_mode and L("auto") or tostring(self.db.mode)))
    self:Print(L("Target: ") .. tostring(UnitExists("target"))
        .. L(", CanAttack: ") .. tostring(UnitCanAttack("player", "target")))
    self:Print(L("Active enemies: ") .. tostring(self.State and self.State.active_enemies))
    if #recs > 0 then
        self:Print(L("Result: ") .. #recs .. L(" recommendation(s), top = ") .. tostring(recs[1].ability))
    else
        self:Print(L("Result: empty (reason: ") .. tostring(self:GetIdleReason()) .. ")")
    end
    return #recs
end

-- ============================================================================
-- SETTINGS
-- ============================================================================

-- Core default settings (class-agnostic)
local coreDefaults = {
    enabled = true,
    paused = false,                -- /rc pause: freeze recommendations but keep the addon on
    debug = false,
    show_debug_frame = false,
    -- Pick the build (arcane/fire/frost/...) from the player's talents
    auto_mode = true,
    display = {
        -- How many upcoming abilities are highlighted on the action bars.
        -- 1 = one at a time: the next ability lights up, after you press it
        -- the following one lights up.
        num_icons = 1,
        -- Glow border size relative to the action button
        glow_size = 1.5,
        -- Show the priority number (1/2/3) above each highlighted button
        show_numbers = false,
        -- Pulsing glow animation
        pulse = true,
        -- Only highlight abilities while in combat
        combat_only = false,
        -- MaxDps-style window showing the next ability icons
        show_spellframe = true,
        spellframe_scale = 1,
        -- How many icons the MaxDps-style window shows (independent of
        -- num_icons, which only controls the action-bar glow count)
        spellframe_icons = 3,
    },
    -- Position of the spell icon window (screen center offsets)
    spellFrame = { x = 0, y = -250 },

    -- Shared per-spec settings (part 1). Class modules register the SAME
    -- table (plus per-spec extras), so every class gets an identical
    -- options window; core keeps this copy as a fallback for profiles
    -- loaded before a class module registers.
    common = {
        menu_mode = "simple",         -- "simple" / "advanced" options window
        dummy_ttd = 300,
        use_racial_cooldowns = true,   -- offer racial cooldowns in the cooldown window
        enemy_count_enabled = true,    -- show the enemy counter near the icon window
        resource_warning_enabled = true, -- warn before capping a resource
        dot_panel_enabled = false,     -- optional DoT/debuff panel
        party_health_enabled = false,  -- optional group health monitor
        party_health_position = { x = 250, y = -80 },
        heal_assist_enabled = false,   -- healer assist window
        heal_assist_position = { x = -260, y = -120 },
        dot_panel_position = { x = 250, y = 80 },
        swing_timer_enabled = false,   -- optional melee swing timer
        swing_timer_position = { x = 0, y = -330 },
        timeline_bars_enabled = true,  -- draw bars in the timeline window
        auto_cooldowns = true,
        cooldown_order = "priority",   -- "manual" skips cooldowns in the queue
        target_mode = "auto",          -- "single" / "cleave" / "aoe" / "auto" (auto = 1/2-3/4+)
        activity_profile = "raid",     -- selects which ttd_* applies
        ttd_raid = 300,
        ttd_dungeon = 60,
        ttd_solo = 15,
        ttd_pvp = 30,
                hold_cd_at_end = true,
        cd_hold_ttd = 30,
        aoe_threshold = 4,             -- "auto" switches to AOE at this count
        cleave_threshold = 2,          -- "auto" switches to cleave at this count
        update_mode = "events",        -- "events" (event-driven) / "poll" (fixed-rate)
        poll_frequency = 5,            -- Hz for the fallback poll / "poll" mode
        build_detect_mode = "talents_glyphs_stats",  -- "talents" / "talents_glyphs" / "talents_glyphs_stats"
        -- Improvement 6: user-authored priority list (APL)
        custom_apl_enabled = false,    -- use the parsed custom APL instead of the class rotation
        custom_apl = {},               -- parsed APL rules (see ns.ParseAPL)
        custom_apl_source = "",        -- raw text the parsed rules came from
        use_glyphs = true,
        raid_buffs = true,
        display_count = 3,             -- how many recs are shown
        sound_procs = false,
        sound_procs_file = "Sound\\Interface\\AlarmClockWarning3.wav",
        proc_flash = false,
        proc_flash_speed = 3.0,
        log_decisions = false,
        log_max_lines = 1000,
        icon_size = 36,
        icon_gap = 4,
        icon_columns = 3,
        orientation = "horizontal",    -- "horizontal" (row) / "vertical" (column)
        spellframe_icons = 3,           -- how many queue icons are drawn (1-10)
        show_gcd_timer = true,         -- show the global-cooldown sweep timer
        show_time = true,              -- show the remaining-time text on icons
        show_priority_numbers = false, -- overlay the priority index on each icon
        show_background = true,        -- draw the backdrop behind the queue window
        show_border = true,            -- draw the border around the queue window
        show_title = true,             -- show the window title text
        hide_out_of_combat = false,    -- hide the queue window out of combat
        hide_no_target = false,        -- hide the queue window with no target
        hide_when_idle = false,        -- hide the queue window when nothing is recommended
        fade_when_idle = false,        -- fade instead of hide when idle
        theme = "class",               -- "class" / "custom" / "dark" / "light" / "contrast"
        theme_custom_color = { 1, 0.82, 0 }, -- accent tint for the "custom" theme
        show_resource_bar = false,     -- reserved: options resource bar removed (kept for compatibility)
        paused_text = true,            -- show a "paused" label when disabled
        glow_style = "pulse",          -- pulse / static / flash / rainbow
        colorblind_mode = false,       -- orange/blue/grey priority palette
        spellFrame_pos_per_spec = false,
        -- Phase 1 UX
        show_keybind = true,           -- show the action-bar binding on each icon
        show_idle_reason = true,       -- explain why nothing is recommended
        spellframe_combat_only = false, -- hide the icon window out of combat
        show_mode_indicator = true,    -- S/A/Au target-mode indicator on the window title
        show_color_legend = true,      -- priority color legend in the options window
        -- Phase 2 UX
        show_cooldowns_display = true,    -- optional big-cooldowns window
        cooldowns_position = { x = -150, y = 0 },
        cooldowns_num_icons = 3,          -- 2-3 icons
        cooldowns_min_cd = 60,            -- only cooldowns this long or longer
        cooldowns_show_ready = true,      -- include ready cooldowns (sorted first)
        cooldowns_hide_empty = false,     -- hide the cooldowns window when nothing is ready
        cooldowns_scale = 1,              -- size of the cooldowns window (resize grip / slider)
        show_interrupts_display = false,  -- optional interrupt window
        interrupts_always_show = false,   -- keep the interrupt window visible when idle
        interrupt_ready_sound = false,    -- play a sound when the interrupt is ready again
        interrupts_position = { x = 170, y = -250 },
        interrupts_scale = 1,             -- size of the interrupt window (resize grip)
        show_timeline_display = true,     -- optional boss-timeline window (phase + timers)
        timeline_position = { x = 0, y = 200 },
        timeline_scale = 1,               -- size of the timeline window
        -- Per-window opacity (config mode) and tint (auto = follow theme).
        opacity_primary = 1, opacity_cooldowns = 1, opacity_interrupts = 1, opacity_timeline = 1,
        tint_primary = "auto", tint_cooldowns = "auto", tint_interrupts = "auto", tint_timeline = "auto",
        -- Phase 2.2 / Phase 3
        show_tooltips = true,             -- tooltips on options controls
        tooltip_delay = 0.3,              -- seconds before the tooltip appears
        profile_export_enabled = true,    -- show Export/Import in the Profiles tab
        spec_profiles_enabled = false,    -- per-specialization settings
        -- Post-phase features
        auto_reload_on_talent_change = true,  -- rebuild the rotation after talents change
        training_mode = false,            -- ALT-SHIFT-L: recommend on a dummy out of combat
        training_chat_output = true,      -- print the REC1 reason on change while training
        training_sound = false,           -- play a sound on REC1 change while training
        heal_dps_mode = "auto",           -- "auto" / "on" / "off": DPS rotation in healer specs
        pvp_mode_enabled = false,         -- ALT-SHIFT-V: PvP priority branch
        pvp_burst_threshold = 50,         -- burst when the target is below this HP %
        -- Post-phase features (prompt 2)
        boss_profiles_enabled = false,    -- ENCOUNTER_START applies a stored boss profile
        boss_profiles = {},               -- [encounterID] = { override settings }
        stats_enabled = false,            -- /rc stats: recommended/cast/missed per spell
        ideal_dps_enabled = false,        -- /rc stats dps: compare against an ideal
        -- Prompt 3: colour palettes / animations / boss timeline / layouts
        color_palette = "default",        -- default/protanopia/deuteranopia/tritanopia/high_contrast/custom
        animations_enabled = true,        -- fade / crossfade transitions on the icon window
        animation_speed = 1.0,            -- 0.5 - 2.0 (higher = faster)
        timeline_enabled = false,         -- DBM / BigWigs boss-timeline hints
        timeline_show_burst = true,       -- show the burst countdown text
        timeline_auto_phase = false,      -- auto-switch rotation by boss phase
        timeline_burst_window = 15,       -- seconds "before burst" that means Hold CD
        display_layout = "center",        -- center / side / minimal / raid / custom
        -- v3.3.0 phase 2/3: coaching, adaptive rotation, learning stats
        dps_forecast_enabled = false,     -- live DPS forecast above the icon window
        dps_forecast_show_actual = true,  -- also show actual DPS + loss %
        dps_forecast_update_interval = 1.0,
        dps_forecast_position = "above_spellframe",
        dps_color = "auto",               -- DPS forecast text colour (auto = default)
        class_pulse_enabled = true,       -- colour indicator: how well you play
        class_pulse_position = "left_of_spellframe",
        pulse_color = "auto",             -- class-pulse colour (auto = score based)
        exam_mode = false,                -- no glow; measure accuracy
        exam_report_in_chat = true,
        mentor_mode = false,              -- explain mistakes after N in a row
        mentor_error_threshold = 3,
        mentor_show_in_chat = true,
        adaptive_rotation = "auto",       -- auto / simple / normal / complex
        ilvl_threshold_simple = 200,
        ilvl_threshold_complex = 245,
        learning_stats_enabled = true,    -- persist per-fight learning sessions
        learning_stats_max_sessions = 100,
        -- v3.4.0 feature pack (12 improvements). All safe to toggle; values are
        -- merged into every profile by MigrationDefaults (no settings lost).
        battle_context_enabled = true,     -- sim.battle_phase available to rotations
        phase_indicators = true,           -- show the current phase on the icon window
        combat_forecast_enabled = false,   -- "through Ns: <proc/cd> ready" lines
        forecast_window = 5,               -- forecast horizon in seconds
        forecast_max_lines = 3,            -- how many forecast lines to show
        group_awareness_enabled = true,    -- scan party/raid for raid buffs
        -- NOTE: boss_profiles_enabled is declared once above (opt-in, default
        -- false). Do not redeclare it here - the last value in this table wins.
        boss_profile_autoload = true,      -- apply the [boss][class][spec] profile automatically
        profile_advanced_ui = false,       -- show advanced profile options (deep personalization)
        timeline_deep_enabled = true,      -- BigWigs/DBM phase-message integration
        timeline_phase_auto = false,       -- switch rotation on deep-phase messages
        timeline_phase_announce = false,   -- print phase changes to chat
        wizard_window_size = { w = 780, h = 560 },  -- wizard window size
        wizard_require_all_answers = false,         -- Next always enabled; every step is optional
        frames_movable_default = true,              -- drag windows without /rc move
        frames_locked = false,                      -- /rc lock / option "Lock windows"
        spellframe_fixed_size = true,               -- don't resize with the rec count
        spellframe_compact = false,                 -- icon-only window (no title/backdrop)
        bg_style = "default",                       -- default / matte
        ui_font = "default",                        -- unified font for all windows
        ui_font_large = false,                      -- larger/readable text mode
        ui_skin = "default",               -- optional skin overlay (default = none)
        ui_opacity = 1,                    -- options window backdrop opacity (0.3 - 1)
        arena_mode = "auto",               -- auto / 2v2 / 3v3 / 5v5
        auto_activity = true,              -- auto-adjust activity (raid/dungeon/pvp/world)
    },
}

-- Deep copy function for defaults
local function DeepCopy(orig)
    local copy
    if type(orig) == 'table' then
        copy = {}
        for k, v in pairs(orig) do
            copy[k] = DeepCopy(v)
        end
    else
        copy = orig
    end
    return copy
end

-- Merge saved vars with defaults.
-- When `strict` is set (loading/importing saved data), a value whose type
-- disagrees with the default is treated as corrupt and replaced by the
-- default. Default-merging (strict off) never overrides a class value that
-- intentionally differs from the core default.
local function MergeDefaults(saved, default, strict)
    if type(default) ~= "table" then return saved or default end
    if type(saved) ~= "table" then saved = {} end

    for k, v in pairs(default) do
        if saved[k] == nil then
            saved[k] = DeepCopy(v)
        elseif type(v) == "table" then
            saved[k] = MergeDefaults(saved[k], v, strict)
        elseif strict and type(saved[k]) ~= type(v) then
            saved[k] = DeepCopy(v)
        end
    end
    return saved
end

-- Build full defaults by merging core + class-specific.
-- Class values win over core values for the same key (deep merge), so a
-- class-specific `common` (e.g. warlock aoe_threshold=2) overrides core.
local function BuildDefaults()
    local defaults = DeepCopy(coreDefaults)
    for k, v in pairs(ns.registered.defaults) do
        if type(v) == "table" and type(defaults[k]) == "table" then
            -- v (class) survives, core fills in only the missing keys
            defaults[k] = MergeDefaults(DeepCopy(v), defaults[k])
        else
            defaults[k] = DeepCopy(v)
        end
    end
    return defaults
end

-- ============================================================================
-- SAVED VARIABLES / PROFILES
-- Standard layout, same idea as most addons using saved variables:
--
--   RotationCoreDB = {
--       profiles    = { ["Default"] = { ...settings... }, ["Alt"] = {...} },
--       profileKeys = { ["Playername - Realmname"] = "Default" },
--       global      = { ...settings shared by every profile... },
--   }
--
-- DH.db always points at the ACTIVE profile table, so all code reading
-- DH.db.xxx keeps working unchanged.
--
-- IMPORTANT: the client loads the saved variables file AFTER all addon files
-- have been executed and BEFORE ADDON_LOADED fires. Nothing may touch
-- RotationCoreDB at file scope - only OnInitialize (ADDON_LOADED) reads it.
-- That was the reason settings were lost on restart in older versions.
-- ============================================================================

-- Settings that only existed in the old flat (<= 2.x) layout
local LEGACY_TOP_KEYS = { "locked", "scale", "alpha", "x", "y" }
local LEGACY_DISPLAY_KEYS = { "iconSize", "scale", "alpha", "x", "y", "showGCD", "showRange" }

-- Give the saved variable its standard structure (migrating the old flat one)
-- v3.4.0-hotfix6: rename legacy camelCase settings to snake_case and copy
-- old values forward so existing profiles keep working after the rename.
local KEY_ALIASES = {
    { "autoMode", "auto_mode" },
    { "numIcons", "num_icons" },
    { "spellFrameIcons", "spellframe_icons" },
    { "spellFrameScale", "spellframe_scale" },
    { "showNumbers", "show_numbers" },
    { "glowSize", "glow_thickness" },  -- legacy thickness -> canonical
    { "combatOnly", "combat_only" },
    { "showSpellFrame", "show_spellframe" },
    { "showDebugFrame", "show_debug_frame" },
}
local function ApplyKeyAliases(t)
    if type(t) ~= "table" then return end
    for i = 1, #KEY_ALIASES do
        local old, new = KEY_ALIASES[i][1], KEY_ALIASES[i][2]
        if t[old] ~= nil and t[new] == nil then t[new] = t[old] end
    end
end
local function MigrateKeyAliases(profile)
    if type(profile) ~= "table" then return end
    ApplyKeyAliases(profile)
    if type(profile.display) == "table" then ApplyKeyAliases(profile.display) end
    if type(profile.common) == "table" then ApplyKeyAliases(profile.common) end
end

local function MigrateSaved(saved)
    if type(saved) ~= "table" then
        return { profiles = { Default = {} }, profileKeys = {}, global = {} }
    end

    -- Already in profile form
    if type(saved.profiles) == "table" then
        if type(saved.profileKeys) ~= "table" then saved.profileKeys = {} end
        if type(saved.global) ~= "table" then saved.global = {} end
        if not next(saved.profiles) then
            saved.profiles.Default = {}
        end
        for _, prof in pairs(saved.profiles) do MigrateKeyAliases(prof) end
        return saved
    end

    -- Old flat database: the whole table becomes the "Default" profile
    local flat = saved
    for _, key in ipairs(LEGACY_TOP_KEYS) do
        flat[key] = nil
    end
    if type(flat.display) == "table" then
        for _, key in ipairs(LEGACY_DISPLAY_KEYS) do
            flat.display[key] = nil
        end
    end

    MigrateKeyAliases(flat)
    return {
        profiles = { Default = flat },
        profileKeys = {},
        global = {},
    }
end

local function GetProfileKey()
    local name = (UnitName and UnitName("player")) or "Unknown"
    local realm = (GetRealmName and GetRealmName()) or ""
    if realm ~= "" then
        return name .. " - " .. realm
    end
    return name
end

-- Load/refresh the active profile table (merges any new defaults into it)
function DH:LoadProfile(name)
    local root = self.dbRoot
    if not root then return nil end

    if not root.profiles[name] then
        root.profiles[name] = {}
    end

    self.db = MergeDefaults(root.profiles[name], BuildDefaults(), true)
    root.profiles[name] = self.db
    self.currentProfile = name
    root.profileKeys[self.profileKey] = name

    self:ApplyProfileDefaults()
    return self.db
end

-- Make sure the profile has a valid rotation mode selected
function DH:ApplyProfileDefaults()
    if not self.db then return end
    local modes = ns.registered.modes
    if not modes or #modes == 0 then return end

    local valid = false
    for _, mode in ipairs(modes) do
        if mode.key == self.db.mode then
            valid = true
            break
        end
    end
    if not valid then
        self.db.mode = modes[1].key
    end
end

-- Sorted list of profile names
function DH:GetProfileNames()
    local names = {}
    if self.dbRoot then
        for name in pairs(self.dbRoot.profiles) do
            if type(name) == "string" then names[#names + 1] = name end
        end
    end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

function DH:GetCurrentProfileName()
    return self.currentProfile or "Default"
end

-- Create a new profile. copyFrom = name to clone, or false for bare defaults
function DH:CreateProfile(name, copyFrom)
    if type(name) ~= "string" then return nil, "Enter a profile name" end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return nil, "Enter a profile name" end

    local root = self.dbRoot
    if not root then return nil, "Database not ready" end
    if root.profiles[name] then return nil, "Profile already exists" end

    local source = {}
    if copyFrom ~= false then
        local from = (type(copyFrom) == "string" and root.profiles[copyFrom]) or root.profiles[self:GetCurrentProfileName()]
        if from then
            source = DeepCopy(from)
        end
    end
    root.profiles[name] = MergeDefaults(source, BuildDefaults(), true)
    return name
end

-- Apply decoded profile data from an import.
-- mode = "replace" writes over the current profile, "new" makes a fresh one.
function DH:ImportProfile(data, mode, name)
    if type(data) ~= "table" then return nil, "Invalid profile data" end
    local root = self.dbRoot
    if not root then return nil, "Database not ready" end

    if mode == "new" then
        name = (type(name) == "string" and name:gsub("^%s+", ""):gsub("%s+$", "")) or ""
        if name == "" then name = "Imported" end
        local base = name
        local i = 2
        while root.profiles[name] do
            name = base .. " " .. i
            i = i + 1
        end
        root.profiles[name] = MergeDefaults(data, BuildDefaults(), true)
        self:LoadProfile(name)
        self:RefreshAfterProfileChange()
        return name
    end

    name = name or self:GetCurrentProfileName()
    root.profiles[name] = MergeDefaults(data, BuildDefaults(), true)
    self:LoadProfile(name)
    self:RefreshAfterProfileChange()
    return name
end

-- Copy one profile's settings over another profile
function DH:CopyProfile(fromName, toName)
    local root = self.dbRoot
    if not root or not root.profiles[fromName] then return false, "Source profile not found" end
    if fromName == toName then return false, "Same profile" end

    root.profiles[toName] = MergeDefaults(DeepCopy(root.profiles[fromName]), BuildDefaults(), true)
    if toName == self.currentProfile then
        self.db = root.profiles[toName]
        self:ApplyProfileDefaults()
        self:RefreshAfterProfileChange()
    end
    return true
end

-- ============================================================================
-- PHASE 3.2: PROFILE IMPORT / EXPORT
-- Plain-text serialization with a safe table-literal parser (no loadstring).
-- ============================================================================

local function IsIdentifier(k)
    return type(k) == "string" and k:match("^[%a_][%w_]*$") ~= nil
end

local function SerializeValue(v, indent, seen)
    local t = type(v)
    if t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "0" end
        return tostring(v)
    elseif t == "boolean" then
        return v and "true" or "false"
    elseif t == "string" then
        return string.format("%q", v)
    elseif t == "table" then
        if seen[v] then return "nil" end
        seen[v] = true
        local pad = string.rep("  ", indent)
        local pad2 = string.rep("  ", indent + 1)

        local n = #v
        local isArray = true
        for k in pairs(v) do
            if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then
                isArray = false
                break
            end
        end

        local parts = {}
        if isArray and n > 0 then
            for i = 1, n do
                parts[#parts + 1] = pad2 .. SerializeValue(v[i], indent + 1, seen)
            end
        else
            local keys = {}
            for k in pairs(v) do keys[#keys + 1] = k end
            table.sort(keys, function(a, b)
                if type(a) == type(b) then return tostring(a) < tostring(b) end
                return type(a) == "string"
            end)
            for _, k in ipairs(keys) do
                local val = v[k]
                local vt = type(val)
                if vt == "number" or vt == "string" or vt == "boolean" or vt == "table" then
                    local key
                    if IsIdentifier(k) then
                        key = k
                    elseif type(k) == "string" then
                        key = "[" .. string.format("%q", k) .. "]"
                    elseif type(k) == "number" then
                        key = "[" .. tostring(k) .. "]"
                    end
                    if key then
                        parts[#parts + 1] = pad2 .. key .. " = " .. SerializeValue(val, indent + 1, seen)
                    end
                end
            end
        end

        seen[v] = nil
        if #parts == 0 then return "{}" end
        return "{\n" .. table.concat(parts, ",\n") .. ",\n" .. pad .. "}"
    end
    return "nil"
end

-- Serialize the active (or named) profile to a portable text blob
function DH:EncodeProfile(name)
    name = name or self:GetCurrentProfileName()
    local root = self.dbRoot
    if not root or not root.profiles[name] then
        return nil, "Profile not found"
    end
    local body = SerializeValue(root.profiles[name], 0, {})
    local stamp = "?"
    if type(date) == "function" then
        stamp = date("%Y-%m-%d %H:%M:%S")
    end
    local lines = {
        "-- RotationCore Profile Export",
        "-- Version: " .. tostring(self.Version or "?"),
        "-- Date: " .. stamp,
        "-- Profile: " .. name,
        "return " .. body,
    }
    return table.concat(lines, "\n")
end

local function DecodeParse(str)
    local pos = 1
    local len = #str

    local function skip()
        while pos <= len do
            local c = str:sub(pos, pos)
            if c == " " or c == "\t" or c == "\n" or c == "\r" then
                pos = pos + 1
            elseif c == "-" and str:sub(pos + 1, pos + 1) == "-" then
                local nl = str:find("\n", pos, true)
                if nl then pos = nl + 1 else pos = len + 1 end
            else
                break
            end
        end
    end

    local parseValue

    local function parseString()
        local quote = str:sub(pos, pos)
        pos = pos + 1
        local out = {}
        while pos <= len do
            local c = str:sub(pos, pos)
            if c == "\\" then
                local n = str:sub(pos + 1, pos + 1)
                if n == "n" then out[#out + 1] = "\n"
                elseif n == "t" then out[#out + 1] = "\t"
                elseif n == "r" then out[#out + 1] = "\r"
                elseif n == "a" then out[#out + 1] = "\a"
                elseif n == "b" then out[#out + 1] = "\b"
                elseif n == "f" then out[#out + 1] = "\f"
                elseif n == "v" then out[#out + 1] = "\v"
                elseif n == "\\" then out[#out + 1] = "\\"
                elseif n == '"' then out[#out + 1] = '"'
                elseif n == "'" then out[#out + 1] = "'"
                elseif n == "\n" then out[#out + 1] = "\n"
                elseif n:match("%d") then
                    local num = n
                    for _ = 1, 2 do
                        local d = str:sub(pos + 1 + #num, pos + 1 + #num)
                        if d:match("%d") then num = num .. d else break end
                    end
                    out[#out + 1] = string.char(tonumber(num) or 63)
                    pos = pos + #num - 1
                else
                    out[#out + 1] = n
                end
                pos = pos + 2
            elseif c == quote then
                pos = pos + 1
                return table.concat(out)
            else
                out[#out + 1] = c
                pos = pos + 1
            end
        end
        error("unterminated string")
    end

    local function parseTable()
        pos = pos + 1 -- consume "{"
        local t = {}
        while true do
            skip()
            local c = str:sub(pos, pos)
            if c == "}" then
                pos = pos + 1
                break
            elseif c == "" then
                error("unterminated table")
            elseif c == "," or c == ";" then
                pos = pos + 1
            elseif c == "[" then
                pos = pos + 1
                local key = parseValue()
                skip()
                if str:sub(pos, pos) ~= "]" then error("expected ]") end
                pos = pos + 1
                skip()
                if str:sub(pos, pos) ~= "=" then error("expected =") end
                pos = pos + 1
                t[key] = parseValue()
            else
                local save = pos
                local name = str:match("^([%a_][%w_]*)", pos)
                if name then
                    local p = pos + #name
                    while p <= len and str:sub(p, p):match("%s") do p = p + 1 end
                    if str:sub(p, p) == "=" then
                        pos = p + 1
                        t[name] = parseValue()
                    else
                        pos = save
                        t[#t + 1] = parseValue()
                    end
                else
                    t[#t + 1] = parseValue()
                end
            end
        end
        return t
    end

    parseValue = function()
        skip()
        local c = str:sub(pos, pos)
        if c == "{" then return parseTable() end
        if c == '"' or c == "'" then return parseString() end
        local rest = str:sub(pos)
        local num = rest:match("^%-?%d+%.?%d*[eE]?[%-+]?%d*")
        if num and num:match("^%-?%d") then
            pos = pos + #num
            return tonumber(num)
        end
        if rest:match("^true") then pos = pos + 4 return true end
        if rest:match("^false") then pos = pos + 5 return false end
        if rest:match("^nil") then pos = pos + 3 return nil end
        error("unexpected token at " .. pos)
    end

    skip()
    if str:sub(pos, pos + 5) == "return" then
        pos = pos + 6
    end
    return parseValue()
end

-- Parse a text blob into a profile table (never executes input as code)
function DH:DecodeProfile(str)
    if type(str) ~= "string" then return nil, "Empty input" end
    str = str:gsub("^\239\187\191", "") -- strip UTF-8 BOM
    if str:match("^%s*$") then return nil, "Empty input" end

    local ok, result = pcall(DecodeParse, str)
    if not ok then
        return nil, "Parse error: " .. tostring(result)
    end
    if type(result) ~= "table" then
        return nil, "Not a profile table"
    end
    return result
end

-- Delete a profile (never the last one left)
function DH:DeleteProfile(name)
    local root = self.dbRoot
    if not root or not root.profiles[name] then return false, "Profile not found" end

    local count = 0
    for _ in pairs(root.profiles) do count = count + 1 end
    if count <= 1 then return false, "Cannot delete the last profile" end

    root.profiles[name] = nil

    -- Any character pointing at the deleted profile falls back to a live one:
    -- prefer "Default", otherwise any remaining profile.
    local fallback = root.profiles["Default"] and "Default" or nil
    if not fallback then
        fallback = next(root.profiles)
    end
    for key, profile in pairs(root.profileKeys) do
        if profile == name then
            root.profileKeys[key] = fallback
        end
    end

    if self.currentProfile == name then
        self:LoadProfile(fallback)
        self:RefreshAfterProfileChange()
    end
    return true
end

-- Switch to another profile
function DH:SetProfile(name)
    if type(name) ~= "string" or name == "" then return false end
    local root = self.dbRoot
    if not root then return false end

    if not root.profiles[name] then
        root.profiles[name] = {}
    end

    self:LoadProfile(name)
    self:RefreshAfterProfileChange()
    self:Print(L("Profile: ") .. name)
    return true
end

-- Reset the current profile back to defaults
function DH:ResetProfile(name)
    local root = self.dbRoot
    name = name or self:GetCurrentProfileName()
    if not root or not root.profiles[name] then return false end

    root.profiles[name] = {}
    if name == self.currentProfile then
        self:LoadProfile(name)
    end
    self:RefreshAfterProfileChange()
    return true
end

-- Let the config/UI layers react to a profile switch
function DH:RefreshAfterProfileChange()
    if self.RefreshConfig then
        self:RefreshConfig()
    end
    if self.UpdateRecommendations then
        self:UpdateRecommendations()
    end
end

-- Debug print (console when debug mode is on).
function DH:Debug(msg, ...)
    local text = string.format(msg, ...)
    if self.db and self.db.debug then
        print("|cFF00FF00RotationCore:|r " .. text)
    end
end

-- Print message
function DH:Print(msg)
    print("|cFF00FF00RotationCore:|r " .. msg)
end

-- ============================================================================
-- EVENT HANDLING
-- ============================================================================

-- Main event frame
local eventFrame = CreateFrame("Frame", "RotationCoreEventFrame", UIParent)
eventFrame:Hide()

-- ----------------------------------------------------------------------------
-- Update scheduling.
--
-- Heavy state groups are event-driven and cached (see DH:MarkStateDirty), so the
-- frame poll is only a *fallback*. Two modes (setting: update_mode):
--   "events" (default): OnUpdate runs only while it matters (in combat or with a
--           target) at PollInterval(), and is removed entirely while idle so the
--           addon costs nothing out of combat. Game events request an update via
--           DH:RequestUpdate(), throttled to UPDATE_THROTTLE so a burst of many
--           events still yields a single update.
--   "poll": legacy fixed-rate polling at poll_frequency Hz, always running.
-- ----------------------------------------------------------------------------
local updateElapsed = 0
local UPDATE_THROTTLE = 0.1       -- min seconds between event-driven updates
local lastUpdateAt = 0
local pendingUpdate = false
local updateLoopActive = false

local function PollInterval()
    local hz = tonumber(DH.GetSetting and DH:GetSetting("poll_frequency")) or 5
    if hz < 1 then hz = 1 elseif hz > 30 then hz = 30 end
    return 1 / hz
end

local function RunUpdate()
    lastUpdateAt = GetTime()
    pendingUpdate = false
    DH:UpdateRecommendations()
    -- Run class-specific glow updater if registered. Guarded so a class module
    -- error cannot break the update loop for other classes / the core UI.
    if ns.registered.glowUpdater then
        local ok, err = pcall(ns.registered.glowUpdater)
        if not ok and ns.AddError then
            ns.AddError("glowUpdater failed: " .. tostring(err))
        end
    end
end

local function TickBody(elapsed)
    updateElapsed = updateElapsed + elapsed
    -- Flush a coalesced event request as soon as the throttle window allows.
    if pendingUpdate then
        if updateElapsed >= UPDATE_THROTTLE then
            updateElapsed = 0
            RunUpdate()
            if DH.SyncUpdateLoop then DH:SyncUpdateLoop() end
        end
        return
    end
    if updateElapsed >= PollInterval() then
        updateElapsed = 0
        RunUpdate()
    end
end

local function OnUpdateTick(_, elapsed)
    local ok, err = pcall(TickBody, elapsed)
    if not ok then
        -- Stop the loop so a persistent error cannot spam the error handler
        -- every frame; a later event can reinstall it via SyncUpdateLoop.
        if eventFrame then eventFrame:SetScript("OnUpdate", nil) end
        updateLoopActive = false
        pendingUpdate = false
        if ns.AddError then
            ns.AddError("Update loop stopped after error: " .. tostring(err))
        end
    end
end

-- Install/remove the fallback poll depending on mode and activity.
function DH:SyncUpdateLoop()
    local enabled = DH.db and DH.db.enabled ~= false
    -- Zero-impact: the scheduler is always event-driven (idle out of combat).
    local mode = "events"
    local want
    if not enabled then
        want = false
    elseif mode == "poll" then
        want = true
    else
        want = ns.inCombat or pendingUpdate or UnitExists("target")
            or (ns.IsTestGlow and ns.IsTestGlow())
    end
    if want and not updateLoopActive then
        updateElapsed = 0
        eventFrame:SetScript("OnUpdate", OnUpdateTick)
        updateLoopActive = true
    elseif not want and updateLoopActive then
        eventFrame:SetScript("OnUpdate", nil)
        updateLoopActive = false
    end
end

-- Status tab: is the update loop currently installed?
function DH:IsUpdateActive()
    return updateLoopActive
end

-- Event-driven update request. Coalesces bursts and never runs more often than
-- UPDATE_THROTTLE. force=true bypasses the throttle (user-initiated changes).
function DH:RequestUpdate(force)
    local now = GetTime()
    if force or (now - lastUpdateAt) >= UPDATE_THROTTLE then
        RunUpdate()
        return
    end
    pendingUpdate = true
    if not updateLoopActive then
        DH:SyncUpdateLoop()
    end
end

-- Run a function once on the next frame. 3.3.5a has no C_Timer, so a throwaway
-- frame's one-shot OnUpdate provides the deferral (used to read talent data
-- after the talent event has fully resolved).
local deferFrame
local deferQueue = {}
local function DeferNextFrame(fn)
    if type(fn) ~= "function" then return end
    deferQueue[#deferQueue + 1] = fn
    if not deferFrame then
        deferFrame = CreateFrame("Frame")
        deferFrame:Show()   -- OnUpdate only fires on a shown frame
    end
    deferFrame:SetScript("OnUpdate", function(self)
        self:SetScript("OnUpdate", nil)
        local queue = deferQueue
        deferQueue = {}
        for i = 1, #queue do
            local ok, err = pcall(queue[i])
            if not ok and ns.AddError then
                ns.AddError("Deferred task failed: " .. tostring(err))
            end
        end
    end)
end

-- Event handler
local function DispatchEvent(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == "RotationCore" then
            DH:OnInitialize()
            DH:OnEnable()
        elseif name == "DBM-Core" or name == "DBM" or name == "BigWigs" or name == "BigWigs_Core" then
            -- Boss mod loaded after us: (re)register the timeline callbacks.
            if ns.InitTimeline then ns.InitTimeline() end
        end
    elseif event == "PLAYER_LOGIN" then
        -- Rotation module (LoadOnDemand) + build from talents
        DH:MarkStateDirty("all")
        DH:LoadClassModule()
        DH:AutoDetectMode()
        DH:MaybeShowFirstRunWizard()
    elseif event == "PLAYER_TALENT_UPDATE" or event == "ACTIVE_TALENT_GROUP_CHANGED" then
        -- Talents changed: always drop the stale caches (cheap, safe), then
        -- rebuild the rotation - optionally deferred to the next frame so we
        -- never read talent data mid-event.
        DH:MarkStateDirty("talents")
        DH:InvalidateKnownSpells()
        if DH:GetSetting("auto_reload_on_talent_change") ~= false then
            DeferNextFrame(function() DH:ReloadRotation() end)
        else
            DH:AutoDetectMode()
            DH:NotifyOptions()
        end
    elseif event == "SPELLS_CHANGED" or event == "PLAYER_LEVEL_UP" then
        -- New spells learned: the "known abilities" cache is stale
        DH:MarkStateDirty("talents")
        DH:MarkStateDirty("glyphs")
        DH:InvalidateKnownSpells()
    elseif event == "GLYPH_ADDED" or event == "GLYPH_REMOVED" or event == "GLYPH_UPDATED" then
        DH:MarkStateDirty("glyphs")
        DH:RequestUpdate()
    elseif event == "PLAYER_REGEN_DISABLED" then
        ns.inCombat = true
        ns.combatStart = GetTime()
        DH:MarkStateDirty("auras")
        -- Prompt 2: start a fight for analytics even outside a boss encounter
        -- (training dummy), unless an encounter already started one.
        if not ns.fight.active then DH:StartFight() end
        DH:ShowUI()
        DH:SyncUpdateLoop()
    elseif event == "PLAYER_REGEN_ENABLED" then
        ns.inCombat = false
        DH:MarkStateDirty("auras")
        -- Prompt 2: finalize the fight and (optionally) print the report.
        DH:EndFight()
        if DH.HandleBossCombatEnd then DH:HandleBossCombatEnd() end
        if not UnitExists("target") then
            DH:HideUI()
        end
        DH:SyncUpdateLoop()
    elseif event == "PLAYER_DEAD" then
        ns.playerDead = true
        DH:MarkStateDirty("auras")
        if ns.ClearGlows then ns.ClearGlows() end
        if ns.HideAllWindows then
            ns.HideAllWindows()
        elseif ns.HideUI then
            ns.HideUI()
        end
        DH:SyncUpdateLoop()
    elseif event == "PLAYER_ALIVE" then
        ns.playerDead = false
        DH:MarkStateDirty("auras")
        DH:RequestUpdate(true)
        DH:SyncUpdateLoop()
    elseif event == "ENCOUNTER_START" then
        local encounterID, encounterName = ...
        DH:OnEncounterStart(encounterID, encounterName)
    elseif event == "ENCOUNTER_END" then
        local encounterID, encounterName, difficultyID, raidSize, endStatus = ...
        DH:OnEncounterEnd(encounterID, encounterName, difficultyID, raidSize, endStatus)
    elseif event == "UNIT_AURA" then
        local unit = ...
        if unit == "player" or unit == "target" then
            DH:MarkStateDirty("auras")
            DH:RequestUpdate()
        end
    elseif event == "UNIT_MANA" or event == "UNIT_RAGE" or event == "UNIT_ENERGY"
        or event == "UNIT_FOCUS" or event == "UNIT_RUNIC_POWER" then
        -- 3.3.5a fires per-resource events (UNIT_POWER is 4.0+)
        local unit = ...
        if unit == "player" then
            DH:MarkStateDirty("resources")
            DH:RequestUpdate()
        end
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        DH:MarkStateDirty("cooldowns")
        DH:RequestUpdate()
    elseif event == "PLAYER_STATS" or event == "COMBAT_RATING_UPDATE"
        or event == "PLAYER_EQUIPMENT_CHANGED" or event == "UNIT_INVENTORY_CHANGED" then
        local unit = ...
        if event ~= "UNIT_INVENTORY_CHANGED" or unit == "player" then
            DH:MarkStateDirty("stats")
            -- phase-3 #1: equipment changes invalidate the cached item level.
            if event == "PLAYER_EQUIPMENT_CHANGED" and DH.State
               and DH.State.InvalidateItemLevel then
                DH.State:InvalidateItemLevel()
            end
            DH:RequestUpdate()
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        if DH.HandleBossTarget then DH:HandleBossTarget() end
        DH:MarkStateDirty("auras")
        DH:MarkStateDirty("cooldowns")
        if DH.State and DH.State.ForceEnemyScan then DH.State:ForceEnemyScan() end
        DH:RequestUpdate()
        DH:SyncUpdateLoop()
        if UnitExists("target") and UnitCanAttack("player", "target") then
            DH:ShowUI()
        elseif not ns.inCombat then
            DH:HideUI()
        end
    elseif event == "UPDATE_SHAPESHIFT_FORM" then
        DH:MarkStateDirty("auras")
        DH:RequestUpdate()
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        DH:OnCombatLogEvent(...)
    end
end

-- Every event runs through pcall so a single malformed payload cannot abort the
-- handler (and, for ADDON_LOADED, leave the addon half-initialised).
local function OnEvent(self, event, ...)
    local ok, err = pcall(DispatchEvent, self, event, ...)
    if not ok and ns.AddError then
        ns.AddError("Event " .. tostring(event) .. " failed: " .. tostring(err))
    end
end

eventFrame:SetScript("OnEvent", OnEvent)
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_STATS")
eventFrame:RegisterEvent("COMBAT_RATING_UPDATE")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
eventFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")

-- ============================================================================
-- ENABLE / DISABLE
-- ============================================================================

function DH:SetEnabled(enabled)
    if not self.db then return false end
    enabled = enabled and true or false
    if self.db.enabled == enabled then return true end

    self.db.enabled = enabled
    if enabled then
        eventFrame:Show()
        self:ShowUI()
        self:UpdateUI()
    else
        ns.recommendations = {}
        eventFrame:Hide()
        self:HideUI()
        -- Hide every on-screen display, not just the glows
        if ns.HideSpellFrame then ns.HideSpellFrame() end
        if ns.UpdateCooldownsFrame then ns.UpdateCooldownsFrame() end
        if ns.UpdateInterruptsFrame then ns.UpdateInterruptsFrame() end
        if ns.UpdateTimelineFrame then ns.UpdateTimelineFrame() end
        if ns.UpdateDebugFrame then ns.UpdateDebugFrame() end
    end

    -- Enabling/disabling changes whether the poll loop should run.
    self:SyncUpdateLoop()

    if self.RefreshOptions then
        self:RefreshOptions()
    end
    return true
end

-- Tell the options window a setting changed (no-op when it is closed)
function DH:NotifyOptions()
    if self.RefreshOptions then
        self:RefreshOptions()
    end
end

-- ============================================================================
-- ROTATION MODE / BUILD SELECTION
-- Class modules register one mode per build (arcane, fire, frost_mage, ...).
-- With auto_mode the build follows the player's talents automatically.
-- ============================================================================

local function CommonPrefixLen(a, b)
    local n = math.min(#a, #b)
    for i = 1, n do
        if a:byte(i) ~= b:byte(i) then
            return i - 1
        end
    end
    return n
end

-- Map a spec detector result ("frost", "retribution", "protection") onto a
-- registered mode key ("frost_mage", "ret", "prot_warrior", ...).
-- "Safe" (healer) modes are matched before their DPS-borrow variants so that
-- e.g. "holy" resolves to "holy_paladin" (not "holy_paladin_dps"); the core
-- then borrows the DPS rotation from the safe mode only when heal_dps_mode
-- allows it (see GetHealDpsMode). Matching a DPS key directly would bypass
-- that gate and run a DPS rotation for grouped healers.
function DH:MatchModeKey(spec)
    if type(spec) ~= "string" or spec == "" then return nil end
    local modes = ns.registered.modes

    local function match(group)
        for _, mode in ipairs(group) do
            if mode.key == spec then return mode.key end
        end
        for _, mode in ipairs(group) do
            local mk = mode.key
            if mk:sub(1, #spec) == spec or spec:sub(1, #mk) == mk then
                return mk
            end
        end
        for _, mode in ipairs(group) do
            if CommonPrefixLen(spec, mode.key) >= 4 then
                return mode.key
            end
        end
        return nil
    end

    local safeModes, otherModes = {}, {}
    for _, mode in ipairs(modes) do
        if mode.safe then
            safeModes[#safeModes + 1] = mode
        else
            otherModes[#otherModes + 1] = mode
        end
    end

    return match(safeModes) or match(otherModes)
end

-- Apply a rotation mode (updates db, minimap icon, recommendations)
function DH:ApplyMode(modeKey)
    if not self.db then return false end

    local found
    for _, mode in ipairs(ns.registered.modes) do
        if mode.key == modeKey then
            found = mode
            break
        end
    end
    if not found then return false end

    self.db.mode = modeKey

    -- Drop the smoothing lock so the new mode's rotation is not stuck behind
    -- an old locked slot (provided by Config.lua).
    if ns.ResetSmoothing then ns.ResetSmoothing() end

    -- Inform once when a safe (unimplemented) mode becomes active - but stay
    -- quiet when heal-spec DPS is enabled (the borrowed rotation is intended).
    local healDps = self.GetHealDpsMode and self:GetHealDpsMode(found)
    if found.safe then
        if found.message and ns._safeModeKey ~= modeKey and not healDps then
            ns._safeModeKey = modeKey
            DH:Print(L(found.message))
        end
    else
        ns._safeModeKey = nil
    end

    if ns.MinimapButton and ns.MinimapButton.icon and found.icon then
        ns.MinimapButton.icon:SetTexture(found.icon)
    end
    if self.UpdateRecommendations then
        self:UpdateRecommendations()
    end
    if self.RefreshOptions then
        self:RefreshOptions()
    end
    return true
end

-- Manual selection: the choice is remembered and auto-detection stops
function DH:SetMode(modeKey)
    if not self:ApplyMode(modeKey) then return false end
    self.db.auto_mode = false
    return true
end

-- Follow the talents (only while auto_mode is on)
function DH:AutoDetectMode()
    if not self.db then return nil end
    local spec = self:GetActiveSpec()
    local key = self:MatchModeKey(spec)
    if not self.db.auto_mode then
        -- Warn once if the manual rotation does not match the detected talents.
        if key and self.db.mode and key ~= self.db.mode then
            local sig = tostring(self.db.mode) .. "|" .. tostring(key)
            if ns._warnedMismatch ~= sig then
                ns._warnedMismatch = sig
                self:Print(string.format(L("Build may not match your talents: rotation '%s' vs detected '%s'."),
                    tostring(self.db.mode), tostring(key)))
            end
        end
        return key
    end

    -- Fallback: the detected spec has no registered mode - use the first mode
    -- so the player still gets a rotation instead of "Rec: none", and warn.
    if not key then
        local modes = ns.registered.modes
        if modes and modes[1] then
            key = modes[1].key
            if spec ~= ns._warnedSpec then
                ns._warnedSpec = spec
                DH:Print(L("Unknown spec (") .. tostring(spec)
                    .. L("), using ") .. tostring(modes[1].name or modes[1].key))
            end
        end
    end
    if key and key ~= self.db.mode then
        self:ApplyMode(key)
    end
    return key
end

-- ============================================================================
-- CLASS MODULES
-- The rotation modules are separate addons (RotationCore_Mage, ...) that
-- the user can switch in the addon list. They are LoadOnDemand and the core
-- loads the module matching the player's class at login.
-- ============================================================================

local CLASS_MODULES = {
    DRUID = "RotationCore_Druid",
    PALADIN = "RotationCore_Paladin",
    WARLOCK = "RotationCore_Warlock",
    SHAMAN = "RotationCore_Shaman",
    WARRIOR = "RotationCore_Warrior",
    HUNTER = "RotationCore_Hunter",
    DEATHKNIGHT = "RotationCore_DeathKnight",
    ROGUE = "RotationCore_Rogue",
    MAGE = "RotationCore_Mage",
    PRIEST = "RotationCore_Priest",
}

function DH:GetClassModuleName()
    return CLASS_MODULES[self.playerClass]
end

-- Load the rotation module for the player's class (LoadOnDemand addon)
function DH:LoadClassModule()
    local name = self:GetClassModuleName()
    if not name then return false end
    if IsAddOnLoaded and IsAddOnLoaded(name) then return true end

    local loaded, reason = LoadAddOn(name)
    if loaded then
        self:Print(L("Loaded ") .. name)
        self:ApplyModuleDefaults()
        return true
    end

    if reason == "DISABLED" then
        self:Print(name .. L(" is disabled - enable it in the addon list (/addons)"))
    else
        self:Print(L("Could not load ") .. name .. " (" .. tostring(reason) .. ")")
    end
    return false
end

-- Class module files run AFTER the core finished initializing, so their
-- registrations (defaults, modes, cooldowns) have to be merged in afterwards.
function DH:ApplyModuleDefaults()
    if not self.db then return end

    -- Buff/debuff/cooldown tables for the newly registered class data
    if self.State and self.State.Init then
        self.State:Init()
    end

    -- New class defaults into the active profile
    MergeDefaults(self.db, BuildDefaults(), true)
    self:ApplyProfileDefaults()

    if self.RefreshConfig then
        self:RefreshConfig()
    end
    if self.UpdateRecommendations then
        self:UpdateRecommendations()
    end
end

-- Initialize addon (runs on ADDON_LOADED - saved variables ARE available here).
-- The body is run through pcall so a corrupt saved-variable file degrades to a
-- fresh profile instead of bricking the whole session.
local function DoInitialize(self)
    -- Saved variables are loaded by the client between file load and
    -- ADDON_LOADED, so this is the first safe place to read them.

    RotationCoreDB = MigrateSaved(RotationCoreDB)
    self.dbRoot = RotationCoreDB
    self.profileKey = GetProfileKey()

    local activeProfile = RotationCoreDB.profileKeys[self.profileKey] or "Default"
    if not RotationCoreDB.profiles[activeProfile] then
        activeProfile = "Default"
    end
    self:LoadProfile(activeProfile)

    -- Error log has its own file: append what was saved last session and point
    -- the SavedVariable at our (now merged) live table.
    if type(RotationCoreErrors) == "table" then
        for _, e in ipairs(RotationCoreErrors) do
            if type(e) == "table" and type(e.msg) == "string" then
                ns.errorLog[#ns.errorLog + 1] = { msg = e.msg, count = tonumber(e.count) or 1 }
            end
        end
        -- Keep only the most recent entries if the saved file is bloated.
        while #ns.errorLog > ns.MAX_ERRORS do
            table.remove(ns.errorLog, 1)
        end
    end
    RotationCoreErrors = ns.errorLog


    -- Register slash commands
    -- Main short alias for the new addon name
    SLASH_ROTATIONCORE1 = "/rc"
    -- Fallback: the old command is kept for compatibility
    SLASH_ROTATIONCORE2 = "/ph"
    -- Full command
    SLASH_ROTATIONCORE3 = "/rotationcore"
    SlashCmdList["ROTATIONCORE"] = function(msg)
        DH:SlashCommand(msg)
    end

    -- Config.lua / Options.lua register their own hooks
    if self.ConfigOnInit then
        self:ConfigOnInit()
    end

    -- Prompt 3.3: wire DBM / BigWigs timelines if the addons are present.
    if ns.InitTimeline then ns.InitTimeline() end

    self:Print("v" .. self.Version .. L(" loaded. Profile: ") .. self:GetCurrentProfileName() .. L(". Type /rc for options."))
end

function DH:OnInitialize()
    if self._initialized then return end
    local ok, err = pcall(DoInitialize, self)
    -- Mark initialised only after the attempt, so a thrown error still leaves a
    -- usable (fresh) database for this session rather than a half-dead addon.
    self._initialized = true
    if not ok then
        if ns.AddError then ns.AddError("OnInitialize failed: " .. tostring(err)) end
        if type(self.dbRoot) ~= "table" then
            RotationCoreDB = MigrateSaved(nil)
            self.dbRoot = RotationCoreDB
            self.profileKey = GetProfileKey()
            pcall(function() self:LoadProfile("Default") end)
        end
    end
end

-- Run the setup wizard once, the very first time this profile is used.
-- Answers are written straight into the current profile (ApplyAnswers).
function DH:MaybeShowFirstRunWizard()
    if not self.db then return end
    if self.db.wizardShown then return end
    self.db.wizardShown = true
    if not (ns.Wizard and ns.Wizard.Show) then return end

    -- Delay ~1s so the class module, modes and UI are ready first.
    local f = CreateFrame("Frame")
    self._wizardTimer = f
    local elapsedTotal = 0
    f:SetScript("OnUpdate", function(_, elapsed)
        elapsedTotal = elapsedTotal + elapsed
        if elapsedTotal >= 1 then
            f:SetScript("OnUpdate", nil)
            f:Hide()
            DH._wizardTimer = nil
            ns.Wizard.Show()
        end
    end)
    f:Show()
end

-- Enable addon
function DH:OnEnable()
    if self._enabled then return end
    self._enabled = true

    -- Enabled by default: only an explicit /rc toggle turns it off.
    if self.db and self.db.enabled == nil then
        self.db.enabled = true
    end

    -- Register events
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_DEAD")
    eventFrame:RegisterEvent("PLAYER_ALIVE")
    eventFrame:RegisterEvent("UNIT_AURA")
    -- Power changes (3.3.5a: one event per resource; UNIT_POWER is 4.0+)
    eventFrame:RegisterEvent("UNIT_MANA")
    eventFrame:RegisterEvent("UNIT_RAGE")
    eventFrame:RegisterEvent("UNIT_ENERGY")
    eventFrame:RegisterEvent("UNIT_FOCUS")
    eventFrame:RegisterEvent("UNIT_RUNIC_POWER")
    eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")

    eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

    -- Learned spells / build detection
    eventFrame:RegisterEvent("SPELLS_CHANGED")
    eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
    eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
    eventFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")

    -- Glyph changes (3.3.5a)
    eventFrame:RegisterEvent("GLYPH_ADDED")
    eventFrame:RegisterEvent("GLYPH_REMOVED")
    eventFrame:RegisterEvent("GLYPH_UPDATED")

    -- Prompt 2: boss encounters drive boss profiles + fight analytics
    eventFrame:RegisterEvent("ENCOUNTER_START")
    eventFrame:RegisterEvent("ENCOUNTER_END")

    -- Initialize state
    if self.State and self.State.Init then
        self.State:Init()
    end

    -- Create UI
    self:InitializeUI()

    -- Event frame must stay shown so events keep arriving; the OnUpdate poll is
    -- installed separately by SyncUpdateLoop() based on mode/combat/target.
    if not self.db or self.db.enabled then
        eventFrame:Show()
    else
        eventFrame:Hide()
    end
    self:SyncUpdateLoop()

    -- Config.lua / Options.lua finish their setup (minimap button, ...)
    if self.ConfigOnEnable then
        self:ConfigOnEnable()
    end
end

-- ============================================================================
-- SLASH COMMANDS
-- ============================================================================

-- Registered slash command handlers from class modules
ns.slashCommands = {}

function DH:RegisterSlashCommand(cmd, handler, helpText)
    ns.slashCommands[cmd] = { handler = handler, help = helpText }
end

function DH:SlashCommand(input)
    local cmd = string.lower(input or "")

    if cmd == "debug spec" then
        local primary = ns.registered.specDetector and ns.registered.specDetector() or "nil"
        local fallback = ns.registered.specDetectorFallback and ns.registered.specDetectorFallback() or "nil"
        self:Print(L("Debug spec:") .. " active=" .. tostring(self:GetActiveSpec() or "nil") .. " primary=" .. tostring(primary) .. " fallback=" .. tostring(fallback))
    elseif cmd == "debug" then
        self.db.debug = not self.db.debug
        self:Print(L("Debug mode: ") .. (self.db.debug and L("ON") or L("OFF")))
    elseif cmd == "toggle" then
        local newState = not self.db.enabled
        self:SetEnabled(newState)
        self:Print(string.format(L("RotationCore %s"), newState and L("enabled") or L("disabled")))
    elseif cmd == "options" or cmd == "menu" then
        if self.OpenOptions then
            self:OpenOptions()
        else
            self:Print(L("Options are still loading"))
        end
    elseif cmd == "close" then
        if self.CloseOptions then self:CloseOptions() end
    elseif cmd == "help full" then
        if self.OpenOptionsTab then
            self:OpenOptionsTab("wizard")
        end
    elseif cmd == "help" then
        if self.OpenOptionsTab then
            self:OpenOptionsTab("help")
        elseif self.OpenOptions then
            self:OpenOptions()
        end
    elseif string.match(cmd, "^profile ") then
        local name = string.match(cmd, "^profile%s+(.+)")
        local from, toName = string.match(cmd, "^profile%s+copy%s+(.-)%s+to%s+(.+)$")
        if from then
            local ok, err = self:CopyProfile(from, toName)
            if ok then
                self:Print(L("Profile copied: ") .. tostring(from) .. " -> " .. tostring(toName))
            else
                self:Print(L("Profile copy failed: ") .. tostring(err))
            end
        elseif name and name ~= "" then
            if self:SetProfile(name) then
                -- profile switched
            else
                self:Print(L("Profile not found: ") .. tostring(name))
            end
        else
            self:Print(L("Current profile: ") .. self:GetCurrentProfileName())
            self:Print(L("Usage: /rc profile <name> | copy <from> to <to>"))
        end
    elseif cmd == "show" then
        self:InitializeUI()
        self:ShowUI()
        self:UpdateState()
        self:UpdateRecommendations()
        self:Print(L("Action bar glow forced on"))
    elseif cmd == "test" then
        self:InitializeUI()
        if ns.ShowTestGlow then
            ns.ShowTestGlow()
        end
    elseif cmd == "test rotation" then
        self:RunRotationSelfTest()
    elseif cmd == "pause" then
        self.db.paused = not (self.db.paused == true)
        self:Print(L("Paused: ") .. (self.db.paused and L("ON") or L("OFF")))
        if self.UpdateRecommendations then self:UpdateRecommendations() end
    elseif cmd == "spec" or string.match(cmd, "^spec%s") then
        local name = string.match(cmd, "^spec%s+(.+)")
        if not name or name == "" then
            self:Print(L("Build: ") .. (self.db.auto_mode and L("auto") or tostring(self.db.mode or L("unknown"))))
            if ns.registered.modes then
                for _, m in ipairs(ns.registered.modes) do
                    self:Print("  " .. tostring(m.key) .. " - " .. L(m.name or m.key))
                end
            end
        else
            name = string.lower(name)
            local target
            for _, m in ipairs(ns.registered.modes or {}) do
                if string.lower(tostring(m.key)) == name
                   or string.lower(tostring(m.name or "")) == name then
                    target = m.key
                    break
                end
            end
            if target and self:SetMode(target) then
                self:Print(L("Build set to ") .. target)
                if self.UpdateRecommendations then self:UpdateRecommendations() end
            else
                self:Print(L("Unknown build: ") .. name)
            end
        end
    elseif cmd == "numbers" then
        self.db.display.show_numbers = not self.db.display.show_numbers
        self:Print(L("Priority numbers: ") .. (self.db.display.show_numbers and L("ON") or L("OFF")))
        self:UpdateUI()
        self:NotifyOptions()
    elseif cmd == "pulse" then
        local enabled = not (self.db.display.pulse == false)
        self.db.display.pulse = not enabled
        self:Print(L("Glow pulse: ") .. (not enabled and L("ON") or L("OFF")))
        self:UpdateUI()
        self:NotifyOptions()
    elseif cmd == "frame" then
        self.db.display.show_spellframe = not self.db.display.show_spellframe
        self:Print(L("Icon window: ") .. (self.db.display.show_spellframe and L("ON") or L("OFF")))
        self:UpdateUI()
        self:NotifyOptions()
    elseif cmd == "selfcheck" or cmd == "check" then
        if self.RunSelfCheck then self:RunSelfCheck() end
    elseif cmd == "status" then
        self:Print(L("--- Status ---"))
        self:Print(L("Addon: ") .. (self.db.enabled and L("enabled") or L("disabled")))
        self:Print(L("Class: ") .. tostring(self.playerClass))
        self:Print(L("Spec: ") .. tostring(self:GetActiveSpec()))
        if self.GetRotationComplexity then
            self:Print(L("Adaptive: ") .. tostring(self:GetRotationComplexity())
                .. " (ilvl " .. tostring(math.floor((self:GetItemLevel() or 0) + 0.5)) .. ")")
        end
        self:Print(L("Target: ") .. tostring(UnitExists("target")) .. L(", CanAttack: ") .. tostring(UnitCanAttack("player", "target")))
        self:Print(L("Recommendations: ") .. #ns.recommendations)
        self:Print(L("Profile: ") .. tostring(self:GetCurrentProfileName()))
        self:Print(L("Action buttons found: ") .. tostring(ns.GetScanCount and ns.GetScanCount() or 0))
        self:Print(L("Glow: ") .. (ns.glowVisible and L("visible") or L("hidden")))
    elseif cmd == "errors" or string.match(cmd, "^errors%s") then
        local sub = string.match(cmd, "^errors%s+(%S+)") or ""
        local log = ns.errorLog or {}
        if sub == "clear" then
            ns.errorLog = {}
            RotationCoreErrors = ns.errorLog
            self:Print(L("Error log cleared."))
        elseif sub == "file" then
            self:Print(L("Error log is saved to:"))
            self:Print("WTF/Account/<account>/SavedVariables/RotationCoreErrors.lua")
        elseif #log == 0 then
            self:Print(L("No errors recorded. /rc errors file shows where the log is saved."))
        else
            local first = math.max(1, #log - 19)
            self:Print(L("Last ") .. (#log - first + 1) .. L(" error line(s):"))
            for i = first, #log do
                local e = log[i]
                if e.count and e.count > 1 then
                    self:Print("(x" .. e.count .. ") " .. e.msg)
                else
                    self:Print(e.msg)
                end
            end
        end
    elseif cmd == "live" then
        self.db.show_debug_frame = not self.db.show_debug_frame
        self:Print(L("Live debug: ") .. (self.db.show_debug_frame and L("ON") or L("OFF")))
        if ns.DebugFrame then
            if self.db.show_debug_frame then
                ns.DebugFrame:Show()
            else
                ns.DebugFrame:Hide()
            end
        end
    elseif cmd == "wizard" then
        -- Phase 1.3: re-run the guided setup at any time
        if self.db then self.db.wizardShown = false end
        if ns.Wizard and ns.Wizard.Show then
            ns.Wizard:Show()
        else
            self:Print(L("Setup Wizard is not loaded."))
        end
    elseif cmd == "move" then
        -- Unlock every window (default state; remaining for power users)
        self:SetSetting("frames_locked", false)
        if ns.SetMoveMode then ns.SetMoveMode(true) end
        self:Print(L("Move mode: drag the boxes, then /rc lock to fix them."))
    elseif cmd == "lock" then
        self:SetSetting("frames_locked", true)
        if ns.SetMoveMode then ns.SetMoveMode(false) end
        self:Print(L("Window(s) locked."))
    elseif cmd == "config" then
        local on = not (ns.IsConfigMode and ns.IsConfigMode())
        if ns.SetConfigMode then ns.SetConfigMode(on) end
        self:Print(on and L("Panel configuration opened.") or L("Panel configuration closed."))
    elseif cmd == "train" then
        -- Post-phase 2: training mode toggle
        self:ToggleTrainingMode()
    elseif cmd == "exam" then
        -- v3.3.0 phase 2: exam mode toggle
        self:ToggleExamMode()
    elseif cmd == "mentor" then
        -- v3.3.0 phase 2: mentor mode toggle
        self:ToggleMentorMode()
    elseif cmd == "dps" then
        -- v3.3.0 phase 2: DPS forecast toggle
        local v = not (self:GetSetting("dps_forecast_enabled") == true)
        self:SetSetting("dps_forecast_enabled", v)
        self:Print(L("DPS forecast: ") .. (v and L("ON") or L("OFF")))
        if self.UpdateUI then self:UpdateUI() end
        if self.NotifyOptions then self:NotifyOptions() end
    elseif string.match(cmd, "^learning") then
        -- v3.3.0 phase 3: learning statistics
        local sub = string.match(cmd, "^learning%s+(%S+)") or ""
        if sub == "graph" then
            self:PrintLearningGraph()
        elseif sub == "clear" or sub == "reset" then
            self:ClearLearning()
        else
            self:PrintLearning()
        end
    elseif cmd == "pvp" then
        -- Post-phase 4: PvP mode toggle
        self:TogglePvPMode()
    elseif string.match(cmd, "^boss") then
        -- Prompt 2: boss profiles
        local sub = string.match(cmd, "^boss%s+(%S+)") or ""
        local arg = string.match(cmd, "^boss%s+%S+%s+(.+)")
        if sub == "list" then
            local n = 0
            for id, p in pairs(self:GetBossProfiles()) do
                n = n + 1
                self:Print("  " .. tostring(id) .. " - " .. tostring(p.name or ""))
            end
            if n == 0 then self:Print(L("No boss profiles yet.")) end
        elseif sub == "save" then
            local id = arg or (self.State and self.State.encounter_id)
            if not id then
                self:Print(L("No boss profile for this encounter."))
            else
                local data = {}
                for _, k in ipairs(ns.bossOverrideKeys) do
                    local v = self:GetSetting(k)
                    if v ~= nil then data[k] = v end
                end
                data.name = (self.State and self.State.encounter_name)
                    or tostring(id)
                self:SetBossProfile(id, data)
                self:Print(L("Boss profile saved: ") .. tostring(id))
            end
        elseif sub == "apply" then
            if not arg then
                self:Print(L("Usage: /rc boss apply <id>"))
            elseif self:ApplyBossProfile(arg) then
                self:Print(L("Boss profile applied: ") .. tostring(arg))
            else
                self:Print(L("No boss profile for this encounter."))
            end
        elseif sub == "clear" or sub == "delete" then
            if not arg then
                self:Print(L("Usage: /rc boss clear <id>"))
            else
                self:DeleteBossProfile(arg)
                self:Print(L("Boss profile removed."))
            end
        elseif sub == "export" then
            self:Print(self:ExportBossProfiles())
        elseif sub == "import" then
            if ns.ShowBossImportWindow then ns.ShowBossImportWindow() end
        elseif sub == "presets" then
            for _, g in ipairs(ns.bossPresets) do
                local names = {}
                for _, b in ipairs(g.bosses) do names[#names + 1] = b.name end
                self:Print("  " .. tostring(g.raid or g.dungeon or "?")
                    .. " (" .. tostring(g.kind or "raid") .. "): "
                    .. table.concat(names, ", "))
            end
        else
            self:Print(L("Boss profiles: /rc boss list|save [id]|apply <id>|clear <id>|export|import|presets"))
        end
    elseif string.match(cmd, "^stats") then
        -- Prompt 2: skill stats + ideal-DPS comparison (Improvements 3/4)
        local sub = string.match(cmd, "^stats%s+(%S+)") or ""
        if sub == "reset" then
            ns.skillStats = {}
            ns.lastFight = nil
            self:Print(L("Stats reset."))
        elseif sub == "dps" then
            self:PrintDPS()
        else
            self:PrintStats()
        end
    elseif string.match(cmd, "^palette") then
        -- Prompt 3.1: colour palette
        local name = string.match(cmd, "^palette%s+(%S+)") or ""
        local pal = ns.PALETTES or {}
        if name == "" then
            self:Print(L("Palette: ") .. tostring(self:GetSetting("color_palette")))
        elseif pal[name] or name == "custom" then
            self:SetSetting("color_palette", name)
            if self.UpdateUI then self:UpdateUI() end
            if self.NotifyOptions then self:NotifyOptions() end
            self:Print(L("Palette set: ") .. name)
        else
            self:Print(L("Usage: /rc palette default|protanopia|deuteranopia|tritanopia|high_contrast|custom"))
        end
    elseif string.match(cmd, "^layout") then
        -- Prompt 3.4: display layout presets
        local sub = string.match(cmd, "^layout%s+(%S+)") or ""
        if sub == "export" then
            self:Print(ns.ExportLayout and ns.ExportLayout() or "")
        elseif sub == "import" then
            if ns.ShowLayoutImportWindow then ns.ShowLayoutImportWindow() end
        elseif ns.LAYOUT_PRESETS and ns.LAYOUT_PRESETS[sub] then
            ns.ApplyLayout(sub)
            self:Print(L("Layout applied: ") .. sub)
        else
            self:Print(L("Layout: /rc layout center|side|minimal|raid|export|import"))
        end
    elseif string.match(cmd, "^timeline") then
        -- Prompt 3.3: boss timeline toggle
        local on = not (self:GetSetting("timeline_enabled") == true)
        self:SetSetting("timeline_enabled", on)
        self:Print(L("Boss timeline: ") .. (on and L("ON") or L("OFF")))
        if self.UpdateUI then self:UpdateUI() end
        if self.NotifyOptions then self:NotifyOptions() end
    elseif string.match(cmd, "^apl") then
        -- Improvement 6: custom APL management
        local sub = string.match(cmd, "^apl%s+(%S+)") or ""
        local arg = string.match(cmd, "^apl%s+%S+%s+(.+)")
        if sub == "enable" or sub == "on" then
            self:SetSetting("custom_apl_enabled", true)
            self:Print(L("Custom APL: ") .. L("ON"))
            self:UpdateUI()
            self:NotifyOptions()
        elseif sub == "disable" or sub == "off" then
            self:SetSetting("custom_apl_enabled", false)
            self:Print(L("Custom APL: ") .. L("OFF"))
            self:UpdateUI()
            self:NotifyOptions()
        elseif sub == "clear" then
            self:SetSetting("custom_apl", {})
            self:SetSetting("custom_apl_source", "")
            self:Print(L("APL cleared."))
            self:UpdateUI()
            self:NotifyOptions()
        elseif sub == "import" then
            if arg and arg ~= "" then
                local n, err = ns.SetCustomAPL(self, ns.DecodeAPLShare(arg))
                if n and n > 0 then
                    self:SetSetting("custom_apl_enabled", true)
                    self:Print(L("APL imported: ") .. n .. " " .. L("rules"))
                else
                    self:Print(L("APL error: ") .. tostring(err))
                end
                self:UpdateUI()
                self:NotifyOptions()
            elseif ns.ShowAPLImportWindow then
                ns.ShowAPLImportWindow()
            else
                self:Print(L("Usage: /rc apl import <text>"))
            end
        elseif sub == "export" then
            self:Print(ns.ExportAPL(self))
        elseif sub == "share" then
            self:Print(ns.ExportAPLShare(self))
        else
            self:Print(L("APL: /rc apl enable|disable|import [text]|export|share|clear"))
        end
    elseif string.match(cmd, "^glow ") or string.match(cmd, "^icons ") then
        local val = tonumber(string.match(cmd, "^%S+%s+(%d+)"))
        if val and val >= 1 and val <= 5 then
            self.db.display.num_icons = val
            self:Print(L("Highlighting next ") .. val .. L(" abilities"))
            self:UpdateUI()
            self:NotifyOptions()
        else
            self:Print(L("Invalid. Use /rc glow <1-5>"))
        end
    elseif string.match(cmd, "^size ") then
        local val = tonumber(string.match(cmd, "^size (.+)"))
        if val and val >= 0.8 and val <= 2.5 then
            self.db.display.glow_size = val
            self:Print(L("Glow size set to ") .. val)
            self:UpdateUI()
            self:NotifyOptions()
        else
            self:Print(L("Invalid size. Use 0.8 to 2.5"))
        end
    else
        -- Try class-registered slash commands
        local handled = false
        for pattern, data in pairs(ns.slashCommands) do
            if cmd == pattern or string.match(cmd, "^" .. pattern .. " ") or string.match(cmd, "^" .. pattern .. "$") then
                data.handler(cmd)
                handled = true
                break
            end
        end

        if not handled then
            self:Print(L("Commands:"))
            self:Print(L("  /rc - Open the options window"))
            self:Print(L("  /rc config - Open the panel configuration (size, scale, opacity, colour)"))
            self:Print(L("  /rc toggle - Enable/disable addon"))
            self:Print(L("  /rc profile <name> - Switch profile"))
            self:Print(L("  /rc glow <1-5> - How many abilities are highlighted"))
            self:Print(L("  /rc size <0.8-2.5> - Glow border size"))
            self:Print(L("  /rc numbers - Toggle priority numbers"))
            self:Print(L("  /rc pulse - Toggle glow animation"))
            self:Print(L("  /rc frame - Toggle the spell icon window"))
            self:Print(L("  /rc test - Test glow on your action bars"))
            self:Print(L("  /rc status - Show debug status"))
            self:Print(L("  /rc live - Toggle live debug frame"))
            self:Print(L("  /rc debug - Toggle debug mode"))
            self:Print(L("  /rc help - Open the help tab (/rc help full for the wizard)"))
            self:Print(L("  /rc wizard - Run the guided setup wizard"))
            self:Print(L("  /rc move - Unlock the icon window to move it"))
            self:Print(L("  /rc lock - Lock the icon window in place"))
            self:Print(L("  /rc train - Toggle training mode (ALT-SHIFT-L)"))
            self:Print(L("  /rc pvp - Toggle PvP mode (ALT-SHIFT-V)"))
            self:Print(L("  /rc boss - Boss profiles (/rc boss list|save|apply)"))
            self:Print(L("  /rc stats - Skill stats (/rc stats, /rc stats dps, /rc stats reset)"))
            -- Show class-registered commands
            for pattern, data in pairs(ns.slashCommands) do
                if data.help then
                    self:Print("  /rc " .. L(data.help))
                end
            end
        end
    end
end

-- ============================================================================
-- COMBAT LOG
-- ============================================================================

function DH:OnCombatLogEvent(timestamp, subevent, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags, spellId, spellName, spellSchool, ...)
    local playerGUID = (self.State and self.State.GUID) or UnitGUID("player")
    if sourceGUID ~= playerGUID then return end

    -- Track enemies the player recently damaged (Improvement 3). The cleave
    -- and AOE decisions use this combat-log signal instead of nameplate tokens.
    if destGUID and self.State and self.State.TrackCombatEnemy
       and type(subevent) == "string" and subevent:find("DAMAGE", 1, true) then
        self.State:TrackCombatEnemy(destGUID)
    end

    -- Build the spellId -> ability key map once (L10 optimization).
    local classAbil = self.Class and self.Class.abilities
    local abilMap = ns._abilityIdMap
    if not abilMap or ns._abilityIdMapSrc ~= classAbil then
        abilMap = {}
        if classAbil then
            for key, ability in pairs(classAbil) do
                local id = ability and ability.id
                if id and not abilMap[id] then abilMap[id] = key end
            end
        end
        ns._abilityIdMap = abilMap
        ns._abilityIdMapSrc = classAbil
    end
    local numericId = spellId and tonumber(spellId)
    local castKey = (numericId and abilMap[numericId]) or abilMap[spellId]

    -- Prompt 2: damage accumulation (fight analytics / ideal DPS) and the
    -- per-cast skill statistics + combat-log CSV row.
    if subevent == "SWING_DAMAGE" or subevent == "SPELL_DAMAGE"
        or subevent == "RANGE_DAMAGE" then
        ns.RecordDamage(self, spellId, select(1, ...))
    end
    if subevent == "SPELL_CAST_SUCCESS" then
        ns.RecordCast(self, castKey, spellId)
        -- v3.3.0: exam / mentor / pulse accuracy on every player cast.
        if ns.OnPlayerCast then ns.OnPlayerCast(self, castKey, spellId) end
    end

    -- Snooze detection: when player uses any ability, check if they skipped a snoozeable recommendation
    if subevent == "SPELL_CAST_SUCCESS" or subevent == "SPELL_DAMAGE" or subevent == "SPELL_AURA_APPLIED" then
        local topRec = ns.recommendations[1]
        if topRec and castKey then
            local topAbility = topRec.ability
            if ns.snooze[castKey] then
                self:ClearSnooze(castKey)
            end

            -- Player used a different ability than recommended — snooze the recommended one
            if castKey ~= topAbility and ns.snoozeable and ns.snoozeable[topAbility] then
                self:Snooze(topAbility, ns.snoozeable[topAbility])
            end
        end
    end

    -- Dispatch to registered handlers. Each is pcall-guarded so one class
    -- module error cannot skip the remaining handlers for this event.
    for _, handler in ipairs(ns.registered.combatLogHandlers) do
        if type(handler) == "function" then
            local ok, err = pcall(handler, subevent, sourceGUID, destGUID, spellId, spellName, ...)
            if not ok and ns.AddError then
                ns.AddError("Combat-log handler failed: " .. tostring(err))
            end
        end
    end
end

-- ============================================================================
-- PROMPT 2: BOSS PROFILES / SKILL STATS / IDEAL DPS
-- Session-only analytics live on ns (never persisted).
-- ============================================================================

-- Keys a boss profile is allowed to override in db.common.
ns.bossOverrideKeys = {
    "target_mode", "use_cooldowns", "auto_cooldowns",
    "cooldown_order", "activity_profile", "display_count",
}

ns.skillStats = {}         -- [spellId] = { recommended, cast, missed, damage, name }
ns.fight = { active = false, damage = 0, duration = 0, startTime = 0 }
ns.lastFight = nil
ns.knownBosses = {}        -- [encounterID] = encounterName
ns.bossBackup = { active = false }

-- ---------------------------------------------------------------------------
-- SKILL STATS (Improvement 3)
-- ---------------------------------------------------------------------------

function ns.SkillStat(id, name)
    id = tonumber(id)
    if not id then return nil end
    local s = ns.skillStats[id]
    if not s then
        s = { recommended = 0, cast = 0, missed = 0, damage = 0, name = name }
        ns.skillStats[id] = s
    elseif name and not s.name then
        s.name = name
    end
    return s
end

local function AbilityIdName(self, key)
    local ab = self.Class and self.Class.abilities and self.Class.abilities[key]
    if ab then return ab.id, ab.name end
    return nil, nil
end

-- Called from UpdateRecommendations with the freshly built list.
function ns.RecordRecommendations(self, recs)
    -- v3.3.0: class-pulse sampling (DoT uptime + cooldown usage). This runs
    -- whenever the pulse indicator is enabled, independent of the stats /
    -- ideal-dps settings.
    if self:GetSetting("class_pulse_enabled") ~= false then
        ns.SamplePulse(self)
        local top = recs and recs[1]
        local topKey = top and top.ability
        local p = ns.pulse
        if ns.IsBigCooldown and ns.IsBigCooldown(self, topKey) then
            if p.lastTopCd ~= topKey then
                p.lastTopCd = topKey
                p.cdSeen = p.cdSeen + 1
            end
        else
            p.lastTopCd = nil
        end
    end

    if not (self:GetSetting("stats_enabled") or self:GetSetting("ideal_dps_enabled")) then
        return
    end
    if type(recs) ~= "table" then return end
    for i = 1, #recs do
        local id, name = AbilityIdName(self, recs[i].ability)
        id = id or recs[i].id
        if id then
            local s = ns.SkillStat(id, recs[i].name or name)
            if s then s.recommended = s.recommended + 1 end
        end
    end
end

-- Called on the player's SPELL_CAST_SUCCESS.
function ns.RecordCast(self, castKey, spellId)
    if not (self:GetSetting("stats_enabled") or self:GetSetting("ideal_dps_enabled")) then
        return
    end
    local ab = castKey and self.Class and self.Class.abilities and self.Class.abilities[castKey]
    local id = (ab and ab.id) or tonumber(spellId)
    if not id then return end
    local s = ns.SkillStat(id, ab and ab.name)
    if s then s.cast = s.cast + 1 end

    -- A cast that is not the current top recommendation counts as a miss for
    -- the recommended ability.
    local top = ns.recommendations and ns.recommendations[1]
    if top then
        local topId, topName = AbilityIdName(self, top.ability)
        if topId and topId ~= id then
            local t = ns.SkillStat(topId, top.name or topName)
            if t then t.missed = t.missed + 1 end
        end
    end
end

-- Accumulate player damage for the current fight and per-spell averages.
function ns.RecordDamage(self, spellId, amount)
    amount = tonumber(amount) or 0
    if amount <= 0 then return end
    if ns.fight and ns.fight.active then
        ns.fight.damage = ns.fight.damage + amount
    end
    if self:GetSetting("ideal_dps_enabled") or self:GetSetting("stats_enabled") then
        local id = tonumber(spellId)
        if id then
            local s = ns.SkillStat(id)
            if s then s.damage = s.damage + amount end
        end
    end
end

local function GlobalAvgDamage()
    local total, casts = 0, 0
    for _, s in pairs(ns.skillStats) do
        total = total + (s.damage or 0)
        casts = casts + (s.cast or 0)
    end
    if casts > 0 then return total / casts end
    return 0
end

-- ---------------------------------------------------------------------------
-- BOSS PROFILES (Improvement 1)
-- ---------------------------------------------------------------------------

function DH:IsBossProfilesEnabled()
    return (self.GetSetting and self:GetSetting("boss_profiles_enabled") == true)
        or false
end

function DH:GetBossProfiles()
    if self.db and type(self.db.boss_profiles) == "table" then
        return self.db.boss_profiles
    end
    return {}
end

function DH:SetBossProfile(id, data)
    if not self.db or id == nil then return false end
    if type(self.db.boss_profiles) ~= "table" then self.db.boss_profiles = {} end
    self.db.boss_profiles[tostring(id)] = data or {}
    return true
end

function DH:DeleteBossProfile(id)
    if self.db and type(self.db.boss_profiles) == "table" then
        self.db.boss_profiles[tostring(id)] = nil
        return true
    end
    return false
end

-- Snapshot the current values of the overridable keys, apply the profile and
-- remember the snapshot so ENCOUNTER_END can put the user's settings back.
function DH:ApplyBossProfile(id, name)
    local profiles = self:GetBossProfiles()
    local prof = profiles[tostring(id or "")]
    if not prof and name then
        for pid, p in pairs(profiles) do
            if p and p.name and p.name == name then prof = p end
        end
    end
    if not prof then return false, "no-profile" end
    if not self.db.common then self.db.common = {} end

    if not ns.bossBackup.active then
        local snap = {}
        for _, k in ipairs(ns.bossOverrideKeys) do
            snap[k] = self.db.common[k]
            snap["_had_" .. k] = (self.db.common[k] ~= nil)
        end
        ns.bossBackup = { active = true, snap = snap, id = tostring(id or "") }
    end
    for k, v in pairs(prof) do
        if type(k) == "string" and k ~= "name" then
            self.db.common[k] = v
        end
    end
    if prof.name then ns.bossBackup.name = prof.name end
    ns.bossBackup.id = tostring(id or ns.bossBackup.id or "")
    self:RefreshConfig()
    self:UpdateRecommendations()
    if self.NotifyOptions then self:NotifyOptions() end
    return true
end

function DH:RestoreDefaultProfile()
    if not ns.bossBackup.active then return false end
    local snap = ns.bossBackup.snap or {}
    if self.db and self.db.common then
        for _, k in ipairs(ns.bossOverrideKeys) do
            if snap["_had_" .. k] then
                self.db.common[k] = snap[k]
            else
                self.db.common[k] = nil
            end
        end
    end
    ns.bossBackup = { active = false }
    ns.bossTargetActive = nil   -- name of the target-detected boss preset currently applied
    self:RefreshConfig()
    self:UpdateRecommendations()
    if self.NotifyOptions then self:NotifyOptions() end
    return true
end

-- ---------------------------------------------------------------------------
-- LIFECYCLE HOOKS (v3.4.0-hotfix6): the feature pack subscribes here instead
-- of re-wrapping methods, so load order can never silently drop the original.
-- ---------------------------------------------------------------------------
ns._hooks = ns._hooks or {}
function DH:RegisterHook(event, fn)
    if type(event) ~= "string" or type(fn) ~= "function" then return end
    ns._hooks[event] = ns._hooks[event] or {}
    table.insert(ns._hooks[event], fn)
end
function ns.RunHooks(event, ...)
    local list = ns._hooks and ns._hooks[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok and DH.Print then
            DH:Print(string.format(L("Hook %s: %s"), tostring(event), tostring(err)))
        end
    end
end

function DH:OnEncounterStart(encounterID, encounterName)
    local id = tostring(encounterID or "")
    if id ~= "" then
        ns.knownBosses[id] = encounterName or ns.knownBosses[id] or id
    end
    if self.State then
        self.State.encounter_id = (id ~= "") and id or nil
        self.State.encounter_name = encounterName
    end
    ns.skillStats = {}
    self:StartFight(encounterID, encounterName)
    if self:IsBossProfilesEnabled() then
        local kind = self.GetInstanceKind and self:GetInstanceKind() or nil
        local applied = self:ApplyBossProfile(encounterID, encounterName)
        if not applied then
            applied = self:ApplyBossPresetFor(encounterID, encounterName, kind)
        end
        if applied then
            if ns.bossBackup and ns.bossBackup.active then
                ns.bossBackup.src = "encounter"
            end
            self:Print(L("Boss profile applied: ")
                .. tostring(encounterName or id))
        end
    end
    ns.RunHooks("OnEncounterStart", encounterID, encounterName)
end

function DH:OnEncounterEnd(encounterID, encounterName, difficultyID, raidSize, endStatus)
    self:EndFight(endStatus)
    if self.State then
        self.State.encounter_id = nil
        self.State.encounter_name = nil
    end
    if ns.bossBackup.active then
        self:RestoreDefaultProfile()
        self:Print(L("Default profile restored."))
    end
end

-- ---------------------------------------------------------------------------
-- FIGHT ANALYTICS / IDEAL DPS (Improvement 4)
-- ---------------------------------------------------------------------------

function DH:StartFight(id, name)
    ns.fight = {
        active = true,
        damage = 0,
        duration = 0,
        startTime = GetTime(),
        bossId = (id ~= nil) and tostring(id) or nil,
        bossName = name,
    }
    -- v3.3.0: reset the per-fight pulse / exam counters.
    if ns.ResetAnalytics then ns.ResetAnalytics() end
    ns.RunHooks("StartFight", id, name)
end

function DH:EndFight(endStatus)
    local f = ns.fight
    if not f or not f.active then
        ns.RunHooks("EndFight", endStatus)
        return
    end
    f.active = false
    f.duration = math.max(0.001, GetTime() - (f.startTime or GetTime()))
    if f.duration < 1 then
        ns.RunHooks("EndFight", endStatus)
        return
    end

    local actual = f.damage / f.duration
    local idealDamage = f.damage
    local losses = {}
    local fallbackAvg = GlobalAvgDamage()
    for id, s in pairs(ns.skillStats) do
        if (s.missed or 0) > 0 then
            local avg = (s.cast and s.cast > 0 and s.damage and s.damage > 0)
                and (s.damage / s.cast) or fallbackAvg
            local lost = s.missed * avg
            if lost > 0 then
                idealDamage = idealDamage + lost
                losses[#losses + 1] = {
                    id = id, name = s.name or tostring(id),
                    lost = lost, missed = s.missed,
                }
            end
        end
    end
    table.sort(losses, function(a, b) return a.lost > b.lost end)

    f.actual_dps = actual
    f.ideal_dps = idealDamage / f.duration
    f.loss_pct = (f.ideal_dps > 0)
        and ((1 - actual / f.ideal_dps) * 100) or 0
    f.losses = losses
    f.killed = (endStatus == 1)
    ns.lastFight = f
    self:ReportFight(f)
    -- v3.3.0: exam report + persistent learning session.
    if ns.FinalizeAnalytics then ns.FinalizeAnalytics(self) end
    ns.RunHooks("EndFight", endStatus)
end

function DH:ReportFight(f)
    if not (self:GetSetting("ideal_dps_enabled")
        or self:GetSetting("training_mode")) then
        return
    end
    local boss = (f.bossName and f.bossName ~= "") and f.bossName or L("fight")
    self:Print(string.format(L("Fight: %s | DPS %d | ideal %d | loss %.1f%%"),
        tostring(boss), math.floor(f.actual_dps or 0),
        math.floor(f.ideal_dps or 0), f.loss_pct or 0))
    local losses = f.losses or {}
    if #losses > 0 then
        self:Print(L("Worst skills by lost damage:"))
        for i = 1, math.min(5, #losses) do
            local x = losses[i]
            self:Print(string.format("  %s: -%d (missed %d)",
                tostring(x.name), math.floor(x.lost), x.missed))
        end
    end
end

-- ---------------------------------------------------------------------------
-- RAID PRESETS
-- ---------------------------------------------------------------------------

local function SP(t) return { target_mode = t, activity_profile = "raid" } end
local function DP(t) return { target_mode = t, activity_profile = "dungeon" } end

-- id = NPC (creature) id, which is locale-independent and matches
-- UnitGUID("target") (see DH:GetUnitNpcID). Name is kept for display and as a
-- secondary match. kind separates raid vs dungeon groups.
ns.bossPresets = {
    { kind = "raid", raid = "Naxxramas", bosses = {
        { id = 15956, name = "Anub'Rekhan", profile = SP("auto") },
        { id = 15953, name = "Grand Widow Faerlina", profile = SP("aoe") },
        { id = 15952, name = "Maexxna", profile = SP("single") },
        { id = 15954, name = "Noth the Plaguebringer", profile = SP("auto") },
        { id = 15936, name = "Heigan the Unclean", profile = SP("single") },
        { id = 16011, name = "Loatheb", profile = SP("single") },
        { id = 16061, name = "Instructor Razuvious", profile = SP("single") },
        { id = 16060, name = "Gothik the Harvester", profile = SP("auto") },
        { id = 16063, name = "The Four Horsemen", profile = SP("cleave") },
        { id = 16028, name = "Patchwerk", profile = SP("single") },
        { id = 15931, name = "Grobbulus", profile = SP("single") },
        { id = 15932, name = "Gluth", profile = SP("aoe") },
        { id = 15928, name = "Thaddius", profile = SP("single") },
        { id = 15989, name = "Sapphiron", profile = SP("single") },
        { id = 15990, name = "Kel'Thuzad", profile = SP("auto") },
    } },
    { kind = "raid", raid = "OS", bosses = {
        { id = 28860, name = "Sartharion", profile = SP("auto") },
        { id = 30452, name = "Tenebron", profile = SP("auto") },
        { id = 30451, name = "Shadron", profile = SP("auto") },
        { id = 30449, name = "Vesperon", profile = SP("auto") },
    } },
    { kind = "raid", raid = "EoE", bosses = {
        { id = 28859, name = "Malygos", profile = SP("auto") },
    } },
    { kind = "raid", raid = "VoA", bosses = {
        { id = 31125, name = "Archavon the Stone Watcher", profile = SP("single") },
        { id = 33993, name = "Emalon the Storm Watcher", profile = SP("cleave") },
        { id = 35013, name = "Koralon the Flame Watcher", profile = SP("cleave") },
        { id = 38433, name = "Toravon the Ice Watcher", profile = SP("single") },
    } },
    { kind = "raid", raid = "Ulduar", bosses = {
        { id = 33113, name = "Flame Leviathan", profile = SP("auto") },
        { id = 33118, name = "Ignis the Furnace Master", profile = SP("auto") },
        { id = 33186, name = "Razorscale", profile = SP("auto") },
        { id = 33293, name = "XT-002 Deconstructor", profile = SP("auto") },
        { id = 32857, name = "Assembly of Iron", profile = SP("cleave") },
        { id = 32930, name = "Kologarn", profile = SP("auto") },
        { id = 33515, name = "Auriaya", profile = SP("auto") },
        { id = 32845, name = "Hodir", profile = SP("single") },
        { id = 32865, name = "Thorim", profile = SP("auto") },
        { id = 32906, name = "Freya", profile = SP("auto") },
        { id = 33350, name = "Mimiron", profile = SP("auto") },
        { id = 33271, name = "General Vezax", profile = SP("single") },
        { id = 33288, name = "Yogg-Saron", profile = SP("auto") },
        { id = 32871, name = "Algalon the Observer", profile = SP("single") },
    } },
    { kind = "raid", raid = "ToC", bosses = {
        { id = 34796, name = "Northrend Beasts", profile = SP("aoe") },
        { id = 34780, name = "Lord Jaraxxus", profile = SP("single") },
        { id = 34447, name = "Faction Champions", profile = SP("cleave") },
        { id = 34496, name = "Twin Val'kyr", profile = SP("cleave") },
        { id = 34564, name = "Anub'arak", profile = SP("aoe") },
    } },
    { kind = "raid", raid = "Onyxia", bosses = {
        { id = 10184, name = "Onyxia", profile = SP("auto") },
    } },
    { kind = "raid", raid = "ICC", bosses = {
        { id = 36612, name = "Lord Marrowgar", profile = SP("auto") },
        { id = 36855, name = "Lady Deathwhisper", profile = SP("auto") },
        { id = 37813, name = "Deathbringer Saurfang", profile = SP("single") },
        { id = 36626, name = "Festergut", profile = SP("single") },
        { id = 36627, name = "Rotface", profile = SP("auto") },
        { id = 36678, name = "Professor Putricide", profile = SP("auto") },
        { id = 37970, name = "Blood Prince Council", profile = SP("cleave") },
        { id = 37955, name = "Blood-Queen Lana'thel", profile = SP("single") },
        { id = 36789, name = "Valithria Dreamwalker", profile = SP("auto") },
        { id = 36853, name = "Sindragosa", profile = SP("single") },
        { id = 36597, name = "The Lich King", profile = SP("auto") },
    } },
    { kind = "raid", raid = "RS", bosses = {
        { id = 39746, name = "General Zarithrian", profile = SP("auto") },
        { id = 39747, name = "Saviana Ragefire", profile = SP("auto") },
        { id = 39751, name = "Baltharus the Warborn", profile = SP("auto") },
        { id = 39863, name = "Halion", profile = SP("auto") },
    } },

    -- WotLK 5-man dungeons (16). Matched by NPC id via the target; used as a
    -- fallback because 5-man bosses do not reliably fire ENCOUNTER_START.
    { kind = "dungeon", dungeon = "Utgarde Keep", bosses = {
        { id = 23953, name = "Prince Keleseth", profile = DP("single") },
        { id = 24200, name = "Skarvald the Constructor", profile = DP("single") },
        { id = 24201, name = "Dalronn the Controller", profile = DP("single") },
        { id = 23954, name = "Ingvar the Plunderer", profile = DP("single") },
    } },
    { kind = "dungeon", dungeon = "Utgarde Pinnacle", bosses = {
        { id = 26668, name = "Svala Sorrowgrave", profile = DP("single") },
        { id = 26687, name = "Gortok Palehoof", profile = DP("single") },
        { id = 26693, name = "Skadi the Ruthless", profile = DP("single") },
        { id = 26861, name = "King Ymiron", profile = DP("single") },
    } },
    { kind = "dungeon", dungeon = "The Nexus", bosses = {
        { id = 26731, name = "Grand Magus Telestra", profile = DP("cleave") },
        { id = 26763, name = "Anomalus", profile = DP("single") },
        { id = 26794, name = "Ormorok the Tree-Shaper", profile = DP("single") },
        { id = 26723, name = "Keristrasza", profile = DP("single") },
        { id = 26796, name = "Commander Stoutbeard", profile = DP("single") },
        { id = 26799, name = "Commander Kolurg", profile = DP("single") },
    } },
    { kind = "dungeon", dungeon = "The Oculus", bosses = {
        { id = 27654, name = "Drakos the Interrogator", profile = DP("single") },
        { id = 27447, name = "Varos Cloudstrider", profile = DP("single") },
        { id = 27655, name = "Mage-Lord Urom", profile = DP("single") },
        { id = 27656, name = "Ley-Guardian Eregos", profile = DP("auto") },
    } },
    { kind = "dungeon", dungeon = "Azjol-Nerub", bosses = {
        { id = 28684, name = "Krik'thir the Gatewatcher", profile = DP("cleave") },
        { id = 28921, name = "Hadronox", profile = DP("cleave") },
        { id = 29120, name = "Anub'arak", profile = DP("single") },
    } },
    { kind = "dungeon", dungeon = "Ahn'kahet: The Old Kingdom", bosses = {
        { id = 29309, name = "Elder Nadox", profile = DP("cleave") },
        { id = 29308, name = "Prince Taldaram", profile = DP("single") },
        { id = 29310, name = "Jedoga Shadowseeker", profile = DP("cleave") },
        { id = 29311, name = "Herald Volazj", profile = DP("single") },
        { id = 30258, name = "Amanitar", profile = DP("single") },
    } },
    { kind = "dungeon", dungeon = "Drak'Tharon Keep", bosses = {
        { id = 26630, name = "Trollgore", profile = DP("cleave") },
        { id = 26631, name = "Novos the Summoner", profile = DP("cleave") },
        { id = 27483, name = "King Dred", profile = DP("single") },
        { id = 26632, name = "The Prophet Tharon'ja", profile = DP("single") },
    } },
    { kind = "dungeon", dungeon = "The Violet Hold", bosses = {
        { id = 29316, name = "Moragg", profile = DP("single") },
        { id = 29315, name = "Erekem", profile = DP("cleave") },
        { id = 29313, name = "Ichoron", profile = DP("cleave") },
        { id = 29312, name = "Lavanthor", profile = DP("single") },
        { id = 29266, name = "Xevozz", profile = DP("single") },
        { id = 29314, name = "Zuramat the Obliterator", profile = DP("single") },
        { id = 31134, name = "Cyanigosa", profile = DP("single") },
    } },
    { kind = "dungeon", dungeon = "Gundrak", bosses = {
        { id = 29304, name = "Slad'ran", profile = DP("cleave") },
        { id = 29307, name = "Drakkari Colossus", profile = DP("cleave") },
        { id = 29305, name = "Moorabi", profile = DP("single") },
        { id = 29306, name = "Gal'darah", profile = DP("single") },
        { id = 29932, name = "Eck the Ferocious", profile = DP("single") },
    } },
    { kind = "dungeon", dungeon = "Halls of Stone", bosses = {
        { id = 27975, name = "Maiden of Grief", profile = DP("single") },
        { id = 27977, name = "Krystallus", profile = DP("single") },
        { id = 28234, name = "Tribunal of Ages", profile = DP("cleave") },
        { id = 27978, name = "Sjonnir the Ironshaper", profile = DP("cleave") },
    } },
    { kind = "dungeon", dungeon = "Halls of Lightning", bosses = {
        { id = 28586, name = "General Bjarngrim", profile = DP("cleave") },
        { id = 28587, name = "Volkhan", profile = DP("single") },
        { id = 28546, name = "Ionar", profile = DP("cleave") },
        { id = 28923, name = "Loken", profile = DP("single") },
    } },
    { kind = "dungeon", dungeon = "The Culling of Stratholme", bosses = {
        { id = 26529, name = "Meathook", profile = DP("cleave") },
        { id = 26530, name = "Salramm the Fleshcrafter", profile = DP("cleave") },
        { id = 26532, name = "Chrono-Lord Epoch", profile = DP("single") },
        { id = 26533, name = "Mal'Ganis", profile = DP("single") },
        { id = 32273, name = "Infinite Corruptor", profile = DP("single") },
    } },
    { kind = "dungeon", dungeon = "Trial of the Champion", bosses = {
        { id = 35119, name = "Eadric the Pure", profile = DP("cleave") },
        { id = 35097, name = "Confessor Paletress", profile = DP("cleave") },
        { id = 35451, name = "The Black Knight", profile = DP("auto") },
    } },
    { kind = "dungeon", dungeon = "The Forge of Souls", bosses = {
        { id = 36497, name = "Bronjahm", profile = DP("single") },
        { id = 36502, name = "Devourer of Souls", profile = DP("single") },
    } },
    { kind = "dungeon", dungeon = "Pit of Saron", bosses = {
        { id = 36494, name = "Forgemaster Garfrost", profile = DP("single") },
        { id = 36476, name = "Krick and Ick", profile = DP("cleave") },
        { id = 36658, name = "Scourgelord Tyrannus", profile = DP("single") },
    } },
    { kind = "dungeon", dungeon = "Halls of Reflection", bosses = {
        { id = 38112, name = "Falric", profile = DP("single") },
        { id = 38113, name = "Marwyn", profile = DP("single") },
        { id = 36954, name = "The Lich King", profile = DP("auto") },
    } },
}

function DH:FindPreset(id, name, kind)
    local ids = tostring(id or "")
    for _, group in ipairs(ns.bossPresets) do
        local gk = group.kind or "raid"
        if not kind or gk == kind then
            for _, b in ipairs(group.bosses) do
                if (ids ~= "" and tostring(b.id) == ids)
                    or (name and b.name == name) then
                    return b
                end
            end
        end
    end
    return nil
end

-- Auto-apply a preset when no stored profile exists (boss_profiles_enabled).
function DH:ApplyBossPresetFor(id, name, kind)
    local b = self:FindPreset(id, name, kind)
    if not b then return false end
    local prof = { name = b.name }
    for k, v in pairs(b.profile) do prof[k] = v end
    local key = b.id or b.name
    if key then self:SetBossProfile(key, prof) end
    return self:ApplyBossProfile(key, b.name)
end

-- ---------------------------------------------------------------------------
-- EXPORT / IMPORT (safe text, no loadstring)
-- ---------------------------------------------------------------------------

function DH:ExportBossProfiles()
    local lines = {}
    for id, prof in pairs(self:GetBossProfiles()) do
        local parts = {}
        for k, v in pairs(prof) do
            if type(v) ~= "table" then
                parts[#parts + 1] = tostring(k) .. "=" .. tostring(v)
            end
        end
        lines[#lines + 1] = tostring(id) .. "|" .. table.concat(parts, ";")
    end
    table.sort(lines)
    return table.concat(lines, "\n")
end

function DH:ImportBossProfiles(text)
    if type(text) ~= "string" then return 0 end
    local count = 0
    for line in text:gmatch("[^\n]+") do
        local id, body = line:match("^%s*([^|]+)|(.*)$")
        if id then
            local prof = {}
            for kv in body:gmatch("([^;]+)") do
                local k, v = kv:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
                if k and v then
                    if v == "true" then prof[k] = true
                    elseif v == "false" then prof[k] = false
                    elseif tonumber(v) then prof[k] = tonumber(v)
                    else prof[k] = v end
                end
            end
            self:SetBossProfile(id, prof)
            count = count + 1
        end
    end
    return count
end

-- ---------------------------------------------------------------------------
-- /rc stats printers
-- ---------------------------------------------------------------------------

function DH:PrintStats()
    local rows = {}
    for id, s in pairs(ns.skillStats) do
        rows[#rows + 1] = {
            id = id, name = s.name or tostring(id),
            recommended = s.recommended or 0, cast = s.cast or 0,
            missed = s.missed or 0,
        }
    end
    if #rows == 0 then
        self:Print(L("No stats recorded."))
        return
    end
    table.sort(rows, function(a, b) return a.missed > b.missed end)
    self:Print(L("Stats: top 10 abilities by missed casts"))
    for i = 1, math.min(10, #rows) do
        local r = rows[i]
        self:Print(string.format("  %s: rec %d, cast %d, missed %d",
            tostring(r.name), r.recommended, r.cast, r.missed))
    end
end

function DH:PrintDPS()
    local f = ns.fight
    if (not f or not f.active) and not ns.lastFight then
        self:Print(L("No stats recorded."))
        return
    end
    if f and f.active then
        local dur = math.max(0.001, GetTime() - (f.startTime or GetTime()))
        local dps = (f.damage or 0) / dur
        local boss = (f.bossName and f.bossName ~= "") and f.bossName or L("fight")
        self:Print(string.format(L("Fight: %s | DPS %d | ideal %d | loss %.1f%%"),
            tostring(boss), math.floor(dps), math.floor(dps), 0))
        return
    end
    self:ReportFight(ns.lastFight)
end

-- ============================================================================
-- PROMPT 3.3: BOSS TIMELINE (DBM / BigWigs, optional, safe without them)
-- Collects boss cast/aura events and DBM/BigWigs timer callbacks into
-- State.boss_timeline, then exposes a short "Hold CD / Prepare / BURST" hint
-- for the icon window. Everything is pcall-guarded: no DBM or BigWigs simply
-- means no hints, never an error.
-- ============================================================================

-- Words that mark a boss timer as "a burst window is about to open".
local TIMELINE_BURST_WORDS = {
    "burst", "bloodlust", "heroism", "time warp", "avatar",
    "wings", "trinket", "potion", "berserk", "empower",
}

local function TimelineMatchesBurst(text)
    if type(text) ~= "string" or text == "" then return false end
    text = text:lower()
    for i = 1, #TIMELINE_BURST_WORDS do
        if text:find(TIMELINE_BURST_WORDS[i], 1, true) then return true end
    end
    return false
end

function ns.GetBossTimeline()
    local st = DH.State
    if not st then return nil end
    if not st.boss_timeline then
        st.boss_timeline = {
            timers = {}, next_burst = nil, burst_active = false,
            events = {}, phase = 1,
        }
    end
    return st.boss_timeline
end

-- Improvement 5: boss phase tracking (phase 1 = default). A phase is detected
-- from DBM/BigWigs text such as "Phase 2" or from a boss aura/cast name that
-- contains it. Phase overrides are optional and never fire unless the user
-- enables timeline_auto_phase.
function ns.SetTimelinePhase(phase)
    phase = tonumber(phase)
    if not phase or phase < 1 or phase > 5 then return end
    local tl = ns.GetBossTimeline()
    if not tl or tl.phase == phase then return end
    tl.phase = phase
    tl.phase_changed_at = GetTime()
    if DH.GetSetting and DH:GetSetting("timeline_auto_phase") then
        if DH.UpdateRecommendations then DH:UpdateRecommendations() end
    end
end

function ns.GetTimelinePhase()
    local tl = ns.GetBossTimeline()
    return tl and tl.phase or 1
end

-- Phase -> target mode used by ResolveTargetMode when timeline_auto_phase is on.
-- Phase 2 opens multi-target; phase 3 tightens back to single for execute.
function ns.GetPhaseTargetMode()
    local tl = ns.GetBossTimeline()
    if not tl then return nil end
    if tl.phase >= 3 then return "single" end
    if tl.phase == 2 then return "aoe" end
    return nil
end

-- True while the auto-phase system considers the fight to be in an execute
-- phase. Rotations may read this via DH:IsExecutePhase().
function DH:IsExecutePhase()
    if not (self.GetSetting and self:GetSetting("timeline_auto_phase")) then
        return false
    end
    return ns.GetTimelinePhase() >= 3
end

-- Detect a phase number in free text ("Phase 2", "Phase Two", "P3", "фаза 2").
local PHASE_WORDS = {
    ["one"] = 1, ["two"] = 2, ["three"] = 3, ["four"] = 4, ["five"] = 5,
    ["первая"] = 1, ["вторая"] = 2, ["третья"] = 3, ["четвёртая"] = 4,
    ["четвертая"] = 4, ["пятая"] = 5,
}
local function PhaseFromText(text)
    if type(text) ~= "string" or text == "" then return nil end
    local lower = text:lower()
    -- "phase 3", "фаза 2", "p2"
    local n = lower:match("phase%s*(%d)") or lower:match("фаза%s*(%d)")
        or lower:match("^%s*p(%d)")
    if n then return tonumber(n) end
    -- "phase two" / "вторая фаза"
    for word, num in pairs(PHASE_WORDS) do
        if lower:find(word, 1, true) then return num end
    end
    return nil
end

-- Record a timed event ("something in N seconds").
function ns.AddBossTimer(text, seconds, source)
    if type(seconds) ~= "number" or seconds <= 0 then return end
    local tl = ns.GetBossTimeline()
    if not tl then return end
    tl.timers[#tl.timers + 1] = {
        text = text,
        expires = GetTime() + seconds,
        duration = seconds,
        burst = TimelineMatchesBurst(text),
        source = source,
    }
    local p = PhaseFromText(text)
    if p then ns.SetTimelinePhase(p) end
end

function ns.AddBossEvent(eventType, destName)
    local tl = ns.GetBossTimeline()
    if not tl then return end
    tl.events[#tl.events + 1] = { event = eventType, name = destName, time = GetTime() }
    if #tl.events > 25 then table.remove(tl.events, 1) end
    local p = PhaseFromText(destName)
    if p then ns.SetTimelinePhase(p) end
end

-- Deep timeline: raw phase messages captured from DBM/BigWigs and boss casts.
ns.timelinePhaseEvents = ns.timelinePhaseEvents or {}
function ns.RecordPhaseEvent(text)
    if type(text) ~= "string" or text == "" then return end
    if not (DH.GetSetting and DH:GetSetting("timeline_deep_enabled")) then return end
    ns.timelinePhaseEvents[#ns.timelinePhaseEvents + 1] = { t = GetTime(), msg = text }
    if #ns.timelinePhaseEvents > 64 then table.remove(ns.timelinePhaseEvents, 1) end
    local p = PhaseFromText(text)
    if p and DH.GetSetting and DH:GetSetting("timeline_phase_auto") then
        ns.SetTimelinePhase(p)
    end
end

-- Newest deep-timeline message, if it is still fresh (used by the icon window).
function ns.GetLatestPhaseText(maxAge)
    if not (DH.GetSetting and DH:GetSetting("timeline_deep_enabled")) then return nil end
    local n = #ns.timelinePhaseEvents
    if n == 0 then return nil end
    local e = ns.timelinePhaseEvents[n]
    if not e or not e.t then return nil end
    if (GetTime() - e.t) > (maxAge or 8) then return nil end
    return e.msg
end

-- Prune expired timers and find the soonest classified burst timer.
local function UpdateBossTimeline()
    local tl = ns.GetBossTimeline()
    if not tl then return nil end
    local now = GetTime()
    for i = #tl.timers, 1, -1 do
        if tl.timers[i].expires <= now then table.remove(tl.timers, i) end
    end
    local nextBurst
    for i = 1, #tl.timers do
        local t = tl.timers[i]
        if t.burst and (not nextBurst or t.expires < nextBurst.expires) then
            nextBurst = t
        end
    end
    tl.next_burst = nextBurst and (nextBurst.expires - now) or nil
    return tl
end

-- Returns label, countdown text. Rules from the spec:
--   burst active (<= 2s)         -> "BURST"
--   burst within burst_window    -> "Hold CD"
--   burst within 2*burst_window  -> "Prepare"
--   otherwise                    -> nil
function ns.GetTimelineHint()
    -- timeline_show_burst = false hides only the burst countdown text.
    if DH.GetSetting and DH:GetSetting("timeline_show_burst") == false then
        return nil, nil
    end
    local tl = UpdateBossTimeline()
    if not tl or not tl.next_burst then return nil, nil end
    local secs = tl.next_burst
    local window = tonumber(DH.GetSetting and DH:GetSetting("timeline_burst_window")) or 15
    if window < 5 then window = 5 end
    local detail = ("Burst in %ds"):format(math.max(0, math.floor(secs + 0.5)))
    if secs <= 2 then
        return (DH.L and DH.L["BURST"]) or "BURST", detail
    elseif secs < window then
        return (DH.L and DH.L["Hold CD"]) or "Hold CD", detail
    elseif secs <= window * 2 then
        return (DH.L and DH.L["Prepare"]) or "Prepare", detail
    end
    return nil, nil
end

-- Best-effort integration with DBM and BigWigs. Both APIs are optional and
-- differ between versions, so every registration is pcall-protected and the
-- callbacks accept any argument shape.
function ns.InitTimeline()
    local CBH = _G.LibStub and _G.LibStub("CallbackHandler-1.0", true)

    -- DBM (Deadly Boss Mods): its object is a CallbackHandler target. Boss mods
    -- may load after us, so registration is retried (InitTimeline runs again on
    -- ADDON_LOADED and on encounter start); each source is hooked only once.
    local dbm = _G.DBM or _G.DBMAPI
    if dbm and dbm.RegisterCallback and not ns._dbmHooked then
        ns._dbmHooked = true
        pcall(function()
            dbm:RegisterCallback("DBM_TimerStart", function(_, id, msg, timer)
                ns.AddBossTimer(msg, tonumber(timer), "DBM")
            end)
        end)
        pcall(function()
            dbm:RegisterCallback("DBM_Announce", function(_, msg)
                ns.AddBossEvent("announce", msg)
                ns.RecordPhaseEvent(msg)
                if TimelineMatchesBurst(msg) then ns.AddBossTimer(msg, 0.1, "DBM") end
            end)
        end)
    end

    -- BigWigs: messages via BigWigsLoader or a shared CallbackHandler.
    local bw = _G.BigWigsLoader or _G.BigWigs
    if bw and not ns._bwHooked then
        if bw.RegisterMessage then
            ns._bwHooked = true
            pcall(function()
                bw.RegisterMessage(bw, "BigWigs_StartBar", function(_, _, text, duration)
                    ns.AddBossTimer(text, tonumber(duration), "BigWigs")
                    ns.RecordPhaseEvent(text)
                end)
            end)
            pcall(function()
                bw.RegisterMessage(bw, "BigWigs_Message", function(_, _, text)
                    ns.RecordPhaseEvent(text)
                end)
            end)
        elseif CBH then
            ns._bwHooked = true
            pcall(function()
                CBH:RegisterCallback("BigWigs_StartBar", function(_, _, _, text, duration)
                    ns.AddBossTimer(text, tonumber(duration), "BigWigs")
                    ns.RecordPhaseEvent(text)
                end, bw)
            end)
        end
    end

    -- Boss cast / debuff tracking (works without DBM/BigWigs). Register once.
    if not ns._timelineEventsReg then
        ns._timelineEventsReg = true
        local f = ns._timelineFrame or CreateFrame("Frame")
        ns._timelineFrame = f
        f:RegisterEvent("SPELL_CAST_START")
        f:RegisterEvent("SPELL_AURA_APPLIED")
        f:SetScript("OnEvent", function(_, event, unit, spellName)
            if event == "SPELL_CAST_START" then
                local name = (type(spellName) == "string" and spellName)
                    or (type(unit) == "string" and unit) or nil
                ns.AddBossEvent("cast", name)
            elseif event == "SPELL_AURA_APPLIED" then
                ns.AddBossEvent("aura", spellName)
            end
        end)
    end
end

-- ============================================================================
-- IMPROVEMENT 6: CUSTOM APL (a small, player-friendly priority language)
-- ============================================================================
-- Format:
--   priority:
--   - Icy Veins if cooldown_ready and not buff_active
--   - Deep Freeze if target_has_debuff("Fingers of Frost")
--   - Ice Lance if buff_active("Fingers of Frost")
--   - Frostbolt
--
-- Conditions: cooldown_ready, buff_active(x), buff_remaining(x[, n]),
-- target_has_debuff(x), target_hp <op> n, player_hp <op> n, mana_pct <op> n,
-- combo_points <op> n, always. "and" combines clauses; "not" negates one.
-- Parsing is pure string work (never loadstring) and every evaluation is
-- pcall-guarded, so a broken APL can only ever produce no recommendations.

local function APLNormalize(s)
    if type(s) ~= "string" then return "" end
    s = s:lower()
    s = s:gsub("[%p%c]", " ")
    s = s:gsub("%s+", " ")
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function APLKey(s)
    return (APLNormalize(s):gsub(" ", "_"))
end

-- Resolve a spell/ability name (key, EN name or localized name) to a class key.
local function APLResolveAbility(self, name)
    if not name or name == "" then return nil end
    local cls = self.Class and self.Class.abilities
    if type(cls) ~= "table" then return nil end
    local key = APLKey(name)
    if cls[key] then return key end
    local norm = APLNormalize(name)
    for k, a in pairs(cls) do
        if APLNormalize(k) == norm then return k end
        if a and a.name and APLNormalize(a.name) == norm then return k end
        if a and a.id and GetSpellInfo then
            local loc = GetSpellInfo(a.id)
            if loc and APLNormalize(loc) == norm then return k end
        end
    end
    return nil
end

-- Resolve an aura display name to a state buff/debuff key.
local function APLResolveAura(st, name, wantDebuff)
    if not st or not name or name == "" then return nil end
    local key = APLKey(name)
    local tbl = wantDebuff and st.debuff or st.buff
    if tbl and tbl[key] then return key end
    local list = wantDebuff and ns.registered.debuffs or ns.registered.buffs
    local norm = APLNormalize(name)
    if type(list) == "table" then
        for i = 1, #list do
            if APLNormalize(list[i]) == norm then return list[i] end
        end
    end
    -- Strict: target_has_debuff only matches debuffs and buff_active only
    -- matches buffs, so a player buff never satisfies a target-debuff test.
    return nil
end

local function APLParseCondition(token)
    token = token:gsub("^%s+", ""):gsub("%s+$", "")
    if token == "" then return nil end
    local cond = { negate = false }
    if token:match("^not%s+") then
        cond.negate = true
        token = token:gsub("^not%s+", "")
    end
    local name = token:match("^([%a_][%w_]*)")
    if not name then return nil end
    cond.name = name
    local rest = token:sub(#name + 1)
    local openParen = rest:find("%(")
    if openParen then
        local closeParen = rest:find("%)", openParen)
        if closeParen then
            local argsStr = rest:sub(openParen + 1, closeParen - 1)
            local args = {}
            for part in (argsStr .. ","):gmatch("(.-),") do
                local a = part:gsub("^%s+", ""):gsub("%s+$", "")
                a = a:gsub('^"(.*)"$', "%1")
                args[#args + 1] = a
            end
            cond.arg = args[1]
            cond.arg2 = args[2] and (tonumber(args[2]) or args[2]) or nil
            rest = rest:sub(closeParen + 1)
        end
    end
    local op, val = rest:match("^%s*(<=|>=|==|~=|<>|<|>)%s*(%-?%d+%.?%d*)")
    if op then
        cond.op = op
        cond.value = tonumber(val)
    end
    return cond
end

-- Parse text into rules. Returns rules, error (rules is always a table).
function ns.ParseAPL(text)
    local rules = {}
    if type(text) ~= "string" then return rules, "no text" end
    for raw in (text .. "\n"):gmatch("(.-)\n") do
        local line = raw:gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and not line:match("^#") and not line:match("^%-%-")
           and not line:match("^priority%s*:?%s*$")
           and not line:match("^actions%s*:?%s*$") then
            line = line:gsub("^[%-%*%+]%s*", "")
            local ability, condText = line:match("^(.-)%s+[Ii][Ff]%s+(.+)$")
            if not ability then ability = line; condText = nil end
            ability = ability:gsub("^%s+", ""):gsub("%s+$", "")
            local rule = { ability = ability, conditions = {} }
            if condText then
                local normalized = condText:gsub("%s+[Aa][Nn][Dd]%s+", "\1")
                for clause in (normalized .. "\1"):gmatch("(.-)\1") do
                    local c = APLParseCondition(clause)
                    if c then rule.conditions[#rule.conditions + 1] = c end
                end
            end
            if ability ~= "" then rules[#rules + 1] = rule end
        end
    end
    return rules, nil
end

local function APLAuraActive(st, key)
    if not key then return false end
    local b = (st.buff and st.buff[key]) or (st.debuff and st.debuff[key])
    if not b then return false end
    local now = st.now or 0
    if b.expires and b.expires > 0 and b.expires <= now then return false end
    return true
end

local function APLEvalCondition(self, st, cond, abilityId)
    local name = cond.name
    local result
    if name == "always" then
        result = true
    elseif name == "cooldown_ready" then
        if abilityId and type(GetSpellCooldown) == "function" then
            local start, dur = GetSpellCooldown(abilityId)
            result = (not start) or (not dur) or dur == 0
                or ((start + dur) - GetTime()) <= 0
        else
            result = true
        end
    elseif name == "buff_active" then
        result = APLAuraActive(st, APLResolveAura(st, cond.arg or "", false))
    elseif name == "debuff_active" then
        result = APLAuraActive(st, APLResolveAura(st, cond.arg or "", true))
    elseif name == "buff_remaining" then
        local key = APLResolveAura(st, cond.arg or "", false)
        local b = key and st.buff and st.buff[key]
        result = (b and b.expires and math.max(0, b.expires - (st.now or 0))) or 0
    elseif name == "target_has_debuff" then
        result = APLAuraActive(st, APLResolveAura(st, cond.arg or "", true))
    elseif name == "target_hp" then
        result = (st.target and st.target.health and st.target.health.pct) or 100
    elseif name == "player_hp" then
        result = (st.health and st.health.pct) or 100
    elseif name == "mana_pct" then
        result = (st.mana and st.mana.pct) or 100
    elseif name == "combo_points" then
        result = (st.combo_points and st.combo_points.current) or 0
    else
        result = false
    end

    if cond.op and type(result) == "number" and cond.value then
        local v = cond.value
        if cond.op == "<" then result = result < v
        elseif cond.op == "<=" then result = result <= v
        elseif cond.op == ">" then result = result > v
        elseif cond.op == ">=" then result = result >= v
        elseif cond.op == "==" then result = result == v
        else result = result ~= v end
    elseif type(result) == "number" then
        result = result > 0
    else
        result = result and true or false
    end

    if cond.negate then result = not result end
    return result
end

-- Evaluate the stored APL. Returns recs, valid. valid is false when there is
-- no APL to run, so the caller can fall back to the class rotation.
function ns.EvaluateAPL(self)
    local rules = self.GetSetting and self:GetSetting("custom_apl")
    if type(rules) ~= "table" or #rules == 0 then return {}, false end
    local st = self.State
    if not st then return {}, false end
    local maxRecs = tonumber(self:GetSetting("display_count")) or 3
    if maxRecs < 1 then maxRecs = 1 end
    local cap = maxRecs + 2
    local recs = {}
    for i = 1, #rules do
        local rule = rules[i]
        local abilityKey = APLResolveAbility(self, rule.ability)
        local passes = true
        local conds = rule.conditions
        if conds then
            for j = 1, #conds do
                local ok = false
                pcall(function()
                    local id = abilityKey and self.Class.abilities[abilityKey]
                        and self.Class.abilities[abilityKey].id or nil
                    ok = APLEvalCondition(self, st, conds[j], id)
                end)
                if not ok then passes = false break end
            end
        end
        if passes and abilityKey then
            recs[#recs + 1] = {
                ability = abilityKey,
                priority = #recs + 1,
                text = rule.ability,
            }
            if #recs >= cap then break end
        end
    end
    return recs, true
end

-- Store parsed rules + the raw source. Returns rule count, error.
function ns.SetCustomAPL(self, text)
    local rules, err = ns.ParseAPL(text)
    if not rules or #rules == 0 then
        return 0, err or "empty"
    end
    self:SetSetting("custom_apl", rules)
    self:SetSetting("custom_apl_source", text or "")
    return #rules, nil
end

-- Export the current APL as text. Round-trips the stored source when present,
-- otherwise emits a starter template from the class ability list.
function ns.ExportAPL(self)
    local src = self.GetSetting and self:GetSetting("custom_apl_source")
    if type(src) == "string" and src ~= "" then return src end
    local cls = (self.Class and self.Class.abilities) or {}
    local keys = {}
    for k in pairs(cls) do keys[#keys + 1] = k end
    table.sort(keys)
    local out = { "priority:" }
    for i = 1, #keys do
        local a = cls[keys[i]]
        out[#out + 1] = "- " .. tostring((a and a.name) or keys[i])
    end
    return table.concat(out, "\n")
end

-- A single-line shareable form of the APL (newlines become "\n").
function ns.ExportAPLShare(self)
    local src = ns.ExportAPL(self)
    local one = src:gsub("\r", ""):gsub("\n", "\\n")
    return "RCAPL1:" .. one
end

-- Decode a share string back to plain APL text.
function ns.DecodeAPLShare(text)
    if type(text) ~= "string" then return text end
    local body = text:match("^%s*RCAPL1:(.*)$")
    if not body then return text end
    return (body:gsub("\\n", "\n"))
end

-- ============================================================================
-- v3.3.0 PHASE 2/3: ANALYTICS
-- Live DPS forecast, class pulse, exam mode, mentor mode, adaptive rotation
-- and persistent learning statistics. Everything here is additive and gated
-- behind opt-in settings, so existing rotations are unaffected.
-- ============================================================================

ns.dpsForecast = { predicted = 0, actual = 0, loss_pct = 0, lastUpdate = 0 }
ns.pulse = {
    correct = 0, total = 0, dotSamples = 0, dotActive = 0,
    cdSeen = 0, cdCast = 0, lastTopCd = nil,
    score = 0, accuracy = 0, dot_uptime = nil, cd_usage = nil,
}
ns.exam = { correct = 0, wrong = 0, missed = 0 }
ns.mentorErrors = 0
ns.mentorCorrect = 0

-- ---- DPS FORECAST (Improvement 1) -----------------------------------------

-- Optional per-spell damage data. Classes (or users) may register
-- { [key or spellId] = { min=, max=, coeff=, ap=, cast= } }. Without data the
-- forecast self-calibrates from observed combat-log damage and finally falls
-- back to a stat-based estimate.
ns.spellDamage = ns.spellDamage or {}
function DH:RegisterSpellDamage(map)
    if type(map) ~= "table" then return end
    for k, v in pairs(map) do ns.spellDamage[k] = v end
end

function DH:GetSpellDamage(key)
    local ab = self.Class and self.Class.abilities and self.Class.abilities[key]
    return ns.spellDamage[key] or (ab and ab.id and ns.spellDamage[ab.id]) or nil
end

local function AbilityAvgDamage(self, key)
    local ab = self.Class and self.Class.abilities and self.Class.abilities[key]
    local id = ab and ab.id
    -- 1) observed average (self-calibrating once the spell has landed)
    if id then
        local s = ns.skillStats[id]
        if s and s.cast and s.cast > 0 and s.damage and s.damage > 0 then
            return s.damage / s.cast
        end
    end
    local st = self.State
    local sp = (st and st.stat and st.stat.spell_power) or 0
    local ap = (st and st.stat and st.stat.attack_power) or 0
    local crit = (st and st.stat and st.stat.crit) or 0
    -- 2) registered coefficient
    local dmg = self:GetSpellDamage(key)
    if dmg then
        local base = ((dmg.min or 0) + (dmg.max or 0)) / 2
        local scale = dmg.ap and ap or sp
        local hit = base + (dmg.coeff or 0) * scale
        return hit * (1 + crit / 100)
    end
    -- 3) generic stat estimate
    if sp > 0 then return (200 + sp * 0.9) * (1 + crit / 100) end
    if ap > 0 then return (150 + ap * 0.35) * (1 + crit / 100) end
    return 0
end

local function AbilityGCD(self, key)
    local ab = self.Class and self.Class.abilities and self.Class.abilities[key]
    local st = self.State
    local haste = (st and st.stat and st.stat.spell_haste) or 1
    if haste <= 0 then haste = 1 end
    local cast = ab and ab.cast
    -- Fall back to the registered damage table's cast time when the ability
    -- table does not carry one.
    if (not cast or cast <= 0) and ns.spellDamage then
        local dmg = ns.spellDamage[key]
        if dmg and dmg.cast then cast = dmg.cast end
    end
    if cast and cast > 0 then return math.max(0.5, cast / haste) end
    return 1.5 / haste
end

function ns.UpdateDPSForecast(self, now)
    local interval = tonumber(self:GetSetting("dps_forecast_update_interval")) or 1.0
    if interval < 0.2 then interval = 0.2 end
    now = now or GetTime()
    local d = ns.dpsForecast
    if d.lastUpdate and (now - d.lastUpdate) < interval then return end
    d.lastUpdate = now

    local recs = ns.recommendations or {}
    local predicted = 0
    if #recs > 0 then
        local count = math.min(#recs, 3)
        local totalDmg, totalTime = 0, 0
        for i = 1, count do
            local w = 1 / i
            totalDmg = totalDmg + AbilityAvgDamage(self, recs[i].ability) * w
            totalTime = totalTime + AbilityGCD(self, recs[i].ability) * w
        end
        if totalTime > 0 then predicted = totalDmg / totalTime end
    end
    d.predicted = predicted

    local f = ns.fight
    if f and f.active then
        local dur = math.max(0.1, now - (f.startTime or now))
        d.actual = (f.damage or 0) / dur
    else
        d.actual = 0
    end
    d.loss_pct = (predicted > 0) and ((1 - d.actual / predicted) * 100) or 0
end

-- Text for the icon window (nil when disabled or no data).
function ns.GetDPSForecastText(self)
    if not (self.GetSetting and self:GetSetting("dps_forecast_enabled")) then return nil end
    local d = ns.dpsForecast
    if (d.predicted or 0) <= 0 then return nil end
    local txt = string.format("~%d DPS", math.floor(d.predicted + 0.5))
    if self:GetSetting("dps_forecast_show_actual") ~= false and (d.actual or 0) > 0 then
        txt = txt .. string.format("   %d (%+d%%)",
            math.floor(d.actual + 0.5), -math.floor(d.loss_pct + 0.5))
    end
    return txt
end

-- ---- CLASS PULSE (Improvement 2) ------------------------------------------

function ns.SamplePulse(self)
    local p = ns.pulse
    local debuffs = ns.registered.debuffs
    if type(debuffs) ~= "table" or #debuffs == 0 then return end
    local st = self.State
    local now = (st and st.now) or GetTime()
    local active = false
    if st and st.debuff then
        for i = 1, #debuffs do
            local d = st.debuff[debuffs[i]]
            if d and d.expires and d.expires > now then active = true break end
        end
    end
    p.dotSamples = p.dotSamples + 1
    if active then p.dotActive = p.dotActive + 1 end
end

function ns.IsBigCooldown(self, key)
    if not key then return false end
    local cfg = ns.lastCdConfig
    local base = cfg and cfg.baseCDs and cfg.baseCDs[key]
    if type(base) == "number" then return base >= 60 end
    local ab = self.Class and self.Class.abilities and self.Class.abilities[key]
    local cd = ab and ab.cooldown
    return (type(cd) == "number" and cd >= 60) or false
end

function ns.UpdatePulse(self)
    local p = ns.pulse
    p.accuracy = (p.total > 0) and (p.correct / p.total * 100) or 0
    p.dot_uptime = (p.dotSamples > 0) and (p.dotActive / p.dotSamples * 100) or nil
    p.cd_usage = (p.cdSeen > 0) and (p.cdCast / p.cdSeen * 100) or nil
    local wsum, vsum = 0.6, 0.6 * p.accuracy
    if p.dot_uptime then wsum = wsum + 0.2; vsum = vsum + 0.2 * p.dot_uptime end
    if p.cd_usage then wsum = wsum + 0.2; vsum = vsum + 0.2 * p.cd_usage end
    p.score = (wsum > 0) and (vsum / wsum) or 0
end

function ns.PulseColor(score)
    score = score or 0
    if score >= 90 then return 0.2, 1.0, 0.2 end
    if score >= 70 then return 1.0, 0.85, 0.1 end
    return 1.0, 0.25, 0.2
end

-- Returns text + r,g,b for the icon-window indicator (nil when disabled).
function ns.GetPulseInfo(self)
    if not (self.GetSetting and self:GetSetting("class_pulse_enabled")) then return nil end
    local p = ns.pulse
    if (p.total or 0) == 0 and (p.dotSamples or 0) == 0 then return nil end
    ns.UpdatePulse(self)
    local r, g, b = ns.PulseColor(p.score)
    local c = ns.GetColorPreset and ns.GetColorPreset(DH:GetSetting("pulse_color"))
    if c then r, g, b = c[1], c[2], c[3] end
    return string.format("%d%%", math.floor(p.score + 0.5)), r, g, b
end

-- ---- PER-CAST HOOK (exam / mentor / pulse accuracy) -----------------------

function ns.OnPlayerCast(self, castKey, spellId)
    local top = ns.recommendations and ns.recommendations[1]
    local topKey = top and top.ability
    local followed = (topKey ~= nil and castKey ~= nil and topKey == castKey)

    -- Pulse accuracy
    local p = ns.pulse
    if topKey then
        p.total = p.total + 1
        if followed then p.correct = p.correct + 1 end
    end
    -- Pulse cooldown usage
    if ns.IsBigCooldown(self, castKey) then p.cdCast = p.cdCast + 1 end

    -- Exam counters
    if self:GetSetting("exam_mode") then
        if followed then
            ns.exam.correct = ns.exam.correct + 1
        else
            ns.exam.wrong = ns.exam.wrong + 1
        end
    end

    -- Mentor: count consecutive mistakes and explain after the threshold.
    if self:GetSetting("mentor_mode") then
        if followed then
            ns.mentorErrors = 0
            ns.mentorCorrect = ns.mentorCorrect + 1
        else
            ns.mentorErrors = ns.mentorErrors + 1
            ns.mentorCorrect = 0
            local threshold = tonumber(self:GetSetting("mentor_error_threshold")) or 3
            if threshold < 1 then threshold = 1 end
            if ns.mentorErrors >= threshold then
                if ns.MentorExplain then ns.MentorExplain(self, castKey) end
                ns.mentorErrors = 0
            end
        end
    end
end

local MENTOR_EXPLAIN = {
    proc_active    = "A proc is up - use it now.",
    dot_expiring   = "Your DoT is about to fall off - refresh it.",
    execute_phase  = "The target is in execute range.",
    cooldown_ready = "A big cooldown is ready.",
}

function ns.MentorExplain(self, castKey)
    local top = ns.recommendations and ns.recommendations[1]
    if not top then return end
    local rk = top.reason_key
    local why
    if rk and MENTOR_EXPLAIN[rk] then
        why = L(MENTOR_EXPLAIN[rk])
    else
        why = L("Follow the highlighted ability.")
    end
    local classes = self.Class and self.Class.abilities or {}
    local castName = castKey and ((classes[castKey] and classes[castKey].name) or castKey)
    local recName = top.name or (classes[top.ability] and classes[top.ability].name) or top.ability
    local msg = string.format(L("You used %s, but %s was recommended. %s"),
        tostring(castName or "?"), tostring(recName or "?"), why)
    if self:GetSetting("mentor_show_in_chat") ~= false then
        self:Print(msg)
    end
end

-- ---- EXAM REPORT + LEARNING STATS (Improvements 3 / phase-3 #2) -----------

local function ExamReport(self)
    if not self:GetSetting("exam_mode") then return end
    local e = ns.exam
    local total = (e.correct or 0) + (e.wrong or 0)
    local acc = (total > 0) and (e.correct / total * 100) or 0
    if self:GetSetting("exam_report_in_chat") ~= false then
        self:Print(string.format(L("Exam: %d%% accuracy (%d/%d). Average DPS %d"),
            math.floor(acc + 0.5), e.correct or 0, total,
            math.floor(((ns.lastFight and ns.lastFight.actual_dps) or 0))))
    end
    e.correct, e.wrong, e.missed = 0, 0, 0
end

function ns.RecordLearningSession(self)
    if self:GetSetting("learning_stats_enabled") == false then return end
    if not self.db then return end
    if type(self.db.learning_stats) ~= "table" then
        self.db.learning_stats = { sessions = {} }
    end
    local ls = self.db.learning_stats
    if type(ls.sessions) ~= "table" then ls.sessions = {} end
    local f = ns.lastFight
    if not f then return end
    local p = ns.pulse
    local acc = (p.total > 0) and (p.correct / p.total * 100) or 0
    local dateStr = tostring(math.floor(GetTime()))
    if os and os.date then dateStr = os.date("%Y-%m-%d %H:%M") end
    ls.sessions[#ls.sessions + 1] = {
        date = dateStr,
        accuracy = math.floor(acc + 0.5),
        dps = math.floor(f.actual_dps or 0),
        loss = math.floor((f.loss_pct or 0) + 0.5),
        ilvl = (self.GetItemLevel and self:GetItemLevel()) or 0,
        spec = (self.GetActiveSpec and self:GetActiveSpec()) or "?",
    }
    local maxS = tonumber(self:GetSetting("learning_stats_max_sessions")) or 100
    if maxS < 1 then maxS = 1 end
    while #ls.sessions > maxS do table.remove(ls.sessions, 1) end
end

function DH:PrintLearning()
    local ls = self.db and self.db.learning_stats
    local sessions = ls and ls.sessions or {}
    if #sessions == 0 then
        self:Print(L("No learning sessions recorded."))
        return
    end
    local last = sessions[#sessions]
    local prev = sessions[#sessions - 1]
    self:Print(string.format(L("Learning: accuracy %d%%, DPS %d, sessions %d"),
        last.accuracy or 0, last.dps or 0, #sessions))
    if prev and prev.accuracy then
        self:Print(string.format(L("Improvement: %+d%%"),
            (last.accuracy or 0) - (prev.accuracy or 0)))
    end
end

function DH:PrintLearningGraph()
    local ls = self.db and self.db.learning_stats
    local sessions = ls and ls.sessions or {}
    if #sessions == 0 then
        self:Print(L("No learning sessions recorded."))
        return
    end
    self:Print(L("Learning accuracy (last sessions):"))
    local start = math.max(1, #sessions - 19)
    for i = start, #sessions do
        local acc = math.max(0, math.min(100, sessions[i].accuracy or 0))
        local bars = math.floor(acc / 5 + 0.5)
        self:Print(string.format("%3d%% | %s", acc, string.rep("#", bars)))
    end
end

function DH:ClearLearning()
    if self.db then self.db.learning_stats = { sessions = {} } end
    self:Print(L("Learning stats cleared."))
end

-- Fight end: emit the exam report and persist a learning session.
function ns.FinalizeAnalytics(self)
    ExamReport(self)
    ns.RecordLearningSession(self)
end

-- Fight start: reset the per-fight pulse / exam counters.
function ns.ResetAnalytics()
    local p = ns.pulse
    p.correct, p.total = 0, 0
    p.dotSamples, p.dotActive = 0, 0
    p.cdSeen, p.cdCast = 0, 0
    p.score, p.accuracy, p.dot_uptime, p.cd_usage = 0, 0, nil, nil
    p.lastTopCd = nil
    local e = ns.exam
    e.correct, e.wrong, e.missed = 0, 0, 0
end

-- ---- ADAPTIVE ROTATION (phase-3 #1) ---------------------------------------

function DH:GetItemLevel()
    if self.State and self.State.GetItemLevel then
        return self.State:GetItemLevel()
    end
    return 0
end

function DH:GetRotationComplexity()
    local setting = (self.GetSetting and self:GetSetting("adaptive_rotation")) or "auto"
    if setting == "simple" or setting == "normal" or setting == "complex" then
        return setting
    end
    local ilvl = self:GetItemLevel()
    local simpleT = tonumber(self:GetSetting("ilvl_threshold_simple")) or 200
    local complexT = tonumber(self:GetSetting("ilvl_threshold_complex")) or 245
    -- Cache the "auto" result: it only changes when the item level or one of
    -- the thresholds changes (both covered by the signature below), and this
    -- is read once per ability from CanUseCooldown.
    local sig = tostring(ilvl) .. "|" .. tostring(simpleT) .. "|" .. tostring(complexT)
    if ns._complexitySig == sig then return ns._complexityRank end
    local rank = "normal"
    if ilvl > 0 and ilvl < simpleT then
        rank = "simple"
    elseif ilvl >= complexT then
        rank = "complex"
    end
    ns._complexitySig, ns._complexityRank = sig, rank
    return rank
end

function DH:IsSimpleRotation()
    return self:GetRotationComplexity() == "simple"
end

function DH:IsComplexRotation()
    return self:GetRotationComplexity() == "complex"
end

-- ============================================================================
-- /rc selfcheck: in-game invariant tests (no live client needed - the same
-- checks as verify.py, run against the running addon).
-- ============================================================================
function DH:RunSelfCheck()
    local results = {}
    local function check(name, ok, detail)
        results[#results + 1] = { name = name, ok = ok and true or false, detail = detail }
    end

    -- 1) core / class module loaded
    check("core db", self.db ~= nil, self.db and "profile: " .. self:GetCurrentProfileName() or "no db")
    if self.Class and type(self.Class.abilities) == "table" then
        local n = 0
        for _ in pairs(self.Class.abilities) do n = n + 1 end
        check("class module", true, "abilities: " .. n)
    else
        check("class module", false, "not loaded")
    end

    -- 2) ability integrity (id/name/texture)
    if self.Class and type(self.Class.abilities) == "table" then
        local bad = 0
        for key, a in pairs(self.Class.abilities) do
            if type(a) ~= "table" or type(a.id) ~= "number" or not a.name or not a.texture then
                bad = bad + 1
            end
        end
        check("ability table", bad == 0, bad .. " entries missing id/name/texture")
    end

    -- 3) build detection
    local info = self.GetBuildInfo and self:GetBuildInfo() or nil
    check("build detection", info ~= nil and info.key ~= nil,
        info and tostring(info.key) .. " (source " .. tostring(info.source) .. ")" or "no build")

    -- 4) registered modes
    local modeCount = (ns.registered.modes and #ns.registered.modes) or 0
    check("rotation modes", modeCount > 0, modeCount)

    -- 5) APL parse (if a source is stored)
    local aplSrc = self:GetSetting("custom_apl_source")
    if type(aplSrc) == "string" and aplSrc ~= "" then
        local rules = ns.ParseAPL(aplSrc)
        check("APL", #rules > 0, #rules .. " rules")
    else
        check("APL", true, "no custom APL stored")
    end

    -- 6) locale keys present
    local L = DH.L
    local missing = 0
    for _, key in ipairs({ "General", "Cooldowns", "Colors", "APL", "BURST", "Learning Stats" }) do
        if not (L and L[key]) then missing = missing + 1 end
    end
    check("locale keys", missing == 0, missing .. " missing of 6 probed")

    -- 7) active mode has a rotation and baseCDs
    local mode = self.GetActiveMode and self:GetActiveMode()
    check("active mode rotation", mode ~= nil and mode.rotation ~= nil, mode and tostring(mode.key) or "none")

    -- 8) resists the timeline frame
    check("timeline init", ns._timelineFrame ~= nil, ns._timelineFrame and "registered" or "not started")

    self:Print(L("--- RotationCore selfcheck ---"))
    local failed = 0
    for i = 1, #results do
        local r = results[i]
        if not r.ok then failed = failed + 1 end
        self:Print(string.format("  [%s] %s: %s",
            r.ok and L("PASS") or L("FAIL"), r.name, tostring(r.detail)))
    end
    self:Print(string.format(L("Selfcheck: %d/%d passed"), #results - failed, #results))
end

-- ============================================================================
-- CORE LOGIC
-- ============================================================================

-- Update state
function DH:UpdateState()
    if not self.db or not self.db.enabled then return end
    if self.State and self.State.Reset then
        self.State:Reset()
    end
end

-- Mark a state group (or "all") for refresh on the next UpdateState().
-- Expensive groups are only rebuilt when their driving event fires.
-- kind: "resources" | "auras" | "cooldowns" | "talents" | "glyphs" | "stats" | "all"
function DH:MarkStateDirty(kind)
    kind = kind or "all"
    if self.State and self.State.MarkDirty then
        self.State:MarkDirty(kind)
    end
end

-- Get active spec using registered detector
function DH:GetActiveSpec()
    local key
    if ns.registered.specDetector then
        local ok, res = pcall(ns.registered.specDetector)
        if ok then key = res end
    end
    if (not key or key == "unknown" or key == "") and ns.registered.specDetectorFallback then
        local ok, res = pcall(ns.registered.specDetectorFallback)
        if ok then key = res end
    end
    if type(key) ~= "string" or key == "" then return "unknown" end
    return key
end

-- ============================================================================
-- PHASE 3.3: PER-SPECIALIZATION SETTINGS
-- spec_profiles[specKey] holds a full copy of the shared settings for that
-- spec; GetSetting/SetSetting consult it while spec_profiles_enabled is true.
-- ============================================================================

-- Snapshot the current shared settings as the active spec's profile
function DH:SaveSpecProfile(spec)
    spec = spec or (self.GetActiveSpec and self:GetActiveSpec()) or nil
    if type(spec) ~= "string" or spec == "" or spec == "unknown" then
        return false, "Unknown spec"
    end
    if not self.db then return false, "Database not ready" end
    if type(self.db.spec_profiles) ~= "table" then self.db.spec_profiles = {} end
    self.db.spec_profiles[spec] = DeepCopy(self.db.common or {})
    return true
end

-- Drop the active spec's overrides (falls back to the shared settings)
function DH:ClearSpecProfile(spec)
    spec = spec or (self.GetActiveSpec and self:GetActiveSpec()) or nil
    if type(spec) ~= "string" or self.db == nil then return false end
    if type(self.db.spec_profiles) == "table" then
        self.db.spec_profiles[spec] = nil
    end
    return true
end

-- Make the active spec the one GetSetting/SetSetting target and refresh
function DH:LoadSpecProfile(spec)
    if not self.db then return false end
    spec = spec or (self.GetActiveSpec and self:GetActiveSpec()) or nil
    self.db.spec_profiles_active = spec
    if self.RefreshConfig then self:RefreshConfig() end
    if self.UpdateRecommendations then self:UpdateRecommendations() end
    return true
end

-- Re-apply settings after the player switches talents/spec
function DH:OnSpecChange()
    if not self.db then return end
    if not self:IsSpecProfilesEnabled() then return end
    self:LoadSpecProfile(self.GetActiveSpec and self:GetActiveSpec() or nil)
    if self.NotifyOptions then self:NotifyOptions() end
end

-- ============================================================================
-- POST-PHASE 1: RELOAD ROTATION
-- A single entry point the client calls after talents/spec/level change so the
-- whole pipeline (spell book cache, mode detection, settings, UI) rebuilds.
-- ============================================================================
function DH:ReloadRotation()
    if not self.db then return end
    if self.MarkStateDirty then self:MarkStateDirty("all") end
    if self.InvalidateKnownSpells then self:InvalidateKnownSpells() end
    if self.AutoDetectMode then self:AutoDetectMode() end
    if self.ApplyProfileDefaults then self:ApplyProfileDefaults() end
    if self.OnSpecChange then self:OnSpecChange() end
    if self.RefreshConfig then self:RefreshConfig() end
    if self.UpdateRecommendations then self:UpdateRecommendations() end
    if self.NotifyOptions then self:NotifyOptions() end
end

-- Is a spell off cooldown right now? (used by the direct heal-DPS lists)
function DH:SpellReady(spellId)
    if not spellId or type(GetSpellCooldown) ~= "function" then return true end
    -- Registered ids are often max-rank; resolve to the rank the player knows,
    -- otherwise GetSpellCooldown reports (0,0) and we'd wrongly say "ready".
    local id = spellId
    if self.ResolveKnownSpellId then
        id = self:ResolveKnownSpellId(spellId) or spellId
    end
    local start, dur = GetSpellCooldown(id)
    if not start or start == 0 then return true end
    return (start + (dur or 0)) <= GetTime()
end

-- Friendly name for an ability key (used by the aura bridge / debug)
function DH:GetAbilityName(key)
    local ability = self.Class and self.Class.abilities and self.Class.abilities[key]
    if ability and ability.name then return ability.name end
    if key == nil then return "" end
    return tostring(key)
end

-- Explain why an ability is being recommended right now (training mode).
-- Returns a localized reason category key and the ability name.
function DH:DescribeRecommendation(rec)
    if not rec or not rec.ability then return nil, nil end
    local key = rec.ability
    local ability = (self.Class and self.Class.abilities and self.Class.abilities[key]) or {}
    local st = self.State
    local tgtPct = st and st.target and st.target.health and st.target.health.pct
    local manaPct = st and st.mana and st.mana.pct
    local rk
    if ability.execute or (tgtPct and tgtPct < 20) then
        rk = "execute_phase"
    elseif ability.cd and ability.cd >= 60 then
        rk = "burst_cd_ready"
    elseif ability.proc then
        rk = "proc_active"
    elseif ability.dot or ability.duration then
        rk = "dot_missing"
    elseif st and st.gcd_remains and st.gcd_remains > 0.35 then
        rk = "gcd_wait"
    elseif manaPct and manaPct < 20 then
        rk = "resource_low"
    elseif ability.filler then
        rk = "filler"
    else
        rk = "priority"
    end
    return rk, self:GetAbilityName(key)
end

-- Print/sound on REC1 change while training mode is on (never spams)
function DH:MaybeTrainingChat(recs)
    local top = recs and recs[1] or nil
    local key = top and top.ability or nil
    if key == self._trainingLastKey then return end
    self._trainingLastKey = key
    if not top then return end
    if self:GetSetting("training_chat_output") ~= false then
        local label = L(top.reason_key or "priority")
        self:Print(L("Cast") .. " " .. self:GetAbilityName(key) .. " (" .. label .. ")")
    end
    if self:GetSetting("training_sound") and PlaySoundFile then
        PlaySoundFile("Sound\\Interface\\igMainMenuOptionCheckBoxOn.wav")
    end
end

-- ============================================================================
-- POST-PHASE 2: TRAINING MODE (toggle: ALT-SHIFT-L)
-- Keeps recommending on a live target out of combat (e.g. a training dummy)
-- instead of hiding the window.
-- ============================================================================
function DH:ToggleTrainingMode()
    if not self.db then return end
    local v = not (self:GetSetting("training_mode") == true)
    self:SetSetting("training_mode", v)
    self:Print(L("Training mode: ") .. (v and L("ON") or L("OFF")))
    if self.UpdateRecommendations then self:UpdateRecommendations() end
    if self.NotifyOptions then self:NotifyOptions() end
    return v
end

-- ============================================================================
-- v3.3.0 PHASE 2: EXAM MODE (toggle: ALT-SHIFT-E)
-- The icon window still shows REC1 but the action bars are never highlighted,
-- so the player must recognise the ability themselves.
-- ============================================================================
function DH:ToggleExamMode()
    if not self.db then return end
    local v = not (self:GetSetting("exam_mode") == true)
    self:SetSetting("exam_mode", v)
    if ns.ResetAnalytics then ns.ResetAnalytics() end
    self:Print(L("Exam mode: ") .. (v and L("ON") or L("OFF")))
    if self.UpdateRecommendations then self:UpdateRecommendations() end
    if self.NotifyOptions then self:NotifyOptions() end
    return v
end

-- ============================================================================
-- v3.3.0 PHASE 2: MENTOR MODE (toggle: ALT-SHIFT-M)
-- Counts consecutive mistakes and explains why when the threshold is reached.
-- ============================================================================
function DH:ToggleMentorMode()
    if not self.db then return end
    local v = not (self:GetSetting("mentor_mode") == true)
    self:SetSetting("mentor_mode", v)
    ns.mentorErrors = 0
    ns.mentorCorrect = 0
    self:Print(L("Mentor mode: ") .. (v and L("ON") or L("OFF")))
    if self.UpdateRecommendations then self:UpdateRecommendations() end
    if self.NotifyOptions then self:NotifyOptions() end
    return v
end

-- ============================================================================
-- POST-PHASE 4: PVP MODE (toggle: ALT-SHIFT-V)
-- Switches activity_profile to "pvp" and back to the previous profile.
-- ============================================================================

function DH:TogglePvPMode()
    if not self.db then return end
    if self:GetSetting("pvp_mode_enabled") then
        self:SetSetting("pvp_mode_enabled", false)
        self:Print(L("PvP mode: ") .. L("OFF"))
    else
        self:SetSetting("pvp_mode_enabled", true)
        self:Print(L("PvP mode: ") .. L("ON") .. " (" .. L("burst under")
            .. " " .. tostring(self:GetSetting("pvp_burst_threshold") or 50) .. "%)")
    end
    if self.UpdateRecommendations then self:UpdateRecommendations() end
    if self.NotifyOptions then self:NotifyOptions() end
end

-- ============================================================================
-- POST-PHASE 3: HEAL-SPEC DPS ROTATIONS (heal_dps_mode = "auto"/"on"/"off")
-- When the active mode is a "safe" healer mode, borrow the class's closest
-- DPS rotation. FilterKnown drops abilities the healer has not learned and the
-- central fallback keeps the UI alive, so nothing wrong is recommended.
-- ============================================================================
local HEAL_DPS_MODE = {
    discipline = "discipline_dps",
    holy_priest = "holy_priest_dps",
    holy_paladin = "holy_paladin_dps",
    resto_druid = "resto_druid_dps",
    resto_shaman = "resto_shaman_dps",
}

-- Should a healer run the borrowed DPS rotation right now?
function DH:IsHealDpsActive()
    local setting = self:GetSetting("heal_dps_mode")
    if setting == false or setting == "off" then return false end
    if setting == true or setting == "on" then return true end
    -- "auto" (default): only while solo / not grouped
    local prof = self:GetSetting("activity_profile") or "raid"
    if prof == "solo" then return true end
    if IsInRaid and IsInRaid() then return false end
    if IsInGroup and IsInGroup() then return false end
    return true
end

-- Return the DPS mode to borrow for a safe (healer) mode, or nil
function DH:GetHealDpsMode(mode)
    if not mode or not mode.safe then return nil end
    if not self:IsHealDpsActive() then return nil end
    local dpsKey = HEAL_DPS_MODE[mode.key]
    if not dpsKey then return nil end
    local modes = ns.registered and ns.registered.modes
    if not modes then return nil end
    for _, m in ipairs(modes) do
        if m.key == dpsKey then return m end
    end
    return nil
end


-- Update recommendations (single implementation).
-- Smoothing / decision logging are provided by Config.lua via ns.*
-- and are optional here so the core still works if Config did not load.
function DH:UpdateRecommendations()
    -- Glow test overrides the normal target/combat gating so the user can
    -- verify action-bar detection any time (see ns.ShowTestGlow).
    if ns.IsTestGlow and ns.IsTestGlow() then
        self:UpdateUI()
        return
    end
    if not self.db or not self.db.enabled then
        ns.recommendations = {}
        self:HideUI()
        return
    end
    if self.db.paused then
        -- /rc pause: keep the window up (so it can show "Paused") but stop
        -- recommending. UpdateUI drives the idle-reason text.
        ns.recommendations = {}
        self:UpdateUI()
        return
    end
    local training = (self:GetSetting("training_mode") == true)
    if not UnitExists("target") and not ns.inCombat and not training then
        ns.recommendations = {}
        self:HideUI()
        -- Still refresh the icon window so it can show an idle reason
        -- (phase 1.2) instead of silently disappearing.
        self:UpdateUI()
        return
    end

    -- Ensure state is updated (throttled/cached inside State:Reset)
    self:UpdateState()

    local mode = self.GetActiveMode and self:GetActiveMode() or nil
    local recommendations = {}

    -- Healer in a "safe" mode: borrow the class's DPS rotation when allowed
    local rotationMode = mode
    if mode and mode.safe then
        local dps = self.GetHealDpsMode and self:GetHealDpsMode(mode)
        if dps then rotationMode = dps end
    end

    -- Post-phase 4: PvP priority branch takes over when enabled for this class
    local pvpRotation = ns.registered.pvpRotation
    if rotationMode and self:GetSetting("pvp_mode_enabled") and pvpRotation then
        local threshold = tonumber(self:GetSetting("pvp_burst_threshold")) or 50
        local target = self.State and self.State.target
        local hp = target and target.health and target.health.pct or 100
        recommendations = pvpRotation(self, self.State, {
            burst = hp <= threshold,
            burstThreshold = threshold,
        }) or {}
    elseif rotationMode and rotationMode.rotation then
        recommendations = rotationMode.rotation(self) or {}
    end

    -- Improvement 6: a user-authored APL replaces the class rotation when it
    -- is enabled and parsed to at least one rule.
    if self:GetSetting("custom_apl_enabled") == true and ns.EvaluateAPL then
        local aplRecs, aplValid = ns.EvaluateAPL(self)
        if aplValid then recommendations = aplRecs end
    end

    -- phase-3 #1: a "simple" adaptive rotation shows only the top ability.
    if self.IsSimpleRotation and self:IsSimpleRotation() and #recommendations > 1 then
        recommendations = { recommendations[1] }
    end

    -- Never recommend abilities the player has not learned yet
    recommendations = self:FilterKnown(recommendations)

    -- Central fallback: if a rotation produced nothing for an attackable
    -- target, recommend the first known basic ability instead of showing
    -- "Rec: none" with a dead UI. This is the safety net for specs/modes
    -- whose single-target branch returns nil (e.g. target_mode = "single").
    if #recommendations == 0 then
        local tgt = self.State and self.State.target
        -- Only fall back when there is something to hit (or no target data);
        -- never suggest attacking a friendly / non-attackable target.
        if (not tgt) or (tgt.canAttack ~= false) then
            local fb = self.FirstKnownFallback and self:FirstKnownFallback()
            if fb then
                recommendations = { { ability = fb, priority = 1 } }
            end
        end
    end

    -- Apply smoothing to prevent stutter (provided by Config.lua)
    if ns.SmoothRecommendations then
        recommendations = ns.SmoothRecommendations(recommendations)
    end

    -- Training / mentor mode: annotate every recommendation with a short
    -- reason and announce REC1 changes (chat/sound), throttled to changes.
    if self:GetSetting("training_mode") or self:GetSetting("mentor_mode") then
        for i = 1, #recommendations do
            local rk, name = self:DescribeRecommendation(recommendations[i])
            recommendations[i].reason_key = rk
            if rk and name and self:GetSetting("training_mode") then
                recommendations[i].reason = L(rk) .. " (" .. name .. ")"
            end
        end
    end

    ns.recommendations = recommendations

    -- Prompt 2: record the recommendation set for /rc stats (Improvement 3).
    ns.RecordRecommendations(self, recommendations)

    -- v3.3.0: refresh the live DPS forecast (throttled by its own interval).
    if ns.UpdateDPSForecast then ns.UpdateDPSForecast(self) end

    if self:GetSetting("training_mode") then
        self:MaybeTrainingChat(recommendations)
    end

    -- Decision log (provided by Config.lua)
    if ns.LogDecision and self:GetSetting("log_decisions") then
        ns.LogDecision(self, recommendations)
    end

    if #recommendations > 0 then
        self:ShowUI()
    end
    self:UpdateUI()
end

-- ============================================================================
-- UI FUNCTIONS (implemented in UI.lua - action bar glow display)
-- ============================================================================

function DH:InitializeUI()
    if ns.InitializeUI then
        ns.InitializeUI(self)
    end
end

function DH:UpdateUI()
    if ns.UpdateUI then
        ns.UpdateUI(self)
    end
end

function DH:ShowUI()
    if ns.ShowUI then
        ns.ShowUI()
    else
        ns.glowVisible = true
    end
end

function DH:HideUI()
    if ns.HideUI then
        ns.HideUI()
    else
        ns.glowVisible = false
        if ns.ClearGlows then ns.ClearGlows() end
    end
end


-- ============================================================================
-- v3.4.0 FEATURE PACK (part 2): status data,
-- skins, boss-class profiles, deep timeline, memory/load/compat helpers.
-- ============================================================================

ns._loadedAt = ns._loadedAt or GetTime()

ns.BUILD = {
    version = "3.4.0",
    interface = 30300,
    author = "Custom",
    date = "2026-10-13",
    files = 36,
    loc = 31667,
}

-- ---------------------------------------------------------------------------
-- STATUS TAB DATA
-- ---------------------------------------------------------------------------

function DH:GetOwnAddonIndex()
    if type(GetNumAddOns) ~= "function" or type(GetAddOnInfo) ~= "function" then
        return nil
    end
    local okN, n = pcall(GetNumAddOns)
    if not okN or type(n) ~= "number" then return nil end
    for i = 1, n do
        local ok, name = pcall(GetAddOnInfo, i)
        if ok and name == "RotationCore" then return i end
    end
    return nil
end

ns.metrics = ns.metrics or { memMB = nil, cpu = nil, at = 0 }

-- Refresh the memory / CPU readings at most once every couple of seconds and
-- cache them, so the live Status rows stay informative without hammering the
-- API every tick.
function ns.UpdateMetrics()
    local idx = DH.GetOwnAddonIndex and DH:GetOwnAddonIndex()
    if not idx then return end
    if type(UpdateAddOnMemoryUsage) == "function" then
        pcall(UpdateAddOnMemoryUsage)
    end
    if type(GetAddOnMemoryUsage) == "function" then
        local ok, m = pcall(GetAddOnMemoryUsage, idx)
        if ok and m then ns.metrics.memMB = m / 1024 end
    end
    if type(GetAddOnCPUUsage) == "function" then
        local ok, c = pcall(GetAddOnCPUUsage, idx)
        if ok and c then ns.metrics.cpu = c end
    end
    ns.metrics.at = GetTime()
end

function DH:GetAddonState()
    local enabled = self.db and self.db.enabled ~= false
    local spec = self.GetActiveSpec and self:GetActiveSpec() or "?"
    local mode = self.GetActiveMode and self:GetActiveMode()
    local modeName = mode and (mode.name or mode.key) or "?"
    local role = "?"
    if mode and mode.key and self.db and self.db[mode.key] then
        role = self.db[mode.key].role or "?"
    end
    if ns.UpdateMetrics and (GetTime() - (ns.metrics.at or 0)) > 2 then
        ns.UpdateMetrics()
    end
    return {
        enabled = enabled,
        spec = spec,
        specRole = role,
        mode = modeName,
        profile = self:GetCurrentProfileName(),
        spellframe = self.db and self.db.display and self.db.display.show_spellframe ~= false,
        updateActive = self:IsUpdateActive() and true or false,
        memoryMB = ns.metrics.memMB,
        cpu = ns.metrics.cpu,
        uptime = ns._loadedAt and (GetTime() - ns._loadedAt) or 0,
        errors = #(ns.errorLog or {}),
        lastErrorAt = ns.lastErrorTime,
    }
end

function DH:HasLib(id)
    if type(LibStub) ~= "function" then return false end
    local ok, lib = pcall(LibStub, id, true)
    return ok and lib ~= nil
end

function DH:ScanIntegrations()
    local list = {}
    local function row(addon, found, what)
        list[#list + 1] = { addon = addon, found = not not found, what = what }
    end
    row("DBM", type(DBM) == "table" or type(DBMLoader) == "table", "Timeline, boss phases")
    row("BigWigs", type(BigWigs) == "table" or type(BigWigsLoader) == "table", "Timeline, boss phases")
    row("ElvUI", type(ElvUI) == "table", "Action bars, cooldowns")
    row("Bartender4", type(Bartender4) == "table", "Action bars")
    row("Dominos", type(Dominos) == "table", "Action bars")
    row("WeakAuras", type(WeakAuras) == "table", "Display the rotation state")
    return list
end

-- ---------------------------------------------------------------------------
-- ADDON INTEROP: read the installed addons and flag likely conflicts.
-- Addons cannot read files from disk, so Interface\AddOns is inspected through
-- the addon-list API (GetNumAddOns / GetAddOnInfo), which reports every
-- installed addon together with its enabled / loaded state.
-- ---------------------------------------------------------------------------

ns.CONFLICT_RULES = {
    {
        id = "rotation", min = 1, level = "high",
        addons = { "MaxDps", "Ovale", "Hekili", "SpellFlash", "CLCInfo", "CLCRet",
                   "AethysRotation", "RotationMaster" },
        reason = "Another rotation addon is installed. Both addons may highlight or queue abilities at the same time.",
        suggest = "Use only one rotation helper at a time.",
    },
    {
        id = "actionbar", min = 2, level = "medium",
        addons = { "Bartender4", "Dominos", "ElvUI" },
        reason = "Several action-bar replacements are installed. They share the same buttons and can taint each other.",
        suggest = "Keep a single action-bar addon active.",
    },
    {
        id = "bossmod", min = 2, level = "low",
        addons = { "DBM", "BigWigs" },
        reason = "Two boss mods are installed; timeline hooks may fire twice.",
        suggest = "Run either DBM or BigWigs, not both.",
    },
}

function DH:ListInstalledAddons()
    local out = {}
    if type(GetNumAddOns) ~= "function" or type(GetAddOnInfo) ~= "function" then
        return out
    end
    local okN, n = pcall(GetNumAddOns)
    if not okN or type(n) ~= "number" then return out end
    for i = 1, n do
        local ok, name, title, _notes, enabled = pcall(GetAddOnInfo, i)
        if ok and type(name) == "string" and name ~= "" and name:sub(1, 9) ~= "Blizzard_" then
            out[#out + 1] = {
                name = name,
                title = (type(title) == "string" and title ~= "" and title) or name,
                enabled = (enabled ~= nil and enabled ~= 0 and enabled ~= false) or false,
                loaded = (type(IsAddOnLoaded) == "function" and IsAddOnLoaded(name)) and true or false,
            }
        end
    end
    return out
end

-- Match an installed addon against a base name ("DBM" matches "DBM-Core").
local function MatchInstalledAddon(installed, token)
    for _, a in ipairs(installed) do
        if a.name == token or a.name:sub(1, #token) == token then
            return a
        end
    end
    return nil
end

function DH:ScanConflicts()
    local installed = self:ListInstalledAddons()
    local conflicts = {}
    for _, rule in ipairs(ns.CONFLICT_RULES) do
        local hits, active, names = {}, 0, {}
        for _, token in ipairs(rule.addons) do
            local a = MatchInstalledAddon(installed, token)
            if a then
                hits[#hits + 1] = a
                if a.enabled or a.loaded then
                    active = active + 1
                    names[#names + 1] = a.title
                end
            end
        end
        if active >= (rule.min or 1) then
            conflicts[#conflicts + 1] = {
                id = rule.id, level = rule.level, addons = names,
                reason = rule.reason, suggest = rule.suggest,
            }
        end
    end
    return conflicts
end

function DH:StatusReport()
    local st = self:GetAddonState()
    local buf = {}
    buf[#buf + 1] = "RotationCore v" .. tostring(self.Version or "?") .. " status"
    buf[#buf + 1] = string.format("Enabled: %s | Spec: %s (%s) | Mode: %s",
        st.enabled and "YES" or "NO", st.spec, st.specRole, st.mode)
    buf[#buf + 1] = string.format("Profile: %s | SpellFrame: %s | OnUpdate: %s",
        st.profile, st.spellframe and "shown" or "hidden",
        st.updateActive and "active" or "idle")
    buf[#buf + 1] = string.format("Memory: %.1f MB | Uptime: %ds | Errors: %d",
        st.memoryMB or 0, math.floor(st.uptime), st.errors)
    local ints = self:ScanIntegrations()
    local found = {}
    for _, r in ipairs(ints) do
        if r.found then found[#found + 1] = r.addon end
    end
    buf[#buf + 1] = "Integrations: " .. ((#found > 0 and table.concat(found, ", ")) or "none")
    return table.concat(buf, "\n")
end

function DH:GetLastErrors(n)
    local log = ns.errorLog or {}
    local out = {}
    local limit = math.min(n or 10, #log)
    for i = math.max(1, #log - limit + 1), #log do
        out[#out + 1] = log[i].msg
    end
    return out
end

-- ---------------------------------------------------------------------------
-- IMPROVEMENT 27: UI SKINS
-- ---------------------------------------------------------------------------

ns.DEFAULT_BG = "Interface\\DialogFrame\\UI-DialogBox-Background"
ns.DEFAULT_EDGE = "Interface\\DialogFrame\\UI-DialogBox-Border"

ns.UI_SKINS = ns.UI_SKINS or {}
ns.UI_SKINS.default = {
    name = "default",
    bg = ns.DEFAULT_BG, edge = ns.DEFAULT_EDGE,
    edgeSize = 16, tile = true, tileSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
    theme = {
        backdrop = { 0.05, 0.05, 0.05, 0.95 },
        border = { 0.3, 0.3, 0.3, 0.8 },
        title = { 1, 0.82, 0 },
        accent = { 1, 0.82, 0 },
        text = { 0.9, 0.9, 0.9 },
    },
}
ns.UI_SKINS.elvui = {
    name = "elvui",
    -- Flat modern look: solid plate + a razor-thin 1px edge.
    bg = "Interface\\Buttons\\WHITE8X8", edge = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1, tile = true, tileSize = 64,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
    theme = {
        backdrop = { 0.07, 0.07, 0.07, 0.97 },
        border = { 0.10, 0.10, 0.10, 0.98 },
        title = { 0.95, 0.78, 0.20 },
        accent = { 0.95, 0.55, 0.20 },
        text = { 0.90, 0.90, 0.90 },
    },
}
ns.UI_SKINS.minimal = {
    name = "minimal",
    bg = "Interface\\Buttons\\WHITE8X8", edge = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 8, tile = true, tileSize = 64,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
    theme = {
        backdrop = { 0.02, 0.02, 0.02, 0.86 },
        border = { 0.28, 0.28, 0.28, 0.7 },
        title = { 1, 1, 1 },
        accent = { 1, 1, 1 },
        text = { 0.95, 0.95, 0.95 },
    },
}
ns.UI_SKINS.classic = {
    name = "classic",
    bg = "Interface\\FrameGeneral\\UI-Background-Rock", edge = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 16, tile = true, tileSize = 256,
    insets = { left = 6, right = 6, top = 6, bottom = 6 },
    theme = {
        backdrop = { 0.34, 0.29, 0.19, 0.96 },
        border = { 0.72, 0.60, 0.32, 0.9 },
        title = { 1, 0.90, 0.50 },
        accent = { 1, 0.82, 0 },
        text = { 0.98, 0.95, 0.88 },
    },
}

-- v3.4.0-hotfix18: extra colour skins (flat WHITE8X8 plates + a thin edge).
local function FlatSkin(name, backdrop, border, title, accent, text)
    return {
        name = name,
        bg = "Interface\\Buttons\\WHITE8X8", edge = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8, tile = true, tileSize = 64,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
        theme = { backdrop = backdrop, border = border, title = title, accent = accent, text = text },
    }
end
ns.UI_SKINS.fel    = FlatSkin("fel",    { 0.05, 0.10, 0.04, 0.96 }, { 0.35, 0.65, 0.20, 0.9 }, { 0.55, 1.00, 0.35 }, { 0.55, 1.00, 0.35 }, { 0.90, 0.98, 0.88 })
ns.UI_SKINS.frost  = FlatSkin("frost",  { 0.04, 0.07, 0.11, 0.96 }, { 0.30, 0.55, 0.85, 0.9 }, { 0.55, 0.80, 1.00 }, { 0.35, 0.70, 1.00 }, { 0.90, 0.95, 1.00 })
ns.UI_SKINS.void   = FlatSkin("void",   { 0.07, 0.04, 0.11, 0.96 }, { 0.50, 0.30, 0.80, 0.9 }, { 0.78, 0.55, 1.00 }, { 0.62, 0.40, 1.00 }, { 0.94, 0.90, 1.00 })
ns.UI_SKINS.blood  = FlatSkin("blood",  { 0.10, 0.03, 0.03, 0.96 }, { 0.75, 0.18, 0.18, 0.9 }, { 1.00, 0.45, 0.40 }, { 0.95, 0.25, 0.20 }, { 1.00, 0.90, 0.88 })
ns.UI_SKINS.jade   = FlatSkin("jade",   { 0.03, 0.09, 0.08, 0.96 }, { 0.20, 0.70, 0.60, 0.9 }, { 0.40, 0.95, 0.80 }, { 0.25, 0.85, 0.70 }, { 0.88, 0.98, 0.95 })
ns.UI_SKINS.gold   = FlatSkin("gold",   { 0.11, 0.08, 0.02, 0.96 }, { 0.85, 0.65, 0.15, 0.9 }, { 1.00, 0.85, 0.35 }, { 1.00, 0.75, 0.20 }, { 1.00, 0.96, 0.85 })
ns.UI_SKINS.ember  = FlatSkin("ember",  { 0.11, 0.05, 0.02, 0.96 }, { 0.90, 0.45, 0.10, 0.9 }, { 1.00, 0.60, 0.25 }, { 1.00, 0.50, 0.15 }, { 1.00, 0.92, 0.85 })

function DH:GetUISkin()
    local name = self.GetSetting and self:GetSetting("ui_skin") or "default"
    local skin = ns.UI_SKINS[name]
    if skin then return skin end
    return ns.UI_SKINS.default
end

function DH:RegisterSkin(name, def)
    if type(name) ~= "string" or type(def) ~= "table" then return false end
    ns.UI_SKINS[name] = def
    return true
end

-- ---------------------------------------------------------------------------
-- IMPROVEMENT 4 (v3.4.0): BOSS PROFILES X CLASS X SPEC
-- Stored under db.common.bossClassProfiles[bossId][class][spec] = settings.
-- ---------------------------------------------------------------------------

function DH:GetBossClassProfile(bossId, class, spec)
    local root = self.db and self.db.common and self.db.common.bossClassProfiles
    return root and root[tostring(bossId)] and root[tostring(bossId)][class]
        and root[tostring(bossId)][class][spec] or nil
end

function DH:SetBossClassProfile(bossId, class, spec, data)
    if not (self.db and self.db.common) then return end
    if type(self.db.common.bossClassProfiles) ~= "table" then
        self.db.common.bossClassProfiles = {}
    end
    local root = self.db.common.bossClassProfiles
    local cid = tostring(bossId)
    root[cid] = root[cid] or {}
    root[cid][class] = root[cid][class] or {}
    root[cid][class][spec] = data
end

function DH:DeleteBossClassProfile(bossId, class, spec)
    local p = self:GetBossClassProfile(bossId, class, spec)
    if not p then return false end
    local root = self.db.common.bossClassProfiles
    root[tostring(bossId)][class][spec] = nil
    return true
end

function DH:CurrentClassSpec()
    local cls = self.playerClass or select(2, UnitClass("player"))
    local spec = self.GetActiveSpec and self:GetActiveSpec() or nil
    if not spec and self.GetActiveMode then
        spec = (self:GetActiveMode() or {}).key
    end
    return tostring(cls or "?"), tostring(spec or "?")
end

function DH:ApplyEncounterBossClassProfile(encounterID, encounterName)
    if (self:GetSetting("boss_profile_autoload")) ~= true then return false end
    if not encounterID then return false end
    local cls, spec = self:CurrentClassSpec()
    local prof = self:GetBossClassProfile(encounterID, cls, spec)
    if not prof then return false end
    local count = 0
    for k, v in pairs(prof) do
        if type(v) ~= "table" then
            self:SetSetting(k, v)
            count = count + 1
        end
    end
    if count > 0 and self.Print then
        self:Print(L("Boss profile applied: ") .. tostring(encounterName or encounterID)
            .. " (" .. cls .. "/" .. spec .. ")")
    end
    return count > 0
end

-- ---------------------------------------------------------------------------
-- IMPROVEMENT 17: DEEP TIMELINE (BigWigs messages -> phase events)
-- ---------------------------------------------------------------------------

ns.timelinePhaseEvents = {}

function DH:SetupDeepTimeline()
    if not (self.GetSetting and self:GetSetting("timeline_deep_enabled")) then return end
    if ns.InitTimeline then ns.InitTimeline() end
end

function DH:OnDeepMessage(addon, msg, ...)
    local text = tostring(msg or "")
    ns.RecordPhaseEvent(text)
    if (self.GetSetting and self:GetSetting("timeline_deep_enabled"))
        and (self:GetSetting("timeline_phase_announce")) ~= false and self.Print then
        self:Print("|cFF9ECBFF[phases]|r " .. text)
    end
end

-- ---------------------------------------------------------------------------
-- IMPROVEMENTS 22 / 23 / 24: MEMORY / LOAD / COMPAT
-- ---------------------------------------------------------------------------

ns._spellCache = {}
ns._spellCacheVersion = 0

function DH:GetCachedSpellInfo(id)
    if ns._spellCache[id] then return ns._spellCache[id] end
    if type(GetSpellInfo) ~= "function" then return nil end
    local name, rank, icon = GetSpellInfo(id)
    ns._spellCache[id] = { name = name, rank = rank, icon = icon }
    return ns._spellCache[id]
end

function DH:MemCleanupFight()
    ns.timelinePhaseEvents = ns.timelinePhaseEvents or {}
end

function DH:RunCompatCheck()
    local log = {}
    if type(ElvUI) == "table" then
        log[#log + 1] = "ElvUI skin detected - if the highlight looks wrong, try ui_skin = elvui."
    end
    if type(Bartender4) == "table" or type(Dominos) == "table" then
        log[#log + 1] = "Custom action bars detected (Bartender4/Dominos)."
    end
    return log
end

-- ---------------------------------------------------------------------------
-- LIFECYCLE WRAPPERS: feed the new features from the existing flow.
-- ---------------------------------------------------------------------------

-- Feature pack attaches through hooks (no method wrapping).
DH:RegisterHook("EndFight", function(endStatus)
    DH:MemCleanupFight()
end)

DH:RegisterHook("OnEncounterStart", function(encounterID, encounterName)
    if (DH.GetSetting and DH:GetSetting("timeline_deep_enabled")) == true
        and DH.SetupDeepTimeline then
        DH:SetupDeepTimeline()
    end
    DH:ApplyEncounterBossClassProfile(encounterID, encounterName)
end)

-- UpdateRecommendations keeps a thin wrapper: it transforms the return value.
local _updateRecs = DH.UpdateRecommendations

function DH:UpdateRecommendations()
    local ok, recs = pcall(_updateRecs, self)
    if ok and type(recs) == "table" then
        return recs
    end
    if ok then
        return ns.recommendations or {}
    end
    if self.Print then self:Print(L("UpdateRecommendations error: ") .. tostring(recs)) end
    return {}
end

-- Compat check at login (guarded by the setting).
if type(GetTime) == "function" and ns._loadedAt then
    local f = CreateFrame("Frame", "RotationCoreCompatTimer", UIParent)
    f:SetScript("OnUpdate", function(self, elapsed)
        self.t = (self.t or 0) + elapsed
        if self.t < 3 then return end
        self:SetScript("OnUpdate", nil)
        self:Hide()
        local log = DH:RunCompatCheck()
        for _, line in ipairs(log) do
            if DH.Print then DH:Print(line) end
        end
    end)
    f:Show()
end

-- ============================================================================
-- v3.4.0 SLASH COMMANDS (arena, memory, load time)
-- ============================================================================

DH:RegisterSlashCommand("arena", function()
    local nextMode = DH:CycleArenaMode() or "auto"
    DH:Print(L("Arena mode: ") .. tostring(nextMode))
end, "arena - cycle arena mode (auto/2v2/3v3/5v5)")

DH:RegisterSlashCommand("mem", function()
    local kb = 0
    local idx = DH:GetOwnAddonIndex()
    if idx then
        if type(UpdateAddOnMemoryUsage) == "function" then
            pcall(UpdateAddOnMemoryUsage)
        end
        if type(GetAddOnMemoryUsage) == "function" then
            local ok, m = pcall(GetAddOnMemoryUsage, idx)
            if ok then kb = m or 0 end
        end
    end
    DH:Print(string.format(L("RotationCore memory: %.2f MB"), (kb or 0) / 1024))
end, "mem - show addon memory usage")

DH:RegisterSlashCommand("loadtime", function()
    local up = ns._loadedAt and (GetTime() - ns._loadedAt) or 0
    DH:Print(string.format(L("RotationCore loaded: %.1f s ago"), up))
end, "loadtime - show time since load")

-- ============================================================================
-- v3.4.0: AUTO-ADAPTATION TO THE CURRENT CONTENT.
-- Maps the player's situation onto the activity_profile that the rotations
-- use for fight-length/cooldown decisions:
--   raid instance -> raid | party dungeon -> dungeon | arena/bg -> pvp
--   world, grouped -> dungeon (short-to-medium fights) | world, solo -> solo
-- ============================================================================

function DH:AutoDetectActivity()
    if type(GetInstanceType) ~= "function" then return nil end
    local ok, itype = pcall(GetInstanceType)
    local t = ok and itype or "none"
    if t == "raid" then return "raid" end
    if t == "party" then return "dungeon" end
    if t == "arena" or t == "pvp" then return "pvp" end
    local grouped = false
    if type(IsInGroup) == "function" and IsInGroup() then grouped = true end
    if type(IsInRaid) == "function" and IsInRaid() then grouped = true end
    if grouped then return "dungeon" end
    return "solo"
end

-- v3.4.0: normalised instance kind ("dungeon" / "raid" / "arena" / "pvp" / nil).
function DH:GetInstanceKind()
    if type(GetInstanceType) ~= "function" then return nil end
    local ok, t = pcall(GetInstanceType)
    t = ok and t or nil
    if t == "party" then return "dungeon" end
    if t == "raid" then return "raid" end
    return t
end

-- v3.4.0: NPC (creature) id from UnitGUID. This is locale-independent, unlike
-- UnitName which is localised. Format: [type]-0-[server]-[instance]-[zone]-[npc]-[spawn].
function DH:GetUnitNpcID(unit)
    if type(UnitGUID) ~= "function" then return nil end
    local ok, guid = pcall(UnitGUID, unit or "target")
    if not ok or type(guid) ~= "string" then return nil end
    local id = select(6, strsplit("-", guid))
    return tonumber(id)
end

-- v3.4.0: 5-man bosses do not reliably fire ENCOUNTER_START in 3.3.5a, and
-- ENCOUNTER_START carries a DungeonEncounter id (not the NPC id), so presets are
-- matched against the current target's NPC id (locale-independent) for both
-- raids and dungeons. A stored encounter profile (applied by ENCOUNTER_START)
-- always wins: we never clobber an active non-target override.
function DH:HandleBossTarget()
    local kind = self:GetInstanceKind()
    local in_instance = (kind == "dungeon" or kind == "raid")
    if not (self.GetSetting and self:GetSetting("boss_profiles_enabled") == true)
       or not in_instance then
        if ns.bossTargetActive then
            self:RestoreDefaultProfile()
            ns.bossTargetActive = nil
        end
        return
    end
    local name = UnitExists("target") and UnitName("target") or nil
    local npc = self:GetUnitNpcID("target")
    local b = npc and self:FindPreset(npc, name, kind) or nil
    if not b and name then b = self:FindPreset(nil, name, kind) end
    if b then
        if ns.bossTargetActive ~= b.name then
            local can_apply = (not ns.bossBackup.active)
                or (ns.bossBackup.src == "target")
            if can_apply then
                if ns.bossBackup.active then self:RestoreDefaultProfile() end
                if self:ApplyBossPresetFor(b.id, b.name, kind) then
                    if ns.bossBackup.active then ns.bossBackup.src = "target" end
                    ns.bossTargetActive = b.name
                    self:Print(L("Boss profile applied: ") .. tostring(b.name))
                end
            end
        end
    elseif ns.bossTargetActive then
        self:RestoreDefaultProfile()
        ns.bossTargetActive = nil
    end
end

-- v3.4.0: clear a target-detected boss override once its fight is over.
function DH:HandleBossCombatEnd()
    if not ns.bossTargetActive then return end
    local kind = self:GetInstanceKind()
    local name = UnitExists("target") and UnitName("target") or nil
    local npc = self:GetUnitNpcID("target")
    local b = npc and self:FindPreset(npc, name, kind) or nil
    if not b and name then b = self:FindPreset(nil, name, kind) end
    if not b or b.name ~= ns.bossTargetActive then
        self:RestoreDefaultProfile()
        ns.bossTargetActive = nil
    end
end

function DH:RefreshAutoActivity()
    if (self.GetSetting and self:GetSetting("auto_activity")) ~= true then return end
    if not self.db then return end
    local v = self:AutoDetectActivity()
    if not v then return end
    local cur = self:GetSetting("activity_profile")
    if cur ~= v then
        self:SetSetting("activity_profile", v)
        if self.NotifyOptions then self:NotifyOptions() end
    end
end

do
    local af = CreateFrame("Frame", "RotationCoreActivity", UIParent)
    af:RegisterEvent("PLAYER_ENTERING_WORLD")
    af:RegisterEvent("PLAYER_LEAVING_WORLD")
    af:RegisterEvent("GROUP_ROSTER_UPDATE")
    af:RegisterEvent("UPDATE_INSTANCE_INFO")
    af:RegisterEvent("ENCOUNTER_START")
    af:RegisterEvent("ENCOUNTER_END")
    af:SetScript("OnEvent", function()
        if DH.RefreshAutoActivity then DH:RefreshAutoActivity() end
        if DH.HandleBossTarget then DH:HandleBossTarget() end
    end)
end

function DH:DebugCooldowns()
    local on = (self.GetSetting and self:GetSetting("show_cooldowns_display")) == true
    local shown, count, alpha, pos = false, 0, 0, {}
    if ns.CooldownState then
        shown, count, alpha, pos = ns.CooldownState()
    end
    self:Print(string.format(
        "Cooldowns window: exists=%s isShown=%s alpha=%s pos=%s,%s count=%s show_setting=%s",
        tostring(ns.CooldownState ~= nil and ns.lastCdConfig ~= nil or false),
        tostring(shown),
        alpha and string.format("%.1f", alpha) or "?",
        pos and tostring(pos.x) or "?", pos and tostring(pos.y) or "?",
        tostring(count), tostring(on)))
    if not on and self.SetSetting then
        self:SetSetting("show_cooldowns_display", true)
        self:Print(L("Show cooldowns window: ENABLED. Drag it to move; /rc lock to stop."))
    end
    if ns.RefreshExtraFrames then ns.RefreshExtraFrames() end
end

DH:RegisterSlashCommand("cleanup", function()
    if ns.CleanupExtraFrames then ns.CleanupExtraFrames() end
    if ns.HideAllWindows then ns.HideAllWindows() end
    if DH.ApplyShellStyle then DH:ApplyShellStyle() end
    DH:Print(L("UI frames cleaned; shell style reapplied."))
end, "cleanup - recreate UI frames / reapply shell style")

DH:RegisterSlashCommand("debug", function(cmd)
    if cmd:match("debug cooldowns") then
        DH:DebugCooldowns()
    else
        DH:Print(L("Usage: /rc debug cooldowns"))
    end
end, "debug cooldowns - inspect the cooldowns window")
