-- Behavior tests. Loaded after mock.lua, RotationCore.lua, Heal.lua and the
-- selected class files. Results are exposed as TEST_SUMMARY.

local DH = RotationCore
local ns = DH.ns

TEST_SUMMARY = { passed = 0, failed = 0, results = {} }

local function check(name, condition, detail)
    if condition then
        TEST_SUMMARY.passed = TEST_SUMMARY.passed + 1
        TEST_SUMMARY.results[#TEST_SUMMARY.results + 1] = "PASS " .. name
        return
    end
    TEST_SUMMARY.failed = TEST_SUMMARY.failed + 1
    TEST_SUMMARY.results[#TEST_SUMMARY.results + 1] = "FAIL " .. name .. (detail and (" - " .. tostring(detail)) or "")
end

local function reset()
    mock.group = false
    mock.party = {}
    mock.raid = {}
    mock.roles = {}
    mock.health = { player = 100 }
    mock.healthMax = { player = 100 }
    mock.level = 80
    mock.spellbook = {}
    mock.spellNames = {}
    mock.power = { player = 100 }
    mock.enemies = {}
    mock.known = {}
    mock.cooldowns = {}
    mock.auras = {}
    mock.target = false
    mock.inInstance = false
    mock.instanceType = "none"
    mock.combat = false
    DH.db = {
        mode = "feral_cat",
        common = {
            target_mode = "single",
            aoe_threshold = 4,
            cleave_threshold = 2,
            heal_dps_mode = "auto",
            activity_profile = "raid",
            timeline_auto_phase = false,
        },
    }
end

local function injuredParty(count, hp)
    mock.group = true
    mock.party = {}
    for i = 1, count do
        local unit = "party" .. i
        mock.party[i] = unit
        mock.health[unit] = hp or 40
        mock.healthMax[unit] = 100
        mock.roles[unit] = (i == 1) and "TANK" or "NONE"
    end
end

local function setTarget(pct, maxHp)
    maxHp = maxHp or 1000
    mock.target = true
    mock.enemies.target = true
    mock.health.target = math.max(1, math.floor(maxHp * pct / 100))
    mock.healthMax.target = maxHp
    local st = DH.State
    st.target.exists = true
    st.target.canAttack = true
    st.target.health.current = mock.health.target
    st.target.health.max = maxHp
    st.target.health.pct = pct
    st.target.time_to_die = pct < 20 and 10 or 30
    st.active_enemies = 1
end

local function findMode(key)
    for _, mode in ipairs(ns.registered.modes or {}) do
        if mode.key == key then
            return mode
        end
    end
    return nil
end

local function recsFor(key)
    local mode = findMode(key)
    if not mode or not mode.rotation then
        return {}
    end
    return mode.rotation(DH) or {}
end

local function hasAbility(recs, key)
    for _, rec in ipairs(recs) do
        if rec.ability == key then
            return true
        end
    end
    return false
end

local function anyAbility(recs, keys)
    for _, key in ipairs(keys) do
        if hasAbility(recs, key) then
            return true
        end
    end
    return false
end

local function noDps(recs, keys)
    return not anyAbility(recs, keys)
end

local function healSpecTests(spec)
    if not findMode(spec.mode) then
        return
    end
    reset()
    injuredParty(1, 40)
    local recs = recsFor(spec.mode)
    check(spec.name .. ": emits a heal", anyAbility(recs, spec.heals), "no expected heal in recommendations")
    check(spec.name .. ": does not emit DPS", noDps(recs, spec.dps), "DPS ability leaked into a heal rotation")

    reset()
    injuredParty(1, 40)
    local noTargetRecs = recsFor(spec.mode)
    check(spec.name .. ": works without an enemy target", #noTargetRecs > 0, "heal rotation returned nothing")

    if spec.aoe then
        reset()
        injuredParty(3, 50)
        local aoeRecs = recsFor(spec.mode)
        check(
            spec.name .. ": uses AoE heal on stacked damage",
            anyAbility(aoeRecs, spec.aoe),
            "no AoE heal recommended"
        )
    end

    if spec.mana then
        reset()
        injuredParty(1, 40)
        mock.power.player = 10
        local lowManaRecs = recsFor(spec.mode)
        check(
            spec.name .. ": uses a mana tool at low mana",
            anyAbility(lowManaRecs, spec.mana),
            "no mana recovery ability recommended"
        )
    end

    if spec.dispel and spec.dispelAura then
        reset()
        injuredParty(1, 40)
        mock.auras.party1 = { { name = "Test " .. spec.dispelAura, debuffType = spec.dispelAura } }
        local dispelRecs = recsFor(spec.mode)
        check(
            spec.name .. ": dispels " .. spec.dispelAura,
            anyAbility(dispelRecs, spec.dispel),
            "no dispel recommended"
        )
    end
end

local SPECS = {
    {
        mode = "resto_druid",
        name = "Resto Druid",
        heals = { "lifebloom", "rejuvenation", "regrowth", "healing_touch", "nourish" },
        dps = { "wrath", "starfire", "mangle_cat" },
        aoe = { "wild_growth" },
        mana = { "innervate" },
        dispel = { "remove_curse" },
        dispelAura = "Curse",
    },
    {
        mode = "holy_paladin",
        name = "Holy Paladin",
        heals = { "holy_light", "flash_of_light", "holy_shock", "beacon_of_light" },
        dps = { "crusader_strike", "judgement_of_wisdom" },
        mana = { "divine_illumination" },
        dispel = { "cleanse" },
        dispelAura = "Magic",
    },
    {
        mode = "resto_shaman",
        name = "Resto Shaman",
        heals = { "earth_shield", "riptide", "healing_wave", "lesser_healing_wave" },
        dps = { "lightning_bolt", "lava_burst", "stormstrike" },
        aoe = { "chain_heal" },
        mana = { "mana_tide_totem" },
        dispel = { "cleanse_spirit" },
        dispelAura = "Curse",
    },
    {
        mode = "discipline",
        name = "Discipline Priest",
        heals = { "power_word_shield", "prayer_of_mending", "penance", "renew", "greater_heal" },
        dps = { "smite", "mind_blast", "holy_fire" },
        mana = { "hymn_of_hope" },
        dispel = { "dispel_magic" },
        dispelAura = "Magic",
    },
    {
        mode = "holy_priest",
        name = "Holy Priest",
        heals = { "power_word_shield", "renew", "prayer_of_mending", "flash_heal", "greater_heal" },
        dps = { "smite", "mind_blast", "holy_fire" },
        aoe = { "circle_of_healing" },
        mana = { "hymn_of_hope" },
        dispel = { "dispel_magic" },
        dispelAura = "Magic",
    },
}

for _, spec in ipairs(SPECS) do
    healSpecTests(spec)
end

-- Unknown spell: a critical tank must not get an unlearned Lay on Hands.
if findMode("holy_paladin") then
    reset()
    injuredParty(1, 10)
    mock.known[ns.SPELLS.LAY_ON_HANDS] = false
    local recs = recsFor("holy_paladin")
    check(
        "Unknown spell: unlearned Lay on Hands is filtered",
        not hasAbility(recs, "lay_on_hands"),
        "unlearned ability was recommended"
    )
end

-- Target mode resolution: single / cleave / AoE / explicit AoE.
reset()
DH.db.common.target_mode = "auto"
check("Target mode auto: 1 enemy is single", DH:ResolveTargetMode({ active_enemies = 1 }) == "single")
check("Target mode auto: 2 enemies is cleave", DH:ResolveTargetMode({ active_enemies = 2 }) == "cleave")
check("Target mode auto: 4 enemies is AoE", DH:ResolveTargetMode({ active_enemies = 4 }) == "aoe")
DH.db.common.target_mode = "aoe"
check("Target mode explicit AoE stays AoE", DH:ResolveTargetMode({ active_enemies = 1 }) == "aoe")

-- Heal mode resolution must prefer the heal mode over the DPS borrow.
if findMode("resto_druid") then
    check("MatchModeKey: resto resolves to the heal mode", DH:MatchModeKey("resto") == "resto_druid")
end
if findMode("holy_paladin") then
    check("MatchModeKey: holy resolves to the heal mode", DH:MatchModeKey("holy") == "holy_paladin")
end
if findMode("discipline") then
    check("MatchModeKey: discipline resolves to the heal mode", DH:MatchModeKey("discipline") == "discipline")
    check("MatchModeKey: holy resolves to the priest heal mode", DH:MatchModeKey("holy") == "holy_priest")
end

-- Heal-DPS borrow: grouped healers never borrow, solo they do.
if findMode("resto_druid") then
    reset()
    injuredParty(1, 40)
    check("Heal-DPS borrow: disabled in a group", DH:GetHealDpsMode(findMode("resto_druid")) == nil)
    reset()
    mock.group = false
    mock.party = {}
    local dps = DH:GetHealDpsMode(findMode("resto_druid"))
    check("Heal-DPS borrow: enabled solo", dps and dps.key == "resto_druid_dps")
end

-- Talent/spell cache invalidation.
do
    reset()
    local id = 12345
    mock.known[id] = false
    DH:InvalidateKnownSpells()
    check("Known-spell cache: unknown spell is filtered", DH:IsSpellKnownId(id) == false)
    mock.known[id] = true
    check("Known-spell cache: stays cached until invalidated", DH:IsSpellKnownId(id) == false)
    DH:InvalidateKnownSpells()
    check("Known-spell cache: rebuild after talent change", DH:IsSpellKnownId(id) == true)
end

-- Executor/finisher layer: the shared table must exist and class modules must
-- register at least one level-aware execute.
check("Executors: shared registry exists", type(ns.executors) == "table")

-- Low-level spellbook fallback: a player who only knows rank 1 Fire Blast
-- must still get the max-rank ID resolved to the learned lower rank.
if findMode("frost_mage") then
    reset()
    DH.db.mode = "frost_mage"
    mock.known[ns.SPELLS.FIRE_BLAST] = false
    mock.spellNames[ns.SPELLS.FIRE_BLAST] = "Fire Blast"
    mock.spellbook = { { name = "Fire Blast", id = 133 } }
    DH:InvalidateKnownSpells()
    check("Known-spell fallback: low-rank Fire Blast is known", DH:IsAbilityKnown("fire_blast"), "lower rank not resolved")
    check("Known-spell fallback: max rank resolves to learned rank", DH:ResolveKnownSpellId(ns.SPELLS.FIRE_BLAST) == 133)
end

-- Paladin: Hammer of Wrath is selected and the shared simulation marks it.
if findMode("ret") then
    reset()
    DH.db.mode = "ret"
    setTarget(15)
    local sim = {
        target_pct = 15,
        target_health = 150,
        cd = {},
        ready = function()
            return true
        end,
    }
    check("Paladin ret: Hammer of Wrath picker active", DH:PickExecutor(sim, "ret") == "hammer_of_wrath")
    local cfg = {
        gcdType = "melee",
        maxRecs = 1,
        cds = { hammer_of_wrath = "hammer_of_wrath" },
        baseCDs = { hammer_of_wrath = 6 },
        getPriority = function()
            return "hammer_of_wrath"
        end,
    }
    local recs = DH:RunSimulation(DH.State, cfg)
    check("Paladin ret: Hammer of Wrath marked execute", recs[1] and recs[1].ability == "hammer_of_wrath" and recs[1].execute == true)
end

-- Mage: Fire Blast is the instant finisher, not a normal filler.
if findMode("frost_mage") then
    reset()
    DH.db.mode = "frost_mage"
    setTarget(15)
    local sim = {
        target_pct = 15,
        target_health = 150,
        cd = {},
        ready = function()
            return true
        end,
    }
    check("Mage frost: Fire Blast picker active", DH:PickExecutor(sim, "frost_mage") == "fire_blast")
    local cfg = {
        gcdType = "spell",
        maxRecs = 1,
        cds = { fire_blast = "fire_blast" },
        baseCDs = { fire_blast = 8 },
        getPriority = function()
            return "fire_blast"
        end,
    }
    local recs = DH:RunSimulation(DH.State, cfg)
    check("Mage frost: Fire Blast marked execute", recs[1] and recs[1].ability == "fire_blast" and recs[1].execute == true)
    sim.target_pct = 80
    sim.target_health = 100000
    check("Mage frost: Fire Blast idle at 80%", DH:PickExecutor(sim, "frost_mage") == nil)
end

-- Druid: Ferocious Bite replaces Rip maintenance when the target is low.
if findMode("feral_cat") then
    reset()
    DH.db.mode = "feral_cat"
    setTarget(15)
    mock.power.player = 100
    mock.known[ns.SPELLS.FEROCIOUS_BITE or 48577] = true
    local sim = {
        cp = 5,
        energy = 100,
        target_pct = 15,
        target_health = 150,
        cd = {},
        ready = function()
            return true
        end,
    }
    check("Druid feral: Ferocious Bite picker active", DH:PickExecutor(sim, "feral_cat") == "ferocious_bite")
end

-- Queue length is a display concern, not a rotation-complexity concern.
-- Simple adaptive rotations must still feed the configured multi-icon queue.
do
    reset()
    ns.ResetSmoothing()
    local recs = {}
    for i = 1, 5 do
        recs[i] = { ability = "queue_test_" .. i }
    end
    local out = ns.SmoothRecommendations(recs)
    check("Queue: smoothing keeps slots beyond the third", #out == 5, "queue was truncated")
    check("Queue: fifth slot survives smoothing", out[5] and out[5].ability == "queue_test_5")

    ns.ResetSmoothing()
    local repeated = { { ability = "frostbolt" }, { ability = "frostbolt" }, { ability = "frostbolt" } }
    local preserved = ns.SmoothRecommendations(repeated)
    check(
        "Queue: smoothing preserves repeated filler icons",
        #preserved == 3 and preserved[2].ability == "frostbolt" and preserved[3].ability == "frostbolt"
    )

    ns.ResetSmoothing()
    local before = { { ability = "a" }, { ability = "b" }, { ability = "c" } }
    ns.SmoothRecommendations(before)
    local after = { { ability = "a", execute = true }, { ability = "b" }, { ability = "c" } }
    local marked = ns.SmoothRecommendations(after)
    check("Queue: execute flag bypasses the smoothing cache", marked[1] and marked[1].execute == true)
end

if DH.Class and DH.Class.abilities then
    reset()
    local oldGetActiveMode = DH.GetActiveMode
    local oldUpdateState = DH.UpdateState
    local oldIsSimpleRotation = DH.IsSimpleRotation
    local oldForecast = ns.UpdateDPSForecast
    local oldRecord = ns.RecordRecommendations

    local stubRecs = {}
    for i = 1, 5 do
        local key = "queue_stub_" .. i
        DH.Class.abilities[key] = { id = 900000 + i, name = key, texture = 134400 }
        stubRecs[i] = { ability = key, name = key, texture = 134400 }
    end

    DH.GetActiveMode = function()
        return { key = "queue_test", rotation = function() return stubRecs end }
    end
    DH.UpdateState = function() end
    DH.IsSimpleRotation = function() return true end
    ns.UpdateDPSForecast = function() end
    ns.RecordRecommendations = function() end
    DH.db = {
        enabled = true,
        mode = "queue_test",
        common = { target_mode = "single", aoe_threshold = 4, cleave_threshold = 2 },
        display = { spellframe_icons = 5 },
    }
    mock.target = true
    mock.enemies.target = true
    ns.ResetSmoothing()
    local out = DH:UpdateRecommendations()
    check("Queue: simple rotation keeps the multi-icon queue", type(out) == "table" and #out == 5, "queue was truncated")

    DH.GetActiveMode = oldGetActiveMode
    DH.UpdateState = oldUpdateState
    DH.IsSimpleRotation = oldIsSimpleRotation
    ns.UpdateDPSForecast = oldForecast
    ns.RecordRecommendations = oldRecord
end

-- A no-cooldown execute must not monopolise the simulation. Once an executor
-- is queued, the next pass has to fall through to the next distinct ability.
if findMode("frost_mage") then
    reset()
    DH.db.mode = "frost_mage"
    setTarget(15, 1000000)
    local cfg = {
        gcdType = "spell",
        maxRecs = 2,
        cds = { fire_blast = "fire_blast" },
        baseCDs = { fire_blast = 0 },
        getPriority = function(sim)
            return DH:PickExecutor(sim, "frost_mage") or "frostbolt"
        end,
    }
    local recs = DH:RunSimulation(DH.State, cfg)
    check(
        "Queue: queued executor falls through to the next ability",
        recs[1] and recs[1].ability == "fire_blast" and recs[2] and recs[2].ability == "frostbolt",
        "executor stayed at the top of the queue"
    )
end

-- Filler repeats are allowed to fill the visible queue; executors and
-- cooldown abilities remain distinct.
if findMode("frost_mage") then
    reset()
    DH.db.mode = "frost_mage"
    setTarget(100, 100000)
    local cfg = {
        gcdType = "spell",
        maxRecs = 3,
        allowDupes = true,
        getPriority = function()
            return "frostbolt"
        end,
    }
    local recs = DH:RunSimulation(DH.State, cfg)
    check(
        "Queue: filler repeats fill the requested icon count",
        #recs == 3 and recs[1].ability == "frostbolt" and recs[3].ability == "frostbolt",
        "filler was not repeated"
    )
end

-- Queue icon count: display/common must not disagree, or an old wizard value
-- of 1 silently overrides the configured 3-10 icons.
do
    reset()
    DH.db.display = {}
    DH.db.display.spellframe_icons = 1
    DH.db.common.spellframe_icons = 3
    check("Queue settings: stale display=1 + common=3 resolves to 3", DH:GetSpellFrameIconCount() == 3)
    DH:SetSpellFrameIconCount(5)
    check(
        "Queue settings: setter syncs display and common",
        DH.db.display.spellframe_icons == 5 and DH.db.common.spellframe_icons == 5
    )

    reset()
    DH.db.display = { spellframe_icons = 1 }
    check("Queue settings: legacy stored 1 repairs to 3", DH:GetSpellFrameIconCount() == 3)
    DH:SetSpellFrameIconCount(1)
    check("Queue settings: explicit 1 is respected", DH:GetSpellFrameIconCount() == 1)
end

-- Adaptive queue: the row shortens when the target will die in fewer casts,
-- and AoE uses the pack HP so the row does not collapse on a low-HP add.
if findMode("frost_mage") then
    local function frostQueue(hp, enemies, targetMode)
        reset()
        DH.db.mode = "frost_mage"
        DH.db.common.target_mode = targetMode
        setTarget(100, hp)
        DH.State.active_enemies = enemies
        DH.State.level = 80
        DH.State.stat = { spell_haste = 1, haste = 0, spell_power = 2000, attack_power = 0, crit = 0 }
        local cfg = {
            gcdType = "spell",
            maxRecs = 5,
            allowDupes = true,
            getPriority = function()
                return "frostbolt"
            end,
        }
        return DH:RunSimulation(DH.State, cfg)
    end

    check("Adaptive queue: low target HP shortens the row", #frostQueue(2000, 1, "single") == 1)
    check("Adaptive queue: high target HP fills the row", #frostQueue(100000, 1, "single") == 5)
    check(
        "Adaptive queue: AoE uses the pack HP",
        #frostQueue(2000, 4, "aoe") > #frostQueue(2000, 1, "single"),
        "AoE queue collapsed like a single target"
    )
end

-- Low level / no damage samples: HP percentage is the fallback so the row
-- still adapts instead of always showing the maximum number of icons.
if findMode("frost_mage") then
    reset()
    DH.db.mode = "frost_mage"
    setTarget(10)
    DH.State.level = 1
    DH.State.stat = { spell_haste = 1, haste = 0, spell_power = 0, attack_power = 0, crit = 0 }
    DH.ns.skillStats = {}
    local cfg = {
        gcdType = "spell",
        maxRecs = 5,
        allowDupes = true,
        getPriority = function()
            return "frostbolt"
        end,
    }
    local recs = DH:RunSimulation(DH.State, cfg)
    check("Adaptive queue: low-level HP fallback shortens the row", #recs == 1, tostring(#recs))
end
