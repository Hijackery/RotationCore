-- RotationCore_Mage/Core.lua
-- Priority rotation logic for Mage specs (3.3.5a compatible)
-- Uses core RunSimulation for CD-aware predictions

local DH = RotationCore
if not DH then return end

if select(2, UnitClass("player")) ~= "MAGE" then
    return
end

local ns = DH.ns
local class = DH.Class
local state = DH.State

-- ============================================================================
-- ARCANE ROTATION
-- ============================================================================

local arcaneConfig = {
    gcdType = "spell",
    maxRecs = 3,
    allowDupes = true,
    cds = {
        arcane_power = "arcane_power",
        icy_veins = "icy_veins",
        presence_of_mind = "presence_of_mind",
        mirror_image = "mirror_image",
        evocation = "evocation",
    },
    baseCDs = {
        arcane_power = 120,
        icy_veins = 180,
        presence_of_mind = 120,
        mirror_image = 180,
        evocation = 240,
    },
    initState = function(sim, s)
        -- Arcane Blast stacks
        sim.ab_stacks = s.buff.arcane_blast_aura.stacks or 0

        -- Procs
        sim.missile_barrage = s.buff.missile_barrage.up
        sim.clearcasting = s.buff.clearcasting.up

        -- Talents
        sim.has_arcane_power = s.talent.arcane_power.rank > 0
        sim.has_icy_veins = s.talent.icy_veins.rank > 0
        sim.has_pom = s.talent.presence_of_mind.rank > 0
        sim.has_barrage = s.talent.arcane_barrage.rank > 0
        sim.has_missile_barrage = s.talent.missile_barrage.rank > 0
    end,
    getPriority = function(sim, recs)
        -- Part 4: target mode (single / aoe / auto)
        local mode = DH:ResolveTargetMode(sim)
        if mode == "cleave" then
            return "arcane_explosion"
        end

        if mode == "aoe" or mode == "cleave" then
            if sim.mana_pct < (DH:GetSetting("mana_threshold_evocation") or 15)
               and DH:CanUseCooldown(sim, "evocation", "use_evocation")
               and sim.ttd > 8 then
                return "evocation"
            end
            return "arcane_explosion"
        end

        -- Evocation when mana low (part 5.2: configurable threshold)
        if sim.mana_pct < (DH:GetSetting("mana_threshold_evocation") or 15)
           and DH:CanUseCooldown(sim, "evocation", "use_evocation")
           and sim.ttd > 8 then
            return "evocation"
        end

        -- At 4 stacks: dump with Arcane Missiles, or Arcane Barrage when the
        -- talent is learned (it is a normal instant, not a cooldown).
        if sim.ab_stacks >= 4 then
            if sim.has_barrage then
                return "arcane_barrage"
            end
            return "arcane_missiles"
        end

        -- Missile Barrage proc at 3+ stacks: dump with free AM
        if sim.missile_barrage and sim.ab_stacks >= 3 then
            return "arcane_missiles"
        end

        -- Cooldown stacking: Icy Veins + Arcane Power + Mirror Image
        -- Use between AB casts (instants, don't break rotation)
        if sim.has_icy_veins and DH:CanUseCooldown(sim, "icy_veins", "use_icy_veins") then
            return "icy_veins"
        end

        if sim.has_arcane_power and DH:CanUseCooldown(sim, "arcane_power", "use_arcane_power") then
            return "arcane_power"
        end

        if DH:CanUseCooldown(sim, "mirror_image", "use_mirror_image") then
            return "mirror_image"
        end

        -- Presence of Mind (instant next AB at high stacks for burst)
        if sim.has_pom and sim.ab_stacks >= 2
           and DH:CanUseCooldown(sim, "presence_of_mind", "use_presence_of_mind") then
            return "presence_of_mind"
        end

        -- Build stacks with Arcane Blast
        return "arcane_blast"
    end,
    onCast = function(sim, key)
        if key == "arcane_blast" then
            sim.ab_stacks = math.min(4, sim.ab_stacks + 1)
        elseif key == "arcane_missiles" then
            sim.missile_barrage = false
            sim.ab_stacks = 0
        elseif key == "arcane_barrage" then
            sim.ab_stacks = 0
        end
    end,
    getAdvanceTime = function(sim, action)
        local h = sim.haste or 1
        if action == "arcane_blast" then return math.max(sim.gcd, 2.5 / h) end
        if action == "arcane_missiles" then
            -- Channeled: 5 ticks, but with Missile Barrage = faster
            if sim.missile_barrage then return math.max(sim.gcd, 2.5 / h) end
            return math.max(sim.gcd, 5.0 / h)
        end
        if action == "evocation" then return math.max(sim.gcd, 8.0 / h) end
        return sim.gcd  -- instants: arcane barrage, arcane power, POM
    end,
}

local function GetArcaneRecommendations(addon)
    return DH:RunSimulation(state, arcaneConfig)
end

-- ============================================================================
-- FIRE ROTATION
-- ============================================================================

local fireConfig = {
    gcdType = "spell",
    maxRecs = 3,
    allowDupes = true,
    cds = {
        combustion = "combustion",
        blast_wave = "blast_wave",
        mirror_image = "mirror_image",
        evocation = "evocation",
    },
    baseCDs = {
        combustion = 120,
        blast_wave = 30,
        mirror_image = 180,
        evocation = 240,
    },
    auras = {
        { up = "living_bomb_up", remains = "living_bomb_remains" },
        { up = "scorch_up", remains = "scorch_remains" },
    },
    initState = function(sim, s)
        -- DoTs/debuffs
        sim.living_bomb_up = s.debuff.living_bomb.up
        sim.living_bomb_remains = s.debuff.living_bomb.remains
        sim.scorch_up = s.debuff.improved_scorch.up
        sim.scorch_remains = s.debuff.improved_scorch.remains

        -- Procs
        sim.hot_streak = s.buff.hot_streak.up  -- instant Pyroblast
        sim.brain_freeze = s.buff.brain_freeze.up  -- instant Fireball/FFB
        sim.combustion_up = s.buff.combustion.up  -- Combustion buff active

        -- Talents
        sim.has_living_bomb = s.talent.living_bomb.rank > 0
        sim.has_hot_streak = s.talent.hot_streak.rank > 0
        sim.has_improved_scorch = s.talent.improved_scorch.rank > 0
        sim.has_combustion = s.talent.combustion.rank > 0
    end,
    getPriority = function(sim, recs)
        -- Part 4: target mode (single / aoe / auto)
        local mode = DH:ResolveTargetMode(sim)
        if mode == "cleave" then
            if sim.has_living_bomb and not sim.living_bomb_up and sim.ttd > 8 then
                return "living_bomb"
            end
            if sim:ready("flamestrike") then
                return "flamestrike"
            end
        end

        if mode == "aoe" or mode == "cleave" then
            if sim.mana_pct < (DH:GetSetting("mana_threshold_evocation") or 15)
               and DH:CanUseCooldown(sim, "evocation", "use_evocation")
               and sim.ttd > 8 then
                return "evocation"
            end
            -- Living Bomb > Blast Wave (cooldown) > Flamestrike filler
            if sim.has_living_bomb and not sim.living_bomb_up and sim.ttd > 8 then
                return "living_bomb"
            end
            if sim:ready("blast_wave") then
                return "blast_wave"
            end
            if sim:ready("flamestrike") then
                return "flamestrike"
            end
            -- Nothing AOE-specific ready: fall through to single rotation
        end

        -- Evocation when mana critically low (part 5.2)
        if sim.mana_pct < (DH:GetSetting("mana_threshold_evocation") or 15)
           and DH:CanUseCooldown(sim, "evocation", "use_evocation")
           and sim.ttd > 8 then
            return "evocation"
        end

        -- Hot Streak proc: instant Pyroblast (react immediately)
        if sim.has_hot_streak and sim.hot_streak then
            return "pyroblast"
        end

        -- Living Bomb: maintain DoT
        if sim.has_living_bomb and not sim.living_bomb_up and sim.ttd > 8 then
            return "living_bomb"
        end

        -- Scorch: maintain Improved Scorch debuff (part 5.1: refresh buffer)
        local buffer = DH:GetSetting("dot_refresh_buffer") or 2.0
        if sim.has_improved_scorch and (not sim.scorch_up or sim.scorch_remains < buffer) then
            return "scorch"
        end

        -- Combustion (major CD, only when buff not already active)
        if sim.has_combustion and not sim.combustion_up
           and DH:CanUseCooldown(sim, "combustion", "use_combustion") then
            return "combustion"
        end

        -- Mirror Image (major CD)
        if DH:CanUseCooldown(sim, "mirror_image", "use_mirror_image") then
            return "mirror_image"
        end

        -- Frostfire build: Frostfire Bolt replaces Fireball as the filler/proc
        -- dump. Guarded by IsSpellKnownId so non-FFB builds are unaffected.
        local is_ffb = (sim.build == "ffb" or sim.build == "ttw")
            and DH.IsSpellKnownId and DH:IsSpellKnownId(SPELLS.FROSTFIRE_BOLT)

        -- Brain Freeze proc: instant Fireball (Frostfire Bolt for FFB builds)
        if sim.brain_freeze then
            return is_ffb and "frostfire_bolt" or "fireball"
        end

        -- Fireball filler (Frostfire Bolt for FFB builds)
        if is_ffb then
            return "frostfire_bolt"
        end
        return "fireball"
    end,
    onCast = function(sim, key)
        if key == "pyroblast" then
            sim.hot_streak = false
        elseif key == "living_bomb" then
            sim.living_bomb_up = true
            sim.living_bomb_remains = 12
        elseif key == "scorch" then
            sim.scorch_up = true
            sim.scorch_remains = 30
        elseif key == "fireball" then
            sim.brain_freeze = false
        end
    end,
    getAdvanceTime = function(sim, action)
        local h = sim.haste or 1
        if action == "fireball" then
            if sim.brain_freeze then return sim.gcd end  -- instant with BF
            return math.max(sim.gcd, 3.0 / h)
        end
        if action == "pyroblast" then
            if sim.hot_streak then return sim.gcd end  -- instant with HS
            return math.max(sim.gcd, 5.0 / h)
        end
        if action == "scorch" then return math.max(sim.gcd, 1.5 / h) end
        if action == "frostfire_bolt" then
            if sim.brain_freeze then return sim.gcd end
            return math.max(sim.gcd, 3.0 / h)
        end
        if action == "evocation" then return math.max(sim.gcd, 8.0 / h) end
        return sim.gcd  -- instants: living bomb, combustion
    end,
}

local function GetFireRecommendations(addon)
    return DH:RunSimulation(state, fireConfig)
end

-- ============================================================================
-- FROST ROTATION
-- ============================================================================

local frostConfig = {
    gcdType = "spell",
    maxRecs = 3,
    allowDupes = true,
    cds = {
        icy_veins = "icy_veins",
        deep_freeze = "deep_freeze",
        cold_snap = "cold_snap",
        cone_of_cold = "cone_of_cold",
        mirror_image = "mirror_image",
        evocation = "evocation",
    },
    baseCDs = {
        icy_veins = 180,
        deep_freeze = 30,
        cold_snap = 480,
        cone_of_cold = 10,
        mirror_image = 180,
        evocation = 240,
    },
    initState = function(sim, s)
        -- Procs
        sim.fingers_of_frost = s.buff.fingers_of_frost.up
        sim.fof_stacks = s.buff.fingers_of_frost.stacks or 0
        sim.brain_freeze = s.buff.brain_freeze.up

        -- Talents
        sim.has_deep_freeze = s.talent.deep_freeze.rank > 0
        sim.has_icy_veins = s.talent.icy_veins.rank > 0
        sim.has_fof = s.talent.fingers_of_frost.rank > 0
        sim.has_brain_freeze = s.talent.brain_freeze.rank > 0
    end,
    getPriority = function(sim, recs)
        -- Part 4: target mode (single / aoe / auto)
        local mode = DH:ResolveTargetMode(sim)
        if mode == "cleave" then
            if sim:ready("cone_of_cold") then
                return "cone_of_cold"
            end
            if sim:ready("blizzard") then
                return "blizzard"
            end
        end

        if mode == "aoe" or mode == "cleave" then
            if sim.mana_pct < (DH:GetSetting("mana_threshold_evocation") or 15)
               and DH:CanUseCooldown(sim, "evocation", "use_evocation")
               and sim.ttd > 8 then
                return "evocation"
            end
            -- Cone of Cold (cooldown) > Blizzard filler > Arcane Explosion
            if sim:ready("cone_of_cold") then
                return "cone_of_cold"
            end
            if sim:ready("blizzard") then
                return "blizzard"
            end
            return "arcane_explosion"
        end

        -- Evocation when mana critically low (part 5.2)
        if sim.mana_pct < (DH:GetSetting("mana_threshold_evocation") or 15)
           and DH:CanUseCooldown(sim, "evocation", "use_evocation")
           and sim.ttd > 8 then
            return "evocation"
        end

        -- Icy Veins (major CD)
        if sim.has_icy_veins and DH:CanUseCooldown(sim, "icy_veins", "use_icy_veins") then
            return "icy_veins"
        end

        -- Cold Snap: resets Icy Veins - use once IV has been pressed
        if DH:CanUseCooldown(sim, "cold_snap", "use_cold_snap")
           and sim:remains("icy_veins") > 0 then
            return "cold_snap"
        end

        -- Mirror Image (major CD)
        if DH:CanUseCooldown(sim, "mirror_image", "use_mirror_image") then
            return "mirror_image"
        end

        -- Deep Freeze (instant, high damage, requires frozen/FoF)
        if sim.has_deep_freeze and sim:ready("deep_freeze") and sim.fingers_of_frost then
            return "deep_freeze"
        end

        -- Brain Freeze proc: instant Fireball/FFB
        if sim.has_brain_freeze and sim.brain_freeze then
            return "frostfire_bolt"
        end

        -- Fingers of Frost: Ice Lance (instant, 3x damage)
        if sim.has_fof and sim.fingers_of_frost and sim.fof_stacks > 0 then
            return "ice_lance"
        end

        -- Frostbolt filler
        return "frostbolt"
    end,
    onCast = function(sim, key)
        if key == "ice_lance" then
            sim.fof_stacks = sim.fof_stacks - 1
            if sim.fof_stacks <= 0 then
                sim.fingers_of_frost = false
                sim.fof_stacks = 0
            end
        elseif key == "frostfire_bolt" then
            sim.brain_freeze = false
        elseif key == "cold_snap" then
            -- Resets the Icy Veins cooldown
            sim.cd.icy_veins = 0
        elseif key == "deep_freeze" then
            -- Consumes FoF stack
            sim.fof_stacks = sim.fof_stacks - 1
            if sim.fof_stacks <= 0 then
                sim.fingers_of_frost = false
                sim.fof_stacks = 0
            end
        end
    end,
    getAdvanceTime = function(sim, action)
        local h = sim.haste or 1
        if action == "frostbolt" then return math.max(sim.gcd, 2.5 / h) end
        if action == "frostfire_bolt" then
            if sim.brain_freeze then return sim.gcd end
            return math.max(sim.gcd, 3.0 / h)
        end
        if action == "evocation" then return math.max(sim.gcd, 8.0 / h) end
        return sim.gcd  -- instants: ice lance, deep freeze, icy veins
    end,
}

local function GetFrostRecommendations(addon)
    return DH:RunSimulation(state, frostConfig)
end

-- ============================================================================
-- ROTATION MODES
-- ============================================================================

DH:RegisterMode("arcane", {
    name = "Arcane (DPS)",
    icon = select(3, GetSpellInfo(42897)) or "Interface\\Icons\\Spell_Nature_StarFall",
    rotation = function(addon)
        return GetArcaneRecommendations(addon)
    end,
})

DH:RegisterMode("fire", {
    name = "Fire (DPS)",
    icon = select(3, GetSpellInfo(42833)) or "Interface\\Icons\\Spell_Fire_FlameBolt",
    rotation = function(addon)
        return GetFireRecommendations(addon)
    end,
})

DH:RegisterMode("frost_mage", {
    name = "Frost (DPS)",
    icon = select(3, GetSpellInfo(42842)) or "Interface\\Icons\\Spell_Frost_FrostBolt02",
    rotation = function(addon)
        return GetFrostRecommendations(addon)
    end,
})

-- Post-phase 4: PvP priority branch (counterspell > control > burst > survival
-- > DoT > filler), used while pvp_mode_enabled is on.
DH:RegisterPvPSpec({
    interrupt = { "counterspell" },
    control = { "polymorph", "frost_nova", "deep_freeze", "cone_of_cold" },
    burst = { "icy_veins", "combustion", "arcane_power", "presence_of_mind", "mirror_image" },
    survival = { "ice_block", "cold_snap", "blink" },
    dot = { "living_bomb" },
    filler = { "frostbolt", "fireball", "arcane_blast" },
})

-- v3.4.0 battle context: defensive-phase recommendation.
DH:RegisterDefensiveAbility("ice_block")
