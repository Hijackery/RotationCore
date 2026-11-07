-- RotationCore_Priest/Core.lua
-- Priority rotation logic for Priest Shadow spec (3.3.5a compatible)
-- Uses core RunSimulation for CD-aware predictions

local DH = RotationCore
if not DH then
    return
end

if select(2, UnitClass("player")) ~= "PRIEST" then
    return
end

local ns = DH.ns
local class = DH.Class
local state = DH.State

-- ============================================================================
-- SHADOW ROTATION
-- DoT maintenance > Mind Blast on CD > Mind Flay filler
-- ============================================================================

local shadowConfig = {
    gcdType = "spell",
    maxRecs = 3,
    allowDupes = true,
    cds = {
        mind_blast = "mind_blast",
        shadow_word_death = "shadow_word_death",
        shadowfiend = "shadowfiend",
        dispersion = "dispersion",
        inner_focus = "inner_focus",
    },
    baseCDs = {
        mind_blast = 8,
        shadow_word_death = 12,
        shadowfiend = 300,
        dispersion = 120,
        inner_focus = 180,
    },
    auras = {
        { up = "swp_up", remains = "swp_remains" },
        { up = "vt_up", remains = "vt_remains" },
        { up = "dp_up", remains = "dp_remains" },
    },
    initState = function(sim, s)
        -- DoTs
        sim.swp_up = s.debuff.shadow_word_pain.up
        sim.swp_remains = s.debuff.shadow_word_pain.remains
        sim.vt_up = s.debuff.vampiric_touch.up
        sim.vt_remains = s.debuff.vampiric_touch.remains
        sim.dp_up = s.debuff.devouring_plague.up
        sim.dp_remains = s.debuff.devouring_plague.remains

        -- Buffs
        sim.shadowform_up = s.buff.shadowform.up
        sim.moving = s.isMoving

        -- Talents
        sim.has_vt = s.talent.vampiric_touch.rank > 0
        sim.has_dp = true -- all priests have DP
        sim.has_dispersion = s.talent.dispersion.rank > 0
        sim.has_shadowform = s.talent.shadowform.rank > 0
        sim.has_mind_flay = s.talent.mind_flay.rank > 0
        sim.has_mind_sear = true -- trainable spell, gated by known check inside sim

        -- Improved Mind Blast reduces CD
        local imb_rank = s.talent.improved_mind_blast.rank or 0
        sim.mb_cd = 8 - (imb_rank * 0.5)

        -- Glyph of Dispersion
        sim.disp_cd = (s.glyph.dispersion and s.glyph.dispersion.enabled) and 75 or 120
    end,
    getPriority = function(sim, recs)
        -- Shadowform if not active
        if sim.has_shadowform and not sim.shadowform_up then
            return "shadowform"
        end

        -- target_mode: AOE rotation (Mind Sear)
        if DH:IsCleave(sim) then
            if (not sim.swp_up or sim.swp_remains < 2) and sim.ttd > 6 then
                return "shadow_word_pain"
            end
            if sim.has_mind_sear and sim.ttd > 3 then
                return "mind_sear"
            end
        end

        if DH:IsMultiTarget(sim) and sim.has_mind_sear and sim.ttd > 3 then
            return "mind_sear"
        end

        -- Dispersion for mana emergency
        if
            sim.has_dispersion
            and sim.mana_pct < (DH:GetSetting("mana_threshold_dispersion") or 10)
            and sim.ttd > 6
            and DH:CanUseCooldown(sim, "dispersion", "use_dispersion")
        then
            return "dispersion"
        end

        -- Shadowfiend for mana
        if sim.mana_pct < 30 and DH:CanUseCooldown(sim, "shadowfiend", "use_shadowfiend") then
            return "shadowfiend"
        end

        -- Inner Focus (free next spell)
        if DH:Ready(sim, "inner_focus") and DH:CanUseCooldown(sim, "inner_focus", "use_inner_focus") then
            return "inner_focus"
        end

        -- MOVING: only instants can be cast - never fall through to the
        -- stationary rotation, or cast-time spells like Vampiric Touch / Mind
        -- Flay get recommended while the player is moving (unusable).
        if sim.moving then
            if not sim.dp_up and sim.ttd > 6 then
                return "devouring_plague"
            end
            if (not sim.swp_up or sim.swp_remains < 2) and sim.ttd > 6 then
                return "shadow_word_pain"
            end
            if DH:Ready(sim, "shadow_word_death") then
                return "shadow_word_death"
            end
            return nil
        end

        -- Vampiric Touch: maintain (cast time ~1.5s, refresh before it falls off)
        if sim.has_vt and (not sim.vt_up or sim.vt_remains < 2) and sim.ttd > 6 then
            return "vampiric_touch"
        end

        -- Devouring Plague: maintain (instant)
        if not sim.dp_up and sim.ttd > 6 then
            return "devouring_plague"
        end

        -- Shadow Word: Pain: maintain (instant)
        if (not sim.swp_up or sim.swp_remains < 2) and sim.ttd > 6 then
            return "shadow_word_pain"
        end

        -- Mind Blast on CD (high damage, generates Replenishment with VT)
        if DH:Ready(sim, "mind_blast") then
            return "mind_blast"
        end

        -- Shadow Word: Death (use on cooldown as a damage filler)
        if DH:Ready(sim, "shadow_word_death") then
            return "shadow_word_death"
        end

        -- Mind Flay filler
        if sim.has_mind_flay then
            return "mind_flay"
        end

        return nil
    end,
    onCast = function(sim, key)
        if key == "vampiric_touch" then
            sim.vt_up = true
            sim.vt_remains = 15
        elseif key == "devouring_plague" then
            sim.dp_up = true
            sim.dp_remains = 24
        elseif key == "shadow_word_pain" then
            sim.swp_up = true
            sim.swp_remains = 18
        elseif key == "mind_blast" then
            sim.cd["mind_blast"] = sim.mb_cd
        elseif key == "dispersion" then
            sim.mana_pct = math.min(100, sim.mana_pct + 36)
            sim.cd["dispersion"] = sim.disp_cd
        elseif key == "shadowform" then
            sim.shadowform_up = true
        end
    end,
    getAdvanceTime = function(sim, action)
        local h = sim.haste or 1
        if action == "vampiric_touch" then
            return math.max(sim.gcd, 1.5 / h)
        end
        if action == "mind_blast" then
            return math.max(sim.gcd, 1.5 / h)
        end
        if action == "mind_flay" then
            return math.max(sim.gcd, 3.0 / h)
        end -- full channel
        if action == "mind_sear" then
            return math.max(sim.gcd, 3.0 / h)
        end -- full channel
        if action == "dispersion" then
            return math.max(sim.gcd, 6.0)
        end
        return sim.gcd -- instants: SWP, DP, SWD, Shadowfiend, Shadowform
    end,
}

local function GetShadowRecommendations(addon)
    return DH:RunSimulation(state, shadowConfig)
end

-- ============================================================================
-- ROTATION MODES
-- ============================================================================

DH:RegisterMode("shadow", {
    name = "Shadow (DPS)",
    icon = select(3, GetSpellInfo(15473)) or "Interface\\Icons\\Spell_Shadow_Shadowform",
    rotation = function(addon)
        return GetShadowRecommendations(addon)
    end,
})

-- Post-phase 3: dedicated heal-DPS lists (Smite/Holy Fire) used when the
-- heal-DPS mode is enabled for a Discipline/Holy priest.
local function BuildHealDps()
    local s = state
    local recs = {}
    local function push(key)
        recs[#recs + 1] = { ability = key, priority = #recs + 1 }
    end
    local function Ready(key)
        local a = class.abilities[key]
        return DH:SpellReady(a and a.id)
    end
    local aoe = s and s.active_enemies and s.active_enemies >= 3
    local hp = s and s.target and s.target.health and s.target.health.pct or 100
    if aoe and Ready("holy_nova") then
        push("holy_nova")
    end
    if hp < 25 and Ready("shadow_word_death") then
        push("shadow_word_death")
    end
    if Ready("holy_fire") then
        push("holy_fire")
    end
    if Ready("smite") then
        push("smite")
    end
    if #recs == 0 then
        push("smite")
    end
    return recs
end

DH:RegisterMode("discipline_dps", {
    name = "Discipline (DPS)",
    icon = select(3, GetSpellInfo(48123)) or "Interface\\Icons\\Spell_Holy_HolySmite",
    rotation = function(addon)
        return BuildHealDps()
    end,
})

DH:RegisterMode("holy_priest_dps", {
    name = "Holy (DPS)",
    icon = select(3, GetSpellInfo(48135)) or "Interface\\Icons\\Spell_Holy_SearingLightPriest",
    rotation = function(addon)
        return BuildHealDps()
    end,
})

-- ============================================================================
-- HEAL ROTATIONS (Discipline / Holy)
-- Isolated from the Shadow rotation and from the heal-DPS lists above. They
-- only emit heal and utility recommendations.
-- ============================================================================
local WEAKENED_SOUL = 6788

local function IsSoulWeakened(unit)
    return ns.GetUnitAuraInfo(unit, WEAKENED_SOUL, "HARMFUL") ~= nil
end

local function GetDisciplineHealRecommendations(addon)
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

    -- Shields, avoiding Weakened Soul.
    if tank and not IsSoulWeakened(tank.unit) then
        push("power_word_shield", tank)
    end
    if low and not IsSoulWeakened(low.unit) then
        push("power_word_shield", low)
    end

    -- Prayer of Mending upkeep.
    if tank and not ns.GetAbilityAura(tank.unit, "prayer_of_mending") then
        push("prayer_of_mending", tank)
    end
    if low and not ns.GetAbilityAura(low.unit, "prayer_of_mending") then
        push("prayer_of_mending", low)
    end

    -- Dispel magic/disease.
    local dispelUnit, _, dispelType = ns.FindDispelTarget(ctx, { Magic = true, Disease = true })
    if dispelUnit then
        if dispelType == "Magic" then
            push("dispel_magic", dispelUnit)
        elseif dispelType == "Disease" then
            push("abolish_disease", dispelUnit)
        end
    end

    -- Emergency and direct healing.
    if critical then
        if critical.pct < 25 then
            push("pain_suppression", critical)
        end
        push("penance", critical)
    end
    if target then
        if not ns.GetAbilityAura(target.unit, "renew") then
            push("renew", target)
        end
        if target.pct < 55 then
            push("flash_heal", target)
        else
            push("greater_heal", target)
        end
    end

    -- Group healing and cooldowns.
    if injured >= 3 then
        push("prayer_of_healing", low or tank)
        if not ns.GetAbilityAura("player", "power_infusion") then
            push("power_infusion", "player")
        end
    end
    if ctx.manaPct < 20 then
        if type(UnitCanAttack) == "function" and UnitExists("target") and UnitCanAttack("player", "target") then
            push("shadowfiend", "target")
        end
        push("hymn_of_hope", "player")
    end

    return recs
end

local function GetHolyHealRecommendations(addon)
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

    -- Guardian Spirit on a dying tank.
    if tank and tank.pct < 35 and not ns.GetAbilityAura(tank.unit, "guardian_spirit") then
        push("guardian_spirit", tank)
    end

    -- Shield, renew and Prayer of Mending upkeep.
    if tank and not IsSoulWeakened(tank.unit) then
        push("power_word_shield", tank)
    end
    if tank and not ns.GetAbilityAura(tank.unit, "renew") then
        push("renew", tank)
    end
    if low and not ns.GetAbilityAura(low.unit, "renew") then
        push("renew", low)
    end
    if low and not ns.GetAbilityAura(low.unit, "prayer_of_mending") then
        push("prayer_of_mending", low)
    end

    -- Dispel magic/disease.
    local dispelUnit, _, dispelType = ns.FindDispelTarget(ctx, { Magic = true, Disease = true })
    if dispelUnit then
        if dispelType == "Magic" then
            push("dispel_magic", dispelUnit)
        elseif dispelType == "Disease" then
            push("abolish_disease", dispelUnit)
        end
    end

    -- Group healing tools.
    if injured >= 3 then
        push("circle_of_healing", low or tank)
    end
    if injured >= 4 then
        push("prayer_of_healing", low or tank)
    end
    if injured >= 5 then
        push("divine_hymn", "player")
    end

    -- Direct healing.
    if critical then
        push("flash_heal", critical)
    end
    if target then
        if target.pct < 55 then
            push("flash_heal", target)
        else
            push("greater_heal", target)
        end
    end
    if critical and not ns.GetAbilityAura(critical.unit, "prayer_of_mending") then
        push("prayer_of_mending", critical)
    end

    if ctx.manaPct < 20 then
        if type(UnitCanAttack) == "function" and UnitExists("target") and UnitCanAttack("player", "target") then
            push("shadowfiend", "target")
        end
        push("hymn_of_hope", "player")
    end

    return recs
end

DH:RegisterHealMode(
    "discipline",
    "Discipline (Healer)",
    select(3, GetSpellInfo(47540)) or "Interface\\Icons\\Spell_Holy_PowerWordShield",
    GetDisciplineHealRecommendations
)

DH:RegisterHealMode(
    "holy_priest",
    "Holy (Healer)",
    select(3, GetSpellInfo(34863)) or "Interface\\Icons\\Spell_Holy_GuardianSpirit",
    GetHolyHealRecommendations
)

-- Post-phase 4: PvP priority branch
DH:RegisterPvPSpec({
    interrupt = { "silence" },
    control = { "psychic_scream", "mind_control" },
    burst = { "shadowfiend", "inner_focus" },
    survival = { "dispersion", "power_word_shield", "fear_ward" },
    dot = { "shadow_word_pain", "vampiric_touch", "devouring_plague" },
    filler = { "mind_blast", "mind_flay", "smite" },
})

-- v3.4.0 battle context: defensive-phase recommendation.
DH:RegisterDefensiveAbility("dispersion")
